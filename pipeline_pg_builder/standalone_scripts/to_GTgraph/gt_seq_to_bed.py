#!/usr/bin/env python3
"""Convertit un GT seq (TSV, cf. aggregate_gt_seq.py) en un BED par type de
SV, prêt à être converti en GFF3 par l'outil dédié AGAT
(agat_convert_bed2gff.pl, package bioconda `agat`) -- cf. rule
run_agat_bed2gff dans ground_truth_graph.smk.

Pourquoi passer par un BED + AGAT plutôt qu'écrire le GFF3 à la main :
AGAT est un outil mûr et testé pour la manipulation GFF/GTF/BED, qui gère
correctement le formatage GFF3 (échappement des attributs, en-tête
##gff-version 3, conversion de coordonnées) -- pas besoin de réinventer un
écrivain GFF3 maison. Sa seule contrainte : `--primary_tag` (colonne 3 du
GFF3, le type de la feature) est un paramètre PAR FICHIER, pas par ligne. On
écrit donc un BED PAR TYPE DE SV (INS, DEL, INV, DUP, TRA, TDM), et la rule
Snakemake appelle AGAT une fois par type puis concatène les GFF3 obtenus.

Un fichier de métadonnées "features_meta.tsv" est écrit en parallèle : il
retrace, pour chaque feature (= chaque événement), son type, son id_event,
son nombre d'échantillons porteurs et la liste des id_SV correspondants.
C'est ce fichier (et non les attributs du GFF3) que gaf_to_gt_graph.py
utilise pour retrouver ces informations après le passage par GrAnnoT.

Conversion de coordonnées : SyRI (et donc pos_ref) est en 1-based fermé ;
le BED est en 0-based demi-ouvert. On applique donc start_bed = start - 1,
end_bed = end (AGAT reconvertira correctement vers le 1-based fermé attendu
par le GFF3, cf. sa documentation).

ATTENTION - hypothèses à valider avec vos données réelles :
  - Le TSV d'entrée a un id_event UNIQUE PAR (type, id_event) au niveau du
    run entier (cf. aggregate_gt_seq.py). Le regroupement ci-dessous se fait
    par dictionnaire (pas par ordre des lignes), donc il reste correct même
    si le fichier d'entrée n'est pas trié -- mais son type doit déjà être
    fusionné (INVDP -> DUP, INVTR -> TRA), ce que fait aggregate_gt_seq.py.
  - Les lignes dont pos_ref == "-" (NULL_ITEM) sont ignorées : sans position
    sur la référence, l'événement ne peut pas être projeté sur le graphe.

- Standalone : python gt_seq_to_bed.py GT_seq_final.tsv --outdir GT_bed/ --meta features_meta.tsv
- Snakemake  : rule gt_seq_to_bed (script: "../scripts/gt_seq_to_bed.py")
"""
import argparse
import csv
import os

# 6 types finaux après fusion (cf. aggregate_gt_seq.RELABEL) -- un BED par
# type, toujours créé (même vide) pour que les output Snakemake soient stables.
FINAL_ORDER = ["INS", "DEL", "INV", "DUP", "TRA", "TDM"]


def _parse_pos(pos_str):
    a, b = pos_str.strip("()").split(", ")
    return int(a), int(b)


def _parse_sv_length(sv_length_str):
    if sv_length_str is None or sv_length_str == "-":
        return None
    s = sv_length_str.strip("()")
    try:
        return abs(int(s))
    except ValueError:
        return None


def load_gt_seq(tsv_path):
    with open(tsv_path) as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        rows = list(reader)
        fieldnames = reader.fieldnames or []
    if rows and "id_SV" not in fieldnames:
        for i, row in enumerate(rows, start=1):
            row["id_SV"] = f"SV{i}"
    return rows


def group_by_event(rows):
    """Regroupe les lignes par (type, id_event) via un dictionnaire --
    fonctionne quel que soit l'ordre des lignes en entrée (contrairement à
    un groupby qui suppose des lignes déjà contiguës par clé).
    """
    groups = {}
    for row in rows:
        if row.get("pos_ref", "-") == "-":
            continue
        key = (row["type"], row["id_event"])
        groups.setdefault(key, []).append(row)
    return groups


