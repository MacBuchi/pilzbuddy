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
import ast
import contextlib
import io
import inspect
import datetime
import importlib.util
import json
import math
import os
import random
import re
import statistics
import sys
import textwrap
import time
import urllib.error
import urllib.parse
import urllib.request

GBIF = "https://api.gbif.org/v1"

_spec = importlib.util.spec_from_file_location(
    "gbif_local", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                               "gbif_local.py"))
gbif_local = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gbif_local)

_spec = importlib.util.spec_from_file_location(
    "ampel_basis", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "ampel_basis.py"))
ampel_basis = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ampel_basis)

# **Welcher Wetterdatensatz** — ab 2026-09-17 ein ausdrücklicher Wert
# statt eines Weglassens (`docs/pilzampel-messbasis.md`, Phase 0.1).
#
# Die Vorgabe bleibt `vorgabe`, also Open-Meteos „best match", damit jeder
# frühere Lauf sich reproduzieren lässt. Sie ist aber nachweislich KEIN
# fester Datensatz: Bis 2016 ist sie ERA5-Land, ab 2017 IFS HRES, und die
# Hold-out-Trennlinie liegt genau auf dieser Naht. Jede neue Messung läuft
# deshalb mit `--dataset pinned`.
DATASET = ampel_basis.DEFAULT_DATASET

# Die Felder JENSEITS von Regen und Temperatur, die der gewählte Datensatz
# mitbringt — Tiefstwert, Schnee, Bodenfeuchte, Bodentemperatur. Auf der
# Vorgabe ist die Liste leer; das Modell der ausgelieferten Ampel rührt
# sie ohnehin nicht an. Sie werden mitgezogen, damit Phase 1 und 2 ohne
# einen zweiten vollständigen Neuabruf auskommen.
EXTRA_FIELDS = []


def use_dataset(name):
    """Den Datensatz wählen — und alles, was daran hängt, mitziehen."""
    global DATASET, EXTRA_FIELDS, SPAN_LOOKBACK
    if name not in ampel_basis.DATASETS:
        raise SystemExit(
            f"Unbekannter Datensatz {name!r}. Bekannt: "
            f"{', '.join(sorted(ampel_basis.DATASETS))}")
    DATASET = name
    EXTRA_FIELDS = [f for f in ampel_basis.dataset_fields(name)
                    if f not in ("rain", "temp")]
    # Der Vorlauf muss reichen, sobald es etwas zu rechnen gibt, was über
    # das Regenfenster hinausgeht (Frostdosis über 28 Tage in H3).
    SPAN_LOOKBACK = 28 if EXTRA_FIELDS else RAIN_WINDOW
    return DATASET

# **Die Vorgabe bleibt der öffentliche Dienst** (#460). Eine eigene
# Instanz ist per `--api` erreichbar, aber nicht die Vorgabe: Ein
# Werkzeug, das stillschweigend mit localhost redet, erzeugt Zahlen, die
# außerhalb dieses Rechners niemand nachrechnen kann.
#
# Dass beide dasselbe liefern, ist GEMESSEN und nicht angenommen:
# Herbsttrompete, vier Jahre, 17 644 Tageswerte, Abweichung 0,00 K und
# 0,00 mm (docs/pilzampel-openmeteo-lokal.md). Die eigene Instanz ist
# damit dasselbe Instrument — deshalb darf ein Lauf, der halb aus dem
# Cache und halb von dort kommt, in einer Tabelle stehen.
OPEN_METEO = "https://archive-api.open-meteo.com/v1/archive"
OPEN_METEO_DEFAULT = OPEN_METEO
MUSHROOM_OBSERVER = "https://mushroomobserver.org/api2/observations"

SPECIES_FILE = "lib/core/mushroom_species.dart"

# Der Modellkern der App. Gespiegelt wird er in diesem Werkzeug seit
# jeher — geprüft wurde die Spiegelung nie.
AMPEL_MODEL_FILE = "lib/features/ampel/ampel_model.dart"
SEASON_CURVES_FILE = "lib/core/season_curves.g.dart"


def repo_path(relative):
    """Pfad im Repo, unabhängig vom Arbeitsverzeichnis des Aufrufers.

    Die Artenliste wurde bis 2026-09-12 RELATIV gelesen; der Tranchen-
    Läufer des August-Laufs musste dafür eigens ins Repo wechseln, und
    ein Aufruf von woanders scheiterte an einer Datei statt an der
    Sache.
    """
    return os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), relative)

# Das RADOLAN-Archiv des DWD beginnt 2006; auch wenn hier Open-Meteo die
# Werte liefert, bleibt es die Grenze, ab der sich jede Zahl gegen deutsche
# Radardaten nachprüfen ließe.
FIRST_YEAR = 2006

# Das LAUFENDE Jahr zählt nicht mit: Seine Saison ist noch nicht vorbei,
# und ein halbes Pilzjahr ist genau die Lücke, die dieses Werkzeug sonst
# überall verweigert (Pilzjahre unterscheiden sich um den Faktor zehn).
#
# Es ist außerdem gar nicht abfragbar: `season_span` reicht bis 91 Tage
# über den spätesten Fund hinaus, das Open-Meteo-Archiv endet aber HEUTE.
# Beim 2000er-Lauf am 2026-08-11 lief der Pfifferling deshalb in ein
# „HTTP 400 … end_date is out of allowed range" und riss den ganzen Lauf
# mit — dieselbe Klasse Fehler wie die frühere feste Klemme auf Index 365
# (siehe `season_span`): eine Obergrenze, die nicht stimmte.
#
# Warum hier und nicht in der GBIF-Abfrage: Die Stichprobe wird aus ALLEN
# Funden gezogen. Nähme man 2026 schon dort heraus, fiele die Ziehung
# anders aus, und der gesamte Wetter-Cache wäre wertlos.
LAST_COMPLETE_YEAR = datetime.date.today().year - 1

# Gröber als das ist die Ortsangabe der Meldungen ohnehin nicht (Median
# 250 m), und schlechter als 1 km wäre für ein 1-km-Wetterraster wertlos.
MAX_UNCERTAINTY_M = 1000

# So viele Funde je Art werden ausgewertet — eine Zufallsstichprobe mit
# festem Seed, keine Auswahl nach Güte.
#
# 2000 statt der ursprünglichen 500 (2026-08-09): Für die EFFEKT-Frage
# („steht dort 0,50 oder 0,58?") reichten 500 Paare (AUC-Standardfehler
# ~0,02) — aber die PLACEBO-Kontrolle stellt eine strengere Frage. Der
# erste vollständige Lauf zeigte Placebo-Abweichungen bis 0,068 bei
# SE≈0,023: zu groß zum Abnicken, zu klein, um Rauschen von einem echten
# Methodenfehler zu unterscheiden — und nach der eigenen Regel des
# Konzepts sind damit ALLE Zahlen nicht bewertbar. Bei 2000 Paaren
# halbiert sich der Standardfehler auf ~0,011; ein echter Bias der
# beobachteten Größe stünde dann als >4σ da, Rauschen fiele auf ≤0,03
# zusammen.
#
# Der Preis ist Zeit, kein Umbau: Open-Meteo zählt Aufrufe gewichtet
# (Orte × Variablen × Tage/365), das Tageslimit liegt bei 10.000, und
# dieser Umfang braucht mehrere Tage. Genau dafür scheitert der Lauf am
# Tageslimit HART (siehe _fetch_json) und der --cache trägt alles schon
# Geholte in den nächsten Lauf — einfach täglich neu starten, bis er
# durchläuft.
SAMPLE_PER_SPECIES = 2000

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

# --- Die Klassen ----------------------------------------------------------
#
# **Die Einheit des Modells ist die Klasse, nicht die Art** (Betreiber,
# 2026-09-12). Der Grund steht in `docs/pilzampel-schwellen-messung.md`:
# Arten mit demselben Fenster bekommen Schwellen, deren
# Vertrauensbereiche sich satt überlappen (Steinpilz [0,148, 0,238]
# gegen Herbsttrompete [0,089, 0,284]) — je Art ausgeliefert wäre das
# Rauschen in Konstantenform, und am Ende stünden 110 Einträge da, von
# denen keiner mehr prüfbar ist. Zwischen den Fenstern liegen dagegen
# Welten (0,493 gegen 0,037 beim Austernseitling).
#
# Eine Klasse ist **ein Temperaturfenster**. Die beiden Schwellen sind
# kein zweiter freier Parameter, sondern fallen daraus: das 50-%- und
# 80-%-Quantil der Verteilung, die dieses Fenster an Vergleichstagen
# erzeugt.
#
# **Nur BESTÄTIGTE Klassen tragen Zahlen.** Eine unbestätigte steht hier
# mit Mitgliedern und Begründung, aber ohne Fenster und ohne Schwellen:
# die kommen aus der Messung, wo sie gebraucht werden (`class_optimum`,
# `class_thresholds`). Der Grund ist an einem Tag zweimal aufgetreten —
# eine Konstante für eine Klasse, die die App nicht ausliefert, bewacht
# nichts und lädt zum Raten ein. Erst stand dort ein von Hand gerundetes
# Fenster, dann eines aus einer Berichtstabelle abgeschrieben, und jede
# Korrektur verschob die Schwellen darunter gleich mit.
#
# Aufgenommen wird nur, was einen HOLD-OUT bestanden hat. „Sieht in der
# Tabelle anders aus" reicht nicht — genau daran ist die
# Pfifferling-Spur fast gescheitert, bis Österreich und die Schweiz sie
# bestätigt haben.
# Die Latten des registrierten Kalttests (2026-09-12,
# docs/pilzampel-artenfenster.md) — hier oben, weil die Klassentabelle
# darunter sie braucht.
COLD_MAX_OPTIMUM_C = 5.0
COLD_MIN_GAIN = 0.05

AMPEL_CLASSES = {
    "sommer": {
        "dart": "ampelSommerClass",
        # Wie die Klasse in der App heißt — nach ihren MITGLIEDERN, nicht
        # nach einer Jahreszeit. „Sommerpilze" behauptete eine Gruppe;
        # drin steht ein Pfifferling.
        "label": "Pfifferling",
        # Gemessen am 2026-09-12; `class_thresholds` rechnet beide Zahlen
        # bei jedem Lauf nach und bricht ab, wenn sie gewandert sind.
        "verhalten": 0.287,
        "guenstig": 0.677,
        "optimum": 17.5,
        "members": ["Pfifferling"],
        "confirmed": True,
        "why": "Hold-out in AT+CH bestätigt: AUC 0,584 → 0,689 "
               "(+0,104 [+0,055, +0,150]), abstandsgleiche Kontrolle "
               "0,510 (docs/pilzampel-artenfenster-holdout.md)",
    },
    "herbst": {
        "dart": "ampelHerbstClass",
        # Wie die Klasse in der App heißt — nach ihren MITGLIEDERN, nicht
        # nach einer Jahreszeit. „Sommerpilze" behauptete eine Gruppe;
        # drin steht ein Pfifferling.
        "label": "Steinpilz & Co.",
        # Gemessen am 2026-09-12; `class_thresholds` rechnet beide Zahlen
        # bei jedem Lauf nach und bricht ab, wenn sie gewandert sind.
        "verhalten": 0.187,
        "guenstig": 0.512,
        "optimum": 13.0,
        "members": ["Steinpilz", "Maronenröhrling", "Birkenpilz",
                    "Fichtenreizker", "Herbsttrompete"],
        "confirmed": True,
        "why": "der ausgelieferte Stand; die eigenen Optima dieser fünf "
               "liegen zwischen 12,0 und 14,5 °C, und keine Abweichung "
               "von 13 °C schließt die Null aus",
    },
    # Noch NICHT ausgeliefert — beide brauchen ihren eigenen Hold-out.
    # Sie stehen hier, damit der Bericht ihre Zahlen mitrechnet und die
    # Entscheidung auf Zahlen trifft statt auf Erinnerung.
    "herbst_holz": {
        # **Kein Fenster, keine Schwellen** — siehe den Tabellenkopf.
        #
        # **Und sie wird auch keine bekommen.** Der registrierte Hold-out
        # ist am 2026-09-13 gescheitert, bei sauberer Kontrolle (beide
        # abstandsgleichen Kontrollen 0,501). Die Klasse bleibt hier
        # stehen, weil ein gelöschter Eintrag die Messung vergessen
        # machte — und weil die Frage, wohin Hallimasch und
        # Stockschwämmchen gehören, offen ist.
        "members": ["Hallimasch", "Stockschwämmchen"],
        "confirmed": False,
        "why": "Hold-out in AT+CH GESCHEITERT (2026-09-13): Hallimasch "
               "+0,018 [-0,003, +0,040], Stockschwämmchen -0,036 "
               "[-0,073, +0,000] gegenüber 13 °C — und dessen Optimum "
               "liegt dort bei 15,5 °C statt bei 12,25 "
               "(docs/pilzampel-herbstholz-holdout.md)",
    },
    "kalt": {
        # **Kein Fenster, keine Schwellen** — siehe den Tabellenkopf.
        # Die drei Mitglieder stehen hier, seit der Kalttest bestanden
        # ist; ausgeliefert ist die Klasse damit NICHT — dafür fehlen die
        # gemessenen Schwellen, und ohne sie macht ein eigenes Fenster
        # die Ampel dunkel statt besser (Austernseitling: „günstig" fiel
        # von 21,7 auf 1,1 % der Fundtage).
        "members": ["Austernseitling", "Judasohr", "Samtfußrübling"],
        # **Die Richtungs-Latte einer KALTEN Klasse sind nicht die
        # 13 °C.** Unter 13 landet ein Winterfrüchter ohnehin; die Frage
        # ist, ob er im Ausland wieder im KALTEN Bereich landet. Deshalb
        # dieselbe Grenze wie im Kalttest.
        "direction_below": COLD_MAX_OPTIMUM_C,
        "confirmed": False,
        "why": "Kalttest in DE bestanden (2026-09-13), Schwellen "
               "gemessen — aber der geografische Hold-out des "
               "KLASSENfensters ist am selben Tag GESCHEITERT: In AT+CH "
               "fällt der Judasohr mit -0,066 [-0,117, -0,013] unter die "
               "13 °C zurück und passt sich dort auf 12,0 °C an statt "
               "auf seine deutschen 1,5. Das Fenster gehört der "
               "deutschen Stichprobe, nicht den Arten "
               "(docs/pilzampel-kaltklasse-holdout.md)",
    },
}


def class_of(name):
    """Die Klasse einer Art — `None`, wenn sie keiner zugeordnet ist."""
    for key, klass in AMPEL_CLASSES.items():
        if name in klass["members"]:
            return key
    return None


