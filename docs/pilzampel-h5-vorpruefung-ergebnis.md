# Vorprüfung zu H5: trägt die Glocke etwas bei? — die Messung

Stand: 2026-09-19 · Erzeugt von `tool/ampel_diagnose.py --zerlegung` · **Registrierung (vor dem Lauf geschrieben): `docs/pilzampel-h5-vorpruefung.md`**

Gerechnet auf **P3, DE ≤ 2018** — den Anpassjahren. Das ist keine Prüfachse; dieser Lauf verbraucht nichts (`docs/pilzampel-pruefachsen.md`).

Messbasis `pinned`, Entdoppeln an, Design B, dieselbe Ziehung wie Phase 1.5.

> **Achtung beim Wiederholen:** Dieser Lauf überschreibt die Datei vollständig. Einordnende Abschnitte (`### …`) sind von Hand geschrieben und danach weg.


## Das Ergebnis

### H5 wird NICHT registriert

| Bedingung | Schwelle | erreicht | |
|---|---|--:|:-:|
| 1 — die Zerlegung reist | B(Regen) > B(Temp) bei ≥ 5 von 6 | 1 von 6 | ✗ |
| 2 — die Glocke trägt nichts bei | B(voll) − B(Regen) < 0.020 bei ≥ 5 von 6 | 1 von 6 | ✗ |
| 3 — der Referenzabstand hält | Band ohne Null bei ≥ 5 von 6 **und** Median nicht mehr als 0.020 darunter | 4 von 6, Median +0.045 gegen +0.065 | ✗ |

**Kein Zwischenergebnis wird nachverhandelt** — die Schwellen standen vor dem Lauf fest.

### Was passiert ist: der P1-Befund reist nicht

**Auf P1 galt bei 6 von 6 ausgelieferten Arten „Regen allein schlägt
Temperatur allein" — auf P3 bei 1 von 6.** Das Vorzeichen dreht sich bei
fünf der sechs um.

| Art | nur Temperatur | | nur Regen | |
|---|--:|--:|--:|--:|
| | **P3** (2006–18) | P1 (2019–25) | **P3** | P1 |
| Steinpilz | **0.625** | 0.582 | **0.609** | 0.646 |
| Maronenröhrling | **0.610** | 0.577 | **0.601** | 0.592 |
| Birkenpilz | **0.617** | 0.582 | **0.604** | 0.596 |
| Fichtenreizker | **0.623** | 0.588 | **0.591** | 0.593 |
| Herbsttrompete | **0.692** | 0.563 | **0.658** | 0.587 |
| Pfifferling | **0.512** | 0.557 | **0.632** | 0.630 |

Die Regenspalte steht in beiden Zeitscheiben ungefähr gleich (0,59–0,66
gegen 0,59–0,65). **Was sich bewegt, ist die Temperatur:** In den
Anpassjahren trennt die Glocke mit 0,61 bis 0,69, in den Prüfjahren nur
noch mit 0,56 bis 0,59.

Damit ist die registrierte Folge eingetreten: *„Zeigt P3 es nicht, wird
H5 nicht registriert — dann war der P1-Befund vermutlich Rauschen oder
jahresspezifisch, und das ist das Ergebnis."* Jahresspezifisch trifft es
besser als Rauschen; die Richtung ist bei fünf von sechs Arten dieselbe.

**Der Pfifferling ist die Ausnahme, und sie passt ins Bild.** Er ist die
einzige Art, bei der der Regen auf beiden Scheiben klar führt — auf P3
mit 0,632 gegen 0,512. Genau das ist zu erwarten, wenn seine Glocke am
falschen Ort steht: Das bedingte Logit setzt sein Optimum auf 13,16 ±
0,94 statt der ausgelieferten 17,5 (`docs/pilzampel-logit.md`). Eine
Glocke, die fünf Kelvin danebenliegt, trägt wenig, und dann trägt der
Regen allein.

