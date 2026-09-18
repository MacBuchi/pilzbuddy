"""Diagnosen ohne neues Modell — Phase 1 des Fahrplans.

    python3 tool/ampel_diagnose.py --self-test          # netzfrei
    python3 tool/ampel_diagnose.py --all \\
        --dataset pinned --dedupe \\
        --api http://127.0.0.1:8080/v1/archive \\
        --cache ~/pilzbuddy-ampel2000/ampel_cache_pinned \\
        --out docs/pilzampel-diagnosen.md

Vier Fragen an die schon gezogenen Paare. **Keine davon passt etwas an**,
und keine fasst Pruefdaten an: Gerechnet wird ausschliesslich auf
Deutschland und den Jahren bis `FIT_UNTIL_YEAR`. Die Ergebnisse liefern
die Startbereiche fuer die Hypothesen in Phase 2, ohne den Hold-out zu
verbrauchen.

1.1 **Richtungs-Split** — trennt das Modell auch, wenn der Vergleichstag
    VOR dem Fund liegt, genauso gut wie danach? Aehnliche Werte deuten auf
    eine Reaktion auf das NIVEAU, eine deutliche Asymmetrie auf eine
    Reaktion auf die AENDERUNG (Abkuehlung, Frost).

1.2 **Frost-Vorlauf** — rein beschreibend: Wie unterscheiden sich Fund-
    und Vergleichstage in Frosttagen, Tagen seit dem letzten Frost und
    Waermesumme seither? Das sind die Zutaten des Zwei-Phasen-Modells aus
    H3, und hier werden ihre Groessenordnungen abgelesen.

1.3 **Suchaufwand-Referenz** — dieselbe Paarpruefung fuer „irgendeine
    Pilzmeldung am Ort". Menschen gehen NACH Regen in den Wald; ein Teil
    des Regensignals kann Sammelverhalten sein. Die AUC dieser Referenz
    ist die Obergrenze des reinen Aufwandssignals. Artspezifisch belastbar
    ist nur, was darueber hinausgeht.

1.4 **Melder-Abhaengigkeit** — traegt eine Handvoll Vielmelder die Zahl?
    AUC ohne die zehn aktivsten, dazu ein Bootstrap ueber Melder statt
    ueber Jahre.

Nur Standardbibliothek, wie jedes Werkzeug in `tool/`.
"""
import argparse
import importlib.util
import math
import os
import random
import statistics
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "ampel_validate", os.path.join(_HERE, "ampel_validate.py"))
av = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(av)
ab = av.ampel_basis

_logit_spec = importlib.util.spec_from_file_location(
    "ampel_logit", os.path.join(_HERE, "ampel_logit.py"))
ampel_logit = importlib.util.module_from_spec(_logit_spec)
_logit_spec.loader.exec_module(ampel_logit)

FROST_C = 0.0          # Tmin, ab der ein Tag als Frosttag zaehlt
FROST_LOOKBACKS = (7, 14, 21, 28)
GDD_BASE = 0.0         # Basis der Waermesumme seit dem letzten Frost
BOOTSTRAP_ROUNDS = 400
TOP_RECORDERS = 10


# --- 1.1 Richtungs-Split ---------------------------------------------------


def direction_split(samples, optimum):
    """Gepaarte AUC getrennt nach der Seite, auf der der Vergleichstag liegt.

    `gap_control` ist negativ, wenn der Vergleichstag VOR dem Fund liegt.
    Ohne das Vorzeichen (bis Phase 0.2) war diese Frage nicht stellbar.
    """
    sides = {"vor": [], "nach": []}
    for s in samples:
        gap = s.get("gap_control")
        if gap is None:
            continue
        pair = (av.ampel_score(*s["found"], optimum),
                av.ampel_score(*s["control"], optimum))
        sides["vor" if gap < 0 else "nach"].append(pair)
    out = {}
    for side, pairs in sides.items():
        out[side] = {"n": len(pairs),
                     "auc": av.paired_auc(pairs) if pairs else None}
    both = [p for pairs in sides.values() for p in pairs]
    out["gesamt"] = {"n": len(both),
                     "auc": av.paired_auc(both) if both else None}
    if out["vor"]["auc"] is not None and out["nach"]["auc"] is not None:
        out["differenz"] = out["nach"]["auc"] - out["vor"]["auc"]
    else:
        out["differenz"] = None
    return out


# --- 1.2 Frost-Vorlauf -----------------------------------------------------


def frost_days(tmin, length):
    """Frosttage in den `length` Tagen vor dem Stichtag.

    `tmin` ist juengster Tag zuerst, wie jedes Fenster hier.
    """
    if tmin is None or len(tmin) < length:
        return None
    return sum(1 for value in tmin[:length] if value <= FROST_C)


def days_since_frost(tmin):
    """Tage seit dem letzten Frosttag — 0 heisst „gestern war Frost".

    `None`, wenn im ganzen Fenster kein Frost lag. Das ist ausdruecklich
    nicht dasselbe wie „lange her": Bei einem 28-Tage-Fenster heisst es
    nur, dass der letzte Frost weiter zurueckliegt als das Fenster reicht.
    """
    if tmin is None:
        return None
    for position, value in enumerate(tmin):
        if value <= FROST_C:
            return position
    return None


def warmth_since_frost(temp, tmin, base=GDD_BASE):
    """Waermesumme seit dem letzten Frosttag (Grad x Tage ueber `base`).

    `None`, wenn kein Frost im Fenster liegt — dann ist die Summe nicht
    definiert, und eine Null waere die Behauptung „gerade erst gefroren".
    """
    since = days_since_frost(tmin)
    if since is None or temp is None or since > len(temp):
        return None
    return sum(max(0.0, value - base) for value in temp[:since])


def frost_profile(samples):
    """Fund- gegen Vergleichstage, je Kennzahl der Mittelwert und der Anteil.

    Rein beschreibend, ohne Torfunktion. Gezaehlt wird auch, fuer wieviele
    Paare eine Kennzahl ueberhaupt bestimmbar war — eine Art ohne Frost im
    Fenster hat keine „Tage seit Frost", und ein Mittelwert ueber die
    wenigen, die einen haben, waere eine andere Aussage als die Kennzahl.
    """
    out = {}
    for length in FROST_LOOKBACKS:
        anteil = {}
        for rolle, feld in (("fund", "extra"), ("vergleich", "extra_control")):
            treffer = total = 0
            for s in samples:
                n = frost_days(s.get(feld, {}).get("tmin"), length)
                if n is None:
                    continue
                total += 1
                treffer += 1 if n > 0 else 0
            anteil[rolle] = (treffer / total if total else None, total)
        out[f"frosttag_in_{length}d"] = anteil

    # **Beide Funktionen nehmen (tmin, temp) — in DIESER Reihenfolge.**
    # `warmth_since_frost` hiess zuerst `(temp, tmin)`, und der Dreher
    # fiel erst im Echtlauf auf, weil er auf gleich langen Zahlenlisten
    # klaglos durchlief. Ein Selbsttest mit unterscheidbaren Reihen faengt
    # ihn jetzt.
    for name, funktion in (
            ("tage_seit_frost", lambda tmin, temp: days_since_frost(tmin)),
            ("waerme_seit_frost",
             lambda tmin, temp: warmth_since_frost(temp, tmin))):
        werte = {}
        for rolle, feld_e, feld_h in (("fund", "extra", "found"),
                                      ("vergleich", "extra_control",
                                       "control")):
            gesammelt = []
            for s in samples:
                tmin = s.get(feld_e, {}).get("tmin")
                temp = s[feld_h][1] if s.get(feld_h) else None
                value = funktion(tmin, temp)
                if value is not None:
                    gesammelt.append(value)
            werte[rolle] = (statistics.fmean(gesammelt) if gesammelt else None,
                            len(gesammelt))
        out[name] = werte
    return out


# --- 1.3 Suchaufwand-Referenz ---------------------------------------------


def target_group_finds(countries=("DE",), progress=True):
    """„Irgendeine Pilzmeldung" — der ganze verwertbare Bestand.

    Derselbe Schnitt wie bei einer Art (menschliche Beobachtung, offene
    Lizenz, tagesgenau, Koordinate scharf genug), nur ohne Einschraenkung
    auf ein Taxon. Das ist die Target-Group aus der
    Verbreitungsmodellierung: Wer meldet, war im Wald — unabhaengig
    davon, was er gefunden hat.

    **Ohne Obergrenze, und das ist der Punkt.** Beim ersten Versuch stand
    hier `LIMIT 3000` wie bei einer Art. Das Entdoppeln nimmt der
    Target-Group aber 92 % — eine Begehung, auf der jemand zwanzig Arten
    meldet, IST eine Begehung, und genau so soll sie zaehlen. Aus 3000
    Meldungen blieben damit 234 Begehungen und 215 Paare; die Referenz
    haette auf einer Stichprobe gestanden, die kleiner ist als die
    duennste Art. In Deutschland sind es 343 941 Meldungen, die zu
    106 979 Begehungen zusammenfallen — daraus zieht `collect_pairs`
    seine 2000 wie bei jeder Art.

    **Die Zielarten bleiben drin.** Jede einzelne stellt unter 1 % des
    Bestands; sie herauszunehmen kostete elf eigene Referenzlaeufe und
    aenderte die Zahl in der dritten Stelle.
    """
    con = av.gbif_local.connect()
    if con is None:
        return None
    platzhalter = ",".join("?" * len(countries))
    rows = con.execute(
        f"SELECT decimalLatitude, decimalLongitude, year, month, day, "
        f"       recordedBy, countryCode, gbifID, species "
        f"FROM occ WHERE {av.gbif_local.WHERE_USABLE} "
        f"  AND countryCode IN ({platzhalter}) "
        f"  AND year >= ? AND day IS NOT NULL AND month IS NOT NULL "
        f"  AND (coordinateUncertaintyInMeters IS NULL "
        f"       OR coordinateUncertaintyInMeters <= ?) "
        f"ORDER BY gbifID",
        (*countries, av.FIRST_YEAR, av.MAX_UNCERTAINTY_M)).fetchall()
    con.close()
    if progress:
        print(f"    {len(rows)} Meldungen im Bestand (ohne Obergrenze)",
              file=sys.stderr)
    return [{"lat": r[0], "lon": r[1], "year": r[2], "month": r[3],
             "day": r[4], "recordedBy": r[5], "countryCode": r[6],
             "gbifID": r[7], "species": r[8]} for r in rows]


# --- A3: die Referenz je Art statt je Klasse ------------------------------

# Wie gross die Zellen sind, in denen „derselbe Ort" gilt. Zehn Kilometer
# ist die Groessenordnung des Wetterrasters (ERA5-Land 11 km): Feiner
# waere eine Genauigkeit, die das Wetter gar nicht hat, groeber liesse
# ganze Landschaften als „derselbe Ort" durchgehen.
MATCH_KM = 10.0


def matched_reference(target_finds, pool, target_sci, seed=42,
                      km=MATCH_KM, size=None):
    """Referenzmeldungen aus DENSELBEN Gegenden und DENSELBEN Monaten.

    Die Referenz aus Phase 1.3 stammte aus der allgemeinen, stark
    herbstlastigen Meldungsverteilung und wurde nur mit einem anderen
    Fenster ausgewertet. Fuer eine Winterart ist das keine faire
    Referenz: Sie vergleicht „Dezemberfunde einer Kaeltefruchtart" gegen
    „Oktobermeldungen von irgendwem".

    Hier wird stattdessen je Zielart gezogen — aus den Zellen, in denen
    sie gefunden wurde, und mit der Monatsverteilung ihrer eigenen
    Fundtage als Gewicht. **Die Zielart selbst faellt heraus**, sonst
    enthielte die Referenz genau das Signal, gegen das sie abgrenzen soll.

    Reicht ein Monat nicht, wird genommen, was da ist, und die Luecke
    gezaehlt: Eine Referenz, die still einen anderen Monat einsetzt,
    beantwortet eine andere Frage.
    """
    zellen = {ab.grid_cell(f["lat"], f["lon"], km) for f in target_finds}
    soll = {}
    for f in target_finds:
        soll[f["month"]] = soll.get(f["month"], 0) + 1
    if size is None:
        size = len(target_finds)

    nach_monat = {}
    for r in pool:
        if r.get("species") == target_sci:
            continue
        if ab.grid_cell(r["lat"], r["lon"], km) not in zellen:
            continue
        nach_monat.setdefault(r["month"], []).append(r)

    rng = random.Random(seed)
    gezogen = []
    fehlend = {}
    gesamt = sum(soll.values())
    for monat, anzahl in sorted(soll.items()):
        wunsch = round(size * anzahl / gesamt)
        topf = nach_monat.get(monat, [])
        if len(topf) <= wunsch:
            gezogen.extend(topf)
            if len(topf) < wunsch:
                fehlend[monat] = wunsch - len(topf)
        else:
            gezogen.extend(rng.sample(topf, wunsch))
    return gezogen, {"zellen": len(zellen), "fehlend": fehlend,
                     "kandidaten": sum(len(v) for v in nach_monat.values())}


# --- 1.4 Melder-Abhaengigkeit ---------------------------------------------


def top_recorders(samples, count=TOP_RECORDERS):
    """Die `count` Melder mit den meisten Paaren, haeufigster zuerst.

    Namenlose Meldungen bilden KEINEN Melder: Sie stammen von vielen
    Menschen, und sie als einen zu zaehlen machte aus ihnen den groessten
    Vielmelder ueberhaupt — der dann als Erster herausflaege.
    """
    zaehler = {}
    for s in samples:
        name = s.get("recordedBy")
        if name:
            zaehler[name] = zaehler.get(name, 0) + 1
    return sorted(zaehler, key=lambda n: (-zaehler[n], n))[:count]


def without_recorders(samples, namen):
    ausschluss = set(namen)
    return [s for s in samples if s.get("recordedBy") not in ausschluss]


def bootstrap_over(samples, optimum, schluessel, rounds=BOOTSTRAP_ROUNDS,
                   seed=42):
    """95-%-Bereich der gepaarten AUC, gezogen ueber GRUPPEN.

    Ueber Melder statt ueber Paare, weil Paare derselben Person nicht
    unabhaengig sind: Ein Vielmelder mit 300 Paaren zaehlt sonst wie 300
    Beobachtungen, und der Bereich wird zu eng.
    """
    gruppen = {}
    for s in samples:
        pair = (av.ampel_score(*s["found"], optimum),
                av.ampel_score(*s["control"], optimum))
        gruppen.setdefault(schluessel(s), []).append(pair)
    namen = sorted(gruppen, key=str)
    if len(namen) < 2:
        return None
    rng = random.Random(seed)
    zuege = []
    for _ in range(rounds):
        gezogen = [rng.choice(namen) for _ in namen]
        pairs = [p for name in gezogen for p in gruppen[name]]
        wert = av.paired_auc(pairs)
        if wert is not None:
            zuege.append(wert)
    if not zuege:
        return None
    zuege.sort()
    lo = zuege[int(0.025 * len(zuege))]
    hi = zuege[min(len(zuege) - 1, int(0.975 * len(zuege)))]
    return lo, hi


# --- Gemeinsames ----------------------------------------------------------


def fit_years_only(samples):
    """Nur die Anpassjahre. **Das ist die Regel, nicht eine Option.**

    Phase 1 erkundet. Wer hier Pruefjahre anfasst, hat den Hold-out
    verbraucht, bevor die erste Hypothese ueberhaupt registriert ist.
    """
    return [s for s in samples if s["year"] <= av.FIT_UNTIL_YEAR]


def _fmt(value, digits=3):
    return "—" if value is None else f"{value:.{digits}f}"


def _pwert(band):
    """Der p-Wert eines Bandes, mit genug Stellen fuer knappe Faelle.

    Vier Stellen, und ein Ausrufezeichen, wo die Entscheidung dicht an
    der Grenze liegt: Bei 20 000 Zuegen hat ein p von 0,025 noch einen
    eigenen Standardfehler von 0,0011, ein Abstand darunter ist also
    keiner. Wer die Marke sieht, soll nicht die Stufe lesen, sondern die
    Zahl.
    """
    if band is None or len(band) < 3:
        return ""
    if band[2] == 0:
        text = f"<{1 / BOOTSTRAP_ROUNDS_B:.5f}"
    else:
        text = f"{band[2]:.4f}"
    return text + (" ⚠" if abs(band[2] - P_GRENZE) < 0.005 else "")


def _signed(value, digits=3):
    """Mit Vorzeichen — auch bei null, damit die Spalte lesbar bleibt."""
    return "—" if value is None else f"{value:+.{digits}f}"


# --- Selbsttest ------------------------------------------------------------


