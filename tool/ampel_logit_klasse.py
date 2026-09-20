#!/usr/bin/env python3
"""Die Logit-Klassen der Pilzampel — der Spiegel zu `AmpelLogitClass` in Dart.

**Warum eine eigene Datei.** `ampel_validate.py` kennt Klassen als
Temperaturfenster: ein Optimum, eine Glocke, zwei Schwellen als Quantile.
Die Klasse für Holz- und Winterpilze ist kein Fenster — sie ist ein
bedingtes Logit mit fünf Konstanten und der Bodenfeuchte der nächsten
DWD-Station (`docs/pilzampel-holz-winter-plan.md`). Sie in die
Fenster-Maschinerie zu pressen hiesse, an sechzig Stellen „wenn Fenster,
sonst …" zu schreiben. Hier steht sie EINMAL, und `ampel_model.dart`
spiegelt sie Zahl fuer Zahl; `test/ampel_model_test.dart` prueft das mit
Fixtures, die `--fixtures` erzeugt.

Was hier definiert ist:
  - die Klassen (Konstanten, Mitglieder, Schwellen, Beleg),
  - der Score `s` — exakt die Rechnung der App,
  - die DWD-Bodenfeuchte (`BFGL_AG`) fuer die Rueckwaertsrechnung: die
    historischen Stationsdateien, die naechste Station per Grosskreis,
    das 26-Tage-Fenster VOR einem Tag — dieselbe Regel wie in der App
    (`WeatherTable.nearestMoisture`) und im Labor (`lab/dwd_boden.py`),
  - die Schwellenmessung: Design B auf P1 (DE ab 2019), Quantile 50 % /
    80 % der `s`-Verteilung an Vergleichstagen, jedes Fundjahr gleich
    schwer, jede Art gleich schwer, Jahres-Bootstrap — dieselben
    Funktionen wie `ampel_diagnose.py --schwellen --scheibe p1`.

Nur Standardbibliothek, wie alles in `tool/`.

    python3 tool/ampel_logit_klasse.py --self-test
    python3 tool/ampel_logit_klasse.py --fixtures
    python3 tool/ampel_logit_klasse.py --schwellen --dataset pinned \\
        --cache-dir ~/pilzbuddy-ampel2000/ampel_cache_pinned
"""

import argparse
import gzip
import json
import math
import os
import re
import sys
import urllib.request
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ampel_validate as av  # noqa: E402

# --- Die Klassen -------------------------------------------------------------

# Boden unter dem Regenfaktor vor dem Logarithmus — wie `logit_features`
# in `ampel_logit.py` und `REGEN_BODEN` im Labor.
REGEN_BODEN = 1e-3
FEUCHTE_FENSTER = 26      # Tage, Mittel — das Feuchtefenster des Modells
QUANTILE = (0.50, 0.80)   # die Auslieferungsquantile (2026-09-12)
SPALTEN = ("log_regen", "temp", "temp2", "feuchte", "feuchte_x_temp")

