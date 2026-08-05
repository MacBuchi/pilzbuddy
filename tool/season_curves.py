#!/usr/bin/env python3
"""Baut aus GBIF-Funddaten eine Saisonkurve je Pilzart.

Die erste Zutat der Pilzampel (docs/pilzampel-konzept.md, Stufe 2) — und
die einzige, die ohne Modellannahme auskommt: Sie kommt aus echten
Beobachtungen. Das Ergebnis ist eine generierte Dart-Konstante, die im
Binary mitfährt:

    lib/core/season_curves.g.dart   91 Arten x 12 Monate

Deshalb eine Konstante und kein Release-Asset wie die Regengitter: Diese
Zahlen ändern sich über Jahre, nicht über Stunden. Sie brauchen keinen
Cron, keinen Ladezustand und kein Netz — im Wald steht die Kurve einfach da.

Aufruf:
    python3 tool/season_curves.py --out lib/core/season_curves.g.dart
    python3 tool/season_curves.py --verify      # Gegenprobe am Dienst
    python3 tool/season_curves.py --self-test   # ohne Netz

Nur Standardbibliothek, wie tool/rain_grid.py und tool/feedback_bot.py.

DIE EFFORT-KORREKTUR IST DER GANZE PUNKT. September und Oktober tragen
41 % aller Pilzmeldungen überhaupt — wer die Rohkurve nimmt, baut die
Gewohnheiten der Melder ins Modell und bekommt für jede Art denselben
Herbstberg. Geteilt wird deshalb durch den Monatsgang ALLER Fungi
(kingdomKey=5, gleiche Filter): Übrig bleibt, wann diese Art im Vergleich
zur allgemeinen Pilzsaison auffällig oft gemeldet wird. Beim Pfifferling
wandert der Gipfel dadurch von August auf Juli.

Was das für die Anzeige bedeutet, und es steht auch so im UI: Der Wert ist
RELATIV zur Pilzsaison, nicht absolut, und er beschreibt Meldungen, keine
Vorhersage.

ZWEI FALLEN, BEIDE STILL, BEIDE AM 2026-08-05 EINGETRETEN:

1. Ein Name, den GBIF nicht kennt, wirft KEINEN Fehler — `species/match`
   klettert die Taxonomie hoch und liefert zufrieden einen Treffer.
   `Agaricus silvaticus` (Tippfehler für `sylvaticus`) kam als CLASS
   Agaricomycetes zurück, mit 1.445.637 Beobachtungen. Die Kurve für
   „Waldchampignon" wäre die Kurve aller Blätterpilze gewesen, und sie
   hätte völlig plausibel ausgesehen.

2. Ein SYNONYM-Name liefert nur die Meldungen, die genau diesen Namen
   tragen — nicht die der Art. `Lactarius volemus`: 54 statt 909.
   `Morchella conica`: 215 statt 1052. Auch das sieht nach einer dünnen,
   aber echten Kurve aus.

Gegen beides steht [check_taxon]: EXACT, ACCEPTED, Rang SPECIES oder
GENUS — sonst Abbruch statt Warnung. Ein falscher Name muss den Lauf
kosten, sonst landet er in der App.

LIZENZFILTER: Nur CC0 und CC BY 4.0. GBIF mischt CC-BY-NC-Datensätze
darunter (beim Steinpilz 26 % der Meldungen); die bleiben draußen, damit
aus einer Play-Veröffentlichung keine Lizenzfrage wird. Der Preis ist
gemessen und in docs/pilzampel-saisonkurven.md notiert.
"""
import argparse
import json
import random
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.gbif.org/v1"

SPECIES_FILE = "lib/core/mushroom_species.dart"
DEFAULT_OUT = "lib/core/season_curves.g.dart"

# Die Filter, die für Artenkurve UND Effort-Baseline gelten müssen — sonst
# dividiert man zwei verschieden erhobene Grundgesamtheiten durcheinander.
BASE_FILTER = {
    "country": ["DE", "AT", "CH"],
    "basisOfRecord": "HUMAN_OBSERVATION",
    "hasCoordinate": "true",
    "license": ["CC0_1_0", "CC_BY_4_0"],
}

# Der Monatsgang aller Fungi. Ein einziger Aufruf, geteilt durch alle Arten.
BASELINE_QUERY = {"kingdomKey": 5}

