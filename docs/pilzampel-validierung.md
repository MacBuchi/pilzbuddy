# Rückwärtsvalidierung der Pilzampel

Stand: 2026-09-12 · Erzeugt von `tool/ampel_validate.py` · Konzept: `docs/pilzampel-konzept.md`

Datenquellen: Fundmeldungen aus [GBIF](https://www.gbif.org) (nur CC0 1.0 und CC BY 4.0); Wetter-Rückrechnung mit Daten von [Open-Meteo](https://open-meteo.com) (CC BY 4.0, nicht-kommerzielle Nutzung — die Zusage dazu steht im README und im Konzeptpapier, entschieden 2026-08-08).

Die Bedingung aus dem Konzeptpapier, bevor eine Ampel gebaut wird:
**Steht das Modell an Fundtagen höher als an zufälligen Tagen
derselben Saison?** Diese Seite beantwortet das mit Zahlen.

## Wie gemessen wurde

Zu jeder Fundmeldung aus GBIF (Deutschland, 2006–2025, taggenau, Ortsgenauigkeit besser als 1000 m) wird ein **Vergleichstag** am selben Ort im selben Jahr gezogen, 26–45 Tage daneben. Für beide Tage rechnet dasselbe Wettermodell einen Wert:

**Das laufende Jahr 2026 zählt nicht mit.** Seine Saison ist noch nicht vorbei, und ein halbes Pilzjahr wäre genau die Lücke, die hier sonst überall zum Abbruch führt — Pilzjahre unterscheiden sich um den Faktor zehn. Die Spalte „Jahre“ nennt deshalb nur die vollständigen.

- Niederschlag über 26 Tage kumuliert, ältere Tage schwächer gewichtet
- Temperatur als Glocke um 13 °C (Mittel über 20 Tage)

**Der Saisonfaktor geht NICHT ein.** Er stammt aus denselben GBIF-Daten (`docs/pilzampel-saisonkurven.md`); ihn mitzurechnen hieße, das Modell mit sich selbst zu bestätigen. Weil Fund- und Vergleichstag wenige Wochen auseinanderliegen, ist die Jahreszeit für beide praktisch gleich — übrig bleibt das Wetter.

Die Kennzahl ist die **AUC**: Wie oft liegt der Fundtag über seinem Vergleichstag? 0,50 heißt zufällig, 1,00 hieße immer. Sie steht hier vor dem p-Wert, weil bei tausenden Paaren auch ein bedeutungsloser Unterschied „signifikant“ wird.

**Der Standort ist durch den Aufbau kontrolliert.** Fund- und Vergleichstag liegen am selben Ort — gleicher Wald, gleiche Baumart, gleicher Boden. Was einen Fichtenhang von einem Buchenhang unterscheidet, kann das Ergebnis also nicht beeinflussen; bei Holzbewohnern erklärt dieser Faktor sonst 56–59 % der Varianz (Alday/Karavani et al. 2017). Gefragt wird nur: Warum an DIESEM Tag und nicht drei Wochen später am selben Fleck?

## Kontrollen: prüfen die Methode

Zwei Tage OHNE Fund treten gegeneinander an. **Hier muss 0,50 stehen.** Alles andere hieße, dass schon die Ziehung verzerrt — und dann wäre jede Zahl in den Tabellen darunter wertlos.

Es sind zwei, und sie fangen Verschiedenes.

**Die abstandsgleiche Kontrolle entscheidet** (seit 2026-09-12): der Vergleichstag gegen seine Spiegelung am Fundtag. Beide liegen exakt gleich weit weg, nur auf verschiedenen Seiten.

**Die gepaarte Kontrolle steht daneben**: der Vergleichstag gegen einen VON IHM AUS gezogenen dritten Tag. Sie war bis 2026-09-12 der Torwächter und taugt dafür nicht, weil ihre beiden Tage unterschiedlich weit vom Fundtag entfernt liegen — die Abstände addieren sich. Und Nähe zum Fundtag hebt den Wert, weil Pilze bei gutem Wetter kommen und gutes Wetter Wochen anhält. Sie misst damit auch Abstand, nicht nur Verzerrung. Behalten wird sie trotzdem: Sie fängt eine EINSEITIGE Ziehung, was die abstandsgleiche bauartbedingt nicht kann.

Die Spalte „Rauschen“ ist der Standardfehler bei dieser Paarzahl (rund 1/(2·√n)). Eine Abweichung, die kleiner ist als das Doppelte davon, ist von Zufall nicht zu unterscheiden — sie wird trotzdem markiert, nicht wegerklärt.

| Art | Paare | abstandsgleich (soll ≈ 0,50) | Rauschen | gepaart |
|---|--:|--:|--:|--:|
| Steinpilz | 1982 | 0.510 | ±0.011 | 0.451 |
| Maronenröhrling | 1953 | 0.515 | ±0.011 | 0.495 |
| Pfifferling | 1315 | 0.512 | ±0.014 | 0.525 |
| Birkenpilz | 1201 | 0.506 | ±0.014 | 0.462 |
| Fichtenreizker | 757 | 0.506 | ±0.018 | 0.490 |
| Herbsttrompete | 291 | 0.457 ⚠ | ±0.029 | 0.512 |
| Hallimasch | 1914 | 0.511 | ±0.011 | 0.497 |
| Stockschwämmchen | 1231 | 0.479 | ±0.014 | 0.453 |
| Austernseitling | 675 | 0.484 | ±0.019 | 0.509 |

**Nicht auswertbar sind damit: Herbsttrompete (0.457, ±0.029).** Für alle übrigen Arten hält die Kontrolle, und ihre Zahlen stehen.


## Mykorrhiza-Speisepilze — hier wird ein Effekt erwartet

| Art | Paare | AUC | Befund | p |
|---|--:|--:|---|--:|
| Steinpilz | 1990 | 0.762 | deutlich | 0.0005 |
| Maronenröhrling | 1974 | 0.743 | deutlich | 0.0005 |
| Pfifferling | 1332 | 0.607 | erkennbar | 0.0005 |
| Birkenpilz | 1203 | 0.743 | deutlich | 0.0005 |
| Fichtenreizker | 765 | 0.739 | deutlich | 0.0005 |
| Herbsttrompete | 294 | 0.684 | deutlich | 0.0005 |

## Arten-Kontrolle: Holzbewohner — hier darf DIESES Modell nicht passen

**Nicht, weil sie kein Wetter spüren.** Der Austernseitling ist ein Kältefrüchter mit Gipfel im Dezember; er reagiert sehr wohl, nur auf anderes. Geprüft wird enger: Das hier gerechnete Modell — Glocke um 13 °C und 26-Tage-Regensumme, beides aus der Steinpilz-Literatur — darf bei ihnen nicht passen. Ein Wert **unter** 0,50 ist deshalb kein Fehlschlag, sondern ein Beleg: Das Modell wirkt artspezifisch und misst nicht bloß „im Herbst wird mehr gemeldet“.

| Art | Paare | AUC | Befund | p |
|---|--:|--:|---|--:|
| Hallimasch | 1953 | 0.749 | deutlich | 0.0005 |
| Stockschwämmchen | 1277 | 0.756 | deutlich | 0.0005 |
| Austernseitling | 987 | 0.463 | kein Effekt | 0.9940 |

**Ergebnis dieser Kontrolle:** 2 von 3 Holzbewohnern passen zum Modell (AUC ≥ 0,55) — Hallimasch 0.749, Stockschwämmchen 0.756. Nach dem Kriterium dieser Seite ist die Kontrolle damit NICHT bestanden: Hier trennt das Modell nicht nach Gilde.

**Entschieden ist das seit dem 2026-09-12 trotzdem** — nur nicht auf dieser Seite. Die Anpassung je Art (`docs/pilzampel-artenfenster-messung.md`) zeigt, dass die Kontrolle an ihrer AUSWAHL scheiterte: Hallimasch und Stockschwämmchen teilen schlicht das Herbstfenster, während der Austernseitling ein eigenes, kaltes hat. Das Modell wirkt artspezifisch; man muss nur Arten vergleichen, die sich wirklich unterscheiden.

**Eine Ampel je ART bleibt dennoch unbegründet**, jetzt aus dem umgekehrten Grund: Die Herbstarten liegen alle beieinander, und ein eigenes Fenster bringt ihnen nichts. Was die Daten stützen, ist eine Unterscheidung nach TYP.
