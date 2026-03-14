-- ============================================================
-- SNRI KNOWLEDGE REPOSITORY — PART 3
-- Vistas utilitarias, funciones helper SQL y seeds de prueba
-- ============================================================

-- ============================================================
-- 23. VISTAS UTILITARIAS
-- ============================================================

-- Vista: Parámetros vigentes del motor (siempre los más recientes)
CREATE OR REPLACE VIEW ref.v_parametros_vigentes AS
SELECT
  clave,
  CASE tipo
    WHEN 'numeric'  THEN valor::numeric
    WHEN 'integer'  THEN valor::integer
    ELSE NULL
  END AS valor_numeric,
  valor AS valor_texto,
  tipo,
  descripcion,
  vigente_desde,
  fuente,
  actualizar_cada
FROM ref.parametros_motor
ORDER BY clave;

COMMENT ON VIEW ref.v_parametros_vigentes IS
  'Vista de acceso rápido a parámetros del motor. '
  'Para obtener un valor: SELECT valor_numeric FROM ref.v_parametros_vigentes WHERE clave = ''tasa_habitacional_t1''';

-- Vista: Tabla de tasas vigentes (más recientes por tipo)
CREATE OR REPLACE VIEW ref.v_tasas_vigentes AS
SELECT DISTINCT ON (destino_tipo)
  destino_tipo,
  tasa_anual_pct,
  vigente_desde,
  descripcion
FROM ref.tasas_impuesto
WHERE (vigente_hasta IS NULL OR vigente_hasta >= CURRENT_DATE)
ORDER BY destino_tipo, vigente_desde DESC;

-- Vista: Montos exentos vigentes
CREATE OR REPLACE VIEW ref.v_exenciones_vigentes AS
SELECT DISTINCT ON (destino_tipo)
  destino_tipo,
  monto_clp,
  monto_uf_ref,
  vigente_desde,
  descripcion
FROM ref.montos_exencion
WHERE (vigente_hasta IS NULL OR vigente_hasta >= CURRENT_DATE)
ORDER BY destino_tipo, vigente_desde DESC;

-- Vista: Resumen completo de parámetros fiscales para el frontend
CREATE OR REPLACE VIEW ref.v_resumen_fiscal_vigente AS
SELECT
  (SELECT monto_clp FROM ref.v_exenciones_vigentes WHERE destino_tipo = 'habitacional') AS exencion_habitacional_clp,
  (SELECT monto_clp FROM ref.v_exenciones_vigentes WHERE destino_tipo = 'agricola')     AS exencion_agricola_clp,
  (SELECT monto_cambio_tasa_clp FROM ref.tramos_tasa_habitacional 
   WHERE vigente_hasta IS NULL ORDER BY vigente_desde DESC LIMIT 1)                      AS mct_habitacional_clp,
  (SELECT tasa_anual_pct FROM ref.v_tasas_vigentes WHERE destino_tipo = 'habitacional_tramo1') AS tasa_t1_pct,
  (SELECT tasa_anual_pct FROM ref.v_tasas_vigentes WHERE destino_tipo = 'habitacional_tramo2') AS tasa_t2_pct,
  (SELECT tasa_anual_pct FROM ref.v_tasas_vigentes WHERE destino_tipo = 'otros_no_agricola')   AS tasa_otros_pct,
  (SELECT tasa_anual_pct FROM ref.v_tasas_vigentes WHERE destino_tipo = 'agricola')            AS tasa_agricola_pct,
  (SELECT tope_avaluo_individual_clp FROM ref.bam_parametros 
   WHERE vigente_hasta IS NULL ORDER BY vigente_desde DESC LIMIT 1)                      AS bam_tope_individual_clp,
  (SELECT tope_patrimonio_total_clp  FROM ref.bam_parametros 
   WHERE vigente_hasta IS NULL ORDER BY vigente_desde DESC LIMIT 1)                      AS bam_tope_patrimonio_clp,
  CURRENT_DATE AS fecha_consulta;

COMMENT ON VIEW ref.v_resumen_fiscal_vigente IS 'Snapshot de todos los parámetros fiscales vigentes para mostrar en UI.';


-- ============================================================
-- 24. FUNCIONES HELPER DEL MOTOR
-- ============================================================

