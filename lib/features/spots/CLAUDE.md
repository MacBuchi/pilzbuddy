# PilzBuddy — Arbeitsregeln für `lib/features/spots/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Der Reiter „Spots"** (#509, seit 1.161.0): die Karte als Liste
  (`lib/features/spots/spots_screen.dart`) plus die Statistik, die bis
  1.160.0 im Profil stand. Sechs Dinge, die man wissen muss:
  - **Keine neue Abfrage, kein Schema-Patch.** Alles kommt aus
    `mySpotListProvider` und `friendSpotsProvider` — der Reiter
    funktioniert damit offline und zeigt den Ausgangskorb mit. Wer hier
    etwas ergänzt, das eine eigene Abfrage bräuchte, hat die Idee
    verlassen.
  - **Sortiert wird nach dem jüngsten EINTRAG, nicht nach dem jüngsten
    Fund** (`spot_list.dart`, ohne Widgets, wie `species_catalogue.dart`):
    Ein Leergang ist Aktivität. Die Trennlinie aus #211 gilt weiter — die
    STATISTIK zählt nur `ownFinds`.
  - **Drei Gruppen, und die dritte gibt es nur wegen der Freigaben.**
    Ein Buddy-Spot ohne `share_details` kommt ohne einen einzigen
    Eintrag an und sähe aus wie eine Vormerkung (#499). Er steht
    deshalb unter „Ohne Einträge" mit demselben Satz, den auch das
    Spot-Blatt sagt. Dieselbe Falle umgeht die Karte am Marker mit
    `spot.isOwn && spot.isPlanned`.
  - **Zwei Ziele je Zeile.** Antippen öffnet `showSpotDetailSheet` an
    Ort und Stelle (das Blatt braucht nur eine id und hängt an keiner
    Karte), das Kartensymbol wechselt den Reiter (`kMapBranchIndex` in
    `lib/core/router_branches.dart` — eigene Datei, weil `router.dart`
    jeden Screen importiert) und stellt dann den Fokus-Wunsch (#345).
    Reihenfolge: erst Reiter, dann Wunsch.
  - **Der Reiter schaltet die Buddy-Meldung NICHT stumm.**
    `lastFindSeenAt` gehört dem Karten-Banner; hier wird nur gelesen
    (`spotsWithNewsProvider` fasst `newBuddyFindsProvider` zusammen —
    EINE Definition von „neu"). Wer das ändert, holt #349/#425 zurück:
    ein Feature, das nach dem ersten Benutzen kaputt aussieht.
  - **Der Karten-Filter bleibt bei der Karte.** Hier stehen eigene,
    leichte Regler (Suche über Name/Art/Buddy mit derselben Faltung wie
    die Artensuche, #395; Dreier-Schalter nur, wenn es geteilte Spots
    gibt). Ein Filter, der an zwei Orten verschieden wirkt, wäre
    schlimmer als zwei getrennte — auf der Karte muss er sich melden
    (#154).
  Die Statistik (`widgets/spot_stats_view.dart`, gerechnet in
  `spot_stats.dart`) ist UMGEZOGEN, nicht verdoppelt: Im Profil steht ein
  Verweis. „Funde nach Jahreszeit" ist dabei einem Monatsverlauf
  gewichen, der `SeasonBars` benutzt — nur so lässt sich der eigene
  Jahresgang neben den gemeldeten legen. Der Vorjahresvergleich rechnet
  **bis zum selben Tag**, sonst stünde man jeden Herbst gegen ein volles
  Vorjahr im Rückstand.

- **Vormerkung** (#499, seit 1.159.0): ein Spot OHNE Einträge, mit
  erwarteten Arten (`spots.expected_species`, Patch 025). Drei Dinge,
  die man wissen muss:
  - **Vorgemerkt IST `finds.isEmpty`**, keine Zustandsspalte: Der erste
    Eintrag beendet die Vormerkung von selbst, zwei Wahrheiten könnten
    auseinanderlaufen. Bis 1.158.0 legte der Anlege-Weg immer einen
    Fund an (der Arten-Sammler meldet auch eine leere Zeile — bewusst:
    „da stand was, ich weiß nicht was"); der Schalter „Nur vormerken"
    im Blatt umgeht genau diese Zeile.
  - **Erwartete Arten sind KEINE Funde.** Als Fund-Sorte (wie der
    Leergang) sickerten sie in Statistik, Marker-Art und
    Artenvorschläge; als Liste am Spot liest sie nur, wer sie braucht:
    `scanSpeciesOf` (Ampel-Blatt, Nachlauf) und `spotSpeciesNames`
    (Arten-Filter, Saison-Filter, Arten-Zähler) — jeweils nur, solange
    der Spot keine Funde hat.
  - **Verblasst wie wartend, aber ohne Uhr** (`MushroomIcon.planned`);
    kein viertes Abzeichen. Der Ausgangskorb trägt die Liste im
    Auftrag mit (`NewSpotJob.expectedSpecies`).

- **Fundfotos für Buddys** (#532, seit 1.185.0): ein Foto am eigenen
  Fund, 14 Tage sichtbar für die, die den Fund sehen dürfen; Posteingang
  ist der Reiter „Spots". Sechs Dinge, die man wissen muss:
  - **Die Bytes liegen im Bucket `find-photos`, nicht in Postgres.**
    Je Foto eine Zeile `find_photos` (~200 Byte, Patch 026) und zwei
    JPEGs (1024 px ≈ 150 KB, Vorschau 200 px ≈ 12 KB). Der Speicher
    ist damit KONSTANT: 14 Tage Frist als Default UND Constraint in der
    Datenbank (ein Client kann sie nicht verlängern), und der
    Feedback-Bot räumt alle zwei Stunden per ABGLEICH — jedes Objekt
    ohne lebende Zeile fliegt (`sweep_find_photos`, Schonfrist 1 h für
    Uploads im Aufbau). Kein „erst Zeile, dann Objekt": Das ließe
    Uploads, deren Zeile nie kam, für immer liegen.
  - **Das Foto erbt die Sichtbarkeit des FUNDES.** `fp_friend_select`
    fragt nur `exists (select … from finds)`; die Storage-Policy
    `find_photos_read` fragt nur, ob eine Zeile sichtbar ist. Keine
    zweite Freigabe, die neben der ersten driften kann. Ein Objekt ohne
    Zeile ist für niemanden lesbar — deshalb erst die Objekte, dann die
    Zeile. Im Fake spiegelt `findVisibleTo` die drei finds-Policies an
    EINER Stelle; Spot-Abruf und Fotos lesen dieselbe Antwort.
  - **Die Fundstelle steckt im Foto, und die Bibliotheken lassen sie
    drin.** `image_picker` kopiert beim Verkleinern auf Android
    absichtlich alle 30 GPS-Tags zurück (`ExifDataCopier.java`);
    `package:image` reicht EXIF durch `bakeOrientation` und
    `copyResize` und schreibt es in `encodeJpg` wieder hinein.
    `lib/core/photo_pipeline.dart` leert `exif` ausdrücklich und LIEST
    das Ergebnis (`jpegForeignMarkers`, Erlaubnisliste der Segmente,
    dazu „Bytes hinter EOI") — bei jedem Upload, nicht nur im Test. In
    der Gegenprobe ohne die eine Zeile wurden drei Tests rot, darunter
    der Laufzeit-Riegel selbst. Der Dialog sagt dazu, was bleibt: Ein
    erkennbarer Ort ist erkennbar.
  - **Die Kachel lädt die Vorschau, die Vergrößerung das Bild** — der
    Egress-Hebel (Faktor 10) auf 5 GB im Monat. Beides über
    `BoundedFileCache` (aus #537 herausgelöst, 24 MB, älteste fliegt).
    Der Profil-Schalter „Fundfotos von Buddys anzeigen" (Vorgabe AN)
    filtert im PROVIDER, nicht in der Kachel: aus heißt kein Abruf,
    eigene bleiben. Rand, Wischen und Ausgänge der Vergrößerung wohnen
    in `PhotoOverlay`, geteilt mit den Artbildern.
  - **Offline scheitert sichtbar, kein dritter Korb-Weg.** Ein Foto ist
    ein Extra-Schritt nach dem Eintragen; ein Binärauftrag im Korb wäre
    eine eigene Idempotenz-Geschichte. Wartende Funde haben keine id
    und deshalb keine Kamera, Leergänge nichts zu zeigen.
  - **Keine neue Berechtigung, kein neues Netzziel** — Storage liegt
    unter der Supabase-Adresse. Trotzdem eine neue Datenkategorie:
    `web/datenschutz.html`, `docs/play-console.md` (Fotos: erhoben,
    optional; die Zeile „Fotos: NICHT erhoben" ist gefallen) und
    `docs/datenschutz-nachweise.md` sind im selben PR mitgezogen. Der
    Schema Dry Run braucht seither `[storage] enabled = true` in
    `config.toml`, sonst gibt es `storage.buckets` nicht.
  - **Foto gleich beim Eintragen** (seit 1.188.0): Das Blatt „Fund
    eintragen" nimmt ein `PreparedPhoto` mit und gibt es als
    `AddFindResult` zurück; hochgeladen wird erst NACH dem Schreiben,
    an die id des ERSTEN Fundes (`SpotRepository.addFinds` liefert die
    ids seither, per `client_id` zugeordnet — `RETURNING` verspricht
    keine Reihenfolge). Der Fund ist das Original: Scheitert der
    Upload, steht er trotzdem, und die Meldung sagt beides. Wandert er
    in den Korb, gibt es keine id und damit kein Foto — ein wartender
    Spot bietet es deshalb gar nicht erst an.
  - **Galerie im Reiter „Buddys"** (seit 1.189.0): `FindPhotoGallery`
    ganz oben, dieselbe `findPhotosProvider`-Liste wie der Streifen —
    keine eigene Abfrage, also keine eigenen Sichtbarkeitsregeln. Der
    Neu-Punkt ist GERÄTELOKAL (`Settings.seenFindPhotoIds`), weil eine
    Tabelle dafür eine Lesequittung wäre, die niemand bestellt hat;
    gesetzt beim Öffnen, nicht beim Vorbeiscrollen, und beim Setzen auf
    lebende Fotos gestutzt. Eigene Fotos sind nie neu. Der Ring rechnet
    über die volle Restdauer, nicht über `daysLeft` — ganze Tage
    springen, ein frisches Foto stünde sonst bei 13/14.
  - **Kudos** (Patch 028, seit 1.190.0): `find_photo_kudos`, ein Pilz
    je Buddy und Foto, keine Skala. Sichtbarkeit geerbt vom Foto
    (`fpk_select` fragt `find_photos`), abgeräumt per Cascade mit ihm.
    **`user_id` verweist auf `auth.users`, NICHT auf `profiles`** — mit
    Fremdschlüsseln auf `find_photos` UND `profiles` hielt PostgREST die
    Tabelle für eine Verbindungstabelle, und das `profiles`-Embed der
    Fotos wurde mehrdeutig (PGRST201). Lokal gegengeprobt: Beide
    Fassungen der Abfrage, auch die der ausgelieferten Clients, brachen.
    Der Schema Check prüft deshalb auch die Abfrage OHNE Kudos (Stand
    1.189.0). Namen löst die App über die eigene Buddy-Liste auf
    (`buddyNamesProvider`); Buddys von Buddys werden nur gezählt — mehr
    gäbe die profiles-Policy ohnehin nicht her.
  - **Ein Bild am Feedback** (#525, seit 1.186.0, Patch 027) läuft
    über dieselbe Naht — `PhotoAttachment` in beiden Melde-Dialogen,
    `photoPickerProvider`/`photoPreparerProvider` aus
    `core/photo_providers.dart`, Repository nimmt nur ein
    `PreparedPhoto`. Der Bucket `feedback-photos` ist STRENGER: Nutzer
    legen nur hinein, lesen darf allein der Betreiber (Service-
    Schlüssel, Dashboard). Der Text einer Meldung wird öffentlich, das
    Bild nicht — das Issue nennt nur den Dateinamen, keinen Pfad und
    keine Nutzer-id (`feedback_issue_body`, Selbsttest). Frist 90 Tage
    wie die Fehlerberichte, der Bot fegt per Erstellzeit; die Zeile
    behält ihren Pfad ins Leere, das Issue existiert ja.
    **Seit 1.196.0 bis zu DREI Bilder** (#569, Patch 033):
    `PhotoAttachmentList`, Repository nimmt eine Liste. Die Pfade stehen
    als Array `photo_paths` in der Zeile, KEINE Kindtabelle — die App
    darf ihre Feedback-Zeile nicht zurücklesen, eine Kindtabelle
    bräuchte deshalb eine vorab erzeugte id und eine Definer-Funktion.
    Grenze und Ordner erzwingt der Check über
    `app_internal.feedback_photos_ok` (ein CHECK kann kein Array
    durchlaufen). **`photo_path` bleibt**, solange 1.186.0–1.195.x im
    Feld sind; neue Clients schreiben nur `photo_paths`, der Bot liest
    beide (`feedback_photo_names`). Erst danach darf die alte Spalte
    weg — erweitern → ausliefern → entfernen.
    **Einwilligung für die Artgalerie** (seit 1.197.0, Patch 034,
    #569 Teil b): ein Haken im Art-Hinweis-Dialog, ab Werk aus, nur mit
    Bild, fällt mit dem letzten Bild weg. Er ist die EINZIGE Grundlage,
    ein Feedback-Bild in `species_photos.dart` zu übernehmen — ohne ihn
    ist ein solches Bild ausdrücklich nicht zur Veröffentlichung
    gedacht. Lizenz `kGalleryPhotoLicence` = CC BY-SA 4.0, dieselbe wie
    die eigenen Aufnahmen (ein Test hält Dialog, Galerie und Bot
    zusammen); Urheber ist der Benutzername, festgehalten im Issue zum
    Zeitpunkt der Meldung. Übernommen wird weiter nur nach Ansicht.
    **Art-Hinweise laden in Galerie-Größe hoch** (seit 1.199.0, Patch
    035): 2048er Kante, Qualität 85 (`prepareGalleryPhoto`,
    `galleryPhotoPreparerProvider`), allgemeines Feedback bleibt bei
    1024. Die Galerie zeigt 1200x1200 im Quadrat, aus 4:3 mit 1024er
    Kante blieben 768 px. Bei einem fremden Melder ist das Hochgeladene
    die EINZIGE Kopie — der Austauschordner ist nur der Weg des
    Betreibers. Gemessen an elf Pixel-Fotos: 581–1186 KB, deshalb
    Bucket-Grenze 2 MB statt 600 KB. Freigegebene Bilder innerhalb der
    90 Tage mit `tool/feedback_photos.py` abholen, danach sind sie weg.

- **Fundstellen weit vom Spot** (#475, seit 1.156.0): Ab 100 m
  (`kFindFixMaxOffsetM`, dieselbe Grenze wie der Riegel beim Eintragen)
  trägt der eigene Spot ein „!"-Abzeichen (im selben Kreis wie Uhr und
  Fragezeichen — kein Dreieck, kein Pilz-Glyph), das Blatt nennt die Stellen,
  „So gewollt" bestätigt. Vier Dinge, die man wissen muss:
  - **Abgeleitet, nicht gespeichert** (`driftingFinds` in
    `find_offset.dart`). Gespeichert ist nur die Bestätigung, und die
    hängt als ZEITPUNKT am Spot (`spots.offset_confirmed_at`, Patch
    024): Warnung, solange eine abweichende Fundstelle jünger ist als
    die Bestätigung. Ein Flag je Fund ginge nicht — den Fund eines
    Buddys darf der Besitzer per RLS nicht schreiben, die Warnung stünde
    für immer.
  - **Verlegen fragt.** Spot mit eigenen Fundstellen: „Nur den Spot"
    (Bestätigung wird gelöscht, eine neue Abweichung fällt wieder auf)
    oder „Spot und alle Fundstellen" (`pinFindsToSpot`: eigene Position
    der Funde wird GELÖSCHT, keine erfundene Koordinate — gemessene
    Stellen gehen verloren, der Dialog sagt es). Fundstelle verlegt:
    „Spot mitverschieben?", Vorgabe Nein.
  - **Fremde Fundstellen bleiben immer**, wo sie sind (RLS
    `finds_author_all`); kein RPC, keine Security-Definer-Funktion.
    Zwei Schreibvorgänge statt einer Transaktion — bricht der zweite ab,
    ist der Spot verlegt und die Warnung zeigt genau das.
  - **Gemessen vor dem Bau** (2026-09-21, Kommentar in #475): 9 von 166
    Funden hatten eine eigene Position, alle innerhalb 20 m. Der
    Hinweis ist eine Vorsorge für #473, kein Befund.

- **Spot an eine Navi-App übergeben** (`lib/features/spots/spot_navigation.dart`,
  #367, seit 1.112.0): Ein Knopf im Spot-Blatt reicht die Koordinate als
  `geo:`-URI an Android weiter; welche App sie bekommt, entscheidet der
  System-Wähler. Drei Dinge, die man wissen muss:
  - **Ein zweiter `<queries>`-Eintrag, diesmal VIEW/geo.** Ohne ihn sieht
    die App ab Android 11 keinen Empfänger, der Wähler bleibt aus, und der
    Knopf fällt still auf die Zwischenablage zurück — ein Fehler, der wie
    eine Entscheidung aussieht. `test/android_manifest_test.dart` prüft
    ihn gegen `kGeoScheme` aus dem Dart-Code, wie beim MethodChannel-Namen.
  - **Kein `https://…/maps?q=…` als Rückfallweg**, so naheliegend er ist:
    Das wäre ein fester Empfänger statt der freien Wahl, ein neues
    Netzziel für Datenschutzerklärung und `docs/play-console.md` — und im
    Funkloch tot. Genau dort steht man, wenn man den Knopf drückt. Der
    Rückfall ist deshalb die Zwischenablage, und die App sagt es.
  - **Die Koordinate steht ZWEIMAL im URI** (`geo:<lat>,<lng>?q=<lat>,<lng>(<name>)`).
    Apps, die `q` auswerten, setzen darüber Pin und Titel; Apps, die es
    ignorieren, zentrieren auf den Pfad. Die verbreitete Kurzform
    `geo:0,0?q=…` schickt die zweite Gruppe in den Golf von Guinea.
  Für Data Safety ist das **keine Weitergabe**: nutzerinitiiert, mit dem
  Wähler als Bestätigung — dieselbe Ausnahme wie „Freunde sehen meine
  Spots", nachgeschrieben in Fußnote ¹ von `docs/play-console.md`.

