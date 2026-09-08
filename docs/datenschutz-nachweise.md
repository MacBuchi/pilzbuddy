# Datenschutz: Nachweise und Verfahren

Was die Datenschutzerklärung (`web/datenschutz.html`) behauptet, steht
hier belegt — und die zwei Verfahren, die die DSGVO verlangt, aber
niemand im Code findet: Auskunft (Art. 15) und Verzeichnis (Art. 30).

Gehört zu Issue #110. **Ändert sich, was die App erhebt oder wohin sie
verbindet, gehört diese Datei in denselben PR** — wie
`docs/play-console.md`.

## Was automatisch geprüft wird — und was nicht

`test/privacy_policy_test.dart` geht den Weg RÜCKWÄRTS: Es prüft nicht
die Erklärung auf Vollständigkeit (das kann kein Test), sondern ob in
`lib/` oder `web/` ein Ziel auftaucht, das niemand eingeordnet hat.

Seit #110 sieht der Wächter auch `web/` an. Vorher nur Dart — und genau
daran ist ihm entgangen, dass `web/push/firebase-messaging-sw.js` das
Firebase-SDK von `www.gstatic.com` nachlädt. Die Web-Hülle IST Teil der
ausgelieferten App.

Vier Kategorien, und die Einordnung ist die eigentliche Entscheidung:

| Kategorie | Bedeutung | Muss in der Erklärung stehen |
|---|---|---|
| `fetched` | die App ruft von sich aus ab | ja |
| `afterConsent` | erst nach ausdrücklichem Einschalten | ja |
| `onTapOnly` | öffnet sich erst auf Tipp | nein |
| `textOnly` | reiner Text, nicht einmal tippbar | nein |

**Was kein Test leisten kann:** ob eine Aussage in der Erklärung WAHR
ist. Dafür ist diese Datei da.

## Nachgeprüfte Aussagen

Stand 2026-09-08, nachgesehen im Code, nicht angenommen.

| Aussage in der Erklärung | Beleg |
|---|---|
| Fehlerberichte werden nach 90 Tagen gelöscht | `tool/feedback_bot.py`, `ERROR_REPORT_RETENTION_DAYS`; läuft im 2-Stunden-Cron mit |
| Feedback wird öffentlich | `feedback_bot.py` legt daraus GitHub-Issues an — das Repo ist öffentlich |
| Live-Standort läuft von selbst ab | `live_locations.expires_at`, gespiegelt in der RLS-Policy und im Fake |
| Benachrichtigungen sind ab Werk aus | `push_devices` hat keine Zeile ohne Zustimmung; eine Zeile IST die Zustimmung |
| Die Pilztour verlässt das Gerät nie | `tours/` als JSON Lines im App-Verzeichnis; in beiden Backup-Ausschlüssen |
| Kein Tracking, keine Analyse-SDKs | Die einzige Firebase-Nutzung ist Cloud Messaging (`pubspec.yaml`: `firebase_core`, `firebase_messaging` — kein Analytics, kein Crashlytics) |
| Serverstandort EU | AWS `eu-west-1` (Irland), Supabase-Dashboard, bestätigt 2026-09-08 |
| Im Browser lädt Push einen Baustein von Google | `web/push/firebase-messaging-sw.js`; ausgelöst erst durch `getToken` in `requestPushToken` |

### Offen — nicht aus dem Code belegbar

