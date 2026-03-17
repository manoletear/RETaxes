#!/usr/bin/env python3
"""
SNRI — Ingestor Catastral SII
==============================
Lee archivos Detalle Catastral SII (pipe-separated, Latin-1) y genera
SQL de inserción masiva compatible con el schema catastro.* de SNRI.

Formatos soportados:
  N   — No agrícola básico (1 fila/ROL, 19 cols reales + trailing pipe)
  NL  — No agrícola líneas (N filas/ROL, 11 cols reales + trailing pipe)
  A   — Agrícola básico (1 fila/ROL, 9 cols reales + trailing pipe)
  AL  — Agrícola suelos/construcciones (12 cols, lin=0000 → solo suelo)
  RC  — Rol cobro (fixed-width 117 chars/fila) [no implementado en esta versión]

Uso:
  python snri_ingest.py <archivo_N> <archivo_NL> <archivo_A> <archivo_AL> [opciones]

  --output FILE     Guardar SQL en archivo (default: stdout)
  --chunk N         Filas por INSERT batch (default: 500)
  --dry-run         Solo parsear y mostrar estadísticas, sin generar SQL
  --commune-code C  Forzar código de comuna (si no se detecta del archivo)
  --db-url URL      Ejecutar directamente contra Supabase/Postgres
  --schema-only     Generar solo DDL (tablas faltantes en catastro.*)

Ejemplos:
  # Generar SQL a archivo
  python snri_ingest.py BRTMPCATASN_2025_2_10108 BRTMPCATASNL_2025_2_10108 \\
         BRTMPCATASA_2025_2_10108 BRTMPCATASAL_2025_2_10108 \\
         --output panguipulli_2025_2.sql

  # Ejecutar directo contra Supabase (requiere --db-url)
  python snri_ingest.py ... --db-url "postgresql://postgres:pass@db.xxx.supabase.co:5432/postgres"

  # Solo estadísticas
  python snri_ingest.py ... --dry-run
"""

import sys
import os
import re
import argparse
import time
from datetime import datetime
from pathlib import Path
from typing import Optional


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

CHUNK_DEFAULT = 500
ENCODING = 'latin-1'

# Destinos válidos SII
DESTINOS_VALIDOS = set('ABCDEFGHILMOPQSTVWYZMKFZ')

# Condiciones especiales conocidas (+ las raras que aparecen en datos reales)
CE_CONOCIDAS = {'AL', 'CA', 'CI', 'MS', 'PZ', 'SB', 'TM'}

# Comunas SII (muestra — en producción cargar desde ref.comunas)
COMUNAS = {
    '10105': 'FUTRONO', '14155': 'LO PRADO', '14202': 'LAMPA', '15128': 'LA FLORIDA', '15132': 'LA REINA', '15161': 'LO BARNECHEA', '16131': 'LA GRANJA', '16154': 'LA PINTANA', '16164': 'LO ESPEJO', '13167': 'INDEPENDENCIA', '14158': 'HUECHURABA', '14502': 'ISLA DE MAIPO', '16110': 'LA CISTERNA', '14127': 'CONCHALI', '14157': 'ESTACION CENTRAL', '14201': 'COLINA', '14503': 'TALAGANTE', '14603': 'CURACAVI', '16165': 'EL BOSQUE', '14156': 'CERRO NAVIA', '14166': 'CERRILLOS', '14605': 'ALHUE', '16402': 'CALERA DE TANGO', '16403': 'BUIN', '10101': 'VALDIVIA', '10102': 'MARIQUINA', '10103': 'LANCO', '10104': 'LOS LAGOS', '10106': 'CORRAL', '10107': 'MAFIL', '10109': 'LA UNION', '10110': 'PAILLACO', '10111': 'RIO BUENO', '10111': 'RIO BUENO', '10112': 'LAGO RANCO', '10108': 'PANGUIPULLI', '14109': 'MAIPU', '14601': 'MELIPILLA', '14602': 'MARIA PINTO', '15151': 'MACUL', '15108': 'LAS CONDES', '13101': 'SANTIAGO',
    '8201': 'CONCEPCION', '5301': 'VALPARAISO', '5302': 'VINA DEL MAR',
    '9201': 'TEMUCO', '10201': 'OSORNO', '10301': 'PUERTO MONTT',
    '4103': 'COQUIMBO', '4101': 'LA SERENA', '13134': 'SANTIAGO OESTE',
    '15160': 'VITACURA', '15161': 'LO BARNECHEA', '14504': 'PENAFLOR', '14505': 'PADRE HURTADO', '15152': 'PENALOLEN', '16162': 'PEDRO AGUIRRE CERDA', '16404': 'PAINE', '15105': 'NUNOA',
    '15103': 'PROVIDENCIA', '15132': 'LA REINA', '16301': 'PUENTE ALTO',
}


