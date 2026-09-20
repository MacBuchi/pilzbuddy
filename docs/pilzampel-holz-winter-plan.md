# Pilzampel — Zuschnitt: die Klasse „Judasohr & Co.“ und Pfifferling 14,5 °C

Stand: 2026-09-20. Plan vor Implementierung; nichts hiervon ist gebaut.
Grundlage sind die Läufe 11–18 des privaten Labors (`pilzbuddy-lab`,
Berichte gespiegelt nach `Claude_exchange/Pilzampel-lab/`), gerechnet
gegen `9a8a2c414f` (`feat/ampel-auftrag-3`), Design B, Erkundungs- und
Testblöcke wie in `docs/pilzampel-auftrag-4.md` §3, seit Lauf 17 um
AT+CH erweitert.

## 1. Was ausgeliefert werden soll

### A. Eine neue Klasse mit eigenem Rechenkern

**Mitglieder (8):** Austernseitling, Judasohr, Krause Glucke, Leberpilz,
Lungenseitling, Rehbrauner Dachpilz, Samtfußrübling, Schwefelporling.
Alle acht stehen in `mushroom_species.dart`; heute sind sie grau.

**Kern:** ein bedingtes Logit, kein Temperaturfenster. Der Score ist die
lineare Vorhersage

    s = 0,1882 · ln F + 0,1321 · T − 0,00446 · T² + 0,00220 · M − 0,000442 · M · T

mit `F` = Regenfaktor der Ampel (26 Tage, wie bisher, Boden 1e-3 vor dem
Logarithmus), `T` = Tagesmittel über 20 Tage in °C (wie bisher, mit
Höhenkorrektur), `M` = Bodenfeuchte 0–60 cm in % nFK, Mittel über 26
Tage, von der nächsten DWD-Bodenfeuchtestation (`BFGL_AG`, Abschnitt 2).
Die fünf Zahlen stammen aus `18-testteil-dach.md` (Fit auf allen
DACH-Erkundungsstrata). Die Stufenschwellen sind Quantile der
`s`-Verteilung an Vergleichstagen (50 % / 80 %, wie bei jeder Klasse) und
werden im Werkzeug gemessen, nicht gesetzt (Abschnitt 4).

**Beleg — die drei Hürden, alle genommen:**

| Prüfung | Kandidat gegen Formel 13 °C | Quelle |
|---|---|---|
| DE-Testblöcke (1 533 Strata, 20 Jahre) | +0,402 [+0,255, +0,596] ▲ | 15 / 18 |
| AT/CH-Testblöcke (458 Strata) | +0,206 [+0,081, +0,352] ▲ | 18 |
| gegen die Klimatologie (Saison allein) | +0,020 [+0,000, +0,038] ▲ | 18 |

Je Art ▲: Samtfußrübling, Judasohr, Austernseitling, Schwefelporling,
Lungenseitling, Leberpilz. Nicht unterscheidbar (kein ▼): Rehbrauner
Dachpilz, Krause Glucke. Kein Mitglied verliert.

**Was die Zahlen NICHT sagen:** Der Gewinn gegenüber der reinen
Saisonkurve ist klein und liegt am Rand des Bandes. Der große Gewinn
gegenüber heute entsteht, weil die 13-°C-Glocke Winterarten kategorisch
falsch bewertet (Log-Lik. der Referenz −2,3 bis −2,5 gegen −1,75). Die
Klasse ist also vor allem „nicht mehr falsch“, und erst in zweiter Linie
„besser als die Saison“. Das gehört in die Evidenzstufe (Abschnitt 5).

**Warum ein Logit und nicht ein weiteres Fenster:** In `14-kandidaten.md`
liefen je Cluster drei Fassungen gegeneinander — Formel mit eigenem
Fenster, Formel plus Feuchtegewicht, freies Logit. Für diese Arten
verliert die Glocke bei jedem Fenster gesichert gegen das Logit (−0,25),
weil „je kälter, desto besser“ mit einer Glocke um ein Optimum nicht
darstellbar ist. Die Bodenfeuchte als Zusatz zur Formel trägt nirgends;
sie trägt nur INNERHALB des Logits.

### B. Pfifferling: Fenster 17,5 → 14,5 °C

Betreiberentscheidung vom 2026-09-20 („kleine Schritte“), ausdrücklich
auf einem **nicht gesicherten** Ergebnis: Vorzeichen fünfmal von fünf
positiv, DE-Test +0,035 [−0,012, +0,079], AT/CH +0,066 [+0,004, +0,135] ▲,
AUC auf dem DE-Test leicht rückläufig (0,642 → 0,632). Nur die Zahl
ändert sich; Glocke, Klasse und Schlüssel `sommer` bleiben. Die beiden
Schwellen der Klasse werden für das neue Fenster neu gemessen
(`--thresholds`), und die Evidenzstufe des Pfifferlings wird
`vorlaeufig` — die Klasse hat ihren bestätigten Hold-out (17,5 °C,
`docs/pilzampel-artenfenster-holdout.md`) mit dieser Änderung verlassen.

