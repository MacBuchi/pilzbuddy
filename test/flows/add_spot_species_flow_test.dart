// Die Pflichtangabe im Blatt „Neuer Pilz-Spot" (#549).
//
// **Pflicht mit Ausweg.** Bis 1.182.0 legte ein leeres Artfeld
// stillschweigend einen artlosen Fund an — bewusst, für „da stand was,
// ich weiß nicht was", aber nicht zu unterscheiden vom Vergessen. Der
// Betreiber wollte die Art verpflichtend; entschieden wurde: Pflicht
// UND „Art unbekannt" als zweite gültige Antwort. Was danach in der
// Datenbank steht, ist unverändert ein Fund OHNE Art.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/map_ui.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  Future<void> openSheet(WidgetTester tester, FakeBackend backend) async {
    await pumpApp(tester, backend);
    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);
    expect(find.text('Neuer Pilz-Spot'), findsOneWidget);
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);
  }

  testWidgets('ohne Art entsteht kein Spot — und das Blatt sagt warum',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await openSheet(tester, backend);
    await tapSave(tester);

    expect(backend.spots, isEmpty, reason: 'nichts angelegt');
    expect(find.text('Neuer Pilz-Spot'), findsOneWidget,
        reason: 'das Blatt bleibt offen, sonst wäre die Eingabe weg');
    expect(find.textContaining('mindestens drei Zeichen'), findsOneWidget,
        reason: 'ein Knopf, der nur nichts tut, liest sich als Fehler');
  });

  testWidgets('zwei Zeichen sind kein Pilzname', (tester) async {
    // Ein oder zwei Buchstaben sind ein Verrutscher. Ohne die Schranke
    // stünde „St" danach als eigene Art in der Liste des Nutzers und
    // schlüge sich beim nächsten Mal selbst vor.
    final (backend, _) = loggedInBackend();
    await openSheet(tester, backend);
    await tester.enterText(speciesField(), 'St');
    await settle(tester, frames: 4);
    await tapSave(tester);

    expect(backend.spots, isEmpty);
    expect(find.textContaining('mindestens drei Zeichen'), findsOneWidget);
  });

  testWidgets('„Art unbekannt" legt denselben artlosen Fund an wie früher',
      (tester) async {
    // **Der Fall, der erhalten bleiben musste.** Was gespeichert wird,
    // ist unverändert ein Fund ohne Artnamen — „Unbekannt" als Name
    // stünde sonst im Artenfilter, in den Vorschlägen und am Marker.
    final (backend, _) = loggedInBackend();
    await openSheet(tester, backend);
    await markSpeciesUnknown(tester);
    await tapSave(tester);
    await drainSnackbars(tester);

    final spot = backend.spots.single;
    expect(spot.finds, hasLength(1));
    expect(spot.finds.single.species, isNull, reason: 'kein Name, wie bisher');
  });

  testWidgets('eine unbekannte Art fragt nach und bietet den besten Treffer',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await openSheet(tester, backend);
    await tester.enterText(speciesField(), 'Steipilz');
    await settle(tester, frames: 4);
    await tapSave(tester);

    expect(find.text('Art nicht bekannt'), findsOneWidget);
    expect(find.textContaining('Meintest du'), findsOneWidget);
    expect(backend.spots, isEmpty, reason: 'noch nichts geschrieben');

    await tester.tap(find.text('„Steinpilz"'));
    await settle(tester);
    await drainSnackbars(tester);

    expect(backend.spots.single.finds.single.species, 'Steinpilz');
  });

  testWidgets('„So eintragen" behält den getippten Namen', (tester) async {
    // Die Gegenrichtung: Wer seinen eigenen Namen will, bekommt ihn.
    // Ohne diesen Weg wäre die Rückfrage eine Bevormundung.
    final (backend, _) = loggedInBackend();
    await openSheet(tester, backend);
    await tester.enterText(speciesField(), 'Hexenbutter');
    await settle(tester, frames: 4);
    await tapSave(tester);

    expect(find.text('Art nicht bekannt'), findsOneWidget);
    await tester.tap(find.text('So eintragen'));
    await settle(tester);
    await drainSnackbars(tester);

    expect(backend.spots.single.finds.single.species, 'Hexenbutter');
  });

  testWidgets('„Zurück" aus der Rückfrage schreibt nichts', (tester) async {
    final (backend, _) = loggedInBackend();
    await openSheet(tester, backend);
    await tester.enterText(speciesField(), 'Hexenbutter');
    await settle(tester, frames: 4);
    await tapSave(tester);
    await tester.tap(find.text('Zurück'));
    await settle(tester);

    expect(backend.spots, isEmpty);
    expect(find.text('Neuer Pilz-Spot'), findsOneWidget,
        reason: 'zurück ins Blatt, nicht aus ihm heraus');
  });

  testWidgets('eine bekannte Art geht ohne Rückfrage durch', (tester) async {
    // Sonst stünde vor jedem Spot ein Dialog, und die Rückfrage verlöre
    // ihre Bedeutung.
    final (backend, _) = loggedInBackend();
    await openSheet(tester, backend);
    await tester.enterText(speciesField(), 'Steinpilz');
    await settle(tester, frames: 4);
    await tapSave(tester);
    await drainSnackbars(tester);

    expect(find.text('Art nicht bekannt'), findsNothing);
    expect(backend.spots.single.finds.single.species, 'Steinpilz');
  });

  testWidgets('die Beschriftungen sagen, was Pflicht ist', (tester) async {
    // **„(optional)" ist eine Zusage.** Das Artfeld hieß so, und der
    // Spot-Name war nur „Name" — beim Betreiber landete darin die
    // Pilzart. Ein Feld, das „optional" sagt und beim Speichern blockt,
    // wäre schlimmer als beides.
    final (backend, _) = loggedInBackend();
    await openSheet(tester, backend);

    expect(find.widgetWithText(TextField, 'Name des Spots (optional)'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, 'Pilzart'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Pilzart (optional)'), findsNothing);
  });
  testWidgets('die Anzahl lässt sich eintippen statt hochzuzählen',
      (tester) async {
    // **Der Grund für das Rad** (Betreiber, 2026-09-22: „Anzahl über +-
    // ist nicht so schnell … So kann man auch mal schnell 200 Pilze
    // erfassen."). 200-mal Plus zu tippen ist keine Eingabe.
    final (backend, _) = loggedInBackend();
    await openSheet(tester, backend);
    await tester.enterText(speciesField(), 'Steinpilz');
    await settle(tester, frames: 4);

    await tester.ensureVisible(find.text('–'));
    await tester.tap(find.text('–'));
    await settle(tester);
    expect(find.text('Anzahl'), findsWidgets);

    await tester.enterText(
        find.widgetWithText(TextField, 'Eintippen'), '200');
    await settle(tester);
    await tester.tap(find.text('Übernehmen'));
    await settle(tester);
    await tapSave(tester);
    await drainSnackbars(tester);

    expect(backend.spots.single.finds.single.count, 200);
  });

  testWidgets('„Keine Angabe" nimmt die Zahl wieder weg', (tester) async {
    // Die Datenbank kennt eine Anzahl ohne Wert, und 0 lässt sie nicht
    // zu (`count > 0`). Ohne diesen Ausgang käme man aus einer einmal
    // gesetzten Zahl nur über Minus wieder heraus.
    final (backend, _) = loggedInBackend();
    await openSheet(tester, backend);
    await tester.enterText(speciesField(), 'Steinpilz');
    await settle(tester, frames: 4);

    await tester.ensureVisible(find.text('–'));
    await tester.tap(find.text('–'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Eintippen'), '7');
    await settle(tester);
    await tester.tap(find.text('Übernehmen'));
    await settle(tester);
    expect(find.text('7'), findsWidgets);

    await tester.ensureVisible(find.text('7').first);
    await tester.tap(find.text('7').first);
    await settle(tester);
    await tester.tap(find.text('Keine Angabe'));
    await settle(tester);
    await tapSave(tester);
    await drainSnackbars(tester);

    expect(backend.spots.single.finds.single.count, isNull);
  });

  testWidgets('Abbrechen lässt die Anzahl, wie sie war', (tester) async {
    // **Abbrechen ist etwas anderes als „keine Angabe".** Ohne den
    // Unterschied löschte ein versehentlich geöffnetes Rad beim
    // Wegtippen die Zahl.
    final (backend, _) = loggedInBackend();
    await openSheet(tester, backend);
    await tester.enterText(speciesField(), 'Steinpilz');
    await settle(tester, frames: 4);

    await tester.ensureVisible(find.text('–'));
    await tester.tap(find.text('–'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Eintippen'), '5');
    await settle(tester);
    await tester.tap(find.text('Übernehmen'));
    await settle(tester);

    await tester.ensureVisible(find.text('5').first);
    await tester.tap(find.text('5').first);
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Eintippen'), '99');
    await settle(tester);
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    await tapSave(tester);
    await drainSnackbars(tester);

    expect(backend.spots.single.finds.single.count, 5);
  });

}
