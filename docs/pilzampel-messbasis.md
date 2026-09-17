# Die Messbasis — welchen Datensatz nageln wir fest?

Stand: 2026-09-17 · Erzeugt von `tool/openmeteo_variables.py --cloud` ·
Arbeitsplan: `docs/pilzampel-fahrplan.md`, Phase 0

Diese Seite hält fest, worauf ab jetzt gemessen wird. Sie wächst mit den
Schritten 0.1 bis 0.4; im Moment steht hier **0.1 — die Wahl des
Datensatzes**.

Die Frage kommt vor allen anderen, weil sie jede Zahl davor mitbetrifft.
`docs/pilzampel-openmeteo-lokal.md` hat gezeigt, dass unsere Messungen gar
keinen Datensatz pinnen: `fetch_weather` fragt ohne `models=`, und die
Vorgabe „best match" wechselt mitten in unserer Zeitreihe das Instrument.

---

## Was gemessen wurde

Zehn Orte in DACH, je Land Tiefland und Gebirge, in vier Fenstern: Herbst
und Winter, je einmal vor und einmal nach der vermuteten Naht. Sechs
Variablen, drei Modelle, dazu der öffentliche Dienst als Gegenprobe.

Die Trennung nach **Winter** und nach **AT/CH** ist kein Beiwerk. Genau
dort schlägt ein Instrumentwechsel am ehesten durch — Tiefstwerte, Frost
und Gebirge sind die Fälle, in denen ein 25-km-Raster und ein
11-km-Raster auseinanderlaufen. Und genau dort lag der gescheiterte
Kaltklassen-Hold-out.

## Befund 1 — Die Naht liegt exakt auf dem 1. Januar 2017

Thüringer Wald, Mittel über den 1.–10. Oktober, Tagesmitteltemperatur:

| Jahr | Vorgabe | `era5_land` | `era5` | Δ zu `era5_land` | Δ zu `era5` |
|---|--:|--:|--:|--:|--:|
| 2014 | 11,05 | 11,05 | 9,93 | **0,00** | 1,12 |
| 2015 | 9,13 | 9,13 | 7,91 | **0,00** | 1,22 |
| 2016 | 6,00 | 6,00 | 5,16 | **0,00** | 0,84 |
| 2017 | 6,21 | 7,19 | 6,53 | 0,98 | 0,32 |
| 2018 | 8,18 | 8,53 | 7,24 | 0,35 | 0,94 |

Bis 2016 ist die Vorgabe **Ziffer für Ziffer** ERA5-Land, ab 2017 ist sie
es nicht mehr. `ecmwf_ifs` liefert für 2015 gar nichts und ab 2017 sehr
wohl — die Vorgabe ist ab dort IFS HRES. Das bestätigt die frühere
Messung und nagelt zusätzlich das Datum fest.

**Was das für unsere Hold-outs heißt**, in Jahren gezählt
(`FIRST_YEAR = 2006`, `FIT_UNTIL_YEAR = 2018`, `LAST_COMPLETE_YEAR = 2025`):

| | Jahre | davon vor der Naht |
|---|--:|--:|
| Anpassung (2006–2018) | 13 | 11 — **85 %** |
| Prüfung (2019–2025) | 7 | 0 — **0 %** |

Angepasst wird also zu fünf Sechsteln auf ERA5-Land und geprüft
ausschließlich auf IFS HRES. Das ist kein Randeffekt, das ist die
Trennlinie selbst.

## Befund 2 — Die eigene Instanz stimmt auch bei den neuen Variablen

Die Zusage aus `docs/pilzampel-openmeteo-lokal.md` war bisher nur für die
**Vorgabe** gemessen. Jetzt für alle drei Modelle und alle sechs
Variablen, gegen den öffentlichen Dienst:

**Abweichung 0,000 in jeder Zelle** — vier Fenster, zehn Orte, sechs
Variablen, drei Modelle. Keine einzige Ausnahme.

Damit dürfen auch die neuen Variablen aus der Instanz kommen, ohne dass
eine Zahl außerhalb dieses Rechners unnachrechenbar wird.

## Befund 3 — Was welches Modell überhaupt liefert

