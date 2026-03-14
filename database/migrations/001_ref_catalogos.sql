-- ============================================================
-- SNRI KNOWLEDGE REPOSITORY — BASE DE CONOCIMIENTO FISCAL
-- Chile · Ley N° 17.235 · SII · Motor de Avalúos y Contribuciones
-- ============================================================
-- Versión: 1.0 | Fecha: Marzo 2026
-- Fuentes: Ley 17.235, Resoluciones Exentas SII, Estructura
--          Detalle Catastral SII, Reavalúo 2024/2025
-- 
-- INSTRUCCIONES DE INSTALACIÓN EN SUPABASE:
-- 1. Ir a SQL Editor en tu proyecto Supabase
-- 2. Ejecutar Part1 (este archivo) primero
-- 3. Luego ejecutar Part2 (tablas de valores y errores)
-- 4. Luego ejecutar Part3 (fórmulas, vistas y funciones)
-- ============================================================

-- ┌─────────────────────────────────────────────────────────┐
-- │  SCHEMA REF — Tablas de sólo lectura / referencia       │
-- └─────────────────────────────────────────────────────────┘

CREATE SCHEMA IF NOT EXISTS ref;
COMMENT ON SCHEMA ref IS 
  'Tablas de referencia normativa para motor SNRI. '
  'Sólo lectura. Actualizar por resoluciones SII.';

-- ============================================================
-- 1. NORMATIVA LEGAL
--    Registro de las leyes y resoluciones que alimentan cada tabla
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.normativa (
  id               serial PRIMARY KEY,
  codigo           text UNIQUE NOT NULL,       -- Ej: 'LEY_17235'
  tipo             text NOT NULL,              -- 'ley' | 'resolucion_exenta' | 'decreto' | 'circular'
  numero           text NOT NULL,              -- '17.235' | 'RE 144/2019'
  nombre           text NOT NULL,
  materia          text,                       -- 'avaluo_terreno' | 'tasas' | 'exenciones' | 'dfl2' etc.
  fecha_publicacion date,
  fecha_vigencia   date,
  url_oficial      text,
  notas            text
);

INSERT INTO ref.normativa (codigo, tipo, numero, nombre, materia, fecha_publicacion, url_oficial) VALUES
('LEY_17235',     'ley',              '17.235',       'Ley sobre Impuesto Territorial (texto refundido)',    'general',          '1969-12-24', 'https://www.leychile.cl/leychile/Navegar?idNorma=28849'),
('DFL2_1959',     'decreto',          'DFL-2',        'D.F.L. Nº 2 de 1959: Plan habitacional viviendas económicas', 'exencion_dfl2', '1959-07-31', NULL),
('RE_144_2019',   'resolucion_exenta','RE 144/2019',  'Tablas clasificación construcciones no agrícolas 2019', 'clasificacion_construccion', '2019-01-01', 'https://www.sii.cl/normativa_legislacion/resoluciones/2019/reso144_anexo2.pdf'),
('RE_118_2015',   'resolucion_exenta','RE 118/2015',  'Tablas valores terrenos y construcciones reavalúo 2015', 'avaluo_construccion', '2015-01-01', 'https://www.sii.cl/documentos/resoluciones/2015/reso118.pdf'),
('RE_097_2009',   'resolucion_exenta','RE 097/2009',  'Tablas clasificación construcciones 2009',           'clasificacion_construccion', '2009-01-01', 'https://www.sii.cl/documentos/resoluciones/2009/reso97_anexo2.pdf'),
('REAVALIUO_2024','resolucion_exenta','Reavalúo 2024','Reavalúo masivo bienes raíces agrícolas 2024',        'reavaluo_agricola',  '2024-01-01', 'https://www.sii.cl/destacados/reavaluo_agricola/2024/'),
('REAVALIUO_2025','resolucion_exenta','Reavalúo 2025','Reavalúo masivo bienes raíces no agrícolas 2025',    'reavaluo_no_agricola','2025-01-01', 'https://www.sii.cl/destacados/reavaluo/2025/index.html'),
('REAVALIUO_2022','resolucion_exenta','Reavalúo 2022','Reavalúo masivo bienes raíces no agrícolas 2022',    'reavaluo_no_agricola','2022-01-01', 'https://www.sii.cl/destacados/reavaluo/2024/4449-4451.html'),
('REAVALIUO_2018','resolucion_exenta','Reavalúo 2018','Reavalúo masivo bienes raíces no agrícolas 2018',    'reavaluo_no_agricola','2018-01-01', NULL),
('REAVALIUO_2014','resolucion_exenta','Reavalúo 2014','Reavalúo masivo bienes raíces no agrícolas 2014',    'reavaluo_no_agricola','2014-01-01', NULL);


-- ============================================================
-- 2. SERIES DE PREDIOS
--    Dicotomía fundamental del sistema SII
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.series_predio (
  codigo           text PRIMARY KEY,           -- 'agricola' | 'no_agricola'
  nombre           text NOT NULL,
  descripcion      text,
  motor_tasacion   text,                       -- descripción del método de valoración
  normativa_id     text REFERENCES ref.normativa(codigo)
);

INSERT INTO ref.series_predio VALUES
('agricola',    'Serie 1 – Agrícola',
 'Predios con destino agrícola o forestal. Motor: capacidad de uso productivo del suelo.',
 'Valor Base Suelo × Hectáreas × Factor Rebaja Camino + Avalúo Construcciones',
 'LEY_17235'),
('no_agricola', 'Serie 2 – No Agrícola',
 'Predios habitacionales, comerciales, industriales, sitios eriazos y todos los demás destinos urbanos.',
 'Avalúo Terreno (Área Homogénea) + Avalúo Construcción (Costo Reposición con Depreciación)',
 'LEY_17235');


