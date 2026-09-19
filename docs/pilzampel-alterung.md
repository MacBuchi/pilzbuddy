# Altert die Glocke? — die Anpassjahre geteilt

Stand: 2026-09-19 · Erzeugt von `tool/ampel_diagnose.py --zerlegung
--jahre 2006-2012` bzw. `--jahre 2013-2018` · Betreiberfrage vom
2026-09-19

**Der Anlass.** Die Vorprüfung zu H5 hat einen Nebenbefund gelassen: Die
Glocke trennt auf den Anpassjahren mit 0,61–0,69 und auf den Prüfjahren
nur noch mit 0,56–0,59, während der Regen stabil bleibt. Nur eine Größe
altert, und es ist die, die angepasst wurde.

Diese Frage lässt sich stellen, **ohne eine Achse anzufassen**: Man
teilt die Anpassjahre selbst. Altert die Glocke schon dort, ist es eine
Eigenschaft des Fensters. Bleibt sie stabil, liegt der Unterschied an
den Prüfjahren.

---

## Gemessen

Dieselbe Zerlegung, drei Zeitscheiben. Die fünf Herbstarten:

| Art | \|  | nur Temperatur | | | \|  | nur Regen | | |
|---|---|--:|--:|--:|---|--:|--:|--:|
| | | 2006–12 | 2013–18 | 2019–25 | | 2006–12 | 2013–18 | 2019–25 |
| Steinpilz | | 0.608 | **0.633** | 0.582 | | 0.582 | 0.622 | 0.646 |
| Maronenröhrling | | 0.583 | **0.623** | 0.577 | | 0.597 | 0.604 | 0.592 |
| Birkenpilz | | 0.582 | **0.635** | 0.582 | | 0.600 | 0.607 | 0.596 |
| Fichtenreizker | | 0.600 | **0.635** | 0.588 | | 0.554 | 0.608 | 0.593 |
| Herbsttrompete ⚠ | | 0.606 | **0.717** | 0.563 | | 0.615 | 0.670 | 0.587 |
| **Mittel ohne ⚠** | | 0.593 | **0.632** | 0.582 | | 0.583 | 0.610 | 0.607 |

⚠ Die Herbsttrompete hat in der ersten Scheibe **33 Funde**. Ihre Zeile
steht zur Vollständigkeit da und trägt nichts.

Funde je Scheibe zum Vergleich: Steinpilz 301 / 650 / 1041.

## Die Antwort: nein, die Glocke altert nicht

**Innerhalb der Anpassjahre wird sie stärker, nicht schwächer.** Bei
allen fünf Herbstarten steigt die Trennschärfe der Temperatur von der
ersten zur zweiten Hälfte, im Mittel von 0,593 auf 0,632. Ein
gleichmäßiges Nachlassen sähe anders aus.

**Der Einbruch liegt ausschließlich in den Prüfjahren.** Von 2013–18 auf
2019–25 fällt die Temperatur um **0,050** (0,632 → 0,582), während der
Regen mit 0,610 → 0,607 praktisch steht. Das ist die Trennung, nach der
gefragt war: Es ist keine Eigenschaft des Fensters, sondern etwas an
2019–2025.

**Eine Korrektur am eigenen Nebenbefund.** In der Vorprüfung stand, der
Regen bleibe „in beiden Scheiben stabil". Über die geteilten
Anpassjahre stimmt das nur für die zweite Hälfte: Von 2006–12 auf
2013–18 steigt auch der Regen, von 0,583 auf 0,610. Beide Größen sind in
der ersten Scheibe schwächer. Was die zweite von der dritten Scheibe
unterscheidet, ist dagegen wirklich die Temperatur allein.

## Was als Erklärung übrig bleibt

**Ein Rest der Messbasis ist ausgeschlossen, und zwar von der
Konstruktion her.** Gerechnet wird auf `pinned` — ERA5-Land für
Temperatur und Boden, ERA5 für Niederschlag, über alle zwanzig Jahre
dasselbe Instrument. Die Naht der Vorgabe lag auf dem 1. Januar 2017 und
ist hier nicht vorhanden (`docs/pilzampel-messbasis.md`). Wäre sie es,
läge sie ohnehin **mitten in der zweiten Scheibe** und nicht zwischen
zweiter und dritter.

Damit bleiben zwei Möglichkeiten, und dieser Aufbau kann sie nicht
trennen:

1. **Echte Veränderung.** Wärmere, trockenere Spätsommer verschieben die
   Fundtage aus dem Fenster heraus. Dazu passen zwei ältere Befunde: der
   Richtungs-Split aus N4 (spätere Kontrolljahre sind leichter zu
   schlagen, bei neun von elf Arten) und das Altern der Schwellen —
   dieselbe 0,5 wurde vor 2019 an rund 30 % der Vergleichstage
   überschritten, seither an rund 20 %.
2. **Etwas an den Meldungen selbst.** Der Melderkreis, die Genauigkeit
   der Datierung und der Anteil app-gestützter Meldungen haben sich seit
   2019 verändert. Die Temperatur hängt am Datum schärfer als der Regen
   — ein 20-Tage-Mittel verschiebt sich mit einem falsch datierten Fund
   stärker als eine 26-Tage-Summe.

## Warum es hier endet

**Jede Vertiefung benutzt die Prüfjahre.** Der Vergleich zweite gegen
dritte Scheibe IST P1; eine Hypothese daraus entstünde wieder dort, wo
sie geprüft werden wollte — genau der Fehler, den die Vorprüfung
abfangen sollte, eine Ebene höher
(`docs/pilzampel-pruefachsen.md`).

Der offene Faden ist damit zu Ende gezogen, soweit die vorhandenen Daten
reichen. Was ihn weiterführen könnte, sind **andere Daten**: mehr
Winter, oder Begehungen mit „nichts gefunden" aus der App selbst (#199)
— eine Stichprobe, in der Abwesenheit wirklich Abwesenheit heißt und
nicht „niemand war da".

## Was das für die App heißt

**Nichts, heute.** Die Ampel ist für die Prüfjahre nicht kaputt: Die
sechs ausgelieferten Arten stehen dort mit einer vollen B-AUC von 0,63
bis 0,70 und liegen +0,054 bis +0,116 über ihrer artgematchten Referenz
(`docs/pilzampel-kontrolldesign.md`). Was nachlässt, ist der **Beitrag
der Temperatur**, nicht die Ampel.

Wer es eines Tages anfasst, sollte es an der Schwelle tun und nicht am
Fenster: Die Schwellen sind gemessen und altern nachweislich
(`docs/pilzampel-schwellen-messung.md`), das Fenster ist ein
Literaturwert und hat drei Angriffe überstanden
(`docs/pilzampel-formel.md`).