KLASSEN = {
    "holz_winter": {
        "dart": "ampelHolzWinterClass",
        # Nach den Mitgliedern benannt (Regel seit 1.137.0); Betreiber
        # 2026-09-20: „Judasohr ist nicht der aussagekraeftigste
        # Winterpilz — wie waere es mit Austernseitling?"
        "label": "Austernseitling & Co.",
        "members": ["Austernseitling", "Judasohr", "Krause Glucke", "Leberpilz",
                    "Lungenseitling", "Rehbrauner Dachpilz", "Samtfußrübling",
                    "Schwefelporling"],
        # Aus `18-testteil-dach.md` (Labor): Fit auf allen DACH-Erkundungs-
        # strata der acht Arten, Reihenfolge wie SPALTEN.
        "koeffizienten": (0.1882, 0.1321, -0.00446, 0.00220, -0.000442),
        # Die Schwellen — gemessen mit `--schwellen` (Design B, P1, 2000
        # Zuege), hier gepinnt; der Lauf prueft sie bei jedem Mal nach.
        # Bänder: verhalten [0,445, 0,462], guenstig [0,599, 0,612].
        "verhalten": 0.454,
        "guenstig": 0.606,
        "schwellen_quelle": "Design B, P1, pinned (2026-09-20), docs/pilzampel-logit-schwellen.md",
        "gilt": "DE",
        "confirmed": True,
        "why": "Phase G auf DE-Test +0,402 [+0,255, +0,596], AT/CH-Test "
               "+0,206 [+0,081, +0,352], gegen die Klimatologie +0,020 "
               "[+0,000, +0,038] — Labor 15/16/18 (2026-09-20)",
    },
    "cantharellales": {
        "dart": "ampelCantharellalesClass",
        "label": "Herbsttrompete & Co.",
        "members": ["Herbsttrompete", "Semmelstoppelpilz", "Trompetenpfifferling"],
        # Aus `15-testteil.md` (Labor): Fit auf allen DE-Erkundungsstrata
        # der drei Arten.
        "koeffizienten": (0.1039, 0.1547, -0.01399, 0.00333, 0.002237),
        # Bänder: verhalten [2,035, 2,339], guenstig [2,861, 3,032] — die
        # Skala ist die von `s`, nicht die 0…1 der Glocke.
        "verhalten": 2.191,
        "guenstig": 2.952,
        "schwellen_quelle": "Design B, P1, pinned (2026-09-20), docs/pilzampel-logit-schwellen.md",
        # **Nur fuer Deutschland belegt** (Betreiber 2026-09-20: „die App
        # ist hauptsaechlich auf Deutschland ausgelegt"): auf dem DE-Test
        # angenommen, reist aber nicht nach AT/CH — dort bleibt die
        # Klasse ohnehin ohne Bodenfeuchte (Station > 100 km).
        "gilt": "DE",
        "confirmed": True,
        "why": "Phase G auf DE-Test +0,417 [+0,131, +0,769]; AT/CH "
               "+0,047 [-0,058, +0,129] (reist nicht) — Labor 15/16 "
               "(2026-09-20)",
    },
}


# **Arten, die noch in einer Fensterklasse stehen und hierher umziehen.**
# Waehrend des Umzugs der Herbsttrompete (1.150.0 → 1.151.0) stand sie
# hier; seit der Dart-Kern sie umgehaengt hat, ist die Menge leer und der
# Riegel im Selbsttest scharf: keine Art in Glocke UND Logit.
UMZUG = set()


def class_of(name):
    """Die Logit-Klasse einer Art — `None`, wenn sie in keiner steht."""
    for key, klasse in KLASSEN.items():
        if name in klasse["members"]:
            return key
    return None


# --- Der Score: exakt die Rechnung der App -----------------------------------

def feuchte_mittel(reihe, tage=FEUCHTE_FENSTER):
    """Mittel der juengsten [tage] Werte — `None`, wenn die Reihe kuerzer
    ist oder eine Luecke hat. Kein Mittel aus halben Fenstern: eine
    erfundene Bodenfeuchte waere eine erfundene Beobachtung."""
    if reihe is None or len(reihe) < tage:
        return None
    werte = reihe[:tage]
    if any(v is None for v in werte):
        return None
    return sum(werte) / tage


def temperatur_mittel(daily_c):
    """Das 20-Tage-Mittel, Fehltage uebersprungen — wie
    `temperature_factor` im Werkzeug und `ampelTemperatureFactor` in
    Dart. `None` ganz ohne Werte."""
    werte = [c for c in daily_c[:av.TEMP_WINDOW] if c is not None]
    if not werte:
        return None
    return sum(werte) / len(werte)


def merkmale(regen, temp, feuchte):
    """Die fuenf Spalten (Reihenfolge SPALTEN) oder `None` bei Luecke."""
    t = temperatur_mittel(temp)
    m = feuchte_mittel(feuchte)
    if t is None or m is None:
        return None
    log_f = math.log(max(av.rain_factor(regen), REGEN_BODEN))
    return (log_f, t, t * t, m, m * t)


def score(regen, temp, feuchte, koeffizienten):
    """`s` = Σ Koeffizient × Spalte — oder `None`, wenn eine Reihe fehlt.

    `regen`: 26 Tageswerte mm, Vortag zuerst. `temp`: 20 Tageswerte °C,
    Vortag zuerst. `feuchte`: 26 Tageswerte % nFK, Vortag zuerst.
    """
    spalten = merkmale(regen, temp, feuchte)
    if spalten is None:
        return None
    return sum(k * x for k, x in zip(koeffizienten, spalten))


def stufe(s, klasse):
    """Die Stufe wie `ampelLevelOf`: 2 guenstig, 1 verhalten, 0 unguenstig,
    `None` ohne Score oder ohne gemessene Schwellen."""
    if s is None or klasse["guenstig"] is None or klasse["verhalten"] is None:
        return None
    if s >= klasse["guenstig"]:
        return 2
    if s >= klasse["verhalten"]:
        return 1
    return 0


