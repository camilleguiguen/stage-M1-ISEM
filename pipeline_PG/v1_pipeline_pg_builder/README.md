# PanQueSt – Pipeline v1 (Minigraph + PGGB + Minigraph-cactus)

Prend un **multi-FASTA** en entrée et produit un ou plusieurs **graphes de pangénome** + un résumé global.

## Structure

```
pipeline_v1/
├── config/config.yaml              ← fichier de config à éditer
└── workflow/
    ├── Snakefile                   ← config, variables globales, rule all, includes
    ├── rules/
    │   ├── minigraph.smk           ← extract_isolate + run_minigraph
    │   ├── pggb.smk                ← prepare_pansn_multifasta + run_pggb
    │   ├── mini-cactus             ← prepare_seqfile + run_minigraph_cactus
    │   ├── report.smk              ← build_summary
    │   └── visu.smk                ← bandage_minigraph + bandage_mc + pggb_visu
    └── scripts/gfa_stats.py        ← stats + résumé global
```

## Configuration (obligatoire)

Le fichier `config/config.yaml` est le seul fichier à éditer pour construire un pangénome :

```yaml
input: "data/mes_data_assemblees.fasta"   # le multi-FASTA déjà assemblé

#afin de construire le nom du dossier de sortie : result_<species>_<chrom>_<other>
species: "ecoli"
chrom: "1"
other: "test"

# Répertoire de sortie racine (ne pas modifier hors besoins particuliers)
output_dir: "all_results" 

# Pour tester sur un sous-ensemble : N premiers isolats du fichier d'entrée.
n_first: 5   # null = tous les isolats

# Isolat de référence (premier de la liste si null)
reference: null

# --- Sélection et paramétrage des constructeurs ---
tools:
  minigraph: true            # activer/désactiver Minigraph
  pggb: false                # activer/désactiver PGGB
  minigraph_cactus: false    # activer/désactiver Minigraph-Cactus
  visualisation: false       # true = génère et gère les images Bandage

minigraph:
  min_sv_len: 50
  threads: 4

pggb:
  n_haplotypes: null   # null = auto (nombre d'isolats)
  segment_length: 5000
  percent_identity: 90
  threads: 4

minigraph_cactus:
  threads: 4
```

## Lancement
**Pour pouvoir lancer le pipeline Snakemake il y a 2 impératifs :**
  - Avoir édité le **fichier de configuration** (voir ci dessus).
  - Avoir un **environnement où Conda/Mamba** est installé (pour que le SLURM installe Snakemake). 
  - Si le SLURM echoue à cause de Snakemake : intaller le à la mains. Voir https://snakemake.readthedocs.io/en/stable/getting_started/installation.html ou simplement via `pip install snakemake`.

### Via le script SLURM (recommandé sur cluster)

Le script `run_pipeline.sh` est auto-suffisant : il vérifie si Snakemake est installé et le télécharge si besoin, puis lance le pipeline.

```bash
# Le code reste dans /home (git pull ici), les données/résultats vont dans /scratch.
# → Mettre des chemins absolus vers /scratch dans config/config.yaml :
#     input:      "/scratch/<user>/data/mes_data.fasta"
#     output_dir: "/scratch/<user>/all_results"

# Lancer depuis /home où se trouve le code
cd ~/path/to/v1_pipeline_pg_builder/

sbatch run_pipeline.sh # Soumettre le job SLURM

squeue -u $USER # Surveiller le job
tail -f logs/pg_builder_<JOBID>.log # Consulter les logs en temps réel
```

> **Adapter avant soumission** : vérifier dans `run_pipeline.sh` les directives `--cpus-per-task`, `--mem`, `--time` et `--partition` selon les ressources disponibles sur le cluster.

---

### Mode manuel (sans SLURM)

```bash
# Aller dans le bon répertoire
cd pipeline_PG/v1_pipeline_pg_builder/

# Dry-run
snakemake --use-singularity -n --snakefile workflow/Snakefile

# Vrai run (en local ou sur un nœud interactif)
snakemake --use-singularity --cores 4 --snakefile workflow/Snakefile

# Si les données sont dans /scratch
snakemake --use-singularity --singularity-args "--bind /scratch" --cores 4 --snakefile workflow/Snakefile
```

> **Attention** : par défaut, le conteneur ne voit que `/home` et `/tmp`.
> Si les données sont dans `/scratch`, ajouter `--singularity-args "--bind /scratch"`.

#### Images utilisées (Apptainer)

