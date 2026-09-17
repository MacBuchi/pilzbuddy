"""Die Messbasis der Ampel — Datensatz, Variablen, Paarziehung.

Phase 0.1 bis 0.3 des Fahrplans (`docs/pilzampel-fahrplan.md`), gemessen
und begruendet in `docs/pilzampel-messbasis.md`.

Warum ein eigenes Modul und nicht noch einmal 400 Zeilen in
`ampel_validate.py`: Was hier steht, ist keine Modelllogik, sondern die
Grundlage, auf der jede spaetere Messung ruht — welcher Wetterdatensatz,
welche Variablen, welche Meldungen, welcher Abstand. Das gehoert an eine
Stelle, an der man es ganz lesen kann.

Drei Dinge, die man wissen muss:

- **Der Datensatz ist ab jetzt ein ausdruecklicher Wert, kein Weglassen.**
  `DATASETS["vorgabe"]` ist der alte Zustand (`models=` gar nicht gesetzt,
  Open-Meteos „best match") und bleibt vorhanden, damit frueher gemessene
  Zahlen reproduzierbar sind. `DATASETS["pinned"]` ist die Wahl des
  Betreibers vom 2026-09-17: ERA5-Land fuer Temperatur und Boden, ERA5
  fuer Niederschlag, ueber alle Jahre gleich.
- **Der Datensatz steckt im Cache-Schluessel.** Ohne das koennte ein Lauf
  halb aus dem einen und halb aus dem anderen Instrument kommen, und
  niemand saehe es — genau der stille Ausfall, den der Fahrplan verbietet.
- **Fehlende Werte sind `None` und werden gezaehlt, nie ersetzt.** ERA5
  hinkt rund fuenf Tage hinterher; wo nichts da ist, faellt das Paar
  heraus und taucht in der Statistik auf.

Nur Standardbibliothek, wie jedes Werkzeug in `tool/`.
"""
import json
import math
import os

# --- Der Datensatz ---------------------------------------------------------

# Je Datensatz: eine Liste von (Modell, {Feldname: API-Variable}). Mehrere
# Eintraege heissen mehrere Anfragen je Ortsgruppe — der Preis dafuer,
# dass kein Modell alle Variablen liefert (ERA5-Land hat keinen
# Niederschlag, ERA5 keine Schneehoehe; gemessen in
# `docs/pilzampel-messbasis.md`).
#
# Bewusst NICHT `models=era5_seamless`, obwohl das zahlenidentisch ist
# (auf 0,0000 gemessen): Diese ganze Phase existiert, weil ein unbenannter
# Vorgabewert sich unter uns geaendert hat. Ein Sammelname, dessen Inhalt
# Open-Meteo definiert, wiederholte denselben Baufehler mit kleinerem
# Radius. Zwei ausdrueckliche Modelle sind eine Zeile mehr und eine
# Ueberraschung weniger.
DATASETS = {
    "vorgabe": [
        (None, {"rain": "precipitation_sum", "temp": "temperature_2m_mean"}),
    ],
    "pinned": [
        ("era5_land", {
            "temp": "temperature_2m_mean",
            "tmin": "temperature_2m_min",
            "snow": "snow_depth_max",
            "smoist": "soil_moisture_7_to_28cm_mean",
            "stemp": "soil_temperature_0_to_7cm_mean",
        }),
        ("era5", {"rain": "precipitation_sum"}),
    ],
}

DEFAULT_DATASET = "vorgabe"


def dataset_fields(name):
    """Alle Feldnamen eines Datensatzes, in stabiler Reihenfolge."""
    fields = []
    for _, mapping in DATASETS[name]:
        fields.extend(sorted(mapping))
    return sorted(fields)


def dataset_fingerprint(name):
    """Kurzer Fingerabdruck fuer den Cache-Schluessel.

    Er haengt an Modellen UND Variablen: Wer eine Variable hinzufuegt,
    bekommt einen neuen Schluessel und damit einen ehrlichen Neuabruf,
    statt eine halb gefuellte Reihe aus dem Cache zu erben.
    """
    import hashlib
    payload = json.dumps(
        [[model, sorted(mapping.items())] for model, mapping in DATASETS[name]],
        sort_keys=True)
    return f"{name}-{hashlib.sha256(payload.encode()).hexdigest()[:8]}"


