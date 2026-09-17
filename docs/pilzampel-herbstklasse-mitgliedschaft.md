# Wie weit trägt das eine Fenster? — Prüfplan, registriert vor der Messung

Stand: 2026-09-16 · Gehört zu `docs/pilzampel-artenfenster.md` und
`docs/pilzampel-konzept.md` · **Diese Seite ist vor dem Lauf
geschrieben und committet worden.** Die Ergebnisse stehen in
`docs/pilzampel-herbstklasse-messung.md`.

## Die Frage

`docs/pilzampel-artenfenster.md` führt seit dem 2026-09-11 zwei Lesarten
nebeneinander, weil die Daten sie nicht trennten:

1. Das Modell misst **allgemeines Pilzwetter** — dann wäre eine
   Unterscheidung je Art Zierrat.
2. Diese Arten **teilen schlicht dasselbe Fenster** — dann ist die
   Unterscheidung sinnvoll, nur an anderen Arten zu zeigen.

Inzwischen gibt es zwei Messungen, die beide in dieselbe Richtung
zeigen, und beide waren als Erweiterung gedacht, nicht als Antwort auf
diese Frage:

| Klasse | eigenes Fenster | gegen die 13 °C in AT+CH | Ausgang |
|---|--:|---|---|
| `herbst_holz` | 11,625 °C | Hallimasch +0,018, Stockschwämmchen −0,036 | gescheitert |
| `kalt` | −1,0 °C | Judasohr −0,066, Austernseitling +0,103 | gescheitert |

**Zwei geschneiderte Fenster haben das ausgelieferte nicht geschlagen**
(`docs/pilzampel-herbstholz-holdout.md`,
`docs/pilzampel-kaltklasse-holdout.md`). Was in beiden Berichten
nebenbei steht und hier die Hauptrolle bekommt, ist die Spalte
darunter: Die AUC **mit** den 13 °C liegt bei Hallimasch bei 0,766 und
bei Stockschwämmchen bei 0,662 — das ausgelieferte Fenster trennt bei
diesen Arten gut, es ist nur nicht zu verbessern.

Daraus folgt nicht „mehr Klassen bauen". Es folgt die Frage, die hier
gestellt wird:

> **Für wie viele Arten trägt das eine, ausgelieferte 13-°C-Fenster?**

Das ist eine Frage nach MITGLIEDSCHAFT, nicht nach Anpassung. Sie
kostet **null neue Parameter**: kein Fenster, keine Schwelle, kein
Freiheitsgrad. Ausgeliefert würde ausschließlich eine längere
Mitgliederliste von `herbst`.

## Warum Deutschland ein gültiger Prüfraum ist

Die 13 °C sind **nie an unseren Daten angepasst worden**. Sie stammen
aus der Bielefelder Steinpilz-Reihe (Brejon Lamartiniere & Hoffman
2025) und stehen seit dem ersten Tag als Literaturwert im Modell — für
keine einzige Art dieses Repos ist je ein Gitter darüber gelaufen, um
sie zu bestimmen.

Die gepaarte AUC dieses Fensters ist damit für **jede** Art eine
Messung außerhalb der Anpassung, auch in Deutschland. Das unterscheidet
diesen Plan von den beiden gescheiterten Hold-outs: Dort wurde in DE
ein Fenster angepasst, also brauchte es AT+CH als unbeteiligten
Prüfraum. Hier wird nichts angepasst.

**Warum nicht trotzdem AT+CH:** Weil die Kontrastgruppe dort
verschwindet. Von den drei Winterarten erreichen in AT+CH nur 367 bzw.
285 Meldungen — eine Vorhersage, die nur für die Bestätigungsgruppe
prüfbar ist, ist keine. AT+CH bleibt als **Kür** und wird für die
bestandenen Arten nachgereicht; ein Tor ist es nicht.

## Der Kandidatenkreis — mechanisch gewählt, hier eingefroren

