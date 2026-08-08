#!/usr/bin/env python3
"""Prüft rückwärts, ob das Pilzampel-Wettermodell überhaupt etwas taugt.

Die Bedingung aus docs/pilzampel-konzept.md, wörtlich: „Steht die Ampel an
Fundtagen höher als an zufälligen Tagen derselben Saison? Wenn nicht, taugt
das Modell nichts — und das merkt man VOR dem Ausliefern."

Das ist der Schritt, an dem das deutsche Forschungsprojekt Pilz4You
gescheitert ist: Modell gebaut, nie veröffentlicht, weil die
Fundbeobachtungen als Zielgröße fehlten. Keiner der ~45 recherchierten
Dienste publiziert eine Validierung. Hier lässt sich eine machen.

    python3 tool/ampel_validate.py --out docs/pilzampel-validierung.md
    python3 tool/ampel_validate.py --crosscheck   # Saison gegen Mushroom Observer
    python3 tool/ampel_validate.py --self-test    # ohne Netz

Nur Standardbibliothek, wie tool/season_curves.py und tool/rain_grid.py.

DER ZIRKELSCHLUSS, DER VERMIEDEN WERDEN MUSS. Die Saisonkurven aus 1.56.0
sind selbst aus GBIF gerechnet. Mit GBIF-Funden zu validieren und den
Saisonfaktor mitlaufen zu lassen hieße: Das Modell bestätigt sich selbst.
Deshalb steht im Konzept „zufällige Tage DERSELBEN Saison" — die
Vergleichstage liegen am selben Ort im selben Jahr, wenige Wochen neben dem
Fund. Der Saisonfaktor ist für beide praktisch gleich und kürzt sich heraus;
gemessen wird allein der Wetterbeitrag. Er geht hier nicht ein.

ZWEI KONTROLLEN, UND SIE PRÜFEN VERSCHIEDENES.

1. Die PLACEBO-Kontrolle prüft die METHODE. Statt Fundtag gegen
   Vergleichstag treten zwei Vergleichstage gegeneinander an — beide ohne
   Fund, beide nach derselben Vorschrift gezogen. Hier MUSS 0,5
   herauskommen. Steht dort etwas anderes, verzerrt die Ziehung selbst
   (etwa weil ein Tag später im Jahr systematisch feuchter ist), und dann
   ist jede Zahl darüber wertlos.

2. Die ARTEN-Kontrolle prüft, ob das Modell artspezifisch wirkt. Sie
   umfasst Holzbewohner — Hallimasch, Stockschwämmchen, Austernseitling.
   **Vorsicht mit der Begründung:** Diese Arten hängen NICHT etwa gar
   nicht am Wetter. Der Austernseitling ist ein Kältefrüchter mit Gipfel
   im Dezember; er reagiert sehr wohl, nur auf anderes. Was hier geprüft
   wird, ist enger: Dieses Modell — Glocke um 13 °C, 26-Tage-Regensumme,
   beides aus der Steinpilz-Literatur — darf bei ihnen NICHT passen. Ein
   Wert unter 0,5 ist deshalb kein Fehlschlag, sondern ein Beleg: Das
   Modell misst nicht bloß „im Herbst wird mehr gemeldet".

Was BEIDE Kontrollen nicht leisten müssen: den Waldtyp herausrechnen. Das
erledigt der Aufbau. Fund- und Vergleichstag liegen am SELBEN Ort — gleicher
Wald, gleiche Baumart, gleicher Boden. Der Standortfaktor, der bei
Holzbewohnern 56–59 % der Varianz erklärt (Alday/Karavani et al. 2017),
kürzt sich damit vollständig heraus. Die Frage lautet nur: Warum an DIESEM
Tag und nicht drei Wochen später am selben Fleck?

WARUM NUR GBIF UND KEINE FOREN (gemessen 2026-08-06). Mushroom Observer und
Pilzforen nennen den Ort als Region („southwestern Germany", 0 von 100
Meldungen mit Koordinate). Im DWD-Raster reicht die 30-Tage-Regensumme
innerhalb genau dieser Region von 14 mm (10 %) bis 82 mm (90 %) — Faktor
5,9, bei einer Sammlerschwelle von ~100 mm. Der Unterschied zwischen Dürre
und guten Bedingungen liegt vollständig INNERHALB der Ortsangabe; als
unabhängige Variable wäre sie Rauschen. GBIF liefert dagegen einen Median
von 250 m. Für die Saison-Gegenprüfung (--crosscheck) genügt die grobe
Angabe, dort zählt nur der Monat.
"""
import argparse
import json
import math
import os
import random
import re
import statistics
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

GBIF = "https://api.gbif.org/v1"
OPEN_METEO = "https://archive-api.open-meteo.com/v1/archive"
MUSHROOM_OBSERVER = "https://mushroomobserver.org/api2/observations"

SPECIES_FILE = "lib/core/mushroom_species.dart"

# Das RADOLAN-Archiv des DWD beginnt 2006; auch wenn hier Open-Meteo die
# Werte liefert, bleibt es die Grenze, ab der sich jede Zahl gegen deutsche
# Radardaten nachprüfen ließe.
FIRST_YEAR = 2006

# Gröber als das ist die Ortsangabe der Meldungen ohnehin nicht (Median
# 250 m), und schlechter als 1 km wäre für ein 1-km-Wetterraster wertlos.
MAX_UNCERTAINTY_M = 1000

# So viele Funde je Art werden ausgewertet — eine Zufallsstichprobe mit
# festem Seed, keine Auswahl nach Güte.
#
# WARUM NICHT ALLE, und die Rechnung dazu: Open-Meteo zählt seine Aufrufe
# gewichtet (Orte × Variablen × Tage/365). Alle Funde über die ganze
# Saison wären rund 22.600 Aufrufe für neun Arten — bei einem Tageslimit
# von 10.000. Der erste Versuch lief deshalb mitten in der zweiten Art in
# ein hartes „try again tomorrow".
#
# Und mehr braucht es nicht: Der Standardfehler einer AUC liegt bei 500
# Paaren um 0,02. Für die Frage, ob dort 0,50 oder 0,58 steht, ist das
# reichlich genau — die Unsicherheit des MODELLS ist um ein Vielfaches
# grösser als die der Stichprobe.
SAMPLE_PER_SPECIES = 500

