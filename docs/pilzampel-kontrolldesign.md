# Zwei Kontrolltag-Designs nebeneinander

Stand: 2026-09-18 · Erzeugt von `tool/ampel_diagnose.py --designs` · Auftrag: `docs/pilzampel-auftrag-2.md`, Abschnitt 3, in der Fassung von `docs/pilzampel-auftrag-2-nachtrag-1.md`

Gerechnet auf **Deutschland und den Jahren bis 2018**. Kein Hold-out-Kontakt. Beide Designs laufen auf **derselben Fundliste** — sonst wäre ihr Unterschied teils die Stichprobe statt das Design.

Messbasis: `pinned`, Entdoppeln an.

Alle Tabellen und die Absätze unmittelbar darunter stammen aus dem
Werkzeug; die Abschnitte, die einordnen, sind von Hand geschrieben und
als solche erkennbar (`### …`). Wer den Lauf wiederholt, bekommt die
Tabellen zurück, nicht die Deutung.


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
| Fichtenreizker | **ja** | 0.756 | 0.642 | −0.113 |
| Herbsttrompete | **ja** | 0.735 | 0.695 | −0.039 |
| Pfifferling | **ja** | 0.643 | **0.629** | **−0.013** |
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
Placebo und einem Jahres-Bootstrap [0.413, 0.606], der die 0,50
einschließt. Seine A-Zahl war fast vollständig Kalender.


## Kontrollen und Vertrauensbereiche

| Art | Spiegel A | Toleranz A | Placebo B | Toleranz B | B über Jahre | p | B über Melder |
|---|--:|--:|--:|--:|---|--:|---|
| Steinpilz | 0.478 | ±0.032 | 0.498 | ±0.032 | [0.538, 0.715] | 0.0069 | [0.625, 0.670] |
| Maronenröhrling | 0.474 | ±0.034 | 0.498 | ±0.034 | [0.531, 0.701] | 0.0073 | [0.612, 0.658] |
| Birkenpilz | 0.509 | ±0.040 | 0.492 | ±0.040 | [0.507, 0.708] | 0.0189 | [0.601, 0.653] |
| Fichtenreizker | 0.451 | ±0.051 | 0.513 | ±0.050 | [0.532, 0.712] | 0.0076 | [0.608, 0.676] |
| Herbsttrompete | 0.395 ⚠ | ±0.082 | 0.488 | ±0.082 | [0.567, 0.759] | 0.0050 | [0.652, 0.739] |
| Pfifferling | 0.530 | ±0.038 | 0.512 | ±0.037 | [0.581, 0.661] | <0.00005 | [0.594, 0.669] |
| Hallimasch | 0.506 | ±0.033 | 0.501 | ±0.033 | [0.367, 0.619] | 0.5437 | [0.463, 0.519] |
| Stockschwämmchen | 0.483 | ±0.042 | 0.500 | ±0.041 | [0.455, 0.647] | 0.1293 | [0.515, 0.595] |
| Austernseitling | 0.510 | ±0.064 | 0.495 | ±0.048 | [0.428, 0.560] | 0.6367 | [0.460, 0.518] |
| Judasohr | 0.547 ⚠ | ±0.046 | 0.492 | ±0.036 | [0.457, 0.609] | 0.1593 | [0.507, 0.565] |
| Samtfußrübling | 0.508 | ±0.090 | 0.493 | ±0.046 | [0.413, 0.606] | 0.4498 | [0.460, 0.547] |

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

