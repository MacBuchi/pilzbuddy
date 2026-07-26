# Datenschutz — Verfahren und Nachweise

Ergänzt `web/datenschutz.html` (die Erklärung für Nutzer) um das, was der
Betreiber braucht: wer welche Daten im Auftrag verarbeitet, wann Mails
rausgehen und wie eine Auskunftsanfrage beantwortet wird.

Teil von Issue #110 (DSGVO-Epic). Diese Datei deckt die **mailbezogenen**
Punkte ab; Impressum, Verarbeitungsverzeichnis nach Art. 30, der
Haftungshinweis in der App und die Prüfung der übrigen Datenflüsse bleiben
dort offen.

Stand: 26. Juli 2026.

## Auftragsverarbeiter

| Wer | Wofür | Serverstandort | AV-Vertrag |
|---|---|---|---|
| **Supabase** | Konto (`auth.users`), Spots, Freundschaften, Fehlerberichte | EU | Über die Supabase-Nutzungsbedingungen (DPA); im Dashboard unter Organization → Legal einsehbar |
| **Brevo** (Sendinblue GmbH) | Zustellung der Konto-Mails; erhält nur die E-Mail-Adresse | EU | Brevos AVV, Bestandteil der Nutzungsbedingungen |
| **GitHub** | Hosting der Web-App und der Rechtsseiten (GitHub Pages), Feedback-Issues, Release-Downloads | USA (Standardvertragsklauseln) | GitHub DPA |

Feedback ist kein Auftragsverarbeitungs-, sondern ein Veröffentlichungsfall:
Der Text wird mit Benutzernamen zu einem **öffentlichen** GitHub-Issue. Das
steht im Absende-Dialog, in der Datenschutzerklärung und auf der Löschseite.

## Wann PilzBuddy Mails verschickt

Es gibt genau zwei Anlässe, beide vom Nutzer ausgelöst, beide über Brevo:

1. **Bestätigung der Adresse bei der Registrierung** — enthält einen
   sechsstelligen Code, keinen Link (Begründung in `CLAUDE.md`).
2. **Passwort vergessen** — derselbe Aufbau, anderer Code-Typ.

Kein Newsletter, keine Werbung, keine Benachrichtigungen. Die vier übrigen
Mail-Vorlagen im Supabase-Dashboard sind bewusst unangetastet, weil die App
sie nicht auslöst.

Der Passwortwechsel für Angemeldete (Issue #127) verschickt **keine** Mail —
er läuft über eine erneute Anmeldung mit dem aktuellen Passwort.

## Auskunft nach Art. 15 DSGVO

Anfragen kommen an `pilzbuddy@proton.me` (Adresse aus der
Datenschutzerklärung). Vorgehen:

1. **Identität prüfen.** Die Anfrage muss von der Adresse kommen, die am
   Konto hängt. Kommt sie von einer anderen, ist die Antwort eine Bitte um
   Bestätigung über die Konto-Adresse — nicht die Datenherausgabe.
2. **Export ziehen** (SQL-Editor im Supabase-Dashboard, `<uid>` ist die id
   aus `auth.users`):

   ```sql
   select to_jsonb(u) - 'encrypted_password' as konto
     from auth.users u where u.id = '<uid>';
   select * from public.profiles     where id = '<uid>';
   select * from public.spots        where owner_id = '<uid>';
   select * from public.finds
     where spot_id in (select id from public.spots where owner_id = '<uid>');
   select * from public.friendships
     where requester_id = '<uid>' or addressee_id = '<uid>';
   select * from public.live_locations where user_id = '<uid>';
   select * from public.feedback       where user_id = '<uid>';
   select * from public.error_reports  where user_id = '<uid>';
   ```

3. **Als JSON antworten**, zusammen mit dem Hinweis auf die Zwecke und
   Empfänger (diese Datei plus `web/datenschutz.html` decken das ab).
4. **Frist:** ein Monat ab Eingang.

Löschung nach Art. 17 braucht keinen Sonderweg: „Konto löschen" in der App
oder über `web/konto-loeschen.html` entfernt alles per Kaskade. Was danach
bleibt, ist ausschließlich veröffentlichtes Feedback — das sagt die
Löschseite ausdrücklich.

## Aufbewahrung

| Daten | Dauer |
|---|---|
| Konto, Profil, Spots, Funde, Freundschaften | Bis zur Löschung durch den Nutzer |
| Live-Standort | Läuft nach der gewählten Dauer von selbst ab |
| `error_reports` | 90 Tage, danach automatisch bereinigt (Feedback-Bot-Cron) |
| Feedback als GitHub-Issue | Dauerhaft und öffentlich — nicht zurückholbar |
| Datenbank-Backups | Die letzten 12 Läufe, verschlüsselt im privaten Repo |
