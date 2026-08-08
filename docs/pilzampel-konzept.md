# Wetterkarte und Pilzampel — Konzept

Zu den Issues #156 (Niederschlags-Kartenebene) und #158 (Wetterdaten →
Pilzwachstumswahrscheinlichkeit, artabhängig). Stand: 3. August 2026.

Diese Seite klärt, **welche Daten es gibt**, **was sich daraus seriös
ableiten lässt** — und wo die Grenze zur Spielerei verläuft. Sie ist noch
keine Umsetzungsanleitung; sie ist die Entscheidungsgrundlage dafür, ob und
in welchem Zuschnitt gebaut wird.

## Die drei Bausteine

Der Wunsch zerfällt in drei Dinge, die technisch **unterschiedlich schwer**
und unterschiedlich verlässlich sind. Sie sollten nicht zusammen geplant
werden:

| Baustein | Was es zeigt | Verlässlichkeit |
|---|---|---|
| **A — Regenkarte** | Rohdaten, unverarbeitet: wo hat es wie viel geregnet | Messwerte, so gut wie Radar eben ist |
| **B — Pilzampel** | Verarbeitet: wie günstig ist die Lage gerade für Art X | Grobe Tendenz, siehe unten |
| **C — Spot-Erinnerung** | Eigene Historie: „dein Spot war letztes Jahr um diese Zeit ergiebig" | Faktisch — es sind die eigenen Daten |

**C ist heute schon möglich, ohne jede externe Quelle**, weil die komplette
Fundhistorie nach dem App-Start ohnehin im Speicher liegt
(`mySpotsProvider`, `select('*, finds(*)')`). Kein Netz, kein Server, keine
neue Berechtigung — nur eine Auswertungsfunktion und ein Banner. Sie ist
gleichzeitig der ehrlichste Teil: keine Prognose, sondern Erinnerung.

## Was die Wissenschaft hergibt — und was nicht

### Der wichtigste Befund: eine Zahl für alle Pilze wäre falsch