### Bedingung 3 ist an der Bandzahl gescheitert, nicht am Median

Das gehört genau hingeschrieben, damit es später niemand umdeutet. Der
**Median hat gehalten** — +0,045 gegen +0,065, also exakt die erlaubten
0,020 Verlust. Gefallen ist die erste Hälfte: Nur **4 von 6** Bändern
schließen unter dem reinen Regen-Score die Null aus; Birkenpilz (p =
0,033) und Herbsttrompete (p = 0,062) reichen nicht.

**Das heißt ausdrücklich nicht, dass das Regensignal reiner Suchaufwand
wäre.** Vier von sechs Arten halten ihren Abstand zur Referenz auch ohne
jede Temperatur, und der Median verliert nur ein Drittel. Die Referenz
steigt also mit, aber nicht vollständig. H5 scheitert nicht daran — H5
scheitert an den Bedingungen 1 und 2, und zwar deutlich: 1 von 6 statt
5 von 6, beide Male.

### Ein Nebenbefund, der eine eigene Frage wäre

Dass die Glocke in den Prüfjahren schwächer trennt als in den
Anpassjahren, ist eine Beobachtung über die **Zeit** und nicht über die
Formel. Sie passt zu zweierlei, das schon dasteht: dem Richtungs-Split
aus N4 (spätere Kontrolljahre sind leichter zu schlagen) und dem
Altern der Schwellen (dieselbe 0,5 wurde vor 2019 an rund 30 % der
Vergleichstage überschritten, seither an rund 20 %).

**Sie ist hier nicht prüfbar.** Der Vergleich der beiden Zeitscheiben
benutzt P1, also eine Prüfachse — eine Hypothese daraus entstünde
wieder dort, wo sie geprüft werden wollte. Genau der Fehler, den diese
Vorprüfung abfangen sollte, nur eine Ebene höher.


## Die Zerlegung je Art

Dieselben Paare, drei Bewerter. „Nur Temperatur“ ist von der Glockenbreite unabhängig, weil das Maß rangbasiert ist.

| Art | ausgeliefert | Funde | B voll | B nur Regen | B nur Temperatur | voll − Regen |
|---|:-:|--:|--:|--:|--:|--:|
| Steinpilz | **ja** | 951 | 0.647 | 0.609 | 0.625 | +0.038 |
| Maronenröhrling | **ja** | 886 | 0.634 | 0.601 | 0.610 | +0.033 |
| Birkenpilz | **ja** | 621 | 0.627 | 0.604 | 0.617 | +0.023 |
| Fichtenreizker | **ja** | 397 | 0.642 | 0.591 | 0.623 | +0.052 |
| Herbsttrompete | **ja** | 147 | 0.695 | 0.658 | 0.692 | +0.037 |
| Pfifferling | **ja** | 716 | 0.629 | 0.632 | 0.512 | -0.003 |
| Hallimasch | nein | 941 | 0.490 | 0.496 | 0.524 | -0.007 |
| Stockschwämmchen | nein | 601 | 0.559 | 0.559 | 0.555 | -0.001 |
| Austernseitling | nein | 451 | 0.489 | 0.460 | 0.508 | +0.029 |
| Judasohr | nein | 783 | 0.539 | 0.545 | 0.529 | -0.006 |
| Samtfußrübling | nein | 494 | 0.506 | 0.508 | 0.500 | -0.002 |

## Die Referenz, in denselben drei Bewertern

Meldungen anderer Pilze aus denselben ~10-km-Zellen und mit der Monatsverteilung der Zielart. **Sie ist kein Abzugsposten** (A6): „irgendeine Pilzmeldung“ ist überwiegend *andere Pilze*, die auf dasselbe Wetter reagieren.

