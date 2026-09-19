# Die Schwellen aus Design B — Vorlage, nicht Übernahme

Stand: 2026-09-19 · Erzeugt von `tool/ampel_diagnose.py --schwellen` · Auftrag: `docs/pilzampel-auftrag-3.md`, Abschnitt A

> **Diese Datei wird erzeugt.** Wer sie von Hand ändert, verliert die Änderung beim nächsten Lauf.

## Was hier gefragt wird

Die vier ausgelieferten Schwellen sind **Quantile der Score-Verteilung an Vergleichstagen**. Sie entscheiden nicht, wie gut die Ampel trennt, sondern **wie oft sie „günstig“ sagt**. Das ist eine Häufigkeitsfrage, und die Antwort hängt daran, welche Tage man „üblich“ nennt.

Gesetzt wurden sie an **Design-A-Vergleichstagen**: ein anderer Tag derselben Saison, 26 bis 45 Tage neben dem Fund, im selben Jahr. Phase 1.5 hat gemessen, dass in dieser Paarung bei den Herbstarten rund 0,09 AUC Kalender stecken. Was in der Trennschärfe steckt, steckt auch in der Verteilung, aus der die Schwelle gezogen wurde.

**Design B fragt dasselbe an einem anderen Tag:** gleicher Ort, gleiches Datum, anderes Jahr. Die Verteilung heißt dann „wie ist das Wetter hier um diese Zeit üblich“ — und genau das ist die Bezugsgröße, die zur Aussage „heute ist es ungewöhnlich gut“ gehört.

## Wie gemessen wurde

Vor dem Lauf festgelegt (`tool/ampel_diagnose.py`, Abschnitt „A aus Auftrag 3“):

- **Gerechnet wird auf P3** — Deutschland bis 2018. Das sind die Anpassjahre; der Lauf verbraucht keine Prüfachse.
- **Bewertet wird mit dem ausgelieferten Fenster** der Klasse (13,0 °C bzw. 17,5 °C) und σ = 5,0 K. Hier geht es um die Schwelle, nicht um das Fenster — das ist H6.
- **Die Quantile bleiben 50 % und 80 %**, die Auslieferungsquantile vom 2026-09-12 („gleich häufig wie bisher“). Gefragt ist, welche ZAHL dasselbe Quantil in Design B trägt.
- **Jedes Fundjahr gleich schwer, jede Art gleich schwer** — dieselben zwei Regeln wie in `class_thresholds`, aus demselben Grund: Stichprobengröße soll nicht für Bedeutung einstehen.
- **Ein Fund zählt einmal**, nicht einmal je Kontrolljahr. Wer fünf brauchbare Jahre hat, verteilt sein Gewicht darauf.
- **Das Band ist ein Jahres-Bootstrap** über Fundjahre, 2000 Züge. Es ist eine Auskunft über die Genauigkeit, keine Entscheidungsgrundlage.

## Korrekturkasten

**Eine Methodenentscheidung ist nach der Datensicht gefallen** und steht deshalb hier, nicht oben.

Der erste Lauf benutzte `MIN_FINDS_B` (150 Funde) als Untergrenze. Damit fiel die Herbsttrompete mit 147 Funden aus der Klasse heraus, und die Klassenschwelle haette auf vier statt fünf Mitgliedern geruht — obwohl die App sie für fünf ausliefert.

Die beiden Grenzen messen nicht dasselbe. `MIN_FINDS_B` entscheidet, ob eine Art ein URTEIL trägt: Dort steht eine einzelne Zahl gegen eine Latte, und eine dünne Zahl darf das nicht. Hier steuert eine Art ein Fünftel zu einem Quantil bei, das mit vier anderen gemittelt wird. **Die Fehlerrichtung ist umgekehrt** — eine ausgelieferte Art wegzulassen verzerrt die Schwelle sicher, sie mit 147 Funden mitzunehmen nur vielleicht. Die Grenze für den Beitrag zu einem Quantil steht deshalb bei 100.

