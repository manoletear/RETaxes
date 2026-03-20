-- ============================================================
-- RETAXES — MIGRATION 006: CORRECCIONES AL MOTOR DE CÁLCULO
-- ============================================================
-- Fecha: 2026-03-20
-- Corrige 6 errores detectados en auditoría de fórmulas:
--
-- [CRÍTICO] Tasa otros no agrícola: 1.088% → 1.042%
-- [CRÍTICO] Sobretasa Art. 7°bis: era fija 0.025%, ahora progresiva
-- [ALTO]    Montos exentos: tabla semestral con valores actualizados
-- [ALTO]    MCT: actualizado con tabla semestral
-- [ALTO]    Alza gradual: nueva tabla + función
-- [BAJO]    F08: corregir naming semestral vs trimestral
-- ============================================================


-- ┌─────────────────────────────────────────────────────────┐
-- │  1. CORREGIR TASA OTROS NO AGRÍCOLA: 1.088% → 1.042%   │
-- │  Fuente: DS 437 + Reavalúo 2025                         │
-- └─────────────────────────────────────────────────────────┘

-- Cerrar la tasa vieja
UPDATE ref.tasas_impuesto
SET vigente_hasta = '2024-12-31'
WHERE destino_tipo = 'otros_no_agricola'
  AND tasa_anual_pct = 1.0880
  AND vigente_desde = '2025-01-01';

-- Insertar la tasa correcta
INSERT INTO ref.tasas_impuesto (vigente_desde, vigente_hasta, destino_tipo, tasa_anual_pct, descripcion, normativa_ref)
VALUES ('2025-01-01', NULL, 'otros_no_agricola', 1.0420,
  'Tasa fija para comercio, industria, bodega, oficina, hotel y otros no agrícolas. '
  'CORREGIDO: era 1.088% (reavalúo 2018/2022), ahora 1.042% (reavalúo 2025).',
  'REAVALIUO_2025')
ON CONFLICT DO NOTHING;

-- Actualizar parámetro motor
UPDATE ref.parametros_motor
SET valor = '0.010420', vigente_desde = '2025-01-01',
    descripcion = 'Tasa fija otros no agrícola (1.042%) — CORREGIDO de 1.088%'
WHERE clave = 'tasa_otros_no_agricola';


-- ┌─────────────────────────────────────────────────────────┐
-- │  2. SOBRETASA ART. 7°BIS: PROGRESIVA POR PATRIMONIO    │
-- │  Fuente: Ley 17.235 Art. 7° bis                        │
-- └─────────────────────────────────────────────────────────┘

-- La "sobretasa_beneficio_fiscal" de 0.025% del Art. 7° se mantiene
-- (aplica sobre tramo 2 habitacional y total otros)
-- PERO el Art. 7°bis es DIFERENTE: es progresiva por patrimonio total del RUT

CREATE TABLE IF NOT EXISTS ref.sobretasa_art7bis (
  id                serial PRIMARY KEY,
  vigente_desde     date NOT NULL,
  vigente_hasta     date,
  tramo_desde_uta   numeric(8,1) NOT NULL,    -- Patrimonio desde (en UTA)
  tramo_hasta_uta   numeric(8,1),             -- NULL = sin tope
  tasa_pct          numeric(6,4) NOT NULL,    -- Tasa porcentual
  descripcion       text,
  normativa_ref     text REFERENCES ref.normativa(codigo)
);

INSERT INTO ref.sobretasa_art7bis (vigente_desde, vigente_hasta, tramo_desde_uta, tramo_hasta_uta, tasa_pct, descripcion, normativa_ref) VALUES
('2025-01-01', NULL,  670,  827.0, 0.0000,
 'Patrimonio inmobiliario 670-827 UTA: sin sobretasa Art. 7°bis (solo aplica sobretasa Art. 7° de 0.025%)',
 'LEY_17235'),
('2025-01-01', NULL,  827.0, 1450.0, 0.0750,
 'Patrimonio inmobiliario 827-1450 UTA: sobretasa 0.075%',
 'LEY_17235'),
('2025-01-01', NULL, 1450.0, 1863.0, 0.1500,
 'Patrimonio inmobiliario 1450-1863 UTA: sobretasa 0.150%',
 'LEY_17235'),
('2025-01-01', NULL, 1863.0, NULL, 0.4250,
 'Patrimonio inmobiliario >1863 UTA: sobretasa 0.425%',
 'LEY_17235');

