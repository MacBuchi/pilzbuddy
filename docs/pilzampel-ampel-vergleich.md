# Ampel-Vergleich: Stufen statt Rangfolge

Stand: 2026-09-12 · Erzeugt von `tool/ampel_validate.py --compare` · Messung: `docs/pilzampel-artenfenster-messung.md`

Die Rückwärtsvalidierung misst eine **Rangfolge** (AUC). Die App zeigt **drei Stufen**, und wo sie liegen, entscheiden zwei gesetzte Zahlen: ab 0.2 „verhalten", ab 0.5 „günstig". Diese Seite fragt deshalb das, was die AUC nicht beantwortet: **Sähe jemand überhaupt etwas anderes?**

Gerechnet auf den Prüfjahren (ab 2019), je Art auf Fund- UND Vergleichstagen.

## Wie oft die Stufe wechselt

| Art | Optimum | Tage | andere Stufe |
|---|--:|--:|--:|
| Steinpilz | 13.0 °C | 2108 | **0.0 %** |
| Maronenröhrling | 13.0 °C | 2236 | **0.0 %** |
| Pfifferling | 17.5 °C | 1220 | **65.5 %** |
| Birkenpilz | 14.5 °C | 1140 | **28.1 %** |
| Fichtenreizker | 12.0 °C | 746 | **15.8 %** |
| Herbsttrompete | 13.0 °C | 288 | **0.0 %** |
| Hallimasch | 11.0 °C | 2058 | **28.0 %** |
| Stockschwämmchen | 12.2 °C | 1372 | **13.3 %** |
| Austernseitling | -3.2 °C | 1264 | **50.2 %** |

## Trennt die neue Stufe besser?

„Günstig" soll an Fundtagen häufiger stehen als an Vergleichstagen. Der **Abstand** dieser beiden Anteile ist, was die Stufe wert ist.

| Art | günstig an Fundtagen | an Vergleichstagen | Abstand | Gewinn (95 %) |
|---|--:|--:|--:|--:|
| Steinpilz | 58.4 → **58.4 %** | 20.3 → **20.3 %** | +38.1 → **+38.1 pp** | +0.0 [+0.0, +0.0] |
| Maronenröhrling | 52.6 → **52.6 %** | 20.3 → **20.3 %** | +32.3 → **+32.3 pp** | +0.0 [+0.0, +0.0] |
| Pfifferling | 37.7 → **56.1 %** | 25.4 → **37.2 %** | +12.3 → **+18.9 pp** | +6.6 [-4.0, +16.6] |
| Birkenpilz | 51.6 → **51.2 %** | 18.9 → **18.4 %** | +32.6 → **+32.8 pp** | +0.2 [-6.7, +5.8] |
| Fichtenreizker | 56.6 → **58.2 %** | 25.5 → **23.9 %** | +31.1 → **+34.3 pp** | +3.2 [-2.1, +9.4] |
| Herbsttrompete | 42.4 → **42.4 %** | 19.4 → **19.4 %** | +22.9 → **+22.9 pp** | +0.0 [+0.0, +0.0] |
| Hallimasch | 54.5 → **62.0 %** | 17.8 → **14.2 %** | +36.7 → **+47.8 pp** | +11.1 [+4.8, +17.9] |
| Stockschwämmchen | 50.3 → **52.2 %** | 16.2 → **14.9 %** | +34.1 → **+37.3 pp** | +3.2 [+0.7, +6.0] |
| Austernseitling | 21.7 → **1.1 %** | 21.8 → **0.6 %** | -0.2 → **+0.5 pp** | +0.6 [-6.3, +6.6] |

## Und dasselbe für „mindestens verhalten"

| Art | an Fundtagen | an Vergleichstagen | Abstand | Gewinn (95 %) |
|---|--:|--:|--:|--:|
| Steinpilz | 90.1 → **90.1 %** | 47.4 → **47.4 %** | +42.7 → **+42.7 pp** | +0.0 [+0.0, +0.0] |
| Maronenröhrling | 87.2 → **87.2 %** | 48.5 → **48.5 %** | +38.7 → **+38.7 pp** | +0.0 [+0.0, +0.0] |
| Pfifferling | 76.7 → **83.3 %** | 62.8 → **63.0 %** | +13.9 → **+20.3 pp** | +6.4 [-0.4, +11.4] |
| Birkenpilz | 88.1 → **92.6 %** | 48.2 → **54.7 %** | +39.8 → **+37.9 pp** | -1.9 [-6.0, +2.2] |
| Fichtenreizker | 86.1 → **83.6 %** | 50.9 → **48.0 %** | +35.1 → **+35.7 pp** | +0.5 [-2.3, +3.8] |
| Herbsttrompete | 80.6 → **80.6 %** | 54.9 → **54.9 %** | +25.7 → **+25.7 pp** | +0.0 [+0.0, +0.0] |
| Hallimasch | 89.9 → **91.3 %** | 43.4 → **42.0 %** | +46.5 → **+49.3 pp** | +2.8 [+0.1, +6.0] |
| Stockschwämmchen | 84.0 → **83.1 %** | 44.5 → **42.4 %** | +39.5 → **+40.7 pp** | +1.2 [-1.9, +3.5] |
| Austernseitling | 46.7 → **6.3 %** | 44.1 → **3.2 %** | +2.5 → **+3.2 pp** | +0.6 [-7.3, +9.6] |

## Was daraus folgt

**Sichtbar besser wird es bei: Hallimasch (11.0 °C, +11.1 pp), Stockschwämmchen (12.2 °C, +3.2 pp).** Bei allen übrigen enthält der Vertrauensbereich die Null — ihr eigenes Fenster ändert für die Nutzerin nichts, auch wenn die AUC sich rührt.

**Und bei Austernseitling verschwindet „günstig“ fast ganz** (21.7 % → 1.1 % an Fundtagen).

Das ist kein Fehler der Anpassung, sondern der Schwellen: 0.2 und 0.5 sind für eine 13-°C-Glocke gesetzt. Verschiebt man das Optimum, verschiebt sich die ganze Werteverteilung mit, und dieselben Zahlen bedeuten etwas anderes. **Ein eigenes Fenster ohne eigene Schwellen macht die Ampel dunkel, nicht besser** — und in einer Anzeige „günstig, sobald eine Klasse günstig steht“ käme eine solche Klasse nie zum Zug.

Die Schwellen sind damit kein Umsetzungsdetail, sondern Teil des Modells. Sie stehen bis heute als „GESETZT, nicht gemessen“ in `ampel_model.dart`, und diese Seite ist die erste Messung, die sie überhaupt anfasst.