| Variable | Vorgabe | `era5` | `era5_land` |
|---|:-:|:-:|:-:|
| `temperature_2m_mean` | ✓ | ✓ | ✓ |
| `temperature_2m_min` | ✓ | ✓ | ✓ |
| `precipitation_sum` | ✓ | ✓ | **fehlt** |
| `snow_depth_max` | ✓ | **fehlt** | ✓ |
| `soil_moisture_7_to_28cm` | ✓ | ✓ | ✓ |
| `soil_temperature_0_to_7cm` | ✓ | ✓ | ✓ |

Keines der beiden Modelle liefert alles. ERA5-Land hat keinen
Niederschlag, ERA5 keine Schneehöhe. Eine Mischung ist damit nicht eine
Vorliebe, sondern die einzige Möglichkeit, alle sechs Variablen zu
bekommen.

## Befund 4 — Für diese Mischung gibt es einen Namen

`era5_seamless` liefert alle sechs Variablen. Und es ist **exakt** die
Mischung, die der Fahrplan vorschlägt — gemessen, nicht angenommen:

| Variable | gegen `era5_land` | gegen `era5` |
|---|--:|--:|
| `temperature_2m_mean` | **0,0000** | 0,68–1,06 K |
| `temperature_2m_min` | **0,0000** | 1,00–1,38 K |
| `precipitation_sum` | (fehlt dort) | **0,0000** |
| `snow_depth_max` | **0,0000** | (fehlt dort) |
| `soil_moisture_7_to_28cm` | **0,0000** | 0,037–0,041 m³/m³ |
| `soil_temperature_0_to_7cm` | **0,0000** | 0,98–1,21 K |

In allen vier Fenstern, beide Jahreszeiten, beide Seiten der Naht.

**Und „seamless" meint hier nicht das, wovor man sich fürchten müsste.**
Der Name klingt nach genau der Zeitnaht, die wir loswerden wollen —
gemessen ist er es nicht: Für die letzten fünf Tage liefert
`era5_seamless` `None`, genau wie `era5_land` und `era5`. Es spleißt kein
Vorhersagemodell an den aktuellen Rand. Die ERA5-Verzögerung wird ehrlich
als fehlender Wert gemeldet. Die **Vorgabe** dagegen füllt diese Tage —
mit IFS. Ihre Naht ist heute noch aktiv.

## Befund 5 — Der Instrumenteffekt hat kein festes Vorzeichen

Das ist der Befund, der am meisten wiegt. Mittlere **vorzeichenbehaftete**
Verschiebung `era5_seamless − Vorgabe`:

| Fenster | Land | T Mittel | T min | Regen |
|---|---|--:|--:|--:|
| Herbst 2015 | DE / AT / CH | +0,000 | +0,000 | +0,000 |
| Herbst 2020 | DE | +0,665 | +0,434 | −0,354 |
| Herbst 2020 | AT | +0,184 | −0,319 | +0,419 |
| Herbst 2020 | CH | **+1,222** | **+1,296** | +0,334 |
| Winter 2015 | DE / AT / CH | +0,000 | +0,000 | +0,000 |
| Winter 2020 | DE | +0,203 | +0,292 | −0,772 |
| Winter 2020 | AT | **−1,317** | −0,966 | −0,419 |
| Winter 2020 | CH | **−0,899** | −0,644 | −0,006 |

Zwei Dinge stehen da:

**Vor 2017 ist die Verschiebung überall exakt null.** Der vorgeschlagene
Datensatz IST die damalige Vorgabe. Pinnen ändert an elf unserer zwanzig
Jahre keine einzige Stelle; es zieht nur die restlichen neun auf dasselbe
Instrument.

**Nach 2017 dreht sich das Vorzeichen mit Jahreszeit und Land.** Im
Herbst ist der gepinnte Datensatz wärmer, im alpinen Winter über ein Kelvin
kälter. Das ist keine Verschiebung, die sich herauskürzt — es ist eine
Verzerrung entlang **genau der Achse**, auf der die Kaltklasse geprüft
wurde: Winterarten, AT und CH, Prüfjahre ab 2019.

