# =============================================================================
# syri_to_gtseq.smk — conversion des sorties SyRI (.out) en tables GT (génotypes)
# =============================================================================
# Variables globales utilisées : config, RUNS
# Wildcard {run}    : nom du dossier de sortie dérivé du nom du fichier FASTA
# Wildcard {sample} : isolat non-référence comparé à la référence (idem syri.smk)
#
# Réutilise le fichier {sample}_syri.out produit par la règle `run_syri`
# (cf. workflow/rules/syri.smk) — même dépendance que dans syri_all.
#
# Le script workflow/scripts/syri_to_GTseq.py contient DÉJÀ le bloc qui le
# relie à Snakemake (on ne le modifie pas) :
#
#   if "snakemake" in dir():
#       main(
#           syri_out=snakemake.input[0],                # <- input de cette rule
#           outdir=snakemake.params.get("outdir", None) # <- params.outdir ci-dessous
#       )
#
# IMPORTANT : le script fait "from assign_event import assigner_event".
# assign_event.py doit donc être copié dans workflow/scripts/, au même
# endroit que syri_to_GTseq.py (Snakemake ajoute le dossier du script à
# sys.path, ce qui permet cet import "local").
# =============================================================================

OUTPUT_DIR = config["output_dir"]

# --- Étape 1 : convertir un .out SyRI en tables GT (une par paire ref/sample)
rule syri_to_gtseq:
    input:
        # Fichier .out produit par SyRI pour cette paire (référence, sample)
        # -> même chemin que l'output de la rule run_syri dans syri.smk
        OUTPUT_DIR + "/{run}/SyRI_and_GTsequences/{sample}_syri/{sample}_syri.out",
    output:
        # write_big_GT() dans syri_to_GTseq.py écrit TOUJOURS ce fichier
        # (même vide, avec juste l'en-tête), contrairement aux GT_<type>.tsv
        # qui ne sont créés que si ce type de SV est présent dans le .out.
        # -> c'est donc le seul fichier "fiable" à déclarer comme output Snakemake.
        big_gt = OUTPUT_DIR + "/{run}/SyRI_and_GTsequences/{sample}_syri/GT/BIG_GT.tsv",
    params:
        # Dossier de sortie transmis à main(outdir=...) côté script,
        # récupéré via snakemake.params.get("outdir", None)
        outdir = lambda wc: OUTPUT_DIR + f"/{wc.run}/SyRI_and_GTsequences/{wc.sample}_syri/GT",
    script:
        # Chemin relatif à CE fichier .smk (donc depuis workflow/rules/)
        # -> pointe vers le script copié dans workflow/scripts/
        "../scripts/syri_to_GTseq.py"


# --- Étape : fusionner les GT de tous les isolats + réassigner les id_event -
rule merge_gtseq:
    input:
        # Un BIG_GT.tsv par isolat non-référence — garantit que syri_to_gtseq
        # est terminé pour CET isolat (ce fichier est toujours créé, même
        # vide, par write_big_GT() dans syri_to_GTseq.py)
        sample_big_gt = lambda wc: expand(
            OUTPUT_DIR + "/{run}/SyRI_and_GTsequences/{sample}_syri/GT/BIG_GT.tsv",
            run=wc.run,
            sample=[s for s in RUNS[wc.run]["samples"] if s != RUNS[wc.run]["reference"]],
        ),
    output:
        big_gt = OUTPUT_DIR + "/{run}/SyRI_and_GTsequences/GTsequences/BIG_GT.tsv",
    params:
        outdir = lambda wc: OUTPUT_DIR + f"/{wc.run}/SyRI_and_GTsequences/GTsequences",
    script:
        "../scripts/merge_gtseq.py"


# --- Point de synchro final : un seul fichier à surveiller maintenant ------
# --- attend que toutes les conversions GT d'un run soient terminées. Même logique que `syri_all` (syri.smk) :
# agrège tous les isolats non-référence et écrit un fichier marqueur.
# ancienne rule qui garde tt les GT et result syri
#rule gt_all:
#    input:
#        OUTPUT_DIR + "/{run}/SyRI_and_GTsequences/GTsequences/BIG_GT.tsv",
#    output:
#        done = OUTPUT_DIR + "/{run}/SyRI_and_GTsequences/gtseq_done.txt",
#    shell:
#        r"""
#        echo "Fusion GTsequences terminée — $(date)" > {output.done}
#        echo "Fichier final : {input}" >> {output.done}
#        """

# Lu une seule fois au chargement du Snakefile (comme les autres options config)
KEEP_PER_SAMPLE_GT = config.get("GTsequences", {}).get("keep_per_sample_outputs", True)

rule gt_all:
    input:
        big_gt    = OUTPUT_DIR + "/{run}/SyRI_and_GTsequences/GTsequences/BIG_GT.tsv",
        # dépendance ajoutée : force gt_all à attendre que syri_all (qui liste
        # et donc "consomme" les .out de chaque isolat) soit terminé, avant
        # de pouvoir supprimer ces mêmes .out ci-dessous
        syri_done = OUTPUT_DIR + "/{run}/SyRI_and_GTsequences/syri_done.txt",
    output:
        done = OUTPUT_DIR + "/{run}/SyRI_and_GTsequences/gtseq_done.txt",
    params:
        keep_per_sample = KEEP_PER_SAMPLE_GT,
        base_dir = lambda wc: OUTPUT_DIR + f"/{wc.run}/SyRI_and_GTsequences",
        samples  = lambda wc: [s for s in RUNS[wc.run]["samples"] if s != RUNS[wc.run]["reference"]],
    run:
        import shutil
        from pathlib import Path
        from datetime import datetime

        lines = [
            f"Fusion GTsequences terminée — {datetime.now().isoformat(timespec='seconds')}",
            f"Fichier final : {input.big_gt}",
        ]

        if not params.keep_per_sample:
            base = Path(params.base_dir)
            removed = []
            for sample in params.samples:
                sample_dir = base / f"{sample}_syri"   # contient .out/.log/.vcf/.summary + GT/
                bam_file   = base / f"{sample}.sorted.bam"
                if sample_dir.exists():
                    shutil.rmtree(sample_dir)
                    removed.append(str(sample_dir))
                if bam_file.exists():
                    bam_file.unlink()
                    removed.append(str(bam_file))
            lines.append("Sorties par isolat supprimées (GTsequences.keep_per_sample_outputs: false) :")
            lines.extend(f"  {r}" for r in removed)
        else:
            lines.append("Sorties par isolat conservées (GTsequences.keep_per_sample_outputs: true)")

        Path(output.done).write_text("\n".join(lines) + "\n")