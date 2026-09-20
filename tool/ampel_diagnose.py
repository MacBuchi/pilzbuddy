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
import bisect
import importlib.util
import inspect
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

_grafik_spec = importlib.util.spec_from_file_location(
    "ampel_grafik", os.path.join(_HERE, "ampel_grafik.py"))
ag = importlib.util.module_from_spec(_grafik_spec)
_grafik_spec.loader.exec_module(ag)

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
    strata, jahre, abg, gesamt = logit_strata([b_sample,
                                               dict(b_sample, controls=[])])
    assert len(strata) == 1 and len(strata[0][1]) == 2, strata
    assert abg == 0 and gesamt == 4, (abg, gesamt)
    # **Die Gruppenmarke ist das Fundjahr und laeuft parallel zu den
    # Strata.** Geriete sie aus dem Takt, clusterte der Sandwich nach
    # etwas anderem als dem, was drueber steht.
    assert jahre == [2010], jahre
    zwei = [b_sample, dict(b_sample, year=2011)]
    assert logit_strata(zwei)[1] == [2010, 2011]
    # **Und die Marke muss auch wirklich uebergeben werden.** Das laesst
    # sich ohne echte Daten nur an der Quelle pruefen — `run_logit`
    # braucht einen Bestand und ein Wetterarchiv. Eine Gegenprobe hat
    # genau hier gruen gelacht: Der Sandwich war gerechnet, nur nie
    # angefordert, und im Bericht stand dann ueberall ein Strich.
    quelle = inspect.getsource(run_logit)
    assert "cluster=jahre" in quelle, \
        "run_logit muss das Fundjahr als Gruppe uebergeben"
    assert "kovarianz_cluster" in quelle, \
        "run_logit muss die robuste Kovarianz auch auswerten"
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

    # --- Vorpruefung zu H5: die Zerlegung auf P3 -----------------------
    #
    # Die drei Bewerter muessen wirklich verschiedene Dinge sehen. Probe:
    # gleicher Regen, verschiedene Temperatur — dann darf NUR der
    # Temperaturzweig etwas anderes als 0,5 sagen.
    gleich_regen = [s for jahr in range(2008, 2018)
                    for s in h1_probe(jahr, 2.0, 13.0, 2.0, 25.0, 5)]
    werte = {v: h1_b(gleich_regen, 13.0, zerlegung_scorer(13.0, v))
             for v in ZERLEGUNG_VARIANTEN}
    assert werte["nur Regen"] == 0.5, werte
    assert werte["nur Temperatur"] == 1.0 and werte["voll"] == 1.0, werte
    # Und umgekehrt: gleiche Temperatur, verschiedener Regen.
    gleich_temp = [s for jahr in range(2008, 2018)
                   for s in h1_probe(jahr, 3.0, 13.0, 1.0, 13.0, 5)]
    werte = {v: h1_b(gleich_temp, 13.0, zerlegung_scorer(13.0, v))
             for v in ZERLEGUNG_VARIANTEN}
    assert werte["nur Temperatur"] == 0.5, werte
    assert werte["nur Regen"] == 1.0 and werte["voll"] == 1.0, werte
    # Der Referenz-Bootstrap muss den Bewerter durchreichen. Ohne ihn
    # rechnete er die volle Formel, und Bedingung 3 pruefte etwas
    # anderes, als in der Registrierung steht.
    ref_kunst = [s for jahr in range(2008, 2018)
                 for s in h1_probe(jahr, 1.0, 13.0, 3.0, 13.0, 5)]
    nur_r = bootstrap_ref_diff(gleich_temp, ref_kunst, 13.0, rounds=100,
                               score=zerlegung_scorer(13.0, "nur Regen"))
    assert nur_r is not None and nur_r[0] > 0, nur_r
    nur_t = bootstrap_ref_diff(gleich_temp, ref_kunst, 13.0, rounds=100,
                               score=zerlegung_scorer(13.0, "nur Temperatur"))
    assert nur_t is not None and abs(nur_t[0]) < 1e-9 \
        and abs(nur_t[1]) < 1e-9, nur_t

    # --- Das Urteil der Vorpruefung, Bedingung fuer Bedingung ---------
    def z_zeile(name, voll, regen, temp, d_voll, d_regen, p_regen=0.001):
        return {"name": name, "ausgeliefert": True,
                "b": {"voll": voll, "nur Regen": regen,
                      "nur Temperatur": temp},
                "delta": {"voll": d_voll, "nur Regen": d_regen,
                          "nur Temperatur": 0.0},
                "band": {"voll": (0.01, 0.09, 0.001),
                         "nur Regen": (0.01, 0.09, p_regen),
                         "nur Temperatur": None}}

    def z_alle(**anders):
        zeilen = []
        for name in ZERLEGUNG_AUSGELIEFERT:
            felder = dict(voll=0.64, regen=0.645, temp=0.58,
                          d_voll=0.06, d_regen=0.06)
            felder.update(anders.get(name, {}))
            zeilen.append(z_zeile(name, **felder))
        return zeilen

    assert len(ZERLEGUNG_AUSGELIEFERT) == 6, ZERLEGUNG_AUSGELIEFERT
    gut = zerlegung_urteil(z_alle())
    assert gut["urteil"] == "H5 wird registriert", gut
    assert gut["arten"] == 6 and gut["n_reist"] == 6

    # Bedingung 1: bei zwei Arten traegt die Temperatur mehr.
    kippt = {n: {"temp": 0.70} for n in ZERLEGUNG_AUSGELIEFERT[:2]}
    schlecht = zerlegung_urteil(z_alle(**kippt))
    assert schlecht["bedingungen"]["reist"] is False, schlecht
    assert schlecht["urteil"] == "H5 wird NICHT registriert"
    # Genau eine Art darf kippen — fuenf von sechs reichen.
    assert zerlegung_urteil(z_alle(**{ZERLEGUNG_AUSGELIEFERT[0]:
                                      {"temp": 0.70}}))["bedingungen"][
        "reist"] is True

    # Bedingung 2: die Glocke traegt doch etwas bei.
    traegt = {n: {"voll": 0.68, "regen": 0.645}
              for n in ZERLEGUNG_AUSGELIEFERT[:2]}
    assert zerlegung_urteil(z_alle(**traegt))["bedingungen"][
        "glocke_traegt_nichts"] is False
    # Die Grenze wird scharf gelesen: genau +0,020 traegt schon.
    knapp = {n: {"voll": 0.665, "regen": 0.645}
             for n in ZERLEGUNG_AUSGELIEFERT[:2]}
    assert zerlegung_urteil(z_alle(**knapp))["bedingungen"][
        "glocke_traegt_nichts"] is False

    # Bedingung 3, erste Haelfte: das Band schliesst die Null ein.
    wackelt = {n: {"p_regen": 0.30} for n in ZERLEGUNG_AUSGELIEFERT[:2]}
    assert zerlegung_urteil(z_alle(**wackelt))["bedingungen"][
        "abstand_haelt"] is False
    # **Zweite Haelfte — die Falle, auf die es ankommt.** Der Abstand
    # darf nicht schrumpfen, auch wenn jedes einzelne Band sauber ist:
    # Ein Regen-Score, der Art UND Referenz gleichermassen hebt, laesst
    # die Baender stehen und den Abstand fallen.
    schrumpft = {n: {"d_regen": 0.01, "d_voll": 0.06}
                 for n in ZERLEGUNG_AUSGELIEFERT}
    geschrumpft = zerlegung_urteil(z_alle(**schrumpft))
    assert geschrumpft["n_abstand"] == 6, geschrumpft
    assert geschrumpft["median_ok"] is False, geschrumpft
    assert geschrumpft["bedingungen"]["abstand_haelt"] is False
    assert geschrumpft["urteil"] == "H5 wird NICHT registriert"
    # Ein Verlust von genau 0,020 ist noch erlaubt, mehr nicht.
    assert zerlegung_urteil(z_alle(**{n: {"d_regen": 0.04, "d_voll": 0.06}
                                      for n in ZERLEGUNG_AUSGELIEFERT}))[
        "median_ok"] is True
    assert zerlegung_urteil(z_alle(**{n: {"d_regen": 0.039, "d_voll": 0.06}
                                      for n in ZERLEGUNG_AUSGELIEFERT}))[
        "median_ok"] is False

    # Nachrichtliche Arten entscheiden nichts.
    mit_gast = z_alle() + [dict(z_zeile("Judasohr", 0.50, 0.62, 0.46,
                                        0.0, 0.0, 0.9),
                                ausgeliefert=False)]
    assert zerlegung_urteil(mit_gast)["arten"] == 6
    assert zerlegung_urteil(mit_gast)["urteil"] == "H5 wird registriert"

    # Und der Bericht muss sich bauen lassen, bevor gemessen wird.
    roh = [dict(z, gruppe="herbst", optimum=13.0, n=900, ref_n=1500,
                zellen=600,
                ref_b={"voll": 0.58, "nur Regen": 0.585,
                       "nur Temperatur": 0.55})
           for z in z_alle()]
    text = render_zerlegung(roh)
    assert "H5 wird registriert" in text and "Die Zerlegung je Art" in text

    # --- Der Riegel vor der Jahresscheibe -----------------------------
    #
    # **Eine verrutschte Ziffer darf keine Pruefachse kosten.** `--jahre`
    # ist eine Zeile im Aufruf; ohne Riegel machte `2006-2020` aus einer
    # kostenlosen Diagnose einen Lauf auf DE ab 2019, und nichts waere
    # rot geworden.
    class _Args:
        def __init__(self, jahre=None):
            self.jahre = jahre
    assert zerlegung_scheibe(_Args()) == (None, av.FIT_UNTIL_YEAR)
    assert zerlegung_scheibe(_Args("2006-2012")) == (2006, 2012)
    assert zerlegung_scheibe(_Args(f"2013-{av.FIT_UNTIL_YEAR}")) \
        == (2013, av.FIT_UNTIL_YEAR)
    for schlecht in (f"2006-{av.FIT_UNTIL_YEAR + 1}", "2006-2025",
                     "2012-2006", "2006", "zwanzig-zwölf", "2006-2012-2018"):
        try:
            zerlegung_scheibe(_Args(schlecht))
        except SystemExit:
            pass
        else:
            raise AssertionError(f"--jahre {schlecht} muss abbrechen")

    # Die Registrierung in Codeform — wer eine dieser Zahlen nach dem
    # Lauf anfasst, hebt sie auf.
    assert (H1_SIGMA_ALT, H1_SIGMA_NEU, H1_SIGMA_GEGEN) == (5.0, 3.25, 8.0)
    assert (H1_MIN_GAIN, H1_MIN_JAHR_ANTEIL) == (0.02, 0.70)
    assert (Z_MIN_ARTEN, Z_GLOCKE_BEITRAG, Z_ABSTAND_VERLUST) == \
        (5, 0.020, 0.020)
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

    # --- A aus Auftrag 3: die Schwellen aus Design B -------------------
    #
    # Jede Behauptung hier ist einmal absichtlich gebrochen worden,
    # bevor sie stehen blieb.

    # **Der Kalendertag muss aus der Ziehung kommen, nicht aus einer
    # Nachstellung.** Ohne diese Zeile in `collect_pairs_b` liefe der
    # Monatsteil auf einer erfundenen Spalte, und der Bericht saehe
    # genauso aus.
    quelle_b = inspect.getsource(av.collect_pairs_b)
    assert '"control_days": control_days' in quelle_b, \
        "collect_pairs_b fuehrt die Kontrolltage nicht mit"
    assert '"found_day": found_day' in quelle_b

    # Der Monat eines Kontrolltags — auch wenn die Streuung aus dem Jahr
    # faellt. Ein geklemmter Index gaebe einen stillen Dezember-Ueberschuss.
    assert schwellen_monat(2015, 0) == 1
    assert schwellen_monat(2015, 364) == 12
    assert schwellen_monat(2015, 365) == 1      # ins Folgejahr gerutscht
    assert schwellen_monat(2015, -1) == 12      # ins Vorjahr gerutscht
    assert schwellen_monat(2016, 59) == 2       # Schaltjahr: 29. Februar
    assert schwellen_monat(2015, 59) == 3       # kein Schaltjahr

    # Ein Fund zaehlt EINMAL, egal wieviele Kontrolljahre er hat.
    def _probe(jahr, tag, controls):
        # Regen gesaettigt (26 x 4 mm > 87 mm), damit der Score allein an
        # der Temperatur haengt: 13 Grad ergibt 1,0, 30 Grad fast 0.
        return {"year": jahr, "found_day": tag,
                "found": ([4.0] * 26, [13.0] * 20),
                "controls": [([4.0] * 26, [c] * 20) for c in controls],
                "control_years": [jahr - 2, jahr - 1, jahr + 1,
                                  jahr + 2][:len(controls)],
                "control_days": [tag] * len(controls)}

    viele = _probe(2010, 250, [13.0] * 4)
    wenige = _probe(2010, 250, [30.0])
    tage = schwellen_tage([viele, wenige], 13.0)
    assert len(tage) == 1 and len(tage[2010]) == 5, tage
    assert abs(sum(g for _, _, g in tage[2010]) - 2.0) < 1e-12
    assert abs(sum(g for w, _, g in tage[2010] if w > 0.5) - 1.0) < 1e-12, \
        "der Fund mit vier Kontrolljahren wiegt nicht mehr als der mit einem"

    # Fehlt die Spalte, bricht der Lauf ab — statt still ohne Monat zu
    # rechnen.
    ohne = dict(viele)
    del ohne["control_days"]
    try:
        schwellen_tage([ohne], 13.0)
        raise AssertionError("fehlende Kontrolltage bleiben unbemerkt")
    except SystemExit:
        pass

    # Jahresbalance: ein Jahr mit zehnmal so vielen Funden wiegt nicht
    # mehr. Und ueber die ganze Art summiert sich das Gewicht auf 1.
    roh = {2010: [(0.9, 9, 1.0)] * 10, 2011: [(0.1, 9, 1.0)]}
    gew = schwellen_gewichte(roh)
    assert abs(sum(g for e in gew.values() for _, _, g in e) - 1.0) < 1e-12
    assert abs(sum(g for _, _, g in gew[2010]) - 0.5) < 1e-12, gew
    assert schwellen_gewichte({}) == {}
    assert schwellen_gewichte({2010: []}) == {}

    # **Die schnelle Quantil-Suche muss dasselbe liefern wie
    # `av.quantile_at`.** Zwei Definitionen nebeneinander waeren genau
    # der Fall, in dem die Schlagzeilenzahl und ihr Band von
    # verschiedenen Groessen reden.
    rng = random.Random(7)
    for _ in range(40):
        bloecke_roh = [[(rng.random(), rng.random()) for _ in
                        range(rng.randint(1, 12))]
                       for _ in range(rng.randint(1, 5))]
        werte = [w for b in bloecke_roh for w, _ in b]
        gewichte = [g for b in bloecke_roh for _, g in b]
        bloecke = [schwellen_block([(w, 0, g) for w, g in b])
                   for b in bloecke_roh]
        kandidaten = sorted(set(werte))
        for q in (0.0, 0.1, 0.5, 0.8, 1.0):
            assert quantil_bloecke(bloecke, q, kandidaten) == \
                av.quantile_at(werte, gewichte, q), (q, bloecke_roh)
    assert quantil_bloecke([], 0.5, []) is None

    # Der Anteil ueber einer Grenze, mit und ohne Monatsfilter.
    proben = [(0.1, 9, 1.0), (0.9, 9, 1.0), (0.9, 10, 2.0)]
    assert abs(schwellen_anteil(proben, 0.5) - 0.75) < 1e-12
    assert abs(schwellen_anteil(proben, 0.5, 9) - 0.5) < 1e-12
    assert abs(schwellen_anteil(proben, 0.5, 10) - 1.0) < 1e-12
    assert schwellen_anteil(proben, 0.5, 3) is None
    # Auf der Grenze zaehlt mit — wie `level_with` in der App.
    assert schwellen_anteil([(0.5, 9, 1.0)], 0.5) == 1.0

    # **Jede Art gleich schwer.** Eine Art mit hundertmal so vielen
    # Tagen darf die Klassenschwelle nicht allein setzen.
    gross = schwellen_gewichte({2010: [(0.9, 9, 1.0)] * 100})
    klein = schwellen_gewichte({2010: [(0.1, 9, 1.0)]})
    klasse = schwellen_klasse([gross, klein], (0.25, 0.75), 0, 1)
    assert klasse["punkt"] == (0.1, 0.9), klasse["punkt"]

    # Das Band kommt aus einem Jahres-Bootstrap: eine Art mit genau
    # einem Jahr kann nicht streuen, zwei verschiedene Jahre schon.
    einjahr = schwellen_klasse([schwellen_gewichte(
        {2010: [(0.2, 9, 1.0), (0.8, 9, 1.0)]})], (0.5, 0.5), 50, 1)
    # Der Median zweier gleich schwerer Werte ist der UNTERE: das
    # 50-%-Quantil ist der kleinste Wert, bis zu dem die halbe Masse
    # liegt — dieselbe Definition wie in `av.quantile_at`.
    assert einjahr["punkt"] == (0.2, 0.2), einjahr
    assert einjahr["band"][0] == einjahr["band"][1] == (0.2, 0.2), einjahr
    zweijahr = schwellen_klasse([schwellen_gewichte(
        {2010: [(0.2, 9, 1.0)], 2011: [(0.8, 9, 1.0)]})], (0.5, 0.5), 200, 1)
    assert zweijahr["band"][0][0] < zweijahr["band"][0][1], zweijahr

    # Die Quantile sind die der Auslieferung — nicht die des Fits.
    assert SCHWELLEN_QUANTILE == (av.SHIP_QUANTILE_VERHALTEN,
                                  av.SHIP_QUANTILE_GUENSTIG)
    # Nur ausgelieferte Klassen. `holz` und `kalt` haben kein Fenster in
    # der App, also auch keine Schwelle, die man ersetzen koennte.
    assert {g for _, g, _ in SCHWELLEN_ARTEN} == {"herbst", "sommer"}
    assert len(SCHWELLEN_ARTEN) == 6, SCHWELLEN_ARTEN

    # **Die Scheibenwahl und ihr Riegel** (Betreiber, 2026-09-19).
    class _Args:
        scheibe = None
    assert schwellen_scheibe(_Args())[0] is False
    _Args.scheibe = "p3"
    assert schwellen_scheibe(_Args())[0] is False
    _Args.scheibe = "p1"
    auf_p1, wie = schwellen_scheibe(_Args())
    assert auf_p1 is True and str(av.FIT_UNTIL_YEAR + 1) in wie, wie
    _Args.scheibe = "P1"
    assert schwellen_scheibe(_Args())[0] is True, "Grossschreibung"
    _Args.scheibe = "at_ch"
    try:
        schwellen_scheibe(_Args())
        raise AssertionError("eine fremde Scheibe geht durch")
    except SystemExit:
        pass

    # Ein schwellenabhaengiges Guetemass bricht auf P1 ab und laeuft auf
    # P3 durch. Das ist der Unterschied zwischen einer beschriebenen
    # Verteilung und einer Guete, die die ausgelieferte Zahl mitbewertet.
    verbiete_schwellenmass(False, "Der Hebel")
    try:
        verbiete_schwellenmass(True, "Der Hebel")
        raise AssertionError("die Sperre greift nicht")
    except SystemExit as fehler:
        assert "P1" in str(fehler) and "AT+CH" in str(fehler), fehler
    assert "Trefferquote" in P1_GESPERRTE_MASSE
    assert "Hebel" in P1_GESPERRTE_MASSE

    # **Der Riegel steht im Bericht, nicht nur im Kommentar.** Wer die
    # Fundtagsspalte spaeter wieder einbaut, laeuft hinein.
    quelle_r = inspect.getsource(render_schwellen)
    assert "verbiete_schwellenmass(auf_p1" in quelle_r, \
        "der Bericht ruft die Sperre nicht auf"
    # Und der Lauf rechnet sie auf P1 gar nicht erst.
    quelle_l = inspect.getsource(run_schwellen)
    assert "funde_b = ({} if auf_p1" in quelle_l, \
        "der Lauf bewertet auf P1 doch Fundtage"

    # **Der Waechter ueber die ausgelieferten Schwellen.** Er ersetzt
    # den, der sie bis zum 2026-09-19 gegen Design-A-Quantile hielt.
    class _PinArgs:
        dataset = "pinned"
        dedupe = True
        seed = 42
        only = None

    def _erg(herbst, sommer):
        return {"herbst": {"b": {"punkt": herbst}},
                "sommer": {"b": {"punkt": sommer}}}

    passend = _erg((av.AMPEL_CLASSES["herbst"]["verhalten"],
                    av.AMPEL_CLASSES["herbst"]["guenstig"]),
                   (av.AMPEL_CLASSES["sommer"]["verhalten"],
                    av.AMPEL_CLASSES["sommer"]["guenstig"]))
    verify_schwellen_konstanten(passend, _PinArgs(), True)

    gewandert = _erg((0.111, 0.222), (0.333, 0.444))
    try:
        verify_schwellen_konstanten(gewandert, _PinArgs(), True)
        raise AssertionError("gewanderte Schwellen bleiben unbemerkt")
    except SystemExit as fehler:
        # Alle vier auf einmal, nicht nur die erste.
        for stueck in ("herbst.verhalten", "herbst.guenstig",
                       "sommer.verhalten", "sommer.guenstig"):
            assert stueck in str(fehler), (stueck, str(fehler))
        assert "ampel_model.dart" in str(fehler)

    # Auf einer anderen Messbasis MUSS er nur warnen: Dort weicht die
    # Zahl zwangslaeufig ab, und ein Abbruch blockierte jede kuenftige
    # Messung auf neuer Basis.
    class _AndereBasis(_PinArgs):
        dataset = "vorgabe"
    verify_schwellen_konstanten(gewandert, _AndereBasis(), True)
    # Ebenso auf P3 und bei einem Teillauf mit --only.
    verify_schwellen_konstanten(gewandert, _PinArgs(), False)

    class _Teillauf(_PinArgs):
        only = "Steinpilz"
    verify_schwellen_konstanten(gewandert, _Teillauf(), True)

    # Die Herkunft steht als Bedingung da, nicht nur im Fliesstext.
    assert SCHWELLEN_HERKUNFT["dataset"] == "pinned"
    assert SCHWELLEN_HERKUNFT["scheibe"] == "p1"
    # Und der Lauf ruft ihn auch auf.
    assert "verify_schwellen_konstanten(ergebnis, args, auf_p1)" in \
        inspect.getsource(run_schwellen)

    # **Das Vorher darf sich nicht mitbewegen.** Liest die Alt-Spalte
    # wieder die Konstanten, zeigt der Bericht nach jeder Uebernahme
    # ueberall null Unterschied — und wird nicht rot dabei.
    assert set(SCHWELLEN_VORHER) == {
        k for k, v in av.AMPEL_CLASSES.items() if v.get("dart")}
    for key, (v, g) in SCHWELLEN_VORHER.items():
        assert (v, g) != (av.AMPEL_CLASSES[key]["verhalten"],
                          av.AMPEL_CLASSES[key]["guenstig"]), (
            f"{key}: das Vorher ist dasselbe wie das Jetzt — die "
            "Vorher-Nachher-Tabelle zeigt dann nichts")
    assert schwelle_vorher("herbst", 0) == SCHWELLEN_VORHER["herbst"][0]
    assert schwelle_vorher("herbst", 1) == SCHWELLEN_VORHER["herbst"][1]
    assert schwelle_vorher("gibtsnicht", 0) is None
    quelle_v = inspect.getsource(render_schwellen)
    assert 'klass["guenstig"]' not in quelle_v, \
        "der Bericht liest die Alt-Spalte wieder aus den Konstanten"
    assert "Im Oktober" in quelle_v, "die Oktober-Zeile fehlt"

    # --- B aus Auftrag 3: die H6-Vorpruefung ---------------------------

    # Das Gitter muss die ausgelieferte Zahl treffen — laege sie
    # zwischen zwei Stuetzstellen, koennte der Vergleich „alt gegen neu"
    # sie nie ergeben.
    gitter = h6_gitterwerte()
    assert H6_OPTIMUM_ALT in gitter, H6_OPTIMUM_ALT
    assert gitter[0] == H6_GITTER_VON and gitter[-1] == H6_GITTER_BIS
    assert abs((gitter[1] - gitter[0]) - H6_GITTER_SCHRITT) < 1e-12
    # Und sie darf nicht am Rand liegen: ein Optimum am Gitterrand ist
    # keine Schaetzung, sondern eine Schranke.
    assert H6_GITTER_VON < H6_OPTIMUM_ALT < H6_GITTER_BIS

    # **Die schnelle Tabelle muss dasselbe liefern wie der ehrliche
    # Weg.** Sonst reden Schlagzeilenzahl und Bootstrap ueber
    # verschiedene Groessen — dieselbe Falle wie bei den Schwellen.
    h6_proben = []
    for jahr in range(2006, 2019):
        h6_proben += h1_probe(jahr, 2.0, 12.0 + (jahr % 3), 2.0, 17.0, 3)
    h6_tab = h6_tabelle(h6_proben)
    h6_jahre = sorted({s["year"] for s in h6_proben})
    for optimum in (10.0, 13.0, 17.5):
        assert abs(h6_b_aus_tabelle(h6_tab, optimum, h6_jahre)
                   - h1_b(h6_proben, optimum, None)) < 1e-12, optimum

    # Ein gepflanztes Optimum wird gefunden: Fundtage bei 12 Grad,
    # Kontrolltage bei 20 — dazwischen trennt es am besten, und zwar auf
    # der Fundseite.
    scharf = [s for jahr in range(2006, 2019)
              for s in h1_probe(jahr, 2.0, 12.0, 2.0, 20.0, 5)]
    got = h6_gitter_optimum(h6_tabelle(scharf),
                            sorted({s["year"] for s in scharf}))
    assert got["b"] == 1.0, got
    # **Bei Gleichstand die MITTE des Blocks, nicht sein linker Rand.**
    # Nachgerechnet: Ein Optimum o bewertet den Fund (12 Grad) hoeher
    # als die Kontrolle (20 Grad), solange |12 − o| < |20 − o|, also
    # o < 16. Gleich gut sind damit alle Stuetzstellen von 5,00 bis
    # 15,75; ihre Mitte ist 10,375. Der linke Rand waere 5,00 — eine
    # Eigenschaft des Gitterrands und keine Schaetzung. Genau diese
    # Verwechslung ist in der Gegenprobe gruen geblieben, bis die Zahl
    # hier stand.
    assert abs(got["optimum"] - 10.375) < 1e-9, got
    assert got["plateau"] == (5.0, 15.75), got

    # **Plateau und Gleichstand sind zwei verschiedene Dinge**, und aus
    # gefaltetem Wetter lassen sie sich schlecht auseinanderhalten.
    # Deshalb hier eine von Hand gesetzte B-Kurve: Gleichstand auf
    # 12,00 bis 13,00 (Mitte 12,50), und knapp darunter — weniger als
    # H6_PLATEAU — zwei Nachbarn bei 11,75 und 13,25.
    def h6_kurve(werte):
        return {o: {2010: (werte(o), 1)} for o in h6_gitterwerte()}

    gebaut = h6_kurve(lambda o: 1.0 if 12.0 <= o <= 13.0
                      else (1.0 - H6_PLATEAU / 2
                            if o in (11.75, 13.25) else 0.5))
    fein = h6_gitter_optimum(gebaut, [2010])
    assert abs(fein["optimum"] - 12.5) < 1e-9, fein
    assert fein["plateau"] == (11.75, 13.25), fein
    assert abs(fein["plateau_breite"] - 1.5) < 1e-9, fein
    # Und ein einzelner Gipfel hat ein Plateau der Breite null.
    spitz = h6_gitter_optimum(h6_kurve(lambda o: 1.0 if o == 14.0 else 0.0),
                              [2010])
    assert spitz["optimum"] == 14.0 and spitz["plateau_breite"] == 0.0

    # Ohne Jahre gibt es kein Optimum und keinen Fehler.
    assert h6_gitter_optimum(h6_tab, []) is None
    assert h6_gitter_se(h6_tab, [2010], 10, 1) is None

    # **Der Bootstrap muss wirklich ziehen.** In `h6_proben` hat jedes
    # dritte Jahr eine andere Fundtemperatur (12, 13, 14 Grad), die
    # Jahre tragen also verschiedene Optima — eine Ziehung mit
    # Zuruecklegen MUSS dann streuen. Ohne diese Zahl bliebe eine
    # Schleife, die jedes Jahr genau einmal nimmt, unbemerkt: Sie
    # lieferte in jedem Zug dasselbe und damit einen Standardfehler von
    # null, der wie Praezision aussieht.
    se = h6_gitter_se(h6_tab, h6_jahre, 200, 1)
    assert se is not None and se["n"] == 200, se
    assert se["se"] > 0, se
    assert se["band"][0] <= se["band"][1], se

    # Diskordanz: dasselbe Optimum ordnet nichts um.
    gleich = h6_diskordanz(h6_proben, 13.0, 13.0)
    assert gleich["anteil"] == 0.0 and gleich["mittlere_aenderung"] == 0.0
    # Und ein Optimum auf der Kontrollseite dreht jedes Paar um.
    dreht = h6_diskordanz(scharf, 12.0, 20.0)
    assert dreht["anteil"] == 1.0, dreht
    assert dreht["paare"] == 2 * len(scharf), dreht

    # Die Differenz aus dem Bootstrap ist die Differenz der beiden
    # B-Masse — nicht der Unterschied zweier getrennter Ziehungen.
    dd = h6_delta_bootstrap(scharf, 20.0, 12.0, 200, 1)
    assert abs(dd["delta"] - (h1_b(scharf, 12.0, None)
                              - h1_b(scharf, 20.0, None))) < 1e-12, dd
    assert abs(dd["mde"] - MDE_FAKTOR * dd["se"]) < 1e-12
    assert h6_delta_bootstrap(h1_probe(2010, 2.0, 12.0, 2.0, 20.0, 5),
                              20.0, 12.0, 10, 1) is None, "ein Jahr"
    # Und auch hier: Bei Jahren mit verschiedenen Differenzen muss das
    # Band Breite haben. `scharf` allein streut nicht (alle Jahre
    # gleich) und taugt dafuer nicht.
    # Ungerade Jahre: Fund 12, Kontrolle 20 — das neue Optimum (12)
    # dreht das Paar zu seinen Gunsten, Delta +1. Gerade Jahre genau
    # andersherum, Delta −1. Nur so tragen die Jahre verschiedene
    # Differenzen, und nur dann kann eine Ziehung ueberhaupt streuen.
    gemischt_j = []
    for jahr in range(2006, 2019):
        if jahr % 2:
            gemischt_j += h1_probe(jahr, 2.0, 12.0, 2.0, 20.0, 4)
        else:
            gemischt_j += h1_probe(jahr, 2.0, 20.0, 2.0, 12.0, 4)
    dd2 = h6_delta_bootstrap(gemischt_j, 20.0, 12.0, 400, 1)
    assert dd2["se"] > 0, dd2
    assert dd2["band"][0] < dd2["band"][1], dd2

    # --- Das Urteil, Bedingung fuer Bedingung --------------------------
    def h6_lage(**anders):
        lage = {
            "v1": {"abstand": 0.5},
            "v2": {"drift": 0.2, "se_ganz": 0.5},
            "v3": {"anteil": 0.20},
            "v4": {"mde": 0.05},
        }
        for schluessel, wert in anders.items():
            if wert is None:
                lage[schluessel] = None
            else:
                lage[schluessel] = {**lage[schluessel], **wert}
        return h6_urteil(lage["v1"], lage["v2"], lage["v3"], lage["v4"])

    assert h6_lage()["urteil"] == "H6 wird registriert"
    # V1: zwei Wege, die ueber mehr als die Latte streiten.
    assert h6_lage(v1={"abstand": H6_V1_MAX_ABWEICHUNG + 0.01})[
        "bedingungen"]["wege_einig"] is False
    # Genau auf der Latte gilt als erfuellt.
    assert h6_lage(v1={"abstand": H6_V1_MAX_ABWEICHUNG})[
        "bedingungen"]["wege_einig"] is True
    # V2: die Drift uebersteigt den Standardfehler.
    assert h6_lage(v2={"drift": 0.51})["bedingungen"]["stabil"] is False
    assert h6_lage(v2={"drift": 0.5})["bedingungen"]["stabil"] is True
    # **Nicht auswertbar faellt wie ein Nein aus.**
    assert h6_lage(v2={"drift": None})["bedingungen"]["stabil"] is False
    assert h6_lage(v2=None)["bedingungen"]["stabil"] is False
    assert h6_lage(v1=None)["bedingungen"]["wege_einig"] is False
    assert h6_lage(v4=None)["bedingungen"]["aufloesung"] is False
    assert h6_lage(v3=None)["bedingungen"]["aufloesung"] is False
    # V4: die Aufloesung reicht nicht an die Obergrenze heran.
    assert h6_lage(v4={"mde": 0.20})["bedingungen"]["aufloesung"] is False
    assert h6_lage(v4={"mde": 0.199})["bedingungen"]["aufloesung"] is True
    # Eine einzige gefallene Bedingung kippt das Urteil.
    for anders in ({"v1": {"abstand": 9.0}}, {"v2": {"drift": 9.0}},
                   {"v4": {"mde": 9.0}}):
        assert h6_lage(**anders)["urteil"] == "H6 wird NICHT registriert", \
            anders

    # Der Bericht nennt das Urteil und die Scheibe.
    quelle_h6 = inspect.getsource(render_h6)
    assert "P3 sind die Anpassjahre" in quelle_h6
    assert "eingefroren" in quelle_h6

    # --- H6, der registrierte Prueflauf --------------------------------

    # Die Ziehung wird EINMAL gemacht und zweimal bewertet.
    h6_gepaart = [s for jahr in range(2006, 2020)
                  for s in h1_probe(jahr, 2.0, 14.0, 2.0, 17.5, 12)]
    dj = h6_paare(h6_gepaart, H6_OPTIMUM_ALT, H6_OPTIMUM_NEU)
    assert len(dj) == 14, sorted(dj)
    assert all(len(v) == 12 for v in dj.values())
    # Fundtag genau auf dem neuen Optimum, Kontrolltag auf dem alten:
    # das neue Fenster dreht jedes Paar, das alte keines.
    assert all(a == 0.0 and n == 1.0 for werte in dj.values()
               for a, n in werte), dj[2006][:2]

    dd6 = h6_delta(h6_gepaart, H6_OPTIMUM_ALT, H6_OPTIMUM_NEU, 200, 1)
    assert abs(dd6["delta"] - 1.0) < 1e-12, dd6
    assert dd6["jahr_anteil"] == 1.0 and dd6["jahre"] == 14, dd6
    assert dd6["band"] is not None and dd6["band"][2] == 0.0, dd6
    # Der Standardfehler wird aus dem Band zurueckgerechnet; bei einem
    # Band der Breite null ist er null und die MDE damit auch.
    assert dd6["se"] == 0.0 and dd6["mde"] == 0.0, dd6
    # Und die Latte faellt dann auf den Mindestwert zurueck.
    assert h6_latte(dd6) == H6_MIN_GAIN
    assert h6_latte(None) == H6_MIN_GAIN
    assert h6_latte({"mde": 0.03}) == 0.03, "die Aufloesung hebt die Latte"

    # --- Das Urteil, Bedingung fuer Bedingung --------------------------
    def h6t(**anders):
        lage = {
            "delta": {"delta": 0.05, "band": (0.01, 0.09, 0.001),
                      "jahr_anteil": 0.9, "mde": 0.02},
            "gegen": {"delta": -0.01, "band": (-0.05, 0.03, 0.4)},
            "placebo": 0.5, "placebo_n": 500,
        }
        for k, v in anders.items():
            if v is None or not isinstance(v, dict):
                lage[k] = v
            else:
                lage[k] = {**lage[k], **v}
        return h6_test_urteil(lage["delta"], lage["gegen"], lage["placebo"],
                              lage["placebo_n"])

    assert h6t()["urteil"] == "H6 bestanden"
    # **Das Vorzeichen muss das Urteil kippen** (Registrierung, 8).
    assert h6t(delta={"delta": -0.05})["urteil"] == "H6 nicht bestanden"
    # Genau auf der Latte gilt als erfuellt, knapp darunter nicht.
    assert h6t(delta={"delta": 0.02})["bedingungen"]["gewinn"] is True
    assert h6t(delta={"delta": 0.0199})["bedingungen"]["gewinn"] is False
    # Der Mindestwert traegt, wenn die Aufloesung kleiner ist.
    assert h6t(delta={"delta": 0.012, "mde": 0.001})[
        "bedingungen"]["gewinn"] is True
    assert h6t(delta={"delta": 0.009, "mde": 0.001})[
        "bedingungen"]["gewinn"] is False
    # Band, Jahresanteil, Placebo — jedes allein kippt das Urteil.
    assert h6t(delta={"band": (-0.01, 0.09, 0.2)})["urteil"] == \
        "H6 nicht bestanden"
    assert h6t(delta={"jahr_anteil": H6_MIN_JAHR_ANTEIL - 0.01})[
        "urteil"] == "H6 nicht bestanden"
    assert h6t(delta={"jahr_anteil": H6_MIN_JAHR_ANTEIL})[
        "bedingungen"]["jahre"] is True
    assert h6t(placebo=0.62)["urteil"] == "H6 nicht bestanden"
    # **Die Gegenprobe kann kippen, aber nicht herstellen.**
    assert h6t(gegen={"delta": 0.05, "band": (0.01, 0.09, 0.001)})[
        "urteil"] == "H6 nicht bestanden", "Gegenprobe ignoriert"
    # Ein grosses Δ' ohne Band kippt nicht — das waere Rauschen.
    assert h6t(gegen={"delta": 0.05, "band": (-0.01, 0.11, 0.3)})[
        "bedingungen"]["gegenprobe"] is True
    # Fehlende Gegenprobe ist kein Fehlschlag, fehlende Messung schon.
    assert h6t(gegen=None)["bedingungen"]["gegenprobe"] is True
    assert h6t(delta=None)["urteil"] == "H6 nicht bestanden"
    assert h6t(placebo=None)["bedingungen"]["placebo"] is False

    # Die eingefrorenen Zahlen stehen als Konstanten da, nicht im Text.
    assert H6_OPTIMUM_NEU == 14.0 and H6_OPTIMUM_ALT == 17.5
    assert H6_OPTIMUM_GEGEN > H6_OPTIMUM_ALT, "Gegenprobe muss nach OBEN"
    assert H6_ACHSE == ("AT", "CH")
    # Der Bericht nennt Achse und Mangel.
    quelle_t = inspect.getsource(render_h6_test)
    assert "Prüfachse" in quelle_t and "gefallenem V1" in quelle_t

    # --- Bodenfeuchte --------------------------------------------------
    assert boden_mittel(None, 7) is None and boden_mittel([], 7) is None
    # Juengste Tage zuerst — `window_of` dreht die Reihe um.
    assert boden_mittel([1.0, 2.0, 3.0, 4.0], 2) == 1.5
    assert boden_mittel([1.0, None, 3.0], 3) == 2.0, "Luecken fallen raus"
    assert boden_mittel([None, None], 2) is None

    def _bp(jahr, fund, ktrl, anzahl=1):
        """Eine Probe mit Zusatzreihen — Regen und Temperatur gleich,
        damit NUR die Bodenfeuchte den Ausschlag geben kann."""
        return [{"year": jahr, "control_years": [jahr - 1, jahr + 1],
                 "found": ([2.0] * av.RAIN_WINDOW, [13.0] * av.TEMP_WINDOW),
                 "controls": [([2.0] * av.RAIN_WINDOW,
                               [13.0] * av.TEMP_WINDOW)] * 2,
                 "extra": {"smoist": [fund] * 28},
                 "extra_controls": [{"smoist": [ktrl] * 28}] * 2}
                for _ in range(anzahl)]

    nass = [s for jahr in range(2008, 2018) for s in _bp(jahr, 0.4, 0.2, 5)]
    trocken = [s for jahr in range(2008, 2018) for s in _bp(jahr, 0.2, 0.4, 5)]
    sc = boden_scorer("smoist", 7)
    assert boden_b(nass, sc, sc) == (1.0, 0), boden_b(nass, sc, sc)
    assert boden_b(trocken, sc, sc) == (0.0, 0)
    # Der Regen ist in beiden gleich — er darf nichts unterscheiden.
    assert h1_b(nass, 13.0, zerlegung_scorer(13.0, "nur Regen")) == 0.5

    # **Fehlende Reihen werden gezaehlt, nicht als Niederlage gewertet.**
    luecke = [dict(s, extra={}) for s in nass[:3]] + nass[3:]
    wert, fehlt = boden_b(luecke, sc, sc)
    assert fehlt == 3 and wert == 1.0, (wert, fehlt)
    # Ebenso, wenn die Zahl der Kontrollreihen nicht passt.
    schief = [dict(s, extra_controls=[{"smoist": [0.2] * 28}]) for s in nass]
    assert boden_b(schief, sc, sc) == (None, len(nass))
    # **Und wenn EIN Kontrolltag keine Reihe hat, faellt der ganze Fund
    # heraus.** Ihn auf den verbliebenen Kontrollen zu bewerten waere
    # eine andere Ziehung als die, die oben gelaufen ist: Der Fund
    # stuende dann gegen weniger Jahre und traege trotzdem dasselbe
    # Gewicht.
    halb = [dict(s, extra_controls=[{"smoist": [0.2] * 28},
                                    {"smoist": [None] * 28}])
            for s in nass[:4]] + nass[4:]
    wert2, fehlt2 = boden_b(halb, sc, sc)
    assert fehlt2 == 4, (wert2, fehlt2)

    # Bodenfeuchte mal Glocke: bei gleicher Temperatur entscheidet die
    # Feuchte, bei gleicher Feuchte die Temperatur.
    assert boden_kombi(nass, 13.0, 7)[0] == 1.0
    kalt = [dict(s, found=([2.0] * av.RAIN_WINDOW, [0.0] * av.TEMP_WINDOW))
            for s in nass]
    assert boden_kombi(kalt, 13.0, 7)[0] == 0.0, \
        "die Glocke muss die nassere Probe schlagen koennen"

    # Ohne Bodenfeuchte im Datensatz bricht der Lauf ab, statt eine
    # leere Tabelle zu schreiben.
    assert "smoist" in av.ampel_basis.dataset_fields("pinned")
    assert "smoist" not in av.ampel_basis.dataset_fields("vorgabe")
    assert "keine Bodenfeuchte" in inspect.getsource(run_boden)
    assert BODEN_FENSTER[0] == 1 and BODEN_FENSTER[-1] == av.RAIN_WINDOW

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
                       seed=42, score=None):
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
    a_jahre = _fractions(art, optimum, jahr, score)
    r_jahre = _fractions(referenz, optimum, jahr, score)
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
    """Aus B-Funden die Strata: ein Fundtag gegen seine Kontrolltage.

    Gibt zusaetzlich je Stratum das **Fundjahr** zurueck. Es ist die
    Gruppe fuer den cluster-robusten Fehler — dieselbe Einheit wie bei
    jedem Bootstrap dieser Arbeit, damit eine Spalte nicht zwischen zwei
    Berichten ihre Bedeutung wechselt.
    """
    strata, jahre = [], []
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
        jahre.append(s["year"])
    return strata, jahre, abgeschnitten, gesamt


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
        strata, jahre, abgeschnitten, gesamt = logit_strata(samples)
        if len(strata) < 50:
            zeilen.append({"name": name, "gruppe": gruppe,
                           "gesetzt": optimum, "fit": None,
                           "strata": len(strata)})
            continue
        fit = ampel_logit.fit_conditional_logit(strata, cluster=jahre)
        glocke = ampel_logit.bell_from_beta(fit["beta"], fit["kovarianz"])
        robust = (ampel_logit.bell_from_beta(fit["beta"],
                                             fit["kovarianz_cluster"])
                  if fit["kovarianz_cluster"] else None)
        zeilen.append({
            "name": name, "gruppe": gruppe, "gesetzt": optimum,
            "fit": fit, "glocke": glocke, "robust": robust,
            "strata": len(strata),
            "abgeschnitten": abgeschnitten / gesamt if gesamt else None,
        })
        quelle = robust or glocke
        print(f"    Optimum {_fmt(glocke.get('optimum'), 2)} ± "
              f"{_fmt(quelle.get('se_optimum'), 2)}   Breite "
              f"{_fmt(glocke.get('breite'), 2)} ± "
              f"{_fmt(quelle.get('se_breite'), 2)}   "
              f"({fit['gruppen']} Jahre)", file=sys.stderr)

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
    w("> **Achtung beim Wiederholen:** Dieser Lauf überschreibt die "
      "Datei vollständig. Die einordnenden Abschnitte (`### …`) sind von "
      "Hand geschrieben und sind danach weg — wer neu rechnet, trägt sie "
      "wieder ein. Genau das ist am 2026-09-19 einmal passiert.\n")

    w("\n## Was das Modell ist\n")
    w("Bedingtes Logit mit den Merkmalen `[log F, T̄₂₀, T̄₂₀²]`, ohne "
      "Achsenabschnitt — Ort, Jahr und Jahreszeit kürzen sich über das "
      "Stratum heraus. Es hängt direkt an der Formel der Ampel:\n")
    w("    log(F · exp(−((T−opt)/σ)²)) = log F − T²/σ² + 2·opt·T/σ² − opt²/σ²\n")
    w("Der letzte Summand ist je Stratum konstant und fällt heraus. Also "
      "`Optimum = −b_T / (2 b_T²)` und `Breite = sqrt(b_logF / −b_T²)`.\n")
    w("**Beide Größen sind maßstabsfrei**, und das ist wichtig für den "
      "Vergleich: Skaliert man alle Koeffizienten mit demselben Faktor, "
      "kürzt er sich in beiden Formeln heraus. Die Breite ist damit "
      "unmittelbar das σ, das zu einem Einheitsgewicht auf `log F` "
      "gehört — also genau das, was die Ampel rechnet.\n")
    w("`b_logF` sagt deshalb nichts über eine Gewichtung, sondern "
      "darüber, **wie scharf die Wahl überhaupt ist**: Es ist der "
      "gemeinsame Faktor vor dem ganzen Nutzen, und ein kleiner Wert "
      "heißt viel Rauschen. Bei AUC-Werten um 0,6 gehört ein kleines "
      "`b_logF` zum Bild. Es steht in der Tabelle, weil es die Schärfe "
      "beziffert — nicht, weil die Breite ohne es unlesbar wäre. (In "
      "einer früheren Fassung dieses Werkzeugs stand genau das, und es "
      "war falsch.)\n")

    w("\n## Gemessen\n")
    w("Die Fehler in **fetter** Spalte sind cluster-robust über das "
      "Fundjahr; die naiven daneben stehen nur zum Vergleich.\n")
    w("| Art | Gruppe | Strata | Jahre | Optimum | **± robust** | ± naiv | "
      "ausgeliefert | Breite | **± robust** | ± naiv | b_logF | "
      "konvergiert |")
    w("|---|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|:-:|")
    for z in zeilen:
        if not z.get("fit"):
            w(f"| {z['name']} | {z['gruppe']} | {z['strata']} | — | — | — | "
              f"— | {z['gesetzt']:.1f} | — | — | — | — | — |")
            continue
        g, r = z["glocke"], (z.get("robust") or {})
        w(f"| {z['name']} | {z['gruppe']} | {z['strata']} | "
          f"{z['fit']['gruppen']} | "
          f"{_fmt(g.get('optimum'), 2)} | **{_fmt(r.get('se_optimum'), 2)}** "
          f"| {_fmt(g.get('se_optimum'), 2)} | "
          f"{z['gesetzt']:.1f} | {_fmt(g.get('breite'), 2)} | "
          f"**{_fmt(r.get('se_breite'), 2)}** | "
          f"{_fmt(g.get('se_breite'), 2)} | {_fmt(g.get('b_logf'), 2)} | "
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
    w("**Die cluster-robusten Fehler sind die, die gelten.** Mehrere "
      "Funde teilen sich Fundjahr, Zelle und Melder; ein gutes Pilzjahr "
      "hebt alle zugleich. Der naive Fehler unterstellt Unabhängigkeit, "
      "die es nicht gibt, und fällt deshalb zu klein aus — eine "
      "frühere Fassung dieser Seite hat auf ihm Sätze wie „das sind "
      "vier Standardfehler“ gebaut, und die standen auf zu schmalen "
      "Balken.\n")
    w("**Auch die robuste Zahl ist keine sichere.** Sie stützt sich auf "
      "ein gutes Dutzend Fundjahre, und bei so wenigen Gruppen ist der "
      "Sandwich selbst verrauscht und eher zu klein als zu groß. Und er "
      "deckt nur das Fundjahr ab: Die Bündelung nach **Melder** und "
      "nach **Zelle** ist damit nicht erfasst. Wer diese Zahlen eng "
      "liest, liest sie falsch.\n")
    w("Und die Delta-Methode hat ihre eigene Grenze: Sie unterstellt, "
      "dass die Umformung im Bereich eines Standardfehlers ungefähr "
      "gerade ist. Bei einer flachen Likelihood — `b_T²` nahe null — ist "
      "sie das nicht, und der Fehler fällt dann eher zu klein aus. "
      "Deshalb hilft im Zweifel der Blick auf `b_T²` selbst.")
    return "\n".join(aus) + "\n"


# --- Vorpruefung zu H5: die Zerlegung auf den Anpassjahren -----------------
#
# Registriert in `docs/pilzampel-h5-vorpruefung.md`, VOR diesem Lauf.
# Gerechnet auf P3 (DE <= FIT_UNTIL_YEAR) — den Anpassjahren. Das ist
# **keine Pruefachse**: Dort wird ohnehin gefittet und diagnostiziert,
# der Lauf verbraucht nichts.
#
# Der Anlass steht in `docs/pilzampel-pruefachsen.md`: Die Zerlegung aus
# `--h1` lief auf P1 und damit auf einer Achse. Eine Hypothese, die dort
# entsteht, kann dort nicht mehr unbefangen geprueft werden.

ZERLEGUNG_VARIANTEN = ("voll", "nur Regen", "nur Temperatur")

# Die Schwellen der Registrierung, Abschnitt „Die Entscheidung".
Z_MIN_ARTEN = 5           # von den sechs ausgelieferten
Z_GLOCKE_BEITRAG = 0.020  # ab hier traegt die Glocke etwas
Z_ABSTAND_VERLUST = 0.020 # so viel darf der Referenzabstand verlieren

ZERLEGUNG_AUSGELIEFERT = (H1_KLASSEN["herbst"] + H1_KLASSEN["sommer"])


def zerlegung_scorer(optimum, variante):
    """Der Bewerter je Variante — die ausgelieferte Breite durchweg.

    `nur Temperatur` ist von sigma unabhaengig (siehe `h1_scorer`); hier
    wird sigma deshalb gar nicht erst zur Wahl gestellt.
    """
    if variante == "nur Regen":
        return lambda regen, temp: av.rain_factor(regen)
    if variante == "nur Temperatur":
        return lambda regen, temp: av.temperature_factor(temp, optimum,
                                                         H1_SIGMA_ALT)
    return lambda regen, temp: av.ampel_score(regen, temp, optimum,
                                              H1_SIGMA_ALT)


def zerlegung_urteil(zeilen):
    """Die drei Bedingungen aus der Registrierung, Zeile fuer Zeile.

    **Betrachtet werden nur die sechs ausgelieferten Arten.** Die
    uebrigen laufen nachrichtlich mit und entscheiden nichts — ihre
    Klassen sind nicht ausgeliefert, und nach Phase 1.5 steht fuer alle
    fuenf „keine Aussage".
    """
    dabei = [z for z in zeilen if z["name"] in ZERLEGUNG_AUSGELIEFERT
             and z.get("b") and z["b"].get("voll") is not None]
    if not dabei:
        return {"urteil": "kein Urteil", "arten": 0}

    reist = [z for z in dabei
             if z["b"]["nur Regen"] is not None
             and z["b"]["nur Temperatur"] is not None
             and z["b"]["nur Regen"] > z["b"]["nur Temperatur"]]
    glocke = [z for z in dabei
              if z["b"]["nur Regen"] is not None
              and (z["b"]["voll"] - z["b"]["nur Regen"]) < Z_GLOCKE_BEITRAG]
    # Bedingung 3, erste Haelfte: Der Abstand zur Referenz ueberlebt den
    # Wechsel auf den reinen Regen-Score — Band ohne die Null.
    abstand = [z for z in dabei
               if z.get("delta", {}).get("nur Regen") is not None
               and z["delta"]["nur Regen"] > 0
               and z.get("band", {}).get("nur Regen") is not None
               and z["band"]["nur Regen"][2] < P_GRENZE]
    # Zweite Haelfte: Er schrumpft nicht. Verglichen werden MEDIANE, weil
    # eine einzelne Art mit duenner Referenz sonst das Bild traegt.
    d_regen = [z["delta"]["nur Regen"] for z in dabei
               if z.get("delta", {}).get("nur Regen") is not None]
    d_voll = [z["delta"]["voll"] for z in dabei
              if z.get("delta", {}).get("voll") is not None]
    median_ok = (bool(d_regen) and bool(d_voll)
                 and statistics.median(d_regen)
                 >= statistics.median(d_voll) - Z_ABSTAND_VERLUST)

    bed = {
        "reist": len(reist) >= Z_MIN_ARTEN,
        "glocke_traegt_nichts": len(glocke) >= Z_MIN_ARTEN,
        "abstand_haelt": len(abstand) >= Z_MIN_ARTEN and median_ok,
    }
    return {
        "urteil": ("H5 wird registriert" if all(bed.values())
                   else "H5 wird NICHT registriert"),
        "bedingungen": bed, "arten": len(dabei),
        "n_reist": len(reist), "n_glocke": len(glocke),
        "n_abstand": len(abstand), "median_ok": median_ok,
        "median_regen": statistics.median(d_regen) if d_regen else None,
        "median_voll": statistics.median(d_voll) if d_voll else None,
    }


def zerlegung_scheibe(args):
    """Die Jahresscheibe des Laufs — und der Riegel davor.

    Ohne `--jahre` sind es die Anpassjahre als Ganzes. Mit `--jahre
    2006-2012` eine Teilscheibe davon.

    **Der Riegel ist der Zweck dieser Funktion.** Eine Jahresangabe ist
    eine Zeile im Aufruf, und eine verrutschte Ziffer machte aus einer
    kostenlosen Diagnose einen Lauf auf einer Pruefachse — ohne dass
    irgendwo etwas rot wuerde. Deshalb bricht der Lauf ab, statt zu
    rechnen: `--zerlegung` kommt nie ueber `FIT_UNTIL_YEAR` hinaus.
    """
    if not getattr(args, "jahre", None):
        return None, av.FIT_UNTIL_YEAR
    teile = args.jahre.split("-")
    if len(teile) != 2 or not all(t.strip().isdigit() for t in teile):
        raise SystemExit("--jahre erwartet die Form 2006-2012")
    von, bis = int(teile[0]), int(teile[1])
    if von > bis:
        raise SystemExit(f"--jahre {args.jahre}: von liegt hinter bis")
    if bis > av.FIT_UNTIL_YEAR:
        raise SystemExit(
            f"--jahre {args.jahre} reicht über die Anpassjahre hinaus "
            f"(bis {av.FIT_UNTIL_YEAR}). `--zerlegung` ist eine Diagnose "
            "und darf keine Prüfachse anfassen.")
    return von, bis


def run_zerlegung(args):
    """Die Vorpruefung zu H5 — auf P3, ohne eine Achse zu verbrauchen."""
    if args.api:
        av.OPEN_METEO = args.api.rstrip("/")
    av.DEDUPE = args.dedupe
    av.use_dataset(args.dataset)
    von, bis = zerlegung_scheibe(args)
    print(f"Zerlegung auf DE {von or 2006}–{bis} — Anpassjahre, "
          "keine Prüfachse", file=sys.stderr)
    print("Registrierung: docs/pilzampel-h5-vorpruefung.md", file=sys.stderr)

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
        print(f"  {name}", file=sys.stderr)
        finds, _ = av.select_finds(sci, args.cache, args.seed, True, ("DE",))
        if not finds:
            continue
        gezogen = av.collect_pairs_b(name, sci, finds=finds,
                                     cache_dir=args.cache, seed=args.seed,
                                     progress=False)
        if not gezogen:
            continue
        # **Dieselbe Ziehung wie in Phase 1.5** — gleicher Seed, gleiche
        # Fundliste, gleiche Jahresscheibe. Sonst waere der Unterschied
        # zu jenen Zahlen teils die Stichprobe.
        samples = h1_panel(fit_years_only(gezogen["samples"]), von, bis)

        if pool is None:
            print("    Referenzbestand wird geladen …", file=sys.stderr)
            pool = target_group_finds(progress=True)
        ref_finds, ref_info = matched_reference(finds, pool, sci,
                                                seed=args.seed)
        ref_s = []
        if len(ref_finds) >= 50:
            rb = av.collect_pairs_b("Referenz " + name, "—", finds=ref_finds,
                                    cache_dir=args.cache, seed=args.seed,
                                    progress=False)
            if rb:
                ref_s = h1_panel(fit_years_only(rb["samples"]), von, bis)

        b, ref_b, delta, band = {}, {}, {}, {}
        for variante in ZERLEGUNG_VARIANTEN:
            score = zerlegung_scorer(optimum, variante)
            b[variante] = h1_b(samples, optimum, score)
            ref_b[variante] = h1_b(ref_s, optimum, score) if ref_s else None
            delta[variante] = (None if b[variante] is None
                               or ref_b[variante] is None
                               else b[variante] - ref_b[variante])
            band[variante] = (bootstrap_ref_diff(
                samples, ref_s, optimum, rounds=BOOTSTRAP_ROUNDS_B,
                seed=args.seed, score=score) if ref_s else None)

        zeilen.append({
            "name": name, "gruppe": gruppe, "optimum": optimum,
            "ausgeliefert": name in ZERLEGUNG_AUSGELIEFERT,
            "n": len(samples), "ref_n": len(ref_s),
            "zellen": ref_info["zellen"],
            "b": b, "ref_b": ref_b, "delta": delta, "band": band,
            "scheibe": f"{von or 2006}–{bis}",
        })
        print(f"    voll {_fmt(b['voll'])}  Regen {_fmt(b['nur Regen'])}  "
              f"Temp {_fmt(b['nur Temperatur'])}   "
              f"Δ_Regen {_signed(delta['nur Regen'])}", file=sys.stderr)

    bericht = render_zerlegung(zeilen)
    if args.out:
        open(args.out, "w", encoding="utf-8").write(bericht)
        print(f"\n{args.out} geschrieben", file=sys.stderr)
    else:
        print(bericht)


def render_zerlegung(zeilen):
    """Der Bericht zur H5-Vorprüfung."""
    import time as _t
    aus = []
    w = aus.append
    band = lambda b: "—" if b is None else f"[{b[0]:+.3f}, {b[1]:+.3f}]"
    haken = lambda ok: "✓" if ok else "✗"
    urteil = zerlegung_urteil(zeilen)
    w("# Vorprüfung zu H5: trägt die Glocke etwas bei? — die Messung\n")
    w(f"Stand: {_t.strftime('%Y-%m-%d')} · Erzeugt von "
      "`tool/ampel_diagnose.py --zerlegung` · **Registrierung (vor dem "
      "Lauf geschrieben): `docs/pilzampel-h5-vorpruefung.md`**\n")
    scheibe = zeilen[0].get("scheibe") if zeilen else None
    w(f"Gerechnet auf **DE {scheibe or f'≤ {av.FIT_UNTIL_YEAR}'}** — "
      "innerhalb der Anpassjahre. Das ist keine Prüfachse; dieser Lauf "
      "verbraucht nichts (`docs/pilzampel-pruefachsen.md`).\n")
    w(f"Messbasis `{av.DATASET}`, Entdoppeln "
      f"{'an' if av.DEDUPE else 'aus'}, Design B, dieselbe Ziehung wie "
      "Phase 1.5.\n")
    w("> **Achtung beim Wiederholen:** Dieser Lauf überschreibt die "
      "Datei vollständig. Einordnende Abschnitte (`### …`) sind von Hand "
      "geschrieben und danach weg.\n")

    w("\n## Das Ergebnis\n")
    w(f"### {urteil['urteil']}\n")
    if urteil.get("bedingungen"):
        b = urteil["bedingungen"]
        w(f"| Bedingung | Schwelle | erreicht | |")
        w("|---|---|--:|:-:|")
        w(f"| 1 — die Zerlegung reist | B(Regen) > B(Temp) bei ≥ "
          f"{Z_MIN_ARTEN} von 6 | {urteil['n_reist']} von "
          f"{urteil['arten']} | {haken(b['reist'])} |")
        w(f"| 2 — die Glocke trägt nichts bei | B(voll) − B(Regen) < "
          f"{Z_GLOCKE_BEITRAG:.3f} bei ≥ {Z_MIN_ARTEN} von 6 | "
          f"{urteil['n_glocke']} von {urteil['arten']} | "
          f"{haken(b['glocke_traegt_nichts'])} |")
        w(f"| 3 — der Referenzabstand hält | Band ohne Null bei ≥ "
          f"{Z_MIN_ARTEN} von 6 **und** Median nicht mehr als "
          f"{Z_ABSTAND_VERLUST:.3f} darunter | {urteil['n_abstand']} von "
          f"{urteil['arten']}, Median {_signed(urteil['median_regen'])} "
          f"gegen {_signed(urteil['median_voll'])} | "
          f"{haken(b['abstand_haelt'])} |")
        w("")
    w("**Kein Zwischenergebnis wird nachverhandelt** — die Schwellen "
      "standen vor dem Lauf fest.\n")

    w("\n## Die Zerlegung je Art\n")
    w("Dieselben Paare, drei Bewerter. „Nur Temperatur“ ist von der "
      "Glockenbreite unabhängig, weil das Maß rangbasiert ist.\n")
    w("| Art | ausgeliefert | Funde | B voll | B nur Regen | "
      "B nur Temperatur | voll − Regen |")
    w("|---|:-:|--:|--:|--:|--:|--:|")
    for z in zeilen:
        d = (None if z["b"]["voll"] is None or z["b"]["nur Regen"] is None
             else z["b"]["voll"] - z["b"]["nur Regen"])
        w(f"| {z['name']} | {'**ja**' if z['ausgeliefert'] else 'nein'} | "
          f"{z['n']} | {_fmt(z['b']['voll'])} | "
          f"{_fmt(z['b']['nur Regen'])} | "
          f"{_fmt(z['b']['nur Temperatur'])} | {_signed(d)} |")

    w("\n## Die Referenz, in denselben drei Bewertern\n")
    w("Meldungen anderer Pilze aus denselben ~10-km-Zellen und mit der "
      "Monatsverteilung der Zielart. **Sie ist kein Abzugsposten** (A6): "
      "„irgendeine Pilzmeldung“ ist überwiegend *andere Pilze*, die "
      "auf dasselbe Wetter reagieren.\n")
    w("| Art | Referenzfunde | Zellen | Ref voll | Ref nur Regen | "
      "Ref nur Temperatur |")
    w("|---|--:|--:|--:|--:|--:|")
    for z in zeilen:
        w(f"| {z['name']} | {z['ref_n']} | {z['zellen']} | "
          f"{_fmt(z['ref_b']['voll'])} | {_fmt(z['ref_b']['nur Regen'])} | "
          f"{_fmt(z['ref_b']['nur Temperatur'])} |")

    w("\n## Die Entscheidung: der Abstand zur Referenz je Bewerter\n")
    w("**Regen wirkt auch auf den Sammler.** Design B nimmt Ort und "
      "Jahreszeit heraus, nicht die Wetterabhängigkeit des Suchens. "
      "Steigt die Referenz mit einem Regen-Score genauso wie die Art, "
      "ist nichts gewonnen — nur der Abstand zählt.\n")
    w("| Art | Δ voll | 95 % | Δ nur Regen | 95 % | p | Δ nur Temperatur |")
    w("|---|--:|---|--:|---|--:|--:|")
    for z in zeilen:
        w(f"| {z['name']} | {_signed(z['delta']['voll'])} | "
          f"{band(z['band']['voll'])} | "
          f"{_signed(z['delta']['nur Regen'])} | "
          f"{band(z['band']['nur Regen'])} | "
          f"{_pwert(z['band']['nur Regen'])} | "
          f"{_signed(z['delta']['nur Temperatur'])} |")

    w("\n## Grenzen\n")
    w(f"**P3 sind die Anpassjahre. Jede Zahl hier ist eine Diagnose.** "
      "Auch ein glänzendes Ergebnis belegt H5 nicht — es erlaubt nur, "
      "H5 zu registrieren und dann auf AT+CH zu prüfen.\n")
    w("Und die Referenz trennt Suchaufwand und allgemeine "
      "Pilz-Wetterreaktion nicht (A6); sie begrenzt beide zusammen nach "
      "oben.")
    return "\n".join(aus) + "\n"


# --- A aus Auftrag 3: die Schwellen aus Design B --------------------------
#
# `docs/pilzampel-auftrag-3.md`, Abschnitt A. **Vor dem Lauf
# geschrieben**; was danach geaendert wurde, steht im Korrekturkasten des
# Berichts.
#
# Die vier ausgelieferten Schwellen sind Quantile der Score-Verteilung an
# VERGLEICHSTAGEN. Sie entscheiden nicht, wie gut die Ampel trennt,
# sondern wie oft sie „guenstig" sagt — eine Haeufigkeitsfrage. Gesetzt
# wurden sie an Design-A-Vergleichstagen: ein anderer Tag derselben
# Saison, 26 bis 45 Tage neben dem Fund, im selben Jahr. Dieselbe
# Jahreszeit-Unwucht, die Phase 1.5 an der AUC gemessen hat, steckt
# damit auch in ihnen.
#
# Design B fragt dieselbe Frage an einem anderen Tag: dasselbe Datum,
# derselbe Ort, ein anderes Jahr. Was dabei herauskommt, ist die
# Verteilung „wie ist das Wetter an diesem Ort um diese Zeit ueblich" —
# und das ist die Bezugsgroesse, die zur Aussage „heute ist es
# ungewoehnlich gut" gehoert.
#
# **Drei Zellen, nicht zwei.** Die ausgelieferten Zahlen stammen aus
# Design A auf den PRUEFJAHREN (P1). Ein blosser Vergleich „alt gegen
# Design B auf P3" vermengte zwei Unterschiede: das Design UND die
# Zeitscheibe. Deshalb wird Design A auf P3 mitgerechnet — es kostet
# nichts, weil P3 die Anpassjahre sind, und erst damit laesst sich
# sagen, welcher Anteil woher kommt. Die vierte Zelle (Design B auf P1)
# faellt aus: Sie waere die auslieferbare Zahl, fasst aber eine
# Pruefachse an und ist deshalb eine eigene Entscheidung.

# Die Quantile der Auslieferung — „gleich haeufig wie bisher",
# Betreiberentscheidung vom 2026-09-12. Sie sind hier NICHT zur
# Diskussion gestellt: Gefragt ist, welche Zahl dasselbe Quantil in
# Design B traegt.
SCHWELLEN_QUANTILE = (av.SHIP_QUANTILE_VERHALTEN, av.SHIP_QUANTILE_GUENSTIG)

# Der Jahres-Bootstrap der Schwelle. Weniger Zuege als bei den
# Pruefbaendern (20 000), und das ist Absicht: Hier haengt keine
# Entscheidung an einer Bandkante, das Band ist eine Auskunft ueber die
# Genauigkeit. 2000 Zuege geben die zweite Nachkommastelle stabil.
SCHWELLEN_ROUNDS = 2000

# Nur die ausgelieferten Klassen. `holz` und `kalt` haben kein Fenster
# in der App und damit auch keine Schwelle, die man ersetzen koennte.
#
# **Das Fenster kommt aus der Klassentabelle, nicht aus DESIGN_ARTEN**
# (seit 2026-09-20). Die Schwellen sind Quantile UNTER dem ausgelieferten
# Fenster; als das Pfifferling-Fenster auf 14,5 °C gesetzt wurde, mass
# dieser Lauf still weiter mit den 17,5 aus der Diagnosetabelle und
# lieferte die alten Zahlen — eine zweite Quelle fuer dieselbe Konstante.
SCHWELLEN_ARTEN = [(n, g, av.AMPEL_CLASSES[g]["optimum"])
                   for n, g, _ in DESIGN_ARTEN if g in ("herbst", "sommer")]

# **Eine eigene Untergrenze, und zwar eine niedrigere als `MIN_FINDS_B`.**
# Nachtraeglich gesetzt, am 2026-09-19, und deshalb im Korrekturkasten
# des Berichts: Mit der Verdikt-Grenze (150 Funde) fiel die
# Herbsttrompete mit 147 aus der Klasse heraus — die Klassenschwelle
# haette dann auf vier statt fuenf Mitgliedern geruht, obwohl die App
# sie fuer fuenf ausliefert.
#
# Die beiden Grenzen messen nicht dasselbe. `MIN_FINDS_B` entscheidet,
# ob eine Art ein URTEIL traegt — dort steht eine einzelne Zahl gegen
# eine Latte, und eine duenne Zahl darf das nicht. Hier steuert eine Art
# ein Fuenftel zu einem Quantil bei, und ihr Beitrag wird mit vier
# anderen gemittelt. Die Fehlerrichtung ist umgekehrt: Eine
# ausgelieferte Art WEGZULASSEN verzerrt die Schwelle sicher, sie mit
# 147 Funden mitzunehmen nur vielleicht.
#
# Damit das keine Ausrede bleibt, steht im Bericht eine
# Leave-one-out-Spalte: was die Schwelle waere, wenn genau diese Art
# fehlte. Traegt eine einzelne Art die Zahl, sieht man es dort.
SCHWELLEN_MIN_FUNDE = 100

# **Die Schwellen VOR der Uebernahme, ausgeschrieben.**
# Bis zum 2026-09-19 las die Alt-Spalte dieses Berichts die Konstanten
# aus `AMPEL_CLASSES`. Das ging genau so lange gut, bis die neuen Zahlen
# uebernommen wurden — danach haette der Bericht „alt" gegen „alt"
# verglichen und ueberall null Unterschied gezeigt, ohne rot zu werden.
# Ein Vorher-Nachher braucht ein Vorher, das sich nicht mitbewegt.
#
# Herkunft dieser vier Zahlen: Design A, Quantile 50/80 auf den
# Pruefjahren, gesetzt am 2026-09-12
# (`docs/pilzampel-schwellen-messung.md`).
SCHWELLEN_VORHER = {"herbst": (0.187, 0.512), "sommer": (0.287, 0.677)}


def schwelle_vorher(key, i):
    """Die alte Schwelle einer Klasse — Stufe 0 verhalten, 1 guenstig."""
    return SCHWELLEN_VORHER[key][i] if key in SCHWELLEN_VORHER else None

# **Warum eine Schwelle auf P1 gerechnet werden DARF** (Betreiber,
# 2026-09-19). Der Grund ist, dass Schwelle und gepaarte AUC disjunkte
# Statistiken sind: Die AUC ist rangbasiert und von jeder Schwelle
# voellig unabhaengig. Eine aus P1 gezogene Schwelle kann deshalb keinen
# bisherigen und keinen kuenftigen AUC-Test beruehren — es gibt dort
# keine Latte, kein Band und nichts zu bestehen. Beschrieben wird eine
# Verteilung, nicht ausgewaehlt.
#
# Und P1 ist hier sogar die RICHTIGE Scheibe: Die App steht heute, nicht
# 2012, und die Zeitscheibe macht beim Pfifferling ueber ein Drittel des
# Sprungs aus (`docs/pilzampel-schwellen-designb.md`).
#
# **Die Grenze dieser Erlaubnis, und sie ist scharf:** Sobald ein Mass
# eine Schwelle BENUTZT, um Fundtage zu bewerten, ist es kein
# Verteilungsbefund mehr, sondern eine Guete — Trefferquote, POD, FAR,
# TSS, und auch der Hebel aus dem P3-Bericht. Solche Zahlen auf P1 zu
# rechnen waere echte Kontamination, denn dort entschiede die
# ausgelieferte Schwelle mit, wie gut die Ampel aussieht. Sie sind auf
# P1 gesperrt; wer sie braucht, rechnet sie auf AT+CH.
P1_GESPERRTE_MASSE = ("Trefferquote", "POD", "FAR", "TSS", "Hebel",
                      "Fundtag-Anteil")


def verbiete_schwellenmass(auf_p1, was):
    """Der Riegel zur Regel vom 2026-09-19.

    Ein Verteilungsbefund auf P1 ist erlaubt, eine schwellenabhaengige
    Guete nicht. Der Unterschied ist eine Zeile im Aufruf und deshalb
    leicht zu uebersehen — also bricht der Lauf ab, statt eine Zahl zu
    liefern, die hinterher niemand mehr von einer erlaubten
    unterscheiden kann.
    """
    if auf_p1:
        raise SystemExit(
            f"{was} ist ein schwellenabhaengiges Guetemass und auf P1 "
            "gesperrt (Regel vom 2026-09-19, "
            "docs/pilzampel-pruefachsen.md). Auf P3 ist es erlaubt, auf "
            "AT+CH waere es ein Pruefachsenlauf.")


def schwellen_scheibe(args):
    """Welche Zeitscheibe der Lauf beschreibt — und was das erlaubt.

    Rueckgabe: (auf_p1, name). Vorgabe ist P3; P1 muss ausdruecklich
    verlangt werden, damit niemand versehentlich dort landet.
    """
    wahl = (getattr(args, "scheibe", None) or "p3").lower()
    if wahl not in ("p1", "p3"):
        raise SystemExit("--scheibe erwartet p3 oder p1")
    if wahl == "p1":
        return True, f"DE ab {av.FIT_UNTIL_YEAR + 1}"
    return False, f"DE bis {av.FIT_UNTIL_YEAR}"

MONATSNAMEN = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli",
               "August", "September", "Oktober", "November", "Dezember"]


