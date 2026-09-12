# Die Schwellen der Ampel — Prüfplan und Registrierung

Stand: 2026-09-12 · Werkzeug: `tool/ampel_validate.py --thresholds` ·
Ergebnis: `docs/pilzampel-schwellen-messung.md`

Dies ist **Stufe 0** der Integration des Artenfensters in die App
(`docs/pilzampel-artenfenster.md`). Sie fasst als erste die beiden
Zahlen an, die seit der ersten Vorschau unangetastet in
`lib/features/ampel/ampel_model.dart` stehen:

```dart
/// Die Schwellen sind GESETZT, nicht gemessen — Startwerte für die
/// Vorschau, Kalibrierung erst nach bestandener Validierung.
const ampelVerhaltenAbove = 0.2;
const ampelGuenstigAbove = 0.5;
```

## Warum die Schwellen VOR der Anzeige drankommen

Der Vergleich in Stufen (`docs/pilzampel-ampel-vergleich.md`) hat
gezeigt, dass sie der Engpass sind — nicht das Fenster:

| Art | Gewinn in der Rangfolge (AUC) | Gewinn in Stufen |
|---|--:|--:|
| Austernseitling (−3,2 °C) | +0,174 [+0,108, +0,248] | **+0,6 pp** [−6,3, +6,6] |
| Pfifferling (17,5 °C) | +0,104 [+0,055, +0,150] im Hold-out | +6,6 pp [−4,0, +16,6] |

Beim Austernseitling fällt „günstig" an Fundtagen von 21,7 % auf
**1,1 %**. Das ist kein Fehler der Anpassung: 0,2 und 0,5 sind für eine
Glocke um 13 °C gesetzt. Verschiebt man das Optimum, verschiebt sich die
ganze Werteverteilung mit, und dieselben Zahlen bedeuten etwas anderes.

**Ein eigenes Fenster ohne eigene Schwellen macht die Ampel dunkel, nicht
besser.** Lieferten wir zuerst die Anzeige aus, wäre das Ergebnis für den
Austernseitling eine Ampel, die praktisch nie mehr günstig steht — und in
der geplanten Anzeige „günstig, sobald **eine Klasse** günstig steht"
(`docs/pilzampel-artenfenster.md`) käme eine solche Klasse nie zum Zug.

Damit sind die Schwellen kein Umsetzungsdetail, sondern Teil des Modells.

## Der Vorschlag: die Schwelle als Quantil, nicht als Zahl

Statt „günstig ab Score 0,5" soll gelten:

> **Günstig sind die besten X % der Tage dieser Saison** — gemessen an
> der Score-Verteilung an **Vergleichstagen**, unter dem Fenster der
> jeweiligen Art.

Vergleichstage sind das, was die Validierung ohnehin zieht: ein anderer
Tag derselben Saison am selben Ort, 26 bis 45 Tage entfernt. Sie sind
damit eine Stichprobe dessen, was das Wetter in der Pilzsaison an
Pilzorten tut — genau die Bezugsgröße, gegen die „günstig" etwas heißen
soll.

Drei Dinge gewinnt man damit, und alle drei fehlen heute:

- **Arten werden vergleichbar.** „Günstig" heißt für jede Art dasselbe,
  egal wo ihr Optimum liegt. Ohne das ist „mindestens eine Klasse steht
  günstig" keine sinnvolle Aussage, sondern eine Wette darauf, welche
  Klasse zufällig nahe an der 13-°C-Skala liegt.
