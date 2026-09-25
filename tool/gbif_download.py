#!/usr/bin/env python3
"""Holt den Pilzbestand für DACH und den Alpenraum aus GBIF und macht
ihn lokal abfragbar.

    python3 tool/gbif_download.py request     # Download anstoßen
    python3 tool/gbif_download.py status      # läuft er noch?
    python3 tool/gbif_download.py fetch       # ZIP holen
    python3 tool/gbif_download.py build       # nach SQLite
    python3 tool/gbif_download.py --self-test # ohne Netz

WARUM ÜBERHAUPT. Dieselbe Begründung wie bei der eigenen
Open-Meteo-Instanz (#460/#461, docs/pilzampel-openmeteo-lokal.md): Die
Messungen sind über die Cloud-API nicht durchführbar. Die Suche kriecht
beim tiefen Blättern (ab `offset` ~10 000 braucht eine Seite 341 s statt
0,3 s, siehe tool/gbif_effort.py), und für 3,8 Mio Datensätze wären das
Stunden — für einen Zweck, für den GBIF ausdrücklich Downloads vorsieht.

DER DOI IST DER EIGENTLICHE GEWINN, nicht die Geschwindigkeit. Jeder
Download bekommt einen, und der nagelt den Stand fest. Bisher löste
`fetch_finds` (tool/ampel_validate.py) dasselbe Problem mit einer
Cache-Datei, weil GBIF täglich wächst: Zwei Läufe derselben Art lieferten
im Abstand von zwei Stunden 2259 gegen 2253 Meldungen — und damit eine
andere Stichprobe. Ein DOI ist dieselbe Zusage, nur zitierfähig, und er
erledigt zugleich die CC-BY-Namensnennung über alle Quell-Datasets.

BEWUSST GROSSZÜGIG GEFILTERT. Der Download nimmt alle Pilze mit
Koordinate in DACH und Liechtenstein, dazu Italien im Alpenraum
(`ALPINE_ITALY`, seit #612) — **ohne** Lizenz-, Genauigkeits- oder
basisOfRecord-Filter. Die stehen als SPALTEN zur Verfügung und werden
lokal gesetzt. Enger zu ziehen spart einmalig Platz und kostet bei der
nächsten Frage einen neuen Download; der Effort-Nenner (#467) braucht
ohnehin alles, auch die Bodenproben, die kein Sammler je sieht.

ZUGANGSDATEN kommen aus der UMGEBUNG, nicht aus einem einprogrammierten
Pfad: `GBIF_USER`/`GBIF_PW` direkt, oder `GBIF_ACCOUNT` (Datei) bzw.
`KEYS_DIR` (Ordner). Wo die Datei liegt, steht in der internen Doku und
bewusst nicht hier — dieses Repo ist öffentlich, und ein Pfad verrät den
Aufbau einer fremden Maschine, auch wenn er von außen nicht erreichbar
ist. Die Datei wird gelesen, nie geschrieben und nie ausgegeben.

Nur Standardbibliothek — sqlite3 ist Teil davon.
"""
import argparse
import base64
import csv
import io
import json
import os
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

API = "https://api.gbif.org/v1"
HOME = os.path.expanduser("~")
def cred_paths():
    """Wo nach den Zugangsdaten gesucht wird — aus der Umgebung, nicht
    aus dem Quelltext.

    Bis zum 2026-09-18 standen hier zwei feste Pfade, einer davon im
    synchronisierten Austauschordner. Beides gehört nicht in
    ein öffentliches Repo: der erste, weil er den Aufbau einer fremden
    Maschine beschreibt, der zweite zusätzlich, weil er einen Ort
    empfahl, an dem Geheimnisse nichts verloren haben.
    """
    kandidaten = []
    datei = os.environ.get("GBIF_ACCOUNT")
    if datei:
        kandidaten.append(os.path.expanduser(datei))
    ordner = os.environ.get("KEYS_DIR")
    if ordner:
        kandidaten.append(
            os.path.join(os.path.expanduser(ordner), "gbif_account.md"))
    return kandidaten


CRED_HINT = (
    "Keine GBIF-Zugangsdaten gefunden.\n"
    "  Entweder GBIF_USER und GBIF_PW setzen, oder den Ablageort nennen:\n"
    "    export KEYS_DIR=<Schlüsselordner>      # enthält gbif_account.md\n"
    "    export GBIF_ACCOUNT=<Pfad zur Datei>   # oder direkt die Datei\n"
    "  Wo das ist, steht in der internen Doku (DocuHub,\n"
    "  guidelines/signing-und-secrets.md) und nicht in diesem Repo.")
