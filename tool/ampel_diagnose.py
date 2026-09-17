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
import os
import random
import statistics
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "ampel_validate", os.path.join(_HERE, "ampel_validate.py"))
av = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(av)

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
        f"       recordedBy, countryCode, gbifID "
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
             "gbifID": r[7]} for r in rows]


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

    # --- Die Regel, die alles traegt ---
    gemischt = [dict(warm, year=j) for j in (2016, 2018, 2019, 2024)]
    nur_fit = fit_years_only(gemischt)
    assert [s["year"] for s in nur_fit] == [2016, 2018], \
        "Pruefjahre duerfen in Phase 1 nicht auftauchen"
    assert av.FIT_UNTIL_YEAR == 2018

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
        w("| Art | AUC der Art | AUC der Referenz | Ueberschuss |")
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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--all", action="store_true")
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
    if not args.all:
        parser.print_help()
        raise SystemExit(0)
    run(args)
