#!/usr/bin/env python3

# Convert a SyRI .out file to per-type GT tables.

# - Standalone : python syri_to_GT_v2.py <syri.out> [--outdir <dir>]
#           ex : python syri_to_GT_v2.py i1vs2_syri.out --outdir outdirGT_test
# - Snakemake  : rule syri_to_gt: script: "syri_to_GT.py"

# Nbline / file :  wc -l *.tsv | sort -rn
# Pretty print  :  head -5 *.tsv | column -t -s $'\t'



import argparse
import csv
import os
import warnings
from pathlib import Path

from assign_event import assigner_event

NULL_ITEM = "-"

ORDER = ["INS", "DEL", "INV", "DUP", "INVDP", "TRA", "INVTR", "TDM"]

COLUMNS = [
    "id_event", "type", "id_allele", "reverse",
    "id_ref", "pos_ref", "id_qry", "pos_qry",
    "sv_length", "complex_region", "fiability",
    "margin_of_error", "TE", "info",
]

#========================================================================================
#               FONCTIONS PERMETTANT DE REMPLIR LES COLONNES DU GTSEQ
#========================================================================================


def get_id_allele(sv_type, ref_start=None, ref_end=None):
    """
    - Tt sauf DEL/TDM : "B1"
    - DEL     : "BO" 
    - TDM     : "[nb_copies]_[motif ≤ 100] " -> TODO post traitement
    - sinon   : NULL_ITEM
    """
    if sv_type == "TDM":
        # TODO : post-traitement voir comment recuperer le nb de copies et le motif
        raise ValueError(f"le type est TDM : cas non géré, à post-traiter")
        return NULL_ITEM
    if sv_type == "DEL" :
        return "B0"
    if sv_type in ("INS", "INV", "INVDP", "TRA", "INVTR", "DUP"):
        return "B1"

    return NULL_ITEM


def get_reverse(sv_type, qry_start, qry_end):
    if qry_start == NULL_ITEM or qry_end == NULL_ITEM:
        return NULL_ITEM
    if sv_type in ("INVDU", "INV", "INVTR") :
        return 1
    reverse_qry = int(qry_start) > int(qry_end)
    if reverse_qry :
        warnings.warn(f"qry_start ({qry_start}) > qry_end ({qry_end}) pour sv_type={sv_type}, cas non géré")
    return 0


def get_pos_qry(sv_type, qry_start, qry_end):
    # si c'est une délétion, on rempli pos_qry comme : (qry_start),
    # et sauf si NULL_ITEM, on rempli pos_qry comme :  (qry_start, qry_end).
    if sv_type == "DEL":
        return f"({qry_start})"
    if qry_start == NULL_ITEM or qry_end == NULL_ITEM:
        return NULL_ITEM
    return f"({qry_start}, {qry_end})"


def sv_length(sv_type, ref_start, ref_end, qry_start, qry_end):
    # si c'est une deletion on rempli comme : (- taille_délétion)
    # TODO : comment faire en cas de reverse ? raj if reverse = False ?
    if qry_start != NULL_ITEM and qry_end != NULL_ITEM :
        if sv_type == "DEL" :
            taille_DEL = int(ref_start) - int(ref_end) - 1
            return f"({taille_DEL})"
        else :
            return int(qry_end) - int(qry_start) + 1
    else :
        return NULL_ITEM


MIN_SV_LENGTH = 50


def passes_length_filter(sv_length_value):
    # renvoie False si |sv_length| < MIN_SV_LENGTH (filtre les petits SV)
    # sv_length_value peut être : int, str du type "(123)" (cas DEL), ou NULL_ITEM
    if sv_length_value == NULL_ITEM:
        return True  # on ne filtre pas les valeurs non calculables

    if isinstance(sv_length_value, str):
        length = int(sv_length_value.strip("()"))
    else:
        length = sv_length_value

    return abs(length) >= MIN_SV_LENGTH


def merge_special_types(GTs_by_type):
    # si la table INVTR ou INVDP existe, ajoute ses lignes à TRA ou DUP puis vide la table d'origine
    # TODO : j'ai pas encore renommé les types parce que comment on va faire pour les identifier ?
    for src_type, dest_type in (("INVTR", "TRA"), ("INVDP", "DUP")):
        if GTs_by_type.get(src_type):
            for row in GTs_by_type[src_type]:
                # row["type"] = dest_type  # pour renommer le type vers la table de destination
                GTs_by_type[dest_type].append(row)
            GTs_by_type[src_type] = []

def _parse_pos(pos_str):
    a, b = pos_str.strip("()").split(", ")
    return int(a), int(b)


def sort_rows(rows):
    # Trie par (id_ref, ref_start) croissant — fonctionne pour tous les types
    rows.sort(key=lambda r: (
        r["id_ref"],
        _parse_pos(r["pos_ref"])[0],
    ))


def sort_rows_by_qry(rows):
    # Trie par (id_qry, ref_start) croissant
    rows.sort(key=lambda r: (
        r["id_qry"],
        _parse_pos(r["pos_ref"])[0],
    ))