# Die Arten, für die gerechnet wird. Mykorrhiza-Speisepilze — bei ihnen
# erwartet die Literatur einen Wettereffekt.
MYCORRHIZAL = [
    "Steinpilz",
    "Maronenröhrling",
    "Pfifferling",
    "Birkenpilz",
    "Fichtenreizker",
    "Herbsttrompete",
]

# Die Arten-Kontrolle. Nicht „die spüren kein Wetter" — der
# Austernseitling ist ein Kältefrüchter mit Gipfel im Dezember. Geprüft
# wird, dass DIESES Modell (13 °C, Steinpilz-Literatur) bei ihnen nicht
# passt; siehe Kopf.
WOOD_DWELLERS = [
    "Hallimasch",
    "Stockschwämmchen",
    "Austernseitling",
]

# --- Das Modell ------------------------------------------------------------
#
# Nach docs/pilzampel-konzept.md, kalibriert mit den Bielefelder Zahlen
# (Brejon Lamartiniere & Hoffman 2025, zehn Jahre nahezu tägliche
# Steinpilz-Erfassung): Fruchtungsgipfel bei ~13 °C Mitteltemperatur über
# die vorangegangenen 20 Tage, linear steigend mit dem über 26 Tage
# kumulierten Niederschlag.

RAIN_WINDOW = 26
TEMP_WINDOW = 20
OPTIMUM_C = 13.0

# Die Breite der Temperaturglocke ist GESETZT, nicht gemessen — das
# Bielefelder Papier nennt einen Gipfel, keine Streuung. 5 K heißt: bei
# 8 °C und 18 °C ist der Faktor noch gut ein Drittel.
TEMP_SIGMA = 5.0

# Ab dieser Kumulation gilt die Feuchte als voll — die Sammlerregel für
# 30 Tage lautet >=100 mm, auf 26 Tage heruntergerechnet.
RAIN_SATURATION_MM = 87.0


def rain_factor(daily_mm):
    """Gewichtete Niederschlagskumulation, 0…1.

    `daily_mm[0]` ist der Vortag, `daily_mm[-1]` der älteste Tag. Ältere
    Tage zählen linear schwächer: Was vor vier Wochen fiel, ist teils
    versickert und verdunstet.

    Für die AUC unten wäre die genaue Kurvenform gleichgültig — sie ist
    rangbasiert, und jede monotone Umformung lässt sie unverändert. Sie
    zählt erst, wo Feuchte und Temperatur multipliziert werden.
    """
    if not daily_mm:
        return 0.0
    weighted = 0.0
    weights = 0.0
    for age, mm in enumerate(daily_mm[:RAIN_WINDOW]):
        weight = 1.0 - age / RAIN_WINDOW
        weighted += (mm or 0.0) * weight
        weights += weight
    if weights == 0:
        return 0.0
    # Auf die Skala „so viel wie bei gleichmäßiger Verteilung" bringen.
    effective = weighted / weights * RAIN_WINDOW
    return min(effective / RAIN_SATURATION_MM, 1.0)


def temperature_factor(daily_c):
    """Glocke um 13 °C über das Mittel der letzten 20 Tage, 0…1."""
    values = [c for c in daily_c[:TEMP_WINDOW] if c is not None]
    if not values:
        return 0.0
    mean = sum(values) / len(values)
    return math.exp(-(((mean - OPTIMUM_C) / TEMP_SIGMA) ** 2))


def ampel_score(daily_mm, daily_c):
    """Der Wetterteil der Ampel — OHNE Saisonfaktor, siehe Kopf."""
    return rain_factor(daily_mm) * temperature_factor(daily_c)


# --- Statistik -------------------------------------------------------------


def paired_auc(pairs):
    """Wie oft liegt der Fundtag über seinem Vergleichstag? 0,5 = zufällig.

    **Die Kennzahl, die zählt.** Bei 2500 Punkten wird jeder Mini-Effekt
    „signifikant"; ein p-Wert allein wäre Dekoration. Die AUC sagt, wie
    groß der Effekt IST — 0,55 heißt: in 55 von 100 Fällen liegt der
    Fundtag vorn. Für eine Ampel, die jemandem den Weg in den Wald
    ersparen soll, ist das die ehrliche Auskunft.

    Gepaart, nicht über alle gegen alle: Jedes Paar teilt Ort, Jahr und
    Jahreszeit. Was übrig bleibt, ist das Wetter.
    """
    if not pairs:
        return 0.5
    wins = 0.0
    for found, control in pairs:
        if found > control:
            wins += 1.0
        elif found == control:
            wins += 0.5
    return wins / len(pairs)


def permutation_p(pairs, rounds=2000, seed=42):
    """Wahrscheinlichkeit, die beobachtete AUC durch Zufall zu erreichen.

    Bei gepaarten Werten genügt es, die Rollen innerhalb eines Paares zu
    tauschen — das ist die Nullhypothese „es ist gleichgültig, welcher der
    beiden Tage der Fundtag war".

    Fester Seed, damit zwei Läufe dasselbe sagen.
    """
    if not pairs:
        return 1.0
    observed = paired_auc(pairs)
    rng = random.Random(seed)
    hits = 0
    for _ in range(rounds):
        shuffled = [
            (b, a) if rng.random() < 0.5 else (a, b) for a, b in pairs
        ]
        if paired_auc(shuffled) >= observed:
            hits += 1
    return (hits + 1) / (rounds + 1)


# --- GBIF ------------------------------------------------------------------