| Art | B der Art | B der Referenz | Differenz zur Referenz | 95 % der Differenz | p | Referenzfunde | Zellen |
|---|--:|--:|--:|---|--:|--:|--:|
| Steinpilz | 0.647 | 0.584 | +0.063 | [0.022, 0.112] | 0.0010 | 2000 | 639 |
| Maronenröhrling | 0.634 | 0.567 | +0.067 | [0.035, 0.108] | <0.00005 | 2000 | 687 |
| Birkenpilz | 0.627 | 0.567 | +0.060 | [0.009, 0.111] | 0.0108 | 1186 | 468 |
| Fichtenreizker | 0.642 | 0.555 | +0.088 | [0.040, 0.128] | 0.0001 | 776 | 321 |
| Herbsttrompete | 0.695 | 0.579 | +0.116 | [0.011, 0.244] | 0.0127 | 293 | 144 |
| Pfifferling | 0.629 | 0.575 | +0.054 | [0.015, 0.099] | 0.0027 | 1331 | 404 |
| Hallimasch | 0.490 | 0.510 | -0.020 | [-0.058, 0.025] | 0.7747 | 2000 | 720 |
| Stockschwämmchen | 0.559 | 0.558 | +0.001 | [-0.034, 0.045] | 0.4792 | 1312 | 504 |
| Austernseitling | 0.489 | 0.488 | +0.001 | [-0.029, 0.034] | 0.4376 | 1615 | 599 |
| Judasohr | 0.539 | 0.506 | +0.033 | [-0.001, 0.072] | 0.0278 ⚠ | 2000 | 653 |
| Samtfußrübling | 0.506 | 0.471 | +0.035 | [-0.005, 0.076] | 0.0482 | 1195 | 399 |

Der Vertrauensbereich der Differenz (N2) ist **gemeinsam über das Fundjahr** gezogen: Ein gezogenes Jahr bringt seine Funde der Art und seine Referenzfunde mit. Getrennt zu ziehen unterstellte, die beiden Zahlen streuten unabhängig — sie teilen sich aber das Wetter derselben Jahre.

Und eine Korrektur am eigenen Text: Schwelle und Referenzabstand sind **nicht zwei unabhängige Kriterien**. Beide beruhen auf denselben B-AUCs; sie sind zwei Blickwinkel auf dieselbe Zahl, und der Referenzabstand ist der inhaltlich bessere, weil er den Suchaufwand mitführt.

### Was hier zurückgenommen wird

Die erste Fassung dieses Berichts hatte einen Abschnitt „Zwei Kriterien,
die unabhängig dasselbe sagen" — die 0,55-Schwelle und der
Referenzabstand. **Das war falsch, und zwar auf die verführerische Art.**
Zwei Zahlen, die aus derselben Rechnung stammen, stimmen nicht
„unabhängig" überein; sie müssen es. Aus einer Übereinstimmung, die
keine sein kann, wurde damit ein Argument gemacht.

Was davon trägt, ist der Referenzabstand allein — und er trägt jetzt
mehr als vorher, weil er seit N2 einen Vertrauensbereich hat. **Erst der
macht das Stockschwämmchen entscheidbar**: +0,001 mit [−0,033, +0,046]
ist nicht „knapp über null", sondern „ununterscheidbar von null". Die
0,55-Schwelle hätte es über der Latte gesehen; sie ist eine gesetzte
Zahl und kommt in der Stufenregel nicht mehr vor.


## Die Jahreszahl allein als Score (N4)

Der Richtungs-Split oben zeigt bei neun von elf Arten: **spätere Kontrolljahre sind leichter zu schlagen.** Ein Instrumentwechsel kann es nicht sein, der Datensatz ist gepinnt. Bleibt die Frage, ob B einen Anteil „das Fundjahr liegt früh im Zeitraum“ enthält — und der schlägt nur durch, wenn die **Ziehung** schief liegt.

Dieselbe Rechnung wie B, nur mit der Jahreszahl statt des Ampel-Scores. Eine ausgeglichene Ziehung ergibt **0,500 von Konstruktion wegen**; jede Abweichung ist Unwucht.

| Art | Jahr als Score | Kontrolljahre früher | später | Richtungs-Differenz | Beitrag |
|---|--:|--:|--:|--:|--:|
| Steinpilz | 0.491 | 2337 | 2418 | +0.026 | +0.000 |
| Maronenröhrling | 0.491 | 2175 | 2253 | +0.015 | +0.000 |
| Birkenpilz | 0.490 | 1522 | 1583 | +0.057 | +0.001 |
| Fichtenreizker | 0.488 | 968 | 1015 | +0.035 | +0.000 |
| Herbsttrompete | 0.487 | 358 | 377 | +0.055 | +0.001 |
| Pfifferling | 0.491 | 1758 | 1821 | +0.057 | +0.000 |
| Hallimasch | 0.491 | 2307 | 2393 | -0.030 | -0.000 |
| Stockschwämmchen | 0.486 | 1455 | 1541 | +0.023 | +0.000 |
| Austernseitling | 0.486 | 1065 | 1113 | +0.042 | +0.001 |
| Judasohr | 0.491 | 1886 | 1951 | +0.058 | +0.000 |
| Samtfußrübling | 0.495 | 1162 | 1193 | +0.060 | +0.000 |