-- ============================================================
-- 3. TABLA DE DESTINOS — Códigos oficiales SII
--    Fuente: Estructura Detalle Catastral SII (BRORGA/BRTMPCATAS)
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.destinos (
  codigo           text PRIMARY KEY,           -- Código de 1 letra (oficial SII)
  nombre           text NOT NULL,
  descripcion      text,
  serie            text REFERENCES ref.series_predio(codigo),
  tiene_exencion_habitacional boolean DEFAULT false,
  tiene_sobretasa_eriazo      boolean DEFAULT false,
  tasa_contribucion_tipo      text,            -- 'habitacional' | 'otros_no_agricola' | 'agricola' | 'exento_total'
  notas            text
);

INSERT INTO ref.destinos (codigo, nombre, descripcion, serie, tiene_exencion_habitacional, tiene_sobretasa_eriazo, tasa_contribucion_tipo) VALUES
('H', 'Habitacional',             'Viviendas, casas, departamentos de uso residencial',                              'no_agricola', true,  false, 'habitacional'),
('O', 'Oficina',                  'Oficinas y usos administrativos privados',                                         'no_agricola', false, false, 'otros_no_agricola'),
('C', 'Comercio',                 'Locales comerciales, tiendas, centros comerciales',                                'no_agricola', false, false, 'otros_no_agricola'),
('I', 'Industria',                'Plantas industriales, fábricas, instalaciones industriales',                       'no_agricola', false, false, 'otros_no_agricola'),
('L', 'Bodega y Almacenaje',      'Bodegas, centros de distribución, almacenes',                                      'no_agricola', false, false, 'otros_no_agricola'),
('Z', 'Estacionamiento',          'Estacionamientos subterráneos o superficiales',                                    'no_agricola', false, false, 'otros_no_agricola'),
('G', 'Hotel / Motel',            'Establecimientos de hospedaje comercial',                                          'no_agricola', false, false, 'otros_no_agricola'),
('S', 'Salud',                    'Clínicas, hospitales, centros médicos privados',                                   'no_agricola', false, false, 'otros_no_agricola'),
('E', 'Educación y Cultura',      'Colegios, universidades, museos, teatros',                                         'no_agricola', false, false, 'exento_total'),
('D', 'Deporte y Recreación',     'Estadios, gimnasios, recintos deportivos',                                         'no_agricola', false, false, 'exento_total'),
('Q', 'Culto',                    'Templos, iglesias, edificios de culto religioso',                                  'no_agricola', false, false, 'exento_total'),
('T', 'Transporte y Telecom.',    'Terminales, aeropuertos, infraestructura de telecomunicaciones',                   'no_agricola', false, false, 'otros_no_agricola'),
('M', 'Minería',                  'Instalaciones mineras',                                                            'no_agricola', false, false, 'otros_no_agricola'),
('P', 'Administración Pública',   'Edificios fiscales, municipalidades, fuerzas armadas (exentos)',                   'no_agricola', false, false, 'exento_total'),
('V', 'Otros no considerados',    'Destinos no clasificados en otras categorías',                                     'no_agricola', false, false, 'otros_no_agricola'),
('W', 'Sitio Eriazo',             'Terrenos sin edificar en área urbana — sujetos a sobretasa 100%',                  'no_agricola', false, true,  'otros_no_agricola'),
('Y', 'Gallineros/Chancheras',    'Instalaciones pecuarias especiales (agrícola)',                                     'agricola',    false, false, 'agricola'),
('A', 'Agrícola',                 'Predios de uso agrícola (serie 1)',                                                 'agricola',    false, false, 'agricola'),
('B', 'Agroindustrial',           'Plantas de procesamiento agroindustrial',                                           'agricola',    false, false, 'agricola'),
('F', 'Forestal',                 'Predios de uso forestal (serie 1)',                                                  'agricola',    false, false, 'agricola');

-- Nota: Destino 'P' en serie agrícola = Casa Patronal
COMMENT ON TABLE ref.destinos IS 
  'Códigos oficiales SII. En serie agrícola, P = Casa Patronal. '
  'Fuente: Estructura Detalle Catastral SII.';


-- ============================================================
-- 4. MATERIALES DE CONSTRUCCIÓN — Códigos oficiales SII
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.materiales_construccion (
  codigo           text PRIMARY KEY,
  nombre           text NOT NULL,
  descripcion      text,
  aplica_serie     text                        -- 'agricola' | 'no_agricola' | 'ambas'
);

INSERT INTO ref.materiales_construccion VALUES
-- Serie No Agrícola
('A',  'Acero',                       'Estructura en tubos y perfiles de acero',                         'no_agricola'),
('B',  'Hormigón Armado',             'Estructura de hormigón armado (HA)',                              'no_agricola'),
('C',  'Albañilería',                 'Ladrillo de arcilla, piedra, bloque de cemento u hormigón celular','no_agricola'),
('E',  'Madera',                      'Estructura de madera aserrada',                                   'no_agricola'),
('F',  'Adobe',                       'Construcción en adobe o tierra cruda',                            'no_agricola'),
('G',  'Perfiles Metálicos',          'Perfiles metálicos livianos (zinc, galvanizado)',                  'no_agricola'),
('K',  'Prefabricado/Industrializado','Estructura con elementos prefabricados e industrializados',        'no_agricola'),
-- Especiales
('GA', 'Acero (Galpón)',              'Galpón de acero',                                                  'ambas'),
('GB', 'Hormigón Armado (Galpón)',    'Galpón de hormigón armado',                                        'ambas'),
('GC', 'Albañilería (Galpón)',        'Galpón de albañilería',                                            'ambas'),
('GE', 'Madera (Galpón)',             'Galpón de madera',                                                 'ambas'),
('GL', 'Madera Laminada (Galpón)',    'Galpón de madera laminada estructural',                            'ambas'),
('GF', 'Adobe (Galpón)',              'Galpón de adobe',                                                  'ambas'),
('OA', 'Acero (Otro)',                'Otra construcción de acero',                                       'ambas'),
('OB', 'HA (Otro)',                   'Otra construcción de hormigón armado',                             'ambas'),
('OE', 'Madera (Otro)',               'Otra construcción de madera',                                      'ambas'),
('SA', 'Silo de Acero',               'Silo metálico de almacenaje',                                      'agricola'),
('SB', 'Silo de Hormigón',            'Silo de hormigón armado',                                          'agricola'),
('EA', 'Estanque de Acero',           'Estanque metálico',                                                'ambas'),
('EB', 'Estanque de Hormigón',        'Estanque de hormigón armado',                                      'ambas'),
('M',  'Marquesina',                  'Cubierta ligera sin cerramientos',                                  'ambas'),
('P',  'Pavimento',                   'Pavimentos y pisos exteriores',                                    'ambas'),
('W',  'Piscina',                     'Piscina (obra de hormigón)',                                        'ambas'),
('TA', 'Techumbre Apoyada Acero',     'Techumbre apoyada en estructura de acero',                         'ambas'),
('TE', 'Techumbre Apoyada Madera',    'Techumbre apoyada en estructura de madera',                        'ambas'),
('TL', 'Techumbre Madera Laminada',   'Techumbre apoyada en madera laminada',                             'ambas');


