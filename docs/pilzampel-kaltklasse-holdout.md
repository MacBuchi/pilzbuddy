# Hold-out der Klasse „kalt“

Stand: 2026-09-13 · Erzeugt von `tool/ampel_validate.py --holdout AT,CH --class kalt` · Prüfplan: `docs/pilzampel-artenfenster.md`

Angepasst wurde in **Deutschland** (Jahre bis 2018), geprüft in **AT und CH** — dort sind ALLE Jahre Prüfjahre, denn an der Anpassung war keiner von ihnen beteiligt.

**Geprüft wird das Fenster der KLASSE, nicht das jeder Art.** Ausgeliefert würde ein Fenster für alle Mitglieder; eines je Art zu prüfen beantwortete eine Frage, die sich in der App nie stellt.

## Die Bedingung, die vor der Messung feststand

> Das an deutschen Funden angepasste Fenster der Klasse trennt auch in AT und CH besser als die 13 °C — gepaarte AUC dort mindestens **+0.05** über der mit 13 °C, und zwar bei **allen** Mitgliedern.

> **Beide oder keine.** Eine Klasse, von deren Arten eine besteht, war vorab ausgeschlossen.

> Dazu, **ohne Torfunktion**, eine Richtungsaussage: Die im Hold-out neu angepassten Optima liegen unter 5 °C.

## Das Fenster

Abgeleitet und nicht gewählt — der Median der deutschen Optima seiner Mitglieder, gerechnet bei diesem Lauf:

| Mitglied | Optimum in DE | Paare DE |
|---|--:|--:|
| Austernseitling | -3.2 °C | 987 |
| Judasohr | 1.5 °C | 1255 |
| Samtfußrübling | -1.0 °C | 540 |

**Fenster der Klasse: -1.0 °C.** Die Bedingung hängt an der Latte, nicht an dieser Zahl.

## Gemessen

| Art | Paare AT+CH | Jahre | AUC mit 13 °C | AUC mit -1.0 °C | Differenz (95 %) | Kontrolle | Bedingung |
|---|--:|--:|--:|--:|---|--:|---|
| Austernseitling | 204 | 20 | 0.480 | 0.583 | +0.103 [-0.051, +0.232] | 0.471 | **erfüllt** |
| Judasohr | 1068 | 20 | 0.580 | 0.513 | -0.066 [-0.117, -0.013] | 0.503 | nicht erfüllt: -0.066 unter +0.05 |
| Samtfußrübling | 243 | 18 | 0.416 | 0.650 | +0.235 [+0.153, +0.312] | 0.467 | nicht auswertbar |

Die Spalte „Kontrolle“ ist die abstandsgleiche Kontrolle — Vergleichstag gegen seinen am Fundtag gespiegelten Partner. Sie MUSS bei 0,50 liegen (Toleranz ±0.03); tut sie es nicht, ist die Ziehung verzerrt und die Zahl daneben wertlos.

## Der Ausgang

**Nicht bestanden — ein Mitglied von 3 erfüllt die Bedingung** (erfüllt: Austernseitling; darunter: Judasohr).

Das ist der Ausgang, der vorab ausgeschlossen war: alle oder keine. Eine Klasse, deren Mitglieder sich im Ausland verschieden verhalten, ist keine — sie ist eine Liste von Arten, die in EINER Stichprobe zusammenlagen.

**Nicht gemessen wurde dabei:** Samtfußrübling (Ziehung verzerrt: 0.467). Das ändert am Ausgang nichts — „alle oder keine“ ist schon entschieden, sobald ein Mitglied bei sauberer Kontrolle unter der Latte bleibt.

**Und bei Austernseitling schließt der Vertrauensbereich die Null ein** — die Bedingung war als Punktschätzer registriert und ist damit erfüllt, aber tragen würde diese Zahl allein nicht.

**Was das heißt, und was nicht.** Es heißt zunächst: „bei dieser Stichprobengröße und diesem Abstand nicht nachweisbar“ — nicht „es gibt keinen Unterschied“.

**Und hier wiegt der Fehlschlag schwerer als sonst:** -1.0 °C liegen 14.0 K neben den 13 °C, also gut 3 Glockenbreiten (σ = 5 K). Bei einem so großen Abstand unterscheiden sich die Scores der beiden Fenster drastisch — wenn sich das NICHT in der Trennschärfe niederschlägt, spricht das gegen das Fenster und nicht gegen die Stichprobengröße.

Ausgeliefert wird die Klasse trotzdem nicht: Der Vorbehalt der App gilt dem, was belegt ist, und nicht dem, was plausibel ist.

## Die Richtungsaussage (kein Tor)

Optima, im Hold-out selbst neu angepasst — angepasst und geprüft auf denselben Daten, also kein Beleg. Die Latte dieser Klasse: unter 5 °C.

| Art | Optimum in AT+CH | bestes Band |
|---|--:|---|
| Austernseitling | 4.5 °C | 4.5 |
| Judasohr | 12.0 °C | 12.0 |
| Samtfußrübling | 4.5 °C | 4.5 |

**Die Richtung hält nur zum Teil:** Austernseitling 4.5 °C, Samtfußrübling 4.5 °C unter den 5 °C, Judasohr 12.0 °C darüber. Für die Klasse als Ganzes ist das keine Stütze — ein gemeinsames Fenster ist gerade das, was hier auseinanderfällt.

## Grenzen

Angepasst wurde ausschließlich an GBIF. Die eigenen Funde und Leergänge der App bleiben draußen — sie sind der unabhängige Prüfstein aus #199.

Auch ein bestätigtes Fenster sagt „die Bedingungen sind günstig“, nicht „hier stehen Pilze“.
