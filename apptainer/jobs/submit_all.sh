#!/bin/bash
# Submit all 13 scenario jobs to SLURM in parallel
#
# Prerequisites:
#   1. Postgres running with MIMIC-III loaded (run setup job first)
#   2. Extraction jobs must run on SAME NODE as setup (Unix socket) - pass NODELIST
#   3. Built SIF: apptainer build apptainer/mimextract.sif apptainer/mimic-extract.def
#
# Usage (after setup completes):
#   cd /path/to/MIMIC_Extract
#   # Get node from setup job: squeue -u $USER or check setup log
#   NODELIST=<node> PGHOST=/scratch/$USER/mimic_pg_socket bash apptainer/jobs/submit_all.sh
#
# Example (with scratch paths from setup):
#   NODELIST=c263.nibi.sharcnet PGHOST=/scratch/ccampb47/mimic_pg_socket bash apptainer/jobs/submit_all.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SLURM_SUBMIT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
cd "$PROJECT_ROOT"

# Default PGHOST to socket path when running from project root
PG_SOCKET_DEFAULT="${PG_SOCKET_DIR:-$PROJECT_ROOT/data/pg_socket}"
export PGHOST="${PGHOST:-$PG_SOCKET_DEFAULT}"
export PG_SOCKET_DIR="${PG_SOCKET_DIR:-$PGHOST}"

# Run sbatch from PROJECT_ROOT so SLURM_SUBMIT_DIR is correct (job scripts use it for SIF path)
cd "$PROJECT_ROOT"

# Pass PGHOST and PG_SOCKET_DIR to jobs (required for Unix socket bind)
SBATCH_EXPORT="ALL,PGHOST=$PGHOST,PG_SOCKET_DIR=$PG_SOCKET_DIR,SLURM_SUBMIT_DIR=$PROJECT_ROOT"

# Build sbatch args
SBATCH_ARGS="--export=$SBATCH_EXPORT"
[ -n "${NODELIST:-}" ] && SBATCH_ARGS="$SBATCH_ARGS --nodelist=$NODELIST"

echo "Submitting 12 scenario jobs (pop5000 already run during setup)..."
echo "  PGHOST=$PGHOST"
[ -n "${NODELIST:-}" ] && echo "  NODELIST=$NODELIST (same node as setup)"
for f in "$SCRIPT_DIR"/job_*.sh; do
  fname=$(basename "$f")
  [ "$fname" = "job_setup_postgres.sh" ] && continue
  [ "$fname" = "job_keep_postgres.sh" ] && continue
  [ "$fname" = "job_pop5000.sh" ] && continue   # already run during setup
  echo "  sbatch $SBATCH_ARGS $f"
  sbatch $SBATCH_ARGS "$f"
done
echo "Done. Check squeue for status."
