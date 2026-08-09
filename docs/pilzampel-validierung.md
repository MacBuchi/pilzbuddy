# Rückwärtsvalidierung der Pilzampel

Stand: 2026-08-09 · Erzeugt von `tool/ampel_validate.py` · Konzept: `docs/pilzampel-konzept.md`

Datenquellen: Fundmeldungen aus [GBIF](https://www.gbif.org) (nur CC0 1.0 und CC BY 4.0); Wetter-Rückrechnung mit Daten von [Open-Meteo](https://open-meteo.com) (CC BY 4.0, nicht-kommerzielle Nutzung — die Zusage dazu steht im README und im Konzeptpapier, entschieden 2026-08-08).

Die Bedingung aus dem Konzeptpapier, bevor eine Ampel gebaut wird:
**Steht das Modell an Fundtagen höher als an zufälligen Tagen
derselben Saison?** Diese Seite beantwortet das mit Zahlen.

## Wie gemessen wurde

Zu jeder Fundmeldung aus GBIF (Deutschland, ab 2006, taggenau, Ortsgenauigkeit besser als 1000 m) wird ein **Vergleichstag** am selben Ort im selben Jahr gezogen, 14–45 Tage daneben. Für beide Tage rechnet dasselbe Wettermodell einen Wert:

- Niederschlag über 26 Tage kumuliert, ältere Tage schwächer gewichtet
- Temperatur als Glocke um 13 °C (Mittel über 20 Tage)

**Der Saisonfaktor geht NICHT ein.** Er stammt aus denselben GBIF-Daten (`docs/pilzampel-saisonkurven.md`); ihn mitzurechnen hieße, das Modell mit sich selbst zu bestätigen. Weil Fund- und Vergleichstag wenige Wochen auseinanderliegen, ist die Jahreszeit für beide praktisch gleich — übrig bleibt das Wetter.

Die Kennzahl ist die **AUC**: Wie oft liegt der Fundtag über seinem Vergleichstag? 0,50 heißt zufällig, 1,00 hieße immer. Sie steht hier vor dem p-Wert, weil bei tausenden Paaren auch ein bedeutungsloser Unterschied „signifikant“ wird.

**Der Standort ist durch den Aufbau kontrolliert.** Fund- und Vergleichstag liegen am selben Ort — gleicher Wald, gleiche Baumart, gleicher Boden. Was einen Fichtenhang von einem Buchenhang unterscheidet, kann das Ergebnis also nicht beeinflussen; bei Holzbewohnern erklärt dieser Faktor sonst 56–59 % der Varianz (Alday/Karavani et al. 2017). Gefragt wird nur: Warum an DIESEM Tag und nicht drei Wochen später am selben Fleck?

## Placebo-Kontrolle: prüft die Methode

Zwei Vergleichstage treten gegeneinander an — beide ohne Fund, beide nach derselben Vorschrift gezogen. **Hier muss 0,50 stehen.** Alles andere hieße, dass schon die Ziehung verzerrt (etwa weil ein späterer Tag im Jahr systematisch feuchter ist) — und dann wäre jede Zahl in den Tabellen darunter wertlos.

| Art | Paare | AUC (soll ≈ 0,50) |
|---|--:|--:|
| Steinpilz | 461 | 0.514 |
| Maronenröhrling | 466 | 0.511 |
| Pfifferling | 479 | 0.509 |
| Birkenpilz | 472 | 0.468 |
| Fichtenreizker | 456 | 0.568 |
| Herbsttrompete | 276 | 0.475 |
| Hallimasch | 439 | 0.503 |
| Stockschwämmchen | 454 | 0.504 |
| Austernseitling | 283 | 0.452 |

## Mykorrhiza-Speisepilze — hier wird ein Effekt erwartet

| Art | Paare | AUC | Befund | p |
|---|--:|--:|---|--:|
| Steinpilz | 497 | 0.738 | deutlich | 0.0005 |
| Maronenröhrling | 495 | 0.729 | deutlich | 0.0005 |
| Pfifferling | 490 | 0.561 | schwach | 0.0045 |
| Birkenpilz | 499 | 0.727 | deutlich | 0.0005 |
| Fichtenreizker | 489 | 0.716 | deutlich | 0.0005 |
| Herbsttrompete | 296 | 0.655 | deutlich | 0.0005 |

## Arten-Kontrolle: Holzbewohner — hier darf DIESES Modell nicht passen

**Nicht, weil sie kein Wetter spüren.** Der Austernseitling ist ein Kältefrüchter mit Gipfel im Dezember; er reagiert sehr wohl, nur auf anderes. Geprüft wird enger: Das hier gerechnete Modell — Glocke um 13 °C und 26-Tage-Regensumme, beides aus der Steinpilz-Literatur — darf bei ihnen nicht passen. Ein Wert **unter** 0,50 ist deshalb kein Fehlschlag, sondern ein Beleg: Das Modell wirkt artspezifisch und misst nicht bloß „im Herbst wird mehr gemeldet“.

| Art | Paare | AUC | Befund | p |
|---|--:|--:|---|--:|
| Hallimasch | 491 | 0.735 | deutlich | 0.0005 |
| Stockschwämmchen | 486 | 0.730 | deutlich | 0.0005 |
| Austernseitling | 314 | 0.481 | kein Effekt | 0.7461 |
