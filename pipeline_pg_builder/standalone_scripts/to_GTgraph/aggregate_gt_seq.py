#!/usr/bin/env python3
"""Agrège les GT seq par isolat (issus des .out SyRI d'un run) en UN SEUL GT
seq pour le run entier, avec un id_event globalement unique PAR TYPE.

Organisation retenue (cf. discussion) : remplissage, tri, concat, id_event.
  1. remplissage : parse tous les .out SyRI du run en une SEULE liste plate
     de lignes (pas de dict par type), en corrigeant au passage le bug de
     `merge_special_types` (cf. note plus bas) : INVDP -> DUP, INVTR -> TRA,
     et REELLEMENT renommé dans le champ "type" (contrairement à
     syri_to_GT_v2.merge_special_types, où la ligne de renommage est
     commentée -- à corriger là-bas aussi si vous réutilisez ce script).
  2. tri : UN SEUL appel à .sort() sur toute la liste, avec la clé
     (rang_du_type, id_ref, position_debut_sur_ref). Ça construit le bigGT
     dans son ordre final direct : les lignes du même type sont contiguës
     (garanti, car le rang du type est la clé primaire du tri), et triées
     par position à l'intérieur de chaque bloc de type -- exactement la
     précondition attendue par assigner_event.
  3. concat : déjà fait -- c'est une seule liste après le tri, pas besoin de
     recombiner des sous-tables.
  4. id_event : pour chaque bloc contigu de même type (itertools.groupby,
     sûr ici car le type est la clé primaire du tri), on appelle
     assigner_event UNE FOIS sur ce bloc.

Complexité : reste O(n log n) au global (dominé par le tri), comme
l'approche "trier chaque table de type puis les fusionner". Le seul (léger)
avantage théorique de trier chaque type séparément est
Sum(n_i log n_i) <= n log n (concavité du log) ; négligeable en pratique
face au gain de lisibilité d'un seul tri.

- Standalone : python aggregate_gt_seq.py ref_vs_i1_syri.out ref_vs_i2_syri.out ... \
               --outfile GT_seq_final.tsv
- Snakemake  : rule aggregate_gt_seq (script: "../scripts/aggregate_gt_seq.py")
"""
import argparse
import csv
import itertools
import sys
from pathlib import Path

# standalone_scripts/ est un dossier frère de workflow/scripts/ (racine pipeline_pg_builder/)
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "standalone_scripts"))

from assign_event import assigner_event, NULL_ITEM  # noqa: E402
from syri_to_GT_v2 import (  # noqa: E402
    get_id_allele, get_reverse, get_pos_qry, sv_length, COLUMNS,
)

# Types acceptés en sortie de SyRI (avant fusion)
RAW_TYPES = {"INS", "DEL", "INV", "DUP", "INVDP", "TRA", "INVTR", "TDM"}

# Fusion des types spéciaux -- ATTENTION : dans syri_to_GT_v2.merge_special_types,
# la ligne équivalente à ce dict (row["type"] = dest_type) est commentée : les
# lignes INVDP/INVTR y gardent leur type d'origine après fusion, ce qui casse
# un regroupement ultérieur par (type, id_event). Ici on renomme réellement.
RELABEL = {"INVDP": "DUP", "INVTR": "TRA"}

# Ordre final des types après fusion (6 types) -- sert de clé de tri primaire
# et sera aussi l'ordre des colonnes de la table GT_graph_nodes.tsv en aval.
FINAL_ORDER = ["INS", "DEL", "INV", "DUP", "TRA", "TDM"]


def _pos_start(pos_str):
    a, b = pos_str.strip("()").split(", ")
    return min(int(a), int(b))


def parse_syri_file(syri_file):
    """Lit un .out SyRI et retourne une liste de lignes GT seq à plat
    (pas de dict par type), type déjà fusionné/renommé, sans id_event.
    """
    rows = []
    with open(syri_file) as sf:
        for line in sf:
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 11:
                continue
            raw_type = fields[10]
            if raw_type not in RAW_TYPES:
                continue
            sv_type = RELABEL.get(raw_type, raw_type)
            rows.append({
                "id_event":       NULL_ITEM,  # rempli globalement à l'étape 4
                "type":           sv_type,
                "id_allele":      get_id_allele(sv_type, fields[1], fields[2]),
                "reverse":        get_reverse(sv_type, fields[6], fields[7]),
                "id_ref":         fields[0],
                "pos_ref":        f"({fields[1]}, {fields[2]})",
                "id_qry":         fields[5],
                "pos_qry":        get_pos_qry(sv_type, fields[6], fields[7]),
                "sv_length":      sv_length(sv_type, fields[1], fields[2], fields[6], fields[7]),
                "complex_region": NULL_ITEM,
                "fiability":      NULL_ITEM,
                "margin_of_error": NULL_ITEM,
                "TE":             NULL_ITEM,
                "info":           NULL_ITEM,
            })
    return rows


def aggregate(syri_out_files):
    # 1. remplissage : une seule liste plate, tous isolats confondus
    all_rows = []
    for syri_file in syri_out_files:
        all_rows.extend(parse_syri_file(syri_file))

    # 2. tri : un seul sort, clé = (rang_type, id_ref, position)
    #    -> les blocs de même type sont garantis contigus après ce tri,
    #    donc itertools.groupby(key=type) est sûr à l'étape 4.
    all_rows.sort(key=lambda r: (FINAL_ORDER.index(r["type"]), r["id_ref"], _pos_start(r["pos_ref"])))

    # 3. concat : déjà fait, all_rows EST le bigGT dans son ordre final

    # 4. id_event : assigner_event une fois par bloc contigu de même type
    for sv_type, block in itertools.groupby(all_rows, key=lambda r: r["type"]):
        assigner_event(list(block), sv_type)  # mutate en place (mêmes objets dict)

    # id_SV unique par ligne, sur le bigGT final
    for i, row in enumerate(all_rows, start=1):
        row["id_SV"] = f"SV{i}"

    return all_rows


def write_tsv(rows, outfile):
    fieldnames = COLUMNS + ["id_SV"]
    with open(outfile, "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)
    print(f"[aggregate_gt_seq] {len(rows)} lignes écrites dans {outfile} "
          f"(bigGT trié par type puis position, id_event global par type)")


def main(syri_out_files, outfile):
    rows = aggregate(syri_out_files)
    write_tsv(rows, outfile)


if "snakemake" in dir():
    _syri_outs = list(snakemake.input.syri_outs) if not isinstance(snakemake.input.syri_outs, str) \
        else [snakemake.input.syri_outs]
    main(_syri_outs, snakemake.output.gt_seq_final)
elif __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("syri_out_files", nargs="+", help="Fichiers .out SyRI (un par isolat non-référence)")
    parser.add_argument("--outfile", default="GT_seq_final.tsv")
    args = parser.parse_args()
    main(args.syri_out_files, args.outfile)
