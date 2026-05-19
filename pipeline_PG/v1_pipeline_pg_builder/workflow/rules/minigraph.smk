# =============================================================================
# minigraph.smk — préparation + construction du graphe Minigraph
# =============================================================================
# Variables globales utilisées : config, RUN_DIR, SAMPLES
# =============================================================================


# --- Étape 1 : extraire chaque isolat dans son propre FASTA -----------------
# Cette règle tourne UNE FOIS PAR ISOLAT (wildcard {sample}).

rule extract_isolate:
    input:
        multifasta = config["input"],
    output:
        fa = str(RUN_DIR / "per_sample" / "{sample}.fa"),
    conda:
        "../envs/minigraph.yaml"
    container:
        "docker://quay.io/biocontainers/samtools:1.21--h50ea8bc_0"
    shell:
        """
        samtools faidx {input.multifasta} {wildcards.sample} > {output.fa}
        """


# --- Étape 2 : lancer Minigraph ---------------------------------------------
# Minigraph attend la référence en premier, puis les autres isolats.

rule run_minigraph:
    input:
        fastas = expand(
            str(RUN_DIR / "per_sample" / "{sample}.fa"),
            sample=SAMPLES,
        ),
    output:
        gfa = str(RUN_DIR / "Minigraph" / "pangenome_MC.gfa"),
        log = str(RUN_DIR / "Minigraph" / "minigraph.log"),
    params:
        min_sv_len = config["minigraph"]["min_sv_len"],
    threads:
        config["minigraph"]["threads"]
    conda:
        "../envs/minigraph.yaml"
    container:
        "docker://quay.io/biocontainers/minigraph:0.21--h577a1d6_3"
    shell:
        """
        minigraph -cxggs -L {params.min_sv_len} -t {threads} {input.fastas} > {output.gfa} 2> {output.log}
        """
