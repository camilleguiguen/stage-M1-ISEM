"""Calcule des stats sur un GFA et écrit un run_summary.txt.

Appelé par la règle `build_summary` du Snakefile. Snakemake fournit
automatiquement la variable `snakemake` avec les input/output/params.
"""
from datetime import datetime
from pathlib import Path


def gfa_stats(gfa_path):
    """Compte segments, liens, paths, walks et taille totale (bp) d'un GFA."""
    n_seg = n_link = n_path = n_walk = 0
    total_bp = 0

    with open(gfa_path) as fh:
        for line in fh:
            if not line:
                continue
            tag = line[0]
            if tag == "S":
                n_seg += 1
                parts = line.rstrip("\n").split("\t")
                # S <id> <seq> [tags...]
                if len(parts) >= 3 and parts[2] != "*":
                    total_bp += len(parts[2])
                else:
                    # séquence absente -> chercher LN:i:<n>
                    for p in parts[3:]:
                        if p.startswith("LN:i:"):
                            total_bp += int(p[5:])
                            break
            elif tag == "L":
                n_link += 1
            elif tag == "P":
                n_path += 1
            elif tag == "W":
                n_walk += 1

    return {
        "segments": n_seg,
        "links": n_link,
        "paths": n_path,
        "walks": n_walk,
        "total_bp": total_bp,
    }


# --- Code exécuté par Snakemake ---------------------------------------------
gfa = snakemake.input.gfa
log_path = snakemake.input.log
out = Path(snakemake.output.summary)
p = snakemake.params

stats = gfa_stats(gfa)

lines = []
lines.append("=" * 60)
lines.append("  PanQueSt - Résumé d'exécution")
lines.append("=" * 60)
lines.append(f"Date      : {datetime.now().isoformat(timespec='seconds')}")
lines.append(f"Run       : {p.run_name}")
lines.append(f"Isolats   : {', '.join(p.samples)} ({len(p.samples)})")
lines.append(f"Référence : {p.ref}")
lines.append("")
lines.append("--- Statistiques du GFA ---")
lines.append(f"  Fichier        : {gfa}")
lines.append(f"  Segments (S)   : {stats['segments']:>10,}")
lines.append(f"  Liens (L)      : {stats['links']:>10,}")
lines.append(f"  Paths (P)      : {stats['paths']:>10,}")
lines.append(f"  Walks (W)      : {stats['walks']:>10,}")
lines.append(f"  Taille totale  : {stats['total_bp']:>10,} bp")
lines.append("")
lines.append("--- Log Minigraph (extrait) ---")
lines.extend("  " + ln for ln in Path(log_path).read_text().splitlines())
lines.append("=" * 60)

out.write_text("\n".join(lines) + "\n")
print(f"[build_summary] écrit : {out}")
