# =============================================================================
# minigraph_cactus.smk
# =============================================================================
# Utilise cactus-pangenome (workflow MC), qui prend un seqfile et produit un
# pangenome au format GFA + vg.
# =============================================================================

rule run_minigraph_cactus:
    input:
        seqfile = str(PREP_DIR / "seqfile.tsv"),
    output:
        gfa = str(RUN_DIR / "minigraph_cactus" / "pangenome.gfa"),
        log = str(RUN_DIR / "minigraph_cactus" / "log.txt"),
    params:
        ref    = REFERENCE,
        extra  = config["minigraph_cactus"].get("extra", ""),
        outdir = str(RUN_DIR / "minigraph_cactus"),
        jobstore = lambda wc: str(RUN_DIR / "minigraph_cactus" / "jobstore"),
    threads:
        config["minigraph_cactus"].get("threads", 16)
    resources:
        mem_mb  = config["resources"]["heavy"]["mem_mb"],
        runtime = config["resources"]["heavy"]["runtime"],
    conda:
        "../envs/cactus.yaml"
    shell:
        r"""
        mkdir -p {params.outdir}
        rm -rf {params.jobstore}

        START=$(date +%s)
        {{
          echo "===== Minigraph-Cactus =====";
          echo "Date          : $(date)";
          echo "Version       : $(cactus-pangenome --version 2>&1 | head -1)";
          echo "Référence     : {params.ref}";
          echo "Seqfile       : {input.seqfile}";
          echo "Threads       : {threads}";
          echo "Extra args    : {params.extra}";
          echo "---------------------------------";
        }} > {output.log}

        cactus-pangenome {params.jobstore} {input.seqfile} \
            --outDir {params.outdir} \
            --outName pangenome \
            --reference {params.ref} \
            --gfa \
            --maxCores {threads} \
            {params.extra} \
            >> {output.log} 2>&1

        # cactus écrit pangenome.gfa.gz, on décompresse pour homogénéiser
        if [ -f {params.outdir}/pangenome.gfa.gz ] && [ ! -f {output.gfa} ]; then
            gunzip -k {params.outdir}/pangenome.gfa.gz
        fi

        END=$(date +%s)
        echo "---------------------------------" >> {output.log}
        echo "Durée (s)     : $((END-START))"    >> {output.log}
        echo "GFA produit   : {output.gfa}"      >> {output.log}
        """
