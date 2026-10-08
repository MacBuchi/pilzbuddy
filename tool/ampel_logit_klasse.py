#!/usr/bin/env python3
"""Die Logit-Klassen der Pilzampel — der Spiegel zu `AmpelLogitClass` in Dart.

**Warum eine eigene Datei.** `ampel_validate.py` kennt Klassen als
Temperaturfenster: ein Optimum, eine Glocke, zwei Schwellen als Quantile.
Die Klasse für Holz- und Winterpilze ist kein Fenster — sie ist ein
bedingtes Logit mit sechs Konstanten (`docs/pilzampel-holz-winter-plan.md`;
seit #676 mit ERA5-Land-Bodenfeuchte statt DWD-Station; die sechste,
„milder", seit Labor 24 — `docs/pilzampel-frost-plan.md`). Sie in die
Fenster-Maschinerie zu pressen hiesse, an sechzig Stellen „wenn Fenster,
sonst …" zu schreiben. Hier steht sie EINMAL, und `ampel_model.dart`
spiegelt sie Zahl fuer Zahl; `test/ampel_model_test.dart` prueft das mit
Fixtures, die `--fixtures` erzeugt.

Was hier definiert ist:
  - die Klassen (Konstanten, Mitglieder, Schwellen, Beleg),
  - der Score `s` — exakt die Rechnung der App,
  - die Bodenfeuchte fuer die Rueckwaertsrechnung: ERA5-Land 7–28 cm
    (m³/m³, `smoist` im gepinnten Datensatz) an der Fundkoordinate, das
    26-Tage-Mittel VOR einem Tag — dieselbe Groesse wie das Gitter, aus
    dem die App liest (`tool/soil_moisture.py`, #676), und wie Labor 25,
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
import json
import math
import os
import re
import sys
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ampel_validate as av  # noqa: E402

# --- Die Klassen -------------------------------------------------------------

# Boden unter dem Regenfaktor vor dem Logarithmus — wie `logit_features`
# in `ampel_logit.py` und `REGEN_BODEN` im Labor.
REGEN_BODEN = 1e-3
FEUCHTE_FENSTER = 26      # Tage, Mittel — das Feuchtefenster des Modells
# **„milder"** (seit 2026-09-21, Labor 22/24): Mittel der Tagesminima der
# juengsten MILDER_JUNG Tage minus Mittel der Tage danach bis
# MILDER_FENSTER — „erst kalt, dann milder" als EINE Zahl in °C. Vor
# Fundtagen der Winterarten sind die letzten Tage milder und die Wochen
# davor kaelter (Labor 21); Frosttage-Zaehlungen (Labor 19) sahen das
# nicht, weil sie die ABFOLGE wegsummieren. Die Grenze 5 kam auf den
# Trainingsbloecken heraus (22), das Merkmal ist auf den Testbloecken
# bestaetigt (24: +0,007 [+0,001, +0,013] je Stratum, keine Art
# schlechter, Placebo darunter). Reihe wie die Feuchte: Vortag zuerst,
# und ein Fenster mit Luecke ist KEIN Fenster.
MILDER_FENSTER = 28
MILDER_JUNG = 5
QUANTILE = (0.50, 0.80)   # die Auslieferungsquantile (2026-09-12)
SPALTEN = ("log_regen", "temp", "temp2", "feuchte", "feuchte_x_temp", "milder")

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
        # **Ohne Bodenfeuchte** seit 2026-10-08 (#676, Labor 25/26,
        # Betreiber: „Ohne Feuchte"): Fit auf allen DACH-Trainingsstrata
        # der acht Arten ohne die beiden Feuchtespalten, Reihenfolge wie
        # SPALTEN. Labor 25 zeigte, dass die Feuchte dieser Klasse aus
        # keiner Quelle etwas bringt (das Placebo gewinnt in AT/CH fast
        # gleich viel); Labor 26 auf den Testbloecken: DE −0,007
        # [−0,031, +0,018] gegen das Logit mit DWD-Feuchte, keine Art
        # schlechter, AT/CH gegen „grau jenseits 100 km" +0,017 [+0,003,
        # +0,031]. Bis 1.222.x die sechs aus `24-testbloecke-abfolge.md`
        # (0.1915, 0.1350, -0.004712, 0.002383, -0.0004888, 0.04193).
        "koeffizienten": (0.1732, 0.06921, -0.003344, 0.0, 0.0, 0.03819),
        # Die Schwellen — gemessen mit `--schwellen` (Design B, P1, 2000
        # Zuege), hier gepinnt; der Lauf prueft sie bei jedem Mal nach.
        # Neu gezogen am 2026-09-21 unter der sechsten Konstante (vorher
        # 0,454 / 0,606 unter fuenf). Baender: verhalten [0,378, 0,396],
        # guenstig [0,551, 0,566]; 23 200 Kontrolltage.
        # Neu gezogen am 2026-10-08 ohne Feuchte (#676), auf ALLEN
        # P1-Strata statt nur denen mit DWD-Station. Vorher 0,387 / 0,558
        # unter sechs Konstanten. Die Skala ist eine andere — ohne die
        # Feuchtespalten verschiebt sich `s` als Ganzes.
        "verhalten": 0.099,
        "guenstig": 0.255,
        "schwellen_quelle": "Design B, P1, pinned (2026-10-08), docs/pilzampel-logit-schwellen.md",
        "gilt": "DE+AT+CH",
        "confirmed": True,
        "why": "Phase G auf DE-Test +0,402 [+0,255, +0,596], AT/CH-Test "
               "+0,206 [+0,081, +0,352], gegen die Klimatologie +0,020 "
               "[+0,000, +0,038] — Labor 15/16/18 (2026-09-20); milder "
               "auf den Testbloecken +0,007 [+0,001, +0,013] — Labor 24 "
               "(2026-09-21); ohne Feuchte DE −0,007 [−0,031, +0,018], "
               "AT/CH gegen grau +0,017 [+0,003, +0,031] — Labor 26 "
               "(2026-10-08)",
    },
    "cantharellales": {
        "dart": "ampelCantharellalesClass",
        "label": "Herbsttrompete & Co.",
        "members": ["Herbsttrompete", "Semmelstoppelpilz", "Trompetenpfifferling"],
        # **ERA5-Land 7–28 cm statt DWD `BFGL_AG`** seit 2026-10-08 (#676,
        # Labor 25, Kandidat E1; Betreiber: „Bauen", „am besten nur eine
        # Quelle"): Fit auf allen DACH-Trainingsstrata der drei Arten,
        # Feuchte in m³/m³. Auf den Testbloecken DE −0,008 n.s. gegen die
        # DWD-Feuchte, keine Art schlechter; AT/CH gegen „grau jenseits
        # 30 km" +0,144 [−0,059, +0,334], AUC 0,684 gegen 0,586 — nicht
        # gesichert (320 Teststrata). Die Naht (ERA5-Land haengt ~5 Tage
        # nach, die App schreibt fort) kostet ≤ 0,003 je Stratum. Bis
        # 1.223.x: (0.1039, 0.1547, -0.01399, 0.00333, 0.002237, 0.0) auf
        # % nFK, aus `15-testteil.md`. Ohne „milder" (0): fuer diese Klasse
        # nie gemessen.
        "koeffizienten": (-0.0368583, -0.0928386, -0.00978573, 4.94857,
                          0.903891, 0.0),
        # Die Skala ist die von `s`, nicht die 0…1 der Glocke. Gemessen am
        # 2026-10-08 auf allen 612 P1-Funden (jeder hat ein lueckenloses
        # ERA5-Fenster, keine Station, kein Abstand); Baender: verhalten
        # [2,535, 2,774], guenstig [3,225, 3,362]; 3 051 Kontrolltage.
        # Bis 1.223.x unter DWD-Feuchte 2,191 / 2,952.
        "verhalten": 2.652,
        "guenstig": 3.306,
        "schwellen_quelle": "Design B, P1, pinned (2026-10-08), docs/pilzampel-logit-schwellen.md",
        # Seit #676 mit ERA5-Land in ganz DACH; der Beleg fuer AT/CH ist
        # „nicht schlechter, eher besser", nicht gesichert.
        "gilt": "DE+AT+CH",
        "confirmed": True,
        "why": "Phase G auf DE-Test +0,417 [+0,131, +0,769] — Labor 15/16 "
               "(2026-09-20); ERA5-Land statt DWD: DE −0,008 n.s., AT/CH "
               "gegen grau +0,144 [−0,059, +0,334] — Labor 25 (2026-10-08)",
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


def milder(tmin, fenster=MILDER_FENSTER, jung=MILDER_JUNG):
    """Mittel der Tagesminima der juengsten `jung` Tage minus Mittel der
    Tage `jung + 1` bis `fenster` — `None`, wenn die Reihe kuerzer ist
    oder im Fenster eine Luecke hat (wie `feuchte_mittel`, und wie das
    Labor gerechnet hat: ein Stratum mit Luecke fiel weg). Nur die
    ersten `fenster` Werte zaehlen, Vortag zuerst. Eine Hoehenkorrektur
    kuerzt sich in der Differenz heraus — die App rechnet deshalb mit
    den rohen Stationsminima."""
    if tmin is None or len(tmin) < fenster:
        return None
    werte = tmin[:fenster]
    if any(v is None for v in werte):
        return None
    return sum(werte[:jung]) / jung - sum(werte[jung:]) / (fenster - jung)


def merkmale(regen, temp, feuchte, tmin=None):
    """Die sechs Spalten (Reihenfolge SPALTEN) oder `None` ohne
    Temperatur. Feuchte (`feuchte`, `feuchte_x_temp`) und `milder` sind
    fuer sich `None`, wenn ihre Reihe fehlt oder eine Luecke hat — ob das
    den Score kostet, entscheidet die Konstante der Klasse (`score`):
    Holz & Winter rechnet seit #676 ohne Feuchte, Herbsttrompete & Co.
    ohne Minima."""
    t = temperatur_mittel(temp)
    if t is None:
        return None
    m = feuchte_mittel(feuchte)
    log_f = math.log(max(av.rain_factor(regen), REGEN_BODEN))
    return (log_f, t, t * t, m, None if m is None else m * t, milder(tmin))


def braucht_feuchte(koeffizienten):
    """Wie `AmpelLogit.needsMoisture`: Zwei Nullen heissen „keine Reihe
    noetig" — dann zaehlt auch keine Feuchtestation."""
    return koeffizienten[3] != 0 or koeffizienten[4] != 0


