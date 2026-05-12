# =============================================================================
# report.smk - run_summary.txt global avec stats sur chaque PG produit
# =============================================================================

def _summary_inputs():
    gfas = []
    if config["tools"].get("minigraph", False):
        gfas.append(str(RUN_DIR / "minigraph" / "pangenome.gfa"))
    if config["tools"].get("minigraph_cactus", False):
        gfas.append(str(RUN_DIR / "minigraph_cactus" / "pangenome.gfa"))
    if config["tools"].get("pggb", False):
        gfas.append(str(RUN_DIR / "pggb" / "pangenome.gfa"))
    return gfas


rule build_summary:
    input:
        gfas = _summary_inputs(),
    output:
        summary = str(RUN_DIR / "run_summary.txt"),
    params:
        run_name  = config["run_name"],
        input_src = config["input"],
        kind      = INPUT_KIND,
        samples   = SAMPLES,
        reference = REFERENCE,
        tools_on  = [t for t, v in config["tools"].items() if v],
        run_dir   = str(RUN_DIR),
    conda:
        "../envs/tools.yaml"
    script:
        "../scripts/build_summary.py"