**Die Ziehung liegt gerade, und damit ist die Sorge erledigt.** Der Wert
liegt bei allen elf Arten zwischen 0,486 und 0,495, die Abweichung von
der 0,500 also unter anderthalb Prozentpunkten. Über die
Richtungs-Differenz gerechnet trägt sie **höchstens 0,001** zur B-Zahl
bei. Kein Ergebnis dieses Berichts ändert sich in der dritten
Nachkommastelle.

Zwei Dinge sind trotzdem zu notieren:

- **Die Schieflage zeigt zur späteren Seite** (unter 0,500 heißt: etwas
  mehr spätere als frühere Kontrolljahre), und spätere Jahre sind
  leichter zu schlagen. Die Unwucht wirkt also in die Richtung, die B
  vergrößert — nur eben um nichts. Sie kommt aus den Randjahren: Ein
  Fund von 2007 hat vier spätere Kontrolljahre und eines davor.
- **Der Zeittrend selbst bleibt bestehen.** Dass spätere Kontrolljahre
  leichter zu schlagen sind, ist gemessen und wird durch die gerade
  Ziehung nicht kleiner — es kommt nur nicht in die B-Zahl hinein. Die
  naheliegende Deutung sind wärmere, trockenere Spätsommer, die unter
  der 13-°C-Glocke schlechter bewertet werden.

**Als Vorschlag notiert, nicht umgesetzt:** Features als Abweichung von
der zelleigenen Klimatologie statt als Absolutwerte. Das nähme dem
Zeittrend die Grundlage. Es ist ein Modellumbau und gehört registriert,
nicht nebenbei gemacht.

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

**Wie groß hätte ein Auslösereffekt sein müssen, um hier aufzufallen?** (N3) Nicht „kein Effekt“, sondern eine Grenze: Unterhalb davon sagt dieser Aufbau nichts, weder ja noch nein.

| Art | Funde in B | B | Standardfehler (Jahre) | nachweisbar ab | zum Vergleich: unabhängige Paare |
|---|--:|--:|--:|--:|--:|
| Austernseitling | 451 | 0.489 | 0.034 | +0.094 | +0.066 |
| Judasohr | 783 | 0.539 | 0.039 | +0.108 | +0.050 |
| Samtfußrübling | 494 | 0.506 | 0.049 | +0.138 | +0.063 |

Der Standardfehler kommt aus dem **Jahres-Bootstrap**, nicht aus der Paarzahl: `sqrt(0,25/n)` unterstellt unabhängige Paare, und B-Paare desselben Jahres teilen sich das Wetter. Die letzte Spalte zeigt, was die Vernachlässigung kostet — sie ist die schönere und die falsche Zahl.

Gelesen wird es so: Ein Auslösereffekt, der die B-AUC um mindestens den Betrag in der vorletzten Spalte über 0,50 hebt, wäre hier mit 80 % Wahrscheinlichkeit aufgefallen (zweiseitig, α = 0,05). Ein kleinerer nicht. Die Feldbeobachtung zur kälteinduzierten Fruktifikation bleibt damit eine **offene** Frage, keine widerlegte.

### H3 und H3b sind geschlossen (N3)

**Nicht registriert, mit einer Zahl statt eines Urteils.**

H3 wollte ein Zwei-Phasen-Wintermodell prüfen: Kältereiz, dann
Wärmesumme. Die Prämisse dafür ist jetzt gemessen, und sie trägt nicht —
in Design B ist von der Frost-Signatur nichts übrig, bei einer der drei
Arten kippt das Vorzeichen. Eine Prüfachse dafür auszugeben hieße, eine
Frage zu stellen, die diese Daten schon beantwortet haben.