def score(regen, temp, feuchte, koeffizienten, tmin=None):
    """`s` = Σ Koeffizient × Spalte — oder `None`, wenn eine Reihe fehlt,
    die die Klasse braucht.

    `regen`: 26 Tageswerte mm, Vortag zuerst. `temp`: 20 Tageswerte °C,
    Vortag zuerst. `feuchte`: 26 Tageswerte m³/m³ (ERA5-Land), Vortag zuerst — nur
    Pflicht, wo die Klasse sie braucht (`braucht_feuchte`). `tmin`:
    28 Tagesminima °C, Vortag zuerst — nur Pflicht, wo die Konstante fuer
    `milder` nicht 0 ist; eine Klasse ohne das Merkmal rechnet ohne die
    Reihe, statt an ihr zu scheitern.
    """
    spalten = merkmale(regen, temp, feuchte, tmin)
    if spalten is None:
        return None
    s = 0.0
    for k, x in zip(koeffizienten, spalten):
        if x is None:
            if k == 0:
                continue
            return None
        s += k * x
    return s


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


def mit_bodenfeuchte(samples):
    """Bodenfeuchte-Fenster fuer Fund und Kontrollen aus `smoist` des
    gepinnten Datensatzes (ERA5-Land 7–28 cm, 28 Tage, Vortag zuerst) —
    an der Fundkoordinate, wie die App am Spot im Gitter nachschlaegt.
    Strata mit Luecke fallen weg; die ersten 26 Werte zaehlen
    (`feuchte_mittel`)."""
    aus = []
    for s in samples:
        fund = (s.get("extra") or {}).get("smoist")
        extras = s.get("extra_controls") or [None] * len(s["controls"])
        kontrollen = [(e or {}).get("smoist") for e in extras]
        if any(feuchte_mittel(f) is None for f in [fund] + kontrollen):
            continue
        aus.append(dict(s, feuchte=fund, feuchte_controls=kontrollen))
    return aus


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
        # Die Minima kommen aus den Zusatzreihen des gepinnten Datensatzes
        # (`tmin`, 28 Tage, Vortag zuerst) — an der Fundkoordinate, wie T;
        # live nimmt die App die naechste Luftstation, mit demselben
        # Vorbehalt. Ein Kontrolltag ohne die Reihe traegt nichts bei.
        extras = s.get("extra_controls") or [None] * len(s["controls"])
        for (regen, temp), feuchte, extra, jahr, tag in zip(
                s["controls"], s["feuchte_controls"], extras,
                s["control_years"], s["control_days"]):
            wert = score(regen, temp, feuchte, koeffizienten,
                         tmin=(extra or {}).get("tmin"))
            if wert is None:
                continue
            aus.setdefault(s["year"], []).append(
                (wert, ad.schwellen_monat(jahr, tag), anteil))
    return aus


