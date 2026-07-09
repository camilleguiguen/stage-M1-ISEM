# ce code est destiné à être integré au GT sequences pour remplir la colonne id_event
from collections import deque

NULL_ITEM = "-"

# doit rester cohérent avec ORDER dans syri_to_GT_v2.py
ORDER = ["INS", "DEL", "INV", "DUP", "INVDP", "TRA", "INVTR", "TDM"]


def _parse_pos(pos_str):
    a, b = pos_str.strip("()").split(", ")
    return int(a), int(b)


def meme_event_INV(LC, EK):
    # comparaison par défaut (position/taille côté ref) : utilisée pour tous les types sauf INS
    if LC["id_ref"] != EK["id_ref"]:
        return False
    
    #recupere les start et end
    lc_start, lc_end = _parse_pos(LC["pos_ref"])
    ek_start, ek_end = _parse_pos(EK["pos_ref"])
    
    #calcule la taille du SV (côté ref) pour la Ligne Courante et l'Event K
    taille_LC = abs(lc_end - lc_start)
    taille_EK = abs(ek_end - ek_start)

    min_taille = min(taille_LC, taille_EK)
    if min_taille == 0:
        return False

    ecart_taille = abs(taille_LC - taille_EK)
    dist_starts = abs(lc_start - ek_start)
    # c'est le meme event si la taille et le debut sur la ref sont quasi identiques (tolérance 10% / 1% de min_taille)
    return ecart_taille < 0.10 * min_taille and dist_starts < 0.01 * min_taille


def meme_event_INS(LC, EK):
    if LC["id_ref"] != EK["id_ref"]:
        return False
    if LC["pos_qry"] == NULL_ITEM or EK["pos_qry"] == NULL_ITEM:
        return False
    lc_qry_start, lc_qry_end = _parse_pos(LC["pos_qry"])
    ek_qry_start, ek_qry_end = _parse_pos(EK["pos_qry"])
    taille_LC = abs(lc_qry_end - lc_qry_start)
    taille_EK = abs(ek_qry_end - ek_qry_start)
    min_taille = min(taille_LC, taille_EK)
    if min_taille == 0:
        return False
    ecart_taille = abs(taille_LC - taille_EK)
    dist_site = abs(_parse_pos(LC["pos_ref"])[0] - _parse_pos(EK["pos_ref"])[0])
    return dist_site < 0.01 * min_taille and ecart_taille < 0.10 * min_taille


# pour chaque type de ORDER : meme_event_INS pour "INS", meme_event_INV pour tous les autres
FONCTIONS_PAR_TYPE = {
    typeGT: (meme_event_INS if typeGT == "INS" else meme_event_INV)
    for typeGT in ORDER
}


# on fixe la taille de la file à 2 evenements (les 2 derniers créés). on est donc en O(n) et pas O(n²) avec les 2 for
def assigner_event(GTseq, typeGT, taille_file=2):
    meme_event = FONCTIONS_PAR_TYPE[typeGT]
    file = deque(maxlen=taille_file)
    compteur = 0

    for LC in GTseq:
        id_trouve = None
        for (id_event, EK) in file:
            if meme_event(LC, EK):
                id_trouve = id_event
                break

        if id_trouve is not None:
            LC["id_event"] = id_trouve
        else:
            LC["id_event"] = compteur
            file.append((compteur, LC))
            compteur += 1

    return GTseq
