-- ============================================================
-- RETAXES — MIGRATION 005: PLATAFORMA COMPLETA
-- Nuevas tablas para: VUT, VUC, Proyecciones, Tokens, API
-- ============================================================
-- Versión: 2.0 | Fecha: Marzo 2026
-- Extiende el schema base para soportar:
--   1. Valores Unitarios de Terreno (VUT) por área homogénea
--   2. Valores Unitarios de Construcción (VUC) por clase/calidad
--   3. Motor de proyección de contribuciones para nuevos desarrollos
--   4. Sistema de tokens/consultas para monetización
--   5. Cache de consultas para performance
-- ============================================================

-- ┌─────────────────────────────────────────────────────────┐
-- │  1. REF.VUT_TERRENO — Valores Unitarios de Terreno      │
-- │  Fuente: PDFs VUT del SII (RE 131/2024)                 │
-- │  Uso: Cruce con catastro.predios.codigo_area_homogenea  │
-- └─────────────────────────────────────────────────────────┘

CREATE TABLE IF NOT EXISTS ref.vut_terreno (
  id                    serial PRIMARY KEY,
  codigo_comuna         integer NOT NULL
    REFERENCES ref.comunas(codigo_sii),
  nombre_comuna         text,
  codigo_area_homogenea text NOT NULL,         -- Ej: "HBB001", "EBB530", "MMB900"

  -- Valor unitario
  vut_pesos_m2          numeric(12,2) NOT NULL, -- $/m2 en pesos del semestre de referencia
  vut_uf_m2             numeric(10,4),          -- UF/m2 (calculado con UF del semestre)

  -- Rango de superficie típico del área
  sup_min_m2            numeric(12,2),          -- Superficie mínima del rango
  sup_max_m2            numeric(12,2),          -- Superficie máxima del rango

  -- Clasificación del área homogénea
  tipo_zona             text,                   -- 'urbana' | 'rural' | 'extension_urbana'
  uso_predominante      text,                   -- 'habitacional' | 'comercial' | 'industrial' | 'mixto'

  -- Vigencia
  reavaluo_ref          text,                   -- '2022' | '2025' — reavalúo de referencia
  semestre_ref          text,                   -- '2S2021' | '1S2025'
  vigente_desde         date,
  vigente_hasta         date,                   -- NULL = vigente

  -- Metadatos
  fuente_pdf            text,                   -- nombre del PDF fuente
  created_at            timestamptz DEFAULT now(),

  CONSTRAINT uq_vut_comuna_area UNIQUE (codigo_comuna, codigo_area_homogenea, reavaluo_ref)
);

CREATE INDEX IF NOT EXISTS idx_vut_comuna ON ref.vut_terreno(codigo_comuna);
CREATE INDEX IF NOT EXISTS idx_vut_area ON ref.vut_terreno(codigo_area_homogenea);
CREATE INDEX IF NOT EXISTS idx_vut_valor ON ref.vut_terreno(vut_pesos_m2);

COMMENT ON TABLE ref.vut_terreno IS
  'Valores Unitarios de Terreno por Área Homogénea (RE 131 Anexo 1). '
  'Permite cruzar con catastro.predios.codigo_area_homogenea para '
  'recalcular avalúo de terreno y proyectar contribuciones.';


-- ┌─────────────────────────────────────────────────────────┐
-- │  2. REF.VUC_CONSTRUCCION — Valores Unitarios Construcc. │
-- │  Fuente: RE 131 Anexo 5 / RE 144                       │
-- │  Uso: Calcular avalúo construcción para proyecciones    │
-- └─────────────────────────────────────────────────────────┘

CREATE TABLE IF NOT EXISTS ref.vuc_construccion (
  id                    serial PRIMARY KEY,

  -- Clasificación
  material_codigo       text
    REFERENCES ref.materiales_construccion(codigo),
  calidad_codigo        integer
    REFERENCES ref.calidades_construccion(codigo),
  clase_construccion    text,                   -- 'A' a 'G' según RE 144
  destino_tipo          text,                   -- 'habitacional' | 'comercial' | 'industrial' | 'bodega' | 'oficina'

  -- Valor unitario
  vuc_pesos_m2          numeric(12,2) NOT NULL, -- $/m2 costo reposición
  vuc_uf_m2             numeric(10,4),          -- UF/m2

  -- Vigencia
  reavaluo_ref          text NOT NULL,          -- '2022' | '2025'
  vigente_desde         date,
  vigente_hasta         date,

  -- Metadatos
  descripcion           text,                   -- "Albañilería, calidad 2, habitacional"
  fuente                text,
  created_at            timestamptz DEFAULT now(),

  CONSTRAINT uq_vuc UNIQUE (material_codigo, calidad_codigo, destino_tipo, reavaluo_ref)
);

