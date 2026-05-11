#!/bin/bash
set -euo pipefail

#SBATCH --job-name=mimic-setup
#SBATCH --mem=120G
#SBATCH --cpus-per-task=8
#SBATCH --time=24:00:00
#SBATCH --output=mimic_setup_%j.log

# One-time setup: Start Postgres, load MIMIC-III data, build concepts.
#
# Submit from project root:
#   cd /path/to/MIMIC_Extract
#   module load postgresql apptainer
#   sbatch apptainer/jobs/job_setup_postgres.sh
#
# If you hit "Disk quota exceeded", use a path with more space:
#   POSTGRES_DATA_DIR=$SCRATCH/mimic_postgres sbatch apptainer/jobs/job_setup_postgres.sh
#
# If you hit "Transport endpoint is not connected", use native Postgres (no container/FUSE):
#   rm -rf $SCRATCH/mimic_postgres $SCRATCH/mimic_pg_socket  # clean first when switching
#   USE_NATIVE_POSTGRES=1 POSTGRES_DATA_DIR=$SCRATCH/mimic_postgres PG_SOCKET_DIR=$SCRATCH/mimic_pg_socket sbatch apptainer/jobs/job_setup_postgres.sh

module load apptainer
module load postgresql 2>/dev/null || true

# Use SLURM_SUBMIT_DIR when in a job (submit from project root: cd MIMIC_Extract && sbatch ...)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SLURM_SUBMIT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
POSTGRES_DATA="${POSTGRES_DATA_DIR:-$PROJECT_ROOT/data/postgres_data}"
PG_SOCKET="${PG_SOCKET_DIR:-$PROJECT_ROOT/data/pg_socket}"
SIF_PATH="${MIMEXTRACT_SIF:-$PROJECT_ROOT/apptainer/mimextract.sif}"
POSTGRES_SIF="${POSTGRES_SIF:-$PROJECT_ROOT/apptainer/postgres.sif}"
MIMIC_DATA="${MIMIC_DATA_PATH:-$PROJECT_ROOT/data/mimiciii/1.4}"
CURATED_OUT="${CURATED_OUTPUT:-$PROJECT_ROOT/data/curated}"

cd "$PROJECT_ROOT"
mkdir -p "$POSTGRES_DATA" "$PG_SOCKET" "$CURATED_OUT"

# Use Unix socket (--network host not allowed on Compute Canada / unprivileged)
export PGHOST="$PG_SOCKET"
export PGPORT=5432
export PGDATABASE=mimic
export PGUSER=mimic
export PGPASSWORD=mimic

USE_NATIVE="${USE_NATIVE_POSTGRES:-0}"
if [ "$USE_NATIVE" = "1" ] && command -v pg_ctl >/dev/null 2>&1; then
  # Native Postgres - avoids "Transport endpoint is not connected" (no container/FUSE)
  echo "Using native Postgres (no container)..."
  if [ ! -f "$POSTGRES_DATA/PG_VERSION" ]; then
    # Fresh init required when switching from container (or first run)
    echo "Initializing Postgres data directory..."
    initdb -D "$POSTGRES_DATA" --auth=trust
    echo "unix_socket_directories = '$PG_SOCKET'" >> "$POSTGRES_DATA/postgresql.conf"
    echo "autovacuum = off" >> "$POSTGRES_DATA/postgresql.conf"
    echo "max_parallel_workers = 0" >> "$POSTGRES_DATA/postgresql.conf"
    echo "max_parallel_workers_per_gather = 0" >> "$POSTGRES_DATA/postgresql.conf"
  fi
  pg_ctl -D "$POSTGRES_DATA" -l "$POSTGRES_DATA/logfile" -o "-c unix_socket_directories=$PG_SOCKET -c autovacuum=off -c max_parallel_workers=0 -c max_parallel_workers_per_gather=0" start
  PGPID=$(head -1 "$POSTGRES_DATA/postmaster.pid" 2>/dev/null) || PGPID=0
  sleep 10
  until psql -h "$PG_SOCKET" -U "$USER" -d postgres -c '\q' 2>/dev/null; do
    echo "Waiting for Postgres..."
    sleep 5
  done
  psql -h "$PG_SOCKET" -U "$USER" -d postgres -tc "SELECT 1 FROM pg_roles WHERE rolname='mimic'" 2>/dev/null | grep -q 1 || \
    psql -h "$PG_SOCKET" -U "$USER" -d postgres -c "CREATE USER mimic WITH PASSWORD 'mimic' SUPERUSER"
  psql -h "$PG_SOCKET" -U "$USER" -d postgres -tc "SELECT 1 FROM pg_database WHERE datname='mimic'" 2>/dev/null | grep -q 1 || \
    psql -h "$PG_SOCKET" -U "$USER" -d postgres -c "CREATE DATABASE mimic OWNER mimic"
  echo "Postgres ready (native)."
  # mimic-extract needs PGHOST as socket path inside container - bind mount
  APPTAINER_PGHOST="/tmp/pg_socket"