# --- Die Meldungen ---------------------------------------------------------

# Eine Wabe von rund einem Kilometer. Ein Breitengrad sind 111,32 km;
# Laengengrade schrumpfen mit dem Kosinus der Breite, sonst waere eine
# „1-km-Zelle" in Kiel halb so breit wie in Bozen.
KM_PER_DEGREE = 111.32
DEDUPE_KM = 1.0


def grid_cell(lat, lon, km=DEDUPE_KM):
    """Die ~km-Wabe, in der ein Punkt liegt."""
    step = km / KM_PER_DEGREE
    row = math.floor(lat / step)
    # Am Pol geht der Kosinus gegen null; DACH ist weit davon entfernt,
    # aber eine Division durch fast null waere ein stiller Ausreisser.
    shrink = max(math.cos(math.radians(lat)), 0.01)
    column = math.floor(lon * shrink / step)
    return row, column


def dedupe_finds(finds, km=DEDUPE_KM):
    """Hoechstens EINE Meldung je Melder x ~km-Wabe x Tag.

    Der vollstaendige Bestand verstaerkt Exkursions-Cluster: In typischen
    5-km-Zellen stammen rund 69 % der Meldungen von einer Person
    (`tool/gbif_effort.py`). Zehn Fotos derselben Begehung sind zehn
    Paare mit demselben Wetter am selben Ort — sie blaehen die Paarzahl
    auf, ohne eine einzige unabhaengige Beobachtung hinzuzufuegen, und
    die Vertrauensbereiche werden dadurch zu eng.

    **Der Melder bleibt Teil des Schluessels.** Zwei verschiedene
    Menschen, die am selben Tag im selben Kilometer melden, sind zwei
    Beobachtungen und werden nicht zusammengelegt.

    **Eine fehlende Melderangabe zaehlt als EIN Melder.** Das legt
    anonyme Meldungen derselben Wabe und desselben Tages zusammen, also
    moeglicherweise mehr als noetig. Die andere Richtung waere teurer:
    Ohne Namen laesst sich eine Serie aus einer Quelle nicht von
    unabhaengigen Beobachtungen unterscheiden, und dann zaehlte genau der
    Cluster mehrfach, gegen den diese Funktion steht.

    Die Reihenfolge bleibt erhalten — der erste Treffer gewinnt. Bei
    `ORDER BY gbifID` ist das der aelteste Eintrag und damit stabil.
    """
    seen = set()
    kept = []
    dropped = 0
    for find in finds:
        row, column = grid_cell(find["lat"], find["lon"], km)
        key = (find.get("recordedBy") or "", row, column,
               find["year"], find["month"], find["day"])
        if key in seen:
            dropped += 1
            continue
        seen.add(key)
        kept.append(find)
    return kept, dropped


# --- Die Wetterreihen ------------------------------------------------------


def window_of(series, field, day_of_year, length):
    """Die `length` Tage VOR einem Tag, juengster zuerst — oder `None`.

    `None` in drei Faellen, die alle dasselbe bedeuten („dieses Paar ist
    nicht auswertbar"), aber verschiedene Ursachen haben:
      * die Reihe reicht nicht weit genug zurueck,
      * das Feld gibt es in diesem Datensatz nicht,
      * mindestens ein Tag im Fenster ist eine Luecke.

    Der dritte Fall ist neu und noetig: ERA5 hinkt rund fuenf Tage
    hinterher und meldet die fehlenden Tage ehrlich als `null`. Ein
    Mittelwert ueber ein Fenster mit Loechern saehe plausibel aus und
    waere falsch — und eine Summe mit `0.0` fuer fehlenden Regen waere
    schlicht eine erfundene Trockenheit.
    """
    values = series.get(field)
    if values is None:
        return None
    end = day_of_year - series["first"]
    if end - length < 0 or end > len(values):
        return None
    window = list(reversed(values[end - length:end]))
    if any(v is None for v in window):
        return None
    return window