def schwellen_monat(jahr, tagindex):
    """Der Monat eines Kontrolltags aus Jahr und Tagesindex.

    Der Index kann durch die ±7-Tage-Streuung aus dem Jahr fallen; dann
    gehoert der Tag zum Nachbarjahr. Ihn auf den 31.12. zu klemmen waere
    ein stiller Dezember-Ueberschuss.
    """
    while tagindex < 0:
        jahr -= 1
        tagindex += 366 if av._leap(jahr) else 365
    laenge = 366 if av._leap(jahr) else 365
    while tagindex >= laenge:
        tagindex -= laenge
        jahr += 1
        laenge = 366 if av._leap(jahr) else 365
    return int(av._date_from_index(jahr, tagindex)[5:7])


def schwellen_tage(samples, optimum, sigma=None):
    """Die bewerteten Kontrolltage einer Art, je Fundjahr gebuendelt.

    Rueckgabe: {fundjahr: [(score, monat, gewicht), …]} mit Gewicht 1 je
    FUND — auf seine Kontrolltage verteilt. Ein Fund mit fuenf
    brauchbaren Jahren zaehlt damit genauso viel wie einer mit zweien;
    ohne das entschiede die Cache-Lage mit, welcher Ort die Schwelle
    zieht.
    """
    sigma = av.TEMP_SIGMA if sigma is None else sigma
    aus = {}
    for s in samples:
        tage = s.get("control_days")
        if tage is None:
            raise SystemExit(
                "Die Ziehung fuehrt keine Kontrolltage mit. "
                "`collect_pairs_b` muss `control_days` schreiben — "
                "ohne den Kalendertag gibt es keine Monatsspalte.")
        if not s["controls"]:
            continue
        anteil = 1.0 / len(s["controls"])
        for (regen, temp), jahr, tag in zip(s["controls"],
                                            s["control_years"], tage):
            aus.setdefault(s["year"], []).append(
                (av.ampel_score(regen, temp, optimum, sigma),
                 schwellen_monat(jahr, tag), anteil))
    return aus