else
  # Container Postgres
  if [ ! -f "$POSTGRES_SIF" ]; then
    echo "Building Postgres SIF (one-time, ~2 min)..."
    apptainer build "$POSTGRES_SIF" docker://postgres:15
  fi
  LOCAL_SIF_DIR=""
  if [ -n "${SLURM_TMPDIR:-}" ] && [ -d "$SLURM_TMPDIR" ]; then
    LOCAL_SIF_DIR="$SLURM_TMPDIR"
  elif [ -n "${SCRATCH:-}" ] && [ -n "${SLURM_JOB_ID:-}" ]; then
    LOCAL_SIF_DIR="$SCRATCH/sif_$SLURM_JOB_ID"
    mkdir -p "$LOCAL_SIF_DIR"
  fi
  if [ -n "$LOCAL_SIF_DIR" ]; then
    echo "Copying SIFs to $LOCAL_SIF_DIR..."
    [ -f "$POSTGRES_SIF" ] && cp -f "$POSTGRES_SIF" "$LOCAL_SIF_DIR/postgres.sif" && POSTGRES_SIF="$LOCAL_SIF_DIR/postgres.sif"
    [ -f "$SIF_PATH" ] && cp -f "$SIF_PATH" "$LOCAL_SIF_DIR/mimextract.sif" && SIF_PATH="$LOCAL_SIF_DIR/mimextract.sif"
  fi
  export APPTAINERENV_POSTGRES_USER=mimic
  export APPTAINERENV_POSTGRES_PASSWORD=mimic
  export APPTAINERENV_POSTGRES_DB=mimic
  echo "Starting Postgres (Unix socket at $PG_SOCKET)..."
  apptainer run \
    --bind "$POSTGRES_DATA:/var/lib/postgresql/data" \
    --bind "$PG_SOCKET:/tmp/pg_socket" \
    "$POSTGRES_SIF" postgres \
    -c unix_socket_directories=/tmp/pg_socket \
    -c autovacuum=off \
    -c max_parallel_workers=0 \
    -c max_parallel_workers_per_gather=0 &
  PGPID=$!
  sleep 30
  until apptainer exec --bind "$PG_SOCKET:/tmp/pg_socket" "$POSTGRES_SIF" \
    psql "host=/tmp/pg_socket user=mimic dbname=postgres" -c '\q' 2>/dev/null; do
    echo "Waiting for Postgres..."
    sleep 5
  done
  apptainer exec --bind "$PG_SOCKET:/tmp/pg_socket" "$POSTGRES_SIF" \
    psql "host=/tmp/pg_socket user=mimic dbname=postgres" -tc "SELECT 1 FROM pg_database WHERE datname='mimic'" 2>/dev/null | grep -q 1 || \
  apptainer exec --bind "$PG_SOCKET:/tmp/pg_socket" "$POSTGRES_SIF" \
    psql "host=/tmp/pg_socket user=mimic dbname=postgres" -c "CREATE DATABASE mimic"
  echo "Restarting Postgres for fresh mount before data load..."
  kill $PGPID 2>/dev/null || true
  wait $PGPID 2>/dev/null || true
  sleep 3
  apptainer run \
    --bind "$POSTGRES_DATA:/var/lib/postgresql/data" \
    --bind "$PG_SOCKET:/tmp/pg_socket" \
    "$POSTGRES_SIF" postgres \
    -c unix_socket_directories=/tmp/pg_socket \
    -c autovacuum=off \
    -c max_parallel_workers=0 \
    -c max_parallel_workers_per_gather=0 &
  PGPID=$!
  sleep 15
  until apptainer exec --bind "$PG_SOCKET:/tmp/pg_socket" "$POSTGRES_SIF" \
    psql "host=/tmp/pg_socket user=mimic dbname=postgres" -c '\q' 2>/dev/null; do
    echo "Waiting for Postgres..."
    sleep 5
  done
  echo "Postgres ready (container)."
  APPTAINER_PGHOST="/tmp/pg_socket"
fi

# Run one scenario to load data and build concepts (pop5000 is fast)
echo "Loading MIMIC data and building concepts (via pop5000 extraction)..."
export MIMIC_EXTRACT_OUTPUT_DIR="/opt/mimic-extract/data/curated/pop5000"
export POP_SIZE=5000
export NUMERICS_BATCH_SIZE=0
export MIN_AGE=15
export MAX_AGE=999
export MIN_DURATION=12
export MAX_DURATION=240
export MIN_PERCENT=0

# Use APPTAINERENV_ prefix; PGHOST is socket dir inside container (bind mount)
export APPTAINERENV_PGHOST="${APPTAINER_PGHOST:-/tmp/pg_socket}"
export APPTAINERENV_PGPORT=5432
export APPTAINERENV_PGDATABASE=mimic
export APPTAINERENV_PGUSER=mimic
export APPTAINERENV_PGPASSWORD=mimic
export APPTAINERENV_MIMIC_EXTRACT_OUTPUT_DIR="/opt/mimic-extract/data/curated/pop5000"
export APPTAINERENV_POP_SIZE=5000
export APPTAINERENV_NUMERICS_BATCH_SIZE=0
export APPTAINERENV_MIN_AGE=15
export APPTAINERENV_MAX_AGE=999
export APPTAINERENV_MIN_DURATION=12
export APPTAINERENV_MAX_DURATION=240
export APPTAINERENV_MIN_PERCENT=0
apptainer run \
    --bind "$MIMIC_DATA:/mimic_data:ro" \
    --bind "$CURATED_OUT:/opt/mimic-extract/data/curated" \
    --bind "$PG_SOCKET:/tmp/pg_socket" \
    "$SIF_PATH"

echo ""
echo "Setup complete. Postgres has MIMIC data and concepts."
echo "To run extraction jobs in parallel, use:"
echo "  PGHOST=$PG_SOCKET PG_SOCKET_DIR=$PG_SOCKET bash apptainer/jobs/submit_all.sh"
echo ""
echo "Keeping Postgres running for 24h (job time limit)."
if [ "$USE_NATIVE" = "1" ]; then
  while kill -0 $(head -1 "$POSTGRES_DATA/postmaster.pid" 2>/dev/null) 2>/dev/null; do sleep 60; done
else
  wait $PGPID
fi