Die Grenze dieser Aussage steht in der Tabelle darüber und gehört
dazugesagt: **Ein Auslösereffekt ab etwa +0,09 bis +0,14 AUC ist
ausgeschlossen, ein kleinerer nicht.** Das ist viel — es entspricht rund
einem Drittel dessen, was der Steinpilz in Design B überhaupt erreicht.
Wer also glaubt, der Kältereiz sei ein feiner Effekt neben einem großen
Jahreszeiteffekt, findet hier keinen Widerspruch.

Was diesen Nachweis teuer macht, ist nicht die Zahl der Meldungen,
sondern ihre **Bündelung in Jahren**: Der Standardfehler über
Fundjahre ist beim Samtfußrübling mit 0,049 fast das Doppelte dessen,
was 494 unabhängige Paare ergäben (0,022). Mehr Meldungen derselben
zwanzig Winter helfen dagegen kaum; mehr *Winter* würden helfen.

Die Feldbeobachtung zur kälteinduzierten Fruktifikation bleibt als
**offene Frage** in der Doku stehen — nicht als widerlegte.


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
| **Pfifferling** | **0.410** | **+0.013** |
| Hallimasch | 0.188 | +0.215 |
| **Samtfußrübling** | **0.155** | **+0.267** |
| Maronenröhrling | 0.113 | +0.084 |
| Judasohr | 0.103 | +0.033 |
| Stockschwämmchen | 0.100 | +0.160 |
| Fichtenreizker | 0.098 | +0.113 |
| Herbsttrompete | 0.052 | +0.039 |
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

## Evidenzstufen nach N1

**Die alte Regel ist ersetzt, und zwar nach dem Blick auf die Zahlen.** Das wird hier hingeschrieben, statt es zu verschweigen. Sie machte den Abschlag `A − B < 0,05` zur Bedingung für „belegt“ — während derselbe Auftrag an anderer Stelle sagt, dass B strukturell kleiner sein MUSS. Die Latte bestrafte also genau den erwarteten Effekt.

Vertretbar ist der Austausch, weil er kein Ergebnis umdeutet, sondern ein Kriterium ersetzt, das die falsche Größe gemessen hat — und weil er die Anforderungen eher **verschärft**: Die Referenz-Bedingung verlangt seit N2 zusätzlich einen Vertrauensbereich ohne die Null.

| Bedingung für „belegt“ | Schwelle |
|---|---|
| Jahres-Bootstrap von B | schließt 0,50 aus |
| Differenz zur artgematchten Referenz | > 0, Vertrauensbereich ohne die Null |
| Funde in Design B | ≥ 150 |
| Kontrollen (Placebo B, Spiegel A) | innerhalb 2 SE |

Die beiden Bänder entscheiden über ihren **p-Wert** und nicht über ihre Kante: Anteil der 20000 Züge auf der falschen Seite, Grenze 0,025. Eine Kante ist der 50. von 2000 Zügen und rauscht; der Anteil tut es nicht. Wo ein p dicht an 0,025 liegt, steht das Urteil auf der Kippe, und dann soll man das sehen.

