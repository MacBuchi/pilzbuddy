# H1 geprüft: schmalere Temperaturglocke (3,25 K statt 5 K)

Stand: 2026-09-18 · Erzeugt von `tool/ampel_diagnose.py --h1` · **Registrierung (vor dem Lauf geschrieben): `docs/pilzampel-h1-registrierung.md`**

Messbasis `pinned`, Entdoppeln an, Design B, σ = 5.0 gegen σ = 3.25. Beide Breiten laufen auf **denselben Funden** — gezogen wird einmal, bewertet zweimal.


## Das Urteil

| Klasse | Mitglieder | Ausgang |
|---|---|---|
| `herbst` | Steinpilz (nicht bestanden), Maronenröhrling (nicht bestanden), Birkenpilz (nicht bestanden), Fichtenreizker (nicht bestanden), Herbsttrompete (zu dünn) | **nicht bestanden** |
| `sommer` | Pfifferling (nicht bestanden) | **nicht bestanden** |

**σ bleibt 5,0.** Die Breite ist EINE Konstante für beide ausgelieferten Klassen; geändert wird sie nur, wenn beide bestehen (Registrierung, Abschnitt 1). Ein σ je Klasse wäre ein neuer Freiheitsgrad und bräuchte eine eigene Registrierung.

**An der ausgelieferten Ampel ist nichts geändert.**

### Was das heißt

**Die externe Zahl trägt hier nicht.** Keine einzige Art erreicht die
Latte; bei den sechs ausgelieferten liegt Δ zwischen −0,011 und +0,010,
also im Rauschen. Kein Vertrauensbereich der Herbstarten schließt die
Null aus, und bei keiner sind mehr als fünf von sieben Fundjahren
besser.

Das ist ein **Ergebnis und kein Fehlschlag des Verfahrens.** Die 3,25 K
stammen aus zehn Jahren täglicher Erfassung an *einem* Standort, bei
*einer* Art. Dass eine dort gemessene Breite auf 2 000 verstreute
GBIF-Meldungen in ganz Deutschland nicht überträgt, ist die
naheliegendste aller Erklärungen — die Streuung zwischen Orten,
Beständen und Meldern ist hier die größere Größe.

**Die gesetzten 5 K bleiben also gesetzt.** Sie sind nach diesem Lauf
nicht besser begründet als vorher; sie sind nur nicht geschlagen worden.
Das ist ein Unterschied, der in `docs/pilzampel-konzept.md` stehen
bleibt.

**Und es gibt einen Grund, warum ausgerechnet DIESE Prüfung nichts
finden konnte.** Das bedingte Logit aus N5
(`docs/pilzampel-logit.md`, getrennt gerechnet und kein Prüfwert) passt
Breite und Mitte gemeinsam an. Die Breiten der Herbstarten landen dort
zwischen 2,26 und 3,62 K, also näher an den geprüften 3,25 als an den
ausgelieferten 5,0 — ihre **Optima** aber bei 9,20 bis 12,52 °C, alle
unter den festgehaltenen 13,0. H1 hat eine von zwei gekoppelten Größen
allein bewegt. Eine schmalere Glocke um einen Gipfel, der selbst ein bis
vier Kelvin danebensteht, trifft weniger als eine breite.

Mit cluster-robusten Fehlern ist keine dieser Verschiebungen für sich
belastbar — belastbar ist nur, dass **alle zehn Zahlen in dieselbe
Richtung zeigen.** Das ist ein Hinweis auf die nächste Frage und kein
Befund.

Das entwertet dieses Ergebnis nicht: Geprüft war genau das, was
registriert war, und die Antwort darauf lautet nein. Es sagt, welche
Frage die nächste wäre — und dass sie ein angepasstes Optimum bräuchte,
also die Größe, die Phase 0.4 als instabil ausgewiesen hat.


## Die Bedingung, Punkt für Punkt

Latte: Δ ≥ +0.020 · Band ohne die Null (p < 0.025) · ≥ 70% der Fundjahre besser · Placebo innerhalb 2 SE · Ausland widerspricht nicht.

