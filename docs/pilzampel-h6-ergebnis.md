# H6 auf AT+CH — das Sommer-Optimum bei 14,0 °C

Stand: 2026-09-19 · Erzeugt von `tool/ampel_diagnose.py --h6-test` · Registrierung: `docs/pilzampel-h6-registrierung.md`

> **Diese Datei wird erzeugt.** Wer sie von Hand ändert, verliert die Änderung beim nächsten Lauf.

> **Das ist ein Lauf auf einer Prüfachse** — der sechste auf AT+CH. Eingetragen in `docs/pilzampel-pruefachsen.md`.

## Das Urteil

# H6 nicht bestanden

| Bedingung | Wert | erfüllt |
|---|--:|---|
| Gewinn ≥ 0,069 | +0.014 | **nein** |
| Band schließt die Null aus (p < 0.025) | 0.2942 | **nein** |
| ≥ 70 % der Fundjahre in dieselbe Richtung | 9/20 | **nein** |
| Placebo sauber bei 0,50 | 0.500 (1876 Paare) | **ja** |
| Gegenprobe (20 °C) schlägt NICHT an | -0.030 | **ja** |

Material: **1876 Funde** des Pfifferlings in AT und CH.

## Die Messung

| Größe | Wert |
|---|--:|
| B bei 17,5 °C (ausgeliefert) | 0.545 |
| B bei 14,0 °C (registriert) | 0.559 |
| **Δ** | +0.014 |
| 95 %-Band | [-0.033, +0.063] |
| p | 0.2942 |
| Standardfehler | 0,0245 |
| nachweisbare Effektgröße (MDE) | 0,069 |
| Latte = max(+0,010, MDE) | 0,069 |

**Wie ein Fehlschlag zu lesen ist.** Liegt Δ unter der Latte, sagt die MDE-Zeile, was das heißt: Ein Δ deutlich unter der MDE heißt „der Aufbau sieht es nicht“; ein Δ nahe null bei kleiner MDE heißt „es ist nichts da“. Hier liegt Δ bei +0.014 und die MDE bei 0,069.

## Pflichtspalten

| Spalte | bei 17,5 °C | bei 14,0 °C |
|---|--:|--:|
| tote Funde | 0,0 % | 0,0 % |
| tote Vergleiche | 0,0 % | 0,0 % |
| exakter Gleichstand | 0,0 % | 0,0 % |

**Tote Vergleiche** sind die, bei denen Fund- und Kontrolltag beide unter 1e-6 liegen — dort unterscheidet das Modell nicht mehr, und ein Δ nahe null hieße etwas anderes als „kein Effekt“.

### Die Zerlegung — nicht entscheidend, aber die eigentliche Frage

Auf P3 und P1 trägt die Glocke dieser Art nichts bei: 0,629 gegen 0,632 an Regen allein, und auf den Prüfjahren 0,557 gegen 0,630. Ob ein anderes Fenster daran etwas ändert, ist das, was man wissen will — es entscheidet hier aber nichts.

| Fenster | voll | nur Regen | nur Temperatur | voll − Regen |
|---|--:|--:|--:|--:|
| 17,5 °C | 0.545 | 0.554 | 0.511 | -0.009 |
| 14,0 °C | 0.559 | 0.554 | 0.540 | +0.005 |

## Was daraus folgt

Gefallen ist: **gewinn, band, jahre**. **Die 17,5 °C bleiben**, und die Herabstufung in `docs/pilzampel-formel.md` bleibt, wie sie ist.

Die Achse ist verbraucht. Ein zweiter Lauf mit einem anderen Wert wäre die Suche nach der Zahl, die besteht — und genau davor steht die Registrierung.
