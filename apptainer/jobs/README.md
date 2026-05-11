# Per-Scenario SLURM Jobs (Parallel Execution)

Each scenario has its own job script so you can run them in parallel with SBATCH.

## Prerequisites

1. **Postgres running** with MIMIC-III loaded. Run the setup first:
   ```bash
   cd /path/to/MIMIC_Extract    # must be run from project root
   module load postgresql apptainer
   sbatch apptainer/jobs/job_setup_postgres.sh
   ```
   Wait for it to finish (loads data, builds concepts). Extraction jobs must run on the **same node** (Unix socket).

2. **Built SIF**: `apptainer build apptainer/mimextract.sif apptainer/mimic-extract.def`

3. **MIMIC-III data** in `data/mimiciii/1.4/`

## Submit all jobs in parallel

```bash
cd research/MIMIC_Extract
bash apptainer/jobs/submit_all.sh
```

If Postgres runs on a different node (e.g. from the setup job):

```bash
# Get the node hostname from the setup job, then:
PGHOST=node123 bash apptainer/jobs/submit_all.sh
```

Or export before submitting:

```bash
export PGHOST=node123
bash apptainer/jobs/submit_all.sh
```

## Job scripts

| Script | Scenario | Output |
|--------|----------|--------|
| job_pop5000.sh | 5000 ICU stays | data/curated/pop5000/ |
| job_min48hr.sh | Long stays (≥48h) | data/curated/min48hr/ |
| job_min18age.sh | Adults (≥18) | data/curated/min18age/ |
| job_minperc5.sh | Stricter missingness | data/curated/minperc5/ |
| job_age35_range5.sh | Ages 33–37 | data/curated/age35_range5/ |
| job_age35_range10.sh | Ages 30–40 | data/curated/age35_range10/ |
| job_age35_range15.sh | Ages 28–42 | data/curated/age35_range15/ |
| job_age45_range5.sh | Ages 43–47 | data/curated/age45_range5/ |
| job_age45_range10.sh | Ages 40–50 | data/curated/age45_range10/ |
| job_age45_range15.sh | Ages 38–52 | data/curated/age45_range15/ |
| job_age55_range5.sh | Ages 53–57 | data/curated/age55_range5/ |
| job_age55_range10.sh | Ages 50–60 | data/curated/age55_range10/ |
| job_age55_range15.sh | Ages 48–62 | data/curated/age55_range15/ |

## Submit individual jobs

```bash
sbatch apptainer/jobs/job_pop5000.sh
sbatch apptainer/jobs/job_min48hr.sh
# etc.
```

## Self-contained mode (no shared Postgres)

If you cannot use a shared Postgres (e.g. jobs on different nodes), each job can start its own Postgres. This is slower (13× data load) but fully parallel. Add `START_POSTGRES=1` to the job scripts or create a wrapper that sets it before starting Postgres.
