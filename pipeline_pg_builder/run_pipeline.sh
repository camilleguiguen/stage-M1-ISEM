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
#   - Apptainer installé sur le système hôte (vérifier : apptainer --version)
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
#SBATCH --partition=genouest    #normal, large... (taper 'sinfo' sur le cluster)
#SBATCH --constraint=avx2


# --- Image Snakemake (Apptainer) ---------------------------------------------
# L'image inclut Singularity/Apptainer — nécessaire pour que Snakemake puisse
# lui-même lancer les conteneurs des règles (--use-singularity).
# Le SIF est mis en cache dans ~/.apptainer/ : le téléchargement n'a lieu
# qu'une seule fois.
SNAKEMAKE_IMAGE="docker://snakemake/snakemake:stable"
SNAKEMAKE_SIF="${HOME}/.apptainer/snakemake_stable.sif"

get_snakemake_sif() {
    if [ -f "$SNAKEMAKE_SIF" ]; then
        echo "[OK] Image Snakemake en cache : $SNAKEMAKE_SIF"
        return 0
    fi
    echo "[INFO] Première utilisation — téléchargement de l'image Snakemake..."
    mkdir -p "$(dirname "$SNAKEMAKE_SIF")"
    apptainer pull "$SNAKEMAKE_SIF" "$SNAKEMAKE_IMAGE"
    echo "[OK] Image téléchargée : $SNAKEMAKE_SIF"
}




set -euo pipefail

mkdir -p logs

echo "============================================================"
echo "  PG_builder — démarrage du pipeline"
echo "  Répertoire de travail : $(pwd)"
echo "  Date : $(date)"
echo "============================================================"

get_snakemake_sif

CORES=${SLURM_CPUS_PER_TASK:-4}   # 4 par défaut si lancé hors SLURM

# Lance Snakemake via l'image Apptainer
# --bind /scratch          : rend /scratch accessible dans le conteneur Snakemake
# --bind $(pwd)            : rend le répertoire courant (code + config) accessible
# --use-singularity        : Snakemake lance chaque règle dans son propre conteneur
# --singularity-args       : transmet --bind /scratch aux conteneurs des règles
apptainer exec \
    --bind /scratch \
    --bind "$(pwd)" \
    "$SNAKEMAKE_SIF" \
    snakemake \
        --use-singularity \
        --singularity-args "--bind /scratch" \
        --cores "$CORES" \
        --snakefile workflow/Snakefile

echo "============================================================"
echo "  Pipeline terminé — $(date)"
echo "============================================================"
