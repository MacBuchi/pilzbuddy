# Hold-out der Klasse „sommer“

Stand: 2026-09-25 · Erzeugt von `tool/ampel_validate.py --holdout IT --class sommer` · Prüfplan: `docs/pilzampel-artenfenster.md`

Angepasst wurde in **Deutschland** (Jahre bis 2018), geprüft in **IT** — dort sind ALLE Jahre Prüfjahre, denn an der Anpassung war keiner von ihnen beteiligt.

**„IT“ ist hier der Alpenraum, nicht Italien:** Der lokale Bestand trägt italienische Meldungen nur aus der Box 6.6–13.9° O, 45.6–47.2° N (Südtirol, Trentino, Belluno, Sondrio, Aostatal; `tool/gbif_download.py`, #612). Die Zahlen unten gelten für diese Box.

**Geprüft wird das Fenster der KLASSE, nicht das jeder Art.** Ausgeliefert würde ein Fenster für alle Mitglieder; eines je Art zu prüfen beantwortete eine Frage, die sich in der App nie stellt.

## Die Bedingung, die vor der Messung feststand

> Das an deutschen Funden angepasste Fenster der Klasse trennt auch in IT besser als die 13 °C — gepaarte AUC dort mindestens **+0.05** über der mit 13 °C, und zwar bei **allen** Mitgliedern.

> **Beide oder keine.** Eine Klasse, von deren Arten eine besteht, war vorab ausgeschlossen.

> Dazu, **ohne Torfunktion**, eine Richtungsaussage: Die im Hold-out neu angepassten Optima liegen unter 13 °C.

## Das Fenster

Abgeleitet und nicht gewählt — der Median der deutschen Optima seiner Mitglieder, gerechnet bei diesem Lauf:

| Mitglied | Optimum in DE | Paare DE |
|---|--:|--:|
| Pfifferling | 17.5 °C | 1332 |

**Fenster der Klasse: 17.5 °C.** Die Bedingung hängt an der Latte, nicht an dieser Zahl.

## Gemessen

| Art | Paare IT | Jahre | AUC mit 13 °C | AUC mit 17.5 °C | Differenz (95 %) | Kontrolle | Bedingung |
|---|--:|--:|--:|--:|---|--:|---|
| Pfifferling | 29 | 10 | 0.483 | 0.724 | +0.241 [-0.143, +0.481] | 0.690 | nicht auswertbar |

Die Spalte „Kontrolle“ ist die abstandsgleiche Kontrolle — Vergleichstag gegen seinen am Fundtag gespiegelten Partner. Sie MUSS bei 0,50 liegen; tut sie es nicht, ist die Ziehung verzerrt und die Zahl daneben wertlos.

**Die Toleranz hängt seit 2026-09-17 an der Paarzahl** (zwei Standardfehler, `2·√(0,25/n)`) statt an festen ±0,03. Die feste Zahl war ein Filter auf die Stichprobengröße: Zwei Standardfehler sind ±0,045 bei 538 Paaren und ±0,022 bei 2000. Frühere Berichte nennen weiterhin die ±0,03, unter der sie entstanden sind — sie werden nicht rückwirkend umetikettiert.

## Der Ausgang

**Noch nicht entschieden.** Nicht auswertbar: Pfifferling (Ziehung verzerrt: 0.690).

Das ist kein Fehlschlag, sondern eine Lücke — und die Bedingung bleibt unverändert stehen.

**Bis dahin ändert sich nichts an der App.**

## Die Richtungsaussage (kein Tor)

Optima, im Hold-out selbst neu angepasst — angepasst und geprüft auf denselben Daten, also kein Beleg. Die Latte dieser Klasse: unter 13 °C.

| Art | Optimum in IT | bestes Band |
|---|--:|---|
| Pfifferling | 17.0 °C | 15.5 bis 18.5 |

**Keines der Optima liegt unter 13 °C** (Pfifferling 17.0 °C). Die Richtungsaussage hält nicht.

## Grenzen

Angepasst wurde ausschließlich an GBIF. Die eigenen Funde und Leergänge der App bleiben draußen — sie sind der unabhängige Prüfstein aus #199.

Auch ein bestätigtes Fenster sagt „die Bedingungen sind günstig“, nicht „hier stehen Pilze“.
