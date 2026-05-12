"""Construit le run_summary.txt du run.

Appelé par la règle build_summary via le mécanisme `script:` de Snakemake :
les variables `snakemake.input`, `snakemake.output`, `snakemake.params`
sont injectées automatiquement.
"""
from __future__ import annotations
import sys
from datetime import datetime
from pathlib import Path

# Permettre l'import du module sibling gfa_stats quand exécuté par Snakemake
sys.path.insert(0, str(Path(__file__).parent))
from gfa_stats import gfa_stats  # noqa: E402


def main():
    out = Path(snakemake.output.summary)  # noqa: F821
    p = snakemake.params  # noqa: F821
    run_dir = Path(p.run_dir)

    lines = []
    lines.append("=" * 72)
    lines.append("  PanQueSt - Résumé d'exécution")
    lines.append("=" * 72)
    lines.append(f"Run name       : {p.run_name}")
    lines.append(f"Date           : {datetime.now().isoformat(timespec='seconds')}")
    lines.append(f"Entrée         : {p.input_src} ({p.kind})")
    lines.append(f"Nb isolats     : {len(p.samples)}")
    lines.append(f"Isolats        : {', '.join(p.samples)}")
    lines.append(f"Référence      : {p.reference}")
    lines.append(f"Outils lancés  : {', '.join(p.tools_on) if p.tools_on else '(aucun)'}")
    lines.append(f"Répertoire     : {run_dir}")
    lines.append("")

    for tool in p.tools_on:
        gfa = run_dir / tool / "pangenome.gfa"
        log = run_dir / tool / "log.txt"
        lines.append("-" * 72)
        lines.append(f"  {tool}")
        lines.append("-" * 72)
        lines.append(f"  GFA : {gfa}")
        lines.append(f"  Log : {log}")

        stats = gfa_stats(gfa)
        if not stats["exists"]:
            lines.append("  /!\\ GFA introuvable ou vide")
        else:
            lines.append(f"  Segments (S)   : {stats['segments']:>12,}")
            lines.append(f"  Liens (L)      : {stats['links']:>12,}")
            lines.append(f"  Paths (P)      : {stats['paths']:>12,}")
            lines.append(f"  Walks (W)      : {stats['walks']:>12,}")
            lines.append(f"  Taille totale  : {stats['total_bp']:>12,} bp")

        # Inclut quelques lignes du log par outil (entête + fin)
        if log.exists():
            content = log.read_text().splitlines()
            head = content[:8]
            tail = content[-5:] if len(content) > 8 else []
            lines.append("")
            lines.append("  Log (extrait):")
            for ln in head:
                lines.append(f"    {ln}")
            if tail:
                lines.append("    ...")
                for ln in tail:
                    lines.append(f"    {ln}")
        lines.append("")

    lines.append("=" * 72)
    out.write_text("\n".join(lines) + "\n")
    print(f"[build_summary] écrit : {out}")


if __name__ == "__main__":
    main()
