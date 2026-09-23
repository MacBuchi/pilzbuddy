#!/usr/bin/env python3
"""Lädt die Bilder zu einem Feedback-Issue auf DIESEN Rechner.

    python3 tool/feedback_photos.py 568            # ein Issue
    python3 tool/feedback_photos.py 568 571 --out ~/tmp/bilder
    python3 tool/feedback_photos.py --self-test

WARUM ES DAS GIBT: Bilder am Feedback (#525, bis zu drei seit #569) sind
NICHT öffentlich. Das Issue nennt deshalb nur die Dateinamen — kein
Pfad, keine Nutzer-id, kein Link, der für jeden Leser funktionierte. Im
Dashboard hieß das: Bucket öffnen, Ordner raten, Namen suchen. Dieses
Werkzeug nimmt die Namen aus dem Issue, sucht die Zeile in `feedback`
und holt die Objekte mit dem Service-Schlüssel.

ES VERÖFFENTLICHT NICHTS. Die Bilder landen in einem Ordner AUSSERHALB
des Repos (Vorgabe `~/pilzbuddy-feedback-photos/<issue>/`), und nichts
wird hochgeladen, kommentiert oder geändert. Ob ein Bild in die
Artgalerie darf, steht im Issue (Patch 034) und wird hier nur angezeigt.

DER SCHLÜSSEL kommt aus `SUPABASE_SERVICE_ROLE_KEY` oder — ohne sie —
aus der angemeldeten Supabase-CLI (`supabase projects api-keys`). Er
wird nie ausgegeben und nie gespeichert.

Braucht `gh` (angemeldet). Nur Standardbibliothek.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, timedelta

# Öffentlich: steht in lib/core/supabase_config.dart.
PROJECT_REF = "tntlujexvdtkynxbrdsn"
URL = f"https://{PROJECT_REF}.supabase.co"
BUCKET = "feedback-photos"
DEFAULT_OUT = "~/pilzbuddy-feedback-photos"

# Der Satz, den `feedback_issue_body` im Bot schreibt: „… im Bucket
# `feedback-photos` als `a.jpg`, `b.jpg` (…)". Nur Namen hinter genau
# diesem Anker zählen — ein `x.jpg` im Meldungstext selbst nicht.
_ANCHOR = re.compile(r"im Bucket `" + re.escape(BUCKET) + r"` als (.+?) \(")
_NAME = re.compile(r"`([A-Za-z0-9_.-]+\.jpg)`")


def photo_names(body: str) -> list[str]:
    """Die Dateinamen aus einem Issue-Text — leer, wenn keine genannt sind."""
    m = _ANCHOR.search(body)
    return _NAME.findall(m.group(1)) if m else []


def consent_line(body: str) -> str:
    """Was das Issue über die Artgalerie sagt (Patch 034)."""
    for line in body.splitlines():
        if "Artgalerie" in line:
            return line.strip()
    return "(keine Angabe — Meldung von vor 1.197.0: NICHT freigegeben)"


def issue_date(body: str) -> date | None:
    """Das Einreichdatum aus „… am JJJJ-MM-TT."."""
    m = re.search(r"am (\d{4}-\d{2}-\d{2})\.", body)
    return date.fromisoformat(m.group(1)) if m else None


def match_paths(rows: list[dict], names: list[str]) -> dict[str, str]:
    """Dateiname → voller Pfad, aus beiden Spalten (Patch 027 und 033)."""
    wanted = set(names)
    found: dict[str, str] = {}
    for row in rows:
        paths = list(row.get("photo_paths") or [])
        if row.get("photo_path"):
            paths.append(row["photo_path"])
        for path in paths:
            name = path.rsplit("/", 1)[-1]
            if name in wanted:
                found[name] = path
    return found


def service_key() -> str:
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if key:
        return key
    try:
        out = subprocess.run(
            ["supabase", "projects", "api-keys", "--project-ref", PROJECT_REF,
             "-o", "json"],
            check=True, capture_output=True, text=True).stdout
    except (OSError, subprocess.CalledProcessError) as e:
        sys.exit("Kein Service-Schlüssel: SUPABASE_SERVICE_ROLE_KEY setzen "
                 f"oder `supabase login` ausführen ({type(e).__name__}).")
    for entry in json.loads(out):
        if entry.get("name") == "service_role" and entry.get("api_key"):
            return entry["api_key"]
    sys.exit("Die Supabase-CLI lieferte keinen service_role-Schlüssel.")


