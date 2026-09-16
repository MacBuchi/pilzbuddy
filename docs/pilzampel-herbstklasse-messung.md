# Wie weit trägt das eine Fenster? — die Messung

Stand: 2026-09-17 · Erzeugt von `tool/ampel_validate.py --membership` · Prüfplan: `docs/pilzampel-herbstklasse-mitgliedschaft.md`

Gemessen wird das **ausgelieferte** 13-°C-Fenster an Arten, für die es nie angepasst wurde — es ist ein Literaturwert. Es wird hier nichts angepasst; die Frage ist allein, wie weit es trägt.

Die Bedingung stand vor der Messung fest: gepaarte AUC ≥ 0.60 bei mindestens 400 Paaren, abstandsgleiche Kontrolle innerhalb abstandsgleiche Kontrolle, deren über Jahre gezogener 95-%-Bereich die 0,50 enthält.

**Das Kontroll-Tor ist am 2026-09-17 umgestellt worden** — von festen ±0,03 auf den Vertrauensbereich, weil die feste Zahl ein Filter auf die Stichprobengröße war und keiner auf die Gültigkeit (`docs/pilzampel-kontrolltoleranz.md`). Die Umstellung war beim Registrieren die Änderung, die den Plan am wahrscheinlichsten beendet.

## Kontrastgruppe: Gipfel im Frühjahr und Sommer

**Diese Gruppe entscheidet zuerst.** Besteht sie mit, trennt das Modell nicht nach Temperaturfenster — dann ist eine längere Mitgliederliste die Erweiterung von etwas, das nichts behauptet.

| Art | Paare | Jahre | AUC (13 °C) | 95 % | Kontrolle | Kontrolle 95 % | Ausgang | Status |
|---|--:|--:|--:|---|--:|---|---|---|
| Sommersteinpilz | 566 | 20 | 0.647 | [0.555, 0.733] | 0.450 | [0.402, 0.502] | **erfüllt** | frisch |
| Maipilz | 411 | 20 | 0.766 | [0.658, 0.862] | 0.550 | [0.494, 0.605] | **erfüllt** | frisch |

## Kontrastgruppe: Gipfel im Winter

Dieselbe Rolle. Ihre Zahlen waren aus dem Kalttest bereits bekannt und tragen das Urteil deshalb nicht mit; sie stehen hier, damit die Tabelle vollständig ist.

| Art | Paare | Jahre | AUC (13 °C) | 95 % | Kontrolle | Kontrolle 95 % | Ausgang | Status |
|---|--:|--:|--:|---|--:|---|---|---|
| Judasohr | 1255 | 20 | 0.508 | [0.470, 0.541] | 0.511 | [0.482, 0.543] | verfehlt | Zahlen bekannt |
| Austernseitling | 987 | 20 | 0.463 | [0.415, 0.506] | 0.484 | [0.440, 0.527] | verfehlt | Zahlen bekannt |
| Samtfußrübling | 540 | 19 | 0.283 | [0.239, 0.334] | 0.541 | [0.468, 0.601] | verfehlt | Zahlen bekannt |

## Die Bestätigungsgruppe: Gipfel im Herbst

Vorhergesagt war: besteht. Das Urteil tragen die als „frisch“ gekennzeichneten Arten — bei den übrigen war die Zahl vorher bekannt.

