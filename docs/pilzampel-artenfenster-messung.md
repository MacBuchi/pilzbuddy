# Artenfenster: gemessen

Stand: 2026-09-12 · Erzeugt von `tool/ampel_validate.py --fit` · Prüfplan: `docs/pilzampel-artenfenster.md`

Angepasst wird das Temperaturoptimum je Art auf den Jahren bis **2018**, geprüft auf allen späteren. Die Regenhälfte des Modells bleibt unangetastet, ebenso die Breite der Glocke (σ = 5 K). Ausgeliefert rechnet die App weiterhin mit 13 °C für alle Arten.

## Umfang dieses Laufs

Enthalten: Steinpilz, Maronenröhrling, Pfifferling, Birkenpilz, Fichtenreizker, Herbsttrompete, Hallimasch, Stockschwämmchen, Austernseitling.

**Das Tageskontingent von Open-Meteo reicht nicht für alle neun Arten auf einmal** (bemessen nach Orten × Tagen, nicht nach Anfragen). Ein Lauf holt gut eine halbe Art; der Cache trägt das Geholte über Tage. Fehlt eine Art hier, ist sie nicht ausgefallen, sondern noch nicht geholt — ein Ergebnis auf lückenhaften Jahren bricht das Werkzeug ab, statt es zu berichten.

## Die Vorhersage, die vor der Messung feststand

> Das angepasste Optimum des **Austernseitlings** liegt unter 9 °C, und seine gepaarte AUC auf den Prüfjahren erreicht mindestens 0.55.

**Ergebnis: eingetroffen.** Optimum -3.2 °C (vorhergesagt: < 9), AUC auf Prüfjahren 0.655 (vorhergesagt: ≥ 0.55).

Damit ist belegt, was die Arten-Kontrolle vom 2026-08-13 offenlassen musste: Arten haben verschiedene Fenster. Die Kontrolle war an ihrer AUSWAHL gescheitert, nicht am Modell.

## Alle Arten

„Band“ ist die Spanne der gleich guten Optima. Ist es breit, ist der Gipfel eine Nachkommastelle ohne Deckung. Der Vertrauensbereich der Differenz ist über **Jahre** gezogen, nicht über Paare.

| Art | Paare Anpassung | Paare Prüfung | Optimum | Band | AUC Prüfung mit 13 °C | AUC Prüfung angepasst | Differenz (95 %) |
|---|--:|--:|--:|---|--:|--:|---|
| Steinpilz | 936 | 1054 | 13.0 °C | 13.0 | 0.790 | 0.790 | +0.000 [+0.000, +0.000] |
| Maronenröhrling | 856 | 1118 | 13.0 °C | 13.0 | 0.747 | 0.747 | +0.000 [+0.000, +0.000] |
| Pfifferling | 722 | 610 | 17.5 °C | 17.5 | 0.611 | 0.677 | +0.066 [+0.021, +0.113] |
| Birkenpilz | 633 | 570 | 14.5 °C | 14.5 | 0.777 | 0.765 | -0.012 [-0.035, +0.015] |
| Fichtenreizker | 392 | 373 | 12.0 °C | 12.0 | 0.737 | 0.753 | +0.016 [-0.009, +0.040] |
| Herbsttrompete | 150 | 144 | 13.0 °C | 13.0 | 0.688 | 0.688 | +0.000 [+0.000, +0.000] |
| Hallimasch | 924 | 1029 | 11.0 °C | 11.0 | 0.788 | 0.836 | +0.048 [+0.024, +0.069] |
| Stockschwämmchen | 591 | 686 | 12.2 °C | 12.0 bis 12.5 | 0.777 | 0.776 | -0.001 [-0.025, +0.018] |
| Austernseitling | 355 | 632 | -3.2 °C | -3.5 bis -3.0 | 0.481 | 0.655 | +0.174 [+0.108, +0.248] |

## Was die Mykorrhiza-Arten sagen

Ihre Optima liegen zwischen 12.0 und 17.5 °C (Spanne 5.5 K); 5 von 6 liegen innerhalb ±1,5 K um die ausgelieferten 13 °C.

**Ein eigenes Fenster trägt bei: Pfifferling (17.5 °C, +0.066), Hallimasch (11.0 °C, +0.048), Austernseitling (-3.2 °C, +0.174).** Dort schließt der Vertrauensbereich der Differenz die Null aus, und gemessen wurde auf Jahren, an denen nicht angepasst wurde.

Das ist ein Fund, keine Entscheidung. Welche von 9 Arten hinterher heraussticht, ist keine Vorhersage — eine davon tut es auch bei reinem Zufall. Ein eigenes Fenster verdient deshalb eine eigene, vorab formulierte Prüfung, nicht den Einbau.


## Grenzen

Angepasst wurde ausschließlich an GBIF. Die eigenen Funde und Leergänge der App bleiben draußen — sie sind der unabhängige Prüfstein aus #199, und wer sie einrechnet, kann mit ihnen nicht mehr prüfen.

Auch ein artenspezifisches Fenster sagt „die Bedingungen sind günstig“, nicht „hier stehen Pilze“.