Damit ist die Feststellung aus dem Fahrplan jetzt beziffert und nicht mehr
nur plausibel: **Der gescheiterte Kaltklassen-Hold-out ist nicht eindeutig
deutbar.** Ob er am Fenster lag oder am Instrument, lässt sich auf der
alten Basis nicht entscheiden. Das ist kein Freispruch für die Klasse —
sie kann trotzdem falsch sein. Es heißt nur, dass die Messung die Frage
nicht beantwortet hat, die sie beantworten sollte.

## Empfehlung

**`models=era5_seamless` über alle Jahre.** Ein Parameter, ein Name im
Cache-Schlüssel, alle sechs Variablen.

Die Begründung in der Reihenfolge ihres Gewichts:

1. **Es ist zeitlich konstant** — das war die ganze Übung.
2. **Es ist kein neues Instrument.** Elf von zwanzig Jahren liegen schon
   darauf, mit Abweichung 0,000. Wir übernehmen den Datensatz, auf dem
   der größere Teil unserer Anpassdaten ohnehin ruht, statt einen dritten
   einzuführen.
3. **ERA5-Land ist im Gebirge das feinere Raster** (0,1° gegen 0,25°).
   AT und CH sind unser Länder-Hold-out; dort ist die Auflösung nicht
   akademisch. Die Alternative „alles aus ERA5" wäre ein Instrument
   statt zwei, würde aber die Temperatur im Gebirge vergröbern — an der
   Stelle, wo die Kaltklasse gescheitert ist.
4. **Es hat keine Zeitnaht am aktuellen Rand**, gemessen.

Der ehrliche Preis: Temperatur und Boden kommen aus einem 11-km-Raster,
der Niederschlag aus einem 28-km-Raster. Zwei Raster in einer Formel sind
nicht schön. Sie sind aber unkritisch, solange keines mitten in der Reihe
wechselt — und die Messung oben zeigt, dass genau das der Unterschied zum
Status quo ist.

## Was daraus folgt, bevor etwas Neues gemessen wird

- **Der Cache wird ungültig.** Nicht teilweise — für die Jahre ab 2017
  vollständig. Ein neuer Ordner, der alte bleibt stehen (Auftrag).
- **Die Schwellen müssen neu gemessen werden.** Eine
  Verschiebung von +0,7 bis +1,2 K im Herbst verschiebt die ganze
  Score-Verteilung, und die Schwellen sind Quantile davon. Das ist
  Schritt 0.4.
- **Die App läuft danach auf einem anderen Instrument als die
  Validierung.** Heute tun beide dasselbe („best match", also IFS für die
  jüngeren Jahre). Nach dem Pinnen misst die Validierung auf ERA5-Land,
  während die App live IFS bekommt — ERA5 hinkt fünf Tage hinterher und
  kommt für „heute" nicht in Frage. Das ist keine Nebensache und gehört
  vor Phase 4 entschieden; die Größenordnung des Unterschieds steht in
  Befund 5. **Bis dahin wird an der ausgelieferten Ampel nichts geändert.**

## Grenzen dieser Messung

Zehn Orte und vier Fenster sagen, **dass** sich die Instrumente
unterscheiden und **wo** am stärksten. Sie sagen nicht, wie stark sich
eine AUC dadurch verschiebt — das ist der Referenzlauf in 0.4 und erst
danach beantwortbar.

Die Verfügbarkeitstabelle gilt für die vier gemessenen Fenster. Eine
Variable, die 2015 und 2020 überall liefert, kann in einem einzelnen
anderen Jahr Lücken haben; fehlende Jahre bleiben ein Abbruchgrund, nicht
ein stiller Ausfall.

---

# 0.2 und 0.3 — die Paarziehung

Gebaut in `tool/ampel_basis.py`, damit die Messbasis an einer Stelle steht
und nicht über fünftausend Zeilen verteilt.

## Was sich geändert hat

- **Entdoppeln**: höchstens eine Meldung je Melder × ~1 km × Tag, und zwar
  **vor** dem Stichprobenziehen. Andersherum zöge man aus einem von
  Clustern aufgeblähten Topf.
