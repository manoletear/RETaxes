#!/bin/bash
# ══════════════════════════════════════════════════════════════
# SNRI — Batch Ingest por Región
# Procesa todas las comunas de una región:
#   1. Descomprime ZIP (Detalle Catastral) → 4 archivos N/NL/A/AL
#   2. Corre snri_ingest.py → genera SQL catastral
#   3. Corre snri_ingest.py con Rol de Cobro → genera SQL rolcob
#   4. Guarda en database/seeds/
# ══════════════════════════════════════════════════════════════

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMUNAS_DIR="$REPO_DIR/Comunas Chile"
SEEDS_DIR="$REPO_DIR/database/seeds"
INGEST="$REPO_DIR/tools/snri_ingest.py"
TMPDIR=$(mktemp -d)

REGION_FILTER="${1:-}"  # Filtrar por región (parcial, ej: "ARICA")

# Contadores
TOTAL=0
OK=0
FAIL=0
SKIP=0

cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

normalize_name() {
    # ARICA → arica, ALTO DEL CARMEN → alto_del_carmen
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/ /_/g' | sed "s/'//g" | sed 's/á/a/g;s/é/e/g;s/í/i/g;s/ó/o/g;s/ú/u/g;s/ñ/n/g;s/ü/u/g'
}

echo "══════════════════════════════════════════════════════════════"
echo "  SNRI — Batch Ingest"
echo "  Región: ${REGION_FILTER:-TODAS}"
echo "══════════════════════════════════════════════════════════════"
echo ""

# Listar todos los ZIPs de Detalle Catastral
cd "$COMUNAS_DIR"
for ZIP in *"Detalle Catastral.zip"; do
    [ -f "$ZIP" ] || continue

    # Extraer región y comuna del nombre
    # Formato: "REGION DE X - COMUNA - Detalle Catastral.zip"
    REGION=$(echo "$ZIP" | sed 's/ - .*//')
    COMUNA=$(echo "$ZIP" | sed 's/^[^-]*- //' | sed 's/ - Detalle Catastral.zip//')

    # Filtrar por región si se especificó
    if [ -n "$REGION_FILTER" ]; then
        if ! echo "$REGION" | grep -qi "$REGION_FILTER"; then
            continue
        fi
    fi

    TOTAL=$((TOTAL + 1))
    NORM_NAME=$(normalize_name "$COMUNA")
    SEED_FILE="$SEEDS_DIR/${NORM_NAME}_2025_2.sql"
    ROLCOB_FILE="$SEEDS_DIR/${NORM_NAME}_rolcob_2025_2.sql"

    # Skip si ya existe
    if [ -f "$SEED_FILE" ] && [ -f "$ROLCOB_FILE" ]; then
        echo "⏭  $COMUNA — ya procesada"
        SKIP=$((SKIP + 1))
        continue
    fi

    echo -n "▶ $COMUNA ($REGION)... "

    # Limpiar temp
    rm -rf "$TMPDIR"/*

    # 1. Descomprimir ZIP
    if ! unzip -o -d "$TMPDIR" "$ZIP" > /dev/null 2>&1; then
        echo "✗ Error descomprimiendo ZIP"
        FAIL=$((FAIL + 1))
        continue
    fi

    # 2. Encontrar archivos N, NL, A, AL (solo no-vacíos)
    N_FILE=$(ls "$TMPDIR"/BRTMPCATASN_* 2>/dev/null | grep -v 'NL' | head -1)
    NL_FILE=$(ls "$TMPDIR"/BRTMPCATASNL_* 2>/dev/null | head -1)
    A_FILE=$(ls "$TMPDIR"/BRTMPCATASA_* 2>/dev/null | grep -v 'AL' | head -1)
    AL_FILE=$(ls "$TMPDIR"/BRTMPCATASAL_* 2>/dev/null | head -1)

    # Filtrar archivos vacíos (comunas urbanas sin datos agrícolas)
    [ -n "$N_FILE" ] && [ ! -s "$N_FILE" ] && N_FILE=""
    [ -n "$NL_FILE" ] && [ ! -s "$NL_FILE" ] && NL_FILE=""
    [ -n "$A_FILE" ] && [ ! -s "$A_FILE" ] && A_FILE=""
    [ -n "$AL_FILE" ] && [ ! -s "$AL_FILE" ] && AL_FILE=""

    # 3. Generar SQL catastral
    if [ -n "$N_FILE" ] || [ -n "$A_FILE" ]; then
        ARGS=""
        [ -n "$N_FILE" ] && ARGS="$ARGS $N_FILE"
        [ -n "$NL_FILE" ] && ARGS="$ARGS $NL_FILE"
        [ -n "$A_FILE" ] && ARGS="$ARGS $A_FILE"
        [ -n "$AL_FILE" ] && ARGS="$ARGS $AL_FILE"

        if ! python3 "$INGEST" $ARGS --output "$SEED_FILE" > /dev/null 2>&1; then
            echo "✗ Error en ingest catastral"
            FAIL=$((FAIL + 1))
            continue
        fi
    fi

    # 4. Procesar Rol de Cobro
    RC_TXT="$COMUNAS_DIR/$REGION - $COMUNA - Rol de cobro.TXT"
    if [ -f "$RC_TXT" ]; then
        if ! python3 "$INGEST" "$RC_TXT" --output "$ROLCOB_FILE" > /dev/null 2>&1; then
            echo "⚠ Catastral OK, Rol de Cobro falló"
            OK=$((OK + 1))
            continue
        fi
    else
        echo -n "(sin Rol de Cobro) "
    fi

    # Verificar tamaño
    SIZE_CAT=$(du -h "$SEED_FILE" 2>/dev/null | cut -f1)
    SIZE_RC=$(du -h "$ROLCOB_FILE" 2>/dev/null | cut -f1)
    echo "✓ catastro=${SIZE_CAT:-0} rolcob=${SIZE_RC:-0}"
    OK=$((OK + 1))

done

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  RESUMEN: $OK OK / $SKIP skip / $FAIL fail / $TOTAL total"
echo "══════════════════════════════════════════════════════════════"