# ══════════════════════════════════════════════════════════════════
# HELPERS SQL
# ══════════════════════════════════════════════════════════════════

def esc(v: str) -> str:
    """Escapa string para SQL. Retorna NULL si vacío."""
    v = v.strip() if v else ''
    if not v or v in ('0', '00000', '00000000000', '000000000000000'):
        return 'NULL'
    return "'" + v.replace("'", "''") + "'"


def esc_keep_zero(v: str) -> str:
    """Escapa string pero mantiene '0' como válido."""
    v = v.strip() if v else ''
    if not v:
        return 'NULL'
    return "'" + v.replace("'", "''") + "'"


def num(v: str) -> str:
    """Convierte a numérico. Retorna NULL si 0 o vacío."""
    v = v.strip() if v else ''
    if not v:
        return 'NULL'
    try:
        n = int(v)
        return str(n) if n != 0 else 'NULL'
    except ValueError:
        return 'NULL'


def num_keep_zero(v: str) -> str:
    """Convierte a numérico incluyendo 0."""
    v = v.strip() if v else ''
    try:
        return str(int(v))
    except (ValueError, TypeError):
        return 'NULL'


def num_nonzero_required(v: str) -> str:
    """Numérico — retorna NULL solo si vacío, mantiene 0 como 0."""
    return num_keep_zero(v)


def avaluo(v: str) -> str:
    """Avalúo: retorna NULL si 0, entero si positivo."""
    v = v.strip() if v else ''
    try:
        n = int(v)
        return str(n) if n > 0 else 'NULL'
    except ValueError:
        return 'NULL'


def sup_ha(v: str) -> str:
    """Superficie agrícola: raw / 100 = hectáreas con 2 decimales."""
    v = v.strip() if v else ''
    try:
        n = int(v)
        return f"{n / 100:.2f}" if n > 0 else 'NULL'
    except ValueError:
        return 'NULL'


def rol_str(cod: str, man: str, pre: str) -> str:
    """Construye string ROL. Retorna NULL si inválido."""
    c, m, p = cod.strip(), man.strip(), pre.strip()
    if not c or not m or not p:
        return 'NULL'
    if c == '00000' or m == '00000' or p == '00000':
        return 'NULL'
    return f"'{c}-{m}-{p}'"


def ce_val(v: str) -> str:
    """Condición especial — acepta cualquier valor no vacío."""
    v = v.strip() if v else ''
    return 'NULL' if not v else "'" + v.replace("'", "''") + "'"


# ══════════════════════════════════════════════════════════════════
# DETECCIÓN DE TIPO
# ══════════════════════════════════════════════════════════════════

def detect_type(filename: str, first_line: str) -> str:
    fn = filename.upper()

    # Por nombre de archivo (patrón oficial SII)
    if re.search(r'CATASNL|BRORGA2441NL|BRTMPCATASNL', fn): return 'NL'
    if re.search(r'CATASAL|BRORGA2441AL|BRTMPCATASAL', fn): return 'AL'
    if re.search(r'CATASN[^L]|BRORGA2441N[^L]|BRTMPCATASN[^L]', fn): return 'N'
    if re.search(r'CATASA[^L]|BRORGA2441A[^L]|BRTMPCATASA[^L]', fn): return 'A'
    if re.search(r'ROLCOB|ROL_COB|_RC_', fn): return 'RC'

    # Fallback por estructura de línea
    if '|' not in first_line:
        if len(first_line) >= 100: return 'RC'
        return 'UN'

    parts = [p for p in first_line.split('|')]
    # Quitar trailing vacío
    if parts and parts[-1].strip() == '':
        parts = parts[:-1]
    n = len(parts)

    if n >= 19: return 'N'
    if n == 9:  return 'A'
    if n == 12:
        # NL tiene año (4 dígitos) en col 7; AL tiene sup_suelo (grande) en col 5
        col5 = parts[4].strip() if len(parts) > 4 else ''
        col7 = parts[6].strip() if len(parts) > 6 else ''
        if re.match(r'^\d{4}$', col7): return 'NL'
        if re.match(r'^\d{6,}$', col5): return 'AL'
        return 'NL'
    if n == 11: return 'NL'

    return 'UN'


