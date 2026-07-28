# =============================================================================
# syri_to_gtseq.smk — conversion des sorties SyRI (.out) en tables GT (génotypes)
# =============================================================================
# Variables globales utilisées : config, RUNS
# Wildcard {run}    : nom du dossier de sortie dérivé du nom du fichier FASTA
# Wildcard {sample} : isolat non-référence comparé à la référence (idem syri.smk)
OUTPUT_DIR = config["output_dir"]

OUTPUT_DIR = config["output_dir"]

rule merge_gtseq:
    input:
        syri_outs = lambda wc: expand(
            OUTPUT_DIR + "/{run}/SyRI/{sample}_syri.out",
            run=wc.run,
            sample=[s for s in RUNS[wc.run]["samples"] if s != RUNS[wc.run]["reference"]],
        ),
    output:
        big_gt = OUTPUT_DIR + "/{run}/GTsequences/BIG_GT.tsv",
    params:
        outdir = lambda wc: OUTPUT_DIR + f"/{wc.run}/GTsequences",
    script:
        "../scripts/merge_gtseq.py"


rule gt_all:
    input:
        big_gt    = OUTPUT_DIR + "/{run}/GTsequences/BIG_GT.tsv",
        syri_done = OUTPUT_DIR + "/{run}/syri_done.txt",
    output:
        done = OUTPUT_DIR + "/{run}/gtseq_done.txt",
    shell:
        r"""
        echo "Fusion GTsequences terminée — $(date)" > {output.done}
        echo "Fichier final : {input.big_gt}" >> {output.done}
        """