def _get(url, params, retries=6, timeout=90):
    """Ein Abruf mit Geduld.

    **429 („zu viele Anfragen") braucht eine andere Pause als ein
    Netzfehler.** Open-Meteo begrenzt pro Minute und pro Stunde; zwei
    Sekunden später wieder anzuklopfen ändert daran nichts. Der Lauf
    wartet deshalb bei 429 in wachsenden Schritten bis zu einer Minute.
    """
    query = urllib.parse.urlencode(params, doseq=True)
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(f"{url}?{query}", timeout=timeout) as r:
                return json.load(r)
        except urllib.error.HTTPError as error:
            # 5xx ist ein Serverproblem und so flüchtig wie ein
            # Netzfehler — der zweite Echtlauf verlor zwei Jahre an
            # einzelne 502 direkt nach Rate-Limit-Wartezeiten. Nur 4xx
            # (außer 429) ist ein Urteil über die ANFRAGE und fliegt
            # sofort — mitsamt Fehlertext: ihn zu verschlucken kostete
            # beim CLMS eine Runde und hier den ersten Echtlauf
            # (nackter 400, Ursache Schaltjahr).
            body = error.read().decode(errors="replace")[:300]
            transient = error.code == 429 or error.code >= 500
            if error.code == 429 and "Daily" in body:
                # Das TAGES-Limit: „try again tomorrow" wartet niemand
                # im Prozess ab. Sofort und deutlich scheitern — der
                # Cache trägt alles Geholte in den nächsten Lauf
                # (vierter Echtlauf: fünf vergebliche Wartezyklen je
                # Jahr, bevor das hier stand).
                transient = False
            if not transient or attempt == retries - 1:
                raise RuntimeError(
                    f"HTTP {error.code} auf {url}: {body}") from error
            if error.code == 429 and "Hourly" in body:
                # Das STUNDEN-Limit — 60 Sekunden später anzuklopfen
                # ist zwecklos (dritter Echtlauf: fünf vergebliche
                # Wartezyklen, dann vier verlorene Jahre). Die API sagt
                # selbst „try again in the next hour": bis zur nächsten
                # vollen Stunde schlafen, mit einer Minute Puffer.
                pause = 3600 - int(time.time()) % 3600 + 60
                print(f"      Stundenlimit, warte {pause // 60} min",
                      file=sys.stderr)
            elif error.code == 429:
                pause = min(15 * (attempt + 1), 60)
                print(f"      Rate-Limit, warte {pause}s", file=sys.stderr)
            else:
                pause = 5 * (attempt + 1)
                print(f"      HTTP {error.code}, warte {pause}s",
                      file=sys.stderr)
            time.sleep(pause)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
            if attempt == retries - 1:
                raise
            time.sleep(2 * (attempt + 1))
    raise AssertionError("unerreichbar")


def read_species(path=SPECIES_FILE):
    """Deutscher Name → wissenschaftlicher Name, aus der Artenliste der App.

    Dieselbe Quelle wie tool/season_curves.py — ein zweites Verzeichnis
    wäre ein zweiter Stand.
    """
    text = open(path, encoding="utf-8").read()
    mapping = {}
    for match in re.finditer(r"KnownSpecies\('([^']+)',[^)]*?\)", text):
        entry, name = match.group(0), match.group(1)
        if "sameAs:" in entry:
            continue
        sci = re.search(r"sci: '([^']+)'", entry)
        if sci:
            mapping[name] = sci.group(1)
    return mapping


def taxon_key(sci):
    match = _get(f"{GBIF}/species/match", {"name": sci, "kingdom": "Fungi"})
    if match.get("matchType") != "EXACT" or match.get("status") != "ACCEPTED":
        raise SystemExit(
            f"'{sci}': GBIF antwortet {match.get('matchType')}/"
            f"{match.get('status')} — siehe tool/season_curves.py, dort ist "
            f"dieselbe Falle beschrieben.")
    return match["usageKey"]


def fetch_finds(sci, limit=3000, progress=True):
    """Fundmeldungen mit Koordinate, taggenauem Datum und Ortsgenauigkeit."""
    key = taxon_key(sci)
    finds = []
    offset = 0
    while len(finds) < limit:
        page = _get(f"{GBIF}/occurrence/search", {
            "taxonKey": key,
            "country": "DE",
            "basisOfRecord": "HUMAN_OBSERVATION",
            "hasCoordinate": "true",
            "hasGeospatialIssue": "false",
            "license": ["CC0_1_0", "CC_BY_4_0"],
            "year": f"{FIRST_YEAR},2026",
            "limit": 300,
            "offset": offset,
        })
        for record in page.get("results", []):
            if not (record.get("year") and record.get("month")
                    and record.get("day")):
                continue
            uncertainty = record.get("coordinateUncertaintyInMeters")
            # Fehlende Angabe wird durchgelassen: Der Median liegt bei
            # 250 m, und die Meldeportale, aus denen sie stammt, geben sie
            # oft schlicht nicht an. Was ausgeschlossen wird, ist die
            # ausdrücklich GROBE Angabe.
            if uncertainty is not None and uncertainty > MAX_UNCERTAINTY_M:
                continue
            finds.append({
                "lat": record["decimalLatitude"],
                "lon": record["decimalLongitude"],
                "year": record["year"],
                "month": record["month"],
                "day": record["day"],
            })
        if page.get("endOfRecords") or not page.get("results"):
            break
        offset += 300
        time.sleep(0.1)
    if progress:
        print(f"    {len(finds)} verwertbare Meldungen", file=sys.stderr)
    return finds


# --- Wetter ----------------------------------------------------------------


def day_index(year, month, day):
    """Tage seit dem 1. Januar des Jahres (0-basiert)."""
    days = [31, 29 if _leap(year) else 28, 31, 30, 31, 30,
            31, 31, 30, 31, 30, 31]
    return sum(days[:month - 1]) + day - 1


def _leap(year):
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


def season_span(days_of_year, year=None):
    """Der Zeitraum, den ein Jahrgang wirklich braucht — nicht mehr.

    Vom frühesten Fund minus dem längsten Rückblick (Vergleichstag plus
    Regenfenster) bis zum spätesten Fund plus dem längsten Vorgriff. Alles
    darüber hinaus wäre bezahlte Luft: Open-Meteo rechnet die Tage in
    seine Aufrufe ein.

    Die Obergrenze hängt am JAHR: Index 365 existiert nur in
    Schaltjahren. Die frühere feste Klemme auf 365 machte aus späten
    Funden in Nicht-Schaltjahren ein end_date „JJJJ-13-01" — Open-Meteo
    antwortete mit einem 400, und beim ersten Echtlauf fehlten dadurch
    ZWÖLF von zwanzig Steinpilz-Jahren, exakt die Nicht-Schaltjahre mit
    Spätfunden.
    """
    last_index = 365 if year is not None and _leap(year) else 364
    first = max(1, min(days_of_year) - CONTROL_MAX_GAP - RAIN_WINDOW - 1)
    last = min(last_index, max(days_of_year) + CONTROL_MAX_GAP * 2 + 1)
    return first, last


