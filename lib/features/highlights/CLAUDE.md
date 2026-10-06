# PilzBuddy — Arbeitsregeln für `lib/features/highlights/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Neuheiten und „Entdecken"** (#596, seit 1.204.0,
  `lib/features/highlights/`): EINE Liste (`kFeatureHighlights`), zwei
  Anzeigen — das Blatt nach einem Update (höchstens drei Highlights
  untereinander, jüngste zuerst) und die Seite „Entdecken" (alles,
  auch die Tipps).
  Die Tour bleibt daneben und hat eine andere Aufgabe: Das Blatt sagt,
  WAS es gibt, die Tour zeigt, WO es ist. Fünf Dinge, die man wissen
  muss:
  - **Wer eine Funktion baut, bringt ihren Eintrag im selben PR mit** —
    Highlight, wenn sie ins Blatt gehört, sonst Tipp. Verankert an drei
    Stellen (seit 1.208.0), weil „steht in CLAUDE.md" allein nicht
    trägt: die PR-Vorlage (`.github/pull_request_template.md`, erster
    Haken), die Vorschau in der Run-Summary von `promote.yml`
    (`tool/highlights_preview.py`: was das Blatt nach dem Update zeigt,
    Warnung bei keinem Highlight — kein Tor, manche Stände bringen ehrlich
    nur Korrekturen) und der Skill `pilz-release` für den Ablauf der
    Beförderung. Die Vorschau kennt den Rückblick: Wer von einem Stand vor
    1.204.0 kommt, hat keinen Merker und bekommt ihn — dort ist „kein neues
    Highlight" kein Befund. Kuratiert wird
    nicht bei der Beförderung: Stehen mehr als drei an, zeigt das Blatt
    die jüngsten, der Rest wartet in „Entdecken".
    `test/feature_highlights_test.dart` prüft Kennungen, `since` gegen
    `pubspec.yaml` und die Textlänge, der Flow-Test, dass jedes Ziel
    eine Route ist.
  - **Rückwirkend geht es nur über `mapTourSeen`.** Vor 1.204.0 hat kein
    Gerät seine Version gemerkt (`highlightsSeenVersion` ist dort
    `null`). Tour gesehen ⇒ Bestandsnutzer ⇒ einmal der Rückblick, mit
    `kRecapLead` an der Spitze (dort wäre „die jüngsten" die falsche
    Regel). Tour nicht gesehen ⇒ frisch installiert ⇒ Version merken,
    nichts zeigen. **Gemerkt wird schon beim ERSTEN Start**, auch wenn
    Haftungshinweis oder Tour laufen — sonst hielte sich eine frische
    Installation nach der Tour für einen Bestandsnutzer. Nur ZEIGEN
    wartet dann auf einen ruhigen Start (keins der beiden, keine
    laufende Pilztour).
  - **Gemerkt wird VOR dem Zeigen**, und nie ein älterer Stand über
    einen jüngeren (Rückschritt vom Vorabkanal). Ein weggewischtes
    Blatt kommt nicht wieder; verpasst ist nichts, „Entdecken" hat es.
    **Das Blatt ist EINE Seite, alle Einträge untereinander** (seit
    1.204.1, Muster der „Neu in …"-Seiten). 1.204.0 blätterte mit
    „Ausprobieren" je Seite, und wer mittendrin antippte, verlor den
    Rest — im Feld gemeldet. Eine „Weiter ansehen"-Leiste am Ziel war
    gebaut und ist verworfen: Sie flickte einen Fall, den der übliche
    Aufbau gar nicht erst hat. Wer das Blatt wieder zum Blättern macht,
    muss „gesehen" je angezeigter Seite merken, nicht beim Öffnen.
  - **Eine Zeile im Blatt führt es VOR** (seit 1.208.0): Sie startet die
    Vorführung aus `highlight_demos.dart`, die selbst an die Stelle
    wechselt. Ohne Vorführung bleibt es beim Sprung.
  - **„Animationen entfernen" und Bildschirmleser** (seit 1.208.0): Ring
    und Hand stehen dann still (`gestureStillFrame`, dasselbe Bild wie in
    „Entdecken"), der Pilz im Bild schaukelt nicht. Während einer Tour
    blendet `CoachSemanticsGate` (in `app.dart` um den Inhalt UNTER der
    Überlagerung) alles darunter für TalkBack aus — dort nimmt ohnehin
    nichts einen Tipp an —, und die Blase ist eine `liveRegion`, ein
    neuer Schritt wird also angesagt. `BlockSemantics` in der Überlagerung
    reichte nicht, es wirkt nicht über die Grenze zum Navigator. Im Test
    `find.semantics.byLabel`, nicht `find.bySemanticsLabel`: Letzteres
    findet auch ausgeblendete Knoten.
  - **Bilder aus Widgets** (`HighlightArt`: das echte Knopfsymbol plus
    ein schaukelnder Pilz-Buddy), keine Screenshots — die veralten mit
    jeder Oberflächenänderung —, kein Lottie.
  - **„Zeig es mir" (seit 1.207.0, `highlight_demos.dart`)**: je Eintrag
    eine Vorführung auf der Hinweis-Maschine, und sie endet IN der
    Funktion (Blatt, Menü, Dialog, Seite). **Wer einen Eintrag anlegt,
    bringt seine Vorführung mit** — `highlight_demos_flow_test.dart`
    verlangt eine je Kennung und fährt JEDE aus „Entdecken" durch: jeder
    gezeigte Schritt findet sein Ziel, die Blase liegt im Bild, danach
    ist nichts offen. Was dafür in die Maschine kam:
    - **Szenen schachteln** (`a/b`): Der Meldedialog liegt AUF der
      Artseite; die äußere bleibt offen, geschlossen wird von innen.
    - **Szenen dürfen sich spät anmelden** (`retryScenes`, je Bild) —
      ihr Besitzer entsteht oft erst, wenn die äußere steht.
    - **`scrollIn`**: Ziele weit unten in einer `ListView` (Ampel-
      Schalter im Profil, Meldeknopf der Artseite) sind nicht gebaut,
      bis man hinscrollt; die Maschine scrollt die genannte Liste weiter,
      bis der Anker da ist.
    - **`unless`** als Gegenstück zu `requires`: der Ersatzschritt
      („erst einen Buddy finden"). Zähler und „Los geht's" rechnen über
      die Schritte, die WIRKLICH laufen.
    - **`reserve`**: Zwischen Tipp und Start (drei Bilder, damit der
      Zielreiter seine Anker meldet) ist die Maschine belegt, und die
      Reiter-Tour weicht für den Rest dieses Besuchs.
    Eine Falle beim Bau: Ein Dialog-`builder`, der über `ref` liest,
    baut beim Schließen noch einmal — schließt die Vorführung erst den
    Dialog und dann die Seite darunter, ist dieses `ref` schon tot. Werte
    vor `showDialog` lesen.
  - **`FakeSettings.highlightsSeenVersion` steht auf `9999.0.0`**, die
    App auf `null`. Andersherum bekäme jeder Bestandstest das Blatt über
    die Karte gelegt; Muster wie `mapTourSeen`.