# --- DWD-Bodenfeuchte fuer die Rueckwaertsrechnung ---------------------------

DWD_BASIS = ("https://opendata.dwd.de/climate_environment/CDC/derived_germany/"
             "soil/daily")
DWD_FELD = "BFGL_AG"
DWD_VERZEICHNIS = os.path.expanduser("~/pilzbuddy-dwd-boden")
ERDRADIUS_KM = 6371.0


def _hole(url, ziel):
    with urllib.request.urlopen(url, timeout=60) as r:
        daten = r.read()
    tmp = ziel + ".part"
    with open(tmp, "wb") as f:
        f.write(daten)
    os.replace(tmp, ziel)


def dwd_stationen(verzeichnis=DWD_VERZEICHNIS, holen=True):
    """`[(id, lat, lon, hoehe, name)]` aus den Stationslisten beider
    Sammlungen; holt sie, wenn sie fehlen."""
    aus = {}
    for art in ("historical", "recent"):
        pfad = os.path.join(verzeichnis, f"stations_{art}.txt")
        if not os.path.isfile(pfad):
            if not holen:
                continue
            os.makedirs(verzeichnis, exist_ok=True)
            _hole(f"{DWD_BASIS}/{art}/derived_germany_soil_daily_{art}_stations_list.txt",
                  pfad)
        for zeile in open(pfad, encoding="latin-1").read().splitlines()[1:]:
            teile = [t.strip() for t in zeile.split(";")]
            if len(teile) < 5 or not teile[0].isdigit():
                continue
            sid = int(teile[0])
            aus[sid] = (sid, float(teile[2]), float(teile[3]),
                        float(teile[1]), teile[4])
    return [aus[k] for k in sorted(aus)]


def _lies_datei(pfad):
    """`{ordinal: wert}` einer Stationsdatei; Fehlwerte (< 0) fehlen."""
    aus = {}
    with gzip.open(pfad, "rt", encoding="latin-1") as f:
        kopf = [t.strip() for t in f.readline().split(";")]
        spalte = kopf.index(DWD_FELD)
        for zeile in f:
            teile = zeile.split(";")
            if len(teile) <= spalte:
                continue
            d = teile[1].strip()
            try:
                wert = float(teile[spalte])
            except ValueError:
                continue
            if wert < 0 or len(d) != 8:
                continue
            aus[date(int(d[:4]), int(d[4:6]), int(d[6:8])).toordinal()] = wert
    return aus


def dwd_reihe(sid, verzeichnis=DWD_VERZEICHNIS, holen=True):
    """`{"first": ordinal, "werte": [float|None, …]}` — historical und
    recent zusammengelegt; `None`, wenn es die Station nirgends gibt."""
    punkte = {}
    for art in ("historical", "recent"):
        name = f"derived_germany_soil_daily_{art}_v2_{sid}.txt.gz"
        pfad = os.path.join(verzeichnis, art, name)
        if not os.path.isfile(pfad) and holen:
            os.makedirs(os.path.dirname(pfad), exist_ok=True)
            try:
                _hole(f"{DWD_BASIS}/{art}/{name}", pfad)
            except Exception:  # noqa: BLE001 — Station ohne diese Sammlung
                continue
        if os.path.isfile(pfad):
            punkte.update(_lies_datei(pfad))
    if not punkte:
        return None
    first, last = min(punkte), max(punkte)
    werte = [None] * (last - first + 1)
    for o, v in punkte.items():
        werte[o - first] = v
    return {"first": first, "werte": werte}


def dwd_naechste(lat, lon, stationen):
    """`(id, km)` der naechsten Station — Grosskreis, sonst nichts (wie
    `WeatherTable._nearest`, ohne die 100-km-Grenze: die Rueckwaerts-
    rechnung soll auch sagen, WIE weit es war)."""
    la, lo = math.radians(lat), math.radians(lon)
    best, best_km = None, float("inf")
    for sid, s_lat, s_lon, _, _ in stationen:
        p, q = math.radians(s_lat), math.radians(s_lon)
        d = (math.sin((p - la) / 2) ** 2
             + math.cos(la) * math.cos(p) * math.sin((q - lo) / 2) ** 2)
        km = 2 * ERDRADIUS_KM * math.asin(math.sqrt(d))
        if km < best_km:
            best, best_km = sid, km
    return best, best_km