def _date_from_index(year, index):
    days = [31, 29 if _leap(year) else 28, 31, 30, 31, 30,
            31, 31, 30, 31, 30, 31]
    month = 1
    remaining = index
    for length in days:
        if remaining < length:
            break
        remaining -= length
        month += 1
    return f"{year:04d}-{month:02d}-{remaining + 1:02d}"


def fetch_weather(points, year, cache_dir=None, progress=True, span=None):
    """Tagesreihen für viele Orte eines Jahres — ein Abruf für alle.

    Open-Meteo nimmt mehrere Koordinaten pro Anfrage und antwortet mit
    einer Liste in derselben Reihenfolge. Der Zeitraum umfasst die ganze
    Saison samt Vorlauf für die 26-Tage-Kumulation.

    **Warum nicht die RADOLAN-Rohraster**, die das Projekt sonst benutzt:
    Ein Tagesraster wiegt gut ein Megabyte; die Saison über zwanzig Jahre
    wären mehrere Gigabyte, das trägt kein CI-Job. Und anders als bei den
    Spots der Nutzer wird hier nichts Geheimes weitergereicht —
    GBIF-Koordinaten sind veröffentlichte CC-BY-Daten.
    """
    first_day, last_day = span or (0, 364)
    cached = _cache_read(cache_dir, year, points, first_day, last_day)
    if cached is not None:
        return cached

    series = []
    for start in range(0, len(points), 100):
        chunk = points[start:start + 100]
        params = {
            "latitude": ",".join(f"{p[0]:.4f}" for p in chunk),
            "longitude": ",".join(f"{p[1]:.4f}" for p in chunk),
            "start_date": _date_from_index(year, first_day),
            "end_date": _date_from_index(year, last_day),
            "daily": "precipitation_sum,temperature_2m_mean",
            "timezone": "Europe/Berlin",
        }
        answer = _get(OPEN_METEO, params, timeout=180)
        if isinstance(answer, dict):
            answer = [answer]
        for place in answer:
            daily = place["daily"]
            series.append({
                "first": first_day,
                "rain": daily["precipitation_sum"],
                "temp": daily["temperature_2m_mean"],
            })
        if progress:
            print(f"    Wetter {year}: {len(series)}/{len(points)} Orte",
                  file=sys.stderr)
        time.sleep(2.0)
    _cache_write(cache_dir, year, points, series, first_day, last_day)
    return series


def _cache_key(year, points, first_day, last_day):
    import hashlib
    digest = hashlib.sha256(
        json.dumps([[round(a, 4), round(b, 4)] for a, b in points]).encode()
    ).hexdigest()[:16]
    return f"weather_{year}_{first_day}_{last_day}_{digest}.json"


def _cache_read(cache_dir, year, points, first_day, last_day):
    if not cache_dir:
        return None
    path = os.path.join(cache_dir, _cache_key(year, points, first_day, last_day))
    if os.path.exists(path):
        return json.load(open(path, encoding="utf-8"))
    return None


def _cache_write(cache_dir, year, points, series, first_day, last_day):
    if not cache_dir:
        return
    os.makedirs(cache_dir, exist_ok=True)
    path = os.path.join(cache_dir, _cache_key(year, points, first_day, last_day))
    json.dump(series, open(path, "w", encoding="utf-8"))


def window_before(series, day_of_year, length):
    """Die `length` Tage VOR einem Tag, jüngster zuerst.

    Leer, wenn die Reihe nicht weit genug zurückreicht — dann wird der
    Fund verworfen statt mit halben Fenstern gerechnet.
    """
    end = day_of_year - series["first"]
    if end - length < 0 or end > len(series["rain"]):
        return None, None
    rain = list(reversed(series["rain"][end - length:end]))
    temp = list(reversed(series["temp"][end - length:end]))
    return rain, temp


# --- Der Test --------------------------------------------------------------

# Der Vergleichstag liegt so weit weg, dass sich die 26-Tage-Fenster kaum
# überlappen — sonst vergleicht man ein Wetter mit sich selbst — und so
# nah, dass Jahreszeit und Saisonfaktor gleich bleiben.
CONTROL_MIN_GAP = 14
CONTROL_MAX_GAP = 45


def pick_control_day(day_of_year, rng):
    gap = rng.randint(CONTROL_MIN_GAP, CONTROL_MAX_GAP)
    if rng.random() < 0.5:
        gap = -gap
    return day_of_year + gap


