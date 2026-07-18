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

## Release-Builds

```bash
flutter build web --release     # Ergebnis in build/web
flutter build apk --release     # Ergebnis in build/app/outputs/flutter-apk
```

Hinweis: Das Supabase-Free-Tier pausiert Projekte nach ca. einer Woche ohne
Zugriffe — im Dashboard lässt sich das Projekt mit einem Klick reaktivieren.