### C. Alles andere bleibt

Herbst-Wald bleibt bei 13 °C (Lauf 14d: kein gesicherter Gewinn ohne die
zwei Winterarten, die dort falsch einsortiert waren). Cantharellales
(Herbsttrompete, Semmelstoppelpilz, Trompetenpfifferling) war auf dem
DE-Test angenommen (15), reist aber nicht (16) und ist mit Frühjahr
zusammen auf DE + AT/CH nicht unterscheidbar (18): **nur für Deutschland
belegt**, bleibt vorerst grau — ob eine DE-only-Klasse ausgeliefert
werden soll, ist eine Produktfrage, die dieser Plan offen lässt.

## 2. Was die App dafür braucht: Bodenfeuchte in der Stationstabelle

Die validierte Größe ist NICHT ERA5 an der Koordinate (das hat die App
nie), sondern das DWD-Stationsprodukt, genau so, wie die App es bekommen
kann (`11-dwd-bodenfeuchte.md`: innerhalb der Strata r = 0,79 zu ERA5,
gepaart nicht unterscheidbar):

    https://opendata.dwd.de/climate_environment/CDC/derived_germany/soil/daily/recent/
      derived_germany_soil_daily_recent_v2_<id>.txt.gz      (laufendes Jahr, täglich, 1–2 Tage Verzug)
      derived_germany_soil_daily_recent_stations_list.txt  (Stationsindex; Höhe; Breite; Länge; Name; Bundesland)

493 Stationen, Spalte `BFGL_AG` (0–60 cm unter Gras, sandiger Lehm,
% nFK, AMBAV-Modell), Fehlwert −999. Median-Abstand Fundort → Station in
DE 11 km, P90 18 km. In AT/CH liegt die nächste Station im Median 90–140
km entfernt — jenseits `WeatherTable.maxStationKm` (100 km) — die Klasse
bleibt dort grau, was zum Beleg passt (Holz & Winter reist zwar, aber
mit genau dieser Unschärfe gemessen).

**Änderungen:**

- `tool/spot_weather.py`: drittes Netz `MOISTURE` neben `AIR` und `SOIL`
  — kein ZIP, sondern `.txt.gz` mit Kopfzeile; Spalte per NAME
  (`BFGL_AG`); Fenster **26 Tage** (das Feuchtefenster), während Luft
  und Boden bei 20 bleiben. Payload: `"moisture": [{…station, "bfgl":
  [26 Werte]}]`, ~493 × 26 Zahlen, unter 60 KB gzip. Selbsttest mit
  einer künstlichen Datei (Fehlwert, Datumslücke), wie beim Labor-Loader
  (`lab/dwd_boden.py`, vier Mutationen rot).
- `lib/features/map/spot_weather.dart`: `MoistureStation` (Reihe
  `bfgl`, ältester Tag zuerst wie die anderen), `WeatherTable.moisture`,
  `nearestMoisture()`. Dieselbe Regel: `competes` ab 10 gemessenen Tagen
  — für das 26-Tage-Mittel des Modells verlangt der Kern aber die volle
  Reihe, sonst `null` (kein Mittel aus halben Fenstern; wie
  `window_of` im Werkzeug).
- `rain_manifest.json` / `rain-data.yml`: nichts Neues am Transport, die
  Datei fährt wie bisher im Release und im Spiegel-Branch mit. **Kein
  neues Netzziel für die App**, keine Änderung an Datenschutzerklärung
  oder `docs/play-console.md`.
- Optional, aber billig: eine Zeile „Bodenfeuchte 0–60 cm: 63 % nFK
  (Station X, 12 km)“ im Spot-Blatt neben der Bodentemperatur.

## 3. Der Modellkern in Dart

`ampel_model.dart` bleibt DER Spiegel des Werkzeugs; die Klasse bekommt
eine Form:

```dart
sealed class AmpelClass { name; verhaltenAbove; guenstigAbove; }
class AmpelBellClass  extends AmpelClass { optimumC }                       // wie bisher
class AmpelLogitClass extends AmpelClass { bRain, bT, bT2, bM, bMT }        // neu
```

- `ampelScore` wird je Form ausgewertet: Glocke wie bisher; Logit als
  lineare Vorhersage aus `log(max(rainFactor, 1e-3))`, `T` (20-Tage-
  Mittel, korrigiert) und `M` (26-Tage-Mittel `bfgl`). Fehlt `M`, gibt es
  keine Stufe (grau) — kein Ersatzwert.