def validate_species(name, sci, cache_dir=None, seed=42, progress=True):
    """Rechnet für eine Art Fundtage gegen Vergleichstage."""
    if progress:
        print(f"  {name} ({sci})", file=sys.stderr)
    finds = fetch_finds(sci, progress=progress)
    if not finds:
        return None

    total_available = len(finds)
    if len(finds) > SAMPLE_PER_SPECIES:
        # Zufällig, mit festem Seed — nicht „die ersten N". GBIF liefert
        # nach id sortiert, und das korreliert mit dem Meldeportal: Die
        # ersten 500 kämen überwiegend aus derselben Quelle und derselben
        # Ecke Deutschlands.
        finds = random.Random(seed).sample(finds, SAMPLE_PER_SPECIES)
        if progress:
            print(f"    Stichprobe: {SAMPLE_PER_SPECIES} von "
                  f"{total_available}", file=sys.stderr)

    by_year = {}
    for find in finds:
        by_year.setdefault(find["year"], []).append(find)

    rng = random.Random(seed)
    pairs = []
    placebo = []
    skipped = 0
    lost_years = []
    for year in sorted(by_year):
        group = by_year[year]
        points = [(f["lat"], f["lon"]) for f in group]
        span = season_span(
            [day_index(year, f["month"], f["day"]) for f in group],
            year=year)
        try:
            series = fetch_weather(points, year, cache_dir,
                                   progress=progress, span=span)
        except Exception as error:  # noqa: BLE001
            # **Ein ausgefallenes Jahr wird NICHT stillschweigend
            # weggelassen.** Jahre unterscheiden sich beim Pilzwetter um
            # den Faktor 10 (Katalonien: 25 → 255 kg/ha); fehlt eines,
            # verschiebt das jede Zahl, ohne dass es jemand sieht. Der
            # Ausfall wird gezählt und unten zum Abbruch geführt.
            print(f"    Jahr {year} FEHLT: {error}", file=sys.stderr)
            lost_years.append(year)
            continue
        for find, place in zip(group, series):
            found_day = day_index(year, find["month"], find["day"])
            control_day = pick_control_day(found_day, rng)
            # Das Placebo-Paar: Der Vergleichstag spielt jetzt selbst den
            # „Fundtag", und sein Partner wird nach derselben Vorschrift
            # VON IHM AUS gezogen. Was dabei herauskommt, MUSS 0,5 sein.
            #
            # Dass hier `control_day` der Anker ist und nicht `found_day`,
            # ist der ganze Witz: Zieht man beide vom selben Punkt aus,
            # hebt sich eine einseitige Ziehung symmetrisch auf und bleibt
            # unentdeckt — während Fund- und Vergleichstag sehr wohl
            # auseinanderlägen. Genau so gebaut, beim Gegenprüfen
            # aufgefallen.
            placebo_day = pick_control_day(control_day, rng)
            a_rain, a_temp = window_before(place, found_day, RAIN_WINDOW)
            b_rain, b_temp = window_before(place, control_day, RAIN_WINDOW)
            c_rain, c_temp = window_before(place, placebo_day, RAIN_WINDOW)
            if a_rain is None or b_rain is None:
                skipped += 1
                continue
            pairs.append((ampel_score(a_rain, a_temp),
                          ampel_score(b_rain, b_temp)))
            if c_rain is not None:
                placebo.append((ampel_score(b_rain, b_temp),
                                ampel_score(c_rain, c_temp)))

    if not pairs:
        return None
    if lost_years:
        raise SystemExit(
            f"\n{name}: {len(lost_years)} von {len(by_year)} Jahren fehlen "
            f"({', '.join(str(y) for y in lost_years)}).\n"
            f"Ein Ergebnis auf lückenhaften Jahren wäre nicht auswertbar — "
            f"Pilzjahre unterscheiden sich um den Faktor 10. Lauf mit "
            f"--cache wiederholen, dann sind die geholten Jahre schon da.")
    auc = paired_auc(pairs)
    return {
        "name": name,
        "sci": sci,
        "n": len(pairs),
        "years": len(by_year),
        "skipped": skipped,
        "auc": auc,
        "p": permutation_p(pairs, seed=seed),
        "placebo_auc": paired_auc(placebo),
        "placebo_n": len(placebo),
        "median_found": statistics.median(p[0] for p in pairs),
        "median_control": statistics.median(p[1] for p in pairs),
    }


# --- Saison-Gegenprüfung ---------------------------------------------------


def mushroom_observer_months(sci, progress=True):
    """Monatsverteilung einer Art bei Mushroom Observer (Deutschland).

    Eine **unabhängige Population**: Sammler und Mykologen statt der
    Naturbeobachter, aus denen die GBIF-Kurven stammen. Der Ort ist dort
    nur eine Region — für den Monat genügt das, für das Wetter nicht (siehe
    Kopf).
    """
    counts = [0] * 12
    page = 1
    while True:
        answer = _get(MUSHROOM_OBSERVER, {
            "region": "Germany",
            "name": sci,
            "detail": "low",
            "format": "json",
            "page": page,
        }, timeout=120)
        results = answer.get("results") or []
        for record in results:
            date = record.get("date") or ""
            match = re.match(r"(\d{4})-(\d{2})-(\d{2})", date)
            if match and int(match.group(1)) >= FIRST_YEAR:
                counts[int(match.group(2)) - 1] += 1
        if page * int(answer.get("number_of_pages", 1) or 1) == 0:
            break
        if page >= int(answer.get("number_of_pages", 1) or 1):
            break
        page += 1
        time.sleep(0.3)
    if progress:
        print(f"    {sum(counts)} Meldungen", file=sys.stderr)
    return counts


def spearman(a, b):
    """Rangkorrelation zweier Zwölfer-Reihen, ohne Fremdpaket."""
    def ranks(values):
        order = sorted(range(len(values)), key=lambda i: values[i])
        result = [0.0] * len(values)
        index = 0
        while index < len(order):
            end = index
            while (end + 1 < len(order)
                   and values[order[end + 1]] == values[order[index]]):
                end += 1
            average = (index + end) / 2 + 1
            for position in range(index, end + 1):
                result[order[position]] = average
            index = end + 1
        return result

    ra, rb = ranks(a), ranks(b)
    mean_a = sum(ra) / len(ra)
    mean_b = sum(rb) / len(rb)
    cov = sum((x - mean_a) * (y - mean_b) for x, y in zip(ra, rb))
    var_a = math.sqrt(sum((x - mean_a) ** 2 for x in ra))
    var_b = math.sqrt(sum((y - mean_b) ** 2 for y in rb))
    if var_a == 0 or var_b == 0:
        return 0.0
    return cov / (var_a * var_b)


# --- Selbsttest ------------------------------------------------------------


