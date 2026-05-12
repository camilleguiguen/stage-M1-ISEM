# =============================================================================
# prepare.smk - normalisation des entrées
# =============================================================================
#
# Chaque outil a ses propres exigences sur les FASTA. Ici on produit, à partir
# de l'entrée utilisateur :
#
#   prepared/per_sample/<sample>.fa        un FASTA par isolat (pour minigraph)
#   prepared/seqfile.tsv                   <sample>\t<chemin> (pour MC)
#   prepared/all.fa.gz                     multi-FASTA bgzippé PanSN (pour PGGB)
#   prepared/all.fa.gz.fai / .gzi          index
#
# Le naming PanSN-spec utilisé pour PGGB est : <sample>#1#<contig>
# (haplotype unique = 1 ; P. destructans est haploïde dominant en culture)
# =============================================================================

rule prepare_per_sample:
    """Extrait/copie chaque isolat dans un FASTA dédié."""
    output:
        fa = str(PREP_DIR / "per_sample" / "{sample}.fa"),
    params:
        kind   = INPUT_KIND,
        src    = lambda wc: SAMPLE_TO_PATH[wc.sample],
        sample = lambda wc: wc.sample,
    log:
        str(PREP_DIR / "logs" / "prepare_{sample}.log"),
    conda:
        "../envs/tools.yaml"
    shell:
        r"""
        mkdir -p $(dirname {output.fa})
        mkdir -p $(dirname {log})
        if [ "{params.kind}" = "dir" ]; then
            # décompresse au besoin
            case "{params.src}" in
                *.gz) zcat "{params.src}" > {output.fa} ;;
                *)    cp     "{params.src}"   {output.fa} ;;
            esac
        else
            # extrait l'enregistrement {params.sample} du multi-FASTA
            samtools faidx "{params.src}" "{params.sample}" > {output.fa}
        fi
        echo "[$(date)] preparé : {output.fa}" > {log}
        echo "  nb records : $(grep -c '^>' {output.fa})" >> {log}
        echo "  taille bp  : $(grep -v '^>' {output.fa} | tr -d '\n' | wc -c)" >> {log}
        """


rule prepare_seqfile:
    """Construit le seqfile TSV pour Minigraph-Cactus."""
    input:
        expand(str(PREP_DIR / "per_sample" / "{sample}.fa"), sample=SAMPLES),
    output:
        seqfile = str(PREP_DIR / "seqfile.tsv"),
    run:
        with open(output.seqfile, "w") as fh:
            # la référence en premier, c'est ce qu'attend cactus-pangenome
            ordered = [REFERENCE] + [s for s in SAMPLES if s != REFERENCE]
            for s in ordered:
                fa = str(PREP_DIR / "per_sample" / f"{s}.fa")
                fh.write(f"{s}\t{Path(fa).resolve()}\n")


rule prepare_pansn_multifasta:
    """Concatène tous les isolats en un multi-FASTA bgzippé au format PanSN."""
    input:
        expand(str(PREP_DIR / "per_sample" / "{sample}.fa"), sample=SAMPLES),
    output:
        fa  = str(PREP_DIR / "all.fa.gz"),
        fai = str(PREP_DIR / "all.fa.gz.fai"),
        gzi = str(PREP_DIR / "all.fa.gz.gzi"),
    log:
        str(PREP_DIR / "logs" / "prepare_pansn.log"),
    conda:
        "../envs/tools.yaml"
    params:
        samples = SAMPLES,
        prep    = str(PREP_DIR),
    shell:
        r"""
        mkdir -p $(dirname {log})
        tmp=$(mktemp)
        for s in {params.samples}; do
            # renomme chaque header en  >sample#1#contig
            awk -v s="$s" '/^>/{{split($1,a," "); name=substr(a[1],2); print ">"s"#1#"name; next}}{{print}}' \
                {params.prep}/per_sample/$s.fa >> "$tmp"
        done
        bgzip -c "$tmp" > {output.fa}
        rm -f "$tmp"
        samtools faidx {output.fa}
        echo "[$(date)] PanSN multi-FASTA prêt : {output.fa}" > {log}
        echo "  nb records : $(zgrep -c '^>' {output.fa})" >> {log}
        """
