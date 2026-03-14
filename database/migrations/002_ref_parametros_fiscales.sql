-- ============================================================
-- SNRI KNOWLEDGE REPOSITORY — PART 2
-- Tasas, Exenciones, Depreciación, Beneficios, Errores
-- ============================================================

-- ============================================================
-- 10. TASAS DE IMPUESTO TERRITORIAL — Por tipo y período
--     Fuente: Ley 17.235 + Resoluciones SII
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.tasas_impuesto (
  id               serial PRIMARY KEY,
  vigente_desde    date NOT NULL,
  vigente_hasta    date,                       -- NULL = vigente actualmente
  destino_tipo     text NOT NULL,              -- 'habitacional_tramo1' | 'habitacional_tramo2' | 'otros_no_agricola' | 'agricola' | 'eriazo'
  tasa_anual_pct   numeric(6,4) NOT NULL,      -- Porcentaje anual (ej: 0.8930 = 0.893%)
  descripcion      text,
  normativa_ref    text REFERENCES ref.normativa(codigo)
);

-- TASAS VIGENTES AL 01/01/2025
-- Fuente: Reavalúo 2025, Ley 17.235 Art. 7°
INSERT INTO ref.tasas_impuesto (vigente_desde, vigente_hasta, destino_tipo, tasa_anual_pct, descripcion, normativa_ref) VALUES
-- Habitacional — sistema progresivo en 2 tramos
('2025-01-01', NULL, 'habitacional_tramo1',   0.8930, 
 'Tasa habitacional Tramo 1: aplica sobre avalúo afecto hasta Monto Cambio Tasa ($207,288,476 al 1/1/2025)', 
 'REAVALIUO_2025'),
('2025-01-01', NULL, 'habitacional_tramo2',   1.0420, 
 'Tasa habitacional Tramo 2: aplica sobre avalúo afecto que excede Monto Cambio Tasa', 
 'REAVALIUO_2025'),
-- No agrícola otros destinos — tasa fija
('2025-01-01', NULL, 'otros_no_agricola',     1.0880, 
 'Tasa fija para comercio, industria, bodega, oficina, hotel y otros no agrícolas',
 'REAVALIUO_2025'),
-- Agrícola — tasa fija
('2025-01-01', NULL, 'agricola',              1.0000, 
 'Tasa fija para bienes raíces agrícolas (Serie 1)',
 'REAVALIUO_2025'),
-- Sitio eriazo — sobretasa punitiva del 100% ADICIONAL a la tasa base
('2025-01-01', NULL, 'sobretasa_eriazo',    100.0000, 
 'Sobretasa sancionatoria 100% sobre contribución neta. Aplica a sitios no edificados, propiedades abandonadas y pozos lastreros en áreas urbanas',
 'LEY_17235'),

-- TASAS HISTÓRICAS — Reavalúo 2022 (para auditorías retrospectivas)
('2022-01-01', '2024-12-31', 'habitacional_tramo1', 0.9310, 
 'Tasa habitacional Tramo 1 — Reavalúo 2022', 'REAVALIUO_2022'),
('2022-01-01', '2024-12-31', 'habitacional_tramo2', 1.0870, 
 'Tasa habitacional Tramo 2 — Reavalúo 2022', 'REAVALIUO_2022'),
('2022-01-01', '2024-12-31', 'otros_no_agricola',   1.1360, 
 'Tasa no agrícola otros — Reavalúo 2022', 'REAVALIUO_2022'),

-- TASAS HISTÓRICAS — Reavalúo 2018
('2018-01-01', '2021-12-31', 'otros_no_agricola',   1.0880, 
 'Tasa fija no agrícola otros — Reavalúo 2018', 'REAVALIUO_2018');

COMMENT ON TABLE ref.tasas_impuesto IS
  'Tasas anuales del impuesto territorial. '
  'Las tasas se aplican sobre el AVALÚO AFECTO (no sobre el avalúo total). '
  'Sistema habitacional es PROGRESIVO: tramo1 hasta MCT, tramo2 sobre MCT.';


-- ============================================================
-- 11. SOBRETASA ART. 7 BIS — Beneficio Fiscal 0.025%
--     Fuente: Ley 17.235 Art. 7 bis
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.sobretasas (
  id               serial PRIMARY KEY,
  codigo           text UNIQUE NOT NULL,
  nombre           text NOT NULL,
  tasa_pct         numeric(8,4) NOT NULL,      -- Porcentaje (ej: 0.0250)
  aplica_a         text NOT NULL,              -- descripción de a qué aplica
  base_calculo     text,                        -- sobre qué monto se calcula
  es_punitiva      boolean DEFAULT false,
  descripcion_legal text,
  normativa_ref    text REFERENCES ref.normativa(codigo)
);

INSERT INTO ref.sobretasas VALUES
(DEFAULT, 'sobretasa_beneficio_fiscal',
 'Sobretasa de Beneficio Fiscal (Art. 7 bis)',
 0.0250,
 'Habitacional: solo sobre tramo 2 (avalúo afecto > MCT). No habitacional: sobre avalúo afecto total.',
 'Tramo 2 avalúo afecto (habitacional) o avalúo afecto total (no habitacional)',
 false,
 'Genera tasa efectiva tramo 2 habitacional: 1.042% + 0.025% = 1.067%',
 'LEY_17235'),

(DEFAULT, 'sobretasa_sitio_eriazo',
 'Sobretasa Sancionatoria Sitio Eriazo / Propiedad Abandonada (Art. 8°)',
 100.0000,
 'Sitios no edificados, propiedades abandonadas o pozos lastreros en zonas urbanas',
 '100% de la contribución neta calculada (duplica el impuesto)',
 true,
 'Instrumento de política pública. Objetivo: forzar el desarrollo o venta de suelo urbano ocioso.',
 'LEY_17235');