def self_test():
    # --- Richtungs-Split ---
    # Gepflanzt: Auf der Seite „nach" trennt das Modell perfekt, auf der
    # Seite „vor" gar nicht. Der Split MUSS das auseinanderhalten.
    def probe(gap, warm):
        # 26 Tage Regen und 20 Tage Temperatur, wie das Modell sie will.
        return {"year": 2010, "gap_control": gap,
                "found": ([3.0] * 26, [13.0] * 20),
                "control": ([3.0] * 26, [warm] * 20),
                "recordedBy": "A", "extra": {}, "extra_control": {}}
    samples = ([probe(+30, 30.0) for _ in range(20)]
               + [probe(-30, 13.0) for _ in range(20)])
    got = direction_split(samples, 13.0)
    assert got["nach"]["n"] == 20 and got["vor"]["n"] == 20
    assert got["nach"]["auc"] == 1.0, got["nach"]
    assert got["vor"]["auc"] == 0.5, got["vor"]
    assert abs(got["differenz"] - 0.5) < 1e-9
    # Ohne Vorzeichen faellt ein Paar heraus, statt auf einer Seite zu landen.
    ohne = [dict(s, gap_control=None) for s in samples]
    assert direction_split(ohne, 13.0)["gesamt"]["n"] == 0

    # --- Frostkennzahlen ---
    # juengster Tag zuerst: gestern 5 °C, vorgestern -1 °C, davor 3 °C …
    tmin = [5.0, -1.0, 3.0, 4.0, -2.0, 6.0, 7.0]
    assert frost_days(tmin, 7) == 2
    assert frost_days(tmin, 2) == 1
    assert frost_days(tmin, 1) == 0
    assert frost_days(tmin, 9) is None, "zu kurzes Fenster muss None sein"
    assert frost_days(None, 7) is None
    assert days_since_frost(tmin) == 1
    assert days_since_frost([-1.0] + tmin) == 0, "Frost gestern ist 0, nicht 1"
    assert days_since_frost([5.0, 6.0]) is None, "kein Frost ist None, nicht 0"
    # Genau die Grenze zaehlt als Frost — sonst faellt ein 0,0-Tag durch.
    assert days_since_frost([0.0]) == 0

    # Waermesumme: nur die Tage SEIT dem Frost, also hier der eine Tag.
    temp = [10.0, 2.0, 8.0, 8.0, 8.0, 8.0, 8.0]
    assert warmth_since_frost(temp, tmin) == 10.0
    assert warmth_since_frost(temp, [-1.0] + tmin[:6]) == 0.0
    assert warmth_since_frost(temp, [5.0, 6.0]) is None
    # Negative Tage zaehlen nicht mit — sonst zoege Kaelte die Summe herunter.
    assert warmth_since_frost([-5.0, 20.0], [5.0, -1.0]) == 0.0

    # --- Profil ---
    warm = {"year": 2010, "gap_control": 30,
            "found": ([1.0] * 26, [10.0] * 20),
            "control": ([1.0] * 26, [10.0] * 20), "recordedBy": "A",
            "extra": {"tmin": [1.0] * 28}, "extra_control": {"tmin": [1.0] * 28}}
    kalt = dict(warm, extra={"tmin": [-1.0] * 28})
    # **Gegenprobe gegen den Argument-Dreher.** Die beiden Reihen sind
    # so gewaehlt, dass ein Tausch von tmin und temp ein ANDERES Ergebnis
    # gibt: tmin hat Frost an Position 1, temp hat gar keinen.
    dreher = {"year": 2010, "gap_control": 30,
              "found": ([1.0] * 26, [20.0] * 20),
              "control": ([1.0] * 26, [20.0] * 20), "recordedBy": "A",
              "extra": {"tmin": [5.0, -1.0] + [5.0] * 26},
              "extra_control": {"tmin": [5.0] * 28}}
    p = frost_profile([dreher])
    assert p["tage_seit_frost"]["fund"] == (1.0, 1), p["tage_seit_frost"]
    # Ein Tag seit Frost, und dieser Tag hat 20 °C ueber Basis 0.
    assert p["waerme_seit_frost"]["fund"] == (20.0, 1), p["waerme_seit_frost"]
    # Und der Vergleichstag hat gar keinen Frost, also keine der beiden
    # Kennzahlen — n muss dort 0 sein und nicht etwa 1 mit einer Null.
    assert p["tage_seit_frost"]["vergleich"][1] == 0
    assert p["waerme_seit_frost"]["vergleich"][1] == 0

    profil = frost_profile([warm, kalt])
    anteil, n = profil["frosttag_in_7d"]["fund"]
    assert n == 2 and anteil == 0.5, (anteil, n)
    anteil, n = profil["frosttag_in_7d"]["vergleich"]
    assert n == 2 and anteil == 0.0, (anteil, n)
    # Eine fehlende Reihe wird nicht mitgezaehlt, statt als 0 zu gelten.
    ohne_tmin = dict(warm, extra={})
    anteil, n = frost_profile([ohne_tmin])["frosttag_in_7d"]["fund"]
    assert n == 0 and anteil is None, (anteil, n)

    # --- Melder ---
    viele = ([dict(warm, recordedBy="Vielmelder") for _ in range(50)]
             + [dict(warm, recordedBy=f"N{i}") for i in range(5)]
             + [dict(warm, recordedBy=None) for _ in range(9)])
    assert top_recorders(viele, 1) == ["Vielmelder"]
    # Namenlose bilden keinen Melder, obwohl sie hier zweithaeufigsten waeren.
    assert "" not in top_recorders(viele, 6)
    assert None not in top_recorders(viele, 6)
    rest = without_recorders(viele, ["Vielmelder"])
    assert len(rest) == 14, len(rest)
    assert all(s["recordedBy"] != "Vielmelder" for s in rest)

    # Bootstrap ueber Gruppen: zwei Melder mit gegensaetzlichem Signal
    # muessen einen BREITEN Bereich ergeben — wer ueber Paare zoege,
    # bekaeme einen engen.
    gut = {"year": 2010, "gap_control": 30,
           "found": ([3.0] * 26, [13.0] * 20),
           "control": ([3.0] * 26, [30.0] * 20), "recordedBy": "A",
           "extra": {}, "extra_control": {}}
    schlecht = dict(gut, recordedBy="B",
                    found=([3.0] * 26, [30.0] * 20),
                    control=([3.0] * 26, [13.0] * 20))
    band = bootstrap_over([gut] * 30 + [schlecht] * 30, 13.0,
                          lambda s: s["recordedBy"])
    assert band is not None and band[1] - band[0] > 0.5, band
    # Ein einziger Melder laesst sich nicht ueber Melder ziehen.
    assert bootstrap_over([gut] * 5, 13.0,
                          lambda s: s["recordedBy"]) is None

    # --- A3: die artgematchte Referenz --------------------------------
    #
    # **Der Kandidatenkreis wird direkt geprueft, nicht ueber das
    # Ziehungsergebnis.** Die erste Fassung tat Letzteres und war
    # wertlos: Bei zwanzig gueltigen Kandidaten je Monat zog `sample`
    # auch dann brauchbare Zeilen, wenn beide Filter ausgebaut waren —
    # die Gegenprobe blieb gruen. Jetzt hat jeder Monat GENAU zwei
    # gueltige Kandidaten, und `info["kandidaten"]` zaehlt sie.
    ziel = [{"lat": 51.0, "lon": 10.0, "month": 11, "year": 2015, "day": 1},
            {"lat": 51.0, "lon": 10.0, "month": 11, "year": 2016, "day": 2},
            {"lat": 51.0, "lon": 10.0, "month": 12, "year": 2016, "day": 3},
            {"lat": 51.0, "lon": 10.0, "month": 12, "year": 2017, "day": 4}]
    topf = (
        # gleiche Zelle, richtige Monate, andere Art — genau zwei je Monat
        [{"lat": 51.0, "lon": 10.0, "month": 11, "year": 2015, "day": 5,
          "species": "Anderer Pilz", "gbifID": i} for i in (1, 2)]
        + [{"lat": 51.0, "lon": 10.0, "month": 12, "year": 2015, "day": 6,
            "species": "Anderer Pilz", "gbifID": i} for i in (3, 4)]
        # gleiche Zelle, richtiger Monat, aber die ZIELART
        + [{"lat": 51.0, "lon": 10.0, "month": 11, "year": 2015, "day": 7,
            "species": "Ziel art", "gbifID": 200 + i} for i in range(20)]
        # richtiger Monat, andere Art, aber 200 km entfernt
        + [{"lat": 53.0, "lon": 10.0, "month": 11, "year": 2015, "day": 8,
            "species": "Anderer Pilz", "gbifID": 300 + i} for i in range(20)]
        # gleiche Zelle, andere Art, aber Hochsommer
        + [{"lat": 51.0, "lon": 10.0, "month": 7, "year": 2015, "day": 9,
            "species": "Anderer Pilz", "gbifID": 400 + i} for i in range(20)]
        # **Rund 14 km oestlich** — das nagelt die Zellgroesse fest: bei
        # 10 km eine andere Gegend, bei 100 km dieselbe. Verschoben wird
        # in der LAENGE bei gleicher Breite, weil die Spalte ueber
        # `cos(lat)` an der Breite haengt und ein Versatz nach Norden
        # deshalb auch die Spalte verschiebt.
        + [{"lat": 51.0, "lon": 10.2, "month": 11, "year": 2015, "day": 10,
            "species": "Anderer Pilz", "gbifID": 500 + i} for i in range(20)])
    gezogen, info = matched_reference(ziel, topf, "Ziel art", size=4)
    # **Das ist die scharfe Zusicherung.** 2 aus November, 2 aus Dezember
    # — der Juli faellt ueber die Monatsgewichte weg, die Zielart ueber
    # den Artfilter, die ferne Zelle ueber den Ortsfilter.
    assert info["kandidaten"] == 24, \
        f"Kandidatenkreis {info['kandidaten']} statt 24 — ein Filter fehlt"
    assert sorted(r["gbifID"] for r in gezogen) == [1, 2, 3, 4], gezogen
    assert {r["month"] for r in gezogen} == {11, 12}
    assert info["zellen"] == 1 and not info["fehlend"], info

    # Und der Monatstopf selbst: November und Dezember je genau zwei.
    assert len([r for r in topf
                if r["species"] != "Ziel art"
                and ab.grid_cell(r["lat"], r["lon"], MATCH_KM)
                == ab.grid_cell(51.0, 10.0, MATCH_KM)
                and r["month"] == 11]) == 2

    # **Ein leerer Monat wird gezaehlt, nicht ersetzt.**
    duenn = [r for r in topf if r["month"] != 12]
    gezogen, info = matched_reference(ziel, duenn, "Ziel art", size=4)
    assert info["fehlend"] == {12: 2}, info
    assert {r["month"] for r in gezogen} == {11}, gezogen

    # --- Die Regel, die alles traegt ---
    gemischt = [dict(warm, year=j) for j in (2016, 2018, 2019, 2024)]
    nur_fit = fit_years_only(gemischt)
    assert [s["year"] for s in nur_fit] == [2016, 2018], \
        "Pruefjahre duerfen in Phase 1 nicht auftauchen"
    assert av.FIT_UNTIL_YEAR == 2018

    # --- Nachtrag 1: N1 bis N4 ----------------------------------------

    # N4 — die Jahreszahl als Score. **Von Konstruktion wegen 0,500**,
    # wenn die Ziehung ausgeglichen ist; jede Abweichung ist Unwucht.
    def b_probe(jahr, kontrolljahre):
        return {"year": jahr, "control_years": list(kontrolljahre),
                "found": ([3.0] * 26, [13.0] * 20),
                "controls": [([3.0] * 26, [13.0] * 20)
                             for _ in kontrolljahre]}
    wert, n, frueher, spaeter = score_b_year(
        [b_probe(2012, [2010, 2011, 2013, 2014])] * 10)
    assert wert == 0.5 and n == 10, (wert, n)
    assert frueher == 20 and spaeter == 20, (frueher, spaeter)
    # Nur frueher: der Fundtag „schlaegt" jedes Kontrolljahr.
    wert, _, frueher, spaeter = score_b_year(
        [b_probe(2012, [2010, 2011])] * 4)
    assert wert == 1.0 and frueher == 8 and spaeter == 0, (wert, frueher)
    # Nur spaeter: keines. Ein Gleichstand kann nicht vorkommen — ein
    # Kontrolljahr ist nie das Fundjahr.
    wert, _, _, _ = score_b_year([b_probe(2012, [2013, 2014])] * 4)
    assert wert == 0.0, wert
    # Halb und halb ueber die FUNDE statt ueber die Jahre: der Mittelwert
    # wird je Fund gebildet, also 0,5 — nicht etwa gewichtet.
    wert, _, _, _ = score_b_year([b_probe(2012, [2010, 2011, 2013]),
                                  b_probe(2012, [2013])])
    assert abs(wert - (2 / 3 + 0.0) / 2) < 1e-12, wert
    # **Das Fundjahr als eigenes Kontrolljahr kann die Ziehung nicht
    # erzeugen — und genau deshalb steht es hier.** Ein solcher Fall
    # waere ein Fehler stromaufwaerts, und dann darf er weder als
    # „frueher" noch als „spaeter" mitzaehlen, sondern muss den Wert wie
    # jeder Gleichstand mit 0,5 treffen. Ohne diese Zeile bleibt die
    # Grenze `<` gegen `<=` austauschbar, ohne dass es auffaellt.
    wert, _, frueher, spaeter = score_b_year([b_probe(2012, [2012, 2010])])
    assert frueher == 1 and spaeter == 0, (frueher, spaeter)
    assert wert == 0.75, wert

    # **Der Schnellweg muss Zahl fuer Zahl derselbe sein wie `score_b`.**
    # Ohne diese Zeile waere die Beschleunigung eine Behauptung: Beide
    # Wege koennten dauerhaft auseinanderliegen, ohne dass ein Band
    # auffaellig aussieht.
    bunt = []
    for j, jahr in enumerate(range(2008, 2018)):
        for k in range(4):
            bunt.append({
                "year": jahr, "control_years": [jahr - 1, jahr + 1],
                "found": ([1.0 + k] * 26, [8.0 + j] * 20),
                "controls": [([2.0] * 26, [11.0 + k] * 20),
                             ([0.5] * 26, [17.0 - j] * 20)]})
    fr = _fractions(bunt, 13.0, lambda s: s["year"])
    flach = [w for werte in fr.values() for w in werte]
    assert len(flach) == len(bunt)
    assert abs(sum(flach) / len(flach) - av.score_b(bunt, 13.0)[0]) < 1e-12
    # Und der Schnellweg darf nicht heimlich zum langen werden: Mit
    # `limit` ist der Anteil je Fund ein anderer, dort gilt er nicht.
    assert av.score_b(bunt, 13.0, limit=1)[0] != av.score_b(bunt, 13.0)[0]

    # N2 — Vertrauensbereich der Differenz zur Referenz.
    # **Gegenprobe-tauglich gebaut:** Die Art trennt perfekt, die
    # Referenz gar nicht. Das Band der Differenz MUSS die Null
    # ausschliessen; bei identischen Listen muss es sie einschliessen.
    def bb(jahr, gut):
        temp = 13.0 if gut else 30.0
        return {"year": jahr, "control_years": [jahr - 1, jahr + 1],
                "found": ([3.0] * 26, [temp] * 20),
                "controls": [([3.0] * 26, [30.0] * 20),
                             ([3.0] * 26, [30.0] * 20)]}
    kunst_art = [bb(j, True) for j in range(2008, 2018) for _ in range(5)]
    kunst_ref = [bb(j, False) for j in range(2008, 2018) for _ in range(5)]
    b = bootstrap_ref_diff(kunst_art, kunst_ref, 13.0, rounds=120)
    assert b is not None and b[0] > 0 and b[2] == 0.0, b
    gleich = bootstrap_ref_diff(kunst_art, list(kunst_art), 13.0, rounds=120)
    assert gleich is not None and gleich[0] <= 0 <= gleich[1], gleich
    # Identische Listen heissen Differenz genau null in JEDEM Zug — der
    # p-Wert zaehlt Gleichstand mit 0,5 und muss deshalb 0,5 sein, nicht
    # 0,0. Ohne diese Zeile faerbte ein „<" statt „<=" die Sache still.
    assert gleich[2] == 0.5, gleich
    # **Und die Art muss WIRKLICH mitgezogen werden.** Die beiden Faelle
    # oben trennen perfekt und haben deshalb gar keine Jahresstreuung —
    # ein Bootstrap, der die Art gar nicht neu zieht, sieht dort genauso
    # aus. Hier schwankt die Art von Jahr zu Jahr zwischen 1,0 und 0,0,
    # waehrend die Referenz still liegt: Wird sie nicht mitgezogen,
    # schrumpft das Band auf nahezu nichts.
    schwankend = [bb(j, j % 2 == 0)
                  for j in range(2008, 2018) for _ in range(5)]
    still = [bb(j, False) for j in range(2008, 2018) for _ in range(5)]
    breit = bootstrap_ref_diff(schwankend, still, 13.0, rounds=200)
    assert breit is not None and breit[1] - breit[0] > 0.2, breit
    # Und dieselbe Probe seitenverkehrt, sonst deckt sie nur die eine
    # Haelfte des gemeinsamen Zugs ab: Jetzt schwankt die REFERENZ.
    breit = bootstrap_ref_diff(still, schwankend, 13.0, rounds=200)
    assert breit is not None and breit[1] - breit[0] > 0.2, breit

    # **`bootstrap_b` selbst, ueber dieselbe schwankende Liste.** Auch
    # hier gilt: Wer nicht wirklich zieht, bekommt ein Band der Breite
    # null und merkt es nie, weil ein schmales Band wie ein gutes
    # aussieht.
    jb = bootstrap_b(schwankend, 13.0, lambda s: s["year"], rounds=200)
    assert jb is not None and jb[1] - jb[0] > 0.2, jb
    # Der p-Wert zaehlt gegen 0,50, und dieses Band liegt darueber.
    assert 0.0 <= jb[2] < 0.5, jb
    # Ein einziges Jahr laesst sich nicht ueber Jahre ziehen.
    assert bootstrap_b(schwankend[:5], 13.0, lambda s: s["year"]) is None
    # Ein einziges Jahr laesst sich nicht ueber Jahre ziehen.
    assert bootstrap_ref_diff(kunst_art[:5], kunst_ref[:5], 13.0) is None

    # N3 — die nachweisbare Effektgroesse. Ein Band der Breite
    # 2 * 1,96 * SE muss genau (1,96 + 0,84) * SE ergeben.
    se = 0.05
    got = mde_from_band((0.5 - 1.959964 * se, 0.5 + 1.959964 * se, 0.03))
    assert abs(got - MDE_FAKTOR * se) < 1e-12, got
    assert mde_from_band(None) is None

    # N1 — die Evidenzstufen. Eine Zeile, die alle vier Bedingungen
    # erfuellt, und dann je eine gebrochen.
    def zeile(**kwargs):
        basis = {"name": "Test", "b_auc": 0.65, "ref_b": 0.58,
                 "b_band_jahr": (0.58, 0.71, 0.001),
                 "ref_band": (0.02, 0.11, 0.004),
                 "b_n": 500, "a_auc": 0.74,
                 "a_mirror": 0.50, "a_mirror_n": 500,
                 "b_plac": 0.50, "b_plac_n": 500}
        basis.update(kwargs)
        return basis
    stufe, bed = evidenzstufe(zeile())
    assert stufe == "belegt" and all(bed.values()), (stufe, bed)
    # Zu wenige Funde: eine Bedingung wackelt, die Aussage bleibt.
    assert evidenzstufe(zeile(b_n=100))[0] == "vorläufig"
    # **Referenzabstand positiv, aber das Band streift die Null** — das
    # ist der ERSTE Ausschluss und nicht bloss ein Wackeln: N1 macht die
    # Referenz zum entscheidenden Mass, und N2 gibt ihr dafuer gerade
    # erst einen Vertrauensbereich.
    assert evidenzstufe(zeile(ref_band=(-0.01, 0.13, 0.08)))[0] \
        == "keine Aussage"
    # Kontrolle daneben — 0,60 liegt weit ausserhalb von 2 SE bei n=500.
    assert evidenzstufe(zeile(b_plac=0.60))[0] == "vorläufig"
    # **Die beiden Ausschluesse schlagen die vier Haken.** Unter der
    # Referenz oder mit 0,50 im Band gibt es keine Aussage, auch wenn
    # sonst alles stimmt.
    assert evidenzstufe(zeile(ref_b=0.66))[0] == "keine Aussage"
    assert evidenzstufe(zeile(ref_b=None))[0] == "keine Aussage"
    # **Der Bootstrap ist KEIN eigener Ausschluss** — so loest der
    # Nachtrag seinen eigenen Widerspruch auf (Fichtenreizker steht dort
    # unter „vorlaeufig" mit der Begruendung „Bootstrap streift 0,50").
    # Waere er einer, faerbte er eine Art schwarz, deren Referenzabstand
    # sauber ueber null liegt.
    assert evidenzstufe(zeile(b_band_jahr=(0.49, 0.71, 0.09)))[0] \
        == "vorläufig"
    # Erst wenn B selbst nicht ueber 0,50 liegt, ist auch das vorbei.
    assert evidenzstufe(zeile(b_auc=0.50, ref_b=0.44,
                              b_band_jahr=(0.44, 0.57, 0.31)))[0] \
        == "keine Aussage"
    # Die p-Grenze liegt bei 0,025 und wird scharf gelesen.
    assert evidenzstufe(zeile(ref_band=(0.0, 0.11, 0.025)))[0] \
        == "keine Aussage"
    assert evidenzstufe(zeile(ref_band=(0.0, 0.11, 0.024)))[0] == "belegt"
    # Und dieselbe Grenze am anderen Band — sonst bleibt sie dort
    # austauschbar, ohne dass eine Zeile widerspricht.
    assert evidenzstufe(zeile(b_band_jahr=(0.5, 0.71, 0.025)))[0] \
        == "vorläufig"
    assert evidenzstufe(zeile(b_band_jahr=(0.5, 0.71, 0.024)))[0] == "belegt"
    # Und der entscheidende Unterschied zur ALTEN Regel: Ein grosser
    # Abschlag A-B ist kein Ausschlussgrund mehr.
    assert evidenzstufe(zeile(a_auc=0.95))[0] == "belegt"
    # Die alte Zuordnung ist woertlich aufgehoben und deckt alle Arten.
    assert {n for n, _, _ in DESIGN_ARTEN} == set(STUFE_ALT)

    # --- N5: die Merkmale des Logits ---------------------------------
    #
    # Die Umrechnung haengt daran, dass die Merkmale GENAU die Formel der
    # Ampel abbilden. Geprueft wird deshalb an einer Reihe, deren Werte
    # von Hand nachrechenbar sind.
    regen = [2.0] * av.RAIN_WINDOW
    merkmale, boden = logit_features(regen, [11.0] * av.TEMP_WINDOW)
    assert not boden
    assert abs(merkmale[0] - math.log(av.rain_factor(regen))) < 1e-12
    assert merkmale[1] == 11.0 and merkmale[2] == 121.0, merkmale
    # **Ein trockenes Fenster wird abgeschnitten und GEZAEHLT.** Ohne den
    # Boden waere es log(0); ohne den Zaehler wuesste niemand, wie oft
    # das Modell etwas anderes rechnet, als es behauptet.
    trocken, boden = logit_features([0.0] * av.RAIN_WINDOW,
                                    [11.0] * av.TEMP_WINDOW)
    assert boden and trocken[0] == math.log(LOGIT_REGEN_BODEN), trocken
    # Eine Reihe ganz ohne Temperatur ergibt keine Merkmale, statt eine
    # Null zu erfinden.
    assert logit_features(regen, [None] * av.TEMP_WINDOW)[0] is None

    # Strata: ein Fall, der Rest Kontrollen — und ein Fund ohne
    # Kontrollen faellt heraus, statt als Stratum der Groesse eins zu
    # zaehlen (dort ist die Wahrscheinlichkeit immer 1 und der Beitrag
    # zur Likelihood null).
    b_sample = {"year": 2010, "control_years": [2009, 2011],
                "found": (regen, [13.0] * av.TEMP_WINDOW),
                "controls": [(regen, [18.0] * av.TEMP_WINDOW),
                             (regen, [8.0] * av.TEMP_WINDOW)]}
    strata, abg, gesamt = logit_strata([b_sample, dict(b_sample,
                                                       controls=[])])
    assert len(strata) == 1 and len(strata[0][1]) == 2, strata
    assert abg == 0 and gesamt == 4, (abg, gesamt)
    assert strata[0][0][1] == 13.0 and strata[0][1][0][1] == 18.0

    # Und der Weg von den Strata bis zur Glocke haelt, was er soll:
    # gepflanzte 13 °C bei Breite 4 kommen wieder heraus.
    rng_l = random.Random(11)
    kunst = []
    for _ in range(3000):
        reihen = [(rng_l.uniform(0.05, 1.0), rng_l.uniform(2.0, 24.0))
                  for _ in range(6)]
        nutzen = [math.log(f) - ((t - 13.0) / 4.0) ** 2 - math.log(
            -math.log(rng_l.random())) for f, t in reihen]
        sieger = max(range(6), key=lambda i: nutzen[i])
        zeilen_l = [[math.log(f), t, t * t] for f, t in reihen]
        kunst.append((zeilen_l[sieger],
                      [z for i, z in enumerate(zeilen_l) if i != sieger]))
    angepasst = ampel_logit.fit_conditional_logit(kunst)
    g = ampel_logit.bell_from_beta(angepasst["beta"],
                                   angepasst["kovarianz"])
    assert abs(g["optimum"] - 13.0) < 1.0 and abs(g["breite"] - 4.0) < 0.7, g

    # --- H1: die schmalere Glocke -------------------------------------
    #
    # **Warum eine Breite ueberhaupt etwas aendern KANN.** Die gepaarte
    # AUC ist rangbasiert; eine monotone Umformung der Temperaturglocke
    # allein liesse jede Zahl unveraendert. Wirksam wird sigma erst, weil
    # der Score ein PRODUKT ist: Die Breite verschiebt das Gewicht
    # zwischen Regen und Temperatur. Genau darauf ist die Probe gebaut —
    # der Fundtag hat wenig Regen bei idealer Temperatur, der
    # Vergleichstag viel Regen bei 5 K Abstand.
    def h1_probe(jahr, fund_mm, fund_c, ktrl_mm, ktrl_c, anzahl=1):
        return [{"year": jahr, "control_years": [jahr - 1, jahr + 1],
                 "found": ([fund_mm] * av.RAIN_WINDOW,
                           [fund_c] * av.TEMP_WINDOW),
                 "controls": [([ktrl_mm] * av.RAIN_WINDOW,
                               [ktrl_c] * av.TEMP_WINDOW)] * 2}
                for _ in range(anzahl)]

    # Zahlen nachgerechnet: Regen 1 mm/Tag -> 0,299; 3 mm/Tag -> 0,897.
    # Glocke bei 5 K Abstand: 0,368 (sigma 5) gegen 0,094 (sigma 3,25).
    # Also 0,299 gegen 0,330 -> der Fund verliert; 0,299 gegen 0,084 ->
    # er gewinnt. Die Breite dreht das Paar um.
    assert abs(av.rain_factor([1.0] * av.RAIN_WINDOW) - 26 / 87) < 1e-12
    schmal_hilft = [s for jahr in range(2008, 2018)
                    for s in h1_probe(jahr, 1.0, 13.0, 3.0, 8.0, 20)]
    d = h1_delta(schmal_hilft, 13.0, H1_SIGMA_NEU, rounds=200)
    assert d["n"] == 200, d
    assert abs(d["b_alt"] - 0.0) < 1e-9 and abs(d["b_neu"] - 1.0) < 1e-9, d
    assert abs(d["delta"] - 1.0) < 1e-9, d
    assert d["band"] is not None and d["band"][0] > 0 and d["band"][2] == 0.0
    assert d["jahre"] == 10 and d["jahre_besser"] == 10, d
    assert d["jahr_anteil"] == 1.0

    # **Die Gegenrichtung muss genauso sichtbar sein.** Seitenverkehrt
    # gebaut verliert die schmalere Glocke, und Δ ist negativ.
    schmal_schadet = [s for jahr in range(2008, 2018)
                      for s in h1_probe(jahr, 3.0, 8.0, 1.0, 13.0, 20)]
    d_gegen = h1_delta(schmal_schadet, 13.0, H1_SIGMA_NEU, rounds=200)
    assert abs(d_gegen["delta"] + 1.0) < 1e-9, d_gegen
    assert d_gegen["band"][1] < 0, d_gegen
    assert d_gegen["jahre_besser"] == 0, d_gegen

    # Ohne Unterschied zwischen den Breiten ist Δ exakt null — und das
    # Band schliesst die Null ein statt sie knapp zu verfehlen.
    gleich = [s for jahr in range(2008, 2018)
              for s in h1_probe(jahr, 2.0, 13.0, 2.0, 20.0, 20)]
    d_null = h1_delta(gleich, 13.0, H1_SIGMA_NEU, rounds=200)
    assert d_null["delta"] == 0.0, d_null
    assert d_null["band"][0] <= 0 <= d_null["band"][1], d_null

    # Duenne Jahre tragen kein Vorzeichen. Neun volle Jahre plus ein
    # Jahr mit drei Funden ergeben neun gezaehlte Jahre, nicht zehn.
    duenn = ([s for jahr in range(2008, 2017)
              for s in h1_probe(jahr, 1.0, 13.0, 3.0, 8.0, 20)]
             + h1_probe(2017, 1.0, 13.0, 3.0, 8.0, 3))
    assert h1_delta(duenn, 13.0, H1_SIGMA_NEU, rounds=100)["jahre"] == 9
    assert H1_MIN_JAHR_FUNDE == 10

    # Die Zerlegung: NUR Temperatur sieht den Regen nicht, NUR Regen
    # sieht die Breite nicht.
    nur_r = h1_delta(schmal_hilft, 13.0, H1_SIGMA_NEU, rounds=50,
                     nur="regen")
    assert nur_r["delta"] == 0.0, "der Regenanteil kennt kein sigma"
    # **B auf der Temperatur allein ist von sigma UNABHAENGIG** — das
    # Mass ist rangbasiert, und die Glocke ist fuer jedes sigma streng
    # monoton im Abstand zum Optimum. Wer hier eine Differenz sucht,
    # sucht etwas, das es nicht geben kann.
    gemischt = [s for jahr in range(2008, 2018)
                for s in (h1_probe(jahr, 1.0, 11.0, 3.0, 19.0, 3)
                          + h1_probe(jahr, 1.0, 19.0, 3.0, 11.0, 2))]
    temp_b = {sigma: h1_b(gemischt, 13.0, h1_scorer(13.0, sigma, "temp"))
              for sigma in (3.25, 5.0, 8.0)}
    assert len(set(temp_b.values())) == 1, temp_b
    assert 0.0 < temp_b[5.0] < 1.0, temp_b
    # Der Regenzweig sieht die Temperatur nicht und umgekehrt.
    assert h1_b(gemischt, 13.0, h1_scorer(13.0, 5.0, "regen")) == 0.0
    assert h1_b(schmal_hilft, 13.0, h1_scorer(13.0, 5.0, "regen")) == 0.0
    # **Bei GLEICHEM Regen muss der Regenzweig genau 0,5 sagen**, egal
    # wie weit die Temperaturen auseinanderliegen. Ohne diese Zeile
    # duerfte er heimlich auf die Temperatur schielen: Wo der Regen
    # ohnehin in dieselbe Richtung zeigt, faellt das nicht auf.
    blind = [s for jahr in range(2008, 2018)
             for s in h1_probe(jahr, 2.0, 13.0, 2.0, 30.0, 5)]
    assert h1_b(blind, 13.0, h1_scorer(13.0, 5.0, "regen")) == 0.5
    assert h1_b(blind, 13.0, h1_scorer(13.0, 5.0, "temp")) == 1.0

    # Gleichstand: zwei Tage weit jenseits der Glocke sind beide null.
    tot = [s for jahr in range(2008, 2018)
           for s in h1_probe(jahr, 2.0, 60.0, 2.0, 70.0, 20)]
    t = h1_ties(tot, 13.0, H1_SIGMA_NEU)
    assert t["fund_tot"] == 1.0 and t["beide_null"] == 1.0, t
    # **Der exakte Gleichstand traegt hier NICHTS** — genau deshalb steht
    # er in der Tabelle neben dem eps-Mass und nicht an dessen Stelle:
    # exp(-209) ist 1e-91 und nicht null, die beiden toten Tage gelten
    # dem Rechner also als verschieden.
    assert t["alle_gleich"] == 0.0, t
    assert av.ampel_score([2.0] * av.RAIN_WINDOW,
                          [60.0] * av.TEMP_WINDOW, 13.0, 3.25) > 0.0
    lebendig = h1_ties(schmal_hilft, 13.0, H1_SIGMA_NEU)
    assert lebendig["fund_tot"] == 0.0 and lebendig["beide_null"] == 0.0
    # **Ein Fund zaehlt erst als tot, wenn JEDER seiner Vergleiche tot
    # ist.** Halb tot ist lebendig: Der Fund traegt dann noch eine
    # Aussage, und sie darf nicht weggezaehlt werden.
    halb = [{"year": 2010, "control_years": [2009, 2011],
             "found": ([2.0] * av.RAIN_WINDOW, [60.0] * av.TEMP_WINDOW),
             "controls": [([2.0] * av.RAIN_WINDOW, [70.0] * av.TEMP_WINDOW),
                          ([2.0] * av.RAIN_WINDOW, [13.0] * av.TEMP_WINDOW)]}]
    h = h1_ties(halb, 13.0, H1_SIGMA_NEU)
    assert h["fund_tot"] == 0.0 and h["beide_null"] == 0.5, h

    # Panels und mittlere Temperatur.
    assert len(h1_panel(schmal_hilft, von=2015)) == 60
    assert len(h1_panel(schmal_hilft, bis=2009)) == 40
    assert len(h1_panel(schmal_hilft)) == 200
    assert abs(h1_mean_temp(schmal_hilft) - 13.0) < 1e-9

    # --- Das Urteil, Bedingung fuer Bedingung -------------------------
    def urteil(p1=None, placebo=0.5, placebo_n=500, p2=None, **anders):
        basis = {"delta": 0.05, "band": (0.02, 0.08, 0.001), "n": 500,
                 "jahre": 10, "jahre_besser": 9, "jahr_anteil": 0.9}
        basis.update(anders)
        return h1_urteil(p1 or basis, placebo, placebo_n, p2)
    assert urteil()[0] == "bestanden"
    # 1 — der Gewinn. Die Latte ist +0,020 und wird scharf gelesen.
    assert urteil(delta=0.02)[0] == "bestanden"
    assert urteil(delta=0.0199)[0] == "nicht bestanden"
    # 2 — das Band.
    assert urteil(band=(-0.01, 0.09, 0.08))[0] == "nicht bestanden"
    assert urteil(band=None)[0] == "nicht bestanden"
    # 3 — der Jahresanteil, ebenfalls scharf an 70 %.
    assert urteil(jahre=10, jahre_besser=7, jahr_anteil=0.7)[0] == "bestanden"
    assert urteil(jahre=10, jahre_besser=6,
                  jahr_anteil=0.6)[0] == "nicht bestanden"
    # 4 — das Placebo. 0,60 liegt bei n = 500 weit ausserhalb von 2 SE.
    assert urteil(placebo=0.60)[0] == "nicht bestanden"
    assert urteil(placebo=None)[0] == "nicht bestanden"
    # **Zu duenn ist kein Fehlschlag, sondern kein Urteil.**
    assert urteil(n=MIN_FINDS_B - 1)[0] == "zu dünn"
    assert h1_urteil(None, 0.5, 500, None)[0] == "zu dünn"
    # P2 kann kippen, aber nicht herstellen: ein Band ganz UNTER null
    # laesst die Art durchfallen, ein blosses „nicht signifikant" nicht.
    assert urteil(p2={"band": (-0.09, -0.02, 0.99)})[0] == "nicht bestanden"
    assert urteil(p2={"band": (-0.04, 0.06, 0.30)})[0] == "bestanden"
    assert urteil(p2={"band": None})[0] == "bestanden"
    assert urteil(delta=0.001, p2={"band": (0.05, 0.15, 0.0)})[0] \
        == "nicht bestanden", "Ausland darf nicht herstellen"

    # --- Klassenurteil: alle oder keine -------------------------------
    def klasse(**urteile):
        return h1_klassenurteil(
            [{"name": name, "urteil": wert} for name, wert in urteile.items()])
    alle_gut = {name: "bestanden"
                for arten in H1_KLASSEN.values() for name in arten}
    got = klasse(**alle_gut)
    assert got["herbst"] == "bestanden" and got["sommer"] == "bestanden"
    assert got["_sigma"] == "wird geändert"
    # Ein einziges Mitglied reicht zum Fall der ganzen Klasse.
    einer_faellt = dict(alle_gut, Birkenpilz="nicht bestanden")
    got = klasse(**einer_faellt)
    assert got["herbst"] == "nicht bestanden", got
    assert got["_sigma"] == "bleibt 5,0"
    # **Und sigma braucht BEIDE Klassen** — es ist eine Konstante.
    got = klasse(**dict(alle_gut, Pfifferling="nicht bestanden"))
    assert got["herbst"] == "bestanden" and got["sommer"] == "nicht bestanden"
    assert got["_sigma"] == "bleibt 5,0", got
    # „Zu dünn" traegt kein Urteil, verhindert aber auch keines.
    got = klasse(**dict(alle_gut, Herbsttrompete="zu dünn"))
    assert got["herbst"] == "bestanden", got
    got = klasse(**{name: "zu dünn" for name in alle_gut})
    assert got["herbst"] == "kein Urteil" and got["_sigma"] == "bleibt 5,0"

    # Die Registrierung in Codeform — wer eine dieser Zahlen nach dem
    # Lauf anfasst, hebt sie auf.
    assert (H1_SIGMA_ALT, H1_SIGMA_NEU, H1_SIGMA_GEGEN) == (5.0, 3.25, 8.0)
    assert (H1_MIN_GAIN, H1_MIN_JAHR_ANTEIL) == (0.02, 0.70)
    assert H1_SIGMA_ALT == av.TEMP_SIGMA, "der Amtsinhaber ist der Ausgeliefertee"
    assert set(H1_KLASSEN) == {"herbst", "sommer"}
    assert len(H1_KLASSEN["herbst"]) == 5 and H1_KLASSEN["sommer"] == \
        ["Pfifferling"]

    # **Der Bericht muss sich bauen lassen, BEVOR gemessen wird.** Ein
    # Formatfehler faellt sonst erst nach dem Lauf auf, und dann steht
    # die Frage im Raum, ob man ihn noch anfassen darf. Gefuettert wird
    # mit erfundenen Zeilen, darunter eine halb leere — Arten ohne
    # Ausland oder ohne P1 gibt es in der Wirklichkeit auch.
    erfunden = [
        {"name": "Steinpilz", "gruppe": "herbst", "optimum": 13.0,
         "klasse": "herbst",
         "panel": {"P1": {"delta": 0.03, "band": (0.01, 0.05, 0.004),
                          "n": 900, "jahre": 7, "jahre_besser": 6,
                          "jahr_anteil": 6 / 7},
                   "P2": {"delta": 0.01, "band": (-0.02, 0.04, 0.3),
                          "n": 300, "jahre": 20, "jahre_besser": 12,
                          "jahr_anteil": 0.6},
                   "P3": None},
         "gegenprobe": {"delta": -0.01, "band": None, "n": 900,
                        "jahre": 7, "jahre_besser": 2, "jahr_anteil": 2 / 7},
         "b_nur_temp": 0.61, "b_nur_regen": 0.55, "t20": 12.4,
         "ties_alt": {"alle_gleich": 0.0, "fund_tot": 0.01,
                      "beide_null": 0.02, "funde": 900},
         "ties_neu": {"alle_gleich": 0.0, "fund_tot": 0.04,
                      "beide_null": 0.07, "funde": 900},
         "placebo_alt": 0.50, "placebo_alt_n": 900,
         "placebo_neu": 0.499, "placebo_neu_n": 900,
         "urteil": "bestanden",
         "bedingungen": {"gewinn": True, "band": True, "jahre": True,
                         "placebo": True, "ausland": True}},
        {"name": "Judasohr", "gruppe": "kalt", "optimum": -2.5,
         "klasse": None,
         "panel": {"P1": None, "P2": None, "P3": None},
         "urteil": "zu dünn", "bedingungen": {}},
    ]
    text = render_h1(erfunden)
    assert "## Das Urteil" in text and "bestanden" in text
    assert "zu dünn" in text
    # Die Klasse `sommer` hat in dieser Liste kein Mitglied — der
    # Bericht muss das aushalten und darf nicht so tun, als waere sie
    # bestanden.
    assert "bleibt 5,0" in text, text[:400]

    print("Selbsttest ok")


