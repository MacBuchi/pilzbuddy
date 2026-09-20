# Die Schwellen der Logit-Klassen — Design B auf P1

Stand: 2026-09-20 · Erzeugt von `tool/ampel_logit_klasse.py --schwellen` · Zeitscheibe: **DE ab 2019**

> **Diese Datei wird erzeugt.** Wer sie von Hand ändert, verliert die Änderung beim nächsten Lauf.

Dieselbe Messung wie `docs/pilzampel-schwellen-designb-p1.md`, nur ist der Score nicht die Glocke, sondern die lineare Vorhersage `s` des bedingten Logits der Klasse (`docs/pilzampel-holz-winter-plan.md`, Abschnitt 1). Vergleichstage nach Design B (gleicher Ort, gleiches Datum, anderes Jahr), Quantile 50 % / 80 %, jedes Fundjahr und jede Art gleich schwer, Jahres-Bootstrap mit 2000 Zügen. Die Bodenfeuchte kommt von der nächsten DWD-Station (`BFGL_AG`), 26-Tage-Mittel — genau so, wie die App sie holt.

## Austernseitling & Co. (`holz_winter`)

| Art | Funde P1 | Kontrolltage | Fundjahre | Station (Median) |
|---|--:|--:|--:|--:|
| Austernseitling | 797 | 3858 | 7 | 10 km |
| Judasohr | 806 | 3919 | 7 | 11 km |
| Krause Glucke | 579 | 2889 | 7 | 11 km |
| Leberpilz | 324 | 1619 | 7 | 11 km |
| Lungenseitling | 225 | 1122 | 7 | 10 km |
| Rehbrauner Dachpilz | 641 | 3205 | 7 | 10 km |
| Samtfußrübling | 307 | 1456 | 7 | 10 km |
| Schwefelporling | 1047 | 5223 | 7 | 10 km |

| Stufe | gepinnt | gemessen | 95 % |
|---|--:|--:|---|
| verhalten | 0.454 | 0.454 | [0.445, 0.462] |
| günstig | 0.606 | 0.606 | [0.599, 0.612] |

Kontrolltage gesamt: 23291. Koeffizienten: log_regen +0.1882, temp +0.1321, temp2 -0.00446, feuchte +0.0022, feuchte_x_temp -0.000442.

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

Kontrolltage gesamt: 3026. Koeffizienten: log_regen +0.1039, temp +0.1547, temp2 -0.01399, feuchte +0.00333, feuchte_x_temp +0.002237.

⚠ unter der Beitragsgrenze — steuert zum Klassenquantil bei, trägt aber kein eigenes Urteil (Korrekturkasten in `docs/pilzampel-schwellen-designb-p1.md`).
