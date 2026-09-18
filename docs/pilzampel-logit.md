# Optimum und Breite mit Standardfehler (bedingtes Logit)

Stand: 2026-09-18 · Erzeugt von `tool/ampel_diagnose.py --logit` · Auftrag: `docs/pilzampel-auftrag-2-nachtrag-1.md`, N5, letzter Punkt

> **Hier wird nichts geprüft.** Diese Seite enthält keine Latte, keine Bedingung und kein Urteil. Sie sagt, wie genau die Daten Optimum und Breite überhaupt bestimmen — und das ist etwas anderes als die Frage, ob eine **extern** gesetzte Breite besser trennt. Diese Frage beantwortet `docs/pilzampel-h1-registrierung.md`.

> Wer eine Zahl von hier zum Prüfwert macht, verwandelt eine externe Größe in eine angepasste. Deren Instabilität war der Befund aus Phase 0.4: Optima wanderten beim Wechsel des Instruments um bis zu 3 K.

Gerechnet auf den **Anpassjahren DE ≤ 2018**, auf den Paaren aus Design B (ein Fundtag gegen fünf Kontrolljahre). Die Prüfachsen P1 und P2 sind davon unberührt.

Messbasis `pinned`, Entdoppeln an.


## Was das Modell ist

Bedingtes Logit mit den Merkmalen `[log F, T̄₂₀, T̄₂₀²]`, ohne Achsenabschnitt — Ort, Jahr und Jahreszeit kürzen sich über das Stratum heraus. Es hängt direkt an der Formel der Ampel:

    log(F · exp(−((T−opt)/σ)²)) = log F − T²/σ² + 2·opt·T/σ² − opt²/σ²

Der letzte Summand ist je Stratum konstant und fällt heraus. Also `Optimum = −b_T / (2 b_T²)` und `Breite = sqrt(b_logF / −b_T²)`.

**Beide Größen sind maßstabsfrei**, und das ist wichtig für den Vergleich: Skaliert man alle Koeffizienten mit demselben Faktor, kürzt er sich in beiden Formeln heraus. Die Breite ist damit unmittelbar das σ, das zu einem Einheitsgewicht auf `log F` gehört — also genau das, was die Ampel rechnet.

`b_logF` sagt deshalb nichts über eine Gewichtung, sondern darüber, **wie scharf die Wahl überhaupt ist**: Es ist der gemeinsame Faktor vor dem ganzen Nutzen, und ein kleiner Wert heißt viel Rauschen. Bei AUC-Werten um 0,6 gehört ein kleines `b_logF` zum Bild. Es steht in der Tabelle, weil es die Schärfe beziffert — nicht, weil die Breite ohne es unlesbar wäre. (In einer früheren Fassung dieses Werkzeugs stand genau das, und es war falsch.)


## Gemessen

| Art | Gruppe | Strata | Optimum | ± | ausgeliefert | Breite | ± | b_logF | ± | konvergiert |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|:-:|
| Steinpilz | herbst | 951 | 11.65 | 0.47 | 13.0 | 3.62 | 0.42 | 0.44 | 0.08 | ✓ |
| Maronenröhrling | herbst | 886 | 10.11 | 0.45 | 13.0 | 2.26 | 0.46 | 0.19 | 0.07 | ✓ |
| Birkenpilz | herbst | 621 | 11.80 | 0.67 | 13.0 | 3.46 | 0.57 | 0.36 | 0.09 | ✓ |
| Fichtenreizker | herbst | 397 | 9.20 | 0.82 | 13.0 | 3.12 | 0.72 | 0.32 | 0.12 | ✓ |
| Herbsttrompete | herbst | 147 | 12.52 | 0.64 | 13.0 | 3.50 | 0.67 | 0.72 | 0.22 | ✓ |
| Pfifferling | sommer | 716 | 13.16 | 0.86 | 17.5 | 6.64 | 0.87 | 0.85 | 0.11 | ✓ |
| Hallimasch | holz | 941 | 4.59 | 1.56 | 13.0 | — | — | -0.18 | 0.05 | ✓ |
| Stockschwämmchen | holz | 601 | 6.79 | 1.42 | 13.0 | 2.47 | 1.09 | 0.09 | 0.08 | ✓ |
| Austernseitling | kalt | 451 | — | — | -2.5 | — | — | — | — | ✓ |
| Judasohr | kalt | 783 | -10.75 | 25.50 | -2.5 | 14.23 | 11.42 | 0.24 | 0.06 | ✓ |
| Samtfußrübling | kalt | 494 | 3.21 | 1.03 | -2.5 | 2.86 | 1.16 | 0.09 | 0.07 | ✓ |

Ein Strich in der Breite heißt, dass es keine gibt — entweder ist `b_T²` nicht negativ (dann ist die Parabel nach oben offen und beschreibt keine Glocke) oder `b_logF` nicht positiv (dann hat die Wurzel kein Argument). Beides ist ein Ergebnis und keine Panne; der Grund steht je Art unten.

- **Hallimasch**: b_logF ist nicht positiv — keine Breite
- **Austernseitling**: b_T² ist nicht negativ — keine Glocke


## Wieviel Regen abgeschnitten wurde

`log F` braucht ein F über null. Ein Fenster ohne einen Tropfen in 26 Tagen wird deshalb auf 0.001 gesetzt. **Wo dieser Anteil groß ist, rechnet das Modell nicht mehr das, was es behauptet** — und die Breite dieser Art ist dann mit Vorsicht zu lesen.