# --- Der Lauf --------------------------------------------------------------

# Die Arten, die schon Paare haben. Herbstarten und Kaeltefruechter
# zusammen, weil 1.1 und 1.2 ihren Sinn erst aus dem KONTRAST beziehen:
# Eine Asymmetrie bei Winterarten sagt wenig, wenn sie bei Herbstarten
# genauso gross ist.
DIAGNOSE_ARTEN = [
    ("Steinpilz", "herbst"), ("Maronenröhrling", "herbst"),
    ("Birkenpilz", "herbst"), ("Fichtenreizker", "herbst"),
    ("Herbsttrompete", "herbst"), ("Pfifferling", "sommer"),
    ("Hallimasch", "holz"), ("Stockschwämmchen", "holz"),
    ("Austernseitling", "kalt"), ("Judasohr", "kalt"),
    ("Samtfußrübling", "kalt"),
]

GRUPPEN_OPTIMUM = {"herbst": 13.0, "sommer": 17.5, "holz": 13.0,
                   "kalt": -2.5}


def sammle(name, sci, args):
    """Paare einer Art — nur Deutschland, nur Anpassjahre."""
    drawn = av.collect_pairs(name, sci, cache_dir=args.cache, seed=args.seed,
                             progress=True, countries=("DE",))
    if not drawn:
        return None
    samples = fit_years_only(drawn["samples"])
    if not samples:
        return None
    drawn["samples"] = samples
    return drawn


