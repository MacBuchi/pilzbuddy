# PilzBuddy — Arbeitsregeln für `lib/features/ampel/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Das Ampel-Banner rechnet beim Start, nicht auf einem Server**
  (Baustein B aus #277, seit 1.101.0): Ein Hinweis auf der Karte, wenn
  die Ampel an einem EIGENEN Spot günstig steht
  (`lib/features/ampel/ampel_scan.dart`). Vier Dinge, die man wissen
  muss:
  - **Die KARTE zeigt das Maximum über alle Klassen** (seit 1.140.0,
    Betreiber 2026-09-12: „soll das Maximum für alle Klassen wiedergeben
    und nicht nur für eine"). Die Regel steht in `ampelBestOf`
    (Gitterweg) und `ampelBestReadingFrom` (volle Ablesung) — und NUR
    dort; Fläche, Legende und „Was ist hier?" müssen dieselbe Antwort
    geben, `test/ampel_fill_test.dart` hält sie Zelle für Zelle zusammen
    (#279). Fünf Dinge:
    - **Saison-Tor je KLASSE auf der Fläche** (seit 1.157.0, #495;
      davor galt „kein Saison-Tor auf der Fläche", weil die Fläche keine
      Art kennt). Die Antwort darauf ist das Maximum über die
      Mitglieder: Eine Klasse rechnet, solange mindestens eine ihrer
      Arten Saison hat (`ampel_season_gate.dart`, Tor, kein Faktor).
      Anlass: „Austernseitling & Co." war im September günstig — zu
      Recht, für Krause Glucke und Leberpilz (Saisonanteil 100), der
      Austernseitling liegt bei 3. Das Fenster kommt aus dem
      Case-Crossover, die Saison kürzt sich dort heraus; die Klasse
      sagt nie „es ist die Saison". Die Legende nennt deshalb, wer die
      Klasse gerade trägt („jetzt: Krause Glucke, Leberpilz"), sobald
      es nicht der Namensgeber ist. Fläche, Legende, Ampel-Blatt,
      Spot-Blatt und Nachlauf lesen `activeAmpelClassesProvider`; die
      Fundorte-Scheiben lesen weiter die rohe Auswahl, sie zeigen
      Meldungen, keine Ampel. Frost/Mindesttemperatur war Laborarbeit
      (#497) — und ist seit 1.160.0 als „milder" ein Code-Wert, siehe
      unten.
    - **Arten lassen sich von der Ampel ausnehmen** (#495, Schalter je
      Art im Reiter „Pilze", gerätelokal `ampel_excluded_species`):
      raus aus Nachlauf, Spot-Blatt und dem Saison-Tor — alle Arten
      einer Klasse aus heißt Klasse aus.
    - **Bei Gleichstand gewinnt die frühere Klasse, nicht der höhere
      Score.** Scores verschiedener Klassen sind nicht vergleichbar:
      Jede Schwelle ist auf ihre eigene Verteilung kalibriert, 0,55
      heißt im Herbstfenster „günstig" und im Sommerfenster
      „verhalten". Aus demselben Grund sortiert das Blatt nach STUFE
      und nicht nach Score.
    - **Die Häufigkeit steigt, und das ist gewollt:** 19,9 % → 30,2 %
      günstige Vergleichstage (`docs/pilzampel-schwellen-messung.md`).
      Es wird mehr behauptet — „für mindestens eine von zwei Gruppen" —,
      also gilt es öfter. Wer eine Klasse hinzufügt, misst die Quote neu.
    - **Die Ampel gilt nur für SAMMELPILZE** (Betreiber, 2026-09-22:
      „für giftige / ungenießbare Pilze brauchen wir keine Ampel").
      Heute stimmt das ohnehin — 16 Arten, alle Speisepilz oder nur
      gegart —, aber seit 1.171.0 hält `test/ampel_model_test.dart`
      es fest. Eine Günstig-Meldung über einen Giftpilz läse sich als
      Einladung, und der Weg von einem neuen Verwechslungspartner in
      eine Ampel-Gruppe ist eine Zeile.
    - **Die Klassen stehen einzeln nur in der AUSGEKLAPPTEN Legende**
      (Betreiberauflage). `_AmpelSection` steckt ohnehin nur im
      `_LegendPanel`; die 40-px-Schiene trägt ihr Urteil in der Form des
      Daumens, eine Aufzählung passt dort nicht hin. Ein Test prüft
      beide Richtungen.
    - **Der Nutzer kann Gruppen abwählen** (seit 1.142.0, Chips im
      Kartenfilter; Betreiber: „Default sollte alles an sein" und
      „auch die Fläche"). Die Auswahl liegt als `SpotFilter.classes`
      (leer = alle, wie bei den Arten) und wird über
      `selectedAmpelClassesProvider` EINMAL aufgelöst — Fläche,
      Legende, Nachlauf und Ampel-Filter lesen dieselbe Liste. Vier
      Dinge, die man wissen muss:
      - **Sie gehört in den FILTER, nicht zu den Ebenen-Schaltern.**
        Ein Filter muss sich auf der Karte melden (#154), und das tut
        nur, was in `describe()` steht — ein Ebenen-Schalter hätte
        diese Pflicht nicht, und die Karte zeigte dann eine engere
        Aussage, ohne es zu sagen. Der Chip sagt „Ampel:
        Steinpilz & Co." und bewusst nicht „nur …": Die Gruppe
        „Pfifferling" heißt wie die Art, und „nur Pfifferling" schreibt
        schon die Artenauswahl.
      - **Sie muss in den DATEINAMEN der Fläche** (`forestFillVariant`).
        Dieselbe Falle wie bei Klassenwahl, Fenster und Feinstufe: Die
        MapLibre-Strecke ist idempotent auf der URL, gleicher Name
        heißt altes Bild.
      - **Sie hängt NICHT am `ampelLevelGridProvider`.** Das Gitter
        trägt die Zutaten und ist die teure Hälfte (Isolate, 26
        Entpackungen); ausgewertet wird beim Abnehmer. Hinge die
        Auswahl im Gitter, würfe jeder Chip-Tipp es weg.
      - **Der Hinweis zieht mit.** `ampelScanOf` überspringt abgewählte
        Gruppen — sonst stünde „2 Spots" über einer Karte, auf der nach
        dem Tipp einer liegt. Die Chips selbst zeigt das Blatt nur bei
        eingeschalteter Vorschau: Ohne sie rechnet die Ampel nirgends,
        und der Artenliste fehlt der Platz.
  - **Die Einheit des Modells ist die KLASSE, nicht die Art** (seit
    1.137.0, Betreiber 2026-09-12). Eine Klasse ist ein
    Temperaturfenster; die beiden Stufenschwellen folgen daraus als
    Quantile der Score-Verteilung an Vergleichstagen und stehen NICHT
    mehr als zwei globale Zahlen da. Drei Dinge, die man wissen muss:
    - **Eine Schwelle gilt für EIN Fenster.** Der Austernseitling kommt
      mit den alten 0,5 auf 1,1 % günstige Fundtage, der Steinpilz auf
      58,4 % — ein eigenes Fenster ohne eigene Schwelle macht die Ampel
      dunkel, nicht besser. Umgekehrt sind die Schwellen von Arten, die
      sich ein Fenster teilen, nicht unterscheidbar; je Art ausgeliefert
      wären sie Rauschen in Konstantenform.
    - **Eine Klasse kommt erst nach einem HOLD-OUT hinein** — angepasst
      auf einem Teil der Daten, bestätigt auf Daten, die daran nie
      beteiligt waren. „Fällt in der Tabelle auf" reicht nicht; daran
      wäre die Pfifferling-Spur fast gescheitert. Hallimasch,
      Stockschwämmchen und Austernseitling haben gemessene Fenster und
      bleiben trotzdem grau.
      **Am 2026-09-13 sind zwei registrierte Erweiterungen daran
      gescheitert**, und beide Male auf dieselbe Weise: Geprüft wird das
      Fenster der KLASSE im Ausland (`--holdout AT,CH --class <key>`),
      nicht das jeder Art für sich — ausgeliefert würde ja ein Fenster
      für alle Mitglieder.
      - **Herbst-Holz** (11,625 °C): Hallimasch +0,018, Stockschwämmchen
        **−0,036** gegenüber 13 °C, beide Kontrollen sauber bei 0,501.
      - **Kalt** (−1,0 °C): Der Judasohr fällt mit −0,066 [−0,117,
        −0,013] unter die 13 °C zurück und passt sich in AT+CH auf
        12,0 °C an statt auf seine deutschen 1,5.
      Zwei Lehren, die bleiben: Ein Kalttest in Deutschland kann
      bestehen, ohne dass die Klasse REIST (`docs/pilzampel-kalttest.md`
      gegen `docs/pilzampel-kaltklasse-holdout.md`) — und ein sauber
      gemessener Fehlschlag EINES Mitglieds entscheidet nach „alle oder
      keine", auch wenn ein anderes ungemessen bleibt. Ein Bericht, der
      das als „noch nicht entschieden" führt, verschiebt die
      Entscheidung auf Daten, die nichts mehr ändern können.
    - **Die Schwellen altern.** Dieselbe 0,5 wurde vor 2019 an rund 30 %
      der Vergleichstage überschritten, seither an rund 20 % — die Ampel
      war im Feld still pessimistischer geworden, ohne Codeänderung. Wer
      sie anfasst, misst nach (`tool/ampel_validate.py --thresholds`,
      rechnet nur aus dem Cache) und schreibt das Datum dazu. Wie oft
      die Ampel „günstig" sagen soll, ist dabei eine
      Produktentscheidung und keine Messung; sie steckt im Quantil
      (80 %) und lautet „gleich häufig wie bisher".
    - **Die Klasse Holz & Winter hat seit 1.160.0 eine SECHSTE
      Konstante, „milder"** (#497, Labor 19–24, `docs/pilzampel-frost-plan.md`):
      das Mittel der Tagesminima der letzten fünf Tage minus das der
      Tage 6 bis 28, in °C, +0,042 je Grad. Fünf Dinge, die man wissen
      muss:
      - **Es ist die ABFOLGE, nicht der Frost.** Vor Fundtagen der
        Winterarten sind die letzten Tage milder und die Wochen davor
        kälter (Labor 21); Frosttage-Zählungen summieren genau das weg
        und trugen auf den Testblöcken nichts (Labor 19). Der Anlass
        war die Betreiberfrage „Minusgrade (Aktivierung) gefolgt von
        milderen Bedingungen?" — und die Regel dahinter: erst die
        vorhandenen Daten verstehen, dann eine Hypothese rechnen.
      - **Gewählt auf Training, bestätigt auf Test** (Betreiberregel
        vom 2026-09-21: Anpassungen nur auf den Trainingsblöcken DE +
        AT + CH, die Testblöcke bewerten). Auf den 1 970 Teststrata
        +0,007 [+0,001, +0,013] je Stratum gegen das
        Fünf-Konstanten-Logit, keine Art schlechter, Placebo mit
        permutiertem Merkmal −0,002 ▼ — der Preis EINES nutzlosen
        Parameters, und die Messlatte für jeden weiteren. Ein
        Zwanzigstel dessen, was die Klasse selbst gebracht hat.
      - **Die Stationstabelle trägt dafür 28 statt 20 Tage** (#506,
        `tool/spot_weather.py`, seit dem 2026-09-21). Eine ältere
        Tabelle füllt das Fenster nicht, und dann ist DIESE Klasse grau
        mit Grund („Tagesminima der Station: keine 28 vollständigen
        Tage"), klassenspezifisch wie ohne Bodenfeuchte — kein Mittel
        aus 20 Tagen, das wäre eine erfundene Beobachtung. Die Glocken
        rechnen weiter. `ampelMilderOf` verlangt 28 lückenlose Werte;
        die Höhenkorrektur kürzt sich in der Differenz heraus, die
        Minima gehen ROH hinein.
      - **Die Konstante 0 heißt „keine Reihe nötig"** (`AmpelLogit.needsMilder`):
        Herbsttrompete & Co. trägt sie, weil das Merkmal dort nie
        gemessen wurde, und rechnet ohne Minima weiter. Wer einer
        Klasse das Merkmal gibt, misst es für SIE — die Null ist keine
        Vorgabe.
      - **Alle sechs Konstanten sind neu gefittet, die Schwellen neu
        gezogen** (Kandidat K6_5 in `24-testbloecke-abfolge.md`;
        0,387 / 0,558 statt 0,454 / 0,606, `tool/ampel_logit_klasse.py
        --schwellen`). Der Python-Selbsttest hält Dart und Werkzeug
        Zahl für Zahl zusammen — deshalb kommen Werkzeug und Dart-Kern
        immer im SELBEN PR.
  - **Es gibt keinen dritten Modellkern.** `ampelScanOf` ruft dasselbe
    `ampelReadingFrom` wie das Spot-Blatt. Ein nächtlicher Server-Push
    hätte das Modell neben `ampel_model.dart` und
    `tool/ampel_validate.py` ein drittes Mal geführt — genau die Stelle,
    an der der geforderte Gleichlauf „Zahl für Zahl" unbemerkt
    auseinanderläuft. Der Preis dafür ist ehrlich: Der Hinweis erreicht
    einen beim ÖFFNEN der App, also wenn man ihn am wenigsten braucht.
  - **Ein EIGENER Schalter, nicht der der Ampel-Vorschau**
    (`ampelBannerEnabled`, ab Werk aus). Der Nachlauf braucht das
    Höhengitter, und dessen 3,4 MB beim Start auszupacken ist genau die
    Last, die 1.99.4 aus dem Startpfad genommen hat. Ohne Höhe rechnen
    wäre kein Ausweg: #279 verlangt, dass Fläche und Blatt gleich
    korrigieren, und in den Alpen sind das ~3 K — ein Banner, das dem
    Blatt widerspricht, wäre schlimmer als keins. **Die Reihenfolge der
    Prüfungen in `ampelScanProvider` IST die Zusage**: erst alle
    Schalter, dann das erste `ref.watch` auf ein Gitter. Beobachten ist
    laden. Ein Flow-Test hält es fest.
  - **Nur `guenstig` zählt.** „Verhalten" ist die Mehrzahl der Tage und
    damit ein Banner, das immer steht — und eines, das immer steht, sagt
    nichts mehr.
  - **Der Hinweis paart ZWEI Bedingungen, und zwar je ART** (seit
    1.138.0, Betreiber 2026-09-12): Die Klasse dieser Art muss günstig
    stehen UND ihre Saisonkurve muss sagen, dass sie jetzt überhaupt
    auftaucht. Ein Spot erscheint, sobald das für eine seiner Arten
    zusammenfällt; der Treffer trägt ihren Namen (`AmpelHit.species`).
    Vier Dinge, die man wissen muss:
    - **Beides über den SPOT zu fragen gäbe Unsinn.** An einer Stelle
      mit Pfifferling- und Steinpilzfunden stünde im Juli die Ampel des
      Herbstfensters (jüngster Fund), während das Saison-Tor wegen des
      Pfifferlings aufginge — zwei Aussagen über zwei Pilze, zu einer
      verrechnet. Gepaart wird deshalb innerhalb der Art.
    - **Die Saison ist ein TOR, kein Faktor.** In den Score darf sie
      nicht: Die Validierung vergleicht den Fundtag gegen Tage
      DERSELBEN Saison, dort kürzt sie sich heraus und ist prinzipiell
      ungeprüft. Als Bedingung „taucht die Art jetzt auf" ist sie eine
      Tatsache über GBIF-Meldungen und braucht keine Validierung.
    - **Banner, Filter und Blatt müssen dieselbe Menge zeigen.** Der
      Tipp setzt deshalb BEIDE Filter (`onlyAmpel` und `onlySeason`,
      beide im Chip genannt — #154), das Blatt zeigt seit 1.138.0 EINE
      ZEILE JE ART (`scanSpeciesOf`, geteilt mit dem Nachlauf) statt nur
      der des jüngsten Fundes, und der Monat kommt aus
      `currentMonthProvider` und nicht aus `DateTime.now()`.
    - **Die Saisonkurven sind damit AUSLIEFERUNGSRELEVANT geworden.**
      `lib/core/season_curves.g.dart` ist ein erzeugtes Asset
      (`tool/season_curves.py`, GBIF, kein Open-Meteo-Kontingent) — und
      seit es das Tor stellt, verschiebt jede Neuerzeugung, welche Spots
      der Hinweis meldet. Wer sie neu baut, misst nach, in wie vielen
      Art-Monaten `months[m] >= kSeasonNowThreshold` kippt, und schreibt
      die Zahl in den PR. Beim Lauf vom 2026-09-12 war es **1 von 1080**
      (Schwefelporling im März, 14 → 15).
    - **Eine Art ohne genug Material kann die Kurve ihrer
      Verwandtschaft BORGEN** (seit 1.139.0): `curveFrom` (Gattung,
      wissenschaftlich) plus `curveFromName` (deutsch, für den Satz) in
      `mushroom_species.dart`; das Werkzeug fragt GBIF nach der Gattung
      und schreibt `borrowedFrom` in die Kurve. Drei Dinge:
      - **Das ist NICHT `isGenus`.** Dort ist der deutsche Name selbst
        ein Sammelbegriff („Rotkappe"), die Kurve gehört also dem, was
        eingetragen wurde. Beim Borgen meint der Name genau eine Art —
        die Anzeige sagt deshalb „Saison nach verwandten Arten: …“ statt
        „(mehrere ähnliche Arten)“.
      - **Es geht nur, wenn die Verwandtschaft eine gemeinsame Saison
        hat.** *Hericium* ja (1147 Meldungen, alle Stachelbärte);
        *Amanita* nein — 60 448 Meldungen, aber Frühjahrs- UND
        Herbstarten gemischt, für den Frühjahrsknollenblätterpilz zeigte
        die Kurve in die Gegenrichtung. Der bleibt ohne, und bei einem
        tödlich giftigen Pilz ist das die richtige Richtung.
      - **`curveFrom` ohne `curveFromName` bricht den Bau ab**, und
        `test/species_test.dart` hält Artenliste und Asset in beide
        Richtungen zusammen: keine geborgte Kurve ohne Quelle, keine
        Quelle an einer Kurve, die nicht borgt.
    - **Im Zweifel zeigen** — die Regeln des Saison-Filters (#414)
      gelten hier genauso: Eine Art ohne Kurve verdeckt nichts (`null`
      heißt „wir wissen es nicht"), ein Spot ohne eingetragene Art
      bleibt die Gildenfrage. Und die Wortleiter im Blatt („Hauptzeit /
      Nebenzeit / Randzeit / kaum gemeldet") hängt unten an
      `kSeasonNowThreshold` — sonst stünde dort „außerhalb", während das
      Banner für dieselbe Art anschlägt.
  - **Der Wortlaut trägt das Urteil.** Die Ampel bewertet BEDINGUNGEN,
    nie Vorkommen. Also „2 Spots · **Ampel günstig (experimentell)**",
    kein „geh jetzt", kein Ausrufezeichen.
    **Geändert am 2026-09-12** (vorher „stünde die Ampel günstig"): Der
    Konjunktiv war mit der durchgefallenen Arten-Kontrolle begründet —
    und die ist aufgelöst, sie war an ihrer AUSWAHL gescheitert
    (`docs/pilzampel-artenfenster-messung.md`). Er tat ohnehin nicht,
    was er sollte: „Ampel günstig" behauptet nichts über Pilze, sondern
    sagt, was die Ampel zeigt. Den Vorbehalt trägt „experimentell", und
    der steht deutlicher da, wenn er nicht um Platz ringt.
    **Was bleibt:** „experimentell" ist ein eigenes Stück im Chip, nicht
    Teil des Textes — dort würde es als Erstes abgeschnitten. Lieber ein
    gekürzter Ortsname als ein gekürzter Vorbehalt.
  - **Ein Urteilswort nur, wo die Zutat die Stufe entscheidet** (#663,
    seit 1.222.6). Die Fakten-Zeile (`_components` in
    `spots/widgets/ampel_section.dart`) sagt bei der Glocke „Regen: zu
    trocken" und „Temperatur: zu kühl" — dort ist der Score ein PRODUKT,
    eine schwache Zutat zieht ihn wirklich herunter. Das Logit rechnet
    additiv; Austernseitling & Co. war mit den alten Konstanten schon ab
    F ≈ 0,15 „günstig" (seit #676 bei 13 °C ab F ≈ 0,26 „verhalten"), und
    „zu trocken" darunter las sich als Widerspruch. Bei Logit-Klassen
    steht deshalb nur die Menge („wenig / mäßig / reichlich") bzw. die
    Zahl. Ein neues Wort in der Zeile an derselben Frage messen: Kann
    die Stufe ihm widersprechen?
  - **Die Bodenfeuchte kennt keine Landesgrenze, nur einen Abstand**
    (#665, seit 1.222.7). Alle Feuchtestationen stehen in Deutschland;
    wie weit eine Logit-Klasse ins Ausland reicht, entscheidet allein
    `AmpelLogit.maxMoistureKm`. Austernseitling & Co. brauchte bis
    1.222.x die 100 km der Tabelle und braucht seit #676 gar keine
    Station mehr (siehe nächster Punkt). Herbsttrompete & Co. reist nicht und bekommt
    30 km: in Deutschland 0,43 % der Fläche grau, im Ausland ein Streifen
    (Straßburg, Basel, Salzburg, Innsbruck rechnen; Colmar, Vogesen
    nicht). Gemessen gegen die DWD-Stationsliste auf einem Raster über
    den Natural-Earth-Umriss; Zahlen am Kommentar der Klasse. Blatt
    (`ampel_providers.dart`, echter Abstand) und Fläche
    (`AmpelLevelGrid.moistureKm`, aufgerundete km) prüfen dieselbe
    Grenze — eine ganze Zahl, sonst fallen sie an verschiedenen Stellen.
  - **Austernseitling & Co. rechnet ohne Bodenfeuchte** (#676, seit
    1.223.0, Labor 25/26, Betreiber 2026-10-08: „Ohne Feuchte"). Labor 25
    stellte die DWD-Feuchte gegen ERA5-Land in drei Schichten: Für diese
    Klasse trägt die Feuchte aus keiner Quelle etwas — das Placebo
    (Feuchte je Stratum vertauscht) gewann in AT/CH fast so viel wie
    ERA5; der Gewinn dort war „rechnet statt grau", nicht die Feuchte.
    Labor 26: ohne die beiden Feuchtekonstanten in DE −0,007 n.s., keine
    Art schlechter, in AT/CH gegen „grau jenseits 100 km" ▲. Drei Dinge,
    die man wissen muss:
    - **Zwei Nullen heißen „keine Reihe nötig"** (`AmpelLogit.needsMoisture`,
      wie `needsMilder`): Dann zählen weder Reihe noch Abstand, Blatt
      und Fläche rechnen die Klasse überall, wo Regen und Temperatur
      antworten — in AT, CH und der Alpenbox über das Modellgitter.
    - **Die Schwellen sind auf einer anderen Skala** (0,099 / 0,255 statt
      0,387 / 0,558): Ohne Feuchtespalten verschiebt sich `s` als Ganzes.
      Gemessen auf ALLEN P1-Strata, nicht nur denen mit DWD-Station —
      wie die App jetzt rechnet. Herbsttrompete & Co. kam bei derselben
      Messung unverändert heraus (Gegenprobe der Messung).
    - **Der Preis ist ehrlich zu nennen:** AUC auf dem Testteil 0,576 →
      0,555, ohne gesicherten Verlust in der Log-Likelihood. Wer die
      Klasse wieder mit einer Feuchte versucht, misst gegen das Placebo,
      nicht gegen „grau" — sonst gewinnt wieder nur das Rechnen an sich.
  - **Das X schaltet nur für die SITZUNG stumm** (#425, seit 1.128.1) —
    vorher bis Tagesende, mit der Begründung „morgen sind es andere
    Daten und damit eine andere Aussage". Die stimmt weiter; ungeprüft
    blieb der Preis. Ein Tipp nahm das Feature für bis zu 24 Stunden
    weg, nirgends stand, dass eine Stummschaltung läuft, und zurück
    führte kein Weg außer Warten — während der Schalter im Profil sich
    weiter als „an" las. Gemeldet als „ich bekomme kein Banner mehr",
    und zwar vom Betreiber selbst: Wer nicht erkennen kann, dass er es
    abgeschaltet hat, hält es für kaputt. Es war die ZWEITE Meldung
    dieser Form (#349: „das Banner schaltet sich beim Antippen selbst
    stumm").
    Die Sitzungsgrenze macht einen Rückweg in der Oberfläche
    überflüssig — der nächste Start IST der Rückweg. Deshalb steht der
    Zustand jetzt als `bool` in `ampelBannerMutedProvider` und nicht
    mehr in den Einstellungen; der Prefs-Schlüssel
    `ampel_banner_dismissed_until` liegt auf Bestandsgeräten weiter
    herum und wird nie wieder gelesen (Vermerk in `settings.dart`).
  Der gebündelte `rainCoursesProvider` ist der Provider zum längst
  vorhandenen `rainCoursesFrom` (1.99.3): 19 Spots kosten 26
  Dekodierungen statt 494. Sein Familienschlüssel ist eine
  zusammengefügte Zeichenkette, keine Liste — zwei inhaltlich gleiche
  Listen sind für `==` verschieden.

- **Höhengitter & Temperaturkorrektur** (`tool/elevation_grid.py` +
  `elevation-data.yml`, Rest aus #279, seit 1.93.0): Drittes Gitter auf
  DEMSELBEN Hex-Raster (Copernicus DEM GLO-90, 1 Byte = 20-m-Stufen,
  Zeilen-Delta + gzip, 3,4 MB, Workflow nur `workflow_dispatch` — das
  DEM ist statisch). Blatt-Ampel und Kartenfläche rechnen die
  Stationstemperatur mit 0,65 K je 100 m auf die Wabenhöhe um. Vier
  Dinge, die man wissen muss:
  - **Die Korrektur ist Eingabe-Aufbereitung, keine Modelländerung**:
    `ampel_model.dart` bleibt Zahl für Zahl Spiegel des
    Validierungswerkzeugs. Und sie führt ZUM validierten Aufbau hin —
    `ampel_validate.py` nahm Open-Meteo-Temperaturen an der
    Fundkoordinate, die dort schon aufs 90-m-DEM heruntergerechnet
    sind. Die unkorrigierte Station war die Abweichung.
  - **Fläche und Blatt korrigieren beide oder keiner** (#279-Regel),
    und zwar seit 1.94.0 JE WABE: `AmpelLevelGrid` trägt je Regenzelle
    die ZUTATEN (Regenfaktor, Stationsmittel, Stationshöhe), und erst
    der Abnehmer wertet die Glocke mit SEINER Höhe aus — der
    Wabenzeichner mit der Höhe jeder Waldwabe (grob wie fein), Legende
    und Blatt am Punkt. Eine je Regenzelle fertig gerechnete Stufe
    (so 1.93.0/.1) konnte der Punkt-Ablesung in steilem Gelände nie
    überall zustimmen — eine 1-km-Zelle überspannt in den Alpen 500+
    Höhenmeter (Feldbericht Berchtesgaden). Wächter:
    `test/ampel_fill_test.dart` (Walker) und der Pixel-Test in
    `test/forest_ampel_fill_test.dart`; Messung (316→733 ms Debug im
    teuersten Fall, Isolate) in `docs/map-performance.md`, nachgeprüft
    von `test/perf_ampel_fill_measure.dart`.
    **Die eine Ausnahme** (#662, Betreiber 2026-10-08): Ist eine Wabe
    kleiner als ein Pixel (Übersichtszoom), rechnet die Fläche die Höhe
    in 100-m-Stufen (`ampelOverviewHeightStepM` in `forest_fill.dart`,
    höchstens 40 m = 0,26 K daneben). Dort kann eine Wabe an einer
    Stufengrenze anders leuchten als das Blatt am selben Punkt; nah dran
    gilt die Regel wieder ohne Ausnahme. Nicht eine Höhe je Wetterzelle —
    die Modellzellen im Alpenraum sind 12 km groß.
  - **Das Diagramm zeigt weiter ROHE Stationswerte** (beschriftet mit
    Station + Höhe) — nur die Ampel-Zeile rechnet um und sagt es ab
    ~0,3 K dazu („auf Spothöhe 1200 m"); darunter bleibt der Zusatz
    weg, sonst erklärte im Flachland jeder Spot eine Nullnummer.
  - Ohne Gitter/außerhalb DACH: still unkorrigiert (`null`-Pfad), wie
    vor 1.93.0 — die Stationshöhe steht ja daneben.

