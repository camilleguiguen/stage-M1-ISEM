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

## Pipeline = 5 règles enchaînées

```
multi-FASTA d'entrée
        │
        ├──────────────────────────────────────┐
        │  rule extract_isolate                │  rule prepare_pansn_multifasta
        │  (1 fois par isolat)                 │  (conversion PanSN directe)
        ▼                                      ▼
per_sample/<isolat>.fa              PGGB/all.fa.gz  (PanSN bgzippé)
        │                                      │
        │  rule run_minigraph                  │  rule run_pggb
        ▼                                      ▼
Minigraph/pangenome_MC.gfa          PGGB/pangenome.gfa
        │                                      │
        └──────────────┬───────────────────────┘
                       │  rule build_summary
                       ▼
              runs_summary_update.txt
```

Snakemake déduit cet ordre **seul** à partir des input/output des règles.
Seules les branches activées dans `tools:` sont exécutées.

## Configuration

Édite `config/config.yaml` :

```yaml
input: "data/mes_data_assemblees.fasta"   # le multi-FASTA déjà assemblé

species: "ecoli"
chrom: "1"
other: "test"

output_dir: "all_results"

n_first: 5   # null = tous les isolats

# --- Sélection des constructeurs ---
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

Deux modes sont disponibles et peuvent coexister dans le même Snakefile.

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

### Mode Apptainer/Singularity (requis pour PGGB, recommandé pour la reproductibilité)

```bash
# Dry-run
snakemake --use-singularity -n --snakefile workflow/Snakefile

# Vrai run (local)
snakemake --use-singularity --cores 4 --snakefile workflow/Snakefile

# Vrai run sur cluster avec données sur /scratch
snakemake --use-singularity --singularity-args "--bind /scratch" --cores 4 --snakefile workflow/Snakefile
```

> **Piège montages cluster** : par défaut, le conteneur ne voit que `/home` et `/tmp`.
> Si tes données sont sur `/scratch` (ou `/work`, `/projects`…), ajoute
> `--singularity-args "--bind /scratch"` pour les rendre visibles depuis l'intérieur du conteneur.

#### Images utilisées (Apptainer)

| Règle | Image BioContainers |
|-------|---------------------|
| `extract_isolate` | `quay.io/biocontainers/samtools:1.21--h50ea8bc_0` |
| `run_minigraph` | `quay.io/biocontainers/minigraph:0.21--h577a1d6_3` |
| `prepare_pansn_multifasta` | `quay.io/biocontainers/pggb:0.7.4--h9ee0642_0` |
| `run_pggb` | `quay.io/biocontainers/pggb:0.7.4--h9ee0642_0` |

## Sortie

```
all_results/
└── result_ecoli_chrom1_test/
    ├── per_sample/
    │   └── *.fa
    ├── Minigraph/                     (si tools.minigraph: true)
    │   ├── pangenome_MC.gfa
    │   └── minigraph.log
    ├── PGGB/                          (si tools.pggb: true)
    │   ├── all.fa.gz  + .fai + .gzi  (multi-FASTA PanSN intermédiaire)
    │   ├── pangenome.gfa
    │   └── pggb.log
    └── runs_summary_update.txt        (agrège tous les constructeurs actifs)
```

## Une fois que ça marche…

Étapes suivantes possibles :
1. Ajouter la détection auto fichier / répertoire
2. Ajouter une option "référence" dans la config
3. Ajouter Minigraph-Cactus
4. Ajouter le profil SLURM pour GenOuest
5. Ajouter le profil SLURM pour GenOuest