def run(args):
    if args.api:
        av.OPEN_METEO = args.api.rstrip("/")
    av.DEDUPE = args.dedupe
    av.use_dataset(args.dataset)
    print(f"Datensatz: {av.DATASET}, Entdoppeln "
          f"{'an' if av.DEDUPE else 'aus'}, nur DE, nur Jahre bis "
          f"{av.FIT_UNTIL_YEAR}", file=sys.stderr)

    mapping = av.read_species()
    wanted = DIAGNOSE_ARTEN
    if args.only:
        gesucht = {n.strip() for n in args.only.split(",") if n.strip()}
        wanted = [(n, g) for n, g in DIAGNOSE_ARTEN if n in gesucht]

    zeilen = []
    for name, gruppe in wanted:
        if name not in mapping:
            continue
        drawn = sammle(name, mapping[name], args)
        if not drawn:
            print(f"  {name}: keine Paare in den Anpassjahren",
                  file=sys.stderr)
            continue
        optimum = GRUPPEN_OPTIMUM[gruppe]
        samples = drawn["samples"]
        oben = top_recorders(samples)
        ohne = without_recorders(samples, oben)
        zeilen.append({
            "name": name, "gruppe": gruppe, "optimum": optimum,
            "n": len(samples),
            "richtung": direction_split(samples, optimum),
            "frost": frost_profile(samples),
            "melder_gesamt": len({s.get("recordedBy") for s in samples
                                  if s.get("recordedBy")}),
            "top": oben[:3],
            "anteil_top": (len(samples) - len(ohne)) / len(samples),
            "auc_ohne_top": av.paired_auc([
                (av.ampel_score(*s["found"], optimum),
                 av.ampel_score(*s["control"], optimum)) for s in ohne])
            if ohne else None,
            "band_melder": bootstrap_over(samples, optimum,
                                          lambda s: s.get("recordedBy") or
                                          f"anonym-{id(s)}", seed=args.seed),
            "band_jahr": bootstrap_over(samples, optimum,
                                        lambda s: s["year"], seed=args.seed),
        })
        letzte = zeilen[-1]
        print(f"    {name}: AUC vor {_fmt(letzte['richtung']['vor']['auc'])} / "
              f"nach {_fmt(letzte['richtung']['nach']['auc'])}",
              file=sys.stderr)

    # 1.3 — die Target-Group, einmal fuer alle
    referenz = None
    print("Suchaufwand-Referenz (irgendeine Pilzmeldung):", file=sys.stderr)
    roh = target_group_finds()
    if roh:
        referenz = target_group_pairs(roh, args)

    bericht = render(zeilen, referenz)
    if args.out:
        open(args.out, "w", encoding="utf-8").write(bericht)
        print(f"\n{args.out} geschrieben", file=sys.stderr)
    else:
        print(bericht)


def target_group_pairs(roh, args):
    """Dieselbe Paarziehung wie fuer eine Art, nur fuer „irgendeinen Pilz".

    Bewusst ueber denselben Weg wie `collect_pairs`: Eine eigene
    Implementierung waere eine zweite Zufallsfolge und damit eine andere
    Stichprobe — der Vergleich haette dann eine Erklaerung mehr.
    """
    echte = av.fetch_finds

    def gefaelscht(sci, **kwargs):
        return roh

    av.fetch_finds = gefaelscht
    try:
        drawn = av.collect_pairs("Alle Pilze (Target Group)", "—",
                                 cache_dir=args.cache, seed=args.seed,
                                 progress=True, countries=("DE",))
    finally:
        av.fetch_finds = echte
    if not drawn:
        return None
    samples = fit_years_only(drawn["samples"])
    if not samples:
        return None
    out = {"n": len(samples)}
    for gruppe, optimum in (("herbst", 13.0), ("sommer", 17.5),
                            ("kalt", -2.5)):
        out[gruppe] = av.paired_auc([
            (av.ampel_score(*s["found"], optimum),
             av.ampel_score(*s["control"], optimum)) for s in samples])
    out["richtung"] = direction_split(samples, 13.0)
    return out


def render(zeilen, referenz):
    """Der Bericht — ein Abschnitt je Diagnose, im Format des Projekts."""
    aus = []
    w = aus.append
    w("# Diagnosen ohne neues Modell\n")
    w(f"Stand: {__import__('time').strftime('%Y-%m-%d')} · Erzeugt von "
      "`tool/ampel_diagnose.py --all` · Arbeitsplan: "
      "`docs/pilzampel-fahrplan.md`, Phase 1\n")
    w("Gerechnet wird **ausschliesslich auf Deutschland und den Jahren bis "
      f"{av.FIT_UNTIL_YEAR}**. Nichts hier ist ein Test: Es wird keine "
      "Bedingung geprueft und keine Hypothese entschieden. Was hier steht, "
      "liefert die Startbereiche fuer Phase 2 — und zwar so, dass der "
      "Hold-out unberuehrt bleibt.\n")
    w(f"Messbasis: `{av.DATASET}`, Entdoppeln "
      f"{'an' if av.DEDUPE else 'aus'} (`docs/pilzampel-messbasis.md`).\n")

    # --- 1.1 ---
    w("\n## 1.1 Richtungs-Split — Niveau oder Aenderung?\n")
    w("Gepaarte AUC, getrennt danach, ob der Vergleichstag **vor** oder "
      "**nach** dem Fundtag liegt. Beide Haelften stammen aus derselben "
      "Ziehung; nur die Seite unterscheidet sie.\n")
    w("Aehnliche Werte heissen: Das Modell reagiert auf das **Niveau** der "
      "Bedingungen. Eine deutliche Asymmetrie heisst: Es reagiert auf eine "
      "**Aenderung** — dann waere ein Sturz- oder Frostterm die richtige "
      "Erweiterung und nicht eine engere Glocke.\n")
    w("| Art | Gruppe | Paare | AUC gesamt | Vergleichstag vor | danach | "
      "Differenz |")
    w("|---|---|--:|--:|--:|--:|--:|")
    for z in zeilen:
        r = z["richtung"]
        w(f"| {z['name']} | {z['gruppe']} | {z['n']} | "
          f"{_fmt(r['gesamt']['auc'])} | "
          f"{_fmt(r['vor']['auc'])} ({r['vor']['n']}) | "
          f"{_fmt(r['nach']['auc'])} ({r['nach']['n']}) | "
          f"{_signed(r['differenz'])} |")

    # --- 1.2 ---
    w("\n## 1.2 Frost-Vorlauf (beschreibend)\n")
    w("Anteil der Tage mit mindestens einem Frosttag (Tmin ≤ 0 °C) im "
      "Rueckblick, dazu Tage seit dem letzten Frost und Waermesumme "
      "seither. **Fundtag gegen Vergleichstag** — je Art dieselben Paare.\n")
    w("Wo kein Frost im 28-Tage-Fenster liegt, gibt es keine „Tage seit "
      "Frost“; solche Paare zaehlen bei dieser Kennzahl nicht mit, und die "
      "Spalte `n` sagt, wie viele uebrig bleiben. Eine Null dort waere die "
      "Behauptung „gerade erst gefroren“.\n")
    w("| Art | Frost in 7 d F/V | 14 d | 28 d | Tage seit Frost F/V | "
      "n | Waerme seit Frost F/V |")
    w("|---|---|---|---|---|--:|---|")
    for z in zeilen:
        f = z["frost"]
        def paar(key, digits=1, prozent=True):
            a = f[key]["fund"][0]
            b = f[key]["vergleich"][0]
            if a is None or b is None:
                return "—"
            if prozent:
                return f"{a:.0%} / {b:.0%}"
            return f"{a:.{digits}f} / {b:.{digits}f}"
        n = f["tage_seit_frost"]["fund"][1]
        w(f"| {z['name']} | {paar('frosttag_in_7d')} | "
          f"{paar('frosttag_in_14d')} | {paar('frosttag_in_28d')} | "
          f"{paar('tage_seit_frost', 1, False)} | {n} | "
          f"{paar('waerme_seit_frost', 0, False)} |")

    # --- 1.3 ---
    w("\n## 1.3 Suchaufwand-Referenz — die Obergrenze des Aufwandssignals\n")
    w("Dieselbe Paarpruefung fuer **irgendeine Pilzmeldung am Ort** statt "
      "fuer eine Art. Wer meldet, war im Wald — unabhaengig davon, was er "
      "gefunden hat. Menschen gehen nach Regen in den Wald, ein Teil des "
      "Regensignals kann also Sammelverhalten sein.\n")
    w("**Was diese Zahl kann und was nicht:** Sie ist die Obergrenze des "
      "reinen Aufwandssignals. Artspezifisch belastbar ist nur, was eine "
      "Art darueber hinaus zeigt. Sie ist KEIN Abzugsposten — man darf sie "
      "nicht von der AUC einer Art subtrahieren, weil beide dieselbe "
      "Ursache teilen koennen.\n")
    if not referenz:
        w("*Nicht messbar — keine Paare in den Anpassjahren.*")
    else:
        w(f"| Fenster | AUC der Referenz | Paare |")
        w("|---|--:|--:|")
        for gruppe, label in (("herbst", "herbst (13,0 °C)"),
                              ("sommer", "sommer (17,5 °C)"),
                              ("kalt", "kalt (−2,5 °C)")):
            w(f"| {label} | {_fmt(referenz.get(gruppe))} | "
              f"{referenz['n']} |")
        w("")
        r = referenz["richtung"]
        w(f"Richtungs-Split der Referenz (13 °C): vor "
          f"{_fmt(r['vor']['auc'])}, danach {_fmt(r['nach']['auc'])}.\n")
        w("**Je Art gegen die Referenz** (nur das Fenster der eigenen "
          "Gruppe):\n")
        w("**Die Spalte heisst „Differenz zur Referenz\u201c und nicht "
          "„Ueberschuss\u201c** (A6): Ein Ueberschuss klaenge nach einem "
          "Betrag, den man behalten darf, wenn man den Rest abzieht. Genau "
          "das geht hier nicht — „irgendeine Pilzmeldung\u201c ist nicht "
          "reiner Suchaufwand, sondern ueberwiegend ANDERE PILZE, die auf "
          "dasselbe Wetter reagieren. Die Referenz ist Obergrenze fuer den "
          "Aufwand UND Untergrenze fuer die allgemeine Pilz-Wetterreaktion; "
          "dieses Design kann die beiden nicht trennen. Die Differenz ist "
          "also kein Abzugsposten, sondern eine Einordnung.\n")
        w("| Art | AUC der Art | AUC der Referenz | Differenz zur Referenz |")
        w("|---|--:|--:|--:|")
        for z in zeilen:
            eigen = z["richtung"]["gesamt"]["auc"]
            ref = referenz.get(z["gruppe"] if z["gruppe"] in referenz
                               else "herbst")
            if eigen is None or ref is None:
                w(f"| {z['name']} | {_fmt(eigen)} | {_fmt(ref)} | — |")
            else:
                w(f"| {z['name']} | {eigen:.3f} | {ref:.3f} | "
                  f"{eigen - ref:+.3f} |")

    # --- 1.4 ---
    w("\n## 1.4 Melder-Abhaengigkeit\n")
    w("Traegt eine Handvoll Vielmelder die Zahl? Zwei Blickwinkel: die AUC "
      "**ohne** die zehn aktivsten Melder, und ein Bootstrap ueber "
      "**Melder** statt ueber Jahre.\n")
    w("Der Bootstrap ueber Melder ist der schaerfere: Paare derselben "
      "Person sind nicht unabhaengig, und wer ueber Paare zieht, bekommt "
      "einen zu engen Bereich. Zum Vergleich steht der Jahres-Bootstrap "
      "daneben — der ist der, mit dem bisher berichtet wurde.\n")
    w("| Art | Melder | Anteil der Top 10 | AUC gesamt | ohne Top 10 | "
      "Bootstrap ueber Melder | ueber Jahre |")
    w("|---|--:|--:|--:|--:|---|---|")
    for z in zeilen:
        def band(b):
            return "—" if b is None else f"[{b[0]:.3f}, {b[1]:.3f}]"
        w(f"| {z['name']} | {z['melder_gesamt']} | {z['anteil_top']:.0%} | "
          f"{_fmt(z['richtung']['gesamt']['auc'])} | "
          f"{_fmt(z['auc_ohne_top'])} | {band(z['band_melder'])} | "
          f"{band(z['band_jahr'])} |")

    w("\n## Grenzen\n")
    w("Gemessen wurde ausschliesslich an GBIF, in Deutschland, auf den "
      "Anpassjahren. Keine dieser Zahlen ist ein Beleg fuer irgendetwas — "
      "sie sagen, wo sich das Hinsehen lohnt.\n")
    w("Und keine ersetzt die Registrierung: Was aus ihnen folgt, wird als "
      "Hypothese aufgeschrieben, BEVOR sie an Pruefdaten kommt.")
    return "\n".join(aus) + "\n"


# --- Phase 1.5: beide Designs nebeneinander --------------------------------

DESIGN_ARTEN = [
    ("Steinpilz", "herbst", 13.0), ("Maronenröhrling", "herbst", 13.0),
    ("Birkenpilz", "herbst", 13.0), ("Fichtenreizker", "herbst", 13.0),
    ("Herbsttrompete", "herbst", 13.0), ("Pfifferling", "sommer", 17.5),
    ("Hallimasch", "holz", 13.0), ("Stockschwämmchen", "holz", 13.0),
    ("Austernseitling", "kalt", -2.5), ("Judasohr", "kalt", -2.5),
    ("Samtfußrübling", "kalt", -2.5),
]

# Unter so vielen Funden wird nicht gerechnet, sondern „zu duenn"
# geschrieben. **Gezaehlt werden FUNDE, nicht Vergleiche** — bei fuenf
# Kontrolljahren je Fund waere die Zahl der Vergleiche fuenfmal so gross
# und sagte ueber die Unabhaengigkeit nichts.
MIN_FINDS_B = 150


def _band(zuege, null):
    """Aus den Zuegen das 95-%-Band UND den Anteil auf der falschen Seite.

    **Der dritte Wert ist der wichtigere**, sobald eine Entscheidung an
    der Bandkante haengt: Der Anteil der Zuege jenseits von `null` ist
    eine stetige Groesse, die 2,5-%-Kante dagegen ist der zehnte von 400
    Zuegen und traegt allein aus dem Losverfahren mehr Rauschen, als
    manche Entscheidung Abstand hat. Zusammen mit einer hohen Zugzahl
    wird daraus eine Zahl, die man hinschreiben kann, statt eines Hakens,
    der kippelt.
    """
    zuege.sort()
    unter = (sum(1 for z in zuege if z < null)
             + 0.5 * sum(1 for z in zuege if z == null))
    return (zuege[int(0.025 * len(zuege))],
            zuege[min(len(zuege) - 1, int(0.975 * len(zuege)))],
            unter / len(zuege))


