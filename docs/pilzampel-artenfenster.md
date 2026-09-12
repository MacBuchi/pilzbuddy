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

## Registriert 2026-09-12: gibt es eine kalte KLASSE?

Der Austernseitling steht bei −3,2 °C und gewinnt +0,174 [+0,108,
+0,248]. Das ist ein belegtes Fenster — aber **eine Art ist keine
Klasse.** Eine Klasse aus einem Mitglied ist eine Art mit einem größeren
Namen, und auf so etwas lässt sich keine Anzeige bauen, die „günstig für
Winterpilze" behauptet.

Der Betreiber hat die beiden fehlenden Mitglieder benannt: **Judasohr**
(*Auricularia auricula-judae*, 3123 Meldungen) und **Samtfußrübling**
(*Flammulina velutipes*, 1222). Beide sind Winterfrüchter, beide stehen
in der Artenliste der App, und — das ist der Punkt — **beide waren an
keiner Anpassung beteiligt.** Sie sind unverbrauchte Daten.

> **Vorhersage, vor der Messung.** Judasohr und Samtfußrübling landen
> beide bei einem Optimum **unter 5 °C**, und beide gewinnen gegenüber
> den ausgelieferten 13 °C mindestens **+0,05** AUC auf ihren
> Prüfjahren.
>
> Die 5 °C sind bewusst großzügig: Die Herbstgruppe liegt zwischen 12,0
> und 14,5 °C. Alles unter 5 trennt eindeutig, ohne dass die Grenze
> nachträglich passend gewählt werden müsste.

**Was ein Treffer bedeutet:** Drei Arten mit kaltem Fenster, unabhängig
voneinander gemessen — dann existiert die Klasse, und die Ampel darf für
sie sprechen.

**Was ein Fehlschlag bedeutet:** Der Austernseitling bleibt ein
Einzelfall. Dann ist „kalt" keine Klasse, sondern eine Eigenschaft
dieser einen Art, und die Ampel bleibt für sie grau — so wie heute.

**Und was in beiden Fällen NICHT passiert:** eine Klasse aus zwei
Arten, von denen eine passt. Beide oder keine.

## Registriert 2026-09-12 (abends): gibt es „Herbst-Holz"?

Hallimasch (11,0 °C) und Stockschwämmchen (12,2 °C) sind in Stufen die
größten Gewinner von allen neun Arten — mit eigenem Fenster und eigener
Schwelle steigt ihr Abstand von +36,7 auf **+53,2 pp** bzw. von +34,1
auf **+44,0 pp** (`docs/pilzampel-schwellen-messung.md`). Sie stehen
trotzdem grau in der App, und zwar aus genau einem Grund: **ausgewählt
wurden sie, nachdem wir die Tabelle gesehen hatten.** Dieselbe Lage, in
der der Pfifferling vor Österreich stand.

**Wie viel davon ist das Fenster?** Aufgeschlüsselt: Beim Hallimasch
bringt das Fenster allein +11,1 pp und die Schwelle weitere ~5,4; beim
Stockschwämmchen ist es umgekehrt (+3,2 aus dem Fenster, ~6,7 aus der
Schwelle). Zu belegen ist also das FENSTER — die Schwelle folgt daraus
und braucht keine eigene Prüfung.

> **Vorhersage, vor der Messung.** Das an deutschen Funden angepasste
> Fenster der Klasse trennt auch in **Österreich und der Schweiz**
> besser als die 13 °C — gepaarte AUC dort mindestens **+0,05** über
> der mit 13 °C, und zwar bei **beiden** Arten.

Das Fenster selbst ist **abgeleitet und nicht gewählt**: der Median der
Optima ihrer Mitglieder, also **11,625 °C** aus 11,0 (Hallimasch) und
12,25 (Stockschwämmchen). Die Vorhersage hängt an der Latte, nicht an
dieser Zahl.

*Zwei Korrekturen an derselben Zahl, beide am 2026-09-12:* Zuerst stand
hier **11,5 °C** — von Hand zwischen den Mitgliedern gerundet und damit
die einzige erfundene Zahl in einer sonst vollständig gemessenen
Tabelle. Das Werkzeug wachte über die *Schwellen* einer Klasse, nicht
über ihr *Fenster*, hätte es also nicht gemerkt; `class_optimum` rechnet
es seither nach. Danach stand **11,6 °C** — aus der Berichtstabelle
abgeschrieben, die eine Dezimalstelle zeigt. Derselbe Fehler in klein,
und gefunden hat ihn dieselbe Prüfung. Die Fehlermeldung nennt jetzt
alle Stellen, damit der Nächste nicht wieder eine gerundete Zahl
abschreibt.
>
> Dazu, ohne Torfunktion, eine Richtungsaussage: Die in AT+CH neu
> angepassten Optima beider Arten liegen **unter 13 °C**.