| Art | Klasse | Δ auf P1 | 95 % | p | Jahre besser | Placebo neu | Ausland | **Ausgang** |
|---|---|--:|---|--:|--:|--:|:-:|---|
| Steinpilz | herbst | -0.008 | [-0.024, +0.007] | 0.8410 | 2/7 | 0.507 | ✓ | **nicht bestanden** |
| Maronenröhrling | herbst | -0.003 | [-0.031, +0.023] | 0.5518 | 3/7 | 0.506 | ✓ | **nicht bestanden** |
| Birkenpilz | herbst | -0.006 | [-0.019, +0.006] | 0.8234 | 3/7 | 0.471 | ✓ | **nicht bestanden** |
| Fichtenreizker | herbst | +0.007 | [-0.003, +0.015] | 0.0860 | 5/7 | 0.503 | ✓ | **nicht bestanden** |
| Herbsttrompete | herbst | +0.010 | [-0.026, +0.056] | 0.3154 | 2/5 | 0.490 | — | **zu dünn** |
| Pfifferling | sommer | -0.011 | [-0.027, -0.000] | 0.9800 | 2/7 | 0.497 | ✗ | **nicht bestanden** |
| Hallimasch | — | +0.000 | [-0.027, +0.027] | 0.4984 | 4/7 | 0.492 | ✓ | **nicht bestanden** |
| Stockschwämmchen | — | -0.006 | [-0.021, +0.009] | 0.7808 | 2/7 | 0.483 | ✓ | **nicht bestanden** |
| Austernseitling | — | -0.016 | [-0.042, +0.010] | 0.8790 | 2/7 | 0.493 | ✓ | **nicht bestanden** |
| Judasohr | — | -0.037 | [-0.053, -0.015] | 0.9985 | 1/7 | 0.483 | ✓ | **nicht bestanden** |
| Samtfußrübling | — | -0.027 | [-0.053, -0.002] | 0.9840 | 3/7 | 0.464 | ✓ | **nicht bestanden** |

Arten ohne Klasse laufen **nachrichtlich** mit und entscheiden nichts: Ihre Klassen sind nicht ausgeliefert, und nach Phase 1.5 steht für alle fünf „keine Aussage“.

### Drei Stellen, an denen die Registrierung gegriffen hat

**Die Herbsttrompete steht auf „zu dünn", nicht auf „nicht
bestanden".** 145 Funde auf P1, fünf unter der Grenze. Ihr Δ von +0,010
ist der zweitbeste der Tabelle, und ohne die vorab gesetzte Grenze wäre
die Versuchung groß gewesen, daraus etwas zu machen — ihr
Vertrauensbereich reicht von −0,026 bis +0,056 und sagt nichts. Auf das
Klassenurteil hat es nicht gewirkt: Die anderen vier Herbstarten sind
gemessen durchgefallen.

**Beim Pfifferling hat der Reisetest zugeschlagen.** Sein Band auf P1
liegt mit [−0,027, −0,000] schon im negativen Bereich; auf AT+CH
(1876 Funde, mehr als in Deutschland) sind es −0,010 mit einem Band, das
die Null von unten ausschließt. Die schmalere Glocke ist dort also nicht
wirkungslos, sondern **schlechter**. Er wäre auch ohne den Reisetest
durchgefallen — aber die Regel war vorher da, und sie hat gezeigt, wofür
sie gedacht ist.

**Die Gegenprobe mit 8 K bestätigt, dass das Verfahren die Breite
misst.** Bei den sechs ausgelieferten Arten fällt auch die breitere
Glocke durch; keine Art besteht in beide Richtungen. Hätte sie es, wäre
nicht die Breite gemessen worden, sondern irgendein Nebeneffekt des
Umrechnens.


## Die drei Panels

P1 = DE ab 2019 (entscheidend) · P2 = AT + CH, alle Jahre (Reisetest, bindend als Ausschluss) · P3 = DE bis 2018 (nachrichtlich — dort wurde das Sommer-Optimum angepasst).

