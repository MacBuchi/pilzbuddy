# PilzBuddy — Arbeitsregeln für `android/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- Signing: `android/key.properties` + `android/pilzbuddy-release.jks` (beide
  gitignored; Backup im Schlüsselordner des Betreibers). CI erzeugt beides aus den Secrets
  `ANDROID_KEYSTORE_*`. PKCS12: keyPassword == storePassword.

- **Der Benachrichtigungs-Kanal ist eine Einbahnstraße** (#277, seit
  1.86.0): Ohne die Manifest-Zeile
  `com.google.firebase.messaging.default_notification_channel_id` legt
  FCM still einen eigenen Kanal an — und der ist so leise, dass nur ein
  Symbol in der Statusleiste erscheint, kein Banner. Genau so am
  2026-08-12 auf dem Pixel gesehen, während das Nachbarprojekt mit
  eigenem Kanal ein Banner zeigte; die Nutzlasten beider Apps sind dabei
  identisch, der Unterschied lag ausschließlich auf der Android-Seite.
  Drei Stellen müssen zusammenpassen — Manifest, `res/values/strings.xml`
  und `createNotificationChannel` in `MainActivity.onCreate`;
  `test/android_manifest_test.dart` hält sie zusammen und liest dafür
  ausnahmsweise Kotlin-Quelltext (der native Code hat sonst kein Netz).
  **Die Wichtigkeit lässt sich nachträglich NICHT ändern:** Android merkt
  sie sich beim ersten Anlegen der ID, eine Änderung im Code erreicht
  bestehende Installationen nie. Deshalb `IMPORTANCE_HIGH` — leiser
  drehen kann der Nutzer selbst, lauter niemand. Wer die Stufe je ändern
  will, braucht eine NEUE Kanal-ID.

- **Ein Statusleisten-Symbol ist NUR sein Alphakanal** (#331, seit
  1.99.5): Android malt jedes nicht durchsichtige Pixel weiß und wirft
  die Farbe weg. Ohne
  `com.google.firebase.messaging.default_notification_icon` greift FCM
  auf `android:icon` zurück — das vollflächig deckende Launcher-Icon, als
  Silhouette also ein weißer Klotz. Genau so kam es beim Nutzer an
  („weißer Kreis"). `res/drawable/ic_notification.xml` ist deshalb EINE
  Fläche, und das Gesicht sind Löcher darin (`fillType="evenOdd"`, ab
  API 24 — unser minSdk). Zwei stille Fallen hält
  `test/android_manifest_test.dart` fest: Ein farbiges `fillColor` sieht
  im Diff wie eine Entscheidung aus und wird trotzdem plattgedrückt, und
  ohne `evenOdd` füllen sich die Löcher — dann ist es wieder ein Klotz.
  Von der Designsprache (`.claude/skills/pilz-designer/`) überlebt hier
  sonst nichts: keine Farbe, kein Halo, keine Kontur, keine
  Boden-Ellipse.
  Dieselbe Grafik trägt die Download-Meldung des Foreground-Service.
  `flutter_foreground_task` sucht sie ausschließlich über einen
  Meta-Data-Namen im Manifest und liefert bei einem Tippfehler stumm die
  Ressourcen-id 0; der Name steht deshalb als
  `downloadNotificationIconMetaData` in Dart, und derselbe Test hält
  beide Seiten zusammen.


## Play Store — offene Blocker

Reihenfolge des Store-Starts: Issue #92 (im Fahrplan #673 eine eigene
Stufe). Stand 2026-07-26 — noch offen:

