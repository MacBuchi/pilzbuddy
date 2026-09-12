# Ampel-Vergleich: Stufen statt Rangfolge

Stand: 2026-09-12 · Erzeugt von `tool/ampel_validate.py --compare` · Messung: `docs/pilzampel-artenfenster-messung.md`

Die Rückwärtsvalidierung misst eine **Rangfolge** (AUC). Die App zeigt **drei Stufen**, und wo sie liegen, entscheiden zwei gesetzte Zahlen: ab 0.2 „verhalten", ab 0.5 „günstig". Diese Seite fragt deshalb das, was die AUC nicht beantwortet: **Sähe jemand überhaupt etwas anderes?**

Gerechnet auf den Prüfjahren (ab 2019), je Art auf Fund- UND Vergleichstagen.

## Wie oft die Stufe wechselt

| Art | Optimum | Tage | andere Stufe |
|---|--:|--:|--:|
| Steinpilz | 14.0 °C | 2120 | **18.1 %** |
| Maronenröhrling | 12.5 °C | 2244 | **9.0 %** |
| Pfifferling | 19.2 °C | 1228 | **70.0 %** |
| Birkenpilz | 14.5 °C | 1138 | **29.0 %** |
| Fichtenreizker | 12.5 °C | 754 | **9.7 %** |
| Herbsttrompete | 13.2 °C | 292 | **4.8 %** |
| Hallimasch | 10.8 °C | 2078 | **29.2 %** |
| Stockschwämmchen | 12.5 °C | 1388 | **8.1 %** |
| Austernseitling | -1.8 °C | 1294 | **57.0 %** |

## Trennt die neue Stufe besser?

„Günstig" soll an Fundtagen häufiger stehen als an Vergleichstagen. Der **Abstand** dieser beiden Anteile ist, was die Stufe wert ist.

| Art | günstig an Fundtagen | an Vergleichstagen | Abstand | Gewinn (95 %) |
|---|--:|--:|--:|--:|
| Steinpilz | 58.1 → **57.8 %** | 26.1 → **25.4 %** | +32.0 → **+32.5 pp** | +0.5 [-3.4, +4.7] |
| Maronenröhrling | 52.5 → **52.5 %** | 25.4 → **25.4 %** | +27.1 → **+27.1 pp** | +0.0 [-1.5, +2.1] |
| Pfifferling | 37.5 → **46.4 %** | 28.5 → **29.8 %** | +9.0 → **+16.6 pp** | +7.7 [+0.4, +14.8] |
| Birkenpilz | 51.7 → **51.3 %** | 23.9 → **21.6 %** | +27.8 → **+29.7 pp** | +1.9 [-6.9, +9.4] |
| Fichtenreizker | 56.0 → **57.6 %** | 27.1 → **27.1 %** | +28.9 → **+30.5 pp** | +1.6 [-1.7, +4.9] |
| Herbsttrompete | 41.8 → **42.5 %** | 22.6 → **23.3 %** | +19.2 → **+19.2 pp** | -0.0 [-2.2, +1.9] |
| Hallimasch | 54.1 → **62.3 %** | 26.9 → **25.0 %** | +27.1 → **+37.2 pp** | +10.1 [+3.6, +17.2] |
| Stockschwämmchen | 49.7 → **51.6 %** | 25.4 → **25.9 %** | +24.4 → **+25.6 pp** | +1.3 [-1.6, +4.2] |
| Austernseitling | 21.3 → **3.2 %** | 21.5 → **2.8 %** | -0.2 → **+0.5 pp** | +0.6 [-5.0, +5.9] |

## Und dasselbe für „mindestens verhalten"

| Art | an Fundtagen | an Vergleichstagen | Abstand | Gewinn (95 %) |
|---|--:|--:|--:|--:|
| Steinpilz | 89.4 → **90.7 %** | 55.6 → **60.4 %** | +33.9 → **+30.3 pp** | -3.6 [-4.4, -2.9] |
| Maronenröhrling | 87.1 → **86.1 %** | 55.1 → **53.3 %** | +32.0 → **+32.8 pp** | +0.8 [-0.9, +2.4] |
| Pfifferling | 76.2 → **73.6 %** | 62.1 → **57.3 %** | +14.2 → **+16.3 pp** | +2.1 [-5.7, +9.5] |
| Birkenpilz | 88.2 → **92.8 %** | 56.6 → **61.3 %** | +31.6 → **+31.5 pp** | -0.2 [-6.5, +6.1] |
| Fichtenreizker | 85.1 → **84.1 %** | 56.2 → **54.4 %** | +28.9 → **+29.7 pp** | +0.8 [-1.4, +3.5] |
| Herbsttrompete | 79.5 → **80.1 %** | 53.4 → **55.5 %** | +26.0 → **+24.7 pp** | -1.4 [-4.2, +1.3] |
| Hallimasch | 89.4 → **91.2 %** | 52.2 → **52.8 %** | +37.2 → **+38.4 pp** | +1.2 [-3.0, +5.5] |
| Stockschwämmchen | 83.1 → **82.6 %** | 55.5 → **53.6 %** | +27.7 → **+29.0 pp** | +1.3 [-1.0, +2.8] |
| Austernseitling | 45.7 → **12.7 %** | 45.9 → **9.6 %** | -0.2 → **+3.1 pp** | +3.2 [-4.6, +11.4] |

## Was daraus folgt

**Sichtbar besser wird es bei: Pfifferling (19.2 °C, +7.7 pp), Hallimasch (10.8 °C, +10.1 pp).** Bei allen übrigen enthält der Vertrauensbereich die Null — ihr eigenes Fenster ändert für die Nutzerin nichts, auch wenn die AUC sich rührt.

**Und bei Austernseitling verschwindet „günstig“ fast ganz** (21.3 % → 3.2 % an Fundtagen).

Das ist kein Fehler der Anpassung, sondern der Schwellen: 0.2 und 0.5 sind für eine 13-°C-Glocke gesetzt. Verschiebt man das Optimum, verschiebt sich die ganze Werteverteilung mit, und dieselben Zahlen bedeuten etwas anderes. **Ein eigenes Fenster ohne eigene Schwellen macht die Ampel dunkel, nicht besser** — und in einer Anzeige „günstig, sobald eine Klasse günstig steht“ käme eine solche Klasse nie zum Zug.

Die Schwellen sind damit kein Umsetzungsdetail, sondern Teil des Modells. Sie stehen bis heute als „GESETZT, nicht gemessen“ in `ampel_model.dart`, und diese Seite ist die erste Messung, die sie überhaupt anfasst.

