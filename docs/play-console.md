# Play Console — Ausfüllhilfe

Vorlage für das **Data-Safety-Formular** und das **Store-Listing** (Issue #91).
Die Angaben sind aus `supabase/schema.sql`, `android/app/src/main/AndroidManifest.xml`
und den tatsächlich aufgerufenen Endpunkten abgeleitet — nicht aus einer Vorlage.

> **Warum das hier steht und nicht nur in der Konsole:** Google lehnt ab, wenn
> Formular und Binary auseinanderlaufen. Ändert sich die App, muss diese Datei
> mitwandern — dann sieht man beim Review des PRs, dass die Konsole nachzuziehen ist.

Stand: 26. Juli 2026, App-Version 1.32.0+68.

---

## 1. Datensicherheit (Data safety)

### Vorfragen

| Frage | Antwort | Begründung |
|---|---|---|
| Erhebt oder teilt deine App die geforderten Nutzerdatentypen? | **Ja** | Konto, Spots, Fehlerberichte |
| Werden alle Daten bei der Übertragung verschlüsselt? | **Ja** | Alle Endpunkte sind HTTPS: Supabase, `tile.openstreetmap.org`, `github.com`, `api.github.com`, `macbuchi.github.io`, `maps.dwd.de`. Kein einziges `http://` im Code. Die Bestätigungs- und Reset-Mails verschickt Supabase serverseitig über Brevo — die App selbst spricht nie mit dem Mail-Anbieter, die Liste bleibt also vollständig |
| Können Nutzer die Löschung ihrer Daten beantragen? | **Ja** | In-App unter *Profil → Konto löschen* (`delete_own_account()`, sofort, ohne Karenzzeit) **und** ohne installierte App über die URL unten |
| URL zum Löschen des Kontos | `https://macbuchi.github.io/pilzbuddy/konto-loeschen.html` | |
| Unabhängige Sicherheitsüberprüfung? | **Nein** | |
| Enthält die App Werbung? | **Nein** | Keine Werbe- oder Analyse-SDKs in `pubspec.yaml` |

### Datentypen

Für jeden Typ fragt die Konsole vier Dinge: *erhoben*, *geteilt*, *nur kurzzeitig
verarbeitet*, *erforderlich oder optional* — plus die Zwecke.

| Datentyp | Erhoben | Geteilt | Pflicht? | Zweck | Woher |
|---|---|---|---|---|---|
| **Standort → Genauer Standort** | Ja | Nein¹ | Optional | App-Funktionalität | `spots.lat/lng`, `live_locations` |
| **Standort → Ungefährer Standort** | Ja | Nein¹ | Optional | App-Funktionalität | `ACCESS_COARSE_LOCATION` ist deklariert; ein grober Fix wird genauso gespeichert |
| **Persönliche Infos → E-Mail-Adresse** | Ja | Nein³ | Erforderlich | App-Funktionalität, Kontoverwaltung | Supabase Auth; zusätzlich Freundessuche über die exakte Adresse; Versand der Bestätigungs- und Reset-Mails über Brevo |
| **Persönliche Infos → Name** | Ja | Nein¹ | Erforderlich | App-Funktionalität, Kontoverwaltung | `profiles.username` (nicht null) und `display_name`; der Benutzername ist für alle Nutzer suchbar |
| **Persönliche Infos → Nutzer-IDs** | Ja | Nein | Erforderlich | App-Funktionalität, Kontoverwaltung | `profiles.id` (UUID aus `auth.users`) |
| **App-Aktivität → Andere nutzergenerierte Inhalte** | Ja | **Ja²** | Optional | App-Funktionalität, Entwicklerkommunikation | Spot-Name, Art, Notiz (`spots`, `finds`) und Feedback-Text (`feedback`) |
| **App-Info und -Leistung → Absturzprotokolle** | Ja | Nein | Erforderlich | App-Funktionalität | `error_reports`: Fehlertyp, Meldung, Stacktrace, App-Version, Plattform |
| **Geräte- oder andere IDs** | Ja⁴ | **Ja⁴** | Optional | App-Funktionalität | `push_devices.token` — die FCM-Gerätekennung, sobald jemand Benachrichtigungen einschaltet |

**Ausdrücklich NICHT erhoben** — im Formular alles andere leer lassen:
Fotos/Videos, Audio, Kontakte, Kalender, Finanzdaten, Gesundheits-/Fitnessdaten,
SMS/E-Mail-Inhalte, Web-Browsing-Verlauf, installierte Apps. **Keine
Advertising-ID** — `error_reports` speichert nur `platform`, also
„android"/„web". GPX-Import und -Export laufen lokal auf dem Gerät; es werden
dabei keine Dateien hochgeladen.

Bis #277 stand hier auch „Geräte- oder andere IDs". Das gilt nicht mehr: Ein
FCM-Token IST eine Gerätekennung, und sie geht an Google. Die Zeile ist deshalb
in die Tabelle gewandert — wer Push wieder ausbaut, holt sie hierher zurück.

**Kurzzeitige Verarbeitung („processed ephemerally"):** bei allen Typen **nein**
— alles wird in PostgreSQL gespeichert.

### Die drei Ermessensfragen — hier lohnt der zweite Blick

**¹ Zählt „Freunde sehen meine Spots" als *geteilt*?**
Empfehlung: **nein**. Google meint mit *geteilt* die Weitergabe an einen Dritten;
nutzerinitiierte Übertragungen, bei denen der Nutzer die Weitergabe selbst
auslöst und darüber informiert wird, sind ausgenommen. Genau das ist es hier:
die Freigabe passiert nur nach angenommener Freundschaftsanfrage, ist pro Spot
und global abschaltbar, und der Live-Standort läuft von selbst ab. Trotzdem muss
es in der Beschreibung und in der Datenschutzerklärung stehen — beides ist der
Fall. Dasselbe gilt für Funde, die man selbst an geteilten Spots von Freunden
einträgt (seit 1.54.0): sichtbar nur für den Eintrager und den Spot-Besitzer,
nie für Dritte — die Freundesgruppe verlässt auch das nicht.

**² Feedback landet öffentlich auf GitHub — *geteilt*.**
Empfehlung: **ja, als geteilt deklarieren.** Der Feedback-Bot macht daraus
öffentliche Issues samt Benutzername, außerhalb der Kontrolle des Nutzers und
unwiderruflich. Das ist eine Weitergabe an einen Dritten (GitHub), auch wenn der
Nutzer sie auslöst. Der Absende-Dialog, die Datenschutzerklärung und die
Löschseite sagen es; das Formular sollte es auch sagen. Untertreiben ist hier
das teurere Risiko.

**³ Der Mailversand über Brevo — *geteilt*?**
Empfehlung: **nein**. Brevo ist Auftragsverarbeiter für genau zwei Zwecke:
die Bestätigungsmail bei der Registrierung zustellen und die Reset-Mail, die
der Nutzer selbst angefordert hat. Google nimmt Dienstanbieter, die Daten nur
im Auftrag und für diesen Zweck verarbeiten, ausdrücklich von *geteilt* aus —
anders als Fußnote 2, wo der Inhalt öffentlich und dauerhaft sichtbar wird.
Übermittelt wird nur die E-Mail-Adresse, nie Spots oder Standorte, und nur auf
Auslösung durch den Nutzer: Beide Mails folgen einer Handlung, die er selbst
angestoßen hat (Konto anlegen bzw. Passwort zurücksetzen). In der
Datenschutzerklärung ist Brevo als Auftragsverarbeiter benannt — das ist die
Bedingung dafür, diese Antwort zu geben.

Weiterhin **nicht** erhoben: E-Mail-*Inhalte*. Die App liest keine Mails; sie
schickt nur den Anlass und liest den Code, den der Nutzer abtippt.

**⁴ Das FCM-Token — erhoben UND geteilt (#277).**
Hier lautet die Antwort anders als bei den Fußnoten davor, und zwar **ja** in
beiden Spalten. Ein FCM-Token ist eine Gerätekennung, es entsteht bei Google,
und ohne Weitergabe an Google kann keine Meldung zugestellt werden — das ist
kein Nebeneffekt, sondern der Zweck. Es hilft nicht, sich auf die
Auftragsverarbeiter-Ausnahme zu berufen: Google ist hier nicht nur
Zustelldienst, sondern erzeugt die Kennung selbst.

Was die Einordnung dagegen trägt: **Optional**. Benachrichtigungen sind ab Werk
aus, es gibt einen Schalter im Profil, und Ausschalten löscht die Zeile in
`push_devices`. Und der Inhalt bleibt unverfänglich — eine Meldung enthält
**nie Koordinaten und nie Spot-Namen**, nur einen allgemeinen Hinweis; die
Einzelheiten holt die App erst beim Öffnen. Genau dieser Satz steht auch in der
Datenschutzerklärung und wird dort von einem Test festgehalten.

**Die Regenebene (`maps.dwd.de`) ändert an all dem nichts.** Sie holt ein
**festes** Bild über Deutschland bzw. den Alpenraum — dieselbe Anfrage bei
jedem Nutzer, unabhängig davon, wo er steht oder hinschaut. Weder Standort
noch Kartenausschnitt gehen an den DWD; übertragen wird technisch nur die
IP-Adresse, wie bei den OSM-Kacheln. Genau deshalb ist der Ausschnitt fest
und wandert nicht mit der Karte mit — die Alternative hätte bei jedem
Verschieben verraten, in welcher Gegend jemand sucht, und das ist bei einer
App für geheime Fundstellen der falsche Handel. Der Abruf läuft nur, solange
die Ebene eingeschaltet ist; Vorgabe ist aus.

### Berechtigungen im Build

Die gebaute APK deklariert **elf** Android-Berechtigungen (plus die
app-eigene `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`, die Android selbst
erzeugt). Nachprüfbar mit:

```bash
aapt2 dump badging build/app/outputs/flutter-apk/app-release.apk | grep uses-permission
```

| Berechtigung | Wofür | Herkunft |
|---|---|---|
| `INTERNET` | Supabase, Kartenkacheln, Update-Check | Manifest |
| `ACCESS_FINE_LOCATION` | eigene Position, „Spot hier", Live-Standort | Manifest |
| `ACCESS_COARSE_LOCATION` | dasselbe, grob | Manifest |
| `FOREGROUND_SERVICE` | Karten-Download hält den Prozess wach | Manifest |
| `FOREGROUND_SERVICE_DATA_SYNC` | Typ des Dienstes (ab Android 14 Pflicht) | Manifest |
| `POST_NOTIFICATIONS` | Fortschrittsmeldung des Downloads | Manifest |
| `ACCESS_NETWORK_STATE` | Verbindungsstatus (Auto-Offline) | `connectivity_plus` |
| `WAKE_LOCK` | Download über den Bildschirm-Timeout hinaus | `flutter_foreground_task` |
| `ACCESS_WIFI_STATE` | Verbindungsart (Auto-Offline) | `connectivity_plus` |
| `com.google.android.c2dm.permission.RECEIVE` | Push-Nachrichten entgegennehmen | `firebase_messaging` |
| `REQUEST_INSTALL_PACKAGES` | Update der GitHub-APK in der App | Manifest — **nur im `github`-Flavor, siehe unten** |

`POST_NOTIFICATIONS` deckt seit #277 beides ab: die Fortschrittsmeldung des
Downloads UND die Push-Benachrichtigungen. Sie stand schon vorher im Manifest
(`flutter_foreground_task`), Push hat also **keine neue** Berechtigung
gebracht — nur die c2dm-Zeile, die keine Laufzeit-Abfrage auslöst und in der
Berechtigungsliste des Play Store nicht auftaucht.

**Kein Hintergrund-Standort** (`ACCESS_BACKGROUND_LOCATION` fehlt bewusst),
und `RECEIVE_BOOT_COMPLETED` wird per `tools:node="remove"` wieder
**entfernt** — `flutter_foreground_task` bringt es für einen Autostart mit,
den die App nicht nutzt. Seit #277 will auch `firebase_messaging` sie haben;
am gemergten Manifest nachgesehen (2026-08-11) hält die Entfernung auch
dagegen. Ob dadurch eine Meldung verloren geht, die während eines Neustarts
eintrifft, ist **am Gerät noch nicht geprüft** — die Zustellung selbst
übernimmt Google Play services, nicht die App. `test/android_manifest_test.dart` wacht darüber,
dass `INSTALL_PACKAGES` und die Speicher-Berechtigungen nicht
zurückkommen (Lehre aus #88).

#### `REQUEST_INSTALL_PACKAGES` gehört nicht ins AAB — erledigt seit 1.87.1

Der In-App-Updater ist seit #161 wieder da, weil der Browser-Umweg im Alltag
zu umständlich war — er betrifft aber ausschließlich die **GitHub-APK**.
Play verbietet Selbst-Updates („Device and Network Abuse").

Der Dart-Pfad war im Play-Build schon vorher vollständig aus
(`AppDistribution.showsUpdateHints`, gesetzt über
`--dart-define=PLAY_BUILD=true`): kein Update-Check, kein Banner, kein
Dialog. **Die Manifest-Zeile blieb davon aber unberührt** und lag im
gebauten AAB — Play fragt danach, und eine Berechtigung ohne zugehörige
Funktion ist die schlechtestmögliche Antwort.

Seit 1.87.1 trennen zwei Produkt-Flavors die Wege:

| | `github` | `play` |
|---|---|---|
| Artefakt | APK am Release | AAB (Artefakt `android-aab`) |
| `REQUEST_INSTALL_PACKAGES` | ja | per `tools:node="remove"` entfernt |
| `PLAY_BUILD` | nicht gesetzt | `true` |
| Update-Weg | GitHub-Release | Play Store |

Drei Dinge, die dabei zusammengehören:

- **Beide tragen dieselbe `applicationId`**, bewusst ohne
  `applicationIdSuffix`. Ein Suffix machte daraus für Android zwei Apps —
  sie ständen nebeneinander auf dem Gerät, und der Wechsel verlöre die
  Installation. Der Signaturwechsel durch Play App Signing verlangt ohnehin
  schon ein Deinstallieren; ein zweiter Grund muss nicht dazukommen.
- **Flavor und `PLAY_BUILD` sind zwei Hälften derselben Entscheidung** —
  das Flag schaltet den Dart-Pfad ab, der Flavor die Berechtigung. Wer nur
  eine setzt, liefert eine halb abgeschaltete Funktion aus.
- **Der Flavor steht im Ausgabepfad** (`app-github-release.apk`,
  `bundle/playRelease/app-play-release.aab`). Ein `cp` auf den alten,
  flavorlosen Namen bricht erst **nach** dem Taggen ab — und ein Tag ohne
  Release ist nur von Hand zu heilen. `test/release_build_test.dart` hält
  Aufruf und Pfad deshalb zusammen, `test/android_manifest_test.dart` das
  Play-Manifest.

Ab hier verlangt Flutter bei **jedem** Android-Build ein `--flavor`. Der
CI-Job „Build Android APK" baut deshalb den `play`-Flavor: `github` baut aus
`src/main` und damit exakt wie vorher, neu ist allein das Zusammenführen des
Play-Manifests — und das soll im PR auffallen, nicht im Release-Workflow.

### Prominent Disclosure für den Standort

**Nicht erforderlich**, und das ist kein Versehen:

- Die App fordert **keinen Hintergrund-Standort** an
  (`ACCESS_BACKGROUND_LOCATION` fehlt im Manifest — bewusst).
- Der Standort wird ausschließlich nach einer sichtbaren Nutzeraktion abgefragt
  (`_currentPosition()` in `lib/features/map/map_screen.dart`, ausgelöst von
  „Auf mich zentrieren", „Spot hier" oder dem Live-Standort-Teilen).
- Ohne Berechtigung läuft die App weiter; Spots entstehen dann über das
  Fadenkreuz.

Falls die Konsole beim Review trotzdem danach fragt: dieser Absatz ist die
Antwort.

---

## 2. Store-Listing

### Angaben

| Feld | Wert |
|---|---|
| App-Name | PilzBuddy |
| Paketname | `de.mcbuchi.pilzbuddy` |
| Kategorie | Reisen & Lokales (Alternative: Lifestyle) |
| Tags | Karte, Natur, Sammeln |
| Kontakt-E-Mail | `pilzbuddy@proton.me` (dieselbe wie in der Datenschutzerklärung) |
| Website | `https://macbuchi.github.io/pilzbuddy/` |
| Datenschutzerklärung | `https://macbuchi.github.io/pilzbuddy/datenschutz.html` |
| Enthält Werbung | Nein |
| In-App-Käufe | Nein |

### Kurzbeschreibung (max. 80 Zeichen)

```
Pilz-Fundorte auf der Karte merken, wiederfinden und mit Freunden teilen.
```

(72 Zeichen)

### Vollständige Beschreibung (Entwurf, max. 4000 Zeichen)

```
PilzBuddy merkt sich, wo deine Pilze wachsen.

Ein guter Fundort ist im nächsten Jahr wieder einer — wenn man ihn wiederfindet.
PilzBuddy hält deine Spots auf einer Karte fest, sammelt die Funde dazu und
zeigt dir nach ein paar Saisons, was sich wann und wo lohnt.

KARTE
• Fadenkreuz auf die Stelle schieben, „Neuer Spot": Art, Anzahl,
  Funddatum, Notiz — auch mehrere Arten auf einmal.
• Oder „Spot hier" für deine aktuelle Position.
• Wiederbesuch mit zwei Taps — Art und Anzahl sind vom letzten Fund vorbelegt.

FREUNDE
• Freunde über Benutzername oder E-Mail finden, Anfrage senden, annehmen.
• Freundes-Spots erscheinen blau auf deiner Karte.
• Du entscheidest, was sichtbar ist: alle Spots oder keine, mit Art und Anzahl
  oder nur der Standort, und einzelne Spots lassen sich ausnehmen.
• Live-Standort für 1, 2 oder 4 Stunden teilen — praktisch, wenn ihr euch im
  Wald sucht. Die Freigabe läuft von selbst ab.

OFFLINE
• Bundesland-Karten herunterladen und im Funkloch weiterarbeiten.
• Kartendaten von OpenStreetMap.

STATISTIK
• Spots, Funde, Funde pro Jahr, Top-Arten, Verteilung über die Saison.
• Eigene Spots als GPX exportieren — deine Daten bleiben deine.

Kein Werbebanner, kein Tracking, keine In-App-Käufe. PilzBuddy ist ein privates
Projekt und finanziert sich nicht über deine Daten.

Hinweis: PilzBuddy bestimmt keine Pilze. Was in deinem Korb landet,
entscheidest du — sammle nur, was du sicher kennst.
```

**Nicht hineinschreiben:** Verweise auf APK-Downloads oder Selbst-Updates. Der
Play-Build hat den Update-Pfad über `--dart-define=PLAY_BUILD=true` abgeschaltet
(`AppDistribution.showsUpdateHints`), und Play verbietet solche Verweise.

### Grafiken

Alle Assets liegen fertig im Repo — beim Ausfüllen nur noch hochladen.
Erzeugen lassen sie sich neu nach `store/README.md`.

| Asset | Datei | Format |
|---|---|---|
| App-Icon | `store/icon-512.png` | 512 × 512 PNG, 32 Bit ✓ |
| Feature-Grafik | `store/feature-graphic.png` | 1024 × 500 PNG ✓ |
| Screenshots Telefon | `store/screenshots/01…05-*.png` | 5 × 1080 × 1920 (9:16) ✓ — Karte, Spot-Detail, Freunde, Statistik, Live-Standort |

Screenshots ohne echte Fundorte aufnehmen (Testkonto), sonst stehen die eigenen
Spots im Store.

### Inhaltsbewertung (IARC-Fragebogen)

Ehrlich antworten, sonst passt die Bewertung nicht zum Binary:

- Gewalt, Sexualität, Drogen, Glücksspiel: **nein**.
- **Können Nutzer miteinander interagieren oder Inhalte austauschen?** **Ja** —
  Freundschaften, geteilte Spots, Feedback.
- **Können Nutzer ihren Standort mit anderen teilen?** **Ja** — Live-Standort
  und Spot-Koordinaten für angenommene Freunde.
- Nutzergenerierte Inhalte werden nicht moderiert; Feedback wird öffentlich.

### Vor dem Upload

- [ ] AAB aus dem Release-Workflow (Artefakt `android-aab`), nicht die APK
- [ ] Build mit `--dart-define=PLAY_BUILD=true` (prüfen, dass der Update-Banner
      im Play-Build fehlt)
- [ ] Datenschutz-URL erreichbar (erst nach dem Pages-Deploy des Releases)
- [ ] Löschseite erreichbar
- [ ] Datensicherheits-Formular = diese Datei

## 3. AAB-Upload aus CI

Seit 1.91.0 lädt `release.yml` das AAB bei jedem Versions-Bump als
**Draft** in den internen Test-Track — sichtbar wird ein Stand erst,
wenn ihn jemand in der Console freigibt (dieselbe Trennung wie
Prerelease/`promote.yml`). Bis das Secret existiert, überspringt der
Schritt sichtbar mit Verweis hierher.

**Warum der erste Upload trotzdem Handarbeit ist:** Die
Play-Developer-API kann keine App-Einträge anlegen, und Play nimmt
API-Uploads für eine App erst an, nachdem einmal von Hand ein Bundle
hochgeladen wurde.

Einmalige Einrichtung, in dieser Reihenfolge:

1. App-Eintrag anlegen (Paketname `de.mcbuchi.pilzbuddy` — unveränderlich)
   und das erste AAB von Hand in den internen Test laden.
2. In der Google Cloud Console (Projekt frei wählbar, `pilzbuddy-app`
   liegt nahe) ein **Dienstkonto** anlegen und einen JSON-Schlüssel
   erzeugen. Keine Cloud-Rollen nötig — die Rechte kommen von Play.
3. Play Console → **Nutzer und Berechtigungen** → Nutzer einladen: die
   Dienstkonto-Mail, mit der Berechtigung **„Releases in Tests-Tracks
   verwalten"** für diese App. Mehr nicht — kein Produktions-Recht, kein
   Konto-Admin: CI soll Testern zuliefern, nicht veröffentlichen.
4. Den JSON-Inhalt als Repo-Secret **`PLAY_SERVICE_ACCOUNT_JSON`**
   hinterlegen.

Ab dann gilt: Bump ⇒ Draft im internen Track. Freigeben bleibt
Handarbeit in der Console — mit Absicht, wie bei `promote.yml`.

Wer hier landet, weil der Schritt **rot** ist statt übersprungen: Das
Secret existiert, aber der Schlüssel ist widerrufen, das Dienstkonto aus
der Console entfernt, oder der Paketname stimmt nicht mehr —
`test/android_manifest_test.dart` hält Letzteres mit dem Gradle-Stand
zusammen.