COMMENT ON TABLE ref.sobretasa_art7bis IS
  'Art. 7°bis Ley 17.235: Sobretasa PROGRESIVA por patrimonio inmobiliario total del RUT. '
  'Se aplica sobre el AVALÚO FISCAL TOTAL de cada propiedad que exceda 670 UTA de patrimonio acumulado. '
  'Es DIFERENTE de la sobretasa Art. 7° (0.025%) que es fija y se aplica por predio. '
  'UTA 2025 ≈ $792.000 → 827 UTA ≈ $655M patrimonio inmobiliario. '
  'IMPORTANTE: Requiere conocer el patrimonio TOTAL del RUT (todas las propiedades sumadas).';


-- ┌─────────────────────────────────────────────────────────┐
-- │  3. MONTOS EXENTOS: TABLA SEMESTRAL ACTUALIZADA         │
-- │  Fuente: SII reajustes semestrales                      │
-- └─────────────────────────────────────────────────────────┘

-- Corregir los montos existentes y agregar semestres faltantes
-- 1S2025: $56,846,995 (confirmado SII web)
-- 2S2025: ~$58,040,782 (nuestro valor original — cercano)
-- 1S2026: $60,030,710 (confirmado SII web)

-- Cerrar el registro incorrecto
UPDATE ref.montos_exencion
SET vigente_hasta = '2025-06-30'
WHERE destino_tipo = 'habitacional'
  AND monto_clp = 58040782
  AND vigente_desde = '2025-01-01';

-- Insertar valores semestrales correctos
INSERT INTO ref.montos_exencion (vigente_desde, vigente_hasta, destino_tipo, monto_clp, monto_uf_ref, factor_ipc_aplicado, descripcion, fuente) VALUES
-- 1er semestre 2025
('2025-01-01', '2025-06-30', 'habitacional', 56846995, NULL, 1.021,
 'Exención habitacional 1S2025 — Factor IPC 1.021', 'SII oficial'),
('2025-01-01', '2025-06-30', 'agricola', 46192449, NULL, 1.021,
 'Exención agrícola 1S2025 (estimado con factor IPC)', 'SII estimado'),
-- 2do semestre 2025
('2025-07-01', '2025-12-31', 'habitacional', 58040782, NULL, NULL,
 'Exención habitacional 2S2025', 'SII estimado'),
('2025-07-01', '2025-12-31', 'agricola', 47192449, NULL, NULL,
 'Exención agrícola 2S2025', 'SII estimado'),
-- 1er semestre 2026
('2026-01-01', NULL, 'habitacional', 60030710, NULL, 1.015,
 'Exención habitacional 1S2026 — Factor IPC 1.015', 'SII oficial sii.cl/ayudas'),
('2026-01-01', NULL, 'agricola', 48810443, NULL, 1.015,
 'Exención agrícola 1S2026', 'SII oficial sii.cl/ayudas'),
('2026-01-01', NULL, 'otros_no_agricola', 0, NULL, NULL,
 'Sin exención para otros destinos', 'Ley 17.235')
ON CONFLICT DO NOTHING;

-- Actualizar parámetros motor con valores 1S2026 (más actuales)
UPDATE ref.parametros_motor SET valor = '60030710', vigente_desde = '2026-01-01',
  descripcion = 'Monto exento habitacional CLP 1S2026 ($60,030,710)'
WHERE clave = 'monto_exento_habitacional';

UPDATE ref.parametros_motor SET valor = '48810443', vigente_desde = '2026-01-01',
  descripcion = 'Monto exento agrícola CLP 1S2026 ($48,810,443)'
WHERE clave = 'monto_exento_agricola';


-- ┌─────────────────────────────────────────────────────────┐
-- │  4. MCT: ACTUALIZAR CON TABLA SEMESTRAL                 │
-- └─────────────────────────────────────────────────────────┘

-- Cerrar MCT viejo
UPDATE ref.tramos_tasa_habitacional
SET vigente_hasta = '2025-12-31'
WHERE monto_cambio_tasa_clp = 207288476
  AND vigente_desde = '2025-01-01'
  AND vigente_hasta IS NULL;

-- MCT 1S2026 (confirmado SII)
INSERT INTO ref.tramos_tasa_habitacional (vigente_desde, vigente_hasta, monto_cambio_tasa_clp, descripcion)
VALUES ('2026-01-01', NULL, 214395361,
  'MCT 1S2026 ($214,395,361). Factor IPC 1.015. '
  'Avalúo Afecto ≤ MCT → Tasa 0.893%. Exceso → Tasa 1.042%.')