Die Auswahlregel enthält **keine Wetterzahl** und wurde vor der ersten
Abfrage festgelegt:

- jede Art aus `lib/core/mushroom_species.dart` mit einem `sci`-Namen,
- mindestens **400 Meldungen** im lokalen GBIF-Bestand für Deutschland,
  2006–2025, taggenau, Ortsgenauigkeit besser als 1000 m oder fehlend
  (derselbe Schnitt wie `fetch_finds`),
- Gruppe allein aus dem **Saisongipfel** (Monat mit den meisten
  Meldungen in DACH) — eine Größe aus GBIF-Monatszahlen, die kein
  Wetter kennt.

Bestand: `~/pilzbuddy-gbif/dach_fungi.sqlite`, DOI
`10.15468/dl.dwbsuf`. Damit ist die Liste reproduzierbar, auch wenn
GBIF weiterwächst.

**Die Vorhersage je Gruppe steht vor der Messung fest:**

| Gruppe | Gipfel | Vorhersage |
|---|---|---|
| **herbstnah** | Aug–Okt | besteht |
| **anders** | Apr–Jul | fällt durch |
| **kalt** | Nov–Mär | fällt durch |

„Zahlen bekannt" markiert Arten, deren AUC aus früheren Läufen bereits
vorliegt. **Sie zählen nicht zum Urteil** — sie laufen mit, damit die
Tabelle vollständig ist, aber eine Regel an Zahlen zu prüfen, die man
schon gesehen hat, beweist nichts. Das Urteil tragen die **39 frischen**
Arten.

