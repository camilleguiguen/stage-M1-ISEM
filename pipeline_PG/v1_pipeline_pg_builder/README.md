# PanQueSt – Pipeline simple (Minigraph seul)

Version minimale du pipeline. Prend un **multi-FASTA** en entrée et produit
un **graphe Minigraph** + un résumé.

## Structure

```
panquest_simple/
├── config/config.yaml         ← fichier de config à éditer par user
└── workflow/
    ├── Snakefile              ← définit les 3 rules
    ├── envs/minigraph.yaml    ← env conda (minigraph + samtools)
    └── scripts/gfa_stats.py   ← stats + résumé
```

## Pipeline = 3 règles enchaînées

```
multi-FASTA d'entrée
        │
        │  rule extract_isolate  (1 fois par isolat)
        ▼
per_sample/<isolat>.fasta
        │
        │  rule run_minigraph
        ▼
pangenome.gfa  +  minigraph.log
        │
        │  rule build_summary
        ▼
run_summary.txt
```

Snakemake déduit cet ordre **seul** à partir des input/output des règles.

## Configuration

Édite `config/config.yaml` :

```yaml
input: "data/mes_data_assemblees.fasta"   # le multi-FASTA déjà assmblé
run_name: "test1"
output_dir: "results_PG"

minigraph:
  min_sv_len: 50
  threads: 4
```

## Lancement

```bash
# Installer conda + snakemake une fois (cf. doc Snakemake)
mamba install -n base -c bioconda snakemake

# DRY-RUN : montre ce qui va se passer SANS rien lancer
cd panquest_simple
snakemake -n -p --snakefile workflow/Snakefile

# Vrai run
snakemake --use-conda --cores 4 --snakefile workflow/Snakefile
```

## Sortie

```
results/test1/
├── per_sample/
│   ├── isolatA.fa
│   ├── isolatB.fa
│   └── ...
├── pangenome.gfa
├── minigraph.log
└── run_summary.txt
```

## Une fois que ça marche…

Étapes suivantes possibles, dans l'ordre :
1. Ajouter la détection auto fichier / répertoire
2. Ajouter une option "référence" dans la config
3. Ajouter PGGB comme 2e constructeur
4. Ajouter Minigraph-Cactus
5. Ajouter le profil SLURM pour GenOuest
