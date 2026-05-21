# =============================================================================
# visu.smk — visualisation des graphes de pangénome
# =============================================================================
# Variables globales utilisées : RUN_DIR
# Activé uniquement si tools.visualisation: true dans config.yaml.
# Commande de lancement nécessaire : --use-singularity (image Bandage utilisée)
# =============================================================================


# --- Bandage pour Minigraph --------------------------------------------------
# Génère une image PNG du graphe Minigraph via Bandage 
# Pas d'image ODGI car pas de "path" dans les gfa produits par Minigraph
rule bandage_minigraph:
    input:
        gfa = str(RUN_DIR / "Minigraph" / "pangenome_MG.gfa"),
    output:
        png = str(RUN_DIR / "Minigraph" / "bandage_MG.png"),
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
        gfa = str(RUN_DIR / "PGGB" / "pangenome.gfa"),
    output:
        bandage = str(RUN_DIR / "PGGB" / "visu_images" / "bandage.png"),
    params:
        pggb_dir = str(RUN_DIR / "PGGB"),
        visu_dir = str(RUN_DIR / "PGGB" / "visu_images"),
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