def weather_params(model, mapping, points, start_date, end_date):
    """Die Anfrage an Open-Meteo fuer EIN Modell und seine Variablen."""
    params = {
        "latitude": ",".join(f"{p[0]:.4f}" for p in points),
        "longitude": ",".join(f"{p[1]:.4f}" for p in points),
        "start_date": start_date,
        "end_date": end_date,
        "daily": ",".join(mapping[f] for f in sorted(mapping)),
        "timezone": "Europe/Berlin",
    }
    if model:
        params["models"] = model
    return params


def merge_place(target, mapping, daily):
    """Die Antwort eines Modells in die Reihe eines Ortes einhaengen."""
    for field in sorted(mapping):
        target[field] = daily.get(mapping[field])
    return target


def cache_name(dataset, year, points, first_day, last_day):
    """Der Cache-Schluessel — mit dem Datensatz darin.

    Ohne ihn koennte ein Lauf halb aus dem einen und halb aus dem anderen
    Instrument kommen. Der Ordner allein reicht dafuer nicht: Ordner
    werden kopiert, umbenannt und wiederverwendet.

    **Die Vorgabe behaelt ihren alten Namen ohne Fingerabdruck.** Das ist
    keine Inkonsequenz, sondern der Grund, warum der vorhandene Cache
    weiter gilt: Dort liegen Stunden an geholten Antworten, und
    `recover_sample` und `cache_hits` finden sie ueber genau diesen Namen.
    Ein Fingerabdruck auch fuer die Vorgabe haette jede dieser Dateien
    unsichtbar gemacht — und mit ihnen die Reproduzierbarkeit der schon
    veroeffentlichten Zahlen. Gemischt werden kann trotzdem nichts: Jeder
    andere Datensatz traegt seinen Fingerabdruck und landet damit in
    eigenen Dateien.
    """
    import hashlib
    digest = hashlib.sha256(
        json.dumps([[round(a, 4), round(b, 4)] for a, b in points]).encode()
    ).hexdigest()[:16]
    if dataset == DEFAULT_DATASET:
        return f"weather_{year}_{first_day}_{last_day}_{digest}.json"
    return (f"weather_{dataset_fingerprint(dataset)}_{year}_"
            f"{first_day}_{last_day}_{digest}.json")


# --- Der Vergleichstag -----------------------------------------------------


def control_gaps(longest_window, max_gap=45):
    """Mindest- und Hoechstabstand des Vergleichstags.

    **Der Mindestabstand haengt am geprueften Modell, nicht an einer
    festen Zahl.** Er ist das laengste Fenster dieses Modells: Kuerzer,
    und die beiden Fenster teilen sich Tage — dann vergleicht man ein
    Wetter teilweise mit sich selbst, und Fund- und Vergleichstag sehen
    aehnlicher aus, als sie sind.

    Fuer die ausgelieferte Ampel ist das laengste Fenster das Regenfenster
    mit 26 Tagen, und damit bleibt es bei den bisherigen 26 bis 45.
    """
    if longest_window < 1:
        raise ValueError("Ein Modell ohne Fenster hat keinen Mindestabstand")
    if max_gap <= longest_window:
        raise ValueError(
            f"Hoechstabstand {max_gap} liegt nicht ueber dem Mindestabstand "
            f"{longest_window} — es bliebe kein Spielraum zum Ziehen")
    return longest_window, max_gap


def pick_control(day_of_year, rng, min_gap, max_gap):
    """Ein Vergleichstag, Richtung zufaellig. Gibt den VORZEICHEN-Abstand mit.

    Der Betrag allein reichte bisher; die Richtung wird seit Phase 0.2
    mitgefuehrt, weil der Richtungs-Split aus Phase 1.1 ohne sie nicht
    messbar ist: Eine Reaktion auf das Niveau gibt vor und nach dem Fund
    aehnliche Werte, eine Reaktion auf Abkuehlung nicht.
    """
    gap = rng.randint(min_gap, max_gap)
    if rng.random() < 0.5:
        gap = -gap
    return day_of_year + gap, gap


