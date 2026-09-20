# H6 — registriert: das Sommer-Optimum auf 14,0 °C

Stand: 2026-09-19 · Auftrag: `docs/pilzampel-auftrag-3.md`, Abschnitt B ·
**vor dem Lauf geschrieben, danach nicht mehr angefasst**

## 1. Was geprüft wird

> **Der Pfifferling trennt Fund- von Kontrolltagen besser, wenn sein
> Temperaturfenster bei 14,0 °C statt bei 17,5 °C liegt.**

σ bleibt bei 5,0 K. Die Herbstklasse wird nicht angefasst. Geprüft wird
**ein** Wert, hier eingefroren; auf der Prüfachse wird kein Gitter
gerechnet.

## 2. Der eingefrorene Wert, und warum gerade er

Die Vorprüfung auf P3 (`docs/pilzampel-h6-vorpruefung-ergebnis.md`)
liefert zwei Schätzer auf derselben Ziehung:

| Weg | Optimum | SE |
|---|--:|--:|
| Gitter (maximiert B) | 15,00 °C | 0,86 K |
| Logit (cluster-robust) | 13,16 °C | 0,86 K |

**14,0 °C ist die Mitte der Uneinigkeit**, gerundet auf das Gitter. Der
Wert liegt in beiden 95-%-Intervallen (Gitter [13,00, 15,75], Logit
[11,5, 14,9]) und im Plateau des Gitters [13,75, 15,75].

Bewusst **nicht** die 15,00: Das ist das Argmax genau des Maßes, mit dem
geprüft wird, angepasst auf P3. Es zu nehmen wäre die günstigste aller
zulässigen Wahlen. Eine Uneinigkeit zweier Wege löst man nicht, indem
man einen davon gewinnen lässt.

**Der Vorbehalt dazu:** 14,0 liegt nahe an den 13,0 der Herbstklasse.
Besteht H6, ist die nächste Frage, ob der Pfifferling überhaupt ein
eigenes Fenster braucht — und das ist dann eine neue Frage, keine
Fortsetzung dieser.

## 3. Der offen benannte Mangel

**Bedingung V1 der Vorprüfung ist gefallen.** Gitter und Logit liegen
1,84 K auseinander, die Latte stand bei 1,0 K. Registriert wird
trotzdem, auf Betreiberentscheidung vom 2026-09-19: Die Ampel ist
experimentell, und was zählt, ist, ob etwas besser ist als der heutige
Stand.

Was dafür spricht, und es steht hier, damit es später nachlesbar ist:

- Die Wege sind sich nicht uneinig darüber, **ob** 17,5 zu hoch ist —
  darin stimmen sie überein, und 17,5 liegt außerhalb des
  Gitter-Intervalls. Uneinig sind sie darüber, **wo** in einem 2 K
  breiten Plateau der Gipfel sitzt.
- Die statistische Fassung derselben Frage besteht (1,96·√(SE²+SE²) =
  2,39 K), und das Gitter-Intervall enthält den Logit-Wert.
- **V2, das harte Abbruchkriterium, hat gehalten** — und zwar in der
  strengen Lesart: Drift 0,75 K gegen SE 0,86 K.

Was dagegen spricht, und auch das steht hier: Eine vorab gesetzte
Bedingung ist gefallen, und der Wert wurde danach von Hand gewählt.
**Beides erhöht die Irrtumswahrscheinlichkeit dieses Tests**, und zwar
in einem Maß, das sich nicht beziffern lässt. Wer diese Zeile später
liest, soll das Ergebnis entsprechend schwächer gewichten als eines aus
einem sauber durchlaufenen Plan.

## 4. Die Prüfachse

**AT + CH, alle Jahre.** Der Pfifferling hat dort 1876 Meldungen, mehr
als in Deutschland. Die Achse ist die knappste der drei — es wird ihr
sechster Lauf (`docs/pilzampel-pruefachsen.md`).

**DE ≥ 2019 als Bestätigung nur, wenn AT+CH besteht.** Ein zweiter Lauf
nach einem Fehlschlag wäre die Suche nach der Achse, die das gewünschte
Ergebnis liefert.

## 5. Was gemessen wird

Design B, Messbasis `pinned`, Entdoppeln an, Seed 42 — dieselbe Ziehung
wie überall.

> **Δ = B(14,0 °C) − B(17,5 °C)**, auf **denselben** Funden.

Gezogen wird einmal und zweimal bewertet. Das Band kommt aus einem
Jahres-Bootstrap der **Differenz je Zug** (20 000 Züge); zwei getrennte
Bänder würfen die Paarung weg und machten den Test stumpfer, ohne dass
es jemand sähe.

## 6. Die Latte

> **H6 besteht, wenn alle vier gelten:**
>
> 1. `Δ ≥ max(+0,010, MDE)` — wobei `MDE = 2,802 · SE` aus dem
>    Jahres-Bootstrap dieses Laufs stammt.
> 2. Das 95-%-Band von Δ schließt die Null aus (`p < 0,025`).
> 3. **Mindestens 70 % der Fundjahre** bewegen sich in dieselbe
>    Richtung.
> 4. Die abstandsgleiche Kontrolle (Placebo) liegt sauber bei 0,50.