ON CONFLICT DO NOTHING;

-- Actualizar parámetro motor
UPDATE ref.parametros_motor SET valor = '214395361', vigente_desde = '2026-01-01',
  descripcion = 'MCT habitacional CLP 1S2026 ($214,395,361)'
WHERE clave = 'monto_cambio_tasa';


-- ┌─────────────────────────────────────────────────────────┐
-- │  5. ALZA GRADUAL: NUEVA TABLA + FUNCIÓN                 │
-- │  Fuente: Ley 17.235, SII Reavalúo 2025                 │
-- └─────────────────────────────────────────────────────────┘

CREATE TABLE IF NOT EXISTS ref.alza_gradual (
  id                serial PRIMARY KEY,
  reavaluo_ref      text NOT NULL,             -- '2025' | '2024' | '2022'
  serie             text NOT NULL,             -- 'no_agricola' | 'agricola'
  semestre_orden    integer NOT NULL,          -- 1, 2, 3, ... desde inicio reavalúo
  fecha_inicio      date NOT NULL,
  fecha_fin         date,
  alza_max_pct      numeric(5,2) NOT NULL,     -- % máximo de alza permitido en este semestre
  alza_acumulada_pct numeric(5,2),             -- % acumulado hasta este semestre
  descripcion       text,

  CONSTRAINT uq_alza_gradual UNIQUE (reavaluo_ref, serie, semestre_orden)
);

-- Alza gradual Reavalúo No Agrícola 2025
INSERT INTO ref.alza_gradual (reavaluo_ref, serie, semestre_orden, fecha_inicio, fecha_fin, alza_max_pct, alza_acumulada_pct, descripcion) VALUES
('2025', 'no_agricola', 1, '2025-01-01', '2025-06-30', 25.00, 25.00,
 'Semestre 1: alza máxima 25% sobre contribución del semestre anterior al reavalúo'),
('2025', 'no_agricola', 2, '2025-07-01', '2025-12-31', 10.00, 35.00,
 'Semestre 2: alza máxima +10% adicional sobre el monto pagado en S1'),
('2025', 'no_agricola', 3, '2026-01-01', '2026-06-30', 10.00, 45.00,
 'Semestre 3: alza máxima +10% adicional'),
('2025', 'no_agricola', 4, '2026-07-01', '2026-12-31', 10.00, 55.00,
 'Semestre 4: alza máxima +10% adicional');

-- Alza gradual Reavalúo Agrícola 2024
INSERT INTO ref.alza_gradual (reavaluo_ref, serie, semestre_orden, fecha_inicio, fecha_fin, alza_max_pct, alza_acumulada_pct, descripcion) VALUES
('2024', 'agricola', 1, '2024-01-01', '2024-06-30', 25.00, 25.00,
 'Semestre 1 reavalúo agrícola 2024'),
('2024', 'agricola', 2, '2024-07-01', '2024-12-31', 10.00, 35.00,
 'Semestre 2'),
('2024', 'agricola', 3, '2025-01-01', '2025-06-30', 10.00, 45.00,
 'Semestre 3'),
('2024', 'agricola', 4, '2025-07-01', '2025-12-31', 10.00, 55.00,
 'Semestre 4');

COMMENT ON TABLE ref.alza_gradual IS
  'Mecanismo de alza gradual: cuando un reavalúo sube la contribución >25%, '
  'el SII distribuye el alza en semestres. Primer semestre máx +25%, luego +10% cada uno. '
  'La contribución REAL del SII en el Rol de Cobro usa el alza gradual, NO el avalúo final directo. '
  'Sin esta tabla, el cálculo puede diferir ~7-14% del valor real SII.';


