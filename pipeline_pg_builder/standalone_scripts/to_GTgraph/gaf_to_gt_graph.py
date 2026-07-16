#!/usr/bin/env python3
"""Construit le Ground Truth sur graphe (GT graph) à partir :
  - du GAF produit par GrAnnoT (une ligne = un événement projeté sur le
    graphe, colonne 6 = chemin de noeuds),
  - du BED de la référence produit par GrAnnoT (colonnes : chrom, start,
    end, id_noeud -- position de chaque noeud sur le génome référence),
  - du features_meta.tsv produit par gt_seq_to_gff3.py (type, id_event,
    nb d'échantillons, id_SV par événement).

Sorties (cf. tableaux "Ground truth on graph" des slides du stage) :
  - GT_graph_events.tsv : id_line, id_event, type, anchor1, anchor2,
    nb_noeuds, length_bp, id_SV
  - GT_graph_nodes.tsv  : id_node, event_list, INS, DEL, INV, DUP, TRA, TDM
    (compteur "sous_GT" : pour chaque noeud du chemin d'un événement, on
    incrémente la colonne du type de l'événement du nombre d'échantillons
    qui le portent -- pas juste +1, cf. n_samples dans features_meta.tsv)

Étapes 3-4-5 demandées :
  3. colonne 6 du GAF (path)             -> parse_gaf_path()
  4. ancres = noeud juste avant/après     -> find_anchor_before/after()
     (position de début/fin du 1er/dernier noeud du chemin, cherchée dans
     le BED ; on essaie la convention BED standard 0-based demi-ouverte
     [end adjacent = start du suivant] PUIS la convention 1-based fermée
     [end = start du suivant - 1] -- À VALIDER sur un cas connu avant de
     faire confiance aux ancres en prod, cf. note plus bas)
  5. nb_noeuds = nombre d'éléments du chemin ; incrément du sous_GT par
     noeud -> build_gt_graph()

ATTENTION - points à valider avec les vraies données GrAnnoT :
  - Le nom de "read" utilisé par GrAnnoT dans la colonne 1 du GAF doit
    correspondre au ID mis dans le GFF3 (feature_id = "<type>_<id_event>").
    Si GrAnnoT utilise plutôt l'attribut Name, ou reformate l'ID, adapter
    `feature_id = fields[0]` ci-dessous en conséquence.
  - Le chemin (colonne 6) peut utiliser des séparateurs différents selon
    la version de GrAnnoT/GraphAligner (">12>13<14" sans séparateur est la
    norme GAF ; certains outils utilisent des virgules). PATH_TOKEN_RE
    couvre le format standard sans séparateur.
  - Le fichier BED de la référence est celui que GrAnnoT calcule en
    interne (une position par noeud, par génome/contig) -- son emplacement
    exact dans les sorties de GrAnnoT est à vérifier (voir la rule
    run_grannot dans ground_truth_graph.smk).

- Standalone : python gaf_to_gt_graph.py annot.gaf ref.bed features_meta.tsv \
               --events GT_graph_events.tsv --nodes GT_graph_nodes.tsv
- Snakemake  : rule gt_graph (script: "../scripts/gaf_to_gt_graph.py")
"""
import argparse
import csv
import re

# types finaux après fusion des types spéciaux dans syri_to_GT_v2.merge_special_types
# (INVDP a été replié dans DUP, INVTR a été replié dans TRA)
GT_NODE_TYPES = ["INS", "DEL", "INV", "DUP", "TRA", "TDM"]

PATH_TOKEN_RE = re.compile(r"([><])([^><]+)")


def parse_gaf_path(path_field):
    """'>12>13<14' -> [('>','12'), ('>','13'), ('<','14')]"""
    return PATH_TOKEN_RE.findall(path_field)


def build_bed_index(bed_path):
    """Charge le BED de la référence produit par GrAnnoT.
    Retourne (starts, ends, node_pos) pour retrouver le voisin d'une position.
    """
    starts, ends, node_pos = {}, {}, {}
    with open(bed_path) as fh:
        for line in fh:
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            chrom, start, end, node_id = fields[0], int(fields[1]), int(fields[2]), fields[3]
            starts[(chrom, start)] = node_id
            ends[(chrom, end)] = node_id
            node_pos[node_id] = (chrom, start, end)
    return starts, ends, node_pos


def find_anchor_before(chrom, pos, ends_index):
    # essaie la convention BED standard (0-based demi-ouverte : end == pos),
    # sinon la convention 1-based fermée (end == pos - 1)
    for candidate in (pos, pos - 1):
        node = ends_index.get((chrom, candidate))
        if node is not None:
            return node
    return None


def find_anchor_after(chrom, pos, starts_index):
    for candidate in (pos, pos + 1):
        node = starts_index.get((chrom, candidate))
        if node is not None:
            return node
    return None