def self_test():
    # AUC: perfekte Trennung, Gleichstand, Umkehrung.
    assert paired_auc([(1.0, 0.0)] * 10) == 1.0
    assert paired_auc([(0.0, 1.0)] * 10) == 0.0
    assert paired_auc([(0.5, 0.5)] * 10) == 0.5
    assert paired_auc([]) == 0.5
    mixed = [(1.0, 0.0)] * 5 + [(0.0, 1.0)] * 5
    assert paired_auc(mixed) == 0.5

    # Der Permutationstest darf bei Zufall nicht anschlagen und bei
    # perfekter Trennung nicht schweigen.
    assert permutation_p([(1.0, 0.0)] * 30, rounds=500) < 0.01
    assert permutation_p(mixed, rounds=500) > 0.05

    # Niederschlag: mehr ist mehr, ältere Tage zählen weniger.
    dry = [0.0] * RAIN_WINDOW
    wet = [10.0] * RAIN_WINDOW
    assert rain_factor(dry) == 0.0
    assert rain_factor(wet) == 1.0, "260 mm müssen die Sättigung erreichen"
    recent = [5.0] * 5 + [0.0] * (RAIN_WINDOW - 5)
    old = [0.0] * (RAIN_WINDOW - 5) + [5.0] * 5
    assert rain_factor(recent) > rain_factor(old), \
        "frischer Regen muss schwerer wiegen als vier Wochen alter"
    assert rain_factor([]) == 0.0

    # Temperatur: Gipfel bei 13 °C, symmetrisch, Lücken überspringen.
    assert temperature_factor([OPTIMUM_C] * TEMP_WINDOW) == 1.0
    warm = temperature_factor([OPTIMUM_C + 8] * TEMP_WINDOW)
    cold = temperature_factor([OPTIMUM_C - 8] * TEMP_WINDOW)
    assert abs(warm - cold) < 1e-9, "die Glocke muss symmetrisch sein"
    assert warm < 0.1
    assert temperature_factor([None] * TEMP_WINDOW) == 0.0

    # Ein trockener, kalter Tag darf nie über einem feuchten, milden liegen.
    good = ampel_score([6.0] * RAIN_WINDOW, [13.0] * TEMP_WINDOW)
    bad = ampel_score([0.0] * RAIN_WINDOW, [-2.0] * TEMP_WINDOW)
    assert good > bad

    # Tagesnummern, inklusive Schaltjahr.
    assert day_index(2026, 1, 1) == 0
    assert day_index(2026, 3, 1) == 59
    assert day_index(2024, 3, 1) == 60, "2024 ist ein Schaltjahr"
    assert _leap(2000) and not _leap(1900) and _leap(2024)

    # Fensterausschnitt: jüngster Tag zuerst, zu kurze Reihen fallen aus.
    series = {"first": 0, "rain": list(range(100)),
              "temp": list(range(100))}
    rain, temp = window_before(series, 30, 5)
    assert rain == [29, 28, 27, 26, 25], rain
    assert temp == rain
    assert window_before(series, 3, 5) == (None, None), \
        "ein zu kurzes Fenster muss verworfen werden, nicht gekürzt"
    assert window_before(series, 200, 5) == (None, None)

    # Der Vergleichstag hält Abstand — sonst vergleicht man ein Wetter mit
    # sich selbst: Zwei Tage, die fünf Tage auseinanderliegen, teilen 21
    # von 26 Regentagen.
    #
    # Geprüft wird die ANFORDERUNG, nicht die eingestellte Zahl. Ein Test
    # der Form `CONTROL_MIN_GAP <= abstand` wäre tautologisch — er ginge
    # auch bei einem Abstand von einem Tag durch, weil er gegen dieselbe
    # Konstante prüft, die jemand gerade verstellt hat. (Genau so
    # passiert, beim Gegenprüfen dieses Selbsttests.)
    assert CONTROL_MIN_GAP >= RAIN_WINDOW // 2, (
        f"Vergleichstage {CONTROL_MIN_GAP} Tage daneben teilen zu viel des "
        f"{RAIN_WINDOW}-Tage-Fensters — der Test verlöre seinen Kontrast")
    assert CONTROL_MAX_GAP > CONTROL_MIN_GAP
    rng = random.Random(7)
    gaps = set()
    for _ in range(400):
        day = pick_control_day(250, rng)
        gaps.add(abs(day - 250))
        assert CONTROL_MIN_GAP <= abs(day - 250) <= CONTROL_MAX_GAP
    # Und beide Richtungen kommen vor — sonst läge der Vergleich immer
    # später im Jahr und trüge die Jahreszeit als stille Verzerrung mit.
    assert min(pick_control_day(250, random.Random(s)) for s in range(50)) < 250
    assert max(pick_control_day(250, random.Random(s)) for s in range(50)) > 250
    assert len(gaps) > 10, "die Abstände dürfen nicht alle gleich sein"

    # Die Placebo-Erwartung, an echtem Wetterverlauf statt an Konstanten:
    # Zwei nach derselben Vorschrift gezogene Tage dürfen im Mittel keinen
    # Sieger haben. Geprüft auf einer künstlichen Reihe mit Jahresgang —
    # gerade der könnte eine Verzerrung erzeugen, wenn die Ziehung eine
    # Richtung bevorzugte.
    rng = random.Random(11)
    season = {
        "first": 0,
        "rain": [3.0 + 3.0 * math.sin(d / 58.0) + rng.random() * 4
                 for d in range(366)],
        "temp": [10.0 + 10.0 * math.sin((d - 100) / 58.0) for d in range(366)],
    }
    placebo_pairs = []
    for _ in range(3000):
        # Fundtage **geballt**, wie in Wirklichkeit — beim Steinpilz um
        # Ende August. Gleichverteilte Anker wären zu gutmütig: Bei ihnen
        # mittelt sich selbst eine einseitig ziehende Vorschrift heraus,
        # weil ebenso oft bergauf wie bergab verglichen wird. Erst die
        # Ballung deckt auf, dass ein stets späterer Vergleichstag
        # systematisch in eine andere Jahreszeit fällt.
        day = int(rng.gauss(240, 20))
        # Dieselbe Ankerbeziehung wie im echten Lauf: Der erste Tag spielt
        # den Fund, der zweite wird VON IHM AUS gezogen. Beide vom selben
        # Punkt aus zu ziehen würde eine einseitige Vorschrift verstecken.
        first = pick_control_day(day, rng)
        second = pick_control_day(first, rng)
        a = window_before(season, first, RAIN_WINDOW)
        b = window_before(season, second, RAIN_WINDOW)
        if a[0] is None or b[0] is None:
            continue
        placebo_pairs.append((ampel_score(*a), ampel_score(*b)))
    placebo = paired_auc(placebo_pairs)
    assert abs(placebo - 0.5) < 0.03, (
        f"Placebo-AUC {placebo:.3f} statt 0,5 — die Ziehung der "
        f"Vergleichstage ist verzerrt, damit wäre jedes Ergebnis wertlos")

    # Der gebrauchte Zeitraum: weit genug für Rückblick und Vorgriff,
    # aber nicht das ganze Jahr — jeder überflüssige Tag kostet Aufrufe.
    first, last = season_span([240])
    assert first <= 240 - CONTROL_MAX_GAP - RAIN_WINDOW, \
        "der Rückblick muss ins Fenster passen"
    assert last >= 240 + CONTROL_MAX_GAP, "der Vorgriff auch"
    assert first >= 1 and last <= 365
    assert last - first < 250, "das ganze Jahr zu holen wäre Verschwendung"
    # Auch am Rand der Saison bleibt es im Jahr.
    assert season_span([5])[0] >= 1
    assert season_span([360])[1] <= 365
    # Und zwar im RICHTIGEN Jahr: Index 365 gibt es nur im Schaltjahr.
    # Die feste Klemme auf 365 machte in Nicht-Schaltjahren aus
    # Spätfunden ein end_date „JJJJ-13-01" — der 400er, der dem ersten
    # Echtlauf zwölf von zwanzig Steinpilz-Jahren kostete.
    assert season_span([360], year=2009)[1] == 364
    assert season_span([360], year=2008)[1] == 365
    assert _date_from_index(
        2009, season_span([360], year=2009)[1]) == "2009-12-31"
    assert _date_from_index(
        2008, season_span([360], year=2008)[1]) == "2008-12-31"

    # Tagesnummer zurück in ein Datum — die Umkehrung von day_index.
    assert _date_from_index(2026, 0) == "2026-01-01"
    assert _date_from_index(2026, day_index(2026, 8, 5)) == "2026-08-05"
    assert _date_from_index(2024, day_index(2024, 3, 1)) == "2024-03-01", \
        "Schaltjahr"
    assert _date_from_index(2026, 364) == "2026-12-31"

    # Rangkorrelation.
    assert abs(spearman([1, 2, 3, 4], [1, 2, 3, 4]) - 1.0) < 1e-9
    assert abs(spearman([1, 2, 3, 4], [4, 3, 2, 1]) + 1.0) < 1e-9
    assert spearman([1, 1, 1, 1], [1, 2, 3, 4]) == 0.0

    # Der Artenleser gegen die echte Datei.
    mapping = read_species()
    assert "Steinpilz" in mapping and mapping["Steinpilz"] == "Boletus edulis"
    for name in MYCORRHIZAL + WOOD_DWELLERS:
        assert name in mapping, f"{name} hat kein `sci` in {SPECIES_FILE}"

    print("ampel_validate self-test: ok")


