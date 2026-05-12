# PanQueSt – Pipeline de construction de graphes de pangénome

Pipeline Snakemake qui prend en entrée des isolats (FASTA) et produit un ou
plusieurs graphes de pangénome avec **Minigraph**, **Minigraph-Cactus** et/ou
**PGGB**, selon un fichier de configuration YAML.

Cible : projet **PanQueSt** (WP2 Benchmark), stage M1 Camille Guiguen.

---

## Arborescence

```
panquest_pg_builder/
├── config/config.yaml          # config utilisateur
├── workflow/
│   ├── Snakefile
│   ├── rules/                  # règles modulaires par outil
│   ├── envs/                   # environnements conda
│   └── scripts/                # stats GFA, build_summary
├── profiles/slurm/config.yaml  # profil SLURM (GenOuest)
└── results/<run_name>/         # sortie
    ├── prepared/               # FASTA normalisés (per_sample, seqfile, PanSN)
    ├── minigraph/pangenome.gfa
    ├── minigraph/log.txt
    ├── minigraph_cactus/...
    ├── pggb/...
    └── run_summary.txt         # ← rapport global
```

---

## Configuration

Éditer `config/config.yaml` :

```yaml
input: "data/isolates"          # fichier OU répertoire FASTA
reference: null                 # null = premier isolat (alphabétique)
run_name: "p_destructans_v1"

tools:
  minigraph:        true
  minigraph_cactus: false
  pggb:             false

minigraph:
  preset: "ggs"
  min_sv_len: 50
  threads: 8
```

**Détection automatique du format d'entrée** :
- fichier `.fa/.fasta/.fna(.gz)` → traité comme multi-FASTA (1 record = 1 isolat,
  nom = 1er mot du header)
- répertoire → 1 FASTA par fichier (nom = basename sans extension)

---

## Lancement

### En local (test rapide)

```bash
cd panquest_pg_builder
snakemake --use-conda --cores 8
```

### Sur GenOuest (SLURM)

```bash
# une seule fois : installer le plugin
pip install --user snakemake-executor-plugin-slurm

# lancement
snakemake --profile profiles/slurm
```

> ⚠️ Toujours lancer depuis un nœud de login (jamais de calcul direct dessus).
> Le profil soumet chaque règle comme un job SLURM séparé.

### Dry-run (recommandé avant tout lancement)

```bash
snakemake -n -p
```

---

## Sortie

`results/<run_name>/run_summary.txt` contient pour chaque outil :
- version utilisée, paramètres, temps d'exécution
- statistiques du GFA : nb segments, liens, paths/walks, taille totale (bp)
- extrait du log

Chaque outil a aussi son propre `log.txt` détaillé.

---

## Notes

- Minigraph-Cactus n'est pas toujours installable via conda ; si l'env échoue
  sur GenOuest, remplacer le `conda:` par un `singularity:` pointant vers
  l'image `quay.io/comparative-genomics-toolkit/cactus`.
- PGGB nécessite que les FASTA soient au format **PanSN-spec**
  (`sample#hap#contig`) : la règle `prepare_pansn_multifasta` s'en charge.
- Pour *P. destructans* (haploïde dominant), on utilise `#1#` partout.
