# PilzBuddy — Arbeitsregeln für `lib/features/species/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Der Reiter „Pilze"** (seit 1.153.0): das Artenverzeichnis — je
  Ampel-Gruppe ihre Mitglieder, je Art die Mini-Saisonkurve, hervorgehoben,
  was jetzt Saison hat. Drei Dinge, die man wissen muss:
  - **Der Inhalt ist GERECHNET, nicht geschrieben**
    (`lib/features/species/species_catalogue.dart`, ohne Widgets): Gruppen
    aus `ampelClasses`, Mitglieder aus `ampelSpeciesClass`, Kurven aus
    `season_curves.g.dart`, Belege aus `ampelEvidenceBySpecies`. Wer eine
    Klasse oder Art hinzufügt, muss hier NICHTS tun —
    `test/species_catalogue_test.dart` verlangt, dass jede bekannte Art
    genau einmal darin steht.
  - **Eine Schwelle, ein Balken-Widget, eine Wortleiter.** Hervorhebung ist
    `kSeasonNowThreshold`; die Balken sind `SeasonBars`
    (`lib/core/widgets/`), die auch das Spot-Blatt zeichnet; die Wörter
    kommen aus `seasonShareWord`. Der Reiter darf der Karte nie
    widersprechen — er ist ihre Legende.
  - **Der Filter „Nur jetzt Saison" verdeckt nichts, was er nicht weiß**:
    Arten ohne Kurve bleiben stehen (#414-Regel), leere Gruppen behalten
    die Überschrift.
  - **Die Suche (seit 1.164.0) trifft über drei Namen** — Hauptbezeichnung,
    Zweitnamen und den wissenschaftlichen —, alle drei durch
    `foldSpeciesName` (#395). `speciesSearch` steht widgetfrei im Katalog.
    **Sie macht DENSELBEN Zweischritt wie `suggestSpecies` im Blatt
    „Fund eintragen"**: erst Teiltreffer, und nur wenn der leer ausgeht,
    der Tippfehler-Ausgleich über den Editierabstand. Der erste Entwurf
    ließ den Rückfall weg („ein Filter, der aufweitet, ist keiner") —
    das Argument trägt genau dort nicht, wo der Rückfall greift: Ist
    nichts gefunden, gibt es nichts aufzuweiten, und die Alternative war
    „Keine Art mit diesem Namen", also der Satz, aus dem #395 entstanden
    ist (Betreiber, 2026-09-21). `speciesTypoTolerance` und
    `nearContainsDistance` liegen deshalb seither in
    `mushroom_species.dart` statt privat bei den Vorschlägen.
    Zwei Auflagen dabei: **Die Oberfläche muss sagen, dass sie rät**
    („Meintest du …?") — ein geratener Treffer, der aussieht wie ein
    gefundener, ist eine Behauptung über die Eingabe. Und **nur der
    beste Abstand** wird angeboten: Bei „Steipilz" liegen acht Arten in
    der Toleranz und drei auf dem besten Abstand.
    Zwei Unterschiede bleiben: **leere Gruppen fallen weg**, anders als
    beim Saison-Filter, der seine Überschrift behält, um „keine" zeigen
    zu können; und die **Gesamtzahl im leeren Zustand ist gezählt**,
    nicht geschrieben.
    Nebenwirkung für Tests: Ein `TextField` bringt einen eigenen
    `Scrollable` mit, der im Reiter ist also nicht mehr der einzige.
    `species_detail_flow_test.dart` sucht seither, statt zu scrollen —
    kürzer UND eindeutig.
  - **Je Art eine Seite darunter** (#511, seit 1.162.0): Route
    `/pilze/:name` als Unterroute wie die Seiten des Profil-Tabs,
    gerechnet in `speciesDetailFor` (weiter widgetfrei), gezeichnet von
    `species_detail_screen.dart`. Sie zeigt, wofür in der Zeile kein
    Platz war — wissenschaftlicher Name, Zweitnamen („auch: …", derselbe
    Wortlaut wie im Spot-Blatt), die volle Kurve MIT Monatsbuchstaben,
    Gruppe samt Fenster und Belegen, eigene Funde und die
    GBIF-Meldungen. Fünf Dinge, die man wissen muss:
    - **Der Satz zur Kurve steht seither in `season_curves.dart`**
      (`seasonSentence`/`seasonSourceLine`), nicht mehr im Spot-Blatt:
      Zwei Fassungen wären zwei Meinungen darüber, wie stark eine
      GEBORGTE Kurve einzuschränken ist — und bis 1.161.0 sagte der
      Reiter „Pilze" davon gar nichts, die Kurve des Igelstachelbarts
      las sich dort als Aussage über ihn.
    - **Hier werden die 0,6 MB der Fundorte ausgepackt, in der Liste
      nicht.** Beobachten ist laden; eine bewusst geöffnete Seite darf
      das (wie das „Was ist hier?"-Blatt), ein Reiterwechsel nicht. Ein
      Flow-Test zählt die Aufrufe der Lade-Naht.
    - **`GbifFinds.totalsFor` unterscheidet „0 Meldungen" von „nicht im
      Asset".** Eine Art ohne wissenschaftlichen Namen wird bei GBIF nie
      abgefragt — das ist eine Lücke bei uns, keine bei den Meldern, und
      die Seite sagt es anders. (Heute trägt jede der 91 Arten einen;
      der Zweig ist gemessen unbenutzt und bleibt trotzdem, weil `sci`
      bewusst nullbar ist.)
    - **Ein Weg auf die Karte, nicht zwei.** `showOnlySpecies` SETZT den
      Artenfilter, und der wirkt auf eigene Spots UND die
      GBIF-Scheiben; zwei Knöpfe wären zwei Antworten auf dieselbe
      Frage. Reihenfolge wie in der Spot-Liste: erst der Reiter, dann
      der Filter.
    - **Keine Bestimmungshilfe und keine Fotos** — und ein Satz am Fuß,
      der das sagt. Eine Detailseite weckt die Erwartung, die eine
      Listenzeile nicht weckt.
  - **Essbar oder giftig** (`lib/core/species_edibility.dart`, seit
    1.163.0): eine Stufe je Art, sechs Stufen, dazu Freitext. Vier
    Dinge, die man wissen muss:
    - **Die Fehlerrichtung ist nicht symmetrisch, und der Code richtet
      sich danach.** Ein zu vorsichtiges „ungenießbar" kostet eine
      Mahlzeit, ein zu großzügiges „essbar" eine Leber. Deshalb: im
      Zweifel die Warnung; `Edibility.umstritten` für die Fälle, in
      denen die Literatur uneins ist (die DGfM führt dafür selbst die
      Kategorie „uneinheitlich beurteilte Arten"); **kein Grün und kein
      Häkchen für „Speisepilz"** (`isWarning`) — Grün läse sich als
      Freigabe; und in der LISTE nur die beiden giftigen Stufen
      (`warnsInList`), weil knapper Platz der teuren Fehlerrichtung
      gehört.
    - **Die Tabelle ordnet NAMEN Stufen zu, nicht Pilzen.** Wer sich bei
      der Bestimmung irrt, liest die Einstufung des falschen Pilzes —
      `kEdibilityDisclaimer` sagt das unter jeder Stufe, einmal
      formuliert.
    - **Prüfbar ist nur das Drumherum.** Ob der Grünling giftig ist,
      steht in der Literatur und nicht in Dart. `test/species_edibility_test.dart`
      prüft stattdessen die Pflegefehler: jede bekannte Art hat genau
      einen Eintrag (eine neue Art erzwingt damit eine Entscheidung,
      statt still ohne Einstufung zu erscheinen), keine Karteileichen,
      Zweitnamen erben, `umstritten` trägt immer eine Begründung, und
      die tödlichen stehen als tödlich da.
    - **Der Freitext steht nur, wo die Stufe allein in die Irre
      führt**: tödliche Verwechslungen, Arten, die jahrzehntelang als
      Speisepilz galten, und deutsche Namen, die eine Gattung meinen.
      Eine Bemerkung an jeder Zeile wäre Lärm, in dem die wichtigen
      untergehen.
  - **Verwechslungspartner** (`lib/core/species_lookalikes.dart`, seit
    1.165.0): je Paar ZWEI Einträge, einer je Richtung. Vier Dinge, die
    man wissen muss:
    - **Die Beziehung ist symmetrisch, und ein Test erzwingt das.** Wer
      auf der Seite des Giftpilzes landet, ist oft gerade der, der dort
      nicht hinwollte; eine einseitige Warnung findet nur, wer schon
      weiß, wonach er sucht.
    - **Der Unterscheidungssatz steht je RICHTUNG.** „Der Perlpilz
      rötet" ist beim Perlpilz eine Bestätigung und beim Pantherpilz ein
      Ausschluss. Ein Test verlangt, dass die beiden Sätze eines Paares
      verschieden sind — wortgleich hieße, eine Seite wurde nur kopiert.
    - **Jede Zeile trägt die Einstufung des PARTNERS** und führt auf
      dessen Seite. „Gifthäubling" allein sagt nichts, „Gifthäubling ·
      Tödlich giftig" beantwortet die Frage, wegen der man hinsieht.
    - **Leer heißt „keine bekannt", nicht „keine vorhanden"** — deshalb
      fällt der Abschnitt bei einer Art ohne Partner ganz weg statt als
      leere Überschrift dazustehen, und unter jeder vollen Liste steht,
      dass sie nicht vollständig ist.
    - **Die harmlosen Partner klappen ein, die warnenden nie** (seit
      1.172.0). Drei Bedingungen, jede mit eigenem Grund: Die Art
      selbst darf nicht warnen (auf der Seite eines Giftpilzes sind die
      Speisepilz-Partner der Punkt), es muss überhaupt eine Warnung
      geben (sonst nimmt das Einklappen nur den Inhalt weg — die vier
      Reizker sind genau dieser Fall), und es muss beides geben. Anlass
      war der Steinpilz mit sechs Partnern, bei dem die harmlosen die
      Warnung aus dem ersten Bildschirm drückten. Dieselbe Trennlinie
      wie in `confusionHint`.

    - **Der Einzeiler beim Eintragen nennt nur, was etwas ändern
      kann** (seit 1.171.0). Ist die eingetippte Art selbst harmlos,
      fallen die harmlosen Partner weg. Anlass: Mit der
      Steinpilz-Gruppe bekam der Steinpilz sechs Partner und die Zeile
      158 Zeichen, mit dem Satansröhrling als zweitem von sechs — eine
      Warnung, die man suchen muss. Bei einer Art, die SELBST warnt,
      bleibt alles stehen; dort erklärt der Speisepilz-Partner erst,
      warum jemand sie im Korb hätte. Die volle Liste trägt die
      Artseite.
    - **iNaturalist ist als Fundquelle brauchbar, als Beleg nicht.**
      `identifications/similar_species` liefert, wie oft eine
      Bestimmung von A nach B korrigiert wurde — daraus kamen die
      beiden echten Lücken (Fliegenpilz ohne jeden Partner, Perlpilz
      ohne den Grünen Knollenblätterpilz). Von 197 gemeldeten Paaren
      waren die meisten Rauschen: „Marone ↔ Steinpilz" mit 180
      Korrekturen sind Anfängerfehler zwischen Arten, die sich nicht
      ähneln. Was aus dieser Quelle kommt, wird gegen Literatur
      geprüft, bevor es in die Tabelle geht.

    Geprüft wird außerdem, dass jeder genannte Partner eine bekannte Art
    ist (ein Verweis ins Leere wäre schlimmer als keiner), dass die acht
    tödlichen Paare drinstehen, und dass jede giftige Art mit Partnern
    mindestens einen Speisepilz nennt — sonst erklärt die Warnung nicht,
    warum jemand sie überhaupt im Korb hätte.
  - **Bestimmungsmerkmale** (`lib/core/species_features.dart`, seit
    1.166.0): sechs Felder je Art — Hut, Unterseite, Stiel, Fleisch,
    Geruch, Vorkommen. Vier Dinge, die man wissen muss:
    - **Die Pflichtmenge ist JEDE bekannte Art** (seit 1.169.0).
      Vorher war sie enger — Arten mit Verwechslungspartner plus die
      giftigen —, und sie hat am falschen Ende gemessen: am Giftpilz
      statt am Sammler. Die vier Reizker sind Speisepilze ohne
      eingetragenen Partner und fielen durch beide Siebe; ihre Seite
      sagte über den Pilz kein Wort (Betreiber, 2026-09-22). Betroffen
      waren 30 Arten, fast alle Speisepilze — also durchweg das, was
      jemand wirklich im Korb hat. `test/species_features_test.dart`
      rechnet die Menge nach: eine neue Art OHNE Merkmale macht den
      Lauf rot. Die Pflicht ist teurer, die Alternative war eine
      Detailseite, die über den Pilz schweigt.
    - **Das Raster ist fest, und das ist kein Ordnungssinn.** Wer zwei
      Arten vergleicht, springt zwischen zwei Seiten und liest dieselbe
      Zeile zweimal; Freitext in wechselnder Reihenfolge macht genau das
      unmöglich — und Vergleichen ist der einzige Grund, aus dem jemand
      hier liest. „Trifft nicht zu" wird ausgeschrieben („keine
      Lamellen"), ein leeres Feld sähe aus wie eine Lücke.
    - **Geprüft wird die Pflege, nicht die Mykologie.** Ob der
      Gifthäubling einen glatten Stiel hat, steht in der Literatur. Der
      Test fängt, was beim Pflegen schiefgeht: zu kurze Felder,
      kopierte GESTALT-Zeilen (Hut/Unterseite/Stiel — Geruch und
      Vorkommen dürfen sich wiederholen, weil zwei Pilze eben beide mild
      riechen), zwei Arten mit demselben ganzen Satz. Beim ersten Lauf
      hat er neun echte Schlampigkeiten gefunden.
    - **Reihenfolge auf der Seite: erst die Warnungen, dann die
      Beschreibung.** Wer von oben liest, weiß vor dem ersten Merkmal,
      ob er es mit einem Giftpilz zu tun hat.
  - **Bildpaare** (`lib/core/species_photos.dart` + `assets/species/`,
    seit 1.167.0): elf Fotos von Wikimedia Commons, 700x700 WebP,
    zusammen 0,85 MB. Fünf Dinge, die man wissen muss:
    - **Zwei oder keines.** Ein einzelnes Bild zeigt, wie EINER von
      beiden aussieht, und das genügt zum Verwechseln — erst das Paar
      stellt die Frage. Deshalb steht kein Porträt am Seitenkopf, und
      eine einseitig bebilderte Zeile bleibt bildlos (den Fall gibt es:
      Grüner Knollenblätterpilz ↔ Frauentäubling).
    - **Die Auswahl hat ein Mensch ANGESEHEN.** Ein Werkzeug kann nicht
      beurteilen, ob ein Foto das Merkmal zeigt, das der
      Unterschiedssatz nennt. Zwei Kandidaten sind beim Ansehen
      ausgeschieden, weil sie eine andere Art zeigten als ihr Dateiname
      behauptete (eine nordamerikanische *Amanita*; ein als
      „Weisser Knollenblätterpilz" abgelegter Scheidenstreifling) — auf
      Commons ist die Bestimmung nicht garantiert. Wer ein Bild tauscht,
      sieht es an.
    - **Die Namensnennung steht an ZWEI Stellen**, und beide kommen aus
      derselben Tabelle: als Zeile unter dem Bild und auf der
      Lizenzseite (`speciesPhotoCredits()`). Eine von Hand gepflegte
      zweite Liste wäre die Stelle, an der ein getauschtes Bild seinen
      alten Urheber behält. NC- und ND-Lizenzen sind ausgeschlossen —
      ein Test prüft es, und der Zuschnitt allein verstößt schon gegen
      ND.
    - **`commons.wikimedia.org` ist `textOnly`** im Datenschutz-Wächter:
      Die Bilder liegen im Binary, die Adresse ist Quellenangabe.
      Geholt werden sie von `tool/species_photos.py` — das Werkzeug
      erzeugt die Assets Byte-genau reproduzierbar.
    - **„Zwei oder keines" ist seit 1.176.0 eine FUNKTION**
      (`onlyWithOwn`), keine Bedingung im Widget. Sie hing sonst daran,
      dass es zufällig eine Art ohne eigenes Bild mit bebildertem
      Partner gibt: Dreimal musste der Flow-Test dafür eine neue Art
      bekommen, und nach der zweiten Commons-Tranche gab es keine mehr
      — die Gegenprobe blieb grün, obwohl der Riegel entfernt war. Über
      zwei Listen geprüft ist die Regel unabhängig vom Datenbestand rot
      zu bekommen. Der Riegel bleibt, obwohl der Fall heute nicht
      vorkommt: Ein Bild wird ersetzt, ein Partner kommt dazu, und dann
      zählt er wieder.

    - **Alle Bilder stehen in EINEM Streifen** (seit 1.174.0): links
      die Art selbst, dann eine sichtbare Trennung, rechts ihre
      Verwechslungspartner. Vorher saß das Paar in der
      Verwechslungszeile — und seit die harmlosen Zeilen einklappen
      (1.172.0), konnte es hinter einem Tipp verschwinden. Vier Dinge:
      **Rahmen nur bei Warnung**, der eigene Pilz und ein harmloser
      Partner bekommen den neutralen Rand; Grün gibt es nicht, es läse
      sich als Freigabe. **Die Unterschrift trägt die Aussage**, nicht
      die Farbe — sonst hält jemand beim Überfliegen das
      Pantherpilz-Bild für den Perlpilz; der Screenreader hört
      „Verwechslungspartner" mit. **„Zwei oder keines" gilt weiter**,
      nur an anderer Stelle: `ownPictures` leer heißt kein Streifen,
      auch wenn ein Partner ein Bild hätte. Und **die Kachel wird nach
      dem BILD geschlüsselt, nicht nach der Art** — drei Porträts einer
      Art hätten sonst denselben Schlüssel, und `getTopLeft` bricht bei
      drei Treffern ab.

    - **Die Detailseite braucht einen Schlüssel je Art**
      (`ValueKey(name)` in `router.dart`). Ohne ihn hält Flutter die
      Seite der nächsten Art für dieselbe, verwendet das Element weiter
      — und die `ListView` behält ihre Scrollposition. Wer von einem
      Verwechslungspartner aus weitertippt, landete mitten auf dessen
      Seite statt oben bei Namen und Einstufung. Gefunden hat das ein
      Test, der eigentlich etwas anderes prüfen sollte.
  - **Porträts je Art** (`speciesPortraits`, seit 1.170.0): bis zu
    fünf EIGENE Aufnahmen des Betreibers je Art, waagerecht
    durchblätterbar, für 14 Arten. Fünf Dinge, die man wissen muss:
    - **Das ist etwas anderes als das Bildpaar, und beide bleiben.**
      Beim Paar gilt „zwei oder keines", weil ein einzelnes Bild eine
      Verwechslung nicht auflöst. Das Porträt beantwortet die andere
      Frage — wie die Art überhaupt aussieht —, und dafür ist ein Bild
      zu wenig: Farbe und Form ändern sich mit Alter und Wetter
      (Betreiber, 2026-09-22: „wir können auch 2-3 Bilder je nehmen").
      Ein Test hält die Spanne fest, seit 2026-10-02 1 bis 5
      (`kMaxPortraits`, Betreiber; vorher 1 bis 3).
    - **Eigene Fundbilder schlagen Lehrbuchbilder**, und das ist
      gemessen, nicht behauptet: Das Reizker-Foto des Betreibers trug
      die Stielgrübchen, die unsere Merkmalstabelle dem Edelreizker
      ALLEIN zuschrieb — die Zeile war zu absolut und ist in 1.169.0
      berichtigt worden. Ein Commons-Bild hätte den Fehler bestätigt,
      weil dort die Lehrbuchform abgelegt wird.
    - **Der Hinweis darunter steht EINMAL je Seite** und hängt an
      „zeigt diese Seite irgendein Bild", nicht an „gibt es Porträts" —
      sonst stünde unter den Vergleichspaaren nichts. Die beiden
      tragenden Sätze (`kPhotoDisclaimer`) stehen AUSSERHALB des
      Ausklappers; eingeklappt wird nur die Begründung. Eine
      eingeklappte Warnung ist Deko.
    - **Die Lizenzseite liest EINE Naht** (`allSpeciesPhotos()`).
      Vorher kannte `speciesPhotoCredits` nur die Paar-Tabelle; eine
      zweite Bildquelle wäre dort stillschweigend unerwähnt geblieben,
      und ein nicht genanntes CC-BY-Bild ist ein Lizenzverstoß. Die
      Gegenprobe dazu ist gemessen.
    - **Die Detailseite hat seither ZWEI Scrollables**, und die
      senkrechte trägt deshalb `kSpeciesDetailListKey`. Ein Test, der
      „das Scrollable dieser Seite" sucht, fand zwei und scheiterte im
      Zug; `descendant` trifft dabei auch das innere, es braucht
      ausdrücklich das erste. Dieselbe Falle wie beim Suchfeld (#516).
      Und eine negative Aussage über die Seite braucht einen ANKER:
      Nach `scrollUntilVisible` steht das Ziel am oberen Rand, alles
      darüber ist nicht gebaut, und `findsNothing` ist dann grün, egal
      was dort stünde. In der Gegenprobe genau so passiert.

  - **Bilder antippen und groß ansehen** (#537, seit 1.179.0): Die
    großen Fassungen (1200x1200, 78 Dateien, 15,9 MB) liegen NICHT im
    APK, sondern auf dem Branch `species-photos`. Fünf Dinge:
    - **Ein Branch, kein Release-Anhang**, aus demselben Grund wie beim
      Regengitter: Release-Anhänge tragen kein
      `access-control-allow-origin`, der Web-Build bekäme still nichts.
      Nachgemessen am 2026-09-22: `raw.githubusercontent.com` liefert
      `*`. Ein Wurzel-Commit, force gepusht — jedes Commons-Bild ist
      ein Platzhalter, wird also ersetzt, und sonst wüchse die Historie
      je Tausch um die volle Bildgröße.
    - **Kein neues Netzziel**, der Host steht schon in der
      Datenschutzerklärung.
    - **Der Tipp vergrößert IMMER**, auch ohne Empfang: erst das
      mitgelieferte 400er, das große ersetzt es, sobald es da ist. Erst
      laden und dann zeigen wäre ein Versprechen, das im Wald nicht
      hält.
    - **Die Lupe an der Kachel löst nichts aus** — „beobachten ist
      laden", geholt wird erst beim Antippen. Ein Test zählt die
      Abrufe.
    - **Jedes Bild braucht seine große Fassung** (#588): `ci.yml`
      bricht ab, wenn ein `assets/species/*.webp` keine auf dem Branch
      hat (`tool/species_photos.py --check-large`). Mit #541 kamen 34
      ohne — die Vergrößerung zeigte still das 400er. `--large` baut sie
      aus dem Commons-Original mit demselben Ausschnitt (SSIM-geprüft);
      kleinere Originale liegen in ihrer Größe da, nie hochgerechnet.
    - **Eine GRÖSSENgrenze, keine Frist** (24 MB, älteste Ansicht
      fliegt zuerst). Das unterscheidet diesen Speicher von
      `spot_cache/`, `outbox/` und `tours/`: Ein Bild ist jederzeit
      nachladbar, deren Inhalt nicht. Im Browser gibt es keinen eigenen
      Speicher — der HTTP-Cache und der Service Worker tun es schon.

  - **Eine neue Art durch die ganze Kette** (Schönfußröhrling, 1.167.0,
    als Muster): `kBekannteArten` mit akzeptiertem GBIF-Namen →
    `tool/season_curves.py --out` (Netz, dabei die Zahl der
    Art-Monate messen, die an `kSeasonNowThreshold` kippen) →
    `tool/gbif_finds.py build` (lokale DB) → `tool/generated_assets.py
    --update` → Einstufung, Paare, Merkmale. Die Tests verlangen jeden
    Schritt: ohne Einstufung rot, mit Paar ohne Merkmale rot, und
    `_Reported` sagte ohne neu gebautes Fundorte-Asset „lässt sich nicht
    laden" über eine Art, die schlicht nicht drin war.
  - **Die Warnung dort, wo der Pilz ist** (seit 1.168.0; Betreiber-
    Durchsicht 2026-09-22: „haben wir was Essenzielles vergessen?" —
    ja, genau das). Bis dahin führte von KEINER anderen Stelle der App
    ein Weg zur Artseite; Einstufung und Partner waren ein
    Nachschlagewerk, das man aufsuchen musste. Drei Dinge:
    - **Eingabefeld** (`species_field.dart`): `confusionHint` unter dem
      Feld, sobald die Vorschlagskarte zu ist — dieselbe Bedingung wie
      das Symbol, denn ein voller Name mit mehreren Treffern
      („Steinpilz") ist noch keine Entscheidung. Bewusst OHNE Verweis:
      Das Blatt ist ein Formular, ein Wechsel würde die Eingabe
      verwerfen. Die Einstufung des Partners steht nur dabei, wenn sie
      warnt (Asymmetrie).
    - **Spot-Blatt**: ein `ActionChip` je bekannter Art des Spots
      (`scanSpeciesOf` → `knownSpeciesFor`, Freitext-Arten haben keine
      Seite). Der Router wird VOR `pop()` gegriffen — danach ist der
      Kontext des Blatts nicht mehr eingehängt.
    - **Rückkanal**: „Hinweis zu dieser Art melden" am Fuß der Artseite,
      als `FeedbackType.bug` mit dem Artnamen im Text — der Bot macht
      daraus ein Bug-Issue. Handgepflegte Tabellen, an denen eine
      Vergiftung hängen kann, brauchen den Weg dort, wo man den Fehler
      sieht.