| Art | Paare | Jahre | AUC (13 °C) | 95 % | Kontrolle | Kontrolle 95 % | Ausgang | Status |
|---|--:|--:|--:|---|--:|---|---|---|
| Fliegenpilz | 1978 | 19 | 0.791 | [0.731, 0.835] | 0.513 | [0.497, 0.528] | **erfüllt** | frisch |
| Parasol | 1973 | 19 | 0.768 | [0.725, 0.803] | 0.489 | [0.469, 0.511] | **erfüllt** | frisch |
| Schopftintling | 1975 | 19 | 0.788 | [0.741, 0.823] | 0.512 | [0.490, 0.537] | **erfüllt** | frisch |
| Grünblättriger Schwefelkopf | 1896 | 20 | 0.701 | [0.670, 0.730] | 0.514 | [0.486, 0.542] | **erfüllt** | frisch |
| Perlpilz | 1987 | 20 | 0.675 | [0.621, 0.718] | 0.496 | [0.483, 0.510] | **erfüllt** | frisch |
| Hallimasch | 1953 | 20 | 0.749 | [0.699, 0.792] | 0.511 | [0.483, 0.536] | **erfüllt** | Zahlen bekannt |
| Maronenröhrling | 1974 | 20 | 0.743 | [0.704, 0.776] | 0.515 | [0.491, 0.540] | **erfüllt** | ausgeliefert |
| Flaschenstäubling | 1889 | 20 | 0.737 | [0.705, 0.767] | 0.499 | [0.479, 0.524] | **erfüllt** | frisch |
| Steinpilz | 1990 | 20 | 0.762 | [0.723, 0.799] | 0.510 | [0.490, 0.533] | **erfüllt** | ausgeliefert |
| Nebelkappe | 1873 | 19 | 0.688 | [0.638, 0.729] | 0.517 | [0.491, 0.543] | **erfüllt** | frisch |
| Rotkappe | 1990 | 19 | 0.755 | [0.715, 0.797] | 0.493 | [0.462, 0.522] | **erfüllt** | frisch |
| Schwefelporling | 1824 | 19 | 0.571 | [0.545, 0.595] | 0.506 | [0.492, 0.524] | verfehlt | frisch |
| Violetter Lacktrichterling | 1832 | 19 | 0.755 | [0.719, 0.787] | 0.506 | [0.479, 0.527] | **erfüllt** | frisch |
| Birnenstäubling | 1500 | 20 | 0.637 | [0.603, 0.671] | 0.507 | [0.474, 0.536] | **erfüllt** | frisch |
| Rotfußröhrling | 1764 | 20 | 0.698 | [0.658, 0.734] | 0.499 | [0.473, 0.524] | **erfüllt** | frisch |
| Kahler Krempling | 1507 | 20 | 0.776 | [0.741, 0.809] | 0.483 | [0.459, 0.509] | **erfüllt** | frisch |
| Falscher Pfifferling | 1395 | 20 | 0.751 | [0.703, 0.796] | 0.501 | [0.479, 0.527] | **erfüllt** | frisch |
| Pfifferling | 1332 | 20 | 0.607 | [0.579, 0.639] | 0.512 | [0.489, 0.533] | **erfüllt** | ausgeliefert |
| Stockschwämmchen | 1277 | 20 | 0.756 | [0.723, 0.785] | 0.479 | [0.458, 0.502] | **erfüllt** | Zahlen bekannt |
| Rehbrauner Dachpilz | 1202 | 19 | 0.713 | [0.674, 0.747] | 0.520 | [0.494, 0.547] | **erfüllt** | frisch |
| Birkenpilz | 1203 | 19 | 0.743 | [0.709, 0.775] | 0.506 | [0.475, 0.540] | **erfüllt** | ausgeliefert |
| Goldröhrling | 1198 | 19 | 0.745 | [0.708, 0.781] | 0.476 | [0.454, 0.503] | **erfüllt** | frisch |
| Ziegenbart | 976 | 19 | 0.696 | [0.659, 0.740] | 0.523 | [0.496, 0.551] | **erfüllt** | frisch |
| Krause Glucke | 985 | 20 | 0.666 | [0.620, 0.712] | 0.489 | [0.448, 0.532] | **erfüllt** | frisch |
| Dunkler Hallimasch | 879 | 19 | 0.745 | [0.696, 0.798] | 0.540 | [0.513, 0.572] | offen | frisch |
| Pantherpilz | 856 | 20 | 0.779 | [0.730, 0.814] | 0.496 | [0.462, 0.546] | **erfüllt** | frisch |
| Violetter Rötelritterling | 803 | 19 | 0.724 | [0.661, 0.777] | 0.522 | [0.490, 0.553] | **erfüllt** | frisch |
| Grüner Knollenblätterpilz | 839 | 19 | 0.726 | [0.671, 0.771] | 0.501 | [0.467, 0.548] | **erfüllt** | frisch |
| Frauentäubling | 827 | 20 | 0.647 | [0.602, 0.698] | 0.472 | [0.433, 0.517] | **erfüllt** | frisch |
| Fichtenreizker | 765 | 20 | 0.739 | [0.704, 0.776] | 0.506 | [0.465, 0.546] | **erfüllt** | ausgeliefert |
| Netzstieliger Hexenröhrling | 752 | 20 | 0.581 | [0.513, 0.652] | 0.469 | [0.428, 0.522] | verfehlt | frisch |
| Safranschirmling | 744 | 19 | 0.741 | [0.688, 0.784] | 0.510 | [0.468, 0.546] | **erfüllt** | frisch |
| Wiesenchampignon | 735 | 20 | 0.744 | [0.697, 0.791] | 0.537 | [0.510, 0.562] | offen | frisch |
| Riesenbovist | 703 | 19 | 0.657 | [0.603, 0.707] | 0.461 | [0.416, 0.493] | offen | frisch |
| Butterpilz | 716 | 19 | 0.764 | [0.725, 0.801] | 0.528 | [0.494, 0.565] | **erfüllt** | frisch |
| Fuchsiger Rötelritterling | 552 | 19 | 0.721 | [0.664, 0.768] | 0.517 | [0.465, 0.572] | **erfüllt** | frisch |
| Semmelstoppelpilz | 554 | 19 | 0.632 | [0.578, 0.692] | 0.496 | [0.462, 0.532] | **erfüllt** | frisch |
| Leberpilz | 550 | 20 | 0.587 | [0.549, 0.624] | 0.502 | [0.452, 0.553] | verfehlt | frisch |
| Edelreizker | 542 | 19 | 0.760 | [0.731, 0.793] | 0.503 | [0.459, 0.552] | **erfüllt** | frisch |
| Ziegenlippe | 511 | 20 | 0.699 | [0.638, 0.752] | 0.467 | [0.417, 0.516] | **erfüllt** | frisch |
| Nelkenschwindling | 490 | 20 | 0.727 | [0.649, 0.785] | 0.517 | [0.469, 0.570] | **erfüllt** | frisch |
| Gallenröhrling | 476 | 20 | 0.466 | [0.414, 0.554] | 0.526 | [0.498, 0.558] | verfehlt | frisch |
| Gifthäubling | 367 | 19 | 0.700 | [0.651, 0.743] | 0.512 | [0.448, 0.584] | offen | frisch |
| Mönchskopf | 369 | 19 | 0.688 | [0.613, 0.762] | 0.480 | [0.411, 0.542] | offen | frisch |