def _fractions(samples, optimum, schluessel, score=None):
    """Je Gruppe die vorgerechneten Anteile aus `score_b`.

    `score` ist der Bewerter `(regen, temp) -> Zahl`; ohne ihn der
    ausgelieferte mit dem uebergebenen Optimum. Ueber ihn laufen die
    H1-Breiten und die Zerlegung in Temperatur- und Regenanteil, ohne
    dass diese Funktion von ihnen wissen muss.

    **Dieselbe Groesse, nur einmal statt je Zug gerechnet.** `score_b`
    bildet fuer jeden Fund den Anteil der geschlagenen Kontrolljahre und
    mittelt darueber; der Anteil haengt ausschliesslich an diesem einen
    Fund. Ein Bootstrap ueber Gruppen zieht also Mittelwerte ueber eine
    feste Zahlenliste — das Neubewerten aller Vergleiche in jedem Zug war
    reine Wiederholung. Der Selbsttest haelt beide Wege gegeneinander.
    """
    if score is None:
        score = lambda regen, temp: av.ampel_score(regen, temp, optimum)
    gruppen = {}
    for s in samples:
        wert = ab.beat_fraction(score(*s["found"]),
                                [score(*c) for c in s["controls"]])
        if wert is not None:
            gruppen.setdefault(schluessel(s), []).append(wert)
    return gruppen


def _ziehe(gruppen, rounds, seed, null):
    """Ein Bootstrap ueber die vorgerechneten Gruppen."""
    namen = sorted(gruppen, key=str)
    if len(namen) < 2:
        return None
    rng = random.Random(seed)
    zuege = []
    for _ in range(rounds):
        werte = [w for name in rng.choices(namen, k=len(namen))
                 for w in gruppen[name]]
        if werte:
            zuege.append(sum(werte) / len(werte))
    return _band(zuege, null) if zuege else None


def bootstrap_b(samples, optimum, schluessel, rounds=BOOTSTRAP_ROUNDS,
                seed=42, limit=None, null=0.5):
    """95-%-Bereich des B-Masses, gezogen ueber Gruppen.

    Ueber das FUNDJAHR, nicht ueber „das Jahr": Ein B-Paar gehoert zu
    zwei Jahren, und ohne diese Festlegung aenderte dieselbe Spalte ihre
    Bedeutung zwischen den Designs, ohne dass es jemand saehe.

    Rueckgabe: `(unten, oben, p)` — siehe `_band`.
    """
    if limit is None:
        return _ziehe(_fractions(samples, optimum, schluessel), rounds,
                      seed, null)
    # Mit `limit` zaehlen nur die ersten Kontrolljahre, der Anteil je Fund
    # ist also ein anderer — dann den langen Weg.
    gruppen = {}
    for s in samples:
        gruppen.setdefault(schluessel(s), []).append(s)
    namen = sorted(gruppen, key=str)
    if len(namen) < 2:
        return None
    rng = random.Random(seed)
    zuege = []
    for _ in range(rounds):
        gezogen = [rng.choice(namen) for _ in namen]
        teil = [s for name in gezogen for s in gruppen[name]]
        wert, _ = av.score_b(teil, optimum, limit=limit)
        if wert is not None:
            zuege.append(wert)
    if not zuege:
        return None
    return _band(zuege, null)


# --- Nachtrag 1 zu Auftrag 2: N1 bis N4 ------------------------------------

# Zweiseitig, alpha = 0,05, Trennschaerfe 80 %: z(0,975) + z(0,80).
MDE_FAKTOR = 1.959964 + 0.841621

# Zuege fuer die Baender in Phase 1.5. **Deutlich mehr als die 400 der
# Phase-1-Diagnosen**, und das hat einen Grund: Hier haengen Urteile an
# der Frage, ob ein Band eine Null einschliesst. Mit 400 Zuegen ist die
# 2,5-%-Kante der zehnte Zug, und ihr Eigenrauschen ist groesser als der
# Abstand, den die knappsten Faelle haben.
# Zwanzigtausend statt zweitausend, und das kostet fast nichts: `score_b`
# mittelt je Fund einen Anteil, und dieser Anteil haengt am Fund allein.
# Einmal vorgerechnet (`_fractions`), ist ein Zug nur noch ein Mittelwert
# ueber Gleitkommazahlen statt ein Neubewerten aller Vergleiche. Erst
# damit ist der p-Wert genauer als die Entscheidung, die an ihm haengt:
# bei 2000 Zuegen hat ein p von 0,025 einen eigenen Standardfehler von
# 0,0035 — und ein Urteil, das zwischen 0,0245 und 0,0255 kippt, ist
# keines.
BOOTSTRAP_ROUNDS_B = 20000

# Ab hier gilt ein Band als „schliesst die Null aus" — dieselbe Grenze,
# die ein 95-%-Band zieht, nur als stetige Zahl statt als Kante.
P_GRENZE = 0.025

# **Die Zuordnung, wie sie im angenommenen Bericht stand** (Commit
# `fb6f2db`, Auftrag 2 Abschnitt 5). Sie wird hier woertlich aufgehoben
# und nicht nachgerechnet: Die alte Regel haengt am Abschlag A-B, und
# eine nachgebaute Regel koennte still von dem abweichen, was damals
# tatsaechlich dastand. Der Nachtrag verlangt beide Zuordnungen
# nebeneinander — dafuer muss die alte unveraenderlich sein.
STUFE_ALT = {
    "Pfifferling": "belegt",
    "Steinpilz": "vorläufig", "Maronenröhrling": "vorläufig",
    "Birkenpilz": "vorläufig", "Fichtenreizker": "vorläufig",
    "Herbsttrompete": "vorläufig",
    "Stockschwämmchen": "keine Aussage", "Judasohr": "keine Aussage",
    "Samtfußrübling": "keine Aussage", "Austernseitling": "keine Aussage",
    "Hallimasch": "keine Aussage",
}


def score_b_year(samples):
    """N4 — die JAHRESZAHL allein als Score auf denselben B-Paaren.

    Die Frage dahinter: Bei neun von elf Arten sind spaetere Kontrolljahre
    leichter zu schlagen. Ein Instrumentwechsel kann es nicht sein, der
    Datensatz ist gepinnt. Bleibt die Moeglichkeit, dass B einen Anteil
    „das Fundjahr liegt frueh im Zeitraum" enthaelt — und der schlaegt nur
    durch, wenn die ZIEHUNG schief liegt.

    Genau das misst dieser Wert. Er ist `score_b` mit der Jahreszahl
    anstelle des Ampel-Scores; ein Gleichstand kann nicht vorkommen, weil
    ein Kontrolljahr nie das Fundjahr ist. Eine perfekt ausgeglichene
    Ziehung ergibt **0,500 von Konstruktion wegen**. Jede Abweichung ist
    Unwucht, und ueber der Richtungs-Differenz gewichtet sagt sie, wieviel
    davon in der B-Zahl steckt.

    Rueckgabe: (wert, n, frueher, spaeter) — die beiden Zaehler sind
    KONTROLLJAHRE, nicht Funde.
    """
    anteile = []
    frueher = spaeter = 0
    for s in samples:
        jahre = s.get("control_years") or []
        if not jahre:
            continue
        frueher += sum(1 for y in jahre if y < s["year"])
        spaeter += sum(1 for y in jahre if y > s["year"])
        anteile.append(ab.beat_fraction(s["year"], jahre))
    return ab.mean_beat(anteile), len(anteile), frueher, spaeter


def bootstrap_ref_diff(art, referenz, optimum, rounds=BOOTSTRAP_ROUNDS,
                       seed=42):
    """N2 — Vertrauensbereich der Differenz Art minus Referenz.

    Gezogen wird ueber das FUNDJAHR wie beim Bootstrap von B, und
    **gemeinsam**: Ein gezogenes Jahr bringt seine Funde der Art UND seine
    Referenzfunde mit. Getrennt zu ziehen unterstellte, die beiden Zahlen
    streuten unabhaengig — sie teilen sich aber das Wetter derselben
    Jahre, und genau deshalb kann die Differenz enger sein als jeder
    ihrer beiden Summanden.

    Warum das noetig wurde: Der Referenzabstand traegt inzwischen die
    haerteste Einzelentscheidung (Stockschwaemmchen +0,001), stand aber
    als Punktschaetzer ohne jede Streuung da.
    """
    jahr = lambda s: s["year"]
    a_jahre = _fractions(art, optimum, jahr)
    r_jahre = _fractions(referenz, optimum, jahr)
    namen = sorted(set(a_jahre) | set(r_jahre))
    if len(namen) < 2:
        return None
    rng = random.Random(seed)
    zuege = []
    for _ in range(rounds):
        gezogen = rng.choices(namen, k=len(namen))
        a = [w for j in gezogen for w in a_jahre.get(j, ())]
        r = [w for j in gezogen for w in r_jahre.get(j, ())]
        if a and r:
            zuege.append(sum(a) / len(a) - sum(r) / len(r))
    if not zuege:
        return None
    return _band(zuege, 0.0)


def mde_from_band(band):
    """N3 — der kleinste Effekt, der bei dieser Streuung 80 % sichtbar wird.

    Der Standardfehler kommt aus dem JAHRES-Bootstrap und nicht aus der
    Paarzahl: `sqrt(0.25/n)` unterstellt unabhaengige Paare, und B-Paare
    desselben Jahres teilen sich das Wetter. Der geclusterte Fehler ist
    hier der groessere — und damit der ehrliche.

    Die Zahl beantwortet „wie gross haette ein Auslaesereffekt sein
    muessen, um aufzufallen", nicht „wie gross ist er". Unterhalb davon
    sagt dieser Aufbau nichts, weder ja noch nein.
    """
    if band is None:
        return None
    return MDE_FAKTOR * (band[1] - band[0]) / (2 * 1.959964)


def evidenzstufe(z):
    """Die Evidenzstufe nach N1 des Nachtrags — vier Bedingungen.

    **Was die alte Regel falsch machte:** Auftrag 2, Abschnitt 5 machte
    den Abschlag `A - B < 0,05` zur Bedingung fuer „belegt". Abschnitt 3
    desselben Auftrags sagt aber, dass B aus zwei strukturellen Gruenden
    kleiner sein MUSS. Die Latte bestrafte damit genau den erwarteten
    Effekt und mass nicht die Belastbarkeit — der Pfifferling galt als
    belegt, weil sein A wenig Kalender zu verlieren hatte.

    Der Abschlag bleibt in jeder Tabelle stehen, als Auskunft darueber,
    wieviel Kalender in der A-Zahl steckt. Er ist nur kein Tor mehr.

    Rueckgabe: (stufe, bedingungen) — `bedingungen` ist ein dict mit
    genau den vier Namen, damit der Bericht zeigen kann, WELCHE wackelt.
    """
    ref_d = (None if z["b_auc"] is None or z["ref_b"] is None
             else z["b_auc"] - z["ref_b"])
    band = z["b_band_jahr"]
    ref_band = z.get("ref_band")
    bed = {
        "bootstrap": band is not None and band[2] < P_GRENZE,
        "referenz": (ref_d is not None and ref_d > 0
                     and ref_band is not None and ref_band[2] < P_GRENZE),
        "funde": z["b_n"] is not None and z["b_n"] >= MIN_FINDS_B,
        "kontrollen": (
            z["a_mirror"] is not None
            and av.control_clean(z["a_mirror"], z["a_mirror_n"])
            and z["b_plac"] is not None
            and av.control_clean(z["b_plac"], z["b_plac_n"])),
    }
    # **Der Ausschluss ist die REFERENZ, und nur sie.**
    #
    # N1 nennt zwei Saetze, die sich an einer Stelle widersprechen:
    # „vorlaeufig" gilt, wenn B ueber der Referenz und ueber 0,50 liegt
    # und EINE der vier Bedingungen wackelt — „keine Aussage" gilt, wenn
    # B die Referenz nicht erreicht ODER der Bootstrap 0,50 einschliesst.
    # Eine Art, deren Bootstrap wackelt und die sonst traegt, faellt
    # unter beide Saetze zugleich.
    #
    # Aufgeloest wird es ueber die Erwartung, die der Nachtrag selbst
    # nennt: Dort steht der Fichtenreizker unter „vorlaeufig" mit der
    # Begruendung „Bootstrap streift 0,50". Der speziellere Satz gewinnt
    # also, und der Bootstrap ist eine der vier wackelnden Bedingungen,
    # kein eigener Ausschluss. Uebrig bleibt als Ausschluss die Referenz
    # — die Groesse, die N2 gerade erst mit einem Vertrauensbereich
    # versehen hat, und nach N1 ohnehin „der inhaltlich bessere" Massstab.
    if not bed["referenz"]:
        return "keine Aussage", bed
    if all(bed.values()):
        return "belegt", bed
    if z["b_auc"] is None or z["b_auc"] <= 0.5:
        return "keine Aussage", bed
    return "vorläufig", bed


def run_designs(args):
    """Phase 1.5 — Design A und Design B auf derselben Stichprobe."""
    if args.api:
        av.OPEN_METEO = args.api.rstrip("/")
    av.DEDUPE = args.dedupe
    av.use_dataset(args.dataset)
    print(f"Datensatz: {av.DATASET}, Entdoppeln "
          f"{'an' if av.DEDUPE else 'aus'}, nur DE, nur Jahre bis "
          f"{av.FIT_UNTIL_YEAR}", file=sys.stderr)

    mapping = av.read_species()
    wanted = DESIGN_ARTEN
    if args.only:
        gesucht = {n.strip() for n in args.only.split(",") if n.strip()}
        wanted = [z for z in DESIGN_ARTEN if z[0] in gesucht]

    pool = None
    zeilen = []
    for name, gruppe, optimum in wanted:
        if name not in mapping:
            continue
        sci = mapping[name]
        print(f"  {name} ({sci})", file=sys.stderr)
        finds, info = av.select_finds(sci, args.cache, args.seed, True,
                                      ("DE",))
        if not finds:
            continue

        # **Dieselbe Fundliste in beide Designs.**
        a = av.collect_pairs(name, sci, cache_dir=args.cache, seed=args.seed,
                             progress=False, finds=finds)
        b = av.collect_pairs_b(name, sci, finds=finds, cache_dir=args.cache,
                               seed=args.seed, progress=True)
        if not a or not b:
            continue
        a_s = fit_years_only(a["samples"])
        b_s = fit_years_only(b["samples"])

        a_auc = av.paired_auc([(av.ampel_score(*s["found"], optimum),
                                av.ampel_score(*s["control"], optimum))
                               for s in a_s]) if a_s else None
        a_mirror = av.paired_auc([(av.ampel_score(*s["control"], optimum),
                                   av.ampel_score(*s["mirror"], optimum))
                                  for s in a_s if s.get("mirror")])
        b_auc, b_n = av.score_b(b_s, optimum)
        b_auc1, _ = av.score_b(b_s, optimum, limit=1)
        b_plac, b_plac_n = av.placebo_b(b_s, optimum)
        b_frueh, _ = av.score_b(b_s, optimum, side="frueher")
        b_spaet, _ = av.score_b(b_s, optimum, side="spaeter")

        # A3 — die artgematchte Referenz, je Art
        if pool is None:
            print("    Referenzbestand wird geladen …", file=sys.stderr)
            pool = target_group_finds(progress=True)
        ref_finds, ref_info = matched_reference(finds, pool, sci,
                                                seed=args.seed)
        ref_b = ref_band = None
        if len(ref_finds) >= 50:
            rb = av.collect_pairs_b("Referenz " + name, "—", finds=ref_finds,
                                    cache_dir=args.cache, seed=args.seed,
                                    progress=False)
            if rb:
                ref_s = fit_years_only(rb["samples"])
                ref_b = av.score_b(ref_s, optimum)[0]
                # N2 — die Differenz bekommt ihre eigene Streuung, und
                # zwar aus demselben Zug: gemeinsam ueber das Fundjahr.
                ref_band = bootstrap_ref_diff(b_s, ref_s, optimum,
                                              rounds=BOOTSTRAP_ROUNDS_B,
                                              seed=args.seed)

        # N4 — traegt die Ziehung einen Zeitanteil? Kostet nichts, die
        # Paare liegen schon da.
        jahr_auc, jahr_n, jahr_frueher, jahr_spaeter = score_b_year(b_s)

        zeilen.append({
            "name": name, "gruppe": gruppe, "optimum": optimum,
            "a_n": len(a_s), "a_auc": a_auc, "a_mirror": a_mirror,
            "a_mirror_n": len([s for s in a_s if s.get("mirror")]),
            "b_n": b_n, "b_auc": b_auc, "b_auc1": b_auc1,
            "b_plac": b_plac, "b_plac_n": b_plac_n,
            "b_frueh": b_frueh, "b_spaet": b_spaet,
            "b_band_jahr": bootstrap_b(b_s, optimum, lambda s: s["year"],
                                       rounds=BOOTSTRAP_ROUNDS_B,
                                       seed=args.seed),
            "b_band_melder": bootstrap_b(
                b_s, optimum,
                lambda s: s.get("recordedBy") or f"a{id(s)}",
                rounds=BOOTSTRAP_ROUNDS_B, seed=args.seed),
            "ausgewichen": b["ausgewichen"], "ohne_jahr": b["ohne_jahr"],
            "fehlende_jahre": b["fehlende_jahre"],
            "ref_b": ref_b, "ref_n": len(ref_finds), "ref_info": ref_info,
            "ref_band": ref_band,
            "jahr_auc": jahr_auc, "jahr_n": jahr_n,
            "jahr_frueher": jahr_frueher, "jahr_spaeter": jahr_spaeter,
            "duenn": b_n < MIN_FINDS_B,
            "frost_b": frost_profile_b(b_s) if gruppe == "kalt" else None,
        })
        z = zeilen[-1]
        print(f"    A {_fmt(z['a_auc'])} ({z['a_n']})   "
              f"B {_fmt(z['b_auc'])} ({z['b_n']})   "
              f"Placebo B {_fmt(z['b_plac'])}", file=sys.stderr)

    bericht = render_designs(zeilen)
    if args.out:
        open(args.out, "w", encoding="utf-8").write(bericht)
        print(f"\n{args.out} geschrieben", file=sys.stderr)
    else:
        print(bericht)


