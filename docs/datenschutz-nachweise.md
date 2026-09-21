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
| Die Pilztour verlässt das Gerät nur bei laufender Standort-Freigabe | `tours/` als JSON Lines im App-Verzeichnis, in beiden Backup-Ausschlüssen. Hochgeladen wird ausschließlich, wenn BEIDES läuft — Tour und Standort-Freigabe (`planTrackShare` in `lib/features/tour/tour_sharing.dart`, geprüft in `test/flows/tour_sharing_flow_test.dart`). Die Frist wird aus der Freigabe geerbt, Sichtbarkeit über `tt_friend_select` (Patch 023); Tour- oder Teilen-Ende löscht die Zeile |
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

  **Nachgetragen am 2026-09-21:** Der Auftragsverarbeitungsvertrag ist
  nichts, was hier fehlen könnte — er gilt durch Annahme der
  Nutzungsbedingungen, und Klausel 12.2 stellt das der Unterschrift
  unter die Standardvertragsklauseln ausdrücklich gleich. Zu belegen
  ist die FASSUNG, nicht der Abschluss. Welche gilt, steht in der
  Verarbeiter-Tabelle in `docs/datenschutz-verfahren.md`, zusammen mit
  den drei Handgriffen, die daraus folgen.
- ~~Impressumspflicht (§ 5 DDG)~~ — **entschieden am 2026-09-21**
  (Betreiber): `web/impressum.html` mit voller Anschrift, verlinkt aus
  der Erklärung, aus der Lösch-Seite und als Zeile im Profil.

  Die Abwägung stand seit dem 2026-09-08 offen und ist so ausgegangen:
  Die Ausnahme „rein privat" trägt nicht. Gerichte werten die dauerhafte
  Verfügbarkeit im App Store regelmäßig als öffentliches Angebot, und
  „geschäftsmäßig" verlangt keine Gewinnabsicht — die Planmäßigkeit
  genügt. Kostenlose Apps sind ausdrücklich mitgemeint.

  **Was die Entscheidung wirklich gekostet hat, war nicht Arbeit,
  sondern die Adresse.** Eine naheliegende Annahme erwies sich beim
  Nachsehen als falsch: Play macht die Anschrift NICHT ohnehin
  öffentlich. Bei einem privaten Entwicklerkonto ohne Monetarisierung
  zeigt Google nur Name, Land und E-Mail; die volle Anschrift erst beim
  Monetarisieren. Das Impressum ist also eine echte zusätzliche
  Offenlegung — genau die Sorte, die der Paketnamen-Umzug auf
  `de.mcbuchi.pilzbuddy` vermeiden sollte. Ein Postfach wäre kein
  Ausweg gewesen (keine ladungsfähige Anschrift), ein c/o-Dienst hätte
  laufende Kosten bedeutet und damit die Null-Kosten-Zusage aus #92
  gebrochen.

  **Zwei Bausteine fehlen mit Absicht.** Kein Link auf die
  EU-Streitschlichtung — die OS-Plattform ist im Juli 2025 abgeschaltet
  worden, ein toter Pflichtlink täuscht Sorgfalt vor; ein Test
  verbietet ihn auf beiden Seiten. Und kein Verantwortlicher nach § 18
  Abs. 2 MStV, dafür bräuchte es journalistisch-redaktionelle Inhalte.

  **Der Sicherheitshinweis steht NICHT im Impressum.** „PilzBuddy
  bestimmt keine Pilze" lebt an einer Stelle (`safety_note.dart`) und
  wird von dort in Erststart-Dialog und Kurzanleitung gereicht. Eine
  zweite Fassung liefe auseinander, und bei einer Pilz-App ist das die
  teuerste Sorte Dopplung.

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
| Freundschaften verwalten | wer wen angefragt hat, Status, Zeitpunkt | Art. 6 (1) b | Supabase, die angefragte Person | bis eine Seite sie auflöst oder ihr Konto löscht |
| Freunde suchen | eingegebene E-Mail-Adresse oder Benutzername-Anfang; zurück kommen Benutzername, Anzeigename, Avatar | Art. 6 (1) b | Supabase | nicht gespeichert, nur im Moment der Abfrage |
| Live-Standort teilen | Koordinate, Ablaufzeit | Art. 6 (1) a | Supabase | selbst gewählte Dauer |
| Pilztour-Weg teilen | Wegpunkte der laufenden Tour: Koordinate und Zeitpunkt, gedünnt auf ≤ 400 | Art. 6 (1) a | Supabase, sichtbar für bestätigte Freunde | Frist der Standort-Freigabe; Tour- oder Teilen-Ende löscht sofort |
| Konto-Mails | E-Mail-Adresse | Art. 6 (1) b | Brevo | Versand |
| Benachrichtigungen | Gerätekennung (Token) | Art. 6 (1) a | Google (FCM) | bis zum Ausschalten |
| Vorhersage prüfen | Fund/Leergang mit Ort und Datum | Art. 6 (1) f | Supabase | bis zur Löschung |
| Fehlerdiagnose | Fehlertext, Stack, Version, Plattform | Art. 6 (1) f | Supabase | 90 Tage |
| Feedback | Text, Benutzername | Art. 6 (1) a | GitHub, öffentlich | dauerhaft |

