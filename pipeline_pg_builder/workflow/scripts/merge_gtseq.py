"""Fusionne les tables GT de TOUS les isolats d'un run en une seule table,
puis réassigne les id_event à l'échelle du run entier (et non plus isolat
par isolat) — c'est cette fusion qui permet de détecter qu'un même évènement
structurel est partagé par plusieurs isolats.

Appelé par la règle `merge_gtseq` du Snakefile (script: directive).
Réutilise SANS LES MODIFIER les fonctions déjà écrites dans syri_to_GT_v2.py
et assign_event.py (même dossier workflow/scripts/).
"""
import csv
from pathlib import Path

from syri_to_GT_v3 import ORDER, sort_rows, write_tables, write_big_GT
from assign_event import assigner_event


def read_gt_tsv(path):
    """Lit un GT_<type>.tsv déjà produit par syri_to_GT_v2.py pour UN isolat.
    On ignore la colonne id_event déjà présente : elle sera entièrement
    recalculée après fusion de tous les isolats (les anciens ids n'ont de
    sens que dans le contexte d'un seul isolat)."""
    with open(path, newline="") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def merge_gt(sample_big_gt_files, outdir):
    """sample_big_gt_files : liste des BIG_GT.tsv, un par isolat non-référence
                             (sert juste à retrouver le dossier GT/ de chaque isolat)
    outdir                 : dossier de sortie pour les tables fusionnées du run
    """
    # Un dossier GT/ par isolat (celui qui contient GT_DEL.tsv, GT_INS.tsv, etc.)
    sample_gt_dirs = [Path(f).parent for f in sample_big_gt_files]

    GTs_by_type = {t: [] for t in ORDER}

    # Concatène les lignes de TOUS les isolats, type de SV par type de SV
    for sv_type in ORDER:
        for gt_dir in sample_gt_dirs:
            f = gt_dir / f"GT_{sv_type}.tsv"
            if f.exists():  # un isolat peut ne pas avoir ce type de SV
                GTs_by_type[sv_type].extend(read_gt_tsv(f))

    # Pour chaque type : trie par position sur la référence (TOUS isolats
    # mélangés) puis réassigne les id_event -> regroupe maintenant les MÊMES
    # évènements détectés dans PLUSIEURS isolats différents
    for sv_type, rows in GTs_by_type.items():
        if rows:
            sort_rows(rows)
            GTs_by_type[sv_type] = assigner_event(rows, sv_type)

    write_tables(GTs_by_type, outdir)
    write_big_GT(GTs_by_type, outdir)


# --- Snakemake entry point ---------------------------------------------------
if "snakemake" in dir():
    merge_gt(
        sample_big_gt_files=list(snakemake.input.sample_big_gt),
        outdir=snakemake.params.outdir,
    )