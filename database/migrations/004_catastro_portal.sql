-- =============================================================================
-- SNRI — CATASTRO DE ROLES POR COMUNA
-- Schema: catastro (operacional) + public (portal usuario)
-- Compatible con: ref schema (snri_knowledge_repository_part1-3.sql)
-- Supabase PostgreSQL 15+
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. SCHEMAS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE SCHEMA IF NOT EXISTS catastro;
COMMENT ON SCHEMA catastro IS
  'Repositorio catastral operacional: predios, construcciones, avalúos y contribuciones por ROL/comuna.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. CATASTRO.PREDIOS — Tabla maestra de ROLs
-- ─────────────────────────────────────────────────────────────────────────────
-- ROL format: "15108-624-6"  →  codigo_comuna=15108 | manzana=624 | predio=6
-- Particionado RANGE por codigo_comuna para queries masivas por comuna.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS catastro.predios (
  -- ── Identificación ──────────────────────────────────────────────────────
  rol                    text          NOT NULL,        -- "15108-624-6" PK lógico
  codigo_comuna          integer       NOT NULL
    REFERENCES ref.comunas(codigo_sii),                -- FK → ref.comunas
  manzana                text          NOT NULL,        -- número de manzana
  predio                 text          NOT NULL,        -- número de predio
  rol_anterior           text,                         -- ROL previo si hubo subdivisión/fusión

  -- ── Ubicación ───────────────────────────────────────────────────────────
  direccion              text,
  numero                 text,
  block                  text,
  depto                  text,
  poblacion_villa        text,
  latitud                numeric(10,7),
  longitud               numeric(10,7),

  -- ── Propietario (snapshot SII — no datos sensibles en RLS) ─────────────
  nombre_propietario     text,
  rut_propietario        text,                         -- enmascarado si RLS activo
  tipo_propietario       text,                         -- persona_natural / juridica / estado

  -- ── Catastro terreno ────────────────────────────────────────────────────
  sup_terreno_m2         numeric(12,2),
  sup_terreno_util_m2    numeric(12,2),                -- descontando AUP
  destino_sii            text
    REFERENCES ref.destinos(codigo),                   -- FK → ref.destinos (A-Z)
  subtipo_destino        text,                         -- vivienda / comercio / bodega...
  serie_predio           text
    REFERENCES ref.series_predio(codigo),              -- Habitacional / No Agrícola / Agrícola

  -- ── Flags catastro ──────────────────────────────────────────────────────
  zona_urbana            boolean DEFAULT true,
  afecto_vial            boolean DEFAULT false,
  insubdivisible         boolean DEFAULT false,
  es_subterraneo         boolean DEFAULT false,
  tiene_servidumbre      boolean DEFAULT false,
  bien_nacional_uso_pub  boolean DEFAULT false,

  -- ── Área Urbana de Protección (AUP/ZC) ─────────────────────────────────
  pct_afectacion_aup     numeric(5,2),                 -- % terreno en zona protección
  tipo_zona_planreg      text,                         -- ZR1 / EAb2 / I2 / etc.
  coeficiente_ocupacion  numeric(4,2),                 -- COS según PRC
  coeficiente_constructi numeric(4,2),                 -- CC según PRC
  min_subdivisión_m2     numeric(8,2),                 -- mínimo de subdivisión PRC

  -- ── Pendiente terreno ───────────────────────────────────────────────────
  pct_pendiente          numeric(5,2),                 -- % pendiente media
  factor_pendiente       numeric(4,3) DEFAULT 1.000,   -- factor corrector SII

  -- ── Área Homogénea y valor unitario ─────────────────────────────────────
  codigo_area_homogenea  text,                         -- código AH asignado SII
  vutah_uf_m2            numeric(10,4),                -- Valor Unitario Terreno Área Homogénea

  -- ── Avalúo vigente (snapshot) ────────────────────────────────────────────
  avaluo_terreno_vigente  numeric(16,2),               -- $ pesos, a la fecha
  avaluo_total_vigente    numeric(16,2),
  avaluo_fecha            date,

  -- ── Contribución vigente (snapshot) ──────────────────────────────────────
  contribucion_anual      numeric(14,2),
  contribucion_semestre   numeric(14,2),
  exento                  boolean DEFAULT false,
  motivo_exencion         text,

  -- ── Beneficios ───────────────────────────────────────────────────────────
  bam_activo             boolean DEFAULT false,
  bam_rebaja_pct         numeric(5,2),
  dfl2_activo            boolean DEFAULT false,
  dfl2_numero_decreto    text,

  -- ── Metadatos ingestión ──────────────────────────────────────────────────
  fuente_datos           text DEFAULT 'SII',           -- SII / CBR / catastro_municipal / usuario
  fecha_ingestion        timestamptz DEFAULT now(),
  fecha_actualizacion    timestamptz DEFAULT now(),
  hash_raw               text,                         -- SHA256 del registro original para dedup
  datos_crudos_sii       jsonb,                        -- payload completo SII sin parsear
  activo                 boolean DEFAULT true,

  -- ── PKs y constraints ────────────────────────────────────────────────────
  CONSTRAINT predios_pkey PRIMARY KEY (rol),
  CONSTRAINT predios_componentes_uq UNIQUE (codigo_comuna, manzana, predio),
  CONSTRAINT predios_rol_format CHECK (rol ~ '^\d{4,5}-\d{1,4}-\d{1,4}$')
);

