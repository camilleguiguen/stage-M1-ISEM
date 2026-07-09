
# =============================================================================
# syri.smk — détection de variants structuraux par SyRI (pairwise ref vs query)
# =============================================================================
# Variables globales utilisées : config, RUNS
# Wildcard (wc) {run} : nom du dossier de sortie dérivé du nom du fichier FASTA
# Wildcard {sample}   : un isolat non-référence comparé à la référence
#
# NOTE IMPORTANTE :
# Il n'existe PAS d'image biocontainers unique regroupant minimap2 + samtools
# + syri (vérifié sur bioconda.github.io/recipes/syri : le paquet syri ne
# dépend que de librairies Python, pas d'outils système). On ne peut donc pas
# mettre un seul `container:` sur syri_launch.sh qui enchaîne les 3 outils.
# -> on découpe l'ancien syri_launch.sh en 3 règles Snakemake, chacune avec
#    SON PROPRE conteneur, comme le fait déjà le reste du pipeline
#    (ex: index_fasta / run_minigraph dans minigraph.smk).
# =============================================================================

OUTPUT_DIR = config["output_dir"]


# AVANT MODIFS (il fallait des containers apptainer et pas reposer sur syri-env)
# --- Étape 1 : lancer SyRI pour chaque paire (ref, isolat) -----------------
# Produit un dossier {sample}_syri/ contenant {sample}_syri.out, .vcf, etc.
#rule run_syri:
#    input:
#        ref = lambda wc: OUTPUT_DIR + f"/{wc.run}/per_sample/{RUNS[wc.run]['reference']}.fa",
#        qry = OUTPUT_DIR + "/{run}/per_sample/{sample}.fa",
#    output:
#        syri_out = OUTPUT_DIR + "/{run}/SyRI/{sample}_syri/{sample}_syri.out",
#    params:
#        prefix = lambda wc: wc.sample,
#        outdir = lambda wc: OUTPUT_DIR + f"/{wc.run}/SyRI",
#    threads:
#        config.get("syri", {}).get("threads", 4)
#    shell:
#        """
#        bash workflow/scripts/syri_launch.sh {input.ref} {input.qry} {params.prefix} {params.outdir} {threads}
#        """


# --- Étape 1 : alignement ref vs query avec minimap2 ------------------------
# -a       : sortie au format SAM
# -x asm5  : préréglage adapté aux assemblages proches (<5% divergence)
# --eqx    : code CIGAR étendu (=/X au lieu de M) — requis par SyRI
rule align_minimap2:
    input:
        ref = lambda wc: OUTPUT_DIR + f"/{wc.run}/per_sample/{RUNS[wc.run]['reference']}.fa",
        qry = OUTPUT_DIR + "/{run}/per_sample/{sample}.fa",
    output:
        sam = temp(OUTPUT_DIR + "/{run}/SyRI/{sample}.sam"),
    threads:
        config.get("syri", {}).get("threads", 4)
    container:
        "docker://quay.io/biocontainers/minimap2:2.31--3df56ce-arm64"
    shell:
        """
        minimap2 -a -x asm5 --eqx -t {threads} {input.ref} {input.qry} > {output.sam}
        """


# --- Étape 2 : conversion SAM -> BAM trié avec samtools ---------------------
# (même image que celle déjà utilisée ailleurs dans le pipeline, cf. minigraph.smk)
rule sort_bam:
    input:
        sam = OUTPUT_DIR + "/{run}/SyRI/{sample}.sam",
    output:
        bam = temp(OUTPUT_DIR + "/{run}/SyRI/{sample}.sorted.bam"),
    container:
        "docker://quay.io/biocontainers/samtools:1.21--h50ea8bc_0"
    shell:
        """
        samtools sort {input.sam} -o {output.bam}
        """


# --- Étape 3 : détection de variants structuraux avec SyRI ------------------
# -c   : fichier BAM d'alignement (query contre ref)
# -F B : format d'entrée = BAM
# -k   : garde les fichiers intermédiaires de SyRI (utile pour debug)
rule run_syri:
    input:
        ref = lambda wc: OUTPUT_DIR + f"/{wc.run}/per_sample/{RUNS[wc.run]['reference']}.fa",
        qry = OUTPUT_DIR + "/{run}/per_sample/{sample}.fa",
        bam = OUTPUT_DIR + "/{run}/SyRI/{sample}.sorted.bam",
    output:
        syri_out = OUTPUT_DIR + "/{run}/SyRI/{sample}_syri/{sample}_syri.out",
    params:
        prefix = lambda wc: f"{wc.sample}_",
        outdir = lambda wc: OUTPUT_DIR + f"/{wc.run}/SyRI/{wc.sample}_syri",
    
    #pour l'instant pas de container attitré a syri donc avec env conda syri-env chez moi
    container:
        #"docker://quay.io/biocontainers/syri:5982cc7861b5"
        "docker://quay.io/biocontainers/syri:1.7.1--pyhdfd78af_0"
    shell:
        """
        mkdir -p {params.outdir}
        syri -c {input.bam} \
             -r {input.ref} \
             -q {input.qry} \
             -F B -k \
             --dir {params.outdir} \
             --prefix {params.prefix}
        """


# --- Étape 4 : point de synchro — attend que tous les run_syri soient finis
# Produit un "fichier marqueur" syri_done.txt utilisé comme cible unique par rule all.

rule syri_all:
    input:
        lambda wc: expand(
            OUTPUT_DIR + "/{run}/SyRI/{sample}_syri/{sample}_syri.out",
            run=wc.run,
            sample=[s for s in RUNS[wc.run]["samples"] if s != RUNS[wc.run]["reference"]],
        ),
    output:
        done = OUTPUT_DIR + "/{run}/SyRI/syri_done.txt",
    params:
        ref = lambda wc: RUNS[wc.run]["reference"],
    shell:
        r"""
        echo "SyRI terminé — $(date)" > {output.done}
        echo "Référence : {params.ref}" >> {output.done}
        echo "Comparaisons :" >> {output.done}
        for f in {input}; do echo "  $f" >> {output.done}; done
        """
