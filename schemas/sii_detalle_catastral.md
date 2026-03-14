# Estructura Archivos SII — Detalle Catastral de Bienes Raíces

> Fuente oficial: SII Chile — `BRORGA2441*_NAC` / `BRTMPCATAS*_COMUNAS`
> Formato: pipe-separated `|`, sin encabezados, encoding Latin-1

---

## Resumen de archivos

| Archivo | Tipo | Serie | Registros | Cols |
|---------|------|-------|-----------|------|
| `BRTMPCATASN_AAAA_S_CCCCC` | N | No agrícola básico | 1 fila / ROL | 19 (+trailing) |
| `BRTMPCATASNL_AAAA_S_CCCCC` | NL | No agrícola líneas | N filas / ROL | 11 (+trailing) |
| `BRTMPCATASA_AAAA_S_CCCCC` | A | Agrícola básico | 1 fila / ROL | 9 (+trailing) |
| `BRTMPCATASAL_AAAA_S_CCCCC` | AL | Agrícola suelos/construcciones | N filas / ROL | 12 |

Nomenclatura: `AAAA` = año, `S` = semestre (1/2), `CCCCC` = código SII de la comuna.

---

## Tipo N — No Agrícola Básico

**Una fila por ROL. 19 campos + trailing pipe (ignorar campo vacío final).**

| # | Campo | Descripción | Notas |
|---|-------|-------------|-------|
| 1 | `cod_comuna` | Código SII de la comuna | 5 dígitos |
| 2 | `manzana` | Número de manzana | 5 dígitos, ceros a la izquierda |
| 3 | `predio` | Número predial | 5 dígitos, ceros a la izquierda |
| 4 | `direccion` | Dirección o nombre del predio | 40 chars, padded con espacios |
| 5 | `avaluo_total` | Avalúo fiscal total | 15 dígitos, sin decimales (pesos) |
| 6 | `contrib_semestre` | Contribución semestral (con aseo) | 13 dígitos |
| 7 | `destino` | Código destino principal | Ver Tabla Destinos |
| 8 | `avaluo_exento` | Avalúo exento de la propiedad | 15 dígitos |
| 9 | `bc1_comuna` | Bien Común 1 — código comuna | `00000` si no aplica |
| 10 | `bc1_manzana` | Bien Común 1 — manzana | `00000` si no aplica |
| 11 | `bc1_predio` | Bien Común 1 — predio | `00000` si no aplica |
| 12 | `bc2_comuna` | Bien Común 2 — código comuna | `00000` si no aplica |
| 13 | `bc2_manzana` | Bien Común 2 — manzana | `00000` si no aplica |
| 14 | `bc2_predio` | Bien Común 2 — predio | `00000` si no aplica |
| 15 | `sup_terreno` | Superficie total del terreno | m², sin decimales |
| 16 | `cod_ubicacion` | Ubicación | `U`=urbano, `R`=rural |
| 17 | `rol_padre_comuna` | Rol Padre — código comuna | `00000` si no aplica |
| 18 | `rol_padre_manzana` | Rol Padre — manzana | `00000` si no aplica |
| 19 | `rol_padre_predio` | Rol Padre — predio | `00000` si no aplica |
| 20 | *(vacío)* | Trailing pipe — ignorar | |

**Construcción del ROL:** `cod_comuna`-`manzana`-`predio` (ej: `15108-00624-00006`)

---

## Tipo NL — No Agrícola Líneas de Construcción

**N filas por ROL (una por cada línea de terreno o construcción). 11 campos + trailing pipe.**

| # | Campo | Descripción | Notas |
|---|-------|-------------|-------|
| 1 | `cod_comuna` | Código SII de la comuna | |
| 2 | `manzana` | Número de manzana | |
| 3 | `predio` | Número predial | |
| 4 | `nro_linea` | Correlativo de la línea | `0001`, `0002`... |
| 5 | `material` | Código material estructural | **Requiere `.trim()`** — viene con padding |
| 6 | `calidad` | Código de calidad | `1`-`5` |
| 7 | `anio` | Año de la construcción | 4 dígitos (ej: `1985`) |
| 8 | `superficie` | Superficie m² | Sin decimales |
| 9 | `destino` | Código destino de la línea | Ver Tabla Destinos |
| 10 | `cond_esp` | Condición especial | Puede estar vacío; requiere trim |
| 11 | `pisos` | Número de pisos | |
| 12 | *(vacío)* | Trailing pipe — ignorar | |

---

## Tipo A — Agrícola Básico

**Una fila por ROL. 9 campos + trailing pipe.**

| # | Campo | Descripción | Notas |
|---|-------|-------------|-------|
| 1 | `cod_comuna` | Código SII de la comuna | |
| 2 | `manzana` | Número de manzana | |
| 3 | `predio` | Número predial | |
| 4 | `direccion` | Dirección o nombre del predio | 40 chars padded |
| 5 | `avaluo_total` | Avalúo fiscal total | Pesos, sin decimales |
| 6 | `contrib_semestre` | Contribución semestral (con aseo) | |
| 7 | `destino` | Código destino principal | Ver Tabla Destinos |
| 8 | `avaluo_exento` | Avalúo exento de la propiedad | |
| 9 | `cod_ubicacion` | Ubicación | `U`=urbano, `R`=rural |
| 10 | *(vacío)* | Trailing pipe — ignorar | |

