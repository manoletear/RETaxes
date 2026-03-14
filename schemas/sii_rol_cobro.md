# Estructura Archivo — Rol Semestral de Contribuciones de Bienes Raíces

> Fuente oficial: SII Chile
> Formato: **Fixed-width**, 117 caracteres por registro, sin encabezados, sin separador

---

## Descripción

El Rol Semestral de Cobro es un archivo `.txt` de ancho fijo que contiene **un registro por cada ROL de avalúo**. Incluye el monto de contribución a cobrar, el avalúo y la exención vigente para el semestre correspondiente.

**Diferencia clave con el Detalle Catastral:** Este archivo NO usa separador `|`. Los campos se extraen por posición de carácter (slicing).

---

## Estructura de Campos

| N° | Campo | Pos. Inicial | Pos. Final | Largo | Tipo | Descripción |
|----|-------|-------------|-----------|-------|------|-------------|
| 1 | `cod_comuna` | 1 | 5 | 5 | Numérico | Código CONARA de la comuna |
| 2 | `anio` | 6 | 9 | 4 | Numérico | Año del proceso de rol de cobro |
| 3 | `semestre` | 10 | 10 | 1 | Numérico | Semestre (`1` o `2`) |
| 4 | `ind_aseo` | 11 | 11 | 1 | Texto | `A` si la cuota trimestral incluye tarifa de aseo. Espacio si no |
| 5 | *(espacios)* | 12 | 17 | 6 | Texto | Campo sin información — ignorar |
| 6 | `direccion` | 18 | 57 | 40 | Texto | Dirección predial (padded con espacios) |
| 7 | `manzana` | 58 | 62 | 5 | Numérico | Número de manzana actual |
| 8 | `predio` | 63 | 67 | 5 | Numérico | Número de predio dentro de la manzana |
| 9 | `serie` | 68 | 68 | 1 | Texto | `A`=Agrícola / `N`=No Agrícola |
| 10 | `cuota_trimestral` | 69 | 81 | 13 | Numérico | Monto contribución neta trimestral (incluye aseo si aplica) |
| 11 | `avaluo_total` | 82 | 96 | 15 | Numérico | Monto del avalúo total de la propiedad |
| 12 | `avaluo_exento` | 97 | 111 | 15 | Numérico | Monto de avalúo exento del cobro |
| 13 | `anio_termino_exencion` | 112 | 115 | 4 | Numérico | Año término exención. `2055` = exención indefinida |
| 14 | `cod_ubicacion` | 116 | 116 | 1 | Texto | `R`=rural / `U`=urbana |
| 15 | `destino` | 117 | 117 | 1 | Texto | Código destino principal (ver Tabla Destinos) |

**Total: 117 caracteres por fila.**

---

## Parsing en Python (fixed-width)

```python
def parse_rol_cobro(filepath: str) -> list:
    registros = []
    with open(filepath, encoding='latin-1') as f:
        for i, line in enumerate(f):
            if len(line.rstrip('\n')) < 117:
                print(f"Línea {i+1} incompleta: {len(line)} chars")
                continue
            registros.append({
                'cod_comuna':          line[0:5].strip(),
                'anio':                line[5:9].strip(),
                'semestre':            line[9:10].strip(),
                'ind_aseo':            line[10:11].strip(),
                # line[11:17] = espacios, ignorar
                'direccion':           line[17:57].strip(),
                'manzana':             line[57:62].strip(),
                'predio':              line[62:67].strip(),
                'serie':               line[67:68].strip(),
                'cuota_trimestral':    int(line[68:81].strip() or 0),
                'avaluo_total':        int(line[81:96].strip() or 0),
                'avaluo_exento':       int(line[96:111].strip() or 0),
                'anio_termino_exen':   line[111:115].strip(),
                'cod_ubicacion':       line[115:116].strip(),
                'destino':             line[116:117].strip(),
            })
    return registros
```

---

## SQL de destino

```sql
INSERT INTO catastro.contribuciones_historial (
  rol, codigo_comuna, manzana, predio,
  anio, semestre, serie_predio,
  cuota_trimestral, avaluo_total, avaluo_exento,
  anio_termino_exencion, cod_ubicacion, destino,
  incluye_aseo, fuente_datos
)
VALUES (
  '10108-00624-00006',  -- cod_comuna-manzana-predio
  '10108', '00624', '00006',
  2025, 2, 'N',
  336978, 62045542, 59143557,
  2055, 'U', 'H',
  false, 'SII_RC'
)
ON CONFLICT (rol, anio, semestre) DO UPDATE SET
  cuota_trimestral = EXCLUDED.cuota_trimestral,
  avaluo_total     = EXCLUDED.avaluo_total;
```

---

## Tabla Destinos

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

---

## Diferencias con Detalle Catastral

| Aspecto | Detalle Catastral | Rol Cobro |
|---------|------------------|-----------|
| Separador | `\|` (pipe) | Fixed-width (sin separador) |
| Encoding | Latin-1 | Latin-1 |
| Encabezados | Sin encabezados | Sin encabezados |
| Registros | 1 o N por ROL | 1 por ROL |
| Largo fila | Variable | **117 chars fijos** |
| Contenido | Avalúo + construcciones | Contribución + avalúo vigente |
| Uso SNRI | Base de recálculo | Validación monto cobrado |

---

*Documentado según especificación oficial SII — "Estructura de Archivo para Rol Semestral de Contribuciones de Bienes Raíces"*