# --- Bericht ---------------------------------------------------------------


def verdict(auc):
    """Worte statt einer nackten Zahl — dieselbe Haltung wie im UI."""
    if auc < 0.53:
        return "kein Effekt"
    if auc < 0.56:
        return "sehr schwach"
    if auc < 0.60:
        return "schwach"
    if auc < 0.65:
        return "erkennbar"
    return "deutlich"


def render_report(mycorrhizal, wood, crosscheck, fetched_on):
    lines = [
        "# Rückwärtsvalidierung der Pilzampel",
        "",
        f"Stand: {fetched_on} · Erzeugt von `tool/ampel_validate.py` · "
        "Konzept: `docs/pilzampel-konzept.md`",
        "",
        "Die Bedingung aus dem Konzeptpapier, bevor eine Ampel gebaut wird:",
        "**Steht das Modell an Fundtagen höher als an zufälligen Tagen",
        "derselben Saison?** Diese Seite beantwortet das mit Zahlen.",
        "",
        "## Wie gemessen wurde",
        "",
        "Zu jeder Fundmeldung aus GBIF (Deutschland, ab "
        f"{FIRST_YEAR}, taggenau, Ortsgenauigkeit besser als "
        f"{MAX_UNCERTAINTY_M} m) wird ein **Vergleichstag** am selben Ort im "
        f"selben Jahr gezogen, {CONTROL_MIN_GAP}–{CONTROL_MAX_GAP} Tage "
        "daneben. Für beide Tage rechnet dasselbe Wettermodell einen Wert:",
        "",
        f"- Niederschlag über {RAIN_WINDOW} Tage kumuliert, ältere Tage "
        "schwächer gewichtet",
        f"- Temperatur als Glocke um {OPTIMUM_C:.0f} °C "
        f"(Mittel über {TEMP_WINDOW} Tage)",
        "",
        "**Der Saisonfaktor geht NICHT ein.** Er stammt aus denselben "
        "GBIF-Daten (`docs/pilzampel-saisonkurven.md`); ihn mitzurechnen "
        "hieße, das Modell mit sich selbst zu bestätigen. Weil Fund- und "
        "Vergleichstag wenige Wochen auseinanderliegen, ist die Jahreszeit "
        "für beide praktisch gleich — übrig bleibt das Wetter.",
        "",
        "Die Kennzahl ist die **AUC**: Wie oft liegt der Fundtag über seinem "
        "Vergleichstag? 0,50 heißt zufällig, 1,00 hieße immer. Sie steht "
        "hier vor dem p-Wert, weil bei tausenden Paaren auch ein "
        "bedeutungsloser Unterschied „signifikant“ wird.",
        "",
        "**Der Standort ist durch den Aufbau kontrolliert.** Fund- und "
        "Vergleichstag liegen am selben Ort — gleicher Wald, gleiche "
        "Baumart, gleicher Boden. Was einen Fichtenhang von einem "
        "Buchenhang unterscheidet, kann das Ergebnis also nicht "
        "beeinflussen; bei Holzbewohnern erklärt dieser Faktor sonst "
        "56–59 % der Varianz (Alday/Karavani et al. 2017). Gefragt wird "
        "nur: Warum an DIESEM Tag und nicht drei Wochen später am selben "
        "Fleck?",
        "",
        "## Placebo-Kontrolle: prüft die Methode",
        "",
        "Zwei Vergleichstage treten gegeneinander an — beide ohne Fund, "
        "beide nach derselben Vorschrift gezogen. **Hier muss 0,50 "
        "stehen.** Alles andere hieße, dass schon die Ziehung verzerrt "
        "(etwa weil ein späterer Tag im Jahr systematisch feuchter ist) — "
        "und dann wäre jede Zahl in den Tabellen darunter wertlos.",
        "",
        "| Art | Paare | AUC (soll ≈ 0,50) |",
        "|---|--:|--:|",
    ]
    for row in mycorrhizal + wood:
        lines.append(
            f"| {row['name']} | {row['placebo_n']} | "
            f"{row['placebo_auc']:.3f} |")

    lines += [
        "",
        "## Mykorrhiza-Speisepilze — hier wird ein Effekt erwartet",
        "",
        "| Art | Paare | AUC | Befund | p |",
        "|---|--:|--:|---|--:|",
    ]
    for row in mycorrhizal:
        lines.append(
            f"| {row['name']} | {row['n']} | {row['auc']:.3f} | "
            f"{verdict(row['auc'])} | {row['p']:.4f} |")

    lines += [
        "",
        "## Arten-Kontrolle: Holzbewohner — hier darf DIESES Modell nicht "
        "passen",
        "",
        "**Nicht, weil sie kein Wetter spüren.** Der Austernseitling ist "
        "ein Kältefrüchter mit Gipfel im Dezember; er reagiert sehr wohl, "
        "nur auf anderes. Geprüft wird enger: Das hier gerechnete Modell — "
        f"Glocke um {OPTIMUM_C:.0f} °C und {RAIN_WINDOW}-Tage-Regensumme, "
        "beides aus der Steinpilz-Literatur — darf bei ihnen nicht passen. "
        "Ein Wert **unter** 0,50 ist deshalb kein Fehlschlag, sondern ein "
        "Beleg: Das Modell wirkt artspezifisch und misst nicht bloß "
        "„im Herbst wird mehr gemeldet“.",
        "",
        "| Art | Paare | AUC | Befund | p |",
        "|---|--:|--:|---|--:|",
    ]
    for row in wood:
        lines.append(
            f"| {row['name']} | {row['n']} | {row['auc']:.3f} | "
            f"{verdict(row['auc'])} | {row['p']:.4f} |")

    if crosscheck:
        lines += [
            "",
            "## Gegenprüfung der Saisonkurven an einer zweiten Population",
            "",
            "Die Saisonkurven stammen aus GBIF — überwiegend von "
            "Naturbeobachtern (NABU-naturgucker, iNaturalist). Mushroom "
            "Observer ist eine andere Gemeinschaft: Sammler und Mykologen. "
            "Stimmen beide Jahresgänge überein, ist die Kurve mehr als die "
            "Gewohnheit einer Melder-Gruppe.",
            "",
            "| Art | Meldungen (MO) | Rangkorrelation |",
            "|---|--:|--:|",
        ]
        for row in crosscheck:
            lines.append(
                f"| {row['name']} | {row['n']} | {row['rho']:+.2f} |")

    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=None,
                        help="Bericht schreiben (z. B. docs/…​.md)")
    parser.add_argument("--crosscheck", action="store_true",
                        help="zusätzlich die Saisonkurven gegenprüfen")
    parser.add_argument("--crosscheck-only", action="store_true",
                        help="NUR die Saisonkurven gegenprüfen (kein "
                             "Open-Meteo nötig)")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--cache", default=None,
                        help="Verzeichnis für Wetterantworten")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return

    mapping = read_species()
    mycorrhizal = []
    wood = []
    # `--crosscheck` allein braucht KEIN Open-Meteo — nur GBIF und
    # Mushroom Observer. Deshalb lässt es sich getrennt laufen, etwa wenn
    # das Tageskontingent des Wetterdienstes erschöpft ist.
    if not args.crosscheck_only:
        print("Mykorrhiza-Speisepilze:", file=sys.stderr)
        mycorrhizal = [
            row for row in (
                validate_species(name, mapping[name], args.cache, args.seed)
                for name in MYCORRHIZAL if name in mapping)
            if row
        ]
        print("Arten-Kontrolle (Holzbewohner):", file=sys.stderr)
        wood = [
            row for row in (
                validate_species(name, mapping[name], args.cache, args.seed)
                for name in WOOD_DWELLERS if name in mapping)
            if row
        ]

    crosscheck = []
    if args.crosscheck or args.crosscheck_only:
        from season_curves import (BASE_FILTER, effort_corrected,  # noqa
                                   month_counts)
        print("Saison-Gegenprüfung (Mushroom Observer):", file=sys.stderr)
        baseline, _ = month_counts({"kingdomKey": 5})
        for name in MYCORRHIZAL:
            if name not in mapping:
                continue
            print(f"  {name}", file=sys.stderr)
            observer = mushroom_observer_months(mapping[name])
            if sum(observer) < 30:
                continue
            key = taxon_key(mapping[name])
            counts, _ = month_counts({"taxonKey": key})
            crosscheck.append({
                "name": name,
                "n": sum(observer),
                "rho": spearman(observer, effort_corrected(counts, baseline)),
            })

    report = render_report(mycorrhizal, wood, crosscheck,
                           time.strftime("%Y-%m-%d"))
    if args.out:
        open(args.out, "w", encoding="utf-8").write(report)
        print(f"\n{args.out} geschrieben", file=sys.stderr)
    else:
        print(report)

    if not (mycorrhizal or wood):
        return
    print("\nZusammenfassung:", file=sys.stderr)
    worst_placebo = 0.0
    for row in mycorrhizal + wood:
        worst_placebo = max(worst_placebo, abs(row["placebo_auc"] - 0.5))
    print(f"  Placebo (soll 0,50): grösste Abweichung {worst_placebo:.3f}",
          file=sys.stderr)
    if worst_placebo > 0.03:
        print("  ⚠ Die Ziehung der Vergleichstage ist verzerrt — die Zahlen "
              "darunter sind nicht auswertbar.", file=sys.stderr)
    print("  --- Mykorrhiza ---", file=sys.stderr)
    for row in mycorrhizal:
        print(f"  {row['name']:22} AUC {row['auc']:.3f}  {verdict(row['auc'])}"
              f"  (n={row['n']})", file=sys.stderr)
    print("  --- Arten-Kontrolle (Holzbewohner) ---", file=sys.stderr)
    for row in wood:
        print(f"  {row['name']:22} AUC {row['auc']:.3f}  {verdict(row['auc'])}"
              f"  (n={row['n']})", file=sys.stderr)


if __name__ == "__main__":
    main()