**Die Latte ist hier härter als beim Pfifferling, und das ist Absicht.**
Sein Fenster lag 4,5 K neben den 13 °C und gewann +0,104; hier sind es
1,5 K. Ein so kleiner Versatz kann echt sein und die +0,05 trotzdem
nicht schaffen — die Glocke ist in ihrer Mitte flach. Die Latte bleibt
gleich, weil eine je Fall angepasste Latte keine Vorhersage mehr ist,
sondern eine Formsache.

**Was ein Fehlschlag deshalb bedeutet:** „bei dieser Stichprobengröße
und diesem Abstand nicht nachweisbar" — nicht „es gibt keinen
Unterschied". Ausgeliefert wird die Klasse dann trotzdem nicht: Der
Vorbehalt der App gilt dem, was belegt ist, und nicht dem, was plausibel
ist. Die Richtungsaussage entscheidet dann, ob sich ein dritter Anlauf
mit mehr Material lohnt oder ob die beiden in die Herbstklasse gehören.

**Und was auch hier nicht passiert:** eine Klasse aus zwei Arten, von
denen eine besteht. Beide oder keine — wie beim Kalttest. Besteht nur
der Hallimasch, ist „Herbst-Holz" eine Art mit einem großen Namen.

Kosten: zwei Arten aus AT und CH, dazu deren Wetterreihen — also etwa
zwei Tageskontingente, nach dem Kalttest.

## Zur allgemeinen Frage: alle Arten einordnen

Der Betreiber am 2026-09-12: „Generell finde ich, dass wir alle Arten,
die wir listen, kategorisieren sollten."

Richtig — mit einer Trennung, die durchgehalten werden muss:
**Einordnen ist billig, eine Klasse BELEGEN ist teuer.** Die App listet
110 Arten; für die meisten davon hat GBIF zu wenig Deutschland-Material,
und eine Einordnung aus der Literatur ist eine Vermutung, keine Messung.

Die Regel dafür steht schon in der App und muss nur weitergelten: Was
nicht gemessen ist, bleibt **grau**. Eine Art darf also einer Klasse
zugeordnet sein, ohne dass die Ampel für sie spricht — die Zuordnung
ordnet, die Messung erlaubt eine Aussage. Verwechselt man beides, hat man
110 Arten mit Farbe und drei mit Deckung.

## Wo die Daten liegen — drei Orte, drei Aufgaben

Festgelegt vom Betreiber am 2026-09-12, nachdem eine Sicherung fast
verloren gegangen wäre.

| Ort | Was | Wann |
|---|---|---|
| `~/pilzbuddy-ampel2000/ampel_cache` | Arbeitsstand, `--cache` zeigt hierher | laufend |
| `…/nextcloud_msb/Claude_exchange/pilzampel-validierung/` | Spiegel, über Nextcloud synchronisiert | nach jedem Abruf |
| Release `ampel-2000` in `pilzbuddy-backups` | gezippter Stand | **nach jedem Validierungslauf** |

**Warum das Archiv nach dem LAUF entsteht und nicht davor.** Ein Stand,
der vor dem letzten Abruf gezogen wurde, ist der Stand eines
Zwischenschritts — genau das ist am 2026-09-11 passiert: hochgeladen um
22:33, zwei Art-Jahre nachgeholt um 00:40, und das Archiv zeigte einen
Stand, mit dem nie gerechnet wurde. Gesichert gehört der Stand, der zu
einem Ergebnis GEFÜHRT hat; nur der ist nachvollziehbar.

**Und die `finds_*.json` sind der Teil, an dem alles hängt** (siehe den
Abschnitt darüber). Ein Archiv ohne sie ist 51 MB, die niemand mehr
adressieren kann.

## Nachtrag 2026-09-11: die Pfifferling-Spur

Der erste Lauf über sieben Arten hat einen Ausreißer geliefert:
**Pfifferling, Optimum 19,2 °C statt 13, AUC auf Prüfjahren 0,590 →
0,656, Differenz +0,067 [+0,012, +0,113]** — als einzige Art ein
Bereich, der die Null ausschließt. Dazu passt dreierlei: Er ist ein
Sommerfrüchter, er war in der ursprünglichen Validierung die einzige
Mykorrhiza-Art mit schwachem Befund (AUC 0,572), und der Gewinn ist auf
Jahren gemessen, an denen nicht angepasst wurde.

**Trotzdem ist das kein Beleg, und zwar aus einem Grund, den keine
weitere Rechnung an denselben Daten behebt:** Ausgewählt wurde die Art
NACH dem Blick auf die Tabelle. Bei sieben Arten und einem freien
Parameter sticht eine auch bei reinem Zufall heraus; die Zeitscheibe
2019–2025 ist zwar ungesehen, die Auswahl der Art ist es nicht.

