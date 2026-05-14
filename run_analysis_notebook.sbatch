#!/bin/bash
#SBATCH --job-name=mimic_analysis_nb
#SBATCH --output=/home/ccampb47/work/MIMIC_Extract/logs/mimic_analysis_nb_%j.out
#SBATCH --error=/home/ccampb47/work/MIMIC_Extract/logs/mimic_analysis_nb_%j.err
#SBATCH --time=10:00:00
#SBATCH --cpus-per-task=2
#SBATCH --mem=32G

set -euo pipefail

source "/home/ccampb47/work/MIMIC_Extract/.venv_stats/bin/activate"

jupyter nbconvert --to notebook --execute --inplace \
    "/home/ccampb47/work/MIMIC_Extract/notebooks/mimic_extract_analysis.ipynb"
