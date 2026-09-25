# Hold-out der Klasse „herbst“

Stand: 2026-09-25 · Erzeugt von `tool/ampel_validate.py --holdout IT --class herbst` · Prüfplan: `docs/pilzampel-artenfenster.md`

Angepasst wurde in **Deutschland** (Jahre bis 2018), geprüft in **IT** — dort sind ALLE Jahre Prüfjahre, denn an der Anpassung war keiner von ihnen beteiligt.

**„IT“ ist hier der Alpenraum, nicht Italien:** Der lokale Bestand trägt italienische Meldungen nur aus der Box 6.6–13.9° O, 45.6–47.2° N (Südtirol, Trentino, Belluno, Sondrio, Aostatal; `tool/gbif_download.py`, #612). Die Zahlen unten gelten für diese Box.

**Gemischte Lizenzbasis (`--include-nc`):** Die Ziehung in IT nimmt zusätzlich Meldungen unter CC BY-NC 4.0 — nur für diese Messung, nie für ein Asset der App; die deutsche Anpassung bleibt auf CC0 und CC BY. Frühere Hold-outs (AT + CH) liefen ohne NC und sind damit nicht Zahl für Zahl vergleichbar.

**Geprüft wird das Fenster der KLASSE, nicht das jeder Art.** Ausgeliefert würde ein Fenster für alle Mitglieder; eines je Art zu prüfen beantwortete eine Frage, die sich in der App nie stellt.

## Die Bedingung, die vor der Messung feststand

> Das an deutschen Funden angepasste Fenster der Klasse trennt auch in IT besser als die 13 °C — gepaarte AUC dort mindestens **+0.05** über der mit 13 °C, und zwar bei **allen** Mitgliedern.

> **Beide oder keine.** Eine Klasse, von deren Arten eine besteht, war vorab ausgeschlossen.

> Dazu, **ohne Torfunktion**, eine Richtungsaussage: Die im Hold-out neu angepassten Optima liegen unter 13 °C.

## Das Fenster

Abgeleitet und nicht gewählt — der Median der deutschen Optima seiner Mitglieder, gerechnet bei diesem Lauf:

| Mitglied | Optimum in DE | Paare DE |
|---|--:|--:|
| Steinpilz | 13.0 °C | 1990 |
| Maronenröhrling | 13.0 °C | 1974 |
| Birkenpilz | 14.5 °C | 1203 |
| Fichtenreizker | 12.0 °C | 765 |

**Fenster der Klasse: 13.0 °C.** Die Bedingung hängt an der Latte, nicht an dieser Zahl.

## Gemessen

| Art | Paare IT | Jahre | AUC mit 13 °C | AUC mit 13.0 °C | Differenz (95 %) | Kontrolle | Bedingung |
|---|--:|--:|--:|--:|---|--:|---|
| Steinpilz | 211 | 15 | 0.626 | 0.626 | +0.000 [+0.000, +0.000] | 0.531 | nicht erfüllt: +0.000 unter +0.05 |
| Maronenröhrling | 103 | 15 | 0.777 | 0.777 | +0.000 [+0.000, +0.000] | 0.456 | nicht erfüllt: +0.000 unter +0.05 |
| Birkenpilz | 10 | 7 | 0.600 | 0.600 | +0.000 [+0.000, +0.000] | 0.800 | nicht erfüllt: +0.000 unter +0.05 |
| Fichtenreizker | 87 | 18 | 0.770 | 0.770 | +0.000 [+0.000, +0.000] | 0.494 | nicht erfüllt: +0.000 unter +0.05 |

Die Spalte „Kontrolle“ ist die abstandsgleiche Kontrolle — Vergleichstag gegen seinen am Fundtag gespiegelten Partner. Sie MUSS bei 0,50 liegen; tut sie es nicht, ist die Ziehung verzerrt und die Zahl daneben wertlos.

**Die Toleranz hängt seit 2026-09-17 an der Paarzahl** (zwei Standardfehler, `2·√(0,25/n)`) statt an festen ±0,03. Die feste Zahl war ein Filter auf die Stichprobengröße: Zwei Standardfehler sind ±0,045 bei 538 Paaren und ±0,022 bei 2000. Frühere Berichte nennen weiterhin die ±0,03, unter der sie entstanden sind — sie werden nicht rückwirkend umetikettiert.

## Der Ausgang

**Nicht messbar — das Fenster der Klasse IST die Referenz.** 13.0 °C gegen 13 °C ergibt bei jeder Art +0,000; dieser Hold-out prüft, ob ein ABWEICHENDES Fenster reist, und hier weicht keines ab.

Was die Tabelle trotzdem sagt: die AUC mit 13 °C je Art ist die Trennschärfe der ausgelieferten Ampel in IT, bei der genannten Paarzahl und mit der Kontrolle daneben. Ob diese Zahl trägt, ist eine andere Frage mit einer anderen Latte (`docs/pilzampel-pruefachsen.md`).

**Bis dahin ändert sich nichts an der App.**

## Die Richtungsaussage (kein Tor)

Optima, im Hold-out selbst neu angepasst — angepasst und geprüft auf denselben Daten, also kein Beleg. Die Latte dieser Klasse: unter 13 °C.

| Art | Optimum in IT | bestes Band |
|---|--:|---|
| Steinpilz | 16.0 °C | 16.0 |
| Maronenröhrling | 12.5 °C | 12.5 |
| Birkenpilz | 14.8 °C | 14.5 bis 15.0 |
| Fichtenreizker | 12.5 °C | 12.0 bis 13.0 |

**Die Richtung hält nur zum Teil:** Maronenröhrling 12.5 °C, Fichtenreizker 12.5 °C unter den 13 °C, Steinpilz 16.0 °C, Birkenpilz 14.8 °C darüber. Für die Klasse als Ganzes ist das keine Stütze — ein gemeinsames Fenster ist gerade das, was hier auseinanderfällt.

## Grenzen

Angepasst wurde ausschließlich an GBIF. Die eigenen Funde und Leergänge der App bleiben draußen — sie sind der unabhängige Prüfstein aus #199.

Auch ein bestätigtes Fenster sagt „die Bedingungen sind günstig“, nicht „hier stehen Pilze“.
