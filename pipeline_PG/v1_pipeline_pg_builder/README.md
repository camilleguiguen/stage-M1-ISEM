# PanQueSt – Pipeline v1 (Minigraph + PGGB)

Prend un **multi-FASTA** en entrée et produit un ou plusieurs **graphes de pangénome** + un résumé global.
Les constructeurs sont activables indépendamment dans la config.

## Structure

```
pipeline_v1/
├── config/config.yaml         ← fichier de config à éditer
└── workflow/
    ├── Snakefile              ← config, variables globales, rule all, includes
    ├── rules/
    │   ├── minigraph.smk      ← extract_isolate + run_minigraph
    │   ├── pggb.smk           ← prepare_pansn_multifasta + run_pggb
    │   └── report.smk         ← build_summary
    ├── envs/
    │   └── minigraph.yaml     ← env conda (minigraph + samtools)
    └── scripts/gfa_stats.py  ← stats + résumé global
```

## Configuration

Le fichier `config/config.yaml` est le seul fichier à éditer pour construire un pangénome :

```yaml
input: "data/mes_data_assemblees.fasta"   # le multi-FASTA déjà assemblé

#afin de construire le nom du dossier de sortie
species: "ecoli"
chrom: "1"
other: "test"

# Répertoire de sortie racine (ne pas modifier hors besoins particuliers)
output_dir: "all_results" 

# Pour tester sur un sous-ensemble : N premiers isolats du fichier d'entrée.
n_first: 5   # null = tous les isolats

# --- Sélection et paramétrage des constructeurs ---
tools:
  minigraph: true   # activer/désactiver Minigraph
  pggb: false       # activer/désactiver PGGB

minigraph:
  min_sv_len: 50
  threads: 4

pggb:
  n_haplotypes: null   # null = auto (nombre d'isolats)
  segment_length: 5000
  percent_identity: 90
  threads: 4
```

## Lancement

Deux modes sont disponibles et peuvent coexister dans le même Snakefile. Recommandation : Mode Apptainer.

### Mode Apptainer/Singularity (requis pour PGGB, recommandé pour la reproductibilité)

```bash
# Dry-run
snakemake --use-singularity -n --snakefile workflow/Snakefile

# Vrai run (en "local" sur cluster)
snakemake --use-singularity --cores 4 --snakefile workflow/Snakefile

# Vrai run sur cluster depuis local avec données sur /scratch
snakemake --use-singularity --singularity-args "--bind /scratch" --cores 4 --snakefile workflow/Snakefile
```

> **Attention** : par défaut, le conteneur ne voit que `/home` et `/tmp`.
> Si les données sont par exemple dans un rep `/scratch`, il faut ajouter
> `--singularity-args "--bind /scratch"` pour les rendre visibles depuis l'intérieur du conteneur.

### Mode conda (Minigraph uniquement)

> PGGB n'a pas d'env conda — il nécessite le mode Apptainer.

```bash
# Installer snakemake une fois
mamba install -n base -c bioconda snakemake

# Dry-run
snakemake --use-conda -n --snakefile workflow/Snakefile

# Vrai run
snakemake --use-conda --cores 4 --snakefile workflow/Snakefile
```

#### Images utilisées (Apptainer)

| Règle | Image BioContainers |
|-------|---------------------|
| `extract_isolate` | `quay.io/biocontainers/samtools:1.21--h50ea8bc_0` |
| `run_minigraph` | `quay.io/biocontainers/minigraph:0.21--h577a1d6_3` |
| `prepare_pansn_multifasta` | `quay.io/biocontainers/pggb:0.7.4--h9ee0642_0` |
| `run_pggb` | `quay.io/biocontainers/pggb:0.7.4--h9ee0642_0` |
> **Remarque** : Si un prochain développeur veut utiliser une autre version pour les outils des rules si dessus, il aura uniquement à changer le **tag** en fin d'image Biocontainer : `samtools:1.21--h50ea8bc_0` -> `samtools:<new_version>--<new_build_string>`. Tout les tags sont disponnible sur cet URL : https://biocontainers.pro/registry 

## Règles du pipeline

- **`extract_isolate`** — découpe le multi-FASTA d'entrée en un fichier par isolat (nécessaire pour Minigraph)
- **`prepare_pansn_multifasta`** — convertit directement le multi-FASTA au format PanSN bgzippé + indexé (nécessaire pour PGGB)
- **`run_minigraph`** — construit le graphe de pangénome avec Minigraph
- **`run_pggb`** — construit le graphe de pangénome avec PGGB
- **`build_summary`** — calcule des stats sur les GFAs produits et génère un résumé global du run
- **`bandage_minigraph`** — génère une image PNG du graphe Minigraph via Bandage *(si visualization: true)*
- **`pggb_visu`** — génère une image Bandage du graphe PGGB et regroupe tous les visuels dans `visu_images/` *(si visualization: true)*


**Remarque** : Snakemake déduit l'ordre d'exécution seul à partir des input/output des règles.
Seules les branches activées dans `tools:` sont exécutées.

## Visualisation d'images png du pangénome

Activée avec `tools.visualization: true` dans `config.yaml`. Nécessite `--use-singularity`.

| Cas | Ce qui est généré |
|-----|-------------------|
| Minigraph seul | `Minigraph/bandage_MG.png` |
| PGGB seul | `PGGB/visu_images/bandage.png` + PNGs générés par PGGB déplacés dans `visu_images/` |
| Les deux | Les deux cas ci-dessus |

Les PNGs générés automatiquement par PGGB (visualisations `odgi` : depth, inversions, positions…) sont déplacés dans `PGGB/visu_images/` en même temps que l'image Bandage.

> **Remarque Minigraph** : pas de visualisation `odgi` pour Minigraph car ses GFA ne contiennent pas de `Path` — Bandage uniquement.

## Sortie

```
all_results/
└── result_ecoli_chrom1_test/
    ├── per_sample/
    │   └── *.fa
    ├── Minigraph/                     (si tools.minigraph: true)
    │   ├── pangenome_MG.gfa
    │   ├── minigraph.log
    │   └── bandage_MG.png             (si tools.visualization: true)
    ├── PGGB/                          (si tools.pggb: true)
    │   ├── all.fa.gz  + .fai + .gzi  (multi-FASTA PanSN intermédiaire)
    │   ├── pangenome.gfa
    │   ├── pggb.log
    │   └── visu_images/               (si tools.visualization: true)
    │       ├── bandage.png
    │       └── *.png                  (visuels odgi générés par PGGB)
    └── runs_summary_update.txt        (résumé des runs généré avec gfa_stats.py)
```

## Une fois que ça marche…

Étapes suivantes possibles :
1. Ajouter la détection auto fichier / répertoire
2. Ajouter une option "référence" dans la config
3. Ajouter Minigraph-Cactus
4. Voir s'il y a d'autres params intéréssants / outils