| Art | P1 Δ | P1 n | P2 Δ | P2 n | P3 Δ | P3 n |
|---|--:|--:|--:|--:|--:|--:|
| Steinpilz | -0.008 | 1041 | +0.001 | 1686 | +0.001 | 951 |
| Maronenröhrling | -0.003 | 1109 | +0.002 | 1474 | -0.004 | 886 |
| Birkenpilz | -0.006 | 564 | -0.005 | 560 | -0.000 | 621 |
| Fichtenreizker | +0.007 | 378 | +0.001 | 1622 | -0.003 | 397 |
| Herbsttrompete | +0.010 | 145 | +0.007 | 426 | +0.000 | 147 |
| Pfifferling | -0.011 | 605 | -0.010 | 1876 | -0.025 | 716 |
| Hallimasch | +0.000 | 1038 | +0.011 | 1094 | +0.003 | 941 |
| Stockschwämmchen | -0.006 | 692 | +0.002 | 530 | +0.000 | 601 |
| Austernseitling | -0.016 | 818 | -0.004 | 244 | +0.014 | 451 |
| Judasohr | -0.037 | 835 | -0.005 | 1108 | -0.002 | 783 |
| Samtfußrübling | -0.027 | 318 | +0.003 | 316 | -0.005 | 494 |

## Gegenprobe: eine BREITERE Glocke

Dieselbe Rechnung mit σ = 8.0 K auf P1. Ergibt auch sie einen Gewinn über der Latte, misst das Verfahren nicht die Breite, sondern irgendetwas anderes. Diese Spalte entscheidet nichts.

| Art | Δ bei 3,25 K | Δ bei 8,0 K | beide über der Latte? |
|---|--:|--:|:-:|
| Steinpilz | -0.008 | -0.005 | nein |
| Maronenröhrling | -0.003 | -0.020 | nein |
| Birkenpilz | -0.006 | -0.007 | nein |
| Fichtenreizker | +0.007 | -0.015 | nein |
| Herbsttrompete | +0.010 | +0.001 | nein |
| Pfifferling | -0.011 | +0.008 | nein |
| Hallimasch | +0.000 | -0.009 | nein |
| Stockschwämmchen | -0.006 | -0.006 | nein |
| Austernseitling | -0.016 | +0.029 | nein |
| Judasohr | -0.037 | +0.066 | nein |
| Samtfußrübling | -0.027 | +0.021 | nein |

### Der Nebenbefund, und was er NICHT ist

Bei den sechs ausgelieferten Arten passiert in beide Richtungen nichts.
Bei den drei Kaltarten dagegen steht ein deutliches Muster: schmaler ist
klar schlechter (−0,016 / −0,037 / −0,027), breiter ist klar besser
(+0,029 / **+0,066** / +0,021). Beim Judasohr ist der Gewinn der
größte Einzelwert der ganzen Tabelle.

**Das ist keine Aussage über die Breite, sondern über die Mitte.** Ihre
Fundtage liegen im Mittel bei 4,5 bis 8,0 °C, das Fenster ihrer Klasse
bei **−2,5 °C** — also 7 bis 10,5 K daneben. Eine Glocke, deren Gipfel
zehn Kelvin neben den Daten liegt, verliert mit jeder Verschmälerung
Rang-Information; eine breitere gibt sie zurück. Die Spalte „tote
Funde" zeigt genau das: beim Austernseitling springt sie von 7,6 % auf
**29,2 %**, beim Judasohr von 4,3 % auf 20,2 %.

Daraus folgt **nichts**, und zwar aus drei Gründen. Diese Klassen sind
nicht ausgeliefert. Nach Phase 1.5 steht für alle fünf Arten „keine
Aussage" — ein besser sitzendes Fenster über einem Grundsignal von 0,49
ist ein besser sitzendes Nichts. Und ein Optimum nachzuziehen, weil
eine Nebentabelle es nahelegt, ist genau der Griff, gegen den der ganze
Aufbau antritt: Das wäre eine Anpassung nach dem Blick auf die Zahlen,
und sie bräuchte eine eigene Registrierung.

Aufgeschrieben wird es trotzdem — als Hinweis darauf, wo eine spätere
Frage ansetzen könnte, nicht als Befund.

## Diagnosen (entscheiden nichts)

Vorab festgelegt, damit sie hinterher nicht als Erklärung erfunden wirken.