def schwellen_funde(samples, optimum, sigma=None):
    """Dieselbe Buendelung fuer die FUNDTAGE — Gewicht 1 je Fund."""
    sigma = av.TEMP_SIGMA if sigma is None else sigma
    aus = {}
    for s in samples:
        aus.setdefault(s["year"], []).append(
            (av.ampel_score(*s["found"], optimum, sigma),
             schwellen_monat(s["year"], s.get("found_day", 0)), 1.0))
    return aus


def schwellen_gewichte(nach_jahr):
    """Jahresbalance und Artnormierung in einem Schritt.

    Zwei Regeln, beide aus `class_thresholds` uebernommen und beide mit
    demselben Grund: Stichprobengroesse soll nicht fuer Bedeutung
    einstehen.

    - **Jedes Fundjahr gleich schwer.** Ein gutes Pilzjahr liefert mehr
      Funde, mehr Kontrolltage — und zoege die Schwelle zu seinem
      Wetter.
    - **Jede Art gleich schwer.** Der Steinpilz bringt zehnmal so viele
      Funde mit wie die Herbsttrompete; ungewichtet waere die
      Klassenschwelle die Steinpilzschwelle mit anderem Namen.

    Rueckgabe: {jahr: [(score, monat, gewicht), …]} mit Gesamtgewicht 1
    ueber die ganze Art.
    """
    jahre = [j for j, eintraege in nach_jahr.items() if eintraege]
    if not jahre:
        return {}
    aus = {}
    for jahr in jahre:
        eintraege = nach_jahr[jahr]
        summe = sum(g for _, _, g in eintraege)
        if summe <= 0:
            continue
        faktor = 1.0 / (summe * len(jahre))
        aus[jahr] = [(w, m, g * faktor) for w, m, g in eintraege]
    return aus