-- ============================================================
-- 5. CALIDADES DE CONSTRUCCIÓN — Códigos oficiales SII
--    Del 1 (superior) al 5 (inferior)
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.calidades_construccion (
  codigo           integer PRIMARY KEY,        -- 1 a 5
  nombre           text NOT NULL,
  descripcion      text,
  terminaciones    text,                        -- descripción de terminaciones típicas
  orden_calidad    integer                      -- 1 = mejor, 5 = peor (coincide con código)
);

INSERT INTO ref.calidades_construccion VALUES
(1, 'Superior',        
   'Máxima calidad de terminaciones y diseño arquitectónico',
   'Materiales de lujo: mármol, piedra natural, carpintería fina, climatización central, domótica',
   1),
(2, 'Media Superior',  
   'Alta calidad, por sobre el estándar residencial promedio',
   'Pisos cerámicos o madera de calidad, ventanas termopanel, cocina y baños equipados',
   2),
(3, 'Media',           
   'Estándar residencial promedio del mercado chileno',
   'Porcelanato o cerámica estándar, ventanas de aluminio, terminaciones completas estándar',
   3),
(4, 'Media Inferior',  
   'Por debajo del estándar residencial, terminaciones básicas',
   'Pisos de cemento o vinílico, sin revestimientos exteriores especiales, baños básicos',
   4),
(5, 'Inferior',        
   'Construcción mínima, sin terminaciones o muy precaria',
   'Sin terminaciones interiores o muy básicas, estructura a la vista, uso mínimo',
   5);


-- ============================================================
-- 6. CLASES DE CONSTRUCCIÓN
--    Combinación Material × Calidad determina el VUC
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.clases_construccion (
  id               serial PRIMARY KEY,
  material_codigo  text REFERENCES ref.materiales_construccion(codigo),
  calidad_codigo   integer REFERENCES ref.calidades_construccion(codigo),
  clase_sii        text NOT NULL,              -- Notación SII: 'A1', 'B2', 'C3', etc.
  valor_uf_m2_ref  numeric(10,2),              -- Valor UF/m² referencial (actualizar con reavalúo vigente)
  valor_clp_m2_ref bigint,                     -- Valor CLP/m² referencial
  vigencia_reavaluo text,                      -- '2025' | '2022' | etc.
  notas            text
);

-- Valores de referencia basados en Reavalúo 2022/2025
-- IMPORTANTE: Estos valores son aproximaciones. Los valores exactos
-- están en las Resoluciones Exentas del SII (RE 144/2019 y actualizaciones).
-- Actualizar según Resolución Exenta vigente al momento del cálculo.

INSERT INTO ref.clases_construccion (material_codigo, calidad_codigo, clase_sii, valor_uf_m2_ref, vigencia_reavaluo, notas) VALUES
-- Hormigón Armado (B) — el más común en edificios
('B', 1, 'B1', 42.50, '2022', 'Edificio de lujo, hormigón armado, calidad superior'),
('B', 2, 'B2', 32.00, '2022', 'Edificio buena calidad, hormigón armado'),
('B', 3, 'B3', 24.00, '2022', 'Edificio estándar, hormigón armado'),
('B', 4, 'B4', 18.00, '2022', 'Edificio básico, hormigón armado'),
('B', 5, 'B5', 13.00, '2022', 'Bodega/industrial, hormigón armado mínimo'),
-- Albañilería (C) — el más común en viviendas
('C', 1, 'C1', 38.00, '2022', 'Vivienda de lujo, albañilería, calidad superior'),
('C', 2, 'C2', 28.00, '2022', 'Vivienda buena calidad, albañilería'),
('C', 3, 'C3', 20.00, '2022', 'Vivienda estándar, albañilería (DFL2 típico)'),
('C', 4, 'C4', 14.00, '2022', 'Vivienda básica, albañilería'),
('C', 5, 'C5', 10.00, '2022', 'Vivienda mínima, albañilería simple'),
-- Madera (E)
('E', 1, 'E1', 25.00, '2022', 'Vivienda madera, calidad superior'),
('E', 2, 'E2', 18.00, '2022', 'Vivienda madera buena calidad'),
('E', 3, 'E3', 13.00, '2022', 'Vivienda madera estándar'),
('E', 4, 'E4',  9.00, '2022', 'Vivienda madera básica'),
('E', 5, 'E5',  6.00, '2022', 'Vivienda madera mínima'),
-- Acero (A) — comercial e industrial
('A', 1, 'A1', 35.00, '2022', 'Estructura acero calidad superior'),
('A', 2, 'A2', 26.00, '2022', 'Estructura acero buena calidad'),
('A', 3, 'A3', 19.00, '2022', 'Estructura acero estándar'),
('A', 4, 'A4', 13.00, '2022', 'Estructura acero básica'),
('A', 5, 'A5',  9.00, '2022', 'Galpón acero mínimo'),
-- Adobe (F)
('F', 3, 'F3',  8.00, '2022', 'Construcción adobe estándar'),
('F', 4, 'F4',  5.50, '2022', 'Construcción adobe básica'),
('F', 5, 'F5',  4.00, '2022', 'Construcción adobe muy precaria');