STORE = os.path.expanduser(os.environ.get("GBIF_STORE", "~/pilzbuddy-gbif"))
DB = os.path.join(STORE, "dach_fungi.sqlite")
KEYFILE = os.path.join(STORE, "download.json")

# Die Spalten, die wir aus SIMPLE_CSV behalten. Alles Übrige (Institution,
# Katalognummer, Medien …) beantwortet keine unserer Fragen und würde die
# Datenbank ohne Gegenwert verdoppeln.
COLUMNS = [
    ("gbifID", "INTEGER PRIMARY KEY"), ("datasetKey", "TEXT"),
    ("species", "TEXT"), ("genus", "TEXT"), ("speciesKey", "INTEGER"),
    ("decimalLatitude", "REAL"), ("decimalLongitude", "REAL"),
    ("coordinateUncertaintyInMeters", "REAL"),
    ("day", "INTEGER"), ("month", "INTEGER"), ("year", "INTEGER"),
    ("basisOfRecord", "TEXT"), ("license", "TEXT"),
    ("recordedBy", "TEXT"), ("countryCode", "TEXT"),
]

# Die Länder, die GANZ im Bestand liegen. Liechtenstein seit dem zweiten
# Download (#612): Es lag mitten in der Box aller Gitter und fehlte nur,
# weil niemand es aufgeschrieben hatte.
COUNTRIES = ["DE", "AT", "CH", "LI"]

# Italien nur im Alpenraum (#612, Südtirol). Ganz Italien wären 471 000
# Meldungen, die meisten davon aus dem Mittelmeerklima — für eine
# Hold-out-Messung der Alpen-Klassen wären sie Rauschen, für die Karte
# außerhalb der Box. Der Schnitt ist eine Box, keine Landesgrenze:
# Aostatal bis Friaul, südlich bis an den Alpenrand (Bergamo liegt drin,
# Brescia und Mailand nicht). GEMESSEN am 2026-09-25 über die Such-API:
# 138 962 Meldungen in der Box, 69 265 davon in Südtirol selbst.
#
# **`IT` im Bestand HEISST damit „italienische Alpen".** Wer
# `--holdout IT` in tool/ampel_validate.py aufruft, prüft diese Box —
# nicht Italien.
ALPINE_ITALY = {"west": 6.6, "south": 45.6, "east": 13.9, "north": 47.2}


def _alpine_italy_wkt(box=ALPINE_ITALY):
    """Die Box als WKT-Polygon, gegen den Uhrzeigersinn, wie GBIF es will."""
    w, s, e, n = box["west"], box["south"], box["east"], box["north"]
    return f"POLYGON(({w} {s},{e} {s},{e} {n},{w} {n},{w} {s}))"


PREDICATE = {
    "type": "and",
    "predicates": [
        {"type": "equals", "key": "TAXON_KEY", "value": "5"},      # Fungi
        {"type": "or", "predicates": [
            {"type": "in", "key": "COUNTRY", "values": COUNTRIES},
            {"type": "and", "predicates": [
                {"type": "equals", "key": "COUNTRY", "value": "IT"},
                {"type": "within", "geometry": _alpine_italy_wkt()},
            ]},
        ]},
        {"type": "equals", "key": "HAS_COORDINATE", "value": "true"},
        {"type": "equals", "key": "HAS_GEOSPATIAL_ISSUE", "value": "false"},
    ],
}


# ------------------------------------------------------------ Zugang

def credentials():
    """(Benutzer, Passwort) — aus Umgebung oder Kontodatei.

    Gibt NIE etwas davon aus; Fehler nennen nur den Pfad.
    """
    if os.environ.get("GBIF_USER") and os.environ.get("GBIF_PW"):
        return os.environ["GBIF_USER"], os.environ["GBIF_PW"]
    for path in cred_paths():
        if not os.path.exists(path):
            continue
        text = io.open(path, encoding="utf-8").read()

        def grab(name):
            m = re.search(
                rf'^[^\S\n]*[-*#>\s]*\**{name}\**\s*[:=]\s*(.+?)\s*$',
                text, re.M | re.I)
            if not m:
                return None
            value = re.sub(r'^[`*_<]+|[`*_>]+$', '', m.group(1).strip())
            # Markdown-Escapes zurueckdrehen. Ein Passwort mit Sonder-
            # zeichen wird beim Ablegen in einer .md-Datei leicht zu
            # `\*` oder `\@` — der Backslash gehoert dann NICHT dazu.
            # Genau daran ist die erste Anmeldung gescheitert
            # (2026-09-16): 20 statt 19 Zeichen, Login im Browser
            # funktionierte, die API lehnte mit 401 ab, und die
            # Fehlermeldung von GBIF unterscheidet nicht zwischen
            # falschem Passwort und unbekanntem Konto.
            value = re.sub(r'\\([\\`*_{}\[\]()#+\-.!@~|])', r'\1', value)
            return value or None
        user, pw = grab("User"), grab("PW")
        if user and pw:
            return user, pw
        raise SystemExit(f"{path}: 'User' oder 'PW' nicht lesbar.")
    raise SystemExit(CRED_HINT)


