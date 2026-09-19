# H6-Vorprüfung: hält das Sommer-Optimum still?

Stand: 2026-09-19 · Erzeugt von `tool/ampel_diagnose.py --h6` · Registrierung: `docs/pilzampel-h6-vorpruefung.md`

> **Diese Datei wird erzeugt.** Wer sie von Hand ändert, verliert die Änderung beim nächsten Lauf.

> **P3 sind die Anpassjahre.** Jede Zahl hier ist eine Diagnose und kein Beleg. Sie entscheidet nur, ob H6 auf AT+CH geprüft wird.

## Das Urteil

# H6 wird NICHT registriert

| Bedingung | erfüllt |
|---|---|
| **V1** — Gitter und Logit einig (≤ 1,0 K) | **nein** |
| **V2** — Optimum stabil über die geteilten Anpassjahre (Drift ≤ SE) | **ja** |
| **V4** — Auflösung reicht (MDE < Diskordanzanteil) | **ja** |

Material: **716 Funde** des Pfifferlings auf P3, 13 Fundjahre.

## V1 — zwei Wege, ein Optimum?

| Weg | Optimum | Standardfehler |
|---|--:|--:|
| **Gitter** (maximiert B) | 15,00 °C | 0,86 K |
| **Logit** (cluster-robust) | 13,16 °C | 0,86 K |
| ausgeliefert | 17,5 °C | — |

**Abstand der beiden Wege: 1,84 K** gegen die Latte von 1,0 K.
Die statistische Fassung, nur zur Einordnung: 1,96·√(SE²+SE²) = 2,39 K. Sie ist hier zu großzügig, weil beide Schätzer auf denselben Daten laufen — deshalb steht sie nicht in der Bedingung.

Das Plateau des Gitters reicht von 13,75 °C bis 15,75 °C (2,00 K breit) — alle Optima, die weniger als 0,005 B darunter liegen. Ein breites Plateau heißt: Der Gipfel ist eine Nachkommastelle ohne Deckung.

## V2 — das harte Abbruchkriterium

| Scheibe | Funde | Gitter | 95 % | Logit |
|---|--:|--:|---|--:|
| 2006–2012 | 216 | 15,75 °C | [9,00 °C, 16,00 °C] | 11,91 °C |
| 2013–2018 | 500 | 15,00 °C | [10,25 °C, 17,75 °C] | 13,76 °C |
| **ganz P3** | 716 | 15,00 °C | [13,00 °C, 15,75 °C] | 13,16 °C |

**Drift des Gitter-Optimums: 0,75 K** gegen den Standardfehler auf ganz P3 von 0,86 K.

Die großzügige Fassung, zur Einordnung: Die Differenz zweier Halbschätzer trägt selbst rund 2,13 K Fehler. Gegen die gemessen wäre die Drift unauffällig. Bindend ist die strenge Fassung aus der Registrierung — gefragt ist nicht, ob die Drift signifikant ist, sondern ob die Genauigkeit haltbar wäre, die wir für die ausgelieferte Zahl behaupten würden.

Das Logit driftet um 1,85 K — es läuft daneben und entscheidet nicht, aber wenn beide Wege verschieden urteilten, stünde V1 in Frage.

## V3 — wieviel kann überhaupt herauskommen?

Zwischen 17,5 °C und 15,00 °C ordnen **18,1 %** der 3579 B-Vergleiche das Paar verschieden.

> **Obergrenze der Effektgröße: |ΔB| ≤ 0,181**

Die zweite, schärfere Schranke ist die mittlere Änderung des Beitrags je Vergleich: 0,181. **Sie ist hier genauso groß wie der Diskordanzanteil.** Das heißt: Jeder Vergleich, der überhaupt kippt, kippt ganz — von „geschlagen“ auf „nicht geschlagen“, nie auf „gleich“. Exakte Gleichstände gibt es bei Fließkommazahlen praktisch nicht.

## V4 — kann der Aufbau das sehen?

Jahres-Bootstrap der **Differenz je Zug**, 20000 Züge über die Fundjahre. Bewertet werden in jedem Zug dieselben Funde zweimal.

| Größe | Wert |
|---|--:|
| ΔB auf P3 (15,00 °C gegen 17,5 °C) | +0,026 |
| 95 %-Band | [+0,008, +0,043] |
| Standardfehler | 0,0087 |
| **nachweisbare Effektgröße (MDE)** | 0,024 |

**MDE 0,024 gegen Obergrenze 0,181** — die Auflösung reicht.

Das ΔB oben ist **kein Beleg**: Das neue Optimum stammt von denselben Anpassjahren, auf denen es hier bewertet wird. Es steht da, damit die Größenordnung sichtbar ist.

## Was daraus folgt

Gefallen ist: **V1 — Gitter und Logit sind sich nicht einig**. **H6 wird nicht registriert**, und AT+CH bleibt unangetastet.

Das ist ein Ergebnis und kein Anlass für einen zweiten Anlauf mit verschobener Latte. Was hier gemessen wurde, steht oben; ob es reicht, ist eine Betreiberentscheidung und keine, die dieser Bericht still trifft.