def schwellen_block(eintraege):
    """Ein vorsortierter Block fuer die schnelle Quantil-Suche.

    Rueckgabe: (werte_sortiert, kumulierte_gewichte, summe).
    """
    paare = sorted((w, g) for w, _, g in eintraege)
    werte = [w for w, _ in paare]
    kum, laufend = [], 0.0
    for _, g in paare:
        laufend += g
        kum.append(laufend)
    return werte, kum, laufend


def quantil_bloecke(bloecke, q, kandidaten):
    """Gewichtetes Quantil ueber vorsortierte Bloecke.

    **Dieselbe Definition wie `av.quantile_at`**: der kleinste Wert, bis
    zu dem (einschliesslich) mindestens `q` der Gewichtsmasse liegt. Nur
    der Weg dorthin ist ein anderer — Bisektion ueber die Kandidatenwerte
    statt ein Durchlauf durch alle Punkte. Das ist der Unterschied
    zwischen einem Bootstrap in einer Minute und einem in einer Stunde;
    dass beide Wege dasselbe liefern, prueft der Selbsttest an
    Zufallsdaten nach.
    """
    gesamt = sum(s for _, _, s in bloecke)
    if gesamt <= 0 or not kandidaten:
        return None
    ziel = q * gesamt

    def masse_bis(wert):
        summe = 0.0
        for werte, kum, _ in bloecke:
            i = bisect.bisect_right(werte, wert)
            if i:
                summe += kum[i - 1]
        return summe

    lo, hi = 0, len(kandidaten) - 1
    if masse_bis(kandidaten[hi]) < ziel:
        return kandidaten[hi]
    while lo < hi:
        mitte = (lo + hi) // 2
        if masse_bis(kandidaten[mitte]) >= ziel:
            hi = mitte
        else:
            lo = mitte + 1
    return kandidaten[lo]


def schwellen_klasse(arten, quantile, rounds, seed):
    """Die beiden Schwellen einer Klasse, mit Jahres-Bootstrap.

    Gezogen werden FUNDJAHRE je Art, mit Zuruecklegen — dieselbe
    Gruppierung wie ueberall hier. Zwei Kontrolltage desselben Jahres
    sind einander aehnlicher als zwei aus verschiedenen Jahren; ueber
    Tage zu ziehen ergaebe ein Band, das zu schmal ist und deshalb luegt.
    """
    if not arten:
        return None
    alle = [(w, g) for art in arten for eintraege in art.values()
            for w, _, g in eintraege]
    if not alle:
        return None
    werte = [w for w, _ in alle]
    gewichte = [g for _, g in alle]
    # **Die Schlagzeilenzahl kommt aus `av.quantile_at` selbst**, nicht
    # aus der schnellen Fassung. Die ausgelieferten Schwellen sind mit
    # genau dieser Funktion entstanden; eine zweite Implementierung
    # daneben waere eine zweite Definition, und die Ruecknahme
    # „dieselbe Rechnung, andere Daten" waere hin.
    punkt = tuple(av.quantile_at(werte, gewichte, q) for q in quantile)

    kandidaten = sorted(set(werte))
    bloecke_je_art = [[schwellen_block(e) for e in art.values()]
                      for art in arten]
    rng = random.Random(seed)
    zuege = [[], []]
    for _ in range(rounds):
        gezogen = []
        for bloecke in bloecke_je_art:
            gezogen.extend(rng.choice(bloecke) for _ in bloecke)
        for i, q in enumerate(quantile):
            zuege[i].append(quantil_bloecke(gezogen, q, kandidaten))
    baender = []
    for spalte in zuege:
        spalte = [z for z in spalte if z is not None]
        if not spalte:
            baender.append(None)
            continue
        spalte.sort()
        baender.append((spalte[int(0.025 * len(spalte))],
                        spalte[min(len(spalte) - 1,
                                   int(0.975 * len(spalte)))]))
    return {"punkt": punkt, "band": baender, "n": len(alle)}


def schwellen_anteil(eintraege, grenze, monat=None):
    """Der Gewichtsanteil auf oder ueber [grenze], gegebenenfalls je Monat."""
    oben = unten = 0.0
    for wert, m, g in eintraege:
        if monat is not None and m != monat:
            continue
        unten += g
        if wert >= grenze:
            oben += g
    return None if unten <= 0 else oben / unten


# --- B aus Auftrag 3: H6, das Sommer-Optimum ------------------------------
#
# Registrierung: `docs/pilzampel-h6-vorpruefung.md`, vor diesem Code
# geschrieben. Was danach anders gemacht wurde, steht im Korrekturkasten
# des Berichts.

H6_ART = "Pfifferling"
H6_KLASSE = "sommer"
H6_OPTIMUM_ALT = 17.5

# Das Gitter der Vorpruefung — feiner und weiter als `FIT_GRID_*` in
# `ampel_validate.py` (dort −5 bis 20 in 0,5-K-Schritten). Weiter, weil
# die ausgelieferten 17,5 nicht am Rand liegen duerfen; feiner, weil die
# Streitfrage gut 4 K gross ist und eine halbe Stufe davon ein Achtel
# waere.
H6_GITTER_VON, H6_GITTER_BIS, H6_GITTER_SCHRITT = 5.0, 25.0, 0.25

# Ein Plateau: alle Optima, die weniger als so viel unter dem besten
# liegen. Dieselbe Zahl wie `grid_optimum` in `ampel_validate.py`.
H6_PLATEAU = 0.005

H6_V1_MAX_ABWEICHUNG = 1.0
H6_HAELFTEN = ((2006, 2012), (2013, 2018))


def h6_gitterwerte():
    """Die Stuetzstellen des Optimum-Gitters."""
    n = int(round((H6_GITTER_BIS - H6_GITTER_VON) / H6_GITTER_SCHRITT))
    return [round(H6_GITTER_VON + i * H6_GITTER_SCHRITT, 4)
            for i in range(n + 1)]


def h6_tabelle(samples):
    """Je Optimum und Fundjahr die Summe der Anteile und ihre Zahl.

    **Das ist der ganze Grund, warum der Bootstrap in Sekunden laeuft.**
    Der Anteil geschlagener Kontrolljahre haengt ausschliesslich an
    EINEM Fund; ein Zug, der Fundjahre zieht, mittelt also ueber eine
    feste Zahlenliste. Einmal 81 Optima x 716 Funde vorrechnen kostet
    so viel wie ein einziger naiver Zug — und danach ist jeder weitere
    Zug eine Addition ueber 13 Jahre.
    """
    tabelle = {}
    for optimum in h6_gitterwerte():
        gruppen = _fractions(samples, optimum, lambda s: s["year"])
        tabelle[optimum] = {jahr: (sum(werte), len(werte))
                            for jahr, werte in gruppen.items()}
    return tabelle


def h6_b_aus_tabelle(tabelle, optimum, jahre):
    """Das B-Mass eines Optimums ueber eine Jahresliste (mit Wiederholung)."""
    summe = anzahl = 0.0
    je_jahr = tabelle[optimum]
    for jahr in jahre:
        if jahr in je_jahr:
            s, n = je_jahr[jahr]
            summe += s
            anzahl += n
    return summe / anzahl if anzahl else None


def h6_gitter_optimum(tabelle, jahre):
    """Das Optimum, das das B-Mass maximiert — samt Plateau.

    **Bei Gleichstand die Mitte, nicht das erste.** Zwei Optima ordnen
    ein Paar nur dann verschieden, wenn sie auf verschiedenen Seiten
    seines Mittelpunkts liegen; gleich gute Optima kommen deshalb in
    Bloecken, und der linke Rand eines Blocks ist keine Schaetzung,
    sondern eine Eigenschaft der Gitterweite. Dieselbe Regel wie in
    `av.grid_optimum`.
    """
    werte = [(o, h6_b_aus_tabelle(tabelle, o, jahre))
             for o in h6_gitterwerte()]
    werte = [(o, b) for o, b in werte if b is not None]
    if not werte:
        return None
    best = max(b for _, b in werte)
    gleich = [o for o, b in werte if b >= best - 1e-12]
    plateau = [o for o, b in werte if b >= best - H6_PLATEAU]
    return {"optimum": (gleich[0] + gleich[-1]) / 2, "b": best,
            "plateau": (min(plateau), max(plateau)),
            "plateau_breite": max(plateau) - min(plateau)}


def h6_gitter_se(tabelle, jahre, rounds, seed):
    """Der Standardfehler des Gitter-Optimums aus dem Jahres-Bootstrap.

    Gezogen werden Fundjahre mit Zuruecklegen — dieselbe Gruppe wie bei
    jedem Bootstrap dieser Arbeit. Zurueck kommen Standardabweichung und
    95-%-Band; das Band steht daneben, weil eine Verteilung ueber einem
    Gitter schief sein kann und die Standardabweichung das dann
    verschweigt.
    """
    present = sorted(jahre)
    if len(present) < 2:
        return None
    rng = random.Random(seed)
    zuege = []
    for _ in range(rounds):
        gezogen = [rng.choice(present) for _ in present]
        got = h6_gitter_optimum(tabelle, gezogen)
        if got:
            zuege.append(got["optimum"])
    if len(zuege) < 2:
        return None
    zuege.sort()
    return {"se": statistics.stdev(zuege),
            "band": (zuege[int(0.025 * len(zuege))],
                     zuege[min(len(zuege) - 1, int(0.975 * len(zuege)))]),
            "n": len(zuege)}


def h6_logit(samples):
    """Das Optimum per bedingtem Logit, cluster-robust ueber Fundjahre."""
    strata, jahre, abgeschnitten, gesamt = logit_strata(samples)
    if len(strata) < 30:
        return {"optimum": None, "grund": f"nur {len(strata)} Strata"}
    fit = ampel_logit.fit_conditional_logit(strata, cluster=jahre)
    got = ampel_logit.bell_from_beta(fit["beta"], fit["kovarianz"])
    got.update({"strata": len(strata), "konvergiert": fit["konvergiert"],
                "abgeschnitten": abgeschnitten, "gesamt": gesamt,
                "gruppen": len(set(jahre))})
    return got


def h6_diskordanz(samples, alt, neu):
    """Wie oft ordnen altes und neues Optimum ein B-Paar verschieden?

    Zurueck kommen zwei Zahlen. Der **Diskordanzanteil** ist der Anteil
    der Vergleiche, bei denen sich der Beitrag ueberhaupt aendert — das
    ist die Obergrenze aus der Registrierung. Die **mittlere Aenderung**
    ist die schaerfere Schranke: Ein Vergleich, der von „geschlagen" auf
    „gleich" kippt, verschiebt nur um einen halben Punkt, nicht um einen
    ganzen.
    """
    s_alt = lambda regen, temp: av.ampel_score(regen, temp, alt)
    s_neu = lambda regen, temp: av.ampel_score(regen, temp, neu)
    anders = aenderung = paare = 0
    for s in samples:
        fa, fn = s_alt(*s["found"]), s_neu(*s["found"])
        for c in s["controls"]:
            ba = 1.0 if fa > s_alt(*c) else (0.5 if fa == s_alt(*c) else 0.0)
            bn = 1.0 if fn > s_neu(*c) else (0.5 if fn == s_neu(*c) else 0.0)
            paare += 1
            if ba != bn:
                anders += 1
                aenderung += abs(bn - ba)
    if not paare:
        return None
    return {"anteil": anders / paare, "mittlere_aenderung": aenderung / paare,
            "paare": paare}


def h6_delta_bootstrap(samples, alt, neu, rounds, seed):
    """Jahres-Bootstrap der DIFFERENZ je Zug — nicht zweier Baender.

    Bewertet werden in jedem Zug **dieselben** Funde zweimal. Zwei
    getrennte Baender wuerfen die Paarung weg und ueberschaetzen die
    Streuung; der Unterschied ist genau das, was der Test sehen soll.
    """
    a = _fractions(samples, alt, lambda s: s["year"])
    n = _fractions(samples, neu, lambda s: s["year"])
    jahre = sorted(set(a) & set(n))
    if len(jahre) < 2:
        return None
    # Je Jahr die Summe der DIFFERENZEN und die Zahl der Funde.
    je_jahr = {}
    for jahr in jahre:
        paare = list(zip(a[jahr], n[jahr]))
        je_jahr[jahr] = (sum(y - x for x, y in paare), len(paare))
    rng = random.Random(seed)
    zuege = []
    for _ in range(rounds):
        summe = anzahl = 0.0
        for _ in jahre:
            s, k = je_jahr[rng.choice(jahre)]
            summe += s
            anzahl += k
        if anzahl:
            zuege.append(summe / anzahl)
    if len(zuege) < 2:
        return None
    punkt = sum(je_jahr[j][0] for j in jahre) / sum(
        je_jahr[j][1] for j in jahre)
    zuege.sort()
    se = statistics.stdev(zuege)
    return {"delta": punkt, "se": se, "mde": MDE_FAKTOR * se,
            "band": (zuege[int(0.025 * len(zuege))],
                     zuege[min(len(zuege) - 1, int(0.975 * len(zuege)))]),
            "n": len(zuege)}


def h6_urteil(v1, v2, v3, v4):
    """Die vier Bedingungen aus der Registrierung.

    `None` heisst **nicht auswertbar** und faellt wie ein Nein aus: Ein
    Kriterium, das man nicht pruefen kann, ist keines, das man bestanden
    hat (Registrierung, Abschnitt V2).
    """
    bed = {
        "wege_einig": (v1 is not None
                       and v1["abstand"] <= H6_V1_MAX_ABWEICHUNG),
        "stabil": v2 is not None and v2.get("drift") is not None
        and v2.get("se_ganz") is not None
        and v2["drift"] <= v2["se_ganz"],
        "aufloesung": (v4 is not None and v3 is not None
                       and v4["mde"] < v3["anteil"]),
    }
    urteil = ("H6 wird registriert" if all(bed.values())
              else "H6 wird NICHT registriert")
    return {"urteil": urteil, "bedingungen": bed}


# --- H6, der registrierte Prueflauf --------------------------------------
#
# Registrierung: `docs/pilzampel-h6-registrierung.md`.

H6_OPTIMUM_NEU = 14.0
# Die Gegenprobe in die ANDERE Richtung (Auftrag 3 B). Verbessert eine
# Verschiebung nach oben UND nach unten das Mass, misst der Aufbau nicht
# das Optimum — dann ist jedes Δ wertlos, auch ein schoenes.
H6_OPTIMUM_GEGEN = 20.0
H6_MIN_GAIN = 0.010
H6_MIN_JAHR_ANTEIL = 0.70
H6_ACHSE = ("AT", "CH")


def h6_paare(samples, alt, neu, nur=None):
    """Je Fundjahr die Paare (B_alt, B_neu) — DERSELBE Fund zweimal.

    Die tragende Festlegung des Tests, wortgleich mit H1: Gezogen wird
    einmal, bewertet zweimal. Zwei Ziehungen machten den Unterschied
    teils zur Stichprobe.
    """
    s_alt = h1_scorer(alt, av.TEMP_SIGMA, nur)
    s_neu = h1_scorer(neu, av.TEMP_SIGMA, nur)
    jahre = {}
    for s in samples:
        controls = s.get("controls") or []
        if not controls:
            continue
        a = ab.beat_fraction(s_alt(*s["found"]), [s_alt(*c) for c in controls])
        n = ab.beat_fraction(s_neu(*s["found"]), [s_neu(*c) for c in controls])
        if a is None or n is None:
            continue
        jahre.setdefault(s["year"], []).append((a, n))
    return jahre


def h6_delta(samples, alt, neu, rounds=BOOTSTRAP_ROUNDS_B, seed=42,
             nur=None):
    """Δ = B(neu) − B(alt), mit Band, p-Wert und Jahresanteil."""
    jahre = h6_paare(samples, alt, neu, nur)
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

    # Duenne Jahre tragen kein Vorzeichen — dieselbe Grenze wie bei H1.
    gezaehlt = besser = 0
    for name in namen:
        werte = jahre[name]
        if len(werte) < H1_MIN_JAHR_FUNDE:
            continue
        gezaehlt += 1
        if (sum(n - a for a, n in werte) / len(werte)) > 0:
            besser += 1
    se = None
    if band is not None:
        # Aus dem Band zurueckgerechnet: die halbe Breite ist 1,96 SE.
        se = (band[1] - band[0]) / (2 * 1.959964)
    return {
        "b_alt": b_alt, "b_neu": b_neu, "delta": b_neu - b_alt,
        "band": band, "n": len(flach), "se": se,
        "mde": None if se is None else MDE_FAKTOR * se,
        "jahre": gezaehlt, "jahre_besser": besser,
        "jahr_anteil": besser / gezaehlt if gezaehlt else None,
    }