def _call(path, method="GET", payload=None):
    user, pw = credentials()
    auth = base64.b64encode(f"{user}:{pw}".encode()).decode()
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        f"{API}/{path}", data=data, method=method,
        headers={"Authorization": "Basic " + auth,
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as handle:
            body = handle.read().decode("utf-8", "replace")
            return json.loads(body) if body.strip().startswith(("{", "[")) \
                else body.strip()
    except urllib.error.HTTPError as exc:
        if exc.code == 401:
            raise SystemExit(
                "GBIF lehnt die Anmeldung ab (401). Häufigste Ursache bei "
                "einem neuen Konto: die Bestätigungsmail ist noch nicht "
                "angeklickt — vorher ist es für die API nicht aktiv. "
                "Sonst Benutzername/Passwort prüfen.")
        raise SystemExit(f"GBIF {exc.code} {exc.reason}: "
                         f"{exc.read(300).decode('utf-8', 'replace')}")


# --------------------------------------------------------- Download

def request_download():
    user, _ = credentials()
    key = _call("occurrence/download/request", "POST", {
        "creator": user, "sendNotification": False,
        "format": "SIMPLE_CSV", "predicate": PREDICATE,
    })
    os.makedirs(STORE, exist_ok=True)
    with open(KEYFILE, "w", encoding="utf-8") as handle:
        json.dump({"key": str(key), "requested": time.time()}, handle)
    print(f"Download angefordert: {key}\n"
          f"  Status: python3 tool/gbif_download.py status")
    return str(key)


def _key():
    if not os.path.exists(KEYFILE):
        raise SystemExit("Kein Download angefordert — erst 'request'.")
    return json.load(open(KEYFILE, encoding="utf-8"))["key"]


def status(quiet=False):
    meta = _call(f"occurrence/download/{_key()}")
    if not quiet:
        print(f"Status : {meta.get('status')}")
        print(f"Treffer: {meta.get('totalRecords', 0):,}")
        if meta.get("doi"):
            print(f"DOI    : {meta['doi']}")
        if meta.get("size"):
            print(f"Größe  : {meta['size'] / 1e6:.0f} MB")
    return meta


def fetch():
    meta = status(quiet=True)
    if meta.get("status") not in ("SUCCEEDED", "FILE_ERASED"):
        raise SystemExit(f"Noch nicht fertig (Status {meta.get('status')}).")
    os.makedirs(STORE, exist_ok=True)
    target = os.path.join(STORE, f"{_key()}.zip")
    if os.path.exists(target):
        print(f"Liegt schon: {target}")
        return target
    url = meta.get("downloadLink")
    print(f"Lade {meta.get('size', 0) / 1e6:.0f} MB …")
    urllib.request.urlretrieve(url, target)
    # Der DOI gehört neben die Daten: Ohne ihn ist der Stand nicht
    # zitierfähig, und die CC-BY-Namensnennung hängt daran.
    with open(os.path.join(STORE, "CITATION.txt"), "w",
              encoding="utf-8") as handle:
        handle.write(f"GBIF Occurrence Download {meta.get('doi', '?')}\n"
                     f"abgerufen am {time.strftime('%Y-%m-%d')}\n"
                     f"{meta.get('totalRecords', 0)} Datensätze\n")
    print(f"Gespeichert: {target}")
    return target


# ----------------------------------------------------------- SQLite

def build(zip_path=None, db_path=DB):
    zip_path = zip_path or os.path.join(STORE, f"{_key()}.zip")
    if os.path.exists(db_path):
        os.remove(db_path)
    con = sqlite3.connect(db_path)
    con.execute("PRAGMA journal_mode=OFF")
    con.execute("PRAGMA synchronous=OFF")
    con.execute("CREATE TABLE occ (%s)" %
                ", ".join(f"{n} {t}" for n, t in COLUMNS))
    names = [n for n, _ in COLUMNS]
    placeholders = ",".join("?" * len(names))
    with zipfile.ZipFile(zip_path) as archive:
        inner = [n for n in archive.namelist() if n.endswith(".csv")][0]
        with archive.open(inner) as raw:
            stream = io.TextIOWrapper(raw, encoding="utf-8", newline="")
            reader = csv.DictReader(stream, delimiter="\t")
            batch, total = [], 0
            for row in reader:
                batch.append(tuple(_cast(row.get(n), t)
                                   for n, t in COLUMNS))
                if len(batch) >= 50000:
                    con.executemany(f"INSERT OR IGNORE INTO occ VALUES "
                                    f"({placeholders})", batch)
                    total += len(batch)
                    print(f"  {total:,} Zeilen", file=sys.stderr)
                    batch = []
            if batch:
                con.executemany(f"INSERT OR IGNORE INTO occ VALUES "
                                f"({placeholders})", batch)
                total += len(batch)
    # Der räumliche Index trägt die Messungen: Ohne ihn ist jede
    # Regionsabfrage ein voller Tabellenscan über Millionen Zeilen.
    con.execute("CREATE INDEX occ_pos ON occ "
                "(decimalLatitude, decimalLongitude)")
    con.execute("CREATE INDEX occ_species ON occ (species)")
    con.execute("CREATE INDEX occ_month ON occ (month)")
    con.commit()
    con.close()
    print(f"{total:,} Zeilen in {db_path} "
          f"({os.path.getsize(db_path) / 1e6:.0f} MB)")
    return total


def _cast(value, sqltype):
    if value is None or value == "":
        return None
    if sqltype.startswith("INTEGER"):
        try:
            return int(float(value))
        except ValueError:
            return None
    if sqltype.startswith("REAL"):
        try:
            return float(value)
        except ValueError:
            return None
    return value


# -------------------------------------------------------- Selbsttest

def self_test():
    import tempfile
    tmp = tempfile.mkdtemp()
    csv_path = os.path.join(tmp, "occurrence.csv")
    header = [n for n, _ in COLUMNS]
    with io.open(csv_path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t")
        writer.writerow(header + ["institutionCode"])   # Extraspalte ignoriert
        writer.writerow([1, "ds", "Boletus edulis", "Boletus", 111,
                         51.5, 10.2, "25.0", 3, 9, 2024,
                         "HUMAN_OBSERVATION", "CC0_1_0", "wer", "DE", "x"])
        writer.writerow([2, "ds", "", "Amanita", 222,
                         48.1, 11.5, "", "", 10, 2023,
                         "MATERIAL_SAMPLE", "CC_BY_4_0", "", "DE", "x"])
    zip_path = os.path.join(tmp, "t.zip")
    with zipfile.ZipFile(zip_path, "w") as archive:
        archive.write(csv_path, "occurrence.csv")
    db_path = os.path.join(tmp, "t.sqlite")
    assert build(zip_path, db_path) == 2
    con = sqlite3.connect(db_path)
    row = con.execute("SELECT species, coordinateUncertaintyInMeters, day "
                      "FROM occ WHERE gbifID=1").fetchone()
    assert row == ("Boletus edulis", 25.0, 3), row
    row = con.execute("SELECT species, coordinateUncertaintyInMeters, day "
                      "FROM occ WHERE gbifID=2").fetchone()
    assert row == (None, None, None), row   # Leerstrings werden NULL
    got = con.execute("SELECT COUNT(*) FROM occ WHERE "
                      "decimalLatitude BETWEEN 51 AND 52").fetchone()[0]
    assert got == 1, got
    con.close()
    # Das Prädikat: Italien NUR mit Box, die Box gegen den Uhrzeigersinn
    # und geschlossen. Ein „IT" ohne Geometrie holte 471 000 Meldungen
    # aus dem Mittelmeerraum in einen Bestand, der „Alpen" verspricht.
    ors = [p for p in PREDICATE["predicates"] if p["type"] == "or"][0]
    plain = [p for p in ors["predicates"] if p["type"] == "in"][0]
    assert "IT" not in plain["values"], plain
    assert "LI" in plain["values"], plain
    italy = [p for p in ors["predicates"] if p["type"] == "and"][0]
    kinds = {p["type"] for p in italy["predicates"]}
    assert kinds == {"equals", "within"}, kinds
    wkt = _alpine_italy_wkt()
    assert wkt.startswith("POLYGON((6.6 45.6,13.9 45.6,13.9 47.2,6.6 47.2,"
                          "6.6 45.6))"), wkt
    print("Selbsttest ok")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("step", nargs="?",
                    choices=["request", "status", "fetch", "build"])
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        self_test()
        return
    if not args.step:
        ap.error("Schritt fehlt (request/status/fetch/build)")
    {"request": request_download, "status": status,
     "fetch": fetch, "build": build}[args.step]()


if __name__ == "__main__":
    main()
