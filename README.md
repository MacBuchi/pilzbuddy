# 🍄 PilzBuddy

Pilz-Fundorte („Spots") auf einer Karte festhalten, Wiederbesuche mit zwei Taps
eintragen und Spots mit Freunden teilen.

**Plattformen:** Android (ab Android 6 / API 23) und Web (PWA)
**Technik:** Flutter · OpenStreetMap (`flutter_map`) · Supabase (Auth + PostgreSQL) · Riverpod

## Funktionen

- **Karte:** Karte gedrückt halten → neuer Spot (Art, Anzahl, Funddatum, Notiz optional).
  Alternativ „Spot hier" für die aktuelle GPS-Position.
- **Wiederbesuch:** Marker antippen → „Fund eintragen" → Speichern.
  Art und Anzahl sind vom letzten Fund vorbelegt.
- **Freunde:** Suche per Benutzername oder genauer E-Mail, Anfrage → Annahme.
  Freundes-Spots erscheinen blau auf der Karte.
- **Live-Standort teilen:** Auf der Karte den Teilen-Button tippen → 1, 2 oder
  4 Stunden. Freunde sehen dich für die gewählte Dauer als Buddy-Avatar live auf
  ihrer Karte; die Freigabe läuft automatisch ab und lässt sich jederzeit beenden.
- **Teilen-Einstellungen** (im Profil):
  - „Meine Spots mit Freunden teilen" (globaler Standard)
  - „Auch Art, Anzahl und Funddatum teilen" — sonst nur der Standort
  - einzelne Spots lassen sich im Spot-Detail von der Freigabe ausschließen
- **Statistik:** Spots, Funde, mehrfach besuchte Spots, Funde pro Jahr,
  Top-Arten, Jahreszeiten-Verteilung.

Alle Freigabe-Regeln werden serverseitig per Row-Level Security erzwungen
(`supabase/schema.sql`) — der Client kann sie nicht umgehen.

## Entwicklung

```bash
flutter pub get

# Web (fester Port, damit die Supabase-Redirect-URL stimmt)
flutter run -d chrome --web-port 3000

# Android (Gerät/Emulator mit `flutter devices` finden)
flutter run -d <device-id>
```

## Supabase-Setup (einmalig)

1. Projekt auf [supabase.com](https://supabase.com) anlegen
2. `supabase/schema.sql` im SQL-Editor ausführen (bei Bestandsprojekten
   zusätzlich vorhandene `patch_*.sql` in Nummernreihenfolge)
3. Authentication → Sign In / Providers → Email: **„Confirm email" ausschalten**
   (für die Entwicklung; später mit konfigurierten Redirect-URLs wieder aktivierbar)
4. Project-URL + Publishable Key in `lib/core/supabase_config.dart` eintragen
   (der Publishable Key ist öffentlich; die Sicherheit liegt in den RLS-Policies)

## Mitmachen & Release-Prozess

Kein direkter Push auf `main` — Änderungen laufen so:

1. Feature-Branch von `main` (`feat/<thema>` oder `fix/<thema>`)
2. Pull Request öffnen; Commit-/PR-Titel im Conventional-Commits-Stil
   (`feat:`, `fix:`, `chore:`, `ci:`, `docs:`, `test:`, `refactor:`)
3. CI muss grün sein (Analyze & Test, Build Web, Build Android APK, Version Guard,
   Schema Check)
4. Squash-Merge

**Release:** Die Version in `pubspec.yaml` ist die einzige Quelle der Wahrheit
(`version: x.y.z+buildNr` — bei jedem Bump beide Teile erhöhen). Landet ein
Versions-Bump auf `main`, taggt der Release-Workflow automatisch `vx.y.z`,
baut die **signierte** APK, hängt sie an ein GitHub-Release und deployt die
Web-App auf GitHub Pages. Kein Bump = kein Release (der Version Guard warnt
im PR daran zu denken).

Die APK ist mit dem PilzBuddy-Release-Key signiert — Updates lassen sich
direkt über die alte Version installieren. Keystore-Sicherung liegt außerhalb
des Repos (`~/pilzbuddy-keys/`); CI bezieht ihn aus den Repo-Secrets
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`,
`ANDROID_KEY_ALIAS`.

Lokale Release-Builds:

```bash
flutter build web --release     # Ergebnis in build/web
flutter build apk --release     # signiert, wenn android/key.properties existiert
```

Hinweis: Das Supabase-Free-Tier pausiert Projekte nach ca. einer Woche ohne
Zugriffe — im Dashboard lässt sich das Projekt mit einem Klick reaktivieren.
