#!/usr/bin/env python3
"""Füllt Googles Data-Safety-Formular aus `docs/play-console.md` aus.

Die Play Console kann die Antworten des Formulars als CSV importieren
(App-Inhalte → Datensicherheit → „Import from CSV"). Dieses Werkzeug
nimmt Googles offizielle Muster-CSV (`store/data_safety_template.csv`,
Quelle: Play-Console-Hilfe, Artikel 10787469) und trägt unsere Antworten
ein — Ergebnis ist `store/data_safety.csv`, fertig zum Import.

Damit ist das größte Console-Formular kein Abtippen von ~60 Fragen mehr,
sondern ein Datei-Upload plus Sichtprüfung. Die INHALTLICHE Wahrheit
bleibt `docs/play-console.md` — die Antworten hier sind wörtlich von
dort übernommen, inklusive der drei Ermessensfragen (Buddy-Teilen ist
kein „geteilt", GitHub-Feedback schon, das FCM-Token ist erhoben UND
geteilt).

Zwei Wächter gegen die naheliegenden Fehler:

* Jeder Schlüssel der Antwort-Tabelle MUSS in der Vorlage existieren —
  eine erfundene oder vertippte ID bricht den Lauf, statt still eine
  Zeile ins Leere zu schreiben.
* `--check` verifiziert, dass die eingecheckte Ausgabedatei exakt dem
  entspricht, was Vorlage + Antworten ergeben (läuft in CI mit). Wer die
  CSV von Hand ändert, macht CI rot — geändert wird die Tabelle HIER,
  und `docs/play-console.md` im selben Commit.

Nutzung:
  python3 tool/play_data_safety.py            # schreibt store/data_safety.csv
  python3 tool/play_data_safety.py --check    # CI-Wächter
"""
from __future__ import annotations

import csv
import io
import sys

TEMPLATE = "store/data_safety_template.csv"
OUTPUT = "store/data_safety.csv"

TRUE, FALSE = "TRUE", "FALSE"

# ---------------------------------------------------------------------------
# Die Antworten. Schlüssel: (Frage-ID, Antwort-ID) — exakt wie in der
# Vorlage. Alles, was hier nicht steht, bleibt leer (= in der Console
# nicht angekreuzt); die Vorlage kennt keine „Nein"-Kästchen.
# ---------------------------------------------------------------------------

ANSWERS: dict[tuple[str, str], str] = {
    # Vorfragen (docs/play-console.md, „Vorfragen").
    ("PSL_DATA_COLLECTION_COLLECTS_PERSONAL_DATA", ""): TRUE,
    ("PSL_DATA_COLLECTION_ENCRYPTED_IN_TRANSIT", ""): TRUE,
    ("PSL_DATA_COLLECTION_USER_REQUEST_DELETE", ""): TRUE,
    # Welche Datentypen. `PSL_USER_ACCOUNT` heißt in der Vorlage
    # „Personal identifiers" — das ist die Zeile „Nutzer-IDs" der
    # heutigen Console (profiles.id).
    ("PSL_DATA_TYPES_LOCATION", "PSL_APPROX_LOCATION"): TRUE,
    ("PSL_DATA_TYPES_LOCATION", "PSL_PRECISE_LOCATION"): TRUE,
    ("PSL_DATA_TYPES_PERSONAL", "PSL_NAME"): TRUE,
    ("PSL_DATA_TYPES_PERSONAL", "PSL_EMAIL"): TRUE,
    ("PSL_DATA_TYPES_PERSONAL", "PSL_USER_ACCOUNT"): TRUE,
    ("PSL_DATA_TYPES_APP_ACTIVITY", "PSL_USER_GENERATED_CONTENT"): TRUE,
    ("PSL_DATA_TYPES_APP_PERFORMANCE", "PSL_CRASH_LOGS"): TRUE,
    ("PSL_DATA_TYPES_IDENTIFIERS", "PSL_DEVICE_ID"): TRUE,
}

