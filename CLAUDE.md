# PilzBuddy — Arbeitsregeln für `web/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- Web-Builds für Pages brauchen `--base-href /pilzbuddy/` und eine `404.html`
  (Kopie von `index.html`) als SPA-Fallback.

- **Web-Push entscheidet unser eigener Worker, nicht Firebase**
  (`web/push/firebase-messaging-sw.js`, seit 1.203.0). Bis dahin lud er
  das Firebase-SDK, und das zeigte nichts an, sobald IRGENDEIN Fenster
  der Domain sichtbar war — auf GitHub Pages liegen Freigabe und
  Vorschau aber auf einem Ursprung, und „sichtbar" heißt nicht
  „angesehen". Im Feld (2026-09-24, Opera) kam deshalb in der Vorschau
  nur die Testnachricht an, obwohl FCM jeden Versand mit `ok`
  quittierte. Vier Dinge, die man wissen muss:
  - **Fokus, nicht Sichtbarkeit, und nur DIESE App**
    (`APP_BASE` = eine Ebene über dem Scope). Fokussiert ⇒ die App bekommt
    die Meldung per `postMessage` als Leiste; sonst zeigt der Browser
    sie. Die Fehlerrichtung ist gewählt: Meldet ein Browser keinen
    Fokus, erscheint die Systembenachrichtigung — eine zu viel statt
    einer verschluckten.
  - **Beide Seiten der Übergabe gehören uns** (`kPushBridgeType`,
    `pushBridgeMessageOf`, `push_web_bridge_web.dart`); im Web hört die
    App NICHT auf `FirebaseMessaging.onMessage`. Das Firebase-Format
    nachzubauen hätte an Interna gehangen. Zum Empfangen braucht der
    Worker kein SDK — das Abo legt die Seite an (`getToken`), nachgeprüft
    mit echtem Token.
  - **Der Tipp kennt sein Ziel selbst**: `#` + `route` unter der eigenen
    App (Hash-Strategie, kein `usePathUrlStrategy`). `send-push` schickt
    kein `fcmOptions.link` mehr; der feste `/pilzbuddy/` öffnete aus der
    Vorschau die Freigabe.
  - **Geprüft im echten Chrome** (`tool/check_push_worker.mjs`, Job
    „Build Web"): echtes `push`-Ereignis über
    `ServiceWorker.deliverPushMessage`, Freigabe und Vorschau
    nebeneinander. Gestellt ist genau eines — der Fokus, weil ein
    kopfloser Chrome `WindowClient.focused` nie wahr meldet.
    **Falle beim Prüfen: `getNotifications()` löscht in Chrome, was
    gespeichert, aber noch nicht angezeigt ist.** Wer auf eine Meldung
    wartet, indem er abfragt, verliert sie gelegentlich, obwohl
    `showNotification` Erfolg meldet (rund jeder zwanzigste Lauf; dichtes
    Abfragen beim Zeigen: 16 von 40 verloren, gemessen in TrailBuddy
    #291). Der Prüfer zählt deshalb im Worker mit, wann `showNotification`
    fertig ist, und liest erst danach, einmal (#691).
  Den Worker frischt die App bei jedem Start auf (`update()`): Sein
  Scope wird nie angesteuert, der Browser sähe sonst höchstens einmal
  am Tag nach. Tote Tokens räumt `send-push` selbst ab („unregistered"),
  weil `push_flush` die Antwort über pg_net nie abwartet.

- **Der eigene Service Worker** (`web/sw.js` + `web/flutter_bootstrap.js`,
  #387, seit 1.117.0). Acht Dinge, die man wissen muss:
  - **Immer zuerst das Netz, der Cache nur als Rückfall.** Das ist die
    tragende Entscheidung: Ein Cache, der gewinnt, nagelt Nutzer auf einen
    alten Stand und umgeht damit genau die kontrollierte Beförderung. Dazu
    ein harter Grund — Flutters Web-Ausgaben tragen KEINE
    Inhalts-Prüfsummen (`main.dart.js` heißt immer gleich), ein
    `cache-first` lieferte also stillschweigend die alte App. Der Preis
    ist ehrlich: Die PWA wird dadurch **nicht schneller**, nur startfähig.
  - **„Zuerst das Netz" heißt nicht „auf das Netz warten"** (seit
    1.204.2, Feldbefund 2026-09-24: „kein Flugmodus, aber quasi kein
    Empfang", die PWA blieb leer). Bis dahin hatte nur die Seite selbst
    eine Grenze (3 s); `main.dart.js` und CanvasKit warteten ohne Grenze
    auf ein Netz, das Verbindungen annahm und nie antwortete. Jetzt gilt
    für jede Datei MIT Kopie eine Grenze (4 s), und nach einem Reißen
    nur noch 300 ms, bis wieder etwas aus dem Netz kommt — die App lädt
    ihre Dateien nacheinander, mit 4 s je Stück waren es gemessen 20 s
    statt 1,8. Ohne Kopie wird weiter gewartet.
  - **Der alte Cache geht erst, wenn der neue alles hat** (seit 1.204.2).
    Vorher löschte das Aktivieren ihn sofort, im neuen lag nur die
    Hülle, und wer nach einem Deploy kurz online war, hatte keinen
    Offline-Start mehr — mit einem Deploy je Merge in der Vorschau der
    Normalfall. Es bleibt genau EIN früherer (der mit Vollständig-
    Merker); solange er steht, kommt jeder Rückfall zuerst aus ihm, damit
    ein Start ohne Netz aus EINEM Stand kommt. `topUp` füllt den neuen
    per `If-None-Match` nach — 304 heißt umlegen statt neu laden — und
    räumt erst dann ab. „Früher" heißt: ein ANDERER Cache MIT
    Vollständig-Merker — liegt der Cache eines neueren, noch wartenden
    Workers daneben (der hat noch keinen), mischte der Rückfall sonst
    zwei Stände, und die Mischung startete ohne Netz nicht (beim Bau
    gemessen). **Nie die Reihenfolge von `caches.keys()`** (#628): Bis
    1.213.0 galt „in Anlegereihenfolge vor dem eigenen", und Chromium
    liefert die Reihenfolge nicht verlässlich so — der neue Cache hielt
    sich dann sofort für vollständig, und der alte blieb je Deploy
    liegen. Gefunden beim Übertragen nach TrailBuddy, wo der Prüfer in
    CI rot wurde.
    **Nie `caches.open` auf einen fremden oder womöglich gelöschten
    Namen**: `open` LEGT AN. Ein abgelöster Worker, der nach dem Löschen
    seines Caches noch eine Antwort ablegte, erzeugte einen leeren Cache
    ohne Merker, den nichts mehr entfernte. Nachgeschlagen wird deshalb
    mit `caches.match(…, {cacheName})`, geschrieben nur hinter
    `caches.has(CACHE)`, und `sweepZombies` räumt Caches ohne Merker UND
    ohne Hülle ab. Der Prüfer zählt seither keine 304 mehr (die Zahl
    maß, wie viel die Seite selbst lädt), sondern verlangt, dass beim
    Nachfüllen nichts Unverändertes voll geladen wird.
    Drei Fallen beim Prüfen, alle passiert: Ein Update bei HÄNGENDEM
    Netz aktiviert nie (der Browser wartet auf die offenen Anfragen des
    alten Workers), prüft also nur den alten. Wird das Netz erst nach
    dem Update knapp, ist das Nachfüllen auf einem schnellen Rechner
    schon fertig, und der Schritt prüft nichts (in CI so). Deshalb
    blockiert der Testserver gezielt nur das Nachfüllen — erkennbar an
    der Kennung `x-pilzbuddy-topup`, die auch die 304 des Nachfüllens von
    denen des Browsers trennt.
    `version.json?cachebuster=…` legt der Worker gar nicht ab — sonst
    wüchse der Cache je Start um einen Eintrag.
  - **`web/flutter_bootstrap.js` ist Pflicht, nicht Bequemlichkeit.** Die
    erzeugte Fassung übergibt dem Loader `serviceWorkerSettings`, und der
    registriert `flutter_service_worker.js` (784 Bytes, meldet sich selbst
    ab) genau dann, wenn für den Scope schon eine Registrierung existiert
    — ab dem zweiten Besuch also UNSERE. Der Cache wäre bei jedem Laden
    weg, ohne eine Fehlermeldung.
  - **Die Platzhalter dürfen in KEINEM Kommentar der Datei stehen.** Der
    Build ersetzt sie überall, und der Lader ist mehrzeilig: Aus einer
    `//`-Zeile bricht er aus, danach ist die Datei Syntaxmüll und die App
    startet gar nicht. Beim Bau von #387 genau so passiert; sichtbar nur
    als `SyntaxError` in der Browser-Konsole. Ein Test wacht darüber.
  - **Der erste Besuch füllt den Cache NICHT von allein.** Die ersten
    Anfragen gehen raus, bevor der Worker aktiv ist; er sieht sie nie
    (`clients.claim()` übernimmt die Seite mitten im Laden, kann aber
    nicht rückwirkend mithören). Deshalb meldet die Seite ihm per
    `postMessage`, was sie geholt hat (`warm`) — eine Liste von Hand wäre
    bei jeder Änderung still falsch, und „still falsch" heißt hier:
    startet ohne Netz nicht. Gegengeprobt: Ohne den Schritt bleiben 6
    statt 12 Einträge übrig und der Offline-Start scheitert, während
    `flutter test` grün bleibt.
  - **Gemeldet wird über einen BEOBACHTER, nicht mit einer
    Momentaufnahme** (#427, seit 1.128.2). Bis dahin stand dort ein
    einmaliges `getEntriesByType('resource')` gleich nach `runApp`. Das
    ersetzte die Liste, tauschte sie aber gegen einen Wettlauf: Was bis
    zu diesem einen Augenblick geholt war, kam in den Cache, alles
    Spätere nie. Zwei Läufe desselben Commits legten daraufhin 15 bzw.
    16 Dateien ab — und der mit 16 startete ohne Server nicht. **Mehr ist
    nicht vollständiger**, die beiden Mengen stehen in keinem
    Teilmengen-Verhältnis; eine Zahl ist hier eine Aussage über den Lauf,
    nicht über den Build. `PerformanceObserver` mit `buffered: true`
    liefert Vergangenes UND Künftiges, es gibt also keinen Zeitpunkt mehr,
    an dem gemessen wird. Damit verhält sich der erste Besuch wie jeder
    weitere — ab dem zweiten legt der Worker als Kontrolleur ohnehin jede
    erfolgreiche eigene Antwort ab. Folgerichtig prüft
    `check_service_worker.mjs` seither keine Untergrenze mehr, sondern die
    Zusage selbst: **jede Datei, die der Besuch geholt hat, liegt danach
    im Cache** — der Lauf gegen sich selbst, eine feste Liste wäre wieder
    still falsch. Die verbliebene Zahl (`>= 8` auf der Soll-Seite) beweist
    nur, dass überhaupt gemessen wurde.
  - **`--no-web-resources-cdn` gehört in JEDEN Web-Build** (ci, promote,
    preview; ein Test wacht darüber). Ohne den Flag holt der Loader
    CanvasKit von `www.gstatic.com` — offline tot, und die IP jedes
    Besuchers ginge an Google. Die Dateien liegen ohnehin im Build, der
    Flag kostet nichts.
  - **Die Notbremse lädt bewusst NICHT neu**
    (`postMessage({type:'unregister'})`): Beim nächsten Laden meldet der
    Bootstrap den Worker sofort wieder an, und dann wäre von der Wirkung
    nichts zu sehen. Der eigentliche Ausweg aus einem kaputten Worker ist
    ein Build ohne die Registrierung plus ein `sw.js`, das sich selbst
    abmeldet — der erreicht jeden Online-Nutzer, eben WEIL die Navigation
    netzwerkzuerst läuft.
  **Geprüft wird im echten Browser**, nicht per Textsuche:
  `tool/check_service_worker.mjs` (Job „Build Web") fährt einen Chrome
  gegen den gebauten Ordner und **schaltet den Webserver dabei wirklich
  ab**. Die Prüfungen in `test/web_shell_test.dart` fangen nur die Fallen,
  die man im Diff übersieht — eine falsche Entscheidung im Worker sehen
  sie nicht.
  **„Beim ersten Versuch rot, beim zweiten grün" war kein Zufall**
  (behoben 2026-10-01): zwei Zeitfehler des PRÜFERS, beide nur auf einem
  langsamen Runner. Der Vorlauf von Schritt 1 räumte nach 2 s aus der
  Seite ab, während der Worker noch installierte („0 im Cache"); jetzt
  räumt `Storage.clearDataForOrigin` vor dem ersten Laden. Und Chrome
  schickt die erste Update-Prüfung nach dem Installieren erst rund eine
  Minute später ab; je nach Tempo fiel diese Minute in den 30-s-Rahmen
  des neuen Deploys, der jetzt 120 s hat. Nachstellen lässt sich ein
  langsamer Runner mit `CPU_SLOW=6 node tool/check_service_worker.mjs
  build/web` — damit war vorher jeder Lauf rot. Wer dort wieder rot
  sieht: erst so nachstellen, nicht neu starten.

- **Die Web-Fassung lädt Roboto von `fonts.gstatic.com`** — gemessen am
  2026-09-04, bei jedem Seitenaufruf und vor jeder Anmeldung. Das ist
  Flutters Vorgabe für die Standardschrift und hat mit CanvasKit nichts zu
  tun (das kommt seit #387 lokal). Offenzulegen war es trotzdem:
  `web/datenschutz.html` nennt es seit 1.117.0. Abstellen hieße Roboto
  mitliefern und im Theme setzen — eigenes Issue, eigene Größenfrage.
  Nebenkosten, die bleiben: `assets/map_glyphs/` (984 KB) landet im
  Web-Build und wird dort nur gelesen, wenn ein Browser den
  MapLibre-Versuch gewählt hat (#689, `?maplibre=1`). Flutter kennt keine
  plattformabhängigen Asset-Listen.

- **`web/maplibre/` ist fremder Code, unverändert aus npm** (#689):
  MapLibre GL JS 5.24.0 und PMTiles 4.5.0, Prüfsummen und Lizenzen in
  `web/maplibre/README.md`. Selbst gehostet, weil ein CDN ein neues
  Netzziel wäre. Der Datenschutz-Wächter liest die Dateien mit und fand
  `maplibre.org` (Logo-/Attributions-Link, den die App nicht einbaut,
  `onTapOnly`). Geladen wird nur mit gewählter Engine, also landet die
  Bibliothek auch nur dann im Cache des Service Workers. Die Version
  folgt dem Paket `maplibre` (0.3.5 ⇒ GL JS 5), nie allein.

