# Zwei Kontrolltag-Designs nebeneinander

Stand: 2026-09-18 · Erzeugt von `tool/ampel_diagnose.py --designs` · Auftrag: `docs/pilzampel-auftrag-2.md`, Abschnitt 3

Gerechnet auf **Deutschland und den Jahren bis 2018**. Kein Hold-out-Kontakt. Beide Designs laufen auf **derselben Fundliste** — sonst wäre ihr Unterschied teils die Stichprobe statt das Design.

Messbasis: `pinned`, Entdoppeln an.


## Was die beiden Designs fragen

**Design A** vergleicht den Fundtag mit einem Tag 26–45 Tage daneben im selben Jahr. Das kürzt die Saison nur ungefähr heraus.

**Design B** vergleicht ihn mit demselben Datum (±7 Tage) in fünf anderen Jahren am selben Ort. Die Saison kürzt sich vollständig heraus, und übrig bleibt: *War das Wetter dieses Jahr an diesem Datum besser als an diesem Datum üblich?*

**Zwei Gründe, warum B kleinere Zahlen liefern MUSS**, beide vorab festgehalten und keine Fehlschläge:

1. Die Kalenderkomponente fehlt. Was in A die Saison beisteuerte, steht in B nicht mehr zur Verfügung.
2. **„Üblich“ schließt die guten Jahre ein.** Ein Kontrolljahr kann am selben Ort zur selben Woche sehr wohl einen Fund getragen haben — Presence-only trennt „kein Fund“ nicht von „niemand war da“. Solche Jahre auszuschließen wäre genau der Detektionsfehler, den die Daten nicht hergeben. Also bleiben sie drin, und sie dämpfen die Zahl.


## Gemessen

| Art | Gruppe | AUC A | AUC B (k=5) | B (k=1) | Differenz B−A | Placebo B | Funde A / B |
|---|---|--:|--:|--:|--:|--:|--:|
| Steinpilz | herbst | 0.737 | **0.647** | 0.637 | -0.090 | 0.498 | 951 / 951 |
| Maronenröhrling | herbst | 0.718 | **0.634** | 0.635 | -0.084 | 0.498 | 876 / 886 |
| Birkenpilz | herbst | 0.739 | **0.627** | 0.643 | -0.112 | 0.492 | 621 / 621 |
| Fichtenreizker | herbst | 0.756 | **0.642** | 0.635 | -0.113 | 0.513 | 393 / 397 |
| Herbsttrompete ⚠ zu dünn | herbst | 0.735 | **0.695** | 0.769 | -0.039 | 0.488 | 147 / 147 |
| Pfifferling | sommer | 0.643 | **0.629** | 0.623 | -0.013 | 0.512 | 711 / 716 |
| Hallimasch | holz | 0.705 | **0.490** | 0.488 | -0.215 | 0.501 | 921 / 941 |
| Stockschwämmchen | holz | 0.719 | **0.559** | 0.562 | -0.160 | 0.500 | 583 / 601 |
| Austernseitling | kalt | 0.637 | **0.489** | 0.499 | -0.148 | 0.495 | 361 / 451 |
| Judasohr | kalt | 0.572 | **0.539** | 0.545 | -0.033 | 0.492 | 631 / 783 |
| Samtfußrübling | kalt | 0.773 | **0.506** | 0.512 | -0.267 | 0.493 | 322 / 494 |

„Zu dünn“ heißt: unter 150 Funden in Design B. Dort steht die Zahl zur Einordnung, sie trägt aber kein Urteil.

### Was da steht

**Die sechs ausgelieferten Arten überstehen Design B. Die drei, die
fallen, wurden nie ausgeliefert.**

| Art | ausgeliefert | A | B | Abschlag |
|---|---|--:|--:|--:|
| Steinpilz | **ja** | 0.737 | 0.647 | −0.090 |
| Maronenröhrling | **ja** | 0.718 | 0.634 | −0.084 |
| Birkenpilz | **ja** | 0.739 | 0.627 | −0.112 |
| Fichtenreizker | **ja** | 0.756 | 0.642 | −0.114 |
| Herbsttrompete | **ja** | 0.735 | 0.695 | −0.040 |
| Pfifferling | **ja** | 0.643 | **0.629** | **−0.014** |
| Stockschwämmchen | nein | 0.719 | 0.559 | −0.160 |
| Judasohr | nein | 0.572 | 0.539 | −0.033 |
| Samtfußrübling | nein | 0.773 | **0.506** | −0.267 |
| Hallimasch | nein | 0.705 | **0.490** | −0.215 |
| Austernseitling | nein | 0.637 | **0.489** | −0.148 |