### Was die Spur bestätigen würde — vorab festgelegt

> **Geografischer Hold-out.** Das an DEUTSCHEN Funden angepasste Optimum
> des Pfifferlings (19,2 °C) trennt auch in **Österreich und der
> Schweiz** besser als die 13 °C — gepaarte AUC dort mindestens 0,05
> über der mit 13 °C, auf Meldungen, die an der Anpassung nie beteiligt
> waren.

Warum ausgerechnet das: Es sind **neue Daten**, nicht neu geschnittene.
Die Frage lautet, ob 19,2 °C eine Eigenschaft der Art ist oder eine der
deutschen Stichprobe — und andere Länder beantworten sie, andere Jahre
nicht mehr.

Kosten: Pfifferling-Meldungen aus AT und CH über `country` in
`fetch_finds`, dazu deren Wetterreihen. Das ist eine Art, also etwa ein
Tageskontingent.

### Die schwache Zusatzprüfung, die nichts kostet

> **Über die Arten hinweg sollte das angepasste Optimum mit der
> Fruchtungszeit laufen:** früher im Jahr fruchtende Arten wärmer,
> späte kälter.

Die Saisonkurven liegen in `docs/pilzampel-saisonkurven.md` und sind an
der Anpassung nicht beteiligt. Mit sieben bis neun Punkten trägt das
keine Statistik — es ist eine Richtungsaussage, und ihr Wert liegt
darin, dass sie auch SCHEITERN kann: Käme heraus, dass die Optima
quer zur Saison liegen, wäre die Erklärung „Sommerfrüchter, also
wärmer" hinfällig, und der Pfifferling-Befund stünde ohne Mechanismus
da.

> **Gemessen am 2026-09-12** (`docs/pilzampel-schwellen-messung.md`,
> Abschnitt „Läuft das Fenster mit der Fruchtungszeit?"): Spearman
> **−0,678** über alle neun Arten, **−0,830** über die acht mit einer
> Kurve, die überhaupt eine Saison hat. Die Richtung stimmt also, und
> sie ist bei n=8 nicht mehr nur ein Wink.
>
> **Das Maß entschied alles.** Mit dem Gipfelmonat kamen −0,494 heraus,
> mit einem LINEAR gemittelten Monat −0,068 — und beides sagte nichts
> über die Sache, sondern über das Maß: Ein lineares Mittel über eine
> Zwölferreihe schiebt den Austernseitling von seinem Dezembergipfel in
> den Juni, weil Dezember und Januar dort weit auseinanderliegen. Auf
> dem Kreis gemittelt steht er bei 12,8.
>
> **Was das für die 85 Arten ohne eigene Messung bedeutet** (Betreiber
> am 2026-09-12: „Arten mit sehr ähnlichen Bedingungen können wir
> zusammenfassen und da müssen wir nicht jede einzelne Art aufwendig
> validieren"): Die Rangfolge trägt eine Zuordnung zu einer KLASSE. Sie
> trägt keine Gradzahl je Art — der Zusammenhang ist nicht linear, von
> Monat 9,3 auf 10,5 fällt das Optimum um 2 K und von 9,3 auf 12,8 um
> 16. Eine Gerade durch diese Punkte wäre erfunden.
>
> **Und der Kalttest ist bereits ihr erster echter Test.** Judasohr und
> Samtfußrübling sind über ihre Saison als Winterarten eingeordnet, und
> die registrierte Vorhersage sagt beide unter 5 °C. Trifft sie zu, ist
> die Zuordnung nach Saison nicht nur korreliert, sondern vorhersagend —
> auf Arten, die an keiner Anpassung beteiligt waren.

### Was NICHT passiert, solange beides offen ist

Kein eigenes Fenster im ausgelieferten Modell — auch nicht „nur für den
Pfifferling, der ist ja klar". Genau so entstehen die Zahlen, die
niemand mehr prüfen kann.

## Was das Ganze NICHT beantwortet

Die eigenen Funde und Leergänge der App bleiben außen vor — sie sind der
unabhängige Prüfstein aus #199, und wer sie einrechnet, kann mit ihnen
nicht mehr prüfen. Angepasst wird ausschließlich an GBIF.

Und die Grenze des Konzeptpapiers gilt unverändert: Auch ein
artenspezifisches Fenster sagt „die Bedingungen sind günstig", nicht
„hier stehen Pilze". Der Zucker des Baumes, das Wasser aus 30 cm Tiefe
und der Substratvorrat stehen in keiner Wetterreihe.
