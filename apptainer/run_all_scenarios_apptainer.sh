#!/bin/bash
# Run MIMIC-Extract pipeline for all scenarios using Apptainer (no Docker)
# Requires: module load apptainer
#
# Usage: from project root (research/MIMIC_Extract), run:
#   bash apptainer/run_all_scenarios_apptainer.sh
#
# Prerequisites:
#   - Postgres running with MIMIC-III loaded (see start_postgres_apptainer.sh)
#   - MIMIC-III CSV files in data/mimiciii/1.4/
#   - Built SIF: apptainer build mimextract.sif apptainer/mimic-extract.def

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SIF_PATH="${MIMEXTRACT_SIF:-$PROJECT_ROOT/apptainer/mimextract.sif}"
MIMIC_DATA="${MIMIC_DATA_PATH:-$PROJECT_ROOT/data/mimiciii/1.4}"
CURATED_OUT="${CURATED_OUTPUT:-$PROJECT_ROOT/data/curated}"
PG_SOCKET="${PG_SOCKET_DIR:-$PROJECT_ROOT/data/pg_socket}"

# Postgres: use socket path (default) or hostname if --network host is allowed
export PGHOST="${PGHOST:-$PG_SOCKET}"
export PGPORT="${PGPORT:-5432}"
export PGDATABASE="${PGDATABASE:-mimic}"
export PGUSER="${PGUSER:-mimic}"
export PGPASSWORD="${PGPASSWORD:-mimic}"

cd "$PROJECT_ROOT"
mkdir -p "$CURATED_OUT"

if [ ! -f "$SIF_PATH" ]; then
    echo "ERROR: SIF not found at $SIF_PATH"
    echo "Build it with: apptainer build $SIF_PATH apptainer/mimic-extract.def"
    exit 1
fi

echo "=============================================="
echo "MIMIC-Extract (Apptainer): Running all scenarios"
echo "SIF: $SIF_PATH"
echo "PGHOST: $PGHOST"
echo "Output: $CURATED_OUT"
echo "=============================================="

run_scenario() {
    local name="$1"
    local out_subdir="$2"
    shift 2
    local extra_args=("$@")

    echo ""
    echo ">>> Scenario: $name"
    echo ">>> Output: $CURATED_OUT/$out_subdir/"

    export MIMIC_EXTRACT_OUTPUT_DIR="/opt/mimic-extract/data/curated/$out_subdir"
    export POP_SIZE="${POP_SIZE:-0}"
    export NUMERICS_BATCH_SIZE="${NUMERICS_BATCH_SIZE:-0}"
    export MIN_AGE="${MIN_AGE:-15}"
    export MAX_AGE="${MAX_AGE:-999}"
    export MIN_DURATION="${MIN_DURATION:-12}"
    export MAX_DURATION="${MAX_DURATION:-240}"
    export MIN_PERCENT="${MIN_PERCENT:-0}"

    for arg in "${extra_args[@]}"; do
        case "$arg" in
            POP_SIZE=*) export POP_SIZE="${arg#*=}" ;;
            MIN_AGE=*) export MIN_AGE="${arg#*=}" ;;
            MAX_AGE=*) export MAX_AGE="${arg#*=}" ;;
            MIN_DURATION=*) export MIN_DURATION="${arg#*=}" ;;
            MAX_DURATION=*) export MAX_DURATION="${arg#*=}" ;;
            MIN_PERCENT=*) export MIN_PERCENT="${arg#*=}" ;;
        esac
    done

    # Use APPTAINERENV_ prefix; PGHOST can be socket path or hostname
    export APPTAINERENV_PGHOST="$PGHOST"
    export APPTAINERENV_PGPORT="$PGPORT"
    export APPTAINERENV_PGDATABASE="$PGDATABASE"
    export APPTAINERENV_PGUSER="$PGUSER"
    export APPTAINERENV_PGPASSWORD="$PGPASSWORD"
    export APPTAINERENV_MIMIC_EXTRACT_OUTPUT_DIR="$MIMIC_EXTRACT_OUTPUT_DIR"
    export APPTAINERENV_POP_SIZE="$POP_SIZE"
    export APPTAINERENV_NUMERICS_BATCH_SIZE="$NUMERICS_BATCH_SIZE"
    export APPTAINERENV_MIN_AGE="$MIN_AGE"
    export APPTAINERENV_MAX_AGE="$MAX_AGE"
    export APPTAINERENV_MIN_DURATION="$MIN_DURATION"
    export APPTAINERENV_MAX_DURATION="$MAX_DURATION"
    export APPTAINERENV_MIN_PERCENT="$MIN_PERCENT"
    # Bind socket dir if PGHOST is a path (Unix socket, no --network host needed)
    BIND_ARGS="--bind $MIMIC_DATA:/mimic_data:ro --bind $CURATED_OUT:/opt/mimic-extract/data/curated"
    [[ "$PGHOST" == /* ]] && BIND_ARGS="$BIND_ARGS --bind $PGHOST:/tmp/pg_socket" && export APPTAINERENV_PGHOST=/tmp/pg_socket
    apptainer run $BIND_ARGS "$SIF_PATH"

    echo ">>> Completed scenario: $name"
}

reset_defaults() {
    export POP_SIZE=0
    export NUMERICS_BATCH_SIZE=0
    export MIN_AGE=15
    export MAX_AGE=999
    export MIN_DURATION=12
    export MAX_DURATION=240
    export MIN_PERCENT=0
}

# 1. pop5000
reset_defaults
run_scenario "pop5000 (medium cohort)" "pop5000" "POP_SIZE=5000"

# 2. min48hr
reset_defaults
run_scenario "min48hr (long stays only)" "min48hr" "MIN_DURATION=48"

# 3. min18age
reset_defaults
run_scenario "min18age (adults only)" "min18age" "MIN_AGE=18"

# 4. minperc5
reset_defaults
run_scenario "minperc5 (stricter missingness)" "minperc5" "MIN_PERCENT=5"

# 5-13. Age-target scenarios
reset_defaults
run_scenario "age35_range5 (ages 33-37)" "age35_range5" "MIN_AGE=33" "MAX_AGE=37"
reset_defaults
run_scenario "age35_range10 (ages 30-40)" "age35_range10" "MIN_AGE=30" "MAX_AGE=40"
reset_defaults
run_scenario "age35_range15 (ages 28-42)" "age35_range15" "MIN_AGE=28" "MAX_AGE=42"
reset_defaults
run_scenario "age45_range5 (ages 43-47)" "age45_range5" "MIN_AGE=43" "MAX_AGE=47"
reset_defaults
run_scenario "age45_range10 (ages 40-50)" "age45_range10" "MIN_AGE=40" "MAX_AGE=50"
reset_defaults
run_scenario "age45_range15 (ages 38-52)" "age45_range15" "MIN_AGE=38" "MAX_AGE=52"
reset_defaults
run_scenario "age55_range5 (ages 53-57)" "age55_range5" "MIN_AGE=53" "MAX_AGE=57"
reset_defaults
run_scenario "age55_range10 (ages 50-60)" "age55_range10" "MIN_AGE=50" "MAX_AGE=60"
reset_defaults
run_scenario "age55_range15 (ages 48-62)" "age55_range15" "MIN_AGE=48" "MAX_AGE=62"

echo ""
echo "=============================================="
echo ">>> All scenarios complete!"
echo ">>> Output: $CURATED_OUT/"
echo "=============================================="