Im Repo steckt kein Blocker mehr, und auch die Grafiken sind fertig
(`store/`: Icon 512×512, Feature-Grafik 1024×500, fünf Screenshots
1080×1920). Seit 1.87.1 ist auch der letzte Rest erledigt: Das AAB kommt
aus dem `play`-Flavor und trägt `REQUEST_INSTALL_PACKAGES` nicht mehr.
Offen ist nur noch, was in der Play Console passiert (#108, #91):
App-Eintrag anlegen, Data-Safety-Formular, Inhaltsbewertung, Store-Listing,
AAB hochladen.

Die Antworten dafür sind vorbereitet und aus dem Code abgeleitet:
**`docs/play-console.md`**. Ändert sich, was die App erhebt oder wohin sie
verbindet, gehört diese Datei in denselben PR — sonst laufen Formular und
Binary auseinander, und genau daran scheitern Play-Reviews.

**Die Frage, die den Zeitplan bestimmt** (#108): Gilt für das Konto die Regel
„12 Tester, 14 Tage durchgehend"? Persönliche Konten ab 2023-11-13 brauchen
das vor dem Produktions-Zugang. Die Antwort zeigt die Konsole erst nach dem
Anlegen des App-Eintrags, und die 14 Tage sind Kalenderzeit — alles andere
lässt sich parallel erledigen, das nicht.

**Paketname `de.mcbuchi.pilzbuddy`** (seit 1.88.0, vorher ein Paketname
mit dem Klarnamen des Betreibers): Umgestellt auf Wunsch des Betreibers, damit
sein Klarname nicht im Paket steht — und **vor** der ersten Einreichung,
weil Play die App ab dem ersten AAB-Upload unwiderruflich daran bindet.
Drei Folgen:

- **Für Android ist das eine andere App.** Der In-App-Updater FUNKTIONIERT
  trotzdem (er vergleicht nur Versionsnummern und übergibt die APK dem
  System-Installer, und ein noch nicht installiertes Paket wird schlicht
  installiert) — er ERSETZT die alte App nur nicht, sondern stellt die
  neue daneben. Die alte muss von Hand gelöscht werden.
  **Korrektur vom 2026-08-13:** Hier stand zuerst, der Installer lehne
  eine abweichende applicationId ab und es brauche eine Handinstallation.
  Das ist falsch — abgelehnt wird nur gleicher Paketname bei anderer
  Signatur. Die Anleitung im Changelog 1.88.0 war entsprechend falsch und
  ist in 1.90.0 richtiggestellt. Verloren gehen alle gerätelokalen Daten —
  Offline-Karten, `spot_cache/`, Einstellungen und der **Ausgangskorb**.
  Steht dort noch etwas, muss es VOR dem Wechsel gesendet sein. Auch das
  Push-Token hängt an der Installation: Benachrichtigungen sind in der
  neuen App wieder einzuschalten. Der Upload-Key bleibt unberührt — die
  Signatur hängt am Keystore, nicht am Paketnamen.
- **Firebase braucht eine eigene Registrierung je Paketname**, App-ID
  `…:android:25638619c3d5509a43dc77`. Während des Umzugs trug
  `google-services.json` beide Pakete, damit ein Build mit dem alten
  Namen nicht still ohne Push dasteht. Am 2026-08-13 hat der Betreiber
  die alte Registrierung gelöscht; die Datei ist seither frisch aus der
  Konsole geholt und trägt nur noch das neue Paket. **Sie wird geholt,
  nicht editiert** — der `mobilesdk_app_id` steht nur dort richtig.
  Folge der Löschung, falls doch noch jemand die alte App hat: Deren
  Push-Tokens sind ungültig, sie bekommt keine Meldungen mehr. Für den
  Umzug war das gewollt.
- **Sechs Stellen müssen gleichzeitig stimmen**, drei davon brechen
  still: Kotlin-Verzeichnis (sonst findet Gradle `.MainActivity` nicht)
  und die beiden MethodChannel-Namen (sonst antwortet niemand, und
  Beendigungsgründe wie APK-Installer hören ohne Fehlermeldung auf).
  `test/android_manifest_test.dart` prüft alle gegen die `applicationId`
  als einzige Quelle. Der Klarname steckte auch in `tool/measure_map.sh`
  und `docs/play-console.md`.

**Play App Signing** (Rest aus #111): Beim ersten AAB-Upload wird unser
Keystore zum *Upload-Key*, signiert wird danach von Google. Folge: Der
Play-Build hat eine **andere Signatur** als die GitHub-APK. Wer die APK
installiert hat, muss zum Wechsel einmal deinstallieren — Konto und Spots
liegen in Supabase und bleiben, verloren gehen nur heruntergeladene
Offline-Karten. Das gehört in die Tester-Einladung, sonst scheitert die
Installation wortlos mit „App nicht installiert".

Der Fingerprint des **Upload-Keys** (aus jeder veröffentlichten APK
ablesbar, also kein Geheimnis):

```
SHA-1    24:F7:09:2F:22:92:F5:CE:D0:3B:87:C0:5B:A1:B0:B0:53:96:1F:7D
SHA-256  CF:C8:C7:83:28:92:FA:71:B7:8A:54:51:DD:FB:76:F7:0F:B6:5A:59:0C:E3:F1:94:5B:7D:9B:89:2A:70:DC:E8
```

**Nicht** der Wert, der nach dem Upload in Firebase gehört: Die
ausgelieferte App trägt Googles App-Signing-Key, dessen Fingerprint erst
die Konsole zeigt (*Test und Veröffentlichung → Einrichtung →
App-Signatur*). Für FCM ist ohnehin keiner nötig — Push authentifiziert
über API-Key und Paketnamen, ein SHA bräuchte erst Google Sign-In, Maps
SDK, Dynamic Links oder App Check. Nachrechnen ohne Keystore:
`keytool -printcert -jarfile` scheitert (Flutter signiert nur v2/v3), es
braucht `apksigner verify --print-certs` oder den Signing-Block direkt.

Erledigt: Datenschutzerklärung (#90, `web/datenschutz.html`), Konto-Löschung
(#89), In-App-Updater entfernt (#88), AAB-Build (#87), Backup-Ausschluss
(#78). Der Build deklariert acht Berechtigungen, alle genutzt — einzeln
aufgeschlüsselt samt Herkunft in `docs/play-console.md`; zwei davon bringen
Plugins mit, und `RECEIVE_BOOT_COMPLETED` wird per `tools:node="remove"`
aktiv wieder entfernt.

Konto-Löschung: `public.delete_own_account()` (Patch 008), `security definer`
ohne Parameter — die id kommt aus `auth.uid()`, ein Argument wäre eine
Einladung, fremde Konten zu löschen. Löscht nur `auth.users`; alles andere
hängt per `on delete cascade` daran. Gegen die Live-DB mit einem
Wegwerf-Konto verifiziert (RPC 204, danach `invalid_credentials`).
Öffentliche Anleitung unter `web/konto-loeschen.html` (Play verlangt eine
URL ohne installierte App).

Unkritisch: `targetSdk` = 36 erfüllt die aktuelle Play-Anforderung,
`minSdk` = 24 (Android 7).

