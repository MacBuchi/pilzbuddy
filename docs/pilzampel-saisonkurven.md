# Saisonkurven je Art — Methode und Ergebnis

Stand: 2026-08-05 · Skript: `tool/season_curves.py` · Ergebnis:
`lib/core/season_curves.g.dart` · Anzeige: „Wann diese Art gemeldet wird"
im Spot-Blatt

Dies ist **Stufe 2** aus `docs/pilzampel-konzept.md`: der Saisonfaktor je
Art. Von allen Zutaten der geplanten Pilzampel ist er die einzige, die
ohne Modellannahme auskommt — er kommt aus echten Beobachtungen. Feuchte-
und Temperaturfaktor warten planmäßig auf die Rückwärtsvalidierung; erst
wenn die trägt, wird aus diesen Kurven eine Ampel.

Was hier ausgeliefert wird, ist deshalb **keine Prognose**, sondern eine
Beschreibung: In welchen Monaten wurde diese Art gemeldet? Dieselbe Grenze
wie beim Wetter am Spot — Fakten, kein Urteil.

## Woher die Zahlen kommen

Aus GBIF, über `occurrence/search` mit `facet=month`. Ein Aufruf je Art,
plus einer für die Baseline.

| Filter | Wert | Warum |
|---|---|---|
| `country` | DE, AT, CH | Der Raum, in dem die App benutzt wird |
| `basisOfRecord` | `HUMAN_OBSERVATION` | Herbarbelege und Sequenzierungen tragen ein anderes Datum als der Fund |
| `hasCoordinate` | `true` | Ohne Ort ist die Landeszuordnung geraten |
| `license` | `CC0_1_0`, `CC_BY_4_0` | Siehe unten |
| Jahresbereich | **keiner** | Beschneidet kaum (Steinpilz 11 837 → 11 270 ab 1990) und hielte die Zahlen im Konzeptpapier nicht mehr vergleichbar |

## Die Effort-Korrektur ist der ganze Punkt

September und Oktober tragen 41 % aller Pilzmeldungen überhaupt. Wer die
Rohkurve nimmt, baut die **Gewohnheiten der Melder** ins Ergebnis und
bekommt für jede Art denselben Herbstberg.

Deshalb wird geteilt:

```
korrigiert(Monat) = Anteil der Art an ihrem Jahr
                    ────────────────────────────
                    Anteil aller Pilze an ihrem Jahr
```

normiert auf Maximum = 100. Übrig bleibt: In welchem Monat ist diese Art
unter den gemeldeten Pilzen **überdurchschnittlich** vertreten?

Der Unterschied ist keine Feinheit. Beim Pfifferling wandert der Gipfel von
August auf **Juli**, beim Steinpilz vom September auf **August/September**.

Was das für die Anzeige bedeutet — und was im UI auch dasteht: Der Wert ist
**relativ zur Pilzsaison**, nicht absolut, und er beschreibt **Meldungen
früherer Jahre**, nicht das Wetter dieses Jahres.

## Die Lizenz-Entscheidung

GBIF mischt Datensätze unter CC0, CC BY 4.0 und **CC BY-NC** 4.0. Der
Filter auf die ersten beiden kostet gemessen **26 %** der Beobachtungen
(Steinpilz: 11 837 → 8 789).

Er ist trotzdem gesetzt. Ausgeliefert werden zwar nur aggregierte
Monatszähler, aber die NC-Frage ist im Projekt bereits eine offene
Entscheidung (Open-Meteo, Konzeptpapier), und vor einer möglichen
Play-Veröffentlichung ist eine NC-Quelle weniger ein Gewinn. Der Preis ist
bezahlbar: Auch nach dem Filter hat die seltenste zugeordnete Art
dreistellige Zahlen.

## Zwei Fallen, beide still, beide eingetreten

Die Prüfung der 91 Zuordnungen am 2026-08-05 hat genau das gefunden, wofür
sie gebaut wurde. Beide Fehler hätten **plausibel aussehende** Kurven
erzeugt.

