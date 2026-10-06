# PilzBuddy — Arbeitsregeln für `lib/features/coach/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Erklär-Tour und Kontexthilfe** (#350, seit 1.107.0/1.108.0): Zwei
  Bausteine, bewusst getrennt. **A** ist Kontexthilfe ohne jede
  Maschinerie — leerer Kartenzustand, Leergang-Erklärung am frischen
  Spot, `lib/features/help/help_screen.dart` als Kurzanleitung mit den
  ECHTEN Symbolen (kein `.md`-Asset: das läge im Binary, gälte dem
  Version Guard aber als `*.md` und wäre damit von der Bump-Pflicht
  ausgenommen — dieselbe Falle wie bei `CHANGELOG.md`). **B** ist die
  geführte Tour (`lib/features/help/map_tour.dart`), seit 1.205.0 ein
  Skript auf der **Hinweis-Maschine** (`lib/features/coach/coach.dart`,
  #596). Die erste Fassung schnitt vergrößerte runde Löcher je Knopf —
  seit die Werkzeuge in EINER Leiste sitzen, griffen die in den
  Nachbarknopf, und sie zeigte nur, WO etwas ist (PWA-Screenshots des
  Betreibers, 2026-09-24). Jetzt FÜHRT sie vor: Der lange Druck öffnet
  das Kontextmenü, die Ebenen öffnen ihr Blatt („wichtig ist mir, dass
  das Kontextmenü gezeigt wird, nicht nur der erste Button"). Sechs
  Dinge, die man wissen muss:
  - **Die Maschine liegt über allem** (`MaterialApp.builder`), also über
    Dialogen und Blättern, und schluckt jeden Tipp — eine Vorführung
    löst nie etwas aus. Deshalb meldet sie sich beim **Zurück-Verteiler
    des Routers** mit Vorrang an, solange sie läuft (sonst verließe
    Zurück auf der Karte die App), und danach wieder ab (sonst sperrte
    sie ein). Beide Richtungen stehen im Flow-Test.
  - **Anker und Szenen haben Kennungen** (`MapCoach`). `CoachAnchor`
    meldet ein Widget an, der Screen meldet Szenen an (Menü, Blatt), und
    eine Szene gibt ihren Schließer zurück. Die Maschine schließt beim
    Szenenwechsel und am Ende immer; das Menü meldet dabei `null`, also
    keine Aktion. Die Szenen rufen `showMapContextMenu`/
    `showMapLayersSheet` DIREKT, nicht `_openContextMenu`/`_openLayers`,
    die das Ergebnis auswerten würden.
  - **Gemessen wird über die ganze Transformation** (`getTransformTo`)
    und bei jedem Bild — die Leiste steckt in einem `FittedBox`, ein
    Blatt fährt animiert herein. **Im Karten-Test wird die Leiste nie
    verkleinert** (auch bei 360×560 nachgemessen: 44×44), deshalb steht
    die Zusage in `test/coach_test.dart` mit einem `Transform.scale`.
  - **Aussparung in Form des Elements, Ring auf dem gemeinten.** Bei der
    Leiste ist sie ganz ausgespart, der Ring sitzt auf dem Knopf; im
    ersten Schritt nur um „Neuer Spot", sonst wäre er ein Kasten von der
    Bildmitte bis in die Ecke. Fehlt ein Ziel ~2 s lang (Menü an der
    Tour vorbei geschlossen), geht es weiter statt ins Leere.
  - **`FakeSettings.mapTourSeen` steht auf `true`, die App auf `false`.**
    Andersherum bekäme jeder Bestandstest die Tour übergestülpt — in der
    Gegenprobe gemessen: 13 Tests brechen. Muster wie `lastFindSeenAt`.
  - **Überspringen und Zurück zählen wie Durchsehen.** Gemerkt wird über
    den Notifier von `mapTourSeenProvider`, nicht über den `ref` des
    Aufrufers — aus der Kurzanleitung gestartet, ist der beim Ende
    vielleicht schon abgebaut.
  Der Merker ist gerätelokal (Betreiber, 2026-08-29); nach einer
  Neuinstallation läuft sie wieder, und das ist angenommen.
  **Zurückgesetzt für alle in 1.208.0** (Betreiber, 2026-09-25): neue
  Schlüssel für Karten-Tour (`map_tour_seen_2`), Reiter-Touren,
  Neuheiten-Stand und „Neu"-Punkte. Der alte Tour-Merker wird weiter
  GELESEN (`legacyMapTourSeen`), aber nur für die Rückblick-Erkennung —
  sonst hielte die App nach dem Zurücksetzen jeden für eine
  Neuinstallation, und der Rückblick fiele weg (Flow-Test mit
  Gegenprobe). Wer wieder zurücksetzt: dieselbe Trennung, und
  `LAST_RESET` in `tool/highlights_preview.py` nachziehen — aber NUR,
  wenn auch der Neuheiten-Stand zurückgesetzt wird.
  **Noch einmal in 1.210.1, nur die Touren** (Betreiber, 2026-09-25,
  nach Startseiten und Beispielen): `map_tour_seen_3`,
  `seen_coach_tours_3`. Neuheiten-Stand und „Neu"-Punkte bleiben, also
  bleibt auch `LAST_RESET`. `legacyMapTourSeen` liest seither ALLE
  früheren Tour-Schlüssel (`_legacyMapTourSeenKeys`) — beim nächsten
  Mal kommt der dann alte dazu, sonst hieße ein Nutzer von 1.208 bis
  1.210 „Willkommen" (`test/settings_tour_reset_test.dart`).
  **Startseiten, Willkommen und die Kette** (seit 1.209.0, Betreiber
  2026-09-25: „man öffnet die App und es geht sofort los"). Jede Tour
  beginnt mit einer Startseite (`CoachStep.art`, Bilder in
  `tour_intro_art.dart`): Bild, WOZU, dann die Wahl. Beim ersten Start
  ist es die Willkommensseite, danach die Karten-Tour mit einem Schritt
  zur Leiste unten, danach fragt JEDE Grenze „Weiter mit den Spots?"
  (`startWelcomeTour`). Sechs Dinge, die man wissen muss:
  - **„Nicht jetzt"/„Später" ist kein Gesehen** (`CoachNotifier.decline`,
    `onDecline`): Die Tour fragt beim nächsten Start wieder, JEDES Mal
    (Betreiber); in derselben Sitzung nicht bei jedem Reiterwechsel
    (`declinedTabToursProvider`, nur im Speicher). Zurück auf der
    Startseite heißt „Nicht jetzt", ein Tipp daneben tut nichts.
  - **Die Willkommens-Tour hat keinen Weg in die Kurzanleitung am Ende**
    — sonst liefe die Kette gleichzeitig in den nächsten Reiter.
  - **Bestandsnutzer sehen nicht „Willkommen"** (`kReturningIntro`, über
    `legacyMapTourSeen`) — nach dem Zurücksetzen in 1.208.0 wäre das
    falsch.
  - **Tippsperre, 400 ms nach jedem neuen Schritt** (`_guarded`, Zeit des
    Takts, nicht der Uhr — im Test wäre `DateTime.now` echt). Feldmeldung
    „scheint einen Schritt direkt zu überspringen": Die neue Blase steht
    woanders, ein nachwackelnder Finger traf ihr „Weiter". Tests müssen
    deshalb nach dem Erscheinen eines Schritts einen Moment warten.
  - **Ein fehlendes Ziel wird gesagt, nicht übersprungen** — bis 1.208.x
    ging die Tour nach ~2 s still weiter, auf einem langsameren Gerät
    sah das wie ein übersprungener Schritt aus.
  - **Auf der Startseite scrollt nur der Inhalt**, die Wahl bleibt immer
    im Bild, und das Bild schrumpft mit dem Schirm — auf einem kurzen
    Schirm lag „Tour starten" sonst unter dem Rand (im Test gesehen).
  Zähler und „Los geht's" zählen die Startseite nicht mit; Vorführungen
  übernehmen Schritte über `tourSteps` (ohne Startseite).

  **Beispiele für leere Konten** (seit 1.210.0, `tour_examples.dart`,
  Betreiber: „er sollte ja dennoch einen Eindruck bekommen"). Ohne Spot
  erklärte die Spot-Tour bis dahin nur das Suchfeld — über die Kette lief
  sie auch ohne Inhalt. Jetzt zeigen Spots und Buddys während ihrer Tour
  eine Beispielzeile, ein Beispiel-Blatt, einen Beispiel-Buddy und eine
  Beispiel-Galerie. Drei Regeln:
  - **Gezeichnet, nie gespeichert** — keine `Spot`-, `Find`- oder
    `Friendship`-Objekte, kein Provider, kein Cache. Als Modell käme ein
    Beispiel-Fund in Statistik, Ampel und GPX-Export an.
  - **Immer „Beispiel"** (`TourExampleBadge`), auch für den
    Bildschirmleser.
  - **Nur während der Tour und nur, wo Echtes fehlt**
    (`CoachScript.examples` → `coachExamplesProvider`). Die Anker sind
    dieselben wie an der echten Zeile. `examples` gehört nur an Skripte
    MIT Startseite: Die Beispiele erscheinen ein Bild nach dem Start, und
    ein erster Schritt mit `requires` fiele sonst sofort weg.
  Die Spot-Tour wartet deshalb nicht mehr auf einen Spot (`ready`); der
  Wächter gegen „Tour fällt über die Karte" ist davon unberührt und hat
  seinen Test behalten.

  **Kurze Touren je Reiter** (seit 1.206.0, `lib/features/help/tab_tours.dart`):
  Spots, Pilze und Buddys, auf derselben Maschine, beim ERSTEN Besuch
  des Reiters. Vier Dinge, die man wissen muss:
  - **Sie startet nur, wenn der Reiter SICHTBAR ist** (`TickerMode`, den
    go_router für verdeckte Reiter abschaltet). Die Reiter bleiben nach
    dem ersten Besuch im Baum, und die Spot-Liste lädt gern nach, während
    man auf der Karte ist — dann fiele die Tour über die Karte. Ein
    Flow-Test hält es fest, die Gegenprobe ist gemessen.
  - **Sie wartet auf Inhalt** (`ready`): ohne Spot keine Spot-Tour, und
    sie bleibt dann ungesehen. Einzelne Schritte an Dingen, die nicht
    jeder hat, tragen `requires` und fallen sofort weg — ein Anker ohne
    Fläche (`SizedBox.shrink`) zählt als fehlend.
  - **Schritttitel dürfen nicht wie etwas auf dem Schirm heißen.** „Buddy
    finden" ist das Suchfeld; mit dem gleichen Titel prüfte der Test das
    Feld statt der Blase. Zum zweiten Mal passiert (vorher „Was ist hier?").
  - **Die Blase wird erst gemessen, dann gesetzt** (`_BubbleLayout`):
    neben ihr Ziel, bei einem hohen schmalen Ziel (die Leiste auf
    360×640) DANEBEN, und ragt sie trotzdem hinaus, wird sie ins Bild
    geschoben — dann ohne Pfeil. Bis 1.205.0 lag sie im Leisten-Schritt
    bei y = −27 und auf der Artseite unten außerhalb, „Weiter" war nicht
    zu erreichen. Der Test prüfte nur „deckt nichts zu", und das tut eine
    Blase außerhalb nie; seither prüft jeder Tour-Test, dass sie ganz im
    Bild liegt. Eine Regel VOR dem Messen („zu wenig Platz ⇒ an den
    Rand") war der erste Versuch und schob sie auch dann aufs Ziel, wenn
    sie gepasst hätte.
  Gemerkt wird in `seenCoachTours` (die Karten-Tour behält
  `mapTourSeen`); `FakeSettings` setzt ab Werk alle, Muster wie bei der
  Karten-Tour.
  **Die Hand** (`FingerPainter`, seit 1.206.0) ist gezeichnet: Zeigefinger
  mit Nagel, eingerollte Finger, Daumen, grüner Ärmel. **Von hinten nach
  vorn gemalt, jedes Teil mit eigener Kontur**, die Handfläche zuletzt
  und ohne Kontur (sie deckt die Fingerenden zu), den Außenrand zieht der
  Umriss aller Teile. Der erste Ansatz — ein Umriss mit eingeritzten
  Trennlinien — zeichnete verdeckte Linien, und der Daumen sah erst
  gebrochen, dann aufgeklebt aus (Betreiber mit Zeige-Icon als Vorlage,
  2026-09-25). Wer die Form ändert: groß rendern und ANSEHEN. Der Ablauf steht
  rein in `FingerMotion` (herankommen, drücken, abheben; beim Wischen von
  rechts nach links), damit ein Test ohne Pixel prüfen kann, dass AUF dem
  Ziel gedrückt wird.
  Nebenbefund aus #350: Der einzige Erklärsatz, den die App davor hatte
  (im Profil, „halte auf der Karte gedrückt"), wies auf eine Geste, die
  seit #210 abschaltbar war und **ab Werk aus** stand. Seit #483 stimmt
  der Satz wieder — er steht jetzt in der Kurzanleitung.