- **`recordedBy` und `countryCode`** werden mitgeführt. Beide Spalten lagen
  die ganze Zeit im Bestand und wurden nur nie gelesen.
- **Der Abstand zum Vergleichstag trägt sein Vorzeichen.** Ohne die Seite
  ist der Richtungs-Split aus Phase 1.1 nicht messbar.
- **Der Mindestabstand hängt am Modell**, nicht an einer festen Zahl: Er
  ist das längste Fenster dessen, was gerade gemessen wird. Für die
  ausgelieferte Ampel sind das die 26 Tage des Regenfensters, es bleibt
  also vorerst bei 26 bis 45.
- **Der Vorlauf wächst auf 28 Tage.** Das ist NICHT dasselbe wie der
  Mindestabstand, auch wenn beide bisher 26 waren: Der Vorlauf sagt,
  wieviel Wetter im Cache liegt. Phase 2 will Frostdosen über 28 Tage
  rechnen, und nachträglich wäre das ein zweiter vollständiger Neuabruf.

## Die alte Basis bleibt reproduzierbar

Das war die Bedingung, unter der überhaupt etwas geändert werden durfte.
Nachgewiesen, nicht behauptet:

- Die Zufallsfolge der Vergleichstage ist über drei Seeds und je 200 Züge
  **identisch** mit der alten Vorschrift.
- Alle **1241** vorhandenen Wetterdateien passen weiter auf den
  Cache-Schlüssel — die Vorgabe behält ihren Namen ohne Fingerabdruck,
  jeder gepinnte Datensatz bekommt einen und landet in eigenen Dateien.
- Maronenröhrling 0.743, Pfifferling 0.607, Hallimasch 0.749,
  Austernseitling 0.463 reproduzieren auf der Vorgabe exakt.

## Das Entdoppeln nimmt viel weniger weg als erwartet

Der Fahrplan begründete es mit den ~69 % Meldungen aus einer Hand in
typischen 5-km-Zellen. Gemessen, über die ausgewerteten Arten in DE:

| Art | Meldungen | entdoppelt | weg |
|---|--:|--:|--:|
| Hallimasch | 2594 | 2341 | 9,8 % |
| Steinpilz | 2259 | 2156 | 4,6 % |
| Maronenröhrling | 2485 | 2423 | 2,5 % |
| Pfifferling | 1356 | 1331 | 1,8 % |
| Stockschwämmchen | 1332 | 1312 | 1,5 % |
| Birkenpilz | 1203 | 1186 | 1,4 % |
| Herbsttrompete | 297 | 293 | 1,3 % |
| Austernseitling | 1628 | 1615 | 0,8 % |
| Fichtenreizker | 779 | 776 | 0,4 % |
| **gesamt** | **13 933** | **13 433** | **3,6 %** |

**3,6 % statt der erwarteten Größenordnung.** Der Grund ist der Schlüssel
selbst: Er fängt nur, was dieselbe Person am selben Tag im selben
Kilometer für dieselbe Art mehrfach meldet — und das ist selten. Das
eigentliche Cluster-Problem liegt quer dazu: **eine Person, die dieselbe
Stelle dreißigmal in einer Saison besucht.** Diese dreißig Meldungen sind
keine Dubletten nach dieser Regel und trotzdem nicht unabhängig. Dafür ist
das Melder-Bootstrap aus Phase 1.4 zuständig, nicht das Entdoppeln.

Die Regel bleibt trotzdem drin: Sie kostet nichts und die 9,8 % beim
Hallimasch sind echt.

## Eine Grenze, die beißt

`_finds_from_local` holt höchstens **3000** Meldungen je Art, sortiert nach
`gbifID`. Unter den ausgewerteten Arten überschreitet genau eine das:
**Judasohr mit 3097 in DE** — ausgerechnet die Art, an der der
Kaltklassen-Hold-out gescheitert ist. Die Wirkung ist klein, weil danach
ohnehin auf 2000 heruntergezogen wird; die Auswahl ist aber nicht zufällig,
sondern schneidet die jüngsten Einträge ab. Für die Arten dieser Messung
bleibt es folgenlos, für eine häufigere Art wäre es das nicht.