# Die beiden Qualitätsschwellen. Sie stehen hier nur, um beim Lauf zu
# melden, welche Art durchfällt — WIRKSAM sind sie in
# lib/core/season_curves.dart, das über `isReliable` entscheidet. Gebaut
# werden alle Kurven, auch die dünnen: In der Doku sollen sie sichtbar
# bleiben, sonst diskutiert niemand über die Schwelle.
#
# Zwölf Monatsfächer aus 90 Meldungen sind Rauschen mit Nachkommastellen.
MIN_OBSERVATIONS = 200

# Und die Gesamtzahl allein genügt nicht — siehe [peak_support].
MIN_PEAK_SUPPORT = 30

MONTHS = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun",
          "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]


class TaxonError(Exception):
    """Eine Zuordnung, der nicht zu trauen ist. Bricht den Lauf ab."""


def _get(path, params, retries=3):
    query = urllib.parse.urlencode(params, doseq=True)
    url = f"{API}/{path}?{query}"
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                return json.load(response)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
            if attempt == retries - 1:
                raise
            time.sleep(2 * (attempt + 1))
    raise AssertionError("unerreichbar")


def read_species(path=SPECIES_FILE):
    """Die Artenliste kommt aus der Dart-Datei, nicht aus einer Kopie hier.

    Zwei Listen wären zwei Wahrheiten: Eine Art, die der Feedback-Bot
    einträgt, fiele in einer Kopie still durch. Gelesen wird dieselbe
    Datei, die er beschreibt (Muster: tool/feedback_bot.py).
    """
    text = open(path, encoding="utf-8").read()
    species = []
    for match in re.finditer(r"KnownSpecies\('([^']+)',[^)]*?\)", text):
        entry = match.group(0)
        name = match.group(1)
        if "sameAs:" in entry:
            continue  # Zweitname, erbt die Kurve seiner Hauptbezeichnung
        sci = re.search(r"sci: '([^']+)'", entry)
        if sci:
            species.append((name, sci.group(1)))
    return species


def check_taxon(sci):
    """Schlägt einen wissenschaftlichen Namen nach — misstrauisch.

    Siehe Falle 1 und 2 im Kopf: Ein unsauberer Treffer ist hier gefährlicher
    als gar keiner, weil er eine vollständig plausible Kurve erzeugt.
    """
    match = _get("species/match", {"name": sci, "kingdom": "Fungi"})
    kind = match.get("matchType")
    status = match.get("status")
    rank = match.get("rank")
    key = match.get("usageKey")
    if kind != "EXACT":
        raise TaxonError(
            f"'{sci}': GBIF antwortet mit matchType={kind} auf Rang {rank} "
            f"({match.get('canonicalName')}). Ein Tippfehler klettert hier "
            f"stillschweigend die Taxonomie hoch — Name prüfen.")
    if status != "ACCEPTED":
        raise TaxonError(
            f"'{sci}': GBIF führt den Namen als {status}, akzeptiert ist "
            f"'{match.get('accepted') or match.get('canonicalName')}'. Unter "
            f"einem Synonym zählt nur ein Bruchteil der Meldungen — den "
            f"akzeptierten Namen eintragen.")
    if rank not in ("SPECIES", "GENUS"):
        raise TaxonError(
            f"'{sci}': Rang {rank}. Erlaubt sind SPECIES und GENUS; alles "
            f"darüber vermischt Arten, die nichts miteinander zu tun haben.")
    return key, rank


def month_counts(query):
    """Meldungen je Monat (Index 0 = Januar) plus Gesamtzahl."""
    result = _get("occurrence/search", {
        **BASE_FILTER, **query, "facet": "month", "facetLimit": 12, "limit": 0})
    counts = [0] * 12
    for bucket in result["facets"][0]["counts"] if result["facets"] else []:
        month = int(bucket["name"])
        counts[month - 1] = bucket["count"]
    return counts, result["count"]


def effort_corrected(counts, baseline):
    """Der Kern: Monatsanteil der Art / Monatsanteil aller Pilze, Max = 100.

    Beide Anteile beziehen sich auf ihre eigene Summe, die Division kürzt
    die Grundgesamtheiten also heraus. Übrig bleibt ein Verhältnis, das
    nur noch aussagt: In welchem Monat ist diese Art unter den gemeldeten
    Pilzen überdurchschnittlich vertreten?
    """
    total = sum(counts)
    base_total = sum(baseline)
    if total == 0 or base_total == 0:
        return [0] * 12
    ratios = []
    for index in range(12):
        if baseline[index] == 0:
            ratios.append(0.0)
            continue
        share = counts[index] / total
        base_share = baseline[index] / base_total
        ratios.append(share / base_share)
    peak = max(ratios)
    if peak == 0:
        return [0] * 12
    return [round(value / peak * 100) for value in ratios]