def messe_schwellen(key, cache_dir, rounds=2000, seed=42,
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
        if braucht_feuchte(klasse["koeffizienten"]):
            strata = mit_bodenfeuchte(p1)
        else:
            # Ohne Feuchte: alle Strata, wie die App, die die Klasse dann
            # ueberall rechnet.
            strata = [dict(s, feuchte=None,
                           feuchte_controls=[None] * len(s["controls"]))
                      for s in p1]
        tage = schwellen_tage(strata, klasse["koeffizienten"])
        n_kontroll = sum(len(v) for v in tage.values())
        mitglieder[art] = {"funde": len(strata), "kontrolltage": n_kontroll,
                           "jahre": len(tage),
                           "p1": len(p1),
                           "unter_grenze": len(strata) < min_funde}
        if progress:
            print(f"  {art}: {len(strata)} von {len(p1)} Funden auf P1, "
                  f"{n_kontroll} Kontrolltage", file=sys.stderr)
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
      "Bodenfeuchte kommt — bei einer Klasse, die sie braucht — seit #676 "
      "aus ERA5-Land 7–28 cm (m³/m³, `smoist` des gepinnten Datensatzes) "
      "an der Fundkoordinate, 26-Tage-Mittel; die App schlägt denselben "
      "Wert im Gitter von `tool/soil_moisture.py` nach. Ein Fund ohne "
      "lückenloses Fenster fällt weg. Eine Klasse ohne Feuchte (Holz & "
      "Winter) rechnet auf allen Strata. Das Merkmal "
      "„milder“ (Tagesminima der jüngsten 5 Tage gegen die Tage 6–28, "
      "seit 2026-09-21) kommt aus den Minima des gepinnten Datensatzes an "
      "der Fundkoordinate; die App nimmt dafür die nächste Luftstation — "
      "dieselbe Ersetzung wie bei der Temperatur.\n")
    for key, e in ergebnisse.items():
        klasse = KLASSEN[key]
        w(f"## {klasse['label']} (`{key}`)\n")
        if not braucht_feuchte(klasse["koeffizienten"]):
            w("Ohne Bodenfeuchte: alle Strata auf P1.\n")
        else:
            w("Bodenfeuchte ERA5-Land 7–28 cm an der Fundkoordinate.\n")
        w("| Art | Funde P1 | mit Fenster | Kontrolltage | Fundjahre |")
        w("|---|--:|--:|--:|--:|")
        for art, m in e["mitglieder"].items():
            if "fehler" in m:
                w(f"| {art} | — | — | — | {m['fehler']} |")
                continue
            warn = " ⚠" if m["unter_grenze"] else ""
            w(f"| {art}{warn} | {m['p1']} | {m['funde']} | {m['kontrolltage']} | "
              f"{m['jahre']} |")
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
    # Bodenfeuchte in m³/m³ (ERA5-Land, seit #676).
    feuchte = [0.30] * 26
    # Minima: fuenf milde Naechte nach 23 kalten — milder = +3 °C.
    tmin3 = [2.0] * 5 + [-1.0] * 23
    aus = {}
    for key, klasse in KLASSEN.items():
        k = klasse["koeffizienten"]
        aus[key] = {
            "koeffizienten": list(k),
            "s_regen20_t8_m030_milder3": score(regen, temp, feuchte, k, tmin=tmin3),
            "s_trocken_t3_m045_milder3": score([0.0] * 26, [3.0] * 20, [0.45] * 26, k,
                                               tmin=tmin3),
            "s_gleichmaessig_t13_m020_milder0": score([87 / 26] * 26, [13.0] * 20,
                                                      [0.20] * 26, k, tmin=[4.0] * 28),
            "s_regen20_t8_m030_milderMinus2": score(regen, temp, feuchte, k,
                                                    tmin=[-3.0] * 5 + [-1.0] * 23),
        }
    aus["merkmale_regen20_t8_m030_milder3"] = list(merkmale(regen, temp, feuchte, tmin3))
    return aus