# ══════════════════════════════════════════════════════════════════
# PARSERS
# ══════════════════════════════════════════════════════════════════

def parse_lines(filepath: str) -> tuple[str, list[list[str]], dict]:
    """Lee archivo, detecta tipo, parsea todas las filas."""
    path = Path(filepath)
    if not path.exists():
        raise FileNotFoundError(f"Archivo no encontrado: {filepath}")

    with open(filepath, encoding=ENCODING, errors='replace') as f:
        raw = f.read()

    lines = [l for l in raw.splitlines() if l.strip()]
    if not lines:
        raise ValueError(f"Archivo vacío: {filepath}")

    file_type = detect_type(path.name, lines[0])

    rows = []
    errors = []

    if file_type == 'RC':
        # Fixed-width
        for i, line in enumerate(lines):
            if len(line) < 117:
                errors.append(f"línea {i+1}: largo {len(line)} < 117")
                continue
            rows.append([
                line[0:5].strip(),   # cod_comuna
                line[5:9].strip(),   # anio
                line[9:10].strip(),  # semestre
                line[10:11].strip(), # ind_aseo
                line[17:57].strip(), # direccion
                line[57:62].strip(), # manzana
                line[62:67].strip(), # predio
                line[67:68].strip(), # serie
                line[68:81].strip(), # cuota_trim
                line[81:96].strip(), # avaluo_total
                line[96:111].strip(),# avaluo_exento
                line[111:115].strip(),# anio_exencion
                line[115:116].strip(),# cod_ubicacion
                line[116:117].strip(),# destino
            ])
    else:
        for i, line in enumerate(lines):
            parts = line.split('|')
            # Quitar trailing vacío
            if parts and parts[-1].strip() == '':
                parts = parts[:-1]
            # Rellenar si faltan columnas
            while len(parts) < 12:
                parts.append('')
            rows.append(parts)

    cod_comuna = rows[0][0].strip() if rows else ''
    nombre_comuna = COMUNAS.get(cod_comuna, f'CÓDIGO {cod_comuna}')

    meta = {
        'filepath': str(path.absolute()),
        'filename': path.name,
        'file_type': file_type,
        'total_rows': len(rows),
        'cod_comuna': cod_comuna,
        'nombre_comuna': nombre_comuna,
        'errors': errors,
    }

    return file_type, rows, meta


# ══════════════════════════════════════════════════════════════════
# GENERADORES SQL POR TIPO
# ══════════════════════════════════════════════════════════════════

