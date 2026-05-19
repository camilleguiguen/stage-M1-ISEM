# =============================================================================
# report.smk — résumé global du run
# =============================================================================
# Variables globales utilisées : RUN_DIR, RUN_NAME, SAMPLES, REFERENCE
# Fonctions utilisées          : summary_gfas, summary_logs, summary_labels
# =============================================================================


rule build_summary:
    input:
        gfas = summary_gfas,
        logs = summary_logs,
    output:
        summary = str(RUN_DIR / "runs_summary_update.txt"),
    params:
        run_name = RUN_NAME,
        samples  = SAMPLES,
        ref      = REFERENCE,
        labels   = summary_labels,
    script:
        "../scripts/gfa_stats.py"