def frost_profile_b(samples):
    """Die Frost-Diagnose aus 1.2, aber in Design B.

    **Erst hier ist sie ablesbar.** In Design A liegen die Vergleichstage
    26–45 Tage neben dem Fund und damit bei einer Winterart zwangslaeufig
    Richtung Herbst und Fruehjahr — dass Fundtage dann mehr Frost im
    Ruecken haben, folgt schon aus dem Kalender. In Design B liegt der
    Vergleichstag am selben Datum anderer Jahre; was hier bleibt, ist
    Wetter und nicht Jahreszeit.
    """
    out = {}
    for length in FROST_LOOKBACKS:
        treffer_f = gesamt_f = treffer_v = gesamt_v = 0
        for s in samples:
            n = frost_days(s.get("extra", {}).get("tmin"), length)
            if n is not None:
                gesamt_f += 1
                treffer_f += 1 if n > 0 else 0
            for extra in s.get("extra_controls", []):
                m = frost_days(extra.get("tmin"), length)
                if m is not None:
                    gesamt_v += 1
                    treffer_v += 1 if m > 0 else 0
        out[f"frosttag_in_{length}d"] = {
            "fund": (treffer_f / gesamt_f if gesamt_f else None, gesamt_f),
            "vergleich": (treffer_v / gesamt_v if gesamt_v else None,
                          gesamt_v)}
    for name, fn in (("tage_seit_frost",
                      lambda tmin, temp: days_since_frost(tmin)),
                     ("waerme_seit_frost",
                      lambda tmin, temp: warmth_since_frost(temp, tmin))):
        f_werte, v_werte = [], []
        for s in samples:
            w = fn(s.get("extra", {}).get("tmin"),
                   s["found"][1] if s.get("found") else None)
            if w is not None:
                f_werte.append(w)
            for extra, ctrl in zip(s.get("extra_controls", []),
                                   s.get("controls", [])):
                w = fn(extra.get("tmin"), ctrl[1])
                if w is not None:
                    v_werte.append(w)
        out[name] = {
            "fund": (statistics.fmean(f_werte) if f_werte else None,
                     len(f_werte)),
            "vergleich": (statistics.fmean(v_werte) if v_werte else None,
                          len(v_werte))}
    return out


def render_designs(zeilen):
    """Der Bericht zu Phase 1.5."""
    import time as _t
    aus = []
    w = aus.append
    band = lambda b: "—" if b is None else f"[{b[0]:.3f}, {b[1]:.3f}]"
    w("# Zwei Kontrolltag-Designs nebeneinander\n")
    w(f"Stand: {_t.strftime('%Y-%m-%d')} · Erzeugt von "
      "`tool/ampel_diagnose.py --designs` · Auftrag: "
      "`docs/pilzampel-auftrag-2.md`, Abschnitt 3\n")
    w("Gerechnet auf **Deutschland und den Jahren bis "
      f"{av.FIT_UNTIL_YEAR}**. Kein Hold-out-Kontakt. Beide Designs "
      "laufen auf **derselben Fundliste** — sonst wäre ihr Unterschied "
      "teils die Stichprobe statt das Design.\n")
    w(f"Messbasis: `{av.DATASET}`, Entdoppeln "
      f"{'an' if av.DEDUPE else 'aus'}.\n")

    w("\n## Was die beiden Designs fragen\n")
    w("**Design A** vergleicht den Fundtag mit einem Tag 26–45 Tage "
      "daneben im selben Jahr. Das kürzt die Saison nur ungefähr heraus.\n")
    w("**Design B** vergleicht ihn mit demselben Datum (±7 Tage) in fünf "
      "anderen Jahren am selben Ort. Die Saison kürzt sich vollständig "
      "heraus, und übrig bleibt: *War das Wetter dieses Jahr an diesem "
      "Datum besser als an diesem Datum üblich?*\n")
    w("**Zwei Gründe, warum B kleinere Zahlen liefern MUSS**, beide vorab "
      "festgehalten und keine Fehlschläge:\n")
    w("1. Die Kalenderkomponente fehlt. Was in A die Saison beisteuerte, "
      "steht in B nicht mehr zur Verfügung.")
    w("2. **„Üblich\u201c schließt die guten Jahre ein.** Ein Kontrolljahr "
      "kann am selben Ort zur selben Woche sehr wohl einen Fund getragen "
      "haben — Presence-only trennt „kein Fund\u201c nicht von „niemand war "
      "da\u201c. Solche Jahre auszuschließen wäre genau der Detektionsfehler, "
      "den die Daten nicht hergeben. Also bleiben sie drin, und sie "
      "dämpfen die Zahl.\n")

    w("\n## Gemessen\n")
    w("| Art | Gruppe | AUC A | AUC B (k=5) | B (k=1) | Differenz B−A | "
      "Placebo B | Funde A / B |")
    w("|---|---|--:|--:|--:|--:|--:|--:|")
    for z in zeilen:
        d = (None if z["a_auc"] is None or z["b_auc"] is None
             else z["b_auc"] - z["a_auc"])
        marke = " ⚠ zu dünn" if z["duenn"] else ""
        w(f"| {z['name']}{marke} | {z['gruppe']} | {_fmt(z['a_auc'])} | "
          f"**{_fmt(z['b_auc'])}** | {_fmt(z['b_auc1'])} | "
          f"{_signed(d)} | {_fmt(z['b_plac'])} | "
          f"{z['a_n']} / {z['b_n']} |")
    w("")
    w(f"„Zu dünn\u201c heißt: unter {MIN_FINDS_B} Funden in Design B. Dort "
      "steht die Zahl zur Einordnung, sie trägt aber kein Urteil.\n")

    w("\n## Kontrollen und Vertrauensbereiche\n")
    w("| Art | Spiegel A | Toleranz A | Placebo B | Toleranz B | "
      "B über Jahre | p | B über Melder |")
    w("|---|--:|--:|--:|--:|---|--:|---|")
    for z in zeilen:
        ta = av.control_tolerance(z["a_mirror_n"])
        tb = av.control_tolerance(z["b_plac_n"])
        ma = "" if z["a_mirror"] is None or av.control_clean(
            z["a_mirror"], z["a_mirror_n"]) else " ⚠"
        mb = "" if z["b_plac"] is None or av.control_clean(
            z["b_plac"], z["b_plac_n"]) else " ⚠"
        w(f"| {z['name']} | {_fmt(z['a_mirror'])}{ma} | ±{ta:.3f} | "
          f"{_fmt(z['b_plac'])}{mb} | ±{tb:.3f} | "
          f"{band(z['b_band_jahr'])} | {_pwert(z['b_band_jahr'])} | "
          f"{band(z['b_band_melder'])} |")
    w("")
    w("Die Toleranz ist **zwei Standardfehler bei der jeweiligen "
      "Paarzahl** (A2), nicht mehr die feste ±0,03. Der Bootstrap in "
      "Design B zieht über das **Fundjahr** — ein B-Paar gehört zu zwei "
      "Jahren, und ohne diese Festlegung änderte dieselbe Spalte ihre "
      "Bedeutung zwischen den Designs.\n")

    w("\n## Richtungs-Split in Design B\n")
    w("Kontrolljahr früher gegen später. Eine Schieflage deckt "
      "Klimatrend und Instrumentreste auf — anders als in Design A, wo "
      "derselbe Split die Saisonsteigung misst.\n")
    w("| Art | B früher | B später | Differenz |")
    w("|---|--:|--:|--:|")
    for z in zeilen:
        d = (None if z["b_frueh"] is None or z["b_spaet"] is None
             else z["b_spaet"] - z["b_frueh"])
        w(f"| {z['name']} | {_fmt(z['b_frueh'])} | {_fmt(z['b_spaet'])} | "
          f"{_signed(d)} |")

    w("\n## Die Ziehung: wo sie ausweichen musste\n")
    w("Bei Funden aus den Randjahren ist eine Seite leer. Dann wird die "
      "andere genommen — und es wird gezählt, sonst wäre die Regel wieder "
      "eine Hoffnung, nur unsichtbar.\n")
    w("| Art | Seitenwechsel | Funde ohne brauchbares Jahr | fehlende Jahre |")
    w("|---|--:|--:|---|")
    for z in zeilen:
        fehlt = (", ".join(f"{j}×{n}" for j, n in
                           sorted(z["fehlende_jahre"].items()))
                 or "keine")
        w(f"| {z['name']} | {z['ausgewichen']} | {z['ohne_jahr']} | {fehlt} |")

    w("\n## Die artgematchte Aufwands-Referenz (A3)\n")
    w("Referenzmeldungen aus **denselben ~10-km-Zellen** und mit der "
      "**Monatsverteilung der Zielart** als Gewicht, Zielart "
      "ausgeschlossen — und in Design B ausgewertet. Die alte Referenz "
      "aus Phase 1.3 stammte aus der allgemeinen, herbstlastigen "
      "Verteilung und war für eine Winterart keine faire Vergleichsgröße.\n")
    w("**Die Spalte ist kein Abzugsposten** (A6): „irgendeine "
      "Pilzmeldung\u201c ist überwiegend *andere Pilze*, die auf dasselbe "
      "Wetter reagieren. Die Referenz begrenzt den Suchaufwand nach oben "
      "und die allgemeine Pilz-Wetterreaktion nach unten; dieses Design "
      "kann die beiden nicht trennen.\n")
    w("| Art | B der Art | B der Referenz | Differenz zur Referenz | "
      "95 % der Differenz | p | Referenzfunde | Zellen |")
    w("|---|--:|--:|--:|---|--:|--:|--:|")
    for z in zeilen:
        d = (None if z["b_auc"] is None or z["ref_b"] is None
             else z["b_auc"] - z["ref_b"])
        w(f"| {z['name']} | {_fmt(z['b_auc'])} | {_fmt(z['ref_b'])} | "
          f"{_signed(d)} | {band(z.get('ref_band'))} | "
          f"{_pwert(z.get('ref_band'))} | {z['ref_n']} | "
          f"{z['ref_info']['zellen']} |")
    w("")
    w("Der Vertrauensbereich der Differenz (N2) ist **gemeinsam über das "
      "Fundjahr** gezogen: Ein gezogenes Jahr bringt seine Funde der Art "
      "und seine Referenzfunde mit. Getrennt zu ziehen unterstellte, die "
      "beiden Zahlen streuten unabhängig — sie teilen sich aber das "
      "Wetter derselben Jahre.\n")
    w("Und eine Korrektur am eigenen Text: Schwelle und Referenzabstand "
      "sind **nicht zwei unabhängige Kriterien**. Beide beruhen auf "
      "denselben B-AUCs; sie sind zwei Blickwinkel auf dieselbe Zahl, und "
      "der Referenzabstand ist der inhaltlich bessere, weil er den "
      "Suchaufwand mitführt.\n")

    w("\n## Die Jahreszahl allein als Score (N4)\n")
    w("Der Richtungs-Split oben zeigt bei neun von elf Arten: **spätere "
      "Kontrolljahre sind leichter zu schlagen.** Ein Instrumentwechsel "
      "kann es nicht sein, der Datensatz ist gepinnt. Bleibt die Frage, "
      "ob B einen Anteil „das Fundjahr liegt früh im Zeitraum\u201c "
      "enthält — und der schlägt nur durch, wenn die **Ziehung** schief "
      "liegt.\n")
    w("Dieselbe Rechnung wie B, nur mit der Jahreszahl statt des "
      "Ampel-Scores. Eine ausgeglichene Ziehung ergibt **0,500 von "
      "Konstruktion wegen**; jede Abweichung ist Unwucht.\n")
    w("| Art | Jahr als Score | Kontrolljahre früher | später | "
      "Richtungs-Differenz | Beitrag |")
    w("|---|--:|--:|--:|--:|--:|")
    for z in zeilen:
        rd = (None if z["b_frueh"] is None or z["b_spaet"] is None
              else z["b_spaet"] - z["b_frueh"])
        # Was die Unwucht zur B-Zahl beitraegt. Mit p = Anteil frueherer
        # Kontrolljahre ist B ~ p*B_frueh + (1-p)*B_spaet; eine
        # ausgeglichene Ziehung waere der Mittelwert der beiden Seiten.
        # Die Differenz dazu ist -(p - 0,5) * (B_spaet - B_frueh).
        schief = (None if z["jahr_auc"] is None else z["jahr_auc"] - 0.5)
        beitrag = (None if schief is None or rd is None else -schief * rd)
        w(f"| {z['name']} | {_fmt(z['jahr_auc'])} | {z['jahr_frueher']} | "
          f"{z['jahr_spaeter']} | {_signed(rd)} | {_signed(beitrag)} |")

    kalt = [z for z in zeilen if z["frost_b"]]
    if kalt:
        w("\n## Frost-Diagnose in Design B\n")
        w("Dieselbe Rechnung wie in Phase 1.2, aber gegen Tage desselben "
          "Datums anderer Jahre. **Erst hier ist ablesbar, ob die "
          "Frost-Signatur den Kalender überlebt** — in Design A liegen die "
          "Vergleichstage einer Winterart zwangsläufig Richtung Herbst und "
          "Frühjahr, dass Fundtage dann mehr Frost im Rücken haben, folgt "
          "schon daraus.\n")
        w("| Art | Frost 7 d F/V | 14 d | 28 d | Tage seit Frost F/V | "
          "Wärme seit Frost F/V |")
        w("|---|---|---|---|---|---|")
        for z in kalt:
            f = z["frost_b"]
            def paar(key, prozent=True, digits=0):
                a, b = f[key]["fund"][0], f[key]["vergleich"][0]
                if a is None or b is None:
                    return "—"
                if prozent:
                    return f"{a:.0%} / {b:.0%}"
                return f"{a:.{digits}f} / {b:.{digits}f}"
            w(f"| {z['name']} | {paar('frosttag_in_7d')} | "
              f"{paar('frosttag_in_14d')} | {paar('frosttag_in_28d')} | "
              f"{paar('tage_seit_frost', False, 1)} | "
              f"{paar('waerme_seit_frost', False, 0)} |")

        w("")
        w("**Wie groß hätte ein Auslösereffekt sein müssen, um hier "
          "aufzufallen?** (N3) Nicht „kein Effekt\u201c, sondern eine "
          "Grenze: Unterhalb davon sagt dieser Aufbau nichts, weder ja "
          "noch nein.\n")
        w("| Art | Funde in B | B | Standardfehler (Jahre) | "
          "nachweisbar ab | zum Vergleich: unabhängige Paare |")
        w("|---|--:|--:|--:|--:|--:|")
        for z in kalt:
            b = z["b_band_jahr"]
            se = None if b is None else (b[1] - b[0]) / (2 * 1.959964)
            mde = mde_from_band(b)
            naiv = (MDE_FAKTOR * (0.25 / z["b_n"]) ** 0.5
                    if z["b_n"] else None)
            w(f"| {z['name']} | {z['b_n']} | {_fmt(z['b_auc'])} | "
              f"{_fmt(se)} | {_signed(mde)} | {_signed(naiv)} |")
        w("")
        w("Der Standardfehler kommt aus dem **Jahres-Bootstrap**, nicht "
          "aus der Paarzahl: `sqrt(0,25/n)` unterstellt unabhängige "
          "Paare, und B-Paare desselben Jahres teilen sich das Wetter. "
          "Die letzte Spalte zeigt, was die Vernachlässigung kostet — "
          "sie ist die schönere und die falsche Zahl.\n")
        w("Gelesen wird es so: Ein Auslösereffekt, der die B-AUC um "
          "mindestens den Betrag in der vorletzten Spalte über 0,50 "
          "hebt, wäre hier mit 80 % Wahrscheinlichkeit aufgefallen "
          "(zweiseitig, α = 0,05). Ein kleinerer nicht. Die "
          "Feldbeobachtung zur kälteinduzierten Fruktifikation bleibt "
          "damit eine **offene** Frage, keine widerlegte.\n")

    w("\n## Evidenzstufen nach N1\n")
    w("**Die alte Regel ist ersetzt, und zwar nach dem Blick auf die "
      "Zahlen.** Das wird hier hingeschrieben, statt es zu verschweigen. "
      "Sie machte den Abschlag `A − B < 0,05` zur Bedingung für "
      "„belegt\u201c — während derselbe Auftrag an anderer Stelle sagt, "
      "dass B strukturell kleiner sein MUSS. Die Latte bestrafte also "
      "genau den erwarteten Effekt.\n")
    w("Vertretbar ist der Austausch, weil er kein Ergebnis umdeutet, "
      "sondern ein Kriterium ersetzt, das die falsche Größe gemessen "
      "hat — und weil er die Anforderungen eher **verschärft**: Die "
      "Referenz-Bedingung verlangt seit N2 zusätzlich einen "
      "Vertrauensbereich ohne die Null.\n")
    w("| Bedingung für „belegt\u201c | Schwelle |")
    w("|---|---|")
    w("| Jahres-Bootstrap von B | schließt 0,50 aus |")
    w("| Differenz zur artgematchten Referenz | > 0, Vertrauensbereich "
      "ohne die Null |")
    w(f"| Funde in Design B | ≥ {MIN_FINDS_B} |")
    w("| Kontrollen (Placebo B, Spiegel A) | innerhalb 2 SE |")
    w("")
    w(f"Die beiden Bänder entscheiden über ihren **p-Wert** und nicht "
      f"über ihre Kante: Anteil der {BOOTSTRAP_ROUNDS_B} Züge auf der "
      "falschen Seite, Grenze 0,025. Eine Kante ist der 50. von 2000 "
      "Zügen und rauscht; der Anteil tut es nicht. Wo ein p dicht an "
      "0,025 liegt, steht das Urteil auf der Kippe, und dann soll man "
      "das sehen.\n")
    w("| Art | alt | **neu** | Bootstrap (p) | Referenz (p) | Funde | "
      "Kontrollen | Abschlag A−B |")
    w("|---|---|---|:-:|:-:|:-:|:-:|--:|")
    haken = lambda ok, wert: (
        ("✓ " if ok else "✗ ") + wert if wert else ("✓" if ok else "✗"))
    for z in zeilen:
        stufe, bed = evidenzstufe(z)
        d = (None if z["a_auc"] is None or z["b_auc"] is None
             else z["a_auc"] - z["b_auc"])
        alt_stufe = STUFE_ALT.get(z["name"], "—")
        marke = "**" if stufe != alt_stufe else ""
        w(f"| {z['name']} | {alt_stufe} | {marke}{stufe}{marke} | "
          f"{haken(bed['bootstrap'], _pwert(z['b_band_jahr']))} | "
          f"{haken(bed['referenz'], _pwert(z.get('ref_band')))} | "
          f"{haken(bed['funde'], str(z['b_n']))} | "
          f"{haken(bed['kontrollen'], '')} | {_signed(d)} |")
    w("")
    w("Der Abschlag steht weiter in der Tabelle — als Auskunft darüber, "
      "wieviel Kalender in der A-Zahl steckt. Er ist nur kein Tor mehr.\n")

    w("\n## Grenzen\n")
    w("Beide Designs messen an GBIF, in Deutschland, auf den "
      "Anpassjahren. Design B ersetzt Design A nicht — was hier steht, "
      "ordnet ein, welche Zahl wieviel Kalender enthält.\n")
    w("Und Design B hat seine eigene Grenze, die oben schon steht: "
      "„üblich\u201c schließt die guten Jahre ein, weil Presence-only "
      "Abwesenheit nicht kennt.")
    return "\n".join(aus) + "\n"