# Je erhobenem Typ: geteilt?, Pflicht?, Zwecke der Erhebung, Zwecke der
# Weitergabe. „Kurzzeitig verarbeitet" ist überall FALSE — alles liegt
# in PostgreSQL (docs/play-console.md).
USAGE = {
    # Standort: nur erhoben. Buddy-Teilen zählt nicht als „geteilt"
    # (Ermessensfrage ¹ — nutzerinitiiert, abschaltbar, dokumentiert).
    "PSL_PRECISE_LOCATION": dict(
        shared=False, required=False, purposes=["PSL_APP_FUNCTIONALITY"]),
    "PSL_APPROX_LOCATION": dict(
        shared=False, required=False, purposes=["PSL_APP_FUNCTIONALITY"]),
    # E-Mail: Brevo ist Auftragsverarbeiter, kein „geteilt"
    # (Ermessensfrage ³).
    "PSL_EMAIL": dict(
        shared=False, required=True,
        purposes=["PSL_APP_FUNCTIONALITY", "PSL_ACCOUNT_MANAGEMENT"]),
    "PSL_NAME": dict(
        shared=False, required=True,
        purposes=["PSL_APP_FUNCTIONALITY", "PSL_ACCOUNT_MANAGEMENT"]),
    "PSL_USER_ACCOUNT": dict(
        shared=False, required=True,
        purposes=["PSL_APP_FUNCTIONALITY", "PSL_ACCOUNT_MANAGEMENT"]),
    # Feedback wird ein öffentliches GitHub-Issue — GETEILT
    # (Ermessensfrage ², „Untertreiben ist hier das teurere Risiko").
    "PSL_USER_GENERATED_CONTENT": dict(
        shared=True, required=False,
        purposes=["PSL_APP_FUNCTIONALITY", "PSL_DEVELOPER_COMMUNICATIONS"],
        share_purposes=["PSL_DEVELOPER_COMMUNICATIONS"]),
    "PSL_CRASH_LOGS": dict(
        shared=False, required=True, purposes=["PSL_APP_FUNCTIONALITY"]),
    # Das FCM-Token: erhoben UND geteilt — es entsteht bei Google, und
    # die Weitergabe ist der Zweck (Ermessensfrage ⁴). Optional, weil
    # Push ab Werk aus ist und Ausschalten die Zeile löscht.
    "PSL_DEVICE_ID": dict(
        shared=True, required=False,
        purposes=["PSL_APP_FUNCTIONALITY"],
        share_purposes=["PSL_APP_FUNCTIONALITY"]),
}

_PREFIX = "PSL_DATA_USAGE_RESPONSES"


def _usage_answers() -> dict[tuple[str, str], str]:
    answers: dict[tuple[str, str], str] = {}
    for dtype, u in USAGE.items():
        base = f"{_PREFIX}:{dtype}"
        answers[(f"{base}:PSL_DATA_USAGE_COLLECTION_AND_SHARING",
                 "PSL_DATA_USAGE_ONLY_COLLECTED")] = TRUE
        if u["shared"]:
            answers[(f"{base}:PSL_DATA_USAGE_COLLECTION_AND_SHARING",
                     "PSL_DATA_USAGE_ONLY_SHARED")] = TRUE
        answers[(f"{base}:PSL_DATA_USAGE_EPHEMERAL", "")] = FALSE
        control = ("PSL_DATA_USAGE_USER_CONTROL_REQUIRED" if u["required"]
                   else "PSL_DATA_USAGE_USER_CONTROL_OPTIONAL")
        answers[(f"{base}:DATA_USAGE_USER_CONTROL", control)] = TRUE
        for p in u["purposes"]:
            answers[(f"{base}:DATA_USAGE_COLLECTION_PURPOSE", p)] = TRUE
        for p in u.get("share_purposes", []):
            answers[(f"{base}:DATA_USAGE_SHARING_PURPOSE", p)] = TRUE
    return answers


def render() -> str:
    answers = dict(ANSWERS)
    answers.update(_usage_answers())
    with open(TEMPLATE, newline="", encoding="utf-8-sig") as f:
        rows = list(csv.reader(f))
    known = {(r[0], r[1]) for r in rows[1:] if r}
    unknown = [k for k in answers if k not in known]
    if unknown:
        raise SystemExit(
            "Antwort-IDs fehlen in der Vorlage (vertippt, oder Google hat "
            f"das Formular geändert): {unknown}")

    used = set()
    for row in rows[1:]:
        if not row:
            continue
        key = (row[0], row[1])
        if key in answers:
            row[2] = answers[key]
            used.add(key)
        else:
            row[2] = ""
    assert used == set(answers)

    out = io.StringIO()
    csv.writer(out, lineterminator="\n").writerows(rows)
    return out.getvalue()


def main() -> None:
    content = render()
    filled = sum(1 for line in content.splitlines()
                 if ",TRUE," in line or ",FALSE," in line)
    if "--check" in sys.argv:
        try:
            current = open(OUTPUT, newline="", encoding="utf-8").read()
        except FileNotFoundError:
            raise SystemExit(f"{OUTPUT} fehlt — python3 tool/play_data_safety.py")
        if current != content:
            raise SystemExit(
                f"{OUTPUT} passt nicht zu Vorlage + Antworten. Nicht die "
                "CSV editieren — die Antwort-Tabelle in "
                "tool/play_data_safety.py ändern (und docs/play-console.md "
                "im selben Commit), dann neu erzeugen.")
        print(f"data_safety.csv: deckungsgleich ({filled} gesetzte Antworten)")
        return
    with open(OUTPUT, "w", newline="", encoding="utf-8") as f:
        f.write(content)
    print(f"{OUTPUT}: {filled} Antworten gesetzt")


if __name__ == "__main__":
    main()