Die Gilde entscheidet, welche Wettergröße überhaupt wirkt
([Sato et al. 2012](https://pmc.ncbi.nlm.nih.gov/articles/PMC3507881/),
30 Jahre, 11.923 Zählungen):

- **Mykorrhizapilze** (Steinpilz, Marone, Pfifferling, Trompeten) fruchten
  klar saisonal und reagieren stark auf Wetter — sie hängen am aktuellen
  Zucker des Baumes.
- **Holzbewohner** (Hallimasch, Stockschwämmchen, Austernseitling) hängen am
  Substrat, nicht an der Saison — Sato misst für sie *minimale* saisonale
  Vorhersagbarkeit. In Katalonien erklärte der **Standort** 56–59 % ihrer
  Varianz, bei Mykorrhizapilzen dagegen das **Jahr** 44 %
  ([Alday/Karavani et al. 2017](https://pmc.ncbi.nlm.nih.gov/articles/PMC5382911/)).

Eine Ampel, die für den Hallimasch dasselbe rechnet wie für den Steinpilz,
ist deshalb nicht ungenau, sondern kategorisch falsch. Der tschechische
Wetterdienst — der weltweit einzige nationale Dienst mit einem Pilzprodukt —
schreibt genau das in seinen Erklärtext: gilt für fleischige, vor allem
**mykorrhizale** Arten.

### Die belastbarsten Zahlen stammen aus einem deutschen Buchenwald

[Brejon Lamartiniere & Hoffman, bioRxiv
2025](https://doi.org/10.64898/2025.12.12.693895): zehn Jahre nahezu
tägliche Steinpilz-Erfassung bei **Bielefeld**.

> Fruchtungs-Peak bei **~13 °C Mitteltemperatur über die vorangegangenen
> 20 Tage**, linear steigend mit dem über **26 Tage kumulierten
> Niederschlag**.

Das ist die Kernformel, und sie stammt aus dem Klima, um das es hier geht.
**Vorbehalt, der mitgeschrieben gehört:** Preprint, nicht begutachtet, ein
Standort, eine Art.

Weitere publizierte Zeitfenster: Morcheln reagieren auf Regenereignisse
>10 mm in den **30 Tagen davor**; für Täublinge und Wulstlinge wurde eine
**Wärmesumme über 3 Wochen** als bester Prädiktor gewählt (Genauigkeit
60–80 %); für Pfifferlinge in Kanada ≥500 Gradtage plus 50–100 mm über
**6–13 Wochen**.

**Daraus folgt die eine Regel, die alle Sammler-Faustformeln schlägt:** Es
zählt die **Kumulation über Wochen**, nicht der letzte Regen. Die
Sammlerregel „3–7 Tage nach Regen" beschreibt das *Strecken* bereits
angelegter Fruchtkörper — nicht ihre Anlage. Beides zu verwechseln ist der
häufigste Denkfehler in Prognose-Apps.

### Was mit reinen Wetterdaten prinzipiell nicht geht

- **Der Zucker des Baumes.** Wird der Saftstrom einer Kiefer unterbrochen,
  brechen die Fruchtkörper binnen 72 Tagen um **98 %** ein. Wetterdaten
  sehen davon nichts.
- **Wasser aus der Tiefe.** Bei trockenem Oberboden stammen 25–80 % des
  Fruchtkörperwassers aus über 30 cm Tiefe — der gemessene Niederschlag ist
  nicht die ganze Geschichte.
- **Myzel ≠ Fruchtkörper.** In sehr trockenen Jahren wächst das Myzel
  weiter, während oben fast nichts erscheint.
- **Die Größenordnung der Unsicherheit:** In Katalonien schwankte die
  Ernte zwischen den Jahren um den **Faktor 10** (25 → 255 kg/ha). Reine
  Wettermodelle erreichen bei einer simplen Ja/Nein-Vorhersage **60–80 %**.

**Die ehrliche Konsequenz:** Die Ampel kann sagen „die Bedingungen sind
günstig/ungünstig". Sie kann **nicht** sagen „hier stehen Pilze". Wer sie
anders beschriftet, baut genau die Falle, für die Pilz-Apps zu Recht
kritisiert werden.

## Die Artenklassifikation

Heute kennt `lib/core/mushroom_species.dart` je Art nur Name, Gruppe und
Zweitnamen — keine Ökologie. Vorschlag, bewusst **grob** und in dieser
Reihenfolge belastbar:

### Stufe 1: Gilde (entscheidet, welches Modell rechnet)

| Gilde | Beispiele | Modell |
|---|---|---|
| Mykorrhiza, Sommer/Herbst | Steinpilz, Marone, Pfifferling, Herbsttrompete, Reizker, Täublinge | volles Wettermodell |
| Mykorrhiza, Frühjahr | Morchel, Maipilz | Gradtage + Bodentemperatur |
| Holzbewohner | Hallimasch, Stockschwämmchen, Austernseitling, Samtfußrübling | **nur Saisonfenster**, Wetter höchstens dämpfend |
| Kältefrüchter | Austernseitling, Samtfußrübling | eigene Kurve (Peak im Dezember!) |

### Stufe 2: Saisonkurve je Art — aus echten Funddaten, nicht geschätzt

**Gebaut und ausgeliefert seit 1.56.0** — `tool/season_curves.py`,
`lib/core/season_curves.g.dart`, Anzeige im Spot-Blatt. Methode, alle 91
Zuordnungen und die beiden Fallen, die dabei aufgeschlagen sind, stehen in
`docs/pilzampel-saisonkurven.md`. Der Abschnitt hier beschreibt die
Vorüberlegung; **maßgeblich ist die andere Datei**.

Aus GBIF (DE+AT+CH, nur menschliche Beobachtungen) lässt sich pro Art eine
Monatskurve rechnen. **Entscheidend ist die Effort-Korrektur:** September
und Oktober enthalten 41 % aller Pilzmeldungen überhaupt — wer die Rohkurve
nimmt, baut die Gewohnheiten der Melder ins Modell. Nach Korrektur
verschiebt sich zum Beispiel der Pfifferling-Peak von August auf **Juli**.

Effort-korrigierte Kurven (Index, Maximum = 100). Diese Zahlen sind
ungefiltert; die ausgelieferten liegen wegen des Lizenzfilters (nur CC0 und
CC BY) um ein bis zwei Punkte daneben — beim Steinpilz etwa Aug 100 · Sep 96
statt Aug 98 · Sep 100. Der netzfreie Selbsttest des Skripts rechnet gegen
**diese** Tabelle, weil sie dokumentiert ist:

| Art | Jahresgang |
|---|---|
| Steinpilz | Jun 22 · Jul 61 · **Aug 98 · Sep 100** · Okt 73 · Nov 37 |
| Pfifferling | Jun 52 · **Jul 100** · Aug 76 · Sep 42 · Okt 18 |
| Marone | Jul 38 · Aug 63 · Sep 89 · **Okt 100** · Nov 74 |
| Herbsttrompete | Jul 31 · Aug 81 · Sep 92 · **Okt 100** · Nov 69 |
| Hallimasch | Sep 36 · **Okt 100** · Nov 80 |
| Maipilz | Apr 58 · **Mai 100** · Jun 18 |
| Austernseitling | Nov 31 · **Dez 100** · Jan 91 · Feb 55 |
| Stockschwämmchen | Apr 37 · Mai 97 · … · Okt 100 · Nov 89 (praktisch flach) |

Alternative, noch besser: der **CC0-Datensatz von Andrew et al. 2018**
([Dryad](https://datadryad.org/dataset/doi:10.5061/dryad.150r1jf)) liefert
je Art und 10×10-km-Rasterzelle den mittleren Fruchtungstag samt
Perzentilen — ein fertiges europäisches Saisonmodell, inklusive der
Verschiebung um bis zu **25–30 Tage** je nach Breite und Höhenlage.

### Stufe 3: unbekannte Arten

Freitext-Arten fallen auf ihre `SpeciesGroup` zurück, unbekannte Gruppen auf
„keine Aussage". Lieber eine graue Ampel als eine erfundene.

## Das Modell — konkret

Angelehnt an den tschechischen Wetterdienst (der einzige amtliche Dienst mit
so einem Produkt), mit den Bielefelder Zahlen kalibriert:

```
Ampel(Art, Ort, Tag) = Saisonfaktor(Art, Tag, Breite, Höhe)   // 0…1, aus GBIF/Dryad
                     × Feuchtefaktor(Ort, Tag)                 // 0…1, 26-Tage-Kumulation
                     × Temperaturfaktor(Art, Ort, Tag)         // 0…1, 20-Tage-Mittel
                     × Dämpfer(Frost, Hitze, Dürre)            // 0…1
```

- **Feuchte:** kumulierter Niederschlag über 26 Tage, ältere Tage schwächer
  gewichtet. Ergänzend die **Bodenfeuchte** (Open-Meteo liefert sie direkt) —
  sie ist näher an dem, was der Pilz merkt, als der Regen an der Oberfläche.
- **Temperatur:** Glockenkurve um **13 °C** (20-Tage-Mittel) für
  Herbst-Mykorrhiza; für Frühjahrsarten stattdessen Gradtagsumme.
- **Dämpfer:** Frost in den letzten Tagen, Hitze über ~27 °C, anhaltende
  Dürre.
- **Holzbewohner:** nur Saisonfaktor, plus ein Feuchte-Dämpfer. Kein
  Temperaturoptimum — es gibt dafür keine belastbaren Zahlen.

**Was ausdrücklich NICHT eingebaut wird:** der „Kälteschock" als Auslöser.
Alle konkreten Zahlen dazu stammen aus der Pilz*zucht*; einen Feldnachweis
für Waldpilze gibt es nicht.

## Datenquellen — geprüft, nicht vermutet

| Quelle | Was | Lizenz/Kosten | Geprüft |
|---|---|---|---|
| **Open-Meteo** | Ein Request liefert 31 Tage Rückschau + 14 Tage Vorhersage: Niederschlag, Temperatur, **Bodenfeuchte, Bodentemperatur**. Mehrere Orte pro Request. | CC BY 4.0, ohne Schlüssel, 10.000 Aufrufe/Tag — **nicht-kommerziell** | ja, live |
| **DWD Radar-WMS** (`dwd:Niederschlagsradar`) | Radar + 2-Stunden-Vorhersage, 5-Minuten-Takt, 1 km, mm/h. Der *deklarierte* Ausschnitt umfasst DACH (45,7–56,2 N / 1,5–18,7 O), die **Daten** aber nicht: punktweise nachgemessen am 2026-08-04 liegen Salzburg, Innsbruck, Zürich, Bern und Chur drin, Wien, Graz, Klagenfurt und Genf **nicht** — dort malt das Produkt seine „Keine Daten"-Fläche. Bounding Box ≠ Abdeckung | „Fees: none", DWD-Copyright/GeoNutzV | ja, live (eingebaut in 1.45.0) |
| **DWD `SF-Produkt`** | gleitende 24-Stunden-Niederschlagssumme als Kartenebene, stündlich; nur Deutschland | wie oben | ja, live (eingebaut in 1.45.0) |
| **DWD `RADOLAN-W4`** | **auf 30 Tage aufsummierte** angeeichte Radardaten, täglich, nur Deutschland — genau die Größe, mit der Sammler rechnen und auf der der tschechische Pilzindex aufsetzt | wie oben | ja, live (eingebaut in 1.45.0) |
| **DWD Open Data (Raster)** | Tages-Bodenfeuchte 1×1 km ab 1991, Bodentemperatur in 5–100 cm | frei | dokumentiert |
| **GBIF** | Funddaten für die Saisonkurven; SwissFungi (927 k) und ÖMG (537 k) unter CC BY 4.0. Nur CC0 und CC BY werden ausgewertet — der Filter kostet gemessen 26 % der Meldungen und erspart die NC-Frage | frei | ja, live (eingebaut in 1.56.0) |
| ~~RainViewer~~ | — | **API im Januar 2026 eingestellt bzw. kostenpflichtig** | — |

**Zu klären, bevor gebaut wird:** Open-Meteo ist nur für
**nicht-kommerzielle** Nutzung frei. PilzBuddy ist kostenlos und werbefrei —
das passt heute, muss aber bei einer Play-Store-Veröffentlichung noch einmal
bewusst bejaht werden. Notfalls trägt der DWD den Deutschland-Teil allein.

## Architektur: Der Standort darf das Gerät nicht verlassen

Heute steht in `web/datenschutz.html`: „Es werden dabei keine Konten oder
Standorte übermittelt". Ein direkter Aufruf
`api.open-meteo.com?lat=…&lon=…` mit der Spot-Koordinate würde diesen Satz
falsch machen und Play-Formular, Datenschutzerklärung und deren Test
nachziehen.

**Empfehlung — der Weg, den das Projekt schon kann:** Ein GitHub-Action-Cron
(wie der Feedback-Bot, alle 2 h) holt die Wetterdaten für ein **DACH-Raster**
und legt das Ergebnis als **Release-Asset** ab — genau wie die
Offline-Karten. Die App lädt dieses eine kleine Paket und rechnet die Ampel
**lokal**.

Das löst gleich vier Probleme auf einmal:

1. Keine Koordinate verlässt das Gerät — Datenschutztext bleibt wahr.
2. Die Ampel funktioniert **offline** im Wald, wo sie gebraucht wird.
3. Die Lizenzfrage (nicht-kommerziell) stellt sich an genau einer Stelle.
4. Aus demselben Raster lässt sich die **Niederschlagskarte für längere
   Zeiträume** (3 Tage/1 Woche/1 Monat, Wunsch aus #156) selbst rendern —
   fertige Kacheln dafür gibt es nirgends.

Ein Raster mit 0,25° über DACH sind rund 1.500 Zellen; Open-Meteo beantwortet
viele Orte pro Request, das sind also wenige Aufrufe pro Lauf. Die
vorberechneten Kennzahlen je Zelle sind wenige hundert Kilobyte.

Für die **Live-Regenkarte** (Wunsch „wie bei Kachelmann") ist dagegen der
DWD-WMS direkt richtig: eine Rasterebene über der Karte, nur online, mit
Zeitschieber über die letzten zwei Stunden plus Vorhersage.

## Der eigentliche Trumpf: Validierung an echten Funden

Das deutsche Forschungsprojekt **Pilz4You** (BMVI-gefördert) hat ein
Prognosemodell gebaut und die App am Ende **nicht** veröffentlicht. Der
Grund steht in der Projektdokumentation: Es fehlten die
**Fundbeobachtungen** als Zielgröße.

**Genau die Daten erhebt PilzBuddy bereits** — mit Datum, Art und Koordinate.
Damit ist etwas möglich, das kein einziger der recherchierten Dienste
vorweisen kann: **eine überprüfte Prognose.** Kein Anbieter (weder ČHMÚ noch
GrzyboRadar noch die kommerziellen) publiziert eine Validierung.

Zwei Schritte dorthin:

1. **Rückwärts prüfen:** Für jeden vorhandenen Fund die Ampel für damals
   nachrechnen (Open-Meteo hat die Historie). Steht die Ampel an Fundtagen
   höher als an zufälligen Tagen derselben Saison? Wenn nicht, taugt das
   Modell nichts — und das merkt man **vor** dem Ausliefern.
2. **Die fehlende Hälfte erheben:** Die App kannte nur Erfolge. Ein
   optionales „war da, nichts gefunden" ist die einzige Möglichkeit, die
   Ampel *wirklich* zu kalibrieren — der Unterschied zwischen Statistik
   und Bauchgefühl. **Gebaut** (2026-08-06, #211, ab 1.58.0): eigener
   Knopf im Spot-Blatt, `finds.blank` (Patch 015).
   **Ohne Art**, und das ist eine inhaltliche Festlegung, kein Sparen am
   Formular: Man sucht im Wald nicht sortenrein, und „keine Steinpilze"
   von jemandem, der an Pfifferlingen vorbeigelaufen ist, wäre eine
   Aussage, die niemand so gemeint hat. Der Leergang gilt dem **Ort** —
   ein Constraint (`finds_blank_leer`) hält das fest.
   Für die Auswertung heißt das: ein Ort-Tag-Paar mit Ausgang „nichts",
   vergleichbar mit dem Wetter dieses Tages. Die Menge entsteht erst mit
   der Zeit; wie viele es für eine belastbare Kalibrierung braucht, steht
   in `pilzampel-validierung.md`.

Zusätzlich fehlt heute jede Möglichkeit, einen einzelnen Fund zu
**korrigieren** (nur der ganze Spot lässt sich löschen). Falsche Daten
bleiben für immer im Trainingsmaterial.

## Ehrlichkeit im UI — nicht verhandelbar

Was die recherchierten Dienste vorbildlich machen und was schiefgeht:

- **ČHMÚ** schreibt hin, für welche Pilzgruppe der Wert gilt. → Die Ampel
  nennt immer die Art oder Gilde, nie „die Pilze".
- **GrzyboRadar** publiziert seine komplette Formel und schreibt dazu, der
  Wert **„bedeutet keine Prozentchance"**. → Kein Prozentzeichen. Drei bis
  fünf Stufen mit Worten („ungünstig / verhalten / günstig"), nicht 73 %.
- Ein Mykologe zur polnischen Karte: *„Man soll den Farben auf der Karte
  nicht blind glauben."* Ein französischer Feldtest: *„Das sind
  Biotopkarten, keine Pilzkarten."* → Die Ampel bewertet **Bedingungen**,
  nicht Vorkommen. Der Text muss das sagen, nicht das Kleingedruckte.
- Ein Sammler im Forum: *„Die besten Pilze findet man auch in der
  schlimmsten Trockenzeit — ich würde nie auf 0 % setzen."* → Keine Stufe
  heißt „aussichtslos".

## Vorgeschlagene Reihenfolge

1. **C — Spot-Erinnerung** („dein Spot war letztes Jahr um diese Zeit
   ergiebig"). Kein Netz, keine externe Quelle, keine Datenschutzänderung;
   reine Auswertung vorhandener Daten plus Banner. Sofort machbar, sofort
   nützlich, und es schärft nebenbei den Blick dafür, wie dünn die eigene
   Datenlage pro Spot noch ist.
2. **A1 — Live-Regenkarte** über den DWD-WMS. Eine Rasterebene, ein
   Schalter, ein Zeitschieber. Unabhängig von jedem Modell — es sind
   Messwerte. **Abhängigkeit:** Diese Ebene sollte auf der MapLibre-Engine
   gebaut werden (Migrationsplan), nicht auf flutter_map — dort war eine
   zweite Kachelebene schon einmal ein Speicherproblem
   (`docs/map-performance.md`).
3. **Validierung vor Modell** — die Rückwärtsprüfung. Ergebnis entscheidet,
   ob Baustein B überhaupt kommt. **Werkzeug gebaut** (2026-08-06):
   `tool/ampel_validate.py`, Methode und Grenzen in
   `docs/pilzampel-validierung.md`. Geprüft wird an **GBIF**-Meldungen, nicht
   an den eigenen Funden: Davon gibt es noch zu wenige, und GBIF liefert
   Tausende mit Koordinate (Median 250 m) und taggenauem Datum. Die eigenen
   Funde bleiben damit als *unabhängiger* Prüfstein für später übrig — das
   ist sauberer, als mit ihnen zu entwickeln und zu prüfen.
4. **B — Ampel**, wenn Schritt 3 trägt: Raster-Cron, Gilden-Modell,
   Anzeige je Spot und je Art. Die **Saisonkurven** sind seit 1.56.0
   gebaut und stehen bereits im Spot-Blatt — als Beschreibung, nicht als
   Bewertung (`docs/pilzampel-saisonkurven.md`). Sie vorzuziehen war
   möglich, weil sie keine Modellannahme enthalten: Sie sagen, wann eine
   Art gemeldet wurde, nicht ob heute etwas wächst.
5. **Waldtyp** (zweiter Teil von #158) — ~~bewusst zurückgestellt~~
   **Stufe 1 gebaut** (2026-08-07, #213, ab 1.62.0): Laub/Misch/Nadel für
   DACH als 250-m-Gitter aus dem Copernicus-HRL „Dominant Leaf Type"
   (jährlich gepflegt, besteht den Borkenkäfer-Aktualitätstest), als
   Asset im APK — Kartenebene plus „Wald hier"-Zeile im Spot-Blatt.
   Die befürchtete Beschaffung war keine: `tool/forest_grid.py` ist die
   zweite Anwendung der Regengitter-Maschinerie. Für die Ampel steht
   damit der Waldtyp am Spot als lokale Abfrage bereit
   (`ForestGrid.classAt`), ohne dass eine Koordinate das Gerät verlässt.
   Quellenwahl und Stufung (Artebene = Stufe 2, nur bei Bedarf) sind am
   Issue #213 dokumentiert. Er ist bei Holzbewohnern wichtiger als das
   Wetter — was FEHLT, ist seine Verrechnung im Modell, nicht mehr die
   Datenlage.

## Offene Entscheidungen

1. ~~Ist **nicht-kommerziell** dauerhaft die richtige Zusage
   (Open-Meteo)?~~ **Entschieden (2026-08-08, Betreiber): ja.** Die App
   ist und bleibt komplett kostenlos und werbefrei — auch mit Blick auf
   den Play Store. **Vermerk des Betreibers:** Sollte sich daran je
   etwas ändern (Werbung, Abo, Bezahlversion), MUSS die
   Open-Meteo-Nutzung neu entschieden werden — sie ist nur für
   nicht-kommerzielle Nutzung frei. Die Zusage steht seither auch im
   README (Abschnitt „Lizenz und Datenquellen"); wer monetarisiert,
   findet sie dort.
2. ~~**Leergang erfassen** ja/nein?~~ **Entschieden (2026-08-06): ja**,
   ausgeliefert mit 1.58.0 (#211). Die Sorge „mehr Erfassungswerkzeug,
   weniger Schatzkarte" ist mit dem Zuschnitt beantwortet: ein Knopf
   neben „Fund eintragen", zwei Taps, ohne Art — wer ihn nicht drückt,
   merkt nichts von ihm.
3. Wie viel **Raster-Auflösung** ist genug? 0,25° (~20 km) ist grob, aber
   ehrlich — Mikroklima kann die Ampel ohnehin nicht sehen.
4. **Nur DACH oder mehr?** Der DWD-Radar deckt DACH ab, Open-Meteo die Welt.
   Die Offline-Karten sind heute DACH.