def sql_n(rows: list, chunk: int) -> tuple[str, dict]:
    """No agrícola básico → catastro.predios"""
    stats = {'total': 0, 'con_bc': 0, 'con_padre': 0, 'exentos': 0, 'contrib_cero': 0}
    batches = []

    for i in range(0, len(rows), chunk):
        batch = rows[i:i+chunk]
        vals = []
        for r in batch:
            if len(r) < 16: continue
            stats['total'] += 1
            if r[8].strip() != '00000': stats['con_bc'] += 1
            if len(r) > 16 and r[16].strip() != '00000': stats['con_padre'] += 1
            if r[7].strip() == r[4].strip(): stats['exentos'] += 1
            if r[5].strip() == '0000000000000': stats['contrib_cero'] += 1

            rol = f"'{r[0].strip()}-{r[1].strip()}-{r[2].strip()}'"
            bc1 = rol_str(r[8], r[9], r[10]) if len(r) > 10 else 'NULL'
            bc2 = rol_str(r[11], r[12], r[13]) if len(r) > 13 else 'NULL'
            rp  = rol_str(r[16], r[17], r[18]) if len(r) > 18 else 'NULL'

            vals.append(
                f"({rol},{esc(r[0])},{esc(r[1])},{esc(r[2])},"
                f"{esc(r[3])},{avaluo(r[4])},{num(r[5])},{esc_keep_zero(r[6])},"
                f"{avaluo(r[7])},{bc1},{bc2},"
                f"{num(r[14])},{esc_keep_zero(r[15])},{rp},"
                f"'no_agricola','SII_CSV')"
            )

        if vals:
            batches.append(
                "INSERT INTO catastro.predios (\n"
                "  rol, codigo_comuna, manzana, predio, direccion,\n"
                "  avaluo_total_vigente, contribucion_semestre, destino_sii,\n"
                "  avaluo_total_exento, bc1_rol, bc2_rol,\n"
                "  sup_terreno_m2, cod_ubicacion, rol_padre,\n"
                "  serie_predio, fuente_datos\n"
                ") VALUES\n" +
                ',\n'.join(vals) +
                "\nON CONFLICT (rol) DO UPDATE SET\n"
                "  avaluo_total_vigente = EXCLUDED.avaluo_total_vigente,\n"
                "  contribucion_semestre = EXCLUDED.contribucion_semestre,\n"
                "  destino_sii          = EXCLUDED.destino_sii,\n"
                "  avaluo_total_exento  = EXCLUDED.avaluo_total_exento,\n"
                "  sup_terreno_m2       = EXCLUDED.sup_terreno_m2,\n"
                "  cod_ubicacion        = EXCLUDED.cod_ubicacion,\n"
                "  fuente_datos         = 'SII_CSV',\n"
                "  fecha_actualizacion  = now();"
            )

    return '\n\n'.join(batches), stats


def sql_nl(rows: list, chunk: int) -> tuple[str, dict]:
    """No agrícola líneas → catastro.construcciones"""
    stats = {'total': 0, 'por_ce': {}, 'materiales': {}}
    batches = []

    for i in range(0, len(rows), chunk):
        batch = rows[i:i+chunk]
        vals = []
        for r in batch:
            if len(r) < 11: continue
            stats['total'] += 1
            mat = r[4].strip()
            ce  = r[9].strip()
            stats['materiales'][mat] = stats['materiales'].get(mat, 0) + 1
            if ce: stats['por_ce'][ce] = stats['por_ce'].get(ce, 0) + 1

            rol = f"'{r[0].strip()}-{r[1].strip()}-{r[2].strip()}'"
            vals.append(
                f"({rol},{num_keep_zero(r[3])},{esc(mat)},"
                f"{num_keep_zero(r[5])},{num(r[6])},"
                f"{num(r[7])},{esc_keep_zero(r[8])},{ce_val(ce)},"
                f"{num_keep_zero(r[10])},'SII_CSV')"
            )

        if vals:
            batches.append(
                "INSERT INTO catastro.construcciones (\n"
                "  rol, numero_construccion, material_codigo,\n"
                "  calidad_codigo, anio_construccion,\n"
                "  sup_total_m2, destino_construccion, condicion_especial,\n"
                "  numero_pisos, fuente_datos\n"
                ") VALUES\n" +
                ',\n'.join(vals) +
                "\nON CONFLICT (rol, numero_construccion) DO UPDATE SET\n"
                "  material_codigo       = EXCLUDED.material_codigo,\n"
                "  calidad_codigo        = EXCLUDED.calidad_codigo,\n"
                "  anio_construccion     = EXCLUDED.anio_construccion,\n"
                "  sup_total_m2          = EXCLUDED.sup_total_m2,\n"
                "  destino_construccion  = EXCLUDED.destino_construccion,\n"
                "  condicion_especial    = EXCLUDED.condicion_especial,\n"
                "  numero_pisos          = EXCLUDED.numero_pisos;"
            )

    return '\n\n'.join(batches), stats


