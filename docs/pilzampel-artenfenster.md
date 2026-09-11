# Artenspezifische Temperaturfenster — Konzept und Prüfplan

Stand: 2026-09-11 · Gehört zu `docs/pilzampel-konzept.md` und
`docs/pilzampel-validierung.md` · Noch **nichts davon ist gebaut**.

## Warum das kein Feature ist, sondern ein Experiment

Die Ampel rechnet heute für jede Art dieselbe Glocke: Gipfel bei 13 °C,
Breite 5 K, aus einer Steinpilz-Arbeit an einem Standort. Der
naheliegende Wunsch lautet, das je Art zu unterscheiden.

**Dieser Wunsch ist genau die Frage, an der die Validierung
hängengeblieben ist.** Die Arten-Kontrolle vom 2026-08-13 ist
durchgefallen: Dieselbe 13-°C-Glocke passt beim Hallimasch (AUC 0,718)
und beim Stockschwämmchen (0,704) so gut wie bei den Mykorrhiza-Arten.
Zwei Lesarten passen gleich gut, und die Daten trennen sie nicht:

1. Das Modell misst **allgemeines Pilzwetter** — dann wäre eine
   Unterscheidung je Art Zierrat auf einer Aussage, die es gar nicht
   trifft.
2. Diese Arten **teilen schlicht dasselbe Fenster** — dann taugen sie
   nicht als Gegenprobe, und je Art zu unterscheiden ist sinnvoll, nur
   eben an anderen Arten zu zeigen.

`docs/pilzampel-validierung.md` schließt daraus: „Solange das offen ist,
bleibt eine Ampel je Art unbegründet." Das gilt weiter. **Ein
artenspezifisches Temperaturfenster einzubauen, wäre also nicht der
nächste Schritt — es einzumessen ist der Weg, die Frage zu
beantworten.** Fällt sie zugunsten von Lesart 1 aus, wird nichts
gebaut, und das Ergebnis gehört genauso veröffentlicht wie die
durchgefallene Kontrolle.

## Was die Literatur hergibt — und die Falle darin

**Es gibt keine Tabelle „Art → Temperaturfenster" für unsere sechs
Arten.** Gesucht, nicht gefunden. Was es gibt:

- **Eine einzige belastbare Feldzahl für eine unserer Arten:** die
  Bielefelder Steinpilz-Reihe (13 °C über 20 Tage). Zehn Jahre, aber
  ein Standort, eine Art, Preprint — steht schon im Konzeptpapier.