Zu 1: Der Mindestwert +0,010 kommt aus dem Auftrag; die Auflösung wird
aus dem Lauf selbst gerechnet, wie bei H1. Ein Standardfehler hängt
nicht am Ergebnis, die Latte bewegt sich also nicht mit ihm. Nach der
Vorprüfung ist `MDE ≈ 0,015` zu erwarten (SE skaliert mit √n, und AT+CH
hat rund 2,6-mal so viele Funde wie P3) — die Latte wird also
voraussichtlich bei etwa 0,015 liegen und nicht bei 0,010.

**Das ist knapp**, und es steht hier, bevor die Zahl da ist: Der auf P3
gemessene Effekt war +0,026, und der ist durch die Anpassung
überschätzt. Fällt H6 durch, kann das heißen „kein Effekt" oder „der
Aufbau sieht ihn nicht" — welches von beiden, sagt die MDE-Zeile im
Bericht.

## 7. Pflichtspalten, die vor dem Urteil dastehen

- **Tote Funde.** Wie oft liegen Fund- und Kontrolltag beide unter
  1e-6? Dort unterscheidet das Modell nicht mehr, und ein Δ nahe null
  hieße dann etwas anderes als „kein Effekt".
- **Placebo.** Zwei Nicht-Fundjahre gegeneinander; muss 0,50 sein.
- **Gegenprobe in die ANDERE Richtung** (Auftrag 3 B): `Δ' = B(20,0 °C)
  − B(17,5 °C)`. Verbessert eine Verschiebung in **beide** Richtungen
  das Maß, misst es nicht das Optimum, sondern etwas anderes.
  > Ist `Δ' ≥ +0,010` mit Band ohne die Null, hat H6 **nicht**
  > bestanden, unabhängig von Δ.
- **Zerlegung** (voll / nur Regen / nur Temperatur), bei beiden Optima.
  **Nicht entscheidend**, aber die eigentliche Frage dahinter: Auf P3
  und P1 trägt die Glocke dieser Art nichts bei (0,629 gegen 0,632 und
  0,557 gegen 0,630). Ob 14,0 daran etwas ändert, ist das, was man
  wissen will.

## 8. Gegenproben, die vor dem Urteil laufen müssen

Kein Test gilt, bevor er einmal absichtlich rot war. Vor dem Urteil:

- Eine Mutation, die `Δ` das Vorzeichen dreht, muss das Urteil kippen.
- Eine Mutation, die die Jahresanteil-Bedingung abschaltet, muss den
  Selbsttest rot machen.
- Eine Mutation, die die Gegenprobe in die andere Richtung ignoriert,
  muss rot werden.
- Eine Mutation, die statt der gepaarten Differenz zwei getrennte
  Bänder zieht, muss rot werden.

## 9. Was jeder Ausgang bedeutet

| Ausgang | Folge |
|---|---|
| **Bestanden** | 14,0 °C wird ausgeliefert — zusammen mit neu gemessenen Sommer-Schwellen (siehe 10). Die Herkunft bleibt „gemessen (Design B), mit gefallenem V1 in der Vorprüfung". |
| **Δ positiv, aber unter der Latte** | Nicht bestanden. Die Zahl und die MDE stehen im Bericht; ob das reicht, ist eine Betreiberentscheidung und keine, die der Bericht trifft. |
| **Δ um null oder negativ** | Nicht bestanden. Die 17,5 bleiben, und die Herabstufung in `docs/pilzampel-formel.md` bleibt, wie sie ist. |
| **Gegenprobe schlägt an** | Nicht bestanden, unabhängig von Δ — dann misst der Aufbau nicht das Optimum. |
| **Glocke trägt auch bei 14,0 nichts** | Kein drittes Optimum. Dann ist die Frage, ob die Ampel des Pfifferlings ein Regensignal ist, und das ist eine Produktfrage. |

## 10. Die Folge, die nicht untergehen darf

**Ein verschobenes Optimum macht die Sommer-Schwellen ungültig.** Die
0,385 und 0,729 sind die 50-/80-%-Quantile der Score-Verteilung **unter
17,5 °C** (`docs/pilzampel-schwellen-designb-p1.md`). Mit 14,0
verschiebt sich die ganze Verteilung, und dieselben Zahlen bedeuteten
eine andere Häufigkeit.

Besteht H6, läuft deshalb `--schwellen --scheibe p1` erneut, und
**Fenster und Schwellen gehen zusammen in eine Version**. Einzeln
ausgeliefert wären sie ein Fenster mit fremden Schwellen.

## 11. Der Lauf

```
python3 tool/ampel_diagnose.py --h6-test \
    --dataset pinned --dedupe \
    --api http://127.0.0.1:8080/v1/archive \
    --cache ~/pilzbuddy-ampel2000/ampel_cache_pinned \
    --seed 42 \
    --out docs/pilzampel-h6-ergebnis.md
```