Damit das keine Ausrede bleibt, steht unten eine **Leave-one-out-Spalte**: was die Schwelle wäre, wenn genau diese Art fehlte.

## Das Material

| Art | Klasse | Funde auf P3 | Kontrolltage | Fundjahre | Design-A-Jahre |
|---|---|--:|--:|--:|--:|
| Steinpilz | Steinpilz & Co. | 951 | 4755 | 13 | 13 |
| Maronenröhrling | Steinpilz & Co. | 886 | 4428 | 13 | 13 |
| Birkenpilz | Steinpilz & Co. | 621 | 3105 | 12 | 12 |
| Fichtenreizker | Steinpilz & Co. | 397 | 1983 | 13 | 13 |
| Herbsttrompete ⚠ | Steinpilz & Co. | 147 | 735 | 12 | 12 |
| Pfifferling | Pfifferling | 716 | 3579 | 13 | 13 |

⚠ unter 150 Funden — trägt kein eigenes Urteil, steuert aber zum Klassenquantil bei (Korrekturkasten).

## Die Schwellen je Klasse

Drei Zellen. Die erste ist die App von heute, die zweite trennt die Zeitscheibe vom Design ab, die dritte ist die gefragte Zahl.

| Klasse | Stufe | ausgeliefert (A, P1) | Design A auf P3 | Design B auf P3 | 95 % |
|---|---|--:|--:|--:|---|
| Steinpilz & Co. | verhalten | 0.187 | 0.255 | 0.400 | [0.366, 0.423] |
|  | günstig | 0.512 | 0.562 | 0.727 | [0.701, 0.758] |
| Pfifferling | verhalten | 0.287 | 0.374 | 0.447 | [0.385, 0.514] |
|  | günstig | 0.677 | 0.831 | 0.805 | [0.708, 0.858] |

### Woher der Unterschied kommt

| Klasse | Stufe | Zeitscheibe (A: P1 → P3) | Design (P3: A → B) | gesamt |
|---|---|--:|--:|--:|
| Steinpilz & Co. | verhalten | +0.068 | +0.145 | +0.213 |
|  | günstig | +0.050 | +0.165 | +0.215 |
| Pfifferling | verhalten | +0.087 | +0.073 | +0.160 |
|  | günstig | +0.154 | -0.026 | +0.128 |

**Die Zeitscheiben-Spalte ist kein Nebeneffekt.** Die ausgelieferten Zahlen stammen mit Absicht aus den Prüfjahren — für die Auslieferung zählt, wo die App HEUTE steht (`docs/pilzampel-schwellen-messung.md`). Eine auf P3 gemessene Schwelle beantwortet „was war 2006 bis 2018 üblich“, nicht „was ist heute üblich“. Und zwischen beiden Scheiben liegt nachweislich etwas: Dieselbe feste Zahl wurde vor 2019 an rund 30 %, danach an rund 20 % der Vergleichstage überschritten (`docs/pilzampel-schwellen-messung.md`), und die Glocke trennt in den Prüfjahren schwächer als in den Anpassjahren (`docs/pilzampel-alterung.md`).

### Trägt eine einzelne Art die Zahl?

Die Klassenschwelle, jeweils **ohne** ein Mitglied. Bei fünf Mitgliedern verschiebt das Weglassen eines Fünftels die Zahl immer ein wenig; interessant ist nur, ob eine Art heraussticht.

| Klasse | ohne … | verhalten | günstig |
|---|---|--:|--:|
| Steinpilz & Co. | Steinpilz | 0.393 | 0.713 |
|  | Maronenröhrling | 0.397 | 0.733 |
|  | Birkenpilz | 0.400 | 0.727 |
|  | Fichtenreizker | 0.396 | 0.705 |
|  | Herbsttrompete | 0.407 | 0.759 |

## Was sich für Nutzer ändert

Gemessen an denselben Design-B-Kontrolltagen. „Kontrolltage“ sind Tage an Pilzorten in der Fruchtzeit der Art — also die Tage, an denen jemand die App aufmacht, ohne dass etwas Besonderes wäre. Die Fundtag-Spalte steht daneben, damit sichtbar bleibt, ob die Schwelle noch trennt.