- **Belege, dass Artunterschiede real sind, ohne Zahlen dafür:**
  [Andrew et al. 2018, *Ecology*](https://esajournals.onlinelibrary.wiley.com/doi/10.1002/ecy.2237)
  werten europaweite Fruchtungsdaten aus und finden, dass
  artspezifische Phänologie-Prädiktoren **nicht stabil** sind, sondern
  vom Gruppenmittel abweichen. Für boreale Mischwälder in Ostkanada
  ist die **Spanne** der Bodentemperatur bei sechs von sieben Arten der
  stärkste Prädiktor des Fruchtungsbeginns
  ([Sirois et al. 2010](https://www.sciencedirect.com/science/article/abs/pii/S0378112710002288)).
  Beides sagt „je Art verschieden", keines sagt „und zwar so".
- **Eine harte Zahl für die Gegenprobe:** *Pleurotus ostreatus*
  (Austernseitling) braucht zum Fruchten einen **Temperatur-Abfall auf
  4–18 °C**; im Anbau wird das Myzel bei 25 °C durchwachsen und dann
  bewusst auf ~15 °C heruntergekühlt, um Primordien auszulösen
  ([Übersicht in PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC10876731/)).

**Und die Falle, in die man dabei tritt:** Der weitaus größte Teil der
publizierten „Temperaturoptima" für Pilze sind **Myzel-Wachstumsoptima
aus dem Labor** — für viele Arten 24–28 °C. Das ist eine völlig andere
Größe als die Feldtemperatur vor der Fruchtung, und beim Austernseitling
zeigen sie sogar in entgegengesetzte Richtungen: 25 °C wachsen, 15 °C
fruchten. Wer Laborwerte in diese Ampel einträgt, baut ein Modell, das
zuverlässig das Falsche sagt. Das Konzeptpapier hält denselben
Denkfehler schon in anderer Form fest („Myzel ≠ Fruchtkörper").

**Folgerung: Wir müssen messen, nicht nachschlagen.** Und wir können es:
`tool/ampel_validate.py` holt je Art 300–2000 Fundtage aus GBIF und
rechnet das Wetter dazu rückwärts. Das ist mehr Material, als jede der
gefundenen Arbeiten je Art hatte.

## Die Falle in der Messung: Optimum ≠ Saisonmittel

Der naive Weg wäre, je Art die mittlere Temperatur an Fundtagen zu
bilden und sie zum Optimum zu erklären. **Das misst die Jahreszeit, nicht
die Temperatur.** Eine Art mit Gipfel im Dezember hat kalte Fundtage,
weil Dezember kalt ist — daraus folgt nichts über einen Auslöser.

Richtig ist die Frage, die der bestehende Aufbau ohnehin stellt:
**Welches Optimum trennt einen Fundtag am besten von einem nahen Tag
ohne Fund am selben Ort?** Der Vergleichstag liegt 14–45 Tage daneben,
das Vorzeichen wird gewürfelt — die Saison kürzt sich damit im Mittel
heraus, und genau das belegt die Placebo-Kontrolle, die für alle neun
Arten bei ~0,50 liegt.

Das Optimum wird also **auf die gepaarte AUC angepasst**, nicht auf die
Fundtage. Gitterlauf über 2…20 °C in 0,5-K-Schritten, je Art das
Maximum. Die Regenhälfte bleibt unangetastet.

**Ein Nebenbefund, auf den zu achten ist:** Wandert das beste Optimum an
den Rand des beobachteten Bereichs, ist die Glocke über diesem Bereich
faktisch eine Gerade — das Modell sagt dann „je kälter, desto besser".
Das ist kein Optimum mehr, sondern der Hinweis, dass die Glockenform für
diese Art falsch ist. Ein solcher Ausgang gehört benannt und nicht als
Zahl weitergereicht.

## Der Prüfplan

### 1. Die Vorhersage steht VOR der Messung

Das ist die tragende Zeile dieses Papiers. Wer erst rechnet und danach
aufschreibt, was herauskam, hat nichts geprüft — bei neun Arten und
einem freien Parameter findet sich immer eine Verbesserung. Deshalb hier,
vorab und nachlesbar:

> **Primäre Hypothese (Austernseitling).** Sein angepasstes Optimum
> liegt **unter 9 °C**, also mehr als 4 K unter dem heutigen Wert, und
> seine gepaarte AUC steigt damit auf **≥ 0,55** — in Jahren, die an der
> Anpassung nicht beteiligt waren.
>
> Grund für genau diese Art: Sie ist die einzige, bei der Literatur
> (Kältereiz 4–18 °C), Saisonkurve (Gipfel Dezember) und unsere eigene
> Messung (AUC 0,465 mit 13 °C — kein Effekt) unabhängig voneinander
> dasselbe sagen. `docs/pilzampel-konzept.md` benennt sie bereits als
> Kandidatin: „das ist eine Art, nicht drei."

Trifft das zu, ist Lesart 2 belegt: Arten haben verschiedene Fenster,
und die bisherige Kontrolle ist an ihrer Auswahl gescheitert, nicht am
Modell. Trifft es nicht zu, bleibt Lesart 1 stehen — und mit ihr die
Regel, dass keine Unterscheidung je Art gebaut wird.

### 2. Angepasst und geprüft wird auf getrennten Jahren

Das Optimum auf denselben Paaren anzupassen, an denen es danach gemessen
wird, macht die AUC zur Selbstbestätigung — derselbe Fehler, den das
Konzeptpapier beim Saisonfaktor schon vermeidet („ihn mitzurechnen hieße,
das Modell mit sich selbst zu bestätigen").

Getrennt wird nach **Jahren**, nicht nach Funden: Pilzjahre unterscheiden
sich um den Faktor zehn, und Funde desselben Jahres sind einander
ähnlicher als Funde verschiedener Jahre. Ein zufälliger Fund-Split würde
diese Ähnlichkeit über die Trennlinie tragen und die Prüfung zu optimistisch
machen.

- **Anpassung:** 2006–2018
- **Prüfung:** 2019–2025 (2026 zählt wie überall nicht mit, die Saison
  läuft noch)
- **Vertrauensbereich:** Bootstrap über die Prüfjahre, nicht über die
  Funde — aus demselben Grund.

### 3. Nur ein freier Parameter

Die Breite der Glocke (σ = 5 K) ist ebenfalls gesetzt und nicht gemessen.
Sie mit anzupassen wäre verlockend und verdoppelt die Freiheitsgrade —
bei der Herbsttrompete mit 296 Paaren, vor dem Jahres-Split, ist das der
Weg ins Rauschen. **σ bleibt zunächst geteilt und fest.** Erst wenn das
Optimum je Art trägt, ist σ eine eigene Frage.

### 4. Welche Arten den Test tragen können

Die Paarzahlen aus der bestehenden Validierung, halbiert durch den
Jahres-Split, entscheiden mit:

| Art | Paare heute | trägt den Test? |
|---|--:|---|
| Steinpilz | 1996 | ja |
| Maronenröhrling | 1980 | ja |
| Hallimasch | 1966 | ja |
| Pfifferling | 1336 | ja |
| Stockschwämmchen | 1282 | ja |
| Birkenpilz | 1202 | ja |
| Austernseitling | 1009 | ja — **die primäre Hypothese** |
| Fichtenreizker | 772 | knapp |
| Herbsttrompete | 296 | **nein** — als Beifund führen, nicht als Beleg |

### 5. Was „nein" heißt, vorab festgelegt

Damit ein Ergebnis auch dann etwas wert ist, wenn es unbequem ist:

- **Die primäre Hypothese verfehlt** (Austernseitling bleibt unter 0,55
  oder sein Optimum bleibt über 9 °C) ⇒ Es wird **nichts gebaut**. Der
  Befund kommt in `pilzampel-validierung.md`, wie die durchgefallene
  Kontrolle auch.
- **Alle sechs Mykorrhiza-Optima landen innerhalb ±1,5 K um 13 °C** und
  die Prüf-AUC verbessert sich nicht ⇒ Lesart 1 ist gestützt: Das Modell
  misst allgemeines Pilzwetter. Auch das gehört veröffentlicht — es
  begrenzt, was die Ampel je behaupten darf.
- **Einzelne Arten verbessern sich, die primäre Hypothese nicht** ⇒
  Beifund, kein Beleg. Bei neun Arten ist eine Verbesserung durch Zufall
  zu erwarten; ohne die vorab benannte Art bleibt es Rauschen mit
  Nachkommastellen.

### 6. Wenn es trägt — was dann zu tun ist

Nicht sofort ausliefern. Drei Dinge kommen zuerst:

1. **Beide Modellkerne ändern**, `lib/features/ampel/ampel_model.dart`
   und `tool/ampel_validate.py`, Zahl für Zahl gleich — die
   Spiegel-Regel steht in beiden Dateiköpfen.
   `ampelOptimumC` wird dabei von einer Konstante zu einer Zuordnung
   Art → Optimum, mit dem heutigen Wert als Rückfall für alles ohne
   eigene Messung.
2. **`ampelValidatedSpecies` neu bestimmen.** Heute stehen dort sechs
   Arten; eine Art mit eigenem, geprüftem Fenster gehört dazu, eine ohne
   nicht — auch dann nicht, wenn sie beliebt ist.
3. **Die Anzeige muss es sagen.** Eine Ampel, die für zwei Arten am
   selben Ort verschiedene Stufen zeigt, braucht dafür einen Satz;
   sonst liest sich der Unterschied wie ein Fehler.

## Was der Lauf praktisch kostet — und die Falle darin

Die Wetterdaten des 2000er-Laufs vom 12./13. August liegen gesichert in
`~/pilzbuddy-ampel2000/ampel_cache` (334 Dateien, 51 MB, Marke `fertig`).
Die Anpassung je Art braucht dieselben Reihen — sie rechnet nur anders
damit. **Trotzdem war der Bestand am 2026-09-11 größtenteils
unbrauchbar, und der Grund ist lehrreich genug, um ihn hier
festzuhalten.**

**Der Cache-Schlüssel ist der Hash der geordneten ORTSLISTE** eines
Jahres (`_cache_key`), und die Datei selbst enthält nur die Reihen, keine
Koordinaten. Wer die Ortsliste nicht exakt reproduziert, findet nichts
wieder — und kann auch nicht nachsehen, wozu eine Datei gehört.

**Und die Ortsliste ist nicht stabil, weil GBIF wächst.** Gemessen an
zwei Läufen derselben Art im Abstand von zwei Stunden, mit demselben
Seed:

| | ~19:30 | ~21:30 |
|---|--:|--:|
| Steinpilz, Orte 2025 | 104 | 106 |
| Steinpilz, Funde 2026 | 1 | 7 |

Im September kommen täglich neue Meldungen herein. `random.sample` zieht
aus einer veränderten Grundgesamtheit eine andere Teilmenge — und damit
sind sämtliche Ortslisten andere, auch die der alten Jahre. Der
August-Bestand stammt aus einer Grundgesamtheit, die es nicht mehr gibt,
und die Fundlisten selbst wurden damals nicht gesichert.

**Die Abhilfe steht seit 2026-09-11 im Werkzeug:** `fetch_finds` legt die
Fundliste je Art als `finds_*.json` im Cache ab und liest sie danach von
dort. Damit ist die Stichprobe festgenagelt, die Ortslisten sind es auch,
und ein Lauf über mehrere Tage wird überhaupt erst möglich. Wer bewusst
neu ziehen will, löscht die Dateien — dann ist es eine Entscheidung und
kein Nebeneffekt der Uhrzeit.

**Betriebsregel:** immer mit demselben `--cache` und demselben `--seed`
laufen. Ohne Cache bemisst sich das Kontingent von Open-Meteo nach
Orten × Tagen, reicht für etwa eine halbe Art, und HTTP 429 kommt mitten
in der zweiten.

Nicht getan, bewusst: die Stichprobe verkleinern, um schneller fertig zu
werden. Das ist die eine Abkürzung, die die Zahlen unvergleichbar mit
`pilzampel-validierung.md` machte — und bei den dünnen Arten ginge sie
ins Rauschen.

## Was das Ganze NICHT beantwortet

Die eigenen Funde und Leergänge der App bleiben außen vor — sie sind der
unabhängige Prüfstein aus #199, und wer sie einrechnet, kann mit ihnen
nicht mehr prüfen. Angepasst wird ausschließlich an GBIF.

Und die Grenze des Konzeptpapiers gilt unverändert: Auch ein
artenspezifisches Fenster sagt „die Bedingungen sind günstig", nicht
„hier stehen Pilze". Der Zucker des Baumes, das Wasser aus 30 cm Tiefe
und der Substratvorrat stehen in keiner Wetterreihe.
