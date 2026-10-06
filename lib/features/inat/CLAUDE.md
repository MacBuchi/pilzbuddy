# PilzBuddy — Arbeitsregeln für `lib/features/inat/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Funde an iNaturalist melden — und darüber an GBIF** (#553, seit
  1.191.0, **noch unsichtbar**): Alle Entscheidungen stehen im TEXT von
  #553 (maßgeblich vor dem Plan-Kommentar), die Registrierung als
  Checkliste daneben. Sieben Dinge, die man wissen muss:
  - **`kInatAppId` ist leer, und das ist der Schalter.** Ohne
    Application ID zeigt die App den Weg nirgends
    (`inatAvailableProvider`). Der Betreiber kann die App bei
    iNaturalist frühestens am 2026-11-24 registrieren (Konto 2 Monate
    alt + 10 verbessernde Bestimmungen im letzten Monat); dann ist die
    ID eine Zeile. Im Browser bleibt es vorerst aus — dort fehlt die
    Rückleitungsseite, und CORS der Token-Adresse ist ungemessen.
  - **Jeder meldet mit SEINEM Konto** (OAuth + PKCE, öffentlicher
    Client, kein Geheimnis in der APK). Ein Sammelkonto hat der
    Betreiber vorgeschlagen; iNaturalist hat genau das bei QuestaGame
    als ToS-Verstoß gesperrt.
  - **Der Zugang liegt im Keystore** (`flutter_secure_storage`), nie in
    Supabase, und ist vom Backup ausgenommen — `FlutterSecureStorage.xml`
    UND `FlutterSecureKeyStorage.xml`, ein Test hält beide fest.
  - **Die Rückleitung steht an drei Stellen**: `kInatRedirectUri`, die
    CallbackActivity im Manifest, die Registrierung bei iNaturalist.
    Stimmt eine nicht, bleibt der Custom Tab nach dem Bestätigen offen,
    ohne Fehlermeldung.
  - **`find_reports` (Patch 029) entsteht VOR dem Senden** und trägt die
    uuid, die iNaturalist übernimmt. Ein zweiter Versuch mit derselben
    uuid legt dort keine zweite Beobachtung an — nachgelesen in
    `observations_controller.rb` (#create sucht erst nach der uuid).
    Reihenfolge: Art, JWT, Zeile, Beobachtung, Fotos, `reported`.
    `user_id` zeigt auf `auth.users`, aus demselben Grund wie bei den
    Kudos (PGRST201).
  - **Die Netzziele stehen AUSGESCHRIEBEN im Code** (`kInatWebBase`,
    `kInatApiBase`). Der Datenschutz-Wächter sucht `https://…`; ein
    `Uri.https(host, …)` hätte er übersehen — beim Bau genau so
    passiert, bevor er es sah.
  - **Was NICHT hinausgeht:** Notiz, Spot-Name, Buddys — und das
    Buddy-Foto nur mit ausdrücklichem Haken (Betreiber: „nicht blind").
    Vorgabe der Stelle ist VERSCHLEIERT; iNaturalist kennt die genaue
    trotzdem, der Verbinden-Dialog sagt es.
  **Stufe 2 (seit 1.192.0): Stand am Fund, nachträglich melden.** Drei
  Dinge:
  - **Einmal je Sitzung abgeglichen, EINE Abfrage für alle**
    (`myFindReportsProvider`, `InatReporter.refresh`): iNaturalist nimmt
    eine id-Liste; GBIF wird nur für bestätigte gefragt, im Datensatz
    `kInatGbifDataset` über `catalogNumber` = Beobachtungsnummer
    (nachgesehen an einer echten Beobachtung). `sending` gleicht niemand
    ab — dort fehlt etwas, das nur ein neuer Versuch nachholt. Fehlt eine
    Beobachtung in der Antwort, gilt sie als gelöscht; deshalb reicht
    `per_page` immer für alle gefragten ids.
  - **„Vervollständigen" ist derselbe Weg wie Melden** und knüpft über
    die uuid an: auch wenn die Beobachtungs-id nie in der Zeile ankam,
    entsteht keine zweite (Flow-Test mit genau diesem Abbruch).
  - **Ein Ausfall bei iNaturalist/GBIF gehört nicht in den
    Wochendigest** — `InatException` und Funklöcher werden beim
    Abgleich verschluckt, der gespeicherte Stand gilt.

