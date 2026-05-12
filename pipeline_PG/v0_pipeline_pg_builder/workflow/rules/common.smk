# =============================================================================
# common.smk - détection des entrées et helpers globaux
# =============================================================================
#
# Le pipeline accepte deux formats d'entrée :
#   1. un répertoire contenant 1 FASTA par isolat
#   2. un fichier FASTA multi-séquences (1 isolat = 1 record)
#
# Dans les deux cas on aboutit à :
#   - SAMPLES        : liste ordonnée des noms d'isolats
#   - REFERENCE      : nom de l'isolat de référence (premier par défaut)
#   - INPUT_KIND     : "dir" ou "multifasta"
# =============================================================================

import os
import gzip
from pathlib import Path

FASTA_EXTS = (".fa", ".fasta", ".fna", ".fa.gz", ".fasta.gz", ".fna.gz")


def _open_text(path):
    """Ouvre un fichier texte ou gzip en mode texte."""
    if str(path).endswith(".gz"):
        return gzip.open(path, "rt")
    return open(path, "r")


def _list_fasta_files(directory):
    """Retourne les FASTA d'un répertoire, triés alphabétiquement."""
    p = Path(directory)
    files = [f for f in sorted(p.iterdir())
             if f.is_file() and f.name.lower().endswith(FASTA_EXTS)]
    if not files:
        raise ValueError(f"Aucun FASTA trouvé dans {directory}")
    return files


def _records_in_multifasta(fasta):
    """Retourne la liste ordonnée des noms de séquence (1er mot du header)."""
    names = []
    with _open_text(fasta) as fh:
        for line in fh:
            if line.startswith(">"):
                names.append(line[1:].split()[0])
    if not names:
        raise ValueError(f"Aucune séquence trouvée dans {fasta}")
    return names


def _detect_inputs(input_path):
    """Détecte le format et renvoie (kind, samples, sample_to_path)."""
    p = Path(input_path)
    if not p.exists():
        raise FileNotFoundError(f"Entrée introuvable : {input_path}")

    if p.is_dir():
        files = _list_fasta_files(p)
        samples = []
        sample_to_path = {}
        for f in files:
            # basename sans extension(s)
            name = f.name
            for ext in sorted(FASTA_EXTS, key=len, reverse=True):
                if name.lower().endswith(ext):
                    name = name[: -len(ext)]
                    break
            samples.append(name)
            sample_to_path[name] = str(f.resolve())
        return "dir", samples, sample_to_path

    if p.is_file():
        names = _records_in_multifasta(p)
        sample_to_path = {n: str(p.resolve()) for n in names}
        return "multifasta", names, sample_to_path

    raise ValueError(f"Entrée non reconnue : {input_path}")


# --- Évaluation au chargement du Snakefile ----------------------------------
INPUT_KIND, SAMPLES, SAMPLE_TO_PATH = _detect_inputs(config["input"])

# Référence : config > premier isolat
_ref_cfg = config.get("reference")
if _ref_cfg:
    if _ref_cfg not in SAMPLES:
        raise ValueError(
            f"Référence '{_ref_cfg}' introuvable parmi les isolats : {SAMPLES}"
        )
    REFERENCE = _ref_cfg
else:
    REFERENCE = SAMPLES[0]

# Dossier de run
RUN_DIR = Path(config["output_dir"]) / config["run_name"]
PREP_DIR = RUN_DIR / "prepared"

# Affichage au lancement (utile dans le log Snakemake)
onstart:
    print("=" * 70)
    print(f"  PanQueSt pipeline - run : {config['run_name']}")
    print(f"  Entrée    : {config['input']}  ({INPUT_KIND})")
    print(f"  Isolats   : {len(SAMPLES)} -> {', '.join(SAMPLES)}")
    print(f"  Référence : {REFERENCE}")
    tools_on = [t for t, v in config["tools"].items() if v]
    print(f"  Outils    : {', '.join(tools_on) if tools_on else '(aucun)'}")
    print("=" * 70)