Das ist kein Freispruch, aber es ist die wichtigste Zeile dieses
Berichts: Was die App heute behauptet, hält auch dann, wenn man den
Kalender vollständig herausrechnet. Der Preis sind rund 0,09 bei den
Herbstarten — beim Pfifferling fast nichts.

**Und es bestätigt die Entscheidung gegen die Kaltklasse, aus einem
Grund, den bisher niemand kannte.** Der Samtfußrübling hatte den
Hold-out am überzeugendsten bestanden (+0.252 [+0.145, +0.381]). In
Design B bleibt von seiner Trennschärfe nichts: 0.506 bei sauberem
Placebo und einem Jahres-Bootstrap [0.417, 0.607], der die 0,50
einschließt. Seine A-Zahl war fast vollständig Kalender.


## Kontrollen und Vertrauensbereiche

| Art | Spiegel A | Toleranz A | Placebo B | Toleranz B | B über Jahre | B über Melder |
|---|--:|--:|--:|--:|---|---|
| Steinpilz | 0.478 | ±0.032 | 0.498 | ±0.032 | [0.518, 0.713] | [0.625, 0.670] |
| Maronenröhrling | 0.474 | ±0.034 | 0.498 | ±0.034 | [0.500, 0.703] | [0.608, 0.659] |
| Birkenpilz | 0.509 | ±0.040 | 0.492 | ±0.040 | [0.522, 0.700] | [0.602, 0.653] |
| Fichtenreizker | 0.451 | ±0.051 | 0.513 | ±0.050 | [0.499, 0.716] | [0.612, 0.682] |
| Herbsttrompete | 0.395 ⚠ | ±0.082 | 0.488 | ±0.082 | [0.539, 0.757] | [0.652, 0.739] |
| Pfifferling | 0.530 | ±0.038 | 0.512 | ±0.037 | [0.576, 0.661] | [0.594, 0.667] |
| Hallimasch | 0.506 | ±0.033 | 0.501 | ±0.033 | [0.345, 0.632] | [0.464, 0.519] |
| Stockschwämmchen | 0.483 | ±0.042 | 0.500 | ±0.041 | [0.434, 0.647] | [0.516, 0.597] |
| Austernseitling | 0.510 | ±0.064 | 0.495 | ±0.048 | [0.433, 0.553] | [0.463, 0.519] |
| Judasohr | 0.547 ⚠ | ±0.046 | 0.492 | ±0.036 | [0.461, 0.609] | [0.512, 0.564] |
| Samtfußrübling | 0.508 | ±0.090 | 0.493 | ±0.046 | [0.417, 0.607] | [0.463, 0.551] |

Die Toleranz ist **zwei Standardfehler bei der jeweiligen Paarzahl** (A2), nicht mehr die feste ±0,03. Der Bootstrap in Design B zieht über das **Fundjahr** — ein B-Paar gehört zu zwei Jahren, und ohne diese Festlegung änderte dieselbe Spalte ihre Bedeutung zwischen den Designs.


## Richtungs-Split in Design B

Kontrolljahr früher gegen später. Eine Schieflage deckt Klimatrend und Instrumentreste auf — anders als in Design A, wo derselbe Split die Saisonsteigung misst.

| Art | B früher | B später | Differenz |
|---|--:|--:|--:|
| Steinpilz | 0.634 | 0.661 | +0.026 |
| Maronenröhrling | 0.627 | 0.642 | +0.015 |
| Birkenpilz | 0.596 | 0.654 | +0.057 |
| Fichtenreizker | 0.624 | 0.659 | +0.035 |
| Herbsttrompete | 0.660 | 0.715 | +0.055 |
| Pfifferling | 0.602 | 0.659 | +0.057 |
| Hallimasch | 0.506 | 0.476 | -0.030 |
| Stockschwämmchen | 0.547 | 0.570 | +0.023 |
| Austernseitling | 0.466 | 0.508 | +0.042 |
| Judasohr | 0.509 | 0.566 | +0.058 |
| Samtfußrübling | 0.474 | 0.534 | +0.060 |

## Die Ziehung: wo sie ausweichen musste

Bei Funden aus den Randjahren ist eine Seite leer. Dann wird die andere genommen — und es wird gezählt, sonst wäre die Regel wieder eine Hoffnung, nur unsichtbar.