CREATE INDEX IF NOT EXISTS idx_vuc_material ON ref.vuc_construccion(material_codigo);
CREATE INDEX IF NOT EXISTS idx_vuc_calidad ON ref.vuc_construccion(calidad_codigo);

COMMENT ON TABLE ref.vuc_construccion IS
  'Valores Unitarios de Construcción (RE 131 Anexo 5). '
  'Costo de reposición por m2 según material, calidad y destino. '
  'Se usa junto con depreciación para calcular avalúo construcción.';


-- ┌─────────────────────────────────────────────────────────┐
-- │  3. PROYECCIONES — Motor de simulación fiscal           │
-- │  Para: desarrolladores inmobiliarios estimando           │
-- │  contribuciones de proyectos en desarrollo               │
-- └─────────────────────────────────────────────────────────┘

CREATE TABLE IF NOT EXISTS public.proyecciones (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id            uuid REFERENCES public.usuarios(id),

  -- Identificación del proyecto
  nombre_proyecto       text NOT NULL,          -- "Edificio Los Alamos"
  tipo_proyecto         text NOT NULL,          -- 'multifamily' | 'oficinas' | 'comercial' | 'bodega' | 'mixto' | 'hotel'
  estado                text DEFAULT 'borrador', -- 'borrador' | 'calculado' | 'archivado'

  -- Ubicación
  codigo_comuna         integer REFERENCES ref.comunas(codigo_sii),
  direccion             text,
  codigo_area_homogenea text,                   -- Para cruzar con VUT
  latitud               numeric(10,7),
  longitud              numeric(10,7),

  -- Terreno
  sup_terreno_m2        numeric(12,2),
  vut_m2_usado          numeric(12,2),          -- VUT aplicado (puede ser override manual)
  avaluo_terreno_proy   numeric(16,2),          -- Avalúo terreno proyectado

  -- Construcción (totales)
  sup_construida_total  numeric(12,2),          -- m2 totales construidos
  num_pisos             integer,
  num_unidades          integer,                -- departamentos / oficinas / locales
  anio_construccion     integer,                -- año estimado de término

  -- Resultado
  avaluo_total_proy     numeric(16,2),          -- Avalúo total proyectado
  contribucion_anual_proy numeric(14,2),        -- Contribución anual estimada
  contribucion_sem_proy numeric(14,2),          -- Contribución semestral
  contribucion_x_unidad numeric(14,2),          -- Contribución promedio por unidad

  -- Parámetros usados
  parametros_usados     jsonb,                  -- Snapshot de tasas/exenciones al momento del cálculo
  detalle_calculo       jsonb,                  -- Desglose completo del cálculo

  -- Metadatos
  created_at            timestamptz DEFAULT now(),
  updated_at            timestamptz DEFAULT now(),
  notas                 text
);

CREATE INDEX IF NOT EXISTS idx_proy_usuario ON public.proyecciones(usuario_id);
CREATE INDEX IF NOT EXISTS idx_proy_comuna ON public.proyecciones(codigo_comuna);
CREATE INDEX IF NOT EXISTS idx_proy_tipo ON public.proyecciones(tipo_proyecto);

COMMENT ON TABLE public.proyecciones IS
  'Simulaciones de contribuciones para proyectos inmobiliarios en desarrollo. '
  'Cada proyección puede tener múltiples unidades con diferentes destinos.';


