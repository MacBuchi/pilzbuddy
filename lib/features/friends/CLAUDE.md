# PilzBuddy — Arbeitsregeln für `lib/features/friends/`

Teil der Root-`CLAUDE.md`, ausgelagert, damit dieses Wissen nur geladen
wird, wenn hier gearbeitet wird. Was überall gilt (Workflow, Version
Guard, Konventionen, Tests) steht weiter dort, ebenso der Index aller
Teildateien. Die Blöcke sind wörtlich übernommen; Verweise wie „siehe
oben“ können in eine andere Teildatei zeigen — der Index sagt, in welche.

## Technik-Notizen

- **Nachrichten zwischen Buddys** (#564, seit 1.193.0, Patch 030): Text
  bis 500 Zeichen, 30 Tage. Entscheidungen im Text von #564. Fünf Dinge,
  die man wissen muss:
  - **Die Grenzen zieht die Datenbank.** `app_internal.may_message`:
    angenommen ⇒ frei, offene Anfrage ⇒ höchstens drei eigene je Person,
    sonst nichts. Die Zahl im Verlauf („Noch 2 Nachrichten …") ist nur
    die Ansage vorher.
  - **Die 30 Tage hängen an SPALTEN-Grants**, nicht nur am Check: Ein
    Client darf beim Anlegen nur `recipient_id` und `body` setzen, beim
    Ändern nur `read_at`. Dafür steht zuerst ein `revoke all` — die
    Legacy-Vorgabe `auto_expose_new_tables` gäbe sonst Tabellen-INSERT,
    und der schlüge jeden Spalten-Grant. `anon` hat damit GAR keinen
    Grant; der Schema Check prüft die Tabelle deshalb über
    `check_get_protected` (42501 = vorhanden, 42703 = Spalte fehlt —
    gemessen, Postgres löst Spalten vor der Rechteprüfung auf).
  - **Ende der Freundschaft löscht den Verlauf beider Seiten** (Trigger
    `friendships_delete_messages`, Definer). `FriendshipsNotifier.remove`
    verwirft danach die Nachrichtenliste, sonst bliebe der
    Ungelesen-Punkt stehen.
  - **„Gelesen" hat eine Sperre: ein Versuch je Nachricht und Öffnen.**
    Ohne sie markierte der Verlauf bei jeder neuen Liste erneut, und
    jede Markierung lud neu — bewirkte der Server nichts, lief das ohne
    Ende (Gegenprobe; der Test dazu HÄNGT ohne Sperre, weil die Schleife
    über Microtasks läuft und kein Test-Timeout greift).
  - **Die Nachrichten lädt der Reiter-Punkt beim Start** (`BuddysNavIcon`)
    — eine Abfrage für alle Verläufe. Kein Realtime; frisch geholt wird
    beim Öffnen eines Verlaufs, per Ziehen und bei jeder eintreffenden
    Nachrichten-Meldung.
  - **Push MIT Text** (seit 1.194.0, Patch 031) — die EINE Ausnahme von
    „nie Inhalt über Google", Betreiber-Entscheidung; Profil-Schalter,
    Datenschutzerklärung und `send-push` sagen es. Eigene Warteschlange
    `app_internal.push_messages` (Cascade an der Nachricht: zurückgenommen
    ⇒ keine Meldung), versandt im selben minütlichen `push_flush`, je
    Empfänger und Absender eine Meldung. **`tool/push_flush_check.sh`
    ruft `push_flush` im Schema Dry Run WIRKLICH auf** (zurückgerollte
    Transaktion, Schein-Geheimnisse): PL/pgSQL prüft den Rumpf erst beim
    Aufruf, und ein Fehler dort legte live ALLE Benachrichtigungen still.
    Das Ziel reist als `data.route`; die App folgt nur Pfaden aus
    `pushRouteOf` (Erlaubnisliste) — Tipp aus dem Hintergrund
    (`onMessageOpenedApp`) UND aus dem beendeten Zustand
    (`getInitialMessage`, `pushInitialMessageProvider`).

- **Aliase für Buddys** (#567, seit 1.195.0, Patch 032): ein eigener
  Name je Buddy, nur für den Besitzer, geräteübergreifend. Vier Dinge,
  die man wissen muss:
  - **Jeder Buddy-Name geht über `BuddyNames.of`**
    (`lib/features/friends/buddy_alias.dart`). Namen stehen an rund
    fünfzehn Stellen; wer dort `username` direkt liest, zeigt an genau
    einer Stelle den alten Namen, und die fällt dann auf. Liste und
    Verlaufskopf zeigen Alias UND Namen, alles andere nur den Alias.
  - **Nur für bestätigte Buddys** (`are_friends` in `fa_insert`/
    `fa_update`), sonst ließe sich jedem Konto aus der Namenssuche ein
    Etikett anheften. Ende der Freundschaft löscht beide Seiten
    (Trigger `friendships_delete_aliases`, Betreiber-Entscheidung).
  - **Die Push trägt den Alias des EMPFÄNGERS** — `push_flush` schlägt
    ihn nach; `tool/push_flush_check.sh` prüft Alias, Rückfall auf den
    Namen und dass der Alias der Gegenseite nicht durchsickert.
  - **Ohne Empfang fällt der Alias weg** und der Name steht da: kein
    eigener Zwischenspeicher, er ist Bequemlichkeit, kein Inhalt.