def sql_a(rows: list, chunk: int) -> tuple[str, dict]:
    """Agrícola básico → catastro.predios"""
    stats = {'total': 0, 'rural': 0, 'urbano': 0, 'exentos': 0}
    batches = []

    for i in range(0, len(rows), chunk):
        batch = rows[i:i+chunk]
        vals = []
        for r in batch:
            if len(r) < 8: continue
            stats['total'] += 1
            ub = r[8].strip() if len(r) > 8 else ''
            if ub == 'R': stats['rural'] += 1
            elif ub == 'U': stats['urbano'] += 1
            if int(r[7].strip() or 0) == int(r[4].strip() or 0) and int(r[4].strip() or 0) > 0:
                stats['exentos'] += 1

            rol = f"'{r[0].strip()}-{r[1].strip()}-{r[2].strip()}'"
            vals.append(
                f"({rol},{esc(r[0])},{esc(r[1])},{esc(r[2])},"
                f"{esc(r[3])},{avaluo(r[4])},{num(r[5])},"
                f"{esc_keep_zero(r[6])},{avaluo(r[7])},"
                f"{esc_keep_zero(ub)},"
                f"'agricola','SII_CSV')"
            )

        if vals:
            batches.append(
                "INSERT INTO catastro.predios (\n"
                "  rol, codigo_comuna, manzana, predio, direccion,\n"
                "  avaluo_total_vigente, contribucion_semestre,\n"
                "  destino_sii, avaluo_total_exento,\n"
                "  cod_ubicacion, serie_predio, fuente_datos\n"
                ") VALUES\n" +
                ',\n'.join(vals) +
                "\nON CONFLICT (rol) DO UPDATE SET\n"
                "  avaluo_total_vigente = EXCLUDED.avaluo_total_vigente,\n"
                "  contribucion_semestre = EXCLUDED.contribucion_semestre,\n"
                "  destino_sii          = EXCLUDED.destino_sii,\n"
                "  avaluo_total_exento  = EXCLUDED.avaluo_total_exento,\n"
                "  cod_ubicacion        = EXCLUDED.cod_ubicacion,\n"
                "  fuente_datos         = 'SII_CSV',\n"
                "  fecha_actualizacion  = now();"
            )

    return '\n\n'.join(batches), stats


def sql_al(rows: list, chunk: int) -> tuple[str, dict]:
    """Agrícola suelos + construcciones → tablas separadas"""
    soil_rows  = [r for r in rows if len(r) >= 5 and (r[5].strip() == '0000' or r[5].strip() == '')]
    const_rows = [r for r in rows if len(r) >= 6 and r[5].strip() not in ('0000', '')]

    stats = {
        'total': len(rows),
        'solo_suelo': len(soil_rows),
        'con_construccion': len(const_rows),
        'tipos_suelo': {},
    }
    for r in soil_rows:
        s = r[3].strip()
        stats['tipos_suelo'][s] = stats['tipos_suelo'].get(s, 0) + 1

    parts = []

    # — Suelos agrícolas
    if soil_rows:
        batches = []
        for i in range(0, len(soil_rows), chunk):
            batch = soil_rows[i:i+chunk]
            vals = []
            for r in batch:
                if len(r) < 5: continue
                rol = f"'{r[0].strip()}-{r[1].strip()}-{r[2].strip()}'"
                vals.append(
                    f"({rol},{esc(r[3])},{sup_ha(r[4])},'SII_CSV')"
                )
            if vals:
                batches.append(
                    "INSERT INTO catastro.suelos_agricolas (\n"
                    "  rol, cod_suelo, sup_ha, fuente_datos\n"
                    ") VALUES\n" +
                    ',\n'.join(vals) +
                    "\nON CONFLICT (rol, cod_suelo) DO UPDATE SET\n"
                    "  sup_ha = EXCLUDED.sup_ha;"
                )
        parts.append('\n\n'.join(batches))

    # — Construcciones agrícolas
    if const_rows:
        batches = []
        for i in range(0, len(const_rows), chunk):
            batch = const_rows[i:i+chunk]
            vals = []
            for r in batch:
                if len(r) < 10: continue
                rol = f"'{r[0].strip()}-{r[1].strip()}-{r[2].strip()}'"
                vals.append(
                    f"({rol},{num_keep_zero(r[5])},{esc(r[6])},"
                    f"{num_keep_zero(r[7])},{num(r[8])},"
                    f"{esc_keep_zero(r[9])},{ce_val(r[10])},'SII_CSV')"
                )
            if vals:
                batches.append(
                    "INSERT INTO catastro.construcciones (\n"
                    "  rol, numero_construccion, material_codigo,\n"
                    "  calidad_codigo, sup_total_m2,\n"
                    "  destino_construccion, condicion_especial, fuente_datos\n"
                    ") VALUES\n" +
                    ',\n'.join(vals) +
                    "\nON CONFLICT (rol, numero_construccion) DO NOTHING;"
                )
        parts.append('\n\n'.join(batches))

    return '\n\n'.join(parts), stats


