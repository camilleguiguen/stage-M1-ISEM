# =============================================================================
# ground_truth_graph.smk — du GT seq au GT sur graphe (via AGAT puis GrAnnoT)
# =============================================================================
# Variables globales utilisées : config, RUNS
# Wildcard {run} : nom du dossier de sortie dérivé du nom du fichier FASTA d'entrée
#
# Pré-requis :
#   - tools.syri: true (ce module part des .out SyRI produits par syri.smk)
#   - tools.pggb: true OU tools.minigraph_cactus: true
#     (GrAnnoT a besoin d'un GFA avec des Path/Walk -> le rGFA de Minigraph
#      seul n'est PAS compatible, cf. papier GrAnnoT §Discussion)
#   - un environnement conda avec AGAT (bioconda `agat`) pour la conversion
#     BED -> GFF3, et un environnement conda avec GrAnnoT + bedtools.
#     Même solution temporaire que pour SyRI (syri.smk) : conda activate
#     dans le shell de la rule, pas d'image Apptainer pour ces deux outils.
#
# Chaîne de règles :
#   run_syri (syri.smk, déjà existant)
#     -> aggregate_gt_seq   : combine tous les isolats, id_event global par
#                             type (remplissage, tri, concat, id_event)
#     -> gt_seq_to_bed      : 1 feature = 1 BED par type de SV + features_meta.tsv
#     -> run_agat_bed2gff   : AGAT (agat_convert_bed2gff.pl) convertit chaque
#                             BED en GFF3, puis on les concatène
#     -> run_grannot        : projette le GFF3 sur le graphe -> GAF + BED réf
#     -> gt_graph           : ancres, nb_noeuds, sous_GT -> GT_graph_*.tsv
# =============================================================================

import os

OUTPUT_DIR = config["output_dir"]

# 6 types finaux après fusion des types spéciaux (cf. aggregate_gt_seq.RELABEL)
GT_TYPES = ["INS", "DEL", "INV", "DUP", "TRA", "TDM"]

# Quel GFA utiliser comme graphe pour GrAnnoT (doit avoir des Path/Walk).
# "pggb" ou "minigraph_cactus" -- PAS "minigraph" (rGFA, pas de Path).
_GT_GRAPH_SOURCE = config.get("ground_truth", {}).get("graph_source", "pggb")

def _graph_gfa_for_grannot(run):
    rd = RUNS[run]["run_dir"]
    if _GT_GRAPH_SOURCE == "minigraph_cactus":
        return str(rd / "MinigraphCactus" / "pangenome_MGC.gfa")
    return str(rd / "PGGB" / "pangenome.gfa")

# Chemin vers le script d'init conda (même remarque que SYRI_ENV_BIN /
# conda_sh dans syri.smk : un simple export PATH ne suffit pas, il faut un
# vrai `conda activate` pour que les bibliothèques partagées soient trouvées).
# TODO : chemin propre à l'utilisateur/cluster, comme dans syri.smk.
_CONDA_SH = "/home/genouest/cnrs_umr5554/cguiguen/miniconda3/etc/profile.d/conda.sh"
_AGAT_ENV = config.get("ground_truth", {}).get("agat_conda_env", "agat-env")
_GRANNOT_ENV = config.get("ground_truth", {}).get("grannot_conda_env", "grannot-env")


# --- Étape 0 : agréger le GT seq de tous les isolats du run, avec un
#     id_event GLOBALEMENT unique par type (remplissage, tri, concat, id_event)

rule aggregate_gt_seq:
    input:
        syri_outs = lambda wc: expand(
            OUTPUT_DIR + "/{run}/SyRI/{sample}_syri/{sample}_syri.out",
            run=wc.run,
            sample=[s for s in RUNS[wc.run]["samples"] if s != RUNS[wc.run]["reference"]],
        ),
    output:
        gt_seq_final = OUTPUT_DIR + "/{run}/GroundTruth/GT_seq_final.tsv",
    script:
        "../scripts/aggregate_gt_seq.py"


# --- Étape 1 : GT seq -> un BED par type de SV + métadonnées ---------------
# (le BED est un format intermédiaire : c'est AGAT, à l'étape suivante, qui
# fera la vraie conversion vers GFF3 -- cf. docstring de gt_seq_to_bed.py)

rule gt_seq_to_bed:
    input:
        gt_seq = OUTPUT_DIR + "/{run}/GroundTruth/GT_seq_final.tsv",
    output:
        beds = expand(
            OUTPUT_DIR + "/{{run}}/GroundTruth/GT_bed/GT_seq.{t}.bed", t=GT_TYPES,
        ),
        meta = OUTPUT_DIR + "/{run}/GroundTruth/features_meta.tsv",
    script:
        "../scripts/gt_seq_to_bed.py"