def h6_latte(delta):
    """Die Latte aus der gemessenen Aufloesung — Mindestwert aus dem Auftrag.

    Ein Standardfehler haengt nicht am Ergebnis; die Latte bewegt sich
    also nicht mit ihm. Fehlt die Aufloesung, bleibt der Mindestwert.
    """
    if delta is None or delta.get("mde") is None:
        return H6_MIN_GAIN
    return max(H6_MIN_GAIN, delta["mde"])


def h6_test_urteil(delta, gegen, placebo, placebo_n):
    """Die vier Bedingungen aus Abschnitt 6 der Registrierung — plus die
    Gegenprobe aus Abschnitt 7.

    `None` faellt wie ein Nein aus: Eine fehlende Zahl darf nicht
    entscheiden wie eine gemessene.
    """
    latte = h6_latte(delta)
    bed = {
        "gewinn": delta is not None and delta["delta"] >= latte,
        "band": (delta is not None and delta["band"] is not None
                 and delta["band"][2] < P_GRENZE),
        "jahre": (delta is not None and delta["jahr_anteil"] is not None
                  and delta["jahr_anteil"] >= H6_MIN_JAHR_ANTEIL),
        "placebo": (placebo is not None
                    and av.control_clean(placebo, placebo_n)),
    }
    # **Die Gegenprobe kann nur kippen, nicht herstellen.** Schlaegt eine
    # Verschiebung in die ANDERE Richtung genauso an, misst der Aufbau
    # nicht das Optimum — und dann ist auch ein schoenes Δ wertlos.
    bed["gegenprobe"] = not (
        gegen is not None and gegen["delta"] >= H6_MIN_GAIN
        and gegen["band"] is not None and gegen["band"][2] < P_GRENZE)
    urteil = ("H6 bestanden" if all(bed.values())
              else "H6 nicht bestanden")
    return {"urteil": urteil, "bedingungen": bed, "latte": latte}


# Die Bedingungen, unter denen die ausgelieferten Schwellen gemessen
# wurden. Nur unter genau diesen darf der Waechter abbrechen — auf einer
# anderen Messbasis oder ohne Entdoppeln MUESSEN die Zahlen abweichen,
# und ein Abbruch waere dann der Waechter, den man nach dem zweiten Mal
# abschaltet (dieselbe Lehre wie bei `verify_class_constants`).
SCHWELLEN_HERKUNFT = {"dataset": "pinned", "dedupe": True, "seed": 42,
                      "scheibe": "p1"}


def verify_schwellen_konstanten(ergebnis, args, auf_p1):
    """Die vier ausgelieferten Schwellen gegen die Daten, die sie gesetzt haben.

    Seit dem 2026-09-19 stammen sie aus Design B auf P1 (Auftrag 3 A).
    Genagelt werden sie deshalb hier und nicht mehr in
    `class_thresholds`: Ein Waechter gehoert dorthin, wo die Zahl
    herkommt, sonst vergleicht er zwei verschiedene Groessen.

    **Alle Abweichungen auf einmal** — ein geaendertes Quantil
    verschiebt beide Stufen einer Klasse, es gibt also selten nur eine,
    und jede kostete sonst einen eigenen Lauf.
    """
    passt = (auf_p1 and args.dataset == SCHWELLEN_HERKUNFT["dataset"]
             and bool(args.dedupe) == SCHWELLEN_HERKUNFT["dedupe"]
             and args.seed == SCHWELLEN_HERKUNFT["seed"]
             and not args.only)
    funde = []
    for key, got in ergebnis.items():
        if not got or not got.get("b"):
            continue
        klass = av.AMPEL_CLASSES[key]
        for i, feld in enumerate(("verhalten", "guenstig")):
            erwartet = klass.get(feld)
            gemessen = round(got["b"]["punkt"][i], 3)
            if erwartet is not None and gemessen != erwartet:
                funde.append(f"  {key}.{feld}: gemessen {gemessen}, "
                             f"Konstante {erwartet}")
    if not funde:
        return
    text = "\n".join(funde)
    if not passt:
        print("\nSchwellen weichen ab — erwartet, denn dieser Lauf hat "
              "nicht die Herkunftsbedingungen "
              f"({SCHWELLEN_HERKUNFT}):\n{text}", file=sys.stderr)
        return
    raise SystemExit(
        "Die ausgelieferten Schwellen passen nicht mehr zu den Daten, "
        f"die sie gesetzt haben:\n{text}\n\n"
        "Konstante, Bericht UND ampel_model.dart gehoeren zusammen neu "
        "gesetzt — nicht einzeln. Die Spiegelpruefung in "
        "`ampel_validate.py --self-test` haelt die beiden Codeseiten "
        "zusammen, diese hier haelt sie an den Daten.")


def run_schwellen(args):
    """A aus Auftrag 3 — die Schwellen an Design-B-Kontrolltagen.

    Kostet keine Pruefachse: gerechnet wird auf DE bis `FIT_UNTIL_YEAR`.
    """
    if args.api:
        av.OPEN_METEO = args.api.rstrip("/")
    av.DEDUPE = args.dedupe
    av.use_dataset(args.dataset)
    auf_p1, scheibe = schwellen_scheibe(args)
    print(f"Schwellen auf {scheibe} — "
          + ("Pruefjahre, als DIAGNOSE (Schwelle und Rang sind disjunkt)"
             if auf_p1 else "Anpassjahre, keine Pruefachse"),
          file=sys.stderr)
    if auf_p1:
        print("  schwellenabhaengige Guetemasse sind hier gesperrt: "
              + ", ".join(P1_GESPERRTE_MASSE), file=sys.stderr)
    print("Auftrag: docs/pilzampel-auftrag-3.md, Abschnitt A",
          file=sys.stderr)

    mapping = av.read_species()
    wanted = SCHWELLEN_ARTEN
    if args.only:
        gesucht = {n.strip() for n in args.only.split(",") if n.strip()}
        wanted = [z for z in SCHWELLEN_ARTEN if z[0] in gesucht]

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
        samples = [z for z in gezogen["samples"]
                   if (z["year"] > av.FIT_UNTIL_YEAR) == auf_p1]
        if len(samples) < SCHWELLEN_MIN_FUNDE:
            print(f"    zu duenn: {len(samples)} Funde", file=sys.stderr)
            continue
        tage_b = schwellen_gewichte(schwellen_tage(samples, optimum))
        # **Auf P1 werden die Fundtage nicht einmal bewertet.** Ihr
        # Anteil ueber der Schwelle IST die Trefferquote; sie hier zu
        # rechnen und nur nicht zu drucken waere derselbe Fehler, eine
        # Datei weiter.
        funde_b = ({} if auf_p1
                   else schwellen_gewichte(schwellen_funde(samples,
                                                           optimum)))

        # **Die Bruecke: dasselbe auf Design A, gleiche Zeitscheibe.**
        # Ohne sie waere der Unterschied zur ausgelieferten Zahl teils
        # das Design und teils die Jahre, und niemand koennte sagen,
        # welcher Teil welcher ist.
        tage_a = {}
        gezogen_a = (None if auf_p1 else
                     av.collect_pairs(name, sci, cache_dir=args.cache,
                                      seed=args.seed, progress=False))
        if gezogen_a:
            roh = {}
            for s in gezogen_a["samples"]:
                if s["year"] > av.FIT_UNTIL_YEAR:
                    continue
                roh.setdefault(s["year"], []).append(
                    (av.ampel_score(*s["control"], optimum), 0, 1.0))
            tage_a = schwellen_gewichte(roh)

        zeilen.append({
            "name": name, "gruppe": gruppe, "optimum": optimum,
            "n": len(samples), "duenn": len(samples) < MIN_FINDS_B,
            "n_tage": sum(len(e) for e in tage_b.values()),
            "jahre": len(tage_b),
            "tage_b": tage_b, "funde_b": funde_b, "tage_a": tage_a,
            "n_a": sum(len(e) for e in tage_a.values()),
        })
        print(f"    {len(samples)} Funde, "
              f"{sum(len(e) for e in tage_b.values())} Kontrolltage, "
              f"{len(tage_a)} Jahre in Design A", file=sys.stderr)

    ergebnis = {}
    for key in ("herbst", "sommer"):
        mitglieder = [z for z in zeilen if z["gruppe"] == key]
        if not mitglieder:
            continue
        ergebnis[key] = {
            "mitglieder": [z["name"] for z in mitglieder],
            "b": schwellen_klasse([z["tage_b"] for z in mitglieder],
                                  SCHWELLEN_QUANTILE, SCHWELLEN_ROUNDS,
                                  args.seed),
            "a": schwellen_klasse([z["tage_a"] for z in mitglieder
                                   if z["tage_a"]],
                                  SCHWELLEN_QUANTILE, 0, args.seed),
            # **Traegt eine einzelne Art die Zahl?** Ohne diese Spalte
            # ist die Gewichtungsregel „jede Art gleich schwer“ eine
            # Behauptung ueber den Code und keine ueber das Ergebnis.
            "ohne": {z["name"]: schwellen_klasse(
                [m["tage_b"] for m in mitglieder if m is not z],
                SCHWELLEN_QUANTILE, 0, args.seed) for z in mitglieder},
        }
        got = ergebnis[key]["b"]
        if got:
            print(f"  {key}: verhalten {got['punkt'][0]:.3f}  "
                  f"guenstig {got['punkt'][1]:.3f}", file=sys.stderr)

    verify_schwellen_konstanten(ergebnis, args, auf_p1)
    bericht = render_schwellen(zeilen, ergebnis, auf_p1, scheibe)
    if args.out:
        open(args.out, "w", encoding="utf-8").write(bericht)
        print(f"\n{args.out} geschrieben", file=sys.stderr)
    else:
        print(bericht)


def _sp(value, digits=1):
    """Prozent mit deutschem Komma."""
    return "—" if value is None else f"{value * 100:.{digits}f} %".replace(
        ".", ",")


def _spanne(band):
    if not band:
        return "—"
    return f"[{_fmt(band[0])}, {_fmt(band[1])}]"


