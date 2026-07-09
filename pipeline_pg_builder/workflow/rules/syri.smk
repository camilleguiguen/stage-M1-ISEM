# =============================================================================
# syri.smk — détection de variants structuraux par SyRI (pairwise ref vs query)
# =============================================================================
# Variables globales utilisées : config, RUNS
# Wildcard (wc) {run} : nom du dossier de sortie dérivé du nom du fichier FASTA
# Wildcard {sample}   : un isolat non-référence comparé à la référence
#
# Réutilise les fichiers par isolat produits par extract_isolate (minigraph.smk).
# Appelle le script syri_launch.sh pour chaque paire (ref, query).
#
# NOTE : pas de directive container: — minimap2, samtools et syri doivent être
# disponibles dans l'environnement d'exécution (module load, conda, ou hôte).
# =============================================================================

OUTPUT_DIR = config["output_dir"]

# --- Étape 1 : lancer SyRI pour chaque paire (ref, isolat) -----------------
# Produit un dossier {sample}_syri/ contenant {sample}_syri.out, .vcf, etc.

rule run_syri:
    input:
        ref = lambda wc: OUTPUT_DIR + f"/{wc.run}/per_sample/{RUNS[wc.run]['reference']}.fa",
        qry = OUTPUT_DIR + "/{run}/per_sample/{sample}.fa",
    output:
        syri_out = OUTPUT_DIR + "/{run}/SyRI/{sample}_syri/{sample}_syri.out",
    params:
        prefix = lambda wc: wc.sample,
        outdir = lambda wc: OUTPUT_DIR + f"/{wc.run}/SyRI",
    threads:
        config.get("syri", {}).get("threads", 4)
    shell:
        """
        bash syri_launch.sh {input.ref} {input.qry} {params.prefix} {params.outdir} {threads}
        """


# --- Étape 2 : point de synchro — attend que tous les run_syri soient finis
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