-- Índices de performance
CREATE INDEX IF NOT EXISTS idx_predios_comuna      ON catastro.predios (codigo_comuna);
CREATE INDEX IF NOT EXISTS idx_predios_manzana     ON catastro.predios (codigo_comuna, manzana);
CREATE INDEX IF NOT EXISTS idx_predios_destino     ON catastro.predios (destino_sii);
CREATE INDEX IF NOT EXISTS idx_predios_serie       ON catastro.predios (serie_predio);
CREATE INDEX IF NOT EXISTS idx_predios_propietario ON catastro.predios (rut_propietario);
CREATE INDEX IF NOT EXISTS idx_predios_avaluo      ON catastro.predios (avaluo_total_vigente);
CREATE INDEX IF NOT EXISTS idx_predios_exento      ON catastro.predios (exento) WHERE exento = false;
CREATE INDEX IF NOT EXISTS idx_predios_geo         ON catastro.predios USING gist (
  point(longitud, latitud)
) WHERE latitud IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_predios_datos_crudos ON catastro.predios USING gin (datos_crudos_sii);

COMMENT ON TABLE catastro.predios IS
  'Repositorio maestro de todos los ROLs de Chile. ROL = codigo_comuna-manzana-predio.
   Particionado lógico por codigo_comuna. Fuente: SII / importación masiva CSV.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. CATASTRO.CONSTRUCCIONES — Detalle constructivo por ROL
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS catastro.construcciones (
  id                     bigserial     PRIMARY KEY,
  rol                    text          NOT NULL
    REFERENCES catastro.predios(rol) ON DELETE CASCADE,

  -- ── Identificación ──────────────────────────────────────────────────────
  numero_construccion    integer       NOT NULL DEFAULT 1,  -- 1..N por predio
  destino_construccion   text
    REFERENCES ref.destinos(codigo),
  uso_interno            text,                              -- vivienda / comercio / estacionamiento

  -- ── Superficie ──────────────────────────────────────────────────────────
  sup_total_m2           numeric(10,2),
  sup_util_m2            numeric(10,2),
  sup_terraza_m2         numeric(10,2) DEFAULT 0,
  sup_subterraneo_m2     numeric(10,2) DEFAULT 0,
  numero_pisos           integer DEFAULT 1,
  numero_subterraneos    integer DEFAULT 0,
  numero_estacionamientos integer DEFAULT 0,

  -- ── Clasificación SII ────────────────────────────────────────────────────
  material_codigo        text
    REFERENCES ref.materiales_construccion(codigo),        -- A-H, MA, MX...
  calidad_codigo         integer
    REFERENCES ref.calidades_construccion(codigo),         -- 1-7
  clase_sii              text,                             -- clase resultante (ej. B)
  condicion_especial     text
    REFERENCES ref.condiciones_especiales(codigo),         -- CE1, CE2, CE3

  -- ── Temporalidad ─────────────────────────────────────────────────────────
  anio_construccion      integer,
  anio_ampliacion        integer,
  estado_construccion    text DEFAULT 'terminada',         -- terminada / en_obras / sin_recepcion

  -- ── Valores unitarios ────────────────────────────────────────────────────
  vuc_uf_m2              numeric(10,4),                    -- VUC tabla SII
  factor_depreciacion    numeric(5,4) DEFAULT 1.0000,      -- D(años)
  factor_condicion_esp   numeric(5,4) DEFAULT 1.0000,      -- CE factor
  factor_comercial       numeric(5,4) DEFAULT 1.0000,      -- FC adicional

  -- ── Avalúo resultante ────────────────────────────────────────────────────
  avaluo_construccion    numeric(16,2),
  avaluo_fecha           date,

  -- ── Flags ────────────────────────────────────────────────────────────────
  tiene_recepcion_final  boolean DEFAULT true,
  permiso_edificacion    text,
  es_irregular           boolean DEFAULT false,            -- sin permiso / sin recepción

  -- ── Metadatos ────────────────────────────────────────────────────────────
  fuente_datos           text DEFAULT 'SII',
  fecha_actualizacion    timestamptz DEFAULT now(),
  datos_crudos_sii       jsonb,

  CONSTRAINT construcciones_uq UNIQUE (rol, numero_construccion)
);

CREATE INDEX IF NOT EXISTS idx_const_rol       ON catastro.construcciones (rol);
CREATE INDEX IF NOT EXISTS idx_const_destino   ON catastro.construcciones (destino_construccion);
CREATE INDEX IF NOT EXISTS idx_const_clase     ON catastro.construcciones (clase_sii);
CREATE INDEX IF NOT EXISTS idx_const_anio      ON catastro.construcciones (anio_construccion);