-- ============================================================
-- 12. MONTOS EXENTOS — Actualizados semestralmente por IPC
--     Fuente: SII — reajuste semestral (1 enero y 1 julio)
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.montos_exencion (
  id               serial PRIMARY KEY,
  vigente_desde    date NOT NULL,
  vigente_hasta    date,
  destino_tipo     text NOT NULL,              -- 'habitacional' | 'agricola' | 'otros_no_agricola'
  monto_clp        bigint NOT NULL,            -- Monto en pesos chilenos
  monto_uf_ref     numeric(10,2),              -- Equivalencia en UF (referencial)
  factor_ipc_aplicado numeric(8,6),            -- Factor IPC que generó este reajuste
  descripcion      text,
  fuente           text
);

-- Datos al 01/01/2025
INSERT INTO ref.montos_exencion (vigente_desde, vigente_hasta, destino_tipo, monto_clp, descripcion, fuente) VALUES
('2025-01-01', NULL, 'habitacional',   58040782,
 'Exención general habitacional. Propiedades con avalúo ≤ este monto NO pagan contribuciones.',
 'SII Reavalúo 2025 — Reajuste IPC'),
('2025-01-01', NULL, 'agricola',       47192449,
 'Exención general agrícola. Predios agrícolas con avalúo ≤ este monto NO pagan contribuciones.',
 'SII Reavalúo 2025 — Reajuste IPC'),
('2025-01-01', NULL, 'otros_no_agricola', 0,
 'Sin exención para comercio, industria, bodega, oficina. Avalúo Afecto = Avalúo Total.',
 'Ley 17.235'),
-- Histórico
('2024-07-01', '2024-12-31', 'habitacional', 55891600,
 'Exención habitacional 2do semestre 2024 (referencial)',
 'SII'),
('2024-01-01', '2024-06-30', 'habitacional', 54050000,
 'Exención habitacional 1er semestre 2024 (referencial)',
 'SII');

COMMENT ON TABLE ref.montos_exencion IS
  'Se reajustan el 1° de enero y 1° de julio de cada año por variación IPC semestre anterior. '
  'Fórmula: Monto_T = Monto_T-1 × (1 + IPC_semestre). '
  'Para valores actualizados consultar: https://www.sii.cl/ayudas/ayudas_por_servicios/2242-reajustes_exenciones-2468.html';


-- ============================================================
-- 13. TRAMOS TASA HABITACIONAL (MCT)
--     Monto Cambio de Tasa — actualizado semestralmente
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.tramos_tasa_habitacional (
  id               serial PRIMARY KEY,
  vigente_desde    date NOT NULL,
  vigente_hasta    date,
  monto_cambio_tasa_clp bigint NOT NULL,       -- MCT en pesos
  monto_cambio_tasa_uf  numeric(10,2),         -- Equivalencia UF referencial
  descripcion      text
);

INSERT INTO ref.tramos_tasa_habitacional (vigente_desde, vigente_hasta, monto_cambio_tasa_clp, descripcion) VALUES
('2025-01-01', NULL,         207288476,
 'MCT 2025. Avalúo Afecto ≤ MCT → Tasa 0.893%. Avalúo Afecto > MCT → Tramo1 a 0.893%, exceso a 1.042%.'),
('2024-07-01', '2024-12-31', 199500000,
 'MCT 2do semestre 2024 (referencial)'),
('2024-01-01', '2024-06-30', 193000000,
 'MCT 1er semestre 2024 (referencial)');


-- ============================================================
-- 14. TABLA DE DEPRECIACIÓN
--     Factor multiplicador sobre avalúo construcción por antigüedad
--     Fuente: Tabla N°9 SII (RE 144/2019 y actualizaciones)
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.depreciacion_construccion (
  id               serial PRIMARY KEY,
  antiguedad_min   integer NOT NULL,           -- Años de antigüedad (desde)
  antiguedad_max   integer,                    -- NULL = sin límite superior
  factor_dp        numeric(5,3) NOT NULL,      -- Factor depreciación (1.000 = sin depreciación)
  pct_depreciacion numeric(5,2) NOT NULL,      -- Porcentaje de pérdida de valor (1-factor)*100
  descripcion      text,
  aplica_clase     text DEFAULT 'todas',       -- 'todas' o clase específica
  normativa_ref    text REFERENCES ref.normativa(codigo)
);

-- Tabla de depreciación estándar SII (aproximada — validar con RE vigente)
-- Factor 1.00 = sin depreciación (nuevo). Factor 0.10 = 90% depreciado.
INSERT INTO ref.depreciacion_construccion (antiguedad_min, antiguedad_max, factor_dp, pct_depreciacion, descripcion, normativa_ref) VALUES
(0,   5,   1.000,  0.00, 'Construcción nueva o hasta 5 años — sin depreciación',         'RE_144_2019'),
(6,   10,  0.950,  5.00, 'Entre 6 y 10 años — depreciación mínima',                      'RE_144_2019'),
(11,  15,  0.880, 12.00, 'Entre 11 y 15 años',                                           'RE_144_2019'),
(16,  20,  0.810, 19.00, 'Entre 16 y 20 años',                                           'RE_144_2019'),
(21,  25,  0.740, 26.00, 'Entre 21 y 25 años',                                           'RE_144_2019'),
(26,  30,  0.670, 33.00, 'Entre 26 y 30 años',                                           'RE_144_2019'),
(31,  35,  0.600, 40.00, 'Entre 31 y 35 años',                                           'RE_144_2019'),
(36,  40,  0.540, 46.00, 'Entre 36 y 40 años',                                           'RE_144_2019'),
(41,  50,  0.450, 55.00, 'Entre 41 y 50 años — depreciación significativa',               'RE_144_2019'),
(51,  60,  0.360, 64.00, 'Entre 51 y 60 años',                                           'RE_144_2019'),
(61,  70,  0.280, 72.00, 'Entre 61 y 70 años',                                           'RE_144_2019'),
(71,  80,  0.220, 78.00, 'Entre 71 y 80 años',                                           'RE_144_2019'),
(81,  99,  0.170, 83.00, 'Entre 81 y 99 años — alto grado de depreciación',              'RE_144_2019'),
(100, NULL, 0.100, 90.00, '100 años o más — depreciación máxima (piso 10%)',              'RE_144_2019');