- `ampelLevelOf(score, klass)` bleibt: Schwellen vergleichen den Score
  seiner eigenen Klasse; `ampelBestOf` vergleicht STUFEN, nie Scores —
  die Regel aus 1.140.0 trägt die neue Form ohne Änderung.
- **Karte** (`ampel_fill.dart`): je Zelle heute Regen aus dem Gitter und
  die nächste Luftstation. Für die Logit-Klasse kommt die nächste
  Feuchtestation dazu — dieselbe Kandidatensuche wie bei den
  Luftstationen (Blockmittelpunkt, Reichweite), ein drittes Stationsfeld
  im `AmpelLevelGrid`. Der Walker in `test/ampel_fill_test.dart` hält
  Fläche und Blatt Zelle für Zelle zusammen (#279); das bleibt die
  Zusage. **Alternative, wenn die Fläche zu teuer wird:** Die Klasse
  rechnet zuerst nur am Spot und steht in der Legende als „nur am Spot“;
  das ist eine Betreiberentscheidung, Vorgabe ist die Fläche.
- Klassenschlüssel `holz_winter`, Anzeigename nach Mitgliedern:
  **„Austernseitling & Co.“** (Betreiber, 2026-09-20: „Judasohr ist
  nicht der aussagekräftigste Winterpilz“).
- `ampelSpeciesClass`: die acht Arten → `holz_winter`. Judasohr,
  Austernseitling und Samtfußrübling hatten am 2026-09-13 den
  Kalt-Hold-out mit einer GLOCKE bei −1 °C nicht bestanden
  (`docs/pilzampel-kaltklasse-holdout.md`); der Logit besteht ihn. Das
  ist kein Widerspruch, sondern der Grund für die neue Form — und
  gehört in den Kommentar an dieser Stelle.

## 4. Der Spiegel: `tool/ampel_validate.py`

Ohne Spiegel kein Kern („kein dritter Modellkern“). Nötig:

- **DWD-Bodenfeuchte im Werkzeug** — Port von `lab/dwd_boden.py` nach
  `tool/` in reiner Standardbibliothek (kein numpy): Stationsliste,
  `historical` + `recent` je Station, nächste Station per Großkreis, 26
  Tage VOR dem Tag, jüngster zuerst, Lücke = kein Wert. Cache im
  `cache_dir` wie das Wetter. Selbsttest mit denselben vier Fällen.
- **Logit-Klasse** in `AMPEL_CLASSES` mit den fünf Koeffizienten und
  einer Funktionsform `logit`; `attach_class_scores` rechnet `s`;
  `--thresholds` misst die beiden Quantile für `holz_winter` (Design B,
  P1, wie am 2026-09-19 für die anderen) und für `sommer` bei 14,5 °C
  neu; `verify_class_constants` wacht wie bisher.
- **Fixtures** für `test/ampel_model_test.dart`: je Form ein Satz
  (Regen, Temperatur, Feuchte → Score, Stufe), aus dem Werkzeug erzeugt.
- **Hold-out-Vermerk** im Werkzeug-Kopf wie bei `sommer`: DE-Test,
  AT/CH-Test, Klimatologie, mit den Bändern aus 18.

Hinweis zur Messbasis: Das Labor rechnet mit Open-Meteo-Tagesmitteln
(ERA5-Land) für `T`; die App nimmt (Max + Min)/2 der Luftstation. Das
gilt schon heute für die Glocke; im Logit geht `T` linear und
quadratisch ein, ein Versatz von wenigen Zehntelgrad verschiebt `s` um
weniger als 0,01. Mitschreiben, nicht beheben.

## 5. Evidenzstufen, Changelog, Hüter

- `ampelEvidenceBySpecies`: Samtfußrübling, Judasohr, Austernseitling,
  Schwefelporling, Lungenseitling, Leberpilz → `belegt`; Rehbrauner
  Dachpilz, Krause Glucke → `vorlaeufig` (Effekt da, Band mit Null);
  Pfifferling → `vorlaeufig` (Fenster ohne Hold-out). Die Wortwahl
  („gut belegt“ / „unsichere Datenlage“) bleibt.
- `test/ampel_evidence_test.dart` hält Klasse und Stufe deckungsgleich —
  die acht neuen Arten müssen an beiden Stellen stehen.
- `CHANGELOG.md`: ein Block „Pilzampel für Winter- und Holzpilze“ in
  Alltagssprache, plus der Pfifferling-Satz, mit dem Vorbehalt.
- Version Guard: `lib/` ändert sich → Bump; `tool/` und `docs/` allein
  nicht.
- `test/privacy_policy_test.dart`: kein neuer Host in `lib/`
  (opendata.dwd.de wird nur in CI gelesen).

## 6. PR-Schnitt (drei PRs, in dieser Reihenfolge)

| PR | Inhalt | Guard |
|---|---|---|
| **1 — Daten** | `spot_weather.py` + drittes Netz, `MoistureStation`, Tabelle liest es, Spot-Blatt zeigt die Zeile | Bump (lib) |
| **2 — Spiegel** | DWD-Loader in `tool/`, Logit-Klasse im Werkzeug, `--thresholds` für `holz_winter` und `sommer` 14,5, Fixtures, dieses Dokument mit den gemessenen Schwellen ergänzt | kein Bump |
| **3 — Kern** | `AmpelLogitClass`, Klasse `holz_winter`, Pfifferling 14,5 + neue Schwellen, Evidenzstufen, Fläche, Changelog | Bump |

PR 1 ist für sich sinnvoll (die Zeile im Blatt), PR 2 hat keinen
sichtbaren Effekt, PR 3 schaltet die Klasse frei. Reihenfolge, damit
nie eine Klasse rechnet, deren Daten noch nicht im Release liegen.

## 7. Offene Entscheidungen für den Betreiber

1. **Anzeigename** der Klasse: „Judasohr & Co.“ oder anders.
2. **Fläche in PR 3 oder später** (Abschnitt 3): Vorgabe ist PR 3.
3. **Cantharellales als DE-only-Klasse** — ja, nein, später.
4. **`feat/ampel-auftrag-3`** (40 Commits, unmerged, trägt die
   Design-B-Werkzeuge und `found_day`/`control_days`): Die Spiegel-
   Arbeit in PR 2 setzt auf diesen Stand auf, nicht auf `main`. Entweder
   den Branch vorher mergen, oder PR 2 darauf aufsetzen.

## Was das nicht ist

Kein neuer Beleg. Alle Zahlen sind gemessen und stehen in den
Laborberichten; dieses Dokument übersetzt sie in Code-Änderungen. Der
Testteil ist für Auswahl tabu — wer an den Konstanten dreht, misst neu
und schreibt das Datum dazu.

## Nachtrag 2026-09-20 — die Entscheidungen des Betreibers, und was sich am Schnitt ändert

1. **Anzeigename:** „Austernseitling & Co.“ (Schlüssel `holz_winter`).
2. **Fläche in PR 3**, ja. Die Klassen werden über die **Chips im
   Filtermenü** zugeschnitten — wie seit 1.142.0; neue Klassen erscheinen
   dort, weil die Chips aus `ampelClasses` kommen.
3. **Cantharellales** (Leistlinge: die Ordnung, zu der auch der
   Pfifferling gehört; in den Daten steht er aber für sich) wird
   angelegt — als **„Herbsttrompete & Co.“** {Herbsttrompete,
   Semmelstoppelpilz, Trompetenpfifferling}, Schlüssel `cantharellales`,
   Logit, **nur für Deutschland belegt** (die App ist hauptsächlich auf
   Deutschland ausgelegt). Die Herbsttrompete verlässt damit
   „Steinpilz & Co.“; deren Schwellen werden mit vier Mitgliedern neu
   gemessen — in PR 3, zusammen mit dem Umzug, damit Werkzeug und App
   nie verschiedene Mitglieder sehen.
4. **Basis:** `main` ist in `feat/ampel-auftrag-3` gemergt (0e18b56);
   PR 2 setzt darauf auf.

**Der Schnitt, wie er jetzt läuft:**

| PR | Stand | Inhalt |
|---|---|---|
| #482 (PR 1) | offen | Bodenfeuchte-Stationen in Tabelle und Spot-Blatt, 1.149.0 |
| #485 (PR 2) | offen | `tool/ampel_logit_klasse.py` (Spiegel, Schwellen gemessen und gepinnt), **Pfifferling 14,5 °C** samt neu gemessener Schwellen und Evidenzstufe `vorlaeufig`, 1.150.0 — Pfifferling ist von PR 3 hierher gewandert, weil `ampel_validate --self-test` Werkzeug und Dart zusammenhält und ein Werkzeug-only-PR sonst rot wäre |
| PR 3 | folgt | `AmpelLogitClass`, beide Klassen, Herbsttrompete-Umzug + `herbst`-Schwellen neu, Fläche mit Feuchtestation je Zelle, Evidenzstufen, Changelog |
| PR 4 | Vorschlag | **Reiter „Pilze“**: die Klassen und ihre Arten, je Art eine Mini-Saisonkurve, hervorgehoben, was gerade Saison hat (Kurve über einer Schwelle, z. B. 15 %). Damit bleibt für den Nutzer transparent, was wozu gehört. Eigener Plan vor der Umsetzung. |

Reihenfolge beim Mergen: #482, dann #485 (trägt 1.150.0; wer #485 zuerst
mergt, muss #482 auf 1.151.0 heben), dann PR 3.