# ══════════════════════════════════════════════════════════════════
# DDL ADICIONAL (tablas que pueden no estar en el schema base)
# ══════════════════════════════════════════════════════════════════

DDL_SUELOS = """
-- Tabla auxiliar para suelos agrícolas (si no existe)
CREATE TABLE IF NOT EXISTS catastro.suelos_agricolas (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rol         text NOT NULL,
    cod_suelo   text NOT NULL,
    sup_ha      numeric(12,2),
    fuente_datos text,
    created_at  timestamptz DEFAULT now(),
    CONSTRAINT fk_suelos_predio FOREIGN KEY (rol)
        REFERENCES catastro.predios(rol) ON DELETE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_suelos_rol_cod
    ON catastro.suelos_agricolas(rol, cod_suelo);
"""


# ══════════════════════════════════════════════════════════════════
# REGISTRO EN catastro.importaciones
# ══════════════════════════════════════════════════════════════════


def sql_rc(rows: list, chunk: int) -> tuple[str, dict]:
    """Rol Cobro fixed-width → catastro.contribuciones_historial"""
    stats = {'total': 0, 'con_aseo': 0, 'exentos': 0, 'agricola': 0}
    batches = []

    for i in range(0, len(rows), chunk):
        batch = rows[i:i+chunk]
        vals = []
        for r in batch:
            if len(r) < 14: continue
            stats['total'] += 1
            if r[3] == 'A': stats['con_aseo'] += 1
            if r[7] == 'A': stats['agricola'] += 1
            try:
                if int(r[10] or 0) >= int(r[9] or 0) and int(r[9] or 0) > 0:
                    stats['exentos'] += 1
            except (ValueError, TypeError):
                pass

            # ROL: cod_comuna-manzana-predio (pos 1-5, 58-62, 63-67 → index 0, 5, 6)
            cod = r[0].strip()
            man = r[5].strip()
            pre = r[6].strip()
            rol = f"'{cod}-{man}-{pre}'" if cod and man and pre else 'NULL'

            vals.append(
                f"({rol},{esc(cod)},{esc(man)},{esc(pre)},"
                f"{num_keep_zero(r[1])},{num_keep_zero(r[2])},"
                f"{esc_keep_zero(r[7])},"
                f"{num(r[8])},{avaluo(r[9])},{avaluo(r[10])},"
                f"{num_keep_zero(r[11])},{esc_keep_zero(r[12])},{esc_keep_zero(r[13])},"
                f"{'true' if r[3]=='A' else 'false'},'SII_RC')"
            )

        if vals:
            batches.append(
                "INSERT INTO catastro.contribuciones_historial (\n"
                "  rol, codigo_comuna, manzana, predio,\n"
                "  anio, semestre, serie_predio,\n"
                "  cuota_trimestral, avaluo_total, avaluo_exento,\n"
                "  anio_termino_exencion, cod_ubicacion, destino,\n"
                "  incluye_aseo, fuente_datos\n"
                ") VALUES\n" +
                ',\n'.join(vals) +
                "\nON CONFLICT (rol, anio, semestre) DO UPDATE SET\n"
                "  cuota_trimestral = EXCLUDED.cuota_trimestral,\n"
                "  avaluo_total     = EXCLUDED.avaluo_total,\n"
                "  avaluo_exento    = EXCLUDED.avaluo_exento;"
            )

    return '\n\n'.join(batches), stats

