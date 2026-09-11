# Artenfenster: gemessen

Stand: 2026-09-11 · Erzeugt von `tool/ampel_validate.py --fit` · Prüfplan: `docs/pilzampel-artenfenster.md`

Angepasst wird das Temperaturoptimum je Art auf den Jahren bis **2018**, geprüft auf allen späteren. Die Regenhälfte des Modells bleibt unangetastet, ebenso die Breite der Glocke (σ = 5 K). Ausgeliefert rechnet die App weiterhin mit 13 °C für alle Arten.

## Umfang dieses Laufs

Enthalten: Steinpilz, Pfifferling, Birkenpilz, Fichtenreizker, Herbsttrompete, Hallimasch, Stockschwämmchen.

**Das Tageskontingent von Open-Meteo reicht nicht für alle neun Arten auf einmal** (bemessen nach Orten × Tagen, nicht nach Anfragen). Ein Lauf holt gut eine halbe Art; der Cache trägt das Geholte über Tage. Fehlt eine Art hier, ist sie nicht ausgefallen, sondern noch nicht geholt — ein Ergebnis auf lückenhaften Jahren bricht das Werkzeug ab, statt es zu berichten.

## Die Vorhersage, die vor der Messung feststand

> Das angepasste Optimum des **Austernseitlings** liegt unter 9 °C, und seine gepaarte AUC auf den Prüfjahren erreicht mindestens 0.55.

**Noch nicht entschieden** — Austernseitling war in diesem Lauf nicht enthalten. Ohne die vorab benannte Art ist alles Folgende **Beifund, kein Beleg**: Bei sieben Arten und einem freien Parameter ist eine Verbesserung durch Zufall zu erwarten, und welche davon man hinterher interessant findet, ist keine Vorhersage.

## Alle Arten

„Band“ ist die Spanne der gleich guten Optima. Ist es breit, ist der Gipfel eine Nachkommastelle ohne Deckung. Der Vertrauensbereich der Differenz ist über **Jahre** gezogen, nicht über Paare.

| Art | Paare Anpassung | Paare Prüfung | Optimum | Band | AUC Prüfung mit 13 °C | AUC Prüfung angepasst | Differenz (95 %) |
|---|--:|--:|--:|---|--:|--:|---|
| Steinpilz | 936 | 1060 | 14.0 °C | 14.0–14.0 | 0.742 | 0.738 | -0.004 [-0.028, +0.023] |
| Pfifferling | 722 | 614 | 19.2 °C | 19.0–19.5 | 0.590 | 0.656 | +0.067 [+0.012, +0.113] |
| Birkenpilz | 633 | 569 | 14.5 °C | 14.5–14.5 | 0.736 | 0.738 | +0.002 [-0.032, +0.043] |
| Fichtenreizker | 395 | 377 | 12.5 °C | 12.5–12.5 | 0.719 | 0.721 | +0.003 [-0.006, +0.011] |
| Herbsttrompete | 150 | 146 | 13.2 °C | 13.0–13.5 | 0.685 | 0.699 | +0.014 [+0.000, +0.024] |
| Hallimasch | 927 | 1039 | 10.8 °C | 10.5–11.0 | 0.743 | 0.769 | +0.026 [-0.005, +0.058] |
| Stockschwämmchen | 588 | 694 | 12.5 °C | 12.5–12.5 | 0.715 | 0.712 | -0.003 [-0.025, +0.016] |

## Was die Mykorrhiza-Arten sagen

Ihre Optima liegen zwischen 12.5 und 19.2 °C (Spanne 6.8 K); 4 von 5 liegen innerhalb ±1,5 K um die ausgelieferten 13 °C.

**Ein eigenes Fenster trägt bei: Pfifferling (19.2 °C, +0.067).** Dort schließt der Vertrauensbereich der Differenz die Null aus, und gemessen wurde auf Jahren, an denen nicht angepasst wurde.

Das ist ein Fund, keine Entscheidung. Welche von 7 Arten hinterher heraussticht, ist keine Vorhersage — eine davon tut es auch bei reinem Zufall. Ein eigenes Fenster verdient deshalb eine eigene, vorab formulierte Prüfung, nicht den Einbau.


## Grenzen

Angepasst wurde ausschließlich an GBIF. Die eigenen Funde und Leergänge der App bleiben draußen — sie sind der unabhängige Prüfstein aus #199, und wer sie einrechnet, kann mit ihnen nicht mehr prüfen.

Auch ein artenspezifisches Fenster sagt „die Bedingungen sind günstig“, nicht „hier stehen Pilze“.