def render_schwellen(zeilen, ergebnis, auf_p1=False, scheibe=None):
    """Der Bericht zu A — eine Vorlage, keine Uebernahme."""
    import time as _t
    AUF, ZU = "„", "“"

    def z(text):
        """Deutsche Anfuehrungszeichen, ohne sie im Quelltext zu tippen."""
        return AUF + text + ZU

    aus = []
    w = aus.append
    w("# Die Schwellen aus Design B — Vorlage, nicht Übernahme\n")
    w(f"Stand: {_t.strftime('%Y-%m-%d')} · Erzeugt von "
      "`tool/ampel_diagnose.py --schwellen"
      + (" --scheibe p1" if auf_p1 else "") + "` · Auftrag: "
      "`docs/pilzampel-auftrag-3.md`, Abschnitt A · Zeitscheibe: "
      f"**{scheibe or 'P3'}**\n")
    if auf_p1:
        w("> **Diagnose, kein Prüflauf.** Schwelle und gepaarte AUC sind "
          "disjunkte Statistiken: Die AUC ist rangbasiert und von jeder "
          "Schwelle unabhängig. Hier wird eine Verteilung beschrieben, "
          "nicht ausgewählt — es gibt keine Latte, kein Band und nichts "
          "zu bestehen. **Schwellenabhängige Gütemaße sind auf dieser "
          "Scheibe gesperrt** (" + ", ".join(P1_GESPERRTE_MASSE) + "); "
          "sie stehen im P3-Bericht.\n")
    w("> **Diese Datei wird erzeugt.** Wer sie von Hand ändert, verliert "
      "die Änderung beim nächsten Lauf.\n")

    w("## Was hier gefragt wird\n")
    w("Die vier ausgelieferten Schwellen sind **Quantile der "
      "Score-Verteilung an Vergleichstagen**. Sie entscheiden nicht, wie "
      "gut die Ampel trennt, sondern **wie oft sie " + z("günstig")
      + " sagt**. Das ist eine Häufigkeitsfrage, und die Antwort hängt "
      "daran, welche Tage man " + z("üblich") + " nennt.\n")
    w("Gesetzt wurden sie an **Design-A-Vergleichstagen**: ein anderer "
      "Tag derselben Saison, 26 bis 45 Tage neben dem Fund, im selben "
      "Jahr. Phase 1.5 hat gemessen, dass in dieser Paarung bei den "
      "Herbstarten rund 0,09 AUC Kalender stecken. Was in der "
      "Trennschärfe steckt, steckt auch in der Verteilung, aus der die "
      "Schwelle gezogen wurde.\n")
    w("**Design B fragt dasselbe an einem anderen Tag:** gleicher Ort, "
      "gleiches Datum, anderes Jahr. Die Verteilung heißt dann "
      + z("wie ist das Wetter hier um diese Zeit üblich") + " — und "
      "genau das ist die Bezugsgröße, die zur Aussage "
      + z("heute ist es ungewöhnlich gut") + " gehört.\n")

    w("## Wie gemessen wurde\n")
    w("Vor dem Lauf festgelegt (`tool/ampel_diagnose.py`, Abschnitt "
      + z("A aus Auftrag 3") + "):\n")
    if auf_p1:
        w(f"- **Gerechnet wird auf P1** — Deutschland ab "
          f"{av.FIT_UNTIL_YEAR + 1}, also die Jahre, in denen die App "
          "benutzt wird. Das ist die Scheibe, für die eine "
          "ausgelieferte Schwelle gelten soll.")
    else:
        w(f"- **Gerechnet wird auf P3** — Deutschland bis "
          f"{av.FIT_UNTIL_YEAR}. Das sind die Anpassjahre; der Lauf "
          "verbraucht keine Prüfachse.")
    w("- **Bewertet wird mit dem ausgelieferten Fenster** der Klasse "
      "(13,0 °C bzw. 17,5 °C) und σ = 5,0 K. Hier geht es um die "
      "Schwelle, nicht um das Fenster — das ist H6.")
    w(f"- **Die Quantile bleiben {_sp(SCHWELLEN_QUANTILE[0], 0)} und "
      f"{_sp(SCHWELLEN_QUANTILE[1], 0)}**, die Auslieferungsquantile vom "
      "2026-09-12 (" + z("gleich häufig wie bisher") + "). Gefragt ist, "
      "welche ZAHL dasselbe Quantil in Design B trägt.")
    w("- **Jedes Fundjahr gleich schwer, jede Art gleich schwer** — "
      "dieselben zwei Regeln wie in `class_thresholds`, aus demselben "
      "Grund: Stichprobengröße soll nicht für Bedeutung einstehen.")
    w("- **Ein Fund zählt einmal**, nicht einmal je Kontrolljahr. Wer "
      "fünf brauchbare Jahre hat, verteilt sein Gewicht darauf.")
    w(f"- **Das Band ist ein Jahres-Bootstrap** über Fundjahre, "
      f"{SCHWELLEN_ROUNDS} Züge. Es ist eine Auskunft über die "
      "Genauigkeit, keine Entscheidungsgrundlage.\n")

    w("## Korrekturkasten\n")
    w("**Eine Methodenentscheidung ist nach der Datensicht gefallen** "
      "und steht deshalb hier, nicht oben.\n")
    w(f"Der erste Lauf benutzte `MIN_FINDS_B` ({MIN_FINDS_B} Funde) als "
      "Untergrenze. Damit fiel die Herbsttrompete mit 147 Funden aus "
      "der Klasse heraus, und die Klassenschwelle haette auf vier statt "
      "fünf Mitgliedern geruht — obwohl die App sie für fünf "
      "ausliefert.\n")
    w("Die beiden Grenzen messen nicht dasselbe. `MIN_FINDS_B` "
      "entscheidet, ob eine Art ein URTEIL trägt: Dort steht eine "
      "einzelne Zahl gegen eine Latte, und eine dünne Zahl darf das "
      "nicht. Hier steuert eine Art ein Fünftel zu einem Quantil bei, "
      "das mit vier anderen gemittelt wird. **Die Fehlerrichtung ist "
      "umgekehrt** — eine ausgelieferte Art wegzulassen verzerrt die "
      "Schwelle sicher, sie mit 147 Funden mitzunehmen nur "
      f"vielleicht. Die Grenze für den Beitrag zu einem Quantil steht "
      f"deshalb bei {SCHWELLEN_MIN_FUNDE}.\n")
    w("Damit das keine Ausrede bleibt, steht unten eine "
      "**Leave-one-out-Spalte**: was die Schwelle wäre, wenn genau "
      "diese Art fehlte.\n")

    w("## Das Material\n")
    spalte_a = "" if auf_p1 else " Design-A-Jahre |"
    w(f"| Art | Klasse | Funde | Kontrolltage | Fundjahre |{spalte_a}")
    w("|---|---|--:|--:|--:|" + ("" if auf_p1 else "--:|"))
    for row in zeilen:
        w(f"| {row['name']}{' ⚠' if row['duenn'] else ''} | "
          f"{av.AMPEL_CLASSES[row['gruppe']]['label']} | "
          f"{row['n']} | {row['n_tage']} | {row['jahre']} |"
          + ("" if auf_p1 else f" {len(row['tage_a'])} |"))
    if any(row["duenn"] for row in zeilen):
        w(f"\n⚠ unter {MIN_FINDS_B} Funden — trägt kein eigenes Urteil, "
          "steuert aber zum Klassenquantil bei (Korrekturkasten).")

    w("\n## Die Schwellen je Klasse\n")
    if auf_p1:
        w("Die auslieferbare Zahl: dasselbe Design wie im P3-Bericht, "
          "aber die Jahre, in denen die App läuft.\n")
        w("| Klasse | Stufe | ausgeliefert | Design B auf P1 | 95 % |")
        w("|---|---|--:|--:|---|")
    else:
        w("Drei Zellen. Die erste ist die App von heute, die zweite "
          "trennt die Zeitscheibe vom Design ab, die dritte ist die "
          "gefragte Zahl.\n")
        w("| Klasse | Stufe | ausgeliefert (A, P1) | Design A auf P3 | "
          "Design B auf P3 | 95 % |")
        w("|---|---|--:|--:|--:|---|")
    for key in ("herbst", "sommer"):
        if key not in ergebnis:
            continue
        klass = av.AMPEL_CLASSES[key]
        got = ergebnis[key]
        for i, stufe in enumerate(("verhalten", "günstig")):
            alt = schwelle_vorher(key, i)
            a = got["a"]["punkt"][i] if got["a"] else None
            b = got["b"]["punkt"][i] if got["b"] else None
            band = got["b"]["band"][i] if got["b"] else None
            mitte = "" if auf_p1 else f"{_fmt(a)} | "
            w(f"| {klass['label'] if i == 0 else ''} | {stufe} | "
              f"{alt:.3f} | {mitte}{_fmt(b)} | {_spanne(band)} |")

    if not auf_p1:
        w("\n### Woher der Unterschied kommt\n")
        w("| Klasse | Stufe | Zeitscheibe (A: P1 → P3) | "
          "Design (P3: A → B) | gesamt |")
        w("|---|---|--:|--:|--:|")
        for key in ("herbst", "sommer"):
            if key not in ergebnis:
                continue
            klass = av.AMPEL_CLASSES[key]
            got = ergebnis[key]
            for i, stufe in enumerate(("verhalten", "günstig")):
                alt = schwelle_vorher(key, i)
                a = got["a"]["punkt"][i] if got["a"] else None
                b = got["b"]["punkt"][i] if got["b"] else None
                w(f"| {klass['label'] if i == 0 else ''} | {stufe} | "
                  f"{_signed(None if a is None else a - alt)} | "
                  f"{_signed(None if (a is None or b is None) else b - a)} | "
                  f"{_signed(None if b is None else b - alt)} |")
        w("")
        w("**Die Zeitscheiben-Spalte ist kein Nebeneffekt.** Die "
          "ausgelieferten Zahlen stammen mit Absicht aus den Prüfjahren "
          "— für die Auslieferung zählt, wo die App HEUTE steht "
          "(`docs/pilzampel-schwellen-messung.md`). Eine auf P3 "
          "gemessene Schwelle beantwortet "
          + z("was war 2006 bis 2018 üblich") + ", nicht "
          + z("was ist heute üblich") + ". Und zwischen beiden Scheiben "
          "liegt nachweislich etwas: Dieselbe feste Zahl wurde vor 2019 "
          "an rund 30 %, danach an rund 20 % der Vergleichstage "
          "überschritten (`docs/pilzampel-schwellen-messung.md`), und "
          "die Glocke trennt in den Prüfjahren schwächer als in den "
          "Anpassjahren (`docs/pilzampel-alterung.md`).\n")

    w("### Trägt eine einzelne Art die Zahl?\n")
    w("Die Klassenschwelle, jeweils **ohne** ein Mitglied. Bei fünf "
      "Mitgliedern verschiebt das Weglassen eines Fünftels die Zahl "
      "immer ein wenig; interessant ist nur, ob eine Art heraussticht.\n")
    w("| Klasse | ohne … | verhalten | günstig |")
    w("|---|---|--:|--:|")
    for key in ("herbst", "sommer"):
        if key not in ergebnis or not ergebnis[key].get("ohne"):
            continue
        klass = av.AMPEL_CLASSES[key]
        erste = True
        for name, got in ergebnis[key]["ohne"].items():
            if not got:
                continue
            w(f"| {klass['label'] if erste else ''} | {name} | "
              f"{_fmt(got['punkt'][0])} | {_fmt(got['punkt'][1])} |")
            erste = False
    w("")

    w("## Was sich für Nutzer ändert\n")
    w("Gemessen an denselben Design-B-Kontrolltagen. " + z("Kontrolltage")
      + " sind Tage an Pilzorten in der Fruchtzeit der Art — also die "
      "Tage, an denen jemand die App aufmacht, ohne dass etwas "
      "Besonderes wäre.\n")

    def _flach(feld, row):
        return [e for eintraege in row[feld].values() for e in eintraege]

    if auf_p1:
        # **Hier steht mit Absicht keine Fundtagsspalte.** Ihr Anteil
        # ueber der Schwelle ist die Trefferquote, und die ist auf P1
        # gesperrt (Regel vom 2026-09-19). Der Riegel steht trotzdem
        # da: Wer die Spalte spaeter einbaut, laeuft in ihn hinein
        # statt an ihm vorbei.
        for row in zeilen:
            if row["funde_b"]:
                verbiete_schwellenmass(auf_p1, "Der Fundtag-Anteil")
        w("| Art | Kontrolltage günstig, alt → neu |")
        w("|---|--:|")
        for row in zeilen:
            got = ergebnis.get(row["gruppe"], {}).get("b")
            if not got:
                continue
            klass = av.AMPEL_CLASSES[row["gruppe"]]
            tage = _flach("tage_b", row)
            w(f"| {row['name']} | "
              f"{_sp(schwellen_anteil(tage, schwelle_vorher(row['gruppe'], 1)))} → "
              f"{_sp(schwellen_anteil(tage, got['punkt'][1]))} |")
        w("")
        w("**Die Fundtagsspalte fehlt hier mit Absicht.** Ihr Anteil "
          "über der Schwelle ist eine Trefferquote, und die ist auf "
          "dieser Scheibe gesperrt. Wie verlässlich der Hinweis ist, "
          "steht im P3-Bericht; was hier steht, ist allein, **wie oft** "
          "er erscheint.\n")
    else:
        w("Die erste Spalte ist die Probe aufs Exempel: Wie oft "
          "überschreitet die heutige Schwelle die Tage, an denen sie "
          "GESETZT wurde? Nahe 20 % heißt, dass die Zahl in ihrer "
          "eigenen Welt genau das tut, was sie soll — und dass der "
          "Sprung daneben wirklich vom Wechsel der Bezugstage kommt.\n")
        w("| Art | alt an A-Tagen | B-Tage günstig, alt → neu | "
          "Fundtage günstig, alt → neu | Hebel, alt → neu |")
        w("|---|--:|--:|--:|--:|")
        for row in zeilen:
            klass = av.AMPEL_CLASSES[row["gruppe"]]
            got = ergebnis.get(row["gruppe"], {}).get("b")
            if not got:
                continue
            neu_g = got["punkt"][1]
            tage = _flach("tage_b", row)
            funde = _flach("funde_b", row)
            a_tage = _flach("tage_a", row)
            aa = schwellen_anteil(a_tage, schwelle_vorher(row["gruppe"], 1)) if a_tage else None
            ka = schwellen_anteil(tage, schwelle_vorher(row["gruppe"], 1))
            kn = schwellen_anteil(tage, neu_g)
            fa = schwellen_anteil(funde, schwelle_vorher(row["gruppe"], 1))
            fn = schwellen_anteil(funde, neu_g)

            def hebel(oben, unten):
                if oben is None or not unten:
                    return "—"
                return f"{oben / unten:.2f}".replace(".", ",")

            w(f"| {row['name']} | {_sp(aa)} | {_sp(ka)} → {_sp(kn)} | "
              f"{_sp(fa)} → {_sp(fn)} | "
              f"{hebel(fa, ka)} → {hebel(fn, kn)} |")
        w("")
        w("**Der Hebel ist die Spalte, die entscheidet, ob eine "
          "Schwelle besser ist.** Er sagt, um welchen Faktor ein "
          "Fundtag wahrscheinlicher günstig ist als ein gewöhnlicher "
          "Tag. Ein seltenerer Hinweis ist nicht von selbst ein "
          "besserer: Wer die Latte hebt, senkt beide Raten, und der "
          "Abstand in Prozentpunkten schrumpft mit. Bleibt der Hebel "
          "gleich, ist die neue Schwelle **dieselbe Aussage an einer "
          "anderen Stelle** — eine Frage der Häufigkeit, wie Abschnitt "
          "A von Auftrag 3 sie nennt, und keine der Trennschärfe.\n")

    w("\n### Je Monat\n")
    w("Anteil der Kontrolltage, an denen die Ampel **günstig** stünde. "
      "Monate unter 5 % des Materials einer Art stehen nicht da — dort "
      "wäre die Zahl ein Gerücht.\n")
    w("| Art | Monat | Anteil des Materials | alt | neu |")
    w("|---|---|--:|--:|--:|")
    for row in zeilen:
        klass = av.AMPEL_CLASSES[row["gruppe"]]
        got = ergebnis.get(row["gruppe"], {}).get("b")
        if not got:
            continue
        neu = got["punkt"][1]
        tage = [e for eintraege in row["tage_b"].values() for e in eintraege]
        gesamt = sum(g for _, _, g in tage)
        erste = True
        for monat in range(1, 13):
            anteil = sum(g for _, m, g in tage if m == monat)
            if gesamt <= 0 or anteil / gesamt < 0.05:
                continue
            w(f"| {row['name'] if erste else ''} | "
              f"{MONATSNAMEN[monat - 1]} | {_sp(anteil / gesamt, 0)} | "
              f"{_sp(schwellen_anteil(tage, schwelle_vorher(row['gruppe'], 1), monat))} | "
              f"{_sp(schwellen_anteil(tage, neu, monat))} |")
            erste = False

    # **Die Oktober-Zeile** (Betreiberauflage 2026-09-19): Das ist die
    # Zahl, an der ein Betreiber entscheidet — nicht die Schwelle
    # selbst, sondern wieviele grüne Tage sie im wichtigsten Monat
    # kostet. Gerechnet, nicht geschätzt, und je Art gleich gewichtet.
    okt_alt, okt_neu, okt_arten = [], [], []
    for row in zeilen:
        got = ergebnis.get(row["gruppe"], {}).get("b")
        if not got:
            continue
        tage = [e for eintraege in row["tage_b"].values() for e in eintraege]
        a = schwellen_anteil(tage, schwelle_vorher(row["gruppe"], 1), 10)
        n = schwellen_anteil(tage, got["punkt"][1], 10)
        if a is None or n is None:
            continue
        okt_alt.append(a)
        okt_neu.append(n)
        okt_arten.append(row["name"])
    if okt_alt:
        ma, mn = statistics.median(okt_alt), statistics.median(okt_neu)
        w(f"\n**Im Oktober** — dem Monat mit dem meisten Material — "
          f"sinkt der Anteil günstiger Tage im Median über "
          f"{len(okt_arten)} Arten von {_sp(ma)} auf {_sp(mn)}. Der "
          "Median und nicht der Durchschnitt, weil der Pfifferling im "
          "Oktober praktisch nie günstig steht und einen Schnitt nach "
          "unten zöge, der für keine Art gilt. Auf die "
          f"31 Oktobertage gerechnet: "
          + f"{ma * 31:.1f}".replace(".", ",") + " grüne Tage vorher, "
          + f"{mn * 31:.1f}".replace(".", ",") + " nachher — es fallen "
          + f"{(ma - mn) * 31:.1f}".replace(".", ",")
          + " weg. **Das ist die Zahl, an der entschieden wird.**\n")

    w("\n## Was die Zahlen sagen\n")
    kenn = []
    for row in zeilen:
        klass = av.AMPEL_CLASSES[row["gruppe"]]
        got = ergebnis.get(row["gruppe"], {}).get("b")
        if not got:
            continue
        tage = [e for eintraege in row["tage_b"].values() for e in eintraege]
        funde = [e for eintraege in row["funde_b"].values() for e in eintraege]
        a_tage = [e for eintraege in row["tage_a"].values() for e in eintraege]
        kenn.append({
            "a_alt": schwellen_anteil(a_tage, schwelle_vorher(row["gruppe"], 1))
            if a_tage else None,
            "b_alt": schwellen_anteil(tage, schwelle_vorher(row["gruppe"], 1)),
            "b_neu": schwellen_anteil(tage, got["punkt"][1]),
            "f_alt": schwellen_anteil(funde, schwelle_vorher(row["gruppe"], 1))
            if funde else None,
            "f_neu": schwellen_anteil(funde, got["punkt"][1])
            if funde else None,
        })

    def _med(feld):
        werte = sorted(k[feld] for k in kenn if k[feld] is not None)
        return statistics.median(werte) if werte else None

    if auf_p1:
        faktor = (None if not _med("b_neu")
                  else _med("b_alt") / _med("b_neu"))
        w("**Die ausgelieferte Schwelle hält ihr Versprechen nicht.** "
          "Gegen die Tage gemessen, für die sie gelten soll — gleicher "
          "Ort, gleiche Zeit im Jahr, andere Jahre — steht die Ampel an "
          f"{_sp(_med('b_alt'))} der Saisontage auf günstig. Vorgesehen "
          f"war {_sp(1 - SCHWELLEN_QUANTILE[1], 0)}"
          ", also etwa jeder fünfte Tag."
          + ("" if faktor is None else
             f" Das ist das {faktor:.1f}-fache.".replace(".", ",")) + "\n")
        w("**Die neue Schwelle stellt das Versprechen wieder her**, ohne "
          "eine Modellzahl anzufassen. Fenster, Breite und Regenkurve "
          "bleiben Zahl für Zahl, wie sie sind; es ändert sich nur, wo "
          "der Schnitt liegt.\n")
        w("**Was hier NICHT steht:** ob der Hinweis dadurch "
          "verlässlicher wird. Das wäre ein schwellenabhängiges Maß und "
          "ist auf dieser Scheibe gesperrt. Auf P3 gemessen bleibt der "
          "Hebel praktisch gleich — die Neukalibrierung ist eine "
          "Häufigkeitsentscheidung, keine Genauigkeitsverbesserung.\n")
    else:
        faktor = (None if not _med("a_alt")
                  else _med("b_alt") / _med("a_alt"))
        w("**Die ausgelieferten Schwellen sind in ihrer eigenen Welt in "
          f"Ordnung.** An Design-A-Vergleichstagen liegen im Mittel "
          f"{_sp(_med('a_alt'))} der Tage über der günstig-Schwelle — "
          "also ungefähr das eine Fünftel, für das sie gesetzt wurde. "
          "Der Kalibrierung fehlt nichts.\n")
        w("**Sie messen nur gegen die falschen Tage.** Dieselbe Zahl an "
          f"Design-B-Kontrolltagen: {_sp(_med('b_alt'))}. Die Ampel "
          "steht an einem gewöhnlichen Tag am Fundort zur Fundzeit also "
          + ("" if faktor is None else
             f"**{faktor:.1f}-mal so oft** auf günstig".replace(".", ","))
          + ", wie ihre eigene Kalibrierung vorsieht.\n")
        w("**Der Grund ist die Jahreszeit, und er ist mechanisch.** Ein "
          "Design-A-Vergleichstag liegt 26 bis 45 Tage neben dem Fund — "
          "bei einem Herbstpilz also im Hochsommer oder im Spätherbst, "
          "und beides ist weiter vom Fenster der Klasse entfernt als "
          "der Fundtag selbst. Die Glocke steht dort niedriger, die "
          "ganze Verteilung rutscht nach unten, und eine daraus "
          "gezogene Schwelle rutscht mit. Genau der Kalenderanteil, den "
          "Phase 1.5 in der AUC gemessen hat, steckt auch hier — nur "
          "sieht man ihn in der Häufigkeit statt in der "
          "Trennschärfe.\n")
        hebel_alt = [k["f_alt"] / k["b_alt"] for k in kenn
                     if k["b_alt"] and k["f_alt"] is not None]
        hebel_neu = [k["f_neu"] / k["b_neu"] for k in kenn
                     if k["b_neu"] and k["f_neu"] is not None]
        if hebel_alt and hebel_neu:
            w("**Die neue Schwelle trennt aber nicht besser.** Der "
              "Hebel steht vorher im Mittel bei "
              + f"{statistics.median(hebel_alt):.2f}".replace(".", ",")
              + " und nachher bei "
              + f"{statistics.median(hebel_neu):.2f}".replace(".", ",")
              + ". Was sich ändert, ist die Häufigkeit — "
              f"{_sp(_med('b_alt'))} gegen {_sp(_med('b_neu'))} der "
              "Tage — und nicht, wie verlässlich der Hinweis ist. Das "
              "ist keine Enttäuschung, sondern die Bestätigung, dass "
              "hier eine Häufigkeitsfrage vorliegt.\n")
        w("**Und die Zahl ist noch nicht auslieferbar.** Zwischen der "
          "Zeitscheibe P3 und den Jahren, in denen die App läuft, "
          "liegen bei den vier Zahlen oben zwischen +0,05 und +0,15 — "
          "mehr als ein Drittel des Gesamtsprungs beim Pfifferling. Wer "
          "die Spalte " + z("Design B auf P3") + " direkt übernimmt, "
          "liefert eine Schwelle aus, die für 2006 bis 2018 gemessen "
          "wurde.\n")

    if auf_p1:
        w("\n## Warum diese Scheibe erlaubt ist\n")
        w("**Schwelle und gepaarte AUC sind disjunkte Statistiken.** Die "
          "AUC ist rangbasiert: Sie zählt, wie oft der Fundtag seinen "
          "Kontrolltag schlägt, und kennt keine Schwelle. Eine aus P1 "
          "gezogene Schwelle kann deshalb keinen bisherigen und keinen "
          "künftigen AUC-Test berühren — es gibt hier keine Latte, kein "
          "Band, nichts zu bestehen. Beschrieben wird eine Verteilung, "
          "nicht ausgewählt.\n")
        w("Und P1 ist hier die richtige Scheibe: Die App steht heute, "
          "nicht 2012. Der P3-Bericht hat gemessen, dass die "
          "Zeitscheibe beim Pfifferling über ein Drittel des Sprungs "
          "ausmacht.\n")
        w("**Die Grenze dieser Erlaubnis** steht in "
          "`docs/pilzampel-pruefachsen.md` als Regel: "
          + ", ".join(P1_GESPERRTE_MASSE) + " sind auf P1 gesperrt. "
          "Sobald ein Maß eine Schwelle benutzt, um Fundtage zu "
          "bewerten, entschiede die ausgelieferte Zahl mit, wie gut die "
          "Ampel aussieht. `verbiete_schwellenmass` bricht den Lauf ab, "
          "statt eine solche Zahl zu liefern.\n")
    else:
        w("\n## Die Zelle, die fehlt\n")
        w("**Design B auf P1.** Das wäre die auslieferbare Zahl: "
          "dasselbe Design, aber die Jahre, in denen die App benutzt "
          "wird. Sie ist hier nicht gerechnet, weil Auftrag 3 A "
          "ausdrücklich als achsenfreier Lauf angelegt ist. Ob sie "
          "gerechnet wird, ist eine eigene Entscheidung; dieser Bericht "
          "ist der Check, der ihr vorausgeht.\n")

    w("## Vorlage, keine Übernahme\n")
    w("**Hier wird nichts übernommen.** Wie oft die Ampel "
      + z("günstig") + " sagen soll, ist eine Produktentscheidung und "
      "keine Messung. Diese Seite sagt nur, welche Zahl welches "
      "Verhalten trägt.\n")
    w("Wer sie übernimmt, ändert **vier Konstanten in "
      "`ampel_model.dart` und `tool/ampel_validate.py` zusammen** — die "
      "Spiegel-Regel gilt, und `verify_class_constants` bricht ab, "
      "sobald eine allein wandert.")
    return "\n".join(aus) + "\n"


def run_h6(args):
    """Die Vorpruefung zu H6 — auf P3, ohne eine Achse zu verbrauchen."""
    if args.api:
        av.OPEN_METEO = args.api.rstrip("/")
    av.DEDUPE = args.dedupe
    av.use_dataset(args.dataset)
    print(f"H6-Vorpruefung auf DE bis {av.FIT_UNTIL_YEAR} — Anpassjahre, "
          "keine Pruefachse", file=sys.stderr)
    print("Registrierung: docs/pilzampel-h6-vorpruefung.md",
          file=sys.stderr)

    mapping = av.read_species()
    if H6_ART not in mapping:
        raise SystemExit(f"{H6_ART} hat kein `sci`")
    finds, _ = av.select_finds(mapping[H6_ART], args.cache, args.seed, True,
                               ("DE",))
    gezogen = av.collect_pairs_b(H6_ART, mapping[H6_ART], finds=finds,
                                 cache_dir=args.cache, seed=args.seed,
                                 progress=False)
    if not gezogen:
        raise SystemExit("keine Paare")
    samples = fit_years_only(gezogen["samples"])
    print(f"  {len(samples)} Funde auf P3", file=sys.stderr)

    print("  Gittertabelle …", file=sys.stderr)
    tabelle = h6_tabelle(samples)
    jahre = sorted({s["year"] for s in samples})

    ganz = h6_gitter_optimum(tabelle, jahre)
    ganz_se = h6_gitter_se(tabelle, jahre, BOOTSTRAP_ROUNDS_B, args.seed)
    logit_ganz = h6_logit(samples)
    print(f"  Gitter {_fmt(ganz['optimum'], 2)} °C, "
          f"Logit {_fmt(logit_ganz.get('optimum'), 2)} °C",
          file=sys.stderr)

    # --- V1 ------------------------------------------------------------
    v1 = None
    if ganz and logit_ganz.get("optimum") is not None:
        se_l = logit_ganz.get("se_optimum")
        se_g = ganz_se["se"] if ganz_se else None
        v1 = {"gitter": ganz["optimum"], "logit": logit_ganz["optimum"],
              "abstand": abs(ganz["optimum"] - logit_ganz["optimum"]),
              "se_logit": se_l, "se_gitter": se_g,
              "statistisch": (None if se_l is None or se_g is None
                              else 1.959964 * math.sqrt(se_l ** 2
                                                        + se_g ** 2))}

    # --- V2: die geteilten Anpassjahre ---------------------------------
    haelften = []
    for von, bis in H6_HAELFTEN:
        teil = [s for s in samples if von <= s["year"] <= bis]
        teil_jahre = sorted({s["year"] for s in teil})
        eintrag = {"von": von, "bis": bis, "n": len(teil),
                   "duenn": len(teil) < MIN_FINDS_B,
                   "gitter": None, "logit": None, "se": None}
        if teil_jahre:
            eintrag["gitter"] = h6_gitter_optimum(tabelle, teil_jahre)
            eintrag["se"] = h6_gitter_se(tabelle, teil_jahre,
                                         BOOTSTRAP_ROUNDS_B, args.seed)
            eintrag["logit"] = h6_logit(teil)
        haelften.append(eintrag)
        print(f"  {von}–{bis}: {len(teil)} Funde, Gitter "
              f"{_fmt((eintrag['gitter'] or {}).get('optimum'), 2)} °C",
              file=sys.stderr)

    v2 = {"haelften": haelften,
          "se_ganz": ganz_se["se"] if ganz_se else None,
          "drift": None, "drift_logit": None, "grossz": None}
    a, b = haelften
    if not a["duenn"] and not b["duenn"] and a["gitter"] and b["gitter"]:
        v2["drift"] = abs(a["gitter"]["optimum"] - b["gitter"]["optimum"])
        if a["se"] and b["se"]:
            v2["grossz"] = math.sqrt(a["se"]["se"] ** 2 + b["se"]["se"] ** 2)
    if (a["logit"] and b["logit"] and a["logit"].get("optimum") is not None
            and b["logit"].get("optimum") is not None):
        v2["drift_logit"] = abs(a["logit"]["optimum"]
                                - b["logit"]["optimum"])

    # --- V3 und V4 ------------------------------------------------------
    neu = ganz["optimum"] if ganz else None
    v3 = h6_diskordanz(samples, H6_OPTIMUM_ALT, neu) if neu else None
    v4 = (h6_delta_bootstrap(samples, H6_OPTIMUM_ALT, neu,
                             BOOTSTRAP_ROUNDS_B, args.seed) if neu else None)

    urteil = h6_urteil(v1, v2, v3, v4)
    print(f"  {urteil['urteil']}", file=sys.stderr)

    bericht = render_h6({
        "n": len(samples), "jahre": jahre, "ganz": ganz,
        "ganz_se": ganz_se, "logit": logit_ganz,
        "v1": v1, "v2": v2, "v3": v3, "v4": v4, "urteil": urteil,
        "alt": H6_OPTIMUM_ALT, "neu": neu,
    })
    if args.out:
        open(args.out, "w", encoding="utf-8").write(bericht)
        print(f"\n{args.out} geschrieben", file=sys.stderr)
    else:
        print(bericht)


def _grad(wert, stellen=2):
    return "—" if wert is None else f"{wert:.{stellen}f} °C".replace(".", ",")


def _k(wert, stellen=2):
    return "—" if wert is None else f"{wert:.{stellen}f} K".replace(".", ",")