def sql_importacion(meta_list: list, stats_map: dict) -> str:
    ts = datetime.utcnow().isoformat()
    vals = []
    for m in meta_list:
        ft   = m['file_type']
        s    = stats_map.get(ft, {})
        total = s.get('total', m['total_rows'])
        vals.append(
            f"('{m['cod_comuna']}', {esc(m['nombre_comuna'])}, "
            f"{esc(m['filename'])}, {esc(ft)}, {total}, "
            f"'{ts}', 'completado', NULL)"
        )
    return (
        "INSERT INTO catastro.importaciones\n"
        "  (codigo_comuna, nombre_comuna, archivo_fuente, tipo_archivo,\n"
        "   total_registros, fecha_importacion, estado, error_msg)\n"
        "VALUES\n" + ',\n'.join(vals) + ";"
    )


# ══════════════════════════════════════════════════════════════════
# HEADER / FOOTER SQL
# ══════════════════════════════════════════════════════════════════

def sql_header(meta_list: list) -> str:
    comunas = list({m['cod_comuna']: m['nombre_comuna'] for m in meta_list}.items())
    commune_str = ', '.join(f"{c[0]} {c[1]}" for c in comunas)
    archivos = '\n--   '.join(m['filename'] for m in meta_list)
    return f"""-- ══════════════════════════════════════════════════════════════
-- SNRI — Ingestión Catastral SII
-- Generado : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
-- Comuna(s): {commune_str}
-- Archivos :
--   {archivos}
-- ══════════════════════════════════════════════════════════════

SET search_path TO catastro, public;
BEGIN;
"""


def sql_footer() -> str:
    return "\nCOMMIT;\n-- ══ FIN DE INGESTIÓN ══\n"


# ══════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════

def print_stats(meta_list: list, stats_map: dict):
    print("\n" + "═" * 55)
    print("  SNRI CATASTRAL — RESUMEN DE INGESTIÓN")
    print("═" * 55)
    for m in meta_list:
        ft = m['file_type']
        s  = stats_map.get(ft, {})
        print(f"\n  [{ft}] {m['filename']}")
        print(f"      Comuna  : {m['cod_comuna']} — {m['nombre_comuna']}")
        print(f"      Filas   : {m['total_rows']:,}")
        if ft == 'N':
            print(f"      Con BC  : {s.get('con_bc',0):,}")
            print(f"      Con padre: {s.get('con_padre',0):,}")
            print(f"      Exentos : {s.get('exentos',0):,}")
            print(f"      Contrib=0: {s.get('contrib_cero',0):,}")
        elif ft == 'NL':
            mats = s.get('materiales', {})
            top3 = sorted(mats.items(), key=lambda x: -x[1])[:3]
            print(f"      Top mat : {', '.join(f'{k}({v})' for k,v in top3)}")
            ces = s.get('por_ce', {})
            if ces:
                print(f"      CEs     : {dict(ces)}")
        elif ft == 'A':
            print(f"      Rural   : {s.get('rural',0):,}")
            print(f"      Urbano  : {s.get('urbano',0):,}")
        elif ft == 'AL':
            print(f"      Solo suelo  : {s.get('solo_suelo',0):,}")
            print(f"      Con construc: {s.get('con_construccion',0):,}")
        if m['errors']:
            print(f"      ⚠ Errores  : {len(m['errors'])}")
    print("\n" + "═" * 55 + "\n")