COMMENT ON TABLE ref.depreciacion_construccion IS
  'Factor DP de la fórmula: AC = VUC × SC × CE × DP × FC × CC. '
  'Valor residual mínimo = 10% (factor 0.100) independiente de antigüedad. '
  'IMPORTANTE: Validar con Tabla N°9 de la RE SII vigente — estos valores son aproximados. '
  'La antigüedad se calcula desde el AÑO DE CONSTRUCCIÓN en catastro SII.';


-- ============================================================
-- 15. BENEFICIO ADULTO MAYOR (BAM)
--     Fuente: Ley 17.235 + SII
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.bam_parametros (
  id               serial PRIMARY KEY,
  vigente_desde    date NOT NULL,
  vigente_hasta    date,
  -- Requisitos
  edad_minima_mujer     integer NOT NULL DEFAULT 60,
  edad_minima_hombre    integer NOT NULL DEFAULT 65,
  tope_avaluo_individual_clp bigint NOT NULL,    -- Avalúo máximo propiedad que recibe beneficio
  tope_patrimonio_total_clp  bigint NOT NULL,    -- Suma de todos los bienes raíces del contribuyente
  -- Tramos de descuento por ingreso (UTA)
  uta_tramo1_max    numeric(5,1) NOT NULL,       -- Hasta este ingreso → descuento 100%
  descuento_tramo1_pct numeric(5,1) NOT NULL,    -- Porcentaje descuento tramo 1
  uta_tramo2_max    numeric(5,1) NOT NULL,       -- Entre tramo1 y tramo2 → descuento 50%
  descuento_tramo2_pct numeric(5,1) NOT NULL,
  aplica_cuota_aseo    boolean DEFAULT false,    -- El BAM NO aplica a la cuota de aseo municipal
  max_viviendas        integer DEFAULT 1,
  notas            text,
  fuente           text
);

INSERT INTO ref.bam_parametros VALUES
(DEFAULT, '2025-07-01', NULL,
 60, 65,                                        -- edad mínima mujer/hombre
 224577396,                                     -- tope individual jul 2025
 300021365,                                     -- tope patrimonial jul 2025
 13.5, 100.0,                                   -- hasta 13.5 UTA → 100% descuento
 30.0, 50.0,                                    -- entre 13.5-30 UTA → 50% descuento
 false, 1,
 'Beneficio Adulto Mayor (BAM). No aplica a cuota de aseo. Aplica sobre contribución neta. '
 'La UTA debe actualizarse con el SII cada período.',
 'SII — https://www.sii.cl/destacados/avaluaciones/bam/');

COMMENT ON TABLE ref.bam_parametros IS
  'Parámetros del BAM vigentes. '
  'El tope de avalúo se reajusta semestralmente por IPC. '
  'UTA 2025: ~$7.9M aprox. Verificar valor UTA vigente en SII.';


-- ============================================================
-- 16. BENEFICIO DFL-2 (Decreto con Fuerza de Ley N°2, 1959)
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.dfl2_parametros (
  id               serial PRIMARY KEY,
  vigente_desde    date NOT NULL DEFAULT '1959-07-31',
  m2_hasta         integer NOT NULL,            -- Hasta estos m² construidos aplica el tramo
  duracion_años    integer NOT NULL,            -- Años de beneficio desde fecha construcción
  descuento_pct    numeric(5,1) NOT NULL,       -- Porcentaje de descuento sobre contribución neta
  max_viviendas    integer NOT NULL DEFAULT 2,  -- Máximo de viviendas por RUT
  descripcion      text,
  notas            text
);

INSERT INTO ref.dfl2_parametros (m2_hasta, duracion_años, descuento_pct, max_viviendas, descripcion, notas) VALUES
(70,  20, 50.0, 2,
 'DFL-2: Viviendas hasta 70 m²',
 '20 años de 50% descuento desde fecha de construcción. Máx. 2 viviendas por RUT.'),
(100, 15, 50.0, 2,
 'DFL-2: Viviendas entre 70 y 100 m²',
 '15 años de 50% descuento desde fecha de construcción.'),
(140, 10, 50.0, 2,
 'DFL-2: Viviendas entre 100 y 140 m²',
 '10 años de 50% descuento desde fecha de construcción. Límite máximo 140 m².'),
(9999, 0, 0.0, 2,
 'DFL-2: Viviendas sobre 140 m² — NO aplica beneficio',
 'El SII aplica el beneficio más favorable entre DFL-2 y exención habitacional general.');

COMMENT ON TABLE ref.dfl2_parametros IS
  'El SII aplica automáticamente el beneficio más favorable entre DFL-2 y exención habitacional. '
  'Ambos beneficios (DFL-2 y BAM) NO son acumulables (se aplica el mayor). '
  'Aplica a destino H exclusivamente. Superficie construida total del predio.';


-- ============================================================
-- 17. HISTORIAL REAVALÚO MASIVO
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.reavaluo_historico (
  id               serial PRIMARY KEY,
  año              integer NOT NULL,
  serie            text NOT NULL,              -- 'agricola' | 'no_agricola'
  fecha_inicio     date NOT NULL,
  descripcion      text,
  incremento_tipico_pct numeric(6,2),          -- % de incremento promedio nacional
  normativa_ref    text REFERENCES ref.normativa(codigo),
  mecanismo_alza_gradual jsonb,                -- Desglose del alza gradual por semestre
  notas            text
);