#========================================================================================
#               FONCTIONS DE LECTURE ET D'ÉCRITURE DES DONNÉES
#   - parse_syri(...)    : lit le .out SyRI et retourne un dict {type: [lignes]}
#   - write_tables(...)  : écrit un TSV par type SV dans le dossier de sortie
#   - main(...)          : point d'entrée commun CLI ou Snakemake
#========================================================================================

def parse_syri(syri_file):
    # Initialise dico de type {"INS": [], "DEL": [], "INV": [], ...}
    GTs_by_type = {t: [] for t in ORDER}

    with open(syri_file) as sf:
        # Partitionne les data du .out, verifie son nb de colonnes 
        for line in sf:
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 11:
                continue
            # Vérifie que le type est dans ORDER pour l'écrire.
            sv_type = fields[10]
            if sv_type not in GTs_by_type:
                continue

            length_value = sv_length(sv_type, fields[1], fields[2], fields[6], fields[7])
            if not passes_length_filter(length_value):
                continue

            GTs_by_type[sv_type].append({
                "id_event":       NULL_ITEM,
                "type":           sv_type,
                "id_allele":      get_id_allele(sv_type, fields[1], fields[2]),
                "reverse":        get_reverse(sv_type, fields[6], fields[7]),
                "id_ref":         fields[0],
                "pos_ref":        f"({fields[1]}, {fields[2]})",
                "id_qry":         fields[5],
                "pos_qry":        get_pos_qry(sv_type, fields[6], fields[7]),
                "sv_length":      length_value,
                "complex_region": NULL_ITEM,
                "fiability":      NULL_ITEM,
                "margin_of_error": NULL_ITEM,
                "TE":             NULL_ITEM,
                "info":           NULL_ITEM,
            })
    
    # merge des types spéciaux (INVDP va dans DUP, INVTR va dans TRA)
    merge_special_types(GTs_by_type)

    # Trie chaque table par (id_ref, start_ref) puis assigne id_event (cf. assign_event.py) :
    for sv_type, rows in GTs_by_type.items():
        if rows:
            sort_rows(rows)
            GTs_by_type[sv_type] = assigner_event(rows, sv_type)

    return GTs_by_type


def write_tables(GTs_by_type, outdir):
    os.makedirs(outdir, exist_ok=True)
    # itère sur les types dans l'ordre défini (pas l'ordre d'apparition dans le fichier)
    for sv_type in ORDER:
        rows = GTs_by_type.get(sv_type, [])
        if not rows:
            continue

        #trie des tables en fonction de leur pos_ref
        sort_rows(rows) 

        outfile = Path(outdir) / f"GT_{sv_type}.tsv"
        # ouvre le fichier en écriture et crée un écrivain (newline="" évite les \r\n)
        with open(outfile, "w", newline="") as outtsv:
            writer = csv.DictWriter(outtsv, fieldnames=COLUMNS, delimiter="\t")
            writer.writeheader()
            writer.writerows(rows)
        print(f"Créé : {outfile} ({len(rows)} lignes)")


def write_big_GT(GTs_by_type, outdir):
    os.makedirs(outdir, exist_ok=True)

    # rassemble toutes les lignes de tous les types
    all_rows = []
    for sv_type in ORDER:
        all_rows.extend(GTs_by_type.get(sv_type, []))

    # trie par id_qry puis par ref_start
    sort_rows_by_qry(all_rows)

    outfile = Path(outdir) / "BIG_GT.tsv"
    with open(outfile, "w", newline="") as outtsv:
        writer = csv.DictWriter(outtsv, fieldnames=COLUMNS, delimiter="\t")
        writer.writeheader()
        writer.writerows(all_rows)
    print(f"Créé : {outfile} ({len(all_rows)} lignes)")


def main(syri_out, outdir=None):
    # si pas de outdir en param : 
    # ex : i1vs2_syri.out → outdirGT_i1vs2/
    if outdir is None:
        syri_path = Path(syri_out)
        outdir = f"outdirGT_{syri_path.name.split('_')[0]}"

    GTs_by_type = parse_syri(syri_out)
    write_tables(GTs_by_type, outdir)
    write_big_GT(GTs_by_type, outdir)



#========================================================================================
#        BLOC VERIFIANT SI ON EST APPELÉ PAR SNAKEMAKE OU Command-Line 
#========================================================================================

# -- Snakemake entry point --
# on lit les inputs/params depuis la rule
if "snakemake" in dir():
    main(
        syri_out=snakemake.input[0],                     # le .out passé en input dans le rule
        outdir=snakemake.params.get("outdir", None),     # outdir défini dans la rule              
    )

# -- CLI entry point --
elif __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)          # crée le parseur, affiche la docstring avec --help
    parser.add_argument("syri_out", help="Fichier .out de SyRI")   # argument obligatoire : le fichier SyRI
    parser.add_argument("--outdir", default=None, help="Dossier de sortie")  # argument optionnel : dossier de sortie
    args = parser.parse_args()                                     # lit les arguments passés dans le terminal
    main(args.syri_out, args.outdir)                               # appelle main avec les valeurs récupérées