def run(args):
    t0 = time.time()
    file_args = [args.n_file, args.nl_file, args.a_file, args.al_file]
    file_args = [f for f in file_args if f]  # omitir None

    if not file_args:
        print("ERROR: debes indicar al menos un archivo.")
        sys.exit(1)

    # — Parsear todos los archivos
    parsed = []
    for filepath in file_args:
        try:
            ftype, rows, meta = parse_lines(filepath)
            parsed.append((ftype, rows, meta))
            print(f"✓ {meta['filename']} [{ftype}] — {meta['total_rows']:,} filas — {meta['nombre_comuna']}")
        except Exception as e:
            print(f"✗ {filepath}: {e}")
            if not args.ignore_errors:
                sys.exit(1)

    if not parsed:
        print("Sin archivos válidos.")
        sys.exit(1)

    if args.dry_run:
        meta_list = [m for _, _, m in parsed]
        stats_map = {}
        for ft, rows, m in parsed:
            if ft == 'N':
                _, s = sql_n(rows, 999999)
            elif ft == 'NL':
                _, s = sql_nl(rows, 999999)
            elif ft == 'A':
                _, s = sql_a(rows, 999999)
            elif ft == 'AL':
                _, s = sql_al(rows, 999999)
            elif ft == 'RC':
                _, s = sql_rc(rows, 999999)
            else:
                s = {'total': m['total_rows']}
            stats_map[ft] = s
        print_stats(meta_list, stats_map)
        print(f"  Tiempo: {time.time()-t0:.2f}s")
        return

    # — Generar SQL
    sql_parts = []
    meta_list  = [m for _, _, m in parsed]
    stats_map  = {}

    sql_parts.append(sql_header(meta_list))

    # DDL auxiliar (suelos_agricolas) si hay archivos AL
    has_al = any(ft == 'AL' for ft, _, _ in parsed)
    if has_al:
        sql_parts.append("-- DDL auxiliar\n" + DDL_SUELOS)

    # — Generar por tipo
    for ftype, rows, meta in parsed:
        sql_parts.append(
            f"\n-- ─────────────────────────────────────────────────\n"
            f"-- {ftype}: {meta['filename']}  |  {meta['nombre_comuna']}\n"
            f"-- {meta['total_rows']:,} filas\n"
            f"-- ─────────────────────────────────────────────────"
        )
        chunk = args.chunk

        if ftype == 'N':
            body, stats = sql_n(rows, chunk)
        elif ftype == 'NL':
            body, stats = sql_nl(rows, chunk)
        elif ftype == 'A':
            body, stats = sql_a(rows, chunk)
        elif ftype == 'AL':
            body, stats = sql_al(rows, chunk)
        elif ftype == 'RC':
            body, stats = sql_rc(rows, chunk)
        else:
            sql_parts.append(f"-- TIPO {ftype} no implementado\n")
            stats = {}

        stats_map[ftype] = stats
        sql_parts.append(body)

    # — Registro importación
    sql_parts.append(
        "\n-- ─────────────────────────────────────────────────\n"
        "-- Registro en catastro.importaciones\n"
        "-- ─────────────────────────────────────────────────"
    )
    sql_parts.append(sql_importacion(meta_list, stats_map))
    sql_parts.append(sql_footer())

    full_sql = '\n'.join(sql_parts)

    # — Salida
    if args.db_url:
        try:
            import psycopg2
            conn = psycopg2.connect(args.db_url)
            cur = conn.cursor()
            print(f"⚡ Ejecutando contra BD...")
            cur.execute(full_sql)
            conn.commit()
            cur.close()
            conn.close()
            print("✓ Ingestión directa completada.")
        except Exception as e:
            print(f"✗ Error BD: {e}")
            sys.exit(1)
    elif args.output:
        out_path = Path(args.output)
        out_path.write_text(full_sql, encoding='utf-8')
        size_kb = out_path.stat().st_size / 1024
        print(f"✓ SQL guardado: {args.output} ({size_kb:.0f} KB)")
    else:
        sys.stdout.write(full_sql)

    print_stats(meta_list, stats_map)
    print(f"  Tiempo total: {time.time()-t0:.2f}s")


# ══════════════════════════════════════════════════════════════════
# CLI
# ══════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='SNRI — Ingestor Catastral SII',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument('n_file',  nargs='?', help='Archivo N  (no agrícola básico)')
    parser.add_argument('nl_file', nargs='?', help='Archivo NL (no agrícola líneas)')
    parser.add_argument('a_file',  nargs='?', help='Archivo A  (agrícola básico)')
    parser.add_argument('al_file', nargs='?', help='Archivo AL (agrícola suelos/const)')

    parser.add_argument('--output',   '-o', help='Archivo SQL de salida')
    parser.add_argument('--chunk',    '-c', type=int, default=CHUNK_DEFAULT, help=f'Filas por batch INSERT (default {CHUNK_DEFAULT})')
    parser.add_argument('--dry-run',  action='store_true', help='Solo estadísticas, sin SQL')
    parser.add_argument('--db-url',   help='DSN Postgres para ejecución directa')
    parser.add_argument('--ignore-errors', action='store_true', help='Continuar aunque un archivo falle')

    args = parser.parse_args()
    run(args)