-- Detalle de unidades dentro de una proyección
CREATE TABLE IF NOT EXISTS public.proyeccion_unidades (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  proyeccion_id         uuid NOT NULL REFERENCES public.proyecciones(id) ON DELETE CASCADE,

  -- Descripción de la unidad
  nombre_unidad         text,                   -- "Dpto Tipo A" | "Local 1" | "Bodega B2"
  destino               text NOT NULL,          -- código destino SII (H, C, O, I, etc.)
  cantidad              integer DEFAULT 1,      -- cuántas unidades de este tipo

  -- Construcción
  sup_m2                numeric(10,2) NOT NULL,
  material_codigo       text,
  calidad_codigo        integer,
  num_pisos             integer DEFAULT 1,

  -- Valores calculados
  vuc_m2_usado          numeric(12,2),
  avaluo_construccion   numeric(16,2),
  contribucion_unitaria numeric(14,2),

  -- Beneficios aplicables
  aplica_dfl2           boolean DEFAULT false,
  aplica_bam            boolean DEFAULT false,

  created_at            timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_proy_unid ON public.proyeccion_unidades(proyeccion_id);

COMMENT ON TABLE public.proyeccion_unidades IS
  'Detalle de unidades dentro de una proyección. Un edificio puede tener '
  'dptos (H), locales comerciales (C), estacionamientos (Z), bodegas (I), etc.';


-- ┌─────────────────────────────────────────────────────────┐
-- │  4. SISTEMA DE TOKENS / CONSULTAS                       │
-- │  Para: monetización y rate limiting                     │
-- └─────────────────────────────────────────────────────────┘

-- Planes de suscripción
CREATE TABLE IF NOT EXISTS public.planes (
  id                    serial PRIMARY KEY,
  codigo                text UNIQUE NOT NULL,   -- 'free' | 'basico' | 'profesional' | 'enterprise'
  nombre                text NOT NULL,
  tokens_diarios        integer NOT NULL,       -- tokens que se renuevan cada día
  tokens_bonus_mensual  integer DEFAULT 0,      -- tokens extra no-renovables por mes

  -- Features
  permite_proyecciones  boolean DEFAULT false,
  permite_auditoria     boolean DEFAULT false,
  permite_exportar      boolean DEFAULT false,
  permite_api           boolean DEFAULT false,
  max_propiedades       integer,                -- NULL = ilimitadas

  -- Pricing
  precio_mensual_clp    integer,
  precio_mensual_uf     numeric(8,4),
  activo                boolean DEFAULT true,
  created_at            timestamptz DEFAULT now()
);

INSERT INTO public.planes (codigo, nombre, tokens_diarios, tokens_bonus_mensual,
  permite_proyecciones, permite_auditoria, permite_exportar, permite_api,
  max_propiedades, precio_mensual_clp) VALUES
('free',         'Gratuito',     5,   0,  false, false, false, false, 3,    0),
('basico',       'Básico',       20,  50, false, true,  false, false, 10,   9990),
('profesional',  'Profesional',  100, 200, true,  true,  true,  false, NULL, 29990),
('enterprise',   'Enterprise',   500, 1000, true, true,  true,  true,  NULL, 99990);

-- Tokens de usuario
CREATE TABLE IF NOT EXISTS public.tokens_usuario (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id            uuid NOT NULL REFERENCES public.usuarios(id),
  plan_id               integer REFERENCES public.planes(id),

  -- Balance
  tokens_disponibles    integer DEFAULT 0,
  tokens_usados_hoy     integer DEFAULT 0,
  fecha_ultimo_reset    date DEFAULT CURRENT_DATE,
  tokens_bonus_restante integer DEFAULT 0,

  -- Suscripción
  suscripcion_inicio    date,
  suscripcion_fin       date,
  estado_suscripcion    text DEFAULT 'activa',  -- 'activa' | 'cancelada' | 'vencida' | 'trial'

  created_at            timestamptz DEFAULT now(),
  updated_at            timestamptz DEFAULT now(),

  CONSTRAINT uq_tokens_usuario UNIQUE (usuario_id)
);

-- Historial de consumo de tokens
CREATE TABLE IF NOT EXISTS public.consumo_tokens (
  id                    bigserial PRIMARY KEY,
  usuario_id            uuid NOT NULL REFERENCES public.usuarios(id),

  -- Qué se consultó
  tipo_consulta         text NOT NULL,          -- 'consulta_rol' | 'auditoria' | 'proyeccion' | 'exportar' | 'api'
  tokens_consumidos     integer NOT NULL DEFAULT 1,

  -- Detalle
  rol_consultado        text,
  parametros            jsonb,                  -- parámetros de la consulta

  -- Resultado
  resultado_exitoso     boolean DEFAULT true,
  tiempo_respuesta_ms   integer,

  created_at            timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_consumo_usuario ON public.consumo_tokens(usuario_id);
CREATE INDEX IF NOT EXISTS idx_consumo_fecha ON public.consumo_tokens(created_at);
CREATE INDEX IF NOT EXISTS idx_consumo_tipo ON public.consumo_tokens(tipo_consulta);

-- Costos por tipo de consulta
INSERT INTO public.planes (codigo, nombre, tokens_diarios, tokens_bonus_mensual,
  permite_proyecciones, permite_auditoria, permite_exportar, permite_api,
  precio_mensual_clp) VALUES
('_config_costos', '_Costos por consulta (tabla interna)', 0, 0, false, false, false, false, 0)
ON CONFLICT (codigo) DO NOTHING;

-- Tabla de costos de tokens por operación
CREATE TABLE IF NOT EXISTS public.costos_token (
  tipo_consulta         text PRIMARY KEY,
  tokens_costo          integer NOT NULL DEFAULT 1,
  descripcion           text
);

INSERT INTO public.costos_token VALUES
('consulta_rol',   1, 'Consulta rápida de un ROL — datos básicos SII'),
('detalle_rol',    2, 'Consulta detallada de un ROL — con construcciones y avalúo desglosado'),
('auditoria_rol',  5, 'Auditoría SNRI completa de un ROL — recálculo + detección errores'),
('proyeccion',     10, 'Proyección de contribuciones para un desarrollo nuevo'),
('exportar_pdf',   3, 'Exportar informe en PDF'),
('api_call',       1, 'Llamada vía API pública');


-- ┌─────────────────────────────────────────────────────────┐
-- │  5. CACHE DE CONSULTAS                                  │
-- │  Para: evitar recálculos repetidos                      │
-- └─────────────────────────────────────────────────────────┘

CREATE TABLE IF NOT EXISTS public.cache_consultas (
  id                    bigserial PRIMARY KEY,
  cache_key             text UNIQUE NOT NULL,    -- hash del query (ej: "rol:15108-624-6:v2")
  tipo                  text NOT NULL,           -- 'consulta_rol' | 'auditoria' | 'proyeccion'

  resultado             jsonb NOT NULL,          -- respuesta cacheada

  -- TTL
  created_at            timestamptz DEFAULT now(),
  expires_at            timestamptz NOT NULL,    -- cuándo expira
  hit_count             integer DEFAULT 0,       -- cuántas veces se usó
  last_hit_at           timestamptz
);

CREATE INDEX IF NOT EXISTS idx_cache_key ON public.cache_consultas(cache_key);
CREATE INDEX IF NOT EXISTS idx_cache_expires ON public.cache_consultas(expires_at);

-- Función: limpiar cache expirado (ejecutar con pg_cron)
CREATE OR REPLACE FUNCTION public.fn_limpiar_cache()
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE
  v_deleted integer;
BEGIN
  DELETE FROM public.cache_consultas WHERE expires_at < now();
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;


-- ┌─────────────────────────────────────────────────────────┐
-- │  6. FUNCIONES DE PROYECCIÓN                             │
-- └─────────────────────────────────────────────────────────┘

-- Función: Obtener VUT para un área homogénea
CREATE OR REPLACE FUNCTION ref.f_vut_area_homogenea(
  p_codigo_area text,
  p_codigo_comuna integer DEFAULT NULL
)
RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT vut_pesos_m2
  FROM ref.vut_terreno
  WHERE codigo_area_homogenea = p_codigo_area
    AND (p_codigo_comuna IS NULL OR codigo_comuna = p_codigo_comuna)
    AND (vigente_hasta IS NULL OR vigente_hasta >= CURRENT_DATE)
  ORDER BY vigente_desde DESC
  LIMIT 1;
$$;

-- Función: Obtener VUC para una combinación material/calidad/destino
CREATE OR REPLACE FUNCTION ref.f_vuc_construccion(
  p_material text,
  p_calidad integer,
  p_destino_tipo text DEFAULT 'habitacional'
)
RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT vuc_pesos_m2
  FROM ref.vuc_construccion
  WHERE material_codigo = p_material
    AND calidad_codigo = p_calidad
    AND destino_tipo = p_destino_tipo
    AND (vigente_hasta IS NULL OR vigente_hasta >= CURRENT_DATE)
  ORDER BY vigente_desde DESC
  LIMIT 1;
$$;

-- Función: Proyectar contribución para un desarrollo nuevo
CREATE OR REPLACE FUNCTION public.fn_proyectar_contribucion(
  p_sup_terreno_m2     numeric,
  p_vut_m2             numeric,        -- VUT del área homogénea ($/m2)
  p_destino            text,           -- código destino SII
  p_sup_construida_m2  numeric,
  p_vuc_m2             numeric,        -- VUC del tipo construcción ($/m2)
  p_anio_construccion  integer DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::integer
)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_avaluo_terreno   numeric;
  v_avaluo_construc  numeric;
  v_dp               numeric;
  v_avaluo_total     numeric;
  v_avaluo_afecto    numeric;
  v_exencion         numeric;
  v_contrib_anual    numeric;
  v_contrib_semestre numeric;
  v_tasa             numeric;
  v_destino_tipo     text;
  v_mct              numeric;
  v_tasa_t1          numeric;
  v_tasa_t2          numeric;
BEGIN
  -- Avalúo terreno
  v_avaluo_terreno := p_sup_terreno_m2 * p_vut_m2;

  -- Depreciación
  v_dp := COALESCE(ref.f_depreciacion(p_anio_construccion), 1.0);

  -- Avalúo construcción
  v_avaluo_construc := p_sup_construida_m2 * p_vuc_m2 * v_dp;

  -- Avalúo total
  v_avaluo_total := v_avaluo_terreno + v_avaluo_construc;

  -- Determinar tipo de destino
  SELECT tasa_contribucion_tipo INTO v_destino_tipo
  FROM ref.destinos WHERE codigo = p_destino;

  -- Exención
  IF v_destino_tipo = 'habitacional' THEN
    SELECT monto_clp INTO v_exencion FROM ref.v_exenciones_vigentes WHERE destino_tipo = 'habitacional';
  ELSIF v_destino_tipo = 'agricola' THEN
    SELECT monto_clp INTO v_exencion FROM ref.v_exenciones_vigentes WHERE destino_tipo = 'agricola';
  ELSE
    v_exencion := 0;
  END IF;

  v_avaluo_afecto := GREATEST(0, v_avaluo_total - COALESCE(v_exencion, 0));

  -- Contribución
  IF v_destino_tipo = 'habitacional' THEN
    SELECT tasa_anual_pct INTO v_tasa_t1 FROM ref.v_tasas_vigentes WHERE destino_tipo = 'habitacional_tramo1';
    SELECT tasa_anual_pct INTO v_tasa_t2 FROM ref.v_tasas_vigentes WHERE destino_tipo = 'habitacional_tramo2';
    SELECT monto_cambio_tasa_clp INTO v_mct FROM ref.tramos_tasa_habitacional
      WHERE vigente_hasta IS NULL ORDER BY vigente_desde DESC LIMIT 1;

    v_contrib_anual := LEAST(v_avaluo_afecto, COALESCE(v_mct, v_avaluo_afecto)) * COALESCE(v_tasa_t1, 0.00893)
                     + GREATEST(0, v_avaluo_afecto - COALESCE(v_mct, v_avaluo_afecto)) * COALESCE(v_tasa_t2, 0.01042);
  ELSE
    SELECT tasa_anual_pct INTO v_tasa FROM ref.v_tasas_vigentes WHERE destino_tipo = 'otros_no_agricola';
    v_contrib_anual := v_avaluo_afecto * COALESCE(v_tasa, 0.01088);
  END IF;

  v_contrib_semestre := v_contrib_anual / 2;

  RETURN jsonb_build_object(
    'avaluo_terreno',      ROUND(v_avaluo_terreno),
    'avaluo_construccion',  ROUND(v_avaluo_construc),
    'depreciacion_factor',  v_dp,
    'avaluo_total',         ROUND(v_avaluo_total),
    'exencion',             COALESCE(v_exencion, 0),
    'avaluo_afecto',        ROUND(v_avaluo_afecto),
    'destino_tipo',         v_destino_tipo,
    'contribucion_anual',   ROUND(v_contrib_anual),
    'contribucion_semestre', ROUND(v_contrib_semestre),
    'contribucion_trimestre', ROUND(v_contrib_semestre / 2),
    'parametros', jsonb_build_object(
      'vut_m2', p_vut_m2,
      'vuc_m2', p_vuc_m2,
      'sup_terreno', p_sup_terreno_m2,
      'sup_construida', p_sup_construida_m2,
      'destino', p_destino,
      'anio_construccion', p_anio_construccion
    )
  );
END;
$$;

COMMENT ON FUNCTION public.fn_proyectar_contribucion IS
  'Proyecta la contribución de un desarrollo nuevo. '
  'Input: terreno + construcción + destino → Output: avalúo y contribución estimados. '
  'Ejemplo: SELECT fn_proyectar_contribucion(500, 150000, ''C'', 2000, 850000, 2026);';


-- ┌─────────────────────────────────────────────────────────┐
-- │  7. FUNCIÓN: Reset diario de tokens                     │
-- └─────────────────────────────────────────────────────────┘

CREATE OR REPLACE FUNCTION public.fn_reset_tokens_diarios()
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE
  v_updated integer;
BEGIN
  UPDATE public.tokens_usuario t
  SET
    tokens_disponibles = p.tokens_diarios + t.tokens_bonus_restante,
    tokens_usados_hoy = 0,
    fecha_ultimo_reset = CURRENT_DATE,
    updated_at = now()
  FROM public.planes p
  WHERE t.plan_id = p.id
    AND t.fecha_ultimo_reset < CURRENT_DATE
    AND t.estado_suscripcion IN ('activa', 'trial');

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated;
END;
$$;

-- Función: Consumir token
CREATE OR REPLACE FUNCTION public.fn_consumir_token(
  p_usuario_id uuid,
  p_tipo_consulta text,
  p_rol text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_costo integer;
  v_disponibles integer;
  v_plan text;
BEGIN
  -- Obtener costo
  SELECT tokens_costo INTO v_costo FROM public.costos_token WHERE tipo_consulta = p_tipo_consulta;
  IF v_costo IS NULL THEN v_costo := 1; END IF;

  -- Reset diario si corresponde
  PERFORM public.fn_reset_tokens_diarios();

  -- Verificar balance
  SELECT tokens_disponibles, p.codigo
  INTO v_disponibles, v_plan
  FROM public.tokens_usuario t
  JOIN public.planes p ON t.plan_id = p.id
  WHERE t.usuario_id = p_usuario_id;

  IF v_disponibles IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Usuario sin plan activo');
  END IF;

  IF v_disponibles < v_costo THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Tokens insuficientes',
      'disponibles', v_disponibles, 'costo', v_costo, 'plan', v_plan);
  END IF;

  -- Consumir
  UPDATE public.tokens_usuario
  SET tokens_disponibles = tokens_disponibles - v_costo,
      tokens_usados_hoy = tokens_usados_hoy + v_costo,
      updated_at = now()
  WHERE usuario_id = p_usuario_id;

  -- Registrar consumo
  INSERT INTO public.consumo_tokens (usuario_id, tipo_consulta, tokens_consumidos, rol_consultado)
  VALUES (p_usuario_id, p_tipo_consulta, v_costo, p_rol);

  RETURN jsonb_build_object('ok', true, 'tokens_consumidos', v_costo,
    'tokens_restantes', v_disponibles - v_costo);
END;
$$;


-- ┌─────────────────────────────────────────────────────────┐
-- │  8. VISTA: Comparables de mercado                       │
-- │  Para: tasadores que buscan predios similares            │
-- └─────────────────────────────────────────────────────────┘

CREATE OR REPLACE VIEW public.v_comparables AS
SELECT
  p.rol,
  p.codigo_comuna,
  c.nombre AS comuna,
  p.direccion,
  p.destino_sii,
  d.nombre AS destino_nombre,
  p.sup_terreno_m2,
  p.avaluo_total_vigente,
  p.contribucion_semestre,
  p.codigo_area_homogenea,
  vut.vut_pesos_m2,
  CASE WHEN p.sup_terreno_m2 > 0
    THEN ROUND(p.avaluo_total_vigente / p.sup_terreno_m2)
    ELSE NULL
  END AS valor_m2_total,
  p.serie_predio
FROM catastro.predios p
LEFT JOIN ref.comunas c ON p.codigo_comuna = c.codigo_sii
LEFT JOIN ref.destinos d ON p.destino_sii = d.codigo
LEFT JOIN ref.vut_terreno vut ON p.codigo_area_homogenea = vut.codigo_area_homogenea
  AND p.codigo_comuna = vut.codigo_comuna
  AND vut.vigente_hasta IS NULL
WHERE p.activo = true;

COMMENT ON VIEW public.v_comparables IS
  'Vista de predios con datos cruzados para búsqueda de comparables. '
  'Incluye VUT, valor por m2, destino y comuna.';


-- ============================================================
-- FIN MIGRATION 005
-- ============================================================