def as_index(counts):
    """Die Rohkurve, ebenfalls auf Max = 100 — zum Vergleich in der Doku.

    Sie bleibt im Generat, weil sonst niemand nachprüfen kann, was die
    Korrektur eigentlich bewirkt hat.
    """
    peak = max(counts) if counts else 0
    if peak == 0:
        return [0] * 12
    return [round(value / peak * 100) for value in counts]


def build(species, progress=True):
    """Holt Baseline und Kurven. Wirft bei jeder zweifelhaften Zuordnung."""
    baseline, baseline_total = month_counts(BASELINE_QUERY)
    if progress:
        print(f"Effort-Baseline: {baseline_total} Pilzmeldungen in DE/AT/CH",
              file=sys.stderr)

    rows = []
    for position, (name, sci) in enumerate(species, start=1):
        key, rank = check_taxon(sci)
        counts, total = month_counts({"taxonKey": key})
        months = effort_corrected(counts, baseline)
        support = peak_support(counts, months)
        rows.append({
            "name": name,
            "sci": sci,
            "key": key,
            "rank": rank,
            "total": total,
            "support": support,
            "raw": as_index(counts),
            "months": months,
            "counts": counts,
        })
        if progress:
            note = ""
            if total < MIN_OBSERVATIONS:
                note = "  (zu wenige Beobachtungen)"
            elif support < MIN_PEAK_SUPPORT:
                note = f"  (Gipfel steht auf nur {support} Meldungen)"
            print(f"  [{position:>2}/{len(species)}] {name}: {total}{note}",
                  file=sys.stderr)
        time.sleep(0.1)  # dem Dienst zuliebe, er ist kostenlos
    return rows, baseline, baseline_total


def peak_support(counts, months):
    """Die kleinste Meldungszahl unter den Monaten der Hauptzeit.

    **Die Schwachstelle der Effort-Korrektur, gemessen am 2026-08-05.** Sie
    teilt durch den Monatsanteil aller Pilze, und der ist im Winter klein.
    Eine Art mit sechs Dezember-Meldungen bekommt so einen Balken von 93 —
    er steht auf sechs Meldungen und sieht aus wie eine Aussage
    (Igelstachelbart, n=94).

    Die Gesamtzahl allein fängt das nicht: Sie kann bequem über der
    Schwelle liegen, während der Gipfel selbst auf einer Handvoll Meldungen
    steht. Deshalb wandert dieser Wert mit in die App, die damit entscheidet
    (`SeasonCurve.isReliable` in lib/core/season_curves.dart).
    """
    run = peak_run(months)
    if not run:
        return 0
    return min(counts[index] for index in run)


def peak_run(months):
    """Die zusammenhängenden Monate der Hauptzeit (Index 0 = Januar).

    **Ausgedehnt vom stärksten Monat aus**, nicht vom kalendarisch ersten.
    Hat eine Kurve zwei getrennte Erhebungen — was bei dünnen Wintermonaten
    nach der Effort-Korrektur vorkommt —, gewinnt sonst die frühere, auch
    wenn die spätere doppelt so hoch ist.

    Über den Jahreswechsel hinweg; die Dart-Seite rechnet dasselbe, und
    beide Tests halten dieselbe Kurve fest (Austernseitling, Dez/Jan).
    """
    peak = max(months) if months else 0
    if peak == 0:
        return []
    threshold = peak * 0.8
    start = end = months.index(peak)
    while months[(start - 1) % 12] >= threshold and (end - start) % 12 < 11:
        start -= 1
    while months[(end + 1) % 12] >= threshold and (end - start) % 12 < 11:
        end += 1
    return [index % 12 for index in range(start, end + 1)]


def peak_label(months):
    """„Aug–Sep" — die zusammenhängenden Monate ab 80 % des Maximums.

    Über den Jahreswechsel hinweg, sonst zerfiele die Kurve des
    Austernseitlings (Dez/Jan) in zwei Enden.
    """
    run = peak_run(months)
    if not run or len(run) == 12:
        # Keine Daten oder praktisch flach — beides hat keinen Gipfel zu
        # nennen. Unterscheiden muss das die App, nicht dieses Etikett.
        return ""
    if len(run) == 1:
        return MONTHS[run[0]]
    return f"{MONTHS[run[0]]}–{MONTHS[run[-1]]}"