| Règle | Image BioContainers |
|-------|---------------------|
| `extract_isolate` | `quay.io/biocontainers/samtools:1.21--h50ea8bc_0` |
| `run_minigraph` | `quay.io/biocontainers/minigraph:0.21--h577a1d6_3` |
| `prepare_pansn_multifasta` | `quay.io/biocontainers/pggb:0.7.4--h9ee0642_0` |
| `run_pggb` | `quay.io/biocontainers/pggb:0.7.4--h9ee0642_0` |
| `prepare_seqfile` | *(règle Python pure, pas de conteneur)* |
| `run_minigraph_cactus` | `quay.io/comparative-genomics-toolkit/cactus:v3.2.1` |
> **Remarque** : Si un prochain développeur veut utiliser une autre version pour les outils des rules ci-dessus, il aura uniquement à changer le **tag** en fin d'image Biocontainer : `samtools:1.21--h50ea8bc_0` -> `samtools:<new_version>--<new_build_string>`. Tout les tags sont disponnible sur cet URL : https://biocontainers.pro/registry 

## Règles du pipeline

- **`extract_isolate`** — découpe le multi-FASTA d'entrée en un fichier par isolat (nécessaire pour Minigraph et Minigraph-Cactus)
- **`prepare_pansn_multifasta`** — convertit directement le multi-FASTA au format PanSN bgzippé + indexé (nécessaire pour PGGB)
- **`prepare_seqfile`** — génère le fichier TSV (seqfile) listant les isolats avec la référence en 1re ligne (nécessaire pour Minigraph-Cactus)
- **`run_minigraph`** — construit le graphe de pangénome avec Minigraph
- **`run_pggb`** — construit le graphe de pangénome avec PGGB
- **`run_minigraph_cactus`** — construit le graphe de pangénome avec cactus-pangenome
- **`build_summary`** — calcule des stats sur les GFAs produits et génère un résumé global du run
- **`bandage_minigraph`** — génère une image PNG du graphe Minigraph via Bandage *(si visualisation: true)*
- **`bandage_mc`** — génère une image PNG du graphe Minigraph-Cactus via Bandage *(si visualisation: true)*
- **`pggb_visu`** — génère une image Bandage du graphe PGGB et regroupe tous les visuels dans `visu_images/` *(si visualisation: true)*


**Remarque** : Snakemake déduit l'ordre d'exécution seul à partir des input/output des règles.
Seules les branches activées dans `tools:` sont exécutées.

## Visualisation d'images png du pangénome

Activée avec `tools.visualisation: true` dans `config.yaml`. Nécessite `--use-singularity`.

| Cas | Ce qui est généré |
|-----|-------------------|
| Minigraph seul | `Minigraph/bandage_MG.png` |
| PGGB seul | `PGGB/visu_images/bandage.png` + PNGs générés par PGGB déplacés dans `visu_images/` |
| Minigraph-Cactus seul | `MinigraphCactus/bandage_MC.png` |
| Plusieurs outils | Combinaison des cas ci-dessus |

Les PNGs générés automatiquement par PGGB (visualisations `odgi` : depth, inversions, positions…) sont déplacés dans `PGGB/visu_images/` en même temps que l'image Bandage.

> **Remarque Minigraph** : pas de visualisation `odgi` pour Minigraph car ses GFA ne contiennent pas de `Path` — Bandage uniquement.

## Sortie

```
all_results/
└── result_ecoli_chrom1_test/
    ├── per_sample/
    │   └── *.fa
    ├── Minigraph/                         (si tools.minigraph: true)
    │   ├── pangenome_MG.gfa
    │   ├── minigraph.log
    │   └── bandage_MG.png                 (si tools.visualisation: true)
    ├── PGGB/                              (si tools.pggb: true)
    │   ├── all.fa.gz  + .fai + .gzi      (multi-FASTA PanSN intermédiaire)
    │   ├── pangenome.gfa
    │   ├── pggb.log
    │   └── visu_images/                   (si tools.visualisation: true)
    │       ├── bandage.png
    │       └── *.png                      (visuels odgi générés par PGGB)
    ├── MinigraphCactus/                   (si tools.minigraph_cactus: true)
    │   ├── seqfile.tsv                    (fichier d'entrée cactus-pangenome)
    │   ├── pangenome_MC.gfa
    │   ├── minigraph_cactus.log
    │   └── bandage_MC.png                 (si tools.visualisation: true)
    └── runs_summary_update.txt            (résumé des runs généré avec gfa_stats.py)
```

## Une fois que ça marche…

Étapes suivantes possibles :
1. Ajouter la détection auto fichier / répertoire
2. Ajouter une option "référence" dans la config
3. Ajouter Minigraph-Cactus
4. Voir s'il y a d'autres params intéréssants / outils
5. ajout d'un formulaire pour remplir le fichier de config
6. Ajouter règles SLURM pour tester sur grosses data !!
