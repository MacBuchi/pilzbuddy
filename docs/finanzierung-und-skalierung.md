# Finanzierung und Skalierung von PilzBuddy

**Status:** recherchiert am 2026-08-17 · **Plattformseite:**
`MitFahrBar/doc/finanzierung-plattformvergleich.md` (einmal geschrieben, gilt
für alle drei Apps)

Dies ist **keine Steuer- oder Rechtsberatung.**

## Die Frage

Was kostet PilzBuddy heute, was bricht zuerst bei steigenden Nutzerzahlen, und
welche Finanzierungsmodelle sind hier zulässig?

## Die Antwort in einem Satz

**PilzBuddy ist lizenzrechtlich frei — alles Ausgelieferte erlaubt
kommerzielle Nutzung.** Was hier bindet, sind ausschließlich **selbst gegebene
Zusagen**. Und das dringlichste Problem ist kein Geldproblem: Eine Schleife
fragt alle 15 Sekunden nach Freundes-Standorten, auch wenn niemand teilt.

## Kostenbild heute

**0 €/Monat** — und der Grund dafür ist eine Architekturentscheidung, die
festgehalten gehört:

> **Massendaten liegen auf GitHub Releases, Supabase trägt nur JSON-Zeilen.**

Das ist die eigentliche Kostenersparnis des Projekts. Was pro Nutzer wirklich
über die Leitung geht:

| Was | Größe | Woher |
| --- | --- | --- |
| Offline-Regionskarten (PMTiles) | mehrere hundert MB je Karte | **fremdes** GitHub-Release (`whitespring/project-nomad-maps-europe`) |
| APK-Selbstaktualisierung | ~60 MB | GitHub Releases (dieses Repo) |
| Feine Waldblöcke | ~26 MB (DACH) bzw. ~1 MB je Gebiet | GitHub Release `forest-data` |
| Regengitter | ~646 KB beim ersten Lauf, dann ~50 KB/Tag | GitHub Release `rain-data` |
| DWD-Regenbilder | 187–568 KB je Abruf, nur bei eingeschalteter Ebene | `maps.dwd.de` |
| **Spots, Funde, Freundschaften** | JSON-Zeilen | **Supabase** |

Supabase sieht von alldem nichts außer der letzten Zeile. Bei 500 MB
Datenbank und 5 GB Egress im Free-Plan ist das der Grund, warum die App
bisher nichts kostet.

Dazu: Brevo Free für Auth-Mails, FCM kostenlos für Push, GitHub Pages für den
Web-Build, GitHub Actions für CI.

## Was zuerst bricht

### 1. Die 15-Sekunden-Schleife — mit Abstand der größte Posten

`lib/features/map/live_share_providers.dart` fragt `live_locations` alle 15
Sekunden ab, in einer `while (true)`-Schleife, **sobald jemand angemeldet ist
und die Karte offen hat**. Geprüft wird dabei nicht:

- ob man überhaupt Freunde hat,
- ob irgendjemand gerade seinen Standort teilt,
- ob man selbst teilt.

Das sind **~240 Abfragen pro Stunde und aktivem Nutzer**. Bei zehn Nutzern mit
je einer Stunde Kartenzeit am Tag sind das 72.000 Abfragen im Monat für eine
Antwort, die fast immer leer ist. Bei hundert Nutzern 720.000.

Das ist kein Fehler in dem Sinn, dass etwas nicht funktioniert — es
funktioniert. Es ist eine Abfrage, die niemand braucht, multipliziert mit der
Nutzerzahl. **Sie ist der erste Posten des Effizienz-Durchgangs.**