> ⚠️ **Corrección documentada:** El campo 9 (`cod_ubicacion`) NO aparece en la documentación oficial pero SÍ existe en los datos reales. Confirmado con datos de Panguipulli 2025-2 (10108).

---

## Tipo AL — Agrícola Suelos y Construcciones

**N filas por ROL. 12 campos. SIN trailing pipe.**

**Lógica de filas:**
- Si `nro_linea = 0000` → fila de **suelo puro** (campos de construcción vacíos/cero)
- Si `nro_linea > 0000` → fila de **construcción** (campo suelo puede estar vacío)

| # | Campo | Descripción | Notas |
|---|-------|-------------|-------|
| 1 | `cod_comuna` | Código SII de la comuna | |
| 2 | `manzana` | Número de manzana | |
| 3 | `predio` | Número predial | |
| 4 | `cod_suelo` | Código de suelo | Ver Tabla Tipos de Suelo |
| 5 | `sup_suelo_raw` | Superficie de suelo | **raw / 100 = hectáreas** (2 decimales implícitos) |
| 6 | `nro_linea` | Correlativo línea construcción | `0000` = solo suelo |
| 7 | `material` | Código material estructural | Vacío si solo suelo |
| 8 | `calidad` | Código de calidad | `0` si solo suelo |
| 9 | `superficie` | Superficie construcción m² | `0` si solo suelo |
| 10 | `destino` | Código destino construcción | Vacío si solo suelo |
| 11 | `cond_esp` | Condición especial | Puede estar vacío |
| 12 | `pisos` | Número de pisos | `000` si solo suelo |

**Conversión sup_suelo:** `raw=00000000120` → `120 / 100 = 1.20 ha`

---

## Tablas de Referencia

### Tabla Destinos (Serie No Agrícola y Agrícola)

| Código | Descripción | Código | Descripción |
|--------|-------------|--------|-------------|
| A | Agrícola | M | Minería |
| B | Agroindustrial | O | Oficina |
| C | Comercio | P* | Administración Pública y Defensa |
| D | Deporte y Recreación | Q | Culto |
| E | Educación y Cultura | S | Salud |
| F | Forestal | T | Transporte y Telecomunicaciones |
| G | Hotel, Motel | V | Otros no considerados |
| H | Habitacional | W | Sitio Eriazo |
| I | Industria | Y | Gallineros, chancheras y otros |
| L | Bodega y Almacenaje | Z | Estacionamiento |

> *Para la serie agrícola, destino P = Casa Patronal

### Códigos de Material

| Código | Descripción |
|--------|-------------|
| A | Acero A en tubos y perfiles |
| B | Hormigón armado |
| C | Albañilería (ladrillo arcilla, piedra, bloque cemento) |
| E | Madera |
| F | Adobe |
| G | Perfiles metálicos |
| K | Estructura con elementos prefabricados e industrializados |
| GA | Acero (agrícola) |
| GB | Hormigón Armado (agrícola) |
| GC | Albañilería (agrícola) |
| GE | Madera (agrícola) |
| GL | Madera Laminada (agrícola) |
| GF | Adobe (agrícola) |
| OA | Acero (otro) |
| OB | Hormigón Armado (otro) |
| OE | Madera (otro) |
| SA | Silo de Acero |
| SB | Silo de Hormigón Armado |
| EA | Estanque de Acero |
| EB | Estanque de Hormigón Armado |
| M | Marquesina |
| P | Pavimento |
| W | Piscina |
| TA | Techumbre Apoyada de Acero |
| TE | Techumbre Apoyada de Madera |
| TL | Techumbre Apoyada de Madera Laminada |

### Códigos de Calidad

| Código | Descripción |
|--------|-------------|
| 1 | Superior |
| 2 | Media Superior |
| 3 | Media |
| 4 | Media Inferior |
| 5 | Inferior |

### Condición Especial

| Código | Descripción |
|--------|-------------|
| AL | Altillo |
| CA | Construcción Abierta |
| CI | Construcción Interior |
| MS | Mansarda |
| PZ | Posi Zócalo |
| SB | Subterráneo |
| TM | Catastrofer 20/02/2010 |

### Tipos de Suelo (serie agrícola)

| Código | Descripción |
|--------|-------------|
| 1R | Primera de riego |
| 2R | Segunda de riego |
| 3R | Tercera de riego |
| 1 | Clase 1 secano arable |
| 2 | Clase 2 secano arable |
| 3 | Clase 3 secano arable |
| 4 | Clase 4 secano arable |
| 5 | Clase 5 secano no arable |
| 6 | Clase 6 secano no arable |
| 7 | Clase 7 secano no arable |
| 8 | Clase 8 secano no arable |

---

## Notas de Implementación

```python
# Parsing correcto en Python
with open(archivo, encoding='latin-1') as f:
    for line in f:
        parts = line.rstrip('\n').split('|')
        # Quitar trailing vacío (trailing pipe)
        if parts and parts[-1].strip() == '':
            parts = parts[:-1]
        # Trim en material (campo 5 en NL, campo 7 en AL)
        material = parts[4].strip() if len(parts) > 4 else ''
        # Superficie suelo en AL: raw / 100
        sup_ha = int(parts[4]) / 100 if tipo == 'AL' else None
```

---

*Corroborado con datos reales: Panguipulli (10108), Semestre 2/2025, 44.216 registros.*