COMMENT ON TABLE ref.clases_construccion IS
  'Valores UF/m² son aproximaciones. '
  'Los valores exactos están en RE SII vigente. '
  'Actualizar con cada Reavalúo masivo (cada ~4 años).';


-- ============================================================
-- 7. CONDICIONES ESPECIALES
--    Factores que ajustan el VUC de una línea de construcción
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.condiciones_especiales (
  codigo           text PRIMARY KEY,           -- Código SII (2 letras)
  nombre           text NOT NULL,
  descripcion      text,
  factor_tipico    numeric(5,3),               -- Factor multiplicador sobre VUC (aproximado)
  aplica_a         text,                        -- 'construccion' | 'terreno'
  notas            text
);

INSERT INTO ref.condiciones_especiales VALUES
('AL', 'Altillo',              
  'Espacio habitable sobre nivel de piso principal, con altura libre reducida',                     
  0.600, 'construccion', 'Factor ~60% del VUC normal por restricciones de altura'),
('CA', 'Construcción Abierta', 
  'Estructura sin cerramientos completos (galpones abiertos, cobertizos)',                          
  0.450, 'construccion', 'Factor reducido por ausencia de cerramientos'),
('CI', 'Construcción Interior', 
  'Construcción ubicada al interior de otra, sin fachada propia',                                  
  0.700, 'construccion', 'Factor menor por acceso dependiente'),
('MS', 'Mansarda',             
  'Espacio habitable bajo cubierta inclinada (techo a dos aguas con habitaciones)',                 
  0.700, 'construccion', 'Factor ~70% del VUC normal. Verificar planos originales'),
('PZ', 'Posi Zócalo',          
  'Piso elevado sobre zócalo de fundación, sin uso habitable bajo él',                             
  0.900, 'construccion', 'Factor leve corrección por tipología'),
('SB', 'Subterráneo',          
  'Construcción bajo nivel de suelo natural o vereda',                                              
  0.800, 'construccion', 'Factor ~80% por acceso restringido y costo diferencial'),
('TM', 'Catástrofe 20/02/2010',
  'Propiedad afectada por el terremoto del 27/F 2010 (Tsunami/Sismo)',                             
  NULL,  'construccion', 'Marca histórica del SII — verificar estado actual');


-- ============================================================
-- 8. TIPOS DE SUELO AGRÍCOLA — Códigos SII
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.tipos_suelo_agricola (
  codigo           text PRIMARY KEY,
  nombre           text NOT NULL,
  descripcion      text,
  capacidad_uso    integer,                    -- Clase capacidad de uso (1-8 estándar USDA/SAG)
  es_riego         boolean DEFAULT false,
  notas            text
);

INSERT INTO ref.tipos_suelo_agricola VALUES
('1R', 'Primera de Riego',        'Mejor suelo regado, plano, sin limitaciones',             1, true,  'Máximo valor productivo'),
('2R', 'Segunda de Riego',        'Buen suelo regado, leves pendientes o limitaciones',      2, true,  NULL),
('3R', 'Tercera de Riego',        'Suelo regado con limitaciones moderadas',                  3, true,  NULL),
('1',  'Clase 1 Secano Arable',   'Mejor secano arable, sin limitaciones significativas',     1, false, NULL),
('2',  'Clase 2 Secano Arable',   'Secano arable con limitaciones ligeras',                   2, false, NULL),
('3',  'Clase 3 Secano Arable',   'Secano arable con limitaciones moderadas',                  3, false, NULL),
('4',  'Clase 4 Secano Arable',   'Secano arable con limitaciones severas, uso restringido',   4, false, NULL),
('5',  'Clase 5 Secano No Arable','No arable, sin limitaciones de pendiente (pantanoso)',       5, false, 'Sin uso agrícola, solo pastoreo/forestal'),
('6',  'Clase 6 Secano No Arable','No arable con pendiente, limitaciones severas',              6, false, NULL),
('7',  'Clase 7 Secano No Arable','No arable, limitaciones muy severas, solo forestal',         7, false, NULL),
('8',  'Clase 8 Secano No Arable','Terreno no apto para uso productivo (quebradas, pedregoso)', 8, false, 'Valor mínimo o cero');


-- ============================================================
-- 9. COMUNAS CHILE — Códigos oficiales SII
--    Fuente: Estructura Detalle Catastral SII
-- ============================================================

CREATE TABLE IF NOT EXISTS ref.comunas (
  codigo_sii       integer PRIMARY KEY,        -- Código SII 4 dígitos
  nombre           text NOT NULL,
  region           integer,                    -- Número de región (1-16 + RM)
  region_nombre    text,
  codigo_iata      text,                       -- Abreviatura opcional
  es_rm            boolean DEFAULT false       -- Pertenece a Región Metropolitana
);