COMMENT ON TABLE catastro.construcciones IS
  'Detalle de cada cuerpo constructivo por ROL. Un predio puede tener N construcciones.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. CATASTRO.AVALUOS_HISTORIAL — Serie histórica de avalúos
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- 3b. SUELOS_AGRICOLAS — Suelos de predios agrícolas (separados de construcciones)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS catastro.suelos_agricolas (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rol          text NOT NULL,
    cod_suelo    text NOT NULL,             -- 1R, 2R, 3R, 1-8 (ref.tipos_suelo_agricola)
    sup_ha       numeric(12,2),             -- hectáreas (raw SII / 100)
    fuente_datos text DEFAULT 'SII_CSV',
    created_at   timestamptz DEFAULT now(),
    CONSTRAINT fk_suelos_predio FOREIGN KEY (rol)
        REFERENCES catastro.predios(rol) ON DELETE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_suelos_rol_cod
    ON catastro.suelos_agricolas(rol, cod_suelo);
CREATE INDEX IF NOT EXISTS idx_suelos_rol
    ON catastro.suelos_agricolas(rol);

COMMENT ON TABLE catastro.suelos_agricolas IS
    'Suelos de predios agrícolas, extraídos del archivo AL del Detalle Catastral SII. '
    'sup_ha = campo raw SII dividido por 100. Un ROL puede tener múltiples clases de suelo.';

-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS catastro.avaluos_historial (
  id                     bigserial     PRIMARY KEY,
  rol                    text          NOT NULL
    REFERENCES catastro.predios(rol) ON DELETE CASCADE,

  periodo_reavaluo       text          NOT NULL,  -- "2015-01" / "2022-01" / "2024-S1"
  fecha_vigencia         date          NOT NULL,

  -- ── Avalúo descompuesto ───────────────────────────────────────────────────
  avaluo_terreno         numeric(16,2),
  avaluo_construccion    numeric(16,2),
  avaluo_total           numeric(16,2),
  avaluo_afecto          numeric(16,2),           -- monto sujeto a contribución
  avaluo_exento          numeric(16,2),           -- monto exento

  -- ── Base de cálculo ──────────────────────────────────────────────────────
  factor_reavaluo        numeric(8,5),            -- factor de ajuste aplicado
  es_reavaluo_general    boolean DEFAULT false,   -- reavalúo masivo SII
  es_reavaluo_parcial    boolean DEFAULT false,   -- modificación individual

  -- ── Metadatos ────────────────────────────────────────────────────────────
  fuente_datos           text DEFAULT 'SII',
  observacion            text,
  fecha_registro         timestamptz DEFAULT now(),

  CONSTRAINT avaluos_hist_uq UNIQUE (rol, periodo_reavaluo)
);

CREATE INDEX IF NOT EXISTS idx_avaluos_rol     ON catastro.avaluos_historial (rol);
CREATE INDEX IF NOT EXISTS idx_avaluos_periodo ON catastro.avaluos_historial (periodo_reavaluo);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. CATASTRO.CONTRIBUCIONES_HISTORIAL — Serie histórica de pagos
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS catastro.contribuciones_historial (
  id                     bigserial     PRIMARY KEY,
  rol                    text          NOT NULL
    REFERENCES catastro.predios(rol) ON DELETE CASCADE,

  anio                   integer       NOT NULL,
  semestre               integer       NOT NULL CHECK (semestre IN (1,2)),

  -- ── Montos ───────────────────────────────────────────────────────────────
  contribucion_neta      numeric(14,2),           -- sin reajustes
  sobretasa_fiscal       numeric(14,2) DEFAULT 0, -- 0.025% sitios sin construir
  sobretasa_municipal    numeric(14,2) DEFAULT 0, -- art. 7 bis
  descuento_bam          numeric(14,2) DEFAULT 0,
  descuento_dfl2         numeric(14,2) DEFAULT 0,
  contribucion_total     numeric(14,2),           -- a pagar efectivo

  -- ── Tasas aplicadas ──────────────────────────────────────────────────────
  tasa_aplicada          numeric(8,5),
  tramo_tasa             text,                    -- T1 / T2 / OTRO
  mct_vigente            numeric(16,2),           -- Monto Cuota Trimestral vigente

  -- ── Estado pago ──────────────────────────────────────────────────────────
  estado_pago            text DEFAULT 'pendiente', -- pagado / pendiente / moroso / exento
  fecha_vencimiento      date,
  fecha_pago             date,

  CONSTRAINT contrib_hist_uq UNIQUE (rol, anio, semestre)
);

CREATE INDEX IF NOT EXISTS idx_contrib_rol   ON catastro.contribuciones_historial (rol);
CREATE INDEX IF NOT EXISTS idx_contrib_anio  ON catastro.contribuciones_historial (anio, semestre);
CREATE INDEX IF NOT EXISTS idx_contrib_estado ON catastro.contribuciones_historial (estado_pago);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. CATASTRO.IMPORTACIONES — Control de ingestión masiva por comuna
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS catastro.importaciones (
  id                     uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo_comuna          integer
    REFERENCES ref.comunas(codigo_sii),
  nombre_comuna          text,

  -- ── Fuente ───────────────────────────────────────────────────────────────
  fuente                 text          NOT NULL,   -- sii_csv / sii_api / cbr / manual
  nombre_archivo         text,
  url_fuente             text,

  -- ── Estadísticas ─────────────────────────────────────────────────────────
  total_roles            integer DEFAULT 0,
  roles_insertados       integer DEFAULT 0,
  roles_actualizados     integer DEFAULT 0,
  roles_con_error        integer DEFAULT 0,

  -- ── Estado ───────────────────────────────────────────────────────────────
  estado                 text DEFAULT 'pendiente', -- pendiente / procesando / completado / error
  fecha_inicio           timestamptz,
  fecha_fin              timestamptz,
  duracion_seg           numeric(10,2),
  mensaje_error          text,
  log_detalle            jsonb,                    -- errores por fila si aplica

  -- ── Metadatos ────────────────────────────────────────────────────────────
  usuario_proceso        text DEFAULT 'system',
  created_at             timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_importaciones_comuna ON catastro.importaciones (codigo_comuna);
CREATE INDEX IF NOT EXISTS idx_importaciones_estado ON catastro.importaciones (estado);

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. PORTAL USUARIO — Tablas propias del usuario final
-- ─────────────────────────────────────────────────────────────────────────────

-- 6a. USUARIOS
CREATE TABLE IF NOT EXISTS public.usuarios (
  id                     uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id           uuid          UNIQUE,     -- FK → auth.users (Supabase Auth)
  email                  text          UNIQUE NOT NULL,
  nombre_completo        text,
  rut                    text,
  telefono               text,
  rol_sistema            text          DEFAULT 'contribuyente'
    CHECK (rol_sistema IN ('contribuyente','admin','analista')),
  plan                   text          DEFAULT 'free'
    CHECK (plan IN ('free','basic','pro','enterprise')),
  fecha_registro         timestamptz   DEFAULT now(),
  ultimo_acceso          timestamptz,
  activo                 boolean       DEFAULT true,
  metadata               jsonb
);

-- 6b. PROPIEDADES_USUARIO
CREATE TABLE IF NOT EXISTS public.propiedades_usuario (
  id                     uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id             uuid          NOT NULL
    REFERENCES public.usuarios(id) ON DELETE CASCADE,
  rol                    text          NOT NULL
    REFERENCES catastro.predios(rol),
  alias_propiedad        text,
  fecha_agregado         timestamptz   DEFAULT now(),
  fuente_inicio          text          DEFAULT 'manual'
    CHECK (fuente_inicio IN ('manual','importado_sii','api','archivo')),
  estado                 text          DEFAULT 'sin_auditar'
    CHECK (estado IN ('sin_auditar','auditado','caso_creado','cerrado')),
  notas_usuario          text,
  CONSTRAINT propusu_uq  UNIQUE (usuario_id, rol)
);

CREATE INDEX IF NOT EXISTS idx_propusu_usuario ON public.propiedades_usuario (usuario_id);
CREATE INDEX IF NOT EXISTS idx_propusu_rol     ON public.propiedades_usuario (rol);

-- 6c. DOCUMENTOS_USUARIO
CREATE TABLE IF NOT EXISTS public.documentos_usuario (
  id                     uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id             uuid          NOT NULL
    REFERENCES public.usuarios(id) ON DELETE CASCADE,
  propiedad_id           uuid          NOT NULL
    REFERENCES public.propiedades_usuario(id) ON DELETE CASCADE,
  tipo_documento         text          NOT NULL
    CHECK (tipo_documento IN (
      'CIP','Permiso_Edificacion','Recepcion_Final',
      'Certificado_SII','Plano','Escritura','Servidumbre','Otro'
    )),
  nombre_archivo         text,
  url_archivo            text          NOT NULL,
  mime_type              text,
  size_bytes             bigint,
  fecha_subida           timestamptz   DEFAULT now(),
  estado_analisis        text          DEFAULT 'pendiente'
    CHECK (estado_analisis IN ('pendiente','procesado','error')),
  -- Metadatos extraídos (manual o por IA)
  metadatos              jsonb,
  /*
    Estructura esperada de metadatos:
    {
      "m2_confirmados": 145.5,
      "anio_construccion": 1998,
      "destino": "habitacional",
      "pisos": 2,
      "servidumbre_tipo": "paso",
      "observaciones": "...",
      "extraido_por": "usuario" | "ia"
    }
  */
  confianza_ia           numeric(4,3)  CHECK (confianza_ia BETWEEN 0 AND 1)
);

CREATE INDEX IF NOT EXISTS idx_docusu_propiedad ON public.documentos_usuario (propiedad_id);
CREATE INDEX IF NOT EXISTS idx_docusu_tipo      ON public.documentos_usuario (tipo_documento);
CREATE INDEX IF NOT EXISTS idx_docusu_metadatos ON public.documentos_usuario USING gin (metadatos);

-- 6d. AUDITORIAS_USUARIO
CREATE TABLE IF NOT EXISTS public.auditorias_usuario (
  id                     uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id             uuid          NOT NULL
    REFERENCES public.usuarios(id),
  rol                    text          NOT NULL
    REFERENCES catastro.predios(rol),
  fecha                  timestamptz   DEFAULT now(),

  -- ── Resultados SII vs SNRI ───────────────────────────────────────────────
  avaluo_sii             numeric(16,2),
  avaluo_snri            numeric(16,2),
  diferencia             numeric(16,2) GENERATED ALWAYS AS (avaluo_snri - avaluo_sii) STORED,
  pct_diferencia         numeric(8,4),            -- ((snri-sii)/sii)*100
  monto_recuperable      numeric(16,2),           -- diferencia en contribuciones
  probabilidad_error     numeric(5,3),            -- 0..1

  -- ── Descomposición ────────────────────────────────────────────────────────
  avaluo_terreno_sii     numeric(16,2),
  avaluo_terreno_snri    numeric(16,2),
  avaluo_const_sii       numeric(16,2),
  avaluo_const_snri      numeric(16,2),
  contribucion_sii       numeric(14,2),
  contribucion_snri      numeric(14,2),

  -- ── Detalle completo ──────────────────────────────────────────────────────
  detalle                jsonb,
  /*
    {
      "errores": [{"codigo":"ERR-C01","descripcion":"...","impacto_uf":12.5}],
      "flags": {"afecto_vial_detectado":false, "bam_aplicable":true},
      "parametros_usados": {...},
      "version_motor": "2.0"
    }
  */
  numero_errores         integer DEFAULT 0,
  estado                 text DEFAULT 'borrador'
    CHECK (estado IN ('borrador','confirmada','caso_generado'))
);

CREATE INDEX IF NOT EXISTS idx_audiusu_usuario ON public.auditorias_usuario (usuario_id);
CREATE INDEX IF NOT EXISTS idx_audiusu_rol     ON public.auditorias_usuario (rol);
CREATE INDEX IF NOT EXISTS idx_audiusu_fecha   ON public.auditorias_usuario (fecha DESC);

-- 6e. CASOS (tabla compartida USUARIO ↔ ADMIN CRM)
CREATE TABLE IF NOT EXISTS public.casos (
  id                     uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  numero_caso            text          UNIQUE,          -- generado: SNRI-YYYY-NNNN
  usuario_id             uuid
    REFERENCES public.usuarios(id),
  auditoria_id           uuid
    REFERENCES public.auditorias_usuario(id),
  rol                    text
    REFERENCES catastro.predios(rol),

  -- ── Estado CRM ────────────────────────────────────────────────────────────
  estado                 text          DEFAULT 'recibido'
    CHECK (estado IN ('recibido','en_revision','en_gestion','resuelto','cerrado','rechazado')),
  prioridad              text          DEFAULT 'normal'
    CHECK (prioridad IN ('baja','normal','alta','critica')),
  asignado_a             text,                          -- analista ADMIN

  -- ── Financiero ───────────────────────────────────────────────────────────
  monto_estimado_uf      numeric(14,4),
  monto_cobrado_uf       numeric(14,4),
  honorarios_pct         numeric(5,2),                 -- % del recuperable pactado

  -- ── Documentos y notas ───────────────────────────────────────────────────
  descripcion            text,
  notas_admin            text,
  historial_estados      jsonb DEFAULT '[]',
  /*
    [{"estado":"recibido","fecha":"...","usuario":"system"},
     {"estado":"en_revision","fecha":"...","usuario":"admin@snri.cl"}]
  */

  -- ── Fechas ────────────────────────────────────────────────────────────────
  fecha_creacion         timestamptz   DEFAULT now(),
  fecha_actualizacion    timestamptz   DEFAULT now(),
  fecha_cierre           timestamptz,

  -- ── Metadatos ────────────────────────────────────────────────────────────
  origen                 text          DEFAULT 'portal_usuario'
    CHECK (origen IN ('portal_usuario','admin_manual','api'))
);

CREATE INDEX IF NOT EXISTS idx_casos_usuario  ON public.casos (usuario_id);
CREATE INDEX IF NOT EXISTS idx_casos_rol      ON public.casos (rol);
CREATE INDEX IF NOT EXISTS idx_casos_estado   ON public.casos (estado);
CREATE INDEX IF NOT EXISTS idx_casos_numero   ON public.casos (numero_caso);

-- Trigger: auto-número de caso SNRI-YYYY-NNNN
CREATE OR REPLACE FUNCTION public.fn_generar_numero_caso()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.numero_caso := 'SNRI-' ||
    TO_CHAR(NOW(), 'YYYY') || '-' ||
    LPAD(NEXTVAL('public.seq_casos')::text, 4, '0');
  RETURN NEW;
END;
$$;

CREATE SEQUENCE IF NOT EXISTS public.seq_casos START 1;

DROP TRIGGER IF EXISTS trg_numero_caso ON public.casos;
CREATE TRIGGER trg_numero_caso
  BEFORE INSERT ON public.casos
  FOR EACH ROW WHEN (NEW.numero_caso IS NULL)
  EXECUTE FUNCTION public.fn_generar_numero_caso();

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. VISTAS — Acceso simplificado para el portal
-- ─────────────────────────────────────────────────────────────────────────────

-- Vista: resumen de ROL enriquecido (UX portal)
CREATE OR REPLACE VIEW public.v_rol_resumen AS
SELECT
  p.rol,
  p.codigo_comuna,
  c.nombre                                 AS nombre_comuna,
  c.region_nombre,
  p.direccion,
  p.numero,
  p.serie_predio,
  p.destino_sii,
  d.nombre                                 AS nombre_destino,
  p.sup_terreno_m2,
  p.avaluo_total_vigente,
  p.contribucion_anual,
  p.contribucion_semestre,
  p.exento,
  p.motivo_exencion,
  p.bam_activo,
  p.dfl2_activo,
  p.zona_urbana,
  p.afecto_vial,
  p.tipo_zona_planreg,
  COUNT(co.id)                             AS num_construcciones,
  COALESCE(SUM(co.sup_total_m2), 0)        AS sup_total_construida_m2,
  p.fecha_actualizacion
FROM catastro.predios p
LEFT JOIN ref.comunas  c  ON c.codigo_sii = p.codigo_comuna
LEFT JOIN ref.destinos d  ON d.codigo     = p.destino_sii
LEFT JOIN catastro.construcciones co ON co.rol = p.rol
WHERE p.activo = true
GROUP BY p.rol, c.nombre, c.region_nombre, d.nombre;

-- Vista: resumen por comuna (para heatmap y estadísticas agregadas)
CREATE OR REPLACE VIEW catastro.v_estadisticas_comuna AS
SELECT
  p.codigo_comuna,
  c.nombre                                 AS nombre_comuna,
  c.region_nombre,
  c.es_rm,
  COUNT(p.rol)                             AS total_roles,
  COUNT(p.rol) FILTER (WHERE p.exento = false) AS roles_afectos,
  COUNT(p.rol) FILTER (WHERE p.exento = true)  AS roles_exentos,
  COUNT(p.rol) FILTER (WHERE p.serie_predio = 'habitacional') AS roles_habitacional,
  COUNT(p.rol) FILTER (WHERE p.serie_predio = 'no_agricola')  AS roles_no_agricola,
  COUNT(p.rol) FILTER (WHERE p.serie_predio = 'agricola')     AS roles_agricola,
  ROUND(AVG(p.avaluo_total_vigente), 0)    AS avaluo_promedio,
  ROUND(SUM(p.avaluo_total_vigente), 0)    AS avaluo_total_comuna,
  ROUND(SUM(p.contribucion_anual), 0)      AS contribucion_anual_total,
  MAX(p.fecha_actualizacion)               AS ultima_actualizacion
FROM catastro.predios p
LEFT JOIN ref.comunas c ON c.codigo_sii = p.codigo_comuna
WHERE p.activo = true
GROUP BY p.codigo_comuna, c.nombre, c.region_nombre, c.es_rm;

-- Vista: casos con contexto completo (ADMIN CRM)
CREATE OR REPLACE VIEW public.v_casos_crm AS
SELECT
  ca.id,
  ca.numero_caso,
  ca.estado,
  ca.prioridad,
  ca.rol,
  p.direccion || ' ' || COALESCE(p.numero,'') AS direccion_completa,
  com.nombre                               AS comuna,
  u.nombre_completo                        AS contribuyente,
  u.email,
  au.avaluo_sii,
  au.avaluo_snri,
  au.diferencia,
  au.monto_recuperable,
  au.probabilidad_error,
  au.numero_errores,
  ca.monto_estimado_uf,
  ca.asignado_a,
  ca.fecha_creacion,
  ca.fecha_actualizacion,
  ca.origen
FROM public.casos ca
LEFT JOIN public.usuarios u              ON u.id  = ca.usuario_id
LEFT JOIN public.auditorias_usuario au   ON au.id = ca.auditoria_id
LEFT JOIN catastro.predios p             ON p.rol = ca.rol
LEFT JOIN ref.comunas com                ON com.codigo_sii = p.codigo_comuna;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. RPCs — Funciones expuestas a PostgREST
-- ─────────────────────────────────────────────────────────────────────────────

-- RPC 1: Validar ROL y retornar datos completos
CREATE OR REPLACE FUNCTION public.rpc_validar_rol(p_rol text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_predio  catastro.predios%ROWTYPE;
  v_result  jsonb;
BEGIN
  -- Normalizar formato
  p_rol := TRIM(p_rol);

  SELECT * INTO v_predio FROM catastro.predios WHERE rol = p_rol AND activo = true;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'encontrado', false,
      'rol', p_rol,
      'mensaje', 'ROL no encontrado en catastro SNRI'
    );
  END IF;

  SELECT jsonb_build_object(
    'encontrado',          true,
    'rol',                 v_predio.rol,
    'direccion',           v_predio.direccion || ' ' || COALESCE(v_predio.numero,''),
    'comuna',              (SELECT nombre FROM ref.comunas WHERE codigo_sii = v_predio.codigo_comuna),
    'destino',             v_predio.destino_sii,
    'nombre_destino',      (SELECT nombre FROM ref.destinos WHERE codigo = v_predio.destino_sii),
    'serie',               v_predio.serie_predio,
    'sup_terreno_m2',      v_predio.sup_terreno_m2,
    'avaluo_sii',          v_predio.avaluo_total_vigente,
    'avaluo_terreno',      v_predio.avaluo_terreno_vigente,
    'contribucion_anual',  v_predio.contribucion_anual,
    'contribucion_semestre', v_predio.contribucion_semestre,
    'exento',              v_predio.exento,
    'motivo_exencion',     v_predio.motivo_exencion,
    'bam_activo',          v_predio.bam_activo,
    'dfl2_activo',         v_predio.dfl2_activo,
    'afecto_vial',         v_predio.afecto_vial,
    'tipo_zona',           v_predio.tipo_zona_planreg,
    'fecha_actualizacion', v_predio.fecha_actualizacion,
    'construcciones', (
      SELECT jsonb_agg(jsonb_build_object(
        'numero',            numero_construccion,
        'destino',           destino_construccion,
        'sup_m2',            sup_total_m2,
        'material',          material_codigo,
        'calidad',           calidad_codigo,
        'clase',             clase_sii,
        'anio',              anio_construccion,
        'avaluo',            avaluo_construccion
      ) ORDER BY numero_construccion)
      FROM catastro.construcciones WHERE rol = p_rol
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- RPC 2: Recalcular predio y generar/actualizar caso
CREATE OR REPLACE FUNCTION public.rpc_recalcular_predio_y_caso(
  p_rol        text,
  p_caso_id    uuid DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_predio     catastro.predios%ROWTYPE;
  v_params     record;
  v_avaluo_snri numeric;
  v_contrib_snri numeric;
  v_resultado  jsonb;
  v_errores    jsonb := '[]';
  v_proba      numeric;
BEGIN
  SELECT * INTO v_predio FROM catastro.predios WHERE rol = p_rol AND activo = true;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', true, 'mensaje', 'ROL no encontrado');
  END IF;

  -- Parámetros vigentes desde ref.parametros_motor
  SELECT
    (SELECT valor_numerico FROM ref.parametros_motor WHERE codigo = 'TASA_HABITACIONAL_T1') AS tasa_t1,
    (SELECT valor_numerico FROM ref.parametros_motor WHERE codigo = 'TASA_HABITACIONAL_T2') AS tasa_t2,
    (SELECT valor_numerico FROM ref.parametros_motor WHERE codigo = 'MCT_PESOS')            AS mct,
    (SELECT valor_numerico FROM ref.parametros_motor WHERE codigo = 'EXENCION_HABITACIONAL') AS exencion_habit
  INTO v_params;

  -- Recalcular avalúo terreno (simplificado — usar VUTAH real cuando disponible)
  v_avaluo_snri := COALESCE(v_predio.avaluo_terreno_vigente, 0);

  -- Acumular avalúo construcciones con depreciación real
  SELECT v_avaluo_snri + COALESCE(SUM(
    co.sup_util_m2
    * COALESCE(co.vuc_uf_m2, 0) * COALESCE((SELECT valor_numerico::integer FROM ref.parametros_motor WHERE codigo = 'uf_valor_clp'), 38420)  -- UF → pesos (ref.parametros_motor)
    * COALESCE(ref.f_depreciacion(EXTRACT(YEAR FROM NOW())::int - co.anio_construccion), 1)
    * COALESCE(co.factor_condicion_esp, 1)
  ), 0)
  INTO v_avaluo_snri
  FROM catastro.construcciones co
  WHERE co.rol = p_rol;

  -- Detectar errores
  -- ERR-C01: discrepancia m² > 10%
  IF EXISTS (
    SELECT 1 FROM catastro.construcciones c
    WHERE c.rol = p_rol
      AND ABS(c.sup_total_m2 - c.sup_util_m2) / NULLIF(c.sup_total_m2,0) > 0.10
  ) THEN
    v_errores := v_errores || jsonb_build_array(jsonb_build_object(
      'codigo','ERR-C01','descripcion','Discrepancia significativa en m² construcción',
      'impacto_estimado_pct', 8
    ));
  END IF;

  -- ERR-C04: sin recepción final
  IF EXISTS (
    SELECT 1 FROM catastro.construcciones WHERE rol = p_rol AND tiene_recepcion_final = false
  ) THEN
    v_errores := v_errores || jsonb_build_array(jsonb_build_object(
      'codigo','ERR-C04','descripcion','Construcción sin recepción final — posible subregistro',
      'impacto_estimado_pct', 12
    ));
  END IF;

  -- ERR-T01: afecto vial no reconocido en avalúo terreno
  IF v_predio.afecto_vial = false AND v_predio.pct_afectacion_aup > 0 THEN
    v_errores := v_errores || jsonb_build_array(jsonb_build_object(
      'codigo','ERR-T01','descripcion','Posible AUP no aplicada en terreno',
      'impacto_estimado_pct', 5
    ));
  END IF;

  -- Probabilidad de error (heurística)
  v_proba := LEAST(1.0,
    0.15 * jsonb_array_length(v_errores) +
    CASE WHEN ABS(v_avaluo_snri - v_predio.avaluo_total_vigente) / NULLIF(v_predio.avaluo_total_vigente,0) > 0.08
      THEN 0.35 ELSE 0.05 END
  );

  -- Contribución SNRI recalculada
  v_contrib_snri := ref.f_calcular_contribucion(v_avaluo_snri, v_predio.serie_predio);

  v_resultado := jsonb_build_object(
    'rol',              p_rol,
    'avaluo_sii',       v_predio.avaluo_total_vigente,
    'avaluo_snri',      ROUND(v_avaluo_snri, 0),
    'diferencia',       ROUND(v_avaluo_snri - v_predio.avaluo_total_vigente, 0),
    'pct_diferencia',   ROUND((v_avaluo_snri - v_predio.avaluo_total_vigente)
                          / NULLIF(v_predio.avaluo_total_vigente,0) * 100, 2),
    'contribucion_sii', v_predio.contribucion_anual,
    'contribucion_snri', v_contrib_snri,
    'monto_recuperable', ROUND(ABS(v_contrib_snri - COALESCE(v_predio.contribucion_anual,0)), 0),
    'probabilidad_error', v_proba,
    'numero_errores',   jsonb_array_length(v_errores),
    'errores',          v_errores,
    'version_motor',    '2.1'
  );

  RETURN v_resultado;
END;
$$;

-- RPC 3: Crear caso desde usuario
CREATE OR REPLACE FUNCTION public.rpc_crear_caso_desde_usuario(
  p_rol        text,
  p_usuario_id uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_auditoria public.auditorias_usuario%ROWTYPE;
  v_caso_id   uuid;
  v_numero    text;
BEGIN
  -- Tomar última auditoría confirmada del usuario para este ROL
  SELECT * INTO v_auditoria
  FROM public.auditorias_usuario
  WHERE usuario_id = p_usuario_id AND rol = p_rol
  ORDER BY fecha DESC LIMIT 1;

  -- Insertar caso
  INSERT INTO public.casos (
    usuario_id, auditoria_id, rol,
    monto_estimado_uf, estado, origen
  ) VALUES (
    p_usuario_id,
    v_auditoria.id,
    p_rol,
    ROUND(v_auditoria.monto_recuperable / COALESCE((SELECT valor_numerico::integer FROM ref.parametros_motor WHERE codigo = 'uf_valor_clp'), 38420)::numeric, 2),  -- pesos → UF (ref.parametros_motor)
    'recibido',
    'portal_usuario'
  )
  RETURNING id, numero_caso INTO v_caso_id, v_numero;

  -- Actualizar estado de la propiedad del usuario
  UPDATE public.propiedades_usuario
  SET estado = 'caso_creado'
  WHERE usuario_id = p_usuario_id AND rol = p_rol;

  RETURN jsonb_build_object(
    'caso_id',      v_caso_id,
    'numero_caso',  v_numero,
    'estado',       'recibido',
    'mensaje',      'Caso creado exitosamente. Un analista SNRI lo revisará en breve.'
  );
END;
$$;

-- RPC 4: Heatmap de riesgo por propiedades del usuario
CREATE OR REPLACE FUNCTION public.rpc_heatmap_usuario(p_usuario_id uuid)
RETURNS TABLE (
  rol                 text,
  direccion           text,
  comuna              text,
  avaluo_sii          numeric,
  contribucion_actual numeric,
  probabilidad_error  numeric,
  monto_recuperable   numeric,
  estado              text
) LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    pu.rol,
    p.direccion || ' ' || COALESCE(p.numero,'') AS direccion,
    c.nombre,
    p.avaluo_total_vigente,
    p.contribucion_anual,
    au.probabilidad_error,
    au.monto_recuperable,
    pu.estado
  FROM public.propiedades_usuario pu
  LEFT JOIN catastro.predios p         ON p.rol = pu.rol
  LEFT JOIN ref.comunas c              ON c.codigo_sii = p.codigo_comuna
  LEFT JOIN LATERAL (
    SELECT probabilidad_error, monto_recuperable
    FROM public.auditorias_usuario
    WHERE usuario_id = pu.usuario_id AND rol = pu.rol
    ORDER BY fecha DESC LIMIT 1
  ) au ON true
  WHERE pu.usuario_id = p_usuario_id
  ORDER BY COALESCE(au.probabilidad_error, 0) DESC;
$$;

-- RPC 5: Estadísticas por comuna (usado en mapa admin)
CREATE OR REPLACE FUNCTION public.rpc_estadisticas_comuna(p_codigo_comuna integer DEFAULT NULL)
RETURNS TABLE (
  codigo_comuna   integer,
  nombre_comuna   text,
  region          text,
  total_roles     bigint,
  roles_afectos   bigint,
  avaluo_promedio numeric,
  contribucion_total numeric
) LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    codigo_comuna,
    nombre_comuna,
    region_nombre,
    total_roles,
    roles_afectos,
    avaluo_promedio,
    contribucion_anual_total
  FROM catastro.v_estadisticas_comuna
  WHERE p_codigo_comuna IS NULL OR codigo_comuna = p_codigo_comuna
  ORDER BY total_roles DESC;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. ROW LEVEL SECURITY
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE catastro.predios             ENABLE ROW LEVEL SECURITY;
ALTER TABLE catastro.construcciones      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usuarios              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.propiedades_usuario   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documentos_usuario    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auditorias_usuario    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.casos                 ENABLE ROW LEVEL SECURITY;

-- Catastro: lectura pública (solo datos no sensibles)
CREATE POLICY catastro_predios_read ON catastro.predios
  FOR SELECT TO anon, authenticated
  USING (activo = true);

CREATE POLICY catastro_const_read ON catastro.construcciones
  FOR SELECT TO anon, authenticated
  USING (true);

-- Usuarios: solo el propio registro
CREATE POLICY usuarios_own ON public.usuarios
  FOR ALL TO authenticated
  USING (auth_user_id = auth.uid());

-- Propiedades, documentos, auditorías: solo las propias
CREATE POLICY propusu_own ON public.propiedades_usuario
  FOR ALL TO authenticated
  USING (usuario_id = (SELECT id FROM public.usuarios WHERE auth_user_id = auth.uid()));

CREATE POLICY docusu_own ON public.documentos_usuario
  FOR ALL TO authenticated
  USING (usuario_id = (SELECT id FROM public.usuarios WHERE auth_user_id = auth.uid()));

CREATE POLICY audiusu_own ON public.auditorias_usuario
  FOR ALL TO authenticated
  USING (usuario_id = (SELECT id FROM public.usuarios WHERE auth_user_id = auth.uid()));

-- Casos: usuario ve los suyos; admin ve todos
CREATE POLICY casos_usuario ON public.casos
  FOR SELECT TO authenticated
  USING (
    usuario_id = (SELECT id FROM public.usuarios WHERE auth_user_id = auth.uid())
    OR (SELECT rol_sistema FROM public.usuarios WHERE auth_user_id = auth.uid()) IN ('admin','analista')
  );

CREATE POLICY casos_insert ON public.casos
  FOR INSERT TO authenticated
  WITH CHECK (usuario_id = (SELECT id FROM public.usuarios WHERE auth_user_id = auth.uid()));

-- Service role: acceso total
CREATE POLICY catastro_service ON catastro.predios
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY casos_service ON public.casos
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. GRANTS
-- ─────────────────────────────────────────────────────────────────────────────

GRANT USAGE ON SCHEMA catastro TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA catastro TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA catastro TO service_role;

GRANT SELECT ON public.v_rol_resumen, public.v_casos_crm TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_validar_rol TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_recalcular_predio_y_caso TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_crear_caso_desde_usuario TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_heatmap_usuario TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_estadisticas_comuna TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. SEED DE PRUEBA — ROL 15108-624-6 (Algeciras 712, Las Condes)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO catastro.predios (
  rol, codigo_comuna, manzana, predio,
  direccion, numero,
  destino_sii, serie_predio,
  sup_terreno_m2, sup_terreno_util_m2,
  tipo_zona_planreg, coeficiente_constructi, afecto_vial, insubdivisible,
  avaluo_terreno_vigente, avaluo_total_vigente,
  contribucion_anual, contribucion_semestre,
  exento, bam_activo, dfl2_activo,
  fuente_datos, activo
) VALUES (
  '15108-624-6', 15108, '624', '6',
  'ALGECIRAS', '712',
  'A', 'habitacional',
  470, 470,
  'EAb2', 0.80, false, true,
  NULL, NULL,    -- avalúo real se carga desde SII
  NULL, NULL,
  false, false, false,
  'seed_test', true
)
ON CONFLICT (rol) DO NOTHING;

-- Construcciones de prueba para Algeciras 712
INSERT INTO catastro.construcciones (
  rol, numero_construccion,
  destino_construccion, uso_interno,
  sup_total_m2, sup_util_m2, numero_pisos,
  material_codigo, calidad_codigo, clase_sii,
  anio_construccion, tiene_recepcion_final,
  fuente_datos
) VALUES
('15108-624-6', 1, 'A', 'vivienda', 240, 220, 2, 'MA', 1, 'C1', 1998, true, 'seed_test'),
('15108-624-6', 2, 'A', 'vivienda', 65,  55,  1, 'MA', 1, 'C1', 2015, true, 'seed_test')
ON CONFLICT (rol, numero_construccion) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. FUNCIÓN UTILIDAD: Parsear ROL texto a componentes
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION catastro.fn_parsear_rol(p_rol text)
RETURNS TABLE (codigo_comuna integer, manzana text, predio text, valido boolean)
LANGUAGE sql IMMUTABLE AS $$
  SELECT
    SPLIT_PART(TRIM(p_rol), '-', 1)::integer AS codigo_comuna,
    SPLIT_PART(TRIM(p_rol), '-', 2)          AS manzana,
    SPLIT_PART(TRIM(p_rol), '-', 3)          AS predio,
    TRIM(p_rol) ~ '^\d{4,5}-\d{1,4}-\d{1,4}$' AS valido;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- FIN MIGRACIÓN
-- Ejecutar en orden:
--   1. snri_knowledge_repository_part1.sql  (ref schema + tablas base)
--   2. snri_knowledge_repository_part2.sql  (parámetros + funciones)
--   3. snri_knowledge_repository_part3.sql  (motor + vistas ref)
--   4. snri_catastro_roles.sql              (este archivo — catastro + portal)
-- =============================================================================
