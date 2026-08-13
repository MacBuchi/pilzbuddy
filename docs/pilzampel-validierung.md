# Rückwärtsvalidierung der Pilzampel

Stand: 2026-08-13 · Erzeugt von `tool/ampel_validate.py` · Konzept: `docs/pilzampel-konzept.md`

Datenquellen: Fundmeldungen aus [GBIF](https://www.gbif.org) (nur CC0 1.0 und CC BY 4.0); Wetter-Rückrechnung mit Daten von [Open-Meteo](https://open-meteo.com) (CC BY 4.0, nicht-kommerzielle Nutzung — die Zusage dazu steht im README und im Konzeptpapier, entschieden 2026-08-08).

Die Bedingung aus dem Konzeptpapier, bevor eine Ampel gebaut wird:
**Steht das Modell an Fundtagen höher als an zufälligen Tagen
derselben Saison?** Diese Seite beantwortet das mit Zahlen.

## Wie gemessen wurde

Zu jeder Fundmeldung aus GBIF (Deutschland, 2006–2025, taggenau, Ortsgenauigkeit besser als 1000 m) wird ein **Vergleichstag** am selben Ort im selben Jahr gezogen, 14–45 Tage daneben. Für beide Tage rechnet dasselbe Wettermodell einen Wert:

**Das laufende Jahr 2026 zählt nicht mit.** Seine Saison ist noch nicht vorbei, und ein halbes Pilzjahr wäre genau die Lücke, die hier sonst überall zum Abbruch führt — Pilzjahre unterscheiden sich um den Faktor zehn. Die Spalte „Jahre“ nennt deshalb nur die vollständigen.

- Niederschlag über 26 Tage kumuliert, ältere Tage schwächer gewichtet
- Temperatur als Glocke um 13 °C (Mittel über 20 Tage)

**Der Saisonfaktor geht NICHT ein.** Er stammt aus denselben GBIF-Daten (`docs/pilzampel-saisonkurven.md`); ihn mitzurechnen hieße, das Modell mit sich selbst zu bestätigen. Weil Fund- und Vergleichstag wenige Wochen auseinanderliegen, ist die Jahreszeit für beide praktisch gleich — übrig bleibt das Wetter.

Die Kennzahl ist die **AUC**: Wie oft liegt der Fundtag über seinem Vergleichstag? 0,50 heißt zufällig, 1,00 hieße immer. Sie steht hier vor dem p-Wert, weil bei tausenden Paaren auch ein bedeutungsloser Unterschied „signifikant“ wird.

**Der Standort ist durch den Aufbau kontrolliert.** Fund- und Vergleichstag liegen am selben Ort — gleicher Wald, gleiche Baumart, gleicher Boden. Was einen Fichtenhang von einem Buchenhang unterscheidet, kann das Ergebnis also nicht beeinflussen; bei Holzbewohnern erklärt dieser Faktor sonst 56–59 % der Varianz (Alday/Karavani et al. 2017). Gefragt wird nur: Warum an DIESEM Tag und nicht drei Wochen später am selben Fleck?

## Placebo-Kontrolle: prüft die Methode

Zwei Vergleichstage treten gegeneinander an — beide ohne Fund, beide nach derselben Vorschrift gezogen. **Hier muss 0,50 stehen.** Alles andere hieße, dass schon die Ziehung verzerrt (etwa weil ein späterer Tag im Jahr systematisch feuchter ist) — und dann wäre jede Zahl in den Tabellen darunter wertlos.

| Art | Paare | AUC (soll ≈ 0,50) |
|---|--:|--:|
| Steinpilz | 1923 | 0.502 |
| Maronenröhrling | 1882 | 0.499 |
| Pfifferling | 1312 | 0.512 |
| Birkenpilz | 1162 | 0.491 |
| Fichtenreizker | 736 | 0.493 |
| Herbsttrompete | 276 | 0.475 |
| Hallimasch | 1838 | 0.518 |
| Stockschwämmchen | 1213 | 0.509 |
| Austernseitling | 916 | 0.539 |

## Mykorrhiza-Speisepilze — hier wird ein Effekt erwartet

| Art | Paare | AUC | Befund | p |
|---|--:|--:|---|--:|
| Steinpilz | 1996 | 0.730 | deutlich | 0.0005 |
| Maronenröhrling | 1980 | 0.709 | deutlich | 0.0005 |
| Pfifferling | 1336 | 0.572 | schwach | 0.0005 |
| Birkenpilz | 1202 | 0.709 | deutlich | 0.0005 |
| Fichtenreizker | 772 | 0.706 | deutlich | 0.0005 |
| Herbsttrompete | 296 | 0.655 | deutlich | 0.0005 |

## Arten-Kontrolle: Holzbewohner — hier darf DIESES Modell nicht passen

**Nicht, weil sie kein Wetter spüren.** Der Austernseitling ist ein Kältefrüchter mit Gipfel im Dezember; er reagiert sehr wohl, nur auf anderes. Geprüft wird enger: Das hier gerechnete Modell — Glocke um 13 °C und 26-Tage-Regensumme, beides aus der Steinpilz-Literatur — darf bei ihnen nicht passen. Ein Wert **unter** 0,50 ist deshalb kein Fehlschlag, sondern ein Beleg: Das Modell wirkt artspezifisch und misst nicht bloß „im Herbst wird mehr gemeldet“.

| Art | Paare | AUC | Befund | p |
|---|--:|--:|---|--:|
| Hallimasch | 1966 | 0.718 | deutlich | 0.0005 |
| Stockschwämmchen | 1282 | 0.704 | deutlich | 0.0005 |
| Austernseitling | 1009 | 0.465 | kein Effekt | 0.9895 |

**Ergebnis dieser Kontrolle:** 2 von 3 Holzbewohnern passen zum Modell (AUC ≥ 0,55) — Hallimasch 0.718, Stockschwämmchen 0.704. Die Kontrolle ist damit NICHT bestanden: Das Modell trennt hier nicht nach Gilde. Zwei Lesarten passen gleich gut — es misst allgemeines Pilzwetter statt etwas Artspezifisches, oder diese Arten teilen schlicht dasselbe Fenster und taugen nicht als Gegenprobe. Diese Daten trennen das nicht. **Solange das offen ist, bleibt eine Ampel je Art unbegründet** — ihre Voraussetzung ist genau der Unterschied, der hier nicht sichtbar wird.