INSERT INTO ref.reavaluo_historico (año, serie, fecha_inicio, descripcion, incremento_tipico_pct, normativa_ref, mecanismo_alza_gradual, notas) VALUES
(2025, 'no_agricola', '2025-01-01',
 'Reavalúo masivo No Agrícola 2025. Actualización de VUTAH y VUC con estudio de precios de mercado.',
 NULL,
 'REAVALIUO_2025',
 '{"semestres": [{"orden":1, "alza_pct": 25}, {"orden":2, "alza_pct": 10}, {"orden":3, "alza_pct": 10}, {"orden":4, "alza_pct": 10}]}',
 'Reavalúo más reciente. Impugnable dentro del plazo legal.'),
(2024, 'agricola', '2024-01-01',
 'Reavalúo masivo Agrícola 2024. Actualización valores base suelo por clase y comuna.',
 NULL,
 'REAVALIUO_2024',
 NULL,
 NULL),
(2022, 'no_agricola', '2022-01-01',
 'Reavalúo masivo No Agrícola 2022.',
 15.0,
 'REAVALIUO_2022',
 NULL,
 'Base de muchas propiedades aún en período de alza gradual en 2023-2024.'),
(2018, 'no_agricola', '2018-01-01',
 'Reavalúo masivo No Agrícola 2018.',
 12.0,
 'REAVALIUO_2018',
 NULL,
 NULL),
(2014, 'no_agricola', '2014-01-01',
 'Reavalúo masivo No Agrícola 2014.',
 NULL,
 'REAVALIUO_2014',
 NULL,
 NULL);


-- ============================================================
-- 18. REAJUSTES IPC SEMESTRAL
--     Factor aplicado a todos los avalúos y montos exentos
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.reajuste_ipc_semestral (
  id               serial PRIMARY KEY,
  vigente_desde    date NOT NULL,              -- 1 enero o 1 julio
  factor_reajuste  numeric(8,6) NOT NULL,      -- Ej: 1.018000 = +1.8% IPC
  ipc_semestral_pct numeric(5,2) NOT NULL,     -- Variación IPC del semestre anterior en %
  fuente           text
);

INSERT INTO ref.reajuste_ipc_semestral (vigente_desde, factor_reajuste, ipc_semestral_pct, fuente) VALUES
('2025-01-01', 1.038000, 3.80, 'SII — IPC 2do semestre 2024 aprox.'),
('2024-07-01', 1.028000, 2.80, 'SII — IPC 1er semestre 2024 aprox.'),
('2024-01-01', 1.018000, 1.80, 'SII — ejemplo documentado en fuentes SII');

COMMENT ON TABLE ref.reajuste_ipc_semestral IS
  'Fórmula: Avalúo_T = Avalúo_T1 × factor_reajuste. '
  'Se aplica el 1° de enero (con IPC jul-dic) y 1° de julio (con IPC ene-jun). '
  'Fuente exacta: https://www.sii.cl/ayudas/ayudas_por_servicios/2242-reajustes_exenciones-2468.html';


-- ============================================================
-- 19. FACTORES HOMOLOGACIÓN — Para tasaciones comerciales
--     Usados en MCM (Método Comparativo de Mercado)
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.factores_homologacion (
  id               serial PRIMARY KEY,
  categoria        text NOT NULL,              -- 'terreno' | 'construccion' | 'ubicacion'
  subcategoria     text NOT NULL,
  factor_nombre    text NOT NULL,
  factor_min       numeric(5,3),
  factor_max       numeric(5,3),
  factor_tipico    numeric(5,3),
  descripcion      text,
  aplica_a         text,                        -- 'tasacion_comercial' | 'snri' | 'ambos'
  notas            text
);

INSERT INTO ref.factores_homologacion (categoria, subcategoria, factor_nombre, factor_min, factor_max, factor_tipico, descripcion, aplica_a, notas) VALUES
-- TERRENO
('terreno', 'superficie',    'Factor Superficie',         0.800, 1.200, 1.000,
 'Ajuste por diferencia de tamaño entre comparable y sujeto. Terrenos más grandes suelen tener menor UF/m².',
 'tasacion_comercial', 'Aplica escala inversa: terreno 2× → factor ~0.85'),

('terreno', 'forma',         'Factor Forma',              0.850, 1.100, 1.000,
 'Ajuste por forma del terreno. Terreno irregular o con frente estrecho tiene menor valor.',
 'ambos', 'Terreno rectangular óptimo = 1.00'),

('terreno', 'pendiente',     'Factor Pendiente Terreno',  0.700, 1.000, 0.900,
 'Descuento por terreno con pendiente pronunciada. Dificulta construcción y accesibilidad.',
 'ambos', 'Pendiente >15% puede implicar descuento 20-30%'),

('terreno', 'esquina',       'Factor Esquina / Doble Frente', 1.000, 1.200, 1.080,
 'Premio por terrenos en esquina o con doble frente (mejor visibilidad comercial, ventilación).',
 'tasacion_comercial', 'Mayor impacto en comercio. Menor en residencial.'),

('terreno', 'aup',           'Factor AUP (Área Urbanización Prioritaria)', 0.600, 0.900, 0.750,
 'Descuento por afectación vial o AUP que reduce superficie útil del terreno.',
 'snri', 'Verificar en PRC de la comuna. Puede reducir valor 10-40%'),

('terreno', 'servidumbre',   'Factor Servidumbre',        0.700, 0.980, 0.880,
 'Descuento por servidumbre activa (paso, vista, conducción eléctrica, etc.)',
 'ambos', 'Requiere título o CIP que documente la servidumbre'),

('terreno', 'ubicacion',     'Factor Ubicación / Acceso', 0.800, 1.200, 1.000,
 'Ajuste por calidad de acceso, conectividad urbana, metro, avenidas principales.',
 'tasacion_comercial', NULL),