# --- Étape 2 : AGAT -- BED (un par type) -> GFF3 (fusionné) -----------------
# agat_convert_bed2gff.pl convertit un BED en GFF3 (coordonnées 0-based
# demi-ouvertes -> 1-based fermées gérées automatiquement par l'outil).
# --primary_tag (colonne 3 du GFF3, le type de la feature) est un paramètre
# PAR FICHIER, pas par ligne : on appelle donc AGAT une fois par type de SV,
# puis on concatène les GFF3 obtenus (en ne gardant qu'un seul en-tête).

rule run_agat_bed2gff:
    input:
        beds = expand(
            OUTPUT_DIR + "/{{run}}/GroundTruth/GT_bed/GT_seq.{t}.bed", t=GT_TYPES,
        ),
    output:
        gff3 = OUTPUT_DIR + "/{run}/GroundTruth/GT_seq.gff3",
    params:
        conda_sh  = _CONDA_SH,
        conda_env = _AGAT_ENV,
        types     = GT_TYPES,
    run:
        import subprocess
        with open(output.gff3, "w") as out:
            out.write("##gff-version 3\n")
        for bed_path, sv_type in zip(input.beds, params.types):
            if os.path.getsize(bed_path) == 0:
                continue  # aucun événement de ce type dans ce run
            cmd = (
                f"source {params.conda_sh} && conda activate {params.conda_env} && "
                f"agat_convert_bed2gff.pl --bed {bed_path} "
                f"--source GTseq_PanQueSt --primary_tag {sv_type} --inflate_off"
            )
            result = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, check=True)
            with open(output.gff3, "a") as out:
                for line in result.stdout.splitlines():
                    if line.startswith("##"):
                        continue
                    out.write(line + "\n")


# --- Étape 3 : GrAnnoT -- projette le GFF3 sur le graphe pangénomique -----
# Comme pour SyRI (syri.smk) : environnement conda activé dans le shell,
# pas d'image Apptainer.
# TODO : commande exacte à vérifier avec `grannot --help` (nom du binaire,
# noms exacts des options -- ce qui suit est un squelette à ajuster).
# TODO : emplacement exact du GAF et du BED de la référence dans les
# sorties de GrAnnoT à vérifier (dépend de la version) ; adapter les
# chemins ci-dessous en conséquence.

rule run_grannot:
    input:
        gff3 = OUTPUT_DIR + "/{run}/GroundTruth/GT_seq.gff3",
        gfa  = lambda wc: _graph_gfa_for_grannot(wc.run),
    output:
        gaf     = OUTPUT_DIR + "/{run}/GroundTruth/GrAnnoT/annotation.gaf",
        ref_bed = OUTPUT_DIR + "/{run}/GroundTruth/GrAnnoT/reference.bed",
    params:
        outdir    = lambda wc: OUTPUT_DIR + f"/{wc.run}/GroundTruth/GrAnnoT",
        reference = lambda wc: RUNS[wc.run]["reference"],
        conda_sh  = _CONDA_SH,
        conda_env = _GRANNOT_ENV,
        extra     = config.get("ground_truth", {}).get("grannot_extra_args", ""),
    shell:
        r"""
        mkdir -p {params.outdir}

        source {params.conda_sh}
        conda activate {params.conda_env}

        # TODO : adapter l'appel exact à GrAnnoT (nom du script/entry point,
        # noms d'options) -- squelette indicatif d'après vos notes :
        grannot \
            --gfa {input.gfa} \
            --gff3 {input.gff3} \
            --reference {params.reference} \
            --gaf \
            --outdir {params.outdir} \
            {params.extra}

        # TODO : GrAnnoT écrit le GAF + les BED par génome quelque part sous
        # {params.outdir} -- retrouver les noms réels et les copier/lier vers
        # les chemins attendus par la rule :
        #   ex. cp {params.outdir}/*.gaf {output.gaf}
        #       cp {params.outdir}/*{params.reference}*.bed {output.ref_bed}
        """


# --- Étape 4-5-6 : GAF + BED -> ancres, nb_noeuds, sous_GT -> GT graph -----

rule gt_graph:
    input:
        gaf     = OUTPUT_DIR + "/{run}/GroundTruth/GrAnnoT/annotation.gaf",
        ref_bed = OUTPUT_DIR + "/{run}/GroundTruth/GrAnnoT/reference.bed",
        meta    = OUTPUT_DIR + "/{run}/GroundTruth/features_meta.tsv",
    output:
        events = OUTPUT_DIR + "/{run}/GroundTruth/GT_graph_events.tsv",
        nodes  = OUTPUT_DIR + "/{run}/GroundTruth/GT_graph_nodes.tsv",
    script:
        "../scripts/gaf_to_gt_graph.py"
