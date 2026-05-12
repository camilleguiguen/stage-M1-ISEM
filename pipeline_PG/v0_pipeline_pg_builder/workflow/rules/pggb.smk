# =============================================================================
# pggb.smk
# =============================================================================
# PGGB attend un multi-FASTA bgzippé indexé au format PanSN.
# Paramètres clés : -n (nb haplotypes), -p (% identité), -s (segment length).
# =============================================================================

def _n_haplotypes():
    n = config["pggb"].get("n_haplotypes")
    return n if n else len(SAMPLES)

rule run_pggb:
    input:
        fa  = str(PREP_DIR / "all.fa.gz"),
        fai = str(PREP_DIR / "all.fa.gz.fai"),
        gzi = str(PREP_DIR / "all.fa.gz.gzi"),
    output:
        gfa = str(RUN_DIR / "pggb" / "pangenome.gfa"),
        log = str(RUN_DIR / "pggb" / "log.txt"),
    params:
        n      = _n_haplotypes(),
        s      = config["pggb"].get("segment_length", 5000),
        p      = config["pggb"].get("percent_identity", 90),
        extra  = config["pggb"].get("extra", ""),
        outdir = str(RUN_DIR / "pggb"),
    threads:
        config["pggb"].get("threads", 16)
    resources:
        mem_mb  = config["resources"]["heavy"]["mem_mb"],
        runtime = config["resources"]["heavy"]["runtime"],
    conda:
        "../envs/pggb.yaml"
    shell:
        r"""
        mkdir -p {params.outdir}
        START=$(date +%s)

        {{
          echo "===== PGGB =====";
          echo "Date          : $(date)";
          echo "Version       : $(pggb --version 2>&1 | head -1)";
          echo "Input FASTA   : {input.fa}";
          echo "n haplotypes  : {params.n}";
          echo "segment len   : {params.s}";
          echo "% identité    : {params.p}";
          echo "Threads       : {threads}";
          echo "Extra args    : {params.extra}";
          echo "---------------------------------";
        }} > {output.log}

        pggb -i {input.fa} \
             -n {params.n} \
             -s {params.s} \
             -p {params.p} \
             -t {threads} \
             -o {params.outdir} \
             {params.extra} \
             >> {output.log} 2>&1

        # PGGB nomme le GFA final *.smooth.final.gfa : on le copie en nom standard
        final=$(ls {params.outdir}/*.smooth.final.gfa 2>/dev/null | head -1)
        if [ -n "$final" ]; then
            cp "$final" {output.gfa}
        fi

        END=$(date +%s)
        echo "---------------------------------" >> {output.log}
        echo "Durée (s)     : $((END-START))"    >> {output.log}
        echo "GFA produit   : {output.gfa}"      >> {output.log}
        """