Die erste Spalte ist die Probe aufs Exempel: Wie oft überschreitet die heutige Schwelle die Tage, an denen sie GESETZT wurde? Nahe 20 % heißt, dass die Zahl in ihrer eigenen Welt genau das tut, was sie soll — und dass der Sprung daneben wirklich vom Wechsel der Bezugstage kommt.

| Art | alt an A-Tagen | B-Tage günstig, alt → neu | Fundtage günstig, alt → neu | Hebel, alt → neu |
|---|--:|--:|--:|--:|
| Steinpilz | 21,8 % | 40,8 % → 23,5 % | 52,9 % → 28,9 % | 1,29 → 1,23 |
| Maronenröhrling | 30,2 % | 37,0 % → 18,6 % | 45,6 % → 24,3 % | 1,23 → 1,31 |
| Birkenpilz | 20,0 % | 38,0 % → 20,0 % | 49,1 % → 25,8 % | 1,29 → 1,29 |
| Fichtenreizker | 21,0 % | 40,4 % → 26,0 % | 46,8 % → 27,2 % | 1,16 → 1,05 |
| Herbsttrompete | 21,6 % | 27,8 % → 11,9 % | 45,1 % → 26,2 % | 1,63 → 2,20 |
| Pfifferling | 30,0 % | 28,4 % → 20,0 % | 40,4 % → 29,2 % | 1,42 → 1,46 |

**Der Hebel ist die Spalte, die entscheidet, ob eine Schwelle besser ist.** Er sagt, um welchen Faktor ein Fundtag wahrscheinlicher günstig ist als ein gewöhnlicher Tag. Ein seltenerer Hinweis ist nicht von selbst ein besserer: Wer die Latte hebt, senkt beide Raten, und der Abstand in Prozentpunkten schrumpft mit. Bleibt der Hebel gleich, ist die neue Schwelle **dieselbe Aussage an einer anderen Stelle** — eine Frage der Häufigkeit, wie Abschnitt A von Auftrag 3 sie nennt, und keine der Trennschärfe.


### Je Monat

Anteil der Kontrolltage, an denen die Ampel **günstig** stünde. Monate unter 5 % des Materials einer Art stehen nicht da — dort wäre die Zahl ein Gerücht.

| Art | Monat | Anteil des Materials | alt | neu |
|---|---|--:|--:|--:|
| Steinpilz | Juni | 7 % | 50,8 % | 29,5 % |
|  | Juli | 7 % | 24,8 % | 10,9 % |
|  | August | 18 % | 38,0 % | 19,7 % |
|  | September | 36 % | 45,1 % | 27,5 % |
|  | Oktober | 26 % | 43,4 % | 26,0 % |
|  | November | 5 % | 13,7 % | 4,2 % |
| Maronenröhrling | August | 11 % | 23,4 % | 9,0 % |
|  | September | 34 % | 39,3 % | 21,3 % |
|  | Oktober | 41 % | 45,2 % | 22,8 % |
|  | November | 9 % | 18,4 % | 8,3 % |
| Birkenpilz | Juli | 7 % | 17,1 % | 3,1 % |
|  | August | 12 % | 18,5 % | 8,9 % |
|  | September | 38 % | 38,4 % | 20,5 % |
|  | Oktober | 35 % | 49,4 % | 28,0 % |
| Fichtenreizker | August | 16 % | 44,0 % | 23,3 % |
|  | September | 31 % | 50,9 % | 34,1 % |
|  | Oktober | 34 % | 45,2 % | 31,3 % |
|  | November | 16 % | 8,8 % | 3,2 % |
| Herbsttrompete | Juni | 6 % | 67,4 % | 39,5 % |
|  | Juli | 19 % | 16,9 % | 2,2 % |
|  | August | 10 % | 8,4 % | 5,8 % |
|  | September | 26 % | 38,9 % | 13,0 % |
|  | Oktober | 31 % | 28,8 % | 16,8 % |
|  | November | 8 % | 8,8 % | 0,0 % |
| Pfifferling | Juni | 15 % | 38,4 % | 22,9 % |
|  | Juli | 17 % | 45,7 % | 39,2 % |
|  | August | 19 % | 49,3 % | 37,0 % |
|  | September | 28 % | 19,3 % | 10,6 % |
|  | Oktober | 16 % | 1,2 % | 0,5 % |

