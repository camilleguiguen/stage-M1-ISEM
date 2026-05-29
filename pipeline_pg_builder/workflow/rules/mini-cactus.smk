# =============================================================================
# mini-cactus — préparation (seqfile) + construction du graphe
#               Minigraph-Cactus (cactus-pangenome)
# =============================================================================
# Variables globales utilisées : config, RUNS
# Wildcard {run} : nom du dossier de sortie dérivé du nom du fichier FASTA d'entrée
# Nécessite --use-singularity.
#
# Format d'entrée Cactus : un "seqfile" TSV (nom<TAB>chemin_fasta)
#   - la référence doit être en PREMIÈRE ligne
#   - chaque ligne = un isolat avec son fichier FASTA individuel
# Les fichiers par isolat sont produits par extract_isolate (minigraph.smk).
# =============================================================================

OUTPUT_DIR = config["output_dir"]

# --- Étape 1 : générer le seqfile TSV pour cactus-pangenome -----------------
# Le seqfile liste : référence en 1re ligne, puis les autres isolats.
# cactus-pangenome utilise ce fichier pour localiser les séquences.

rule prepare_seqfile:
    input:
        # Dépend de tous les FASTA par isolat produits par extract_isolate
        fastas = lambda wc: expand(
            OUTPUT_DIR + "/{run}/per_sample/{sample}.fa",
            run=wc.run,
            sample=RUNS[wc.run]["samples"],
        ),
    output:
        seqfile = OUTPUT_DIR + "/{run}/MinigraphCactus/seqfile.tsv",
    params:
        reference  = lambda wc: RUNS[wc.run]["reference"],
        samples    = lambda wc: RUNS[wc.run]["samples"],
        sample_dir = lambda wc: OUTPUT_DIR + f"/{wc.run}/per_sample",
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
        seqfile = OUTPUT_DIR + "/{run}/MinigraphCactus/seqfile.tsv",
    output:
        gfa = OUTPUT_DIR + "/{run}/MinigraphCactus/pangenome_MGC.gfa",
        log = OUTPUT_DIR + "/{run}/MinigraphCactus/minigraph_cactus.log",
    params:
        outdir    = lambda wc: OUTPUT_DIR + f"/{wc.run}/MinigraphCactus",
        jobstore  = lambda wc: OUTPUT_DIR + f"/{wc.run}/MinigraphCactus/jobstore",
        reference = lambda wc: RUNS[wc.run]["reference"],
    threads:
        config["minigraph_cactus"].get("threads", 4)
    container:
        "docker://quay.io/comparative-genomics-toolkit/cactus:v3.2.1"
    shell:
        r"""
        mkdir -p {params.outdir}
        # Nettoie le jobstore d'une éventuelle run précédente — sinon Toil refuse de démarrer
        rm -rf {params.jobstore}

        # cactus-pangenome produit un GFA dans outdir/
        # --maxCores limite le nombre de cœurs utilisés
        # --reference désigne l'isolat de référence (doit correspondre à la 1re ligne du seqfile)
        cactus-pangenome {params.jobstore} {input.seqfile} \
            --outDir {params.outdir} \
            --outName pangenome_MGC \
            --reference {params.reference} \
            --maxCores {threads} \
            --gfa \
            > {output.log} 2>&1

        # Le GFA final est nommé pangenome_MGC.gfa dans outDir
        # → on vérifie qu'il est bien là (cactus peut varier le nom exact)
        final=$(ls {params.outdir}/pangenome_MGC*.gfa 2>/dev/null | head -1)
        [ -n "$final" ] && [ "$final" != "{output.gfa}" ] && mv "$final" {output.gfa}
        """
