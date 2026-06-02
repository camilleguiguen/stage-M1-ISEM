# =============================================================================
# minigraph.smk — préparation + construction du graphe Minigraph
# =============================================================================
# Variables globales utilisées : config, RUNS (dict run→{fasta,samples,reference,run_dir})
# Wildcard {run} : nom du dossier de sortie dérivé du nom du fichier FASTA d'entrée
# =============================================================================

OUTPUT_DIR = config["output_dir"]
INPUT_DIR  = config["input_dir"].rstrip("/")

# --- Indexation des FASTA d'entrée ------------------------------------------
# Règle dédiée : crée le .fai UNE SEULE FOIS par fichier FASTA.
# Évite la race condition quand plusieurs extract_isolate tournent en parallèle
# et essaient tous de créer le .fai simultanément.

rule index_fasta:
    input:
        INPUT_DIR + "/{fasta_stem}.fasta",
    output:
        INPUT_DIR + "/{fasta_stem}.fasta.fai",
    container:
        "docker://quay.io/biocontainers/samtools:1.21--h50ea8bc_0"
    shell:
        "samtools faidx {input}"


# --- Étape 1 : extraire chaque isolat dans son propre FASTA -----------------
# Cette règle tourne UNE FOIS PAR (run, isolat) (wildcards {run} et {sample}).

rule extract_isolate:
    input:
        multifasta = lambda wc: RUNS[wc.run]["fasta"],
        fai = lambda wc: RUNS[wc.run]["fasta"] + ".fai",  # garantit que l'index existe avant l'extraction
    output:
        fa = temp(OUTPUT_DIR + "/{run}/per_sample/{sample}.fa"),
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
        # La référence est placée en tête de liste, puis les autres isolats
        fastas = lambda wc: (
            [OUTPUT_DIR + f"/{wc.run}/per_sample/{RUNS[wc.run]['reference']}.fa"] +
            [OUTPUT_DIR + f"/{wc.run}/per_sample/{s}.fa"
             for s in RUNS[wc.run]["samples"] if s != RUNS[wc.run]["reference"]]
        ),
    output:
        gfa = OUTPUT_DIR + "/{run}/Minigraph/pangenome_MG.gfa",
        log = OUTPUT_DIR + "/{run}/Minigraph/minigraph.log",
    params:
        min_sv_len = config["minigraph"]["min_sv_len"],
    threads:
        config["minigraph"]["threads"]
    container:
        "docker://quay.io/biocontainers/minigraph:0.21--h577a1d6_3"
    shell:
        """
        minigraph -cxggs -L {params.min_sv_len} -t {threads} {input.fastas} > {output.gfa} 2> {output.log}
        """
