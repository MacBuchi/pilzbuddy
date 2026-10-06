# PilzBuddy — Arbeitsregeln für `lib/features/tour/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Die Pilztour macht aus einem Weg die Leergänge, die niemand
  einträgt** (#338, seit 1.102.0): GPS-Aufzeichnung auf Knopfdruck
  (`lib/features/tour/`), Punktspur auf der Karte, und beim Beenden ein
  Blatt, das je eigenem Spot vorschlägt, ob dort „nichts gefunden"
  gebucht wird. Sechs Dinge, die man wissen muss:
  - **Die Fehlerrichtung ist vorgegeben, überall.** Ein übersehener
    Leergang kostet eine Zeile; ein ERFUNDENER vergiftet die Stichprobe,
    die #199 als unabhängigen Prüfstein für die Ampel aufhebt. Wo
    `tour_track.dart` zwischen „lieber zu wenig" und „lieber zu viel"
    wählen muss, wählt sie zu wenig — ein Zeitabschnitt zählt nur, wenn
    BEIDE Enden im Radius liegen und BEIDE Fixes scharf genug sind.
  - **Ein Radius, ein Faktor — keine zweite Zahl.**
    `kNearbySpotMeters` (20 m, #215) bleibt die eine Antwort auf
    „derselbe Ort"; das Vorbeigeh-Band ist `kTourPassByFactor` × davon
    (Betreiber, 2026-08-27). Die Verweildauer ist die einzige
    unterscheidende Achse: Der Radius sagt, wo man war, die Uhr sagt, ob
    man hingesehen hat.
  - **Die Genauigkeit je Fix wird MITGEFÜHRT und entscheidet.** Unter
    Blätterdach liegt GPS 10–20 m daneben; ein 20-m-Radius gegen einen
    ±40-m-Fix ist Rauschen im Gewand einer Messung. Unscharfe Punkte
    zählen keine Verweildauer, gehen aber weiter in die kürzeste
    Entfernung ein — sonst verschwände ein wirklich abgesuchter Spot ganz
    aus dem Blatt.
  - **Das Blatt zeigt die Bewertung, statt sie zu verstecken.** Erfüllt
    ⇒ hervorgehoben und angehakt; gestreift ⇒ verblasst, aus, mit Grund
    und Zahl. Eine Liste, in der alles vorangekreuzt ist, wäre ein
    Anstupser, Leergänge zu buchen, die nie verdient wurden. Ein Fund
    von HEUTE am selben Spot sperrt den Leergang doppelt — in der
    Anzeige und im Buchen; die zweite Sperre trägt wirklich, weil ein
    abgesuchter Spot in `_checked` auf true steht.
  - **Foreground-Service vom Typ `location`, NICHT
    `ACCESS_BACKGROUND_LOCATION`.** Die Aufnahme startet im Vordergrund
    und trägt eine Dauerbenachrichtigung — die IST die Offenlegung. Der
    ganze Abschnitt „Prominent Disclosure: nicht erforderlich" in
    `docs/play-console.md` hängt daran, und ein Test hält beide Hälften
    fest. Der Manifest-Typ ist `dataSync|location` als OBERMENGE; welche
    Typen ein Lauf beansprucht, entscheidet `startService`. **Ändert
    sich die Typmenge, startet der Koordinator den Service NEU** —
    `updateService` kann Typen nicht ändern (nachgesehen in
    flutter_foreground_task 10.0.0).
  - **Gemessen wird im ISOLATE DES SERVICE, nicht im Main-Isolate**
    (#342, korrigiert in 1.103.0). Die erste Fassung nahm einen
    `Timer.periodic` in der App — richtig, solange die App lebt, und
    genau das war der Fehler: Wischt der Nutzer sie aus der Übersicht,
    stirbt der Flutter-Prozess samt aller Timer, während der Service
    sichtbar weiterläuft (`START_STICKY`, kein `stopWithTask`). Im Feld
    am 2026-08-27 so gesehen. `flutter_foreground_task` startet für den
    Service ein eigenes Flutter-Isolate; dort steht jetzt
    `recordTourTick`. Drei Folgen:
    - **Der Service hat genau EINEN Einstiegspunkt**, also trägt ein
      Handler beide Nutzer: Für einen Download tut er nichts, für eine
      Tour misst er. Was gilt, steht in der Brücke
      (`kTourDataActive` über `FlutterForegroundTask.saveData`, also
      SharedPreferences — sie ist in beiden Isolaten lesbar).
    - **Der Takt lässt sich am laufenden Service ändern**
      (`updateService` nimmt `foregroundTaskOptions`), die Service-TYPEN
      dagegen nicht. Deshalb `setRepeat` ohne Neustart und ein Neustart
      bei Typwechsel.
    - **Im Isolate gibt es kein Riverpod, keine Widgets und keinen
      `ErrorSink`.** Der Verzeichnispfad wird einmal drüben aufgelöst
      und über die Brücke gereicht; `recordTourTick` fängt alles, weil
      eine durchgereichte Ausnahme dort niemanden hat, der sie fängt —
      und die Tour für den Rest des Wegs still beenden würde.
    - **Die Rückrichtung muss in `main()` ANGEMELDET werden** (#465,
      behoben in 1.143.1). `sendDataToMain` schlägt seinen Port über
      `IsolateNameServer.lookupPortByName` nach, und angelegt wird der
      ausschließlich von `FlutterForegroundTask.initCommunicationPort()`
      — das Paket ruft es nie von selbst, es steht als Zeile für `main()`
      in dessen README. Sie hat von #342 an gefehlt: Jeder Takt landete
      korrekt in der Datei und die Meldung im Nichts, weil
      `sendPort?.send(data)` auf `null` still durchfällt. Vier Wochen
      unbemerkt, und zwar weil `_firstFix` noch im Main-Isolate
      `acceptTick` ruft — die Karte hatte damit GENAU EINEN Punkt: als
      Punkt ein Pünktchen unterm Fadenkreuz, das nach „läuft" aussieht,
      als Linie gar nichts (`tourTrackPolyline` braucht zwei). Gemeldet
      wurde deshalb „die Linie geht nicht", kaputt war die Anzeige
      insgesamt. Verloren ging nie etwas; ein Neustart holte den Weg
      über `restore()` zurück, und genau das war beim Nachstellen der
      entscheidende Kontrollversuch. `test/tour_live_bridge_test.dart`
      prüft Rundlauf, Gegenprobe UND die Zeile in `main.dart` — die
      ersten beiden allein leuchten grün, während die App steht.
    Ebenfalls gefallen: das `timeLimit` von 20 s auf dem Fix. Es machte
    aus jedem langsamen Hintergrund-Fix stillschweigend gar keinen.
  - **Der Track liegt in `tours/` als JSON Lines** und wird beim Gehen
    angehängt, nicht am Ende geschrieben: Der Prozess-Kill ist hier der
    Normalfall (#147). Ein Abbruch kostet damit höchstens die letzte
    Zeile; beim Ausgangskorb wäre derselbe Abbruch eine halbe Datei,
    deshalb steht dort `.part` + `rename`. `tours/` gehört in beide
    Backup-Ausschlüsse — ein Bewegungsprofil hat in Googles Cloud so
    wenig verloren wie die Fundstellen. Gelöscht wird **erst nach dem
    Blatt**: Wer vorher aufräumt, verliert drei Stunden Gehen, wenn das
    Blatt weggewischt wird.
  - **Die Spur verlässt das Gerät seit 1.147.0 doch** (#340 Stufe 2) —
    aber nur, wenn BEIDES läuft: eine Tour UND die Standort-Freigabe.
    Die Bedingung ist ein UND und steht als eine Zeile in
    `planTrackShare` (`tour_sharing.dart`); wer aufzeichnet, ohne zu
    teilen, behält Stufe 1 unverändert. `expires_at` wird aus der
    Freigabe GEERBT statt neu eingeholt: eine Zustimmung statt zwei, und
    zwei Fristen könnten auseinanderlaufen. Tour- oder Teilen-Ende
    löscht die Zeile sofort — nicht erst beim Ablauf, sonst läge dort
    eine Freigabe, die niemand mehr gibt.
    **Eine Zeile je Nutzer, ersetzt statt angehängt** (`tour_tracks`,
    Patch 023, Policies als Spiegel von `live_locations`): Eine Zeile je
    Messpunkt wären ~720 je Person und Drei-Stunden-Tour — die erste
    Tabelle, deren Größe mit der verbrachten ZEIT wächst statt mit den
    Funden. Gedünnt sind es ≤ 400 Punkte, rund 10 KB.
    **Hochgeladen wird im MAIN-Isolate**, gemessen wird im Service-Isolate
    (#342). Die Folge ist benennbar: Wer die App wegwischt, zeichnet
    weiter auf, lädt aber nichts mehr hoch, bis er sie öffnet. Verloren
    geht nichts, weil immer die GANZE Spur geschrieben wird — deshalb
    braucht der Weg auch keinen Ausgangskorb.
    **Die Spur eines Buddys darf die eigenen Leergänge NIE beeinflussen.**
    Boden, den jemand anders gegangen ist, ist kein Boden, den ICH
    abgesucht habe; `tourVisits` sieht weiterhin nur eigene Punkte. Das
    ist die Stichprobe, die #199 als unabhängigen Prüfstein aufhebt.
    Die vier Stellen, an denen die alte Zusage stand, sind im selben PR
    mitgezogen: `web/datenschutz.html`, `docs/play-console.md`,
    `docs/datenschutz-nachweise.md` und dieser Abschnitt.
  - **Die Anzeige (1.148.0) hat kein eigenes Tor.** `friendTracksProvider`
    hängt am ERGEBNIS von `friendLocationsProvider`: Eine Spur gibt es
    nur, wo ein geteilter Standort ist, also spart man sich den Poll,
    wenn niemand teilt — statt dessen drei Tore (Freundschaft,
    Vordergrund, träger Takt) zu kopieren. `select` auf „teilt überhaupt
    jemand", nicht auf die Liste: Der Standort-Strom liefert alle paar
    Sekunden neu und baute die Schleife sonst jedes Mal neu auf.
    Der Takt ist der des SENDERS (`kTrackUploadInterval`) — häufiger zu
    fragen, als geschrieben wird, holt dieselben Punkte noch einmal.
    Im Test ist der Provider wie `friendLocationsProvider` auf einen
    Einmal-Abruf überschrieben (`test/fakes/test_app.dart`), sonst
    hinge nach jedem Widget-Test ein Timer.
    **Die Farbe je Buddy kommt aus der Spanne, nicht aus einem
    Sonderfall**: 190°…429°, umgebrochen also [190°,359°] ∪ [0°,69°] —
    `forestGreen` (~123°) liegt außerhalb. Ein erster Entwurf hatte
    zusätzlich einen Sprung über den grünen Sektor; die Gegenprobe zeigte
    ihn als toten Code (entfernen ließ den Test grün). Wer die Spanne
    ändert, muss den Test lesen.