| Art | alt | **neu** | Bootstrap (p) | Referenz (p) | Funde | Kontrollen | Abschlag A−B |
|---|---|---|:-:|:-:|:-:|:-:|--:|
| Steinpilz | vorläufig | **belegt** | ✓ 0.0069 | ✓ 0.0010 | ✓ 951 | ✓ | +0.090 |
| Maronenröhrling | vorläufig | **belegt** | ✓ 0.0073 | ✓ <0.00005 | ✓ 886 | ✓ | +0.084 |
| Birkenpilz | vorläufig | **belegt** | ✓ 0.0189 | ✓ 0.0108 | ✓ 621 | ✓ | +0.112 |
| Fichtenreizker | vorläufig | **belegt** | ✓ 0.0076 | ✓ 0.0001 | ✓ 397 | ✓ | +0.113 |
| Herbsttrompete | vorläufig | vorläufig | ✓ 0.0050 | ✓ 0.0127 | ✗ 147 | ✗ | +0.039 |
| Pfifferling | belegt | belegt | ✓ <0.00005 | ✓ 0.0027 | ✓ 716 | ✓ | +0.013 |
| Hallimasch | keine Aussage | keine Aussage | ✗ 0.5437 | ✗ 0.7747 | ✓ 941 | ✓ | +0.215 |
| Stockschwämmchen | keine Aussage | keine Aussage | ✗ 0.1293 | ✗ 0.4792 | ✓ 601 | ✓ | +0.160 |
| Austernseitling | keine Aussage | keine Aussage | ✗ 0.6367 | ✗ 0.4376 | ✓ 451 | ✓ | +0.148 |
| Judasohr | keine Aussage | keine Aussage | ✗ 0.1593 | ✗ 0.0278 ⚠ | ✓ 783 | ✗ | +0.033 |
| Samtfußrübling | keine Aussage | keine Aussage | ✗ 0.4498 | ✗ 0.0482 | ✓ 494 | ✓ | +0.267 |

Der Abschlag steht weiter in der Tabelle — als Auskunft darüber, wieviel Kalender in der A-Zahl steckt. Er ist nur kein Tor mehr.

### Was sich verschiebt

| Stufe | alt | neu |
|---|---|---|
| **belegt** | Pfifferling | Steinpilz, Maronenröhrling, Birkenpilz, Fichtenreizker, Pfifferling |
| **vorläufig** | Steinpilz, Maronenröhrling, Birkenpilz, Fichtenreizker, Herbsttrompete | Herbsttrompete |
| **keine Aussage** | Hallimasch, Stockschwämmchen, Austernseitling, Judasohr, Samtfußrübling | unverändert |

Die alte Regel hatte die Rangfolge auf den Kopf gestellt: Der
Pfifferling galt als einziger als „belegt", weil sein A mit 0,643 wenig
Kalender zu verlieren hatte — während der Steinpilz bei **höherem** B
(0,647) und **größerem** Referenzabstand darunter stand. Nach der neuen
Regel liegen beide gleichauf, und das ist der Punkt: Gemessen wird, was
B trägt, nicht wie klein der Abstand zu A ist.

### Zwei Abweichungen von der Erwartung im Nachtrag

Der Nachtrag nennt eine Erwartung nach Aktenlage und sagt dazu „bitte
nachrechnen, nicht übernehmen". Das war gut so, denn zwei Zeilen fallen
anders aus:

**Maronenröhrling und Fichtenreizker stehen auf „belegt", nicht auf
„vorläufig".** Die Erwartung stützte sich darauf, dass ihr
Jahres-Bootstrap die 0,50 streift — im alten Bericht [0,500, 0,703] und
[0,499, 0,716]. **Diese beiden Kanten waren Losrauschen.** Sie stammen
aus 400 Zügen, und die 2,5-%-Kante ist dort der zehnte Zug; ihr eigener
Fehler ist größer als der Abstand, um den es geht. Mit 20 000 Zügen
liegen die Bänder bei [0,531, 0,701] und [0,532, 0,712], die p-Werte bei
0,0073 und 0,0076 — nicht knapp, sondern deutlich.

Daraus folgt eine Regeländerung im Werkzeug, die keine Ermessensfrage
ist: **Entschieden wird über den p-Wert, nicht über die Bandkante.** Der
Anteil der Züge jenseits der Null ist eine stetige Größe und lässt sich
beliebig genau rechnen; eine Quantilskante ist ein einzelner Zug. Möglich
wurde das durch eine Beschleunigung — `score_b` mittelt je Fund einen
Anteil, der nur an diesem Fund hängt, also wird er einmal vorgerechnet
statt in jedem Zug neu. Der Selbsttest hält beide Wege Zahl für Zahl
gegeneinander.

### Der eine Fall, der wirklich auf der Kippe steht