def render_dart(rows, baseline_total, fetched_on):
    """Erzeugt lib/core/season_curves.g.dart."""
    lines = [
        "// GENERIERT von tool/season_curves.py — nicht von Hand ändern.",
        "//",
        "// Saisonkurven aus GBIF-Beobachtungen (DE/AT/CH, nur menschliche",
        "// Beobachtungen mit Koordinate, CC0 und CC BY 4.0). `months` ist",
        "// effort-korrigiert: Monatsanteil der Art geteilt durch den",
        "// Monatsanteil aller Pilze, Maximum auf 100 normiert. `raw` ist",
        "// dieselbe Kurve ohne Korrektur — sie steht daneben, damit",
        "// nachprüfbar bleibt, was die Korrektur bewirkt.",
        "//",
        f"// Abgerufen am {fetched_on} gegen {baseline_total} Pilzmeldungen",
        "// als Effort-Baseline. Neu bauen:",
        "//   python3 tool/season_curves.py --out lib/core/season_curves.g.dart",
        "",
        "import 'season_curves.dart';",
        "",
        "const kSeasonCurves = <String, SeasonCurve>{",
    ]
    for row in sorted(rows, key=lambda r: r["name"]):
        months = ", ".join(str(value) for value in row["months"])
        raw = ", ".join(str(value) for value in row["raw"])
        lines += [
            f"  '{row['name']}': SeasonCurve(",
            f"    sci: '{row['sci']}',",
            f"    taxonKey: {row['key']},",
            f"    isGenus: {'true' if row['rank'] == 'GENUS' else 'false'},",
            f"    observations: {row['total']},",
            f"    peakSupport: {row['support']},",
            f"    months: [{months}],",
            f"    raw: [{raw}],",
            "  ),",
        ]
    lines += ["};", ""]
    return "\n".join(lines)


def verify(rows, sample=8, progress=True):
    """Gegenprobe: Facet-Zahlen gegen Einzelabfragen mit `month=N`.

    Dieselbe Rolle wie `--verify` bei den Regengittern — ein zweiter Kanal
    zum selben Wert. Eine Facette ist eine Aggregation über der Suche; wenn
    Filter und Aggregation auseinanderlaufen, sieht man das nur so.
    """
    checked = 0
    for row in random.sample(rows, min(sample, len(rows))):
        month = max(range(12), key=lambda i: row["counts"][i]) + 1
        expected = row["counts"][month - 1]
        actual = _get("occurrence/search", {
            **BASE_FILTER, "taxonKey": row["key"], "month": month, "limit": 0,
        })["count"]
        if actual != expected:
            raise SystemExit(
                f"Gegenprobe fehlgeschlagen: {row['name']} ({row['sci']}), "
                f"Monat {month}: Facette sagt {expected}, Einzelabfrage "
                f"{actual}. Die Kurven NICHT ausliefern.")
        checked += 1
        if progress:
            print(f"  ok: {row['name']}, Monat {month} = {expected}",
                  file=sys.stderr)
        time.sleep(0.1)
    print(f"Gegenprobe: {checked} Stichproben stimmen überein",
          file=sys.stderr)


# --- Selbsttest -------------------------------------------------------------
#
# Netzfrei. Die Zähler unten sind echte, am 2026-08-05 gemessene Werte —
# ungefiltert, weil die Tabelle in docs/pilzampel-konzept.md aus denselben
# stammt. Geprüft wird damit die METHODE gegen ein dokumentiertes Ergebnis,
# nicht der Datenstand: Der ändert sich täglich, die Rechnung nicht.

# Monatsmeldungen aller Fungi in DE/AT/CH (Jan..Dez).
_BASELINE_FIXTURE = [83244, 68803, 80067, 109039, 125700, 163667,
                     196118, 320226, 471977, 510262, 181515, 77281]

