#!/usr/bin/env python3
"""Der lokale GBIF-Bestand als Quelle für die Mess-Skripte.

Gebaut von `tool/gbif_download.py`; dort steht auch, warum es ihn gibt.
Dieses Modul ist nur der Zugriff — gemeinsam, damit `season_curves.py`
und `ampel_validate.py` nicht zwei Fassungen desselben Filters führen,
die auseinanderlaufen können.

**Der Bestand ist optional.** Fehlt er, liefert [connect] `None`, und
jeder Aufrufer geht seinen bisherigen Weg über die API weiter. Das ist
Absicht: Die Skripte müssen auf einem frischen Rechner und in CI ohne
889-MB-Datei laufen.

**Derselbe Schnitt wie der Netzweg.** `WHERE_USABLE` bildet
`BASE_FILTER` aus `season_curves.py` nach — menschliche Beobachtungen
unter CC0/CC BY. Der Download selbst ist bewusst ungefiltert; gefiltert
wird hier, damit eine andere Frage später keinen neuen Download braucht.
"""
import os
import sqlite3

DB_PATH = os.path.expanduser(
    os.environ.get("GBIF_DB", "~/pilzbuddy-gbif/dach_fungi.sqlite"))

# Muss mit season_curves.BASE_FILTER übereinstimmen. Ein Test wacht darüber.
WHERE_USABLE = ("basisOfRecord = 'HUMAN_OBSERVATION' "
                "AND license IN ('CC0_1_0', 'CC_BY_4_0')")


def connect(path=None):
    """Die Datenbank — oder `None`, wenn es sie nicht gibt."""
    target = path or DB_PATH
    if not os.path.exists(target):
        return None
    return sqlite3.connect(f"file:{target}?mode=ro", uri=True)


def month_counts(con, extra="1=1", args=()):
    """Meldungen je Monat (Index 0 = Januar) plus Gesamtzahl.

    Gleiche Form wie `season_curves.month_counts`, damit der Aufrufer
    nicht unterscheiden muss, woher die Zahlen kommen.
    """
    counts = [0] * 12
    for month, number in con.execute(
            f"SELECT month, COUNT(*) FROM occ WHERE {WHERE_USABLE} "
            f"AND month IS NOT NULL AND {extra} GROUP BY month", args):
        counts[month - 1] = number
    total = con.execute(
        f"SELECT COUNT(*) FROM occ WHERE {WHERE_USABLE} AND {extra}",
        args).fetchone()[0]
    return counts, total


def taxon_where(sci, rank, key=None):
    """Wie eine Art bzw. Gattung in der Tabelle zu finden ist.

    **Für Arten über `speciesKey`, nicht über den Namen.** Der
    Namens-String ist nicht eindeutig: Bei der Krausen Glucke fängt
    `species = 'Sparassis crispa'` 2137 Meldungen ein, wo die API unter
    ihrem `taxonKey` 1701 zählt — 436 zu viel, still und plausibel
    aussehend. Der Key ist derselbe, den `check_taxon` von GBIF holt,
    und trifft damit genau das, was der Netzweg fragt (nachgemessen:
    58 von 91 Arten exakt, der Rest im Rahmen des Geo-Filters).

    Für Gattungen bleibt der Name: Einen `genusKey` führt die Tabelle
    nicht, und dort ist der Name eindeutig.
    """
    if rank == "GENUS":
        return "genus = ?", (sci,)
    if key is None:
        return "species = ?", (sci,)
    return "speciesKey = ?", (key,)


def finds(con, sci, rank, first_year, max_uncertainty_m, key=None):
    """Fundmeldungen mit Koordinate und taggenauem Datum.

    Spiegelt `ampel_validate._fetch_finds_raw`. Die Unschärfe wird wie
    dort behandelt: **fehlende Angabe wird durchgelassen**, zu grobe
    fliegt raus.
    """
    where, args = taxon_where(sci, rank, key)
    rows = con.execute(
        f"SELECT decimalLatitude, decimalLongitude, year, month, day "
        f"FROM occ WHERE {WHERE_USABLE} AND {where} "
        f"  AND year >= ? AND day IS NOT NULL AND month IS NOT NULL "
        f"  AND (coordinateUncertaintyInMeters IS NULL "
        f"       OR coordinateUncertaintyInMeters <= ?) "
        f"ORDER BY gbifID",
        (*args, first_year, max_uncertainty_m)).fetchall()
    return [{"lat": r[0], "lon": r[1], "year": r[2], "month": r[3],
             "day": r[4]} for r in rows]


