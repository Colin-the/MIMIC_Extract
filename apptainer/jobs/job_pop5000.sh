#!/bin/bash
set -euo pipefail

#SBATCH --job-name=mimic-pop5000
#SBATCH --mem=100G
#SBATCH --cpus-per-task=8
#SBATCH --time=96:00:00
#SBATCH --output=mimic_pop5000_%j.log

# Scenario: pop5000 (medium cohort, 5000 ICU stays)
# Output: data/curated/pop5000/
# Prerequisite: Postgres running (set PGHOST if on another node)

module load apptainer

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SLURM_SUBMIT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SIF_PATH="${MIMEXTRACT_SIF:-$PROJECT_ROOT/apptainer/mimextract.sif}"
MIMIC_DATA="${MIMIC_DATA_PATH:-$PROJECT_ROOT/data/mimiciii/1.4}"
CURATED_OUT="${CURATED_OUTPUT:-$PROJECT_ROOT/data/curated}"
PG_SOCKET="${PG_SOCKET_DIR:-$PROJECT_ROOT/data/pg_socket}"

export PGHOST="${PGHOST:-$PG_SOCKET}"
export PGPORT="${PGPORT:-5432}"
export PGDATABASE="${PGDATABASE:-mimic}"
export PGUSER="${PGUSER:-mimic}"
export PGPASSWORD="${PGPASSWORD:-mimic}"
export MIMIC_EXTRACT_OUTPUT_DIR="/opt/mimic-extract/data/curated/pop5000"
export POP_SIZE=5000
export NUMERICS_BATCH_SIZE=2500
export MIN_AGE=15
export MAX_AGE=999
export MIN_DURATION=12
export MAX_DURATION=240
export MIN_PERCENT=0

cd "$PROJECT_ROOT"
mkdir -p "$CURATED_OUT" "$PG_SOCKET"

# Use APPTAINERENV_ prefix - some clusters misinterpret -e VAR=value
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
# Use socket bind when PGHOST is a path (no --network host on Compute Canada)
BIND_ARGS="--bind $PROJECT_ROOT:/opt/mimic-extract --bind $MIMIC_DATA:/mimic_data:ro"
[[ "$PGHOST" == /* ]] && BIND_ARGS="$BIND_ARGS --bind $PGHOST:/tmp/pg_socket" && export APPTAINERENV_PGHOST=/tmp/pg_socket
apptainer run $BIND_ARGS "$SIF_PATH"

echo "Done: pop5000"