# --- H1: schmalere Temperaturglocke ----------------------------------------
#
# Registriert in `docs/pilzampel-h1-registrierung.md`, VOR diesem Lauf.
# Was dort nicht steht, entscheidet hier nichts. Die Konstanten unten sind
# die Registrierung in Codeform; wer eine davon nach dem Lauf anfasst,
# hebt die Registrierung auf.

H1_SIGMA_ALT = 5.0        # der Amtsinhaber, gesetzt und nie gemessen
H1_SIGMA_NEU = 3.25       # extern: Nachrechnung der Bielefelder Tagesdaten
H1_SIGMA_GEGEN = 8.0      # Umkehrprobe — eine BREITERE Glocke

H1_MIN_GAIN = 0.02        # Standardlatte des Fahrplans
H1_MIN_JAHR_ANTEIL = 0.70
H1_MIN_JAHR_FUNDE = 10    # duennere Jahre tragen kein Vorzeichen

# Die ausgelieferten Klassen. **Nur sie entscheiden** — und beide
# zusammen, weil sigma EINE Konstante fuer beide ist.
H1_KLASSEN = {
    "herbst": ["Steinpilz", "Maronenröhrling", "Birkenpilz",
               "Fichtenreizker", "Herbsttrompete"],
    "sommer": ["Pfifferling"],
}


def h1_scorer(optimum, sigma, nur=None):
    """Der Bewerter eines Laufs: ganze Formel, nur Temperatur, nur Regen.

    Die beiden Teilbewerter sind die Zerlegung aus Abschnitt 7 der
    Registrierung. Eine schmalere Glocke verschiebt zwangslaeufig Gewicht
    zur Temperatur; ohne die Zerlegung liesse sich ein Gewinn nicht davon
    unterscheiden, dass die Temperatur bloss lauter geworden ist.
    """
    if nur == "temp":
        # **Der Temperaturzweig kennt kein sigma, und das ist kein
        # Versehen.** Das Mass ist rangbasiert, und die Glocke faellt
        # fuer JEDES sigma > 0 streng monoton im Abstand zum Optimum — B
        # auf der Temperatur allein ist deshalb von der Breite
        # unabhaengig. Die Zerlegung liefert also eine Obergrenze und
        # keinen Vergleich: „so weit kaeme die Temperatur allein". Der
        # Selbsttest rechnet die Unabhaengigkeit nach, damit niemand
        # spaeter eine Differenz sucht, die es nicht geben kann.
        #
        # Abschnitt 7 der Registrierung sprach von „B nur aus dem
        # Temperaturfaktor, JE BREITE". Das war ein Denkfehler;
        # aufgefallen ist er an einer Gegenprobe, die gruen blieb — vor
        # dem ersten gemessenen Wert.
        return lambda regen, temp: av.temperature_factor(temp, optimum,
                                                         H1_SIGMA_ALT)
    if nur == "regen":
        return lambda regen, temp: av.rain_factor(regen)
    return lambda regen, temp: av.ampel_score(regen, temp, optimum, sigma)


def h1_b(samples, optimum, score):
    """Das B-Mass unter einem beliebigen Bewerter."""
    werte = [w for liste in _fractions(samples, optimum, lambda s: 0,
                                       score).values() for w in liste]
    return sum(werte) / len(werte) if werte else None


def h1_paare(samples, optimum, sigma_neu, sigma_alt=H1_SIGMA_ALT, nur=None):
    """Je Fund die beiden Anteile — alte und neue Breite, DERSELBE Fund.

    Das ist die tragende Festlegung des Tests: Gezogen wird einmal, und
    danach wird jeder Fund zweimal bewertet. Zwei Ziehungen machten den
    Unterschied teils zur Stichprobe.
    """
    alt = h1_scorer(optimum, sigma_alt, nur)
    neu = h1_scorer(optimum, sigma_neu, nur)
    jahre = {}
    for s in samples:
        controls = s.get("controls") or []
        if not controls:
            continue
        a = ab.beat_fraction(alt(*s["found"]), [alt(*c) for c in controls])
        n = ab.beat_fraction(neu(*s["found"]), [neu(*c) for c in controls])
        if a is None or n is None:
            continue
        jahre.setdefault(s["year"], []).append((a, n))
    return jahre


def h1_delta(samples, optimum, sigma_neu, sigma_alt=H1_SIGMA_ALT,
             rounds=BOOTSTRAP_ROUNDS_B, seed=42, nur=None):
    """Δ = B(neu) − B(alt), mit Band ueber Fundjahre und Jahresanteil.

    **Gezogen wird die DIFFERENZ, nicht die beiden Werte getrennt.** Sie
    teilen sich jeden einzelnen Fund; getrennt gezogen waere das Band
    weit breiter, als die Frage es hergibt — und der Test damit
    stumpfer, ohne dass es jemand saehe.
    """
    jahre = h1_paare(samples, optimum, sigma_neu, sigma_alt, nur)
    flach = [wert for werte in jahre.values() for wert in werte]
    if not flach:
        return None
    b_alt = sum(a for a, _ in flach) / len(flach)
    b_neu = sum(n for _, n in flach) / len(flach)

    namen = sorted(jahre)
    band = None
    if len(namen) >= 2:
        rng = random.Random(seed)
        zuege = []
        for _ in range(rounds):
            werte = [w for name in rng.choices(namen, k=len(namen))
                     for w in jahre[name]]
            if werte:
                zuege.append(sum(n - a for a, n in werte) / len(werte))
        if zuege:
            band = _band(zuege, 0.0)

    # Der Jahresanteil. Duenne Jahre tragen kein Vorzeichen — ein Jahr
    # mit drei Funden wuerde sonst so viel zaehlen wie eines mit dreihundert.
    gezaehlt = besser = 0
    for name in namen:
        werte = jahre[name]
        if len(werte) < H1_MIN_JAHR_FUNDE:
            continue
        gezaehlt += 1
        if (sum(n - a for a, n in werte) / len(werte)) > 0:
            besser += 1
    return {
        "b_alt": b_alt, "b_neu": b_neu, "delta": b_neu - b_alt,
        "band": band, "n": len(flach),
        "jahre": gezaehlt, "jahre_besser": besser,
        "jahr_anteil": besser / gezaehlt if gezaehlt else None,
    }


def h1_ties(samples, optimum, sigma, eps=1e-6):
    """Wo das Modell aufhoert zu unterscheiden.

    Bei sehr schmaler Glocke laufen Scores weit vom Optimum gegen null,
    und dann traegt der Regen nichts mehr bei. Ein Δ nahe null hiesse
    dann „das Modell unterscheidet nicht mehr" und nicht „kein Effekt" —
    ein Unterschied, den man nur sieht, wenn man ihn vorher zaehlt.

    **Der EXAKTE Gleichstand ist dafuer das falsche Mass**, und das war
    beim Schreiben der Registrierung nicht klar: `exp(-209)` ist nicht
    null, sondern 1e-91, und zwei solche Zahlen sind verschieden. Der
    Selbsttest hat es gezeigt — zwei Tage 47 und 57 K neben dem Optimum,
    beide praktisch tot, und `alle_gleich` blieb bei 0 %. Getragen wird
    die Aussage deshalb von `fund_tot` (jeder Vergleich beidseitig unter
    `eps`); der exakte Gleichstand bleibt als Zahl stehen, damit
    sichtbar ist, dass er nichts traegt.
    """
    score = h1_scorer(optimum, sigma)
    alle_gleich = fund_tot = funde = beide_null = vergleiche = 0
    for s in samples:
        controls = s.get("controls") or []
        if not controls:
            continue
        f = score(*s["found"])
        cs = [score(*c) for c in controls]
        funde += 1
        if all(c == f for c in cs):
            alle_gleich += 1
        if all(f < eps and c < eps for c in cs):
            fund_tot += 1
        for c in cs:
            vergleiche += 1
            if f < eps and c < eps:
                beide_null += 1
    return {
        "alle_gleich": alle_gleich / funde if funde else None,
        "fund_tot": fund_tot / funde if funde else None,
        "beide_null": beide_null / vergleiche if vergleiche else None,
        "funde": funde,
    }


def h1_mean_temp(samples):
    """Mittlere 20-Tage-Temperatur am Fundtag — wem eine schmalere
    Glocke ueberhaupt nuetzen kann."""
    werte = []
    for s in samples:
        temps = [c for c in s["found"][1][:av.TEMP_WINDOW] if c is not None]
        if temps:
            werte.append(sum(temps) / len(temps))
    return statistics.fmean(werte) if werte else None


def h1_panel(samples, von=None, bis=None):
    """Die Jahresscheibe eines Panels."""
    return [s for s in samples
            if (von is None or s["year"] >= von)
            and (bis is None or s["year"] <= bis)]


def h1_urteil(p1, placebo, placebo_n, p2):
    """Die vier Bedingungen aus Abschnitt 5 der Registrierung.

    Rueckgabe: (urteil, bedingungen). „zu dünn" ist KEIN Fehlschlag,
    sondern kein Urteil — sonst entschiede eine fehlende Zahl wie eine
    gemessene.
    """
    if p1 is None or p1["n"] < MIN_FINDS_B:
        return "zu dünn", {}
    bed = {
        "gewinn": p1["delta"] >= H1_MIN_GAIN,
        "band": p1["band"] is not None and p1["band"][2] < P_GRENZE,
        "jahre": (p1["jahr_anteil"] is not None
                  and p1["jahr_anteil"] >= H1_MIN_JAHR_ANTEIL),
        "placebo": (placebo is not None
                    and av.control_clean(placebo, placebo_n)),
    }
    # **P2 kann kippen, aber nicht herstellen.** Ein Band, das die Null
    # ausschliesst und UNTER ihr liegt, heisst: die schmalere Glocke
    # reist nicht. Ein blosses „nicht signifikant" im Ausland reicht
    # nicht zum Durchfallen — die Stichprobe ist dort duenner, und eine
    # duenne Zahl darf keine dicke schlagen.
    reist_nicht = (p2 is not None and p2.get("band") is not None
                   and p2["band"][1] < 0)
    bed["ausland"] = not reist_nicht
    return ("bestanden" if all(bed.values()) else "nicht bestanden"), bed


def run_h1(args):
    """Der registrierte Prueflauf zu H1."""
    if args.api:
        av.OPEN_METEO = args.api.rstrip("/")
    av.DEDUPE = args.dedupe
    av.use_dataset(args.dataset)
    print(f"H1 — Datensatz {av.DATASET}, Entdoppeln "
          f"{'an' if av.DEDUPE else 'aus'}, σ {H1_SIGMA_ALT} gegen "
          f"{H1_SIGMA_NEU} (Gegenprobe {H1_SIGMA_GEGEN})", file=sys.stderr)
    print(f"Registrierung: docs/pilzampel-h1-registrierung.md",
          file=sys.stderr)

    mapping = av.read_species()
    wanted = DESIGN_ARTEN
    if args.only:
        gesucht = {n.strip() for n in args.only.split(",") if n.strip()}
        wanted = [z for z in DESIGN_ARTEN if z[0] in gesucht]

    zeilen = []
    for name, gruppe, optimum in wanted:
        if name not in mapping:
            continue
        sci = mapping[name]
        klasse = next((k for k, arten in H1_KLASSEN.items() if name in arten),
                      None)
        print(f"  {name} ({sci}) — Klasse {klasse or 'nachrichtlich'}",
              file=sys.stderr)

        # **Einmal ziehen je Laendergruppe, dann in Jahresscheiben
        # schneiden.** P1 und P3 sind dieselbe Ziehung; sie zweimal zu
        # holen hiesse, zwei verschiedene Stichproben zu vergleichen.
        roh = {}
        for laender in (("DE",), ("AT", "CH")):
            finds, _ = av.select_finds(sci, args.cache, args.seed, True,
                                       laender)
            if not finds:
                continue
            gezogen = av.collect_pairs_b(name, sci, finds=finds,
                                         cache_dir=args.cache, seed=args.seed,
                                         progress=False, countries=laender)
            if gezogen:
                roh[laender] = gezogen["samples"]

        panels = {
            "P1": h1_panel(roh.get(("DE",), []), von=av.FIT_UNTIL_YEAR + 1),
            "P2": list(roh.get(("AT", "CH"), [])),
            "P3": h1_panel(roh.get(("DE",), []), bis=av.FIT_UNTIL_YEAR),
        }
        eintrag = {"name": name, "gruppe": gruppe, "optimum": optimum,
                   "klasse": klasse, "panel": {}}
        for schluessel, samples in panels.items():
            eintrag["panel"][schluessel] = (
                h1_delta(samples, optimum, H1_SIGMA_NEU, seed=args.seed)
                if samples else None)

        p1 = panels["P1"]
        if p1:
            eintrag["gegenprobe"] = h1_delta(p1, optimum, H1_SIGMA_GEGEN,
                                             seed=args.seed)
            # Zerlegung: zwei Obergrenzen, kein Vergleich — siehe
            # `h1_scorer`. Beide sind von sigma unabhaengig.
            eintrag["b_nur_temp"] = h1_b(
                p1, optimum, h1_scorer(optimum, H1_SIGMA_ALT, "temp"))
            eintrag["b_nur_regen"] = h1_b(
                p1, optimum, h1_scorer(optimum, H1_SIGMA_ALT, "regen"))
            eintrag["ties_alt"] = h1_ties(p1, optimum, H1_SIGMA_ALT)
            eintrag["ties_neu"] = h1_ties(p1, optimum, H1_SIGMA_NEU)
            eintrag["t20"] = h1_mean_temp(p1)
            for marke, sigma in (("alt", H1_SIGMA_ALT), ("neu", H1_SIGMA_NEU)):
                wert, anzahl = av.placebo_b(p1, optimum, sigma)
                eintrag[f"placebo_{marke}"] = wert
                eintrag[f"placebo_{marke}_n"] = anzahl
        eintrag["urteil"], eintrag["bedingungen"] = h1_urteil(
            eintrag["panel"]["P1"], eintrag.get("placebo_neu"),
            eintrag.get("placebo_neu_n") or 0, eintrag["panel"]["P2"])
        zeilen.append(eintrag)
        p1_wert = eintrag["panel"]["P1"]
        print(f"    P1 Δ {_signed(p1_wert['delta']) if p1_wert else '—'}   "
              f"{eintrag['urteil']}", file=sys.stderr)

    bericht = render_h1(zeilen)
    if args.out:
        open(args.out, "w", encoding="utf-8").write(bericht)
        print(f"\n{args.out} geschrieben", file=sys.stderr)
    else:
        print(bericht)


def h1_klassenurteil(zeilen):
    """Alle oder keine — und sigma nur, wenn BEIDE Klassen bestehen.

    Die Regel ist die, an der am 2026-09-13 die Herbst-Holz-Klasse und
    die Kaltklasse gescheitert sind: Ein sauber gemessener Fehlschlag
    eines Mitglieds entscheidet, auch wenn ein anderes glaenzt. „Zu
    dünn" ist kein Fehlschlag, sondern kein Urteil.
    """
    aus = {}
    for klasse, arten in H1_KLASSEN.items():
        urteile = [z["urteil"] for z in zeilen if z["name"] in arten]
        geurteilt = [u for u in urteile if u != "zu dünn"]
        if not geurteilt:
            aus[klasse] = "kein Urteil"
        elif all(u == "bestanden" for u in geurteilt):
            aus[klasse] = "bestanden"
        else:
            aus[klasse] = "nicht bestanden"
    aus["_sigma"] = ("wird geändert"
                     if all(aus.get(k) == "bestanden" for k in H1_KLASSEN)
                     else "bleibt 5,0")
    return aus


