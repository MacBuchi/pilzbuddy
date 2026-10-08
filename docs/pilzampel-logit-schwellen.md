# Die Schwellen der Logit-Klassen — Design B auf P1

Stand: 2026-10-08 · Erzeugt von `tool/ampel_logit_klasse.py --schwellen` · Zeitscheibe: **DE ab 2019**

> **Diese Datei wird erzeugt.** Wer sie von Hand ändert, verliert die Änderung beim nächsten Lauf.

Dieselbe Messung wie `docs/pilzampel-schwellen-designb-p1.md`, nur ist der Score nicht die Glocke, sondern die lineare Vorhersage `s` des bedingten Logits der Klasse (`docs/pilzampel-holz-winter-plan.md`, Abschnitt 1). Vergleichstage nach Design B (gleicher Ort, gleiches Datum, anderes Jahr), Quantile 50 % / 80 %, jedes Fundjahr und jede Art gleich schwer, Jahres-Bootstrap mit 2000 Zügen. Die Bodenfeuchte kommt — bei einer Klasse, die sie braucht — seit #676 aus ERA5-Land 7–28 cm (m³/m³, `smoist` des gepinnten Datensatzes) an der Fundkoordinate, 26-Tage-Mittel; die App schlägt denselben Wert im Gitter von `tool/soil_moisture.py` nach. Ein Fund ohne lückenloses Fenster fällt weg. Eine Klasse ohne Feuchte (Holz & Winter) rechnet auf allen Strata. Das Merkmal „milder“ (Tagesminima der jüngsten 5 Tage gegen die Tage 6–28, seit 2026-09-21) kommt aus den Minima des gepinnten Datensatzes an der Fundkoordinate; die App nimmt dafür die nächste Luftstation — dieselbe Ersetzung wie bei der Temperatur.

## Austernseitling & Co. (`holz_winter`)

Ohne Bodenfeuchte: alle Strata auf P1.

| Art | Funde P1 | mit Fenster | Kontrolltage | Fundjahre |
|---|--:|--:|--:|--:|
| Austernseitling | 818 | 818 | 3925 | 7 |
| Judasohr | 835 | 835 | 4021 | 7 |
| Krause Glucke | 592 | 592 | 2954 | 7 |
| Leberpilz | 328 | 328 | 1639 | 7 |
| Lungenseitling | 234 | 234 | 1167 | 7 |
| Rehbrauner Dachpilz | 658 | 658 | 3290 | 7 |
| Samtfußrübling | 318 | 318 | 1483 | 7 |
| Schwefelporling | 1089 | 1089 | 5430 | 7 |

| Stufe | gepinnt | gemessen | 95 % |
|---|--:|--:|---|
| verhalten | 0.099 | 0.099 | [0.091, 0.108] |
| günstig | 0.255 | 0.255 | [0.249, 0.260] |

Kontrolltage gesamt: 23909. Koeffizienten: log_regen +0.1732, temp +0.06921, temp2 -0.003344, feuchte +0, feuchte_x_temp +0, milder +0.03819.

## Herbsttrompete & Co. (`cantharellales`)

Bodenfeuchte ERA5-Land 7–28 cm an der Fundkoordinate.

| Art | Funde P1 | mit Fenster | Kontrolltage | Fundjahre |
|---|--:|--:|--:|--:|
| Herbsttrompete | 145 | 145 | 725 | 7 |
| Semmelstoppelpilz | 269 | 269 | 1344 | 7 |
| Trompetenpfifferling | 198 | 198 | 982 | 7 |

| Stufe | gepinnt | gemessen | 95 % |
|---|--:|--:|---|
| verhalten | 2.652 | 2.652 | [2.535, 2.774] |
| günstig | 3.306 | 3.306 | [3.225, 3.362] |

Kontrolltage gesamt: 3051. Koeffizienten: log_regen -0.0368583, temp -0.0928386, temp2 -0.00978573, feuchte +4.94857, feuchte_x_temp +0.903891, milder +0.

⚠ unter der Beitragsgrenze — steuert zum Klassenquantil bei, trägt aber kein eigenes Urteil (Korrekturkasten in `docs/pilzampel-schwellen-designb-p1.md`).