**Das Judasohr**, und zwar an seinem Referenzabstand: p = 0,0278 gegen
eine Grenze von 0,025. Fiele es auf die andere Seite, wäre es nicht
„keine Aussage", sondern „vorläufig". Der Abstand ist kleiner als das,
was eine andere Ziehung der Kontrolljahre bewegen würde.

Gegen eine Aufwertung sprechen zwei weitere Zahlen, und deshalb bleibt
es dabei: Sein Jahres-Bootstrap liegt bei p = 0,159, schließt die 0,50
also klar ein — und seine Spiegel-Kontrolle in Design A steht bei 0,547
außerhalb der Toleranz. Es wäre die schwächste „vorläufig"-Art, die es
gäbe. Wer die Stufe trotzdem vergeben will, muss das als Entscheidung
tun und nicht als Ablesung.

### Die Regel ist schärfer geworden, nicht weicher

Das ist der Prüfstein für eine Regeländerung nach dem Blick auf die
Zahlen. Drei Punkte:

- **Der Referenzabstand braucht jetzt einen Vertrauensbereich** (N2).
  Vorher genügte ein positiver Punktschätzer; das Stockschwämmchen kam
  mit +0,001 durch die erste Hälfte des alten Kriteriums.
- **Die 0,55-Schwelle ist ganz entfallen.** Sie war gesetzt, nicht
  gemessen, und hätte das Stockschwämmchen gehalten.
- **Vier Bedingungen statt drei**, und keine davon ist der Abschlag.

Weicher ist nur eines geworden: Vier Arten, die vorher wegen einer
Größe unten standen, die sie gar nicht messen sollte, stehen jetzt
oben. Das ist die Korrektur, nicht die Lockerung.


## Was daraus für Phase 2 folgt

**H3 ist geschlossen** (oben, N3). Die Prämisse ist gemessen und trägt
nicht; die nachweisbare Effektgröße steht daneben, damit aus „nicht
gestützt" keine Behauptung wird.

**H1 ist die nächste Hypothese** (N5): schmalere Glocke, 3,25 K. Sie
wird noch nicht registriert — das ist der nächste Arbeitsschritt nach
dem Checkpoint. Vier Festlegungen aus dem Nachtrag gehören schon
hierher, weil sie sich aus diesem Bericht ergeben:

- **Maßgeblich ist Design B.** Nach diesem Bericht ist das keine
  Geschmacksfrage mehr: Design A enthält bei den Herbstarten rund 0,09
  Kalender, und eine Breite, die auf A angepasst wird, passt sich zum
  Teil an die Jahreszeit an.
- **Die Anpassjahre DE ≤ 2018 bleiben unberührt**, weil die 3,25 K aus
  den Bielefelder Daten stammen. Alle GBIF-Jahre sind damit Prüfdaten.
- **Das Optimum bleibt fest bei 13,0 °C.** Phase 0.4 hat gezeigt, dass
  angepasste Optima den Instrumentwechsel nicht überstehen; eine zweite
  freie Größe machte den Test unlesbar.
- **Der Pfifferling ist dabei.** Seine Kontrollen halten in B, und er
  hat den kleinsten Kalenderanteil aller elf Arten. Seine Sommerklasse
  behält ihr eigenes Optimum; geprüft wird nur die Breite.

**Das bedingte Logit** auf den B-Paaren der Anpassjahre (`[log R, t,
t²]`) liefert Optimum und Breite mit Standardfehler — **klar getrennt
vom Test**. Wer daraus den Prüfwert macht, verwandelt eine externe Zahl
in eine angepasste, und deren Instabilität war der Befund aus Phase 0.4.

**An der ausgelieferten Ampel ändert sich nichts.** Auch die
Evidenzstufen gehen nach N7 erst dann in die App, wenn H1 durch ist —
dann in einem Zug mit den dann gültigen Stufen und Schwellen.

## Grenzen

Beide Designs messen an GBIF, in Deutschland, auf den Anpassjahren. Design B ersetzt Design A nicht — was hier steht, ordnet ein, welche Zahl wieviel Kalender enthält.

Und Design B hat seine eigene Grenze, die oben schon steht: „üblich“ schließt die guten Jahre ein, weil Presence-only Abwesenheit nicht kennt.