def render_h1(zeilen):
    """Der Ergebnisbericht zu H1."""
    import time as _t
    aus = []
    w = aus.append
    band = lambda b: "—" if b is None else f"[{b[0]:+.3f}, {b[1]:+.3f}]"
    haken = lambda ok: "✓" if ok else "✗"
    w("# H1 geprüft: schmalere Temperaturglocke (3,25 K statt 5 K)\n")
    w(f"Stand: {_t.strftime('%Y-%m-%d')} · Erzeugt von "
      "`tool/ampel_diagnose.py --h1` · **Registrierung (vor dem Lauf "
      "geschrieben): `docs/pilzampel-h1-registrierung.md`**\n")
    w(f"Messbasis `{av.DATASET}`, Entdoppeln "
      f"{'an' if av.DEDUPE else 'aus'}, Design B, σ = {H1_SIGMA_ALT} gegen "
      f"σ = {H1_SIGMA_NEU}. Beide Breiten laufen auf **denselben "
      "Funden** — gezogen wird einmal, bewertet zweimal.\n")

    urteile = h1_klassenurteil(zeilen)
    w("\n## Das Urteil\n")
    w("| Klasse | Mitglieder | Ausgang |")
    w("|---|---|---|")
    for klasse, arten in H1_KLASSEN.items():
        dabei = [z for z in zeilen if z["name"] in arten]
        text = ", ".join(f"{z['name']} ({z['urteil']})" for z in dabei) or "—"
        w(f"| `{klasse}` | {text} | **{urteile.get(klasse)}** |")
    w("")
    w(f"**σ {urteile['_sigma']}.** Die Breite ist EINE Konstante für beide "
      "ausgelieferten Klassen; geändert wird sie nur, wenn beide "
      "bestehen (Registrierung, Abschnitt 1). Ein σ je Klasse wäre ein "
      "neuer Freiheitsgrad und bräuchte eine eigene Registrierung.\n")
    w("**An der ausgelieferten Ampel ist nichts geändert.**\n")

    w("\n## Die Bedingung, Punkt für Punkt\n")
    w(f"Latte: Δ ≥ +{H1_MIN_GAIN:.3f} · Band ohne die Null (p < "
      f"{P_GRENZE}) · ≥ {H1_MIN_JAHR_ANTEIL:.0%} der Fundjahre besser · "
      "Placebo innerhalb 2 SE · Ausland widerspricht nicht.\n")
    w("| Art | Klasse | Δ auf P1 | 95 % | p | Jahre besser | Placebo neu | "
      "Ausland | **Ausgang** |")
    w("|---|---|--:|---|--:|--:|--:|:-:|---|")
    for z in zeilen:
        p1 = z["panel"]["P1"]
        bed = z["bedingungen"]
        jahre = ("—" if not p1 or p1["jahr_anteil"] is None
                 else f"{p1['jahre_besser']}/{p1['jahre']}")
        w(f"| {z['name']} | {z['klasse'] or '—'} | "
          f"{_signed(p1['delta']) if p1 else '—'} | "
          f"{band(p1['band']) if p1 else '—'} | "
          f"{_pwert(p1['band']) if p1 else '—'} | {jahre} | "
          f"{_fmt(z.get('placebo_neu'))} | "
          f"{haken(bed['ausland']) if bed else '—'} | "
          f"**{z['urteil']}** |")
    w("")
    w("Arten ohne Klasse laufen **nachrichtlich** mit und entscheiden "
      "nichts: Ihre Klassen sind nicht ausgeliefert, und nach Phase 1.5 "
      "steht für alle fünf „keine Aussage“.\n")

    w("\n## Die drei Panels\n")
    w("P1 = DE ab 2019 (entscheidend) · P2 = AT + CH, alle Jahre "
      "(Reisetest, bindend als Ausschluss) · P3 = DE bis 2018 "
      "(nachrichtlich — dort wurde das Sommer-Optimum angepasst).\n")
    w("| Art | P1 Δ | P1 n | P2 Δ | P2 n | P3 Δ | P3 n |")
    w("|---|--:|--:|--:|--:|--:|--:|")
    for z in zeilen:
        teile = []
        for schluessel in ("P1", "P2", "P3"):
            d = z["panel"].get(schluessel)
            teile.append(_signed(d["delta"]) if d else "—")
            teile.append(str(d["n"]) if d else "—")
        w(f"| {z['name']} | " + " | ".join(teile) + " |")

    w("\n## Gegenprobe: eine BREITERE Glocke\n")
    w(f"Dieselbe Rechnung mit σ = {H1_SIGMA_GEGEN} K auf P1. Ergibt auch "
      "sie einen Gewinn über der Latte, misst das Verfahren nicht die "
      "Breite, sondern irgendetwas anderes. Diese Spalte entscheidet "
      "nichts.\n")
    w("| Art | Δ bei 3,25 K | Δ bei 8,0 K | beide über der Latte? |")
    w("|---|--:|--:|:-:|")
    for z in zeilen:
        p1, gegen = z["panel"]["P1"], z.get("gegenprobe")
        beide = (p1 and gegen and p1["delta"] >= H1_MIN_GAIN
                 and gegen["delta"] >= H1_MIN_GAIN)
        w(f"| {z['name']} | {_signed(p1['delta']) if p1 else '—'} | "
          f"{_signed(gegen['delta']) if gegen else '—'} | "
          f"{'**ja ⚠**' if beide else 'nein'} |")

    w("\n## Diagnosen (entscheiden nichts)\n")
    w("Vorab festgelegt, damit sie hinterher nicht als Erklärung "
      "erfunden wirken.\n")
    w("| Art | T̄₂₀ am Fundtag | Optimum | Abstand | B nur Temperatur "
      "| B nur Regen | tote Funde alt → neu | exakt gleich alt → neu |")
    w("|---|--:|--:|--:|--:|--:|--:|--:|")
    for z in zeilen:
        t20 = z.get("t20")
        ta, tn = z.get("ties_alt"), z.get("ties_neu")
        quote = lambda a, b, key: (
            "—" if not a or not b or a[key] is None or b[key] is None
            else f"{a[key]:.1%} → {b[key]:.1%}")
        w(f"| {z['name']} | {_fmt(t20, 1)} | {z['optimum']:.1f} | "
          f"{_fmt(abs(t20 - z['optimum']), 1) if t20 is not None else '—'} | "
          f"{_fmt(z.get('b_nur_temp'))} | "
          f"{_fmt(z.get('b_nur_regen'))} | {quote(ta, tn, 'fund_tot')} | "
          f"{quote(ta, tn, 'alle_gleich')} |")
    w("")
    w("**Die vorletzte Spalte ist die wichtigste dieser Tabelle.** Sie "
      "zählt Funde, bei denen jeder Vergleich beidseitig unter 10⁻⁶ "
      "liegt — dort rechnet das Modell noch und sagt nichts mehr. "
      "Steigt der Anteil deutlich, hat eine schmalere Glocke nicht "
      "besser getrennt, sondern aufgehört zu trennen; dann heißt ein Δ "
      "nahe null „die Messung kann die Frage hier nicht beantworten“ "
      "und nicht „kein Effekt“.\n")
    w("Die letzte Spalte zählt **exakte** Gleichstände und steht nur da, "
      "damit sichtbar bleibt, dass sie nichts trägt: `exp(−209)` ist "
      "1e−91 und nicht null, zwei tote Tage gelten dem Rechner also als "
      "verschieden. Beim Schreiben der Registrierung war das nicht klar "
      "— der Selbsttest hat es gezeigt, bevor eine einzige Zahl gemessen "
      "war.\n")

    w("\n## Grenzen\n")
    w("Design B misst gegen dasselbe Datum anderer Jahre am selben Ort, "
      "und „üblich“ schließt die guten Jahre ein — das dämpft beide "
      "Breiten gleich und ist für eine Differenz unkritisch, für die "
      "absoluten Werte nicht.\n")
    w("Und geprüft ist eine **Form**, keine Biologie: Dass eine Glocke "
      "mit σ = 3,25 besser trennt, hieße nicht, dass Steinpilze bei "
      "9,75 °C auf ein Drittel fallen. Es hieße, dass die Rangfolge der "
      "Tage damit besser stimmt.")
    return "\n".join(aus) + "\n"


# --- N5, zweiter Teil: das bedingte Logit ----------------------------------
#
# **Getrennt vom Test, und zwar mit Absicht auch im Aufruf.** N5 sagt:
# „Information fuer spaeter und NICHT der geprueft Wert. Wer daraus den
# Testwert macht, verwandelt eine externe Zahl in eine angepasste — und
# deren Instabilitaet war der Befund aus Phase 0.4." Ein eigener Schalter
# und eine eigene Ausgabedatei machen die Verwechslung unmoeglich; stuende
# es im H1-Bericht, laege die angepasste Breite neben der geprueften.
#
# Gerechnet wird auf den **Anpassjahren DE <= 2018** — nicht auf P1 und
# nicht auf P2. Die Pruefachsen werden davon nicht angefasst.

# Unter diesem Regenfaktor wird `log F` nicht mehr gerechnet, sondern
# abgeschnitten. Ein Fenster ohne einen Tropfen in 26 Tagen ergaebe
# log(0); die Zahl der abgeschnittenen Faelle gehoert in den Bericht,
# weil das Modell dort nicht mehr das rechnet, was es behauptet.
LOGIT_REGEN_BODEN = 1e-3


def logit_features(regen, temp):
    """`[log F, T̄₂₀, T̄₂₀²]` — die Merkmale aus N5.

    Sie haengen direkt an der Formel der Ampel: `log(F · exp(−((T−opt)/σ)²))`
    ist `log F − T²/σ² + 2·opt·T/σ² − opt²/σ²`, und der letzte Summand
    ist je Stratum konstant und faellt heraus.
    """
    f = av.rain_factor(regen)
    abgeschnitten = f < LOGIT_REGEN_BODEN
    werte = [c for c in temp[:av.TEMP_WINDOW] if c is not None]
    if not werte:
        return None, abgeschnitten
    mittel = sum(werte) / len(werte)
    return [math.log(max(f, LOGIT_REGEN_BODEN)), mittel, mittel * mittel], \
        abgeschnitten


def logit_strata(samples):
    """Aus B-Funden die Strata: ein Fundtag gegen seine Kontrolltage."""
    strata = []
    abgeschnitten = gesamt = 0
    for s in samples:
        reihen, fehlt = [], False
        for regen, temp in [s["found"]] + list(s.get("controls") or []):
            werte, boden = logit_features(regen, temp)
            gesamt += 1
            abgeschnitten += 1 if boden else 0
            if werte is None:
                fehlt = True
                break
            reihen.append(werte)
        if fehlt or len(reihen) < 2:
            continue
        strata.append((reihen[0], reihen[1:]))
    return strata, abgeschnitten, gesamt


def run_logit(args):
    """N5, zweiter Teil — Optimum und Breite MIT Standardfehler."""
    if args.api:
        av.OPEN_METEO = args.api.rstrip("/")
    av.DEDUPE = args.dedupe
    av.use_dataset(args.dataset)
    print(f"Bedingtes Logit auf den Anpassjahren DE ≤ {av.FIT_UNTIL_YEAR} — "
          "Information, kein Prüfwert", file=sys.stderr)

    mapping = av.read_species()
    wanted = DESIGN_ARTEN
    if args.only:
        gesucht = {n.strip() for n in args.only.split(",") if n.strip()}
        wanted = [z for z in DESIGN_ARTEN if z[0] in gesucht]

    zeilen = []
    for name, gruppe, optimum in wanted:
        if name not in mapping:
            continue
        sci = mapping[name]
        print(f"  {name}", file=sys.stderr)
        finds, _ = av.select_finds(sci, args.cache, args.seed, True, ("DE",))
        if not finds:
            continue
        gezogen = av.collect_pairs_b(name, sci, finds=finds,
                                     cache_dir=args.cache, seed=args.seed,
                                     progress=False)
        if not gezogen:
            continue
        samples = fit_years_only(gezogen["samples"])
        strata, abgeschnitten, gesamt = logit_strata(samples)
        if len(strata) < 50:
            zeilen.append({"name": name, "gruppe": gruppe,
                           "gesetzt": optimum, "fit": None,
                           "strata": len(strata)})
            continue
        fit = ampel_logit.fit_conditional_logit(strata)
        glocke = ampel_logit.bell_from_beta(fit["beta"], fit["kovarianz"])
        zeilen.append({
            "name": name, "gruppe": gruppe, "gesetzt": optimum,
            "fit": fit, "glocke": glocke, "strata": len(strata),
            "abgeschnitten": abgeschnitten / gesamt if gesamt else None,
        })
        print(f"    Optimum {_fmt(glocke.get('optimum'), 2)} ± "
              f"{_fmt(glocke.get('se_optimum'), 2)}   Breite "
              f"{_fmt(glocke.get('breite'), 2)} ± "
              f"{_fmt(glocke.get('se_breite'), 2)}", file=sys.stderr)

    bericht = render_logit(zeilen)
    if args.out:
        open(args.out, "w", encoding="utf-8").write(bericht)
        print(f"\n{args.out} geschrieben", file=sys.stderr)
    else:
        print(bericht)


def render_logit(zeilen):
    """Der Bericht zum Logit — ohne ein einziges Urteil."""
    import time as _t
    aus = []
    w = aus.append
    w("# Optimum und Breite mit Standardfehler (bedingtes Logit)\n")
    w(f"Stand: {_t.strftime('%Y-%m-%d')} · Erzeugt von "
      "`tool/ampel_diagnose.py --logit` · Auftrag: "
      "`docs/pilzampel-auftrag-2-nachtrag-1.md`, N5, letzter Punkt\n")
    w("> **Hier wird nichts geprüft.** Diese Seite enthält keine Latte, "
      "keine Bedingung und kein Urteil. Sie sagt, wie genau die Daten "
      "Optimum und Breite überhaupt bestimmen — und das ist etwas "
      "anderes als die Frage, ob eine **extern** gesetzte Breite besser "
      "trennt. Diese Frage beantwortet "
      "`docs/pilzampel-h1-registrierung.md`.\n")
    w("> Wer eine Zahl von hier zum Prüfwert macht, verwandelt eine "
      "externe Größe in eine angepasste. Deren Instabilität war der "
      "Befund aus Phase 0.4: Optima wanderten beim Wechsel des "
      "Instruments um bis zu 3 K.\n")
    w(f"Gerechnet auf den **Anpassjahren DE ≤ {av.FIT_UNTIL_YEAR}**, auf "
      "den Paaren aus Design B (ein Fundtag gegen fünf Kontrolljahre). "
      "Die Prüfachsen P1 und P2 sind davon unberührt.\n")
    w(f"Messbasis `{av.DATASET}`, Entdoppeln "
      f"{'an' if av.DEDUPE else 'aus'}.\n")

    w("\n## Was das Modell ist\n")
    w("Bedingtes Logit mit den Merkmalen `[log F, T̄₂₀, T̄₂₀²]`, ohne "
      "Achsenabschnitt — Ort, Jahr und Jahreszeit kürzen sich über das "
      "Stratum heraus. Es hängt direkt an der Formel der Ampel:\n")
    w("    log(F · exp(−((T−opt)/σ)²)) = log F − T²/σ² + 2·opt·T/σ² − opt²/σ²\n")
    w("Der letzte Summand ist je Stratum konstant und fällt heraus. Also "
      "`Optimum = −b_T / (2 b_T²)` und `Breite = sqrt(b_logF / −b_T²)`.\n")
    w("**Die Breite ist relativ zum Gewicht der Feuchte.** Sie ist nur "
      "dann in Kelvin lesbar wie das σ der Ampel, wenn `b_logF` bei 1 "
      "liegt. Steht dort etwas anderes, sagt das Modell auch etwas über "
      "die Gewichtung von Feuchte gegen Temperatur — deshalb steht die "
      "Zahl in der Tabelle und nicht im Kleingedruckten.\n")

    w("\n## Gemessen\n")
    w("| Art | Gruppe | Strata | Optimum | ± | ausgeliefert | Breite | ± | "
      "b_logF | ± | konvergiert |")
    w("|---|---|--:|--:|--:|--:|--:|--:|--:|--:|:-:|")
    for z in zeilen:
        if not z.get("fit"):
            w(f"| {z['name']} | {z['gruppe']} | {z['strata']} | — | — | "
              f"{z['gesetzt']:.1f} | — | — | — | — | — |")
            continue
        g = z["glocke"]
        w(f"| {z['name']} | {z['gruppe']} | {z['strata']} | "
          f"{_fmt(g.get('optimum'), 2)} | {_fmt(g.get('se_optimum'), 2)} | "
          f"{z['gesetzt']:.1f} | {_fmt(g.get('breite'), 2)} | "
          f"{_fmt(g.get('se_breite'), 2)} | {_fmt(g.get('b_logf'), 2)} | "
          f"{_fmt(g.get('se_b_logf'), 2)} | "
          f"{'✓' if z['fit']['konvergiert'] else '✗'} |")
    w("")
    w(f"Ein Strich in der Breite heißt, dass es keine gibt — entweder ist "
      "`b_T²` nicht negativ (dann ist die Parabel nach oben offen und "
      "beschreibt keine Glocke) oder `b_logF` nicht positiv (dann hat "
      "die Wurzel kein Argument). Beides ist ein Ergebnis und keine "
      "Panne; der Grund steht je Art unten.\n")
    gruende = [(z["name"], z["glocke"]["grund"]) for z in zeilen
               if z.get("glocke") and z["glocke"].get("grund")]
    if gruende:
        for name, grund in gruende:
            w(f"- **{name}**: {grund}")
        w("")

    w("\n## Wieviel Regen abgeschnitten wurde\n")
    w(f"`log F` braucht ein F über null. Ein Fenster ohne einen Tropfen "
      f"in {av.RAIN_WINDOW} Tagen wird deshalb auf "
      f"{LOGIT_REGEN_BODEN} gesetzt. **Wo dieser Anteil groß ist, "
      "rechnet das Modell nicht mehr das, was es behauptet** — und die "
      "Breite dieser Art ist dann mit Vorsicht zu lesen.\n")
    w("| Art | abgeschnittene Tage |")
    w("|---|--:|")
    for z in zeilen:
        anteil = z.get("abgeschnitten")
        w(f"| {z['name']} | {'—' if anteil is None else f'{anteil:.2%}'} |")

    w("\n## Wie das zu lesen ist\n")
    w("**Der Standardfehler ist der Zweck dieser Seite, nicht die "
      "Punktschätzung.** Das Gitter aus `--fit` liefert einen Punkt in "
      "0,5-K-Schritten und sagt nichts darüber, wie flach die "
      "Likelihood um ihn herum liegt. Eine Breite von 4,0 ± 0,3 und eine "
      "von 4,0 ± 2,5 sehen in einer Tabelle gleich aus und bedeuten "
      "Gegenteiliges.\n")
    w("Und die Delta-Methode hat ihre eigene Grenze: Sie unterstellt, "
      "dass die Umformung im Bereich eines Standardfehlers ungefähr "
      "gerade ist. Bei einer flachen Likelihood — `b_T²` nahe null — ist "
      "sie das nicht, und der Fehler fällt dann eher zu klein aus. "
      "Deshalb hilft im Zweifel der Blick auf `b_T²` selbst.")
    return "\n".join(aus) + "\n"

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--designs", action="store_true",
                        help="Phase 1.5: Design A und B "
                             "nebeneinander")
    parser.add_argument("--logit", action="store_true",
                        help="N5: Optimum und Breite mit Standardfehler "
                             "— Information, kein Prüfwert")
    parser.add_argument("--h1", action="store_true",
                        help="der registrierte Prüflauf zu H1 "
                             "(docs/pilzampel-h1-registrierung.md)")
    parser.add_argument("--dataset", default="vorgabe")
    parser.add_argument("--dedupe", action="store_true")
    parser.add_argument("--api", default=None)
    parser.add_argument("--cache", default=None)
    parser.add_argument("--out", default=None)
    parser.add_argument("--only", default=None)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()
    if args.self_test:
        self_test()
        raise SystemExit(0)
    if args.designs:
        run_designs(args)
        raise SystemExit(0)
    if args.h1:
        run_h1(args)
        raise SystemExit(0)
    if args.logit:
        run_logit(args)
        raise SystemExit(0)
    if not args.all:
        parser.print_help()
        raise SystemExit(0)
    run(args)
