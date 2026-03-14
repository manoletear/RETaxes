# RETaxes 🏠📊

> **La biblia técnica para el cálculo correcto de tasaciones, contribuciones, avalúos fiscales e información catastral en Chile.**

Sistema de auditoría fiscal de bienes raíces (SNRI — Sistema Nacional de Revisión de Impuesto Territorial), orientado a contribuyentes, abogados tributarios y profesionales de la tasación.

---

## ¿Qué es RETaxes?

RETaxes es un repositorio técnico completo que contiene:

1. **Schema de base de datos** — Toda la normativa fiscal SII modelada en tablas Postgres/Supabase
2. **Motor de cálculo** — Fórmulas exactas para recalcular avalúos y contribuciones
3. **Ingestor de datos SII** — CLI para procesar el Detalle Catastral masivo del SII
4. **Documentación técnica** — PDFs y análisis del sistema de tasación chileno
5. **Dashboard** — Interfaz visual para auditoría de ROLs

---

## Arquitectura del Sistema

```
SII (datos públicos)
    │
    ▼
snri_ingest.py ──── lee CSV SII ──── genera SQL masivo
    │
    ▼
Supabase (PostgreSQL)
    ├── ref.*          → Normativa fiscal (tasas, exenciones, fórmulas)
    ├── catastro.*     → Predios, construcciones, avalúos, contribuciones
    └── public.*       → Portal usuario: casos, auditorías, documentos
    │
    ▼
Frontend (RETaxes Portal)
    ├── Consulta por ROL
    ├── Auditoría SNRI
    └── Gestión de casos
```

---

## Estructura del Repositorio

```
RETaxes/
├── README.md                          ← Este archivo
├── database/
│   ├── migrations/
│   │   ├── 001_ref_catalogos.sql      ← Catálogos SII: destinos, materiales, comunas
│   │   ├── 002_ref_parametros.sql     ← Tasas, exenciones, BAM, DFL2, fórmulas
│   │   ├── 003_ref_vistas.sql         ← Vistas, funciones de cálculo, RLS
│   │   └── 004_catastro_portal.sql    ← Predios, construcciones, usuarios, casos, RPCs
│   └── seeds/
│       └── panguipulli_2025_2.sql     ← Dataset real: Panguipulli, 44.216 registros
├── tools/
│   └── snri_ingest.py                 ← CLI ingestor de archivos SII
├── frontend/
│   └── snri-dashboard.html            ← Dashboard SNRI (single-file, dark theme)
├── schemas/
│   ├── sii_detalle_catastral.md       ← Estructura archivos SII (N, NL, A, AL)
│   └── sii_rol_cobro.md               ← Estructura Rol Semestral de Cobro
└── docs/
    ├── Calculo_Contribuciones_SII.pdf         ← Análisis técnico-forense completo
    ├── estructura_detalle_catastral.pdf        ← Estructura oficial SII
    ├── estructura_rol_cobro_semestral.pdf      ← Estructura Rol Cobro SII
    └── ...                                     ← Documentación adicional
```

---

## Quick Start — Deploy en Supabase

### 1. Ejecutar migrations en orden

```sql
-- En Supabase SQL Editor, ejecutar en este orden:
\i database/migrations/001_ref_catalogos.sql
\i database/migrations/002_ref_parametros_fiscales.sql
\i database/migrations/003_ref_vistas_funciones.sql
\i database/migrations/004_catastro_portal.sql
```

### 2. Verificar instalación

```sql
SELECT COUNT(*) FROM ref.comunas;             -- debe retornar ~345
SELECT COUNT(*) FROM ref.errores_tipicos;     -- debe retornar 11
SELECT * FROM ref.v_resumen_fiscal_vigente;   -- parámetros vigentes
SELECT * FROM catastro.fn_parsear_rol('15108-624-6');
```

### 3. Ingestar datos SII

```bash
# Instalar dependencias
pip install psycopg2-binary

# Generar SQL desde archivos SII
python tools/snri_ingest.py \
  BRTMPCATASN_2025_2_XXXXX \
  BRTMPCATASNL_2025_2_XXXXX \
  BRTMPCATASA_2025_2_XXXXX \
  BRTMPCATASAL_2025_2_XXXXX \
  --output mi_comuna.sql

# O ejecutar directo contra Supabase
python tools/snri_ingest.py \
  BRTMPCATASN_2025_2_XXXXX \
  BRTMPCATASNL_2025_2_XXXXX \
  BRTMPCATASA_2025_2_XXXXX \
  BRTMPCATASAL_2025_2_XXXXX \
  --db-url "postgresql://postgres:PASS@db.XXX.supabase.co:5432/postgres"
```

---

## El Sistema de Tasación Chileno — Resumen Técnico

### Fase 1: Tasación (Avalúo Fiscal)

**No Agrícola:**
```
Avalúo Total = Avalúo Terreno (AT) + Avalúo Construcción (AC)

AT = VUTAH × ST × CT
     donde CT = (CS o CE) × CA

AC = VUC × SC × CE × DP × FC × CC
```

**Agrícola:**
```
ATS = Σ(VBS × HAS) × (1 - RCD/100)
ATCA = Σ(VBC × CM × GC × DP × CE)
```

### Fase 2: Cálculo de Contribuciones (vigentes 2025)

