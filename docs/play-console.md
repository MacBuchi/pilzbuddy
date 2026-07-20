# Play Console — Ausfüllhilfe

Vorlage für das **Data-Safety-Formular** und das **Store-Listing** (Issue #91).
Die Angaben sind aus `supabase/schema.sql`, `android/app/src/main/AndroidManifest.xml`
und den tatsächlich aufgerufenen Endpunkten abgeleitet — nicht aus einer Vorlage.

> **Warum das hier steht und nicht nur in der Konsole:** Google lehnt ab, wenn
> Formular und Binary auseinanderlaufen. Ändert sich die App, muss diese Datei
> mitwandern — dann sieht man beim Review des PRs, dass die Konsole nachzuziehen ist.

Stand: 21. Juli 2026, App-Version 1.26.0+51.

---

## 1. Datensicherheit (Data safety)

### Vorfragen

| Frage | Antwort | Begründung |
|---|---|---|
| Erhebt oder teilt deine App die geforderten Nutzerdatentypen? | **Ja** | Konto, Spots, Fehlerberichte |
| Werden alle Daten bei der Übertragung verschlüsselt? | **Ja** | Alle Endpunkte sind HTTPS: Supabase, `tile.openstreetmap.org`, `github.com`, `api.github.com`, `macbuchi.github.io`. Kein einziges `http://` im Code |
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
| **Persönliche Infos → E-Mail-Adresse** | Ja | Nein | Erforderlich | App-Funktionalität, Kontoverwaltung | Supabase Auth; zusätzlich Freundessuche über die exakte Adresse |
| **Persönliche Infos → Name** | Ja | Nein¹ | Erforderlich | App-Funktionalität, Kontoverwaltung | `profiles.username` (nicht null) und `display_name`; der Benutzername ist für alle Nutzer suchbar |
| **Persönliche Infos → Nutzer-IDs** | Ja | Nein | Erforderlich | App-Funktionalität, Kontoverwaltung | `profiles.id` (UUID aus `auth.users`) |
| **App-Aktivität → Andere nutzergenerierte Inhalte** | Ja | **Ja²** | Optional | App-Funktionalität, Entwicklerkommunikation | Spot-Name, Art, Notiz (`spots`, `finds`) und Feedback-Text (`feedback`) |
| **App-Info und -Leistung → Absturzprotokolle** | Ja | Nein | Erforderlich | App-Funktionalität | `error_reports`: Fehlertyp, Meldung, Stacktrace, App-Version, Plattform |

**Ausdrücklich NICHT erhoben** — im Formular alles andere leer lassen:
Fotos/Videos, Audio, Kontakte, Kalender, Finanzdaten, Gesundheits-/Fitnessdaten,
SMS/E-Mail-Inhalte, Web-Browsing-Verlauf, installierte Apps, **Geräte- oder
andere IDs** (keine Advertising-ID, keine Geräte-Kennung — `error_reports`
speichert nur `platform`, also „android"/„web"). GPX-Import und -Export laufen
lokal auf dem Gerät; es werden dabei keine Dateien hochgeladen.

**Kurzzeitige Verarbeitung („processed ephemerally"):** bei allen Typen **nein**
— alles wird in PostgreSQL gespeichert.

### Die zwei Ermessensfragen — hier lohnt der zweite Blick

**¹ Zählt „Freunde sehen meine Spots" als *geteilt*?**
Empfehlung: **nein**. Google meint mit *geteilt* die Weitergabe an einen Dritten;
nutzerinitiierte Übertragungen, bei denen der Nutzer die Weitergabe selbst
auslöst und darüber informiert wird, sind ausgenommen. Genau das ist es hier:
die Freigabe passiert nur nach angenommener Freundschaftsanfrage, ist pro Spot
und global abschaltbar, und der Live-Standort läuft von selbst ab. Trotzdem muss
es in der Beschreibung und in der Datenschutzerklärung stehen — beides ist der
Fall.

**² Feedback landet öffentlich auf GitHub — *geteilt*.**
Empfehlung: **ja, als geteilt deklarieren.** Der Feedback-Bot macht daraus
öffentliche Issues samt Benutzername, außerhalb der Kontrolle des Nutzers und
unwiderruflich. Das ist eine Weitergabe an einen Dritten (GitHub), auch wenn der
Nutzer sie auslöst. Der Absende-Dialog, die Datenschutzerklärung und die
Löschseite sagen es; das Formular sollte es auch sagen. Untertreiben ist hier
das teurere Risiko.

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
| Paketname | `de.marcusbucher.pilzbuddy` |
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
• Karte gedrückt halten, Spot anlegen: Art, Anzahl, Funddatum, Notiz.
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

| Asset | Format | Status |
|---|---|---|
| App-Icon | 512 × 512 PNG, 32 Bit | aus `assets/` ableiten |
| Feature-Grafik | 1024 × 500 PNG/JPG | offen |
| Screenshots Telefon | mind. 2, 16:9 oder 9:16, Kante 320–3840 px | offen — Karte mit Spots, Spot-Detail, Freundesliste, Statistik |

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