- **Die Häufigkeit bleibt steuerbar.** Wie oft die Ampel überhaupt
  günstig steht, ist eine Produktentscheidung („ein Hinweis, der immer
  steht, sagt nichts mehr") und keine Nebenwirkung einer
  Glockenbreite.
- **Das Fenster wird messbar.** Mit gepinnter Vergleichstag-Quote misst
  der Abstand Fundtag−Vergleichstag die Trennschärfe und nicht mehr
  nebenbei, wie selten „günstig" geworden ist.

## Was vorab festgelegt ist

### Vorhersage 1 — die Quantile reproduzieren die heutige App

> Unter dem ausgelieferten Fenster (13 °C) entsprechen die gesetzten
> Schwellen 0,2 und 0,5 an Vergleichstagen ungefähr den Quantilen
> **50 %** und **80 %**. „Ungefähr" heißt: Der Median über die sechs
> Mykorrhiza-Herbstarten liegt für 0,5 zwischen **75 % und 85 %** und
> für 0,2 zwischen **45 % und 55 %**.

Das ist die Vorhersage, an der alles Weitere hängt. Trifft sie zu, ist
die Quantil-Formulierung **keine Umdeutung**, sondern dieselbe Aussage in
übertragbarer Form — und die Umstellung ändert für die heute
ausgelieferten sechs Arten fast nichts, während sie für jedes andere
Fenster überhaupt erst eine Bedeutung herstellt.

Trifft sie nicht zu, sind die gerundeten Quantile eine neue Entscheidung
über die Häufigkeit der Ampel und gehören als solche begründet — nicht
als Kalibrierung getarnt.

**Die Quantile werden aus dieser Messung gesetzt, nicht aus einer
zweiten.** Gerundet wird auf volle 5 %, und gerundet wird EINMAL: an den
Zahlen der sechs Mykorrhiza-Arten, die die App heute ausliefert. Weder
der Austernseitling noch sonst eine Art aus Vorhersage 2 ist daran
beteiligt — sonst wäre die Schwelle auf ihr Ergebnis hin gewählt.

### Vorhersage 2 — die Schwellen waren wirklich der Engpass

> Mit Quantil-Schwellen liegt der Abstand „günstig an Fundtagen" minus
> „günstig an Vergleichstagen" beim **Austernseitling** auf den
> Prüfjahren bei mindestens **+10 pp**, gegenüber +0,5 pp mit den festen
> Schwellen.

Der Austernseitling ist der Härtefall: das kälteste gemessene Fenster
(−3,2 °C), der größte AUC-Gewinn (+0,174) und zugleich der vollständige
Zusammenbruch in Stufen. Wenn die Schwellen die Ursache waren, muss der
Abstand hier erscheinen.

**Sie kann scheitern, und das wäre der wertvollere Ausgang:** Bliebe der
Abstand klein, läge der AUC-Gewinn in Feinheiten der Rangfolge, die drei
Stufen prinzipiell nicht abbilden können. Dann ist nicht die Schwelle das
Problem, sondern die Erwartung, dass sich ein Rangfolgen-Gewinn
überhaupt in eine Ampel übersetzt — und die Integration in die App
bräuchte einen anderen Plan.

## Methode

- **Angepasst wird auf den Anpassjahren (≤ 2018), geprüft auf den
  Prüfjahren (≥ 2019)** — dieselbe Trennlinie wie beim Optimum, über
  dieselbe Funktion `split_by_year`. Schwellen auf den Daten zu setzen,
  auf denen man sie danach prüft, wäre Selbstbestätigung.
- **Das Optimum je Art kommt aus den Anpassjahren**, wie gehabt. Die
  Schwelle wird für DIESES Optimum bestimmt; beide gehören zusammen.
- **Zwei Quantile je Art werden berichtet**: das über alle
  Vergleichstage und das **jahresbalancierte** (jedes Jahr zählt gleich
  viel). Grund: Ein gutes Pilzjahr liefert mehr Funde und damit mehr
  Vergleichstage, die Verteilung erbt also den Melde-Eifer. Ob das
  zählbar etwas ändert, ist eine Zahl und keine Meinung — deshalb stehen
  beide da.

## Was hier NICHT entschieden wird

Kein App-Code. Diese Stufe ändert `ampel_model.dart` nicht — sie liefert
die Zahlen, mit denen darüber entschieden wird. Der Gleichlauf „Zahl für
Zahl" zwischen Modellkern und Werkzeug bleibt bis dahin unberührt.

Und die Grenze des Konzeptpapiers gilt unverändert: Auch eine kalibrierte
Schwelle sagt „die Bedingungen sind günstig", nicht „hier stehen Pilze".

## Nachtrag 2026-09-12: was herausgekommen ist

Die Registrierung oben bleibt, wie sie war. Hier steht, wie beide
Vorhersagen ausgegangen sind — Ergebnis:
`docs/pilzampel-schwellen-messung.md`.

### Vorhersage 1: nicht bestätigt

Der Median der sechs Mykorrhiza-Arten liegt auf den Anpassjahren bei
**39,7 %** (für 0,2) und **69,7 %** (für 0,5). Registriert waren
45–55 % und 75–85 %; beide Bänder sind knapp verfehlt.

**Der Fehler liegt in der Registrierung, nicht in der Messung.** Das
Band war aus dem Stufenvergleich abgeleitet — und der rechnet auf den
**Prüfjahren**. Dort liegt der Median bei **79,9 %**, also mitten im
registrierten Band. Gemessen wird aber auf den Anpassjahren, weil diese
Zahlen die Schwellen setzen.

### Der eigentliche Befund: die Schwelle altert

Zwischen den beiden Zeitscheiben liegen im Median rund **8
Prozentpunkte**, und alle sechs Arten wandern in dieselbe Richtung —
beim Herbsttrompete sind es 17 (63,7 % → 81,0 %).

Im Klartext: **Die ausgelieferte 0,5 ist heute eine deutlich strengere
Schwelle als zur Zeit ihrer Festlegung.** Vor 2019 wurde sie an rund
30 % der Vergleichstage überschritten, seither nur noch an rund 20 % —
ohne dass je eine Zeile Code geändert wurde. Die Ampel ist im Feld still
pessimistischer geworden.

Ob dahinter trockeneres Wetter steckt oder eine gewachsene, anders
verteilte GBIF-Stichprobe, trennt diese Messung **nicht**. Für die App
ist die Folge dieselbe: Eine als Score eingefrorene Schwelle behält ihre
Bedeutung nicht.

### Vorhersage 2: Latte verfehlt, Effekt vorhanden

Beim Austernseitling steigt der Abstand von **−0,2 pp** auf **+8,1 pp**
[+0,9, +15,8]. Der Bereich schließt die Null aus, die vorab gesetzte
Latte von +10 pp ist trotzdem nicht genommen.

**Zur Offenlegung:** Der erste Lauf, mit den vorab *erwarteten*
Quantilen 50/80, ergab **+10,1 pp** — die Latte wäre genommen gewesen.
Maßgeblich ist der Lauf mit den **gemessenen** Quantilen 40/70, weil die
Registrierung genau das vorschreibt: einmal runden, an den sechs Arten
der App, vor der Prüfung von Vorhersage 2. Beide Zahlen stehen hier,
damit niemand die passende aussuchen muss — auch ich nicht.

**Und die Latte war das falsche Maß.** Wie groß der Abstand ausfällt,
hängt am gewählten Quantil; nach Vorhersage 1 ist dessen Wahl aber keine
vorgefundene Größe mehr, sondern eine Entscheidung. Eine Latte in
Prozentpunkten unterstellt eine Schwelle, die feststeht.

### Was daraus für die App folgt

1. **Die Schwellen sind kalibrierbar, und es lohnt sich.** Der
   Austernseitling geht von „in Stufen nicht sichtbar" zu einem echten
   Abstand; Hallimasch (+36,7 → +53,2 pp) und Stockschwämmchen
   (+34,1 → +44,0 pp) gewinnen deutlich.
2. **Eine eingefrorene Zahl verfällt.** Wer sie ausliefert, muss
   dazusagen, wann sie zuletzt gemessen wurde — und sie nachmessen. Das
   Werkzeug dafür ist jetzt ein Befehl.
3. **Wie oft die Ampel „günstig" sagt, ist eine Produktentscheidung.**
   Mit dem 70-%-Quantil stünde sie im Median an **21,8 %** der
   Vergleichstage auf günstig statt an 20,3 % heute — bei den einzelnen
   Arten aber viel weiter gestreut (16,7 bis 34,2 %, heute 16,2 bis
   25,5 %). Das ist keine Messfrage.
4. **Und die Drift schlägt sofort durch.** Ein auf den Anpassjahren
   gesetztes 70-%-Quantil müsste „günstig" an 30 % der Vergleichstage
   zeigen; auf den Prüfjahren sind es 21,8 %. Die fehlenden gut acht
   Punkte sind genau die gemessene Drift — dieselbe Zahl, von der
   anderen Seite gesehen. Eine Schwelle, die als Score eingefroren
   wird, verfehlt ihre eigene Zusage in dem Moment, in dem sie
   ausgeliefert wird.
