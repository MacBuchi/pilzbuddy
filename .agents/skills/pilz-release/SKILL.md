---
name: pilz-release
description: Einen PilzBuddy-Stand für alle Nutzer freigeben („befördern", „Release", „promoten", „freigeben") — vorher prüfen, was das Neuheiten-Blatt zeigt, ob Touren, Vorführungen und Kurzanleitung noch zur Oberfläche passen und ob der Changelog für Nutzer lesbar ist; dann promote.yml starten, das Ergebnis nachsehen und das App-Dossier im DocuHub des Betreibers nachziehen. Auch zu benutzen, wenn nur gefragt wird, was bei der nächsten Freigabe mitkäme.
---

# Freigabe: vom Vorab-Stand zu allen Nutzern

Jeder Merge mit Versions-Bump wird ein **Prerelease** — unsichtbar für
normale Nutzer. Erst `promote.yml` gibt frei: Android meldet das Update,
das Web wird aus dem Tag neu gebaut, und **das Neuheiten-Blatt geht an
alle**. Das ist der eine Moment, in dem „Was ist neu" ankommt, und der
einzige, an dem ein Fehler darin noch billig ist.

Rhythmus: **höchstens wöchentlich** (Betreiber, 2026-08-17). Die
Beförderung selbst startet der Betreiber oder ich NACH seinem Ja — sie
ist nach außen sichtbar und schickt jedem Nutzer einen Update-Hinweis.

---

## 1. Was käme mit?

```bash
gh release list --limit 40 --json tagName,isPrerelease \
  --jq '.[] | "\(.tagName) \(if .isPrerelease then "vorab" else "STABIL" end)"'
python3 tool/release_notes.py --version <neu> --since <letzter-stabiler> --out /tmp/notes.md
```

Die Notizen sind die Changelog-Blöcke seit dem letzten stabilen Stand.
**Lesen, nicht nur erzeugen**: Sie stehen gleich so im GitHub-Release
und — über „Was ist neu" — in der App. Fachwörter aus PRs (Anker, Szene,
Provider) haben dort nichts verloren.

## 2. Was zeigt das Neuheiten-Blatt?

```bash
python3 tool/highlights_preview.py --version <neu> --since <letzter-stabiler>
```

Dasselbe Werkzeug schreibt `promote.yml` in die Run-Summary. Hier VORHER
laufen lassen, weil danach nichts mehr zu ändern ist.

- **Warnung „kein Highlight"**: Steht in den Notizen aus Schritt 1 eine
  Funktion, die ein Nutzer bemerken soll? Dann fehlt ihr Eintrag in
  `kFeatureHighlights` — nachtragen (mit `since` = Version, in der sie
  kam, und einer Vorführung in `highlight_demos.dart`), neuer
  Patch-Bump, dann erst befördern. Bringt der Stand ehrlich nur
  Korrekturen, ist die Warnung richtig und das Blatt bleibt aus.
- **Mehr als drei Highlights**: Das Blatt zeigt die drei jüngsten, der
  Rest steht in „Entdecken". Stimmt die Reihenfolge nicht mit dem
  Gewicht überein, ist `since` die Stellschraube — nicht die Liste.
- Texte: zwei, höchstens drei Sätze, sagen WAS und WO, keine Technik.

## 3. Passen Touren und Vorführungen noch?

Die Tests sind das Netz: `map_tour_flow_test`, `tab_tours_flow_test` und
`highlight_demos_flow_test` fahren jede Tour und jede Vorführung durch,
auf 800×600 und 360×640, und scheitern, wenn ein Ziel fehlt oder eine
Blase aus dem Bild ragt. Grün heißt: Jeder Anker ist da.

Was sie NICHT sehen, ist, ob der TEXT noch stimmt. Deshalb:

```bash
git diff <letzter-stabiler>..<neu> --stat -- lib/features
```

Für jede geänderte Oberfläche, auf die eine Tour zeigt (Karte, Spots,
Pilze, Buddys, Profil), den Wortlaut der Schritte in `map_tour.dart`,
`tab_tours.dart` und `highlight_demos.dart` gegenlesen — und die
Kurzanleitung in `help_screen.dart`. Ein umbenannter Knopf, auf den ein
Schritt mit altem Namen zeigt, ist genau der Fehler, den kein Test
findet.

## 4. Der Rest der Liste

- `minimum_supported_version` liegt nicht über dem stabilen Stand
  (`tool/schema_check.sh` prüft es, aber ein Blick kostet nichts).
- Store-Screenshots: `promote.yml` schreibt ihren Stand in die Summary
  (`tool/screenshot_stand.py`).
- Offene Feldtests: Was wird mit dieser Beförderung zum ersten Mal für
  alle sichtbar, und hat es jemand auf einem echten Handy gesehen? Wenn
  nicht, den Betreiber fragen, ob er es vorher in der Vorschau ansieht
  (https://macbuchi.github.io/pilzbuddy-preview/).

## 5. Befördern und nachsehen

Nach dem Ja des Betreibers:

```bash
gh workflow run promote.yml            # ohne Eingabe = jüngstes Prerelease
gh run watch "$(gh run list --workflow promote.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```

Danach:

- `gh release view v<neu>` — nicht mehr Prerelease, Notizen vollständig.
- Die Run-Summary lesen: Neuheiten-Blatt und Screenshot-Stand.
- https://macbuchi.github.io/pilzbuddy/version.json zeigt die neue
  Version (Pages braucht ein, zwei Minuten).
- Dem Betreiber sagen, was jetzt bei allen ankommt — und was davon noch
  niemand auf einem echten Gerät gesehen hat.

## 6. Den DocuHub nachziehen

Der Betreiber führt außerhalb des Repos einen DocuHub (Pfad in
`CLAUDE.local.md`, nie hier — das Repo ist öffentlich). Darin beschreibt
`apps/pilzbuddy.md` die App fürs ganze Portfolio, und er veraltet still:
Bis 2026-09-25 stand er auf 1.35.0, während die App bei 1.210 war, und
behauptete Dinge, die längst anders waren (Pages-Deploy aus
`release.yml`, ein entfernter Karten-Schalter, eine behobene
Play-Blockade). Eine Beförderung ist der natürliche Moment, ihn zu
prüfen — hier ist ohnehin gerade alles gelesen worden, was sich geändert
hat.

- **Kopfzeile:** stabile Version und Datum der Beförderung,
  Dateien/Zeilen/Testfälle neu zählen.
- **Features (§1):** was die Release-Notizen aus Schritt 1 an Neuem
  bringen, als je eine Zeile — nicht den Changelog abschreiben.
- **Was nicht mehr stimmt:** Abschnitte, die eine geänderte Stelle
  beschreiben (CI, Navigation, Karten-Engine, Muster, Schwächen), gegen
  den Code prüfen und berichtigen oder durchstreichen (`~~…~~` mit ✅ und
  Version, wie in §13).
- **Betriebswissen (§14):** letzte Beförderung, Merker-Resets, alles, was
  Zustand außerhalb des Codes betrifft.
- **Guidelines:** Hat dieser Stand ein übertragbares Muster gebracht oder
  eine Falle gefunden, gehört das in die passende Guideline (Skill
  `docuhub-pflege`), nicht nur ins App-Dossier.
- Die Versionszeile in der `README.md` des DocuHub mitziehen.

Der DocuHub ist ein lokales Git ohne Remote: selbst committen, mit einer
Nachricht, die sagt, auf welchen Stand gebracht wurde. Private Angaben
(Testkonten, Pfade) sind dort richtig aufgehoben — genau dafür gibt es
ihn.
