# Hold-out der Klasse „herbst_holz“

Stand: 2026-09-13 · Erzeugt von `tool/ampel_validate.py --holdout AT,CH --class herbst_holz` · Prüfplan: `docs/pilzampel-artenfenster.md`

Angepasst wurde in **Deutschland** (Jahre bis 2018), geprüft in **AT und CH** — dort sind ALLE Jahre Prüfjahre, denn an der Anpassung war keiner von ihnen beteiligt.

**Geprüft wird das Fenster der KLASSE, nicht das jeder Art.** Ausgeliefert würde ein Fenster für alle Mitglieder; eines je Art zu prüfen beantwortete eine Frage, die sich in der App nie stellt.

## Die Bedingung, die vor der Messung feststand

> Das an deutschen Funden angepasste Fenster der Klasse trennt auch in AT und CH besser als die 13 °C — gepaarte AUC dort mindestens **+0.05** über der mit 13 °C, und zwar bei **allen** Mitgliedern.

> **Beide oder keine.** Eine Klasse, von deren Arten eine besteht, war vorab ausgeschlossen.

> Dazu, **ohne Torfunktion**, eine Richtungsaussage: Die im Hold-out neu angepassten Optima liegen unter 13 °C.

## Das Fenster

Abgeleitet und nicht gewählt — der Median der deutschen Optima seiner Mitglieder, gerechnet bei diesem Lauf:

| Mitglied | Optimum in DE | Paare DE |
|---|--:|--:|
| Hallimasch | 11.0 °C | 1953 |
| Stockschwämmchen | 12.2 °C | 1277 |

**Fenster der Klasse: 11.625 °C.** Die Bedingung hängt an der Latte, nicht an dieser Zahl.

## Gemessen

| Art | Paare AT+CH | Jahre | AUC mit 13 °C | AUC mit 11.625 °C | Differenz (95 %) | Kontrolle | Bedingung |
|---|--:|--:|--:|--:|---|--:|---|
| Hallimasch | 1280 | 20 | 0.766 | 0.784 | +0.018 [-0.003, +0.040] | 0.501 | nicht erfüllt: +0.018 unter +0.05 |
| Stockschwämmchen | 527 | 20 | 0.662 | 0.626 | -0.036 [-0.073, +0.000] | 0.501 | nicht erfüllt: -0.036 unter +0.05 |

Die Spalte „Kontrolle“ ist die abstandsgleiche Kontrolle — Vergleichstag gegen seinen am Fundtag gespiegelten Partner. Sie MUSS bei 0,50 liegen (Toleranz ±0.03); tut sie es nicht, ist die Ziehung verzerrt und die Zahl daneben wertlos.

## Der Ausgang

**Nicht bestanden — kein Mitglied erreicht die Latte.**

**Was das heißt, und was nicht.** Es heißt: „bei dieser Stichprobengröße und diesem Abstand nicht nachweisbar“ — nicht „es gibt keinen Unterschied“. Die Glocke ist in ihrer Mitte flach, und 11.625 °C liegen nur 1.4 K neben den 13 °C; ein echter Unterschied dieser Größe kann die Latte verfehlen.

Ausgeliefert wird die Klasse trotzdem nicht: Der Vorbehalt der App gilt dem, was belegt ist, und nicht dem, was plausibel ist.

## Die Richtungsaussage (kein Tor)

Optima, im Hold-out selbst neu angepasst — angepasst und geprüft auf denselben Daten, also kein Beleg:

| Art | Optimum in AT+CH | bestes Band |
|---|--:|---|
| Hallimasch | 11.5 °C | 11.5 |
| Stockschwämmchen | 15.5 °C | 15.5 |

**Die Richtung hält nur zum Teil:** Hallimasch 11.5 °C unter den 13 °C, Stockschwämmchen 15.5 °C darüber. Für die Klasse als Ganzes ist das keine Stütze — ein gemeinsames Fenster ist gerade das, was hier auseinanderfällt.

## Grenzen

Angepasst wurde ausschließlich an GBIF. Die eigenen Funde und Leergänge der App bleiben draußen — sie sind der unabhängige Prüfstein aus #199.

Auch ein bestätigtes Fenster sagt „die Bedingungen sind günstig“, nicht „hier stehen Pilze“.