_FIXTURES = {
    # Steinpilz. docs/pilzampel-konzept.md:
    # Jun 22 - Jul 61 - Aug 98 - Sep 100 - Okt 73 - Nov 37
    "Steinpilz": {
        "counts": [15, 8, 3, 1, 19, 307, 1010, 2632, 3972, 3122, 568, 30],
        "expect": {6: 22, 7: 61, 8: 98, 9: 100, 10: 73, 11: 37},
        "peak": "Aug–Sep",
    },
    # Austernseitling — Kältefrüchter, Gipfel über den Jahreswechsel.
    # docs/pilzampel-konzept.md: Nov 31 - Dez 100 - Jan 91 - Feb 55
    "Austernseitling": {
        "counts": [1090, 551, 214, 80, 53, 86, 76, 100, 213, 549, 801, 1116],
        "expect": {11: 31, 12: 100, 1: 91, 2: 55},
        "peak": "Dez–Jan",
    },
}

# Der Zweitname trägt hier absichtlich BEIDES — `sameAs` und `sci`. In der
# echten Liste kommt das nicht vor, und ohne diesen Fall im Fixture prüft
# der Test den `sameAs`-Filter gar nicht: Ein Zweitname ohne `sci` fällt
# schon durch die zweite Bedingung. Genau so entstehen Filter, die niemand
# absichert und die beim nächsten Anfassen still verschwinden.
_DART_SAMPLE = """
const kBekannteArten = <KnownSpecies>[
  KnownSpecies('Steinpilz', _roe, sci: 'Boletus edulis'),
  KnownSpecies('Herrenpilz', _roe, sameAs: 'Steinpilz', sci: 'Boletus edulis'),
  KnownSpecies('Netzstieliger Hexenröhrling', _roe, sci: 'Suillellus luridus'), // via In-App-Wunsch
  KnownSpecies('Eigenbau', _son),
];
"""


