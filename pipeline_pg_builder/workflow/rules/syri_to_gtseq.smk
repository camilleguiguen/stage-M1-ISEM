# =============================================================================
# syri_to_gtseq.smk — conversion des sorties SyRI (.out) en tables GT (génotypes)
# =============================================================================
# Variables globales utilisées : config, RUNS
# Wildcard {run}    : nom du dossier de sortie dérivé du nom du fichier FASTA
# Wildcard {sample} : isolat non-référence comparé à la référence (idem syri.smk)
OUTPUT_DIR = config["output_dir"]

rule merge_gtseq:
    input:
        # Un .out par isolat non-référence -> garantit que run_syri est
        # terminé pour chacun avant de lancer la fusion.
        syri_outs = lambda wc: expand(
            OUTPUT_DIR + "/{run}/SyRI_and_GTsequences/SyRI/{sample}_syri.out",
            run=wc.run,
            sample=[s for s in RUNS[wc.run]["samples"] if s != RUNS[wc.run]["reference"]],
        ),
    output:
        # Seul fichier garanti (les BIG_GT_<type>.tsv ne sont écrits que si le
        # type est présent dans le run, donc pas déclarés comme output fixe -
        # même logique que l'ancien BIG_GT.tsv par isolat)
        big_gt = OUTPUT_DIR + "/{run}/SyRI_and_GTsequences/GTsequences/BIG_GT.tsv",
    params:
        outdir = lambda wc: OUTPUT_DIR + f"/{wc.run}/SyRI_and_GTsequences/GTsequences",
    script:
        "../scripts/merge_gtseq.py"


rule gt_all:
    input:
        big_gt    = OUTPUT_DIR + "/{run}/SyRI_and_GTsequences/GTsequences/BIG_GT.tsv",
        syri_done = OUTPUT_DIR + "/{run}/SyRI_and_GTsequences/syri_done.txt",
    output:
        done = OUTPUT_DIR + "/{run}/SyRI_and_GTsequences/gtseq_done.txt",
    shell:
        r"""
        echo "Fusion GTsequences terminée — $(date)" > {output.done}
        echo "Fichier final : {input.big_gt}" >> {output.done}
        """