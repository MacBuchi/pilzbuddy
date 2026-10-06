# PilzBuddy — Arbeitsregeln für `test/`

Teil der Root-`CLAUDE.md` (dort: Abschnitt „Tests" und der Index aller
Teildateien). Hier stehen die Fallen, die beim Schreiben von Tests schon
je eine Debug-Runde gekostet haben — und zwar still: Jede davon lässt
einen Test grün oder scheitern, ohne auf die Ursache zu zeigen.
Zusammengeführt am 2026-10-06 aus Erfahrungsnotizen, die bis dahin nur im
Agenten-Gedächtnis lagen und damit für Codex unsichtbar waren.

## Gegenprobe — bevor ein Test als Absicherung gilt

Kein Test gilt, bevor er einmal absichtlich rot war: die geschützte
Produktionsstelle entschärfen (Bedingung umdrehen, Zeile ausbauen), Test
rot sehen, zurückbauen, grün sehen. **Zurückbauen per Dateikopie, nie per
`git checkout --`**, solange im Arbeitsverzeichnis Unkommittiertes liegt —
so ist zweimal Arbeit verloren gegangen. Bei vielen Zusicherungen lohnt ein
Skript, das jede Mutation einzeln anwendet und den Test fährt.

Die Gegenprobe selbst kann lügen, in drei Formen:

- **Der Aufbau erreicht die Stelle nicht.** Bleibt die Gegenprobe grün,
  ist zuerst der TESTAUFBAU verdächtig (Beispiel: ohne `useRealMap: true`
  bleibt `mapIdleCenterProvider` null, die Ablesung feuert nie).
- **Die mutierte Bedingung war ohnehin unerreichbar** — dann ist die
  Mutation ein No-op. Gegen die Variante prüfen, die man wirklich bauen
  würde.
- **Der Test holt seine Eingabe aus der Konstante, die er bewacht** (#544):
  Konstante verstellen verschiebt die Eingabe mit. Eine Konstante liefert
  entweder die Eingabe oder wird geprüft — den Wert dann einmal absolut.

Fällt die Gegenprobe auf einer anderen Zusicherung als der gemeinten, ist
die Reihenfolge falsch: die tragende Zusicherung nach vorn. Zwei
Zusicherungen je Negativfall (Meldung sichtbar UND Zustand unverändert).
Testkommentare sagen, was der Test BEWEIST, nicht was er abdeckt.

## Widget-Test-Fallen

- **Bildschirmgröße kommt aus `tester.view`, nicht aus `setSurfaceSize`.**
  `setSurfaceSize` ändert nur die Zeichenfläche; `MediaQuery.sizeOf` meldet
  weiter 800×600 (#414, drei Anläufe). Der Weg, der wirkt:
  ```dart
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  ```
- **Gegen die eigene Hülle messen, nie gegen den Bildschirm.** Layout über
  `pumpApp` in der echten App-Hülle messen (`tester.getRect`), nie in einer
  nachgebauten `MaterialApp` — ein Blatt unter der Reiterleiste bekommt den
  Body (810 dp), nicht den Schirm (914 dp). Dreimal falsch gemessen, einmal
  davon ausgeliefert (#358, #350: Tour-Blase 80 dp zu tief, im
  PRODUKTIONScode über `MediaQuery.sizeOf`). Der Kasten kennt seine Maße
  (`LayoutBuilder`), der Bildschirm nicht. Tests auf die EIGENSCHAFT
  schreiben („wie viel Platz bleibt"), nicht auf die Formel.
- **Ein zweiter `pumpApp` ist kein Neustart.** Derselbe `ProviderScope` an
  derselben Stelle behält seinen Container. Für „wird gemerkt" dazwischen
  `await tester.pumpWidget(const SizedBox());` und beide Hälften prüfen:
  das Schreiben (`FakeSettings`-Feld) UND das Zurücklesen (Providerwert
  nach dem Neustart). Gegenprobe gegen das LESEN fahren (#349).
- **Plattform-Kanäle mocken.** Unter `FakeAsync` löst sich die Antwort
  eines nicht gemockten Kanals nie auf — der Knopf bleibt folgenlos, ohne
  Fehler, weiter unten scheitert eine Erwartung (#367). Kanal per
  `setMockMethodCallHandler` bedienen und die echte Nutzlast prüfen.
  Diagnose, wenn ein Test „nichts tut": `SystemChannels.platform`
  mitloggen — `SystemSound.play` beweist, dass der Knopf gedrückt wurde.
- **In `TabBarView` leben beide Reiter.** `find.byType(Scrollable).first`
  trifft den unsichtbaren, `scrollUntilVisible` scheitert mit
  `Bad state: No element`. Zielbereich benennen:
  `find.descendant(of: find.byType(SpotStatsView), matching: find.byType(Scrollable))`.
  Reiterwechsel über `openTab()` aus `test/fakes/test_app.dart` (Wörter wie
  „Spots" stehen sonst doppelt im Baum).

## Werkzeug

- `flutter analyze` und `flutter test` schreiben bei JEDEM Lauf einen
  `exclude`-Block in `analysis_options.yaml`. Vor dem Commit
  `git restore analysis_options.yaml`; ebenso eine `pubspec.lock`, die nur
  ein IDE-`pub get` verändert hat.
- Während der Arbeit nur betroffene Dateien,
  `flutter test --reporter failures-only test/…`; die ganze Suite einmal am
  Ende.
