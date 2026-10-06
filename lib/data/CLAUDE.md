# PilzBuddy — Arbeitsregeln für `lib/data/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Zwischenspeicher und Ausgangskorb liegen im Browser in IndexedDB**
  (#385 seit 1.115.0, #386 seit 1.116.0). `NoSpotCache`/`NoOutbox` sind
  nicht mehr der Web-Zweig, sondern nur noch der Fall „kein IndexedDB".
  **Name und Version der Datenbank haben EINEN Besitzer**
  (`browser_db.dart`): Öffnete der eine Speicher v1 und der andere v2,
  blockierte der Upgrade — im selben Tab, dauerhaft, ohne Fehlermeldung.
  Ein neuer Speicher heißt: dort eintragen und `kBrowserDbVersion`
  erhöhen. Vier Dinge, die man wissen muss:
  - **Abgelegt wird derselbe JSON-TEXT wie in der Datei auf Android**,
    nicht ein Objekt. IndexedDB nähme verschachtelte Maps direkt an, gäbe
    sie aber als `Map<String, Object?>` zurück — und darauf ist
    `Map<String, dynamic>` nicht zuweisbar, was `Spot.fromJson` erwartet.
    Ein Text nimmt denselben Weg durch `jsonDecode` wie auf dem Telefon:
    `encodeSpotCache`/`decodeSpotCache` sind deshalb geteilt.
  - **Fester Schlüssel, Konto IM Eintrag** — wie in der Datei. Nach der
    Nutzer-id zu schlüsseln wäre naheliegend, ließe aber die Spots jedes
    früher angemeldeten Kontos im Browser liegen.
  - **Zwei Fächer seit 1.217.0** (`SpotCacheSlot`): eigene Spots und die
    geteilten der Buddys — Feldbefund „die Buddy-Spots waren nicht
    offline verfügbar". Bis dahin sagte die Datenschutzerklärung
    ausdrücklich, dass Freundes-Spots NICHT gespeichert werden; der Satz
    ist im selben PR ersetzt. Getrennte Fächer, weil beide getrennt
    abgerufen werden und ein Abruf nie die Kopie des anderen
    überschreiben darf; `clear()` räumt beide. Grenze, benannt: Eine
    zurückgenommene Freigabe verschwindet erst beim nächsten Abruf MIT
    Empfang.
  - **`idb_shim` ist DIREKTE Abhängigkeit**, obwohl `vector_map_tiles` es
    ohnehin mitbringt (dieselbe Begründung wie bei `executor_lib`: nicht
    an einer exakt gepinnten Beta hängen). Der Nebengewinn ist der Test:
    `newIdbFactoryMemory()` fährt dieselbe Implementierung auf der VM.
  - **Ohne IndexedDB (privater Modus, `file://`) gelten weiter
    `NoSpotCache`/`NoOutbox`.** Bewusst NICHT `idbFactoryBrowser`, das
    still auf die Speicher-Fassung zurückfällt — ein Zwischenspeicher,
    der jeden Neustart vergisst, sähe von außen aus wie einer, der
    bleibt.
  Und der Unterschied, der die zweite Stufe ausmacht: **Ein Browser darf
  seinen Speicher ohne Vorwarnung räumen.** Für die KOPIE ist das
  verkraftbar, für das ORIGINAL im Korb nicht. Deshalb bittet
  `IndexedDbOutbox.append` beim ersten Ablegen einmal um
  `navigator.storage.persist()` (`browser_storage.dart`) — erst dort und
  nicht beim Start, weil Firefox dafür nachfragt und eine Nachfrage ohne
  Anlass eine Zumutung wäre; dieselbe Linie wie `positionFixProvider`.
  Lehnt der Browser ab, wird **trotzdem abgelegt** und die Karte sagt es
  (Streifen unter dem Korb-Banner): Chrome lehnt in einem gewöhnlichen
  Tab regelmäßig ab, und dann wäre der Fund SOFORT verloren statt
  vielleicht später. Die Anzeige fragt nie nach (`persisted()`, nicht
  `persist()`), und der Stub auf Android sagt `true` — ein Warnhinweis
  über ein Dateisystem wäre schlicht falsch.

- Beendigungsgründe (`lib/data/exit_info_repository.dart` + `exit_reporting.dart`,
  Issue #147): Beim Start liest die App über einen MethodChannel Androids
  eigene Historie (`getHistoricalProcessExitReasons`, ab Android 11, keine
  Berechtigung nötig für die eigenen Einträge) und meldet ANRs, Abstürze und
  Speicher-Kills nach `error_reports` — bei ANR mit dem Haupt-Thread-Abschnitt
  des Thread-Dumps. Das schließt die Lücke, die `logError` prinzipbedingt hat:
  Dort landet nur, was die App **überlebt**; ein ANR hinterlässt nichts, und
  genau deshalb blieb #142 unsichtbar, bis jemand ein USB-Kabel angesteckt hat.
  **Der einzige native Code im Projekt** (`MainActivity.kt`) — wer ihn anfasst,
  hat keinen Test als Netz, die Dart-Seite dagegen schon. Normale
  Beendigungen (`USER_REQUESTED`, `EXIT_SELF` …) werden bewusst NICHT
  gemeldet, sonst füllt jedes Wegwischen den Wochendigest (Lehre aus
  #124/#136). `created_at` ist der Todes-, nicht der Meldezeitpunkt. Ein
  Merker im App-Verzeichnis verhindert Doppelmeldungen; sein Verlust kostet
  nur eine doppelte Zeile. Web und Android < 11 liefern nichts.
  **Seit 1.122.0 kommt auch der NATIVE Absturz mit Spur** (#394): Android
  legt dafür seit API 31 ein Tombstone bereit, und der Kommentar „nur bei
  ANR liefert Android einen Dump" war seither falsch — der `CRASH_NATIVE`
  aus KW36 kam ohne eine Zeile an, obwohl sie bereitlag. Drei Dinge, die
  man wissen muss:
  - **Kotlin liest das Tombstone NICHT, es reicht es durch.** Es ist ein
    Protobuf; gelesen wird es in `lib/data/tombstone.dart`. Begründung:
    `MainActivity.kt` ist die einzige Datei ohne Test-Netz, ein Parser
    dort wäre der am wenigsten geprüfte Code an der am schlechtesten
    erreichbaren Stelle. Drüben prüfen erfundene Tombstones jeden Zweig.
    `test/android_manifest_test.dart` verbietet deshalb ausdrücklich ein
    `Tombstone.parseFrom` in Kotlin.
  - **Die Feldnummern stehen als Zahlen im Dart-Code**, nicht als
    kopierte `.proto`. Sie sind Teil eines veröffentlichten Formats
    („NOTE TO OEMS: do not use numbers in the reserved range") und ändern
    sich nicht rückwirkend; eine kopierte Datei müsste dagegen mit AOSP
    Schritt halten.
  - **`formatTombstone` wirft nie.** Der Weg dorthin IST die
    Fehlermeldung — ein Leser, der über ein unerwartetes Byte stolpert,
    nähme dem Bericht auch noch den Rest. Alles, was nicht passt, ergibt
    `null`, und der Bericht steht dann ohne Spur da wie zuvor.
  Die nativen Frames eines solchen Dumps übersetzt
  `python3 tool/symbolize_anr.py v1.32.0 dump.txt` — ohne dass beim Bauen
  irgendetwas aufgehoben werden muss: `(offset …)` im Dump ist die Position
  der Bibliothek in der APK (native Libs liegen dort unkomprimiert), das
  Release-Asset liefert die APK, und zu jedem Engine-Build veröffentlicht
  Flutter eine ungestrippte `libflutter.so`. Die Flutter-Version nimmt das
  Skript aus `release.yml` **im Tag selbst** — die Datei hat den Build
  gemacht, sie kann nicht danebenliegen. So kam in #151 heraus, dass der
  Haupt-Thread in `dart::MarkingVisitor::ProcessOldMarkingStack` stand,
  also im GC und nicht im Kartenrenderer. **Grenze:** `libapp.so` trägt im
  Release-Build gar keine Funktionssymbole (nur die vier Snapshot-Blobs);
  Frames im eigenen Dart-Code bleiben unbenannt, solange nicht mit
  `--split-debug-info` gebaut wird.

- **Ausgangskorb** (`lib/data/outbox.dart` + `outbox_runner.dart` +
  `outbox_view.dart`, #267, seit 1.79.0): Lesen ohne Empfang konnte die
  App seit 1.44.0, Schreiben nicht — ein Fund im Funkloch war weg. Jetzt
  legen **genau zwei** Schreibwege ihren Auftrag lokal ab: neuer Spot und
  Fund/Leergang an einem Spot. Alles andere (korrigieren, löschen,
  zusammenführen, GPX-Import) scheitert weiter sichtbar; das ist
  Schreibtischarbeit im WLAN, und ein Löschauftrag, der Tage später
  zuschlägt, wäre schlimmer als eine Fehlermeldung.
  Sechs Dinge, die man wissen muss:
  - **Nur `looksOffline` führt in den Korb.** Ein Serverfehler muss
    sichtbar scheitern — sonst sammelte der Korb still Aufträge, die nie
    durchgehen, und ein kaputtes Deployment bliebe unbemerkt (dieselbe
    Regel wie im Zwischenspeicher, Lehre aus #80). Ein Flow-Test wacht
    darüber.
  - **Der Korb wirft beim Schreiben**, anders als `spot_cache.dart`: Der
    Cache ist eine Kopie, der Korb trägt das Original. Landet der Auftrag
    nicht auf der Platte, meldet die App den ursprünglichen Netzfehler
    weiter — „gespeichert" wäre eine Lüge.
  - **Der Auftrag entsteht VOR dem ersten Sendeversuch**, mit `client_id`
    je Spot und je Fund (Patch 016). Nur so trägt schon der erste Versuch
    die Kennung, und ein Abriss NACH dem Insert erzeugt beim Nachholen
    keinen zweiten Spot: Das Repository deutet `23505` als „stand schon"
    und holt sich die id von damals.
  - **Auflösen und Entfernen werden gemeinsam gültig** — der Runner
    schreibt am Ende den ganzen Korb neu (`replaceAll`). Ein Fund kann an
    einem Spot hängen, den es serverseitig noch nicht gibt; stürbe die App
    zwischen „Spot gesendet" und „Fund umgeschrieben", zeigte der Fund auf
    einen Auftrag, den es nicht mehr gibt.
  - **Wartende Einträge zählen überall mit** (Statistik, Ampel,
    GPX-Export) — sie sind passiert. Gesperrt ist nur das Ändern
    einzelner Einträge: dafür fehlt die Server-id. Auf der Karte sind sie
    blass mit Uhr (`MushroomIcon.pending`), sonst legt man denselben Spot
    zweimal an.
  - **`outbox/` gehört in beide Backup-Ausschlüsse** (`backup_rules.xml`,
    `full_backup_content.xml`) — dieselbe Begründung wie bei
    `spot_cache/`, nur schärfer: Hier stehen die Koordinaten, bevor sie
    irgendwo anders stehen. Beim Abmelden wird der Korb mitgelöscht,
    deshalb fragt das Profil vorher nach.
  - **Seit 1.116.0 gibt es ihn auch im Browser** (#386, `outbox_idb.dart`
    auf IndexedDB) — Einzelheiten oben beim Zwischenspeicher. Alles
    darüber bleibt unberührt: `outbox_view.dart`, `outbox_runner.dart`
    und die `client_id`-Idempotenz aus Patch 016 kennen nur die
    Schnittstelle.
  Ausgelöst wird die Wiedervorlage beim App-Start, bei der Rückkehr der
  Verbindung (`noConnectivityProvider`) und auf Tippen im Banner —
  bewusst NICHT am App-Resume: Wer aus dem Wald nach Hause kommt, ohne
  die App zu schließen, hat kein Resume, aber sehr wohl einen
  Netzwechsel.