Keine automatisierte Entscheidungsfindung, kein Profiling, keine
Werbung. Betroffene sind ausschließlich Nutzer der App.

**Warum der Tour-Weg eine eigene Zeile hat und nicht in der des
Live-Standorts steht.** Rechtsgrundlage und Frist sind dieselben — die
Frist wird sogar aus der Standort-Freigabe geerbt, es gibt nur eine
Zustimmung. Die Datenkategorie ist es nicht: Ein Live-Standort ist ein
Punkt, ein Tour-Weg ist ein Bewegungsprofil über Stunden. Ein
Verzeichnis, das beides in einer Zeile führt, benennt die eingreifendere
Verarbeitung nicht.

Zwei Eigenschaften gehören dazu, weil sie die Datenminimierung nach
Art. 5 (1) c belegen und aus der Zeile allein nicht hervorgehen. Der Weg
wird **vor** dem Hochladen gedünnt (`thinnedTrack`) — roh wären es bei
drei Stunden rund 720 Punkte, hochgeladen werden höchstens 400. Und die
gemeldete **Messgenauigkeit fährt bewusst nicht mit**
(`encodeTrackPoint`): Sie trägt auf dem eigenen Gerät die Auswertung der
Leergänge, für die Spur eines Buddys wird sie nirgends gebraucht.

**Die Freundessuche verarbeitet die Daten DRITTER**, nicht nur die des
Suchenden — deshalb die eigene Zeile. Zwei Eigenschaften begrenzen sie,
und beide stehen in `search_profiles` (Patch 011): Die E-Mail-Adresse
wird nur **exakt** verglichen und **nie zurückgegeben**; wer sie nicht
schon kennt, erfährt nichts. Beim Benutzernamen genügt der Anfang, und
das ist der Unterschied — ein Name ist ein selbst gewähltes öffentliches
Kennzeichen, eine Adresse nicht. Die Funktion ist `anon` entzogen: ohne
Anmeldung gibt es die Abfrage nicht, sonst wäre sie ein
E-Mail-Orakel.

**Nicht im Verzeichnis, weil keine personenbezogenen Daten:**
`app_config` — eine Zeile mit der Mindestversion, für alle gleich und
bewusst ohne Anmeldung lesbar, weil die Prüfung vor dem Login läuft.

**Was NICHT in diesem Verzeichnis steht, weil es das Gerät nie
verlässt:** die Tour selbst. Sie liegt als JSON Lines in `tours/` im
App-Verzeichnis, ist von beiden Backup-Ausschlüssen erfasst und wird nur
hochgeladen, solange Tour UND Standort-Freigabe laufen (`planTrackShare`
in `lib/features/tour/tour_sharing.dart`). Wer aufzeichnet, ohne zu
teilen, erzeugt hier keine Verarbeitung.
