# PanQueSt – Pangenome builder pipeline

Prend un répertoire de un ou plusieurs **multi-FASTA assemblés** en entrée et produit un ou plusieurs **graphes de pangénome** avec les constructeurs Minigraph, Minigraph-cactus et PGGB.

## Sommaire

- [Structure](#structure)
- [Lancement](#lancement)
  - [Via le script SLURM](#via-le-script-slurm-recommandé-sur-cluster)
  - [Mode manuel](#mode-manuel-sans-slurm)
- [Configuration](#configuration-obligatoire)
- [Règles du pipeline](#règles-du-pipeline)
- [Visualisation](#visualisation-dimages-png-du-pangénome)
- [Sortie](#sortie)
- [Tester le pipeline](#tester-le-pipeline-avec-le-fichier-de-test-fourni)
- [Perspectives d'amélioration](#perspectives-damélioration-pour-ce-pipeline)

## Structure

```
pipeline_pg_builder/
├── config/config.yaml              ← fichier de config à éditer
└── workflow/
    ├── Snakefile                   ← config, variables globales, rule all, includes
    ├── rules/
    │   ├── minigraph.smk           ← rules pour minigraph
    │   ├── pggb.smk                ← rules pour PGGB
    │   ├── mini-cactus             ← rules pour minigraph-cactus
    │   ├── report.smk              ← build_summary
    │   └── visu.smk                ← bandage_minigraph + bandage_mgc + pggb_visu
    └── scripts/gfa_stats.py        ← stats + résumé global
```


## Lancement

Clonner le pipeline dans un répertoire dédié :
```bash
git clone https://github.com/camilleguiguen/stage-M1-ISEM.git
tree
```

**Pour pouvoir lancer le pipeline Snakemake il y a 2 impératifs :**
  - Avoir édité le **fichier de configuration** (voir ci dessous [Configuration](#configuration-obligatoire)).
  - Avoir un **environnement où Apptainer** est installé (vérifier avec `apptainer --version`). 
    > **Attention** : si vous êtes sur le cluster Genouest, soyez sûr d'être sur un noeud avec AVX2 (Advanced Vector Extensions). Vérifier : `grep -o 'avx2' /proc/cpuinfo | head -1`, si rien ne s'affiche, relancer la connection mais forcer le noeud avec : `srun --constraint avx2 --pty bash`.

    > **Si le SLURM échoue** à cause de l'installation de Snakemake : intaller le à la mains. Voir https://snakemake.readthedocs.io/en/stable/getting_started/installation.html ou via `pip install snakemake`.

### Via le script SLURM (recommandé sur cluster)

Le script `run_pipeline.sh` est auto-suffisant : il vérifie si Snakemake est installé et le télécharge si besoin, puis **lance le pipeline**.

```bash
# Le code reste dans /home (git pull ici), les données/résultats vont dans /scratch.
# → Mettre des chemins absolus vers /scratch dans config/config.yaml :
#     input:      "/scratch/<user>/data/mes_data.fasta"
#     output_dir: "/scratch/<user>/all_results"

# Lancer depuis /home où se trouve le code
cd ~/path/to/stage-M1-ISEM/pipeline_pg_builder/

sbatch run_pipeline.sh # LANCEMENT du job et donc du pipeline

squeue -u $USER # Surveiller le job
tail -f logs/pg_builder_<JOBID>.log # Consulter les logs en temps réel
```

> **Adapter avant soumission** : vérifier dans `run_pipeline.sh` les directives `--cpus-per-task`, `--mem`, `--time` et `--partition` selon les ressources disponibles sur le cluster.

---

### Mode manuel (sans SLURM)

```bash
# Aller dans le bon répertoire
cd pipeline_PG/pipeline_pg_builder/

# Dry-run
snakemake --use-singularity -n --snakefile workflow/Snakefile

# Vrai run (en local ou sur un nœud interactif)
snakemake --use-singularity --cores 4 --snakefile workflow/Snakefile

# Si les données sont dans /scratch
snakemake --use-singularity --singularity-args "--bind /scratch" --cores 4 --snakefile workflow/Snakefile
```

> **Attention** : par défaut, le conteneur ne voit que `/home` et `/tmp`.
> Si les données sont dans `/scratch`, ajouter `--singularity-args "--bind /scratch"`.

## Configuration (obligatoire)

Le fichier `config/config.yaml` est le seul fichier à éditer pour construire un pangénome :
Depuis le répertoire pipeline_pg_builder faire `nano config/config.yaml` puis éditer.


```yaml
# Répertoire contenant les fichiers FASTA assemblés
# Format des noms : <espece>_<chrom>_<commentaire>.fasta
# Ex : pdestructans_1_run1.fasta → dossier result_pdestructans_chrom1_run1/
input_dir: "data/"

output_dir: "all_results"

# Pour tester sur un sous-ensemble : N premiers isolats de chaque FASTA.
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
- **`bandage_mgc`** — génère une image PNG du graphe Minigraph-Cactus via Bandage *(si visualisation: true)*
- **`pggb_visu`** — génère une image Bandage du graphe PGGB et regroupe tous les visuels dans `visu_images/` *(si visualisation: true)*


**Remarque** : Snakemake déduit l'ordre d'exécution seul à partir des input/output des règles.
Seules les branches activées dans `tools:` sont exécutées.

## Visualisation d'images png du pangénome

Activée avec `tools.visualisation: true` dans `config.yaml`. Nécessite `--use-singularity`.

| Cas | Ce qui est généré |
|-----|-------------------|
| Minigraph seul | `MinUne fois que ça marche…igraph/bandage_MG.png` |
| PGGB seul | `PGGB/visu_images/bandage.png` + PNGs générés par PGGB déplacés dans `visu_images/` |
| Minigraph-Cactus seul | `MinigraphCactus/bandage_MGC.png` |
| Plusieurs outils | Combinaison des cas ci-dessus |

Les PNGs générés automatiquement par PGGB (visualisations `odgi` : depth, inversions, positions…) sont déplacés dans `PGGB/visu_images/` en même temps que l'image Bandage.

> **Remarque Minigraph** : pas de visualisation `odgi` pour Minigraph car ses GFA ne contiennent pas de `Path` — Bandage uniquement.

## Sortie

```
data/
├── pdestructans_1_run1.fasta    ← un fichier FASTA = une run
└── pdestructans_2_run1.fasta

all_results/
├── result_pdestructans_chrom1_run1/    ← nom dérivé automatiquement du fichier FASTA
│   ├── per_sample/
│   │   └── *.fa
│   ├── Minigraph/                         (si tools.minigraph: true)
│   │   ├── pangenome_MG.gfa
│   │   ├── minigraph.log
│   │   └── bandage_MG.png                 (si tools.visualisation: true)
│   ├── PGGB/                              (si tools.pggb: true)
│   │   ├── all.fa.gz  + .fai + .gzi      (multi-FASTA PanSN intermédiaire)
│   │   ├── pangenome.gfa
│   │   ├── pggb.log
│   │   └── visu_images/                   (si tools.visualisation: true)
│   │       ├── bandage.png
│   │       └── *.png                      (visuels odgi générés par PGGB)
│   ├── MinigraphCactus/                   (si tools.minigraph_cactus: true)
│   │   ├── seqfile.tsv
│   │   ├── pangenome_MGC.gfa
│   │   ├── minigraph_cactus.log
│   │   └── bandage_MGC.png                 (si tools.visualisation: true)
│   └── runs_summary_update.txt
└── result_pdestructans_chrom2_run1/       ← second run traité en parallèle
    └── ...
```

## Tester le pipeline avec le fichier de test fourni

Le fichier `test_data/generated_3samples_testfile.fasta` contient 3 séquences synthétiques de ~30 kb. `sampleA` (30 kb) sert de référence et est composé de deux blocs de 15 kb ; `sampleB` (35 kb) contient une insertion de 5 kb au milieu de la référence ; `sampleC` (29 kb) combine une insertion de 2 kb et une délétion de 3 kb.

Le but est de vérifier que le **dry-run** passe sans erreur pour tous les outils et toutes les fonctionnalités.

**1. Préparer le répertoire de données**

Le fichier doit être nommé au format `<espece>_<chrom>_<commentaire>.fasta` et placé dans `data/` :

```bash
cd pipeline_pg_builder/
mkdir -p data
mkdir -p data/test
cp ../test_data/generated_3samples_testfile.fasta  data/test
```

**2. Configurer `config/config.yaml` — tout activer**

```yaml
input_dir: "data/test"
output_dir: "all_results"
n_first: null      # 3 isolats seulement dans ce fichier de test
reference: null    # sampleA utilisé comme référence

tools:
  minigraph: true
  pggb: true
  minigraph_cactus: true
  visualisation: true   # teste aussi la génération des images Bandage
```

**3. Dry-run — aucune exécution réelle, vérifie que toutes les règles se résolvent**

```bash
snakemake --use-singularity -n --snakefile workflow/Snakefile
```

Le dry-run doit lister les jobs sans erreur. Exemple de sortie attendue :

```
Job counts:
  count  jobs
  3      extract_isolate         (1 par isolat)
  1      run_minigraph
  1      prepare_pansn_multifasta
  1      run_pggb
  1      prepare_seqfile
  1      run_minigraph_cactus
  1      build_summary
  1      bandage_minigraph
  1      bandage_mgc
  1      pggb_visu
```

Si une règle manque ou si Snakemake signale une erreur de résolution de wildcard ou de fichier manquant, c'est ici que ça se verra — sans avoir lancé de calcul coûteux.

**4. Vrai run après validation du dry-run (non obligatoire, le dry run peut suffire)**

```bash
snakemake --use-singularity --cores 4 --snakefile workflow/Snakefile
```

**5. Résultat attendu**

```
all_results/
└── result_pdestructans_chrom1_test/
    ├── per_sample/
    │   ├── sampleA.fa
    │   ├── sampleB.fa
    │   └── sampleC.fa
    ├── Minigraph/
    │   ├── pangenome_MG.gfa
    │   ├── minigraph.log
    │   └── bandage_MG.png
    ├── PGGB/
    │   ├── pangenome.gfa
    │   ├── pggb.log
    │   └── visu_images/bandage.png
    ├── MinigraphCactus/
    │   ├── seqfile.tsv
    │   ├── pangenome_MGC.gfa
    │   ├── minigraph_cactus.log
    │   └── bandage_MGC.png
    └── runs_summary_update.txt
```

## Perspectives d'amélioration pour ce pipeline

Étapes suivantes possibles :
1. Voir s'il y a d'autres params intéréssants / outils
5. ajout d'un formulaire pour remplir le fichier de config
6. Ajouter règles SLURM pour tester sur grosses data !!