| Art | Seitenwechsel | Funde ohne brauchbares Jahr | fehlende Jahre |
|---|--:|--:|---|
| Steinpilz | 641 | 0 | keine |
| Maronenröhrling | 621 | 0 | keine |
| Birkenpilz | 330 | 0 | keine |
| Fichtenreizker | 244 | 0 | keine |
| Herbsttrompete | 141 | 0 | keine |
| Pfifferling | 423 | 0 | keine |
| Hallimasch | 692 | 0 | keine |
| Stockschwämmchen | 409 | 0 | keine |
| Austernseitling | 625 | 0 | keine |
| Judasohr | 601 | 1 | keine |
| Samtfußrübling | 124 | 0 | keine |

## Die artgematchte Aufwands-Referenz (A3)

Referenzmeldungen aus **denselben ~10-km-Zellen** und mit der **Monatsverteilung der Zielart** als Gewicht, Zielart ausgeschlossen — und in Design B ausgewertet. Die alte Referenz aus Phase 1.3 stammte aus der allgemeinen, herbstlastigen Verteilung und war für eine Winterart keine faire Vergleichsgröße.

**Die Spalte ist kein Abzugsposten** (A6): „irgendeine Pilzmeldung“ ist überwiegend *andere Pilze*, die auf dasselbe Wetter reagieren. Die Referenz begrenzt den Suchaufwand nach oben und die allgemeine Pilz-Wetterreaktion nach unten; dieses Design kann die beiden nicht trennen.

| Art | B der Art | B der Referenz | Differenz zur Referenz | Referenzfunde | Zellen |
|---|--:|--:|--:|--:|--:|
| Steinpilz | 0.647 | 0.584 | +0.063 | 2000 | 639 |
| Maronenröhrling | 0.634 | 0.567 | +0.067 | 2000 | 687 |
| Birkenpilz | 0.627 | 0.567 | +0.060 | 1186 | 468 |
| Fichtenreizker | 0.642 | 0.555 | +0.088 | 776 | 321 |
| Herbsttrompete | 0.695 | 0.579 | +0.116 | 293 | 144 |
| Pfifferling | 0.629 | 0.575 | +0.054 | 1331 | 404 |
| Hallimasch | 0.490 | 0.510 | -0.020 | 2000 | 720 |
| Stockschwämmchen | 0.559 | 0.558 | +0.001 | 1312 | 504 |
| Austernseitling | 0.489 | 0.488 | +0.001 | 1615 | 599 |
| Judasohr | 0.539 | 0.506 | +0.033 | 2000 | 653 |
| Samtfußrübling | 0.506 | 0.471 | +0.035 | 1195 | 399 |

### Zwei Kriterien, die unabhängig dasselbe sagen

Die Schwelle von 0,55 und der Abstand zur artgematchten Referenz sind
verschiedene Maßstäbe — hier fallen sie zusammen:

| | Differenz zur Referenz | B |
|---|--:|--:|
| Herbsttrompete | +0.116 | 0.695 |
| Fichtenreizker | +0.088 | 0.642 |
| Maronenröhrling | +0.067 | 0.634 |
| Steinpilz | +0.063 | 0.647 |
| Birkenpilz | +0.060 | 0.627 |
| Pfifferling | +0.054 | 0.629 |
| Samtfußrübling | +0.035 | 0.506 |
| Judasohr | +0.033 | 0.539 |
| **Stockschwämmchen** | **+0.001** | 0.559 |
| **Austernseitling** | **+0.001** | 0.489 |
| **Hallimasch** | **−0.020** | 0.490 |

Die sechs ausgelieferten Arten liegen alle zwischen +0,054 und +0,116
über einer Referenz, die aus **denselben Gegenden und denselben Monaten**
gezogen wurde. Die drei Schlusslichter liegen bei null oder darunter —
sie sagen über „irgendein Pilz an diesem Ort in diesem Monat" hinaus
nichts.

**Das Stockschwämmchen ist der Grenzfall, den man nicht übersehen darf.**
Mit B = 0.559 liegt es über der 0,55-Schwelle und wäre danach knapp
„vorläufig". Gegen seine eigene Referenz bringt es aber **+0,001** — also
nichts. Wo zwei Kriterien auseinandergehen, gilt das strengere; die
Schwelle ist eine gesetzte Zahl, der Referenzabstand eine gemessene.


## Frost-Diagnose in Design B

