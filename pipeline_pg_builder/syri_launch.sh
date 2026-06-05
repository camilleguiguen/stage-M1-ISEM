#!/bin/bash
#SBATCH --job-name=syri
#SBATCH --time=06:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=4
#SBATCH --output=slurm-%j.out
#SBATCH --error=slurm-%j.err

# Usage : sbatch syri_launch.sh i1.fasta i2.fasta i1vs2

REF=$1
QRY=$2
PREFIX=$3

# ÉTAPE 1 : Aligner
minimap2 -a -x asm5 --eqx -t $SLURM_CPUS_PER_TASK $REF $QRY > ${PREFIX}.sam

# Étape 2 : Convertir en BAM
samtools sort ${PREFIX}.sam -o ${PREFIX}.sorted.bam
rm ${PREFIX}.sam

# Étape 3 : SyRI
mkdir -p ${PREFIX}_syri
syri -c ${PREFIX}.sorted.bam -r $REF -q $QRY -F B -k --prefix ${PREFIX}_syri/${PREFIX}_