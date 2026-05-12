"""Statistiques basiques sur un fichier GFA (v1).

Compte les segments (S), liens (L), paths (P) ou walks (W), et la taille totale
en bp des segments. Utilisable en CLI ou importable.
"""
from __future__ import annotations
from pathlib import Path


def gfa_stats(gfa_path: str | Path) -> dict:
    gfa_path = Path(gfa_path)
    n_segments = 0
    n_links = 0
    n_paths = 0
    n_walks = 0
    total_bp = 0

    if not gfa_path.exists() or gfa_path.stat().st_size == 0:
        return {
            "path": str(gfa_path),
            "exists": False,
            "segments": 0,
            "links": 0,
            "paths": 0,
            "walks": 0,
            "total_bp": 0,
        }

    with open(gfa_path, "r") as fh:
        for line in fh:
            if not line:
                continue
            t = line[0]
            if t == "S":
                n_segments += 1
                # S <id> <seq> [tags...]
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 3 and parts[2] != "*":
                    total_bp += len(parts[2])
                else:
                    # séquence absente : essayer le tag LN:i:
                    for p in parts[3:]:
                        if p.startswith("LN:i:"):
                            total_bp += int(p[5:])
                            break
            elif t == "L":
                n_links += 1
            elif t == "P":
                n_paths += 1
            elif t == "W":
                n_walks += 1

    return {
        "path": str(gfa_path),
        "exists": True,
        "segments": n_segments,
        "links": n_links,
        "paths": n_paths,
        "walks": n_walks,
        "total_bp": total_bp,
    }


if __name__ == "__main__":
    import sys, json
    print(json.dumps(gfa_stats(sys.argv[1]), indent=2))
