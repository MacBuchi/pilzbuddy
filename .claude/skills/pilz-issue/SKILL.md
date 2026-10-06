---
name: pilz-issue
description: Ein PilzBuddy-Issue oder eine Änderungsanfrage vom Anfang bis zum PR durchziehen, ohne Schleifen — vor dem Coden Lagebild, frischer Branch, Issue samt Kommentaren und die Ordner-CLAUDE.md lesen; am Ende Version, Changelog, Neuheiten-Eintrag, gezielte Tests mit Gegenprobe und PR-Text. Nutzen, sobald an einem Issue (#NNN) oder einer Funktions-/Fehleränderung in lib/, assets/, supabase/ oder web/ gearbeitet wird — auch wenn nur „schau dir #NNN an" oder „bau X" gesagt wird.
---

# Vom Issue zum PR

Jeder Schritt hier steht da, weil er schon einmal gefehlt hat. Der Skill
bündelt; die Einzelheiten stehen dort, wo sie hingehören — Regeln in der
Root-`CLAUDE.md`, Fachwissen in der `CLAUDE.md` des Ordners, GitHub-Abläufe
im Skill `github-flow`.

## Wie viel Ritual

Die Größe der Anfrage bestimmt den Aufwand, nicht dieser Skill.

- **Klein und eindeutig** (Text ändern, Farbe, ein Fehler mit klarer
  Ursache): Start-Schritte 1–3 still erledigen, dann direkt bauen. Kein
  Plan zur Freigabe, keine Rückfrage.
- **Größer oder mehrdeutig** (neue Funktion, Schema, Datenschutz, mehrere
  Ordner, oder „fertig" ist nicht beschrieben): kurzer Plan zur Freigabe
  (Betreiberregel „Plan vor Implementierung").

Rückfragen nur, wenn die Antwort den Bau ändert — und dann gebündelt, mit
einer empfohlenen Option. Der Betreiber soll nie umständlich formulieren
müssen, damit es klappt: Fehlendes Abnahmekriterium selbst als Vorschlag
in den Plan schreiben („fertig, wenn …"), nicht abfragen.

## Start

1. **Lagebild lesen.** Der SessionStart-Hook (`tool/session_status.py`)
   hat es schon in den Kontext geschrieben: Branch, Abstand zu
   `origin/main`, Unkommittiertes, offene Bump-PRs. Fehlt es (lange
   Sitzung, Branch gewechselt): `python3 tool/session_status.py`.
   - Unkommittiertes ansehen, nie per `git checkout` verwerfen.
   - Offene PRs mit Versions-Bump notieren — sie bestimmen die Version am
     Ende (Schritt „Abschluss" 1).
2. **Issue lesen, mit allen Kommentaren:** `gh issue view N --comments`.
   Entscheidungen des Betreibers stehen oft im TEXT des Issues und gelten
   vor einem späteren Plan-Kommentar (so bei #553). Verlinkte Issues und
   PRs kurz mitlesen.
3. **Branch frisch von `origin/main`:**
   `git fetch origin && git switch -c feat/<thema> origin/main`
   (`fix/`, `chore/` …). Nie vom lokalen `main` und nie von einem Branch,
   dessen PR schon squash-gemergt ist — der trägt den Commit sonst doppelt.
4. **Fachwissen laden:** In der Root-`CLAUDE.md` den Abschnitt
   „Technik-Notizen — Index" ansehen und die Teildatei(en) der betroffenen
   Ordner lesen, BEVOR geplant wird. Breite Suchen über viele Ordner an
   einen Explore-Subagenten geben.
5. **Plan** (nur bei größeren Anfragen, s. o.): was sich ändert, welche
   Dateien, welche Tests, „fertig, wenn …", und was bewusst NICHT
   gemacht wird. Dann warten.

## Bauen

- Tests während der Arbeit gezielt: nur die betroffenen Dateien,
  `flutter test --reporter failures-only test/…`.
- Fallen, die beim Testen schon Runden gekostet haben, stehen in
  `test/CLAUDE.md` — vor dem ersten neuen Widget-Test lesen.
- Neues Fachwissen (eine Falle, eine Messung, eine Entscheidung) gehört in
  die `CLAUDE.md` des Ordners, in dem der Code liegt — nicht in die Root.

## Abschluss

1. **Version:** Ändert sich etwas unter `lib/` oder `assets/` (oder
   `CHANGELOG.md`), beide Teile in `pubspec.yaml` erhöhen. Ausgangspunkt
   ist `origin/main`; liegt ein offener Bump-PR davor, der zuerst gemergt
   wird, über ihn hinaus zählen oder die Reihenfolge mit dem Betreiber
   klären (`github-flow` §4).
2. **Changelog:** Block oder Versionszeile in `CHANGELOG.md`, in
   Alltagssprache, nach Thema. Nackte URLs, keine Markdown-Links.
3. **Sichtbare Funktion?** Eintrag in `kFeatureHighlights` plus Vorführung
   in `highlight_demos.dart` — oder im PR einen Satz, warum nicht.
   Oberfläche, auf die eine Tour zeigt, geändert? Anker prüfen.
4. **Neues Netzziel, neue Berechtigung, neue Datenkategorie?**
   `web/datenschutz.html`, `docs/play-console.md`,
   `docs/datenschutz-nachweise.md` im selben PR.
   **Schema?** Skill `supabase-schema-flow`; `patch_NNN`, Struktur in
   `schema.sql` UND Saat-Liste.
5. **Prüfen:** betroffene Tests, dann `flutter analyze`, dann einmal die
   ganze Suite `flutter test --reporter failures-only`. Für jede neue
   Zusicherung die **Gegenprobe**: Produktionsstelle entschärfen, Test rot
   sehen, per Dateikopie zurückbauen, grün sehen.
6. **Aufräumen vor dem Commit:** `git restore analysis_options.yaml`
   (Flutter schreibt dort bei jedem Lauf einen `exclude`-Block hinein) und
   `pubspec.lock` nur behalten, wenn eine Abhängigkeit wirklich dazukam.
   Kein `dart format`.
7. **Commit und PR** auf Englisch, Conventional Commits. PR-Text nach
   `.github/pull_request_template.md`, Checkliste ehrlich abhaken, im Text
   nennen, welche Gegenprobe gefahren wurde. `Closes #N` in den PR-Body
   (nur der Body verknüpft — `github-flow` §2). Gemergt wird vom Menschen.
8. **Schnitt anbieten:** Ist die Aufgabe mit dem PR erledigt, die Antwort
   mit einem Satz schließen: „Guter Moment für `/rename <thema>` und
   `/clear`." Was danach noch zählt (Merge abwarten, Nacharbeit), gehört
   vorher ins Memory oder ins Issue — nicht in den Verlauf, der gleich
   verschwindet. Abschnitt „Compact instructions" in der Root-`CLAUDE.md`.