def dwd_fenster(reihe, jahr, tag, laenge=FEUCHTE_FENSTER):
    """Die `laenge` Tage VOR (jahr, tag) — `tag` 0-basiert wie
    `av.day_index` —, juengster zuerst; `None` bei Luecke. Dieselbe
    Konvention wie `ampel_basis.window_of`."""
    if reihe is None:
        return None
    ende = date(jahr, 1, 1).toordinal() + tag - reihe["first"]
    if ende - laenge < 0 or ende > len(reihe["werte"]):
        return None
    w = reihe["werte"][ende - laenge:ende]
    if any(v is None for v in w):
        return None
    return list(reversed(w))


class DwdBestand:
    """Stationsliste plus faul geladene Reihen."""

    def __init__(self, verzeichnis=DWD_VERZEICHNIS, holen=True):
        self.verzeichnis = verzeichnis
        self.holen = holen
        self.liste = dwd_stationen(verzeichnis, holen)
        self._reihen = {}

    def naechste(self, lat, lon):
        return dwd_naechste(lat, lon, self.liste)

    def reihe(self, sid):
        if sid not in self._reihen:
            self._reihen[sid] = dwd_reihe(sid, self.verzeichnis, self.holen)
        return self._reihen[sid]


# --- Ziehung: Strata mit Koordinate und Bodenfeuchte -------------------------

def mit_koordinate(samples, finds):
    """Haengt jedem Stratum lat/lon seines Funds an.

    `collect_pairs_b` arbeitet die Funde jahrweise ab, behaelt innerhalb
    eines Jahres die Reihenfolge — und laesst Funde ohne Fenster AUS.
    Deshalb rueckt der Zeiger je Jahr vor, bis der Fundtag passt; passt
    keiner mehr, faellt das Stratum weg (dieselbe Korrektur wie im Labor
    am 2026-09-20, 410 falsch zugeordnete Strata).
    """
    nach_jahr = {}
    for f in finds:
        nach_jahr.setdefault(f["year"], []).append(f)
    zeiger = {}
    aus = []
    for s in samples:
        liste = nach_jahr.get(s["year"], [])
        i = zeiger.get(s["year"], 0)
        while i < len(liste) and av.day_index(
                liste[i]["year"], liste[i]["month"], liste[i]["day"]) != s["found_day"]:
            i += 1
        if i >= len(liste):
            continue
        zeiger[s["year"]] = i + 1
        s = dict(s, lat=liste[i]["lat"], lon=liste[i]["lon"])
        aus.append(s)
    return aus


def mit_bodenfeuchte(samples, bestand):
    """Bodenfeuchte-Fenster fuer Fund und Kontrollen; Strata mit Luecke
    fallen weg. Gibt `(strata, km_liste)` zurueck."""
    aus, km_liste = [], []
    for s in samples:
        sid, km = bestand.naechste(s["lat"], s["lon"])
        reihe = bestand.reihe(sid)
        fund = dwd_fenster(reihe, s["year"], s["found_day"])
        kontrollen = [dwd_fenster(reihe, j, t)
                      for j, t in zip(s["control_years"], s["control_days"])]
        if fund is None or any(k is None for k in kontrollen):
            continue
        km_liste.append(km)
        aus.append(dict(s, feuchte=fund, feuchte_controls=kontrollen,
                        station=sid, km=km))
    return aus, km_liste


# --- Schwellen: Design B auf P1 ----------------------------------------------

def schwellen_tage(strata, koeffizienten):
    """`{fundjahr: [(score, monat, gewicht), …]}` der Kontrolltage — Gewicht
    1 je Fund, auf seine Kontrolltage verteilt (wie
    `ampel_diagnose.schwellen_tage`)."""
    import ampel_diagnose as ad
    aus = {}
    for s in strata:
        if not s["controls"]:
            continue
        anteil = 1.0 / len(s["controls"])
        for (regen, temp), feuchte, jahr, tag in zip(
                s["controls"], s["feuchte_controls"], s["control_years"],
                s["control_days"]):
            wert = score(regen, temp, feuchte, koeffizienten)
            if wert is None:
                continue
            aus.setdefault(s["year"], []).append(
                (wert, ad.schwellen_monat(jahr, tag), anteil))
    return aus