def render_h6(d):
    """Der Bericht zur H6-Vorpruefung."""
    import time as _t
    AUF, ZU = "„", "“"

    def z(text):
        return AUF + text + ZU

    aus = []
    w = aus.append
    ok = lambda b: "**ja**" if b else "**nein**"

    w("# H6-Vorprüfung: hält das Sommer-Optimum still?\n")
    w(f"Stand: {_t.strftime('%Y-%m-%d')} · Erzeugt von "
      "`tool/ampel_diagnose.py --h6` · Registrierung: "
      "`docs/pilzampel-h6-vorpruefung.md`\n")
    w("> **Diese Datei wird erzeugt.** Wer sie von Hand ändert, verliert "
      "die Änderung beim nächsten Lauf.\n")
    w(f"> **P3 sind die Anpassjahre.** Jede Zahl hier ist eine Diagnose "
      "und kein Beleg. Sie entscheidet nur, ob H6 auf AT+CH geprüft "
      "wird.\n")

    w("## Das Urteil\n")
    w(f"# {d['urteil']['urteil']}\n")
    w("| Bedingung | erfüllt |")
    w("|---|---|")
    bed = d["urteil"]["bedingungen"]
    w(f"| **V1** — Gitter und Logit einig (≤ "
      f"{_k(H6_V1_MAX_ABWEICHUNG, 1)}) | {ok(bed['wege_einig'])} |")
    w(f"| **V2** — Optimum stabil über die geteilten Anpassjahre "
      f"(Drift ≤ SE) | {ok(bed['stabil'])} |")
    w(f"| **V4** — Auflösung reicht (MDE < Diskordanzanteil) | "
      f"{ok(bed['aufloesung'])} |")
    w("")
    w(f"Material: **{d['n']} Funde** des {H6_ART}s auf P3, "
      f"{len(d['jahre'])} Fundjahre.\n")

    w("## V1 — zwei Wege, ein Optimum?\n")
    v1 = d["v1"]
    w("| Weg | Optimum | Standardfehler |")
    w("|---|--:|--:|")
    w(f"| **Gitter** (maximiert B) | {_grad(d['ganz']['optimum'] if d['ganz'] else None)} | "
      f"{_k(d['ganz_se']['se'] if d['ganz_se'] else None)} |")
    w(f"| **Logit** (cluster-robust) | {_grad(d['logit'].get('optimum'))} | "
      f"{_k(d['logit'].get('se_optimum'))} |")
    w(f"| ausgeliefert | {_grad(d['alt'], 1)} | — |")
    w("")
    if v1:
        w(f"**Abstand der beiden Wege: {_k(v1['abstand'])}** gegen die "
          f"Latte von {_k(H6_V1_MAX_ABWEICHUNG, 1)}.")
        if v1["statistisch"] is not None:
            w(f"Die statistische Fassung, nur zur Einordnung: "
              f"1,96·√(SE²+SE²) = {_k(v1['statistisch'])}. Sie ist hier "
              "zu großzügig, weil beide Schätzer auf denselben Daten "
              "laufen — deshalb steht sie nicht in der Bedingung.")
    if d["ganz"]:
        w(f"\nDas Plateau des Gitters reicht von "
          f"{_grad(d['ganz']['plateau'][0])} bis "
          f"{_grad(d['ganz']['plateau'][1])} "
          f"({_k(d['ganz']['plateau_breite'])} breit) — alle Optima, die "
          "weniger als " + f"{H6_PLATEAU:.3f}".replace(".", ",")
          + " B darunter liegen. Ein breites Plateau heißt: Der Gipfel "
            "ist eine Nachkommastelle ohne Deckung.")
    if d["logit"].get("grund"):
        w(f"\n⚠ Logit: {d['logit']['grund']}")
    if d["logit"].get("konvergiert") is False:
        w("\n⚠ **Das Logit ist nicht konvergiert.** Die Zahl daneben ist "
          "keine Schätzung.")

    w("\n## V2 — das harte Abbruchkriterium\n")
    v2 = d["v2"]
    w("| Scheibe | Funde | Gitter | 95 % | Logit |")
    w("|---|--:|--:|---|--:|")
    for h in v2["haelften"]:
        g = h["gitter"]
        band = h["se"]["band"] if h["se"] else None
        w(f"| {h['von']}–{h['bis']}{' ⚠ zu dünn' if h['duenn'] else ''} | "
          f"{h['n']} | {_grad(g['optimum'] if g else None)} | "
          + ("—" if not band else
             f"[{_grad(band[0])}, {_grad(band[1])}]") + " | "
          f"{_grad((h['logit'] or {}).get('optimum'))} |")
    w(f"| **ganz P3** | {d['n']} | "
      f"{_grad(d['ganz']['optimum'] if d['ganz'] else None)} | "
      + ("—" if not d["ganz_se"] else
         f"[{_grad(d['ganz_se']['band'][0])}, "
         f"{_grad(d['ganz_se']['band'][1])}]") + " | "
      f"{_grad(d['logit'].get('optimum'))} |")
    w("")
    if v2["drift"] is None:
        w("**Nicht auswertbar** — eine Hälfte ist zu dünn. Ein "
          "Kriterium, das man nicht prüfen kann, ist keines, das man "
          "bestanden hat: H6 wird nicht registriert.")
    else:
        w(f"**Drift des Gitter-Optimums: {_k(v2['drift'])}** gegen den "
          f"Standardfehler auf ganz P3 von {_k(v2['se_ganz'])}.")
        if v2["grossz"] is not None:
            w(f"\nDie großzügige Fassung, zur Einordnung: Die Differenz "
              f"zweier Halbschätzer trägt selbst rund "
              f"{_k(v2['grossz'])} Fehler. Gegen die gemessen wäre die "
              "Drift "
              + ("auffällig" if v2["drift"] > 1.96 * v2["grossz"]
                 else "unauffällig")
              + ". Bindend ist die strenge Fassung aus der "
                "Registrierung — gefragt ist nicht, ob die Drift "
                "signifikant ist, sondern ob die Genauigkeit haltbar "
                "wäre, die wir für die ausgelieferte Zahl behaupten "
                "würden.")
        if v2["drift_logit"] is not None:
            w(f"\nDas Logit driftet um {_k(v2['drift_logit'])} — es "
              "läuft daneben und entscheidet nicht, aber wenn beide "
              "Wege verschieden urteilten, stünde V1 in Frage.")

    w("\n## V3 — wieviel kann überhaupt herauskommen?\n")
    v3 = d["v3"]
    if not v3:
        w("Nicht gerechnet.")
    else:
        w(f"Zwischen {_grad(d['alt'], 1)} und {_grad(d['neu'])} ordnen "
          f"**{_sp(v3['anteil'])}** der {v3['paare']} B-Vergleiche das "
          "Paar verschieden.\n")
        w(f"> **Obergrenze der Effektgröße: |ΔB| ≤ "
          f"{v3['anteil']:.3f}**".replace(".", ",") + "\n")
        schaerfer = v3["mittlere_aenderung"] < v3["anteil"] - 1e-12
        w("Die zweite, schärfere Schranke ist die mittlere Änderung des "
          "Beitrags je Vergleich: "
          + f"{v3['mittlere_aenderung']:.3f}".replace(".", ",")
          + (" — sie liegt darunter, weil ein Vergleich, der von "
             + z("geschlagen") + " auf " + z("gleich") + " kippt, nur "
             "einen halben Punkt verschiebt." if schaerfer else
             ". **Sie ist hier genauso groß wie der Diskordanzanteil.** "
             "Das heißt: Jeder Vergleich, der überhaupt kippt, kippt "
             "ganz — von " + z("geschlagen") + " auf "
             + z("nicht geschlagen") + ", nie auf " + z("gleich") + ". "
             "Exakte Gleichstände gibt es bei Fließkommazahlen "
             "praktisch nicht."))

    w("\n## V4 — kann der Aufbau das sehen?\n")
    v4 = d["v4"]
    if not v4:
        w("Nicht gerechnet.")
    else:
        w(f"Jahres-Bootstrap der **Differenz je Zug**, {v4['n']} Züge "
          "über die Fundjahre. Bewertet werden in jedem Zug dieselben "
          "Funde zweimal.\n")
        w("| Größe | Wert |")
        w("|---|--:|")
        w(f"| ΔB auf P3 ({_grad(d['neu'])} gegen {_grad(d['alt'], 1)}) | "
          + f"{v4['delta']:+.3f}".replace(".", ",") + " |")
        w(f"| 95 %-Band | ["
          + f"{v4['band'][0]:+.3f}".replace(".", ",") + ", "
          + f"{v4['band'][1]:+.3f}".replace(".", ",") + "] |")
        w(f"| Standardfehler | " + f"{v4['se']:.4f}".replace(".", ",")
          + " |")
        w(f"| **nachweisbare Effektgröße (MDE)** | "
          + f"{v4['mde']:.3f}".replace(".", ",") + " |")
        w("")
        if v3:
            w(f"**MDE {v4['mde']:.3f} gegen Obergrenze "
              f"{v3['anteil']:.3f}**".replace(".", ",") + " — "
              + ("die Auflösung reicht." if v4["mde"] < v3["anteil"]
                 else "**die Auflösung reicht nicht**: Der "
                      "größtmögliche Effekt wäre von null nicht zu "
                      "unterscheiden."))
        w(f"\nDas ΔB oben ist **kein Beleg**: Das neue Optimum stammt "
          "von denselben Anpassjahren, auf denen es hier bewertet wird. "
          "Es steht da, damit die Größenordnung sichtbar ist.")

    w("\n## Was daraus folgt\n")
    if d["urteil"]["urteil"].startswith("H6 wird registriert"):
        w("Alle Bedingungen sind erfüllt. **H6 wird registriert** — "
          "geprüft wird auf **AT + CH**, mit einem auf P3 festgelegten "
          "und danach eingefrorenen Wert. Die Registrierung ist ein "
          "eigenes Dokument und kommt vor dem Achsenlauf.")
    else:
        namen = {"wege_einig": "V1 — Gitter und Logit sind sich nicht "
                                "einig",
                 "stabil": "V2 — das Optimum wandert",
                 "aufloesung": "V4 — die Auflösung reicht nicht"}
        gefallen = [namen[name] for name, wert in
                    d["urteil"]["bedingungen"].items() if not wert]
        w("Gefallen ist: **" + "**, **".join(gefallen) + "**. **H6 wird "
          "nicht registriert**, und AT+CH bleibt unangetastet.\n")
        w("Das ist ein Ergebnis und kein Anlass für einen zweiten "
          "Anlauf mit verschobener Latte. Was hier gemessen wurde, "
          "steht oben; ob es reicht, ist eine Betreiberentscheidung und "
          "keine, die dieser Bericht still trifft.")
    return "\n".join(aus) + "\n"


def run_h6_test(args):
    """Der registrierte Prueflauf zu H6 — auf AT+CH."""
    if args.api:
        av.OPEN_METEO = args.api.rstrip("/")
    av.DEDUPE = args.dedupe
    av.use_dataset(args.dataset)
    print("H6 auf " + "+".join(H6_ACHSE) + " — **Pruefachse**",
          file=sys.stderr)
    print("Registrierung: docs/pilzampel-h6-registrierung.md",
          file=sys.stderr)
    print(f"  eingefroren: {H6_OPTIMUM_NEU} °C gegen "
          f"{H6_OPTIMUM_ALT} °C", file=sys.stderr)

    mapping = av.read_species()
    finds, _ = av.select_finds(mapping[H6_ART], args.cache, args.seed, True,
                               H6_ACHSE)
    if not finds:
        raise SystemExit("keine Funde auf der Achse")
    gezogen = av.collect_pairs_b(H6_ART, mapping[H6_ART], finds=finds,
                                 cache_dir=args.cache, seed=args.seed,
                                 progress=False)
    if not gezogen:
        raise SystemExit("keine Paare")
    samples = gezogen["samples"]
    print(f"  {len(samples)} Funde", file=sys.stderr)

    delta = h6_delta(samples, H6_OPTIMUM_ALT, H6_OPTIMUM_NEU,
                     BOOTSTRAP_ROUNDS_B, args.seed)
    gegen = h6_delta(samples, H6_OPTIMUM_ALT, H6_OPTIMUM_GEGEN,
                     BOOTSTRAP_ROUNDS_B, args.seed)
    placebo, placebo_n = av.placebo_b(samples, H6_OPTIMUM_NEU)
    tot_alt = h1_ties(samples, H6_OPTIMUM_ALT, av.TEMP_SIGMA)
    tot_neu = h1_ties(samples, H6_OPTIMUM_NEU, av.TEMP_SIGMA)
    zerlegung = {}
    for name, optimum in (("alt", H6_OPTIMUM_ALT), ("neu", H6_OPTIMUM_NEU)):
        zerlegung[name] = {
            v: h1_b(samples, optimum, zerlegung_scorer(optimum, v))
            for v in ZERLEGUNG_VARIANTEN}

    urteil = h6_test_urteil(delta, gegen, placebo, placebo_n)
    print(f"  Δ {_signed(delta['delta'] if delta else None)}  "
          f"Latte {urteil['latte']:.3f}  {urteil['urteil']}",
          file=sys.stderr)

    bericht = render_h6_test({
        "n": len(samples), "delta": delta, "gegen": gegen,
        "placebo": placebo, "placebo_n": placebo_n,
        "tot_alt": tot_alt, "tot_neu": tot_neu,
        "zerlegung": zerlegung, "urteil": urteil,
        "laender": gezogen.get("partial_years"),
    })
    if args.out:
        open(args.out, "w", encoding="utf-8").write(bericht)
        print(f"\n{args.out} geschrieben", file=sys.stderr)
    else:
        print(bericht)


def render_h6_test(d):
    """Der Bericht zum registrierten H6-Lauf."""
    import time as _t
    aus = []
    w = aus.append
    ok = lambda b: "**ja**" if b else "**nein**"
    u, bed = d["urteil"], d["urteil"]["bedingungen"]
    delta, gegen = d["delta"], d["gegen"]

    w("# H6 auf AT+CH — das Sommer-Optimum bei 14,0 °C\n")
    w(f"Stand: {_t.strftime('%Y-%m-%d')} · Erzeugt von "
      "`tool/ampel_diagnose.py --h6-test` · Registrierung: "
      "`docs/pilzampel-h6-registrierung.md`\n")
    w("> **Diese Datei wird erzeugt.** Wer sie von Hand ändert, "
      "verliert die Änderung beim nächsten Lauf.\n")
    w("> **Das ist ein Lauf auf einer Prüfachse** — der sechste auf "
      "AT+CH. Eingetragen in `docs/pilzampel-pruefachsen.md`.\n")

    w("## Das Urteil\n")
    w(f"# {u['urteil']}\n")
    w("| Bedingung | Wert | erfüllt |")
    w("|---|--:|---|")
    latte = f"{u['latte']:.3f}".replace(".", ",")
    w(f"| Gewinn ≥ {latte} | {_signed(delta['delta']) if delta else '—'} | "
      f"{ok(bed['gewinn'])} |")
    w(f"| Band schließt die Null aus (p < {P_GRENZE}) | "
      f"{_pwert(delta['band']) if delta else '—'} | {ok(bed['band'])} |")
    w(f"| ≥ {_sp(H6_MIN_JAHR_ANTEIL, 0)} der Fundjahre in dieselbe "
      f"Richtung | "
      + (f"{delta['jahre_besser']}/{delta['jahre']}" if delta else "—")
      + f" | {ok(bed['jahre'])} |")
    w(f"| Placebo sauber bei 0,50 | {_fmt(d['placebo'])} "
      f"({d['placebo_n']} Paare) | {ok(bed['placebo'])} |")
    w(f"| Gegenprobe (20 °C) schlägt NICHT an | "
      f"{_signed(gegen['delta']) if gegen else '—'} | "
      f"{ok(bed['gegenprobe'])} |")
    w("")
    w(f"Material: **{d['n']} Funde** des {H6_ART}s in "
      + " und ".join(H6_ACHSE) + ".\n")

    w("## Die Messung\n")
    if not delta:
        w("Keine Paare.")
    else:
        w("| Größe | Wert |")
        w("|---|--:|")
        w(f"| B bei {_grad(H6_OPTIMUM_ALT, 1)} (ausgeliefert) | "
          f"{_fmt(delta['b_alt'])} |")
        w(f"| B bei {_grad(H6_OPTIMUM_NEU, 1)} (registriert) | "
          f"{_fmt(delta['b_neu'])} |")
        w(f"| **Δ** | {_signed(delta['delta'])} |")
        w(f"| 95 %-Band | "
          + (f"[{_signed(delta['band'][0])}, "
             f"{_signed(delta['band'][1])}]" if delta["band"] else "—")
          + " |")
        w(f"| p | {_pwert(delta['band'])} |")
        w(f"| Standardfehler | "
          + ("—" if delta["se"] is None
             else f"{delta['se']:.4f}".replace(".", ",")) + " |")
        w(f"| nachweisbare Effektgröße (MDE) | "
          + ("—" if delta["mde"] is None
             else f"{delta['mde']:.3f}".replace(".", ",")) + " |")
        w(f"| Latte = max(+0,010, MDE) | {latte} |")
        w("")
        if delta["mde"] is not None and not bed["gewinn"]:
            w("**Wie ein Fehlschlag zu lesen ist.** Liegt Δ unter der "
              "Latte, sagt die MDE-Zeile, was das heißt: Ein Δ deutlich "
              "unter der MDE heißt „der Aufbau sieht es nicht“; ein Δ "
              "nahe null bei kleiner MDE heißt „es ist nichts da“. "
              + (f"Hier liegt Δ bei {_signed(delta['delta'])} und die "
                 f"MDE bei "
                 + f"{delta['mde']:.3f}".replace(".", ",") + ".") + "\n")

    w("## Pflichtspalten\n")
    w("| Spalte | bei 17,5 °C | bei 14,0 °C |")
    w("|---|--:|--:|")
    for schluessel, label in (("fund_tot", "tote Funde"),
                              ("beide_null", "tote Vergleiche"),
                              ("alle_gleich", "exakter Gleichstand")):
        a = d["tot_alt"].get(schluessel) if d["tot_alt"] else None
        n = d["tot_neu"].get(schluessel) if d["tot_neu"] else None
        w(f"| {label} | {_sp(a) if a is not None else '—'} | "
          f"{_sp(n) if n is not None else '—'} |")
    w("")
    w("**Tote Vergleiche** sind die, bei denen Fund- und Kontrolltag "
      "beide unter 1e-6 liegen — dort unterscheidet das Modell nicht "
      "mehr, und ein Δ nahe null hieße etwas anderes als "
      "„kein Effekt“.\n")

    w("### Die Zerlegung — nicht entscheidend, aber die eigentliche Frage\n")
    w("Auf P3 und P1 trägt die Glocke dieser Art nichts bei: 0,629 "
      "gegen 0,632 an Regen allein, und auf den Prüfjahren 0,557 gegen "
      "0,630. Ob ein anderes Fenster daran etwas ändert, ist das, was "
      "man wissen will — es entscheidet hier aber nichts.\n")
    w("| Fenster | voll | nur Regen | nur Temperatur | voll − Regen |")
    w("|---|--:|--:|--:|--:|")
    for name, label in (("alt", "17,5 °C"), ("neu", "14,0 °C")):
        z = d["zerlegung"][name]
        diff = (None if z["voll"] is None or z["nur Regen"] is None
                else z["voll"] - z["nur Regen"])
        w(f"| {label} | {_fmt(z['voll'])} | {_fmt(z['nur Regen'])} | "
          f"{_fmt(z['nur Temperatur'])} | {_signed(diff)} |")

    w("\n## Was daraus folgt\n")
    if u["urteil"] == "H6 bestanden":
        w("**14,0 °C wird ausgeliefert** — zusammen mit neu gemessenen "
          "Sommer-Schwellen. Die 0,385 und 0,729 sind Quantile der "
          "Verteilung unter 17,5 °C; mit einem anderen Fenster bedeuten "
          "dieselben Zahlen eine andere Häufigkeit. Fenster und "
          "Schwellen gehen **zusammen** in eine Version "
          "(`--schwellen --scheibe p1`).\n")
        w("Die Herkunft bleibt „gemessen (Design B), mit gefallenem V1 "
          "in der Vorprüfung“ — der Mangel aus "
          "`docs/pilzampel-h6-registrierung.md`, Abschnitt 3, wandert "
          "mit der Zahl.")
    else:
        gefallen = [name for name, wert in bed.items() if not wert]
        w(f"Gefallen ist: **{', '.join(gefallen)}**. **Die 17,5 °C "
          "bleiben**, und die Herabstufung in `docs/pilzampel-formel.md` "
          "bleibt, wie sie ist.\n")
        w("Die Achse ist verbraucht. Ein zweiter Lauf mit einem anderen "
          "Wert wäre die Suche nach der Zahl, die besteht — und genau "
          "davor steht die Registrierung.")
    return "\n".join(aus) + "\n"


# --- Grafiken: die Aussagen als Bild --------------------------------------
#
# **Warum es die gibt** (Betreiberfrage 2026-09-19): „Ich kann mir nicht
# vorstellen, dass es hier gar keine Zusammenhaenge gibt." Die Frage war
# berechtigt, und die Tabellen haben sie nicht beantwortet — weil sie
# eine ANDERE Frage beantworten, als sie zu beantworten schienen.
#
# Design B vergleicht einen Fundtag mit demselben Kalenderdatum anderer
# Jahre am selben Ort. Die Jahreszeit kuerzt sich dabei heraus, und
# damit auch der offensichtliche Zusammenhang „im Februar waechst kein
# Pfifferling". Was uebrig bleibt, ist eine viel engere Frage: Sagt die
# Abweichung dieses Jahres von der ortsueblichen Temperatur dieser Woche
# etwas vorher? Ein B von 0,51 heisst „diese enge Frage: nein" und NICHT
# „Temperatur ist egal".
#
# Genau das zeigen die Bilder, und deshalb stehen hier zwei
# Vergleichsmengen nebeneinander: Design A (26 bis 45 Tage daneben, also
# quer durch die Saison) und Design B (dieselbe Woche, anderes Jahr).

GRAFIK_ORDNER = "docs/bilder"
GRAFIK_ARTEN = ["Pfifferling", "Steinpilz"]
GRAFIK_STUFEN = 32


def grafik_mittel(paar):
    """Das 20-Tage-Temperaturmittel eines Fenster-Paares."""
    werte = [c for c in paar[1][:av.TEMP_WINDOW] if c is not None]
    return sum(werte) / len(werte) if werte else None


def grafik_glocke(optimum, sigma, x_von, x_bis, hoehe, schritte=120):
    """Die Glocke als Stuetzstellen — auf eine Hoehe skaliert.

    Sie steht im Bild neben Haeufigkeiten und hat mit ihnen keine
    gemeinsame Einheit; skaliert wird deshalb auf die Bildhoehe, und die
    y-Achse gilt ausdruecklich nur fuer die Balken.
    """
    punkte = []
    for i in range(schritte + 1):
        x = x_von + (x_bis - x_von) * i / schritte
        punkte.append((x, hoehe * math.exp(-(((x - optimum) / sigma) ** 2))))
    return punkte


def grafik_temperaturen(art, samples_b, samples_a):
    """Zwei Bilder: Design A quer durch die Saison, Design B in der Woche."""
    fund = [t for t in (grafik_mittel(s["found"]) for s in samples_b)
            if t is not None]
    b_ktrl = [t for t in (grafik_mittel(c) for s in samples_b
                          for c in s["controls"]) if t is not None]
    a_ktrl = [t for t in (grafik_mittel(s["control"]) for s in samples_a)
              if t is not None]
    if not fund:
        return {}

    alle = fund + b_ktrl + a_ktrl
    von, bis = math.floor(min(alle)) - 1, math.ceil(max(alle)) + 1
    klass = av.class_of(art)
    optimum = (av.AMPEL_CLASSES[klass]["optimum"] if klass
               else av.OPTIMUM_C)

    bilder = {}
    for schluessel, ktrl, titel, unter, ktrl_name in (
            ("saison", a_ktrl,
             f"{art}: Fundtage gegen Tage QUER DURCH DIE SAISON",
             "Design A — Vergleichstag 26 bis 45 Tage neben dem Fund, "
             "gleiches Jahr, gleicher Ort",
             "Vergleichstage (quer durch die Saison)"),
            ("woche", b_ktrl,
             f"{art}: Fundtage gegen DIESELBE WOCHE anderer Jahre",
             "Design B — gleicher Ort, gleiches Kalenderdatum ±7 Tage, "
             "anderes Jahr",
             "Kontrolltage (dieselbe Woche)")):
        if not ktrl:
            continue
        mitten, a_fund = ag.histogramm(fund, von, bis, GRAFIK_STUFEN)
        _, a_ktrl_h = ag.histogramm(ktrl, von, bis, GRAFIK_STUFEN)
        hoch = max(a_fund + a_ktrl_h) * 1.25
        d = ag.Diagramm(titel, von, bis, 0, hoch,
                        x_titel="20-Tage-Mittel der Temperatur (°C)",
                        y_titel="Anteil der Tage", untertitel=unter)
        weite = (bis - von) / GRAFIK_STUFEN
        d.balken(mitten, a_ktrl_h, weite, ag.FARBEN["kontrolle"], 0.55,
                 name=ktrl_name)
        d.balken(mitten, a_fund, weite, ag.FARBEN["fund"], 0.6,
                 name="Fundtage")
        d.linie(grafik_glocke(optimum, av.TEMP_SIGMA, von, bis, hoch * 0.92),
                ag.FARBEN["kurve"],
                name=f"Glocke der App ({ag.Diagramm.zahl(optimum)} °C, "
                     "eigene Höhe)")
        d.senkrechte(optimum, ag.FARBEN["warn"],
                     f"{ag.Diagramm.zahl(optimum)} °C")
        bilder[schluessel] = d.svg()
    return bilder


def grafik_antwortkurve(art, samples_b, samples_a):
    """Wie stark sind Funde bei welcher Temperatur ueberrepraesentiert?

    **Das ist die Frage, die die B-Tabellen NICHT beantworten** und die
    der Betreiber am 2026-09-19 gestellt hat: Wachsen bei −5 Grad
    genauso viele Pfifferlinge wie bei 15?

    Geteilt wird der Anteil der FUNDTAGE in einer Temperaturklasse durch
    den Anteil der VERGLEICHSTAGE in derselben Klasse. Ueber 1 heisst
    ueberrepraesentiert, unter 1 unterrepraesentiert. Das ist eine
    Beschreibung und kein Modell — es wird nichts angepasst und nichts
    geprueft.

    **Die Grenze, und sie ist wichtig:** Die Vergleichstage aus Design A
    liegen 26 bis 45 Tage neben einem Fund, sind also selbst noch
    saisonnah. Eine gleichverteilte Stichprobe ueber das ganze Jahr
    waere die ehrlichere Bezugsmenge, und gegen sie faellt die Kurve an
    den Raendern noch steiler ab. Was hier steht, ist die UNTERGRENZE
    des Zusammenhangs.
    """
    fund = [t for t in (grafik_mittel(s["found"]) for s in samples_b)
            if t is not None]
    ktrl = [t for t in (grafik_mittel(s["control"]) for s in samples_a)
            if t is not None]
    if not fund or not ktrl:
        return None
    alle = fund + ktrl
    von, bis = math.floor(min(alle)) - 1, math.ceil(max(alle)) + 1
    stufen = 22
    mitten, a_fund = ag.histogramm(fund, von, bis, stufen)
    _, a_ktrl = ag.histogramm(ktrl, von, bis, stufen)
    # **Duenn besetzte Klassen tragen kein Verhaeltnis.** Ein Fund gegen
    # einen Vergleichstag ergibt rechnerisch eine 1,0 und sagt nichts;
    # solche Klassen bleiben leer statt eine Zacke zu malen.
    mindest = 0.005
    punkte = [(m, f / k) for m, f, k in zip(mitten, a_fund, a_ktrl)
              if k >= mindest]
    if len(punkte) < 3:
        return None
    hoch = max(y for _, y in punkte) * 1.2
    klass = av.class_of(art)
    optimum = (av.AMPEL_CLASSES[klass]["optimum"] if klass
               else av.OPTIMUM_C)
    d = ag.Diagramm(
        f"{art}: Bei welcher Temperatur wird überhaupt gefunden?",
        von, bis, 0, hoch,
        x_titel="20-Tage-Mittel der Temperatur (°C)",
        y_titel="Fundtage je Vergleichstag",
        untertitel="Über 1 heißt: bei dieser Temperatur wird häufiger "
                   "gemeldet, als es solche Tage überhaupt gibt. "
                   "Beschreibung, kein Modell.")
    d.linie([(von, 1.0), (bis, 1.0)], ag.FARBEN["blass"], 1.4,
            gestrichelt=True, name="1,0 — so häufig wie die Tage selbst")
    d.balken([m for m, _ in punkte], [y for _, y in punkte],
             (bis - von) / stufen, ag.FARBEN["fund"], 0.55,
             name="Fundtage je Vergleichstag")
    d.senkrechte(optimum, ag.FARBEN["warn"],
                 f"Glocke der App: {ag.Diagramm.zahl(optimum)} °C")
    return d.svg()