-- CONSTRUCCIÓN
('construccion', 'estado',   'Factor Estado de Conservación', 0.600, 1.050, 0.900,
 'Ajuste por estado real de conservación vs. año catastral SII. Muy bueno puede superar la tabla.',
 'ambos', 'L1=Muy bueno ~1.00-1.05; L3=Regular ~0.80; L5=Malo ~0.60'),

('construccion', 'calidad',  'Factor Calidad Real vs SII', 0.800, 1.300, 1.000,
 'Corrección cuando la clase real difiere de la registrada en catastro SII.',
 'snri', 'Error frecuente: SII clasifica C3 siendo C1 real → factor corrección 1.20-1.40'),

('construccion', 'antiguedad','Factor Antigüedad Real',   0.700, 1.050, 1.000,
 'Corrección cuando el año de construcción real difiere del catastral.',
 'snri', 'Error frecuente: SII sobrevalora por año incorrecto → aplicar depreciación correcta'),

('construccion', 'subterraneo','Factor Subterráneo',      0.750, 0.850, 0.800,
 'Factor de ajuste para construcciones subterráneas (menor valor per m²).',
 'ambos', 'SII ya aplica CE=SB, pero validar'),

-- UBICACIÓN / ZONA
('ubicacion', 'zona_comercial', 'Factor Zona Comercial vs Residencial', 1.100, 1.500, 1.200,
 'Premio de ubicación en zona de comercio consolidado sobre zona residencial equivalente.',
 'tasacion_comercial', NULL),

('ubicacion', 'vista',       'Factor Vista (mar/cordillera/parque)', 1.050, 1.300, 1.120,
 'Premio por vista privilegiada certificable (mar, cordillera, parque).',
 'tasacion_comercial', 'Difícil de cuantificar sin estudio de mercado específico');


-- ============================================================
-- 20. CATÁLOGO DE ERRORES TÍPICOS SII
--     Errores detectables por el motor SNRI en auditorías
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.errores_tipicos (
  id               serial PRIMARY KEY,
  codigo_error     text UNIQUE NOT NULL,
  categoria        text NOT NULL,              -- 'terreno' | 'construccion' | 'clasificacion' | 'beneficio' | 'superficie'
  nombre           text NOT NULL,
  descripcion      text NOT NULL,
  impacto          text,                       -- 'sobre_avaluo' | 'sub_avaluo' | 'ambos'
  probabilidad_base numeric(4,2),              -- % base de probabilidad (según literatura)
  fuente_deteccion text,                       -- Qué documento/dato permite detectarlo
  campo_afectado   text,                       -- Campo en catastro SII afectado
  efecto_en_contribucion text,
  es_impugnable    boolean DEFAULT true,
  plazo_impugnacion_dias integer,
  documentos_requeridos text[],
  notas            text
);

INSERT INTO ref.errores_tipicos (codigo_error, categoria, nombre, descripcion, impacto, probabilidad_base, fuente_deteccion, campo_afectado, efecto_en_contribucion, documentos_requeridos, notas) VALUES
('ERR-C01', 'clasificacion',
 'Clase/Calidad Construcción Incorrecta',
 'El SII clasifica la construcción en una clase o calidad superior a la real, elevando el VUC y por tanto el avalúo de construcción.',
 'sobre_avaluo', 35.00,
 'Inspección visual + ficha técnica + CIP',
 'Clase material + Calidad (catastro)',
 'Sobrevalúa directamente. Cada grado de calidad puede significar 15-40% del VUC.',
 ARRAY['CIP DOM', 'Permiso de edificación', 'Fotos interiores recientes'],
 'Error más frecuente en viviendas de los 80s-90s con clase asignada por sobre la real.'),

('ERR-C02', 'superficie',
 'Superficie Construida Mayor a la Real',
 'El catastro SII registra más m² construidos que los reales (por construcciones demolidas, alteraciones, remodelaciones no actualizadas).',
 'sobre_avaluo', 20.00,
 'Planos de arquitectura + CIP + medición en sitio',
 'SC (superficie construcción)',
 'Proporcional: 10% más de m² = 10% más de avalúo construcción.',
 ARRAY['CIP DOM', 'Planos originales', 'Escritura con m² originales'],
 NULL),

('ERR-C03', 'superficie',
 'Superficie Construida Menor a la Real',
 'El SII no ha registrado ampliaciones o construcciones posteriores (sin permiso o no declaradas).',
 'sub_avaluo', 15.00,
 'Inspección visual + certificado DOM',
 'SC (superficie construcción)',
 'Subavalúa. El contribuyente paga menos pero está expuesto a fiscalización SII.',
 ARRAY['CIP DOM', 'Permiso ampliación si existe'],
 'Situación de riesgo fiscal para el contribuyente. SNRI debe advertir, no usar como "ahorro".'),

('ERR-T01', 'terreno',
 'Superficie de Terreno Incorrecta',
 'Discrepancia entre el m² de terreno registrado por SII y el real según escritura/plano de loteo.',
 'sobre_avaluo', 12.00,
 'Escritura de dominio + CBR + plano de loteo',
 'ST (superficie terreno)',
 'Proporcional al VUTAH de la zona. En áreas de alto valor, diferencias pequeñas = grandes montos.',
 ARRAY['Escritura dominio', 'Plano de subdivisión CBR', 'Certificado dominio vigente'],
 NULL),

('ERR-T02', 'terreno',
 'AUP/Afectación Vial No Aplicada',
 'El SII valora la superficie total sin descontar la superficie afectada por vía pública, AUP o ensanche.',
 'sobre_avaluo', 18.00,
 'PRC de la comuna + DOM + Plano regulador',
 'ST (superficie efectiva terreno)',
 'La afectación vial reduce el terreno útil. SII debería valorar solo superficie no afectada.',
 ARRAY['Certificado de afectación vial DOM', 'Plano regulador comunal'],
 'Crítico en predios con frente a avenidas o en zonas con PRC nuevo. Las Condes tiene muchos casos.'),

