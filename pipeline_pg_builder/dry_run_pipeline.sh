#!/bin/bash

#SBATCH --job-name=pg_builder_dryrun
#SBATCH --output=logs/pg_builder_%j.log
#SBATCH --error=logs/pg_builder_%j.err
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=4:00:00
#SBATCH --partition=genouest

set -euo pipefail

mkdir -p logs

if [ ! -f "$SNAKEMAKE_SIF" ]; then
    apptainer pull "$SNAKEMAKE_SIF" docker://snakemake/snakemake:stable
fi

SNAKEMAKE_SIF="${HOME}/.apptainer/snakemake_stable.sif"


echo "============================================================"
echo "  PG_builder — DRY-RUN du pipeline"
echo "  Répertoire de travail : $(pwd)"
echo "  Date : $(date)"
echo "============================================================"

apptainer exec \
    --bind /scratch \
    --bind "$(pwd)" \
    "$SNAKEMAKE_SIF" \
    snakemake \
        --use-singularity \
        --singularity-args "--bind /scratch" \
        --cores "${SLURM_CPUS_PER_TASK:-4}" \
        -n \
        --snakefile workflow/Snakefile

echo "============================================================"
echo "  DRY-RUN terminé — $(date)"
echo "============================================================"
