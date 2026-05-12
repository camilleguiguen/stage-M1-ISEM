# =============================================================================
# minigraph.smk
# =============================================================================
# Minigraph construit le graphe en mode incrémental : il faut passer la
# référence en premier, puis les autres assemblages.
# =============================================================================

rule run_minigraph:
    input:
        fastas = expand(str(PREP_DIR / "per_sample" / "{sample}.fa"), sample=SAMPLES),
    output:
        gfa = str(RUN_DIR / "minigraph" / "pangenome.gfa"),
        log = str(RUN_DIR / "minigraph" / "log.txt"),
    params:
        preset     = config["minigraph"].get("preset", "ggs"),
        min_sv_len = config["minigraph"].get("min_sv_len", 50),
        extra      = config["minigraph"].get("extra", ""),
        ref        = REFERENCE,
        samples    = SAMPLES,
        prep       = str(PREP_DIR),
    threads:
        config["minigraph"].get("threads", 8)
    resources:
        mem_mb  = config["resources"]["default"]["mem_mb"],
        runtime = config["resources"]["default"]["runtime"],
    conda:
        "../envs/minigraph.yaml"
    shell:
        r"""
        mkdir -p $(dirname {output.gfa})
        START=$(date +%s)

        # ordre : référence d'abord
        ordered_fas="{params.prep}/per_sample/{params.ref}.fa"
        for s in {params.samples}; do
            if [ "$s" != "{params.ref}" ]; then
                ordered_fas="$ordered_fas {params.prep}/per_sample/$s.fa"
            fi
        done

        {{
          echo "===== Minigraph =====";
          echo "Date          : $(date)";
          echo "Version       : $(minigraph --version)";
          echo "Référence     : {params.ref}";
          echo "Isolats       : {params.samples}";
          echo "Preset        : {params.preset}";
          echo "min SV length : {params.min_sv_len}";
          echo "Threads       : {threads}";
          echo "Extra args    : {params.extra}";
          echo "FASTAs (ordre): $ordered_fas";
          echo "---------------------------------";
        }} > {output.log}

        minigraph -cxggs -L {params.min_sv_len} -t {threads} {params.extra} \
            $ordered_fas > {output.gfa} 2>> {output.log}

        END=$(date +%s)
        echo "---------------------------------" >> {output.log}
        echo "Durée (s)     : $((END-START))"    >> {output.log}
        echo "GFA produit   : {output.gfa}"      >> {output.log}
        """