# --- Selbsttest ------------------------------------------------------------


def self_test():
    # Der Datensatz der Vorgabe muss genau das alte Verhalten sein:
    # kein `models=`, und exakt die beiden alten Variablen.
    assert DATASETS["vorgabe"] == [
        (None, {"rain": "precipitation_sum", "temp": "temperature_2m_mean"})]
    assert dataset_fields("vorgabe") == ["rain", "temp"]
    # Der gepinnte Datensatz traegt beide Modelle und alle sechs Felder.
    assert dataset_fields("pinned") == [
        "rain", "smoist", "snow", "stemp", "temp", "tmin"]
    models = [model for model, _ in DATASETS["pinned"]]
    assert models == ["era5_land", "era5"], models
    # Kein Feld darf aus ZWEI Modellen kommen — sonst entschiede die
    # Reihenfolge der Anfragen, welches Instrument gewinnt.
    seen = set()
    for _, mapping in DATASETS["pinned"]:
        assert not (seen & set(mapping)), seen & set(mapping)
        seen |= set(mapping)

    # Der Fingerabdruck trennt die Datensaetze und ist stabil.
    assert dataset_fingerprint("pinned") != dataset_fingerprint("vorgabe")
    assert dataset_fingerprint("pinned") == dataset_fingerprint("pinned")
    assert dataset_fingerprint("pinned").startswith("pinned-")

    # Und er haengt wirklich an den Variablen, nicht nur am Namen:
    # Gegenprobe ueber eine voruebergehend geaenderte Zuordnung.
    before = dataset_fingerprint("pinned")
    DATASETS["pinned"][1][1]["rain"] = "rain_sum"
    after = dataset_fingerprint("pinned")
    DATASETS["pinned"][1][1]["rain"] = "precipitation_sum"
    assert before != after, "Fingerabdruck ignoriert die Variablenwahl"
    assert dataset_fingerprint("pinned") == before

    # Cache-Schluessel: verschiedene Datensaetze, verschiedene Dateien.
    points = [(51.0, 10.0), (48.0, 11.0)]
    a = cache_name("vorgabe", 2020, points, 100, 300)
    b = cache_name("pinned", 2020, points, 100, 300)
    assert a != b, "Datensatz faellt aus dem Cache-Schluessel"
    # Die Vorgabe muss den ALTEN Namen behalten, sonst ist der vorhandene
    # Cache unsichtbar und alle veroeffentlichten Zahlen unreproduzierbar.
    assert a == "weather_2020_100_300_" + a.split("_")[-1], a
    assert "vorgabe" not in a
    assert b.startswith("weather_pinned-")
    assert cache_name("pinned", 2020, points, 100, 300) == b
    assert cache_name("pinned", 2021, points, 100, 300) != b
    assert cache_name("pinned", 2020, points[::-1], 100, 300) != b

    # Waben: rund ein Kilometer, und in der Laenge kosinus-korrigiert.
    assert grid_cell(51.0, 10.0) == grid_cell(51.0, 10.0)
    assert grid_cell(51.0, 10.0) != grid_cell(51.05, 10.0)   # ~5,6 km
    assert grid_cell(51.0, 10.0) == grid_cell(51.000, 10.001)  # ~70 m
    # Dieselbe Laengendifferenz ist im Norden eine kuerzere Strecke —
    # ohne Kosinus waeren die Zellen dort zu breit.
    assert grid_cell(60.0, 10.0)[1] != grid_cell(51.0, 10.0)[1]

    # Entdoppeln: dieselbe Person, dieselbe Wabe, derselbe Tag -> einer.
    base = {"lat": 51.0, "lon": 10.0, "year": 2020, "month": 9, "day": 3}
    finds = [
        dict(base, recordedBy="A", gbifID=1),
        dict(base, recordedBy="A", gbifID=2),              # Dublette
        dict(base, recordedBy="A", lon=10.0005, gbifID=3),  # 35 m -> Dublette
        dict(base, recordedBy="B", gbifID=4),              # anderer Melder
        dict(base, recordedBy="A", day=4, gbifID=5),       # anderer Tag
        dict(base, recordedBy="A", lat=51.05, gbifID=6),   # andere Wabe
    ]
    kept, dropped = dedupe_finds(finds)
    assert dropped == 2, dropped
    assert [f["gbifID"] for f in kept] == [1, 4, 5, 6], kept
    # Ohne Melderangabe zaehlen alle als EIN Melder.
    anon = [dict(base, recordedBy=None, gbifID=7),
            dict(base, recordedBy="", gbifID=8)]
    kept, dropped = dedupe_finds(anon)
    assert len(kept) == 1 and dropped == 1

    # Fenster: juengster Tag zuerst, und Loecher sind toedlich.
    series = {"first": 0, "temp": [float(d) for d in range(10)],
              "rain": [0.0] * 5 + [None] + [0.0] * 4}
    assert window_of(series, "temp", 5, 3) == [4.0, 3.0, 2.0]
    assert window_of(series, "temp", 2, 3) is None      # reicht nicht zurueck
    assert window_of(series, "temp", 99, 3) is None     # zu weit vorn
    assert window_of(series, "rain", 5, 3) == [0.0, 0.0, 0.0]
    assert window_of(series, "rain", 8, 3) is None, "Luecke durchgelassen"
    assert window_of(series, "tmin", 5, 3) is None      # Feld fehlt

    # Der Versatz `first` wird beachtet.
    shifted = {"first": 100, "temp": [float(d) for d in range(10)]}
    assert window_of(shifted, "temp", 105, 2) == [4.0, 3.0]

    # Abstaende: der Mindestabstand ist das laengste Fenster.
    assert control_gaps(26) == (26, 45)
    assert control_gaps(30) == (30, 45)
    for bad in (0, -1):
        try:
            control_gaps(bad)
        except ValueError:
            pass
        else:
            raise AssertionError("Fenster ohne Laenge angenommen")
    try:
        control_gaps(45)
    except ValueError:
        pass
    else:
        raise AssertionError("Hoechstabstand gleich Mindestabstand angenommen")

    # Der Vergleichstag traegt sein Vorzeichen.
    import random
    rng = random.Random(42)
    both = set()
    for _ in range(200):
        day, gap = pick_control(100, rng, 26, 45)
        assert day == 100 + gap
        assert 26 <= abs(gap) <= 45
        both.add(gap > 0)
    assert both == {True, False}, "Die Ziehung ist einseitig"

    # Die Anfrage traegt das Modell — und laesst es bei der Vorgabe weg.
    params = weather_params("era5_land", {"temp": "temperature_2m_mean"},
                            [(51.0, 10.0)], "2020-01-01", "2020-01-31")
    assert params["models"] == "era5_land"
    assert params["daily"] == "temperature_2m_mean"
    assert "models" not in weather_params(
        None, {"temp": "temperature_2m_mean"}, [(51.0, 10.0)],
        "2020-01-01", "2020-01-31")

    # Zusammenfuehren: jedes Modell schreibt nur SEINE Felder.
    place = {"first": 0}
    merge_place(place, {"temp": "temperature_2m_mean"},
                {"temperature_2m_mean": [1.0, 2.0]})
    merge_place(place, {"rain": "precipitation_sum"},
                {"precipitation_sum": [0.0, 3.0]})
    assert place == {"first": 0, "temp": [1.0, 2.0], "rain": [0.0, 3.0]}
    # Eine fehlende Variable wird None und nicht eine leere Liste — sonst
    # saehe „nicht geliefert" aus wie „keine Tage".
    merge_place(place, {"snow": "snow_depth_max"}, {})
    assert place["snow"] is None

    print("Selbsttest ok")


if __name__ == "__main__":
    self_test()


def self_test_quiet():
    """Wie [self_test], nur ohne die Erfolgsmeldung.

    `ampel_validate.py` ruft ihn mit auf: Die beiden Dateien teilen sich
    die Messbasis, und ein Werkzeug, dessen Grundlage ungeprueft bleibt,
    prueft sich selbst nur zur Haelfte.
    """
    import io
    import contextlib
    with contextlib.redirect_stdout(io.StringIO()):
        self_test()
