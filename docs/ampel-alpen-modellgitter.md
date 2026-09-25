# Das Modellgitter des Alpenraums — Wetter und Ampel jenseits des Radars

Stand: 2026-09-26 · Issue #612 · Werkzeug `tool/model_weather.py` · seit 1.212.0

## Die Frage

Der Betreiber wünschte am 2026-09-25 „Wetterdaten und damit Pilzampel
für Südtirol". Die Ampel braucht vier Wetterzutaten am Ort, alle aus
Gittern auf dem Gerät: den Regenfaktor (26 Tage, RADOLAN-Stapel), die
Temperatur (nächste DWD-Station plus Höhenkorrektur), für Holz & Winter
zusätzlich Bodenfeuchte und die Minima-Reihe. Alle vier enden an der
deutschen Grenze. Österreich lief auf dem Radarrand und einer
bayerischen Station in 100 km Entfernung, Südtirol hatte nichts.

## Warum ein Modell und nicht Radar oder Stationen

Eine freie, europaweite Quelle gibt es nur in EINER Familie: numerische
Modellfelder. OPERA (Radarkomposit) ist nicht frei, ERA5-Land läuft fünf
Tage nach, E-OBS monatlich, und regionale Stationsdienste wären eine
Pipeline je Land. Entscheidend: **Die Ampel wurde nie auf Radar
validiert.** `tool/ampel_validate.py` misst gegen das Open-Meteo-Archiv
(IFS HRES 9 km ab 2017, ERA5 davor). Modellregen ist das validierte
Instrument; das Radar in der App ist die Abweichung davon.

## Was gebaut ist

- **Quelle:** Open-Meteo, `models=icon_seamless` (ICON-D2 2 km über den
  Alpen, ICON-EU darüber hinaus), `precipitation_sum`,
  `temperature_2m_max`, `temperature_2m_min`. Free-Tier, nicht
  kommerziell, CC BY 4.0. Lizenzseite der App nennt es.
- **Raster:** EPSG:3857, 12 km, Box 5,9–17,2° O / 45,6–49,1° N minus
  Deutschland (Polylinie der Südgrenze). 105 × 48 Zellen, 3 574 Punkte.
  Derselbe Mercator-Aufbau wie der Radar-Stapel — `RainGrid.mmAt` liest
  beide.
- **Zustand = Tagesdateien im Release `rain-data`:** `model_rain_*`,
  `model_tmax_*`, `model_tmin_*` (0,5-°C-Schritte), `model_elevation`.
  Jeder Lauf holt nur fehlende Tage, neueste zuerst, innerhalb
  4 500 Calls (Open-Meteo: 600/min, 5 000/h, 10 000/Tag; ein Ort für
  ≤ 7 Tage ist ein Call). Ein leerer Stapel füllt sich über drei bis
  vier tägliche Läufe.
- **In der App:** Der Regen ist ein zweiter Stapel mit Vorrang Radar →
  Modell je Tag und Punkt (`rainCoursesFromStacks`) bzw. je Wabe
  (`AmpelLevels`). Die Temperatur reist als virtuelle Stationen in der
  Stationstabelle (`src: "openmeteo"`) — Nachbarsuche, Höhenkorrektur
  und Fläche unverändert. Das Blatt sagt „Modellwerte (Open-Meteo)" und
  „kein Messwert".
- **Nicht dabei:** Bodenfeuchte (Holz & Winter bleibt außerhalb
  Deutschlands grau), die Regen-Kartenebene, Slowenien.

## Was gemessen ist

Der GBIF-Bestand deckt seit #615 die italienische Alpenbox. Mit CC0/
CC BY war die Stichprobe dort zu dünn (`pilzampel-pruefachsen.md` #12,
#13). Mit CC BY-NC — nur für Messungen, nie für ein Asset — besteht das
Pfifferling-Fenster 17,5 °C in der Box: 142 Paare, +0,183
[+0,055, +0,328], Kontrolle 0,486 (#14). Für Steinpilz & Co. ist der
Klassen-Hold-out leer (Fenster = 13-°C-Referenz); beschreibend trennt
13 °C dort mit AUC 0,63 (Steinpilz, 211 Paare), 0,78 (Marone, 103) und
0,77 (Fichtenreizker, 87) (#15).

## Prüfung

- `python3 tool/model_weather.py --self-test` (netzfrei, in CI): Raster
  und Dart-Arithmetik, Maske (München drin, Innsbruck, Bozen, Bregenz
  draußen), Kodierung, Budgetplanung, Bau gegen einen Schein-Dienst,
  Stationszeilen, Nachfüllen über die History-API, Verify.
- `--verify` im Workflow: sechs zufällige Punkte des jüngsten Tags
  einzeln nachgefragt.
- Dart: `rain_stack_test` (Vorrang je Tag), `ampel_fill_test`
  (`AmpelLevels`), `spot_weather_test` (`src`), `spot_rain_section_test`
  (Sätze), `rain_grid_repository_test` (eigener Abschnitt, eigenes
  Aufräumen), `flows/spot_rain_flow_test` (Blatt ohne Radar, gemischt).
- Live-Probelauf am 2026-09-25 mit 20 Punkten: 28 Tage geholt, Verify
  6/6, Stationstabelle +65 Byte je Punkt gepackt (≈ 230 KB bei 3 574).
