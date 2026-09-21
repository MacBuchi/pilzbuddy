# Datenschutz — Verfahren und Nachweise

Ergänzt `web/datenschutz.html` (die Erklärung für Nutzer) um das, was der
Betreiber braucht: wer welche Daten im Auftrag verarbeitet, wann Mails
rausgehen und wie eine Auskunftsanfrage beantwortet wird.

Teil von Issue #110 (DSGVO-Epic). Impressum (#500),
Verarbeitungsverzeichnis nach Art. 30 (#502), Haftungshinweis in der App
und die Prüfung der Datenflüsse sind erledigt und stehen in
`docs/datenschutz-nachweise.md`.

Stand: 21. September 2026.

## Auftragsverarbeiter

| Wer | Wofür | Serverstandort | AV-Vertrag |
|---|---|---|---|
| **Supabase** | Konto (`auth.users`), Spots, Funde, Freundschaften, Standort- und Tourfreigaben, Fehlerberichte | AWS `eu-west-1` (Irland) | supabase.com/legal/dpa, Fassung 1 vom 2026-08-01. **Gilt durch Annahme der Nutzungsbedingungen** — Klausel 12.2 stellt das der Unterschrift unter die Standardvertragsklauseln ausdrücklich gleich |
| **Brevo** (Sendinblue GmbH) | Zustellung der Konto-Mails; erhält nur die E-Mail-Adresse | EU | Brevos AVV, Bestandteil der Nutzungsbedingungen |
| **GitHub** | Hosting der Web-App und der Rechtsseiten (GitHub Pages), Feedback-Issues, Release-Downloads | USA (Standardvertragsklauseln) | GitHub Data Protection Agreement, Bestandteil der Nutzungsbedingungen |
| **Google** (Firebase Cloud Messaging) | Zustellung der Benachrichtigungen; erhält die Gerätekennung (Token) | USA (Standardvertragsklauseln) | Firebase Data Processing and Security Terms, angenommen mit der Firebase-Nutzung |
| **Proton** (Proton AG) | Postfach `pilzbuddy@proton.me` — dort laufen Auskunftsersuchen und Löschbitten ein | Schweiz (Angemessenheitsbeschluss, keine Standardvertragsklauseln nötig) | proton.me/legal/dpa — siehe Vorbehalt unten |

**Google hat hier gefehlt, obwohl die Erklärung es längst nannte.** In
`web/datenschutz.html` steht seit #277 eine eigene Überschrift „Google
(Auftragsverarbeiter, Benachrichtigungen)", im Art.-30-Verzeichnis steht
es als Empfänger — nur diese Tabelle führte drei statt vier. Zwei
Unterlagen über denselben Sachverhalt, die sich widersprechen, sind
schlechter als eine.

**Das Postfach ist der wacklige Eintrag, und das steht hier statt es zu
glätten.** Proton veröffentlicht einen AVV, adressiert ihn aber an
Geschäfts- und Enterprise-Kunden; ob er ein kostenloses persönliches
Konto erfasst, ist daraus nicht zu entnehmen. Solange das so ist, gilt
für diesen einen Verarbeiter nur die veröffentlichte Fassung, nicht eine
geprüfte Zusage. Wer das sauber haben will, hat zwei Wege: ein
Proton-Business-Konto, oder das Postfach zu einem Anbieter mit
unstrittigem AVV. Beides kostet Geld und ist deshalb eine Entscheidung,
keine Aufgabe.

## Was für Art. 28 wirklich zu tun ist

Der offene Punkt in #110 war als „AV-Vertrag abrufen und ablegen"
notiert. Beim Nachsehen am 2026-09-21 stellte sich heraus, dass das die
falsche Vorstellung von der Sache war: **Es gibt nichts zu
unterschreiben.** Bei allen fünf Verarbeitern ist der AVV Bestandteil
der Nutzungsbedingungen; bei Supabase sagt Klausel 12.2 das sogar
wörtlich. Es gibt also keinen gegengezeichneten Vertrag, der irgendwo
fehlen könnte.

Was Rechenschaftspflicht nach Art. 5 (2) trotzdem verlangt, ist der
Nachweis, **welche Fassung** gilt. Daraus folgen drei Handgriffe, und
nur der dritte ist wiederkehrend:

1. Die AVV-Fassungen als PDF sichern, mit Datum im Dateinamen. Bei
   Supabase ist das Fassung 1 vom 2026-08-01.
2. Die Unterauftragnehmer-Liste sichern —
   supabase.com/legal/customer-resources/subprocessor-list, PDF vom
   2026-06-01.
3. **Auf derselben Seite die Änderungsbenachrichtigung abonnieren.**
   Das ist der eigentliche Gewinn: Supabase kündigt Änderungen 30 Tage
   vorher an, und ein Abo verwandelt eine Pflicht, die man sonst
   halbjährlich von Hand prüfen müsste, in eine Mail. Eine Aufgabe, die
   halbjährlich fällig wird, passiert einmal.

Abgelegt wird im Unterlagenordner des Betreibers, nicht im Repo — es
sind fremde Dokumente, und das Repo ist öffentlich. Hierher gehört nur,
welche Fassung gilt und wann sie geholt wurde; genau dafür steht sie in
der Tabelle.

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
   -- Funde über den AUTOR, nicht über den Spot (Patch 014): Eigene Funde
   -- an fremden Spots gehören in den Export hinein; fremde Funde auf den
   -- eigenen Spots sind Daten der anderen und gehören NICHT hinein.
   select * from public.finds        where author_id = '<uid>';
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