def _get(path: str, key: str) -> bytes:
    req = urllib.request.Request(
        URL + path, headers={"apikey": key, "Authorization": f"Bearer {key}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def fetch_issue(number: int, out_root: str, key: str) -> int:
    body = subprocess.run(
        ["gh", "issue", "view", str(number), "--json", "body", "--jq", ".body"],
        check=True, capture_output=True, text=True).stdout
    names = photo_names(body)
    print(f"#{number}: {len(names)} Bild(er) genannt")
    if not names:
        return 0
    print(f"  {consent_line(body)}")

    # Die Zeile über das Datum eingrenzen — der Bot schreibt es aus
    # `created_at`, ein Tag Spielraum für die UTC-Grenze.
    day = issue_date(body)
    query = "select=photo_path,photo_paths"
    if day:
        query += (f"&created_at=gte.{day - timedelta(days=1)}"
                  f"&created_at=lt.{day + timedelta(days=2)}")
    rows = json.loads(_get(f"/rest/v1/feedback?{query}", key))
    paths = match_paths(rows, names)

    target = os.path.join(os.path.expanduser(out_root), str(number))
    os.makedirs(target, exist_ok=True)
    got = 0
    for name in names:
        path = paths.get(name)
        if path is None:
            print(f"  ✗ {name}: keine Zeile dazu gefunden")
            continue
        try:
            data = _get(f"/storage/v1/object/{BUCKET}/"
                        + urllib.parse.quote(path), key)
        except urllib.error.HTTPError as e:
            # 400/404: nach 90 Tagen gefegt (Bot), oder nie angekommen.
            print(f"  ✗ {name}: nicht im Bucket (HTTP {e.code}) — "
                  "vermutlich nach 90 Tagen gelöscht")
            continue
        dest = os.path.join(target, name)
        with open(dest, "wb") as f:
            f.write(data)
        print(f"  ✓ {dest} ({len(data) // 1024} KB)")
        got += 1
    return got


def self_test() -> None:
    body = (
        "> Hinweis zur Art „X\": schau `falsch.jpg` an\n\n"
        "Eingereicht in der App von **waldfee** aus Version 1.197.0 am 2026-09-23."
        "\n\n📎 3 Bilder sind angehängt — nicht öffentlich, nur im Bucket "
        "`feedback-photos` als `a1.jpg`, `b2.jpg`, `c3.jpg` "
        "(https://supabase.com/dashboard/project/x/storage/buckets/feedback-photos); "
        "wird nach 90 Tagen gelöscht.\n\n✅ Für die Artgalerie freigegeben: "
        "selbst aufgenommen, CC BY-SA 4.0, Urheber **waldfee** (am 2026-09-23).")
    assert photo_names(body) == ["a1.jpg", "b2.jpg", "c3.jpg"], photo_names(body)
    assert "falsch.jpg" not in photo_names(body)
    assert consent_line(body).startswith("✅"), consent_line(body)
    assert issue_date(body) == date(2026, 9, 23)
    assert photo_names("> nur Text\n\n_Automatisch erstellt._") == []
    old = "… nur im Bucket `feedback-photos` als `dead.jpg` (https://…); …"
    assert photo_names(old) == ["dead.jpg"]
    assert "NICHT freigegeben" in consent_line(old)
    rows = [{"photo_path": "u1/dead.jpg", "photo_paths": None},
            {"photo_path": None, "photo_paths": ["u2/a1.jpg", "u2/b2.jpg"]},
            {"photo_path": None, "photo_paths": ["u3/zz.jpg"]}]
    assert match_paths(rows, ["a1.jpg", "dead.jpg", "c3.jpg"]) == {
        "a1.jpg": "u2/a1.jpg", "dead.jpg": "u1/dead.jpg"}
    print("feedback_photos self-test passed (no network)")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("issues", nargs="*", type=int)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        self_test()
        return
    if not args.issues:
        ap.error("Issue-Nummer fehlt")
    key = service_key()
    total = sum(fetch_issue(n, args.out, key) for n in args.issues)
    print(f"{total} Bild(er) geladen.")


if __name__ == "__main__":
    main()
