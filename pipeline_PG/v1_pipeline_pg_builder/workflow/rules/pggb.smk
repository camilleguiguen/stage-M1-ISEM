# =============================================================================
# pggb.smk — préparation PanSN + construction du graphe PGGB
# =============================================================================
# Variables globales utilisées : config, RUN_DIR, SAMPLES
# Nécessite --use-singularity (pas d'env conda pour ces règles).
# =============================================================================


# --- Étape 1 : préparer le multi-FASTA PanSN pour PGGB ----------------------
# PGGB exige un multi-FASTA bgzippé + indexé avec headers au format PanSN :
# >sample#1#contig  (haplotype unique = 1)
# Lit directement le multi-FASTA d'entrée — indépendant de extract_isolate.

rule prepare_pansn_multifasta:
    input:
        multifasta = config["input"],
    output:
        fa  = str(RUN_DIR / "PGGB" / "all.fa.gz"),
        fai = str(RUN_DIR / "PGGB" / "all.fa.gz.fai"),
        gzi = str(RUN_DIR / "PGGB" / "all.fa.gz.gzi"),
    params:
        samples = SAMPLES,
    container:
        "docker://quay.io/biocontainers/pggb:0.7.4--h9ee0642_0"
    shell:
        r"""
        mkdir -p $(dirname {output.fa})

        # Pour chaque isolat : samtools extrait sa séquence,
        # awk renomme header au format PanSN (>sample#1#contig)
        for s in {params.samples}; do
            samtools faidx {input.multifasta} "$s" | \
                awk -v s="$s" '/^>/{{split($1,a," "); name=substr(a[1],2); print ">"s"#1#"name; next}}{{print}}'
        done | bgzip > {output.fa}

        # Crée les index .fai et .gzi — obligatoires pour PGGB
        samtools faidx {output.fa}
        """


# --- Étape 2 : lancer PGGB --------------------------------------------------

rule run_pggb:
    input:
        fa  = str(RUN_DIR / "PGGB" / "all.fa.gz"),
        fai = str(RUN_DIR / "PGGB" / "all.fa.gz.fai"),
        gzi = str(RUN_DIR / "PGGB" / "all.fa.gz.gzi"),
    output:
        gfa = str(RUN_DIR / "PGGB" / "pangenome.gfa"),
        log = str(RUN_DIR / "PGGB" / "pggb.log"),
    params:
        n      = lambda wc: config["pggb"].get("n_haplotypes") or len(SAMPLES),
        s      = config["pggb"].get("segment_length", 5000),   # longueur de segment
        p      = config["pggb"].get("percent_identity", 90),   # % identité minimum
        outdir = str(RUN_DIR / "PGGB"),
    threads:
        config["pggb"].get("threads", 4)
    container:
        "docker://quay.io/biocontainers/pggb:0.7.4--h9ee0642_0"
    shell:
        r"""
        mkdir -p {params.outdir}

        # -i  fichier d'entrée (le .fa.gz PanSN préparé)
        # -n  nombre d'haplotypes — OBLIGATOIRE pour l'alignement
        # -o  dossier de sortie
        pggb -i {input.fa} \
             -n {params.n} \
             -s {params.s} \
             -p {params.p} \
             -t {threads} \
             -o {params.outdir} \
             > {output.log} 2>&1

        # PGGB nomme son GFA final *.smooth.final.gfa (avec hashes dans le nom)
        # → on le déplace vers le nom standard attendu par Snakemake
        final=$(ls {params.outdir}/*.smooth.final.gfa 2>/dev/null | head -1)
        [ -n "$final" ] && mv "$final" {output.gfa}
        """