-- Función: Aplicar alza gradual a una contribución calculada
CREATE OR REPLACE FUNCTION ref.f_aplicar_alza_gradual(
  p_contribucion_nueva    numeric,   -- Contribución calculada con avalúo nuevo
  p_contribucion_anterior numeric,   -- Contribución del semestre pre-reavalúo
  p_reavaluo_ref          text,      -- '2025' | '2024'
  p_serie                 text,      -- 'no_agricola' | 'agricola'
  p_fecha                 date DEFAULT CURRENT_DATE
)
RETURNS TABLE (
  contribucion_con_alza_gradual numeric,
  contribucion_sin_alza_gradual numeric,
  alza_pct_aplicada             numeric,
  semestre_alza                 integer,
  en_periodo_alza_gradual       boolean
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_semestre   record;
  v_tope       numeric;
  v_resultado  numeric;
BEGIN
  -- Buscar el semestre de alza gradual vigente
  SELECT * INTO v_semestre
  FROM ref.alza_gradual
  WHERE reavaluo_ref = p_reavaluo_ref
    AND serie = p_serie
    AND p_fecha BETWEEN fecha_inicio AND COALESCE(fecha_fin, '2099-12-31')
  LIMIT 1;

  -- Si no hay alza gradual vigente, retornar contribución completa
  IF NOT FOUND THEN
    RETURN QUERY SELECT
      p_contribucion_nueva,
      p_contribucion_nueva,
      0::numeric,
      0,
      false;
    RETURN;
  END IF;

  -- Calcular tope con alza gradual acumulada
  v_tope := p_contribucion_anterior * (1 + v_semestre.alza_acumulada_pct / 100);

  -- La contribución real es el MENOR entre: calculada o tope
  v_resultado := LEAST(p_contribucion_nueva, v_tope);

  RETURN QUERY SELECT
    ROUND(v_resultado, 0),
    ROUND(p_contribucion_nueva, 0),
    ROUND(((v_resultado / NULLIF(p_contribucion_anterior, 0)) - 1) * 100, 2),
    v_semestre.semestre_orden,
    true;
END;
$$;

COMMENT ON FUNCTION ref.f_aplicar_alza_gradual IS
  'Aplica el mecanismo de alza gradual a una contribución calculada. '
  'Requiere conocer la contribución del semestre anterior al reavalúo. '
  'Retorna la contribución REAL (con tope) y la teórica (sin tope). '
  'Ejemplo: SELECT * FROM ref.f_aplicar_alza_gradual(500000, 300000, ''2025'', ''no_agricola'');';


-- ┌─────────────────────────────────────────────────────────┐
-- │  6. CORREGIR F08 NAMING + ACTUALIZAR FÓRMULAS           │
-- └─────────────────────────────────────────────────────────┘

UPDATE ref.formulas_calculo SET
  nombre = 'Cuota Trimestral y Contribución Semestral',
  formula_latex = 'C_{trim} = CA / 4 ;\quad C_{sem} = CA / 2',
  formula_sql = 'cuota_trimestral := contribucion_anual / 4; contribucion_semestral := contribucion_anual / 2',
  variables = '{"C_trim": "Cuota trimestral (lo que se paga cada cuota)", "C_sem": "Contribución semestral (lo que muestra el Rol de Cobro)", "CA": "Contribución Anual Total"}',
  notas = 'SII cobra en 4 cuotas: abril, junio, septiembre, noviembre. '
          'El Rol de Cobro Semestral muestra CA/2. El campo contribucion_semestre en seeds = CA/2.'
WHERE codigo = 'F08_CONTRIBUCION_CUOTA';

-- Agregar fórmula de alza gradual
INSERT INTO ref.formulas_calculo (codigo, nombre, fase, serie, formula_latex, formula_sql, variables, normativa_ref, notas) VALUES
('F13_ALZA_GRADUAL',
 'Mecanismo de Alza Gradual',
 'ajuste', 'ambas',
 'C_{real} = MIN(C_{nueva}, C_{anterior} \times (1 + AG_{acum}))',
 'contribucion_real := LEAST(contribucion_nueva, contribucion_anterior * (1 + alza_acumulada/100))',
 '{"C_real": "Contribución que realmente paga el contribuyente", "C_nueva": "Contribución calculada con avalúo del reavalúo", "C_anterior": "Contribución del semestre pre-reavalúo", "AG_acum": "% acumulado de alza gradual permitida"}',
 'LEY_17235',
 'Aplica cuando un reavalúo sube la contribución >25%. S1: máx +25%, S2+: máx +10% adicional por semestre. '
 'Sin esto, el cálculo teórico difiere ~7-14% del Rol de Cobro real del SII.')
ON CONFLICT (codigo) DO UPDATE SET
  nombre = EXCLUDED.nombre, formula_latex = EXCLUDED.formula_latex,
  formula_sql = EXCLUDED.formula_sql, variables = EXCLUDED.variables, notas = EXCLUDED.notas;

-- Agregar fórmula Art. 7°bis
INSERT INTO ref.formulas_calculo (codigo, nombre, fase, serie, formula_latex, formula_sql, variables, normativa_ref, notas) VALUES
('F14_SOBRETASA_ART7BIS',
 'Sobretasa Progresiva Art. 7°bis (por patrimonio)',
 'fase2_computo', 'ambas',
 'ST_{7bis} = \sum_{tramos} MAX(0, MIN(AF, T_{sup}) - T_{inf}) \times t_i',
 'sobretasa := sum of (min(avaluo, tramo_sup) - tramo_inf) * tasa for each tramo',
 '{"ST_7bis": "Sobretasa Art. 7°bis", "AF": "Avalúo fiscal total de la propiedad", "T_inf/T_sup": "Límites del tramo en UTA", "t_i": "Tasa del tramo (0.075/0.15/0.425%)"}',
 'LEY_17235',
 'Se aplica sobre el patrimonio inmobiliario TOTAL del RUT (todas las propiedades sumadas). '
 'Requiere conocer el patrimonio completo del contribuyente. '
 'No confundir con la sobretasa Art. 7° (0.025%) que es fija y por predio.')
ON CONFLICT (codigo) DO UPDATE SET
  nombre = EXCLUDED.nombre, formula_latex = EXCLUDED.formula_latex,
  formula_sql = EXCLUDED.formula_sql, variables = EXCLUDED.variables, notas = EXCLUDED.notas;


-- ┌─────────────────────────────────────────────────────────┐
-- │  7. ACTUALIZAR FUNCIÓN f_calcular_contribucion          │
-- │  Corrige tasa otros y mejora documentación               │
-- └─────────────────────────────────────────────────────────┘

CREATE OR REPLACE FUNCTION ref.f_calcular_contribucion(
  p_avaluo_total      bigint,
  p_destino_tipo      text,    -- 'habitacional' | 'otros_no_agricola' | 'agricola'
  p_es_eriazo         boolean DEFAULT false,
  p_tiene_bam         boolean DEFAULT false,
  p_descuento_bam_pct numeric  DEFAULT 0,
  p_tiene_dfl2        boolean DEFAULT false,
  p_dfl2_vigente      boolean DEFAULT false,
  p_fecha_calculo     date    DEFAULT CURRENT_DATE  -- NUEVO: para seleccionar parámetros del semestre correcto
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
  -- 1. Obtener parámetros vigentes PARA LA FECHA DE CÁLCULO
  SELECT monto_clp INTO v_monto_exento
  FROM ref.montos_exencion
  WHERE destino_tipo = p_destino_tipo
    AND p_fecha_calculo BETWEEN vigente_desde AND COALESCE(vigente_hasta, '2099-12-31')
  ORDER BY vigente_desde DESC LIMIT 1;
  v_monto_exento := COALESCE(v_monto_exento, 0);

  -- 2. Avalúo afecto
  v_avaluo_afecto := GREATEST(0, p_avaluo_total - v_monto_exento);

  -- 3. Contribución neta según destino
  IF p_destino_tipo = 'habitacional' THEN
    -- MCT para la fecha de cálculo
    SELECT monto_cambio_tasa_clp INTO v_mct
    FROM ref.tramos_tasa_habitacional
    WHERE p_fecha_calculo BETWEEN vigente_desde AND COALESCE(vigente_hasta, '2099-12-31')
    ORDER BY vigente_desde DESC LIMIT 1;

    SELECT tasa_anual_pct/100 INTO v_tasa_t1
    FROM ref.tasas_impuesto
    WHERE destino_tipo = 'habitacional_tramo1'
      AND p_fecha_calculo BETWEEN vigente_desde AND COALESCE(vigente_hasta, '2099-12-31')
    ORDER BY vigente_desde DESC LIMIT 1;

    SELECT tasa_anual_pct/100 INTO v_tasa_t2
    FROM ref.tasas_impuesto
    WHERE destino_tipo = 'habitacional_tramo2'
      AND p_fecha_calculo BETWEEN vigente_desde AND COALESCE(vigente_hasta, '2099-12-31')
    ORDER BY vigente_desde DESC LIMIT 1;

    v_contrib_neta := (LEAST(v_avaluo_afecto, v_mct) * v_tasa_t1)
                    + (GREATEST(0, v_avaluo_afecto - v_mct) * v_tasa_t2);

    -- Sobretasa fiscal 0.025% solo sobre tramo 2
    v_sobretasa_fiscal := GREATEST(0, v_avaluo_afecto - v_mct) * 0.000250;

  ELSIF p_destino_tipo = 'agricola' THEN
    SELECT tasa_anual_pct/100 INTO v_tasa_fija
    FROM ref.tasas_impuesto
    WHERE destino_tipo = 'agricola'
      AND p_fecha_calculo BETWEEN vigente_desde AND COALESCE(vigente_hasta, '2099-12-31')
    ORDER BY vigente_desde DESC LIMIT 1;
    v_contrib_neta     := v_avaluo_afecto * v_tasa_fija;
    v_sobretasa_fiscal := 0;

  ELSE -- otros_no_agricola (TASA CORREGIDA a 1.042%)
    SELECT tasa_anual_pct/100 INTO v_tasa_fija
    FROM ref.tasas_impuesto
    WHERE destino_tipo = 'otros_no_agricola'
      AND p_fecha_calculo BETWEEN vigente_desde AND COALESCE(vigente_hasta, '2099-12-31')
    ORDER BY vigente_desde DESC LIMIT 1;
    v_contrib_neta     := v_avaluo_afecto * v_tasa_fija;
    -- Sobretasa fiscal 0.025% sobre avalúo afecto total
    v_sobretasa_fiscal := v_avaluo_afecto * 0.000250;
  END IF;

  -- 4. Sobretasa eriazo
  v_sobretasa_eriazo := CASE WHEN p_es_eriazo THEN v_contrib_neta ELSE 0 END;

  -- 5. Descuentos (BAM vs DFL2 no acumulables)
  v_desc_bam  := CASE WHEN p_tiene_bam  THEN v_contrib_neta * (p_descuento_bam_pct / 100) ELSE 0 END;
  v_desc_dfl2 := CASE WHEN p_tiene_dfl2 AND p_dfl2_vigente THEN v_contrib_neta * 0.50 ELSE 0 END;

  IF v_desc_bam >= v_desc_dfl2 THEN
    v_desc_dfl2 := 0;
  ELSE
    v_desc_bam := 0;
  END IF;

  -- 6. Total
  v_contrib_anual := v_contrib_neta + v_sobretasa_fiscal + v_sobretasa_eriazo - v_desc_bam - v_desc_dfl2;
  v_contrib_anual := GREATEST(0, v_contrib_anual);

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
      'fecha_calculo', p_fecha_calculo,
      'es_eriazo', p_es_eriazo,
      'tiene_bam', p_tiene_bam,
      'tiene_dfl2', p_tiene_dfl2,
      'exencion_aplicada', v_monto_exento > 0,
      'mct_usado', v_mct,
      'tasa_t1', v_tasa_t1,
      'tasa_t2', v_tasa_t2,
      'tasa_fija', v_tasa_fija
    );
END;
$$;

COMMENT ON FUNCTION ref.f_calcular_contribucion IS
  'Motor de cálculo contribuciones v2.0 — CORREGIDO. '
  'Cambios vs v1: tasa otros=1.042%, parámetros por fecha, soporte semestral. '
  'Uso: SELECT * FROM ref.f_calcular_contribucion(200000000, ''habitacional'', fecha_calculo:=''2025-07-01''); '
  'NOTA: Este cálculo NO incluye alza gradual. Para eso, aplicar ref.f_aplicar_alza_gradual() al resultado.';


-- ┌─────────────────────────────────────────────────────────┐
-- │  8. ACTUALIZAR VERSIÓN MOTOR                            │
-- └─────────────────────────────────────────────────────────┘

UPDATE ref.parametros_motor
SET valor = '2.0', descripcion = 'Versión del motor de cálculo SNRI — v2.0 corregida'
WHERE clave = 'version_motor';


-- ============================================================
-- VERIFICACIÓN POST-MIGRACIÓN
-- ============================================================
/*
-- Verificar tasa corregida
SELECT destino_tipo, tasa_anual_pct FROM ref.v_tasas_vigentes;
-- otros_no_agricola debe ser 1.0420

-- Verificar montos exentos 1S2026
SELECT * FROM ref.v_exenciones_vigentes;

-- Test cálculo comercial Panguipulli (debe dar ~$1,020,080)
SELECT * FROM ref.f_calcular_contribucion(191205208, 'otros_no_agricola');

-- Test Art. 7°bis
SELECT * FROM ref.sobretasa_art7bis;

-- Test alza gradual
SELECT * FROM ref.f_aplicar_alza_gradual(500000, 300000, '2025', 'no_agricola', '2025-07-01');
-- Esperado: MIN(500000, 300000 * 1.35) = MIN(500000, 405000) = 405000
*/

-- ============================================================
-- FIN MIGRATION 006
-- ============================================================
