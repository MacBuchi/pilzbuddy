# Die Bodenfeuchte — die Spalte, die zwei Tage lang dalag

Stand: 2026-09-19 · Erzeugt von `tool/ampel_diagnose.py --boden` · Betreiberfrage vom 2026-09-19

> **Diese Datei wird erzeugt.** Wer sie von Hand ändert, verliert die Änderung beim nächsten Lauf.

> **P3 sind die Anpassjahre.** Jede Zahl hier ist eine Diagnose und kein Beleg.

## Warum das eine naheliegende Frage ist

Die Ampel rechnet eine gewichtete **Regensumme** über 26 Tage — einen Stellvertreter für das, was beim Myzel ankommt. Die Bodenfeuchte in 7 bis 28 cm Tiefe **ist** diese Größe, und zwar schon integriert: Versickerung, Verdunstung und Vorgeschichte stecken darin, ohne dass jemand eine Gewichtskurve setzen muss.

Für den Vergleich unten muss nichts geeicht werden: Das B-Maß ist rangbasiert, jede monotone Umformung lässt es unverändert. Verglichen wird also die **rohe** Bodenfeuchte gegen den fertigen Regenfaktor der App — kein Handicap für die App, eher eines für die Bodenfeuchte.

**Eine Einschränkung, die man dabei nicht übersehen darf.** Für die erste Spalte gilt die Rang-Unempfindlichkeit; für eine ausgelieferte Ampel nicht. Dort werden Feuchte und Glocke **multipliziert**, und ein Produkt hängt sehr wohl an der Skala seiner Faktoren — der Regenfaktor sättigt bei 87 mm, die rohe Bodenfeuchte sättigt nirgends. Genau deshalb steht die letzte Spalte unten nicht überall dort vorn, wo die Bodenfeuchte-Spalte vorn steht. Eine Ampel auf Bodenfeuchte bräuchte also **eine eigene Übertragungskurve** — eine neue Konstante, gesetzt oder angepasst. Der Gewinn wäre dann nicht „eine Konstante weniger“, sondern eine bessere Eingangsgröße.

## Was die Spalten heißen

- **Regen**: der ausgelieferte Regenfaktor allein, 26 Tage gewichtet.
- **Boden 1/7/14/26 d**: das Mittel der Bodenfeuchte über so viele Tage vor dem Tag, sonst nichts.
- **voll**: die ausgelieferte Ampel (Regen × Glocke).
- **Boden × Glocke**: dieselbe Formel mit getauschtem Feuchtemaß, bestes Fenster.

| Art | Funde | Regen | Boden 1 d | Boden 7 d | Boden 14 d | Boden 26 d | Temperatur | voll | Boden × Glocke |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| Steinpilz | 951 | **0.609** | 0.611 | 0.614 | 0.616 | 0.600 | 0.625 | **0.647** | 0.640 |
| Maronenröhrling | 886 | **0.601** | 0.631 | 0.638 | 0.641 | 0.627 | 0.610 | **0.634** | 0.643 |
| Birkenpilz | 621 | **0.604** | 0.617 | 0.617 | 0.606 | 0.593 | 0.617 | **0.627** | 0.627 |
| Fichtenreizker | 397 | **0.591** | 0.630 | 0.632 | 0.640 | 0.638 | 0.623 | **0.642** | 0.651 |
| Herbsttrompete ⚠ | 147 | **0.658** | 0.735 | 0.758 | 0.766 | 0.769 | 0.692 | **0.695** | 0.759 |
| Pfifferling | 716 | **0.632** | 0.660 | 0.662 | 0.669 | 0.662 | 0.512 | **0.629** | 0.620 |

⚠ unter 150 Funden — die Zeile steht zur Vollständigkeit da und trägt kein eigenes Urteil.

## Was daraus folgt

**Bei 6 von 6 Arten trennt die rohe Bodenfeuchte besser als der ausgelieferte Regenfaktor**, und bei 4 von 6 schlägt „Bodenfeuchte × Glocke“ die ausgelieferte Ampel.

Welches Fenster je Art das beste ist: 1 d bei 1 Art, 7 d bei 1 Art, 14 d bei 4 Arten, 26 d bei 1 Art.

Ein an denselben Daten ausgesuchtes Fenster ist keine Messung — die Spalten stehen alle da, damit sichtbar ist, wie wenig die Wahl ausmacht.

**Das ist eine Diagnose und kein Beleg.** Die Fensterlänge ist hier an denselben Daten ausgesucht worden, auf denen sie bewertet wird — wer eine davon ausliefern will, braucht eine Registrierung mit EINEM eingefrorenen Fenster und eine Prüfachse. Die Zahlen oben sagen nur, ob sich das lohnt.

**Was hier noch nicht steht:** die Bodentemperatur (`soil_temperature_0_to_7cm`) liegt ebenso vollständig im Cache. Sie mit der Luft-Glocke zu bewerten wäre falsch — die Niveaus sind verschieden, das Optimum müsste neu bestimmt werden. Die Temperaturspalte oben ist die der Luft.