def self_test():
    import tempfile
    path = os.path.join(tempfile.mkdtemp(), "t.sqlite")
    con = sqlite3.connect(path)
    con.execute("CREATE TABLE occ (gbifID INTEGER PRIMARY KEY, species TEXT, "
                "genus TEXT, decimalLatitude REAL, decimalLongitude REAL, "
                "coordinateUncertaintyInMeters REAL, day INTEGER, "
                "month INTEGER, year INTEGER, basisOfRecord TEXT, "
                "license TEXT)")
    rows = [
        (1, "Boletus edulis", "Boletus", 51.0, 10.0, 25.0, 3, 9, 2024,
         "HUMAN_OBSERVATION", "CC0_1_0"),
        (2, "Boletus edulis", "Boletus", 51.1, 10.1, None, 4, 9, 2024,
         "HUMAN_OBSERVATION", "CC_BY_4_0"),
        # zu grob -> faellt bei finds() raus, zaehlt aber im Monat mit
        (3, "Boletus edulis", "Boletus", 51.2, 10.2, 9000.0, 5, 10, 2024,
         "HUMAN_OBSERVATION", "CC0_1_0"),
        # falsche Lizenz -> zaehlt nirgends
        (4, "Boletus edulis", "Boletus", 51.3, 10.3, 10.0, 6, 9, 2024,
         "HUMAN_OBSERVATION", "CC_BY_NC_4_0"),
        # Bodenprobe -> zaehlt nirgends
        (5, "Boletus edulis", "Boletus", 51.4, 10.4, 10.0, 7, 9, 2024,
         "MATERIAL_SAMPLE", "CC0_1_0"),
        # zu alt -> faellt bei finds() raus
        (6, "Boletus edulis", "Boletus", 51.5, 10.5, 10.0, 8, 9, 1999,
         "HUMAN_OBSERVATION", "CC0_1_0"),
    ]
    con.executemany("INSERT INTO occ VALUES (?,?,?,?,?,?,?,?,?,?,?)", rows)
    con.commit(); con.close()

    con = connect(path)
    assert con is not None
    counts, total = month_counts(con, *taxon_where("Boletus edulis", "SPECIES"))
    assert total == 4, total                  # 4 und 5 raus
    assert counts[8] == 3 and counts[9] == 1, counts
    counts, total = month_counts(con, *taxon_where("Boletus", "GENUS"))
    assert total == 4, total

    got = finds(con, "Boletus edulis", "SPECIES", 2006, 1000)
    assert len(got) == 2, got                 # 3 zu grob, 6 zu alt
    assert {g["day"] for g in got} == {3, 4}, got
    assert all(g["lat"] and g["lon"] for g in got)

    assert connect("/nicht/vorhanden.sqlite") is None

    # Die Zusage aus dem Kopf dieser Datei: derselbe Schnitt wie der
    # Netzweg. Laufen die beiden auseinander, liefern lokaler Lauf und
    # API-Lauf verschiedene Kurven — und niemand merkt es, weil beide
    # plausibel aussehen.
    import importlib.util as _il
    _s = _il.spec_from_file_location(
        "sc", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "season_curves.py"))
    sc = _il.module_from_spec(_s)
    _s.loader.exec_module(sc)
    assert sc.BASE_FILTER["basisOfRecord"] == "HUMAN_OBSERVATION", \
        "season_curves filtert anders als WHERE_USABLE"
    assert set(sc.BASE_FILTER["license"]) == {"CC0_1_0", "CC_BY_4_0"}, \
        "Lizenzliste weicht von WHERE_USABLE ab"
    for token in ("HUMAN_OBSERVATION", "CC0_1_0", "CC_BY_4_0"):
        assert token in WHERE_USABLE, token
    # Der Download muss den Geo-Filter setzen, den BASE_FILTER erwartet —
    # sonst enthaelt der Bestand Zeilen, die der Netzweg nie sieht.
    assert sc.BASE_FILTER.get("hasGeospatialIssue") == "false", \
        "BASE_FILTER ohne hasGeospatialIssue — der Bestand ist enger gefasst"

    print("Selbsttest ok")


if __name__ == "__main__":
    self_test()