-- Función: Obtener factor de depreciación por año de construcción
CREATE OR REPLACE FUNCTION ref.f_depreciacion(p_año_construccion integer)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
  SELECT factor_dp
  FROM ref.depreciacion_construccion
  WHERE (EXTRACT(YEAR FROM CURRENT_DATE)::integer - p_año_construccion) BETWEEN antiguedad_min AND COALESCE(antiguedad_max, 9999)
  LIMIT 1;
$$;

COMMENT ON FUNCTION ref.f_depreciacion IS
  'Retorna el factor DP para una construcción según su año. '
  'Ejemplo: SELECT ref.f_depreciacion(1985) → 0.450';

-- Función: Calcular avalúo afecto
CREATE OR REPLACE FUNCTION ref.f_avaluo_afecto(
  p_avaluo_total bigint,
  p_destino_tipo text  -- 'habitacional' | 'agricola' | 'otros_no_agricola'
)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
  SELECT GREATEST(0, p_avaluo_total - COALESCE(
    (SELECT monto_clp FROM ref.v_exenciones_vigentes WHERE destino_tipo = p_destino_tipo),
    0
  ));
$$;

-- Función: Calcular contribución neta anual completa
CREATE OR REPLACE FUNCTION ref.f_calcular_contribucion(
  p_avaluo_total      bigint,
  p_destino_tipo      text,    -- 'habitacional' | 'otros_no_agricola' | 'agricola'
  p_es_eriazo         boolean DEFAULT false,
  p_tiene_bam         boolean DEFAULT false,
  p_descuento_bam_pct numeric  DEFAULT 0,     -- 0, 50 o 100
  p_tiene_dfl2        boolean DEFAULT false,
  p_dfl2_vigente      boolean DEFAULT false
)
RETURNS TABLE(
  avaluo_total          bigint,
  monto_exento          bigint,
  avaluo_afecto         bigint,
  contribucion_neta     numeric,
  sobretasa_fiscal      numeric,
  sobretasa_eriazo      numeric,
  descuento_bam         numeric,
  descuento_dfl2        numeric,
  contribucion_anual    numeric,
  contribucion_semestral numeric,
  cuota_trimestral      numeric,
  tasa_efectiva_pct     numeric,
  detalle               jsonb
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_monto_exento      bigint;
  v_avaluo_afecto     bigint;
  v_mct               bigint;
  v_tasa_t1           numeric;
  v_tasa_t2           numeric;
  v_tasa_fija         numeric;
  v_contrib_neta      numeric;
  v_sobretasa_fiscal  numeric;
  v_sobretasa_eriazo  numeric;
  v_desc_bam          numeric;
  v_desc_dfl2         numeric;
  v_contrib_anual     numeric;
BEGIN
  -- 1. Obtener parámetros vigentes
  SELECT monto_clp INTO v_monto_exento
  FROM ref.v_exenciones_vigentes WHERE destino_tipo = p_destino_tipo;
  v_monto_exento := COALESCE(v_monto_exento, 0);

  -- 2. Avalúo afecto
  v_avaluo_afecto := GREATEST(0, p_avaluo_total - v_monto_exento);

  -- 3. Contribución neta según destino
  IF p_destino_tipo = 'habitacional' THEN
    SELECT monto_cambio_tasa_clp INTO v_mct
    FROM ref.tramos_tasa_habitacional WHERE vigente_hasta IS NULL ORDER BY vigente_desde DESC LIMIT 1;

    SELECT tasa_anual_pct/100 INTO v_tasa_t1 FROM ref.v_tasas_vigentes WHERE destino_tipo = 'habitacional_tramo1';
    SELECT tasa_anual_pct/100 INTO v_tasa_t2 FROM ref.v_tasas_vigentes WHERE destino_tipo = 'habitacional_tramo2';

    v_contrib_neta := (LEAST(v_avaluo_afecto, v_mct) * v_tasa_t1)
                    + (GREATEST(0, v_avaluo_afecto - v_mct) * v_tasa_t2);

    -- Sobretasa fiscal 0.025% solo sobre tramo 2
    v_sobretasa_fiscal := GREATEST(0, v_avaluo_afecto - v_mct) * 0.000250;

  ELSIF p_destino_tipo = 'agricola' THEN
    SELECT tasa_anual_pct/100 INTO v_tasa_fija FROM ref.v_tasas_vigentes WHERE destino_tipo = 'agricola';
    v_contrib_neta     := v_avaluo_afecto * v_tasa_fija;
    v_sobretasa_fiscal := 0;

  ELSE -- otros_no_agricola
    SELECT tasa_anual_pct/100 INTO v_tasa_fija FROM ref.v_tasas_vigentes WHERE destino_tipo = 'otros_no_agricola';
    v_contrib_neta     := v_avaluo_afecto * v_tasa_fija;
    -- Sobretasa fiscal 0.025% sobre avalúo afecto total
    v_sobretasa_fiscal := v_avaluo_afecto * 0.000250;
  END IF;

  -- 4. Sobretasa eriazo (solo sitio eriazo)
  v_sobretasa_eriazo := CASE WHEN p_es_eriazo THEN v_contrib_neta ELSE 0 END;

  -- 5. Descuentos
  v_desc_bam  := CASE WHEN p_tiene_bam  THEN v_contrib_neta * (p_descuento_bam_pct / 100) ELSE 0 END;
  v_desc_dfl2 := CASE WHEN p_tiene_dfl2 AND p_dfl2_vigente THEN v_contrib_neta * 0.50 ELSE 0 END;

  -- Aplicar solo el mayor descuento (BAM vs DFL2 no acumulables)
  IF v_desc_bam >= v_desc_dfl2 THEN
    v_desc_dfl2 := 0;
  ELSE
    v_desc_bam := 0;
  END IF;

  -- 6. Total
  v_contrib_anual := v_contrib_neta + v_sobretasa_fiscal + v_sobretasa_eriazo - v_desc_bam - v_desc_dfl2;
  v_contrib_anual := GREATEST(0, v_contrib_anual);

  -- Return
  RETURN QUERY SELECT
    p_avaluo_total,
    v_monto_exento,
    v_avaluo_afecto,
    ROUND(v_contrib_neta, 0),
    ROUND(v_sobretasa_fiscal, 0),
    ROUND(v_sobretasa_eriazo, 0),
    ROUND(v_desc_bam, 0),
    ROUND(v_desc_dfl2, 0),
    ROUND(v_contrib_anual, 0),
    ROUND(v_contrib_anual / 2, 0),
    ROUND(v_contrib_anual / 4, 0),
    CASE WHEN p_avaluo_total > 0 THEN ROUND((v_contrib_anual / p_avaluo_total) * 100, 4) ELSE 0 END,
    jsonb_build_object(
      'destino_tipo', p_destino_tipo,
      'es_eriazo', p_es_eriazo,
      'tiene_bam', p_tiene_bam,
      'tiene_dfl2', p_tiene_dfl2,
      'exencion_aplicada', v_monto_exento > 0
    );
END;
$$;

COMMENT ON FUNCTION ref.f_calcular_contribucion IS
  'Motor de cálculo contribuciones. Uso: '
  'SELECT * FROM ref.f_calcular_contribucion(200000000, ''habitacional''); '
  'Retorna detalle completo incluyendo sobretasas, descuentos y cuotas.';

-- Función: Calcular avalúo construcción desde parámetros
CREATE OR REPLACE FUNCTION ref.f_avaluo_construccion(
  p_material_codigo text,
  p_calidad_codigo  integer,
  p_sup_m2          numeric,
  p_año_construccion integer,
  p_condicion_especial text DEFAULT NULL  -- 'SB', 'MS', 'AL', 'CA', 'CI', NULL
)
RETURNS TABLE (
  clase_sii           text,
  vuc_uf_m2           numeric,
  sup_m2              numeric,
  factor_ce           numeric,
  factor_depreciacion numeric,
  avaluo_uf           numeric,
  antiguedad_años     integer,
  detalle             jsonb
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_vuc       numeric;
  v_clase     text;
  v_dp        numeric;
  v_ce        numeric;
  v_antig     integer;
BEGIN
  -- Obtener VUC
  SELECT valor_uf_m2_ref, clase_sii INTO v_vuc, v_clase
  FROM ref.clases_construccion
  WHERE material_codigo = p_material_codigo AND calidad_codigo = p_calidad_codigo
  ORDER BY vigencia_reavaluo DESC LIMIT 1;

  -- Antigüedad
  v_antig := EXTRACT(YEAR FROM CURRENT_DATE)::integer - p_año_construccion;

  -- Depreciación
  v_dp := ref.f_depreciacion(p_año_construccion);
  IF v_dp IS NULL THEN v_dp := 0.100; END IF; -- mínimo 10%

  -- Condición especial
  SELECT COALESCE(factor_tipico, 1.000) INTO v_ce
  FROM ref.condiciones_especiales WHERE codigo = p_condicion_especial;
  IF v_ce IS NULL THEN v_ce := 1.000; END IF;

  RETURN QUERY SELECT
    v_clase,
    COALESCE(v_vuc, 0),
    p_sup_m2,
    v_ce,
    COALESCE(v_dp, 0.100),
    ROUND(COALESCE(v_vuc, 0) * p_sup_m2 * v_ce * COALESCE(v_dp, 0.100), 2),
    v_antig,
    jsonb_build_object(
      'material', p_material_codigo,
      'calidad', p_calidad_codigo,
      'condicion_especial', p_condicion_especial,
      'año_construccion', p_año_construccion
    );
END;
$$;

COMMENT ON FUNCTION ref.f_avaluo_construccion IS
  'Calcula avalúo de una línea de construcción en UF. '
  'Uso: SELECT * FROM ref.f_avaluo_construccion(''C'', 1, 120, 1995, ''MS'')';


-- ============================================================
-- 25. TABLA DE GRUPOS COMUNALES (para avalúo agrícola)
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.grupos_comunales_agricola (
  id              serial PRIMARY KEY,
  codigo_sii_comuna integer REFERENCES ref.comunas(codigo_sii),
  nombre_comuna   text,
  grupo_comunal   integer NOT NULL,            -- 1-5 donde 1 = mayor costo construcción
  coeficiente_gc  numeric(6,4) NOT NULL,       -- Factor GC en fórmula ATCA = VBC × CM × GC × DP × CE
  descripcion     text
);

-- Grupos comunales referenciales (aproximados — verificar con RE SII vigente)
-- Grupo 1: Mayor costo (RM, Valparaíso, Antofagasta, ciudades principales)
-- Grupo 5: Menor costo (zonas rurales extremas)
INSERT INTO ref.grupos_comunales_agricola (codigo_sii_comuna, nombre_comuna, grupo_comunal, coeficiente_gc, descripcion) VALUES
(13101, 'SANTIAGO',      1, 1.2000, 'RM — Mayor costo de construcción'),
(15108, 'LAS CONDES',    1, 1.2000, 'RM — Mayor costo de construcción'),
(15160, 'VITACURA',      1, 1.2000, 'RM — Mayor costo de construcción'),
(5301,  'VALPARAISO',    2, 1.1000, 'Ciudad principal Región V'),
(2201,  'ANTOFAGASTA',   2, 1.1500, 'Ciudad principal Región II — costo materiales alto'),
(9201,  'TEMUCO',        2, 1.0500, 'Ciudad principal Región IX'),
(10201, 'OSORNO',        3, 0.9500, 'Ciudad secundaria'),
(7201,  'TALCA',         3, 0.9500, 'Ciudad secundaria'),
(8401,  'LOS ANGELES',   3, 0.9000, 'Ciudad secundaria'),
(9101,  'ANGOL',         4, 0.8500, 'Ciudad menor — zona rural'),
(10504, 'PALENA',        5, 0.7500, 'Zona extrema austral');

COMMENT ON TABLE ref.grupos_comunales_agricola IS
  'Grupos comunales para cálculo de construcciones agrícolas. '
  'Los coeficientes son aproximados. Obtener tabla exacta de RE SII vigente para reavalúo agrícola 2024.';


-- ============================================================
-- 26. TIPOS DE DOCUMENTO EN SNRI-USUARIO
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.tipos_documento (
  codigo           text PRIMARY KEY,
  nombre           text NOT NULL,
  descripcion      text,
  utilidad_snri    text,
  es_critico       boolean DEFAULT false,
  fuente           text                        -- Entidad que emite el documento
);

INSERT INTO ref.tipos_documento VALUES
('CIP',         'Certificado de Informaciones Previas',
 'Emitido por DOM comunal. Indica normas urbanísticas del predio: zonificación, CC, COS, subdivisión.',
 'Verificar zonificación, CC, AUP, insubdivisibilidad, restricciones edificación',
 true, 'DOM Municipal'),

('CERT_AVALUO', 'Certificado de Avalúo SII',
 'Emitido por SII. Indica avalúo fiscal vigente, destino, superficie, clase construcción.',
 'Verificar datos catastro SII: m², año construcción, clase, calidad, destino',
 true, 'SII'),

('PERMISO_EDIF','Permiso de Edificación',
 'Autorización DOM para construir o ampliar. Indica m² aprobados, año, plano.',
 'Verificar superficie construida legal, año construcción, condiciones especiales (mansarda, subterráneo)',
 false, 'DOM Municipal'),

('RECEPCION_FINAL','Recepción Final de Obras',
 'Certificado DOM que certifica que la obra terminó según lo aprobado.',
 'Confirmar año real de término construcción para calcular depreciación correcta',
 false, 'DOM Municipal'),

('ESCRITURA',   'Escritura de Dominio',
 'Escritura pública de compraventa o dominio vigente.',
 'Verificar superficie terreno real, descripción construcciones, precio de referencia',
 false, 'Notaría / CBR'),

('PLANO_LOTEO', 'Plano de Subdivisión o Loteo',
 'Plano catastral con subdivisión aprobada por DOM.',
 'Verificar superficie exacta del lote, lindes, afectaciones',
 false, 'DOM / CBR'),

('PLANO_ARQT',  'Planos de Arquitectura',
 'Planos de plantas, elevaciones y cortes de la construcción.',
 'Verificar m² reales, condiciones especiales (mansarda, altillo, subterráneo), calidad',
 false, 'Arquitecto / Archivo DOM'),

('TITULO_SERV', 'Título o Certificado de Servidumbre',
 'Documento legal que establece servidumbre activa sobre el predio.',
 'Justificar descuento por servidumbre en avalúo terreno',
 false, 'Notaría / CBR'),

('CERT_DFL2',   'Certificado DFL-2',
 'Certifica que la vivienda está acogida al beneficio DFL-2.',
 'Verificar elegibilidad y vigencia del beneficio DFL-2 para descuento en contribuciones',
 false, 'SII'),

('CBR_ESCRITURA','Certificado CBR / Historial CBR',
 'Historial de transferencias del predio en el Conservador de Bienes Raíces.',
 'Verificar precios de transferencias comparables para MCM (Método A)',
 false, 'CBR'),

('FOTO_INSPECCION','Fotografías de Inspección',
 'Registro fotográfico interior y exterior de la propiedad.',
 'Evidenciar estado de conservación, calidad real de terminaciones',
 false, 'Tasador / Propietario');

COMMENT ON TABLE ref.tipos_documento IS
  'Catálogo de documentos requeridos para auditoría SNRI. '
  'Los documentos críticos (CIP + Cert. Avalúo) son indispensables para cualquier cálculo.';


-- ============================================================
-- 27. SEEDS MÍNIMOS PARA TESTING
-- ============================================================

-- Usuario de prueba (contribuyente)
-- (Asume que la tabla 'usuarios' existe en el schema público de SNRI)
-- INSERT INTO public.usuarios (id, nombre, email, rol_sistema) VALUES
-- ('00000000-0000-0000-0000-000000000001', 'Usuario Test', 'test@snri.cl', 'contribuyente')
-- ON CONFLICT DO NOTHING;

-- Ejemplo de consulta de cálculo completo
COMMENT ON SCHEMA ref IS
  'Schema de referencia SNRI. Para usar las funciones de cálculo: '
  '-- Ejemplo 1: Contribución habitacional $200M '
  'SELECT * FROM ref.f_calcular_contribucion(200000000, ''habitacional''); '
  '-- Ejemplo 2: Depreciación para casa de 1990 '
  'SELECT ref.f_depreciacion(1990); '
  '-- Ejemplo 3: Avalúo construcción C1, 120m², año 1995, mansarda '
  'SELECT * FROM ref.f_avaluo_construccion(''C'', 1, 120, 1995, ''MS''); '
  '-- Ejemplo 4: Todos los parámetros fiscales vigentes '
  'SELECT * FROM ref.v_resumen_fiscal_vigente;';


-- ============================================================
-- 28. ÍNDICES PARA PERFORMANCE
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_destinos_serie           ON ref.destinos(serie);
CREATE INDEX IF NOT EXISTS idx_comunas_region           ON ref.comunas(region);
CREATE INDEX IF NOT EXISTS idx_comunas_rm               ON ref.comunas(es_rm);
CREATE INDEX IF NOT EXISTS idx_tasas_vigencia           ON ref.tasas_impuesto(vigente_desde, vigente_hasta);
CREATE INDEX IF NOT EXISTS idx_exencion_vigencia        ON ref.montos_exencion(vigente_desde, vigente_hasta, destino_tipo);
CREATE INDEX IF NOT EXISTS idx_depr_antiguedad          ON ref.depreciacion_construccion(antiguedad_min, antiguedad_max);
CREATE INDEX IF NOT EXISTS idx_clases_construccion      ON ref.clases_construccion(material_codigo, calidad_codigo);
CREATE INDEX IF NOT EXISTS idx_errores_categoria        ON ref.errores_tipicos(categoria);
CREATE INDEX IF NOT EXISTS idx_formulas_fase            ON ref.formulas_calculo(fase, serie);
CREATE INDEX IF NOT EXISTS idx_parametros_clave         ON ref.parametros_motor(clave);


-- ============================================================
-- 29. ROW LEVEL SECURITY (solo lectura pública)
-- ============================================================

-- Habilitar RLS en tablas ref (todas son públicamente legibles)
ALTER TABLE ref.normativa                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.destinos                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.materiales_construccion    ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.calidades_construccion     ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.clases_construccion        ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.condiciones_especiales     ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.tipos_suelo_agricola       ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.comunas                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.tasas_impuesto             ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.sobretasas                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.montos_exencion            ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.tramos_tasa_habitacional   ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.depreciacion_construccion  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.bam_parametros             ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.dfl2_parametros            ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.reavaluo_historico         ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.reajuste_ipc_semestral     ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.factores_homologacion      ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.errores_tipicos            ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.formulas_calculo           ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.parametros_motor           ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.grupos_comunales_agricola  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ref.tipos_documento            ENABLE ROW LEVEL SECURITY;

-- Políticas: LECTURA pública (anon y authenticated)
-- Solo escritura para service_role (sin policy = solo service_role puede escribir)

DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'normativa','destinos','materiales_construccion','calidades_construccion',
    'clases_construccion','condiciones_especiales','tipos_suelo_agricola',
    'comunas','tasas_impuesto','sobretasas','montos_exencion',
    'tramos_tasa_habitacional','depreciacion_construccion','bam_parametros',
    'dfl2_parametros','reavaluo_historico','reajuste_ipc_semestral',
    'factores_homologacion','errores_tipicos','formulas_calculo',
    'parametros_motor','grupos_comunales_agricola','tipos_documento'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format('
      CREATE POLICY "read_public_%1$s" ON ref.%1$s
      FOR SELECT TO anon, authenticated USING (true);
    ', t);
  END LOOP;
END $$;

-- Restricción: solo service_role puede modificar tablas de referencia
-- (No se crean políticas INSERT/UPDATE/DELETE → por defecto bloqueadas con RLS activo)


-- ============================================================
-- 30. GRANTS
-- ============================================================

-- Acceso de lectura al schema ref para roles de la aplicación
GRANT USAGE ON SCHEMA ref TO anon, authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA ref TO anon, authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ref TO anon, authenticated;

-- Solo service_role puede modificar
GRANT ALL ON ALL TABLES    IN SCHEMA ref TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA ref TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA ref TO service_role;


-- ============================================================
-- VERIFICACIÓN FINAL
-- ============================================================

-- Ejecutar estas queries para verificar instalación correcta:
/*
SELECT COUNT(*) AS comunas          FROM ref.comunas;               -- debe ser ~345
SELECT COUNT(*) AS destinos         FROM ref.destinos;              -- debe ser 20
SELECT COUNT(*) AS materiales       FROM ref.materiales_construccion; -- debe ser 24+
SELECT COUNT(*) AS clases           FROM ref.clases_construccion;   -- debe ser 22
SELECT COUNT(*) AS errores          FROM ref.errores_tipicos;       -- debe ser 11
SELECT COUNT(*) AS formulas         FROM ref.formulas_calculo;      -- debe ser 12
SELECT COUNT(*) AS parametros       FROM ref.parametros_motor;      -- debe ser 16

-- Test función contribuciones habitacionales:
SELECT * FROM ref.f_calcular_contribucion(200000000, 'habitacional');
-- Esperado: avaluo_afecto ~$141.9M, contribucion_anual ~$1.34M aprox

-- Test depreciación:
SELECT ref.f_depreciacion(1990); -- Esperado: ~0.45 (45 años → factor 0.450)
SELECT ref.f_depreciacion(2020); -- Esperado: ~0.95 (5 años → factor 0.950)

-- Test resumen fiscal:
SELECT * FROM ref.v_resumen_fiscal_vigente;
*/