('ERR-T03', 'terreno',
 'Zona Homogénea (AH) Incorrecta',
 'El predio está asignado a un Área Homogénea con VUTAH más alto que la zona que corresponde por ubicación real.',
 'sobre_avaluo', 8.00,
 'Planos de precios SII + geolocalización del predio',
 'VUTAH (valor unitario área homogénea)',
 'El error más difícil de detectar. Requiere consultar planos de precios oficiales SII.',
 ARRAY['Certificado de avalúo SII', 'Planos precios SII de la comuna'],
 NULL),

('ERR-A01', 'clasificacion',
 'Año de Construcción Incorrecto',
 'El SII registra un año de construcción más reciente que el real, aplicando menor depreciación.',
 'sobre_avaluo', 22.00,
 'Permiso de edificación + recepción final DOM',
 'Año construcción (depreciación DP)',
 'Cada década de error puede significar 5-15% de sobreavalúo en construcciones. Crítico en casas antiguas.',
 ARRAY['Permiso edificación original', 'Recepción final DOM', 'Escritura original'],
 'Muy frecuente en casas de los 60s-80s que el SII catastró tardíamente.'),

('ERR-A02', 'clasificacion',
 'Condición Especial No Registrada (Mansarda/Altillo)',
 'Una construcción tipo mansarda o altillo está valorada como piso normal sin el factor CE de reducción.',
 'sobre_avaluo', 10.00,
 'Planos de arquitectura + inspección visual',
 'CE (condición especial)',
 'Mansarda debería tener factor ~0.70 sobre VUC. Sin CE = sobrevalúo ~30% en esa superficie.',
 ARRAY['Planos arquitectura originales', 'CIP DOM'],
 NULL),

('ERR-B01', 'beneficio',
 'DFL-2 No Aplicado / Vencido Erróneamente',
 'El SII no aplicó el beneficio DFL-2 o lo canceló por error, pese a que la vivienda cumple requisitos.',
 'sobre_avaluo', 8.00,
 'Certificado DFL-2 + escritura + fecha construcción',
 'Beneficio DFL-2',
 'Si aplica: 50% de descuento sobre contribución neta por el período correspondiente.',
 ARRAY['Certificado DFL-2 SII', 'Escritura con cláusula DFL-2'],
 NULL),

('ERR-B02', 'beneficio',
 'BAM No Aplicado por Error Administrativo',
 'Contribuyente adulto mayor elegible que no recibió el BAM por error o falta de información.',
 'sobre_avaluo', 12.00,
 'Solicitud BAM + documentación SII',
 'Beneficio BAM',
 '50% o 100% de descuento sobre contribución neta. Error administrativo corregible retroactivamente.',
 ARRAY['Cédula de identidad', 'Declaración de renta SII', 'Certificado de avalúo'],
 'No es un error de tasación sino de gestión. Impugnable ante SII directamente.'),

('ERR-S01', 'superficie',
 'Subterráneo Registrado sin Factor CE',
 'Construcción subterránea valorada al mismo VUC que construcción sobre suelo, sin aplicar factor CE=SB (0.80).',
 'sobre_avaluo', 7.00,
 'Planos de arquitectura + inspección',
 'CE (condición especial subterráneo)',
 'Subterráneo debería valer ~80% del VUC normal. Sin CE = 25% de sobrevalúo en esa superficie.',
 ARRAY['Planos arquitectura', 'CIP DOM'],
 NULL),

('ERR-M01', 'clasificacion',
 'Destino Incorrecto',
 'Propiedad registrada en destino más gravoso (ej: comercio sin exención) siendo en realidad habitacional.',
 'sobre_avaluo', 5.00,
 'Certificado de avalúo SII + inspección + RCF',
 'Destino principal (campo catastro)',
 'Destinos no habitacionales no tienen exención habitacional y pueden tener tasa diferente.',
 ARRAY['Certificado de avalúo SII', 'Permiso de edificación original'],
 'Crítico cuando el destino real es H (tiene exención ~$58M) pero SII registra otro destino.');

COMMENT ON TABLE ref.errores_tipicos IS
  'Catálogo de errores detectables por SNRI. '
  'probabilidad_base es % estimado de ocurrencia en la población de predios chilenos. '
  'El motor SNRI combina múltiples errores para calcular probabilidad_total_sobreavaluo.';


-- ============================================================
-- 21. FÓRMULAS DE CÁLCULO — Documentación del motor
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.formulas_calculo (
  id               serial PRIMARY KEY,
  codigo           text UNIQUE NOT NULL,
  nombre           text NOT NULL,
  fase             text NOT NULL,              -- 'fase1_tasacion' | 'fase2_computo' | 'ajuste' | 'actualizacion'
  serie            text,                       -- 'agricola' | 'no_agricola' | 'ambas'
  formula_latex    text NOT NULL,              -- Fórmula en notación matemática
  formula_sql      text,                       -- Implementación en SQL/pseudocódigo
  variables        jsonb NOT NULL,             -- Descripción de cada variable
  ejemplo_calculo  jsonb,                      -- Ejemplo numérico
  normativa_ref    text REFERENCES ref.normativa(codigo),
  notas            text
);

INSERT INTO ref.formulas_calculo (codigo, nombre, fase, serie, formula_latex, formula_sql, variables, normativa_ref, notas) VALUES

('F01_AVALUO_TOTAL_NO_AGRICOLA',
 'Avalúo Fiscal Total — No Agrícola',
 'fase1_tasacion', 'no_agricola',
 'AF = AT + AC',
 'avaluo_fiscal := avaluo_terreno + avaluo_construccion',
 '{"AF": "Avalúo Fiscal Total", "AT": "Avalúo Terreno", "AC": "Avalúo Construcción"}',
 'LEY_17235',
 'Para copropiedad se agrega tercer componente: + Avalúo Bienes Comunes'),

