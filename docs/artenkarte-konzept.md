# Artenkarte: „wo finde ich diesen Pilz bei mir?"

Konzept zu Issue #414. **Noch nichts gebaut** — diese Seite entscheidet,
ob und wie.

Die Frage stammt vom Betreiber (2026-09-08) und ist die eine, die die App
heute nicht beantworten kann: Sie weiß, wo man SCHON war. Wo man
hingehen sollte, sagt sie nicht.

> **Zweite Fassung, 2026-09-09.** Der Betreiber hat drei Dinge
> nachgeschoben, und alle drei sitzen an Stellen, an denen die erste
> Fassung zu grob war: die Temperaturnische je Art (Winterpilze wachsen
> nicht bei Sommerbedingungen), das Offenland (der Parasol steht auf der
> Wiese) und die ausdrückliche Rolle der Fundhistorie. Was sich dadurch
> geändert hat, steht in „Was die zweite Fassung ändert" am Ende.

## Was da ist, und was fehlt

| Baustein | Wo | Abdeckung |
|---|---|---|
| Saisonkurve je Art, monatlich, effort-korrigiert | `lib/core/season_curves.g.dart` aus `tool/season_curves.py` | **91 Arten** mit ≥200 GBIF-Meldungen |
| Führende Laub- und Nadelart je Wabe | `lib/features/map/forest_species.dart` | **nur Deutschland** |
| Waldklasse (Laub/Misch/Nadel/**kein Wald**) | Waldgitter (Copernicus) | DACH |
| Höhe | Höhengitter (Copernicus DEM) | DACH |
| Regen, Temperatur des Tages | die bestehenden Gitter und Stationen | DACH |

Alles liegt auf dem Gerät, alles auf **demselben Hexgitter**, ein
`hexNearestCell` je Wabe. Das ist der Grund, warum das Ganze überhaupt
denkbar ist: kein neues Netzziel, keine neue Zustimmung, offline nutzbar.

**Es fehlt genau eine Sache: die Verknüpfung Pilz → Standort.**
`KnownSpecies` trägt Name, Gruppe, Zweitnamen und den wissenschaftlichen
Namen. Kein Habitat, keinen Partnerbaum, keine Temperaturnische. Ohne sie
lässt sich Landschaft nicht in eine Aussage über eine BESTIMMTE Art
übersetzen — und damit steht und fällt das Feature.

## Die Saisonkurve IST die Fundhistorie

Das gehört an den Anfang, weil es sonst wie eine Lücke aussieht: Die
Frage „warum berücksichtigt die Karte nicht, wann diese Art tatsächlich
gefunden wird?" ist bereits beantwortet. `season_curves.g.dart` ist genau
das — 2 009 375 GBIF-Pilzmeldungen aus DACH als Grundgesamtheit, je Art
mindestens 200 eigene, und effort-korrigiert: Der Monatsanteil der Art
wird durch den Monatsanteil ALLER Pilze geteilt. Sonst misst die Kurve
mit, wann Menschen in den Wald gehen, und nicht, wann der Pilz wächst.

Der Austernseitling steht dort so da:

    Jan  Feb  Mär  Apr  Mai  Jun  Jul  Aug  Sep  Okt  Nov  Dez
     92   60   19    5    2    3    3    2    3    8   27  100

**Die EIGENEN Funde bleiben draußen.** Zwei Gründe, und beide sind
hart. Erstens sind sie zu dünn: Ein paar Funde je Art ergeben keine
Jahreszeit, und eine Kurve aus drei Punkten sähe genauso aus wie eine
aus dreitausend. Zweitens hebt #199 sie ausdrücklich als **unabhängigen
Prüfstein** auf — wer sie in die Rechnung nimmt, kann mit ihnen nicht
mehr prüfen, ob die Rechnung stimmt.

Als PERSÖNLICHER Hinweis sind sie trotzdem etwas wert („hier hattest du
schon einmal Glück"), aber das ist eine andere Aussage als die der
Karte, und sie gehört neben sie, nicht hinein. Eigenes Issue, wenn
überhaupt.

## Drei Arten von Standort, nicht eine

Die erste Fassung kannte nur Mykorrhiza: Pilz sucht Baum. Das ist für
die Röhrlinge und Täublinge richtig und lässt genau die Arten fallen,
die auf der Wiese stehen. In der Artenliste sind das **Parasol**
(inkl. Riesenschirmling), **Wiesenchampignon**, **Schopftintling**
(inkl. Spargelpilz), **Riesenbovist** und **Nelkenschwindling** — fünf
Hauptnamen, keine Randerscheinung. Für sie hätte die alte Regel „kein
Wald ⇒ 0" die Wiese schwarz gemalt, also die richtige Antwort ins
Gegenteil verkehrt.

Deshalb trägt die Tabelle je Art **einen Standorttyp**:

| Typ | Was „guter Ort" heißt | Beispiele |
|---|---|---|
| `mykorrhiza` | der Partnerbaum steht da | Birkenpilz, Fichtensteinpilz, Pfifferling |
| `offenland` | **kein** Wald: Wiese, Weide, Park | Parasol, Nelkenschwindling, Riesenbovist |
| `holz` | totes oder krankes Holz einer Baumgruppe | Austernseitling, Hallimasch, Stockschwämmchen |

**`holz` bleibt im ersten Ausbau ohne Aussage.** „Totes Laubholz" steht
auf keinem unserer Gitter, und die Waldklasse allein sagt darüber
nichts: In jedem Buchenwald liegt irgendwo Totholz. Der Typ steht
trotzdem in der Tabelle, damit die Karte den Unterschied zwischen „wir
wissen es nicht" und „hier nicht" auch für diese Arten sagen kann.

**Und `offenland` ist absichtlich grob.** Unser Gitter kennt nur „Wald
ja/nein" — ein Parkplatz, ein Maisfeld und eine Streuobstwiese sind
darin dasselbe. Der Faktor ist deshalb gedeckelt (siehe unten): Er darf
eine Wiese nicht so laut empfehlen wie ein Buchenhang einen
Steinpilz. Feiner ginge es mit einer Grünland-Klasse aus derselben
Copernicus-Quelle — das ist ein eigenes Gitter und ein eigenes Issue,
kein Nebenbei.

## Die neun Bäume sind das Vokabular

Das Gitter unterscheidet **Buche, Eiche, Birke, Erle** und **Fichte,
Kiefer, Tanne, Douglasie, Lärche**. Mehr kann eine Verknüpfung nicht
sagen, und weniger braucht sie nicht: Neun Namen lassen sich von Hand
pflegen und einzeln belegen.

Zwei Eigenheiten dieses Vokabulars, die das Konzept tragen muss:

- **Je Wabe nur die FÜHRENDE Laub- und die führende Nadelart.** Das ist
  gemessen und dokumentiert (`tool/forest_species.py`): Die häufigste Art
  allein verschluckte in 17,6 % der Waldzellen den Mischpartner, deshalb
  zwei Halbbytes. Aber ein buchendominierter Hang hat trotzdem Birken.
  **Die Baumangabe ist deshalb ein Hinweis, kein Filter.**
- **Manche Partner fehlen.** Die Espenrotkappe steht mit der Espe, und
  Espe ist keine der neun. Für solche Arten gibt es keine Aussage — und
  „keine Aussage" muss anders aussehen als „hier nicht".

## Woher die Verknüpfung kommt

Drei Wege, und nur einer trägt.

**Von Hand kuratiert, Art für Art belegt.** Das ist der Vorschlag.
Mykorrhiza-Partnerschaften gehören zu den bestbelegten Tatsachen der
Mykologie, und ein erstaunlicher Teil steht **im deutschen Namen**:
Birkenpilz, Fichtensteinpilz, Kiefernsteinpilz, Goldröhrling (Lärche),
Butterpilz (Kiefer), Fichtenreizker. Wo der Name es sagt, ist die
Verknüpfung so sicher wie die Artbestimmung selbst.

Es gelten dieselben Regeln wie für die Pilz-Grafiken
(`.claude/skills/pilz-designer/`): erst nachschlagen, dann eintragen; die
deutsche Wikipedia als Mindestbeleg; und **wo die Quelle nicht eindeutig
ist, bleibt das Feld leer.** Eine falsche Verknüpfung schickt Leute mit
Zuversicht in den falschen Wald — eine fehlende schickt sie nur nicht los.

Verworfen: **GBIF-Habitatfelder** (Freitext, sehr ungleiche Qualität) und
**Ableitung aus den eigenen Funden** (zu dünn, und für eine spätere
Validierung zirkulär — siehe oben).

## Die Temperaturnische je Art

Der Anstoß des Betreibers, und er trifft einen echten Fehler im
AUSGELIEFERTEN Code, nicht nur im Konzept: Die Pilzampel rechnet mit
**einer Glocke für alle Arten** — Optimum 13 °C, σ 5 K
(`ampelOptimumC`, `ampelTempSigma`). Für den Austernseitling an einem
typischen Dezembertag mit 3 °C ergibt das

    exp(−((3 − 13) / 5)²) = exp(−4) ≈ 0,02

Am besten Tag seines Jahres sagt die Ampel also **2 %**. Winterpilze
sind für sie nicht vorgesehen.

### Sie beschreibt den ORT, nicht den Tag

Die erste Fassung ließ das Wetter komplett draußen, mit der Begründung:
Die Ampel beantwortet „ist gerade ein guter Tag", die Karte „ist das
grundsätzlich ein guter Ort". Diese Trennung bleibt — sie ist der Grund,
warum beide Aussagen lesbar bleiben. Was dazukommt, ist keine
Wetterlage, sondern eine **Eigenschaft des Ortes**: wie warm es in
dieser Wabe in diesem Monat ÜBLICHERWEISE ist. Eine Kammlage auf 1400 m
ist im Oktober schlicht ein anderer Lebensraum als der Oberrhein, und
das ändert sich nicht mit dem Wetterbericht.

Billigste ehrliche Fassung, und sie braucht **kein neues Asset**: eine
Monatskurve für das DACH-Tiefland (zwölf Zahlen, aus denselben
historischen Daten wie die Validierung) plus die vorhandene
Höhenkorrektur mit 0,65 K je 100 m auf die Wabenhöhe — Gitter und
Konstante sind seit 1.93.0 im Einsatz. Damit ist die Höhe abgebildet,
und die ist in DACH der bei weitem größte Term. Was so NICHT abgebildet
ist: die Kontinentalität von West nach Ost. Ein Gitter aus
DWD-Klimanormalen 1991–2020 wäre der nächste Ausbau, nicht der erste.

### Die Falle: den Kalender nicht zweimal zählen

Saisonkurve und Temperaturnische beschreiben teilweise dasselbe — wer im
Dezember gipfelt, ist der Winterpilz, und im Dezember ist es kalt. Beide
absolut zu multiplizieren quadrierte das Jahreszeitensignal, und die
Karte wäre im Sommer überall dunkel.

Deshalb wirkt die Nische **relativ**: Die Glocke der Art wird an der
Wabentemperatur ausgewertet UND an der typischen Temperatur desselben
Monats im Tiefland; gerechnet wird der Quotient. An einem
durchschnittlichen Ort ergibt das 1,0, und die Nische verschiebt nur
noch zwischen Tal und Kamm, zwischen Nord und Süd. Genau das war der
Zugewinn, um den es geht.

### Die Nische wird abgeleitet, nicht geraten

Dieselbe GBIF-Stichprobe, aus der die Saisonkurven kommen, trägt Datum
UND Koordinate; historische Temperaturen dazu holt
`tool/ampel_validate.py` heute schon. Daraus fällt je Art heraus, bei
welchen Temperaturen sie tatsächlich gemeldet wurde — mit derselben
Effort-Korrektur wie bei den Kurven, sonst misst man wieder das
Verhalten der Sammler und nicht das der Pilze.

**Der Nebengewinn ist der eigentliche Gewinn:** Dieselbe Tabelle
repariert die 2 % oben. Die Ampel bekäme ihr Optimum je Art statt 13 °C
für alle. Das ist von der Karte ablösbar, kleiner als sie und für die
Nutzer sofort spürbar — es sollte deshalb **zuerst** kommen, wenn die
Zahlen tragen.

**Aber der Riegel bleibt stehen:** Die Rückwärtsvalidierung ist an genau
der Arten-Achse einmal gescheitert (`docs/pilzampel-validierung.md` —
zwei von drei Holzbewohnern passten zum Mykorrhiza-Modell, die
Artspezifik war nicht belegbar). Eine Nische je Art muss also zeigen,
dass sie die eine gemeinsame Glocke **schlägt**, auf einer Hälfte der
Daten angepasst und auf der anderen geprüft. Sonst tauschen wir eine
ehrliche Vereinfachung gegen besser aussehendes Rauschen.

## Wie die Faktoren zusammenkommen

    Eignung(Wabe, Art, Monat)
        = Saison(Art, Monat) × Standort(Art, Wabe) × Nische(Art, Wabe, Monat)

**Saison** ist die Kurve, 0–100. Sie wirkt multiplikativ, weil sie
wirklich ein Tor ist: Im Dezember gibt es keine Pfifferlinge, egal wie
der Wald steht.

**Standort** ist ABGESTUFT, nicht binär — wegen der führenden Art oben:

| Lage | `mykorrhiza` | `offenland` |
|---|---|---|
| Partnerbaum ist die führende Art der Wabe | 1,0 | — |
| Partner passt zur Klasse, ist aber nicht führend | ~0,5 | — |
| falsche Klasse (Nadel-Partner im reinen Laubwald) | ~0,15 | — |
| kein Wald | 0 | **~0,7** (gedeckelt, siehe oben) |
| Wald | — | ~0,1 |
| keine Baumangabe (außerhalb DE) | **keine Aussage** | — |
| kein Eintrag für die Art / Typ `holz` | **keine Aussage** | **keine Aussage** |

**Nische** ist der relative Quotient von oben, um 1,0 herum.

Der wichtigste Punkt der Tabelle ist die letzte Zeile. Eine leere Fläche
in Österreich, die aussieht wie „hier wächst nichts", wäre eine Lüge über
fehlende Daten — derselbe Fehler, den die Wald-Ebene schon einmal
vermeiden musste. Bemerkenswert dabei: Für `offenland`-Arten reicht die
Waldklasse, und die gibt es für ganz DACH. Der Parasol ist also in
Österreich beantwortbar, der Birkenpilz nicht.

**Das TAGESwetter bleibt draußen.** Die Ampel beantwortet den Tag, diese
Karte den Ort. Beides zu multiplizieren machte aus zwei
nachvollziehbaren Aussagen eine, die keiner mehr auseinanderhalten kann
— und die Ampel trägt aus gutem Grund das Wort „experimentell".

## Wie es aussieht

Eine **Kartenebene**, hinter einem eigenen Eintrag im Ebenen-Blatt, mit
einer Artenauswahl. Die Wabenfüllung gibt es schon (Waldebene, #249):
dasselbe Gitter, dasselbe Zeichenverfahren, dieselbe Isolate-Rechnung.

Bewusst NICHT über den bestehenden Filter: Der filtert **deine Spots**,
also Vergangenheit. Diese Ebene malt Möglichkeiten. Zwei verschiedene
Fragen in einem Bedienelement wären eine dritte.

## Was die Karte behaupten darf

Das ist die schärfste Frage, und sie entscheidet über den Wortlaut.

Was hier gerechnet wird, ist **Standorteignung aus Literatur mal Saison
aus Beobachtungen mal Temperaturnische aus Beobachtungen**. Es ist keine
Vorhersage, dass dort Pilze stehen. Der Unterschied ist nicht
akademisch: Eine eingefärbte Fläche liest sich viel zuversichtlicher als
ein Ampel-Banner.

Daraus folgt der Ton: „**Hier passt der Wald zu dieser Art, und die
Jahreszeit stimmt**" — nicht „hier findest du sie". Und in der Legende
steht, woraus sich das speist.

**Eine Validierung ist möglich und gehört dazu**, bevor die Ebene
ausgeliefert wird: Dieselbe GBIF-Stichprobe trägt Koordinaten. Die Frage
lautet: Liegen echte Fundmeldungen einer Art häufiger in Waben mit hoher
Eignung als an zufälligen Waben derselben Region? Das ist dieselbe
AUC-Methode wie bei der Ampel und braucht keine neue Datenquelle.
**Nicht mit unseren eigenen Funden validieren** — die sind die
Stichprobe, die #199 als unabhängigen Prüfstein aufhebt.

Ein Fallstrick, der beim Zuschnitt der Zufallswaben entscheidet: Die
Vergleichswaben müssen aus derselben Region UND demselben Monat kommen.
Sonst gewinnt das Modell schon dadurch, dass Menschen im Oktober im Wald
sind und im Februar nicht.

## Was zuerst

1. **Die Verknüpfungstabelle**, für die zwanzig bis dreißig Arten, die
   wirklich gesammelt werden: Standorttyp, Partnerbäume, Beleg je Zeile
   — und leer, wo die Quelle schwankt.
2. **Die Temperaturnische je Art** aus der GBIF-Stichprobe, samt der
   Hälfte-gegen-Hälfte-Prüfung gegen die gemeinsame Glocke. Trägt sie,
   ist die Ampel-Korrektur der erste sichtbare Gewinn — und sie kommt
   ohne die Kartenebene aus.
3. **Die Validierung** der Eignung aus dem Abschnitt darüber. Fällt sie
   durch, ist das Feature beantwortet, bevor eine Zeile Oberfläche
   entsteht.
4. Erst dann Ebene, Legende und Artenauswahl.

Die Reihenfolge ist Absicht: 1 bis 3 sind Werkzeugarbeit ohne Risiko für
Nutzer, und sie können das Vorhaben abräumen. Schritt 4 ist der teure
Teil.

## Abdeckung, klar gesagt

Baumarten gibt es nur für Deutschland; in Österreich und der Schweiz
bleiben `mykorrhiza`-Arten deshalb ohne Aussage. Waldklasse und Höhe
gibt es für ganz DACH — `offenland`-Arten und die Temperaturnische
funktionieren also überall. Die Ebene sagt das, statt leer zu wirken;
dieselbe Lösung wie beim Wald-Blatt, das die Copernicus- und
DLR-Abdeckung schon nebeneinander nennt.

## Was die zweite Fassung ändert

- **Standorttyp statt „Baum oder nichts".** `offenland` dazu, `holz`
  benannt und ausdrücklich ohne Aussage gelassen. Die alte Regel „kein
  Wald ⇒ 0" hätte für fünf Arten der Liste die richtige Antwort ins
  Gegenteil verkehrt.
- **Temperaturnische je Art** als dritter Faktor — als Eigenschaft des
  ORTES, relativ gerechnet, damit der Kalender nicht doppelt zählt.
- **Die Ampel-Korrektur wird vorgezogen.** Sie fällt als Nebenprodukt
  der Nischen-Tabelle an, ist kleiner als die Kartenebene und behebt
  einen Fehler, der heute in der App steckt.
- **Die Rolle der Fundhistorie steht jetzt ausdrücklich da**, samt der
  Begründung, warum die EIGENEN Funde draußen bleiben.