| Art | wissenschaftlich | Meldungen DE | Gipfel | Gruppe | Status |
|---|---|--:|--:|---|---|
| Fliegenpilz | Amanita muscaria | 6009 | 10 | herbstnah | frisch |
| Parasol | Macrolepiota procera | 4252 | 10 | herbstnah | frisch |
| Schopftintling | Coprinus comatus | 3884 | 10 | herbstnah | frisch |
| Grünblättriger Schwefelkopf | Hypholoma fasciculare | 3660 | 10 | herbstnah | frisch |
| Perlpilz | Amanita rubescens | 2721 | 8 | herbstnah | frisch |
| Hallimasch | Armillaria | 2589 | 10 | herbstnah | Zahlen bekannt |
| Maronenröhrling | Imleria badia | 2482 | 10 | herbstnah | ausgeliefert |
| Flaschenstäubling | Lycoperdon perlatum | 2459 | 10 | herbstnah | frisch |
| Steinpilz | Boletus edulis | 2251 | 9 | herbstnah | ausgeliefert |
| Nebelkappe | Clitocybe nebularis | 2202 | 10 | herbstnah | frisch |
| Rotkappe | Leccinum | 2073 | 9 | herbstnah | frisch |
| Schwefelporling | Laetiporus sulphureus | 2030 | 9 | herbstnah | frisch |
| Violetter Lacktrichterling | Laccaria amethystina | 1858 | 10 | herbstnah | frisch |
| Birnenstäubling | Apioperdon pyriforme | 1788 | 10 | herbstnah | frisch |
| Rotfußröhrling | Xerocomellus chrysenteron | 1782 | 10 | herbstnah | frisch |
| Kahler Krempling | Paxillus involutus | 1522 | 10 | herbstnah | frisch |
| Falscher Pfifferling | Hygrophoropsis aurantiaca | 1470 | 10 | herbstnah | frisch |
| Pfifferling | Cantharellus cibarius | 1354 | 8 | herbstnah | ausgeliefert |
| Stockschwämmchen | Kuehneromyces mutabilis | 1323 | 10 | herbstnah | Zahlen bekannt |
| Rehbrauner Dachpilz | Pluteus cervinus | 1214 | 10 | herbstnah | frisch |
| Birkenpilz | Leccinum scabrum | 1203 | 9 | herbstnah | ausgeliefert |
| Goldröhrling | Suillus grevillei | 1202 | 9 | herbstnah | frisch |
| Ziegenbart | Ramaria | 1028 | 9 | herbstnah | frisch |
| Krause Glucke | Sparassis crispa | 1017 | 9 | herbstnah | frisch |
| Dunkler Hallimasch | Armillaria ostoyae | 896 | 10 | herbstnah | frisch |
| Pantherpilz | Amanita pantherina | 862 | 10 | herbstnah | frisch |
| Violetter Rötelritterling | Lepista nuda | 852 | 10 | herbstnah | frisch |
| Grüner Knollenblätterpilz | Amanita phalloides | 842 | 10 | herbstnah | frisch |
| Frauentäubling | Russula cyanoxantha | 828 | 9 | herbstnah | frisch |
| Fichtenreizker | Lactarius deterrimus | 779 | 9 | herbstnah | ausgeliefert |
| Netzstieliger Hexenröhrling | Suillellus luridus | 753 | 8 | herbstnah | frisch |
| Safranschirmling | Chlorophyllum | 752 | 10 | herbstnah | frisch |
| Wiesenchampignon | Agaricus campestris | 738 | 10 | herbstnah | frisch |
| Riesenbovist | Calvatia gigantea | 731 | 8 | herbstnah | frisch |
| Butterpilz | Suillus luteus | 721 | 10 | herbstnah | frisch |
| Fuchsiger Rötelritterling | Paralepista flaccida | 591 | 10 | herbstnah | frisch |
| Semmelstoppelpilz | Hydnum repandum | 583 | 9 | herbstnah | frisch |
| Leberpilz | Fistulina hepatica | 553 | 9 | herbstnah | frisch |
| Edelreizker | Lactarius deliciosus | 545 | 10 | herbstnah | frisch |
| Ziegenlippe | Xerocomus subtomentosus | 515 | 9 | herbstnah | frisch |
| Nelkenschwindling | Marasmius oreades | 498 | 10 | herbstnah | frisch |
| Gallenröhrling | Tylopilus felleus | 476 | 8 | herbstnah | frisch |
| Gifthäubling | Galerina marginata | 418 | 10 | herbstnah | frisch |
| Mönchskopf | Infundibulicybe geotropa | 412 | 10 | herbstnah | frisch |
| Sommersteinpilz | Boletus reticulatus | 566 | 6 | anders | frisch |
| Maipilz | Calocybe gambosa | 413 | 5 | anders | frisch |
| Judasohr | Auricularia auricula-judae | 3013 | 1 | kalt | Zahlen bekannt |
| Austernseitling | Pleurotus ostreatus | 1600 | 12 | kalt | Zahlen bekannt |
| Samtfußrübling | Flammulina velutipes | 1178 | 12 | kalt | Zahlen bekannt |

**44 herbstnah** (37 frisch), **2 anders** (2 frisch), **3 kalt**
(0 frisch) — zusammen 49 Arten, davon 39 frisch.

## Die Bedingung, Art für Art

> Eine Art wird Mitglied von `herbst`, wenn das **ausgelieferte**
> 13-°C-Fenster ihre Fundtage von ihren Vergleichstagen trennt:
> gepaarte **AUC ≥ 0,60**, bei mindestens **400 Paaren**, und
> abstandsgleiche Kontrolle innerhalb **0,50 ± 0,03**.

Drei Zahlen, und warum sie so stehen:

- **0,60** liegt bei rund 1000 Paaren etwa vier Standardfehler über dem
  Zufall und unter allen fünf heutigen Herbst-Mitgliedern (0,655 bis
  0,730). Sie ist gesetzt, bevor eine frische Art gemessen wurde, und
  bewusst nicht auf eine Trefferzahl hin gewählt.
- **400 Paare** — darunter ist der Standardfehler (≈ 0,025) so groß,
  dass 0,60 und 0,55 nicht mehr unterscheidbar sind.