('F02_AVALUO_TERRENO',
 'Avalúo Terreno — No Agrícola',
 'fase1_tasacion', 'no_agricola',
 'AT = ST \times VUTAH \times CT',
 'avaluo_terreno := sup_terreno * vutah * (cs * ca)',
 '{"AT": "Avalúo Terreno ($)", "ST": "Superficie Terreno (m²)", "VUTAH": "Valor Unitario Área Homogénea ($/m²)", "CT": "Coeficiente Terreno = CS × CA", "CS": "Coeficiente por Superficie", "CA": "Coeficiente por Altura Edificación"}',
 'LEY_17235',
 'VUTAH está en planos de precios SII por comunas. Se reajusta semestralmente por IPC.'),

('F03_AVALUO_CONSTRUCCION',
 'Avalúo Construcción — No Agrícola',
 'fase1_tasacion', 'no_agricola',
 'AC = VUC \times SC \times CE \times DP \times FC \times CC',
 'avaluo_construccion := vuc * sup_construida * ce * factor_depreciacion * fc * cc',
 '{"AC": "Avalúo Construcción ($)", "VUC": "Valor Unitario Construcción ($/m²) según Clase+Calidad", "SC": "Superficie Construida (m²)", "CE": "Coeficiente Condición Especial", "DP": "Factor Depreciación por antigüedad", "FC": "Factor de Corrección", "CC": "Coeficiente de Corrección"}',
 'RE_144_2019',
 'VUC se obtiene de tablas paramétricas SII según combinación Clase×Calidad. FC y CC generalmente 1.0 salvo zonas especiales.'),

('F04_AVALUO_AFECTO',
 'Cálculo del Avalúo Afecto',
 'fase2_computo', 'ambas',
 'AA = MAX(0, AF - ME)',
 'avaluo_afecto := GREATEST(0, avaluo_fiscal - monto_exento)',
 '{"AA": "Avalúo Afecto (base imponible real)", "AF": "Avalúo Fiscal Total", "ME": "Monto Exento según destino y período"}',
 'LEY_17235',
 'Si AF ≤ ME → contribución = 0. Monto exento habitacional 2025: $58,040,782'),

('F05_CONTRIBUCION_HABITACIONAL',
 'Cálculo Contribución Habitacional (progresiva)',
 'fase2_computo', 'no_agricola',
 'CN = MIN(AA, MCT) \times t1 + MAX(0, AA - MCT) \times t2',
 'contribucion_neta := LEAST(avaluo_afecto, mct) * tasa1 + GREATEST(0, avaluo_afecto - mct) * tasa2',
 '{"CN": "Contribución Neta", "AA": "Avalúo Afecto", "MCT": "Monto Cambio Tasa ($207,288,476 al 1/1/2025)", "t1": "Tasa Tramo 1 (0.8930%)", "t2": "Tasa Tramo 2 (1.0420%)"}',
 'REAVALIUO_2025',
 'La sobretasa 0.025% se aplica adicional sobre el tramo 2: tasa efectiva = 1.042% + 0.025% = 1.067%'),

('F06_CONTRIBUCION_NO_AGRICOLA_OTROS',
 'Cálculo Contribución — Otros No Agrícola (tasa fija)',
 'fase2_computo', 'no_agricola',
 'CN = AA \times t',
 'contribucion_neta := avaluo_afecto * 0.01088',
 '{"CN": "Contribución Neta", "AA": "Avalúo Afecto (= Avalúo Total, sin exención)", "t": "Tasa fija 1.088%"}',
 'REAVALIUO_2025',
 'Sin exención. Avalúo afecto = avalúo total. Sobretasa 0.025% sobre avalúo afecto total.'),

('F07_CONTRIBUCION_ANUAL_CON_SOBRETASA',
 'Contribución Anual Total con Sobretasas',
 'fase2_computo', 'ambas',
 'CA = CN + ST_{fiscal} + ST_{eriazo}',
 'contribucion_anual := contribucion_neta + sobretasa_beneficio_fiscal + sobretasa_eriazo',
 '{"CA": "Contribución Anual Total", "CN": "Contribución Neta", "ST_fiscal": "Sobretasa 0.025% Art. 7bis", "ST_eriazo": "Sobretasa 100% (solo sitio eriazo/abandonado)"}',
 'LEY_17235',
 'Pagadero en 4 cuotas: abril, junio, septiembre, noviembre. No incluye cuota de aseo.'),

('F08_CONTRIBUCION_CUOTA',
 'Contribución Semestral (cuota)',
 'fase2_computo', 'ambas',
 'C_{sem} = CA / 4',
 'cuota := contribucion_anual / 4',
 '{"C_sem": "Cuota trimestral", "CA": "Contribución Anual Total"}',
 'LEY_17235',
 'El SII publica el rol semestral de contribuciones (no anual). La cuota semestral = CA/2.'),

('F09_REAJUSTE_IPC',
 'Reajuste Semestral IPC sobre Avalúo',
 'actualizacion', 'ambas',
 'AF_T = AF_{T-1} \times (1 + IPC_{T-1})',
 'avaluo_nuevo := avaluo_anterior * factor_reajuste',
 '{"AF_T": "Avalúo nuevo semestre T", "AF_T-1": "Avalúo semestre anterior", "IPC_T-1": "Variación IPC semestre calendario anterior (decimal)"}',
 'LEY_17235',
 'Mismo factor aplica a todos los montos exentos y MCT. Se ejecuta el 1° ene y 1° jul.'),

('F10_AVALUO_SUELO_AGRICOLA',
 'Avalúo Suelo Agrícola',
 'fase1_tasacion', 'agricola',
 'ATS = \left( \sum (VBS \times HAS) \right) \times \left( 1 - \frac{RCD}{100} \right)',
 'avaluo_suelo := (sum of vbs * hectareas per type) * (1 - rcd/100)',
 '{"ATS": "Avalúo Total Suelo", "VBS": "Valor Base Suelo ($/ha) por clase y comuna", "HAS": "Hectáreas de cada clase", "RCD": "Factor Rebaja Camino-Distancia (%)"}',
 'REAVALIUO_2024',
 'RCD modela fricción económica por distancia a centros y calidad vial.'),

