# Die Schwellen der Logit-Klassen — Design B auf P1

Stand: 2026-09-21 · Erzeugt von `tool/ampel_logit_klasse.py --schwellen` · Zeitscheibe: **DE ab 2019**

> **Diese Datei wird erzeugt.** Wer sie von Hand ändert, verliert die Änderung beim nächsten Lauf.

Dieselbe Messung wie `docs/pilzampel-schwellen-designb-p1.md`, nur ist der Score nicht die Glocke, sondern die lineare Vorhersage `s` des bedingten Logits der Klasse (`docs/pilzampel-holz-winter-plan.md`, Abschnitt 1). Vergleichstage nach Design B (gleicher Ort, gleiches Datum, anderes Jahr), Quantile 50 % / 80 %, jedes Fundjahr und jede Art gleich schwer, Jahres-Bootstrap mit 2000 Zügen. Die Bodenfeuchte kommt von der nächsten DWD-Station (`BFGL_AG`), 26-Tage-Mittel — genau so, wie die App sie holt. Das Merkmal „milder“ (Tagesminima der jüngsten 5 Tage gegen die Tage 6–28, seit 2026-09-21) kommt aus den Minima des gepinnten Datensatzes an der Fundkoordinate; die App nimmt dafür die nächste Luftstation — dieselbe Ersetzung wie bei der Temperatur.

## Austernseitling & Co. (`holz_winter`)

| Art | Funde P1 | Kontrolltage | Fundjahre | Station (Median) |
|---|--:|--:|--:|--:|
| Austernseitling | 797 | 3824 | 7 | 10 km |
| Judasohr | 806 | 3888 | 7 | 11 km |
| Krause Glucke | 579 | 2889 | 7 | 11 km |
| Leberpilz | 324 | 1619 | 7 | 11 km |
| Lungenseitling | 225 | 1122 | 7 | 10 km |
| Rehbrauner Dachpilz | 641 | 3205 | 7 | 10 km |
| Samtfußrübling | 307 | 1433 | 7 | 10 km |
| Schwefelporling | 1047 | 5220 | 7 | 10 km |

| Stufe | gepinnt | gemessen | 95 % |
|---|--:|--:|---|
| verhalten | 0.387 | 0.387 | [0.378, 0.396] |
| günstig | 0.558 | 0.558 | [0.551, 0.566] |

Kontrolltage gesamt: 23200. Koeffizienten: log_regen +0.1915, temp +0.135, temp2 -0.004712, feuchte +0.002383, feuchte_x_temp -0.0004888, milder +0.04193.

## Herbsttrompete & Co. (`cantharellales`)

| Art | Funde P1 | Kontrolltage | Fundjahre | Station (Median) |
|---|--:|--:|--:|--:|
| Herbsttrompete | 144 | 720 | 7 | 12 km |
| Semmelstoppelpilz | 268 | 1339 | 7 | 10 km |
| Trompetenpfifferling | 195 | 967 | 7 | 11 km |

| Stufe | gepinnt | gemessen | 95 % |
|---|--:|--:|---|
| verhalten | 2.191 | 2.191 | [2.035, 2.339] |
| günstig | 2.952 | 2.952 | [2.861, 3.032] |

Kontrolltage gesamt: 3026. Koeffizienten: log_regen +0.1039, temp +0.1547, temp2 -0.01399, feuchte +0.00333, feuchte_x_temp +0.002237, milder +0.

⚠ unter der Beitragsgrenze — steuert zum Klassenquantil bei, trägt aber kein eigenes Urteil (Korrekturkasten in `docs/pilzampel-schwellen-designb-p1.md`).