def grafik_differenz(art, samples_b):
    """Wie weit Fund- und Kontrolltag in Design B ueberhaupt auseinanderliegen."""
    diffs = []
    for s in samples_b:
        f = grafik_mittel(s["found"])
        if f is None:
            continue
        for c in s["controls"]:
            k = grafik_mittel(c)
            if k is not None:
                diffs.append(f - k)
    if not diffs:
        return None
    grenze = max(6.0, math.ceil(max(abs(min(diffs)), abs(max(diffs)))))
    mitten, anteile = ag.histogramm(diffs, -grenze, grenze, GRAFIK_STUFEN)
    hoch = max(anteile) * 1.25
    innerhalb = sum(1 for x in diffs if abs(x) < 2.0) / len(diffs)
    d = ag.Diagramm(
        f"{art}: Wie viel wärmer war der Fundtag als sein Vergleichstag?",
        -grenze, grenze, 0, hoch,
        x_titel="Fundtag minus Vergleichstag (K)",
        y_titel="Anteil der Vergleiche",
        untertitel=f"Design B — {_sp(innerhalb, 0)} aller Vergleiche "
                   "liegen innerhalb von ±2 K. Auf diesem schmalen Band "
                   "wird die Glocke befragt.")
    d.flaeche_x(-2, 2, ag.FARBEN["kurve"], 0.10, name="±2 K")
    d.balken(mitten, anteile, 2 * grenze / GRAFIK_STUFEN,
             ag.FARBEN["kontrolle"], 0.7, name="Vergleiche")
    d.senkrechte(0, ag.FARBEN["achse"], "kein Unterschied")
    return d.svg()


def grafik_optimumkurve(art, samples_b, tabelle=None):
    """Das B-Mass als Funktion des Optimums — wie flach der Gipfel ist."""
    jahre = sorted({s["year"] for s in samples_b})
    tabelle = tabelle or h6_tabelle(samples_b)
    punkte = [(o, h6_b_aus_tabelle(tabelle, o, jahre))
              for o in h6_gitterwerte()]
    punkte = [(o, b) for o, b in punkte if b is not None]
    if len(punkte) < 2:
        return None
    best = h6_gitter_optimum(tabelle, jahre)
    werte = [b for _, b in punkte]
    spanne = max(werte) - min(werte)
    y_von = min(werte) - spanne * 0.25
    y_bis = max(werte) + spanne * 0.35
    klass = av.class_of(art)
    ausgeliefert = (av.AMPEL_CLASSES[klass]["optimum"] if klass
                    else av.OPTIMUM_C)
    d = ag.Diagramm(
        f"{art}: Wie gut trennt die Ampel bei welchem Optimum?",
        H6_GITTER_VON, H6_GITTER_BIS, y_von, y_bis,
        x_titel="Angenommenes Optimum (°C)",
        y_titel="B — Anteil geschlagener Kontrolljahre",
        untertitel="Design B auf den Anpassjahren. 0,50 hieße: kein "
                   "Unterschied zu einem gewöhnlichen Tag derselben "
                   "Woche.")
    if best:
        d.flaeche_x(best["plateau"][0], best["plateau"][1],
                    ag.FARBEN["kurve"], 0.10,
                    name="Plateau (weniger als 0,005 unter dem Gipfel)")
    d.linie(punkte, ag.FARBEN["kurve"], 2.6, name="B")
    if y_von <= 0.5 <= y_bis:
        d.linie([(H6_GITTER_VON, 0.5), (H6_GITTER_BIS, 0.5)],
                ag.FARBEN["blass"], 1.4, gestrichelt=True,
                name="0,50 — kein Signal")
    d.senkrechte(ausgeliefert, ag.FARBEN["warn"],
                 f"ausgeliefert: {ag.Diagramm.zahl(ausgeliefert)} °C")
    if best:
        d.senkrechte(best["optimum"], ag.FARBEN["neben"],
                     f"bestes: {ag.Diagramm.zahl(best['optimum'])} °C",
                     oben=False)
    return d.svg()


def run_grafiken(args):
    """Die Aussagen der Berichte als Bild — reine Beschreibung."""
    if args.api:
        av.OPEN_METEO = args.api.rstrip("/")
    av.DEDUPE = args.dedupe
    av.use_dataset(args.dataset)
    print(f"Grafiken auf DE bis {av.FIT_UNTIL_YEAR} — Anpassjahre, "
          "keine Pruefachse", file=sys.stderr)

    arten = GRAFIK_ARTEN
    if args.only:
        arten = [n.strip() for n in args.only.split(",") if n.strip()]
    mapping = av.read_species()
    os.makedirs(GRAFIK_ORDNER, exist_ok=True)
    geschrieben = []
    for art in arten:
        if art not in mapping:
            continue
        print(f"  {art}", file=sys.stderr)
        sci = mapping[art]
        finds, _ = av.select_finds(sci, args.cache, args.seed, True, ("DE",))
        if not finds:
            continue
        b = av.collect_pairs_b(art, sci, finds=finds, cache_dir=args.cache,
                               seed=args.seed, progress=False)
        a = av.collect_pairs(art, sci, cache_dir=args.cache, seed=args.seed,
                             progress=False)
        if not b:
            continue
        sb = fit_years_only(b["samples"])
        sa = ([s for s in a["samples"] if s["year"] <= av.FIT_UNTIL_YEAR]
              if a else [])
        kurz = art.lower().replace("ä", "ae").replace("ö", "oe") \
                  .replace("ü", "ue").replace("ß", "ss")
        bilder = grafik_temperaturen(art, sb, sa)
        bilder["antwort"] = grafik_antwortkurve(art, sb, sa)
        bilder["differenz"] = grafik_differenz(art, sb)
        bilder["optimum"] = grafik_optimumkurve(art, sb)
        for schluessel, svg in bilder.items():
            if not svg:
                continue
            pfad = os.path.join(GRAFIK_ORDNER, f"{kurz}-{schluessel}.svg")
            open(pfad, "w", encoding="utf-8").write(svg)
            geschrieben.append(pfad)
            print(f"    {pfad}", file=sys.stderr)
    print(f"\n{len(geschrieben)} Bilder geschrieben", file=sys.stderr)
    return geschrieben


# --- Bodenfeuchte: die nie ausgewertete Spalte ----------------------------
#
# **Betreiberfrage vom 2026-09-19: „Haben wir schon eine Auswertung mit
# der Bodenfeuchte gemacht?" Nein.** Seit der Messbasis `pinned`
# (2026-09-18) holt jeder Lauf `soil_moisture_7_to_28cm` und
# `soil_temperature_0_to_7cm` mit und legt sie im Cache ab; benutzt
# wurde davon bisher nur `tmin`, fuer die Frost-Diagnose zu H3. Die
# Bodenfeuchte lag zwei Tage lang vollstaendig da und ist nie
# angesehen worden.
#
# **Warum sie der naheliegendere Kandidat ist als der Regen.** Die
# Ampel rechnet eine gewichtete Regensumme ueber 26 Tage — ein
# Stellvertreter fuer das, was das Myzel erreicht. Die Bodenfeuchte in
# 7 bis 28 cm Tiefe IST diese Groesse, und zwar schon integriert:
# Versickerung, Verdunstung und Vorgeschichte stecken drin, ohne dass
# jemand eine Gewichtskurve setzen muss. Der 26-Tage-Vorlauf und die
# 87-mm-Saettigung sind beide GESETZT (`docs/pilzampel-formel.md`);
# eine Groesse ohne gesetzte Konstanten waere ein Fortschritt, selbst
# wenn sie gleich gut traegt.
#
# **Das Mass ist rangbasiert, also braucht es hier keine Eichung.** B
# fragt nur, ob der Fundtag seinen Kontrolltag schlaegt; jede monotone
# Umformung laesst die Zahl unveraendert. Eine Saettigungskurve fuer
# die Bodenfeuchte zu setzen waere also fuer diesen Vergleich
# ueberfluessig — und fuer eine spaetere Ampel eine eigene Frage.

BODEN_FENSTER = (1, 7, 14, 26)


def boden_mittel(reihe, tage):
    """Mittel der juengsten [tage] Tage einer Zusatzreihe."""
    if not reihe:
        return None
    werte = [v for v in reihe[:tage] if v is not None]
    return sum(werte) / len(werte) if werte else None


def boden_scorer(feld, tage):
    """Ein Bewerter, der NUR auf einer Zusatzreihe rangt.

    Er bekommt die Reihe nicht ueber `(regen, temp)` wie die anderen
    Bewerter, sondern ueber die Stichprobe — deshalb nimmt `boden_b`
    ihn gesondert entgegen und nicht ueber `h1_b`.
    """
    def wert(extra):
        return boden_mittel((extra or {}).get(feld), tage)
    return wert


def boden_b(samples, fund_wert, ktrl_wert):
    """Das B-Mass auf einer Groesse, die in `extra` steht.

    Funde, bei denen die Groesse fehlt, fallen heraus und werden
    gezaehlt — sie stillschweigend als „nicht geschlagen" zu werten
    waere eine erfundene Beobachtung.
    """
    anteile, fehlend = [], 0
    for s in samples:
        f = fund_wert(s.get("extra"))
        extras = s.get("extra_controls") or []
        if f is None or len(extras) != len(s.get("controls") or []):
            fehlend += 1
            continue
        ks = [ktrl_wert(e) for e in extras]
        if any(k is None for k in ks):
            fehlend += 1
            continue
        anteil = ab.beat_fraction(f, ks)
        if anteil is not None:
            anteile.append(anteil)
    if not anteile:
        return None, fehlend
    return sum(anteile) / len(anteile), fehlend


def boden_kombi(samples, optimum, tage, sigma=None):
    """Bodenfeuchte MAL Glocke — die Ampel mit getauschtem Feuchtemass."""
    sigma = av.TEMP_SIGMA if sigma is None else sigma

    def wert(s, extra, paar):
        feuchte = boden_mittel((extra or {}).get("smoist"), tage)
        if feuchte is None:
            return None
        return feuchte * av.temperature_factor(paar[1], optimum, sigma)

    anteile, fehlend = [], 0
    for s in samples:
        extras = s.get("extra_controls") or []
        controls = s.get("controls") or []
        if len(extras) != len(controls):
            fehlend += 1
            continue
        f = wert(s, s.get("extra"), s["found"])
        ks = [wert(s, e, c) for e, c in zip(extras, controls)]
        if f is None or any(k is None for k in ks):
            fehlend += 1
            continue
        anteil = ab.beat_fraction(f, ks)
        if anteil is not None:
            anteile.append(anteil)
    return (sum(anteile) / len(anteile) if anteile else None), fehlend


def run_boden(args):
    """Die erste Auswertung der Bodenfeuchte — Diagnose auf P3."""
    if args.api:
        av.OPEN_METEO = args.api.rstrip("/")
    av.DEDUPE = args.dedupe
    av.use_dataset(args.dataset)
    if "smoist" not in av.EXTRA_FIELDS:
        raise SystemExit(
            f"Der Datensatz '{args.dataset}' liefert keine Bodenfeuchte. "
            "`--dataset pinned` holt sie mit.")
    print(f"Bodenfeuchte auf DE bis {av.FIT_UNTIL_YEAR} — Anpassjahre, "
          "keine Prüfachse", file=sys.stderr)

    mapping = av.read_species()
    wanted = SCHWELLEN_ARTEN
    if args.only:
        gesucht = {n.strip() for n in args.only.split(",") if n.strip()}
        wanted = [z for z in DESIGN_ARTEN if z[0] in gesucht]

    zeilen = []
    for name, gruppe, optimum in wanted:
        if name not in mapping:
            continue
        print(f"  {name}", file=sys.stderr)
        finds, _ = av.select_finds(mapping[name], args.cache, args.seed,
                                   True, ("DE",))
        if not finds:
            continue
        gezogen = av.collect_pairs_b(name, mapping[name], finds=finds,
                                     cache_dir=args.cache, seed=args.seed,
                                     progress=False)
        if not gezogen:
            continue
        samples = fit_years_only(gezogen["samples"])
        if len(samples) < SCHWELLEN_MIN_FUNDE:
            continue
        zeile = {
            "name": name, "gruppe": gruppe, "optimum": optimum,
            "n": len(samples),
            "voll": h1_b(samples, optimum, zerlegung_scorer(optimum, "voll")),
            "regen": h1_b(samples, optimum,
                          zerlegung_scorer(optimum, "nur Regen")),
            "temp": h1_b(samples, optimum,
                         zerlegung_scorer(optimum, "nur Temperatur")),
            "smoist": {}, "stemp": {}, "kombi": {}, "fehlend": 0,
        }
        for tage in BODEN_FENSTER:
            s = boden_scorer("smoist", tage)
            wert, fehlt = boden_b(samples, s, s)
            zeile["smoist"][tage] = wert
            zeile["fehlend"] = max(zeile["fehlend"], fehlt)
            zeile["kombi"][tage] = boden_kombi(samples, optimum, tage)[0]
        st = boden_scorer("stemp", av.TEMP_WINDOW)
        zeile["stemp"] = boden_b(samples, st, st)[0]
        zeilen.append(zeile)
        beste = max((v for v in zeile["smoist"].values() if v is not None),
                    default=None)
        print(f"    Regen {_fmt(zeile['regen'])}  "
              f"Bodenfeuchte bestes Fenster {_fmt(beste)}  "
              f"voll {_fmt(zeile['voll'])}", file=sys.stderr)

    bericht = render_boden(zeilen)
    if args.out:
        open(args.out, "w", encoding="utf-8").write(bericht)
        print(f"\n{args.out} geschrieben", file=sys.stderr)
    else:
        print(bericht)


def render_boden(zeilen):
    """Der Bericht zur ersten Bodenfeuchte-Auswertung."""
    import time as _t
    aus = []
    w = aus.append
    w("# Die Bodenfeuchte — die Spalte, die zwei Tage lang dalag\n")
    w(f"Stand: {_t.strftime('%Y-%m-%d')} · Erzeugt von "
      "`tool/ampel_diagnose.py --boden` · Betreiberfrage vom "
      "2026-09-19\n")
    w("> **Diese Datei wird erzeugt.** Wer sie von Hand ändert, "
      "verliert die Änderung beim nächsten Lauf.\n")
    w("> **P3 sind die Anpassjahre.** Jede Zahl hier ist eine Diagnose "
      "und kein Beleg.\n")

    w("## Warum das eine naheliegende Frage ist\n")
    w("Die Ampel rechnet eine gewichtete **Regensumme** über 26 Tage — "
      "einen Stellvertreter für das, was beim Myzel ankommt. Die "
      "Bodenfeuchte in 7 bis 28 cm Tiefe **ist** diese Größe, und zwar "
      "schon integriert: Versickerung, Verdunstung und Vorgeschichte "
      "stecken darin, ohne dass jemand eine Gewichtskurve setzen "
      "muss.\n")
    w("Für den Vergleich unten muss nichts geeicht werden: Das B-Maß "
      "ist rangbasiert, jede monotone Umformung lässt es unverändert. "
      "Verglichen wird also die **rohe** Bodenfeuchte gegen den "
      "fertigen Regenfaktor der App — kein Handicap für die App, eher "
      "eines für die Bodenfeuchte.\n")
    w("**Eine Einschränkung, die man dabei nicht übersehen darf.** Für "
      "die erste Spalte gilt die Rang-Unempfindlichkeit; für eine "
      "ausgelieferte Ampel nicht. Dort werden Feuchte und Glocke "
      "**multipliziert**, und ein Produkt hängt sehr wohl an der Skala "
      "seiner Faktoren — der Regenfaktor sättigt bei 87 mm, die rohe "
      "Bodenfeuchte sättigt nirgends. Genau deshalb steht die letzte "
      "Spalte unten nicht überall dort vorn, wo die "
      "Bodenfeuchte-Spalte vorn steht. Eine Ampel auf Bodenfeuchte "
      "bräuchte also **eine eigene Übertragungskurve** — eine neue "
      "Konstante, gesetzt oder angepasst. Der Gewinn wäre dann nicht "
      "„eine Konstante weniger“, sondern eine bessere "
      "Eingangsgröße.\n")

    w("## Was die Spalten heißen\n")
    w("- **Regen**: der ausgelieferte Regenfaktor allein, 26 Tage "
      "gewichtet.")
    w("- **Boden 1/7/14/26 d**: das Mittel der Bodenfeuchte über so "
      "viele Tage vor dem Tag, sonst nichts.")
    w("- **voll**: die ausgelieferte Ampel (Regen × Glocke).")
    w("- **Boden × Glocke**: dieselbe Formel mit getauschtem "
      "Feuchtemaß, bestes Fenster.\n")

    w("| Art | Funde | Regen | Boden 1 d | Boden 7 d | Boden 14 d | "
      "Boden 26 d | Temperatur | voll | Boden × Glocke |")
    w("|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|")
    for z in zeilen:
        beste_k = max((v for v in z["kombi"].values() if v is not None),
                      default=None)
        w(f"| {z['name']}{' ⚠' if z['n'] < MIN_FINDS_B else ''} | "
          f"{z['n']} | **{_fmt(z['regen'])}** | "
          + " | ".join(_fmt(z["smoist"].get(t)) for t in BODEN_FENSTER)
          + f" | {_fmt(z['temp'])} | **{_fmt(z['voll'])}** | "
          f"{_fmt(beste_k)} |")

    # --- Die Auswertung, gerechnet statt behauptet ---------------------
    if any(z["n"] < MIN_FINDS_B for z in zeilen):
        w(f"\n⚠ unter {MIN_FINDS_B} Funden — die Zeile steht zur "
          "Vollständigkeit da und trägt kein eigenes Urteil.")
    besser = [z for z in zeilen
              if z["regen"] is not None
              and max((v for v in z["smoist"].values() if v is not None),
                      default=-1) > z["regen"]]
    kombi_besser = [z for z in zeilen
                    if z["voll"] is not None
                    and max((v for v in z["kombi"].values()
                             if v is not None), default=-1) > z["voll"]]
    w("\n## Was daraus folgt\n")
    w(f"**Bei {len(besser)} von {len(zeilen)} Arten trennt die rohe "
      "Bodenfeuchte besser als der ausgelieferte Regenfaktor**, und bei "
      f"{len(kombi_besser)} von {len(zeilen)} schlägt „Bodenfeuchte × "
      "Glocke“ die ausgelieferte Ampel.\n")
    if zeilen:
        fenster_siege = {t: sum(1 for z in zeilen
                                if z["smoist"].get(t) is not None
                                and z["smoist"][t] == max(
                                    v for v in z["smoist"].values()
                                    if v is not None))
                         for t in BODEN_FENSTER}
        w("Welches Fenster je Art das beste ist: "
          + ", ".join(f"{t} d bei {n} " + ("Art" if n == 1 else "Arten")
                      for t, n in fenster_siege.items() if n) + ".\n")
        w("Ein an denselben Daten ausgesuchtes Fenster ist keine "
          "Messung — die Spalten stehen alle da, damit sichtbar ist, "
          "wie wenig die Wahl ausmacht.\n")
    w("**Das ist eine Diagnose und kein Beleg.** Die Fensterlänge ist "
      "hier an denselben Daten ausgesucht worden, auf denen sie bewertet "
      "wird — wer eine davon ausliefern will, braucht eine "
      "Registrierung mit EINEM eingefrorenen Fenster und eine Prüfachse. "
      "Die Zahlen oben sagen nur, ob sich das lohnt.\n")
    w("**Was hier noch nicht steht:** die Bodentemperatur "
      "(`soil_temperature_0_to_7cm`) liegt ebenso vollständig im Cache. "
      "Sie mit der Luft-Glocke zu bewerten wäre falsch — die Niveaus "
      "sind verschieden, das Optimum müsste neu bestimmt werden. Die "
      "Temperaturspalte oben ist die der Luft.")
    return "\n".join(aus) + "\n"

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--designs", action="store_true",
                        help="Phase 1.5: Design A und B "
                             "nebeneinander")
    parser.add_argument("--zerlegung", action="store_true",
                        help="Vorprüfung zu H5 auf P3 "
                             "(docs/pilzampel-h5-vorpruefung.md)")
    parser.add_argument("--logit", action="store_true",
                        help="N5: Optimum und Breite mit Standardfehler "
                             "— Information, kein Prüfwert")
    parser.add_argument("--h1", action="store_true",
                        help="der registrierte Prüflauf zu H1 "
                             "(docs/pilzampel-h1-registrierung.md)")
    parser.add_argument("--boden", action="store_true",
                        help="erste Auswertung der Bodenfeuchte, auf P3")
    parser.add_argument("--grafiken", action="store_true",
                        help="die Aussagen als SVG nach docs/bilder/")
    parser.add_argument("--h6-test", action="store_true",
                        dest="h6_test",
                        help="der registrierte Prüflauf zu H6 auf AT+CH "
                             "(docs/pilzampel-h6-registrierung.md)")
    parser.add_argument("--h6", action="store_true",
                        help="B aus Auftrag 3: die Vorprüfung zum "
                             "Sommer-Optimum, auf P3")
    parser.add_argument("--schwellen", action="store_true",
                        help="A aus Auftrag 3: die Schwellen an "
                             "Design-B-Kontrolltagen")
    parser.add_argument("--scheibe", default="p3", choices=("p3", "p1"),
                        help="Zeitscheibe für --schwellen. p1 ist "
                             "erlaubt, weil Schwelle und Rang disjunkt "
                             "sind; schwellenabhängige Gütemaße sind "
                             "dort gesperrt")
    parser.add_argument("--dataset", default="vorgabe")
    parser.add_argument("--dedupe", action="store_true")
    parser.add_argument("--api", default=None)
    parser.add_argument("--cache", default=None)
    parser.add_argument("--out", default=None)
    parser.add_argument("--only", default=None)
    parser.add_argument("--jahre", default=None,
                        help="Teilscheibe der Anpassjahre für "
                             "--zerlegung, z. B. 2006-2012")
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
    if args.zerlegung:
        run_zerlegung(args)
        raise SystemExit(0)
    if args.schwellen:
        run_schwellen(args)
        raise SystemExit(0)
    if args.h6:
        run_h6(args)
        raise SystemExit(0)
    if args.h6_test:
        run_h6_test(args)
        raise SystemExit(0)
    if args.grafiken:
        run_grafiken(args)
        raise SystemExit(0)
    if args.boden:
        run_boden(args)
        raise SystemExit(0)
    if not args.all:
        parser.print_help()
        raise SystemExit(0)
    run(args)
