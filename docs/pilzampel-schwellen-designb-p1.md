# Die Schwellen aus Design B — Vorlage, nicht Übernahme

Stand: 2026-09-19 · Erzeugt von `tool/ampel_diagnose.py --schwellen --scheibe p1` · Auftrag: `docs/pilzampel-auftrag-3.md`, Abschnitt A · Zeitscheibe: **DE ab 2019**

> **Diagnose, kein Prüflauf.** Schwelle und gepaarte AUC sind disjunkte Statistiken: Die AUC ist rangbasiert und von jeder Schwelle unabhängig. Hier wird eine Verteilung beschrieben, nicht ausgewählt — es gibt keine Latte, kein Band und nichts zu bestehen. **Schwellenabhängige Gütemaße sind auf dieser Scheibe gesperrt** (Trefferquote, POD, FAR, TSS, Hebel, Fundtag-Anteil); sie stehen im P3-Bericht.

> **Diese Datei wird erzeugt.** Wer sie von Hand ändert, verliert die Änderung beim nächsten Lauf.

## Was hier gefragt wird

Die vier ausgelieferten Schwellen sind **Quantile der Score-Verteilung an Vergleichstagen**. Sie entscheiden nicht, wie gut die Ampel trennt, sondern **wie oft sie „günstig“ sagt**. Das ist eine Häufigkeitsfrage, und die Antwort hängt daran, welche Tage man „üblich“ nennt.

Gesetzt wurden sie an **Design-A-Vergleichstagen**: ein anderer Tag derselben Saison, 26 bis 45 Tage neben dem Fund, im selben Jahr. Phase 1.5 hat gemessen, dass in dieser Paarung bei den Herbstarten rund 0,09 AUC Kalender stecken. Was in der Trennschärfe steckt, steckt auch in der Verteilung, aus der die Schwelle gezogen wurde.

**Design B fragt dasselbe an einem anderen Tag:** gleicher Ort, gleiches Datum, anderes Jahr. Die Verteilung heißt dann „wie ist das Wetter hier um diese Zeit üblich“ — und genau das ist die Bezugsgröße, die zur Aussage „heute ist es ungewöhnlich gut“ gehört.

## Wie gemessen wurde

Vor dem Lauf festgelegt (`tool/ampel_diagnose.py`, Abschnitt „A aus Auftrag 3“):

- **Gerechnet wird auf P1** — Deutschland ab 2019, also die Jahre, in denen die App benutzt wird. Das ist die Scheibe, für die eine ausgelieferte Schwelle gelten soll.
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

| Art | Klasse | Funde | Kontrolltage | Fundjahre |
|---|---|--:|--:|--:|
| Steinpilz | Steinpilz & Co. | 1041 | 5205 | 7 |
| Maronenröhrling | Steinpilz & Co. | 1109 | 5545 | 7 |
| Birkenpilz | Steinpilz & Co. | 564 | 2820 | 7 |
| Fichtenreizker | Steinpilz & Co. | 378 | 1890 | 7 |
| Herbsttrompete ⚠ | Steinpilz & Co. | 145 | 725 | 7 |
| Pfifferling | Pfifferling | 605 | 3021 | 7 |

⚠ unter 150 Funden — trägt kein eigenes Urteil, steuert aber zum Klassenquantil bei (Korrekturkasten).

## Die Schwellen je Klasse

Die auslieferbare Zahl: dasselbe Design wie im P3-Bericht, aber die Jahre, in denen die App läuft.

| Klasse | Stufe | ausgeliefert | Design B auf P1 | 95 % |
|---|---|--:|--:|---|
| Steinpilz & Co. | verhalten | 0.187 | 0.389 | [0.355, 0.422] |
|  | günstig | 0.512 | 0.742 | [0.710, 0.772] |
| Pfifferling | verhalten | 0.287 | 0.385 | [0.350, 0.414] |
|  | günstig | 0.677 | 0.729 | [0.678, 0.774] |
### Trägt eine einzelne Art die Zahl?

Die Klassenschwelle, jeweils **ohne** ein Mitglied. Bei fünf Mitgliedern verschiebt das Weglassen eines Fünftels die Zahl immer ein wenig; interessant ist nur, ob eine Art heraussticht.

| Klasse | ohne … | verhalten | günstig |
|---|---|--:|--:|
| Steinpilz & Co. | Steinpilz | 0.393 | 0.744 |
|  | Maronenröhrling | 0.386 | 0.743 |
|  | Birkenpilz | 0.388 | 0.739 |
|  | Fichtenreizker | 0.386 | 0.737 |
|  | Herbsttrompete | 0.393 | 0.747 |

## Was sich für Nutzer ändert

Gemessen an denselben Design-B-Kontrolltagen. „Kontrolltage“ sind Tage an Pilzorten in der Fruchtzeit der Art — also die Tage, an denen jemand die App aufmacht, ohne dass etwas Besonderes wäre.

| Art | Kontrolltage günstig, alt → neu |
|---|--:|
| Steinpilz | 35,9 % → 19,6 % |
| Maronenröhrling | 37,8 % → 19,8 % |
| Birkenpilz | 37,7 % → 20,5 % |
| Fichtenreizker | 37,9 % → 21,5 % |
| Herbsttrompete | 34,4 % → 18,7 % |
| Pfifferling | 23,7 % → 20,0 % |

**Die Fundtagsspalte fehlt hier mit Absicht.** Ihr Anteil über der Schwelle ist eine Trefferquote, und die ist auf dieser Scheibe gesperrt. Wie verlässlich der Hinweis ist, steht im P3-Bericht; was hier steht, ist allein, **wie oft** er erscheint.