| Art | abgeschnittene Tage |
|---|--:|
| Steinpilz | 0.00% |
| Maronenröhrling | 0.04% |
| Birkenpilz | 0.00% |
| Fichtenreizker | 0.04% |
| Herbsttrompete | 0.00% |
| Pfifferling | 0.00% |
| Hallimasch | 0.07% |
| Stockschwämmchen | 0.03% |
| Austernseitling | 0.23% |
| Judasohr | 0.26% |
| Samtfußrübling | 0.14% |

## Drei Dinge, die hier ablesbar sind

Alles Folgende ist **Beobachtung, keine Empfehlung.** Gerechnet auf
Anpassjahren, mit angepassten Größen — genau der Sorte Zahl, die Phase
0.4 als instabil ausgewiesen hat. Wer eine davon anfassen will,
registriert sie vorher.

### 1. Das Logit und der gescheiterte H1-Test widersprechen sich nicht

Auf den ersten Blick sieht es so aus. Die Breiten der Herbstarten liegen
hier zwischen **2,26 und 3,62 K** und damit alle näher an den geprüften
3,25 als an den ausgelieferten 5,0. Trotzdem hat H1 nichts gebracht
(`docs/pilzampel-h1-ergebnis.md`).

Der Grund steht in der Spalte daneben: **Das Logit verschiebt auch die
Mitte.** Die Optima der fünf Herbstarten liegen bei 9,20 bis 12,52 °C,
alle unter den ausgelieferten 13,0 — beim Fichtenreizker sind es 3,8 K
und damit gut vier Standardfehler. H1 hat die Mitte festgehalten und nur
die Breite verschmälert. Eine schmalere Glocke um einen Gipfel, der
selbst ein bis vier Kelvin danebensteht, trifft weniger als eine breite;
die beiden Größen sind gekoppelt, und H1 hat eine davon allein bewegt.

**Das ist der brauchbarste Satz dieser Seite.** Er sagt nicht, dass eine
andere Kombination besser wäre — er sagt, welche Frage die nächste wäre.

### 2. Das Fenster des Pfifferlings ist womöglich Kalender

Der Pfifferling wird mit **17,5 °C** ausgeliefert. Dieses Logit sagt
**13,16 ± 0,86** — rund fünf Standardfehler darunter, und damit näher an
der Herbstklasse als an seinem eigenen Fenster.

Die Erklärung liegt nahe und passt zu Phase 1.5: Die 17,5 wurden in
**Design A** angepasst, wo der Vergleichstag 26–45 Tage neben dem Fund
liegt. Bei einem Sommerfrüchter heißt das Frühjahr oder Herbst, und
beides ist kühler — der Fundtag sieht dort zwangsläufig warm aus, und
das Optimum wandert nach oben. Hier steht Design B, gleiches Datum
anderer Jahre, und der Kalenderanteil ist weg.

**Was das NICHT heißt.** Der Hold-out-Erfolg der 17,5 in AT+CH
(`docs/pilzampel-artenfenster-holdout.md`) bleibt als Messung stehen;
er wurde in Design A erzielt und gilt dort. Und der Pfifferling ist die
Art, die Design B am besten überstanden hat (`belegt`, +0,054 über
ihrer Referenz). Was hier steht, ist ein Verdacht gegen eine
**Konstante**, nicht gegen die Art.

### 3. Wo das Modell gar keine Glocke findet, sagt es das

Drei Zeilen ohne Zahl, und jede ist ein Ergebnis:

- **Austernseitling** — `b_T²` ist nicht negativ. Die Parabel ist nach
  oben offen; es gibt kein Optimum, sondern ein Minimum. Eine Zahl
  auszurechnen hätte das Minimum als Gipfel ausgegeben.
- **Hallimasch** — `b_logF` ist nicht positiv: *mehr* Regen ist in
  diesen Paaren schlechter. Dann hat `sqrt(b_logF / −b_T²)` kein
  Argument, und eine Breite gäbe es nur erfunden.
- **Judasohr** — hier steht eine Zahl, und sie ist das beste Beispiel
  dieser Seite: **−10,75 ± 25,50**. Das Vertrauensintervall reicht von
  Sibirien bis Sizilien. Ein Gitterlauf hätte dort einen sauberen Punkt
  ausgegeben, und niemand hätte gesehen, dass er nichts bedeutet.

Alle drei stehen nach Phase 1.5 ohnehin auf „keine Aussage". Die
Übereinstimmung ist keine Bestätigung — es sind dieselben Daten —, aber
sie ist auch kein Zufall.

## Wie das zu lesen ist

**Der Standardfehler ist der Zweck dieser Seite, nicht die Punktschätzung.** Das Gitter aus `--fit` liefert einen Punkt in 0,5-K-Schritten und sagt nichts darüber, wie flach die Likelihood um ihn herum liegt. Eine Breite von 4,0 ± 0,3 und eine von 4,0 ± 2,5 sehen in einer Tabelle gleich aus und bedeuten Gegenteiliges.

Und die Delta-Methode hat ihre eigene Grenze: Sie unterstellt, dass die Umformung im Bereich eines Standardfehlers ungefähr gerade ist. Bei einer flachen Likelihood — `b_T²` nahe null — ist sie das nicht, und der Fehler fällt dann eher zu klein aus. Deshalb hilft im Zweifel der Blick auf `b_T²` selbst.