INSERT INTO ref.comunas (codigo_sii, nombre, region, region_nombre, es_rm) VALUES
-- Región I — Tarapacá (Arica y Parinacota + Tarapacá)
(1101,'ARICA',             1,'Arica y Parinacota', false),
(1106,'CAMARONES',         1,'Arica y Parinacota', false),
(1201,'IQUIQUE',           1,'Tarapacá',            false),
(1203,'PICA',              1,'Tarapacá',            false),
(1204,'POZO ALMONTE',      1,'Tarapacá',            false),
(1206,'HUARA',             1,'Tarapacá',            false),
(1208,'CAMINA',            1,'Tarapacá',            false),
(1210,'COLCHANE',          1,'Tarapacá',            false),
(1211,'ALTO HOSPICIO',     1,'Tarapacá',            false),
(1301,'PUTRE',             1,'Arica y Parinacota', false),
(1302,'GENERAL LAGOS',     1,'Arica y Parinacota', false),
-- Región II — Antofagasta
(2101,'TOCOPILLA',         2,'Antofagasta',  false),
(2103,'MARIA ELENA',       2,'Antofagasta',  false),
(2201,'ANTOFAGASTA',       2,'Antofagasta',  false),
(2202,'TALTAL',            2,'Antofagasta',  false),
(2203,'MEJILLONES',        2,'Antofagasta',  false),
(2206,'SIERRA GORDA',      2,'Antofagasta',  false),
(2301,'CALAMA',            2,'Antofagasta',  false),
(2302,'OLLAGUE',           2,'Antofagasta',  false),
(2303,'SAN PEDRO DE ATACAMA',2,'Antofagasta',false),
-- Región III — Atacama
(3101,'CHANARAL',          3,'Atacama',  false),
(3102,'DIEGO DE ALMAGRO',  3,'Atacama',  false),
(3201,'COPIAPO',           3,'Atacama',  false),
(3202,'CALDERA',           3,'Atacama',  false),
(3203,'TIERRA AMARILLA',   3,'Atacama',  false),
(3301,'VALLENAR',          3,'Atacama',  false),
(3302,'FREIRINA',          3,'Atacama',  false),
(3303,'HUASCO',            3,'Atacama',  false),
(3304,'ALTO DEL CARMEN',   3,'Atacama',  false),
-- Región IV — Coquimbo
(4101,'LA SERENA',         4,'Coquimbo', false),
(4102,'LA HIGUERA',        4,'Coquimbo', false),
(4103,'COQUIMBO',          4,'Coquimbo', false),
(4104,'ANDACOLLO',         4,'Coquimbo', false),
(4105,'VICUNA',            4,'Coquimbo', false),
(4106,'PAIHUANO',          4,'Coquimbo', false),
(4201,'OVALLE',            4,'Coquimbo', false),
(4203,'MONTE PATRIA',      4,'Coquimbo', false),
(4204,'PUNITAQUI',         4,'Coquimbo', false),
(4205,'COMBARBALA',        4,'Coquimbo', false),
(4206,'RIO HURTADO',       4,'Coquimbo', false),
(4301,'ILLAPEL',           4,'Coquimbo', false),
(4302,'SALAMANCA',         4,'Coquimbo', false),
(4303,'LOS VILOS',         4,'Coquimbo', false),
(4304,'CANELA',            4,'Coquimbo', false),
-- Región V — Valparaíso
(5101,'ISLA DE PASCUA',    5,'Valparaíso', false),
(5201,'LA LIGUA',          5,'Valparaíso', false),
(5202,'PETORCA',           5,'Valparaíso', false),
(5203,'CABILDO',           5,'Valparaíso', false),
(5204,'ZAPALLAR',          5,'Valparaíso', false),
(5205,'PAPUDO',            5,'Valparaíso', false),
(5301,'VALPARAISO',        5,'Valparaíso', false),
(5302,'VINA DEL MAR',      5,'Valparaíso', false),
(5303,'VILLA ALEMANA',     5,'Valparaíso', false),
(5304,'QUILPUE',           5,'Valparaíso', false),
(5305,'CASABLANCA',        5,'Valparaíso', false),
(5306,'QUINTERO',          5,'Valparaíso', false),
(5307,'PUCHUNCAVI',        5,'Valparaíso', false),
(5308,'JUAN FERNANDEZ',    5,'Valparaíso', false),
(5309,'CONCON',            5,'Valparaíso', false),
(5401,'SAN ANTONIO',       5,'Valparaíso', false),
(5402,'SANTO DOMINGO',     5,'Valparaíso', false),
(5403,'CARTAGENA',         5,'Valparaíso', false),
(5404,'EL TABO',           5,'Valparaíso', false),
(5405,'EL QUISCO',         5,'Valparaíso', false),
(5406,'ALGARROBO',         5,'Valparaíso', false),
(5501,'QUILLOTA',          5,'Valparaíso', false),
(5502,'NOGALES',           5,'Valparaíso', false),
(5503,'HIJUELAS',          5,'Valparaíso', false),
(5504,'LA CALERA',         5,'Valparaíso', false),
(5505,'LA CRUZ',           5,'Valparaíso', false),
(5506,'LIMACHE',           5,'Valparaíso', false),
(5507,'OLMUE',             5,'Valparaíso', false),
(5601,'SAN FELIPE',        5,'Valparaíso', false),
(5602,'PANQUEHUE',         5,'Valparaíso', false),
(5603,'CATEMU',            5,'Valparaíso', false),
(5604,'PUTAENDO',          5,'Valparaíso', false),
(5605,'SANTA MARIA',       5,'Valparaíso', false),
(5606,'LLAY-LLAY',         5,'Valparaíso', false),
(5701,'LOS ANDES',         5,'Valparaíso', false),
(5702,'CALLE LARGA',       5,'Valparaíso', false),
(5703,'SAN ESTEBAN',       5,'Valparaíso', false),
(5704,'RINCONADA',         5,'Valparaíso', false),
-- Región VI — O'Higgins
(6101,'RANCAGUA',          6,'O''Higgins', false),
(6102,'MACHALI',           6,'O''Higgins', false),
(6103,'GRANEROS',          6,'O''Higgins', false),
(6104,'SAN FRANCISCO DE MOSTAZAL',6,'O''Higgins',false),
(6105,'DONIHUE',           6,'O''Higgins', false),
(6106,'COLTAUCO',          6,'O''Higgins', false),
(6107,'CODEGUA',           6,'O''Higgins', false),
(6108,'PEUMO',             6,'O''Higgins', false),
(6109,'LAS CABRAS',        6,'O''Higgins', false),
(6110,'SAN VICENTE',       6,'O''Higgins', false),
(6111,'PICHIDEGUA',        6,'O''Higgins', false),
(6112,'RENGO',             6,'O''Higgins', false),
(6113,'REQUINOA',          6,'O''Higgins', false),
(6114,'OLIVAR',            6,'O''Higgins', false),
(6115,'MALLOA',            6,'O''Higgins', false),
(6116,'COINCO',            6,'O''Higgins', false),
(6117,'QUINTA DE TILCOCO', 6,'O''Higgins', false),
(6201,'SAN FERNANDO',      6,'O''Higgins', false),
(6202,'CHIMBARONGO',       6,'O''Higgins', false),
(6203,'NANCAGUA',          6,'O''Higgins', false),
(6204,'PLACILLA',          6,'O''Higgins', false),
(6205,'SANTA CRUZ',        6,'O''Higgins', false),
(6206,'LOLOL',             6,'O''Higgins', false),
(6207,'PALMILLA',          6,'O''Higgins', false),
(6208,'PERALILLO',         6,'O''Higgins', false),
(6209,'CHEPICA',           6,'O''Higgins', false),
(6214,'PUMANQUE',          6,'O''Higgins', false),
(6301,'PICHILEMU',         6,'O''Higgins', false),
(6302,'NAVIDAD',           6,'O''Higgins', false),
(6303,'LITUECHE',          6,'O''Higgins', false),
(6304,'LA ESTRELLA',       6,'O''Higgins', false),
(6305,'MARCHIGUE',         6,'O''Higgins', false),
(6306,'PAREDONES',         6,'O''Higgins', false),
-- Región VII — Maule
(7101,'CURICO',            7,'Maule', false),
(7102,'TENO',              7,'Maule', false),
(7103,'ROMERAL',           7,'Maule', false),
(7104,'RAUCO',             7,'Maule', false),
(7105,'LICANTEN',          7,'Maule', false),
(7106,'VICHUQUEN',         7,'Maule', false),
(7107,'HUALANE',           7,'Maule', false),
(7108,'MOLINA',            7,'Maule', false),
(7109,'SAGRADA FAMILIA',   7,'Maule', false),
(7201,'TALCA',             7,'Maule', false),
(7202,'SAN CLEMENTE',      7,'Maule', false),
(7203,'PELARCO',           7,'Maule', false),
(7204,'RIO CLARO',         7,'Maule', false),
(7205,'PENCAHUE',          7,'Maule', false),
(7206,'MAULE',             7,'Maule', false),
(7207,'CUREPTO',           7,'Maule', false),
(7208,'CONSTITUCION',      7,'Maule', false),
(7209,'EMPEDRADO',         7,'Maule', false),
(7210,'SAN RAFAEL',        7,'Maule', false),
(7301,'LINARES',           7,'Maule', false),
(7302,'YERBAS BUENAS',     7,'Maule', false),
(7303,'COLBUN',            7,'Maule', false),
(7304,'LONGAVI',           7,'Maule', false),
(7305,'PARRAL',            7,'Maule', false),
(7306,'RETIRO',            7,'Maule', false),
(7309,'VILLA ALEGRE',      7,'Maule', false),
(7310,'SAN JAVIER',        7,'Maule', false),
(7401,'CAUQUENES',         7,'Maule', false),
(7402,'PELLUHUE',          7,'Maule', false),
(7403,'CHANCO',            7,'Maule', false),
-- Región VIII — Biobío
(8101,'CHILLAN',           8,'Ñuble/Biobío', false),
(8102,'PINTO',             8,'Ñuble/Biobío', false),
(8103,'COIHUECO',          8,'Ñuble/Biobío', false),
(8104,'QUIRIHUE',          8,'Ñuble/Biobío', false),
(8105,'NINHUE',            8,'Ñuble/Biobío', false),
(8106,'PORTEZUELO',        8,'Ñuble/Biobío', false),
(8107,'COBQUECURA',        8,'Ñuble/Biobío', false),
(8108,'TREHUACO',          8,'Ñuble/Biobío', false),
(8109,'SAN CARLOS',        8,'Ñuble/Biobío', false),
(8110,'NIQUEN',            8,'Ñuble/Biobío', false),
(8111,'SAN FABIAN',        8,'Ñuble/Biobío', false),
(8112,'SAN NICOLAS',       8,'Ñuble/Biobío', false),
(8113,'BULNES',            8,'Ñuble/Biobío', false),
(8114,'SAN IGNACIO',       8,'Ñuble/Biobío', false),
(8115,'QUILLON',           8,'Ñuble/Biobío', false),
(8116,'YUNGAY',            8,'Ñuble/Biobío', false),
(8117,'PEMUCO',            8,'Ñuble/Biobío', false),
(8118,'EL CARMEN',         8,'Ñuble/Biobío', false),
(8119,'RANQUIL',           8,'Ñuble/Biobío', false),
(8120,'COELEMU',           8,'Ñuble/Biobío', false),
(8121,'CHILLAN VIEJO',     8,'Ñuble/Biobío', false),
(8201,'CONCEPCION',        8,'Biobío', false),
(8202,'PENCO',             8,'Biobío', false),
(8203,'HUALQUI',           8,'Biobío', false),
(8204,'FLORIDA',           8,'Biobío', false),
(8205,'TOME',              8,'Biobío', false),
(8206,'TALCAHUANO',        8,'Biobío', false),
(8207,'CORONEL',           8,'Biobío', false),
(8208,'LOTA',              8,'Biobío', false),
(8209,'SANTA JUANA',       8,'Biobío', false),
(8210,'SAN PEDRO DE LA PAZ',8,'Biobío', false),
(8211,'CHIGUAYANTE',       8,'Biobío', false),
(8212,'HUALPEN',           8,'Biobío', false),
(8301,'ARAUCO',            8,'Biobío', false),
(8302,'CURANILAHUE',       8,'Biobío', false),
(8303,'LEBU',              8,'Biobío', false),
(8304,'LOS ALAMOS',        8,'Biobío', false),
(8305,'CANETE',            8,'Biobío', false),
(8306,'CONTULMO',          8,'Biobío', false),
(8307,'TIRUA',             8,'Biobío', false),
(8401,'LOS ANGELES',       8,'Biobío', false),
(8402,'SANTA BARBARA',     8,'Biobío', false),
(8403,'LAJA',              8,'Biobío', false),
(8404,'QUILLECO',          8,'Biobío', false),
(8405,'NACIMIENTO',        8,'Biobío', false),
(8406,'NEGRETE',           8,'Biobío', false),
(8407,'MULCHEN',           8,'Biobío', false),
(8408,'QUILACO',           8,'Biobío', false),
(8409,'YUMBEL',            8,'Biobío', false),
(8410,'CABRERO',           8,'Biobío', false),
(8411,'SAN ROSENDO',       8,'Biobío', false),
(8412,'TUCAPEL',           8,'Biobío', false),
(8413,'ANTUCO',            8,'Biobío', false),
(8414,'ALTO BIOBIO',       8,'Biobío', false),
-- Región IX — La Araucanía
(9101,'ANGOL',             9,'Araucanía', false),
(9102,'PUREN',             9,'Araucanía', false),
(9103,'LOS SAUCES',        9,'Araucanía', false),
(9104,'RENAICO',           9,'Araucanía', false),
(9105,'COLLIPULLI',        9,'Araucanía', false),
(9106,'ERCILLA',           9,'Araucanía', false),
(9107,'TRAIGUEN',          9,'Araucanía', false),
(9108,'LUMACO',            9,'Araucanía', false),
(9109,'VICTORIA',          9,'Araucanía', false),
(9110,'CURACAUTIN',        9,'Araucanía', false),
(9111,'LONQUIMAY',         9,'Araucanía', false),
(9201,'TEMUCO',            9,'Araucanía', false),
(9202,'VILCUN',            9,'Araucanía', false),
(9203,'FREIRE',            9,'Araucanía', false),
(9204,'CUNCO',             9,'Araucanía', false),
(9205,'LAUTARO',           9,'Araucanía', false),
(9206,'PERQUENCO',         9,'Araucanía', false),
(9207,'GALVARINO',         9,'Araucanía', false),
(9208,'NUEVA IMPERIAL',    9,'Araucanía', false),
(9209,'CARAHUE',           9,'Araucanía', false),
(9210,'SAAVEDRA',          9,'Araucanía', false),
(9211,'PITRUFQUEN',        9,'Araucanía', false),
(9212,'GORBEA',            9,'Araucanía', false),
(9213,'TOLTEN',            9,'Araucanía', false),
(9214,'LONCOCHE',          9,'Araucanía', false),
(9215,'VILLARRICA',        9,'Araucanía', false),
(9216,'PUCON',             9,'Araucanía', false),
(9217,'MELIPEUCO',         9,'Araucanía', false),
(9218,'CURARREHUE',        9,'Araucanía', false),
(9219,'TEODORO SCHMIDT',   9,'Araucanía', false),
(9220,'PADRE LAS CASAS',   9,'Araucanía', false),
(9221,'CHOLCHOL',          9,'Araucanía', false),
-- Región X — Los Lagos
(10101,'VALDIVIA',         10,'Los Ríos/Los Lagos', false),
(10102,'MARIQUINA',        10,'Los Ríos',  false),
(10103,'LANCO',            10,'Los Ríos',  false),
(10104,'LOS LAGOS',        10,'Los Ríos',  false),
(10105,'FUTRONO',          10,'Los Ríos',  false),
(10106,'CORRAL',           10,'Los Ríos',  false),
(10107,'MAFIL',            10,'Los Ríos',  false),
(10108,'PANGUIPULLI',      10,'Los Ríos',  false),
(10109,'LA UNION',         10,'Los Ríos',  false),
(10110,'PAILLACO',         10,'Los Ríos',  false),
(10111,'RIO BUENO',        10,'Los Ríos',  false),
(10112,'LAGO RANCO',       10,'Los Ríos',  false),
(10201,'OSORNO',           10,'Los Lagos', false),
(10202,'SAN PABLO',        10,'Los Lagos', false),
(10203,'PUERTO OCTAY',     10,'Los Lagos', false),
(10204,'PUYEHUE',          10,'Los Lagos', false),
(10205,'RIO NEGRO',        10,'Los Lagos', false),
(10206,'PURRANQUE',        10,'Los Lagos', false),
(10207,'SAN JUAN DE LA COSTA',10,'Los Lagos',false),
(10301,'PUERTO MONTT',     10,'Los Lagos', false),
(10302,'COCHAMO',          10,'Los Lagos', false),
(10303,'PUERTO VARAS',     10,'Los Lagos', false),
(10304,'FRESIA',           10,'Los Lagos', false),
(10305,'FRUTILLAR',        10,'Los Lagos', false),
(10306,'LLANQUIHUE',       10,'Los Lagos', false),
(10307,'MAULLIN',          10,'Los Lagos', false),
(10308,'LOS MUERMOS',      10,'Los Lagos', false),
(10309,'CALBUCO',          10,'Los Lagos', false),
(10401,'CASTRO',           10,'Los Lagos', false),
(10402,'CHONCHI',          10,'Los Lagos', false),
(10403,'QUEILEN',          10,'Los Lagos', false),
(10404,'QUELLON',          10,'Los Lagos', false),
(10405,'PUQUELDON',        10,'Los Lagos', false),
(10406,'ANCUD',            10,'Los Lagos', false),
(10407,'QUEMCHI',          10,'Los Lagos', false),
(10408,'DALCAHUE',         10,'Los Lagos', false),
(10410,'CURACO DE VELEZ',  10,'Los Lagos', false),
(10415,'QUINCHAO',         10,'Los Lagos', false),
(10501,'CHAITEN',          10,'Los Lagos', false),
(10502,'HUALAIHUE',        10,'Los Lagos', false),
(10503,'FUTALEUFU',        10,'Los Lagos', false),
(10504,'PALENA',           10,'Los Lagos', false),
-- Región XI — Aysén
(11101,'AYSEN',            11,'Aysén', false),
(11102,'CISNES',           11,'Aysén', false),
(11104,'GUAITECAS',        11,'Aysén', false),
(11201,'CHILE CHICO',      11,'Aysén', false),
(11203,'RIO IBANEZ',       11,'Aysén', false),
(11301,'COCHRANE',         11,'Aysén', false),
(11302,'OHIGGINS',         11,'Aysén', false),
(11303,'TORTEL',           11,'Aysén', false),
(11401,'COYHAIQUE',        11,'Aysén', false),
(11402,'LAGO VERDE',       11,'Aysén', false),
-- Región XII — Magallanes
(12101,'NATALES',          12,'Magallanes', false),
(12103,'TORRES DEL PAINE', 12,'Magallanes', false),
(12202,'RIO VERDE',        12,'Magallanes', false),
(12204,'SAN GREGORIO',     12,'Magallanes', false),
(12205,'PUNTA ARENAS',     12,'Magallanes', false),
(12206,'LAGUNA BLANCA',    12,'Magallanes', false),
(12301,'PORVENIR',         12,'Magallanes', false),
(12302,'PRIMAVERA',        12,'Magallanes', false),
(12304,'TIMAUKEL',         12,'Magallanes', false),
(12401,'CABO DE HORNOS',   12,'Magallanes', false),
-- Región Metropolitana (RM) — códigos 13xxx y 14xxx y 15xxx y 16xxx
(13101,'SANTIAGO',         13,'Región Metropolitana', true),
(13134,'SANTIAGO OESTE',   13,'Región Metropolitana', true),
(13135,'SANTIAGO SUR',     13,'Región Metropolitana', true),
(13159,'RECOLETA',         13,'Región Metropolitana', true),
(13167,'INDEPENDENCIA',    13,'Región Metropolitana', true),
(14107,'QUINTA NORMAL',    13,'Región Metropolitana', true),
(14109,'MAIPU',            13,'Región Metropolitana', true),
(14111,'PUDAHUEL',         13,'Región Metropolitana', true),
(14113,'RENCA',            13,'Región Metropolitana', true),
(14114,'QUILICURA',        13,'Región Metropolitana', true),
(14127,'CONCHALI',         13,'Región Metropolitana', true),
(14155,'LO PRADO',         13,'Región Metropolitana', true),
(14156,'CERRO NAVIA',      13,'Región Metropolitana', true),
(14157,'ESTACION CENTRAL', 13,'Región Metropolitana', true),
(14158,'HUECHURABA',       13,'Región Metropolitana', true),
(14166,'CERRILLOS',        13,'Región Metropolitana', true),
(14201,'COLINA',           13,'Región Metropolitana', true),
(14202,'LAMPA',            13,'Región Metropolitana', true),
(14203,'TIL-TIL',          13,'Región Metropolitana', true),
(14501,'TALAGANTE',        13,'Región Metropolitana', true),
(14502,'ISLA DE MAIPO',    13,'Región Metropolitana', true),
(14503,'EL MONTE',         13,'Región Metropolitana', true),
(14504,'PENAFLOR',         13,'Región Metropolitana', true),
(14505,'PADRE HURTADO',    13,'Región Metropolitana', true),
(14601,'MELIPILLA',        13,'Región Metropolitana', true),
(14602,'MARIA PINTO',      13,'Región Metropolitana', true),
(14603,'CURACAVI',         13,'Región Metropolitana', true),
(14604,'SAN PEDRO',        13,'Región Metropolitana', true),
(14605,'ALHUE',            13,'Región Metropolitana', true),
(15103,'PROVIDENCIA',      13,'Región Metropolitana', true),
(15105,'NUNOA',            13,'Región Metropolitana', true),
(15108,'LAS CONDES',       13,'Región Metropolitana', true),
(15128,'LA FLORIDA',       13,'Región Metropolitana', true),
(15132,'LA REINA',         13,'Región Metropolitana', true),
(15151,'MACUL',            13,'Región Metropolitana', true),
(15152,'PENALOLEN',        13,'Región Metropolitana', true),
(15160,'VITACURA',         13,'Región Metropolitana', true),
(15161,'LO BARNECHEA',     13,'Región Metropolitana', true),
(16106,'SAN MIGUEL',       13,'Región Metropolitana', true),
(16110,'LA CISTERNA',      13,'Región Metropolitana', true),
(16131,'LA GRANJA',        13,'Región Metropolitana', true),
(16153,'SAN RAMON',        13,'Región Metropolitana', true),
(16154,'LA PINTANA',       13,'Región Metropolitana', true),
(16162,'PEDRO AGUIRRE CERDA',13,'Región Metropolitana', true),
(16163,'SAN JOAQUIN',      13,'Región Metropolitana', true),
(16164,'LO ESPEJO',        13,'Región Metropolitana', true),
(16165,'EL BOSQUE',        13,'Región Metropolitana', true),
(16301,'PUENTE ALTO',      13,'Región Metropolitana', true),
(16302,'PIRQUE',           13,'Región Metropolitana', true),
(16303,'SAN JOSE DE MAIPO',13,'Región Metropolitana', true),
(16401,'SAN BERNARDO',     13,'Región Metropolitana', true),
(16402,'CALERA DE TANGO',  13,'Región Metropolitana', true),
(16403,'BUIN',             13,'Región Metropolitana', true),
(16404,'PAINE',            13,'Región Metropolitana', true);

COMMENT ON TABLE ref.comunas IS
  'Códigos oficiales SII de todas las comunas de Chile. '
  'Fuente: Estructura Detalle Catastral SII (BRTMPCATASA_COMUNAS). '
  'Nota: Varios códigos RM empiezan en 14xxx, 15xxx, 16xxx por subdivisión histórica.';