| Art | Referenzfunde | Zellen | Ref voll | Ref nur Regen | Ref nur Temperatur |
|---|--:|--:|--:|--:|--:|
| Steinpilz | 819 | 639 | 0.584 | 0.570 | 0.573 |
| Maronenröhrling | 816 | 687 | 0.567 | 0.554 | 0.567 |
| Birkenpilz | 526 | 468 | 0.567 | 0.559 | 0.564 |
| Fichtenreizker | 354 | 321 | 0.555 | 0.550 | 0.556 |
| Herbsttrompete | 151 | 144 | 0.579 | 0.574 | 0.566 |
| Pfifferling | 628 | 404 | 0.575 | 0.588 | 0.501 |
| Hallimasch | 695 | 720 | 0.510 | 0.496 | 0.538 |
| Stockschwämmchen | 540 | 504 | 0.558 | 0.554 | 0.542 |
| Austernseitling | 450 | 599 | 0.488 | 0.495 | 0.512 |
| Judasohr | 580 | 653 | 0.506 | 0.512 | 0.505 |
| Samtfußrübling | 322 | 399 | 0.471 | 0.492 | 0.470 |

## Die Entscheidung: der Abstand zur Referenz je Bewerter

**Regen wirkt auch auf den Sammler.** Design B nimmt Ort und Jahreszeit heraus, nicht die Wetterabhängigkeit des Suchens. Steigt die Referenz mit einem Regen-Score genauso wie die Art, ist nichts gewonnen — nur der Abstand zählt.

| Art | Δ voll | 95 % | Δ nur Regen | 95 % | p | Δ nur Temperatur |
|---|--:|---|--:|---|--:|--:|
| Steinpilz | +0.063 | [+0.022, +0.112] | +0.039 | [+0.011, +0.075] | 0.0038 | +0.052 |
| Maronenröhrling | +0.067 | [+0.035, +0.108] | +0.047 | [+0.013, +0.087] | 0.0022 | +0.042 |
| Birkenpilz | +0.060 | [+0.009, +0.111] | +0.046 | [-0.003, +0.097] | 0.0333 | +0.054 |
| Fichtenreizker | +0.088 | [+0.040, +0.128] | +0.041 | [+0.009, +0.068] | 0.0040 | +0.068 |
| Herbsttrompete | +0.116 | [+0.011, +0.244] | +0.084 | [-0.019, +0.232] | 0.0622 | +0.126 |
| Pfifferling | +0.054 | [+0.015, +0.099] | +0.044 | [+0.006, +0.100] | 0.0078 | +0.010 |
| Hallimasch | -0.020 | [-0.058, +0.025] | +0.000 | [-0.041, +0.047] | 0.4377 | -0.014 |
| Stockschwämmchen | +0.001 | [-0.034, +0.045] | +0.005 | [-0.034, +0.050] | 0.4083 | +0.013 |
| Austernseitling | +0.001 | [-0.029, +0.034] | -0.034 | [-0.073, +0.019] | 0.9091 | -0.003 |
| Judasohr | +0.033 | [-0.001, +0.072] | +0.033 | [-0.005, +0.069] | 0.0408 | +0.024 |
| Samtfußrübling | +0.035 | [-0.005, +0.076] | +0.016 | [-0.040, +0.064] | 0.2662 | +0.030 |

## Grenzen

**P3 sind die Anpassjahre. Jede Zahl hier ist eine Diagnose.** Auch ein glänzendes Ergebnis belegt H5 nicht — es erlaubt nur, H5 zu registrieren und dann auf AT+CH zu prüfen.

Und die Referenz trennt Suchaufwand und allgemeine Pilz-Wetterreaktion nicht (A6); sie begrenzt beide zusammen nach oben.

**Und diese Seite sagt nichts darüber, ob die Glocke gebraucht wird.**
Sie sagt, dass die Beobachtung, aus der diese Frage entstand, in den
Anpassjahren nicht wiederkehrt. Ob eine Ampel ohne Temperatur besser
wäre, ist damit offen — nur ist der Weg dorthin nicht dieser Befund.
