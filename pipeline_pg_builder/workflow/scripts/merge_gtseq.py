"""Fusionne les tables GT de TOUS les isolats d'un run en une seule table,
puis reassigne les id_event a l'echelle du run entier.

Etapes (cf. discussion) :
  1. concatene les GT_<type>.tsv de tous les isolats, TYPE PAR TYPE
     (ex : tous les GT_INS.tsv -> une seule liste INS)
  2. trie chaque liste de type par position sur la reference -> BIG_GT_<type>.tsv
  3. concatene les BIG_GT_<type> dans l'ordre de ORDER, SANS melanger les
     types (toutes les INS, puis toutes les DEL, etc.) -- on ne retrie plus
     jamais apres ca (c'etait le bug : l'ancien write_big_GT retriait par
     id_qry, ce qui detruisait ce regroupement)
  4. assigne les id_event, un bloc de type a la fois, sur le bigGT deja
     concatene (itertools.groupby, sur ici car le type est reste la cle de
     tri primaire -> les blocs sont garantis contigus)
"""
import csv
import itertools
import os
from pathlib import Path

from syri_to_GTseq import ORDER, sort_rows
from assign_event import assigner_event


def read_gt_tsv(path):
    with open(path, newline="") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def write_per_type_tables(GTs_by_type, outdir):
    """Ecrit un BIG_GT_<type>.tsv par type -- distinct des GT_<type>.tsv
    par isolat (memes colonnes, mais fusionnes/tries sur tout le run)."""
    os.makedirs(outdir, exist_ok=True)
    for sv_type in ORDER:
        rows = GTs_by_type.get(sv_type, [])
        if not rows:
            continue
        outfile = Path(outdir) / f"BIG_GT_{sv_type}.tsv"
        with open(outfile, "w", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()), delimiter="\t")
            writer.writeheader()
            writer.writerows(rows)
        print(f"Cree : {outfile} ({len(rows)} lignes)")


def write_big_GT(all_rows, outdir):
    """Ecrit le BIG_GT.tsv final : toutes les BIG_GT_<type> concatenees
    DANS L'ORDRE DE ORDER, sans aucun tri supplementaire."""
    os.makedirs(outdir, exist_ok=True)
    outfile = Path(outdir) / "BIG_GT.tsv"
    fieldnames = list(all_rows[0].keys()) if all_rows else []
    with open(outfile, "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerows(all_rows)
    print(f"Cree : {outfile} ({len(all_rows)} lignes)")


def merge_gt(sample_big_gt_files, outdir):
    sample_gt_dirs = [Path(f).parent for f in sample_big_gt_files]
    GTs_by_type = {t: [] for t in ORDER}

    # 1) concatene les GT_<type>.tsv de tous les isolats, type par type
    for sv_type in ORDER:
        for gt_dir in sample_gt_dirs:
            f = gt_dir / f"GT_{sv_type}.tsv"
            if f.exists():
                GTs_by_type[sv_type].extend(read_gt_tsv(f))

    # 2) trie chaque table de type par (id_ref, pos_ref) -> BIG_GT_<type>
    for sv_type, rows in GTs_by_type.items():
        if rows:
            sort_rows(rows)
    write_per_type_tables(GTs_by_type, outdir)

    # 3) concatene toutes les BIG_GT_<type> dans l'ordre de ORDER
    all_rows = []
    for sv_type in ORDER:
        all_rows.extend(GTs_by_type.get(sv_type, []))

    # 4) assignation des evenements, un bloc de type a la fois
    for sv_type, block in itertools.groupby(all_rows, key=lambda r: r["type"]):
        assigner_event(list(block), sv_type)

    write_big_GT(all_rows, outdir)


if "snakemake" in dir():
    merge_gt(
        sample_big_gt_files=list(snakemake.input.sample_big_gt),
        outdir=snakemake.params.outdir,
    )
