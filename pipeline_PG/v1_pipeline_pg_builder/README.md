# PanQueSt – Pipeline simple (Minigraph seul)

Version minimale du pipeline. Prend un **multi-FASTA** en entrée et produit
un **graphe Minigraph** + un résumé.

## Structure

```
pipeline_v1/
├── config/config.yaml         ← fichier de config à édité par user
└── workflow/
    ├── Snakefile              ← définit les 3 rules
    ├── envs/minigraph.yaml    ← env conda (minigraph + samtools + python)
    └── scripts/gfa_stats.py   ← stats + résumé
```

## Pipeline = 3 règles enchaînées

```
multi-FASTA d'entrée
        │
        │  rule extract_isolate  (1 fois par isolat)
        ▼
per_sample/<isolat>.fa
        │
        │  rule run_minigraph
        ▼
Minigraph/pangenome_MC.gfa  +  Minigraph/minigraph.log
        │
        │  rule build_summary
        ▼
runs_summary_update.txt
```

Snakemake déduit cet ordre **seul** à partir des input/output des règles.

## Configuration

Édite `config/config.yaml` :

```yaml
input: "data/mes_data_assemblees.fasta"   # le multi-FASTA déjà assemblé

# nom du dossier à composé pour l'instant: result_<species>_chrom<chrom>_<other>
species: "ecoli"
chrom: "1"
other: "test"

output_dir: "all_results"

n_first: 5   # null = tous les isolats

minigraph:
  min_sv_len: 50
  threads: 4
```

## Lancement

```bash
# Installer conda + snakemake une fois (cf. doc Snakemake)
mamba install -n base -c bioconda snakemake

# DRY-RUN : montre ce qui va se passer SANS rien lancer
cd pipeline_v1
snakemake -n -p --snakefile workflow/Snakefile

# Vrai run
snakemake --use-conda --cores 4 --snakefile workflow/Snakefile
```

## Sortie

```
all_results/
└── result_ecoli_chrom1_test/
    ├── per_sample/
    │   └── *.fa
    ├── Minigraph/
    │   ├── pangenome_MC.gfa
    │   └── minigraph.log
    └── runs_summary_update.txt

```

## Une fois que ça marche…

Étapes suivantes possibles, dans l'ordre :
1. Ajouter la détection auto fichier / répertoire
2. Ajouter une option "référence" dans la config
3. Ajouter PGGB comme 2e constructeur
4. Ajouter Minigraph-Cactus
5. Ajouter le profil SLURM pour GenOuest
