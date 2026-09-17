# Die Kontroll-Toleranz war ein Stichprobengrößenfilter — Nachregistrierung

Stand: 2026-09-17 · Ändert eine Bedingung aus
`docs/pilzampel-herbstklasse-mitgliedschaft.md` · **Vor dem Lauf
geschrieben und committet**, wie die erste Registrierung.

## Was geändert wird

Die abstandsgleiche Kontrolle bleibt Tor. Geändert wird allein, **wann
sie als verletzt gilt**:

> **Alt:** `|Kontrolle − 0,50| ≤ 0,03`, eine feste Zahl.
>
> **Neu:** Der über JAHRE gezogene 95-%-Vertrauensbereich der Kontrolle
> muss **0,50 enthalten**.

Alles andere bleibt, wie es am 2026-09-16 registriert wurde: derselbe
eingefrorene Kandidatenkreis, dieselbe Latte von 0,60, dieselben
mindestens 400 Paare, dieselbe Gruppenzuordnung aus dem Saisongipfel,
dieselbe Vorhersage je Gruppe.

## Warum — gemessen, nicht gefunden

Die feste Toleranz hat im Lauf vom 2026-09-16 acht Arten verworfen.
**Alle acht liegen innerhalb von 2,5 Standardfehlern um 0,50**, sind
also mit reinem Rauschen vereinbar:

| Art | Paare | Kontrolle | Abweichung |
|---|--:|--:|--:|
| Sommersteinpilz | 566 | 0,450 | 2,4 SE |
| Dunkler Hallimasch | 879 | 0,540 | 2,4 SE |
| Riesenbovist | 703 | 0,461 | 2,1 SE |
| Maipilz | 411 | 0,550 | 2,0 SE |
| Wiesenchampignon | 735 | 0,537 | 2,0 SE |
| Samtfußrübling | 540 | 0,541 | 1,9 SE |
| Netzstieliger Hexenröhrling | 752 | 0,469 | 1,7 SE |
| Ziegenlippe | 511 | 0,467 | 1,5 SE |

Und die Verteilung zeigt, was die Zahl wirklich tut:

- große Stichproben (≥ 1500 Paare): **0 von 16** verworfen
- kleine Stichproben (< 800 Paare): **7 von 18** verworfen

Bei 2000 Paaren sind ±0,03 rund 2,7 SE — eine vernünftige Schranke. Bei
411 Paaren sind sie **1,2 SE** — dort verwirft sie im Normalbetrieb.
Eine feste Zahl auf Stichproben von 400 bis 2000 Paaren angewandt ist
kein Gültigkeitstest, sondern ein **Filter auf die Stichprobengröße**.

**Es liegt nicht an schiefem Ziehen.** Nachgemessen an den beiden
Kontrastarten: Der Spiegeltag ist zu 99,6 bzw. 100 % vorhanden, und die
Kontrolltage liegen zu 49,3 bzw. 50,1 % nach dem Fund. Die Ziehung ist
symmetrisch und praktisch lückenlos; es gibt nichts zu korrigieren, die
Abweichung ist Rauschen.

## Warum nicht der naheliegendere Umbau

Vorgeschlagen war, statt des Tors einen **Mindestabstand zwischen
Haupt-AUC und Kontrolle** zu verlangen. Das trägt nicht, und das ist
simuliert worden (künstliche Daten, wahre Antwort bekannt):

| Saisongefälle | Haupt-AUC | Kontrolle | wahr | „korrigiert" |
|---|--:|--:|--:|--:|
| 0,00 | 0,863 | 0,497 | 0,865 | 0,860 |
| 0,02 | 0,841 | 0,495 | 0,865 | 0,836 |
| 0,05 | 0,749 | **0,498** | 0,865 | 0,748 |

Ein Saisongefälle verbiegt die Haupt-AUC um bis zu **0,115**, während
die Kontrolle unbeirrt bei 0,50 steht. Sie misst diese Verzerrung also
gar nicht — `AUC − Kontrolle` korrigiert nichts, die korrigierte Spalte
ist keinen Deut besser als die rohe. Die Kontrolle prüft eine engere
Sache: ob die beiden Vergleichstage austauschbar sind.

**Das ist zugleich ein Befund über alle bisherigen Ampel-Zahlen** und
gehört als eigener Punkt verfolgt: Gegen ein Saisongefälle hat dieser
Aufbau derzeit keinen Wächter.

## Warum über Jahre gezogen und nicht über Paare

Der Vertrauensbereich kommt aus `bootstrap_years`, wie überall sonst im
Werkzeug. Funde desselben Jahres sind einander ähnlicher als Funde
verschiedener Jahre — Pilzjahre unterscheiden sich um den Faktor zehn.
Über Paare zu ziehen behandelte sie als unabhängig und lieferte einen
zu engen Bereich, also eine Sicherheit, die es nicht gibt.

Das ist zugleich die **konservativere** Wahl: Der Bereich wird breiter,
das Tor also durchlässiger. Es lässt damit mehr Kontrastarten herein —
und genau die können den Plan scheitern lassen. Die strengere Methode
ist hier die, die gegen das Vorhaben arbeitet, und das ist die richtige
Richtung für eine nachträgliche Änderung.

## Die Erwartung, offen hingeschrieben

Diese Änderung wird registriert, **nachdem** die Zahlen des ersten Laufs
bekannt sind. Das ist die schwächste Form einer Registrierung, und der
einzige Ausgleich dafür ist, die Folge vorher zu nennen:

> **Erwartet wird der Ausgang `generisch`.** Sommersteinpilz (0,647) und
> Maipilz (0,766) werden durch die neue Toleranz auswertbar, und beide
> überspringen die Latte von 0,60. Damit bestünde die Kontrastgruppe
> vollständig — und der registrierte Gegen-Ausgang lautet: Das Modell
> trennt nicht nach Temperaturnische, die Klassenmaschinerie gehört
> zurückgebaut statt ausgebaut.

Wer diese Seite später liest, soll sehen können, dass die Lockerung
**nicht** aufs gewünschte Ergebnis hin gewählt wurde: Sie war zum
Zeitpunkt der Registrierung die Änderung, die das Vorhaben am
wahrscheinlichsten beendet.

Tritt der erwartete Ausgang ein, wird nichts ausgeliefert — weder die
27 Arten noch eine neue Klasse. Dann ist die nächste Frage, ob die
bestehenden zwei Klassen überhaupt tragen.