- Die **abstandsgleiche Kontrolle** ist dieselbe wie überall: Vergleichstag
  gegen seinen am Fundtag gespiegelten Partner. Liegt sie daneben, ist
  die Ziehung verzerrt und die Zahl daneben wertlos — die Art wird dann
  als „nicht auswertbar" geführt und nicht als durchgefallen.

## Der Ausgang, der gegen dieses Vorhaben spricht — mitregistriert

**Bestehen die Kontrastgruppen mit**, also Sommersteinpilz und Maipilz
(Gipfel Mai/Juni) und die drei Winterarten, dann trennt das Modell
nicht nach Temperaturnische. Es misst dann etwas Generisches — und
zwar innerhalb der Saison, denn der Vergleichstag liegt 14–45 Tage
neben dem Fund am selben Ort. Ein plausibler Kandidat dafür wäre reine
Feuchte.

**In diesem Fall wird nichts erweitert.** Dann ist die
Klassenmaschinerie Zierrat auf einer Aussage, die das Modell nicht
trifft, und der nächste Schritt ist ihr Rückbau, nicht ihr Ausbau. Das
ist der Ausgang, der die Richtung dieses Plans widerlegt; er wird
genauso veröffentlicht wie ein Erfolg.

Ebenso vorab festgelegt: **Fallen die frischen herbstnahen Arten
breit durch** (weniger als die Hälfte besteht), dann ist `herbst` keine
Gilde, sondern eine kleine Gruppe — dann bleibt die Mitgliederliste,
wie sie ist, und Hallimasch und Stockschwämmchen bleiben grau.

## Was NICHT gemacht wird

**Kein Umgruppieren, bis etwas besteht.** Die Mitglieder der beiden
gescheiterten Klassen (`herbst_holz`, `kalt`) werden nicht neu
sortiert, und aus den Ergebnissen dieses Laufs wird keine neue Klasse
geschnitten. Wer nach einem gescheiterten Hold-out dieselben Daten
umrührt, bis eine Gruppe besteht, misst seine eigene Ausdauer.

Hallimasch und Stockschwämmchen können über die **Regel** Mitglieder
werden — also weil die Latte auf 39 frischen Arten getragen hat und sie
diese Latte überspringen —, nie wegen ihrer bereits bekannten Zahlen.

**Kein neues Fenster, keine Anpassung.** Wenn eine Art durchfällt, ist
das Ergebnis „sie bekommt keine Ampel", nicht „sie bekommt ein eigenes
Fenster".

## Wenn die Regel trägt: was danach zwingend gemessen wird

Eine längere Mitgliederliste ist keine folgenlose Zeile. Drei
Nachmessungen gehören in denselben PR, alle drei von CLAUDE.md
verlangt:

1. **Die Schwellen neu** (`--thresholds`). Sie sind Quantile der
   Score-Verteilung der Klasse an Vergleichstagen; mehr Mitglieder =
   andere Verteilung. Der heutige Stand (0,187 / 0,512) gilt für fünf
   Arten.
2. **Die Quote günstiger Vergleichstage.** „Wie oft sagt die Ampel
   günstig" ist eine Produktaussage, keine Messung — sie lag bei
   19,9 % und ist mit der zweiten Klasse auf 30,2 % gestiegen.
3. **Wie viele Art-Monate der Banner-Hinweis kippt.** Der Hinweis paart
   Klasse und Saisonkurve je Art; neue Mitglieder heißen neue
   gemeldete Spots.

## Grenzen

Angepasst und geprüft wird ausschließlich an GBIF. Die eigenen Funde
und Leergänge der App bleiben draußen — sie sind der unabhängige
Prüfstein aus #199.

Auch eine bestandene Mitgliedschaft sagt „die Bedingungen sind
günstig", nicht „hier stehen Pilze".

Und sie sagt nichts darüber, ob ein **eigenes** Fenster für diese Art
noch besser wäre. Diese Frage ist mit den beiden gescheiterten
Hold-outs nicht beantwortet, sondern nur zweimal verneint worden.
