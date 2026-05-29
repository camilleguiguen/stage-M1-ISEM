#!/bin/bash
# =============================================================================
# run_pipeline.sh — Soumission SLURM du pipeline de construction de pangénome
# =============================================================================
# Usage :
#   sbatch run_pipeline.sh                  (depuis /scratch/.../pipeline_pg_builder/)
#   bash   run_pipeline.sh                  (en interactif, sans SLURM)
#
# Pré-requis :
#   - Être dans le répertoire pipeline_pg_builder/
#   - Avoir configuré config/config.yaml
# =============================================================================

# --- Directives SLURM --------------------------------------------------------
#SBATCH --job-name=pg_builder
#SBATCH --output=logs/pg_builder_%j.log
#SBATCH --error=logs/pg_builder_%j.err
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8        # doit être >= threads max dans config.yaml
#SBATCH --mem=32G
#SBATCH --time=4:00:00
#SBATCH --partition=genouest

# --- Vérification et installation de Snakemake -------------------------------
check_and_install_snakemake() {
    if command -v snakemake &> /dev/null; then
        echo "[OK] Snakemake trouvé : $(snakemake --version)"
        return 0
    fi

    echo "[INFO] Snakemake non trouvé. Tentative d'installation via mamba/conda..."

    if command -v mamba &> /dev/null; then
        mamba install -n base -c conda-forge -c bioconda snakemake -y
    elif command -v conda &> /dev/null; then
        conda install -n base -c conda-forge -c bioconda snakemake -y
    else
        echo "[ERREUR] ni mamba ni conda trouvés — impossible d'installer Snakemake automatiquement."
        echo "  → Installe mamba : https://github.com/conda-forge/miniforge"
        echo "  → Puis relance ce script."
        exit 1
    fi

    # Vérifie que l'installation a réussi
    if ! command -v snakemake &> /dev/null; then
        echo "[ERREUR] L'installation de Snakemake a échoué."
        exit 1
    fi
    echo "[OK] Snakemake installé : $(snakemake --version)"
}

# --- Corps principal ----------------------------------------------------------
set -euo pipefail

# Crée le dossier de logs si nécessaire (SLURM en a besoin avant de démarrer)
mkdir -p logs

echo "============================================================"
echo "  PG_builder — démarrage du pipeline"
echo "  Répertoire de travail : $(pwd)"
echo "  Date : $(date)"
echo "============================================================"

check_and_install_snakemake

# Lance Snakemake
# --use-singularity       : active les conteneurs Apptainer
# --singularity-args      : donne accès à /scratch depuis les conteneurs
# --cores                 : utilise tous les cœurs alloués par SLURM (ou N en interactif)
CORES=${SLURM_CPUS_PER_TASK:-4}   # 4 par défaut si lancé hors SLURM

snakemake \
    --use-singularity \
    --singularity-args "--bind /scratch" \
    --cores "$CORES" \
    --snakefile workflow/Snakefile

echo "============================================================"
echo "  Pipeline terminé — $(date)"
echo "============================================================"