def self_test():
    for name, fixture in _FIXTURES.items():
        months = effort_corrected(fixture["counts"], _BASELINE_FIXTURE)
        for month, expected in fixture["expect"].items():
            actual = months[month - 1]
            assert actual == expected, (
                f"{name}, {MONTHS[month - 1]}: {actual} statt {expected} — "
                f"die Effort-Korrektur weicht von docs/pilzampel-konzept.md ab")
        label = peak_label(months)
        assert label == fixture["peak"], \
            f"{name}: Gipfel '{label}' statt '{fixture['peak']}'"

    # Ohne Korrektur läge der Steinpilz-Gipfel im Oktober — genau der
    # Melder-Effekt, den die Korrektur entfernt. Bliebe sie aus, fiele es
    # sonst niemandem auf.
    raw = as_index(_FIXTURES["Steinpilz"]["counts"])
    assert raw.index(100) == 8, "Rohkurve: Gipfel sollte im September liegen"
    corrected = effort_corrected(
        _FIXTURES["Steinpilz"]["counts"], _BASELINE_FIXTURE)
    assert corrected[7] > raw[7], \
        "Die Korrektur muss den August anheben, sonst wirkt sie nicht"

    # Leere und einzelne Eingaben dürfen nicht durch eine Division fallen.
    assert effort_corrected([0] * 12, _BASELINE_FIXTURE) == [0] * 12
    assert as_index([0] * 12) == [0] * 12
    assert peak_label([0] * 12) == ""
    single = [0] * 12
    single[4] = 100
    assert peak_label(single) == "Mai"

    # Der Leser der Dart-Datei: Zweitnamen raus, Arten ohne `sci` raus,
    # Zeilenkommentare stören nicht.
    import tempfile
    import os
    handle, path = tempfile.mkstemp(suffix=".dart")
    with os.fdopen(handle, "w", encoding="utf-8") as file:
        file.write(_DART_SAMPLE)
    try:
        parsed = read_species(path)
    finally:
        os.unlink(path)
    assert parsed == [("Steinpilz", "Boletus edulis"),
                      ("Netzstieliger Hexenröhrling", "Suillellus luridus")], \
        f"Artenleser liefert {parsed}"

    # Und derselbe Leser gegen die echte Datei — sie ist die Quelle.
    real = read_species()
    assert len(real) >= 80, f"Nur {len(real)} Arten mit `sci` gefunden"
    names = [name for name, _ in real]
    assert len(names) == len(set(names)), "Doppelte Art in der Liste"

    # Die Stützung des Gipfels — der Wert, an dem die App eine Kurve
    # verwirft, deren Hauptzeit auf einer Handvoll Meldungen steht.
    steinpilz = _FIXTURES["Steinpilz"]["counts"]
    assert peak_run(corrected) == [7, 8], \
        f"Steinpilz-Hauptzeit: {peak_run(corrected)} statt August/September"
    assert peak_support(steinpilz, corrected) == 2632, \
        "Stützung ist der SCHWÄCHSTE Monat der Hauptzeit, nicht der stärkste"

    # Der Fall, der die Prüfung überhaupt nötig macht: genug Meldungen im
    # Jahr, aber der Gipfel liegt in einem Wintermonat mit fast nichts
    # drin. Der Dezember trägt die kleinste Effort-Baseline, also hebt die
    # Korrektur ihn am stärksten — 22 Meldungen schlagen 200 im Oktober.
    # Die Gesamtzahl merkt davon nichts, nur die Stützung.
    winter = [0, 0, 0, 0, 0, 0, 0, 0, 10, 150, 25, 25]
    winter_months = effort_corrected(winter, _BASELINE_FIXTURE)
    assert winter_months.index(100) == 11, \
        f"Erwartet: Dezember-Gipfel, bekommen: {winter_months}"
    assert sum(winter) > MIN_OBSERVATIONS, \
        "Die Gesamtzahl muss über der Schwelle liegen, sonst prüft der Fall nichts"
    assert peak_support(winter, winter_months) < MIN_PEAK_SUPPORT, \
        f"Stützung {peak_support(winter, winter_months)} — die Kurve muss hier scheitern"

    # Zwei getrennte Erhebungen: Die Hauptzeit ist die HÖHERE, nicht die
    # frühere. Ohne diese Regel gewinnt der Januar-Ausläufer über den
    # Oktobergipfel, nur weil er im Kalender vorn steht.
    twin = [0] * 12
    twin[0], twin[9] = 85, 100
    assert peak_run(twin) == [9], f"Zwei Gipfel: {peak_run(twin)} statt [9]"

    # Die Dart-Ausgabe muss gültig aussehen und die Zahlen tragen.
    rendered = render_dart([{
        "name": "Steinpilz", "sci": "Boletus edulis", "key": 5954958,
        "rank": "SPECIES", "total": 8789, "support": 2632,
        "raw": raw, "months": corrected,
    }], 2544089, "2026-08-05")
    assert "import 'season_curves.dart';" in rendered
    assert "'Steinpilz': SeasonCurve(" in rendered
    assert "isGenus: false," in rendered
    assert "peakSupport: 2632," in rendered
    assert f"months: [{', '.join(str(v) for v in corrected)}]," in rendered

    print("season_curves self-test: ok")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=DEFAULT_OUT,
                        help=f"Zieldatei (Vorgabe: {DEFAULT_OUT})")
    parser.add_argument("--verify", action="store_true",
                        help="Gegenprobe gegen den Dienst statt Neubau")
    parser.add_argument("--self-test", action="store_true",
                        help="Rechnung und Leser prüfen, ohne Netz")
    parser.add_argument("--fetched-on", default=None,
                        help="Abrufdatum für den Kopf der Datei (JJJJ-MM-TT)")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return

    species = read_species()
    print(f"{len(species)} Arten mit wissenschaftlichem Namen", file=sys.stderr)
    try:
        rows, _, baseline_total = build(species)
    except TaxonError as error:
        raise SystemExit(f"\nZuordnung unbrauchbar — {error}")

    if args.verify:
        verify(rows)
        return

    fetched_on = args.fetched_on or time.strftime("%Y-%m-%d")
    open(args.out, "w", encoding="utf-8").write(
        render_dart(rows, baseline_total, fetched_on))

    print(f"\n{args.out}: {len(rows)} Kurven", file=sys.stderr)
    thin = [r for r in rows if r["total"] < MIN_OBSERVATIONS]
    weak = [r for r in rows
            if r["total"] >= MIN_OBSERVATIONS
            and r["support"] < MIN_PEAK_SUPPORT]
    if thin:
        print(f"Unter {MIN_OBSERVATIONS} Beobachtungen (die App zeigt sie "
              f"nicht): " + ", ".join(f"{r['name']} ({r['total']})"
                                      for r in thin), file=sys.stderr)
    if weak:
        print(f"Gipfel unter {MIN_PEAK_SUPPORT} Meldungen gestützt (die App "
              f"zeigt sie nicht): "
              + ", ".join(f"{r['name']} ({r['support']})" for r in weak),
              file=sys.stderr)


if __name__ == "__main__":
    main()