def load_features_meta(meta_path):
    meta = {}
    with open(meta_path) as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            meta[row["feature_id"]] = row
    return meta


def build_gt_graph(gaf_path, bed_path, meta_path):
    starts_idx, ends_idx, node_pos = build_bed_index(bed_path)
    meta = load_features_meta(meta_path)

    event_rows = []
    node_counts = {}  # id_node -> {"events": set(), "INS": 0, "DEL": 0, ...}
    skipped = []

    with open(gaf_path) as fh:
        for line in fh:
            if not line.strip():
                continue
            fields = line.rstrip("\n").split("\t")
            feature_id = fields[0]           # colonne 1 : nom du "read" = ID de la feature GFF3
            path_field = fields[5]           # colonne 6 : chemin de noeuds

            tokens = parse_gaf_path(path_field)
            if not tokens:
                skipped.append((feature_id, "chemin vide"))
                continue

            info = meta.get(feature_id)
            if info is None:
                skipped.append((feature_id, "absent de features_meta.tsv"))
                continue

            first_node = tokens[0][1]
            last_node = tokens[-1][1]
            if first_node not in node_pos or last_node not in node_pos:
                skipped.append((feature_id, "noeud absent du BED référence"))
                continue

            chrom, first_start, _ = node_pos[first_node]
            _, _, last_end = node_pos[last_node]

            # étape 4 : ancres = noeud juste avant / juste après le chemin
            anchor1 = find_anchor_before(chrom, first_start, ends_idx)
            anchor2 = find_anchor_after(chrom, last_end, starts_idx)

            sv_type = info["type"]
            id_event = info["id_event"]
            n_samples = int(info["n_samples"])
            nb_noeuds = len(tokens)  # étape 5 : nb d'éléments du chemin

            event_rows.append({
                "id_line": len(event_rows) + 1,
                "id_event": id_event,
                "type": sv_type,
                "anchor1": anchor1 if anchor1 is not None else "NA",
                "anchor2": anchor2 if anchor2 is not None else "NA",
                "nb_noeuds": nb_noeuds,
                "length_bp": info.get("length_bp", ""),
                "id_SV": info["id_SV"],
            })

            # étape 5 : à chaque noeud du chemin, incrémente le sous_GT
            # (le compte augmente du nb d'échantillons qui portent cet
            # événement, pas juste de 1 -- cf. exemple des slides : le
            # noeud de l'INV partagé par 3 isolats affiche INV=3)
            event_tag = f"{sv_type}_{id_event}"
            for _, node_id in tokens:
                entry = node_counts.setdefault(
                    node_id, {"events": set(), **{t: 0 for t in GT_NODE_TYPES}}
                )
                entry["events"].add(event_tag)
                if sv_type in entry:
                    entry[sv_type] += n_samples
                else:
                    # type imprévu (vérifier merge_special_types en amont)
                    entry[sv_type] = entry.get(sv_type, 0) + n_samples

    if skipped:
        print(f"[gaf_to_gt_graph] {len(skipped)} lignes GAF ignorées, ex: {skipped[:5]}")

    return event_rows, node_counts


def write_events(event_rows, outfile):
    fieldnames = ["id_line", "id_event", "type", "anchor1", "anchor2",
                  "nb_noeuds", "length_bp", "id_SV"]
    with open(outfile, "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerows(event_rows)


def write_nodes(node_counts, outfile):
    fieldnames = ["id_node", "event_list"] + GT_NODE_TYPES
    with open(outfile, "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        for node_id, entry in sorted(node_counts.items()):
            row = {"id_node": node_id, "event_list": ",".join(sorted(entry["events"]))}
            row.update({t: entry.get(t, 0) for t in GT_NODE_TYPES})
            writer.writerow(row)


def main(gaf_path, bed_path, meta_path, events_out, nodes_out):
    event_rows, node_counts = build_gt_graph(gaf_path, bed_path, meta_path)
    write_events(event_rows, events_out)
    write_nodes(node_counts, nodes_out)
    print(f"[gaf_to_gt_graph] {len(event_rows)} événements -> {events_out} ; "
          f"{len(node_counts)} noeuds annotés -> {nodes_out}")


if "snakemake" in dir():
    main(
        gaf_path=snakemake.input.gaf,
        bed_path=snakemake.input.ref_bed,
        meta_path=snakemake.input.meta,
        events_out=snakemake.output.events,
        nodes_out=snakemake.output.nodes,
    )
elif __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gaf")
    parser.add_argument("ref_bed")
    parser.add_argument("meta")
    parser.add_argument("--events", default="GT_graph_events.tsv")
    parser.add_argument("--nodes", default="GT_graph_nodes.tsv")
    args = parser.parse_args()
    main(args.gaf, args.ref_bed, args.meta, args.events, args.nodes)