# Die registrierte Prüfung auf eine KALTE KLASSE (2026-09-12,
# docs/pilzampel-artenfenster.md). Beide waren an keiner Anpassung
# beteiligt — das ist ihr Wert. Sie stehen NICHT im Standardlauf: Dessen
# Zahlen sind veröffentlicht, und eine Liste, die stillschweigend wächst,
# macht jede Wiederholung unvergleichbar.
COLD_CANDIDATES = [
    "Judasohr",
    "Samtfußrübling",
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


# --- Anpassung je Art (docs/pilzampel-artenfenster.md) ---------------------
#
# **Getrennt wird nach JAHREN, nicht nach Funden.** Pilzjahre
# unterscheiden sich um den Faktor zehn, und Funde desselben Jahres sind
# einander ähnlicher als Funde verschiedener Jahre — ein zufälliger
# Fund-Split trüge diese Ähnlichkeit über die Trennlinie und machte jede
# Prüfzahl zu optimistisch.
FIT_UNTIL_YEAR = 2018

# Der Gitterlauf. Bewusst grob: Eine feinere Auflösung als ein halbes
# Kelvin behauptet eine Genauigkeit, die 300–2000 Paare nicht hergeben.
#
# **Die Untergrenze lag bis 2026-09-11 bei 2 °C und war zu hoch.** Der
# Austernseitling landete dort auf dem Boden, und die `at_edge`-Warnung
# hat genau dafür angeschlagen: Ein Gipfel am Gitterrand ist keiner. Die
# Nachschau über einen weiteren Bereich zeigte den echten Gipfel bei
# etwa 0 °C — die Kurve flacht darunter ab, läuft also nicht weiter
# davon. −5 °C gibt ihm Luft, ohne ins Sinnlose zu reichen: Ein Mittel
# über zwanzig Tage unter −5 °C kommt in unseren Reihen praktisch nicht
# vor.
#
# Das ist KEINE Anpassung an ein Ergebnis. Die Grenze wurde verschoben,
# weil der Wächter sie als bindend gemeldet hat — hätte er geschwiegen,
# wäre sie geblieben.
FIT_GRID_MIN_C = -5.0
FIT_GRID_MAX_C = 20.0
FIT_GRID_STEP_C = 0.5

# Wie viele Bootstrap-Ziehungen für den Vertrauensbereich — gezogen wird
# über PRÜFJAHRE, nicht über Paare, aus demselben Grund wie oben.
FIT_BOOTSTRAP_ROUNDS = 1000


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


def temperature_factor(daily_c, optimum=OPTIMUM_C):
    """Glocke um [optimum] über das Mittel der letzten 20 Tage, 0…1.

    Der Vorgabewert ist der ausgelieferte (13 °C) — die Spiegel-Regel zu
    `ampel_model.dart` gilt für ihn. [optimum] ist NUR für die Anpassung
    je Art da (`docs/pilzampel-artenfenster.md`); ein anderer Wert hier
    bedeutet nicht, dass die App ihn rechnet.
    """
    values = [c for c in daily_c[:TEMP_WINDOW] if c is not None]
    if not values:
        return 0.0
    mean = sum(values) / len(values)
    return math.exp(-(((mean - optimum) / TEMP_SIGMA) ** 2))


def ampel_score(daily_mm, daily_c, optimum=OPTIMUM_C):
    """Der Wetterteil der Ampel — OHNE Saisonfaktor, siehe Kopf."""
    return rain_factor(daily_mm) * temperature_factor(daily_c, optimum)


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

    **Aufgelöst über [repo_path]**, nicht relativ zum Arbeitsverzeichnis.
    Vorher scheiterte jeder Aufruf von außerhalb des Repos an einer
    fehlenden Datei statt an der Sache; der Tranchen-Läufer des
    August-Laufs musste deshalb eigens ins Repo wechseln.
    """
    text = open(repo_path(path) if not os.path.isabs(path) else path,
                encoding="utf-8").read()
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


def _finds_cache_path(cache_dir, sci, countries=("DE",)):
    safe = "".join(c if c.isalnum() else "_" for c in sci)
    # Deutschland bleibt ohne Zusatz — sonst wären alle vorhandenen
    # Fundlisten mit einem Schlag nicht mehr auffindbar, und genau das
    # ist der Fehler, gegen den diese Dateien überhaupt angelegt wurden.
    if tuple(countries) == ("DE",):
        return os.path.join(cache_dir, f"finds_{safe}.json")
    return os.path.join(cache_dir, f"finds_{safe}_{'-'.join(countries)}.json")


def fetch_finds(sci, limit=3000, progress=True, cache_dir=None,
                countries=("DE",)):
    """Fundmeldungen mit Koordinate, taggenauem Datum und Ortsgenauigkeit.

    **Mit `cache_dir` wird die Liste FESTGENAGELT** — und das ist keine
    Beschleunigung, sondern die Voraussetzung dafür, dass ein Lauf über
    mehrere Tage überhaupt möglich ist.

    Der Grund, gemessen am 2026-09-11: GBIF WÄCHST. Zwei Läufe derselben
    Art im Abstand von zwei Stunden lieferten 2259 gegen 2253 Meldungen
    (im September kommen täglich neue herein). Damit zieht
    `random.Random(seed).sample` eine andere Teilmenge, die Ortslisten je
    Jahr ändern sich — und der Wetter-Cache ist ein Hash GENAU dieser
    Ortslisten. Sein Schlüssel zeigt danach ins Leere, obwohl die Daten
    dahinter dieselben wären.

    So ist der Bestand vom August unbrauchbar geworden: Seine Ortslisten
    stammen aus einer Grundgesamtheit, die es nicht mehr gibt, und die
    Fundlisten selbst wurden nicht gesichert. Deshalb jetzt hier.

    Wer bewusst neu ziehen will, löscht die `finds_*.json` — dann ist es
    eine Entscheidung und kein Nebeneffekt der Uhrzeit.
    """
    if cache_dir:
        path = _finds_cache_path(cache_dir, sci, countries)
        if os.path.exists(path):
            finds = json.load(open(path, encoding="utf-8"))
            if progress:
                print(f"    {len(finds)} Meldungen (festgenagelt)",
                      file=sys.stderr)
            return finds
    finds = _finds_from_local(sci, limit, progress, countries)
    if finds is None:
        finds = [{k: v for k, v in record.items() if k != "key"}
                 for record in _fetch_finds_raw(sci, limit, progress,
                                                countries)]
    if cache_dir:
        os.makedirs(cache_dir, exist_ok=True)
        with open(_finds_cache_path(cache_dir, sci, countries), "w",
                  encoding="utf-8") as handle:
            json.dump(finds, handle)
    return finds


def _finds_from_local(sci, limit, progress, countries):
    """Fundmeldungen aus dem lokalen Bestand — oder `None`.

    **Erst NACH dem Cache, nie davor.** Die Reihenfolge ist hier keine
    Geschmacksfrage: Der Wetter-Cache ist ein Hash GENAU der Ortslisten,
    die aus dieser Stichprobe fallen. Die Datenbank sortiert nach
    `gbifID`, die API paginiert in ihrer eigenen Reihenfolge — beide
    liefern also verschiedene 3000er-Ausschnitte. Zöge man den lokalen
    Bestand vor, zeigte jeder bestehende Wetter-Cache-Schlüssel ins
    Leere, und Wochen an Messungen wären hin (siehe COWORK.md im
    Ampel-Ordner, wo genau das schon einmal passiert ist).

    Für eine Art OHNE Cache ist er dagegen richtig: Die Stichprobe wird
    ohnehin neu gezogen und anschließend festgenagelt.
    """
    con = gbif_local.connect()
    if con is None:
        return None
    # Der Rang steckt im Namen: ein Wort = Gattung (`Armillaria`), zwei =
    # Art. Dieselbe Unterscheidung trifft `season_curves.check_taxon`
    # über GBIF; hier reicht der Name, weil `taxon_key` den Namen bereits
    # gegen GBIF geprüft hat und bei allem außer EXACT/ACCEPTED abbricht.
    rank = "GENUS" if " " not in sci.strip() else "SPECIES"
    where, args = gbif_local.taxon_where(sci, rank, taxon_key(sci))
    # **Der lokale Bestand kennt keine Obergrenze mehr** (A4, 2026-09-17).
    #
    # Die 3000 stammen vom NETZWEG, wo tiefes Blättern kriecht (ab
    # `offset` ~10 000 braucht dieselbe Seite 341 s statt 0,3 s,
    # CLAUDE.md). Hier kostet die Grenze nichts und schneidet dafür nach
    # `gbifID`, also die JÜNGSTEN Einträge ab — und `gbifID` korreliert
    # mit dem Meldeportal.
    #
    # Betroffen war unter den gemessenen Arten genau eine: **Judasohr**
    # mit 3097 Meldungen in DE. Ausgerechnet die Art, gegen die vier
    # Befunde stehen — und alle vier stammen aus derselben,
    # möglicherweise beschnittenen Stichprobe. Vier Blickwinkel sind
    # keine vier unabhängigen Tests.
    limit = None
    rows = con.execute(
        f"SELECT decimalLatitude, decimalLongitude, year, month, day, "
        f"       recordedBy, countryCode, gbifID "
        f"FROM occ WHERE {gbif_local.WHERE_USABLE} AND {where} "
        f"  AND countryCode IN ({','.join('?' * len(countries))}) "
        f"  AND year >= ? AND day IS NOT NULL AND month IS NOT NULL "
        f"  AND (coordinateUncertaintyInMeters IS NULL "
        f"       OR coordinateUncertaintyInMeters <= ?) "
        f"ORDER BY gbifID" + ("" if limit is None else " LIMIT ?"),
        (*args, *countries, FIRST_YEAR, MAX_UNCERTAINTY_M)
        + ((), (limit,))[limit is not None]).fetchall()
    con.close()
    if progress:
        print(f"    {len(rows)} Meldungen (lokaler Bestand)", file=sys.stderr)
    # `recordedBy` und `countryCode` seit Phase 0.2: Das erste trägt das
    # Entdoppeln (eine Exkursion ist keine zehn Beobachtungen), das
    # zweite die Melder-Diagnose aus Phase 1.4. Beide Spalten lagen die
    # ganze Zeit im Bestand und wurden nur nie gelesen.
    return [{"lat": r[0], "lon": r[1], "year": r[2], "month": r[3],
             "day": r[4], "recordedBy": r[5], "countryCode": r[6],
             "gbifID": r[7]} for r in rows]


def _fetch_finds_raw(sci, limit=3000, progress=True, countries=("DE",)):
    """Wie [fetch_finds], aber MIT der GBIF-id je Meldung.

    Die id trägt die Aufnahmereihenfolge: Neu aufgenommene Meldungen
    bekommen höhere Werte. Genau daran hängt [recover_sample].
    """
    key = taxon_key(sci)
    finds = []
    offset = 0
    while len(finds) < limit:
        page = _get(f"{GBIF}/occurrence/search", {
            "taxonKey": key,
            "country": list(countries),
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
                "key": record["key"],
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


# **Wieviel Vorlauf geholt wird**, in Tagen vor dem frühesten Fund
# (zusätzlich zum Höchstabstand des Vergleichstags).
#
# Das ist NICHT dasselbe wie der Mindestabstand des Vergleichstags, auch
# wenn beide bisher 26 waren. Der Vorlauf sagt, wieviel Wetter im Cache
# liegt; der Abstand sagt, wie weit der Vergleichstag wegrückt. Phase 2
# will Frostdosen über 28 Tage rechnen — dafür muss der Vorlauf jetzt
# reichen, denn nachträglich wäre es ein zweiter vollständiger Neuabruf.
# Der Abstand bleibt davon unberührt bei 26, sonst wäre der Referenzlauf
# in 0.4 nicht mehr nur ein Instrumentwechsel.
SPAN_LOOKBACK = RAIN_WINDOW


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
    first = max(1, min(days_of_year) - CONTROL_MAX_GAP - SPAN_LOOKBACK - 1)
    last = min(last_index, max(days_of_year) + CONTROL_MAX_GAP * 2 + 1)
    return first, last


def clamp_span(span, year):
    """Einen Zeitraum auf ein ANDERES Jahr zuschneiden.

    **Index 365 gibt es nur in Schaltjahren.** `season_span` klemmt
    deshalb schon auf das Jahr, aus dem es gerufen wurde — Design B
    reicht denselben Zeitraum aber an bis zu zehn andere Jahre weiter,
    und in einem Nicht-Schaltjahr wird aus Index 365 das Datum
    „JJJJ-13-01". Open-Meteo antwortet darauf mit einem 400, und zwar
    ohne zu sagen, welches Feld es stört.

    Genau so ist beim ersten Probelauf die Hälfte der Kontrolljahre
    ausgefallen — und weil Design B fehlende Jahre absichtlich nur zählt
    statt abzubrechen, wäre es als „dünne Datenlage" durchgegangen. Der
    Zähler hat den Fehler sichtbar gemacht; das ist der Grund, warum er
    da ist.
    """
    last_index = 365 if _leap(year) else 364
    return span[0], min(span[1], last_index)


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

    sources = ampel_basis.DATASETS[DATASET]
    series = []
    for start in range(0, len(points), 100):
        chunk = points[start:start + 100]
        # **Ein Ort, mehrere Modelle, EINE Reihe.** Kein Modell liefert
        # alle Variablen (ERA5-Land hat keinen Niederschlag, ERA5 keine
        # Schneehöhe), also wird je Modell einmal gefragt und das
        # Ergebnis feldweise zusammengelegt. Die Zuordnung Feld → Modell
        # steht in `ampel_basis.DATASETS` und ist dort eindeutig; ein
        # Selbsttest verbietet, dass zwei Modelle dasselbe Feld füllen.
        merged = [{"first": first_day} for _ in chunk]
        for model, mapping in sources:
            params = ampel_basis.weather_params(
                model, mapping, chunk,
                _date_from_index(year, first_day),
                _date_from_index(year, last_day))
            answer = _get(OPEN_METEO, params, timeout=180)
            if isinstance(answer, dict):
                answer = [answer]
            # **Eine kürzere Antwort wäre ein stiller Versatz.** `zip`
            # würde sie klaglos annehmen, und ab dem fehlenden Ort trüge
            # jede Reihe das Wetter eines anderen Fundorts.
            if len(answer) != len(chunk):
                raise RuntimeError(
                    f"Wetter {year}: {len(answer)} Antworten für "
                    f"{len(chunk)} Orte (Modell {model or 'Vorgabe'})")
            for place, target in zip(answer, merged):
                ampel_basis.merge_place(target, mapping,
                                        place.get("daily", {}))
            if len(sources) > 1:
                time.sleep(_politeness())
        series.extend(merged)
        if progress:
            print(f"    Wetter {year}: {len(series)}/{len(points)} Orte",
                  file=sys.stderr)
        time.sleep(_politeness())
    _cache_write(cache_dir, year, points, series, first_day, last_day)
    return series


def _politeness():
    """Wie lange zwischen zwei Abrufen gewartet wird.

    Gegen den oeffentlichen Dienst zwei Sekunden — er ist kostenlos, hat
    ein Kontingent und gehoert nicht geflutet. Gegen die eigene Instanz
    null: Dort wartet das Werkzeug nur auf sich selbst, und beim gepinnten
    Datensatz sind es zwei Abrufe je Ortsgruppe statt einem. Ueber einen
    Lauf von Stunden ist das der Unterschied zwischen einem Abend und
    einer Nacht.
    """
    host = urllib.parse.urlparse(OPEN_METEO).hostname or ""
    return 0.0 if host in ("127.0.0.1", "localhost", "::1") else 2.0


def _cache_key(year, points, first_day, last_day):
    """Der Dateiname im Cache — er trägt seit Phase 0.1 den Datensatz.

    Die Vorgabe behält ihren alten Namen, damit die 1241 schon geholten
    Dateien weiter gefunden werden; jeder gepinnte Datensatz bekommt
    einen Fingerabdruck und landet in eigenen Dateien. Ein Lauf kann
    damit nicht halb aus dem einen und halb aus dem anderen Instrument
    kommen.
    """
    return ampel_basis.cache_name(DATASET, year, points, first_day, last_day)


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
    # **Eine Lücke macht das Fenster ungültig, nicht nur dünn.**
    # Ohne diese Zeile liest das Modell fehlende Werte als Zahlen:
    # `rain_factor` nimmt `mm or 0.0`, also erfundene Trockenheit, und
    # `temperature_factor` siebt sie aus und liefert bei lauter Lücken
    # 0.0 — das heißt „Temperatur maximal daneben“ und nicht „unbekannt“.
    #
    # Auf der Vorgabe fiel das nie auf, weil sie keine Lücken hat. Der
    # gepinnte Datensatz hat welche: **ERA5-Land ist landgebunden**, eine
    # Fundkoordinate in einer Seezelle bekommt gar keine Temperatur.
    # Gemessen sind es 6 von 8492 Fenstern (0,07 %), alle mit komplett
    # leerer Temperatur — numerisch klein, aber eine erfundene Zahl bleibt
    # eine erfundene Zahl.
    if any(v is None for v in rain) or any(v is None for v in temp):
        return None, None
    return rain, temp


# --- Der Test --------------------------------------------------------------

# Der Vergleichstag liegt so weit weg, dass sich die Wetterfenster NICHT
# überlappen — sonst vergleicht man ein Wetter teilweise mit sich selbst
# — und so nah, dass Jahreszeit und Saisonfaktor gleich bleiben.
#
# **Die Untergrenze war bis 2026-09-12 mit 14 Tagen zu klein**, und der
# Kommentar an dieser Stelle behauptete, die Fenster überlappten „kaum".
# Bei 14 Tagen Abstand teilen sich die beiden 26-Tage-Regenfenster aber
# 12 Tage, also 46 %. Der Betreiber hat es gesehen: „Nur weil keiner da
# war, heißt nicht, dass nicht die gleichen Bedingungen herrschten."
#
# Gemessen kostet die Überlappung Trennschärfe, sie erschleicht sie
# nicht: Auf Paaren mit mindestens 26 Tagen Abstand stieg die AUC des
# Steinpilzes von 0,730 auf 0,762, die des Pfifferlings von 0,572 auf
# 0,602. Überlappende Fenster machen Fund- und Vergleichstag ÄHNLICHER,
# als sie sind — der Test war also zu vorsichtig, nicht zu großzügig.
#
# Der Preis ist gut ein Drittel der Paare. Bei der Herbsttrompete, die
# schon vorher dünn war, ist das die Grenze der Auswertbarkeit; der
# Bericht nennt die Paarzahl je Art, damit das sichtbar bleibt.
CONTROL_MIN_GAP = RAIN_WINDOW
CONTROL_MAX_GAP = 45

# **Der Mindestabstand hängt ab Phase 0.3 am geprüften MODELL**, nicht an
# einer festen Zahl: Er ist das längste Fenster dessen, was gerade
# gemessen wird. Für die ausgelieferte Ampel ist das das Regenfenster mit
# 26 Tagen, deshalb ändert sich hier vorerst nichts. Ein Zwei-Phasen-
# Wintermodell mit 28-Tage-Rückblick bräuchte 28, sonst teilen sich Fund-
# und Vergleichstag Tage ihrer Frostdosis.
LONGEST_WINDOW = RAIN_WINDOW

# **Entdoppeln: höchstens eine Meldung je Melder × ~1 km × Tag.** Aus
# ("vorgabe") bleibt jeder frühere Lauf reproduzierbar; für den
# vollständigen Bestand an (Phase 0.2), weil er Exkursions-Cluster
# verstärkt.
DEDUPE = False


def pick_control_day(day_of_year, rng):
    """Wie `ampel_basis.pick_control`, nur ohne das Vorzeichen.

    Bleibt stehen, weil die REIHENFOLGE der Zufallsgriffe an dieser
    Vorschrift hängt: erst `randint`, dann `random`. Wer sie ändert,
    verschiebt die ganze Folge — und damit jede bisher berichtete Zahl.
    """
    day, _gap = ampel_basis.pick_control(
        day_of_year, rng, CONTROL_MIN_GAP, CONTROL_MAX_GAP)
    return day


def _extra_windows(place, day):
    """Die Zusatzreihen eines Tages — nur die, die vollständig sind.

    Ein Feld, das der Datensatz nicht liefert, und eines mit einer Lücke
    im Fenster fehlen hier gleichermaßen. Das ist Absicht: Beides heißt
    „darauf lässt sich nicht rechnen", und eine Unterscheidung an dieser
    Stelle lüde dazu ein, doch zu rechnen.
    """
    out = {}
    for field in EXTRA_FIELDS:
        window = ampel_basis.window_of(place, field, day, SPAN_LOOKBACK)
        if window is not None:
            out[field] = window
    return out


def collect_pairs(name, sci, cache_dir=None, seed=42, progress=True,
                  countries=("DE",), finds=None):
    """Zieht die Paare EINMAL und gibt die rohen Fenster zurück.

    **Warum getrennt vom Bewerten.** Seit der Anpassung je Art
    (`docs/pilzampel-artenfenster.md`) gibt es zwei Abnehmer für dieselben
    Paare: die Validierung mit dem ausgelieferten Optimum und der
    Gitterlauf, der viele Optima durchprobiert. Zwei Schleifen, die
    Vergleichstage ziehen, wären zwei Zufallsfolgen — und damit zwei
    verschiedene Stichproben, deren Zahlen niemand vergleichen darf.
    Hier wird gezogen, dort gerechnet.

    Die Reihenfolge der Zufallsgriffe ist die von vorher (erst der
    Vergleichstag, dann der Placebo-Tag, und zwar VOR dem Verwerfen
    unvollständiger Fenster) — sonst verschöbe sich die ganze Folge und
    alle bisherigen Zahlen wären andere.
    """
    if progress:
        print(f"  {name} ({sci})", file=sys.stderr)
    # **Eine fertige Liste darf hereingereicht werden** — dann gilt sie,
    # wie sie ist. So laufen Design A und Design B auf DERSELBEN
    # Stichprobe; zögen beide für sich, wäre ihr Unterschied teils die
    # Stichprobe statt das Design. Ohne das Argument ändert sich nichts.
    vorgegeben = finds is not None
    if not vorgegeben:
        finds = fetch_finds(sci, progress=progress, cache_dir=cache_dir,
                            countries=countries)
    if not finds:
        return None

    total_available = len(finds)
    # **Entdoppeln VOR dem Stichprobenziehen.** Andersherum zöge man aus
    # einem von Clustern aufgeblähten Topf: Eine Exkursion mit zwanzig
    # Fotos hätte zwanzigfache Chance, in die 2000 zu kommen, und die
    # Stichprobe bestünde am Ende überproportional aus Serien.
    deduped = 0
    if DEDUPE and not vorgegeben:
        finds, deduped = ampel_basis.dedupe_finds(finds)
        if progress:
            print(f"    entdoppelt: {deduped} von {total_available} "
                  f"Meldungen fallen weg ({len(finds)} bleiben)",
                  file=sys.stderr)
    if len(finds) > SAMPLE_PER_SPECIES and not vorgegeben:
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
    samples = []
    skipped = 0
    incomplete_extra = 0
    lost_years = []
    partial_years = []
    for year in sorted(by_year):
        if year > LAST_COMPLETE_YEAR:
            # Kein Ausfall, sondern Absicht — und deshalb auch kein
            # Abbruch: Die Saison läuft noch. Gezählt wird es trotzdem,
            # und der Bericht nennt es; ein stilles Weglassen wäre genau
            # das, was `lost_years` verhindern soll.
            partial_years.append(year)
            if progress:
                print(f"    Jahr {year} ausgelassen: Saison läuft noch "
                      f"({len(by_year[year])} Funde)", file=sys.stderr)
            continue
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
            control_day, control_gap = ampel_basis.pick_control(
                found_day, rng, CONTROL_MIN_GAP, CONTROL_MAX_GAP)
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
            # **Die abstandsgleiche Kontrolle** (2026-09-12): der
            # Vergleichstag, am Fundtag gespiegelt. Beide liegen dann
            # GENAU gleich weit weg, nur auf verschiedenen Seiten.
            #
            # Warum es sie braucht: Der Placebo-Tag oben wird vom
            # VERGLEICHSTAG aus gezogen, seine Abstände addieren sich also
            # (Ø 34 statt 30 Tage). Und Nähe zum Fundtag hebt den Wert —
            # gemessen am Pfifferling: Wo der Placebo-Tag ferner liegt,
            # steht die Kontrolle bei 0,585, wo er näher liegt, bei 0,432.
            # In Deutschland heben sich beide Hälften fast auf (0,512), in
            # den Alpen nicht mehr (0,550), weil der Jahresgang dort
            # schärfer ist.
            #
            # Die gespiegelte Kontrolle hat dieses Problem nicht. Sie
            # ersetzt die alte NICHT: Jene fängt eine einseitige Ziehung,
            # diese kann es bauartbedingt nicht.
            mirror_day = 2 * found_day - control_day
            a_rain, a_temp = window_before(place, found_day, RAIN_WINDOW)
            b_rain, b_temp = window_before(place, control_day, RAIN_WINDOW)
            c_rain, c_temp = window_before(place, placebo_day, RAIN_WINDOW)
            m_rain, m_temp = window_before(place, mirror_day, RAIN_WINDOW)
            if a_rain is None or b_rain is None:
                skipped += 1
                continue
            extra_found = _extra_windows(place, found_day)
            extra_control = _extra_windows(place, control_day)
            # **Ein Paar mit halben Zusatzreihen wird NICHT verworfen**,
            # sondern gezählt. Die ausgelieferte Ampel braucht sie nicht;
            # ein Paar wegen einer Lücke in der Bodenfeuchte zu streichen
            # würde den Referenzlauf verfälschen, um einer späteren
            # Hypothese zu dienen. Wer die Felder braucht, sieht an dieser
            # Zahl, wieviel ihm fehlt.
            if (len(extra_found) < len(EXTRA_FIELDS)
                    or len(extra_control) < len(EXTRA_FIELDS)):
                incomplete_extra += 1
            samples.append({
                "year": year,
                "found": (a_rain, a_temp),
                "control": (b_rain, b_temp),
                "placebo": (c_rain, c_temp) if c_rain is not None else None,
                # Die Abstände zum Fundtag — mitgeführt seit 2026-09-12,
                # weil die Placebo-Kontrolle im Ausland ausschlug und man
                # ohne sie nicht messen kann, WARUM.
                "mirror": (m_rain, m_temp) if m_rain is not None else None,
                "d_control": abs(control_day - found_day),
                "d_placebo": abs(placebo_day - found_day),
                # **Mit Vorzeichen** seit Phase 0.2: Der Richtungs-Split
                # aus 1.1 ist ohne die Seite nicht messbar. Eine Reaktion
                # auf das NIVEAU gibt vor und nach dem Fund ähnliche
                # Werte, eine Reaktion auf ABKÜHLUNG nicht. Der Betrag
                # oben bleibt stehen, weil die Kontrollen ihn lesen.
                "gap_control": control_gap,
                # Woher die Meldung stammt — für das Melder-Bootstrap
                # (1.4) und den Länder-Hold-out. Kein Wetter, nur Herkunft.
                "recordedBy": find.get("recordedBy"),
                "country": find.get("countryCode"),
                # Die zusätzlichen Wetterreihen des gepinnten Datensatzes.
                # Leer, solange auf der Vorgabe gemessen wird — dort gibt
                # es sie nicht, und ein leeres dict ist ehrlicher als
                # Felder voller None.
                "extra": extra_found,
                "extra_control": extra_control,
            })

    if progress and (skipped or incomplete_extra):
        # **Verworfenes gehört gezählt und genannt.** Zwei verschiedene
        # Gründe, und sie dürfen nicht verwechselt werden:
        #   * `skipped` heißt, dass Fund- oder Vergleichstag kein
        #     vollständiges Fenster hatten — das Paar gibt es nicht.
        #     Unter dem gepinnten Datensatz kommt ein neuer Fall dazu:
        #     ERA5-Land ist LANDGEBUNDEN und liefert über See gar nichts,
        #     eine Fundkoordinate in einer Seezelle hat also keine
        #     Temperatur (gemessen: 9 von 15 865 Ortsreihen, 0,06 %).
        #   * `incomplete_extra` heißt, dass das Paar steht, aber eine
        #     Zusatzreihe fehlt. Phase 2 sieht daran, wieviel ihr fehlt.
        print(f"    verworfen: {skipped} Paare ohne vollständiges Fenster"
              + (f", {incomplete_extra} ohne vollständige Zusatzreihen"
                 if incomplete_extra else ""), file=sys.stderr)
    if not samples:
        return None
    if lost_years:
        raise SystemExit(
            f"\n{name}: {len(lost_years)} von {len(by_year)} Jahren fehlen "
            f"({', '.join(str(y) for y in lost_years)}).\n"
            f"Ein Ergebnis auf lückenhaften Jahren wäre nicht auswertbar — "
            f"Pilzjahre unterscheiden sich um den Faktor 10. Lauf mit "
            f"--cache wiederholen, dann sind die geholten Jahre schon da.")
    return {
        "name": name,
        "sci": sci,
        "samples": samples,
        "skipped": skipped,
        # Die WIRKLICH ausgewerteten Jahre, nicht die vorhandenen: Die
        # laufende Saison ist oben absichtlich herausgefallen, und eine
        # Jahreszahl, die sie mitzählt, wäre eine falsche Angabe.
        "years": len(by_year) - len(partial_years),
        "partial_years": partial_years,
        "dataset": DATASET,
        "deduped": deduped,
        "available": total_available,
        "incomplete_extra": incomplete_extra,
    }


def select_finds(sci, cache_dir=None, seed=42, progress=True,
                 countries=("DE",)):
    """Die Fundliste — entdoppelt und auf die Stichprobe gezogen.

    **Herausgelöst, damit Design A und Design B auf DERSELBEN Liste
    laufen.** Zögen beide für sich, wäre ihr Unterschied teils die
    Stichprobe statt das Design — und genau das soll Phase 1.5 messen.

    Die Reihenfolge der Griffe ist die von `collect_pairs`: erst
    entdoppeln, dann `random.Random(seed).sample`. Wer sie ändert,
    verschiebt jede bisher berichtete Zahl.
    """
    finds = fetch_finds(sci, progress=progress, cache_dir=cache_dir,
                        countries=countries)
    if not finds:
        return None, {}
    total = len(finds)
    deduped = 0
    if DEDUPE:
        finds, deduped = ampel_basis.dedupe_finds(finds)
        if progress:
            print(f"    entdoppelt: {deduped} von {total} Meldungen fallen "
                  f"weg ({len(finds)} bleiben)", file=sys.stderr)
    if len(finds) > SAMPLE_PER_SPECIES:
        finds = random.Random(seed).sample(finds, SAMPLE_PER_SPECIES)
        if progress:
            print(f"    Stichprobe: {SAMPLE_PER_SPECIES} von {total}",
                  file=sys.stderr)
    return finds, {"available": total, "deduped": deduped}


def collect_pairs_b(name, sci, finds=None, cache_dir=None, seed=42,
                    progress=True, countries=("DE",),
                    control_count=None):
    """Design B: gleicher Ort, gleiches Kalenderfenster, ANDERES Jahr.

    Design A vergleicht den Fundtag mit einem Tag 26–45 Tage daneben im
    selben Jahr. Das kürzt die Saison nur ungefähr heraus — bei Arten,
    deren Fruchtzeit auf einem steilen Stück des Jahresgangs liegt, misst
    die AUC dann zu einem großen Teil den Kalender (Phase 1.1).

    Design B fragt stattdessen: **War das Wetter in diesem Jahr an diesem
    Datum besser als an diesem Datum üblich?** Die Saison kürzt sich
    vollständig heraus, und übrig bleibt genau der Zusatznutzen, den die
    Ampel neben der ohnehin angezeigten Saisonkurve haben soll.

    Vier Dinge, die man wissen muss:

    - **Die Seiten wechseln sich ab**, beginnend mit einer gewürfelten.
      Ein Münzwurf je Zug wäre im Erwartungswert ausgeglichen und im
      Einzelfall nicht — und diese Unwucht ist es, die in Design A die
      Spiegel-Kontrolle stört (A5). Wo eine Seite leer ist (Funde von
      2006 oder 2025), wird die andere genommen und es wird GEZÄHLT.
    - **Fünf Kontrolljahre statt einem.** Das Wetter liegt nach dem
      ersten Lauf ohnehin im Cache, und der Mittelwert über fünf Jahre
      hängt viel weniger am Seed. Der Wert je Fund ist der Anteil der
      Kontrolljahre, die der Fundtag schlägt; für ein einziges
      Kontrolljahr ist das genau der Beitrag eines Paares zur gepaarten
      AUC, die Größe bleibt also mit A vergleichbar. `k = 1` wird
      zusätzlich mitgerechnet.
    - **Der Kontrolltag streut ±7 Tage, je Kontrolljahr neu gezogen.**
      Ohne Streuung träfe die Ziehung in jedem Jahr denselben
      Wochentag-Rhythmus und dieselbe Meldeportal-Kampagne.
    - **Ein fehlendes Jahr bricht nicht ab**, anders als in Design A. Es
      verkleinert den Kandidatenkreis, wird gezählt und berichtet; erst
      wenn ein Fund gar kein brauchbares Jahr hat, entsteht kein Wert.

    **Was B NICHT kann:** Ein Kontrolljahr kann am selben Ort zur selben
    Woche sehr wohl einen Fund getragen haben — Presence-only trennt
    „kein Fund" nicht von „niemand war da". Solche Jahre auszuschließen
    wäre genau der Detektionsfehler, den die Daten nicht hergeben. „Üblich"
    schließt also die guten Jahre ein, und das dämpft die Zahl zusätzlich.
    """
    if control_count is None:
        control_count = ampel_basis.CONTROL_YEARS
    if finds is None:
        finds, _ = select_finds(sci, cache_dir, seed, progress, countries)
    if not finds:
        return None

    by_year = {}
    for find in finds:
        by_year.setdefault(find["year"], []).append(find)

    rng = random.Random(seed)
    samples = []
    fehlende_jahre = {}
    ausgewichen = 0
    ohne_jahr = 0
    skipped = 0
    partial_years = []

    for year in sorted(by_year):
        if year > LAST_COMPLETE_YEAR:
            partial_years.append(year)
            continue
        group = by_year[year]
        points = [(f["lat"], f["lon"]) for f in group]
        span = season_span(
            [day_index(year, f["month"], f["day"]) for f in group], year=year)

        # **Derselbe Zeitraum und dieselben Punkte in allen Jahren.** Der
        # Vorlauf von `season_span` (45 + 28 Tage) deckt ±7 Tage plus den
        # 28-Tage-Rückblick mit Abstand; damit ist der Cache-Schlüssel
        # (Jahr, gleiche Punkte, gleicher Zeitraum) und über die
        # Kontrolljahre hinweg wiederverwendbar.
        reihen = {}
        kandidaten = [y for y in range(year - ampel_basis.YEAR_SPAN,
                                       year + ampel_basis.YEAR_SPAN + 1)
                      if FIRST_YEAR <= y <= LAST_COMPLETE_YEAR]
        for other in kandidaten:
            try:
                reihen[other] = fetch_weather(points, other, cache_dir,
                                              progress=False,
                                              span=clamp_span(span, other))
            except Exception as error:  # noqa: BLE001
                fehlende_jahre.setdefault(other, 0)
                fehlende_jahre[other] += 1
                if progress:
                    print(f"    Kontrolljahr {other} fehlt: {error}",
                          file=sys.stderr)
        if year not in reihen:
            continue
        brauchbar = sorted(y for y in reihen if y != year)
        if progress:
            print(f"    {year}: {len(group)} Funde, {len(brauchbar)} "
                  f"Kontrolljahre", file=sys.stderr)

        for index, find in enumerate(group):
            found_day = day_index(year, find["month"], find["day"])
            a_rain, a_temp = window_before(reihen[year][index], found_day,
                                           RAIN_WINDOW)
            if a_rain is None:
                skipped += 1
                continue
            jahre, aus = ampel_basis.pick_control_years(
                year, rng, control_count, FIRST_YEAR, LAST_COMPLETE_YEAR,
                used=[y for y in kandidaten if y not in brauchbar])
            ausgewichen += aus
            controls, control_years, extra_controls = [], [], []
            for other in jahre:
                tag = found_day + rng.randint(-ampel_basis.DAY_JITTER,
                                              ampel_basis.DAY_JITTER)
                b_rain, b_temp = window_before(reihen[other][index], tag,
                                               RAIN_WINDOW)
                if b_rain is None:
                    continue
                controls.append((b_rain, b_temp))
                control_years.append(other)
                extra_controls.append(_extra_windows(reihen[other][index], tag))
            if not controls:
                ohne_jahr += 1
                continue
            # **Das Placebo zieht nach DERSELBEN Regel.** Ein Nicht-Fundjahr
            # spielt den Fundtag, die übrigen sind seine Kontrollen. Zöge
            # es anders, prüfte es eine andere Ziehung als die, die oben
            # gelaufen ist.
            placebo_found = placebo_controls = None
            if len(control_years) >= 2:
                anker_jahr = control_years[0]
                tag = found_day + rng.randint(-ampel_basis.DAY_JITTER,
                                              ampel_basis.DAY_JITTER)
                p_rain, p_temp = window_before(reihen[anker_jahr][index], tag,
                                               RAIN_WINDOW)
                if p_rain is not None:
                    placebo_found = (p_rain, p_temp)
                    placebo_controls = controls[1:]
            samples.append({
                "year": year,
                "found": (a_rain, a_temp),
                "controls": controls,
                "control_years": control_years,
                "placebo_found": placebo_found,
                "placebo_controls": placebo_controls,
                "recordedBy": find.get("recordedBy"),
                "country": find.get("countryCode"),
                "extra": _extra_windows(reihen[year][index], found_day),
                "extra_controls": extra_controls,
            })

    if not samples:
        return None
    if progress:
        print(f"    Design B: {len(samples)} Funde, "
              f"{sum(len(s['controls']) for s in samples)} Vergleiche, "
              f"{ausgewichen} mal die Seite gewechselt, {ohne_jahr} Funde "
              f"ohne brauchbares Jahr, {skipped} ohne Fenster",
              file=sys.stderr)
    return {
        "name": name, "sci": sci, "samples": samples,
        "design": "B", "control_count": control_count,
        "ausgewichen": ausgewichen, "ohne_jahr": ohne_jahr,
        "skipped": skipped, "fehlende_jahre": fehlende_jahre,
        "years": len({s["year"] for s in samples}),
        "partial_years": partial_years,
        "dataset": DATASET,
    }


def score_b(samples, optimum=OPTIMUM_C, limit=None, side=None):
    """Das Maß von Design B — Mittel der geschlagenen Anteile.

    `limit` schneidet auf die ersten `limit` Kontrolljahre (für k = 1 zum
    Vergleich mit A), `side` auf „früher" oder „später" (Richtungs-Split).
    """
    anteile = []
    for s in samples:
        paare = list(zip(s["control_years"], s["controls"]))
        if side == "frueher":
            paare = [p for p in paare if p[0] < s["year"]]
        elif side == "spaeter":
            paare = [p for p in paare if p[0] > s["year"]]
        if limit is not None:
            paare = paare[:limit]
        if not paare:
            continue
        anteile.append(ampel_basis.beat_fraction(
            ampel_score(*s["found"], optimum),
            [ampel_score(*c, optimum) for _, c in paare]))
    return ampel_basis.mean_beat(anteile), len(anteile)


def placebo_b(samples, optimum=OPTIMUM_C):
    """Zwei Nicht-Fundjahre gegeneinander — MUSS 0,5 sein."""
    anteile = []
    for s in samples:
        if not s.get("placebo_found") or not s.get("placebo_controls"):
            continue
        anteile.append(ampel_basis.beat_fraction(
            ampel_score(*s["placebo_found"], optimum),
            [ampel_score(*c, optimum) for c in s["placebo_controls"]]))
    return ampel_basis.mean_beat(anteile), len(anteile)


def score_pairs(samples, optimum=OPTIMUM_C):
    """Die gezogenen Paare mit EINEM Optimum bewerten."""
    return [(ampel_score(*s["found"], optimum),
             ampel_score(*s["control"], optimum)) for s in samples]


def validate_species(name, sci, cache_dir=None, seed=42, progress=True):
    """Rechnet für eine Art Fundtage gegen Vergleichstage."""
    drawn = collect_pairs(name, sci, cache_dir=cache_dir, seed=seed,
                          progress=progress)
    if drawn is None:
        return None
    samples = drawn["samples"]
    pairs = score_pairs(samples)
    placebo = [(ampel_score(*s["control"]), ampel_score(*s["placebo"]))
               for s in samples if s["placebo"] is not None]
    mirrored = [(ampel_score(*s["control"]), ampel_score(*s["mirror"]))
                for s in samples if s["mirror"] is not None]
    auc = paired_auc(pairs)
    return {
        "name": name,
        "sci": sci,
        "n": len(pairs),
        "years": drawn["years"],
        "partial_years": drawn["partial_years"],
        "skipped": drawn["skipped"],
        "auc": auc,
        "p": permutation_p(pairs, seed=seed),
        "placebo_auc": paired_auc(placebo),
        "placebo_n": len(placebo),
        "mirror_auc": paired_auc(mirrored),
        "mirror_n": len(mirrored),
        "median_found": statistics.median(p[0] for p in pairs),
        "median_control": statistics.median(p[1] for p in pairs),
    }


# --- Was der Nutzer sieht: die drei Stufen ---------------------------------
#
# **Spiegel von `ampel_model.dart`**, wie der Rest dieser Datei. Die
# Schwellen sind dort ausdrücklich GESETZT und nicht gemessen — und bis
# 2026-09-12 kannte dieses Werkzeug sie überhaupt nicht.
#
# Das ist die Lücke, die der Vergleich schließt: Die AUC misst eine
# RANGFOLGE („stand die Ampel am Fundtag höher als am Vergleichstag"),
# die App zeigt aber drei STUFEN. Ein Modell kann die Rangfolge
# verbessern, ohne dass ein einziger Nutzer je eine andere Farbe sieht —
# und umgekehrt kann ein verschobenes Optimum die Verteilung so
# verschieben, dass dieselben Schwellen etwas anderes bedeuten.
VERHALTEN_ABOVE = 0.2
GUENSTIG_ABOVE = 0.5

LEVELS = ("ungünstig", "verhalten", "günstig")


def ampel_level(score):
    """0 = ungünstig, 1 = verhalten, 2 = günstig."""
    if score >= GUENSTIG_ABOVE:
        return 2
    if score >= VERHALTEN_ABOVE:
        return 1
    return 0


def compare_species(name, sci, cache_dir=None, seed=42, progress=True):
    """Ausgelieferte Ampel gegen die mit eigenem Fenster — in STUFEN."""
    drawn = collect_pairs(name, sci, cache_dir=cache_dir, seed=seed,
                          progress=progress)
    if drawn is None:
        return None
    fit, test = split_by_year(drawn["samples"])
    if not fit or not test:
        return {"name": name, "usable": False}
    optimum = grid_optimum(fit)["optimum"]

    def levels(kind, opt):
        return [ampel_level(ampel_score(*s[kind], opt)) for s in test]

    found_old, found_new = levels("found", OPTIMUM_C), levels("found", optimum)
    ctrl_old, ctrl_new = levels("control", OPTIMUM_C), levels("control", optimum)
    all_old = found_old + ctrl_old
    all_new = found_new + ctrl_new
    differ = sum(1 for a, b in zip(all_old, all_new) if a != b)

    def share(values, at_least):
        return sum(1 for v in values if v >= at_least) / len(values)

    # **Ohne Vertrauensbereich ist ein Abstand von Prozentpunkten eine
    # Behauptung.** Gezogen wird über JAHRE, wie überall hier: Funde
    # desselben Jahres sind einander ähnlicher als Funde verschiedener
    # Jahre. Und beide Modelle werden auf DERSELBEN Ziehung gerechnet,
    # sonst ist ihre Differenz nicht gepaart.
    def gap_ci(at_least, rounds=FIT_BOOTSTRAP_ROUNDS):
        by_year = {}
        for sample in test:
            by_year.setdefault(sample["year"], []).append(sample)
        years = sorted(by_year)
        if len(years) < 2:
            return None
        rng = random.Random(seed)
        deltas = []
        for _ in range(rounds):
            pool = [s for y in (rng.choice(years) for _ in years)
                    for s in by_year[y]]
            def gap(opt):
                f = [ampel_level(ampel_score(*s["found"], opt)) for s in pool]
                c = [ampel_level(ampel_score(*s["control"], opt))
                     for s in pool]
                return share(f, at_least) - share(c, at_least)
            deltas.append(gap(optimum) - gap(OPTIMUM_C))
        deltas.sort()
        return (deltas[int(0.025 * len(deltas))],
                deltas[min(len(deltas) - 1, int(0.975 * len(deltas)))])

    return {
        "name": name,
        "usable": True,
        "optimum": optimum,
        "n_days": len(all_old),
        # Der Anteil der Tage, an denen die Nutzerin eine ANDERE Stufe
        # sähe. Das ist die Zahl, die über eine Umstellung entscheidet —
        # nicht die AUC.
        "differ": differ / len(all_old),
        "guenstig_found_old": share(found_old, 2),
        "guenstig_found_new": share(found_new, 2),
        "guenstig_ctrl_old": share(ctrl_old, 2),
        "guenstig_ctrl_new": share(ctrl_new, 2),
        "verhalten_found_old": share(found_old, 1),
        "verhalten_found_new": share(found_new, 1),
        "verhalten_ctrl_old": share(ctrl_old, 1),
        "verhalten_ctrl_new": share(ctrl_new, 1),
        "gap_ci_guenstig": gap_ci(2),
        "gap_ci_verhalten": gap_ci(1),
    }


def render_compare_report(rows, fetched_on):
    out = ["# Ampel-Vergleich: Stufen statt Rangfolge", "",
           f"Stand: {fetched_on} · Erzeugt von `tool/ampel_validate.py "
           "--compare` · Messung: `docs/pilzampel-artenfenster-messung.md`",
           "",
           "Die Rückwärtsvalidierung misst eine **Rangfolge** (AUC). Die App "
           "zeigt **drei Stufen**, und wo sie liegen, entscheiden zwei "
           f"gesetzte Zahlen: ab {VERHALTEN_ABOVE} „verhalten\", ab "
           f"{GUENSTIG_ABOVE} „günstig\". Diese Seite fragt deshalb das, "
           "was die AUC nicht beantwortet: **Sähe jemand überhaupt etwas "
           "anderes?**", "",
           "Gerechnet auf den Prüfjahren (ab "
           f"{FIT_UNTIL_YEAR + 1}), je Art auf Fund- UND Vergleichstagen.",
           "",
           "## Wie oft die Stufe wechselt", "",
           "| Art | Optimum | Tage | andere Stufe |",
           "|---|--:|--:|--:|"]
    for row in rows:
        if not row.get("usable"):
            out.append(f"| {row['name']} | — | — | zu wenig Material |")
            continue
        out.append(f"| {row['name']} | {row['optimum']:.1f} °C | "
                   f"{row['n_days']} | **{row['differ'] * 100:.1f} %** |")

    out += ["", "## Trennt die neue Stufe besser?", "",
            "„Günstig\" soll an Fundtagen häufiger stehen als an "
            "Vergleichstagen. Der **Abstand** dieser beiden Anteile ist, "
            "was die Stufe wert ist.", "",
            "| Art | günstig an Fundtagen | an Vergleichstagen | Abstand | "
            "Gewinn (95 %) |",
            "|---|--:|--:|--:|--:|"]
    for row in rows:
        if not row.get("usable"):
            continue
        gap_old = row["guenstig_found_old"] - row["guenstig_ctrl_old"]
        gap_new = row["guenstig_found_new"] - row["guenstig_ctrl_new"]
        span = row.get("gap_ci_guenstig")
        ci = (f" [{span[0] * 100:+.1f}, {span[1] * 100:+.1f}]"
              if span else "")
        out.append(
            f"| {row['name']} | {row['guenstig_found_old'] * 100:.1f} → "
            f"**{row['guenstig_found_new'] * 100:.1f} %** | "
            f"{row['guenstig_ctrl_old'] * 100:.1f} → "
            f"**{row['guenstig_ctrl_new'] * 100:.1f} %** | "
            f"{gap_old * 100:+.1f} → **{gap_new * 100:+.1f} pp** | "
            f"{(gap_new - gap_old) * 100:+.1f}{ci} |")

    out += ["", "## Und dasselbe für „mindestens verhalten\"", "",
            "| Art | an Fundtagen | an Vergleichstagen | Abstand | "
            "Gewinn (95 %) |",
            "|---|--:|--:|--:|--:|"]
    for row in rows:
        if not row.get("usable"):
            continue
        gap_old = row["verhalten_found_old"] - row["verhalten_ctrl_old"]
        gap_new = row["verhalten_found_new"] - row["verhalten_ctrl_new"]
        span = row.get("gap_ci_verhalten")
        ci = (f" [{span[0] * 100:+.1f}, {span[1] * 100:+.1f}]"
              if span else "")
        out.append(
            f"| {row['name']} | {row['verhalten_found_old'] * 100:.1f} → "
            f"**{row['verhalten_found_new'] * 100:.1f} %** | "
            f"{row['verhalten_ctrl_old'] * 100:.1f} → "
            f"**{row['verhalten_ctrl_new'] * 100:.1f} %** | "
            f"{gap_old * 100:+.1f} → **{gap_new * 100:+.1f} pp** | "
            f"{(gap_new - gap_old) * 100:+.1f}{ci} |")

    # --- Was daraus folgt, aus den Zahlen gerechnet -----------------------
    usable = [r for r in rows if r.get("usable")]

    def gains(row):
        span = row.get("gap_ci_guenstig")
        return bool(span) and span[0] > 0

    winners = [r for r in usable if gains(r)]
    # Wo „günstig" einbricht: Die Stufe verschwindet, statt besser zu
    # treffen. Halbierung als Grenze — darunter redet niemand mehr von
    # derselben Anzeige.
    dark = [r for r in usable
            if r["guenstig_found_old"] > 0
            and r["guenstig_found_new"] < r["guenstig_found_old"] / 2]

    out += ["", "## Was daraus folgt", ""]
    if winners:
        out += ["**Sichtbar besser wird es bei: "
                + ", ".join(f"{r['name']} ({r['optimum']:.1f} °C, "
                            f"{(r['guenstig_found_new'] - r['guenstig_ctrl_new'] - r['guenstig_found_old'] + r['guenstig_ctrl_old']) * 100:+.1f} pp)"
                            for r in winners)
                + ".** Bei allen übrigen enthält der Vertrauensbereich die "
                "Null — ihr eigenes Fenster ändert für die Nutzerin nichts, "
                "auch wenn die AUC sich rührt.", ""]
    else:
        out += ["**Keine Art wird sichtbar besser.** Bei allen enthält der "
                "Vertrauensbereich des Gewinns die Null.", ""]
    if dark:
        out += ["**Und bei "
                + ", ".join(r["name"] for r in dark)
                + " verschwindet „günstig“ fast ganz** ("
                + ", ".join(f"{r['guenstig_found_old'] * 100:.1f} % → "
                            f"{r['guenstig_found_new'] * 100:.1f} % an "
                            f"Fundtagen" for r in dark)
                + ").", "",
                f"Das ist kein Fehler der Anpassung, sondern der Schwellen: "
                f"{VERHALTEN_ABOVE} und {GUENSTIG_ABOVE} sind für eine "
                f"{OPTIMUM_C:.0f}-°C-Glocke gesetzt. Verschiebt man das "
                "Optimum, verschiebt sich die ganze Werteverteilung mit, und "
                "dieselben Zahlen bedeuten etwas anderes. **Ein eigenes "
                "Fenster ohne eigene Schwellen macht die Ampel dunkel, nicht "
                "besser** — und in einer Anzeige „günstig, sobald eine Klasse "
                "günstig steht“ käme eine solche Klasse nie zum Zug.", ""]
    out += ["Die Schwellen sind damit kein Umsetzungsdetail, sondern Teil "
            "des Modells. Sie stehen bis heute als „GESETZT, nicht "
            "gemessen“ in `ampel_model.dart`, und diese Seite ist die "
            "erste Messung, die sie überhaupt anfasst.", ""]
    return "\n".join(out) + "\n"


# --- Die Schwellen: Quantile statt gesetzter Zahlen ------------------------
#
# `docs/pilzampel-schwellen.md` — Stufe 0 der Integration ins App-Modell.
#
# Der Vergleich in Stufen hat gezeigt, dass die beiden gesetzten Zahlen
# der Engpass sind, nicht das Fenster: Der bestätigte AUC-Gewinn des
# Austernseitlings (+0,174) schrumpft in Stufen auf +0,6 pp, weil
# „günstig" an Fundtagen von 21,7 % auf 1,1 % fällt. Eine feste Zahl
# gilt eben für EINE Werteverteilung, und ein verschobenes Optimum
# verschiebt die ganze Verteilung mit.
#
# Die Bezugsgröße ist der VERGLEICHSTAG: ein anderer Tag derselben
# Saison am selben Ort. „Günstig" heißt damit „unter den besten X % der
# Tage dieser Saison an Pilzorten" — für jede Art dasselbe, egal wo ihr
# Optimum liegt. Ohne diese Vergleichbarkeit ist „mindestens eine Klasse
# steht günstig" keine Aussage, sondern eine Wette darauf, welche Klasse
# zufällig nahe an der 13-°C-Skala liegt.

# **Registriert VOR der Messung** (`docs/pilzampel-schwellen.md`): Unter
# dem ausgelieferten Fenster sollen 0,2 und 0,5 ungefähr hier liegen.
# Gerundet wird auf volle 5 % und genau EINMAL — an den sechs Arten, die
# die App heute ausliefert; keine Art aus Vorhersage 2 ist beteiligt,
# sonst wäre die Schwelle auf ihr Ergebnis hin gewählt.
# **Gesetzt am 2026-09-12 aus der Messung**, auf volle 5 % gerundet:
# Der Median der sechs Mykorrhiza-Arten lag bei 39,7 % und 69,7 %.
# Erwartet worden waren 50 % und 80 % — die Vorhersage ist damit NICHT
# bestätigt, und der Grund steht im Bericht: Das registrierte Band war
# aus Zahlen der PRÜFJAHRE abgeleitet, gemessen wird auf den
# Anpassjahren, und zwischen beiden Zeitscheiben liegt eine Drift von
# rund 8 Prozentpunkten in dieselbe Richtung bei allen sechs Arten.
QUANTILE_VERHALTEN = 0.40
QUANTILE_GUENSTIG = 0.70

# Die Bänder aus der Registrierung. Liegt der Median der sechs
# Mykorrhiza-Arten darin, ist die Quantil-Fassung eine Umformulierung
# der heutigen App — und keine neue Entscheidung über ihre Häufigkeit.
QUANTILE_BAND_VERHALTEN = (0.45, 0.55)
QUANTILE_BAND_GUENSTIG = (0.75, 0.85)

# Vorhersage 2, ebenfalls vorab: Waren die Schwellen die Ursache, muss
# der Abstand beim Austernseitling mit ihnen erscheinen.
# **Gemessen am 2026-09-12, Betreiberentscheidung „gleich häufig
# vorerst".** Der Median der sechs ausgelieferten Arten auf den
# Prüfjahren, auf volle 5 % gerundet. Sie stehen als Konstante da, damit
# die Vertrauensbereiche der Schwellen an ihnen hängen können — und
# `deployment_quantiles` rechnet sie bei jedem Lauf nach: Wandert die
# Verteilung, meldet sich das Werkzeug, statt eine veraltete Zahl
# weiterzureichen.
SHIP_QUANTILE_VERHALTEN = 0.50
SHIP_QUANTILE_GUENSTIG = 0.80

THRESHOLD_PREDICTION_SPECIES = "Austernseitling"
THRESHOLD_PREDICTION_MIN_GAP = 0.10


def level_with(score, verhalten, guenstig):
    """Wie [ampel_level], aber mit frei gesetzten Schwellen.

    `ampel_level` bleibt bewusst OHNE Parameter der Spiegel der App:
    Die Spiegel-Prüfung liest die beiden Konstanten aus dem Dart-Code,
    und eine Funktion mit Vorgabewerten lüde dazu ein, die Vorgabe für
    „das, was die App tut" zu halten.
    """
    if score >= guenstig:
        return 2
    if score >= verhalten:
        return 1
    return 0


def control_scores(samples, optimum, balanced=False):
    """Die Score-Verteilung an VERGLEICHSTAGEN, mit Gewichten.

    [balanced] gibt jedem JAHR dasselbe Gewicht. Ohne das erbt die
    Verteilung den Melde-Eifer: Ein gutes Pilzjahr liefert mehr Funde,
    damit mehr Vergleichstage, und zieht die Schwelle zu sich hin. Beide
    Fassungen stehen im Bericht — ob der Unterschied zählt, ist eine
    Zahl und keine Meinung.
    """
    values = [ampel_score(*s["control"], optimum) for s in samples]
    if not balanced:
        return values, [1.0] * len(values)
    counts = {}
    for sample in samples:
        counts[sample["year"]] = counts.get(sample["year"], 0) + 1
    weights = [1.0 / counts[s["year"]] for s in samples]
    return values, weights


def quantile_at(values, weights, q):
    """Der Wert, unter dem [q] der Gewichtsmasse liegt."""
    if not values:
        return None
    total = sum(weights)
    seen = 0.0
    for value, weight in sorted(zip(values, weights)):
        seen += weight
        if seen >= q * total:
            return value
    return max(values)


def rank_of(values, weights, threshold):
    """Der Anteil der Gewichtsmasse UNTER [threshold].

    Die Umkehrung von [quantile_at] — und die eigentliche Frage von
    Vorhersage 1: Welchem Quantil entspricht die heute ausgelieferte
    Zahl?
    """
    if not values:
        return None
    below = sum(w for v, w in zip(values, weights) if v < threshold)
    return below / sum(weights)


def threshold_species(name, sci, cache_dir=None, seed=42, progress=True):
    """Was die gesetzten Schwellen als Quantil sind — und was
    Quantil-Schwellen in Stufen ändern."""
    drawn = collect_pairs(name, sci, cache_dir=cache_dir, seed=seed,
                          progress=progress)
    if drawn is None:
        return None
    fit, test = split_by_year(drawn["samples"])
    if not fit or not test:
        return {"name": name, "usable": False}
    optimum = grid_optimum(fit)["optimum"]

    # **Vorhersage 1 wird unter dem AUSGELIEFERTEN Fenster gemessen.**
    # Die Frage lautet, was die App heute tut — nicht, was sie mit einem
    # neuen Fenster täte.
    plain = control_scores(fit, OPTIMUM_C)
    even = control_scores(fit, OPTIMUM_C, balanced=True)
    # Dieselbe Frage auf den PRÜFJAHREN — nicht als zweite Antwort,
    # sondern als Diagnose: Weicht sie ab, hat sich das Wetter unter der
    # festen Zahl verschoben, und die ausgelieferte Schwelle bedeutet
    # heute etwas anderes als zur Zeit ihrer Festlegung.
    later = control_scores(test, OPTIMUM_C, balanced=True)

    # **Die neuen Schwellen entstehen auf den ANPASSJAHREN**, unter dem
    # eigenen Fenster und jahresbalanciert. Sie dort zu setzen, wo sie
    # danach geprüft werden, wäre Selbstbestätigung — dieselbe
    # Trennlinie wie beim Optimum, über dieselbe Funktion.
    own = control_scores(fit, optimum, balanced=True)
    verhalten_at = quantile_at(*own, QUANTILE_VERHALTEN)
    guenstig_at = quantile_at(*own, QUANTILE_GUENSTIG)
    # Dieselbe Verteilung auf den PRÜFJAHREN. Aus ihr entstehen die
    # Zahlen, die ausgeliefert würden — nicht aus den Anpassjahren:
    # Zwischen beiden liegen gut acht Prozentpunkte Drift, und für die
    # Auslieferung zählt, wo die App HEUTE steht.
    own_later = control_scores(test, optimum, balanced=True)

    # **Wie genau ist eine Schwelle überhaupt?** Davon hängt ab, ob jede
    # Art ihre eigene braucht oder ob Arten mit demselben Fenster sich
    # eine teilen können. Überlappen die Bereiche, wäre eine Schwelle je
    # Art ausgeliefertes Rauschen.
    def threshold_ci(q, rounds=FIT_BOOTSTRAP_ROUNDS):
        grouped = {}
        for sample in test:
            grouped.setdefault(sample["year"], []).append(sample)
        present = sorted(grouped)
        if len(present) < 2:
            return None
        rng = random.Random(seed)
        draws = []
        for _ in range(rounds):
            pool = [s for y in (rng.choice(present) for _ in present)
                    for s in grouped[y]]
            draws.append(quantile_at(
                *control_scores(pool, optimum, balanced=True), q))
        draws.sort()
        return (draws[int(0.025 * len(draws))],
                draws[min(len(draws) - 1, int(0.975 * len(draws)))])

    configs = {
        # Was die App heute rechnet.
        "shipped": (OPTIMUM_C, VERHALTEN_ABOVE, GUENSTIG_ABOVE),
        # Nur das Fenster getauscht — der Stand aus `--compare`.
        "window": (optimum, VERHALTEN_ABOVE, GUENSTIG_ABOVE),
        # Fenster UND Schwellen — der Vorschlag.
        "both": (optimum, verhalten_at, guenstig_at),
    }

    def share(samples, kind, config, at_least):
        opt, low, high = config
        levels = [level_with(ampel_score(*s[kind], opt), low, high)
                  for s in samples]
        return sum(1 for v in levels if v >= at_least) / len(levels)

    def gap(samples, config, at_least):
        return (share(samples, "found", config, at_least)
                - share(samples, "control", config, at_least))

    # **Ohne Vertrauensbereich ist ein Abstand eine Behauptung.** Gezogen
    # wird über JAHRE, wie überall hier: Funde desselben Jahres sind
    # einander ähnlicher als Funde verschiedener Jahre.
    by_year = {}
    for sample in test:
        by_year.setdefault(sample["year"], []).append(sample)
    years = sorted(by_year)

    def gap_ci(config, at_least, rounds=FIT_BOOTSTRAP_ROUNDS):
        if len(years) < 2:
            return None
        rng = random.Random(seed)
        draws = []
        for _ in range(rounds):
            pool = [s for y in (rng.choice(years) for _ in years)
                    for s in by_year[y]]
            draws.append(gap(pool, config, at_least))
        draws.sort()
        return (draws[int(0.025 * len(draws))],
                draws[min(len(draws) - 1, int(0.975 * len(draws)))])

    return {
        "name": name,
        "usable": True,
        "optimum": optimum,
        "n_fit": len(fit),
        "n_test": len(test),
        # Vorhersage 1: das Quantil der heute ausgelieferten Zahlen.
        "rank_verhalten": rank_of(*plain, VERHALTEN_ABOVE),
        "rank_guenstig": rank_of(*plain, GUENSTIG_ABOVE),
        "rank_verhalten_even": rank_of(*even, VERHALTEN_ABOVE),
        "rank_guenstig_even": rank_of(*even, GUENSTIG_ABOVE),
        "rank_verhalten_later": rank_of(*later, VERHALTEN_ABOVE),
        "rank_guenstig_later": rank_of(*later, GUENSTIG_ABOVE),
        # Die daraus gesetzten Schwellen dieser Art.
        "verhalten_at": verhalten_at,
        "guenstig_at": guenstig_at,
        "own_later": own_later,
        "klass": class_of(name),
        # Die Vergleichstage der Prüfjahre selbst — die Bewertung unter
        # dem KLASSEN-Fenster kommt später (`attach_class_scores`), denn
        # dieses Fenster entsteht erst aus den Optima ALLER Mitglieder.
        # Sie hier zu rechnen ginge nur mit einer Konstante je Klasse,
        # und genau die hat sich bei den unbestätigten als Einladung zum
        # Raten erwiesen.
        "test_samples": test,
        "ship_verhalten_ci": threshold_ci(SHIP_QUANTILE_VERHALTEN),
        "ship_guenstig_ci": threshold_ci(SHIP_QUANTILE_GUENSTIG),
        # Was die Nutzerin sähe — je Aufbau der Abstand Fund/Vergleich.
        "gap_shipped": gap(test, configs["shipped"], 2),
        "gap_window": gap(test, configs["window"], 2),
        "gap_both": gap(test, configs["both"], 2),
        "gap_both_ci": gap_ci(configs["both"], 2),
        "found_shipped": share(test, "found", configs["shipped"], 2),
        "found_both": share(test, "found", configs["both"], 2),
        "ctrl_shipped": share(test, "control", configs["shipped"], 2),
        "ctrl_both": share(test, "control", configs["both"], 2),
    }


def _pct(value, digits=1):
    """Prozent mit deutschem Komma — `None` bleibt ein Strich."""
    if value is None:
        return "—"
    return f"{value * 100:.{digits}f} %".replace(".", ",")


def _pp(value, digits=1):
    """Prozentpunkte mit Vorzeichen."""
    if value is None:
        return "—"
    return f"{value * 100:+.{digits}f} pp".replace(".", ",")


def deployment_quantiles(rows):
    """Die Quantile, die die HEUTIGE Häufigkeit erhalten.

    **Betreiberentscheidung 2026-09-12: „gleich häufig vorerst".** Die
    Umstellung soll die Treffsicherheit ändern und nicht zugleich, wie
    oft die Ampel überhaupt spricht — beides in einem Schritt machte
    hinterher unauswertbar, was gewirkt hat.

    Genommen wird der Median der sechs ausgelieferten Arten auf den
    **Prüfjahren**, also dort, wo die App heute steht; auf ganze 5 %
    gerundet wie überall hier. Die Anpassjahre wären die falsche
    Referenz: Zwischen beiden liegen gut acht Prozentpunkte Drift, und
    wer dort kalibriert, liefert eine Ampel aus, die um genau diese
    Drift zu großzügig ist.
    """
    shipped = [r for r in rows
               if r.get("usable") and r["name"] in MYCORRHIZAL]
    if not shipped:
        return None

    def rounded(values):
        return round(statistics.median(values) * 20) / 20

    measured = (rounded([r["rank_verhalten_later"] for r in shipped]),
                rounded([r["rank_guenstig_later"] for r in shipped]))
    # **Die Konstanten gegen die Daten, bei jedem Lauf.** Sonst stünden
    # zwei Zahlen im Werkzeug, die einmal aus einer Messung kamen und
    # seither nur noch dastehen — genau die Sorte, die dieses Projekt
    # schon als „GESETZT, nicht gemessen" im Modellkern hatte.
    if measured != (SHIP_QUANTILE_VERHALTEN, SHIP_QUANTILE_GUENSTIG):
        raise SystemExit(
            f"Die Auslieferungs-Quantile haben sich verschoben: gemessen "
            f"{measured}, als Konstante stehen "
            f"({SHIP_QUANTILE_VERHALTEN}, {SHIP_QUANTILE_GUENSTIG}). Die "
            f"Verteilung ist gewandert — Konstanten und Bericht gehören "
            f"zusammen neu gesetzt, nicht einzeln.")
    return measured


def class_optimum(rows, key):
    """Das Fenster einer Klasse: der MEDIAN der Optima ihrer Mitglieder.

    **Jede Art eine Stimme**, nicht jede Beobachtung — dieselbe
    Begründung wie bei den Schwellen. Die Paare aller Mitglieder in
    einen Topf zu werfen und darauf eine AUC zu maximieren klingt
    gründlicher, ließe aber die größte Art das Fenster bestimmen: Der
    Hallimasch bringt 2000 Paare mit, das Stockschwämmchen 1332.

    Der Median ist bei zwei Mitgliedern das Mittel, bei fünf die Mitte —
    und er verträgt einen Ausreißer, was bei drei bis fünf Stimmen das
    Entscheidende ist.
    """
    fitted = [row["optimum"] for row in rows
              if row.get("usable") and row.get("klass") == key]
    return statistics.median(fitted) if fitted else None


def class_windows(rows):
    """Das Fenster je Klasse — Konstante, wo die App eine ausliefert,
    sonst gemessen.

    **Die Reihenfolge ist die Aussage:** Für eine ausgelieferte Klasse
    gilt die Konstante, und `verify_class_constants` prüft sie gegen
    diese Messung. Für eine unbestätigte gilt die Messung selbst — dort
    gibt es nichts auszuliefern, also auch nichts festzuschreiben.
    """
    out = {}
    for key, klass in AMPEL_CLASSES.items():
        measured = class_optimum(rows, key)
        if measured is None:
            continue
        out[key] = {
            "window": klass.get("optimum", measured),
            "measured": measured,
        }
    return out


def attach_class_scores(rows):
    """Bewertet die Vergleichstage jeder Art unter ihrem KLASSEN-Fenster.

    Zweiter Durchgang, und er muss einer sein: Das Fenster einer Klasse
    ist der Median der Optima ihrer Mitglieder — es steht also erst
    fest, wenn alle Arten gerechnet sind.
    """
    windows = class_windows(rows)
    for row in rows:
        key = row.get("klass") if row.get("usable") else None
        samples = row.get("test_samples")
        # `setdefault` statt Zuweisung: Im Selbsttest stehen gepflanzte
        # Bewertungen in den Zeilen und keine Stichproben. Ein blindes
        # Überschreiben machte sie dort lautlos zu `None`, und die
        # Wächter prüften nichts mehr.
        if key is None or key not in windows or samples is None:
            row.setdefault("class_later", None)
            continue
        row["class_later"] = control_scores(
            samples, windows[key]["window"], balanced=True)
    return windows


def class_thresholds(rows, quantiles, verify=True):
    """Die Schwellen je Klasse, aus den Vergleichstagen ALLER Mitglieder.

    **Jede Art zählt gleich viel**, nicht jede Beobachtung. Der Steinpilz
    bringt 2000 Paare mit, die Herbsttrompete 288 — ungewichtet wäre die
    Klassenschwelle die Steinpilzschwelle mit anderem Namen. Dieselbe
    Begründung wie bei der Jahresbalance: Stichprobengröße soll nicht
    für Bedeutung einstehen.
    """
    pooled = {}
    for row in rows:
        if not row.get("usable") or not row.get("klass"):
            continue
        values, weights = row["class_later"]
        if not values:
            continue
        # Auf Gesamtgewicht 1 je Art normieren — erst das macht aus
        # „alle Tage zusammen" wirklich „alle Arten gleich".
        total = sum(weights)
        entry = pooled.setdefault(row["klass"], ([], [], []))
        entry[0].extend(values)
        entry[1].extend(w / total for w in weights)
        entry[2].append(row["name"])
    out = {}
    for key, (values, weights, members) in pooled.items():
        got = {
            "verhalten": quantile_at(values, weights, quantiles[0]),
            "guenstig": quantile_at(values, weights, quantiles[1]),
            "members": members,
            "n": len(values),
            "optimum_measured": class_optimum(rows, key),
        }
        # **Die Konstanten gegen die Daten, bei jedem Lauf** — dieselbe
        # Regel wie bei den Auslieferungs-Quantilen. Diese vier Zahlen
        # gehen in den Modellkern der App; eine, die sich still von ihrer
        # Quelle löst, wäre wieder ein „GESETZT, nicht gemessen".
        # Verglichen wird auf drei Stellen, denn genau so viele stehen
        # auch in Dart.
        out[key] = got
    if verify:
        verify_class_constants(out)
    return out


def verify_class_constants(measured):
    """Konstanten gegen Daten — **alle Abweichungen auf einmal.**

    Bis zum 2026-09-12 brach die Prüfung beim ersten Fund ab. Das ist
    genau der Wächter, den man nach dem zweiten Mal abschaltet: Ein
    geändertes Klassenfenster verschiebt auch die Schwelle darunter, es
    gibt also selten nur EINE Abweichung — und jede kostete einen
    zehnminütigen Lauf, um die nächste zu erfahren.
    """
    findings = []
    for key, got in measured.items():
        klass = AMPEL_CLASSES[key]
        # Ohne Dart-Namen liefert die App die Klasse nicht aus — dann gibt
        # es auch nichts, was auseinanderlaufen könnte.
        if not klass.get("dart"):
            continue
        for field in ("verhalten", "guenstig"):
            expected = klass.get(field)
            if expected is not None and round(got[field], 3) != expected:
                findings.append(
                    f"  {key}.{field}: gemessen {round(got[field], 3)}, "
                    f"Konstante {expected}")
        if "optimum_measured" in got:
            expected = klass["optimum"]
            if abs(got["optimum_measured"] - expected) > 1e-9:
                findings.append(
                    f"  {key}.optimum: gemessen "
                    f"{got['optimum_measured']!r} °C, Konstante "
                    f"{expected!r} °C")
    if not findings:
        return findings
    # **Auf einer anderen Messbasis vergleicht der Wächter Äpfel mit
    # Birnen** (seit 2026-09-17). Die ausgelieferten Konstanten sind auf
    # der Vorgabe gemessen — also auf einem Instrument, das bis 2016
    # ERA5-Land ist und ab 2017 IFS HRES. Auf einem gepinnten Datensatz
    # MÜSSEN sie abweichen; das ist der Befund, nicht der Fehler.
    #
    # Würde hier trotzdem abgebrochen, wäre jede künftige Messung auf
    # einer neuen Basis blockiert — und der Wächter genau das, wovor sein
    # eigener Kommentar warnt: einer, den man nach dem zweiten Mal
    # abschaltet. Er wacht weiter scharf über den Gleichlauf von Werkzeug
    # und `ampel_model.dart`, aber nur dort, wo beide dasselbe messen.
    if DATASET != ampel_basis.DEFAULT_DATASET:
        print("\nKlassen-Konstanten weichen ab — erwartet, denn gemessen "
              f"wird auf '{DATASET}' und die Konstanten stammen von "
              f"'{ampel_basis.DEFAULT_DATASET}':\n"
              + "\n".join(findings)
              + "\n\nDas ist eine Nachmessung, keine Freigabe. Übernommen "
                "wird nichts ohne Betreiberentscheidung.\n",
              file=sys.stderr)
        return findings
    raise SystemExit(
        "Klassen-Konstanten passen nicht zu den Daten:\n"
        + "\n".join(findings)
        + "\n\nKonstante, Bericht UND ampel_model.dart gehören "
          "zusammen neu gesetzt — nicht einzeln.")


def class_table_row(key, klass, got):
    """Eine Zeile der Klassentabelle.

    **Eigene Funktion, damit sie prüfbar ist.** Aus genau dieser Spalte
    ist am 2026-09-12 die 11,6 in die Registrierung gewandert, während
    das Fenster 11,625 war — die Tabelle rundete auf eine Stelle, und
    abgeschrieben wurde, was dastand. Inline war daran nichts zu prüfen.
    """
    window = klass.get("optimum", got.get("optimum_measured"))
    return (f"| {key} | {_optimum_text(window)} °C | "
            f"{got['verhalten']:.3f} | {got['guenstig']:.3f} | "
            f"{', '.join(got['members'])} | "
            f"{'ja' if klass['confirmed'] else '**nein**'} |")


def render_threshold_report(rows, fetched_on):
    usable = [r for r in rows if r.get("usable")]
    mycorrhizal = [r for r in usable if r["name"] in MYCORRHIZAL]
    out = ["# Die Schwellen der Ampel — gemessen", "",
           f"Stand: {fetched_on} · Erzeugt von `tool/ampel_validate.py "
           "--thresholds` · Prüfplan: `docs/pilzampel-schwellen.md`", "",
           "Die App zeigt drei Stufen. Wo sie liegen, entscheiden zwei "
           "Zahlen, die seit der ersten Vorschau als „GESETZT, nicht "
           "gemessen“ in `lib/features/ampel/ampel_model.dart` stehen — "
           "diese Seite ist ihre erste Messung.", ""]

    out += ["## Vorhersage 1: Welchem Quantil entsprechen 0,2 und 0,5?", "",
            "Gemessen an den Vergleichstagen der **Anpassjahre**, unter dem "
            "**ausgelieferten** Fenster (13 °C) — also an dem, was die App "
            "heute rechnet. „Jahresbalanciert“ gibt jedem Jahr dasselbe "
            "Gewicht, damit ein gutes Pilzjahr die Schwelle nicht über "
            "seine Meldemenge zu sich zieht.", "",
            "Die letzte Spalte ist eine **Diagnose, keine zweite "
            "Antwort**: Gemessen wird auf den Anpassjahren, weil diese "
            "Zahlen die Schwellen setzen. Weicht die Prüfjahr-Spalte ab, "
            "bedeutet dieselbe feste Zahl in den beiden Zeitscheiben "
            "etwas Verschiedenes — die Schwelle altert dann mit dem "
            "Wetter, und zwar im ausgelieferten Binary.", "",
            "| Art | 0,2 entspricht | 0,5 entspricht | 0,2 balanciert | "
            "0,5 balanciert | 0,5 auf den Prüfjahren |",
            "|---|--:|--:|--:|--:|--:|"]
    for row in mycorrhizal:
        out.append(f"| {row['name']} | {_pct(row['rank_verhalten'])} | "
                   f"{_pct(row['rank_guenstig'])} | "
                   f"{_pct(row['rank_verhalten_even'])} | "
                   f"{_pct(row['rank_guenstig_even'])} | "
                   f"{_pct(row['rank_guenstig_later'])} |")

    verdict_1 = None
    if mycorrhizal:
        med_v = statistics.median(r["rank_verhalten_even"]
                                  for r in mycorrhizal)
        med_g = statistics.median(r["rank_guenstig_even"] for r in mycorrhizal)
        in_band = (QUANTILE_BAND_VERHALTEN[0] <= med_v
                   <= QUANTILE_BAND_VERHALTEN[1]
                   and QUANTILE_BAND_GUENSTIG[0] <= med_g
                   <= QUANTILE_BAND_GUENSTIG[1])
        verdict_1 = in_band
        out += ["",
                f"**Median über die sechs Mykorrhiza-Arten** "
                f"(jahresbalanciert): 0,2 liegt bei **{_pct(med_v)}**, 0,5 "
                f"bei **{_pct(med_g)}**.", "",
                f"Registriert war: {_pct(QUANTILE_BAND_VERHALTEN[0], 0)}–"
                f"{_pct(QUANTILE_BAND_VERHALTEN[1], 0)} und "
                f"{_pct(QUANTILE_BAND_GUENSTIG[0], 0)}–"
                f"{_pct(QUANTILE_BAND_GUENSTIG[1], 0)}.", ""]
        later_g = statistics.median(r["rank_guenstig_later"]
                                    for r in mycorrhizal)
        drift = statistics.median(r["rank_guenstig_later"]
                                  - r["rank_guenstig_even"]
                                  for r in mycorrhizal)
        same_way = all(r["rank_guenstig_later"] > r["rank_guenstig_even"]
                       for r in mycorrhizal)
        if in_band:
            out.append(
                "**Ergebnis: bestätigt.** Die Quantil-Fassung ist damit "
                "keine Umdeutung, sondern dieselbe Aussage in "
                "übertragbarer Form — für die heute ausgelieferten Arten "
                "ändert sie fast nichts, für jedes andere Fenster stellt "
                "sie überhaupt erst eine Bedeutung her.")
        else:
            out.append(
                "**Ergebnis: NICHT bestätigt.** Der Median liegt unter "
                "dem registrierten Band.")
            out += ["",
                    f"Auf den **Prüfjahren** liegt er dagegen bei "
                    f"**{_pct(later_g)}** — und daher kam die Erwartung: "
                    "Sie war aus dem Stufenvergleich abgeleitet, und der "
                    "rechnet auf Prüfjahren. Zwischen den beiden "
                    f"Zeitscheiben liegen im Median **{_pp(drift)}**"
                    + (", bei allen sechs Arten in dieselbe Richtung."
                       if same_way else ", uneinheitlich in der Richtung.")]
            out += ["",
                    "Damit ist die eigentliche Auskunft dieser Tabelle "
                    "nicht das Quantil, sondern: **Dieselbe feste Zahl "
                    "bedeutet in den beiden Hälften der Daten etwas "
                    "Verschiedenes.** Die ausgelieferte 0,5 ist heute "
                    "eine strengere Schwelle als zur Zeit ihrer "
                    "Festlegung — ohne dass je eine Zeile Code geändert "
                    "wurde. Ob dahinter das Wetter steckt oder eine "
                    "gewachsene GBIF-Stichprobe, trennt diese Messung "
                    "nicht; für die App ist die Folge dieselbe.",
                    "",
                    "Und für die Quantile heißt es: Sie sind hier eine "
                    "**Entscheidung darüber, wie oft die Ampel günstig "
                    "steht**, und keine Kalibrierung auf einen "
                    "vorgefundenen Wert. Gerundet wurde trotzdem nur "
                    "einmal und nur an diesen sechs Arten — die "
                    "Alternative wäre gewesen, so lange zu runden, bis "
                    "Vorhersage 2 durchgeht."]

    out += ["", "## Die Schwellen, die daraus folgen", "",
            f"Gesetzt auf **{_pct(QUANTILE_VERHALTEN, 0)}** (verhalten) und "
            f"**{_pct(QUANTILE_GUENSTIG, 0)}** (günstig) der "
            "Vergleichstage, je Art unter ihrem eigenen Fenster und auf "
            "den Anpassjahren bestimmt.", "",
            "| Art | Optimum | verhalten ab | günstig ab |",
            "|---|--:|--:|--:|"]
    for row in usable:
        out.append(f"| {row['name']} | {row['optimum']:.1f} °C | "
                   f"{row['verhalten_at']:.3f} | {row['guenstig_at']:.3f} |"
                   .replace(" °C |", " °C |"))

    out += ["", "## Was die Nutzerin sähe", "",
            "Der **Abstand** zwischen „günstig an Fundtagen“ und „günstig "
            "an Vergleichstagen“, auf den Prüfjahren. Er ist das, was eine "
            "Stufe wert ist: Stünde sie an beiden gleich oft, sagte sie "
            "nichts.", "",
            "**Und er hängt daran, WO die Schwelle liegt.** Er ist null, "
            "wenn „günstig“ nie oder immer gilt, und am größten "
            "irgendwo dazwischen — eine strengere Schwelle kann ihn also "
            "verkleinern, ohne dass das Modell schlechter wäre. Die "
            "schwellenfreie Aussage steht als AUC in "
            "`docs/pilzampel-artenfenster-messung.md`; diese Seite fragt "
            "bewusst das andere: was die Nutzerin sieht.", "",
            "| Art | heute | nur eigenes Fenster | Fenster **und** "
            "Schwellen | günstig an Fundtagen | an Vergleichstagen |",
            "|---|--:|--:|--:|--:|--:|"]
    for row in usable:
        ci = row["gap_both_ci"]
        band = (f" [{_pp(ci[0])}, {_pp(ci[1])}]".replace(" pp", "")
                if ci else "")
        out.append(f"| {row['name']} | {_pp(row['gap_shipped'])} | "
                   f"{_pp(row['gap_window'])} | **{_pp(row['gap_both'])}**"
                   f"{band} | {_pct(row['found_shipped'])} → "
                   f"**{_pct(row['found_both'])}** "
                   f"| {_pct(row['ctrl_shipped'])} → "
                   f"{_pct(row['ctrl_both'])} |")

    prediction = next((r for r in usable
                       if r["name"] == THRESHOLD_PREDICTION_SPECIES), None)
    out += ["", f"## Vorhersage 2: der {THRESHOLD_PREDICTION_SPECIES}", "",
            "> Mit Quantil-Schwellen liegt der Abstand beim "
            f"{THRESHOLD_PREDICTION_SPECIES} bei mindestens "
            f"**{_pp(THRESHOLD_PREDICTION_MIN_GAP, 0)}**, gegenüber "
            "+0,5 pp mit den festen Schwellen.", ""]
    if prediction is None:
        out.append(f"*{THRESHOLD_PREDICTION_SPECIES} war in diesem Lauf "
                   "nicht dabei — die Vorhersage ist offen.*")
    else:
        met = prediction["gap_both"] >= THRESHOLD_PREDICTION_MIN_GAP
        ci = prediction["gap_both_ci"]
        band = (f" [{_pp(ci[0])}, {_pp(ci[1])}]" if ci else "")
        out += [f"Gemessen: **{_pp(prediction['gap_both'])}**{band} — "
                f"„günstig“ an Fundtagen "
                f"{_pct(prediction['found_shipped'])} → "
                f"**{_pct(prediction['found_both'])}**, an Vergleichstagen "
                f"{_pct(prediction['ctrl_shipped'])} → "
                f"{_pct(prediction['ctrl_both'])}.", ""]
        real = ci is not None and ci[0] > 0
        if met:
            out.append(
                "**Ergebnis: bestätigt.** Die Schwellen waren wirklich "
                "der Engpass — derselbe Gewinn, der in der Rangfolge "
                "längst messbar war, erreicht mit ihnen auch die drei "
                "Stufen.")
        elif real:
            out.append(
                "**Ergebnis: Schwelle verfehlt — der Effekt ist aber "
                "da.** Der Abstand ist von praktisch null auf "
                f"{_pp(prediction['gap_both'])} gestiegen, und sein "
                "Bereich schließt die Null aus; die vorab gesetzte Latte "
                f"von {_pp(THRESHOLD_PREDICTION_MIN_GAP, 0)} hat er "
                "trotzdem nicht genommen. Beides gehört nebeneinander "
                "berichtet: Die Richtung stimmt, die Größe war zu "
                "optimistisch angesagt.")
            out += ["",
                    "**Und die Latte hing an einer Zahl, die selbst "
                    "unsicher ist.** Wie groß der Abstand ausfällt, hängt "
                    "am gewählten Quantil — und dessen Wahl ist nach "
                    "Vorhersage 1 keine vorgefundene Größe mehr, sondern "
                    "eine Entscheidung. Eine Latte in Prozentpunkten war "
                    "dafür das falsche Maß; sie unterstellt eine "
                    "Schwelle, die feststeht."]
        else:
            out.append(
                "**Ergebnis: NICHT bestätigt.** Der Bereich des Abstands "
                "schließt die Null ein — in Stufen ist vom Gewinn der "
                "Rangfolge nichts übrig. Dann ist nicht die Schwelle das "
                "Problem, sondern die Erwartung, dass sich ein "
                "Rangfolgen-Gewinn überhaupt in eine Ampel übersetzt, und "
                "die Integration in die App braucht einen anderen Plan.")

    # --- Was ausgeliefert würde ------------------------------------
    #
    # **Getrennt vom Rest, und zwar streng.** Diese Zahlen sind auf den
    # Prüfjahren gesetzt und dort auch ausgewertet — als BELEG taugen sie
    # deshalb nicht, und der Abschnitt nennt bewusst keinen Abstand.
    # Beleg ist die Tabelle darüber (angepasst früh, geprüft spät); hier
    # steht nur, welche Konstanten daraus folgen.
    ship = deployment_quantiles(rows)
    if ship:
        attach_class_scores(rows)
        ship_v, ship_g = ship
        out += ["", "## Was ausgeliefert würde", "",
                "**Betreiberentscheidung 2026-09-12: „gleich häufig "
                "vorerst.“** Die Umstellung soll die Treffsicherheit "
                "ändern, nicht zugleich, wie oft die Ampel überhaupt "
                "spricht; beides auf einmal machte hinterher "
                "unauswertbar, was gewirkt hat.", "",
                f"Daraus folgen die Quantile **{_pct(ship_v, 0)}** "
                f"(verhalten) und **{_pct(ship_g, 0)}** (günstig) — der "
                "Median der sechs ausgelieferten Arten auf den "
                "**Prüfjahren**, also dort, wo die App heute steht. Auf "
                "den Anpassjahren zu kalibrieren wäre hier falsch: Die "
                "Ampel käme um die gemessene Drift zu großzügig heraus.",
                "",
                "| Art | Optimum | verhalten ab | günstig ab | "
                "günstig an Vergleichstagen |",
                "|---|--:|--:|--:|--:|"]
        def band(ci):
            return ("" if ci is None
                    else f" [{ci[0]:.3f}, {ci[1]:.3f}]")
        for row in usable:
            low = quantile_at(*row["own_later"], ship_v)
            high = quantile_at(*row["own_later"], ship_g)
            rate = 1.0 - rank_of(*row["own_later"], high)
            out.append(f"| {row['name']} | {row['optimum']:.1f} °C | "
                       f"{low:.3f}{band(row['ship_verhalten_ci'])} | "
                       f"{high:.3f}{band(row['ship_guenstig_ci'])} | "
                       f"{_pct(rate)} |")
        out += ["",
                "Die letzte Spalte ist **keine Messung, sondern die "
                "Probe aufs Exempel**: Sie muss auf eine Beobachtung "
                f"genau bei {_pct(1 - ship_g, 0)} herauskommen, weil die "
                "Schwelle genau so gesetzt wurde. Steht dort etwas "
                "anderes, ist die Rechnung kaputt.", "",
                "**Und diese Zahlen verfallen.** Sie beschreiben die "
                "Verteilung der Jahre ab 2019; die Messung oben zeigt, "
                "dass sich genau diese Verteilung über ein Jahrzehnt um "
                "gut acht Prozentpunkte verschoben hat. Wer sie "
                "ausliefert, schreibt das Datum dazu und misst nach."]

    # --- Die Klassen ------------------------------------------------
    if ship:
        klassen = class_thresholds(rows, ship, verify=False)
        out += ["", "## Die Klassen", "",
                "**Die Einheit ist die Klasse, nicht die Art** "
                "(Betreiber, 2026-09-12). Eine Klasse ist ein "
                "Temperaturfenster; die beiden Schwellen fallen daraus, "
                "als Quantile der Verteilung, die dieses Fenster an "
                "Vergleichstagen erzeugt. Zusammengelegt wird so, dass "
                "**jede Art gleich viel zählt** — ungewichtet wäre die "
                "Herbstschwelle die Steinpilzschwelle mit anderem Namen.",
                "",
                "| Klasse | Fenster | verhalten ab | günstig ab | Arten "
                "| ausgeliefert |",
                "|---|--:|--:|--:|---|---|"]
        for key, klass in AMPEL_CLASSES.items():
            got = klassen.get(key)
            if not got:
                continue
            out.append(class_table_row(key, klass, got))
        out += ["",
                "Die Spalte „ausgeliefert“ ist die eigentliche Grenze: "
                "Aufgenommen wird nur, was einen **Hold-out** bestanden "
                "hat. „Sieht in der Tabelle anders aus“ reicht nicht — "
                "daran wäre die Pfifferling-Spur fast gescheitert, bis "
                "Österreich und die Schweiz sie bestätigt haben. Für die "
                "übrigen gilt bis dahin, was für jede ungeprüfte Art "
                "gilt: lieber grau als erfunden."]
        for key, klass in AMPEL_CLASSES.items():
            if key in klassen:
                out.append(f"- **{key}** — {klass['why']}")

    # --- Läuft das Fenster mit der Saison? ---------------------------
    rule = season_rule(rows, read_season_curves())
    if rule:
        out += ["", "## Läuft das Fenster mit der Fruchtungszeit?", "",
                "Die registrierte Zusatzprüfung aus "
                "`docs/pilzampel-artenfenster.md` — und die Grundlage für "
                "die Frage, ob Arten **ohne** eigene Messung einer Klasse "
                "zugeordnet werden können. Die Saisonkurven sind an "
                "keiner Anpassung beteiligt: Sie kommen aus "
                "GBIF-Meldemonaten, die Fenster aus Wetterreihen.", "",
                "Der mittlere Fruchtungsmonat wird auf dem **Kreis** "
                "gebildet. Linear gemittelt landet der Austernseitling "
                "mit seinem Dezembergipfel im Juni, also genau zwischen "
                "seinen beiden Enden — und die Korrelation fällt von "
                "−0,68 auf −0,07. Die „Schärfe“ ist die Länge des "
                "Summenvektors: 1 heißt „alles in einem Monat“, 0 heißt "
                "„über das Jahr verteilt“.", "",
                "| Art | mittlerer Monat | Schärfe | Optimum |",
                "|---|--:|--:|--:|"]
        for point in sorted(rule["points"], key=lambda p: p["centre"]):
            mark = "" if point["sharpness"] >= SEASON_SHARPNESS_MIN else " ⚠"
            out.append(
                f"| {point['name']}{mark} | {point['centre']:.1f} | "
                f"{point['sharpness']:.2f} | {point['optimum']:.1f} °C |")
        out += ["",
                f"**Spearman über alle {rule['n_all']}: "
                f"{rule['rho_all']:+.3f}**".replace(".", ","), ""]
        if rule["dropped"]:
            out += [
                f"Ohne Kurven unter Schärfe "
                f"{SEASON_SHARPNESS_MIN:.2f} ".replace(".", ",")
                + f"({', '.join(rule['dropped'])} — eine flache Kurve hat "
                  f"keine Saison, über die sich korrelieren ließe): "
                  f"**{rule['rho_sharp']:+.3f}** bei n={rule['n_sharp']}"
                  .replace(".", ","), "",
                "**Diese Schwelle ist NACH dem Blick auf die Daten "
                "gesetzt**, und das gehört dazugesagt. Was für sie "
                "spricht: Die Lücke ist breit (0,29 gegen 0,69), es liegt "
                "keine einzige Art dazwischen, und „flach“ ist eine "
                "Eigenschaft der Kurve allein — sie kennt das Optimum "
                "nicht. Was gegen sie spricht: Sie ist trotzdem eine "
                "Entscheidung, die die Zahl verbessert hat.", ""]
        out += ["**Was die Zahl trägt — und was nicht.** Die Rangfolge "
                "hält: Sommerfrüchter warm, Herbstarten um 13 °C, "
                "Winterfrüchter kalt. Der ZUSAMMENHANG ist aber nicht "
                "linear — von 9,3 auf 10,5 Monate fällt das Optimum um "
                "2 K, von 9,3 auf 12,8 um 16. Eine Gerade durch diese "
                "Punkte zu legen und damit einer Art eine Gradzahl "
                "zuzuweisen wäre erfunden; sie einer **Klasse** "
                "zuzuordnen ist es nicht.", ""]

    # --- Die Karte: Maximum über die Klassen ------------------------
    #
    # Betreiberwunsch 2026-09-12: „Die Pilzampel auf der Karte soll das
    # Maximum für alle Klassen wiedergeben und nicht nur für eine, wie
    # das Herbstfenster." Die Fläche kennt keine Art, kann aber jede
    # BESTÄTIGTE Klasse rechnen und die beste zeigen.
    #
    # Die Zahl, die darüber entscheidet, ist nicht die Trennschärfe
    # (jede Klasse ist einzeln kalibriert), sondern die HÄUFIGKEIT: Zwei
    # Klassen, die je an 20 % der Tage günstig stehen, stehen zusammen
    # an mehr als 20 % günstig — und „gleich häufig vorerst" war eine
    # ausdrückliche Entscheidung.
    shipped = {key: klass for key, klass in AMPEL_CLASSES.items()
               if klass.get("dart")}
    days = []
    for row in usable:
        samples = row.get("test_samples")
        if not samples:
            continue
        weight = 1.0 / len(samples)
        for sample in samples:
            days.append((sample["control"], weight))
    if days and len(shipped) > 1:
        total = sum(w for _, w in days)

        def share(at_least, keys):
            hit = 0.0
            for control, weight in days:
                best = max(
                    level_with(ampel_score(*control, shipped[k]["optimum"]),
                               shipped[k]["verhalten"],
                               shipped[k]["guenstig"])
                    for k in keys)
                if best >= at_least:
                    hit += weight
            return hit / total

        out += ["", "## Wenn die Karte das Maximum aller Klassen zeigt", "",
                "Die Fläche kennt keine Art. Sie kann aber jede "
                "**bestätigte** Klasse rechnen und die beste zeigen — "
                "„günstig, sobald es für mindestens eine Gruppe günstig "
                "steht“. Was sich dadurch ändert, ist nicht die "
                "Trennschärfe (jede Klasse ist einzeln kalibriert), "
                "sondern die **Häufigkeit**.", "",
                "Gemessen an den Vergleichstagen der Prüfjahre, jede Art "
                "gleich gewichtet.", "",
                "| Anzeige | günstig | mindestens verhalten |",
                "|---|--:|--:|"]
        for label, keys in [
                ("nur Herbst (heute)", ["herbst"]),
                *[(f"nur {k}", [k]) for k in shipped if k != "herbst"],
                ("Maximum aller bestätigten", list(shipped))]:
            out.append(f"| {label} | {_pct(share(2, keys))} | "
                       f"{_pct(share(1, keys))} |")
        out += ["",
                "**Die Zeile „Maximum“ ist die Entscheidung**, nicht die "
                "Messung: Wie oft die Karte sprechen soll, ist eine "
                "Produktfrage. Steigt die Quote deutlich, lässt sie sich "
                "über das Quantil zurückdrehen — dann heißt „günstig“ "
                "aber für jede Klasse etwas Strengeres als am Spot, und "
                "Karte und Blatt sagten wieder Verschiedenes.", ""]

    out += ["", "## Was diese Seite NICHT sagt", "",
            "Sie ändert `ampel_model.dart` nicht. Über eine Umstellung "
            "entscheidet der Betreiber mit diesen Zahlen; bis dahin bleibt "
            "der Gleichlauf „Zahl für Zahl“ zwischen Modellkern und "
            "Werkzeug unberührt.", "",
            "Und die Grenze des Konzeptpapiers gilt unverändert: Auch eine "
            "kalibrierte Schwelle sagt „die Bedingungen sind günstig“, "
            "nicht „hier stehen Pilze“.", ""]
    return "\n".join(out)


# --- Geografischer Hold-out (docs/pilzampel-artenfenster.md) ---------------
#
# Die registrierte Bestätigung der Pfifferling-Spur. Die Zeitscheibe
# 2019–2025 war ungesehen, die AUSWAHL der Art war es nicht — und das
# repariert keine weitere Rechnung an denselben Daten. Andere Länder sind
# neue Daten statt neu geschnittener: Sie beantworten, ob 19,2 °C eine
# Eigenschaft der ART ist oder eine der deutschen Stichprobe.

# Die Schwelle stand vor der Messung fest und steht als Konstante hier,
# damit sie sich hinterher nicht umformulieren lässt.
HOLDOUT_MIN_GAIN = 0.05

# Wie weit die Placebo-Kontrolle von 0,50 abweichen darf. Dieselbe Grenze
# wie in der Zusammenfassung der Rückwärtsvalidierung — dort steht sie
# seit jeher, hier stand sie als nackte Zahl im Bericht.
PLACEBO_TOLERANCE = 0.03


def control_tolerance(n):
    """Zwei Standardfehler bei DIESER Paarzahl — statt einer festen Zahl.

    ±0,03 war eine feste Grenze an einer Größe, deren Streuung an `n`
    hängt. Zwei Standardfehler sind **±0,045 bei 538 Paaren** und
    **±0,022 bei 2000**: Die feste Zahl war bei kleinen Stichproben zu
    lasch und bei großen zu streng — ein Filter auf die Stichprobengröße
    und nicht auf die Gültigkeit.

    Genau das war schon am 2026-09-17 gemessen worden
    (`docs/pilzampel-kontrolltoleranz.md`: alle acht Ablehnungen lagen
    innerhalb von 2,5 Standardfehlern, 0 von 16 großen Stichproben wurden
    abgelehnt gegen 7 von 18 kleinen). Damals wurde daraus der
    Jahres-Bootstrap; wo es den nicht gibt, stand die feste Zahl weiter.

    Ohne Paarzahl bleibt es bei der alten Grenze — dann ist sie die
    einzige Auskunft, die da ist.
    """
    if not n:
        return PLACEBO_TOLERANCE
    return 2.0 * math.sqrt(0.25 / n)


def control_clean(auc, n):
    """Hält die Kontrolle bei dieser Paarzahl?"""
    return abs(auc - 0.5) <= control_tolerance(n)


def _tolerance_text(n):
    """Die verwendete Toleranz IM BERICHT nennen, nicht nur anwenden.

    Der Auftrag verlangt sie in jeder Tabelle: Eine Grenze, die sich mit
    der Paarzahl ändert, ist ohne die Zahl daneben nicht nachvollziehbar.
    Die alte feste Grenze steht dabei, solange es Berichte gibt, die sie
    benutzt haben.
    """
    if not n:
        return f"Toleranz ±{PLACEBO_TOLERANCE:.2f}"
    return (f"Toleranz ±{control_tolerance(n):.3f} = 2 SE bei {n} Paaren; "
            f"früher fest ±{PLACEBO_TOLERANCE:.2f}")


def holdout_species(name, sci, countries, cache_dir=None, seed=42,
                    progress=True, window=None):
    """In Deutschland anpassen, im Ausland prüfen.

    **Das Optimum kommt aus dem deutschen Lauf, nicht aus dem Aufruf.**
    Eine Zahl von Hand einzutippen wäre die Stelle, an der sich
    unbemerkt eine andere einschleicht als die berichtete — und im
    Hold-out sind ALLE Jahre Prüfjahre, dort gibt es keine zweite
    Trennlinie, die einen Irrtum auffinge.

    [window] prüft statt des ART-Fensters das der KLASSE. Es ist
    ebenfalls gerechnet und nicht getippt (`class_optimum` über die
    deutschen Optima der Mitglieder) — nur eben über mehrere Arten. Das
    ist die härtere Prüfung und zugleich die ehrlichere: Ausgeliefert
    würde EIN Fenster für die Klasse, nicht eines je Art.
    """
    if progress:
        print(f"  {name}: anpassen in DE …", file=sys.stderr)
    home = fit_species(name, sci, cache_dir=cache_dir, seed=seed,
                       progress=progress)
    if home is None or not home.get("usable"):
        return {"name": name, "usable": False, "why": "DE-Anpassung fehlt"}
    own = home["optimum"]
    optimum = own if window is None else window

    if progress:
        print(f"  {name}: prüfen in {'+'.join(countries)} "
              f"mit {optimum:.1f} °C …", file=sys.stderr)
    drawn = collect_pairs(name, sci, cache_dir=cache_dir, seed=seed,
                          progress=progress, countries=countries)
    if drawn is None:
        return {"name": name, "usable": False, "why": "keine Funde"}
    samples = drawn["samples"]
    shared = paired_auc(score_pairs(samples, OPTIMUM_C))
    fitted = paired_auc(score_pairs(samples, optimum))
    # **Die Richtungsaussage** (registriert, ohne Torfunktion): Wohin
    # zeigt das Optimum, wenn man es IM Hold-out neu anpasst? Sie ist
    # kein zweiter Beleg — auf denselben Daten angepasst und geprüft
    # wäre sie Selbstbestätigung. Sie sagt nur, ob ein dritter Anlauf
    # mit mehr Material lohnte.
    refit = grid_optimum(samples)
    # Die Placebo-Kontrolle gilt auch hier: Ohne sie wüsste niemand, ob
    # die Ziehung im Ausland genauso unverzerrt ist wie zu Hause.
    placebo = [(ampel_score(*s["control"]), ampel_score(*s["placebo"]))
               for s in samples if s["placebo"] is not None]
    mirrored = [(ampel_score(*s["control"]), ampel_score(*s["mirror"]))
                for s in samples if s["mirror"] is not None]
    return {
        "name": name,
        "usable": True,
        "countries": list(countries),
        "optimum": optimum,
        "own_optimum": own,
        "window": window,
        "refit": refit["optimum"],
        "refit_band": refit["best_set"],
        "n_home": home["n_fit"] + home["n_test"],
        "n": len(samples),
        "years": drawn["years"],
        "auc_shared": shared,
        "auc_fitted": fitted,
        "gain": fitted - shared,
        "placebo_auc": paired_auc(placebo),
        "placebo_n": len(placebo),
        "mirror_auc": paired_auc(mirrored),
        "mirror_n": len(mirrored),
        "ci": bootstrap_years(samples, [OPTIMUM_C, optimum], seed=seed),
    }


def class_holdout_clean(row):
    """Trägt die Ziehung dieser Art im Hold-out überhaupt?

    Die abstandsgleiche Kontrolle entscheidet VOR dem Ergebnis: Steht sie
    nicht bei 0,50, ist die Ziehung verzerrt, und die Zahl darüber ist
    wertlos — egal wie gut sie aussieht.
    """
    return control_clean(row["mirror_auc"], row.get("mirror_n"))


def class_holdout_verdict(rows, members):
    """Vier Ausgänge, wie beim Kalttest — und „offen" ist nicht „keine".

    Eine Art ohne Material oder mit verzerrter Ziehung ist NICHT
    gemessen worden. Das als Fehlschlag zu berichten wäre eine Aussage
    über Daten, die es nicht gibt.
    """
    by_name = {row["name"]: row for row in rows}
    offen, met, failed = [], [], []
    for name in members:
        row = by_name.get(name)
        if row is None or not row.get("usable"):
            offen.append(f"{name} (kein auswertbares Material)")
        elif not class_holdout_clean(row):
            offen.append(f"{name} (Ziehung verzerrt: "
                         f"{row['mirror_auc']:.3f})")
        elif row["gain"] >= HOLDOUT_MIN_GAIN:
            met.append(name)
        else:
            failed.append(name)
    # **Ein sauber gemessener Fehlschlag entscheidet — trotz Lücken.**
    # „Alle oder keine" heißt: Eine Art, die bei sauberer Kontrolle unter
    # der Latte bleibt, nimmt die Klasse mit, und keine ungemessene
    # dritte kann sie zurückholen. Das als „noch nicht entschieden" zu
    # melden verstünde jeder als „vielleicht doch" — und verschöbe die
    # Entscheidung auf Daten, die daran nichts mehr ändern können.
    if failed:
        return {"state": "nur-eine" if met else "keine",
                "met": met, "failed": failed, "offen": offen}
    if offen:
        return {"state": "offen", "offen": offen, "met": met,
                "failed": failed}
    return {"state": "bestanden", "met": met, "failed": [], "offen": []}


def render_class_holdout_report(rows, countries, key, window, fits,
                                fetched_on):
    """Der Hold-out einer KLASSE — ein Fenster, mehrere Arten.

    Eigener Bericht neben `render_holdout_report`: Dort steht die
    Vorhersage des Pfifferlings, hier die der Klasse. Zwei registrierte
    Bedingungen in einem Text lesen sich als eine.
    """
    klass = AMPEL_CLASSES[key]
    members = klass["members"]
    verdict_info = class_holdout_verdict(rows, members)
    state = verdict_info["state"]
    laender = " und ".join(countries)
    out = [f"# Hold-out der Klasse „{key}“", "",
           f"Stand: {fetched_on} · Erzeugt von `tool/ampel_validate.py "
           f"--holdout {','.join(countries)} --class {key}` · Prüfplan: "
           "`docs/pilzampel-artenfenster.md`", "",
           f"Angepasst wurde in **Deutschland** (Jahre bis {FIT_UNTIL_YEAR}), "
           f"geprüft in **{laender}** — dort sind ALLE Jahre Prüfjahre, denn "
           "an der Anpassung war keiner von ihnen beteiligt.", "",
           "**Geprüft wird das Fenster der KLASSE, nicht das jeder Art.** "
           "Ausgeliefert würde ein Fenster für alle Mitglieder; eines je "
           "Art zu prüfen beantwortete eine Frage, die sich in der App nie "
           "stellt.", "",
           "## Die Bedingung, die vor der Messung feststand", "",
           f"> Das an deutschen Funden angepasste Fenster der Klasse trennt "
           f"auch in {laender} besser als die {OPTIMUM_C:.0f} °C — gepaarte "
           f"AUC dort mindestens **{HOLDOUT_MIN_GAIN:+.2f}** über der mit "
           f"{OPTIMUM_C:.0f} °C, und zwar bei **allen** Mitgliedern.", "",
           "> **Beide oder keine.** Eine Klasse, von deren Arten eine "
           "besteht, war vorab ausgeschlossen.", "",
           "> Dazu, **ohne Torfunktion**, eine Richtungsaussage: Die im "
           f"Hold-out neu angepassten Optima liegen unter "
           f"{klass.get('direction_below', OPTIMUM_C):.0f} °C.", "",
           "## Das Fenster", "",
           "Abgeleitet und nicht gewählt — der Median der deutschen Optima "
           "seiner Mitglieder, gerechnet bei diesem Lauf:", "",
           "| Mitglied | Optimum in DE | Paare DE |", "|---|--:|--:|"]
    for row in fits:
        if not row.get("usable"):
            out.append(f"| {row['name']} | — | — |")
            continue
        out.append(f"| {row['name']} | {row['optimum']:.1f} °C | "
                   f"{row['n_fit'] + row['n_test']} |")
    out += ["", f"**Fenster der Klasse: {_optimum_text(window)} °C.** Die "
            "Bedingung hängt an der Latte, nicht an dieser Zahl.", "",
            "## Gemessen", "",
            f"| Art | Paare {'+'.join(countries)} | Jahre | AUC mit "
            f"{OPTIMUM_C:.0f} °C | AUC mit {_optimum_text(window)} °C | "
            "Differenz (95 %) | Kontrolle | Bedingung |",
            "|---|--:|--:|--:|--:|---|--:|---|"]
    for name in members:
        row = next((r for r in rows if r["name"] == name), None)
        if row is None or not row.get("usable"):
            grund = (row or {}).get("why", "nicht gerechnet")
            out.append(f"| {name} | — | — | — | — | — | — | {grund} |")
            continue
        span = (row.get("ci") or {}).get("difference")
        ci = (f"{row['gain']:+.3f} [{span[0]:+.3f}, {span[1]:+.3f}]"
              if span else f"{row['gain']:+.3f} (kein Bereich)")
        clean = class_holdout_clean(row)
        if not clean:
            mark = "nicht auswertbar"
        elif row["gain"] >= HOLDOUT_MIN_GAIN:
            mark = "**erfüllt**"
        else:
            mark = (f"nicht erfüllt: {row['gain']:+.3f} unter "
                    f"{HOLDOUT_MIN_GAIN:+.2f}")
        out.append(f"| {name} | {row['n']} | {row['years']} | "
                   f"{row['auc_shared']:.3f} | {row['auc_fitted']:.3f} | "
                   f"{ci} | {row['mirror_auc']:.3f} | {mark} |")
    out += ["", "Die Spalte „Kontrolle“ ist die abstandsgleiche "
            "Kontrolle — Vergleichstag gegen seinen am Fundtag "
            "gespiegelten Partner. Sie MUSS bei 0,50 liegen; tut sie es "
            "nicht, ist die Ziehung verzerrt und die Zahl daneben wertlos.",
            "", "**Die Toleranz hängt seit 2026-09-17 an der Paarzahl** "
            "(zwei Standardfehler, `2·√(0,25/n)`) statt an festen ±0,03. "
            "Die feste Zahl war ein Filter auf die Stichprobengröße: Zwei "
            "Standardfehler sind ±0,045 bei 538 Paaren und ±0,022 bei 2000. "
            "Frühere Berichte nennen weiterhin die ±0,03, unter der sie "
            "entstanden sind — sie werden nicht rückwirkend umetikettiert.",
            "",
            "## Der Ausgang", ""]

    if state == "offen":
        out += ["**Noch nicht entschieden.** Nicht auswertbar: "
                + ", ".join(verdict_info["offen"]) + ".", "",
                "Das ist kein Fehlschlag, sondern eine Lücke — und die "
                "Bedingung bleibt unverändert stehen.", "",
                "**Bis dahin ändert sich nichts an der App.**"]
    elif state == "bestanden":
        out += [f"**Bestanden — alle Mitglieder, im Ausland geprüft.** Das "
                f"Fenster von {_optimum_text(window)} °C gehört damit der "
                "Klasse und nicht der deutschen Stichprobe.", "",
                "Was noch fehlt, bevor die App sie zeigt: **die Schwellen "
                "der Klasse**, als Quantil der Vergleichstage DIESES "
                "Fensters (`--thresholds`). Ein eigenes Fenster ohne "
                "eigene Schwellen macht die Ampel dunkel statt besser."]
    else:
        if state == "nur-eine":
            out += ["**Nicht bestanden — "
                    + (f"{len(verdict_info['met'])} von {len(members)} "
                       "Mitgliedern erfüllen die Bedingung"
                       if len(verdict_info["met"]) > 1 else
                       f"ein Mitglied von {len(members)} erfüllt die "
                       "Bedingung")
                    + "** (erfüllt: " + ", ".join(verdict_info["met"])
                    + "; darunter: " + ", ".join(verdict_info["failed"])
                    + ").", "",
                    "Das ist der Ausgang, der vorab ausgeschlossen war: "
                    "alle oder keine. Eine Klasse, deren Mitglieder sich "
                    "im Ausland verschieden verhalten, ist keine — sie "
                    "ist eine Liste von Arten, die in EINER Stichprobe "
                    "zusammenlagen."]
        else:
            out += ["**Nicht bestanden — kein Mitglied erreicht die "
                    "Latte.**"]
        if verdict_info.get("offen"):
            out += ["", "**Nicht gemessen wurde dabei:** "
                    + ", ".join(verdict_info["offen"]) + ". Das ändert am "
                    "Ausgang nichts — „alle oder keine“ ist schon "
                    "entschieden, sobald ein Mitglied bei sauberer "
                    "Kontrolle unter der Latte bleibt."]
        # **Wer die Latte nahm, nahm sie vielleicht knapp.** Die
        # registrierte Bedingung ist ein Punktschätzer; ein Bericht, der
        # verschweigt, dass der Vertrauensbereich die Null einschließt,
        # sagt mehr als gemessen wurde.
        weich = [n for n in verdict_info.get("met", [])
                 if ((by := next((r for r in rows if r["name"] == n), None))
                     and (span := (by.get("ci") or {}).get("difference"))
                     and span[0] <= 0)]
        if weich:
            out += ["", "**Und bei " + ", ".join(weich) + " schließt der "
                    "Vertrauensbereich die Null ein** — die Bedingung war "
                    "als Punktschätzer registriert und ist damit erfüllt, "
                    "aber tragen würde diese Zahl allein nicht."]
        # **Wie ein Fehlschlag zu lesen ist, hängt am ABSTAND.** Der
        # Satz „die Glocke ist in ihrer Mitte flach" entschuldigt ein
        # knappes Verfehlen — bei 1,4 K zu Recht. Für ein Fenster 14 K
        # neben den 13 °C ist er das Gegenteil der Wahrheit: Ein
        # Unterschied dieser Größe MUSS sich zeigen, wenn es ihn gibt.
        # Ein vorformulierter Satz, der die falsche Ursache behauptet,
        # ist hier schon zweimal vorgekommen; deshalb entscheidet die
        # Zahl und nicht die Formulierung. Die Grenze ist die Breite der
        # Glocke selbst (σ = TEMP_SIGMA) und nicht geraten.
        versatz = abs(window - OPTIMUM_C)
        if versatz < TEMP_SIGMA:
            deutung = [f"Die Glocke ist in ihrer Mitte flach, und "
                       f"{_optimum_text(window)} °C liegen nur "
                       f"{versatz:.1f} K neben den {OPTIMUM_C:.0f} °C "
                       f"(σ = {TEMP_SIGMA:.0f} K); ein echter Unterschied "
                       "dieser Größe kann die Latte verfehlen."]
        else:
            deutung = [f"**Und hier wiegt der Fehlschlag schwerer als "
                       f"sonst:** {_optimum_text(window)} °C liegen "
                       f"{versatz:.1f} K neben den {OPTIMUM_C:.0f} °C, "
                       f"also gut {versatz / TEMP_SIGMA:.0f} Glockenbreiten "
                       f"(σ = {TEMP_SIGMA:.0f} K). Bei einem so großen "
                       "Abstand unterscheiden sich die Scores der beiden "
                       "Fenster drastisch — wenn sich das NICHT in der "
                       "Trennschärfe niederschlägt, spricht das gegen das "
                       "Fenster und nicht gegen die Stichprobengröße."]
        out += ["", "**Was das heißt, und was nicht.** Es heißt zunächst: "
                "„bei dieser Stichprobengröße und diesem Abstand nicht "
                "nachweisbar“ — nicht „es gibt keinen Unterschied“."]
        out += ["", " ".join(deutung), "",
                "Ausgeliefert wird die Klasse trotzdem nicht: Der Vorbehalt "
                "der App gilt dem, was belegt ist, und nicht dem, was "
                "plausibel ist."]

    # **Die Richtungsaussage steht NACH dem Urteil** — sie ist keine
    # zweite Chance zu bestehen. Angepasst und geprüft auf denselben
    # Daten wäre sie Selbstbestätigung; sie sagt nur, ob mehr Material
    # lohnte.
    gerechnet = [r for r in rows if r.get("usable")]
    if gerechnet:
        # Die Latte gehört der KLASSE: Für eine kalte ist „unter 13 °C“
        # keine Aussage, dort landet ein Winterfrüchter ohnehin.
        latte = klass.get("direction_below", OPTIMUM_C)
        out += ["", "## Die Richtungsaussage (kein Tor)", "",
                f"Optima, im Hold-out selbst neu angepasst — angepasst "
                f"und geprüft auf denselben Daten, also kein Beleg. Die "
                f"Latte dieser Klasse: unter {latte:.0f} °C.", "",
                "| Art | Optimum in " + "+".join(countries) + " | bestes "
                "Band |", "|---|--:|---|"]
        for row in gerechnet:
            low, high = row["refit_band"]
            band = (f"{low:.1f}" if low == high
                    else f"{low:.1f} bis {high:.1f}")
            out.append(f"| {row['name']} | {row['refit']:.1f} °C | {band} |")
        unter = [r for r in gerechnet if r["refit"] < latte]
        drueber = [r for r in gerechnet if r["refit"] >= latte]

        def _namen(rows):
            return ", ".join(f"{r['name']} {r['refit']:.1f} °C"
                             for r in rows)

        # **Der Zusatz „stützt die Richtung" gehört NUR an den Fall, in
        # dem alle darunter liegen.** Er hing zuerst daran, dass
        # IRGENDEINE Art darunter liegt — und stand damit unter dem Satz
        # „Nicht alle liegen unter 13 °C", also direkt unter seinem
        # eigenen Gegenteil. Genau die Sorte vorformulierter Satz, die
        # hier schon zweimal die falsche Ursache behauptet hat.
        if not unter:
            satz = (f"**Keines der Optima liegt unter {latte:.0f} °C** "
                    f"({_namen(drueber)}). Die Richtungsaussage hält "
                    "nicht.")
        elif not drueber:
            satz = (f"**Alle liegen unter {latte:.0f} °C**, wie "
                    "vorhergesagt. Das stützt die Richtung, belegt aber "
                    "nichts.")
        else:
            satz = (f"**Die Richtung hält nur zum Teil:** "
                    f"{_namen(unter)} unter den {latte:.0f} °C, "
                    f"{_namen(drueber)} darüber. Für die Klasse als Ganzes "
                    "ist das keine Stütze — ein gemeinsames Fenster ist "
                    "gerade das, was hier auseinanderfällt.")
        out += ["", satz]

    out += ["", "## Grenzen", "",
            "Angepasst wurde ausschließlich an GBIF. Die eigenen Funde und "
            "Leergänge der App bleiben draußen — sie sind der unabhängige "
            "Prüfstein aus #199.", "",
            "Auch ein bestätigtes Fenster sagt „die Bedingungen sind "
            "günstig“, nicht „hier stehen Pilze“."]
    return "\n".join(out) + "\n"


def render_holdout_report(rows, countries, fetched_on):
    out = ["# Artenfenster: der geografische Hold-out", "",
           f"Stand: {fetched_on} · Erzeugt von `tool/ampel_validate.py "
           f"--holdout` · Prüfplan: `docs/pilzampel-artenfenster.md`", "",
           f"Angepasst wurde in **Deutschland** (Jahre bis {FIT_UNTIL_YEAR}), "
           f"geprüft in **{' und '.join(countries)}** — dort sind ALLE Jahre "
           "Prüfjahre, denn an der Anpassung war keiner von ihnen beteiligt. "
           "Das beantwortet, was eine weitere Zeitscheibe nicht mehr kann: "
           "ob das Fenster der ART gehört oder der deutschen Stichprobe.", "",
           "## Die Schwelle, die vor der Messung feststand", "",
           f"> Die gepaarte AUC mit dem angepassten Optimum liegt im "
           f"Hold-out mindestens **{HOLDOUT_MIN_GAIN:+.2f}** über der mit "
           f"{OPTIMUM_C:.0f} °C.", ""]
    for row in rows:
        if not row.get("usable"):
            out += [f"**{row['name']}: nicht auswertbar** — {row['why']}.", ""]
            continue
        # **Die Placebo-Kontrolle entscheidet VOR dem Ergebnis.** Steht
        # sie nicht bei 0,50, ist die Ziehung verzerrt — und dann ist die
        # Zahl darüber wertlos, egal wie gut sie aussieht. Der erste
        # Bericht schrieb „bestätigt" und zwei Zeilen darunter „nicht
        # auswertbar"; von zwei widersprüchlichen Sätzen liest jeder den,
        # der ihm passt.
        clean = control_clean(row["mirror_auc"], row.get("mirror_n"))
        met = clean and row["gain"] >= HOLDOUT_MIN_GAIN
        span = (row.get("ci") or {}).get("difference")
        ci = f" [{span[0]:+.3f}, {span[1]:+.3f}]" if span else ""
        out += [f"## {row['name']}", "",
                f"Optimum aus Deutschland: **{row['optimum']:.1f} °C** "
                f"({row['n_home']} Paare). Im Hold-out "
                f"{row['n']} Paare aus {row['years']} Jahren.", "",
                f"| | AUC |", "|---|--:|",
                f"| mit {OPTIMUM_C:.0f} °C | {row['auc_shared']:.3f} |",
                f"| mit {row['optimum']:.1f} °C | {row['auc_fitted']:.3f} |",
                f"| Differenz | **{row['gain']:+.3f}**{ci} |", "",
                "**Ergebnis: " + (
                    "bestätigt" if met else
                    "NICHT AUSWERTBAR — die Placebo-Kontrolle ist verzerrt"
                    if not clean else "nicht bestätigt")
                + f"** (Schwelle {HOLDOUT_MIN_GAIN:+.2f}).", ""]
        # Ohne sie ist die Zahl darüber nichts wert — dieselbe Regel wie
        # in der Rückwärtsvalidierung.
        off = abs(row["placebo_auc"] - 0.5)
        out += [f"Placebo-Kontrolle im Hold-out: {row['placebo_auc']:.3f} "
                f"bei {row['placebo_n']} Paaren "
                f"({_tolerance_text(row['placebo_n'])})"
                + (" — erwartbar abweichend, siehe unten."
                   if not control_clean(row["placebo_auc"], row["placebo_n"])
                   else " — unauffällig.")]
        out += [f"**Abstandsgleiche Kontrolle: {row['mirror_auc']:.3f}** bei "
                f"{row['mirror_n']} Paaren — der Vergleichstag gegen seine "
                f"Spiegelung am Fundtag, beide exakt gleich weit weg"
                + (" — unauffällig. Daran hängt das Urteil oben."
                   if clean else
                   " — **verzerrt.** Zwei fundfreie Tage, nach derselben "
                   "Vorschrift gezogen, dürfen sich nicht unterscheiden. "
                   "Tun sie es doch, misst der Aufbau etwas anderes als "
                   "das Wetter am Fundtag, und die Zahlen darüber sind "
                   "keine Aussage über das Modell."),
                ""]
    return "\n".join(out) + "\n"


# --- Eine vorhandene Sammlung wieder benutzbar machen -----------------------
#
# **Warum es das braucht.** Der Wetter-Cache ist nach dem Hash der
# geordneten Ortsliste eines Jahres benannt, und die Dateien enthalten
# keine Koordinaten. Wächst GBIF — im September täglich —, zieht
# `random.sample` aus einer anderen Grundgesamtheit, sämtliche Ortslisten
# verschieben sich, und 51 MB mühsam geholter Wetterdaten sind nicht mehr
# auffindbar. Genau so ist es dem Bestand vom August 2026 ergangen.
#
# **Der Ausweg nutzt aus, dass GBIF nur WÄCHST.** Die Meldungen sind
# dieselben geblieben, es sind welche dazugekommen, und die id trägt die
# Aufnahmereihenfolge. Entfernt man die k neuesten, erhält man die Liste
# von damals — und ob k stimmt, sagt der Cache selbst: Bei richtigem k
# treffen die Hashes, bei falschem trifft keiner. Eine Prüfsumme passt
# nicht zwanzigmal zufällig.

# So viele neue Meldungen werden höchstens abgezogen. 60 reicht für ein
# paar Monate; wer eine Sammlung aus dem Vorjahr wiederbeleben will,
# dreht hoch und wartet länger.
MAX_RECOVER_DROP = 60


def without_newest(finds, count):
    """Die [count] zuletzt aufgenommenen Meldungen entfernen.

    **Die Reihenfolge der übrigen bleibt**, und das ist der Punkt: Die
    Stichprobe hängt an ihr, nicht nur am Inhalt. Ausgewählt wird über
    die GBIF-id, nicht über die Position — eine neue Meldung kann
    mitten in der Seitenfolge auftauchen.
    """
    if count <= 0:
        return list(finds)
    newest = sorted(range(len(finds)),
                    key=lambda i: finds[i]["key"], reverse=True)[:count]
    drop = set(newest)
    return [f for i, f in enumerate(finds) if i not in drop]


def cache_hits(finds, cache_dir, seed=42):
    """Wie viele Jahre dieser Stichprobe liegen schon im Cache?"""
    if len(finds) > SAMPLE_PER_SPECIES:
        finds = random.Random(seed).sample(finds, SAMPLE_PER_SPECIES)
    by_year = {}
    for find in finds:
        by_year.setdefault(find["year"], []).append(find)
    found = total = 0
    for year, group in by_year.items():
        if year > LAST_COMPLETE_YEAR:
            continue
        total += 1
        points = [(f["lat"], f["lon"]) for f in group]
        span = season_span(
            [day_index(year, f["month"], f["day"]) for f in group], year=year)
        if os.path.exists(os.path.join(
                cache_dir, _cache_key(year, points, span[0], span[1]))):
            found += 1
    return found, total


def recover_sample(name, sci, cache_dir, seed=42, progress=True):
    """Die Stichprobe suchen, zu der ein vorhandener Cache gehört."""
    if progress:
        print(f"  {name} ({sci})", file=sys.stderr)
    full = _fetch_finds_raw(sci, progress=progress)
    best = (0, -1, 0)
    for count in range(MAX_RECOVER_DROP + 1):
        candidate = without_newest(full, count)
        found, total = cache_hits(candidate, cache_dir, seed)
        if found > best[1]:
            best = (count, found, total)
        if total and found == total:
            break
    count, found, total = best
    finds = [{k: v for k, v in f.items() if k != "key"}
             for f in without_newest(full, count)]
    os.makedirs(cache_dir, exist_ok=True)
    with open(_finds_cache_path(cache_dir, sci), "w",
              encoding="utf-8") as handle:
        json.dump(finds, handle)
    if progress:
        print(f"    {len(full)} heute − {count} neue = {len(finds)}; "
              f"{found}/{total} Jahre im Cache", file=sys.stderr)
    return {"name": name, "today": len(full), "dropped": count,
            "n": len(finds), "hits": found, "years": total}


# --- Anpassung je Art ------------------------------------------------------
#
# Der Prüfplan steht in `docs/pilzampel-artenfenster.md`. Hier steht nur
# die Rechnung dazu — und die drei Stellen, an denen sie sich selbst
# misstraut: Gitterlauf NUR auf Anpassjahren, Bewertung NUR auf
# Prüfjahren, Vertrauensbereich über JAHRE.


def grid_optimum(samples):
    """Das Optimum, das Fund- und Vergleichstag am besten trennt.

    **Angepasst wird an die Trennung, nicht an die Fundtage.** Das
    Mittel der Temperatur an Fundtagen wäre der naheliegende Weg und
    misst die Jahreszeit: Eine Art mit Gipfel im Dezember hat kalte
    Fundtage, weil Dezember kalt ist. Die gepaarte AUC fragt dagegen,
    welches Optimum einen Fundtag von einem NAHEN Tag ohne Fund trennt —
    und dort kürzt sich die Saison heraus (Placebo ≈ 0,50).

    Zurück kommt neben dem besten Wert die **Plateaubreite**: alle
    Optima, die weniger als 0,005 AUC darunter liegen. Ist sie breit,
    ist der Gipfel eine Nachkommastelle ohne Deckung — und das gehört
    berichtet, nicht weggerundet.
    """
    if not samples:
        return None
    scored = []
    steps = int(round((FIT_GRID_MAX_C - FIT_GRID_MIN_C) / FIT_GRID_STEP_C))
    for step in range(steps + 1):
        optimum = FIT_GRID_MIN_C + step * FIT_GRID_STEP_C
        scored.append((optimum, paired_auc(score_pairs(samples, optimum))))
    best_auc = max(auc for _, auc in scored)
    # **Bei Gleichstand die MITTE, nicht das erste.** Zwei Temperaturen
    # trennen ein Paar nur dann verschieden, wenn sie auf verschiedenen
    # Seiten seines Mittelpunkts liegen — gleich gute Optima kommen
    # deshalb als zusammenhängendes Band vor, nicht vereinzelt. Wer davon
    # den Rand nimmt, verschiebt jeden Gipfel systematisch dorthin; beim
    # Selbsttest mit gepflanztem Optimum von 7 °C kam so 4,5 heraus.
    best_set = [o for o, auc in scored if auc == best_auc]
    best_optimum = statistics.median(best_set)
    plateau = [o for o, auc in scored if auc >= best_auc - 0.005]
    return {
        "optimum": best_optimum,
        "auc_fit": best_auc,
        "best_set": (min(best_set), max(best_set)),
        "plateau": (min(plateau), max(plateau)),
        # Gemessen am Band der wirklich besten Werte, nicht am Mittelwert:
        # Reicht es bis ans Gitter, liegt die Wahrheit vermutlich
        # dahinter — die Glocke ist dort keine Glocke mehr, sondern eine
        # Gerade.
        "at_edge": min(best_set) <= FIT_GRID_MIN_C
        or max(best_set) >= FIT_GRID_MAX_C,
    }


def bootstrap_years(samples, optima, rounds=FIT_BOOTSTRAP_ROUNDS, seed=42):
    """Vertrauensbereiche, gezogen über JAHRE statt über Paare.

    Funde desselben Jahres sind einander ähnlicher als Funde
    verschiedener Jahre (Pilzjahre unterscheiden sich um den Faktor
    zehn). Über Paare zu ziehen behandelte sie als unabhängig und
    lieferte einen Bereich, der zu eng ist — also eine Sicherheit, die
    es nicht gibt.

    Alle [optima] werden auf DERSELBEN Ziehung gerechnet; nur so ist
    ihre Differenz gepaart und ihr Bereich aussagekräftig.
    """
    by_year = {}
    for sample in samples:
        by_year.setdefault(sample["year"], []).append(sample)
    years = sorted(by_year)
    if len(years) < 2:
        return None
    rng = random.Random(seed)
    draws = {optimum: [] for optimum in optima}
    differences = []
    for _ in range(rounds):
        picked = [rng.choice(years) for _ in years]
        pool = [s for year in picked for s in by_year[year]]
        values = {}
        for optimum in optima:
            values[optimum] = paired_auc(score_pairs(pool, optimum))
            draws[optimum].append(values[optimum])
        if len(optima) == 2:
            differences.append(values[optima[1]] - values[optima[0]])

    def interval(values):
        values = sorted(values)
        lo = values[int(0.025 * len(values))]
        hi = values[min(len(values) - 1, int(0.975 * len(values)))]
        return (lo, hi)

    result = {optimum: interval(values) for optimum, values in draws.items()}
    if differences:
        result["difference"] = interval(differences)
    return result


def split_by_year(samples):
    """Anpassjahre und Prüfjahre — die eine Trennlinie dieses Aufbaus.

    Als eigene Funktion, weil sie die Zusage IST: Kein Jahr darf auf
    beiden Seiten stehen. Inline wäre daraus ein Vergleichsoperator, den
    niemand prüft, und ein verrutschtes `<` machte die Prüfung zur
    Selbstbestätigung, ohne dass eine Zahl auffällig aussähe.
    """
    fit = [s for s in samples if s["year"] <= FIT_UNTIL_YEAR]
    test = [s for s in samples if s["year"] > FIT_UNTIL_YEAR]
    return fit, test


def fit_species(name, sci, cache_dir=None, seed=42, progress=True):
    """Optimum auf frühen Jahren anpassen, auf späten prüfen."""
    drawn = collect_pairs(name, sci, cache_dir=cache_dir, seed=seed,
                          progress=progress)
    if drawn is None:
        return None
    fit, test = split_by_year(drawn["samples"])
    # Ohne beide Hälften gibt es nichts zu prüfen, und ein Ergebnis auf
    # einer halben Trennung wäre schlimmer als keines.
    if not fit or not test:
        return {"name": name, "sci": sci, "n_fit": len(fit),
                "n_test": len(test), "usable": False}
    grid = grid_optimum(fit)
    fitted = grid["optimum"]
    result = {
        "name": name,
        "sci": sci,
        "usable": True,
        "n_fit": len(fit),
        "n_test": len(test),
        "fit_years": sorted({s["year"] for s in fit}),
        "test_years": sorted({s["year"] for s in test}),
        "optimum": fitted,
        # Das Band der wirklich besten Werte — der Bericht zeigt es, weil
        # ein Gipfel ohne seine Breite eine Nachkommastelle ohne Deckung
        # ist. Fehlte es hier, stürzte erst das Rendern ab, nach der
        # ganzen Rechnung (so geschehen am 2026-09-11).
        "best_set": grid["best_set"],
        "plateau": grid["plateau"],
        "at_edge": grid["at_edge"],
        "auc_fit": grid["auc_fit"],
        "auc_test_shared": paired_auc(score_pairs(test, OPTIMUM_C)),
        "auc_test_fitted": paired_auc(score_pairs(test, fitted)),
    }
    result["gain"] = result["auc_test_fitted"] - result["auc_test_shared"]
    result["ci"] = bootstrap_years(test, [OPTIMUM_C, fitted], seed=seed)
    return result


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


def read_season_curves(path=SEASON_CURVES_FILE):
    """Die ausgelieferten Saisonkurven — dieselbe Quelle wie die App.

    Gelesen statt neu geholt: Die Kurven sind ein ERZEUGTES Asset
    (`tool/season_curves.py`), und die Frage hier lautet, ob das, was in
    der App steht, mit dem zusammenpasst, was gemessen wurde. Ein
    frischer GBIF-Abruf beantwortete eine andere Frage.
    """
    text = open(repo_path(path), encoding="utf-8").read()
    out = {}
    for block in re.finditer(
            r"^  '([^']+)': SeasonCurve\((.*?)\n  \),", text, re.M | re.S):
        name, body = block.group(1), block.group(2)
        months = re.search(r"months: \[([^\]]+)\]", body)
        if not months:
            continue
        values = [int(v) for v in months.group(1).replace("\n", "").split(",")
                  if v.strip()]
        observations = re.search(r"observations: (\d+)", body)
        peak = re.search(r"peakSupport: (\d+)", body)
        out[name] = {
            "months": values,
            "observations": int(observations.group(1)) if observations else 0,
            "peak_support": int(peak.group(1)) if peak else 0,
        }
    return out


def season_centre(months):
    """Mittlerer Fruchtungsmonat auf dem KREIS, plus Schärfe.

    **Linear gemittelt ist das Unsinn**, und zwar gerade bei den Arten,
    auf die es ankommt: Der Austernseitling fruchtet im Dezember, und
    ein lineares Mittel über seine Zwölferreihe landet im Juni — genau
    zwischen seinen beiden Enden. Dezember liegt neben Januar, also
    werden die Monate als Winkel summiert.

    Die **Schärfe** ist die Länge des Summenvektors: 1 heißt „alles in
    einem Monat", 0 heißt „über das Jahr verteilt". Sie unterscheidet
    eine Art ohne Saison von einer mit — das Stockschwämmchen liegt bei
    0,29, alle anderen gemessenen Arten über 0,69.
    """
    total = sum(months)
    if total == 0:
        return None
    x = sum(v * math.cos(2 * math.pi * i / 12)
            for i, v in enumerate(months))
    y = sum(v * math.sin(2 * math.pi * i / 12)
            for i, v in enumerate(months))
    centre = (math.degrees(math.atan2(y, x)) / 30) % 12 + 1
    return {"centre": centre, "sharpness": math.hypot(x, y) / total}


# Unter dieser Schärfe hat eine Kurve keine Saison, über die sich
# korrelieren ließe. GESETZT, und zwar NACH dem Blick auf die Daten —
# das gehört dazugesagt. Die Lücke ist allerdings breit: 0,29 gegen
# 0,69, und dazwischen liegt keine einzige Art.
SEASON_SHARPNESS_MIN = 0.35


def season_rule(rows, curves):
    """Läuft das gemessene Fenster mit der Fruchtungszeit?

    Die registrierte Zusatzprüfung aus `docs/pilzampel-artenfenster.md`,
    und die Grundlage dafür, Arten OHNE eigene Messung einer Klasse
    zuzuordnen: Wenn die Saison das Fenster vorhersagt, muss nicht jede
    der 91 Arten einzeln validiert werden.

    Die Saisonkurven sind an keiner Anpassung beteiligt — sie kommen aus
    GBIF-Meldemonaten, die Fenster aus Wetterreihen. Das macht die
    Korrelation zu einer Aussage über zwei unabhängige Messungen.
    """
    points = []
    for row in rows:
        if not row.get("usable"):
            continue
        curve = curves.get(row["name"])
        if curve is None:
            continue
        centre = season_centre(curve["months"])
        if centre is None:
            continue
        points.append({
            "name": row["name"],
            "centre": centre["centre"],
            "sharpness": centre["sharpness"],
            "optimum": row["optimum"],
        })
    if len(points) < 3:
        return None
    sharp = [p for p in points if p["sharpness"] >= SEASON_SHARPNESS_MIN]
    return {
        "points": points,
        "rho_all": spearman([p["centre"] for p in points],
                            [p["optimum"] for p in points]),
        "n_all": len(points),
        "rho_sharp": spearman([p["centre"] for p in sharp],
                              [p["optimum"] for p in sharp]),
        "n_sharp": len(sharp),
        "dropped": [p["name"] for p in points
                    if p["sharpness"] < SEASON_SHARPNESS_MIN],
    }


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

# --- Mitgliedschaft in der Herbstklasse ------------------------------------
#
# Registriert am 2026-09-16 in `docs/pilzampel-herbstklasse-mitgliedschaft.md`,
# geschrieben und committet VOR der ersten Messung.
#
# **Die Frage ist nicht, ob ein besseres Fenster existiert, sondern wie
# weit das ausgelieferte trägt.** Zwei geschneiderte Fenster haben es
# nicht geschlagen (`herbst_holz`, `kalt`); was in beiden Berichten
# nebenbei steht, ist die AUC MIT den 13 °C — bei Hallimasch 0,766.
#
# Hier wird deshalb **nichts angepasst**. Gemessen wird allein, ob das
# ausgelieferte Fenster die Fundtage einer Art von ihren
# Vergleichstagen trennt. Das kostet null Freiheitsgrade, und genau
# deshalb ist Deutschland ein gültiger Prüfraum: Die 13 °C sind ein
# Literaturwert (Bielefeld) und wurden nie an unseren Daten bestimmt.

# Die Auswahlregel — MECHANISCH, damit der Kreis nicht nach dem ersten
# Blick auf die Zahlen wächst oder schrumpft.
MEMBERSHIP_MIN_RECORDS = 400
# Die Bedingung.
MEMBERSHIP_MIN_PAIRS = 400
MEMBERSHIP_MIN_AUC = 0.60


def membership_group(peak_month):
    """Die Gruppe einer Art — allein aus ihrem Saisongipfel.

    **Diese Zuordnung kennt kein Wetter.** Sie kommt aus GBIF-Monats-
    zahlen und steht fest, bevor ein einziger Wert von Open-Meteo
    geholt wird; sie ist die VORHERSAGE, gegen die gemessen wird.
    """
    if peak_month in (8, 9, 10):
        return "herbstnah"
    if peak_month in (11, 12, 1, 2, 3):
        return "kalt"
    return "anders"


# Die Vorhersage je Gruppe, registriert vor der Messung.
MEMBERSHIP_PREDICTION = {
    "herbstnah": True,
    "anders": False,
    "kalt": False,
}


def membership_status(name):
    """Trägt diese Art das Urteil mit — oder sind ihre Zahlen bekannt?

    Eine Regel an Zahlen zu prüfen, die man schon gesehen hat, beweist
    nichts. Die früher gemessenen Arten laufen mit, damit die Tabelle
    vollständig ist; das Urteil tragen die frischen.
    """
    if name in AMPEL_CLASSES["herbst"]["members"] or name == "Pfifferling":
        return "ausgeliefert"
    if name in MYCORRHIZAL or name in WOOD_DWELLERS or name in COLD_CANDIDATES:
        return "Zahlen bekannt"
    return "frisch"


def membership_candidates(con=None, path=SPECIES_FILE):
    """Der Kandidatenkreis aus dem LOKALEN Bestand.

    Über die API ginge das nicht in vertretbarer Zeit — 91 Arten mal
    eine Zählabfrage, und für den Saisongipfel je Art zwölf weitere.
    Der Bestand beantwortet beides in Millisekunden, und weil er einen
    DOI trägt, ist der Kreis reproduzierbar, obwohl GBIF weiterwächst.
    """
    own = con is None
    if own:
        con = gbif_local.connect()
    if con is None:
        return None
    try:
        rows = []
        for name, sci in sorted(read_species(path).items()):
            rank = "GENUS" if " " not in sci.strip() else "SPECIES"
            column = "genus" if rank == "GENUS" else "species"
            where = (f"{gbif_local.WHERE_USABLE} AND {column} = ? "
                     "AND day IS NOT NULL AND month IS NOT NULL "
                     f"AND year BETWEEN {FIRST_YEAR} AND {LAST_COMPLETE_YEAR} "
                     "AND (coordinateUncertaintyInMeters IS NULL "
                     "     OR coordinateUncertaintyInMeters <= ?)")
            found = con.execute(
                f"SELECT COUNT(*) FROM occ WHERE {where} "
                "AND countryCode = 'DE'",
                (sci, MAX_UNCERTAINTY_M)).fetchone()[0]
            if found < MEMBERSHIP_MIN_RECORDS:
                continue
            months = [0] * 12
            for month, number in con.execute(
                    f"SELECT month, COUNT(*) FROM occ WHERE {where} "
                    "GROUP BY month", (sci, MAX_UNCERTAINTY_M)):
                months[month - 1] = number
            peak = max(range(12), key=lambda i: months[i]) + 1
            rows.append({
                "name": name, "sci": sci, "records": found, "peak": peak,
                "group": membership_group(peak),
                "status": membership_status(name),
            })
    finally:
        if own:
            con.close()
    order = {"herbstnah": 0, "anders": 1, "kalt": 2}
    rows.sort(key=lambda r: (order[r["group"]], -r["records"]))
    return rows


def bootstrap_years_pairs(samples, pick, rounds=FIT_BOOTSTRAP_ROUNDS,
                          seed=42):
    """Vertrauensbereich einer gepaarten AUC, gezogen über JAHRE.

    Schwester von [bootstrap_years], nur für Paare, die nicht aus einem
    Optimum fallen — [pick] macht aus einer Probe ein Paar oder `None`.
    Gebraucht für die abstandsgleiche Kontrolle: Seit dem 2026-09-17 ist
    ihr Tor ihr Vertrauensbereich und nicht mehr eine feste Zahl
    (`docs/pilzampel-kontrolltoleranz.md`).

    **Über Jahre und nicht über Paare**, aus demselben Grund wie dort:
    Funde desselben Jahres sind einander ähnlicher, über Paare gezogen
    käme ein zu enger Bereich heraus — also eine Sicherheit, die es
    nicht gibt.
    """
    by_year = {}
    for sample in samples:
        pair = pick(sample)
        if pair is not None:
            by_year.setdefault(sample["year"], []).append(pair)
    years = sorted(by_year)
    if len(years) < 2:
        return None
    rng = random.Random(seed)
    draws = []
    for _ in range(rounds):
        picked = [rng.choice(years) for _ in years]
        draws.append(paired_auc([p for year in picked for p in by_year[year]]))
    draws.sort()
    return (draws[int(0.025 * len(draws))],
            draws[min(len(draws) - 1, int(0.975 * len(draws)))])


def mirror_pair(sample):
    """Die abstandsgleiche Kontrolle als Paar — `None`, wenn sie fehlt."""
    if sample.get("mirror") is None:
        return None
    return (ampel_score(*sample["control"]), ampel_score(*sample["mirror"]))


def membership_species(name, sci, cache_dir=None, seed=42, progress=True):
    """Trennt das AUSGELIEFERTE Fenster die Fundtage dieser Art?

    Kein Gitterlauf, keine Anpassung — ein Optimum, das von außen kommt.
    """
    drawn = collect_pairs(name, sci, cache_dir=cache_dir, seed=seed,
                          progress=progress)
    if drawn is None:
        return {"name": name, "usable": False, "why": "keine Funde"}
    samples = drawn["samples"]
    if not samples:
        return {"name": name, "usable": False, "why": "keine Paare"}
    mirrored = [(ampel_score(*s["control"]), ampel_score(*s["mirror"]))
                for s in samples if s["mirror"] is not None]
    placebo = [(ampel_score(*s["control"]), ampel_score(*s["placebo"]))
               for s in samples if s["placebo"] is not None]
    return {
        "name": name,
        "usable": True,
        "n": len(samples),
        "years": drawn["years"],
        "auc": paired_auc(score_pairs(samples, OPTIMUM_C)),
        "ci": bootstrap_years(samples, [OPTIMUM_C], seed=seed),
        "mirror_auc": paired_auc(mirrored),
        "mirror_n": len(mirrored),
        "mirror_ci": bootstrap_years_pairs(samples, mirror_pair, seed=seed),
        "placebo_auc": paired_auc(placebo),
        "placebo_n": len(placebo),
    }


def membership_control_clean(row):
    """Trägt die Ziehung dieser Art — gemessen an ihrem EIGENEN Bereich?

    **Warum keine feste Zahl mehr** (2026-09-17,
    `docs/pilzampel-kontrolltoleranz.md`): ±0,03 sind bei 2000 Paaren
    2,7 Standardfehler und bei 411 Paaren 1,2. Dieselbe Zahl ist also
    bei der kleinen Stichprobe ein ganz anderes Tor als bei der großen —
    im Lauf vom 2026-09-16 wurden 7 von 18 kleinen Stichproben verworfen
    und 0 von 16 großen, und alle acht Verwerfungen lagen innerhalb von
    2,5 SE um 0,50. Das war ein Filter auf die Stichprobengröße, kein
    Gültigkeitstest.

    Fehlt der Bereich (weniger als zwei Jahre), bleibt die feste Zahl
    als Rückfall: ganz ohne Prüfung durchzulassen wäre die falsche
    Richtung.
    """
    band = row.get("mirror_ci")
    if band is None:
        return control_clean(row["mirror_auc"], row.get("mirror_n"))
    return band[0] <= 0.5 <= band[1]


def membership_outcome(row):
    """Der Ausgang EINER Art: „erfüllt", „verfehlt" oder „offen".

    **„Offen" ist nicht „verfehlt".** Eine verzerrte Ziehung oder zu
    wenig Material heißt, dass nicht gemessen wurde; das als
    Durchfallen zu berichten wäre eine Aussage über Daten, die es nicht
    gibt. Dieselbe Trennung wie in `class_holdout_verdict`.
    """
    if not row.get("usable"):
        return "offen"
    if not membership_control_clean(row):
        return "offen"
    if row["n"] < MEMBERSHIP_MIN_PAIRS:
        return "offen"
    return "erfüllt" if row["auc"] >= MEMBERSHIP_MIN_AUC else "verfehlt"


def membership_verdict(rows, candidates):
    """Das Urteil über den REGISTRIERTEN Plan — nicht über einzelne Arten.

    Getragen wird es allein von den frischen Arten. Drei Ausgänge waren
    vorab festgelegt (`docs/pilzampel-herbstklasse-mitgliedschaft.md`):

    - **bestanden**: die Mehrheit der frischen herbstnahen Arten erfüllt
      die Bedingung, und keine Kontrastart tut es.
    - **generisch**: die Kontrastgruppen bestehen mit. Dann misst das
      Modell keine Temperaturnische, und die Klassenmaschinerie gehört
      zurückgebaut statt ausgebaut.
    - **eng**: die frischen herbstnahen Arten fallen breit durch. Dann
      ist `herbst` keine Gilde, und die Mitgliederliste bleibt.
    """
    by_name = {row["name"]: row for row in rows}
    groups = {}
    for candidate in candidates:
        if candidate["status"] != "frisch":
            continue
        row = by_name.get(candidate["name"])
        outcome = membership_outcome(row) if row else "offen"
        groups.setdefault(candidate["group"], []).append(
            (candidate["name"], outcome))

    autumn = groups.get("herbstnah", [])
    measured = [item for item in autumn if item[1] != "offen"]
    passed = [name for name, outcome in autumn if outcome == "erfüllt"]
    contrast = [item for group in ("anders", "kalt")
                for item in groups.get(group, [])]
    contrast_passed = [name for name, outcome in contrast
                       if outcome == "erfüllt"]
    contrast_measured = [item for item in contrast if item[1] != "offen"]

    # **Die Kontrastgruppe entscheidet zuerst.** Besteht sie mit, ist
    # die Frage nach der Mitgliedschaft gegenstandslos — dann trennt
    # das Modell nicht nach Fenster, und eine längere Mitgliederliste
    # wäre eine Erweiterung von etwas, das nichts behauptet.
    #
    # **Und wenn sie gar nicht messbar war, entscheidet sie ebenfalls —
    # nämlich gegen ein sauberes „bestanden"** (nachgetragen am
    # 2026-09-16, nachdem der erste Lauf genau darin lief). Die erste
    # Fassung prüfte den Gegen-Ausgang nur, wenn überhaupt eine
    # Kontrastart auswertbar war; fiel die ganze Gruppe wegen
    # verzerrter Ziehung aus, sagte sie stillschweigend „bestanden".
    # Das ist der Wächter, der genau dann schweigt, wenn er gebraucht
    # wird: Die Bestätigungsgruppe allein kann nicht zeigen, dass das
    # Fenster ETWAS AUSSCHLIESST — dafür ist die Kontrastgruppe da.
    # Die Änderung macht den Ausgang strenger, nie milder.
    if contrast_measured and len(contrast_passed) == len(contrast_measured):
        state = "generisch"
    elif not measured:
        state = "offen"
    elif len(passed) * 2 < len(measured):
        state = "eng"
    elif not contrast_measured:
        state = "flanke"
    else:
        state = "bestanden"
    return {
        "state": state,
        "passed": passed,
        "measured": [name for name, _ in measured],
        "autumn_open": [name for name, outcome in autumn
                        if outcome == "offen"],
        "contrast_passed": contrast_passed,
        "contrast_measured": [name for name, _ in contrast_measured],
    }



def render_membership_report(rows, candidates, verdict, stamp):
    """Der Bericht — Kontrastgruppe zuerst, weil sie zuerst entscheidet."""
    by_name = {row["name"]: row for row in rows}
    lines = [
        "# Wie weit trägt das eine Fenster? — die Messung",
        "",
        f"Stand: {stamp} · Erzeugt von `tool/ampel_validate.py "
        "--membership` · Prüfplan: "
        "`docs/pilzampel-herbstklasse-mitgliedschaft.md`",
        "",
        "Gemessen wird das **ausgelieferte** 13-°C-Fenster an Arten, für "
        "die es nie angepasst wurde — es ist ein Literaturwert. Es wird "
        "hier nichts angepasst; die Frage ist allein, wie weit es trägt.",
        "",
        f"Die Bedingung stand vor der Messung fest: gepaarte AUC ≥ "
        f"{MEMBERSHIP_MIN_AUC:.2f} bei mindestens {MEMBERSHIP_MIN_PAIRS} "
        "Paaren, abstandsgleiche Kontrolle innerhalb "
        "abstandsgleiche Kontrolle, deren über Jahre gezogener "
        "95-%-Bereich die 0,50 enthält.",
        "",
        "**Das Kontroll-Tor ist am 2026-09-17 umgestellt worden** — von "
        "festen ±0,03 auf den Vertrauensbereich, weil die feste Zahl ein "
        "Filter auf die Stichprobengröße war und keiner auf die "
        "Gültigkeit (`docs/pilzampel-kontrolltoleranz.md`). Die "
        "Umstellung war beim Registrieren die Änderung, die den Plan am "
        "wahrscheinlichsten beendet.",
        "",
    ]

    def table(group, title, note):
        picked = [c for c in candidates if c["group"] == group]
        if not picked:
            return
        lines.extend([f"## {title}", "", note, "",
                      "| Art | Paare | Jahre | AUC (13 °C) | 95 % | "
                      "Kontrolle | Kontrolle 95 % | Ausgang | Status |",
                      "|---|--:|--:|--:|---|--:|---|---|---|"])
        for candidate in picked:
            row = by_name.get(candidate["name"])
            if row is None or not row.get("usable"):
                why = (row or {}).get("why", "nicht gemessen")
                lines.append(f"| {candidate['name']} | — | — | — | — | — | "
                             f"— | offen ({why}) | {candidate['status']} |")
                continue
            outcome = membership_outcome(row)
            band = row["ci"].get(OPTIMUM_C) if isinstance(row["ci"], dict) \
                else None
            span = (f"[{band[0]:.3f}, {band[1]:.3f}]"
                    if band and len(band) == 2 else "—")
            mark = {"erfüllt": "**erfüllt**", "verfehlt": "verfehlt",
                    "offen": "offen"}[outcome]
            band_m = row.get("mirror_ci")
            span_m = (f"[{band_m[0]:.3f}, {band_m[1]:.3f}]"
                      if band_m else "—")
            lines.append(
                f"| {candidate['name']} | {row['n']} | {row['years']} | "
                f"{row['auc']:.3f} | {span} | {row['mirror_auc']:.3f} | "
                f"{span_m} | {mark} | {candidate['status']} |")
        lines.append("")

    table("anders", "Kontrastgruppe: Gipfel im Frühjahr und Sommer",
          "**Diese Gruppe entscheidet zuerst.** Besteht sie mit, trennt "
          "das Modell nicht nach Temperaturfenster — dann ist eine "
          "längere Mitgliederliste die Erweiterung von etwas, das nichts "
          "behauptet.")
    table("kalt", "Kontrastgruppe: Gipfel im Winter",
          "Dieselbe Rolle. Ihre Zahlen waren aus dem Kalttest bereits "
          "bekannt und tragen das Urteil deshalb nicht mit; sie stehen "
          "hier, damit die Tabelle vollständig ist.")
    table("herbstnah", "Die Bestätigungsgruppe: Gipfel im Herbst",
          "Vorhergesagt war: besteht. Das Urteil tragen die als "
          "„frisch“ gekennzeichneten Arten — bei den übrigen war die "
          "Zahl vorher bekannt.")

    state = verdict["state"]
    lines.extend(["## Der Ausgang", ""])
    passed, measured = len(verdict["passed"]), len(verdict["measured"])
    if state == "generisch":
        lines.append(
            "**Die Kontrastgruppe besteht mit.** Damit ist die Frage nach "
            "der Mitgliedschaft gegenstandslos: Das Modell trennt "
            "Fundtage von Vergleichstagen auch dort, wo sein Fenster "
            "nicht passen kann. Es misst also etwas Generisches — "
            "innerhalb der Saison, denn der Vergleichstag liegt 14–45 "
            "Tage neben dem Fund am selben Ort. Der registrierte Plan "
            "sieht dafür den Rückbau der Klassenmaschinerie vor, nicht "
            "ihren Ausbau.")
    elif state == "bestanden":
        lines.append(
            f"**Bestanden — {passed} von {measured} gemessenen frischen "
            "Arten der Bestätigungsgruppe erfüllen die Bedingung**, und "
            "die Kontrastgruppen tun es nicht. Das ausgelieferte Fenster "
            "trägt damit über die fünf heutigen Mitglieder hinaus.")
    elif state == "flanke":
        lines.append(
            f"**Kein sauberer Ausgang.** Die Bestätigungsgruppe trägt "
            f"deutlich — {passed} von {measured} gemessenen frischen "
            "Arten erfüllen die Bedingung. Aber **keine einzige frische "
            "Kontrastart war auswertbar**: Ihre Ziehungen sind verzerrt, "
            "dort wurde nichts gemessen. Damit fehlt genau die Hälfte "
            "des registrierten Plans — die Bestätigungsgruppe kann "
            "zeigen, dass das Fenster trägt, aber nicht, dass es etwas "
            "AUSSCHLIESST.")
        lines.append("")
        lines.append(
            "Das ist kein Formfehler. Eine Kontrastart mit hoher AUC und "
            "verzerrter Ziehung ist keine Entwarnung, sondern eine "
            "ungeprüfte Warnung: Wäre ihre Ziehung sauber und die Zahl "
            "bliebe, stünde hier der Gegen-Ausgang.")
        lines.append("")
        lines.append(
            "**Was dagegen spricht, und warum es den Ausgang trotzdem "
            "nicht trägt:** Die Winterarten fallen bei sauberer "
            "Kontrolle durch — das Fenster feuert dort also nicht. Das "
            "ist die Richtung, die ein echtes Temperaturfenster zeigen "
            "muss. Ihre Zahlen waren aber vor der Registrierung bekannt, "
            "und eine Regel an bekannten Zahlen zu prüfen beweist "
            "nichts; sie sind Kontext, kein Beleg.")
    elif state == "eng":
        lines.append(
            f"**Nicht bestanden — nur {passed} von {measured} gemessenen "
            "frischen Arten erfüllen die Bedingung.** `herbst` ist "
            "danach keine Gilde, sondern eine kleine Gruppe; die "
            "Mitgliederliste bleibt, wie sie ist.")
    else:
        lines.append(
            "**Offen** — es wurde zu wenig auswertbares Material "
            "gemessen, um den Plan zu entscheiden.")
    lines.append("")
    if verdict["contrast_measured"]:
        lines.append(
            "Kontrastgruppe: "
            f"{len(verdict['contrast_passed'])} von "
            f"{len(verdict['contrast_measured'])} gemessenen Arten "
            "erfüllen die Bedingung"
            + (f" ({', '.join(verdict['contrast_passed'])})"
               if verdict["contrast_passed"] else "")
            + ".")
        lines.append("")
    if verdict["autumn_open"]:
        lines.append(
            "**Nicht gemessen** (verzerrte Ziehung oder zu wenig "
            "Material): " + ", ".join(verdict["autumn_open"])
            + ". Das ist kein Durchfallen — dort wurde nichts gemessen.")
        lines.append("")
    lines.extend([
        "## Grenzen", "",
        "Gemessen wurde ausschließlich an GBIF. Die eigenen Funde und "
        "Leergänge der App bleiben draußen — sie sind der unabhängige "
        "Prüfstein aus #199.",
        "",
        "Eine bestandene Mitgliedschaft sagt „die Bedingungen sind "
        "günstig“, nicht „hier stehen Pilze“. Und sie sagt nichts "
        "darüber, ob ein eigenes Fenster für diese Art noch besser wäre.",
        "",
    ])
    return "\n".join(lines)

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

    # Wiederherstellung: Die k neuesten fallen weg, die Reihenfolge der
    # übrigen bleibt. Die ids stehen bewusst NICHT in Reihenfolge — eine
    # neue Meldung taucht mitten in der Seitenfolge auf, und wer nach
    # Position statt nach id abschneidet, erwischt die falschen.
    records = [{"key": k} for k in [50, 900, 10, 800, 20, 700]]
    assert [r["key"] for r in without_newest(records, 0)] == \
        [50, 900, 10, 800, 20, 700]
    assert [r["key"] for r in without_newest(records, 1)] == \
        [50, 10, 800, 20, 700], "die höchste id muss fallen, nicht die letzte"
    assert [r["key"] for r in without_newest(records, 3)] == [50, 10, 20]
    assert without_newest(records, 99) == []

    # **Der Bericht darf nicht nach Feldern greifen, die es nicht
    # gibt.** Am 2026-09-11 lief die Anpassung zehn Minuten und stürzte
    # dann beim Rendern ab (`KeyError: 'best_set'`), weil ein Feld in
    # `grid_optimum` ergänzt, aber nicht durch `fit_species`
    # durchgereicht worden war. Ein Lauf, der erst nach der Rechnung
    # scheitert, kostet die ganze Rechnung.
    # **BEIDE Seiten kommen aus dem Quelltext, und zwar aus dem
    # SYNTAXBAUM.** Zwei Anläufe waren vorher nötig, und beide Fehler
    # sind lehrreich:
    #
    # 1. Die gelieferten Felder standen als Liste von Hand da. Der Test
    #    verglich damit meine Liste mit dem Bericht statt den Code mit
    #    dem Bericht — und blieb bei der Gegenprobe grün.
    # 2. Danach las ein Muster die Zeilenanfänge. Es übersah jeden
    #    einzeiligen Dict (`{"name": …, "why": …}`) und meldete
    #    korrekten Code als kaputt. Ein Wächter, der bei heilem Code rot
    #    wird, wird abgeschaltet — und dann wacht er über gar nichts.
    def keys_written(func):
        """Alle Schlüssel, die diese Funktion je in ein Dict schreibt."""
        tree = ast.parse(textwrap.dedent(inspect.getsource(func)))
        keys = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Dict):
                keys |= {k.value for k in node.keys
                         if isinstance(k, ast.Constant)
                         and isinstance(k.value, str)}
            elif isinstance(node, ast.Subscript) and isinstance(
                    node.slice, ast.Constant) and isinstance(
                    node.slice.value, str):
                keys.add(node.slice.value)
        return keys

    def keys_read(func, holders):
        """Alle Schlüssel, die diese Funktion aus [holders] liest."""
        tree = ast.parse(textwrap.dedent(inspect.getsource(func)))
        keys = set()
        for node in ast.walk(tree):
            if (isinstance(node, ast.Subscript)
                    and isinstance(node.value, ast.Name)
                    and node.value.id in holders
                    and isinstance(node.slice, ast.Constant)
                    and isinstance(node.slice.value, str)):
                keys.add(node.slice.value)
            elif (isinstance(node, ast.Call)
                  and isinstance(node.func, ast.Attribute)
                  and node.func.attr == "get"
                  and isinstance(node.func.value, ast.Name)
                  and node.func.value.id in holders
                  and node.args
                  and isinstance(node.args[0], ast.Constant)):
                keys.add(node.args[0].value)
        return keys

    holders = {"row", "primary", "r", "prediction"}
    for report, producer in [(render_fit_report, fit_species),
                             (render_holdout_report, holdout_species),
                             (render_threshold_report, threshold_species)]:
        missing = keys_read(report, holders) - keys_written(producer)
        assert not missing, (
            f"{report.__name__} liest Felder, die {producer.__name__} nicht "
            f"liefert: {sorted(missing)}")
    assert "best_set" in keys_read(render_fit_report, holders), \
        "die Prüfung selbst muss etwas zu prüfen haben"
    assert "gap_both_ci" in keys_read(render_threshold_report, holders), \
        "die Prüfung selbst muss etwas zu prüfen haben"

    # --- Die Schwellen als Quantil (docs/pilzampel-schwellen.md) -----
    #
    # Gewichtete Quantile sind die Stelle, an der ein Fehler NICHT
    # auffällt: Eine Schwelle, die um ein paar Prozent danebenliegt,
    # liest sich in jedem Bericht plausibel.
    ladder = [float(i) for i in range(100)]
    flat = [1.0] * 100
    assert quantile_at(ladder, flat, 0.5) == 49.0
    assert quantile_at(ladder, flat, 0.8) == 79.0
    assert quantile_at(ladder, flat, 0.0) == 0.0
    assert quantile_at([], [], 0.5) is None
    # Hin und zurück — das Quantil des Quantils ist das Quantil.
    for q in (0.2, 0.5, 0.8, 0.95):
        back = rank_of(ladder, flat, quantile_at(ladder, flat, q))
        # Genauer als EINE Beobachtung kann ein empirisches Quantil
        # nicht sein — die Toleranz ist deshalb 1/n, keine Zierzahl.
        assert abs(back - q) <= 1.0 / len(ladder) + 1e-9, \
            f"Quantil {q} kommt als {back} zurück"

    # **Die Jahresbalance muss wirken.** Ein Jahr mit vielen Meldungen
    # darf die Schwelle nicht zu sich ziehen, sonst erbt sie den
    # Melde-Eifer statt das Wetter zu beschreiben. Gepflanzt: 90 trockene
    # Vergleichstage in einem Jahr, 10 nasse in einem zweiten.
    dry_day = ([0.0] * RAIN_WINDOW, [OPTIMUM_C] * TEMP_WINDOW)
    wet_day = ([10.0] * RAIN_WINDOW, [OPTIMUM_C] * TEMP_WINDOW)
    lopsided = ([{"year": 2001, "control": dry_day}] * 90
                + [{"year": 2002, "control": wet_day}] * 10)
    assert quantile_at(*control_scores(lopsided, OPTIMUM_C), 0.6) == 0.0
    assert quantile_at(*control_scores(lopsided, OPTIMUM_C, balanced=True),
                       0.6) == 1.0, \
        "jahresbalanciert muss das kleine Jahr dasselbe Gewicht haben"

    # **Das Urteil wird GERENDERT geprüft, nicht gedacht.** Zweimal hat
    # in diesem Werkzeug ein vorformulierter Schlusssatz etwas behauptet,
    # das die Zahlen daneben nicht hergaben — einmal „alles gleich, also
    # allgemeines Pilzwetter“ trotz erfüllter Vorhersage, einmal „der
    # Gewinn liegt in Feinheiten, die Stufen nicht abbilden können“ bei
    # einem Abstand, dessen Bereich die Null ausschließt. Verfehlte Latte
    # und fehlender Effekt sind zwei Ausgänge; wer sie zusammenwirft,
    # erzählt beim nächsten Lesen etwas Falsches.
    def planted(name, gap, ci):
        return {"name": name, "usable": True, "optimum": 13.0,
                "n_fit": 10, "n_test": 10,
                "rank_verhalten": 0.4, "rank_guenstig": 0.7,
                "rank_verhalten_even": 0.4, "rank_guenstig_even": 0.7,
                "rank_verhalten_later": SHIP_QUANTILE_VERHALTEN,
                "rank_guenstig_later": SHIP_QUANTILE_GUENSTIG,
                "verhalten_at": 0.2, "guenstig_at": 0.5,
                "own_later": ([i / 100 for i in range(100)],
                              [1.0] * 100),
                "klass": class_of(name),
                "class_later": ([i / 100 for i in range(100)],
                                [1.0] * 100),
                "ship_verhalten_ci": (0.45, 0.55),
                "ship_guenstig_ci": (0.75, 0.85),
                "gap_shipped": 0.0, "gap_window": 0.0, "gap_both": gap,
                "gap_both_ci": ci, "found_shipped": 0.2,
                "found_both": 0.2 + gap, "ctrl_shipped": 0.2,
                "ctrl_both": 0.2}

    species = THRESHOLD_PREDICTION_SPECIES
    bar = THRESHOLD_PREDICTION_MIN_GAP
    genommen = render_threshold_report(
        [planted(species, bar + 0.05, (bar, bar + 0.1))], "—")
    assert "**Ergebnis: bestätigt.**" in genommen
    verfehlt = render_threshold_report(
        [planted(species, bar - 0.02, (0.01, bar + 0.05))], "—")
    assert "Schwelle verfehlt — der Effekt ist aber da" in verfehlt, verfehlt
    assert "bestätigt.**" not in verfehlt, \
        "eine verfehlte Latte darf nicht als bestätigt durchgehen"
    keiner = render_threshold_report(
        [planted(species, bar - 0.02, (-0.05, bar))], "—")
    assert "**Ergebnis: NICHT bestätigt.**" in keiner
    assert "Effekt ist aber da" not in keiner, \
        "ohne Effekt darf der Bericht keinen behaupten"

    # **Die Auslieferungs-Quantile müssen aus den PRÜFJAHREN kommen.**
    # Nähme man die Anpassjahre, käme die Ampel um die gemessene Drift
    # zu großzügig heraus — und zwar lautlos, denn beide Zahlen sehen
    # gleich plausibel aus. Gepflanzt: Die beiden Zeitscheiben liegen
    # weit auseinander, das Ergebnis darf nur die spätere sein.
    drifted = [planted(name, 0.1, (0.05, 0.15)) | {
        "rank_verhalten_even": 0.40, "rank_guenstig_even": 0.70,
        "rank_verhalten_later": SHIP_QUANTILE_VERHALTEN,
        "rank_guenstig_later": SHIP_QUANTILE_GUENSTIG}
        for name in MYCORRHIZAL]
    assert deployment_quantiles(drifted) == (SHIP_QUANTILE_VERHALTEN,
                                             SHIP_QUANTILE_GUENSTIG), \
        "die Auslieferung muss auf den Prüfjahren kalibrieren"
    # Gerundet wird auf volle 5 %, wie überall hier.
    krumm = [row | {"rank_guenstig_later": SHIP_QUANTILE_GUENSTIG - 0.017}
             for row in drifted]
    assert deployment_quantiles(krumm)[1] == SHIP_QUANTILE_GUENSTIG, \
        "auf 5 % runden"
    assert deployment_quantiles([]) is None

    # **Und die Konstanten-Prüfung muss auch wirklich zuschlagen
    # können.** Die Zeilen oben leiten ihre Ränge AUS den Konstanten ab
    # — an ihnen kann sie nie scheitern, sie ist dort also kein Wächter,
    # sondern eine Tautologie. Gepflanzt wird deshalb eine gewanderte
    # Verteilung; genau dafür gibt es die Prüfung.
    gewandert = [row | {"rank_guenstig_later": SHIP_QUANTILE_GUENSTIG - 0.1}
                 for row in drifted]
    try:
        deployment_quantiles(gewandert)
    except SystemExit:
        pass
    else:
        raise AssertionError("eine gewanderte Verteilung muss auffallen, "
                             "sonst reicht das Werkzeug eine veraltete "
                             "Konstante weiter")

    # Die „Probe aufs Exempel" im Bericht muss wirklich aufgehen: Die
    # Quote an Vergleichstagen ist per Konstruktion 1 − Quantil, und
    # steht dort etwas anderes, ist die Rechnung kaputt.
    gezeigt = render_threshold_report(drifted, "—")
    assert "## Was ausgeliefert würde" in gezeigt
    assert f"**{_pct(SHIP_QUANTILE_GUENSTIG, 0)}** (günstig)" in gezeigt, \
        "das Auslieferungs-Quantil steht nicht im Bericht"
    # Die Probe: Ein auf das 80-%-Quantil gesetzter Schwellwert muss an
    # rund 20 % der Vergleichstage überschritten werden. „Rund" heißt
    # 1/n — genauer kann ein empirisches Quantil nicht sein.
    verteilung = drifted[0]["own_later"]
    quote = 1.0 - rank_of(*verteilung,
                          quantile_at(*verteilung, SHIP_QUANTILE_GUENSTIG))
    assert abs(quote - (1 - SHIP_QUANTILE_GUENSTIG)) \
        <= 1.0 / len(verteilung[0]) + 1e-9, quote
    # **Und die beiden Spalten müssen aus VERSCHIEDENEN Quantilen
    # kommen.** Stünde in „verhalten ab" das günstig-Quantil, wäre die
    # mittlere Stufe stillschweigend verschwunden — die Tabelle sähe
    # völlig unauffällig aus, denn beide Zahlen sind plausibel. Genau
    # diese Vertauschung ist bei der Gegenprobe durchgerutscht.
    erwartet = (f"| {quantile_at(*verteilung, SHIP_QUANTILE_VERHALTEN):.3f}"
                f" [0.450, 0.550] "
                f"| {quantile_at(*verteilung, SHIP_QUANTILE_GUENSTIG):.3f}"
                f" [0.750, 0.850] |")
    assert erwartet in gezeigt, \
        f"die Auslieferungs-Schwellen stehen nicht als {erwartet} da"

    # **Der zirkulare Monatsmittelwert.** Er ist der Grund, warum die
    # Korrelation Saison↔Fenster überhaupt trägt: Linear gemittelt
    # landet eine Dezemberart im Juni, und aus −0,83 wird −0,07.
    # Gepflanzt: alles im Januar, alles im Juli, und die Hälfte im
    # Dezember plus die Hälfte im Januar — deren Mitte MUSS der
    # Jahreswechsel sein, nicht der Juni.
    nur_januar = [100] + [0] * 11
    assert abs(season_centre(nur_januar)["centre"] - 1.0) < 1e-9
    assert season_centre(nur_januar)["sharpness"] == 1.0
    nur_juli = [0] * 6 + [100] + [0] * 5
    assert abs(season_centre(nur_juli)["centre"] - 7.0) < 1e-9
    jahreswechsel = [50] + [0] * 10 + [50]
    mitte = season_centre(jahreswechsel)["centre"]
    assert mitte > 12.4 or mitte < 0.6, \
        f"Dezember und Januar müssen sich am Jahreswechsel treffen, " \
        f"nicht im Juni — gemessen {mitte:.1f}"
    # Gleichverteilt: keine Saison, Schärfe ~0.
    assert season_centre([100] * 12)["sharpness"] < 1e-9
    assert season_centre([0] * 12) is None

    # Und der Leser gegen das echte Asset.
    curves = read_season_curves()
    assert len(curves) > 80, f"nur {len(curves)} Kurven gelesen"
    assert "Steinpilz" in curves and len(curves["Steinpilz"]["months"]) == 12
    assert curves["Steinpilz"]["observations"] > 200

    # **Der Wächter muss ALLE Abweichungen nennen, nicht die erste.**
    # Ein geändertes Klassenfenster verschiebt auch die Schwelle
    # darunter — es gibt selten nur eine. Bricht die Prüfung beim ersten
    # Fund ab, kostet jede weitere einen zehnminütigen Lauf, und nach
    # dem zweiten Mal schaltet man sie ab.
    try:
        verify_class_constants({
            "herbst": {"verhalten": 0.0, "guenstig": 0.0,
                       "optimum_measured": 99.0},
            "sommer": {"verhalten": 0.0, "guenstig": 0.0},
        })
    except SystemExit as stop:
        gemeldet = str(stop)
        for erwartet in ("herbst.verhalten", "herbst.guenstig",
                         "herbst.optimum", "sommer.verhalten",
                         "sommer.guenstig"):
            assert erwartet in gemeldet, \
                f"{erwartet} fehlt in der Meldung:\n{gemeldet}"
    else:
        raise AssertionError("fünf falsche Konstanten müssen auffallen")

    # **Auf einer anderen Basis darf derselbe Fund NICHT abbrechen.**
    # Sonst wäre jede Messung auf einem gepinnten Datensatz blockiert —
    # genau das ist am 2026-09-17 im Referenzlauf passiert.
    try:
        use_dataset("pinned")
        with contextlib.redirect_stderr(io.StringIO()) as _quiet:
            gemeldet = verify_class_constants({
                "herbst": {"verhalten": 0.0, "guenstig": 0.0,
                           "optimum_measured": 99.0},
                "sommer": {"verhalten": 0.0, "guenstig": 0.0},
            })
        # Die Meldung muss den Grund nennen, sonst liest sie sich wie ein
        # verschluckter Fehler.
        assert "pinned" in _quiet.getvalue(), _quiet.getvalue()
        assert "Nachmessung" in _quiet.getvalue()
        assert len(gemeldet) == 5, gemeldet
        assert any("herbst.optimum" in f for f in gemeldet), gemeldet
    finally:
        use_dataset(ampel_basis.DEFAULT_DATASET)
    # Und auf der Vorgabe bricht er weiter ab — der Wächter ist nicht
    # abgeschaltet, nur auf das eingeschränkt, was er beantworten kann.
    try:
        verify_class_constants({"herbst": {"verhalten": 0.0,
                                           "guenstig": 0.0}})
    except SystemExit:
        pass
    else:
        raise AssertionError("auf der Vorgabe muss er weiter abbrechen")

    # **Und der Erfolgsfall.** Hier stand nach einem Umbau ein verirrtes
    # `return out`, und der Selbsttest hat es nicht bemerkt, weil er nur
    # den Fehlerpfad ging: Ein Wächter, der prüft, dass FALSCHE
    # Konstanten auffallen, aber nicht, dass richtige durchgehen, stürzt
    # bei heilem Code ab — nach zehn Minuten Rechnen.
    verify_class_constants({
        key: {"verhalten": klass["verhalten"],
              "guenstig": klass["guenstig"],
              "optimum_measured": klass["optimum"]}
        for key, klass in AMPEL_CLASSES.items() if klass.get("dart")
    })

    # **Das Fenster einer Klasse: jede Art eine Stimme.** Gepflanzt: eine
    # große Art bei 11 °C und eine kleine bei 15 °C. Der Median muss 13
    # sein; zählte die Stichprobengröße mit, käme 11 heraus — und das
    # wäre die Sorte Fehler, die in einer Tabelle plausibler Zahlen
    # niemandem auffällt.
    def voter(name, optimum):
        return {"name": name, "usable": True, "klass": "herbst",
                "optimum": optimum}

    assert class_optimum(
        [voter("Steinpilz", 11.0), voter("Herbsttrompete", 15.0)],
        "herbst") == 13.0
    assert class_optimum([], "herbst") is None
    # Eine Art, die einer ANDEREN Klasse gehört, stimmt nicht mit.
    assert class_optimum(
        [voter("Steinpilz", 11.0),
         {"name": "Pfifferling", "usable": True, "klass": "sommer",
          "optimum": 17.5}],
        "herbst") == 11.0

    # **Die Klassenschwelle darf nicht der größten Art gehören.** Der
    # Steinpilz bringt 2000 Paare mit, die Herbsttrompete 288 —
    # ungewichtet wäre „Herbstklasse" nur ein anderer Name für
    # „Steinpilz". Gepflanzt: eine große trockene und eine kleine nasse
    # Art in derselben Klasse.
    assert class_of("Pfifferling") == "sommer"
    assert class_of("Steinpilz") == "herbst"
    assert class_of("Omas Lieblingspilz") is None

    def member(name, value, count):
        return {"name": name, "usable": True, "klass": "herbst",
                "optimum": AMPEL_CLASSES["herbst"]["optimum"],
                "class_later": ([value] * count, [1.0] * count)}

    ungleich = [member("Steinpilz", 0.0, 900),
                member("Herbsttrompete", 1.0, 100)]
    got = class_thresholds(ungleich, (0.5, 0.6), verify=False)["herbst"]
    assert got["guenstig"] == 1.0, \
        "die kleine Art muss dasselbe Gewicht haben wie die große"
    assert sorted(got["members"]) == ["Herbsttrompete", "Steinpilz"]
    # Ohne Klasse fällt eine Art heraus, statt still in eine zu rutschen.
    assert class_thresholds(
        [{"name": "X", "usable": True, "klass": None,
          "class_later": None}], (0.5, 0.8), verify=False) == {}

    # **Und die Prüfung der Klassenkonstanten muss zuschlagen können.**
    # Diese vier Zahlen wandern in den Modellkern der App; löst sich eine
    # still von ihrer Quelle, rechnet die App etwas anderes als die
    # Validierung — der teuerste stille Fehler, den dieses Projekt hier
    # haben kann.
    try:
        class_thresholds(ungleich, (0.5, 0.6))
    except SystemExit:
        pass
    else:
        raise AssertionError("eine gewanderte Klassenschwelle muss "
                             "auffallen")

    # Und dasselbe für Vorhersage 1: Das Band muss wirklich entscheiden.
    inside = statistics.mean(QUANTILE_BAND_GUENSTIG)
    drin = render_threshold_report(
        [planted(MYCORRHIZAL[0], 0.1, (0.05, 0.15)) | {
            "rank_guenstig_even": inside,
            "rank_verhalten_even": statistics.mean(
                QUANTILE_BAND_VERHALTEN)}], "—")
    assert "**Ergebnis: bestätigt.** Die Quantil-Fassung" in drin
    draussen = render_threshold_report(
        [planted(MYCORRHIZAL[0], 0.1, (0.05, 0.15)) | {
            "rank_guenstig_even": QUANTILE_BAND_GUENSTIG[0] - 0.05}], "—")
    assert "Der Median liegt unter dem registrierten Band" in draussen

    # `level_with` muss mit den ausgelieferten Schwellen exakt das tun,
    # was `ampel_level` tut — sonst vergliche der Bericht zwei Modelle,
    # die sich schon vor der Schwelle unterscheiden.
    for score in (0.0, 0.19, 0.2, 0.21, 0.49, 0.5, 0.51, 1.0):
        assert level_with(score, VERHALTEN_ABOVE,
                          GUENSTIG_ABOVE) == ampel_level(score), score

    # **Die Spiegel-Regel, zum ersten Mal geprüft.** Beide Dateiköpfe
    # behaupten seit jeher, dieses Werkzeug rechne Zahl für Zahl
    # dasselbe wie `ampel_model.dart` — und niemand hat es je
    # nachgerechnet. Eine Konstante, die nur in einer der beiden Dateien
    # geändert wird, macht die Validierung zur Aussage über ein Modell,
    # das die App nicht rechnet. Genau das ist der teuerste stille
    # Fehler, den dieses Projekt hier haben kann.
    dart = open(repo_path(AMPEL_MODEL_FILE), encoding="utf-8").read()
    spiegel = {
        "ampelRainWindow": RAIN_WINDOW,
        "ampelTempWindow": TEMP_WINDOW,
        "ampelOptimumC": OPTIMUM_C,
        "ampelTempSigma": TEMP_SIGMA,
        "ampelRainSaturationMm": RAIN_SATURATION_MM,
    }
    for const, here in spiegel.items():
        found = re.search(rf"const {const} = ([\d.]+);", dart)
        assert found, f"{const} steht nicht mehr in {AMPEL_MODEL_FILE}"
        there = float(found.group(1))
        assert there == float(here), (
            f"Spiegel gebrochen: {const} ist in Dart {there}, hier {here}. "
            f"Die Validierung gälte dann einem Modell, das die App nicht "
            f"rechnet.")

    # **Die Klassentabelle ist die neue Nahtstelle** — und damit die
    # Stelle, an der App und Validierung ab 1.137.0 auseinanderlaufen
    # können, ohne dass irgendwo etwas rot wird. Drei Zahlen je Klasse
    # plus die Mitgliederliste; geprüft wird jede einzeln gegen den
    # Dart-Quelltext.
    for key, klass in AMPEL_CLASSES.items():
        dart_name = klass.get("dart")
        if not dart_name:
            # Unbestätigte Klassen stehen absichtlich NICHT in Dart.
            assert dart_name is None and not klass["confirmed"], key
            assert f"const {key}" not in dart, (
                f"Klasse {key} hat keinen Hold-out, steht aber in "
                f"{AMPEL_MODEL_FILE}")
            continue
        block = re.search(
            rf"const {dart_name} = \((.*?)\);", dart, re.S)
        assert block, f"{dart_name} steht nicht in {AMPEL_MODEL_FILE}"
        body = block.group(1)
        # Der Name zuerst, und als Zeichenkette: Er steht im Blatt und in
        # der Legende, und eine Klasse, die dort anders heißt als hier,
        # macht jeden Bericht unlesbar.
        found = re.search(r"name: '([^']*)',", body)
        assert found, f"{dart_name} hat keinen Namen"
        assert found.group(1) == klass["label"], (
            f"Spiegel gebrochen: {dart_name}.name ist in Dart "
            f"'{found.group(1)}', hier '{klass['label']}'")
        for field, here in [("optimumC", klass["optimum"]),
                            ("verhaltenAbove", klass["verhalten"]),
                            ("guenstigAbove", klass["guenstig"])]:
            found = re.search(rf"{field}: ([\w.-]+),", body)
            assert found, f"{dart_name} hat kein {field}"
            raw = found.group(1)
            # `optimumC: ampelOptimumC` ist erlaubt — die Gilde und die
            # Herbstklasse sollen NICHT zwei Zahlen sein, die man
            # getrennt ändern kann.
            there = OPTIMUM_C if raw == "ampelOptimumC" else float(raw)
            assert there == float(here), (
                f"Spiegel gebrochen: {dart_name}.{field} ist in Dart "
                f"{there}, hier {here}. Die App zeigte dann Stufen, die "
                f"die Validierung nie gemessen hat.")

    # **Und die Mitgliederliste in beide Richtungen.** Eine Art, die in
    # Dart einer Klasse zugeordnet ist, aber im Werkzeug nicht, bekäme
    # eine Ampel, für die nie jemand eine Zahl gerechnet hat — genau die
    # Sorte Eintrag, die sich später nicht mehr begründen lässt.
    block = re.search(
        r"const ampelSpeciesClass = <String, String>\{(.*?)\};", dart, re.S)
    assert block, f"ampelSpeciesClass steht nicht in {AMPEL_MODEL_FILE}"
    in_dart = dict(re.findall(r"'([^']+)': '([^']+)'", block.group(1)))
    in_tool = {name: key for key, klass in AMPEL_CLASSES.items()
               if klass.get("dart")
               for name in klass["members"]}
    assert in_dart == in_tool, (
        f"Spiegel gebrochen: ampelSpeciesClass ist in Dart {in_dart}, "
        f"hier {in_tool}")

    # **Der Schlusssatz der Arten-Kontrolle wird gerendert, nicht
    # geschrieben** — und genau dort hat eine implizite
    # Zeichenketten-Verkettung den Satz zerlegt. Ein Bericht, den niemand
    # nachliest, trägt so etwas jahrelang.
    fake_wood = [{"name": "Hallimasch", "n": 1953, "auc": 0.749, "p": 0.0005,
                  "placebo_auc": 0.497, "placebo_n": 1900, "mirror_auc": 0.511,
                  "mirror_n": 1914, "years": 20, "partial_years": [],
                  "skipped": 0, "median_found": 0.3, "median_control": 0.2,
                  "sci": "Armillaria"},
                 {"name": "Stockschwämmchen", "n": 1277, "auc": 0.756,
                  "p": 0.0005, "placebo_auc": 0.453, "placebo_n": 1200,
                  "mirror_auc": 0.479, "mirror_n": 1231, "years": 20,
                  "partial_years": [], "skipped": 0, "median_found": 0.3,
                  "median_control": 0.2, "sci": "Kuehneromyces mutabilis"}]
    rendered = render_report([], fake_wood, [], "2026-09-12")
    assert "Hallimasch 0.749, Stockschwämmchen 0.756" in rendered, \
        "der Schlusssatz der Arten-Kontrolle ist zerlegt"
    assert "2 von 2 Holzbewohnern" in rendered

    # --- Anpassung je Art (docs/pilzampel-artenfenster.md) ---
    #
    # Ein gepflanztes Optimum muss wiedergefunden werden. Die
    # Vergleichstage liegen dafür auf BEIDEN Seiten (1 °C und 13 °C) —
    # lägen sie nur auf einer, gewänne jedes Optimum jenseits davon
    # genauso, und der Gitterlauf liefe an den Rand statt auf den Gipfel.
    wet26 = [6.0] * RAIN_WINDOW
    planted = []
    for i in range(40):
        # Der Abstand WÄCHST, und die Seite wechselt: Läge jeder
        # Vergleichstag gleich weit weg, wäre jedes Optimum zwischen den
        # beiden Seiten gleich gut, und „wiedergefunden" hieße nur „im
        # Band gelandet". Der engste Abstand (±2 K) schnürt das Band auf
        # 6,5…7,5 zusammen.
        distance = 2 + (i % 10)
        offset = -distance if i % 2 else distance
        planted.append({
            "year": 2010 + (i % 12),
            "found": (wet26, [7.0] * TEMP_WINDOW),
            "control": (wet26, [7.0 + offset] * TEMP_WINDOW),
            "placebo": None,
        })
    found = grid_optimum(planted)
    assert abs(found["optimum"] - 7.0) < 0.6, \
        f"gepflanztes Optimum nicht wiedergefunden: {found['optimum']}"
    assert not found["at_edge"]
    assert found["plateau"][1] - found["plateau"][0] <= 3.0, \
        "ein breites Plateau darf nicht als scharfer Gipfel durchgehen"

    # Und der Gegenfall: Liegt die Wahrheit außerhalb des Gitters, muss
    # das GEMELDET werden. Die Glocke ist dort keine Glocke mehr, sondern
    # eine Gerade — „je kälter, desto besser" ist keine Optimumsangabe.
    outside = [{
        "year": 2010 + i,
        "found": (wet26, [-8.0] * TEMP_WINDOW),
        "control": (wet26, [14.0] * TEMP_WINDOW),
        "placebo": None,
    } for i in range(12)]
    assert grid_optimum(outside)["at_edge"], \
        "ein Gipfel am Gitterrand muss als solcher gemeldet werden"
    assert grid_optimum([]) is None

    # Die Trennlinie: kein Jahr auf beiden Seiten, und beide Seiten
    # nicht leer.
    mixed_years = [{"year": y, "found": (wet26, [10.0] * TEMP_WINDOW),
                    "control": (wet26, [10.0] * TEMP_WINDOW),
                    "placebo": None}
                   for y in range(2006, LAST_COMPLETE_YEAR + 1)]
    fit_part, test_part = split_by_year(mixed_years)
    assert fit_part and test_part, "beide Seiten müssen belegt sein"
    assert not ({s["year"] for s in fit_part} & {s["year"] for s in test_part}), \
        "ein Jahr steht auf beiden Seiten der Trennlinie"
    assert max(s["year"] for s in fit_part) <= FIT_UNTIL_YEAR
    assert min(s["year"] for s in test_part) > FIT_UNTIL_YEAR

    # Der Bootstrap braucht mehrere Jahre — bei einem einzigen gäbe es
    # nichts zu ziehen, und ein Bereich aus einer Ziehung wäre erfunden.
    one_year = [dict(sample, year=2020) for sample in planted]
    assert bootstrap_years(one_year, [13.0]) is None
    spread = bootstrap_years(planted, [13.0, 7.0], rounds=50)
    assert spread is not None and "difference" in spread
    low, high = spread["difference"]
    assert low <= high

    # Das Optimum ist ein PARAMETER und ändert die Vorgabe nicht — die
    # Spiegel-Regel zu ampel_model.dart hängt daran.
    assert temperature_factor([13.0] * TEMP_WINDOW) == \
        temperature_factor([13.0] * TEMP_WINDOW, OPTIMUM_C)
    assert temperature_factor([7.0] * TEMP_WINDOW, 7.0) == 1.0

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
    # Die Vorgabe der Archiv-API ist der öffentliche Dienst. Stünde hier
    # eine eigene Instanz, liefen Messungen still auf einem Rechner, den
    # niemand sonst hat — und der Bericht sähe genauso aus.
    assert OPEN_METEO_DEFAULT.startswith("https://archive-api.open-meteo.com")
    assert OPEN_METEO == OPEN_METEO_DEFAULT, \
        "der Selbsttest läuft mit der Vorgabe, nicht mit --api"

    # --- Design B: das Maß, netzfrei ----------------------------------
    #
    # Gepflanzt: Ein Fund schlägt drei von vier Kontrolljahren, der
    # zweite keines. Das Mittel muss 0,375 sein.
    def _b(jahr, found_c, controls):
        return {"year": jahr, "found": ([1.0] * 26, [found_c] * 20),
                "controls": [([1.0] * 26, [c] * 20) for c in controls],
                "control_years": [jahr - 2, jahr - 1, jahr + 1, jahr + 2],
                "placebo_found": None, "placebo_controls": None}
    # 13 °C trifft das Optimum; 30 °C liegt weit daneben.
    gut = _b(2015, 13.0, [30.0, 30.0, 30.0, 13.0])     # 3 geschlagen, 1 gleich
    schlecht = _b(2016, 30.0, [13.0, 13.0, 13.0, 13.0])
    wert, n = score_b([gut, schlecht])
    assert n == 2 and abs(wert - 0.4375) < 1e-9, (wert, n)

    # `limit` schneidet auf die ersten k — für k = 1 ist es der Beitrag
    # eines einzelnen Paares und damit dieselbe Größe wie in Design A.
    assert score_b([gut], limit=1)[0] == 1.0
    assert score_b([schlecht], limit=1)[0] == 0.0

    # Der Richtungs-Split trennt frühere von späteren Kontrolljahren.
    assert score_b([gut], side="frueher")[0] == 1.0      # 2013, 2014
    assert score_b([gut], side="spaeter")[0] == 0.75     # 2016 ja, 2017 gleich
    # Eine Art ohne Kontrolljahr auf einer Seite liefert dort nichts,
    # statt eine Null beizusteuern.
    einseitig = dict(gut, control_years=[2013, 2014, 2013, 2014])
    assert score_b([einseitig], side="spaeter") == (None, 0)

    # Das Placebo greift nur, wo es gezogen wurde.
    assert placebo_b([gut]) == (None, 0)
    mit = dict(gut, placebo_found=([1.0] * 26, [13.0] * 20),
               placebo_controls=[([1.0] * 26, [30.0] * 20)])
    assert placebo_b([mit]) == (1.0, 1)

    # **Ein Zeitraum aus einem Schaltjahr passt nicht in jedes andere.**
    # Index 365 existiert nur in Schaltjahren; ungeklemmt wird daraus
    # das Datum „JJJJ-13-01" und Open-Meteo antwortet mit einem 400.
    assert clamp_span((10, 365), 2020) == (10, 365)      # Schaltjahr
    assert clamp_span((10, 365), 2021) == (10, 364)      # keines
    assert clamp_span((10, 300), 2021) == (10, 300)      # nichts zu tun
    assert _date_from_index(2020, 365) == "2020-12-31"
    assert _date_from_index(2021, 364) == "2021-12-31"
    # Und der Beweis, dass es ohne Klemmen schiefgeht:
    assert _date_from_index(2021, 365).startswith("2021-13"), \
        "ohne Klemmen entsteht ein Monat 13 — genau der stille 400er"

    # **`select_finds` wird netzfrei durch BEIDE Zweige geschickt.**
    # Der Stichproben-Zweig laeuft erst ab SAMPLE_PER_SPECIES Meldungen,
    # und genau dort stand eine Zeile mit einer Variablen, die es in
    # dieser Funktion gar nicht gibt. Der Selbsttest lief gruen, der
    # Probelauf lief gruen (die Art hatte zu wenige Meldungen), und der
    # Volllauf brach bei der ersten haeufigen Art ab. Ein Zweig, der nur
    # bei grossen Eingaben genommen wird, braucht eine grosse Eingabe.
    _echte_finds = globals()["fetch_finds"]
    try:
        _viele = [{"lat": 51.0 + i * 1e-4, "lon": 10.0, "year": 2010,
                   "month": 9, "day": 1 + (i % 28), "recordedBy": f"M{i}"}
                  for i in range(SAMPLE_PER_SPECIES + 500)]
        globals()["fetch_finds"] = lambda sci, **kw: _viele
        _gezogen, _info = select_finds("x", None, 42, False)
        assert len(_gezogen) == SAMPLE_PER_SPECIES, len(_gezogen)
        assert _info["available"] == SAMPLE_PER_SPECIES + 500
        # Und der kleine Zweig: weniger als die Grenze bleibt unangetastet.
        globals()["fetch_finds"] = lambda sci, **kw: _viele[:10]
        _gezogen, _info = select_finds("x", None, 42, False)
        assert len(_gezogen) == 10, len(_gezogen)
        # Leere Liste ergibt None statt eines Absturzes weiter unten.
        globals()["fetch_finds"] = lambda sci, **kw: []
        assert select_finds("x", None, 42, False) == (None, {})
    finally:
        globals()["fetch_finds"] = _echte_finds

    # --- Design B: das Mass, netzfrei ----------------------------------
    #
    # Gepflanzt: Ein Fund schlaegt drei von vier Kontrolljahren und steht
    # beim vierten gleich; der zweite schlaegt keines.
    def _b(jahr, found_c, controls):
        return {"year": jahr, "found": ([1.0] * 26, [found_c] * 20),
                "controls": [([1.0] * 26, [c] * 20) for c in controls],
                "control_years": [jahr - 2, jahr - 1, jahr + 1, jahr + 2],
                "placebo_found": None, "placebo_controls": None}
    gut = _b(2015, 13.0, [30.0, 30.0, 30.0, 13.0])
    schlecht = _b(2016, 30.0, [13.0, 13.0, 13.0, 13.0])
    wert, n = score_b([gut, schlecht])
    assert n == 2 and abs(wert - 0.4375) < 1e-9, (wert, n)

    # `limit` schneidet auf die ersten k — fuer k = 1 ist es der Beitrag
    # eines einzelnen Paares und damit dieselbe Groesse wie in Design A.
    assert score_b([gut], limit=1)[0] == 1.0
    assert score_b([schlecht], limit=1)[0] == 0.0

    # Der Richtungs-Split trennt fruehere von spaeteren Kontrolljahren.
    assert score_b([gut], side="frueher")[0] == 1.0
    assert score_b([gut], side="spaeter")[0] == 0.75
    # Eine Seite ohne Kontrolljahr liefert dort nichts, statt eine Null
    # beizusteuern — sonst saehe „fehlt" aus wie „schlecht".
    einseitig = dict(gut, control_years=[2013, 2014, 2013, 2014])
    assert score_b([einseitig], side="spaeter") == (None, 0)

    # Das Placebo greift nur, wo es gezogen wurde.
    assert placebo_b([gut]) == (None, 0)
    mit = dict(gut, placebo_found=([1.0] * 26, [13.0] * 20),
               placebo_controls=[([1.0] * 26, [30.0] * 20)])
    assert placebo_b([mit]) == (1.0, 1)

    # Und `collect_pairs` muss eine fertige Liste unveraendert uebernehmen,
    # sonst laufen A und B doch auf verschiedenen Stichproben.
    _quelle = inspect.getsource(collect_pairs)
    assert "if DEDUPE and not vorgegeben:" in _quelle, \
        "eine hereingereichte Liste wuerde noch einmal entdoppelt"
    assert "if len(finds) > SAMPLE_PER_SPECIES and not vorgegeben:" in _quelle, \
        "eine hereingereichte Liste wuerde noch einmal beprobt"

    # --- A4: der lokale Bestand wird nicht mehr beschnitten -----------
    #
    # Netzfrei prüfbar ist nur die Absicht im Quelltext — die Datenbank
    # liegt nicht in CI. Das ist als Wächter dünn, aber es fängt genau
    # den Fall, um den es geht: dass jemand die Grenze wieder einbaut,
    # weil sie beim Netzweg sinnvoll ist.
    _quelle = inspect.getsource(_finds_from_local)
    assert "limit = None" in _quelle, \
        "der lokale Bestand darf nicht nach gbifID beschnitten werden"
    assert "LIMIT ?" in _quelle, \
        "der Netzweg braucht seine Grenze weiterhin"

    # --- A2: die Kontroll-Toleranz hängt an der Paarzahl --------------
    #
    # Die feste ±0,03 war ein Filter auf die Stichprobengröße. Der Test
    # nagelt beide Richtungen fest: dieselbe Abweichung muss bei kleiner
    # Paarzahl durchgehen und bei großer auffallen.
    assert abs(control_tolerance(2000) - 0.0224) < 1e-3, control_tolerance(2000)
    assert abs(control_tolerance(538) - 0.0431) < 1e-3, control_tolerance(538)
    assert control_tolerance(2000) < control_tolerance(538), \
        "mehr Paare müssen eine ENGERE Grenze geben"
    assert control_tolerance(0) == PLACEBO_TOLERANCE
    assert control_tolerance(None) == PLACEBO_TOLERANCE
    # 0,470 — genau der Wert der Aufwands-Referenz aus Phase 1.3.
    assert control_clean(0.470, 538), "bei 538 Paaren sind das 1,4 SE"
    assert not control_clean(0.470, 2000), "bei 2000 Paaren sind das 2,7 SE"
    # Und die alte feste Grenze hätte beides gleich behandelt — genau das
    # war der Fehler.
    assert (abs(0.470 - 0.5) > PLACEBO_TOLERANCE) is True
    # Der Bericht muss die verwendete Grenze NENNEN, nicht nur anwenden.
    text = _tolerance_text(538)
    assert "0.043" in text and "538" in text and "0.03" in text, text
    assert "±0.03" in _tolerance_text(0)

    # **Ein Fenster mit Lücke ist kein Fenster.** Die beiden Faktoren
    # verrechnen fehlende Werte still (Regen als 0 mm, Temperatur als
    # „maximal daneben“) — beides sind Zahlen, die niemand gemessen hat.
    _heil = {"first": 0, "rain": [1.0] * 40, "temp": [10.0] * 40}
    assert window_before(_heil, 30, 26)[0] is not None
    _loch_regen = {"first": 0, "rain": [1.0] * 20 + [None] + [1.0] * 19,
                   "temp": [10.0] * 40}
    assert window_before(_loch_regen, 30, 26) == (None, None), \
        "Regen-Lücke käme als erfundene Trockenheit durch"
    _loch_temp = {"first": 0, "rain": [1.0] * 40,
                  "temp": [10.0] * 20 + [None] + [10.0] * 19}
    assert window_before(_loch_temp, 30, 26) == (None, None), \
        "Temperatur-Lücke käme durch"
    # Eine Lücke AUSSERHALB des Fensters darf es nicht ungültig machen.
    _loch_daneben = {"first": 0, "rain": [None] + [1.0] * 39,
                     "temp": [10.0] * 40}
    assert window_before(_loch_daneben, 30, 26)[0] is not None
    # Die Bremse gilt dem oeffentlichen Dienst, nicht der eigenen Instanz.
    assert _politeness() == 2.0, "der oeffentliche Dienst wird geflutet"

    # --- Keine Zuweisung in `main` darf eine Funktion verdecken --------
    #
    # Genau das ist am 2026-09-17 passiert: `verdict = membership_verdict(…)`
    # im `--membership`-Zweig machte den modulweiten `verdict(auc)` in
    # GANZ `main()` zu einer lokalen Variablen. Python entscheidet das je
    # Funktion und nicht je Zweig — der Standardlauf stürzte deshalb mit
    # `UnboundLocalError` ab, und zwar erst NACH dem vollständigen
    # Bericht, was es wie ein Fehler beim Schreiben aussehen ließ.
    #
    # Der Wächter ist bewusst allgemein: Der nächste Fall heißt nicht
    # wieder `verdict`.
    _tree = ast.parse(open(__file__, encoding="utf-8").read())
    _functions = {node.name for node in _tree.body
                  if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))}
    for _node in _tree.body:
        if not isinstance(_node, ast.FunctionDef):
            continue
        _assigned = set()
        for _inner in ast.walk(_node):
            if isinstance(_inner, ast.Assign):
                _targets = _inner.targets
            elif isinstance(_inner, (ast.AugAssign, ast.AnnAssign)):
                _targets = [_inner.target]
            elif isinstance(_inner, (ast.For, ast.AsyncFor)):
                _targets = [_inner.target]
            else:
                continue
            for _target in _targets:
                for _name in ast.walk(_target):
                    if isinstance(_name, ast.Name):
                        _assigned.add(_name.id)
        # `global` hebt die Verdeckung auf — das ist Absicht und kein Fund.
        _global = {n for _inner in ast.walk(_node)
                   if isinstance(_inner, ast.Global) for n in _inner.names}
        _shadowed = (_assigned & _functions) - _global - {_node.name}
        assert not _shadowed, (
            f"{_node.name}() weist {sorted(_shadowed)} zu und verdeckt damit "
            f"die gleichnamige Funktion in der GANZEN Funktion — auch in "
            f"Zweigen, die die Zuweisung nie erreichen.")

    # --- Die Messbasis (Phase 0, docs/pilzampel-messbasis.md) ----------
    #
    # **Die Vorgabe muss Zeile für Zeile das alte Verhalten sein.** Sonst
    # wäre jede schon veröffentlichte Zahl still eine andere geworden —
    # und zwar ohne dass irgendein Bericht sich ändert.
    assert DATASET == ampel_basis.DEFAULT_DATASET == "vorgabe"
    assert EXTRA_FIELDS == [], EXTRA_FIELDS
    assert SPAN_LOOKBACK == RAIN_WINDOW == 26
    assert DEDUPE is False, "Entdoppeln ist ab Werk aus"
    probe = [(51.0, 10.0), (48.0, 11.0)]
    assert _cache_key(2020, probe, 100, 300).startswith("weather_2020_"), \
        "der alte Cache wäre unsichtbar"

    # Die Zufallsfolge ist die von vorher: erst `randint`, dann `random`.
    # Wer die Reihenfolge ändert, verschiebt jede bisher berichtete Zahl.
    # Deshalb steht hier eine festgenagelte Folge und keine Eigenschaft.
    rng = random.Random(42)
    drawn = [pick_control_day(100, rng) for _ in range(5)]
    assert drawn == [71, 66, 130, 57, 61], drawn
    # Und dieselbe Folge muss aus `ampel_basis` kommen — sonst laufen die
    # beiden Wege auseinander, sobald einer angefasst wird.
    rng = random.Random(42)
    mirror = [ampel_basis.pick_control(100, rng, CONTROL_MIN_GAP,
                                       CONTROL_MAX_GAP)[0] for _ in range(5)]
    assert mirror == drawn, (mirror, drawn)

    # Umschalten zieht Felder UND Vorlauf mit.
    try:
        use_dataset("pinned")
        assert DATASET == "pinned"
        assert EXTRA_FIELDS == ["smoist", "snow", "stemp", "tmin"], EXTRA_FIELDS
        assert SPAN_LOOKBACK == 28, \
            "ohne größeren Vorlauf fehlt Phase 2 die Frostdosis über 28 Tage"
        assert not _cache_key(2020, probe, 100, 300).startswith(
            "weather_2020_"), "gepinnt und Vorgabe teilten sich eine Datei"
        # Der größere Vorlauf muss sich auch im Zeitraum niederschlagen.
        assert season_span([200], year=2020)[0] == 200 - 45 - 28 - 1
    finally:
        use_dataset(ampel_basis.DEFAULT_DATASET)
    assert SPAN_LOOKBACK == RAIN_WINDOW and EXTRA_FIELDS == []
    assert season_span([200], year=2020)[0] == 200 - 45 - 26 - 1

    # Ein unbekannter Datensatz bricht ab, statt still auf die Vorgabe
    # zurückzufallen — ein Tippfehler im Flag wäre sonst ein ganzer Lauf
    # auf dem falschen Instrument.
    try:
        use_dataset("era5land")
    except SystemExit:
        pass
    else:
        raise AssertionError("unbekannter Datensatz angenommen")
    assert DATASET == "vorgabe"

    ampel_basis.self_test_quiet()

    # Die Kandidaten des Kalttests stehen NICHT im Standardlauf — geprüft
    # wird trotzdem, dass es sie gibt: Ein Tippfehler fiele sonst erst
    # nach dem ersten Abruf auf, also nach dem halben Tageskontingent.
    for name in COLD_CANDIDATES + [COLD_MEMBER]:
        assert name in mapping, f"{name} hat kein `sci` in {SPECIES_FILE}"

    # --- Der Klassen-Hold-out: vier Ausgänge, und die Kontrolle zuerst --
    #
    # Dieselbe Bauart wie beim Kalttest, mit einem zusätzlichen Zustand,
    # der hier das Entscheidende ist: Eine verzerrte Ziehung ist KEINE
    # Messung. Ein Bericht, der darüber ein Urteil schreibt, ist schlimmer
    # als einer, der schweigt — genau das ist dem ersten Hold-out-Bericht
    # passiert („bestätigt" und zwei Zeilen darunter „nicht auswertbar").
    def hold_row(name, gain, mirror=0.500, usable=True, refit=11.0):
        if not usable:
            return {"name": name, "usable": False, "why": "keine Funde"}
        return {"name": name, "usable": True, "countries": ["AT", "CH"],
                "optimum": 11.625, "own_optimum": 11.0, "window": 11.625,
                "refit": refit, "refit_band": (refit, refit),
                "n_home": 900, "n": 300, "years": 15,
                "auc_shared": 0.520, "auc_fitted": 0.520 + gain,
                "gain": gain, "placebo_auc": 0.505, "placebo_n": 280,
                "mirror_auc": mirror, "mirror_n": 280,
                "ci": {"difference": (gain - 0.02, gain + 0.02)}}

    # **Die Klassentabelle rundet ihr Fenster nicht.** Die Zeile, aus
    # der die falsche 11,6 abgeschrieben wurde.
    zeile = class_table_row(
        "herbst_holz", AMPEL_CLASSES["herbst_holz"],
        {"verhalten": 0.149, "guenstig": 0.408,
         "members": ["Hallimasch", "Stockschwämmchen"],
         "optimum_measured": 11.625})
    assert "11.625 °C" in zeile and "11.6 °C" not in zeile
    assert "**nein**" in zeile, "unbestätigt gehört benannt"
    assert "11.625 °C" not in class_table_row(
        "herbst", AMPEL_CLASSES["herbst"],
        {"verhalten": 0.187, "guenstig": 0.512, "members": ["Steinpilz"],
         "optimum_measured": 11.625}), \
        "für eine ausgelieferte Klasse gilt die KONSTANTE, nicht die Messung"

    holz = AMPEL_CLASSES["herbst_holz"]["members"]
    a, b = holz
    assert class_holdout_verdict(
        [hold_row(a, 0.09), hold_row(b, 0.07)], holz)["state"] == "bestanden"
    assert class_holdout_verdict(
        [hold_row(a, 0.09), hold_row(b, 0.02)], holz)["state"] == "nur-eine"
    assert class_holdout_verdict(
        [hold_row(a, 0.01), hold_row(b, 0.02)], holz)["state"] == "keine"
    assert class_holdout_verdict(
        [hold_row(a, 0.09)], holz)["state"] == "offen"
    # **Die Kontrolle schlägt das Ergebnis.** Zwei satte Gewinne, aber
    # eine verzerrte Ziehung — das darf nicht „bestanden" heißen.
    assert class_holdout_verdict(
        [hold_row(a, 0.30), hold_row(b, 0.30, mirror=0.62)],
        holz)["state"] == "offen"
    # **Ein sauberer Fehlschlag entscheidet trotzdem.** Eine Art unter
    # der Latte bei sauberer Kontrolle, die andere ungemessen: „alle
    # oder keine" ist damit beantwortet, und keine dritte Messung holt
    # das zurück. Als „offen" gemeldet läse es sich als „vielleicht
    # doch".
    entschieden = class_holdout_verdict(
        [hold_row(a, 0.01), hold_row(b, 0.30, mirror=0.62)], holz)
    assert entschieden["state"] == "keine"
    assert entschieden["offen"], "die Lücke gehört trotzdem genannt"
    gemischt = class_holdout_verdict(
        [hold_row(a, 0.09), hold_row(b, 0.01)], holz)
    assert gemischt["state"] == "nur-eine" and gemischt["failed"] == [b]

    fits = [{"name": a, "usable": True, "optimum": 11.0, "n_fit": 500,
             "n_test": 400, "klass": "herbst_holz"},
            {"name": b, "usable": True, "optimum": 12.25, "n_fit": 300,
             "n_test": 250, "klass": "herbst_holz"}]
    fenster = class_optimum(fits, "herbst_holz")
    assert fenster == 11.625, "der Median zweier Mitglieder ist ihr Mittel"
    gut = render_class_holdout_report(
        [hold_row(a, 0.09), hold_row(b, 0.07)], ["AT", "CH"], "herbst_holz",
        fenster, fits, "2026-09-13")
    # **Die Zahl, an der dieses Projekt zweimal gescheitert ist.** Erst
    # 11,5 von Hand gerundet, dann 11,6 aus einer einstelligen Tabelle
    # abgeschrieben. Sie muss mit allen Stellen dastehen.
    assert "11.625" in gut and "11.5 °C" not in gut and "11.6 °C" not in gut
    assert "Bestanden" in gut
    assert "Schwellen" in gut, "ohne sie liefert die Klasse nicht aus"
    assert "vorab ausgeschlossen war" not in gut
    # Die Richtungsaussage steht NACH dem Urteil und nennt sich kein Tor.
    assert gut.index("## Der Ausgang") < gut.index("## Die Richtungsaussage")
    assert "kein Tor" in gut and "kein Beleg" in gut

    halb = render_class_holdout_report(
        [hold_row(a, 0.09), hold_row(b, 0.02)], ["AT", "CH"], "herbst_holz",
        fenster, fits, "2026-09-13")
    # NICHT auf „Beide oder keine" prüfen — der Satz steht schon in der
    # Bedingung oben. Dieselbe Falle wie beim Kalttest, dort in der
    # Gegenprobe aufgefallen.
    assert "vorab ausgeschlossen war" in halb and "Bestanden" not in halb
    assert "nicht nachweisbar" in halb, \
        "ein Fehlschlag ist keine Aussage über die Wirklichkeit"
    # **Die Deutung hängt am Abstand, nicht an der Formulierung.** Bei
    # 1,4 K entschuldigt die flache Glockenmitte ein Verfehlen; 14 K
    # neben den 13 °C tut sie das Gegenteil.
    assert "Mitte flach" in halb and "wiegt der Fehlschlag schwerer" \
        not in halb
    kalt_fits = [{"name": n, "usable": True, "optimum": o, "n_fit": 200,
                  "n_test": 200, "klass": "kalt"}
                 for n, o in zip(AMPEL_CLASSES["kalt"]["members"],
                                 (-3.2, 1.5, -1.0))]
    kalt_rows = [hold_row(n, 0.01) for n in AMPEL_CLASSES["kalt"]["members"]]
    weit = render_class_holdout_report(
        kalt_rows, ["AT", "CH"], "kalt", class_optimum(kalt_fits, "kalt"),
        kalt_fits, "2026-09-13")
    assert "wiegt der Fehlschlag schwerer" in weit
    # **Die Zahl der Mitglieder steht nicht im Text.** „Eine Klasse aus
    # zwei Arten" war hineingeschrieben, als es nur zweigliedrige
    # Klassen gab — bei der dreigliedrigen kalten stand es dann falsch
    # da, ohne dass etwas rot wurde.
    kalt_namen = AMPEL_CLASSES["kalt"]["members"]
    kalt_gemischt = render_class_holdout_report(
        [hold_row(kalt_namen[0], 0.09), hold_row(kalt_namen[1], 0.01),
         hold_row(kalt_namen[2], 0.01)],
        ["AT", "CH"], "kalt", class_optimum(kalt_fits, "kalt"), kalt_fits,
        "2026-09-13")
    assert f"ein Mitglied von {len(kalt_namen)}" in kalt_gemischt
    assert "zwei Arten" not in kalt_gemischt
    assert "darunter: " in kalt_gemischt, \
        "wer durchgefallen ist, gehört genannt"
    assert "Mitte flach" not in weit, \
        "14 K neben dem Fenster ist keine flache Mitte"
    assert "+0.020 unter" in halb.replace(",", "."), \
        "welche Zahl gefehlt hat, gehört hinein"

    offen = render_class_holdout_report(
        [hold_row(a, 0.30), hold_row(b, 0.30, mirror=0.62)], ["AT", "CH"],
        "herbst_holz", fenster, fits, "2026-09-13")
    assert "Noch nicht entschieden" in offen and "Bestanden" not in offen
    assert "0.620" in offen, "die verzerrte Kontrolle gehört genannt"

    # Der entschiedene Fehlschlag nennt die Lücke — und nennt sie als
    # folgenlos, statt sie zu verschweigen oder als Hoffnung zu führen.
    trotzdem = render_class_holdout_report(
        [hold_row(a, 0.01), hold_row(b, 0.30, mirror=0.62)], ["AT", "CH"],
        "herbst_holz", fenster, fits, "2026-09-13")
    assert "Noch nicht entschieden" not in trotzdem
    assert "Nicht gemessen wurde dabei" in trotzdem and "0.620" in trotzdem
    assert "schon\nentschieden" in trotzdem.replace(" ", "\n")

    # Ein knapper Treffer, dessen Bereich die Null einschließt, wird als
    # solcher benannt — ohne die Latte nachträglich zu verschieben.
    knapp = hold_row(a, 0.06)
    knapp["ci"] = {"difference": (-0.01, 0.13)}
    knapper_bericht = render_class_holdout_report(
        [knapp, hold_row(b, 0.01)], ["AT", "CH"], "herbst_holz", fenster,
        fits, "2026-09-13")
    assert "schließt der Vertrauensbereich die Null ein" in knapper_bericht
    assert "als Punktschätzer registriert" in knapper_bericht

    # Und die Richtungsaussage sagt, wenn sie NICHT hält.
    schief = render_class_holdout_report(
        [hold_row(a, 0.09, refit=14.5), hold_row(b, 0.07)], ["AT", "CH"],
        "herbst_holz", fenster, fits, "2026-09-13")
    assert "hält nur zum Teil" in schief and "14.5" in schief
    # **Und der Zusatz steht NICHT unter seinem eigenen Gegenteil.** Er
    # hing zuerst daran, dass irgendeine Art darunter liegt.
    assert "stützt die Richtung" not in schief
    assert "stützt die Richtung" in gut, "wo alle darunter liegen, schon"
    keins = render_class_holdout_report(
        [hold_row(a, 0.09, refit=14.5), hold_row(b, 0.07, refit=15.5)],
        ["AT", "CH"], "herbst_holz", fenster, fits, "2026-09-13")
    assert "Keines der Optima" in keins and "hält\nnicht" in keins.replace(
        " ", "\n") or "hält nicht" in keins

    # --- Der Kalttest: die vier Ausgänge und ihr Wortlaut ---------------
    #
    # **Geprüft wird am GERENDERTEN Text**, nicht am Zustandswort. Ein
    # Bericht, dessen Urteil vorformuliert ist, kann die falsche Ursache
    # behaupten — genau das ist am 2026-09-12 passiert (ein Satz erklärte
    # eine Lücke, deren Vertrauensbereich die Null ausschloss). Was hier
    # zählt: Jeder Zweig sagt seine Zahl, und keiner sagt die Worte eines
    # anderen.
    def cold_row(name, optimum, gain, usable=True):
        if not usable:
            return {"name": name, "usable": False, "n_fit": 3, "n_test": 0}
        return {"name": name, "usable": True, "n_fit": 400, "n_test": 300,
                "optimum": optimum, "best_set": (optimum, optimum),
                "at_edge": False, "plateau": 1, "auc_fit": 0.6,
                "auc_test_shared": 0.52,
                "auc_test_fitted": 0.52 + gain, "gain": gain,
                "ci": {"difference": (gain - 0.02, gain + 0.02)}}

    kalt, samt = COLD_CANDIDATES
    beide = [cold_row(kalt, 2.0, 0.09), cold_row(samt, 4.0, 0.07)]
    assert cold_verdict(beide)["state"] == "bestanden"
    # Eine Hälfte zu wenig reicht, und zwar jede der beiden.
    assert cold_verdict([cold_row(kalt, 2.0, 0.09),
                         cold_row(samt, 4.0, 0.03)])["state"] == "nur-eine"
    assert cold_verdict([cold_row(kalt, 2.0, 0.09),
                         cold_row(samt, 7.0, 0.09)])["state"] == "nur-eine"
    assert cold_verdict([cold_row(kalt, 7.0, 0.01),
                         cold_row(samt, 9.0, 0.00)])["state"] == "keine"
    # Nicht gemessen ist NICHT durchgefallen.
    assert cold_verdict([cold_row(kalt, 2.0, 0.09),
                         cold_row(samt, 0, 0, usable=False)]
                        )["state"] == "offen"
    assert cold_verdict([cold_row(kalt, 2.0, 0.09)])["state"] == "offen", \
        "eine fehlende Art ist eine Lücke, kein Fehlschlag"

    # Der Median von drei Ein-Stellen-Werten trägt keine drei Stellen,
    # der von zwei sehr wohl.
    assert _optimum_text(-1.0) == "-1.0"
    assert _optimum_text(11.625) == "11.625"

    gut = render_cold_report(beide, None, "2026-09-13")
    assert "Bestanden" in gut and "Median" in gut
    assert "-1.000" not in gut and "2.000" not in gut, \
        "erfundene Nachkommastellen"
    # Eine Grundlinie über 0,5 braucht den Deutungs-Satz NICHT …
    assert "falsche Richtung" not in gut
    # … eine darunter schon, sonst liest sich der Gewinn als Triumph.
    verkehrt = [cold_row(kalt, 2.0, 0.09), cold_row(samt, 4.0, 0.07)]
    verkehrt[1]["auc_test_shared"] = 0.29
    verkehrt[1]["auc_test_fitted"] = 0.79
    verkehrt[1]["gain"] = 0.50
    verkehrt[1]["ci"] = {"difference": (0.38, 0.57)}
    gedeutet = render_cold_report(verkehrt, None, "2026-09-13")
    assert "falsche Richtung" in gedeutet and samt in gedeutet
    assert "Bestanden" in gedeutet, "die Bedingung bleibt erfüllt"
    # Mit dem Satz drumherum, nicht als nackte Zahl: „+0.05" traf in der
    # Gegenprobe zufällig eine Vertrauensbereichs-Grenze in der Tabelle,
    # und damit hielt die Zusage, obwohl die Bedingung aus dem Kopf
    # verschwunden war.
    assert f"mindestens **{COLD_MIN_GAIN:+.2f}** AUC" in gut, \
        "die Latte gehört in den Bericht"
    assert f"unter {COLD_MAX_OPTIMUM_C:.0f} °C" in gut
    assert "Einzelfall" not in gut
    halb = render_cold_report(
        [cold_row(kalt, 2.0, 0.09), cold_row(samt, 4.0, 0.03)], None,
        "2026-09-13")
    # **Nicht auf „Beide oder keine" prüfen** — der Satz steht schon in
    # der Bedingung oben, und damit wäre die Zusage von selbst erfüllt.
    # In der Gegenprobe genau so aufgefallen: Der Zweig ließ sich
    # entfernen, ohne dass ein Test rot wurde.
    assert "der vorab ausgeschlossen war" in halb
    assert "Bestanden" not in halb
    assert "+0.030 unter" in halb.replace(",", ".") or \
        "Gewinn +0,030" in halb, "welche Hälfte gefehlt hat, gehört hinein"
    assert "Einzelfall" in halb
    keiner = render_cold_report(
        [cold_row(kalt, 7.0, 0.01), cold_row(samt, 9.0, 0.0)], None,
        "2026-09-13")
    assert "keine der beiden" in keiner
    assert "wetterunabhängig" in keiner, \
        "der Bericht darf nicht mehr behaupten als gemessen wurde"
    offen = render_cold_report(
        [cold_row(kalt, 2.0, 0.09), cold_row(samt, 0, 0, usable=False)],
        None, "2026-09-13")
    assert "Noch nicht entschieden" in offen and samt in offen
    assert "Bestanden" not in offen and "Einzelfall" not in offen
    # Und die Kontextzeile tritt nicht als Prüfling an.
    mit_kontext = render_cold_report(beide, cold_row(COLD_MEMBER, -3.2, 0.17),
                                     "2026-09-13")
    assert "tritt nicht an" in mit_kontext
    assert cold_verdict(beide + [cold_row(COLD_MEMBER, -3.2, 0.17)]
                        )["state"] == "bestanden", \
        "das Mitglied darf den Ausgang nicht mitentscheiden"

    # --- Mitgliedschaft am ausgelieferten Fenster -------------------------
    #
    # Die Gruppe fällt aus dem Saisongipfel und kennt kein Wetter. Sie ist
    # die VORHERSAGE, gegen die gemessen wird — dreht sie sich, dreht sich
    # die Registrierung.
    assert membership_group(9) == "herbstnah"
    assert membership_group(10) == "herbstnah"
    assert membership_group(12) == "kalt" and membership_group(1) == "kalt"
    assert membership_group(5) == "anders" and membership_group(6) == "anders"
    assert MEMBERSHIP_PREDICTION["herbstnah"] is True
    assert not MEMBERSHIP_PREDICTION["anders"]
    assert not MEMBERSHIP_PREDICTION["kalt"]
    # Der Status trennt, wer das Urteil trägt.
    assert membership_status("Steinpilz") == "ausgeliefert"
    assert membership_status("Hallimasch") == "Zahlen bekannt"
    assert membership_status("Judasohr") == "Zahlen bekannt"
    assert membership_status("Fliegenpilz") == "frisch"

    def m_row(name, auc, n=1000, mirror=0.5, usable=True):
        return {"name": name, "usable": usable, "n": n, "years": 20,
                "auc": auc, "ci": {OPTIMUM_C: (auc - 0.03, auc + 0.03)},
                "mirror_auc": mirror, "mirror_n": n,
                "placebo_auc": 0.5, "placebo_n": n}

    def cand(name, group, status="frisch"):
        return {"name": name, "sci": "X y", "records": 900,
                "peak": {"herbstnah": 9, "kalt": 12, "anders": 5}[group],
                "group": group, "status": status}

    # Der Ausgang EINER Art.
    assert membership_outcome(m_row("A", 0.70)) == "erfüllt"
    assert membership_outcome(m_row("A", MEMBERSHIP_MIN_AUC)) == "erfüllt", \
        "die Latte ist erreicht, nicht überschritten"
    assert membership_outcome(m_row("A", 0.55)) == "verfehlt"
    # **Verzerrte Ziehung und zu wenig Material sind NICHT Durchfallen.**
    # Dort wurde nichts gemessen; als Fehlschlag berichtet wäre es eine
    # Aussage über Daten, die es nicht gibt.
    assert membership_outcome(m_row("A", 0.70, mirror=0.56)) == "offen"
    assert membership_outcome(m_row("A", 0.70, n=100)) == "offen"
    assert membership_outcome(m_row("A", 0.0, usable=False)) == "offen"

    # **Das Tor ist der BEREICH, nicht mehr die feste Zahl** (2026-09-17).
    # Eine weit danebenliegende Kontrolle mit breitem Bereich ist
    # Rauschen und darf nicht verwerfen; eine knapp danebenliegende mit
    # schmalem Bereich ist ein Befund und muss es.
    weit = m_row("A", 0.70, mirror=0.55)
    weit["mirror_ci"] = (0.47, 0.63)
    assert membership_control_clean(weit)
    assert membership_outcome(weit) == "erfüllt", \
        "0,55 bei breitem Bereich ist Rauschen — die alte Zahl verwarf hier"
    schmal = m_row("A", 0.70, mirror=0.515)
    schmal["mirror_ci"] = (0.505, 0.525)
    assert not membership_control_clean(schmal)
    assert membership_outcome(schmal) == "offen", \
        "0,515 bei schmalem Bereich ist ein Befund — die alte Zahl liess das durch"
    # Ohne Bereich (weniger als zwei Jahre) bleibt die feste Zahl.
    ohne = m_row("A", 0.70, mirror=0.56)
    ohne["mirror_ci"] = None
    assert not membership_control_clean(ohne), \
        "ganz ohne Pruefung durchzulassen waere die falsche Richtung"
    # Der Bootstrap ueber Jahre selbst: gleiche Paare, aber ein Jahr oder viele.
    proben = [{"year": 2000 + (i % 10),
               "control": ([10.0] * 26, [13.0] * 20),
               "mirror": ([10.0] * 26, [13.0] * 20)} for i in range(200)]
    band = bootstrap_years_pairs(proben, mirror_pair, rounds=200)
    assert band is not None and band[0] <= 0.5 <= band[1]
    # **Und der Bereich muss die JAHRE spueren.** Haelfte der Jahre laeuft
    # in die eine Richtung, Haelfte in die andere: Gesamt-AUC 0,50, aber
    # ein Bereich, der das Jahr als Einheit nimmt, MUSS breit sein. Ohne
    # Ziehung ueber Jahre faellt er auf null zusammen — eine Sicherheit,
    # die es nicht gibt (und die Gegenprobe dazu blieb sonst gruen).
    nass, trocken = ([10.0] * 26, [13.0] * 20), ([0.1] * 26, [13.0] * 20)
    geteilt = []
    for jahr in range(2000, 2010):
        hoch = jahr < 2005
        for _ in range(20):
            geteilt.append({"year": jahr,
                            "control": nass if hoch else trocken,
                            "mirror": trocken if hoch else nass})
    breit = bootstrap_years_pairs(geteilt, mirror_pair, rounds=300)
    assert breit is not None and breit[1] - breit[0] > 0.30, \
        f"ueber Jahre gezogen muss der Bereich breit sein, ist {breit}"
    assert breit[0] <= 0.5 <= breit[1]

    einjahr = [dict(p, year=2000) for p in proben]
    assert bootstrap_years_pairs(einjahr, mirror_pair, rounds=200) is None, \
        "ein einziges Jahr traegt keinen Bereich"
    assert mirror_pair({"control": ([1.0], [1.0]), "mirror": None}) is None

    herbst_cands = [cand(f"H{i}", "herbstnah") for i in range(4)]
    kontrast = [cand("Mai", "anders"), cand("Winter", "kalt")]
    # Bestanden: die Bestätigungsgruppe trägt, die Kontrastgruppe nicht.
    gut = membership_verdict(
        [m_row(f"H{i}", 0.70) for i in range(4)]
        + [m_row("Mai", 0.52), m_row("Winter", 0.48)],
        herbst_cands + kontrast)
    assert gut["state"] == "bestanden", gut
    assert len(gut["passed"]) == 4
    # **Die Kontrastgruppe entscheidet zuerst.** Besteht sie mit, hilft
    # es nicht, dass die Bestätigungsgruppe glänzt — dann misst das
    # Modell etwas Generisches, und der Plan sieht Rückbau vor.
    generisch = membership_verdict(
        [m_row(f"H{i}", 0.75) for i in range(4)]
        + [m_row("Mai", 0.71), m_row("Winter", 0.69)],
        herbst_cands + kontrast)
    assert generisch["state"] == "generisch", generisch
    # Eine EINZELNE bestehende Kontrastart kippt das Urteil nicht.
    assert membership_verdict(
        [m_row(f"H{i}", 0.70) for i in range(4)]
        + [m_row("Mai", 0.71), m_row("Winter", 0.48)],
        herbst_cands + kontrast)["state"] == "bestanden"
    # Eng: die frischen Herbstarten fallen breit durch.
    eng = membership_verdict(
        [m_row("H0", 0.70)] + [m_row(f"H{i}", 0.52) for i in range(1, 4)]
        + [m_row("Mai", 0.50), m_row("Winter", 0.48)],
        herbst_cands + kontrast)
    assert eng["state"] == "eng", eng
    # **Offene Flanke: die Bestaetigungsgruppe traegt, die Kontrastgruppe
    # war gar nicht messbar.** Genau dieser Fall trat am 2026-09-16 ein —
    # beide frischen Kontrastarten hatten verzerrte Ziehungen. Ohne
    # diesen Zweig meldete das Urteil dort "bestanden", also einen
    # sauberen Ausgang, obwohl die Haelfte des Plans ausgefallen war.
    flanke = membership_verdict(
        [m_row(f"H{i}", 0.70) for i in range(4)]
        + [m_row("Mai", 0.77, mirror=0.55), m_row("Winter", 0.48, mirror=0.54)],
        herbst_cands + kontrast)
    assert flanke["state"] == "flanke", flanke
    assert len(flanke["passed"]) == 4, "die Bestaetigungsgruppe traegt trotzdem"
    assert not flanke["contrast_measured"]
    flanke_bericht = render_membership_report(
        [m_row(f"H{i}", 0.70) for i in range(4)]
        + [m_row("Mai", 0.77, mirror=0.55), m_row("Winter", 0.48, mirror=0.54)],
        herbst_cands + kontrast, flanke, "2026-09-16")
    assert "Kein sauberer Ausgang" in flanke_bericht
    assert "AUSSCHLIESST" in flanke_bericht
    assert "Kontext, kein Beleg" in flanke_bericht, \
        "die saubere Gegenrichtung gehoert genannt — aber als Kontext"
    assert "ungeprüfte Warnung" in flanke_bericht, \
        "eine hohe AUC bei verzerrter Ziehung ist keine Entwarnung"
    # Und eine EINZIGE messbare Kontrastart genuegt fuer den sauberen Ausgang.
    assert membership_verdict(
        [m_row(f"H{i}", 0.70) for i in range(4)]
        + [m_row("Mai", 0.52), m_row("Winter", 0.48, mirror=0.54)],
        herbst_cands + kontrast)["state"] == "bestanden"

    # Offen: nichts sauber gemessen.
    assert membership_verdict(
        [m_row(f"H{i}", 0.70, mirror=0.6) for i in range(4)],
        herbst_cands)["state"] == "offen"
    # Bekannte Zahlen tragen das Urteil NICHT mit.
    bekannt = membership_verdict(
        [m_row("Alt", 0.75)], [cand("Alt", "herbstnah", "Zahlen bekannt")])
    assert bekannt["state"] == "offen" and not bekannt["passed"], \
        "eine Regel an bekannten Zahlen zu prüfen beweist nichts"

    # Der Bericht sagt, was gemessen wurde — und nicht mehr.
    bericht = render_membership_report(
        [m_row(f"H{i}", 0.70) for i in range(4)]
        + [m_row("Mai", 0.52), m_row("Winter", 0.48)],
        herbst_cands + kontrast, gut, "2026-09-16")
    assert "Bestanden" in bericht and "0.700" in bericht
    assert "gegenstandslos" not in bericht
    offen_bericht = render_membership_report(
        [m_row("H0", 0.70, mirror=0.58)], [cand("H0", "herbstnah")],
        membership_verdict([m_row("H0", 0.70, mirror=0.58)],
                           [cand("H0", "herbstnah")]), "2026-09-16")
    assert "offen" in offen_bericht
    assert "0.580" in offen_bericht, "die verzerrte Kontrolle gehört sichtbar"
    generisch_bericht = render_membership_report(
        [m_row(f"H{i}", 0.75) for i in range(4)]
        + [m_row("Mai", 0.71), m_row("Winter", 0.69)],
        herbst_cands + kontrast, generisch, "2026-09-16")
    assert "gegenstandslos" in generisch_bericht
    assert "Rückbau" in generisch_bericht, \
        "der Ausgang gegen das Vorhaben muss im Bericht stehen"

    print("ampel_validate self-test: ok")


# --- Bericht ---------------------------------------------------------------


# Die vorab festgelegte Vorhersage aus
# docs/pilzampel-artenfenster.md. Sie steht als KONSTANTE hier, damit
# sie im Bericht nicht nachträglich umformuliert werden kann.
PREDICTION_SPECIES = "Austernseitling"
PREDICTION_MAX_OPTIMUM_C = 9.0
PREDICTION_MIN_AUC = 0.55

# Und dasselbe für den KALTTEST (registriert 2026-09-12, derselbe
# Prüfplan). Zwei Zahlen, beide vor der Messung festgelegt:
#
#   „Judasohr und Samtfußrübling landen beide bei einem Optimum unter
#    5 °C, und beide gewinnen gegenüber den ausgelieferten 13 °C
#    mindestens +0,05 AUC auf ihren Prüfjahren."
#
# **Und die Bedingung ist konjunktiv über die ARTEN**: „Beide oder
# keine." Eine Klasse aus zwei Arten, von denen eine passt, war vorab
# ausgeschlossen — sonst wäre die Latte nach der Messung verschoben.

# Das Mitglied, das den Test überhaupt ausgelöst hat. Es steht im
# Bericht als KONTEXT und nicht als Prüfling: Sein Fenster ist gemessen
# (docs/pilzampel-artenfenster-messung.md), und an einer Art, die an der
# Anpassung beteiligt war, lässt sich nichts mehr bestätigen.
COLD_MEMBER = "Austernseitling"


def cold_check(row):
    """Erfüllt diese Art die registrierte Bedingung? Beide Hälften.

    Gibt die Einzelurteile zurück statt eines Wahrheitswerts: Der
    Bericht muss sagen können, WELCHE Hälfte gefehlt hat — „nicht
    erfüllt" allein ist eine Behauptung ohne Zahl.
    """
    if not row or not row.get("usable"):
        return None
    return {
        "optimum": row["optimum"] < COLD_MAX_OPTIMUM_C,
        "gain": row["gain"] >= COLD_MIN_GAIN,
    }


def cold_verdict(rows):
    """Der Ausgang des Kalttests — vier Zustände, und sie bedeuten
    Verschiedenes.

    `offen` ist NICHT `keine`: Eine Art, die über zu wenig Material
    nicht auf beide Seiten der Jahres-Trennlinie kommt, ist nicht
    gemessen worden. Das als Fehlschlag zu berichten wäre eine Aussage
    über Daten, die es nicht gibt (dieselbe Trennung wie in
    `render_fit_report`).
    """
    by_name = {row["name"]: row for row in rows}
    checks = {}
    for name in COLD_CANDIDATES:
        row = by_name.get(name)
        if row is None or not row.get("usable"):
            return {"state": "offen", "checks": checks,
                    "missing": [n for n in COLD_CANDIDATES
                                if n not in by_name
                                or not by_name[n].get("usable")]}
        checks[name] = cold_check(row)
    met = [n for n, c in checks.items() if c["optimum"] and c["gain"]]
    if len(met) == len(COLD_CANDIDATES):
        state = "bestanden"
    elif met:
        state = "nur-eine"
    else:
        state = "keine"
    return {"state": state, "checks": checks, "met": met}


def render_fit_report(rows, fetched_on):
    """Der Bericht zur Anpassung — Vorhersage zuerst, Zahlen danach."""
    out = ["# Artenfenster: gemessen", "",
           f"Stand: {fetched_on} · Erzeugt von `tool/ampel_validate.py "
           f"--fit` · Prüfplan: `docs/pilzampel-artenfenster.md`", "",
           "Angepasst wird das Temperaturoptimum je Art auf den Jahren bis "
           f"**{FIT_UNTIL_YEAR}**, geprüft auf allen späteren. Die "
           "Regenhälfte des Modells bleibt unangetastet, ebenso die Breite "
           f"der Glocke (σ = {TEMP_SIGMA:.0f} K). Ausgeliefert rechnet die "
           f"App weiterhin mit {OPTIMUM_C:.0f} °C für alle Arten.", "",
           "## Umfang dieses Laufs", "",
           "Enthalten: " + ", ".join(r["name"] for r in rows) + ".", "",
           "**Das Tageskontingent von Open-Meteo reicht nicht für alle "
           "neun Arten auf einmal** (bemessen nach Orten × Tagen, nicht "
           "nach Anfragen). Ein Lauf holt gut eine halbe Art; der Cache "
           "trägt das Geholte über Tage. Fehlt eine Art hier, ist sie "
           "nicht ausgefallen, sondern noch nicht geholt — ein Ergebnis "
           "auf lückenhaften Jahren bricht das Werkzeug ab, statt es zu "
           "berichten.", "",
           "## Die Vorhersage, die vor der Messung feststand", "",
           f"> Das angepasste Optimum des **{PREDICTION_SPECIES}s** liegt "
           f"unter {PREDICTION_MAX_OPTIMUM_C:.0f} °C, und seine gepaarte "
           f"AUC auf den Prüfjahren erreicht mindestens "
           f"{PREDICTION_MIN_AUC:.2f}.", ""]

    primary = next((r for r in rows
                    if r["name"] == PREDICTION_SPECIES and r.get("usable")), None)
    if primary is None:
        # **Zwei Gründe, und sie bedeuten Verschiedenes.** Nicht im Lauf
        # heißt „noch nicht gemessen"; im Lauf und unbrauchbar heißt
        # „gemessen, trägt nicht". Beides als dasselbe zu melden wäre
        # eine Aussage über Daten, die es nicht gibt.
        ran = any(r["name"] == PREDICTION_SPECIES for r in rows)
        out += [f"**Noch nicht entschieden** — {PREDICTION_SPECIES} "
                + ("war in diesem Lauf nicht enthalten."
                   if not ran else
                   "kam über zu wenig Material nicht auf beide Seiten der "
                   "Jahres-Trennlinie.")
                + " Ohne die vorab benannte Art ist alles Folgende "
                "**Beifund, kein Beleg**: Bei sieben Arten und einem "
                "freien Parameter ist eine Verbesserung durch Zufall zu "
                "erwarten, und welche davon man hinterher interessant "
                "findet, ist keine Vorhersage.", ""]
    else:
        met = (primary["optimum"] < PREDICTION_MAX_OPTIMUM_C
               and primary["auc_test_fitted"] >= PREDICTION_MIN_AUC)
        out += [f"**Ergebnis: {'eingetroffen' if met else 'nicht eingetroffen'}.** "
                f"Optimum {primary['optimum']:.1f} °C "
                f"(vorhergesagt: < {PREDICTION_MAX_OPTIMUM_C:.0f}), "
                f"AUC auf Prüfjahren {primary['auc_test_fitted']:.3f} "
                f"(vorhergesagt: ≥ {PREDICTION_MIN_AUC:.2f}).", ""]
        if met:
            out += ["Damit ist belegt, was die Arten-Kontrolle vom "
                    "2026-08-13 offenlassen musste: Arten haben "
                    "verschiedene Fenster. Die Kontrolle war an ihrer "
                    "AUSWAHL gescheitert, nicht am Modell.", ""]
        else:
            out += ["Damit bleibt die Lesart stehen, dass das Modell "
                    "allgemeines Pilzwetter misst. **Es wird nichts je Art "
                    "gebaut** — so vorab festgelegt.", ""]

    out += ["## Alle Arten", "",
            "„Band“ ist die Spanne der gleich guten Optima. Ist es breit, "
            "ist der Gipfel eine Nachkommastelle ohne Deckung. Der "
            "Vertrauensbereich der Differenz ist über **Jahre** gezogen, "
            "nicht über Paare.", "",
            "| Art | Paare Anpassung | Paare Prüfung | Optimum | Band | "
            f"AUC Prüfung mit {OPTIMUM_C:.0f} °C | AUC Prüfung angepasst | "
            "Differenz (95 %) |",
            "|---|--:|--:|--:|---|--:|--:|---|"]
    for row in rows:
        if not row.get("usable"):
            out.append(f"| {row['name']} | {row['n_fit']} | {row['n_test']} | "
                       "— | — | — | — | zu wenig Material |")
            continue
        low, high = row["best_set"]
        # „-2.0–-1.5" ist nicht lesbar, seit der Gitterboden negativ sein
        # darf. Ein Band aus einem einzigen Wert schreibt sich als Wert.
        band = (f"{low:.1f}" if low == high
                else f"{low:.1f} bis {high:.1f}")
        if row["at_edge"]:
            band += " ⚠ am Gitterrand"
        ci = row.get("ci") or {}
        span = ci.get("difference")
        ci_text = (f"{row['gain']:+.3f} [{span[0]:+.3f}, {span[1]:+.3f}]"
                   if span else f"{row['gain']:+.3f} (kein Bereich)")
        out.append(
            f"| {row['name']} | {row['n_fit']} | {row['n_test']} | "
            f"{row['optimum']:.1f} °C | {band} | "
            f"{row['auc_test_shared']:.3f} | {row['auc_test_fitted']:.3f} | "
            f"{ci_text} |")

    usable = [r for r in rows if r.get("usable")]
    mycos = [r for r in usable if r["name"] in MYCORRHIZAL]
    primary_met = bool(primary) and (
        primary["optimum"] < PREDICTION_MAX_OPTIMUM_C
        and primary["auc_test_fitted"] >= PREDICTION_MIN_AUC)
    if mycos:
        spread = max(r["optimum"] for r in mycos) - min(r["optimum"] for r in mycos)
        near = [r for r in mycos if abs(r["optimum"] - OPTIMUM_C) <= 1.5]
        out += ["", "## Was die Mykorrhiza-Arten sagen", "",
                f"Ihre Optima liegen zwischen "
                f"{min(r['optimum'] for r in mycos):.1f} und "
                f"{max(r['optimum'] for r in mycos):.1f} °C "
                f"(Spanne {spread:.1f} K); {len(near)} von {len(mycos)} "
                f"liegen innerhalb ±1,5 K um die ausgelieferten "
                f"{OPTIMUM_C:.0f} °C.", ""]
        all_same = (len(near) == len(mycos)
                    and all(r["gain"] <= 0.01 for r in mycos))
        if all_same and not primary_met:
            out += ["**Das ist der vorab benannte Ausgang „alle gleich“ — "
                    "und die vorab benannte Art zeigt ebenfalls nichts.** "
                    "Zusammen stützt das die Lesart, dass hier allgemeines "
                    "Pilzwetter gemessen wird. Es begrenzt damit, was die "
                    "Ampel je behaupten darf, und **es wird nichts je Art "
                    "gebaut**.", ""]
        elif all_same and primary_met:
            # Beides zugleich ist kein Widerspruch, sondern genau die
            # Erwartung aus Sato 2012 und Alday 2017: Die Gilde
            # entscheidet, nicht die Art. Ein Bericht, der hier
            # „allgemeines Pilzwetter“ stempeln würde, widerspräche seiner
            # eigenen ersten Seite.
            out += ["**Die sechs teilen ein Fenster — der Austernseitling "
                    "hat ein eigenes.** Das ist kein Widerspruch zur "
                    "Vorhersage oben, sondern die Gilden-Erwartung aus der "
                    "Literatur: Nicht jede Art braucht ein eigenes Fenster, "
                    "wohl aber jede GILDE. Für die App hieße das eine "
                    "Ampel je Gilde, nicht je Art — und der Aufwand "
                    "beschränkte sich auf die Arten, die heute grau "
                    "bleiben.", ""]
        else:
            # **Der Fall, in dem einzelne Arten ausscheren.** Ohne diesen
            # Zweig bliebe die auffälligste Zeile der Tabelle
            # unkommentiert — ein Bericht, der eine Spanne von 6,8 K
            # nennt und dann schweigt, überlässt die Deutung dem
            # Zufall.
            #
            # Was zählt, ist NICHT der Abstand zu 13 °C, sondern ob der
            # Vertrauensbereich der Differenz die Null ausschließt. Ein
            # weit entferntes Optimum ohne Wirkung ist eine Zahl, kein
            # Befund.
            def carries(row):
                span = (row.get("ci") or {}).get("difference")
                return bool(span) and span[0] > 0

            strong = [r for r in usable if carries(r)]
            far = [r for r in mycos if abs(r["optimum"] - OPTIMUM_C) > 1.5]
            if strong:
                out += ["**Ein eigenes Fenster trägt bei: "
                        + ", ".join(f"{r['name']} ({r['optimum']:.1f} °C, "
                                    f"{r['gain']:+.3f})" for r in strong)
                        + ".** Dort schließt der Vertrauensbereich der "
                        "Differenz die Null aus, und gemessen wurde auf "
                        "Jahren, an denen nicht angepasst wurde.", "",
                        "Das ist ein Fund, keine Entscheidung. Welche von "
                        f"{len(usable)} Arten hinterher heraussticht, ist "
                        "keine Vorhersage — eine davon tut es auch bei "
                        "reinem Zufall. Ein eigenes Fenster verdient "
                        "deshalb eine eigene, vorab formulierte Prüfung, "
                        "nicht den Einbau.", ""]
            else:
                out += ["**Keine Art gewinnt nachweisbar.** Bei allen "
                        "enthält der Vertrauensbereich der Differenz die "
                        "Null — die Optima unterscheiden sich als Zahl, "
                        "aber nicht in der Wirkung.", ""]
            if far and not strong:
                out += ["Weit von den 13 °C entfernt liegen trotzdem: "
                        + ", ".join(f"{r['name']} ({r['optimum']:.1f} °C)"
                                    for r in far)
                        + ". Ohne Wirkung ist das eine Zahl, kein Befund.",
                        ""]

    out += ["", "## Grenzen", "",
            "Angepasst wurde ausschließlich an GBIF. Die eigenen Funde und "
            "Leergänge der App bleiben draußen — sie sind der unabhängige "
            "Prüfstein aus #199, und wer sie einrechnet, kann mit ihnen "
            "nicht mehr prüfen.", "",
            "Auch ein artenspezifisches Fenster sagt „die Bedingungen sind "
            "günstig“, nicht „hier stehen Pilze“."]
    return "\n".join(out) + "\n"


def _optimum_text(value):
    """Ein Fenster mit so vielen Stellen, wie es hat.

    Der Median von drei Ein-Stellen-Werten IST einer von ihnen; „-1.000"
    behauptete eine Genauigkeit, die nicht da ist. Bei gerader Anzahl
    entsteht dagegen wirklich eine dritte Stelle (11,625 aus 11,0 und
    12,2 beim Herbst-Holz), und die darf nicht wegfallen — das
    Nachkommastellen-Abschreiben aus einer Tabelle war schon einmal der
    Fehler.
    """
    return (f"{value:.1f}" if abs(value - round(value, 1)) < 1e-9
            else f"{value:.3f}")


def render_cold_report(rows, context, fetched_on):
    """Der Bericht zum Kalttest — Bedingung zuerst, Zahlen danach.

    Eigener Bericht und nicht ein Abschnitt in `render_fit_report`: Der
    Fit-Bericht hängt an SEINER Vorhersage (Austernseitling, unter
    9 °C). Zwei registrierte Bedingungen in einem Text lesen sich als
    eine, und dann entscheidet der Leser, welche gemeint war.
    """
    verdict_info = cold_verdict(rows)
    state = verdict_info["state"]
    out = ["# Kalttest: gibt es eine kalte KLASSE?", "",
           f"Stand: {fetched_on} · Erzeugt von `tool/ampel_validate.py "
           f"--cold` · Prüfplan: `docs/pilzampel-artenfenster.md`", "",
           "Angepasst wird das Temperaturoptimum je Art auf den Jahren bis "
           f"**{FIT_UNTIL_YEAR}**, geprüft auf allen späteren — dasselbe "
           "Verfahren wie in `docs/pilzampel-artenfenster-messung.md`, "
           "dieselbe Stichprobengröße, derselbe Seed.", "",
           "## Die Bedingung, die vor der Messung feststand", "",
           f"> {' und '.join(COLD_CANDIDATES)} landen **beide** bei einem "
           f"Optimum unter {COLD_MAX_OPTIMUM_C:.0f} °C, und **beide** "
           f"gewinnen gegenüber den ausgelieferten {OPTIMUM_C:.0f} °C "
           f"mindestens **{COLD_MIN_GAIN:+.2f}** AUC auf ihren "
           "Prüfjahren.", "",
           "> **Beide oder keine.** Eine Klasse aus zwei Arten, von denen "
           "eine besteht, war vorab ausgeschlossen.", "",
           "**Warum diese zwei Arten.** Sie waren an keiner Anpassung "
           "beteiligt — weder an der Glocke aus der Steinpilz-Literatur "
           "noch an den Fenstern der neun Arten. Unverbrauchte Daten sind "
           "der ganze Grund, warum hier etwas zu bestätigen ist.", "",
           "## Gemessen", "",
           "| Art | Paare Anpassung | Paare Prüfung | Optimum | bestes Band "
           f"| AUC mit {OPTIMUM_C:.0f} °C | AUC angepasst | Differenz "
           "(95 %) | Bedingung |",
           "|---|--:|--:|--:|---|--:|--:|---|---|"]

    def row_line(row, context_row=False):
        tag = " (Kontext)" if context_row else ""
        if not row.get("usable"):
            return (f"| {row['name']}{tag} | {row['n_fit']} | "
                    f"{row['n_test']} | — | — | — | — | — | "
                    "nicht gemessen |")
        low, high = row["best_set"]
        band = (f"{low:.1f}" if low == high
                else f"{low:.1f} bis {high:.1f}")
        if row["at_edge"]:
            band += " ⚠ am Gitterrand"
        span = (row.get("ci") or {}).get("difference")
        ci_text = (f"{row['gain']:+.3f} [{span[0]:+.3f}, {span[1]:+.3f}]"
                   if span else f"{row['gain']:+.3f} (kein Bereich)")
        check = cold_check(row)
        if context_row:
            # Das gemessene Mitglied tritt nicht an — an einer Art, die
            # an der Anpassung beteiligt war, ist nichts zu bestätigen.
            mark = "tritt nicht an"
        elif check["optimum"] and check["gain"]:
            mark = "**erfüllt**"
        else:
            fehlt = []
            if not check["optimum"]:
                fehlt.append(f"Optimum {row['optimum']:.1f} °C nicht unter "
                             f"{COLD_MAX_OPTIMUM_C:.0f}")
            if not check["gain"]:
                fehlt.append(f"Gewinn {row['gain']:+.3f} unter "
                             f"{COLD_MIN_GAIN:+.2f}")
            mark = "nicht erfüllt: " + "; ".join(fehlt)
        return (f"| {row['name']}{tag} | {row['n_fit']} | "
                f"{row['n_test']} | {row['optimum']:.1f} °C | {band} | "
                f"{row['auc_test_shared']:.3f} | "
                f"{row['auc_test_fitted']:.3f} | {ci_text} | {mark} |")

    for row in rows:
        out.append(row_line(row))
    if context:
        out.append(row_line(context, context_row=True))
    out.append("")
    if context:
        out += [f"Die Kontextzeile ist das bereits gemessene Mitglied, aus "
                "dem Cache nachgerechnet. Sie steht da, weil eine Klasse "
                "ihre Mitglieder zusammen zeigen muss — und **nicht als "
                f"Prüfling**: Der {COLD_MEMBER} hat das kalte Fenster "
                "überhaupt erst aufgeworfen, an ihm ist nichts zu "
                "bestätigen.", ""]
    else:
        out += [f"Der {COLD_MEMBER} ist in diesem Lauf nicht mitgerechnet "
                "worden; seine Zahlen stehen in "
                "`docs/pilzampel-artenfenster-messung.md`. Die Bedingung "
                "hängt nicht an ihm.", ""]

    out += ["## Der Ausgang", ""]
    if state == "offen":
        out += ["**Noch nicht entschieden.** Nicht gemessen wurde: "
                + ", ".join(verdict_info["missing"]) + ".", "",
                "Eine Art, die nicht auf beide Seiten der Jahres-Trennlinie "
                f"({FIT_UNTIL_YEAR}) kommt, ist nicht gemessen worden — das "
                "ist kein Fehlschlag, sondern eine Lücke. Was fehlt, holt "
                "ein weiterer Lauf mit demselben Cache nach; die Bedingung "
                "bleibt unverändert stehen.", "",
                "**Bis dahin ändert sich nichts an der App.**"]
    elif state == "bestanden":
        optima = sorted([r["optimum"] for r in rows if r.get("usable")]
                        + ([context["optimum"]]
                           if context and context.get("usable") else []))
        middle = (optima[len(optima) // 2] if len(optima) % 2
                  else (optima[len(optima) // 2 - 1]
                        + optima[len(optima) // 2]) / 2)
        out += ["**Bestanden — beide Arten, beide Hälften.** Damit stehen "
                f"{len(optima)} Arten mit kaltem Fenster, unabhängig "
                "voneinander gemessen. „Kalt“ ist damit eine Klasse und "
                "nicht die Eigenschaft einer Art.", "",
                "Was daraus folgt, und in dieser Reihenfolge:", "",
                "1. **Das Fenster der Klasse ist abgeleitet, nicht "
                "gewählt:** der Median der Optima ihrer Mitglieder, also "
                f"**{_optimum_text(middle)} °C** aus "
                + ", ".join(f"{o:.1f}" for o in optima) + " °C.",
                "2. **Die Schwellen müssen GEMESSEN werden**, als Quantil "
                "der Vergleichstage dieses Fensters (`--thresholds`, "
                "`docs/pilzampel-schwellen.md`). Ein eigenes Fenster ohne "
                "eigene Schwellen macht die Ampel dunkel, nicht besser — "
                f"beim {COLD_MEMBER} fiel „günstig“ mit den "
                "ausgelieferten Schwellen von 21,7 auf 1,1 % der "
                "Fundtage.",
                "3. **Erst dann darf sie in die App**, samt ihren "
                "Mitgliedern in `ampelSpeciesClass`.",
                "4. **Und die Häufigkeit ist neu zu messen:** Jede weitere "
                "Klasse lässt die Fläche öfter „günstig“ sagen (19,9 % → "
                "30,2 % beim Sprung auf zwei Klassen). Wie oft sie das "
                "sagen soll, ist eine Produktentscheidung und keine "
                "Messung."]
        # **Ein Gewinn über einer Grundlinie unter 0,5 ist etwas anderes
        # als ein Gewinn über 0,5.** Unter 0,5 heißt: Mit dem
        # ausgelieferten Fenster zeigt das Modell für diese Art in die
        # FALSCHE Richtung — Fundtage stehen dort schlechter da als
        # Vergleichstage. Der große Teil der Differenz ist dann die
        # Korrektur dieses Vorzeichens und nicht die Feinheit des neuen
        # Fensters. Ohne diesen Satz liest sich +0,498 wie ein Triumph.
        verkehrt = [r for r in rows
                    if r.get("usable") and r["auc_test_shared"] < 0.5]
        if verkehrt:
            out += ["", "**Eine Zahl braucht hier ihre Deutung:** "
                    + ", ".join(f"{r['name']} startet bei "
                                f"{r['auc_test_shared']:.3f}"
                                for r in verkehrt)
                    + " — also UNTER 0,5. Mit den ausgelieferten "
                    f"{OPTIMUM_C:.0f} °C zeigt das Modell für diese Art in "
                    "die falsche Richtung: Fundtage stehen schlechter da "
                    "als Vergleichstage derselben Saison. Der größte Teil "
                    "der Differenz ist deshalb die Korrektur dieses "
                    "Vorzeichens und nicht die Feinheit des neuen "
                    "Fensters. Für die Frage „gibt es eine kalte "
                    "Klasse“ ist genau das die Antwort — für die Frage "
                    "„wie gut trifft die Ampel“ nicht."]
    else:
        if state == "nur-eine":
            out += ["**Nicht bestanden — eine der beiden Arten erfüllt die "
                    "Bedingung, die andere nicht** (erfüllt: "
                    + ", ".join(verdict_info["met"]) + ").", "",
                    "Das ist der Ausgang, der vorab ausgeschlossen war: "
                    "„Beide oder keine.“ Eine Klasse aus zwei Arten, von "
                    "denen eine passt, wäre eine nach der Messung "
                    "verschobene Latte."]
        else:
            out += ["**Nicht bestanden — keine der beiden Arten erfüllt die "
                    "Bedingung.**"]
        out += ["", f"Damit bleibt der {COLD_MEMBER} ein Einzelfall: „Kalt“ "
                "ist keine Klasse, sondern eine Eigenschaft dieser einen "
                "Art. Die Ampel bleibt für sie grau — so wie heute.", "",
                "**Was das NICHT heißt.** Keine der beiden Arten ist damit "
                "wetterunabhängig. Geprüft wurde eine engere Frage: ob "
                "dieses Modell — Glocke um ihr angepasstes Optimum, "
                f"{RAIN_WINDOW}-Tage-Regensumme — bei ihnen über die "
                "registrierte Latte kommt. Warum es das nicht tut, sagt "
                "diese Messung nicht.", "",
                "**Und die Regel, die hier gerade gehalten hat:** Die "
                "Bedingung stand vorher da, mit Zahlen. Ohne sie ließe "
                "sich aus derselben Tabelle eine Klasse begründen — man "
                "müsste die Latte nur dorthin legen, wo die Zahlen schon "
                "sind."]

    out += ["", "## Grenzen", "",
            "Angepasst wurde ausschließlich an GBIF. Die eigenen Funde und "
            "Leergänge der App bleiben draußen — sie sind der unabhängige "
            "Prüfstein aus #199, und wer sie einrechnet, kann mit ihnen "
            "nicht mehr prüfen.", "",
            "Auch ein bestätigtes Fenster sagt „die Bedingungen sind "
            "günstig“, nicht „hier stehen Pilze“."]
    return "\n".join(out) + "\n"


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
        "Datenquellen: Fundmeldungen aus [GBIF](https://www.gbif.org) "
        "(nur CC0 1.0 und CC BY 4.0); Wetter-Rückrechnung mit Daten von "
        "[Open-Meteo](https://open-meteo.com) (CC BY 4.0, "
        "nicht-kommerzielle Nutzung — die Zusage dazu steht im README "
        "und im Konzeptpapier, entschieden 2026-08-08).",
        "",
        "Die Bedingung aus dem Konzeptpapier, bevor eine Ampel gebaut wird:",
        "**Steht das Modell an Fundtagen höher als an zufälligen Tagen",
        "derselben Saison?** Diese Seite beantwortet das mit Zahlen.",
        "",
        "## Wie gemessen wurde",
        "",
        "Zu jeder Fundmeldung aus GBIF (Deutschland, "
        f"{FIRST_YEAR}–{LAST_COMPLETE_YEAR}, taggenau, Ortsgenauigkeit "
        f"besser als {MAX_UNCERTAINTY_M} m) wird ein **Vergleichstag** "
        "am selben Ort im "
        f"selben Jahr gezogen, {CONTROL_MIN_GAP}–{CONTROL_MAX_GAP} Tage "
        "daneben. Für beide Tage rechnet dasselbe Wettermodell einen Wert:",
        "",
        f"**Das laufende Jahr {LAST_COMPLETE_YEAR + 1} zählt nicht mit.** "
        "Seine Saison ist noch nicht vorbei, und ein halbes Pilzjahr wäre "
        "genau die Lücke, die hier sonst überall zum Abbruch führt — "
        "Pilzjahre unterscheiden sich um den Faktor zehn. Die Spalte "
        "„Jahre“ nennt deshalb nur die vollständigen.",
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
        "## Kontrollen: prüfen die Methode",
        "",
        "Zwei Tage OHNE Fund treten gegeneinander an. **Hier muss 0,50 "
        "stehen.** Alles andere hieße, dass schon die Ziehung verzerrt — "
        "und dann wäre jede Zahl in den Tabellen darunter wertlos.",
        "",
        "Es sind zwei, und sie fangen Verschiedenes.",
        "",
        "**Die abstandsgleiche Kontrolle entscheidet** (seit 2026-09-12): "
        "der Vergleichstag gegen seine Spiegelung am Fundtag. Beide liegen "
        "exakt gleich weit weg, nur auf verschiedenen Seiten.",
        "",
        "**Die gepaarte Kontrolle steht daneben**: der Vergleichstag gegen "
        "einen VON IHM AUS gezogenen dritten Tag. Sie war bis 2026-09-12 "
        "der Torwächter und taugt dafür nicht, weil ihre beiden Tage "
        "unterschiedlich weit vom Fundtag entfernt liegen — die Abstände "
        "addieren sich. Und Nähe zum Fundtag hebt den Wert, weil Pilze bei "
        "gutem Wetter kommen und gutes Wetter Wochen anhält. Sie misst "
        "damit auch Abstand, nicht nur Verzerrung. Behalten wird sie "
        "trotzdem: Sie fängt eine EINSEITIGE Ziehung, was die "
        "abstandsgleiche bauartbedingt nicht kann.",
        "",
        "Die Spalte „Rauschen“ ist der Standardfehler bei dieser "
        "Paarzahl (rund 1/(2·√n)). Eine Abweichung, die kleiner ist als "
        "das Doppelte davon, ist von Zufall nicht zu unterscheiden — sie "
        "wird trotzdem markiert, nicht wegerklärt.",
        "",
        "| Art | Paare | abstandsgleich (soll ≈ 0,50) | Rauschen | gepaart |",
        "|---|--:|--:|--:|--:|",
    ]
    for row in mycorrhizal + wood:
        noise = 1 / (2 * math.sqrt(row["mirror_n"])) if row["mirror_n"] else 0
        mark = "" if control_clean(
            row["mirror_auc"], row["mirror_n"]) else " ⚠"
        lines.append(
            f"| {row['name']} | {row['mirror_n']} | "
            f"{row['mirror_auc']:.3f}{mark} | ±{noise:.3f} | "
            f"{row['placebo_auc']:.3f} |")

    failed = [r for r in mycorrhizal + wood
              if not control_clean(r["mirror_auc"], r["mirror_n"])]
    lines += [""]
    if failed:
        # **Je Art, nicht pauschal.** Ein durchgefallener Wächter bei
        # EINER Art sagt nichts über die anderen acht — sie haben ihre
        # eigene Ziehung, ihre eigenen Orte und ihre eigene Paarzahl. Die
        # erste Fassung erklärte den ganzen Bericht für unauswertbar,
        # sobald irgendwo ein ⚠ stand; das ist bequem und falsch.
        lines += ["**Nicht auswertbar sind damit: "
                  + ", ".join(f"{r['name']} ({r['mirror_auc']:.3f}, "
                              f"±{1 / (2 * math.sqrt(r['mirror_n'])):.3f})"
                              for r in failed)
                  + ".** Für alle übrigen Arten hält die Kontrolle, und "
                  "ihre Zahlen stehen.", ""]
    else:
        lines += ["Alle Arten halten die Kontrolle; die Zahlen darunter "
                  "sind auswertbar.", ""]

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

    # Das Urteil über die Arten-Kontrolle schreibt sich selbst.
    #
    # Beim 2000er-Lauf (2026-08-13) fiel sie durch: Hallimasch 0,718 und
    # Stockschwämmchen 0,704 passten so gut wie die Mykorrhiza-Arten. Ein
    # von Hand gesetzter Satz wäre beim nächsten Lauf still falsch
    # geworden — deshalb zählt der Bericht nach, statt zu behaupten.
    fitting = [row for row in wood if row["auc"] >= 0.55]
    if wood:
        # **Klammern, nicht Aneinanderreihung.** Bis 2026-09-12 stand
        # hier `f"…" ", ".join(…)` — zwei Zeichenketten nebeneinander
        # sind in Python implizit EINE, und `.join` bekam damit den
        # ganzen Satz als Trennzeichen. Im Bericht stand dann
        # „Hallimasch 0.7492 von 3 Holzbewohnern passen zum Modell … — ,
        # Stockschwämmchen 0.756“. Sichtbar nur beim Lesen des Ergebnisses.
        namen = ", ".join(f"{r['name']} {r['auc']:.3f}" for r in fitting)
        if fitting:
            urteil = (
                f"{len(fitting)} von {len(wood)} Holzbewohnern passen zum "
                f"Modell (AUC ≥ 0,55) — {namen}. Nach dem Kriterium dieser "
                f"Seite ist die Kontrolle damit NICHT bestanden: Hier "
                f"trennt das Modell nicht nach Gilde."
                f"\n\n"
                f"**Entschieden ist das seit dem 2026-09-12 trotzdem** — "
                f"nur nicht auf dieser Seite. Die Anpassung je Art "
                f"(`docs/pilzampel-artenfenster-messung.md`) zeigt, dass "
                f"die Kontrolle an ihrer AUSWAHL scheiterte: Hallimasch "
                f"und Stockschwämmchen teilen schlicht das Herbstfenster, "
                f"während der Austernseitling ein eigenes, kaltes hat. Das "
                f"Modell wirkt artspezifisch; man muss nur Arten "
                f"vergleichen, die sich wirklich unterscheiden."
                f"\n\n"
                f"**Eine Ampel je ART bleibt dennoch unbegründet**, jetzt "
                f"aus dem umgekehrten Grund: Die Herbstarten liegen alle "
                f"beieinander, und ein eigenes Fenster bringt ihnen "
                f"nichts. Was die Daten stützen, ist eine Unterscheidung "
                f"nach TYP.")
        else:
            urteil = (
                "Kein Holzbewohner passt zum Modell (alle AUC < 0,55). Die "
                "Kontrolle ist bestanden: Das Modell wirkt artspezifisch "
                "und misst nicht bloß „im Herbst wird mehr gemeldet“.")
        lines += ["", "**Ergebnis dieser Kontrolle:** " + urteil]

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
    global OPEN_METEO, SAMPLE_PER_SPECIES, DEDUPE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=None,
                        help="Bericht schreiben (z. B. docs/…​.md)")
    parser.add_argument("--crosscheck", action="store_true",
                        help="zusätzlich die Saisonkurven gegenprüfen")
    parser.add_argument("--crosscheck-only", action="store_true",
                        help="NUR die Saisonkurven gegenprüfen (kein "
                             "Open-Meteo nötig)")
    parser.add_argument("--fit", action="store_true",
                        help="Temperaturoptimum je Art anpassen und "
                             "auf getrennten Jahren prüfen "
                             "(docs/pilzampel-artenfenster.md)")
    parser.add_argument("--compare", action="store_true",
                        help="Ausgelieferte Ampel gegen die mit eigenem "
                             "Fenster — gemessen in STUFEN, nicht in AUC")
    parser.add_argument("--api", default=None,
                        help="Basis-URL der Archiv-API. Vorgabe ist der "
                             "öffentliche Dienst; eine eigene Instanz "
                             "kennt kein Kontingent (#460).")
    parser.add_argument("--cold", action="store_true",
                        help="Der registrierte Kalttest: gibt es eine kalte "
                             "KLASSE? (docs/pilzampel-artenfenster.md)")
    parser.add_argument("--membership", action="store_true",
                        help="Wie weit trägt das AUSGELIEFERTE Fenster? "
                             "Misst es an allen Arten mit genug Material, "
                             "ohne irgendetwas anzupassen "
                             "(docs/pilzampel-herbstklasse-"
                             "mitgliedschaft.md)")
    parser.add_argument("--thresholds", action="store_true",
                        help="Die Schwellen messen statt sie zu setzen — "
                             "als Quantil der Vergleichstage "
                             "(docs/pilzampel-schwellen.md)")
    parser.add_argument("--holdout", default=None,
                        help="Länderkürzel (z. B. AT,CH): in Deutschland "
                             "anpassen, dort prüfen. Braucht --only.")
    parser.add_argument("--class", dest="klass", default=None,
                        help="Hold-out für eine KLASSE statt je Art: Das "
                             "Fenster ist der Median der deutschen Optima "
                             "ihrer Mitglieder, geprüft wird es an allen. "
                             "Braucht --holdout.")
    parser.add_argument("--recover-sample", action="store_true",
                        help="Die Stichprobe suchen, zu der ein vorhandener "
                             "--cache gehört, und sie festnageln. Einmal "
                             "nötig für Sammlungen von vor dem Festnageln.")
    parser.add_argument("--only", default=None,
                        help="Nur diese Arten (kommagetrennt). Für --fit "
                             "gedacht: Das Tageskontingent von Open-Meteo "
                             "reicht nicht für alle neun auf einmal, und "
                             "die vorab festgelegte Vorhersage hängt an "
                             "EINER Art.")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--cache", default=None,
                        help="Verzeichnis für Wetterantworten")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--dataset", default=ampel_basis.DEFAULT_DATASET,
                        choices=sorted(ampel_basis.DATASETS),
                        help="Wetterdatensatz: 'vorgabe' ist Open-Meteos "
                             "'best match' und wechselt 2017 das Instrument "
                             "(reproduziert alte Laeufe); 'pinned' ist "
                             "ERA5-Land + ERA5 ueber alle Jahre")
    parser.add_argument("--window", type=float, default=None,
                        help="Fenster der Klasse von Hand setzen statt es "
                             "abzuleiten — fuer Nachmessungen auf einer "
                             "anderen Messbasis, nie fuer einen neuen "
                             "Hold-out-Versuch")
    parser.add_argument("--dedupe", action="store_true",
                        help="hoechstens eine Meldung je Melder x ~1 km x Tag")
    parser.add_argument("--sample", type=int, default=None,
                        help=f"Meldungen je Art (Vorgabe {SAMPLE_PER_SPECIES})")
    args = parser.parse_args()
    if args.api:
        OPEN_METEO = args.api.rstrip("/")
        print(f"Archiv-API: {OPEN_METEO}", file=sys.stderr)
    if args.sample is not None:
        SAMPLE_PER_SPECIES = args.sample
    DEDUPE = args.dedupe
    use_dataset(args.dataset)
    # **Die Basis steht im Protokoll, immer.** Ein Lauf, dem man nicht
    # ansieht, auf welchem Instrument er lief, ist spaeter nicht mehr
    # einzuordnen — und genau das war der Zustand, den Phase 0 aufraeumt.
    print(f"Datensatz: {DATASET} "
          f"({ampel_basis.dataset_fingerprint(DATASET)}), "
          f"Vorlauf {SPAN_LOOKBACK} d, "
          f"Entdoppeln {'an' if DEDUPE else 'aus'}, "
          f"Stichprobe {SAMPLE_PER_SPECIES}", file=sys.stderr)

    if args.self_test:
        self_test()
        return

    mapping = read_species()

    # **`--fit` ist ein eigener Lauf, keine Zugabe zur Validierung.** Er
    # beantwortet eine andere Frage (`docs/pilzampel-artenfenster.md`) und
    # schreibt einen anderen Bericht; beides in einem Aufruf zu mischen
    # hieße, zwei Ergebnisse in eine Datei zu schreiben.
    if args.compare:
        wanted = MYCORRHIZAL + WOOD_DWELLERS
        if args.only:
            wanted = [n.strip() for n in args.only.split(",") if n.strip()]
        print("Ampel-Vergleich in Stufen:", file=sys.stderr)
        rows = [row for row in (
            compare_species(name, mapping[name], args.cache, args.seed)
            for name in wanted if name in mapping) if row]
        report = render_compare_report(rows, time.strftime("%Y-%m-%d"))
        if args.out:
            open(args.out, "w", encoding="utf-8").write(report)
            print(f"\n{args.out} geschrieben", file=sys.stderr)
        else:
            print(report)
        print("\nZusammenfassung:", file=sys.stderr)
        for row in rows:
            if not row.get("usable"):
                continue
            print(f"  {row['name']:20} {row['differ'] * 100:5.1f} % andere "
                  f"Stufe   (Optimum {row['optimum']:5.1f} °C)",
                  file=sys.stderr)
        return

    if args.thresholds:
        wanted = MYCORRHIZAL + WOOD_DWELLERS
        # **Eine Klasse braucht ihre Mitglieder in diesem Lauf**, sonst
        # bekommt sie keine Schwellen: Gepoolt wird über die
        # Vergleichstage ALLER Mitglieder, jede Art mit gleicher Stimme.
        # Seit der Kalttest bestanden ist, stehen zwei Mitglieder
        # außerhalb der Standardlisten (Judasohr, Samtfußrübling) — ohne
        # diese Zeilen bliebe die kalte Klasse für immer ohne Zahlen,
        # ohne dass es jemandem auffiele.
        #
        # Die ausgelieferten Schwellen rührt das nicht an: Gepoolt wird
        # je Klasse, und `verify_class_constants` rechnet bei jedem Lauf
        # nach, dass herbst und sommer da stehen, wo sie stehen.
        for klass in AMPEL_CLASSES.values():
            for name in klass["members"]:
                if name not in wanted:
                    wanted.append(name)
        if args.only:
            wanted = [n.strip() for n in args.only.split(",") if n.strip()]
        print("Schwellen messen:", file=sys.stderr)
        rows = [row for row in (
            threshold_species(name, mapping[name], args.cache, args.seed)
            for name in wanted if name in mapping) if row]
        # **Erst prüfen, dann rendern.** Wandern die Klassenschwellen von
        # ihren Konstanten weg, bricht der Lauf ab, statt einen Bericht
        # zu schreiben, dessen Zahlen niemand mehr zu Dart passen.
        ship = deployment_quantiles(rows)
        if ship:
            attach_class_scores(rows)
            class_thresholds(rows, ship, verify=True)
        # Fenster UND Schwellen jeder Klasse gegen die Daten — in EINEM
        # Durchgang, damit ein Lauf alle Abweichungen nennt. Bis hierher
        # wachte das Werkzeug nur über die Schwellen; das Fenster der
        # Klasse „herbst_holz" war deshalb mit 11,5 °C von Hand zwischen
        # 11,0 und 12,2 gerundet — die einzige erfundene Zahl in einer
        # sonst vollständig gemessenen Tabelle.
        report = render_threshold_report(rows, time.strftime("%Y-%m-%d"))
        if args.out:
            open(args.out, "w", encoding="utf-8").write(report)
            print(f"\n{args.out} geschrieben", file=sys.stderr)
        else:
            print(report)
        print("\nZusammenfassung:", file=sys.stderr)
        for row in rows:
            if not row.get("usable"):
                continue
            print(f"  {row['name']:20} 0,5 liegt bei "
                  f"{row['rank_guenstig_even'] * 100:5.1f} %   "
                  f"Abstand {row['gap_shipped'] * 100:+5.1f} → "
                  f"{row['gap_both'] * 100:+5.1f} pp", file=sys.stderr)
        return

    if args.membership:
        candidates = membership_candidates()
        if candidates is None:
            raise SystemExit(
                "--membership braucht den lokalen GBIF-Bestand "
                f"({gbif_local.DB_PATH}). Er trägt Kandidatenkreis UND "
                "Saisongipfel; über die API wären das hunderte Abfragen "
                "für eine Liste, die sich täglich ändert. Bauen: "
                "python3 tool/gbif_download.py")
        if args.only:
            wanted = {n.strip() for n in args.only.split(",") if n.strip()}
            unknown = wanted - {c["name"] for c in candidates}
            if unknown:
                raise SystemExit(
                    "Nicht im Kandidatenkreis: " + ", ".join(sorted(unknown))
                    + ". Der Kreis steht in "
                    "docs/pilzampel-herbstklasse-mitgliedschaft.md; ihn "
                    "hier zu erweitern hieße, ihn nach dem ersten Blick "
                    "auf die Zahlen zu ändern.")
            candidates = [c for c in candidates if c["name"] in wanted]
        print(f"Mitgliedschaft am ausgelieferten Fenster "
              f"({_optimum_text(OPTIMUM_C)} °C), {len(candidates)} Arten:",
              file=sys.stderr)
        rows = []
        for index, candidate in enumerate(candidates, start=1):
            print(f"  [{index}/{len(candidates)}] {candidate['name']} "
                  f"({candidate['group']}, {candidate['status']})",
                  file=sys.stderr)
            rows.append(membership_species(
                candidate["name"], candidate["sci"], args.cache, args.seed))
        # **Nicht `verdict` nennen.** So hieß die Variable zuerst, und
        # damit war der modulweite `verdict(auc)` in ganz `main()` eine
        # lokale Zuweisung — der STANDARD-Lauf (ohne --membership) stürzte
        # am Ende mit `UnboundLocalError` ab, nachdem er den ganzen
        # Bericht schon gedruckt hatte. Python entscheidet das je
        # Funktion, nicht je Zweig; dass der Zweig hier gar nicht lief,
        # half also nichts.
        outcome = membership_verdict(rows, candidates)
        report = render_membership_report(rows, candidates, outcome,
                                          time.strftime("%Y-%m-%d"))
        if args.out:
            open(args.out, "w", encoding="utf-8").write(report)
            print(f"\n{args.out} geschrieben", file=sys.stderr)
        else:
            print(report)
        print(f"\n  Ausgang: {outcome['state']} — "
              f"{len(outcome['passed'])} von {len(outcome['measured'])} "
              "gemessenen frischen Herbstarten erfüllen die Bedingung",
              file=sys.stderr)
        return
    if args.holdout:
        if not args.only and not args.klass:
            raise SystemExit("--holdout braucht --only oder --class: Der "
                             "Hold-out prüft eine registrierte Spur, nicht "
                             "alles auf Verdacht.")
        countries = [c.strip().upper() for c in args.holdout.split(",")
                     if c.strip()]
        if args.klass:
            if args.klass not in AMPEL_CLASSES:
                raise SystemExit(
                    f"Unbekannte Klasse „{args.klass}“. Bekannt: "
                    + ", ".join(AMPEL_CLASSES))
            members = AMPEL_CLASSES[args.klass]["members"]
            # **Erst das Fenster, dann die Prüfung.** Es kommt aus den
            # deutschen Optima der Mitglieder und wird bei JEDEM Lauf
            # gerechnet — eine getippte Zahl war hier schon zweimal der
            # Fehler (11,5 von Hand gerundet, 11,6 aus einer Tabelle mit
            # einer Nachkommastelle abgeschrieben).
            print(f"Klassen-Hold-out „{args.klass}“ in "
                  f"{'+'.join(countries)}:", file=sys.stderr)
            print("  Fenster aus den deutschen Optima:", file=sys.stderr)
            fits = []
            for name in members:
                row = fit_species(name, mapping[name], args.cache, args.seed)
                if row:
                    row["klass"] = args.klass
                    fits.append(row)
            window = class_optimum(fits, args.klass)
            if window is None:
                raise SystemExit(
                    "Kein Fenster: keines der Mitglieder ist in Deutschland "
                    "auswertbar.")
            if args.window is not None:
                # **Ein von Hand gesetztes Fenster ist kein neuer
                # Hold-out-Versuch, sondern eine Nachmessung** — und es
                # muss eine geben: Beim Wechsel der Messbasis verschieben
                # sich die angepassten Optima, und damit das abgeleitete
                # Fenster. Ohne diese Möglichkeit ließe sich nie sagen, ob
                # ein anderer Ausgang am INSTRUMENT hing oder daran, dass
                # das Fenster mitgewandert ist.
                #
                # Der abgeleitete Wert wird trotzdem gerechnet und
                # genannt, damit im Protokoll steht, wovon abgewichen wird.
                print(f"  Fenster der Klasse wäre {_optimum_text(window)} °C "
                      f"— gesetzt auf {args.window} °C (Nachmessung)",
                      file=sys.stderr)
                window = args.window
            print(f"  Fenster der Klasse: {_optimum_text(window)} °C",
                  file=sys.stderr)
            rows = [holdout_species(name, mapping[name], countries,
                                    args.cache, args.seed, window=window)
                    for name in members if name in mapping]
            report = render_class_holdout_report(
                rows, countries, args.klass, window, fits,
                time.strftime("%Y-%m-%d"))
            if args.out:
                open(args.out, "w", encoding="utf-8").write(report)
                print(f"\n{args.out} geschrieben", file=sys.stderr)
            else:
                print(report)
            print(f"\n  Ausgang: "
                  f"{class_holdout_verdict(rows, members)['state']}",
                  file=sys.stderr)
            return
        wanted = [n.strip() for n in args.only.split(",") if n.strip()]
        print(f"Hold-out in {'+'.join(countries)}:", file=sys.stderr)
        rows = [holdout_species(name, mapping[name], countries, args.cache,
                                args.seed)
                for name in wanted if name in mapping]
        report = render_holdout_report(rows, countries,
                                       time.strftime("%Y-%m-%d"))
        if args.out:
            open(args.out, "w", encoding="utf-8").write(report)
            print(f"\n{args.out} geschrieben", file=sys.stderr)
        else:
            print(report)
        return

    if args.recover_sample:
        if not args.cache:
            raise SystemExit("--recover-sample braucht --cache: Es sucht die "
                             "Stichprobe, die zu einer vorhandenen Sammlung "
                             "passt.")
        print("Stichprobe wiederherstellen:", file=sys.stderr)
        rows = [recover_sample(name, mapping[name], args.cache, args.seed)
                for name in MYCORRHIZAL + WOOD_DWELLERS if name in mapping]
        print("\nZusammenfassung:", file=sys.stderr)
        for row in rows:
            mark = "  " if row["hits"] == row["years"] else " ⚠"
            print(f"{mark} {row['name']:20} {row['n']:5} Meldungen "
                  f"(−{row['dropped']})   {row['hits']}/{row['years']} Jahre",
                  file=sys.stderr)
        missing = sum(r["years"] - r["hits"] for r in rows)
        print(f"\n  Es fehlen noch {missing} Art-Jahre.", file=sys.stderr)
        return

    if args.cold:
        # Die Artenliste steht in COLD_CANDIDATES und kommt NICHT von der
        # Kommandozeile: Sie ist Teil der registrierten Bedingung. Eine
        # Liste, die der Aufrufer bestimmt, ließe sich nach der Messung
        # passend wählen.
        unknown = [n for n in COLD_CANDIDATES + [COLD_MEMBER]
                   if n not in mapping]
        if unknown:
            raise SystemExit(
                f"Unbekannte Art(en): {', '.join(unknown)}.\n"
                f"Die Art muss in {SPECIES_FILE} mit `sci:` stehen.")
        print("Kalttest (registriert 2026-09-12):", file=sys.stderr)
        rows = [row for row in (
            fit_species(name, mapping[name], args.cache, args.seed)
            for name in COLD_CANDIDATES) if row]
        # **Die Kontextzeile darf den Lauf nicht kosten.** Sie kommt aus
        # dem Cache; fehlt dort etwas, greift sie zum Netz und kann am
        # Tageskontingent scheitern — und dann wäre das Ergebnis der
        # beiden Prüflinge mit ihr verloren. Deshalb läuft sie zuletzt
        # und ihr Scheitern kostet nur sie selbst.
        context = None
        try:
            context = fit_species(COLD_MEMBER, mapping[COLD_MEMBER],
                                  args.cache, args.seed)
        except (RuntimeError, OSError) as error:
            print(f"  {COLD_MEMBER}: Kontextzeile entfällt — {error}",
                  file=sys.stderr)
        report = render_cold_report(rows, context, time.strftime("%Y-%m-%d"))
        if args.out:
            open(args.out, "w", encoding="utf-8").write(report)
            print(f"\n{args.out} geschrieben", file=sys.stderr)
        else:
            print(report)
        print("\nZusammenfassung:", file=sys.stderr)
        for row in rows + ([context] if context else []):
            if not row.get("usable"):
                print(f"  {row['name']:22} zu wenig Material",
                      file=sys.stderr)
                continue
            print(f"  {row['name']:22} Optimum {row['optimum']:5.1f} °C   "
                  f"AUC {row['auc_test_shared']:.3f} → "
                  f"{row['auc_test_fitted']:.3f}  ({row['gain']:+.3f})",
                  file=sys.stderr)
        print(f"  Ausgang: {cold_verdict(rows)['state']}", file=sys.stderr)
        return

    if args.fit:
        wanted = MYCORRHIZAL + WOOD_DWELLERS
        if args.only:
            asked = [n.strip() for n in args.only.split(",") if n.strip()]
            # Geprüft wird gegen die ARTENLISTE DER APP, nicht gegen die
            # Listen hier oben: Eine registrierte Vorhersage darf eine Art
            # benennen, die im Standardlauf nichts zu suchen hat
            # (COLD_CANDIDATES). Ein Tippfehler fällt trotzdem auf.
            unknown = [n for n in asked if n not in mapping]
            if unknown:
                raise SystemExit(
                    f"Unbekannte Art(en): {', '.join(unknown)}.\n"
                    f"Die Art muss in {SPECIES_FILE} mit `sci:` stehen.")
            wanted = asked
        print("Anpassung je Art:", file=sys.stderr)
        rows = [row for row in (
            fit_species(name, mapping[name], args.cache, args.seed)
            for name in wanted if name in mapping)
            if row]
        report = render_fit_report(rows, time.strftime("%Y-%m-%d"))
        if args.out:
            open(args.out, "w", encoding="utf-8").write(report)
            print(f"\n{args.out} geschrieben", file=sys.stderr)
        else:
            print(report)
        print("\nZusammenfassung:", file=sys.stderr)
        for row in rows:
            if not row.get("usable"):
                print(f"  {row['name']:22} zu wenig Material", file=sys.stderr)
                continue
            print(f"  {row['name']:22} Optimum {row['optimum']:5.1f} °C   "
                  f"AUC {row['auc_test_shared']:.3f} → "
                  f"{row['auc_test_fitted']:.3f}  ({row['gain']:+.3f})",
                  file=sys.stderr)
        return

    mycorrhizal = []
    wood = []
    # `--crosscheck` allein braucht KEIN Open-Meteo — nur GBIF und
    # Mushroom Observer. Deshalb lässt es sich getrennt laufen, etwa wenn
    # das Tageskontingent des Wetterdienstes erschöpft ist.
    # **`--only` gilt auch hier.** Bis 2026-09-17 tat es das NICHT: Der
    # Standardlauf ignorierte das Flag stillschweigend und maß trotzdem
    # alle Arten — ein Aufruf mit `--only Steinpilz` lief also eine
    # Stunde länger als verlangt, ohne dass irgendwo stand, warum. Ein
    # Flag, das nichts tut, ist schlimmer als keines.
    only_mycorrhizal, only_wood = MYCORRHIZAL, WOOD_DWELLERS
    if args.only:
        asked = [n.strip() for n in args.only.split(",") if n.strip()]
        unknown = [n for n in asked
                   if n not in MYCORRHIZAL and n not in WOOD_DWELLERS]
        if unknown:
            raise SystemExit(
                f"Unbekannte Art(en) für den Standardlauf: "
                f"{', '.join(unknown)}.\n"
                f"Er kennt nur die Listen MYCORRHIZAL und WOOD_DWELLERS; "
                f"für andere Arten gibt es --fit, --membership oder "
                f"--thresholds.")
        only_mycorrhizal = [n for n in MYCORRHIZAL if n in asked]
        only_wood = [n for n in WOOD_DWELLERS if n in asked]
    if not args.crosscheck_only:
        print("Mykorrhiza-Speisepilze:", file=sys.stderr)
        mycorrhizal = [
            row for row in (
                validate_species(name, mapping[name], args.cache, args.seed)
                for name in only_mycorrhizal if name in mapping)
            if row
        ]
        print("Arten-Kontrolle (Holzbewohner):", file=sys.stderr)
        wood = [
            row for row in (
                validate_species(name, mapping[name], args.cache, args.seed)
                for name in only_wood if name in mapping)
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
    worst = 0.0
    for row in mycorrhizal + wood:
        worst = max(worst, abs(row["mirror_auc"] - 0.5))
    print(f"  Abstandsgleiche Kontrolle (soll 0,50): grösste Abweichung "
          f"{worst:.3f}", file=sys.stderr)
    broken = [row["name"] for row in mycorrhizal + wood
              if not control_clean(row["mirror_auc"], row["mirror_n"])]
    if broken:
        print(f"  ⚠ Nicht auswertbar: {', '.join(broken)} — dort ist die "
              f"Ziehung verzerrt. Die übrigen Arten sind davon nicht "
              f"betroffen.", file=sys.stderr)
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