- ~~Supabase-Serverstandort~~ — **geklärt am 2026-09-08** (Betreiber):
  Das Projekt liegt in der AWS-Region **eu-west-1** (Irland), also in der
  EU. Damit stimmt die Ortsangabe.

  Der frühere zweite Halbsatz („eine Übermittlung in ein Drittland findet
  nicht statt") ist daraufhin **gestrichen** worden: Er folgt nicht aus
  der Region. Supabase Inc. ist ein US-Unternehmen; Support-Zugriffe und
  Unterauftragnehmer sind genau der Fall, den er ausschloss. Die
  Erklärung nennt jetzt beides getrennt — wo die Daten liegen, und wer
  darauf zugreifen kann.

  **Noch zu tun:** Den Auftragsverarbeitungsvertrag samt
  Unterauftragnehmer-Liste bei Supabase abrufen und ablegen (Art. 28).
  Die Erklärung beruft sich darauf; abgeheftet ist er noch nicht.
- **Impressumspflicht (§ 5 DDG).** Bewusst offen (Betreiber, 2026-09-08).
  Dafür spricht: Die App liegt bald im Play Store, und die Abgrenzung
  „geschäftsmäßig" ist bei dauerhaft angebotenen Diensten weit ausgelegt.
  Dagegen: erklärtermaßen privates Projekt ohne Gewinnabsicht, keine
  Werbung, keine Käufe. Name und E-Mail stehen bereits im Abschnitt
  „Verantwortlicher". **Spätestens beim Play-Store-Eintrag entscheiden**,
  dort werden ohnehin Kontaktangaben verlangt.

## Auskunft nach Art. 15 — das Verfahren

Eine Anfrage kommt an `pilzbuddy@proton.me`. Es gibt bewusst keinen
Knopf dafür: Bei der Zahl der Nutzer ist ein Verfahren auf Papier
ehrlicher als eine Automatik, die selten läuft und darum kaputtgeht.

1. **Identität prüfen.** Nur über die E-Mail-Adresse des Kontos — sie ist
   bestätigt (seit 2026-07-26 Pflicht) und damit der einzige Beleg, den
   wir haben. Aus einer fremden Adresse wird nichts herausgegeben.
2. **Zusammenstellen**, im Supabase-Dashboard per SQL über die
   `user_id`: `profiles`, `spots` (mit `finds`), `friendships`,
   `live_locations`, `push_devices`, `feedback`, `error_reports`.
   Das sind alle Tabellen mit Personenbezug — der Abgleich gehört bei
   jedem neuen Patch wiederholt.
3. **Als JSON schicken**, innerhalb eines Monats (Art. 12 Abs. 3).
4. **Nicht enthalten und das sagen:** Was nur auf dem Gerät liegt
   (Pilztour, Zwischenspeicher, Einstellungen, Ausgangskorb) — dort
   kommen wir nicht heran, und der Nutzer hat es ohnehin.

**Löschung (Art. 17)** braucht kein Verfahren: Der Knopf im Profil
löscht `auth.users`, alles andere hängt per `on delete cascade` daran.
Öffentlich schon veröffentlichtes Feedback bleibt bestehen — das steht
so in der Erklärung.

## Verzeichnis nach Art. 30

| Zweck | Daten | Rechtsgrundlage | Empfänger | Dauer |
|---|---|---|---|---|
| Konto führen | E-Mail, Benutzername, Avatar | Art. 6 (1) b | Supabase | bis zur Löschung |
| Spots und Funde speichern | Koordinaten, Art, Anzahl, Datum, Notiz | Art. 6 (1) b | Supabase | bis zur Löschung |
| Mit Freunden teilen | wie oben, für bestätigte Freunde | Art. 6 (1) b | Supabase | bis zur Löschung |
| Live-Standort teilen | Koordinate, Ablaufzeit | Art. 6 (1) a | Supabase | selbst gewählte Dauer |
| Konto-Mails | E-Mail-Adresse | Art. 6 (1) b | Brevo | Versand |
| Benachrichtigungen | Gerätekennung (Token) | Art. 6 (1) a | Google (FCM) | bis zum Ausschalten |
| Fehlerdiagnose | Fehlertext, Stack, Version, Plattform | Art. 6 (1) f | Supabase | 90 Tage |
| Feedback | Text, Benutzername | Art. 6 (1) a | GitHub, öffentlich | dauerhaft |

Keine automatisierte Entscheidungsfindung, kein Profiling, keine
Werbung. Betroffene sind ausschließlich Nutzer der App.