## Was die Zahlen sagen

**Die ausgelieferten Schwellen sind in ihrer eigenen Welt in Ordnung.** An Design-A-Vergleichstagen liegen im Mittel 21,7 % der Tage über der günstig-Schwelle — also ungefähr das eine Fünftel, für das sie gesetzt wurde. Der Kalibrierung fehlt nichts.

**Sie messen nur gegen die falschen Tage.** Dieselbe Zahl an Design-B-Kontrolltagen: 37,5 %. Die Ampel steht an einem gewöhnlichen Tag am Fundort zur Fundzeit also **1,7-mal so oft** auf günstig, wie ihre eigene Kalibrierung vorsieht.

**Der Grund ist die Jahreszeit, und er ist mechanisch.** Ein Design-A-Vergleichstag liegt 26 bis 45 Tage neben dem Fund — bei einem Herbstpilz also im Hochsommer oder im Spätherbst, und beides ist weiter vom Fenster der Klasse entfernt als der Fundtag selbst. Die Glocke steht dort niedriger, die ganze Verteilung rutscht nach unten, und eine daraus gezogene Schwelle rutscht mit. Genau der Kalenderanteil, den Phase 1.5 in der AUC gemessen hat, steckt auch hier — nur sieht man ihn in der Häufigkeit statt in der Trennschärfe.

**Die neue Schwelle trennt aber nicht besser.** Der Hebel steht vorher im Mittel bei 1,29 und nachher bei 1,30. Was sich ändert, ist die Häufigkeit — 37,5 % gegen 20,0 % der Tage — und nicht, wie verlässlich der Hinweis ist. Das ist keine Enttäuschung, sondern die Bestätigung, dass hier eine Häufigkeitsfrage vorliegt.

**Und die Zahl ist noch nicht auslieferbar.** Zwischen der Zeitscheibe P3 und den Jahren, in denen die App läuft, liegen bei den vier Zahlen oben zwischen +0,05 und +0,15 — mehr als ein Drittel des Gesamtsprungs beim Pfifferling. Wer die Spalte „Design B auf P3“ direkt übernimmt, liefert eine Schwelle aus, die für 2006 bis 2018 gemessen wurde.


## Die Zelle, die fehlt

**Design B auf P1.** Das wäre die auslieferbare Zahl: dasselbe Design, aber die Jahre, in denen die App benutzt wird. Sie ist hier nicht gerechnet, weil P1 eine Prüfachse ist (`docs/pilzampel-pruefachsen.md`) und Auftrag 3 A ausdrücklich als achsenfreier Lauf angelegt ist.

Ob sie gerechnet wird, ist eine eigene Entscheidung. Dafür spricht, dass eine Schwelle keine Hypothese ist, sondern eine beschreibende Zahl — die ausgelieferten vier sind auf demselben Weg entstanden und stehen in der Strichliste als Diagnose. Dagegen spricht die Regel vom 2026-09-19: kein Lauf auf einer Achse ohne vorherigen Check auf P3. Dieser Bericht IST dieser Check.

## Vorlage, keine Übernahme

**Hier wird nichts übernommen.** Wie oft die Ampel „günstig“ sagen soll, ist eine Produktentscheidung und keine Messung. Diese Seite sagt nur, welche Zahl welches Verhalten trägt.

Wer sie übernimmt, ändert **vier Konstanten in `ampel_model.dart` und `tool/ampel_validate.py` zusammen** — die Spiegel-Regel gilt, und `verify_class_constants` bricht ab, sobald eine allein wandert.
