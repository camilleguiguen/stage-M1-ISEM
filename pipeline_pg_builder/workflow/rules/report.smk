# =============================================================================
# report.smk — résumé global du run
# =============================================================================
# Variables globales utilisées : RUNS, config
# Fonctions utilisées          : summary_gfas, summary_logs, summary_labels
# Wildcard {run} : nom du dossier de sortie dérivé du nom du fichier FASTA d'entrée
# =============================================================================

OUTPUT_DIR = config["output_dir"]

# Copie le config.yaml utilisé pour la run dans le dossier de sortie
# -> permet de retrouver a posteriori les paramètres avec lesquels une run a été lancée
rule save_config:
    input:
        CONFIG_PATH,
    output:
        OUTPUT_DIR + "/{run}/config_used.yaml",
    shell:
        "cp {input} {output}"

rule build_summary:
    input:
        gfas = summary_gfas,
        logs = summary_logs,
    output:
        summary = OUTPUT_DIR + "/{run}/runs_summary_update.txt",
    params:
        run_name = lambda wc: wc.run,
        samples  = lambda wc: RUNS[wc.run]["samples"],
        ref      = lambda wc: RUNS[wc.run]["reference"],
        labels   = summary_labels,
    script:
        "../scripts/gfa_stats.py"