def messe_schwellen(key, cache_dir, bestand, rounds=2000, seed=42,
                    min_funde=None, progress=True):
    """Die beiden Schwellen einer Logit-Klasse auf P1 — `{punkt, band,
    n, mitglieder: {art: {...}}}` oder `None`."""
    import ampel_diagnose as ad
    klasse = KLASSEN[key]
    mapping = av.read_species()
    min_funde = ad.SCHWELLEN_MIN_FUNDE if min_funde is None else min_funde
    arten, mitglieder = [], {}
    for art in klasse["members"]:
        sci = mapping.get(art)
        if not sci:
            mitglieder[art] = {"fehler": "kein wissenschaftlicher Name"}
            continue
        finds, _ = av.select_finds(sci, cache_dir, seed, True, ("DE",))
        gezogen = av.collect_pairs_b(art, sci, finds=finds or [],
                                     cache_dir=cache_dir, seed=seed,
                                     progress=False) if finds else None
        if not gezogen:
            mitglieder[art] = {"fehler": "keine Strata"}
            continue
        p1 = [s for s in gezogen["samples"] if s["year"] > av.FIT_UNTIL_YEAR]
        p1 = mit_koordinate(p1, finds)
        strata, km = mit_bodenfeuchte(p1, bestand)
        tage = schwellen_tage(strata, klasse["koeffizienten"])
        n_kontroll = sum(len(v) for v in tage.values())
        mitglieder[art] = {"funde": len(strata), "kontrolltage": n_kontroll,
                           "jahre": len(tage),
                           "km": sorted(km)[len(km) // 2] if km else None,
                           "unter_grenze": len(strata) < min_funde}
        if progress:
            print(f"  {art}: {len(strata)} Funde auf P1, {n_kontroll} "
                  f"Kontrolltage, Station im Median "
                  f"{mitglieder[art]['km'] or float('nan'):.0f} km", file=sys.stderr)
        if strata:
            arten.append(ad.schwellen_gewichte(tage))
    if not arten:
        return None
    ergebnis = ad.schwellen_klasse(arten, QUANTILE, rounds, seed)
    ergebnis["mitglieder"] = mitglieder
    return ergebnis


def pruefe_schwellen(key, gemessen):
    """Die gepinnten Konstanten gegen die Messung — Befunde als Liste."""
    klasse = KLASSEN[key]
    befunde = []
    for feld, wert in zip(("verhalten", "guenstig"), gemessen["punkt"]):
        erwartet = klasse.get(feld)
        if erwartet is not None and round(wert, 3) != erwartet:
            befunde.append(f"  {key}.{feld}: gemessen {round(wert, 3)}, "
                           f"Konstante {erwartet}")
    return befunde


def schreibe_bericht(ergebnisse, pfad):
    z = []
    w = z.append
    w("# Die Schwellen der Logit-Klassen — Design B auf P1\n")
    w("Stand: {} · Erzeugt von `tool/ampel_logit_klasse.py --schwellen` · "
      "Zeitscheibe: **DE ab {}**\n".format(
          date.today().isoformat(), av.FIT_UNTIL_YEAR + 1))
    w("> **Diese Datei wird erzeugt.** Wer sie von Hand ändert, verliert die "
      "Änderung beim nächsten Lauf.\n")
    w("Dieselbe Messung wie `docs/pilzampel-schwellen-designb-p1.md`, nur ist "
      "der Score nicht die Glocke, sondern die lineare Vorhersage `s` des "
      "bedingten Logits der Klasse (`docs/pilzampel-holz-winter-plan.md`, "
      "Abschnitt 1). Vergleichstage nach Design B (gleicher Ort, gleiches "
      "Datum, anderes Jahr), Quantile 50 % / 80 %, jedes Fundjahr und jede "
      "Art gleich schwer, Jahres-Bootstrap mit 2000 Zügen. Die "
      "Bodenfeuchte kommt von der nächsten DWD-Station (`BFGL_AG`), "
      "26-Tage-Mittel — genau so, wie die App sie holt.\n")
    for key, e in ergebnisse.items():
        klasse = KLASSEN[key]
        w(f"## {klasse['label']} (`{key}`)\n")
        w("| Art | Funde P1 | Kontrolltage | Fundjahre | Station (Median) |")
        w("|---|--:|--:|--:|--:|")
        for art, m in e["mitglieder"].items():
            if "fehler" in m:
                w(f"| {art} | — | — | — | {m['fehler']} |")
                continue
            warn = " ⚠" if m["unter_grenze"] else ""
            w(f"| {art}{warn} | {m['funde']} | {m['kontrolltage']} | {m['jahre']} | "
              f"{m['km']:.0f} km |")
        w("")
        w("| Stufe | gepinnt | gemessen | 95 % |")
        w("|---|--:|--:|---|")
        for feld, punkt, band in zip(("verhalten", "günstig"), e["punkt"], e["band"]):
            gepinnt = klasse.get("verhalten" if feld == "verhalten" else "guenstig")
            w(f"| {feld} | {gepinnt if gepinnt is not None else '—'} | {punkt:.3f} | "
              + (f"[{band[0]:.3f}, {band[1]:.3f}]" if band else "—") + " |")
        w(f"\nKontrolltage gesamt: {e['n']}. Koeffizienten: "
          + ", ".join(f"{s} {k:+.6g}" for s, k in zip(SPALTEN, klasse["koeffizienten"]))
          + ".\n")
    w("⚠ unter der Beitragsgrenze — steuert zum Klassenquantil bei, trägt "
      "aber kein eigenes Urteil (Korrekturkasten in "
      "`docs/pilzampel-schwellen-designb-p1.md`).")
    with open(pfad, "w", encoding="utf-8") as f:
        f.write("\n".join(z) + "\n")


# --- Fixtures fuer Dart ------------------------------------------------------

def fixtures():
    """Eingaben und Sollwerte fuer `test/ampel_model_test.dart`."""
    regen = [20.0] + [0.0] * 25
    temp = [8.0] * 20
    feuchte = [60.0] * 26
    aus = {}
    for key, klasse in KLASSEN.items():
        aus[key] = {
            "koeffizienten": list(klasse["koeffizienten"]),
            "s_regen20_t8_m60": score(regen, temp, feuchte, klasse["koeffizienten"]),
            "s_trocken_t3_m90": score([0.0] * 26, [3.0] * 20, [90.0] * 26,
                                      klasse["koeffizienten"]),
            "s_gleichmaessig_t13_m40": score([87 / 26] * 26, [13.0] * 20, [40.0] * 26,
                                             klasse["koeffizienten"]),
        }
    aus["merkmale_regen20_t8_m60"] = list(merkmale(regen, temp, feuchte))
    return aus


# --- Selbsttest --------------------------------------------------------------

def self_test():
    k = (1.0, 0.5, -0.01, 0.02, -0.001)
    regen = [20.0] + [0.0] * 25
    temp = [8.0] * 20
    feuchte = [60.0] * 26
    # Von Hand: log F + 0,5·8 − 0,01·64 + 0,02·60 − 0,001·60·8
    f = av.rain_factor(regen)
    soll = math.log(f) + 4.0 - 0.64 + 1.2 - 0.48
    assert abs(score(regen, temp, feuchte, k) - soll) < 1e-12
    # Trockener Regen: Boden 1e-3 vor dem Logarithmus, kein log(0).
    assert abs(score([0.0] * 26, temp, feuchte, k) - (math.log(1e-3) + 4.0 - 0.64 + 1.2 - 0.48)) < 1e-12
    # Feuchte: zu kurz oder mit Luecke -> kein Score; Temperatur mit
    # Luecke -> Fehltag uebersprungen (wie die Glocke).
    assert score(regen, temp, feuchte[:25], k) is None
    assert score(regen, temp, feuchte[:10] + [None] + feuchte[11:], k) is None
    assert abs(score(regen, [8.0] * 10 + [None] * 10, feuchte, k) - soll) < 1e-12
    assert score(regen, [None] * 20, feuchte, k) is None
    # Nur die ersten 26 Feuchtetage zaehlen (juengste zuerst).
    assert abs(score(regen, temp, feuchte + [0.0] * 5, k) - soll) < 1e-12
    # Stufen wie in Dart.
    kl = {"verhalten": 1.0, "guenstig": 2.0}
    assert stufe(2.0, kl) == 2 and stufe(1.5, kl) == 1 and stufe(0.9, kl) == 0
    assert stufe(None, kl) is None
    assert stufe(5.0, {"verhalten": None, "guenstig": None}) is None

    # Klassen: keine Art in zwei Logit-Klassen, keine in einer
    # Fensterklasse der App zugleich.
    alle = [a for kl in KLASSEN.values() for a in kl["members"]]
    assert len(alle) == len(set(alle)), "eine Art in zwei Logit-Klassen"
    for key, klasse in av.AMPEL_CLASSES.items():
        if klasse.get("dart"):
            doppelt = set(alle) & set(klasse["members"]) - UMZUG
            assert not doppelt, f"{doppelt} in Fensterklasse {key} UND Logit"
    assert class_of("Judasohr") == "holz_winter" and class_of("Steinpilz") is None
    for klasse in KLASSEN.values():
        assert len(klasse["koeffizienten"]) == len(SPALTEN)

    # DWD-Fenster: Wert = Index, Tag 40 -> die 3 Tage davor 39, 38, 37.
    first = date(2020, 1, 1).toordinal()
    reihe = {"first": first, "werte": [float(i) for i in range(400)]}
    assert dwd_fenster(reihe, 2020, 40, 3) == [39.0, 38.0, 37.0]
    assert dwd_fenster(reihe, 2020, 2, 3) is None
    assert dwd_fenster(reihe, 2021, 100, 3) is None
    loch = {"first": first, "werte": reihe["werte"][:38] + [None] + reihe["werte"][39:]}
    assert dwd_fenster(loch, 2020, 40, 3) is None
    assert dwd_fenster(None, 2020, 40, 3) is None
    # Naechste Station: reine Distanz.
    st = [(1, 50.0, 8.0, 100.0, "A"), (2, 52.0, 10.0, 100.0, "B")]
    sid, km = dwd_naechste(50.1, 8.1, st)
    assert sid == 1 and 10 < km < 15, (sid, km)
    assert dwd_naechste(51.9, 9.9, st)[0] == 2
    # Datei lesen: Fehlwert und Datumsluecke.
    import tempfile
    tmp = tempfile.mkdtemp()
    os.makedirs(os.path.join(tmp, "historical"))
    with gzip.open(os.path.join(tmp, "historical",
                                "derived_germany_soil_daily_historical_v2_7.txt.gz"),
                   "wt", encoding="latin-1") as fh:
        fh.write("Stationsindex;Datum;TS05;BFGS_AG;BFGL_AG;eor\n"
                 "  7;20200101;  1.0;  70;   80;eor\n"
                 "  7;20200102;  1.0;  70; -999;eor\n"
                 "  7;20200104;  1.0;  70;   82;eor\n")
    r = dwd_reihe(7, tmp, holen=False)
    assert r["first"] == first and r["werte"] == [80.0, None, None, 82.0], r
    assert dwd_reihe(8, tmp, holen=False) is None

    # Koordinaten-Zuordnung: uebersprungener Fund verschiebt nichts.
    finds = [{"year": 2010, "month": 7, "day": 19, "lat": 50.1, "lon": 8.1},
             {"year": 2010, "month": 8, "day": 8, "lat": 51.1, "lon": 9.1},
             {"year": 2010, "month": 8, "day": 9, "lat": 52.1, "lon": 10.1}]
    tag = lambda m, d: av.day_index(2010, m, d)  # noqa: E731
    samples = [{"year": 2010, "found_day": tag(7, 19)},
               {"year": 2010, "found_day": tag(8, 9)}]   # 8.8. uebersprungen
    zu = mit_koordinate(samples, finds)
    assert [s["lat"] for s in zu] == [50.1, 52.1], zu
    assert mit_koordinate([{"year": 2011, "found_day": 5}], finds) == []

    # Bodenfeuchte an Strata: Kontrolle i bekommt (control_years[i],
    # control_days[i]); eine Luecke wirft das Stratum heraus.
    class _B:
        liste = st

        def naechste(self, lat, lon):
            return 1, 3.0

        def reihe(self, sid):
            return reihe
    s = {"year": 2020, "found_day": 40, "lat": 50, "lon": 8,
         "controls": [("r", "t"), ("r", "t")],
         "control_years": [2020, 2020], "control_days": [50, 1]}
    voll, km = mit_bodenfeuchte([dict(s, control_days=[50, 60])], _B())
    assert len(voll) == 1 and voll[0]["feuchte"][:2] == [39.0, 38.0]
    assert voll[0]["feuchte_controls"][1][0] == 59.0
    assert mit_bodenfeuchte([s], _B())[0] == []   # Tag 1 hat keine 26 Tage davor

    # **Der Spiegel in Dart, Zahl fuer Zahl** — wie `ampel_validate
    # --self-test` fuer die Glockenklassen: Konstanten, Schwellen und
    # Mitglieder jeder Logit-Klasse muessen in `ampel_model.dart` so
    # stehen wie hier.
    dart_pfad = os.path.join(av.repo_path(""), av.AMPEL_MODEL_FILE) \
        if hasattr(av, "AMPEL_MODEL_FILE") else None
    if dart_pfad and os.path.isfile(dart_pfad):
        dart = open(dart_pfad, encoding="utf-8").read()
        for key, klasse in KLASSEN.items():
            m = re.search(r"const %s = \((.*?)\n\);" % klasse["dart"], dart, re.S)
            assert m, f"{klasse['dart']} fehlt in ampel_model.dart"
            block = m.group(1)
            for feld, erwartet in (("verhaltenAbove", klasse["verhalten"]),
                                   ("guenstigAbove", klasse["guenstig"])):
                w = re.search(r"%s: ([-0-9.e]+)" % feld, block)
                assert w and float(w.group(1)) == erwartet, (key, feld, w and w.group(1))
            for feld, erwartet in zip(("rain", "temp", "temp2", "moisture", "moistureTemp"),
                                      klasse["koeffizienten"]):
                w = re.search(r"\b%s: ([-0-9.e]+)" % feld, block)
                assert w and float(w.group(1)) == erwartet, (key, feld, w and w.group(1))
            assert "logit: AmpelLogit(" in block, key
        arten = re.search(r"const ampelSpeciesClass = <String, String>\{(.*?)\};", dart, re.S)
        in_dart = dict(re.findall(r"'([^']+)': '([^']+)'", arten.group(1)))
        for key, klasse in KLASSEN.items():
            assert {a for a, k in in_dart.items() if k == key} == set(klasse["members"]), key

    # Fixtures sind deterministisch und vollstaendig.
    fx = fixtures()
    assert fx == fixtures()
    for key in KLASSEN:
        assert all(v is not None for kk, v in fx[key].items())
    print("ampel_logit_klasse self-test: ok")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--fixtures", action="store_true",
                        help="Sollwerte fuer test/ampel_model_test.dart (JSON)")
    parser.add_argument("--schwellen", action="store_true",
                        help="Schwellen messen (Design B, P1) und gegen die Konstanten pruefen")
    parser.add_argument("--klasse", help="nur diese Klasse")
    parser.add_argument("--dataset", default="pinned")
    parser.add_argument("--cache-dir", default=None)
    parser.add_argument("--api", default=None,
                        help="Open-Meteo-Instanz (die Labor-Laeufe: http://127.0.0.1:8080/v1/archive)")
    # **Entdoppelt, wie das Labor gemessen hat** (`lab/bruecke.py` setzt
    # DEDUPE = True). Ohne das ist die Stichprobe eine andere, das Wetter
    # liegt nicht im Cache, und der Lauf holt es neu — am 2026-09-20 gegen
    # die oeffentliche API, bis ins Stundenlimit.
    parser.add_argument("--no-dedupe", action="store_true",
                        help="Doppelmeldungen behalten (nicht der Labor-Stand)")
    parser.add_argument("--dwd-dir", default=DWD_VERZEICHNIS)
    parser.add_argument("--rounds", type=int, default=2000)
    parser.add_argument("--bericht", default="docs/pilzampel-logit-schwellen.md")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return 0
    if args.fixtures:
        print(json.dumps(fixtures(), indent=2, ensure_ascii=False))
        return 0
    if args.schwellen:
        av.use_dataset(args.dataset)
        av.DEDUPE = not args.no_dedupe
        if args.api:
            av.OPEN_METEO = args.api.rstrip("/")
        bestand = DwdBestand(args.dwd_dir)
        ergebnisse, befunde = {}, []
        for key in ([args.klasse] if args.klasse else KLASSEN):
            print(f"{KLASSEN[key]['label']} ({key})", file=sys.stderr)
            e = messe_schwellen(key, args.cache_dir, bestand, rounds=args.rounds)
            if e is None:
                print("  keine Kontrolltage", file=sys.stderr)
                continue
            ergebnisse[key] = e
            print(f"  verhalten {e['punkt'][0]:.3f} {e['band'][0]}, "
                  f"guenstig {e['punkt'][1]:.3f} {e['band'][1]}", file=sys.stderr)
            befunde += pruefe_schwellen(key, e)
        schreibe_bericht(ergebnisse, args.bericht)
        print(f"{args.bericht} geschrieben", file=sys.stderr)
        if befunde:
            print("Konstanten weichen von der Messung ab:\n" + "\n".join(befunde),
                  file=sys.stderr)
            return 1
        return 0
    parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