def build_features(groups):
    """Une feature par (type, id_event) : coordonnées BED (0-based, demi-
    ouvertes) + toutes les métadonnées utiles à gaf_to_gt_graph.py.
    """
    features = []
    for (sv_type, id_event), lines in sorted(groups.items()):
        id_ref = lines[0]["id_ref"]
        starts, ends, lengths = [], [], []
        for l in lines:
            s, e = _parse_pos(l["pos_ref"])
            starts.append(min(s, e))
            ends.append(max(s, e))
            sl = _parse_sv_length(l.get("sv_length"))
            if sl is not None:
                lengths.append(sl)

        start_1based, end_1based = min(starts), max(ends)
        if start_1based < 1:
            start_1based = 1
        if end_1based < start_1based:
            end_1based = start_1based
        strand = "-" if any(l.get("reverse") == "1" for l in lines) else "+"

        feature_id = f"{sv_type}_{id_event}"
        id_svs = [l["id_SV"] for l in lines]
        length_bp = max(lengths) if lengths else (end_1based - start_1based + 1)

        features.append({
            "chrom": id_ref,
            "bed_start": start_1based - 1,  # 1-based fermé -> 0-based demi-ouvert
            "bed_end": end_1based,
            "name": feature_id,
            "strand": strand,
            "type": sv_type,
            "id_event": id_event,
            "n_samples": len(lines),
            "id_SV": ",".join(id_svs),
            "length_bp": length_bp,
        })
    features.sort(key=lambda f: (f["type"], f["chrom"], f["bed_start"]))
    return features


def write_beds(features, outdir):
    os.makedirs(outdir, exist_ok=True)
    bed_paths = {}
    handles = {}
    for sv_type in FINAL_ORDER:
        path = os.path.join(outdir, f"GT_seq.{sv_type}.bed")
        bed_paths[sv_type] = path
        handles[sv_type] = open(path, "w")  # toujours créé, même vide
    try:
        for f in features:
            fh = handles[f["type"]]
            # BED6 : chrom start end name score strand
            fh.write(f"{f['chrom']}\t{f['bed_start']}\t{f['bed_end']}\t"
                      f"{f['name']}\t0\t{f['strand']}\n")
    finally:
        for fh in handles.values():
            fh.close()
    return bed_paths


def write_meta(features, outfile):
    fieldnames = ["feature_id", "type", "id_event", "n_samples", "id_SV", "length_bp"]
    with open(outfile, "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        for f in features:
            writer.writerow({
                "feature_id": f["name"], "type": f["type"], "id_event": f["id_event"],
                "n_samples": f["n_samples"], "id_SV": f["id_SV"], "length_bp": f["length_bp"],
            })


def main(gt_seq_tsv, outdir, meta_out):
    rows = load_gt_seq(gt_seq_tsv)
    groups = group_by_event(rows)
    features = build_features(groups)
    bed_paths = write_beds(features, outdir)
    write_meta(features, meta_out)
    n_by_type = {t: sum(1 for f in features if f["type"] == t) for t in FINAL_ORDER}
    print(f"[gt_seq_to_bed] {len(features)} événements -> {outdir}/GT_seq.<type>.bed "
          f"({n_by_type}) ; métadonnées -> {meta_out}")
    return bed_paths


if "snakemake" in dir():
    main(
        gt_seq_tsv=snakemake.input.gt_seq,
        outdir=os.path.dirname(snakemake.output.beds[0]),
        meta_out=snakemake.output.meta,
    )
elif __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gt_seq_tsv", help="GT seq final agrégé (id_event global par type)")
    parser.add_argument("--outdir", default="GT_bed")
    parser.add_argument("--meta", default="features_meta.tsv")
    args = parser.parse_args()
    main(args.gt_seq_tsv, args.outdir, args.meta)