Dieselbe Rechnung wie in Phase 1.2, aber gegen Tage desselben Datums anderer Jahre. **Erst hier ist ablesbar, ob die Frost-Signatur den Kalender überlebt** — in Design A liegen die Vergleichstage einer Winterart zwangsläufig Richtung Herbst und Frühjahr, dass Fundtage dann mehr Frost im Rücken haben, folgt schon daraus.

| Art | Frost 7 d F/V | 14 d | 28 d | Tage seit Frost F/V | Wärme seit Frost F/V |
|---|---|---|---|---|---|
| Austernseitling | 46% / 46% | 57% / 56% | 62% / 60% | 4.2 / 4.0 | 26 / 25 |
| Judasohr | 45% / 47% | 58% / 58% | 69% / 67% | 5.8 / 5.0 | 43 / 36 |
| Samtfußrübling | 70% / 73% | 87% / 85% | 92% / 90% | 4.0 / 3.4 | 24 / 20 |

### Die Frost-Signatur überlebt den Kalender bei keiner der drei Arten

Direkt gegenübergestellt, Fundtag / Vergleichstag:

| Art | | Frost 7 d | Frost 28 d | Wärme seit Frost |
|---|---|---|---|---|
| **Samtfußrübling** | Design A | **67 % / 44 %** | **89 % / 62 %** | **25 / 34** |
| | Design B | 70 % / 73 % | 92 % / 90 % | 24 / 20 |
| **Austernseitling** | Design A | 40 % / 30 % | 54 % / 46 % | 28 / 40 |
| | Design B | 46 % / 46 % | 62 % / 60 % | 26 / 25 |
| **Judasohr** | Design A | 39 % / 40 % | 63 % / 54 % | 51 / 39 |
| | Design B | 45 % / 47 % | 69 % / 67 % | 43 / 36 |

In Design A sah der Samtfußrübling nach einem klaren Auslöser aus: 67 %
gegen 44 % Frosttage, dazu weniger Wärme seit dem letzten Frost. Gegen
**dieselben Kalendertage anderer Jahre** bleibt davon nichts — 70 %
gegen 73 %, das Vorzeichen kippt sogar. Dasselbe beim Austernseitling
(46 / 46). Beim Judasohr war schon in A nichts, und in B ist es
weiterhin nichts.

**Das ist die Antwort auf die Frage, für die Design B gebaut wurde.**
Der Auftrag formulierte sie so: „Auslöser und Niveau sind mit diesen
Paaren nicht trennbar — und genau das sollte H3 beantworten." Jetzt sind
sie getrennt. Der Auslöser ist nicht da; was Phase 1.2 gemessen hat, war
die Jahreszeit.

Dass Winterarten im Winter Frost im Rücken haben und Tage 26–45 Tage
daneben weniger, folgt aus dem Kalender und nicht aus der Biologie. Die
Feldbeobachtung zur kälteinduzierten Fruktifikation wird dadurch nicht
widerlegt — **sie wird von diesen Daten nur nicht gestützt.** Der
Unterschied ist wichtig: Mit 2000 Meldungen je Art, gepaart über Jahre,
ist ein schwacher Auslösereffekt durchaus möglich, ohne hier sichtbar zu
werden.

## Eine registrierte Erwartung, die nicht gehalten hat

Vor dem Lauf, nach den ersten beiden Arten, hatte ich aufgeschrieben:

> Der Abschlag A − B sollte mit dem Betrag der Richtungs-Asymmetrie aus
> Phase 1.1 zusammenhängen. Trifft das zu, ist die Asymmetrie ein
> billiger Vorhersager dafür, wieviel Kalender in einer A-Zahl steckt —
> und man braucht Design B künftig nicht für jede Art. Trifft es nicht
> zu, ist meine Deutung von 1.1 falsch gewesen.

Gemessen über alle elf Arten:

| Art | \|Asymmetrie 1.1\| | Abschlag A−B |
|---|--:|--:|
| Austernseitling | 0.439 | +0.148 |
| **Pfifferling** | **0.410** | **+0.014** |
| Hallimasch | 0.188 | +0.215 |
| **Samtfußrübling** | **0.155** | **+0.267** |
| Maronenröhrling | 0.113 | +0.084 |
| Judasohr | 0.103 | +0.033 |
| Stockschwämmchen | 0.100 | +0.160 |
| Fichtenreizker | 0.098 | +0.114 |
| Herbsttrompete | 0.052 | +0.040 |
| Steinpilz | 0.036 | +0.090 |
| Birkenpilz | 0.034 | +0.112 |