### Je Monat

Anteil der Kontrolltage, an denen die Ampel **günstig** stünde. Monate unter 5 % des Materials einer Art stehen nicht da — dort wäre die Zahl ein Gerücht.

| Art | Monat | Anteil des Materials | alt | neu |
|---|---|--:|--:|--:|
| Steinpilz | August | 11 % | 7,7 % | 1,7 % |
|  | September | 28 % | 27,3 % | 13,9 % |
|  | Oktober | 45 % | 54,1 % | 32,6 % |
|  | November | 11 % | 21,5 % | 5,2 % |
| Maronenröhrling | August | 7 % | 8,4 % | 2,8 % |
|  | September | 21 % | 28,1 % | 13,9 % |
|  | Oktober | 48 % | 55,7 % | 32,7 % |
|  | November | 21 % | 22,2 % | 5,3 % |
| Birkenpilz | August | 8 % | 4,7 % | 0,0 % |
|  | September | 32 % | 25,3 % | 11,8 % |
|  | Oktober | 46 % | 55,5 % | 33,7 % |
|  | November | 8 % | 34,5 % | 11,0 % |
| Fichtenreizker | August | 7 % | 14,2 % | 4,8 % |
|  | September | 24 % | 40,2 % | 24,2 % |
|  | Oktober | 47 % | 51,0 % | 30,8 % |
|  | November | 19 % | 17,0 % | 4,2 % |
| Herbsttrompete | Juli | 6 % | 8,2 % | 0,0 % |
|  | August | 11 % | 7,0 % | 1,9 % |
|  | September | 16 % | 19,1 % | 11,8 % |
|  | Oktober | 47 % | 53,2 % | 33,2 % |
|  | November | 19 % | 27,4 % | 5,0 % |
| Pfifferling | Juni | 13 % | 38,7 % | 32,1 % |
|  | Juli | 13 % | 42,8 % | 37,6 % |
|  | August | 17 % | 39,7 % | 35,9 % |
|  | September | 24 % | 23,6 % | 17,9 % |
|  | Oktober | 20 % | 0,8 % | 0,5 % |
|  | November | 8 % | 1,1 % | 0,6 % |

**Im Oktober** — dem Monat mit dem meisten Material — sinkt der Anteil günstiger Tage im Median über 6 Arten von 53,6 % auf 32,7 %. Der Median und nicht der Durchschnitt, weil der Pfifferling im Oktober praktisch nie günstig steht und einen Schnitt nach unten zöge, der für keine Art gilt. Auf die 31 Oktobertage gerechnet: 16,6 grüne Tage vorher, 10,1 nachher — es fallen 6,5 weg. **Das ist die Zahl, an der entschieden wird.**


## Was die Zahlen sagen

**Die ausgelieferte Schwelle hält ihr Versprechen nicht.** Gegen die Tage gemessen, für die sie gelten soll — gleicher Ort, gleiche Zeit im Jahr, andere Jahre — steht die Ampel an 36,8 % der Saisontage auf günstig. Vorgesehen war 20 %, also etwa jeder fünfte Tag. Das ist das 1,8-fache,

**Die neue Schwelle stellt das Versprechen wieder her**, ohne eine Modellzahl anzufassen. Fenster, Breite und Regenkurve bleiben Zahl für Zahl, wie sie sind; es ändert sich nur, wo der Schnitt liegt.

**Was hier NICHT steht:** ob der Hinweis dadurch verlässlicher wird. Das wäre ein schwellenabhängiges Maß und ist auf dieser Scheibe gesperrt. Auf P3 gemessen bleibt der Hebel praktisch gleich — die Neukalibrierung ist eine Häufigkeitsentscheidung, keine Genauigkeitsverbesserung.


## Warum diese Scheibe erlaubt ist

**Schwelle und gepaarte AUC sind disjunkte Statistiken.** Die AUC ist rangbasiert: Sie zählt, wie oft der Fundtag seinen Kontrolltag schlägt, und kennt keine Schwelle. Eine aus P1 gezogene Schwelle kann deshalb keinen bisherigen und keinen künftigen AUC-Test berühren — es gibt hier keine Latte, kein Band, nichts zu bestehen. Beschrieben wird eine Verteilung, nicht ausgewählt.

Und P1 ist hier die richtige Scheibe: Die App steht heute, nicht 2012. Der P3-Bericht hat gemessen, dass die Zeitscheibe beim Pfifferling über ein Drittel des Sprungs ausmacht.

**Die Grenze dieser Erlaubnis** steht in `docs/pilzampel-pruefachsen.md` als Regel: Trefferquote, POD, FAR, TSS, Hebel, Fundtag-Anteil sind auf P1 gesperrt. Sobald ein Maß eine Schwelle benutzt, um Fundtage zu bewerten, entschiede die ausgelieferte Zahl mit, wie gut die Ampel aussieht. `verbiete_schwellenmass` bricht den Lauf ab, statt eine solche Zahl zu liefern.

## Vorlage, keine Übernahme

**Hier wird nichts übernommen.** Wie oft die Ampel „günstig“ sagen soll, ist eine Produktentscheidung und keine Messung. Diese Seite sagt nur, welche Zahl welches Verhalten trägt.

Wer sie übernimmt, ändert **vier Konstanten in `ampel_model.dart` und `tool/ampel_validate.py` zusammen** — die Spiegel-Regel gilt, und `verify_class_constants` bricht ab, sobald eine allein wandert.