| Art | T̄₂₀ am Fundtag | Optimum | Abstand | B nur Temperatur | B nur Regen | tote Funde alt → neu | exakt gleich alt → neu |
|---|--:|--:|--:|--:|--:|--:|--:|
| Steinpilz | 13.3 | 13.0 | 0.3 | 0.582 | 0.646 | 0.0% → 0.0% | 0.0% → 0.0% |
| Maronenröhrling | 12.7 | 13.0 | 0.3 | 0.577 | 0.592 | 0.0% → 0.0% | 0.0% → 0.0% |
| Birkenpilz | 14.2 | 13.0 | 1.2 | 0.582 | 0.596 | 0.0% → 0.0% | 0.0% → 0.0% |
| Fichtenreizker | 12.3 | 13.0 | 0.7 | 0.588 | 0.593 | 0.0% → 0.0% | 0.0% → 0.0% |
| Herbsttrompete | 13.7 | 13.0 | 0.7 | 0.563 | 0.587 | 0.0% → 0.0% | 0.0% → 0.0% |
| Pfifferling | 15.4 | 17.5 | 2.1 | 0.557 | 0.630 | 0.0% → 2.6% | 0.0% → 0.0% |
| Hallimasch | 11.4 | 13.0 | 1.6 | 0.559 | 0.593 | 0.0% → 0.0% | 0.0% → 0.0% |
| Stockschwämmchen | 11.9 | 13.0 | 1.1 | 0.557 | 0.611 | 0.0% → 0.0% | 0.0% → 0.0% |
| Austernseitling | 8.0 | -2.5 | 10.5 | 0.470 | 0.553 | 7.6% → 29.2% | 0.0% → 0.0% |
| Judasohr | 7.2 | -2.5 | 9.7 | 0.464 | 0.629 | 4.3% → 20.2% | 0.0% → 0.0% |
| Samtfußrübling | 4.5 | -2.5 | 7.0 | 0.459 | 0.537 | 0.3% → 6.0% | 0.0% → 0.0% |

**Die vorletzte Spalte ist die wichtigste dieser Tabelle.** Sie zählt Funde, bei denen jeder Vergleich beidseitig unter 10⁻⁶ liegt — dort rechnet das Modell noch und sagt nichts mehr. Steigt der Anteil deutlich, hat eine schmalere Glocke nicht besser getrennt, sondern aufgehört zu trennen; dann heißt ein Δ nahe null „die Messung kann die Frage hier nicht beantworten“ und nicht „kein Effekt“.

### Die Diagnose hat ihren Zweck erfüllt

**Bei den sechs ausgelieferten Arten bleibt die Spalte „tote Funde" auf
0,0 %** — beim Pfifferling steigt sie von 0 auf 2,6 %. Das Δ nahe null
heißt dort also wirklich „kein Effekt" und nicht „das Modell hat
aufgehört zu unterscheiden". Ohne diese vorab festgelegte Spalte wären
beide Lesarten offen geblieben, und die bequemere hätte gewonnen.

Bei den drei Kaltarten ist es umgekehrt, und auch das steht in der
Spalte: Dort ist das negative Δ zu einem guten Teil Abtötung und nicht
Verschlechterung. Der Unterschied ist nicht akademisch — im ersten Fall
sagt die Messung etwas, im zweiten kann sie es nicht.

Die letzte Spalte zählt **exakte** Gleichstände und steht nur da, damit sichtbar bleibt, dass sie nichts trägt: `exp(−209)` ist 1e−91 und nicht null, zwei tote Tage gelten dem Rechner also als verschieden. Beim Schreiben der Registrierung war das nicht klar — der Selbsttest hat es gezeigt, bevor eine einzige Zahl gemessen war.


## Grenzen

Design B misst gegen dasselbe Datum anderer Jahre am selben Ort, und „üblich“ schließt die guten Jahre ein — das dämpft beide Breiten gleich und ist für eine Differenz unkritisch, für die absoluten Werte nicht.

**Und ein Nichtbestehen ist schwächer als ein Bestehen.** Δ ≈ 0 heißt
„diese Daten sehen keinen Unterschied", nicht „es gibt keinen". Bei
rund 1 000 Funden je Art und einem Jahres-Standardfehler um 0,008 wäre
ein Effekt ab etwa +0,022 mit 80 % Wahrscheinlichkeit aufgefallen — das
ist ungefähr die Latte selbst. Ein Vorteil von +0,01 könnte also
bestehen und hier unsichtbar bleiben. Er wäre nur zu klein, um eine
ausgelieferte Konstante dafür anzufassen.

Und geprüft ist eine **Form**, keine Biologie: Dass eine Glocke mit σ = 3,25 besser trennt, hieße nicht, dass Steinpilze bei 9,75 °C auf ein Drittel fallen. Es hieße, dass die Rangfolge der Tage damit besser stimmt.
