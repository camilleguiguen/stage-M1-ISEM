# =============================================================================
# mini-cactus — préparation (seqfile) + construction du graphe
#                         Minigraph-Cactus (cactus-pangenome)
# =============================================================================
# Variables globales utilisées : config, RUN_DIR, SAMPLES, REFERENCE
# Nécessite --use-singularity.
#
# Format d'entrée Cactus : un "seqfile" TSV (nom<TAB>chemin_fasta)
#   - la référence doit être en PREMIÈRE ligne
#   - chaque ligne = un isolat avec son fichier FASTA individuel
# Les fichiers par isolat sont produits par extract_isolate (minigraph.smk).
# =============================================================================


# --- Étape 1 : générer le seqfile TSV pour cactus-pangenome -----------------
# Le seqfile liste : référence en 1re ligne, puis les autres isolats.
# cactus-pangenome utilise ce fichier pour localiser les séquences.

rule prepare_seqfile:
    input:
        # Dépend de tous les FASTA par isolat produits par extract_isolate
        fastas = expand(str(RUN_DIR / "per_sample" / "{sample}.fa"), sample=SAMPLES),
    output:
        seqfile = str(RUN_DIR / "MinigraphCactus" / "seqfile.tsv"),
    params:
        reference  = REFERENCE,
        samples    = SAMPLES,
        sample_dir = str(RUN_DIR / "per_sample"),
    run:
        import os
        os.makedirs(os.path.dirname(output.seqfile), exist_ok=True)
        with open(output.seqfile, "w") as fh:
            # Référence en première ligne — obligatoire pour cactus-pangenome
            ref_fa = os.path.join(params.sample_dir, f"{params.reference}.fa")
            fh.write(f"{params.reference}\t{ref_fa}\n")
            for s in params.samples:
                if s != params.reference:
                    fh.write(f"{s}\t{os.path.join(params.sample_dir, s + '.fa')}\n")


# --- Étape 2 : lancer cactus-pangenome --------------------------------------

rule run_minigraph_cactus:
    input:
        seqfile = str(RUN_DIR / "MinigraphCactus" / "seqfile.tsv"),
    output:
        gfa = str(RUN_DIR / "MinigraphCactus" / "pangenome_MC.gfa"),
        log = str(RUN_DIR / "MinigraphCactus" / "minigraph_cactus.log"),
    params:
        outdir   = str(RUN_DIR / "MinigraphCactus"),
        jobstore = str(RUN_DIR / "MinigraphCactus" / "jobstore"),
        reference = REFERENCE,
    threads:
        config["minigraph_cactus"].get("threads", 4)
    container:
        "docker://quay.io/comparative-genomics-toolkit/cactus:v3.2.1"
    shell:
        r"""
        mkdir -p {params.outdir}

        # cactus-pangenome produit un GFA dans outdir/
        # --maxCores limite le nombre de cœurs utilisés
        # --reference désigne l'isolat de référence (doit correspondre à la 1re ligne du seqfile)
        
        cactus-pangenome {params.jobstore} {input.seqfile} \
            --outDir {params.outdir} \
            --outName pangenome_MC \
            --reference {params.reference} \
            --maxCores {threads} \
            --gfa \
            > {output.log} 2>&1

        # Le GFA final est nommé pangenome_MC.gfa dans outDir
        
        # → on vérifie qu'il est bien là (cactus peut varier le nom exact)
        final=$(ls {params.outdir}/pangenome_MC*.gfa 2>/dev/null | head -1)
        [ -n "$final" ] && [ "$final" != "{output.gfa}" ] && mv "$final" {output.gfa}
        """