## Der Ausgang

**Die Kontrastgruppe besteht mit.** Damit ist die Frage nach der Mitgliedschaft gegenstandslos: Das Modell trennt Fundtage von Vergleichstagen auch dort, wo sein Fenster nicht passen kann. Es misst also etwas Generisches — innerhalb der Saison, denn der Vergleichstag liegt 14–45 Tage neben dem Fund am selben Ort. Der registrierte Plan sieht dafür den Rückbau der Klassenmaschinerie vor, nicht ihren Ausbau.

Kontrastgruppe: 2 von 2 gemessenen Arten erfüllen die Bedingung (Sommersteinpilz, Maipilz).

**Nicht gemessen** (verzerrte Ziehung oder zu wenig Material): Dunkler Hallimasch, Wiesenchampignon, Riesenbovist, Gifthäubling, Mönchskopf. Das ist kein Durchfallen — dort wurde nichts gemessen.

## Grenzen

Gemessen wurde ausschließlich an GBIF. Die eigenen Funde und Leergänge der App bleiben draußen — sie sind der unabhängige Prüfstein aus #199.

Eine bestandene Mitgliedschaft sagt „die Bedingungen sind günstig“, nicht „hier stehen Pilze“. Und sie sagt nichts darüber, ob ein eigenes Fenster für diese Art noch besser wäre.
