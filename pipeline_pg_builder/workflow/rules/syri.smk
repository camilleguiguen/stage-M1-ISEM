# =============================================================================
# syri.smk — détection de variants structuraux par SyRI (pairwise ref vs query)
# =============================================================================
# ...
#
# SOLUTION TEMPORAIRE (2026-07-10) :
# Pas d'image biocontainers combinant minimap2+samtools+syri (vérifié).
# En attendant une vraie solution propre (env conda déclaré via `conda:` +
# --use-conda, ou 3 conteneurs séparés), on utilise l'environnement conda
# "syri-env" déjà installé et testé par Camille, en forçant son PATH
# directement dans le shell de la règle.
# -> On NE PEUT PAS compter sur un `conda activate` fait avant `sbatch` :
#    le job Slurm démarre un nouveau shell qui n'hérite pas de l'activation.
# -> D'où le `export PATH=...` explicite ci-dessous, qui rend la règle
#    autonome quel que soit l'état du shell qui a lancé le pipeline.
# =============================================================================

OUTPUT_DIR = config["output_dir"]

# Chemin vers le bin/ de l'environnement conda contenant syri+samtools+minimap2
# TODO (à corriger si besoin) : chemin absolu propre à l'utilisateur/cluster.
# A terme, remplacer par une vraie solution portable (container ou --use-conda).
SYRI_ENV_BIN = "/home/genouest/cnrs_umr5554/cguiguen/miniconda3/envs/syri-env/bin"

rule run_syri:
    input:
        ref = lambda wc: OUTPUT_DIR + f"/{wc.run}/per_sample/{RUNS[wc.run]['reference']}.fa",
        qry = OUTPUT_DIR + "/{run}/per_sample/{sample}.fa",
    output:
        syri_out = OUTPUT_DIR + "/{run}/SyRI/{sample}_syri/{sample}_syri.out",
    params:
        prefix = lambda wc: wc.sample,
        outdir = lambda wc: OUTPUT_DIR + f"/{wc.run}/SyRI",
        # Chemin vers le script d'init conda (nécessaire pour que `conda activate`
        # fonctionne dans un shell non-interactif comme celui lancé par Snakemake)
        conda_sh  = "/home/genouest/cnrs_umr5554/cguiguen/miniconda3/etc/profile.d/conda.sh",
        conda_env = "syri-env",
    threads:
        config.get("syri", {}).get("threads", 4)
    shell:
        """
        # Solution temporaire : un simple export PATH ne suffit pas car syri
        # charge des bibliothèques partagées (ex: libgomp.so.1 pour igraph)
        # qui vivent dans envs/syri-env/lib/ — seul un vrai `conda activate`
        # configure correctement LD_LIBRARY_PATH (et le reste) pour ça.
        source {params.conda_sh}
        conda activate {params.conda_env}

        bash workflow/scripts/syri_launch.sh {input.ref} {input.qry} {params.prefix} {params.outdir} {threads}
        """

# --- point de synchro (inchangé) --------------------------------------------
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