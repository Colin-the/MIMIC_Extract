# MIMIC-Extract with Apptainer (Singularity)

Use this when Docker is not available (e.g. HPC with `module load apptainer`).

## RAM requirements

See [docs/RESOURCE_ESTIMATES.md](../docs/RESOURCE_ESTIMATES.md). **Recommended: 100 GB** for the job.

## Quick start

### 1. Load modules

```bash
module load postgresql apptainer
```

### 2. Build images (one-time)

From the project root:

```bash
cd research/MIMIC_Extract
apptainer build apptainer/mimextract.sif apptainer/mimic-extract.def
apptainer build apptainer/postgres.sif docker://postgres:15
```

The Postgres SIF avoids "Transport endpoint is not connected" errors on clusters using CVMFS/FUSE.

### 3. Place MIMIC-III data

Put MIMIC-III CSV files in `data/mimiciii/1.4/` (same as Docker setup).

### 4. Run the setup job (SLURM)

**Important:** Submit from the project root so paths resolve correctly:

```bash
cd /path/to/MIMIC_Extract
sbatch apptainer/jobs/job_setup_postgres.sh
```

If running interactively (not via SLURM):

```bash
cd /path/to/MIMIC_Extract
nohup bash apptainer/start_postgres_apptainer.sh > postgres.log 2>&1 &
# Wait ~30s, then:
PGHOST=$PWD/data/pg_socket bash apptainer/run_all_scenarios_apptainer.sh
```

### 5. Run all scenarios (sequential, single job)

```bash
cd /path/to/MIMIC_Extract
sbatch apptainer/job_slurm.sh
```

Output goes to `data/curated/{scenario_name}/`.

## Parallel execution (per-scenario jobs)

Run each scenario as a separate SLURM job in parallel:

```bash
# 1. Run setup once (loads data, builds concepts, keeps Postgres running)
sbatch apptainer/jobs/job_setup_postgres.sh

# 2. After setup completes, submit all 13 extraction jobs (use node from setup job)
PGHOST=<hostname> bash apptainer/jobs/submit_all.sh
```

Or submit individual jobs: `sbatch apptainer/jobs/job_pop5000.sh`, etc.

See [apptainer/jobs/README.md](jobs/README.md) for details.

## Sequential execution (single job)

```bash
#!/bin/bash
#SBATCH --job-name=mimic-extract
#SBATCH --mem=100G
#SBATCH --cpus-per-task=8
#SBATCH --time=72:00:00
#SBATCH --output=mimic_extract_%j.log

module load apptainer

cd $SLURM_SUBMIT_DIR/research/MIMIC_Extract

# Start Postgres in background
bash apptainer/start_postgres_apptainer.sh &
PGPID=$!
sleep 30
until PGPASSWORD=mimic psql -h localhost -U mimic -d mimic -c '\q' 2>/dev/null; do
  sleep 5
done

# Run all scenarios sequentially
bash apptainer/run_all_scenarios_apptainer.sh

kill $PGPID 2>/dev/null || true
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PGHOST` | localhost | Postgres host (use if Postgres is on another node) |
| `PGPORT` | 5432 | Postgres port |
| `MIMIC_DATA_PATH` | `data/mimiciii/1.4` | Path to MIMIC-III CSV files |
| `CURATED_OUTPUT` | `data/curated` | Output directory |
| `MIMEXTRACT_SIF` | `apptainer/mimextract.sif` | Path to built SIF file |
| `POSTGRES_SIF` | `apptainer/postgres.sif` | Postgres SIF (avoids FUSE disconnect errors) |
| `POSTGRES_DATA_DIR` | `data/postgres_data` | Postgres data directory (for start_postgres) |

## Disk quota

MIMIC-III loading needs **~50–80 GB** for the Postgres database. If you hit "Disk quota exceeded", use a path with more space:

```bash
# Use scratch/project space (check your cluster: $SCRATCH, $PROJECT, etc.)
POSTGRES_DATA_DIR=$SCRATCH/mimic_postgres sbatch apptainer/jobs/job_setup_postgres.sh
```

Set `PG_SOCKET_DIR` to the same area if needed; extraction jobs must use the same `PG_SOCKET_DIR` path.

## "Transport endpoint is not connected"

This error occurs when the Postgres container's filesystem (from `docker://postgres:15`) disconnects—common with CVMFS or long jobs. **Fix:** build a local Postgres SIF first:

```bash
apptainer build apptainer/postgres.sif docker://postgres:15
```

The setup job will auto-build it if missing, but building on the login node before submitting avoids timeouts.

## Compute Canada / restricted networks

On clusters where `--network host` is not permitted (e.g. Compute Canada), the scripts use **Unix sockets** instead. Postgres is configured to use a socket at `data/pg_socket/`, and mimic-extract connects via that path. No network access is required.

**Parallel jobs:** Extraction jobs must run on the **same node** as the setup job to share the socket. Use `job_slurm.sh` for sequential execution, or submit extraction jobs with `--nodelist=<node>` matching the setup job.