**Spearman = +0,16. Widerlegt.** Die größte Asymmetrie (Pfifferling)
hat den kleinsten Abschlag, der größte Abschlag (Samtfußrübling) kommt
aus einer mittleren Asymmetrie.

**Was das für Phase 1 heißt.** Die Asymmetrie misst, wie
**unterschiedlich** die beiden Hälften von Design A sind. Sie misst
nicht, wieviel **Kalender** in der Zahl steckt. Das sind zwei Dinge, die
ich in Phase 1.1 in einen Topf geworfen hatte: Eine Art kann eine steile
Saisonsteigung haben und trotzdem ein Wettersignal, das den Wechsel zu
Design B übersteht — der Pfifferling ist genau dieser Fall.

**Die Folge ist unbequem:** Design B lässt sich nicht durch eine
billigere Diagnose ersetzen. Es muss je Art gerechnet werden.

Der Satz in `docs/pilzampel-diagnosen.md`, die Asymmetrie zeige „die
Steigung des Scores über die Saison", bleibt richtig. Falsch war der
Schluss, den ich daraus gezogen habe — dass diese Steigung dann auch die
Trennschärfe trägt.

## Evidenzstufen (Auftrag 2, Abschnitt 5)

Nach den vorab festgelegten Bedingungen, mit dem Referenzabstand als
zusätzlichem Maßstab, wo er der strengere ist:

| Art | Stufe | warum |
|---|---|---|
| **Pfifferling** | **belegt** | B bestätigt A (−0.014 < 0.05), Kontrollen sauber, 716 Funde, Jahres-Bootstrap [0.576, 0.661] ohne die 0,50, +0.054 über Referenz |
| Steinpilz | vorläufig | B trägt (0.647, +0.063 über Referenz), aber Abschlag 0.090 über der 0,05-Latte |
| Maronenröhrling | vorläufig | wie oben, Abschlag 0.084 |
| Birkenpilz | vorläufig | wie oben, Abschlag 0.112 |
| Fichtenreizker | vorläufig | wie oben, Abschlag 0.114; Jahres-Bootstrap [0.499, 0.716] streift die 0,50 |
| Herbsttrompete | vorläufig | Abschlag nur 0.040, aber **147 Funde** (unter 150) und Spiegel-Kontrolle A bei 0.395 ⚠ |
| Stockschwämmchen | keine Aussage | B 0.559 über der Schwelle, aber **+0.001** gegen die eigene Referenz |
| Judasohr | keine Aussage | B 0.539 unter 0,55 |
| Samtfußrübling | keine Aussage | B 0.506, Bootstrap schließt 0,50 ein |
| Austernseitling | keine Aussage | B 0.489, +0.001 gegen Referenz |
| Hallimasch | keine Aussage | B 0.490, **−0.020** gegen Referenz |

**Keine dieser Stufen ändert etwas an der App**, solange nichts
freigegeben ist. Fünf der sechs ausgelieferten Arten stehen auf
„vorläufig" — nach dem Auftrag heißt das: Ampel bleibt, mit dem Hinweis
„unsichere Datenlage für diese Art". Und keine der fünf verliert ihre
Ampel; „vorläufig" begrenzt die Behauptung, es schafft sie nicht ab.

## Was daraus für Phase 2 folgt

**Die Prämisse von H3 ist gemessen und sie trägt nicht.** Die
Frost-Signatur des Samtfußrüblings war der stärkste Einzelbefund aus
Phase 1.2 — in Design B ist sie verschwunden, an sieben Tagen sogar mit
umgekehrtem Vorzeichen. Ein Zwei-Phasen-Wintermodell auf Arten zu
registrieren, deren Grundsignal in Design B bei 0,50 liegt, hieße eine
Prüfachse für eine Frage auszugeben, die die Daten schon beantwortet
haben.

Das ist eine Feststellung, keine Umplanung: Der Auftrag verlangt an
dieser Stelle anzuhalten und zu berichten.

## Grenzen

Beide Designs messen an GBIF, in Deutschland, auf den Anpassjahren. Design B ersetzt Design A nicht — was hier steht, ordnet ein, welche Zahl wieviel Kalender enthält.

Und Design B hat seine eigene Grenze, die oben schon steht: „üblich“ schließt die guten Jahre ein, weil Presence-only Abwesenheit nicht kennt.