```
Avalúo Afecto = MAX(0, Avalúo Total − Monto Exento)

Exenciones:
  Habitacional:  $58.040.782
  Agrícola:      $47.192.449
  Otros:         $0

Contribución Neta (Habitacional — progresiva):
  Tramo 1: MIN(Avalúo Afecto, $207.288.476) × 0,893%
  Tramo 2: MAX(0, Avalúo Afecto − $207.288.476) × 1,042%

Contribución Neta (Otros destinos — tasa fija):
  Avalúo Afecto × 1,088%

Sobretasas:
  Fiscal (0,025%):     tramo 2 habitacional / total otros
  SNE (100%):          sitios eriazos / predios abandonados
  Art. 7°bis (progresiva): patrimonio inmobiliario total del RUT

Contribución Total = Contribución Neta + Sobretasas − Beneficios
```

---

## Archivos SII — Formatos

### Detalle Catastral (pipe-separated `|`, Latin-1, sin encabezados)

| Archivo | Tipo | Contenido | Cols |
|---------|------|-----------|------|
| `BRTMPCATASN_*` | N | 1 fila/ROL no agrícola | 19 |
| `BRTMPCATASNL_*` | NL | N líneas/ROL construcciones | 11 |
| `BRTMPCATASA_*` | A | 1 fila/ROL agrícola | 9 |
| `BRTMPCATASAL_*` | AL | N líneas suelos+construcciones agrícolas | 12 |

### Rol Semestral de Cobro (fixed-width 117 chars/fila)

| Pos | Campo | Largo |
|-----|-------|-------|
| 1-5 | Código comuna | 5 |
| 6-9 | Año | 4 |
| 10 | Semestre | 1 |
| 18-57 | Dirección | 40 |
| 69-81 | Cuota trimestral | 13 |
| 82-96 | Avalúo total | 15 |
| 97-111 | Avalúo exento | 15 |

Ver `schemas/` para especificación completa.

---

## Schema SQL — Tablas Principales

### `ref.*` — Normativa (read-only)
- `ref.comunas` — 345 comunas con código SII oficial
- `ref.destinos` — 20 códigos A-Z
- `ref.materiales_construccion`, `ref.calidades_construccion`
- `ref.tasas_impuesto`, `ref.montos_exencion`
- `ref.depreciacion_construccion`, `ref.bam_parametros`, `ref.dfl2_parametros`
- `ref.errores_tipicos` — 11 errores auditables (ERR-C01 a ERR-M01)
- `ref.formulas_calculo` — 12 fórmulas documentadas (F01-F12)

### `catastro.*` — Datos prediales
- `catastro.predios` — ROLs (PK: `CCCC-MMM-P`)
- `catastro.construcciones` — N líneas por ROL
- `catastro.suelos_agricolas` — Suelos agrícolas
- `catastro.avaluos_historial` — Serie histórica
- `catastro.contribuciones_historial` — Pagos históricos
- `catastro.importaciones` — Control de ingestión masiva

### `public.*` — Portal usuario
- `public.usuarios` — Contribuyentes autenticados
- `public.propiedades_usuario` — Propiedades registradas
- `public.documentos_usuario` — CIP, certificados, planos
- `public.auditorias_usuario` — Historial de auditorías
- `public.casos` — CRM de casos (auto-numerados `SNRI-YYYY-NNNN`)

### RPCs disponibles
```sql
rpc_validar_rol(rol)                          -- Carga datos SII de un ROL
rpc_recalcular_predio_y_caso(rol, null)       -- Auditoría SNRI completa
rpc_crear_caso_desde_usuario(rol, usuario_id) -- Crea caso desde auditoría
rpc_heatmap_usuario(usuario_id)               -- Mapa de riesgo personal
rpc_estadisticas_comuna(cod_comuna)           -- Stats agregadas por comuna
```

---

## Errores Detectables (SNRI)

| Código | Descripción |
|--------|-------------|
| ERR-C01 | Superficie construcción incorrecta |
| ERR-C02 | Año construcción incorrecto |
| ERR-C03 | Calidad construcción sobreestimada |
| ERR-C04 | Condición especial no registrada |
| ERR-C05 | Destino construcción incorrecto |
| ERR-T01 | Superficie terreno incorrecta |
| ERR-T02 | Área homogénea incorrecta |
| ERR-T03 | Afectación vial no descontada |
| ERR-B01 | BAM no aplicado |
| ERR-B02 | DFL-2 no aplicado |
| ERR-M01 | Destino principal incorrecto |

---

## Marco Legal

| Norma | Contenido |
|-------|-----------|
| Ley N° 17.235 | Ley sobre Impuesto Territorial |
| DS N° 437 (2022) | Tasas vigentes |
| RE SII N° 131 (2024) | Tablas de valores y coeficientes (Reavalúo 2025) |
| Art. 7°bis Ley 17.235 | Sobretasa patrimonial progresiva |
| DFL-2 (1959) | Beneficio habitacional |
| Ley 20.732 | Beneficio Adulto Mayor |

---

## Datos de Validación (Panguipulli — Semestre 2/2025)

| Métrica | Valor |
|---------|-------|
| ROLs no agrícolas | 13.679 |
| ROLs agrícolas | 7.078 |
| Líneas construcción | 13.158 |
| Líneas suelo agrícola | 10.301 |
| Material dominante | Madera (E) — 94% |
| Destinos urbanos top | H (Habitacional) 57%, W (Eriazo) 38% |
| Predios con exención | 6.981 (51%) |

---

## Roadmap

- [ ] Frontend RETaxes Portal (Next.js 14 + TypeScript)
- [ ] Ingestión nacional completa (345 comunas)
- [ ] RE 131 Anexo 1 — VUTAH por Área Homogénea
- [ ] RE 131 Anexo 5 — VUC por Clase/Calidad
- [ ] API pública de consulta por ROL
- [ ] Motor de auditoría SNRI v2 (IA)

---

## Licencia

MIT — Uso libre con atribución.

---

*Construido para contribuyentes, abogados tributarios y tasadores chilenos.*
