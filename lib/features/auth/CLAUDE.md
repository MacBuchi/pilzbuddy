# PilzBuddy — Arbeitsregeln für `lib/features/auth/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- Passwort ändern für Angemeldete (`AuthRepository.changePassword`, Dialog im
  Profil, Issue #127, seit 1.31.0): meldet sich zuerst mit dem **aktuellen**
  Passwort neu an (`signInWithPassword`) und ruft erst dann `updateUser` —
  wegen „Secure password change" scheitert `updateUser` allein mit 403. Wer
  den Zwischenschritt wegkürzt, merkt es nur live; deshalb prüft ihn
  `tool/auth_reset_check.sh` gegen echtes GoTrue. Nebeneffekt mit Absicht:
  Ein falsches aktuelles Passwort scheitert schon an der Anmeldung.
  Mitfahrbars `_AdminPasswordDialog` fragt das aktuelle Passwort NICHT ab —
  das geht dort nur, solange die Einstellung aus ist; beim nächsten Anfassen
  mitziehen.

- Passwort-Reset (`lib/features/auth/login_screen.dart`, drei Modi;
  `AuthRepository.sendPasswordResetCode` / `resetPasswordWithCode`): läuft
  über den **Zahlencode** aus der Mail (`verifyOTP` mit
  `OtpType.recovery`), nicht über deren Link. Grund: Im PKCE-Standardflow
  legt das SDK beim Anfordern einen „code verifier" im Speicher des
  anfragenden Geräts ab und verlangt ihn beim Einlösen wieder — wer in der
  App anfordert und die Mail im Browser öffnet, scheitert an
  „Code verifier could not be found in local storage.". Daraus folgen zwei
  Pflichten im Dashboard: eigenes SMTP (Brevo Free, der Standardversand
  liefert nur an Projekt-Mitglieder) und eine Reset-Mail-Vorlage, die
  `{{ .Token }}` zeigt und **keinen** Link enthält — bleibt der Link drin,
  existiert der kaputte Weg weiter. Der Router lässt eine
  `passwordRecovery`-Sitzung bewusst nicht in die App (`lib/core/router.dart`
  filtert das Ereignis), sonst läge die Karte mitten im Reset offen, bevor
  das neue Passwort gesetzt ist.
  Mitfahrbar löst denselben Fall über den Mail-Link und hat damit genau die
  Lücke, die PilzBuddy hier umgeht (dort `MacBuchi/MitFahrBar` Issue #102) —
  beim nächsten Anfassen dort gleich mitziehen.
  Von den sechs Mail-Vorlagen im Dashboard sind **drei** angepasst (deutsch,
  mit Code, im Stil von #192): „Reset password", „Confirm sign up" und seit
  #193 „Change email address" — genau die drei, die die App auslöst.
  „Magic link or OTP", „Invite user" und „Reauthentication" schlafen und
  stehen bewusst auf englischem Standardtext: Eine fertig aussehende
  Vorlage würde vortäuschen, das Feature existiere (Einladen läuft über
  das System-Teilen-Blatt, nicht über eine Server-Mail). Der Zahlencode kommt aus der jeweiligen Vorlage, NICHT aus
  „Magic link or OTP" — `/recover` bzw. `/signup` verschickt, `verifyOTP`
  prüft nur. „Confirm email" ist seit 2026-07-26 **an**; damit liefert
  `signUp` keine Sitzung mehr — `AuthRepository.signUp` gibt deshalb zurück,
  ob bestätigt werden muss, und der Registrieren-Screen zeigt dann die
  Code-Eingabe statt stumm stehenzubleiben (Issue #129, seit 1.31.0). Beide
  Wege haben ein „Erneut senden" mit 60-Sekunden-Sperre (`ResendButton`);
  im Reset meldet es bewusst immer dasselbe, ein Rate-Limit-Hinweis käme nur
  bei existierendem Konto und wäre damit ein Orakel. Bestätigt wird wie beim
  Reset über den **Code** aus der Mail (`verifyOTP` mit `OtpType.signup`),
  nicht über deren Link: `signUp` legt denselben PKCE-Verifier auf dem
  anfordernden Gerät ab, der Link wäre also wieder gerätegebunden.
  `verifyOTP` meldet direkt an, die Registrierung endet also auf der Karte.
  Warum überhaupt Pflicht: Freundessuche läuft über die exakte
  E-Mail-Adresse, und der Reset-Code geht an ein Postfach — beides
  verlässt sich darauf, dass die Adresse dem Konto gehört. Am 2026-07-25
  ist genau das passiert: eine Registrierung auf eine `+`-Alias-Adresse,
  die web.de nicht zustellt, hinterließ ein dauerhaft unrettbares Konto;
  solche Zustellversuche zählen bei Brevo zusätzlich als Hard Bounce
  gegen die Absender-Reputation.
  **Reihenfolge beim Umstellen im Dashboard** (am 2026-07-26 so gemacht,
  hier als Muster für den nächsten Schalter dieser Art): erst die App-Version
  ausliefern, die beide Einstellungen beherrscht, dann die Vorlage „Confirm
  sign up" auf `{{ .Token }}` ohne Link setzen, dann „Confirm email"
  anschalten. Andersherum bricht die Registrierung still.
  **Unverlangte Reset-Mails an das Play-Testkonto sind erwartbares
  Rauschen** (Befund 2026-08-17; die Adresse steht im DocuHub, `apps/pilzbuddy.md`): Die Adresse
  liegt als App-Zugriff in der Play Console, und Googles automatische
  Prüf-Robots klicken die App durch — auch „Passwort vergessen" auf dem
  Login-Screen (im Wochendigest als „Passwort-Reset anfordern" mit 429/
  504 sichtbar). Ohne Postfachzugriff ist das harmlos: Der Code geht nur
  dorthin, die Vorlage trägt die „nicht angefordert? nichts passiert"-
  Zeile. Geräte-/IP-Angaben in der Mail gehen NICHT — GoTrue reicht
  keine Request-Metadaten an Vorlagen (nur Token/URL/Email); üblich sind
  solche Angaben ohnehin in Anmelde-Benachrichtigungen, nicht in
  Reset-Mails. Der eine echte Hebel gegen Missbrauch: das Mail-Rate-
  Limit im Dashboard (Auth → Rate Limits) unter Brevos 300/Tag halten —
  **gesetzt auf 3/h am 2026-08-17** (≤ 72/Tag). Es gilt projektweit für
  ALLE Mail-Sorten, auch Registrierungs-Bestätigungen: Für eine
  Einladungs-Welle (12 Tester an einem Abend) vorher hochdrehen und
  danach zurück.
  E-Mail ändern (Issue #193, seit 1.52.0): `AuthRepository.changeEmail`
  meldet sich wie beim Passwortwechsel erst mit dem aktuellen Passwort neu
  an, dann verschickt `updateUser(email:)` ZWEI Mails mit je eigenem Code
  (alte und neue Adresse, „Secure email change"/`double_confirm_changes`).
  Der erste eingelöste Code wird nur quittiert, erst der zweite vollzieht
  den Wechsel und bringt eine frische Sitzung — die Profil-Kachel hört auf
  `authStateProvider`, sonst zeigt sie die alte Adresse weiter (am
  Emulator gefunden). Ein Postfach allein reicht also nie, und genau das
  prüft der Wächter mit.
  Geprüft werden die Flows von `tool/auth_reset_check.sh` im Job „Schema Dry
  Run" — gegen echtes GoTrue im lokalen Stack, inklusive Mailabholung aus
  Mailpit: Registrierung samt Bestätigung, Reset, Passwortwechsel und
  E-Mail-Wechsel (der Name des Skripts ist seit #127/#129/#193 zu eng).
  `supabase/config.toml` spiegelt dafür die Dashboard-Härtung
  (`[auth.email] secure_password_change = true`,
  `double_confirm_changes = true`), damit lokal nicht laxer
  geprüft wird als live; die Mail-Vorlagen liegen als versionierte Kopien
  unter `supabase/templates/`. **Blinder Fleck:** Die im Dashboard
  hinterlegte Vorlage sieht CI nie. Wer sie dort auf den Link zurückstellt,
  bricht „Passwort vergessen" oder den Adresswechsel in Produktion,
  während CI grün bleibt — Vorlagen also immer an beiden Stellen ändern.