**1. Ein unbekannter Name wirft keinen Fehler.** `species/match` klettert
die Taxonomie hoch und liefert zufrieden einen Treffer. `Agaricus
silvaticus` — ein Buchstabe daneben, richtig ist `sylvaticus` — kam als
Klasse *Agaricomycetes* zurück, mit 1 445 637 Beobachtungen. Die Kurve für
„Waldchampignon" wäre die Kurve **aller Blätterpilze** gewesen.

**2. Ein Synonym liefert nur einen Bruchteil.** GBIF zählt unter einem
Synonym-Namen ausschließlich die Meldungen, die genau diesen Namen tragen:

| Eingetragen | Status | n | Akzeptiert | n |
|---|---|--:|---|--:|
| *Lactarius volemus* | Synonym | 54 | *Lactifluus volemus* | 909 |
| *Morchella conica* | Synonym | 215 | *Morchella elata* | 1052 |
| *Inocybe erubescens* | Synonym | 121 | *Inosperma erubescens* | 441 |

Gegen beides steht `check_taxon`: **EXACT, ACCEPTED, Rang SPECIES oder
GENUS** — sonst bricht der Lauf ab. Eine Warnung hätte nicht gereicht; ein
falscher Name muss den Lauf kosten, sonst landet er in der App.

## Zwei Qualitätsschwellen, nicht eine

Wirksam sind sie in `lib/core/season_curves.dart` (`SeasonCurve.isReliable`);
das Skript baut **alle** Kurven und meldet nur, welche durchfallen — sie
sollen in dieser Tabelle sichtbar bleiben.

- **200 Beobachtungen** insgesamt. Zwölf Monatsfächer aus wenigen Dutzend
  Meldungen sind Rauschen, und Rauschen mit Balken sieht aus wie eine
  Aussage.
- **30 Meldungen im schwächsten Monat der Hauptzeit.** Die Gesamtzahl
  allein genügt nicht, und das ist die Schwachstelle der Effort-Korrektur:
  Sie teilt durch den Monatsgang aller Pilze, und der ist im Winter klein.
  Der Igelstachelbart bekommt so für **sechs** Dezember-Meldungen einen
  Balken von 93. Eine Art kann bequem über der ersten Schwelle liegen und
  trotzdem einen Gipfel zeigen, der auf einer Handvoll Meldungen steht.

Heute fallen zwei Arten durch, beide an der ersten Schwelle:
Frühjahrsknollenblätterpilz (56) und Igelstachelbart (94). Sie sind in DACH
wirklich selten — die Schwelle bildet die Wirklichkeit ab, statt sie zu
glätten.

## Die Hauptzeit

Die zusammenhängenden Monate ab 80 % des Maximums, **ausgedehnt vom
stärksten Monat aus** und über den Jahreswechsel hinweg. Beides ist nötig:

- Ohne den Jahreswechsel zerfiele der Austernseitling (Dezember/Januar) in
  zwei Enden, und die App behauptete, seine Zeit sei der Dezember.
- Ohne den Start am Maximum gewönne bei zwei getrennten Erhebungen die
  **frühere**, auch wenn die spätere doppelt so hoch ist.

Dieselbe Rechnung steht zweimal — `peak_run` in `tool/season_curves.py` und
`SeasonCurve._peakRun` in Dart. Beide Seiten haben denselben Testfall
(Austernseitling, Dez/Jan), damit sie nicht auseinanderlaufen.

## Neu bauen

```bash
python3 tool/season_curves.py --self-test                       # netzfrei
python3 tool/season_curves.py --out lib/core/season_curves.g.dart
python3 tool/season_curves.py --verify                          # Gegenprobe
```

Kein Cron: Diese Zahlen ändern sich über Jahre, nicht über Stunden — anders
als die Regengitter, die deshalb auf einem Release-Tag liegen. Der Diff der
generierten Datei ist das Ergebnis und gehört gesichtet; fällt eine Art
auffällig aus dem Rahmen, ist meist die Taxon-Zuordnung schuld.

