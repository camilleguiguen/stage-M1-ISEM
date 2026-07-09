#!/bin/bash
#SBATCH --job-name=syri
#SBATCH --time=06:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=4
#SBATCH --output=slurm-%j.out
#SBATCH --error=slurm-%j.err

# Usage : sbatch syri_launch.sh <ref.fa> <query.fa> <prefix> [outdir] [threads]
#         bash   syri_launch.sh <ref.fa> <query.fa> <prefix> [outdir] [threads]
# ex    : bash   syri_launch.sh i1.fasta i4.fasta i1vsi4
#          → crée ./i1vsi4_syri/i1vsi4_syri.out
#         bash   syri_launch.sh ref.fa qry.fa sample results/SyRI 8
#          → crée results/SyRI/sample_syri/sample_syri.out

set -euo pipefail

REF=$1
QRY=$2
PREFIX=$3
OUTDIR=${4:-.}
CPUS=${5:-${SLURM_CPUS_PER_TASK:-4}}

mkdir -p "${OUTDIR}"

# Alignement ref vs query
minimap2 -a -x asm5 --eqx -t "${CPUS}" "${REF}" "${QRY}" > "${OUTDIR}/${PREFIX}.sam"

# Conversion SAM → BAM trié
samtools sort "${OUTDIR}/${PREFIX}.sam" -o "${OUTDIR}/${PREFIX}.sorted.bam"
rm "${OUTDIR}/${PREFIX}.sam"

# Détection de variants structuraux avec SyRI
mkdir -p "${OUTDIR}/${PREFIX}_syri"
syri -c "${OUTDIR}/${PREFIX}.sorted.bam" \
    -r "${REF}" \
    -q "${QRY}" \
    -F B -k \
    --dir "${OUTDIR}/${PREFIX}_syri" \
    --prefix "${PREFIX}_"
