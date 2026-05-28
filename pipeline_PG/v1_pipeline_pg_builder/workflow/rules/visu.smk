# =============================================================================
# visu.smk — visualisation des graphes de pangénome
# =============================================================================
# Variables globales utilisées : config
# Wildcard {run} : nom du dossier de sortie dérivé du nom du fichier FASTA d'entrée
# Activé uniquement si tools.visualisation: true dans config.yaml.
# Commande de lancement nécessaire : --use-singularity (image Bandage utilisée)
# =============================================================================

OUTPUT_DIR = config["output_dir"]

# --- Bandage pour Minigraph --------------------------------------------------
# Génère une image PNG du graphe Minigraph via Bandage
# Pas d'image ODGI car pas de "path" dans les gfa produits par Minigraph
rule bandage_minigraph:
    input:
        gfa = OUTPUT_DIR + "/{run}/Minigraph/pangenome_MG.gfa",
    output:
        png = OUTPUT_DIR + "/{run}/Minigraph/bandage_MG.png",
    container:
        "docker://quay.io/biocontainers/bandage:0.9.0--h9948957_0"
    shell:
        """
        Bandage image {input.gfa} {output.png} --height 800
        """


# --- Bandage pour Minigraph-Cactus ------------------------------------------
# Génère une image PNG du graphe Minigraph-Cactus via Bandage

rule bandage_mc:
    input:
        gfa = OUTPUT_DIR + "/{run}/MinigraphCactus/pangenome_MC.gfa",
    output:
        png = OUTPUT_DIR + "/{run}/MinigraphCactus/bandage_MC.png",
    container:
        "docker://quay.io/biocontainers/bandage:0.9.0--h9948957_0"
    shell:
        """
        Bandage image {input.gfa} {output.png} --height 800
        """


# --- Bandage + collecte des png PGGB ------------------------------------
# Génère une image Bandage du graphe PGGB et déplace tous les PNGs
# produits automatiquement par PGGB dans le dossier visu_images/.

rule pggb_visu:
    input:
        gfa = OUTPUT_DIR + "/{run}/PGGB/pangenome.gfa",
    output:
        bandage = OUTPUT_DIR + "/{run}/PGGB/visu_images/bandage.png",
    params:
        pggb_dir = lambda wc: OUTPUT_DIR + f"/{wc.run}/PGGB",
        visu_dir = lambda wc: OUTPUT_DIR + f"/{wc.run}/PGGB/visu_images",
    container:
        "docker://quay.io/biocontainers/bandage:0.9.0--h9948957_0"
    shell:
        r"""
        mkdir -p {params.visu_dir}

        # Déplace les PNGs générés automatiquement par PGGB dans visu_images/
        # (|| true pour ne pas échouer si déjà déplacés lors d'un re-run)
        mv {params.pggb_dir}/*.png {params.visu_dir}/ 2>/dev/null || true

        # Génère l'image Bandage du graphe final
        Bandage image {input.gfa} {output.bandage} --height 800
        """