`--verify` ist die Gegenprobe über einen zweiten Kanal: Die Facet-Zahl wird
gegen eine eigene Abfrage mit `month=N` gehalten. Dieselbe Rolle wie bei
`tool/rain_grid.py`.

**Eine neue Art bekommt ihre Kurve nicht von selbst.** Wer in
`lib/core/mushroom_species.dart` ein `sci` einträgt, muss das Skript laufen
lassen — `test/season_curves_test.dart` macht die Lücke sonst rot.

## Ergebnis

89 der 91 zugeordneten Arten werden angezeigt. Jahresgang gekürzt auf
Monate ab 25.

| Art | Wissenschaftlich | Hauptzeit | Jahresgang (korrigiert) | Beobachtungen |
|---|---|---|---|---|
| Anischampignon | *Agaricus arvensis* | Aug–Okt | Jan 38 · Mai 52 · Jun 67 · Jul 78 · Aug 93 · Sep 100 · Okt 87 · Nov 57 | 959 |
| Austernseitling | *Pleurotus ostreatus* | Dez–Jan | Jan 92 · Feb 60 · Nov 27 · Dez 100 | 2882 |
| Birkenpilz | *Leccinum scabrum* | Sep–Okt | Jun 34 · Jul 56 · Aug 64 · Sep 100 · Okt 90 · Nov 30 | 3306 |
| Birkenrotkappe | *Leccinum versipelle* | Aug–Sep | Jun 58 · Jul 78 · Aug 100 · Sep 90 · Okt 55 | 801 |
| Birnenstäubling | *Apioperdon pyriforme* | Sep–Dez | Jan 72 · Feb 88 · Mär 88 · Apr 54 · Aug 42 · Sep 81 · Okt 100 · Nov 93 · Dez 93 | 6243 |
| Bronzeröhrling | *Boletus aereus* | Jul–Aug | Jun 50 · Jul 88 · Aug 100 · Sep 60 · Okt 29 | 348 |
| Brätling | *Lactifluus volemus* | Jul–Aug | Jul 96 · Aug 100 · Sep 25 | 909 |
| Butterpilz | *Suillus luteus* | Okt–Nov | Sep 64 · Okt 100 · Nov 94 | 1812 |
| Böhmische Verpel | *Verpa bohemica* | Apr | Mär 36 · Apr 100 | 334 |
| Dunkler Hallimasch | *Armillaria ostoyae* | Okt–Nov | Sep 37 · Okt 100 · Nov 84 | 2932 |
| Edelreizker | *Lactarius deliciosus* | Okt–Nov | Aug 27 · Sep 49 · Okt 88 · Nov 100 | 1548 |
| Espenrotkappe | *Leccinum aurantiacum* | Sep | Jul 38 · Aug 71 · Sep 100 · Okt 61 | 1487 |
| Falscher Pfifferling | *Hygrophoropsis aurantiaca* | Okt–Nov | Aug 25 · Sep 64 · Okt 80 · Nov 100 · Dez 76 | 3724 |
| Fichtenreizker | *Lactarius deterrimus* | Aug–Okt | Jul 54 · Aug 94 · Sep 100 · Okt 83 · Nov 65 | 7334 |
| Flaschenstäubling | *Lycoperdon perlatum* | Sep–Okt | Jul 34 · Aug 65 · Sep 94 · Okt 100 · Nov 70 · Dez 42 | 8649 |
| Fliegenpilz | *Amanita muscaria* | Okt | Aug 36 · Sep 55 · Okt 100 · Nov 68 | 12880 |
| Flockenstieliger Hexenröhrling | *Neoboletus luridiformis* | Jun–Aug | Jun 100 · Jul 91 · Aug 98 · Sep 77 · Okt 33 | 1248 |
| Frauentäubling | *Russula cyanoxantha* | Jul | Jun 76 · Jul 100 · Aug 66 · Sep 41 | 9504 |
| Frühjahrsknollenblätterpilz | *Amanita verna* | Mai | Mai 100 · Jun 75 · Jul 44 | 56 — **wird nicht gezeigt** |
| Frühjahrslorchel | *Gyromitra esculenta* | Apr | Mär 38 · Apr 100 · Mai 28 | 442 |
| Fuchsiger Rötelritterling | *Paralepista flaccida* | Nov | Sep 34 · Okt 79 · Nov 100 · Dez 65 | 3283 |
| Gallenröhrling | *Tylopilus felleus* | Aug | Jul 77 · Aug 100 · Sep 44 | 2395 |
| Gifthäubling | *Galerina marginata* | Nov | Sep 29 · Okt 69 · Nov 100 · Dez 63 | 2979 |
| Goldröhrling | *Suillus grevillei* | Aug–Sep | Jun 36 · Jul 67 · Aug 100 · Sep 91 · Okt 59 | 5715 |
| Grünblättriger Schwefelkopf | *Hypholoma fasciculare* | Okt–Nov | Apr 38 · Mai 64 · Jun 54 · Jul 32 · Aug 42 · Sep 63 · Okt 97 · Nov 100 · Dez 60 | 12749 |
| Grüner Knollenblätterpilz | *Amanita phalloides* | Aug–Okt | Jul 37 · Aug 100 · Sep 96 · Okt 84 · Nov 28 | 3770 |
| Grüngefelderter Täubling | *Russula virescens* | Jul–Aug | Jul 100 · Aug 86 · Sep 29 | 1367 |
| Grünling | *Tricholoma equestre* | Okt–Nov | Jan 29 · Sep 34 · Okt 100 · Nov 97 · Dez 33 | 427 |
| Habichtspilz | *Sarcodon imbricatus* | Aug–Sep | Jul 31 · Aug 100 · Sep 94 · Okt 39 | 2718 |
| Hallimasch | *Armillaria* (Gattung) | Okt–Nov | Sep 29 · Okt 100 · Nov 80 | 6597 |
| Herbsttrompete | *Craterellus cornucopioides* | Aug–Okt | Jul 35 · Aug 85 · Sep 97 · Okt 100 · Nov 68 | 2684 |
| Igelstachelbart | *Hericium erinaceus* | Nov–Dez | Sep 40 · Okt 77 · Nov 100 · Dez 93 | 94 — **wird nicht gezeigt** |
| Judasohr | *Auricularia auricula-judae* | Jan–Feb | Jan 82 · Feb 100 · Mär 64 · Apr 47 · Mai 31 · Dez 73 | 6668 |
| Kahler Krempling | *Paxillus involutus* | Sep–Okt | Jul 34 · Aug 52 · Sep 91 · Okt 100 · Nov 64 | 4983 |
| Karbolchampignon | *Agaricus xanthodermus* | Sep–Okt | Jun 75 · Jul 72 · Aug 77 · Sep 82 · Okt 100 · Nov 68 | 906 |
| Kegelhütiger Knollenblätterpilz | *Amanita virosa* | Aug | Aug 100 · Sep 67 | 560 |
| Kiefernreizker | *Lactarius sanguifluus* | Nov | Okt 65 · Nov 100 | 303 |
| Kiefernsteinpilz | *Boletus pinophilus* | Aug–Sep | Mai 42 · Jun 79 · Jul 79 · Aug 84 · Sep 100 · Okt 77 · Nov 44 | 588 |
| Krause Glucke | *Sparassis crispa* | Sep–Okt | Aug 61 · Sep 100 · Okt 88 · Nov 60 · Dez 69 | 1695 |
| Käppchenmorchel | *Morchella semilibera* | Apr | Apr 100 · Mai 33 | 697 |
| Körnchenröhrling | *Suillus granulatus* | Jul–Sep | Mai 27 · Jun 75 · Jul 86 · Aug 100 · Sep 89 · Okt 59 · Nov 32 | 2255 |
| Lachsreizker | *Lactarius salmonicolor* | Sep–Nov | Jul 29 · Aug 55 · Sep 83 · Okt 100 · Nov 91 | 3888 |
| Leberpilz | *Fistulina hepatica* | Aug–Sep | Jul 26 · Aug 89 · Sep 100 · Okt 58 | 1379 |
| Ledertäubling | *Russula integra* | Aug | Jul 70 · Aug 100 · Sep 71 · Okt 32 | 3864 |
| Lungenseitling | *Pleurotus pulmonarius* | Jun | Mai 28 · Jun 100 · Jul 51 · Aug 39 · Sep 32 | 982 |
| Maipilz | *Calocybe gambosa* | Mai | Apr 48 · Mai 100 | 2386 |
| Maronenröhrling | *Imleria badia* | Sep–Okt | Jul 48 · Aug 72 · Sep 92 · Okt 100 · Nov 77 | 7700 |
| Mohrenkopfmilchling | *Lactarius lignyotus* | Aug | Jul 49 · Aug 100 · Sep 61 | 1537 |
| Morchelbecherling | *Disciotis venosa* | Apr | Apr 100 | 831 |
| Mönchskopf | *Infundibulicybe geotropa* | Nov | Sep 25 · Okt 72 · Nov 100 · Dez 63 | 2266 |
| Nebelkappe | *Clitocybe nebularis* | Nov | Okt 63 · Nov 100 · Dez 44 | 7537 |
| Nelkenschwindling | *Marasmius oreades* | Jun | Mai 78 · Jun 100 · Jul 56 · Aug 44 · Sep 37 · Okt 42 · Nov 43 | 3169 |
| Netzstieliger Hexenröhrling | *Suillellus luridus* | Jul | Jun 68 · Jul 100 · Aug 72 · Sep 29 | 4822 |
| Orangefuchsiger Raukopf | *Cortinarius orellanus* | Aug–Sep | Jun 25 · Jul 78 · Aug 100 · Sep 80 · Okt 64 · Nov 26 | 324 |
| Pantherpilz | *Amanita pantherina* | Jul–Okt | Jun 62 · Jul 100 · Aug 99 · Sep 94 · Okt 98 · Nov 44 | 3282 |
| Parasol | *Macrolepiota procera* | Sep–Okt | Jul 42 · Aug 65 · Sep 80 · Okt 100 · Nov 75 | 8423 |
| Perlpilz | *Amanita rubescens* | Jun–Jul | Jun 83 · Jul 100 · Aug 72 · Sep 46 · Okt 28 | 11850 |
| Pfifferling | *Cantharellus cibarius* | Jul | Jun 53 · Jul 100 · Aug 74 · Sep 40 | 8436 |
| Rehbrauner Dachpilz | *Pluteus cervinus* | Mai–Jun | Apr 49 · Mai 100 · Jun 90 · Jul 66 · Aug 56 · Sep 76 · Okt 88 · Nov 85 | 6247 |
| Reifpilz | *Cortinarius caperatus* | Aug | Feb 45 · Jul 59 · Aug 100 · Sep 67 | 2375 |
| Riesenbovist | *Calvatia gigantea* | Aug | Jan 83 · Feb 34 · Mär 43 · Apr 31 · Mai 36 · Jun 36 · Jul 79 · Aug 100 · Sep 69 · Okt 37 | 1043 |
| Riesenrötling | *Entoloma sinuatum* | Aug–Okt | Jul 41 · Aug 95 · Sep 100 · Okt 84 · Nov 33 | 471 |
| Riesenträuschling | *Stropharia rugosoannulata* | Mai | Apr 29 · Mai 100 · Jun 46 | 364 |
| Rotfußröhrling | *Xerocomellus chrysenteron* | Jul–Okt | Jun 75 · Jul 100 · Aug 87 · Sep 88 · Okt 90 · Nov 56 | 7764 |
| Rotkappe | *Leccinum* (Gattung) | Sep | Jun 30 · Jul 53 · Aug 73 · Sep 100 · Okt 75 | 7351 |
| Safranschirmling | *Chlorophyllum* (Gattung) | Okt–Nov | Jul 30 · Aug 44 · Sep 73 · Okt 100 · Nov 82 | 2887 |
| Samtfußrübling | *Flammulina velutipes* | Dez–Jan | Jan 93 · Feb 60 · Mär 26 · Dez 100 | 3686 |
| Sandröhrling | *Suillus variegatus* | Sep–Okt | Jul 33 · Aug 74 · Sep 100 · Okt 91 · Nov 48 | 1352 |
| Satansröhrling | *Rubroboletus satanas* | Aug–Sep | Jul 67 · Aug 100 · Sep 96 | 671 |
| Scheidenstreifling | *Amanita vaginata* | Jul–Aug | Jun 48 · Jul 100 · Aug 88 · Sep 57 · Okt 29 | 3228 |
| Schopftintling | *Coprinus comatus* | Okt | Sep 48 · Okt 100 · Nov 78 | 7151 |
| Schwefelporling | *Laetiporus sulphureus* | Mai | Apr 27 · Mai 100 · Jun 42 · Aug 27 | 3946 |
| Semmelstoppelpilz | *Hydnum repandum* | Aug–Sep | Jul 45 · Aug 100 · Sep 93 · Okt 72 · Nov 61 · Dez 29 | 5339 |
| Sommersteinpilz | *Boletus reticulatus* | Jun | Jun 100 · Jul 78 · Aug 40 | 3543 |
| Speisemorchel | *Morchella esculenta* | Apr | Apr 100 · Mai 42 | 1993 |
| Speisetäubling | *Russula vesca* | Jul | Jun 54 · Jul 100 · Aug 71 · Sep 39 | 4107 |
| Speitäubling | *Russula emetica* | Aug–Sep | Jul 66 · Aug 100 · Sep 83 · Okt 43 | 1355 |
| Spitzgebuckelter Raukopf | *Cortinarius rubellus* | Aug | Jul 61 · Aug 100 · Sep 60 | 1188 |
| Spitzmorchel | *Morchella elata* | Apr | Mär 53 · Apr 100 · Mai 43 | 1052 |
| Stadtchampignon | *Agaricus bitorquis* | Mai | Mai 100 · Jun 77 · Jul 41 · Aug 29 | 939 |
| Steinpilz | *Boletus edulis* | Aug–Sep | Jul 67 · Aug 100 · Sep 96 · Okt 66 · Nov 32 | 8789 |
| Stockschwämmchen | *Kuehneromyces mutabilis* | Mai–Jun | Apr 36 · Mai 100 · Jun 91 · Jul 63 · Aug 63 · Sep 68 · Okt 85 · Nov 78 · Dez 49 | 5346 |
| Tigerritterling | *Tricholoma pardinum* | Sep | Aug 57 · Sep 100 · Okt 75 | 590 |
| Trompetenpfifferling | *Craterellus tubaeformis* | Sep–Nov | Jan 26 · Aug 62 · Sep 94 · Okt 100 · Nov 97 · Dez 51 | 3821 |
| Violetter Lacktrichterling | *Laccaria amethystina* | Okt | Aug 46 · Sep 77 · Okt 100 · Nov 76 | 7348 |
| Violetter Rötelritterling | *Lepista nuda* | Nov | Okt 79 · Nov 100 · Dez 37 | 4387 |
| Waldchampignon | *Agaricus sylvaticus* | Jul–Okt | Jan 42 · Jun 48 · Jul 92 · Aug 86 · Sep 100 · Okt 97 · Nov 65 | 1843 |
| Wiesenchampignon | *Agaricus campestris* | Aug–Okt | Mai 26 · Jun 58 · Jul 68 · Aug 87 · Sep 100 · Okt 91 · Nov 78 | 1718 |
| Ziegelroter Risspilz | *Inosperma erubescens* | Jun | Jun 100 | 441 |
| Ziegenbart | *Ramaria* (Gattung) | Aug–Sep | Jul 36 · Aug 100 · Sep 95 · Okt 56 · Nov 43 | 4747 |
| Ziegenlippe | *Xerocomus subtomentosus* | Jul–Aug | Jun 65 · Jul 100 · Aug 97 · Sep 70 · Okt 36 | 3589 |
