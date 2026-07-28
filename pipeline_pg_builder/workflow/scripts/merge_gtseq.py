"""Fusionne directement les .out SyRI de TOUS les isolats d'un run en tables
BIG_GT_<type>.tsv + BIG_GT.tsv, sans étape intermédiaire par isolat.

Étapes :
  1. parse chaque {sample}_syri.out avec parse_syri() (syri_to_GTseq.py)
     -> dict {type: [lignes]} pour CET isolat
  2. fusionne tous les isolats, type par type, dans un seul gros dict
  3. trie chaque liste de type par (id_ref, pos_ref) -> BIG_GT_<type>.tsv
  4. concatène les BIG_GT_<type> dans l'ordre de ORDER, SANS mélanger les
     types (toutes les INS, puis toutes les DEL, etc.)
  5. réassigne les id_event, un bloc de type à la fois (itertools.groupby,
     valide ici car le type reste la clé de tri primaire -> blocs contigus),
     avec un offset qui ne repart pas à 0 à chaque nouveau type
"""
import csv
import itertools
import os
from pathlib import Path

from syri_to_GTseq import ORDER, parse_syri, sort_rows
from assign_event import assigner_event


def write_per_type_tables(GTs_by_type, outdir):
    """Écrit un BIG_GT_<type>.tsv par type présent (type absent du run -> pas
    de fichier, même logique que les anciennes GT_<type>.tsv par isolat)."""
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
        print(f"Créé : {outfile} ({len(rows)} lignes)")


def write_big_GT(all_rows, outdir):
    os.makedirs(outdir, exist_ok=True)
    outfile = Path(outdir) / "BIG_GT.tsv"
    fieldnames = list(all_rows[0].keys()) if all_rows else []
    with open(outfile, "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerows(all_rows)
    print(f"Créé : {outfile} ({len(all_rows)} lignes)")


def merge_gt(syri_out_files, outdir):
    GTs_by_type = {t: [] for t in ORDER}

    # 1) parse chaque .out et fusionne directement type par type
    #    (parse_syri applique déjà le filtre MIN_SV_LENGTH et le merge
    #    INVDP->DUP / INVTR->TRA en interne)
    for syri_out in syri_out_files:
        sample_GTs = parse_syri(syri_out)
        for sv_type, rows in sample_GTs.items():
            GTs_by_type[sv_type].extend(rows)

    # 2) trie chaque table de type par (id_ref, pos_ref) -> BIG_GT_<type>
    for rows in GTs_by_type.values():
        if rows:
            sort_rows(rows)
    write_per_type_tables(GTs_by_type, outdir)

    # 3) concatène toutes les BIG_GT_<type> dans l'ordre de ORDER
    all_rows = []
    for sv_type in ORDER:
        all_rows.extend(GTs_by_type.get(sv_type, []))

    # 4) réassigne les id_event, un bloc de type à la fois, avec offset continu
    #    (les id_event assignés localement dans parse_syri par isolat sont
    #    ici écrasés -> normal, ils n'avaient de sens qu'à l'échelle de l'isolat)
    offset = 0
    for sv_type, block in itertools.groupby(all_rows, key=lambda r: r["type"]):
        block_rows = list(block)
        assigner_event(block_rows, sv_type)
        for row in block_rows:
            row["id_event"] = int(row["id_event"]) + offset
        if block_rows:
            offset = max(int(r["id_event"]) for r in block_rows) + 1

    write_big_GT(all_rows, outdir)


if "snakemake" in dir():
    merge_gt(
        syri_out_files=list(snakemake.input.syri_outs),
        outdir=snakemake.params.outdir,
    )