Der Eingriff ist klein: Das Intervall liegt bereits als überschreibbarer
Provider vor (`friendLocationsPollProvider`, ausdrücklich „damit Tests es
überschreiben können"), und die Freundesliste wird ohnehin geladen. Die
Schleife könnte ruhen, solange niemand teilt, und erst anziehen, wenn eine
Freigabe läuft.

### 2. Der Resume-Rundumschlag

`lib/features/map/map_screen.dart` ruft bei **jedem** `AppLifecycleState.resumed`
ein `_refreshData()`, das sechs Provider auf einmal invalidiert:
`mySpots`, `friendSpots`, `friendships`, `updateInfo`, `availableMaps`,
`installedMaps`.

Vier davon gehen an Supabase, **zwei an die GitHub-API** (Update-Prüfung und
Kartenkatalog). Es gibt keine Mindestzeit im Hintergrund — wer kurz auf die
Uhr schaut und zurückwechselt, löst den vollen Satz erneut aus. Die
Begründung im Code („Android hält die App lange im Hintergrund am Leben") ist
für den langen Fall richtig und für den kurzen zu großzügig.

Ein Update-Check und ein Kartenkatalog-Abruf brauchen keine Sekundenaktualität.
**Ebenfalls für den Effizienz-Durchgang vorgemerkt.**

### 3. Datenbankgröße

`spots`, `finds` und `friendships` wachsen mit der Nutzung — das ist der
gewollte Teil. `error_reports` hat 90 Tage Aufbewahrung (der Feedback-Bot
räumt auf), `live_locations` läuft über RLS ab. Der aktuelle Stand steht
wöchentlich in der Zusammenfassung des Backup-Jobs; **dort nachsehen statt
schätzen**, wie CLAUDE.md es festhält.

### 4. Der Free-Plan pausiert

Nach etwa einer Woche ohne Zugriff. Dass das nicht passiert, ist eine bewusste
Zusage: Der Feedback-Bot (alle 2 h), der Backup-Job und der
Minutentakt-Cron `push-flush` halten das Projekt wach. Wer beim Aufräumen
Takte reduziert, muss diesen Nebeneffekt mitdenken — mindestens einer der
Wecker muss bleiben, solange der Free-Plan gilt.

## Die Lizenzlage: grün

Alles, was PilzBuddy ausliefert, erlaubt kommerzielle Nutzung, sofern die
Namensnennung steht. Das ist kein Zufall, sondern gebaut: `tool/season_curves.py`
filtert GBIF ausdrücklich auf CC0 und CC BY („damit aus einer
Play-Veröffentlichung keine Lizenzfrage wird"), und `tool/license_config.yaml`
lehnt NC- und starke Copyleft-Abhängigkeiten ab.

| Quelle | Was | Lizenz | Kommerziell? |
| --- | --- | --- | --- |
| OpenStreetMap / Protomaps | Kartenkacheln, PMTiles | ODbL | **ja**, Namensnennung + Share-Alike auf die *Datenbank* |
| DWD (RADOLAN, Stationen) | Regen, Temperatur | DL-DE-BY-2.0 | **ja**, Namensnennung |
| Copernicus (DLT, DEM GLO-90) | Waldtypen, Höhen | Copernicus-Datenpolitik / CC BY 4.0 | **ja**, Namensnennung |
| DLR | Baumarten Deutschland 2022 | CC BY 4.0 | **ja**, Namensnennung |
| GBIF (gefiltert) | Saisonkurven | CC0 1.0 + CC BY 4.0 | **ja** |
| Noto Sans | Kartenschrift | SIL OFL | **ja**, Lizenztext mitliefern |
| Eigener Code | | MIT | **ja** |

Die Namensnennungen stehen bereits vollständig in
`lib/core/map_data_license.dart` und werden über die Lizenzseite der App
ausgeliefert; `test/flows/license_flow_test.dart` erzwingt, dass kein
ausgeliefertes Asset ohne Lizenzentscheidung dasteht.

**Ergebnis: Einmalkauf, Pro-Version und selbst Werbung wären lizenzrechtlich
möglich.**

### Die eine Ausnahme, und sie ist harmlos

Open-Meteo (`tool/ampel_validate.py`) ist **frei nur für nicht-kommerzielle
Nutzung** — ausdrücklich definiert als Apps „ohne Abonnements oder Werbung".
Der README hält das bereits fest: *„PilzBuddy ist und bleibt kostenlos und
werbefrei; sollte sich das je ändern, muss diese Zusage neu entschieden
werden."*

Warum das trotzdem kein Blocker ist: Open-Meteo läuft **nur im
Entwicklungswerkzeug**, nie in der App, und liefert dort Validierungsdaten für
die Pilzampel. Bei einer Monetarisierung bräuchte man für **künftige**
Validierungsläufe den Standard-Plan (~29 $/Monat). Das ist billig — es soll
nur niemanden überraschen.

## Was stattdessen bindet: eigene Zusagen

Hier liegt die eigentliche Hürde, und sie ist eine Frage der Glaubwürdigkeit,
nicht des Rechts. An vier Stellen steht heute geschrieben, dass PilzBuddy
nichts kostet:

1. `web/datenschutz.html`: *„PilzBuddy ist ein privates Projekt ohne
   Gewinnabsicht: keine Werbung, keine In-App-Käufe, keine Bezahlfunktionen."*
2. `README.md` §Lizenz: *„PilzBuddy ist und bleibt kostenlos und werbefrei."*
3. `docs/play-console.md` und `store/data_safety.csv`: Store-Listing
   „Enthält Werbung: Nein, In-App-Käufe: Nein".
4. Die Datenschutzerklärung insgesamt, die mit „keine Werbung, kein Tracking"
   argumentiert.

Alle vier müssten im **selben** PR geändert werden. Bei Werbung kämen dazu:
das Werbe-SDK als neues Netzziel in der Datenschutzerklärung — sonst wird
`test/privacy_policy_test.dart` rot, der genau dafür gebaut ist —, ein
angepasstes Data-Safety-Formular und eine ehrliche Antwort darauf, was ein
Werbenetz an Standortdaten mitbekommt. Bei einer App, deren Kern die
**geheime Fundstelle** ist und die extra ein Gitter aufs Gerät legt, damit
keine Koordinate an den DWD geht, wäre das ein Bruch mit dem eigenen Entwurf.

## Empfehlung

1. **Erst aufräumen.** Die Poll-Schleife und der Resume-Rundumschlag sind
   zusammen der größte Kostenposten und nehmen niemandem etwas weg.
2. **Spenden** als erster und einfachster Schritt: GitHub Sponsors oder Ko-fi,
   verlinkt von README und Projektseite. Ohne Gegenleistung bleibt es außerhalb
   des Gewerbes, und keine der vier Zusagen oben muss angefasst werden — sie
   sprechen von Werbung, In-App-Käufen und Bezahlfunktionen, nicht von Spenden.
3. **Falls mehr nötig wird: eine Pro-Version**, und zwar für das
   Karten-Vorladen. Das ist der einzige Teil der App mit spürbarem Aufwand
   dahinter (Gitterbau in CI, Speicher, Bandbreite) und zugleich der, den
   Gelegenheitsnutzer nicht brauchen. Ein Einmalkauf passt besser als ein Abo:
   Die laufenden Kosten der App sind nahezu null, ein Abo wäre schwer zu
   begründen.
4. **Werbung nicht** — lizenzrechtlich erlaubt, aber im Widerspruch zum
   Datensparsamkeits-Entwurf, der überall im Projekt trägt.

## Offene Punkte

- Liegen PilzBuddy und MitFahrBar in derselben Supabase-Organisation? Der
  Free-Plan erlaubt nur zwei aktive Projekte je Organisation.
- Wie groß ist die Datenbank aktuell? Steht in der Zusammenfassung des
  Backup-Jobs.
- Wie viele Nutzer gibt es? **Nirgends im Repo** — es gibt bewusst keine
  Telemetrie. Vor jeder Ertragsschätzung wäre das die erste Zahl, die fehlt.

## Quellen

Abgerufen am 2026-08-17.

- [Open-Meteo: Nutzungsbedingungen und Preise](https://open-meteo.com/en/pricing)
- [DLR EOC Geoservice: Tree Species Germany 2022 (CC BY 4.0)](https://geoservice.dlr.de/web/datasets/treespecies_de_2022)
- [Copernicus DEM: Datenpolitik und Lizenz](https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM)
- [Datenlizenz Deutschland – Namensnennung 2.0](https://spdx.org/licenses/DL-DE-BY-2.0.html)
- [GitHub: Storage und Bandbreite (Releases ohne Bandbreitengrenze)](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-storage-and-bandwidth-usage)
- Repo-intern: `lib/core/map_data_license.dart`, `tool/license_config.yaml`,
  `tool/season_curves.py`, `web/datenschutz.html`, `docs/play-console.md`,
  `lib/features/map/live_share_providers.dart`, `lib/features/map/map_screen.dart`
- Plattformpreise und rechtlicher Rahmen:
  `MitFahrBar/doc/finanzierung-plattformvergleich.md`