('F11_BAM_DESCUENTO',
 'Cálculo Descuento BAM',
 'ajuste', 'no_agricola',
 'C_{final} = CN \times (1 - d_{BAM})',
 'contribucion_final := contribucion_neta * (1 - descuento_bam)',
 '{"C_final": "Contribución con BAM", "CN": "Contribución Neta", "d_BAM": "Descuento BAM: 1.0 (100%) o 0.5 (50%) según tramo ingreso"}',
 'LEY_17235',
 'BAM no aplica sobre cuota de aseo. Aplica sobre contribución neta (antes o después de sobretasa según interpretación).'),

('F12_DFL2_DESCUENTO',
 'Cálculo Descuento DFL-2',
 'ajuste', 'no_agricola',
 'C_{final} = CN \times 0.50',
 'contribucion_final := contribucion_neta * 0.50',
 '{"C_final": "Contribución con DFL-2", "CN": "Contribución Neta"}',
 'DFL2_1959',
 'Solo si DFL-2 vigente (dentro del plazo por m²). El SII aplica el beneficio más favorable entre DFL-2 y exención habitacional.');

COMMENT ON TABLE ref.formulas_calculo IS
  'Documentación completa de todas las fórmulas del motor SNRI. '
  'formula_sql es pseudocódigo ilustrativo — la implementación real está en los RPCs de Supabase.';


-- ============================================================
-- 22. VARIABLES GLOBALES DEL MOTOR SNRI
--     Parámetros actualizables sin modificar lógica
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.parametros_motor (
  clave            text PRIMARY KEY,
  valor            text NOT NULL,
  tipo             text NOT NULL,              -- 'numeric' | 'integer' | 'boolean' | 'text' | 'date'
  descripcion      text,
  vigente_desde    date,
  fuente           text,
  actualizar_cada  text                        -- 'semestral' | 'anual' | 'con_reavaluo' | 'manual'
);

INSERT INTO ref.parametros_motor VALUES
-- Tasas vigentes 2025
('tasa_habitacional_t1',       '0.008930', 'numeric', 'Tasa Tramo 1 habitacional anual (0.893%)', '2025-01-01', 'SII Reavalúo 2025', 'con_reavaluo'),
('tasa_habitacional_t2',       '0.010420', 'numeric', 'Tasa Tramo 2 habitacional anual (1.042%)', '2025-01-01', 'SII Reavalúo 2025', 'con_reavaluo'),
('tasa_otros_no_agricola',     '0.010880', 'numeric', 'Tasa fija otros no agrícola (1.088%)',     '2025-01-01', 'SII Reavalúo 2025', 'con_reavaluo'),
('tasa_agricola',              '0.010000', 'numeric', 'Tasa fija agrícola (1.000%)',              '2025-01-01', 'Ley 17.235',         'con_reavaluo'),
('sobretasa_beneficio_fiscal',  '0.000250', 'numeric', 'Sobretasa Art. 7bis (0.025%)',            '2025-01-01', 'Ley 17.235',         'manual'),
-- Montos exentos 2025
('monto_exento_habitacional',  '58040782', 'integer', 'Monto exento habitacional CLP 1/1/2025',  '2025-01-01', 'SII',                'semestral'),
('monto_exento_agricola',      '47192449', 'integer', 'Monto exento agrícola CLP 1/1/2025',      '2025-01-01', 'SII',                'semestral'),
('monto_cambio_tasa',          '207288476','integer', 'MCT habitacional CLP 1/1/2025',           '2025-01-01', 'SII Reavalúo 2025', 'semestral'),
-- BAM 2025
('bam_tope_avaluo_individual', '224577396','integer', 'Tope avalúo individual BAM jul 2025',      '2025-07-01', 'SII',                'semestral'),
('bam_tope_patrimonio_total',  '300021365','integer', 'Tope patrimonio total BAM jul 2025',        '2025-07-01', 'SII',                'semestral'),
('bam_uta_tramo1',             '13.5',     'numeric', 'UTA máximo tramo 100% descuento BAM',     '2025-01-01', 'Ley 17.235',         'manual'),
('bam_uta_tramo2',             '30.0',     'numeric', 'UTA máximo tramo 50% descuento BAM',      '2025-01-01', 'Ley 17.235',         'manual'),
-- DFL-2
('dfl2_m2_maximo',             '140',      'integer', 'Superficie máxima para DFL-2 (m²)',       '1959-07-31', 'DFL-2/1959',          'manual'),
('dfl2_max_viviendas_rut',     '2',        'integer', 'Máximo viviendas DFL-2 por RUT',          '1959-07-31', 'DFL-2/1959',          'manual'),
-- Motor SNRI
('version_motor',               '1.0',      'text',    'Versión del motor de cálculo SNRI',       '2026-03-01', 'SNRI internal',       'manual'),
('umbral_diferencia_alerta',   '0.05',     'numeric', 'Diferencia % mínima para generar alerta (5%)', '2026-03-01', 'SNRI internal',  'manual'),
('uf_valor_clp',              '38420',    'integer', 'Valor UF en CLP — actualizar diariamente (mindicador.cl)', '2026-03-14', 'mindicador.cl',       'diario'),
('descuento_potencial_expansion','0.60',   'numeric', 'Descuento sobre valor expansión potencial (60%)', '2026-03-01', 'SNRI internal','manual');

COMMENT ON TABLE ref.parametros_motor IS
  'Tabla maestra de parámetros del motor SNRI. '
  'Actualizar semestralmente los parámetros marcados como "semestral". '
  'Los valores "manual" requieren resolución o análisis explícito para cambiar.';