# --- Selbsttest --------------------------------------------------------------

def self_test():
    # Sechs Konstanten; die sechste (milder) mit 0,1 je °C.
    k = (1.0, 0.5, -0.01, 0.02, -0.001, 0.1)
    regen = [20.0] + [0.0] * 25
    temp = [8.0] * 20
    feuchte = [60.0] * 26
    tmin = [2.0] * 5 + [-1.0] * 23      # milder = 2 − (−1) = +3 °C
    # Von Hand: log F + 0,5·8 − 0,01·64 + 0,02·60 − 0,001·60·8 + 0,1·3
    f = av.rain_factor(regen)
    soll = math.log(f) + 4.0 - 0.64 + 1.2 - 0.48 + 0.3
    assert abs(score(regen, temp, feuchte, k, tmin=tmin) - soll) < 1e-12
    # Trockener Regen: Boden 1e-3 vor dem Logarithmus, kein log(0).
    assert abs(score([0.0] * 26, temp, feuchte, k, tmin=tmin)
               - (math.log(1e-3) + 4.0 - 0.64 + 1.2 - 0.48 + 0.3)) < 1e-12
    # Feuchte: zu kurz oder mit Luecke -> kein Score; Temperatur mit
    # Luecke -> Fehltag uebersprungen (wie die Glocke).
    assert score(regen, temp, feuchte[:25], k, tmin=tmin) is None
    assert score(regen, temp, feuchte[:10] + [None] + feuchte[11:], k, tmin=tmin) is None
    assert abs(score(regen, [8.0] * 10 + [None] * 10, feuchte, k, tmin=tmin) - soll) < 1e-12
    assert score(regen, [None] * 20, feuchte, k, tmin=tmin) is None
    # Nur die ersten 26 Feuchtetage zaehlen (juengste zuerst).
    assert abs(score(regen, temp, feuchte + [0.0] * 5, k, tmin=tmin) - soll) < 1e-12
    # **milder**: 28 Tage, Vortag zuerst, jung gegen alt; zu kurz oder
    # mit Luecke ist KEIN Fenster; nur die ersten 28 Werte zaehlen.
    assert milder(tmin) == 3.0
    assert milder([2.0] * 5 + [-1.0] * 22) is None, "27 Tage sind kein Fenster"
    assert milder([2.0] * 5 + [-1.0] * 10 + [None] + [-1.0] * 12) is None
    assert milder(tmin + [50.0] * 3) == 3.0, "der 29. Tag zaehlt nicht"
    assert milder([4.0] * 28) == 0.0
    assert milder([-3.0] * 5 + [-1.0] * 23) == -2.0, "kaelter zuletzt ist negativ"
    assert milder(None) is None
    # Ohne Minima: kein Score, wo die Konstante nicht 0 ist — und der
    # alte Score, wo sie es ist (Cantharellales braucht die Reihe nicht).
    assert score(regen, temp, feuchte, k) is None
    assert score(regen, temp, feuchte, k, tmin=tmin[:27]) is None
    k0 = k[:5] + (0.0,)
    assert abs(score(regen, temp, feuchte, k0) - (soll - 0.3)) < 1e-12
    assert abs(score(regen, temp, feuchte, k0, tmin=tmin) - (soll - 0.3)) < 1e-12
    assert merkmale(regen, temp, feuchte)[5] is None
    assert merkmale(regen, temp, feuchte, tmin)[5] == 3.0
    # **Ohne Feuchte** (#676): zwei Nullen heissen „keine Reihe noetig",
    # eine fehlende oder lueckige Reihe kostet dann nichts; wo die Klasse
    # sie braucht, bleibt es bei „kein Score".
    kf = (k[0], k[1], k[2], 0.0, 0.0, k[5])
    ohne_feuchte = soll - 1.2 + 0.48
    assert not braucht_feuchte(kf) and braucht_feuchte(k)
    assert abs(score(regen, temp, None, kf, tmin=tmin) - ohne_feuchte) < 1e-12
    assert abs(score(regen, temp, feuchte[:25], kf, tmin=tmin) - ohne_feuchte) < 1e-12
    assert abs(score(regen, temp, feuchte, kf, tmin=tmin) - ohne_feuchte) < 1e-12
    assert score(regen, temp, None, k, tmin=tmin) is None
    assert merkmale(regen, temp, None, tmin)[3:5] == (None, None)
    assert not braucht_feuchte(KLASSEN["holz_winter"]["koeffizienten"])
    assert braucht_feuchte(KLASSEN["cantharellales"]["koeffizienten"])
    assert KLASSEN["cantharellales"]["koeffizienten"][5] == 0.0
    assert KLASSEN["holz_winter"]["koeffizienten"][5] != 0.0
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

    # Bodenfeuchte an Strata: `smoist` aus Fund und Kontrollen; eine
    # Luecke in irgendeinem Fenster wirft das Stratum heraus, Werte nach
    # dem 26. Tag zaehlen nicht.
    s = {"year": 2020, "controls": [("r", "t"), ("r", "t")],
         "extra": {"smoist": [0.3] * 26 + [None, None]},
         "extra_controls": [{"smoist": [0.2] * 28}, {"smoist": [0.25] * 28}]}
    voll = mit_bodenfeuchte([s])
    assert len(voll) == 1 and abs(feuchte_mittel(voll[0]["feuchte"]) - 0.3) < 1e-12
    assert [round(feuchte_mittel(f), 12) for f in voll[0]["feuchte_controls"]] == [0.2, 0.25]
    loch = dict(s, extra_controls=[{"smoist": [0.2] * 10 + [None] + [0.2] * 17},
                                   {"smoist": [0.25] * 28}])
    assert mit_bodenfeuchte([loch]) == []
    assert mit_bodenfeuchte([dict(s, extra_controls=None)]) == []
    assert mit_bodenfeuchte([dict(s, extra={})]) == []

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
            felder = ("rain", "temp", "temp2", "moisture", "moistureTemp", "milder")
            assert len(felder) == len(SPALTEN) == len(klasse["koeffizienten"]), key
            for feld, erwartet in zip(felder, klasse["koeffizienten"]):
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
        ergebnisse, befunde = {}, []
        for key in ([args.klasse] if args.klasse else KLASSEN):
            print(f"{KLASSEN[key]['label']} ({key})", file=sys.stderr)
            e = messe_schwellen(key, args.cache_dir, rounds=args.rounds)
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
