// Szenarien rund um Spots: anlegen am Fadenkreuz, Arten-Vorschläge,
// Vorbelegung, Wiederbesuch (Fund eintragen), Freigabe-Ausschluss, Löschen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/widgets/mushroom_avatar.dart';
import 'package:pilzbuddy/core/widgets/mushroom_icon.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  testWidgets('Eigene Position erscheint als Avatar auf der Karte',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        position: fakePosition(51.16, 10.45)); // nahe Kartenmitte
    expect(find.byType(MushroomAvatar), findsOneWidget);
  });

  testWidgets('Ohne Standortfreigabe kein Positions-Avatar', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend); // position: null
    expect(find.byType(MushroomAvatar), findsNothing);
  });

  testWidgets('Eigene Spots erscheinen als Marker auf der Karte',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz');
    await pumpApp(tester, backend);

    expect(find.byTooltip('Buchenhang'), findsOneWidget);
    expect(find.byType(MushroomIcon), findsOneWidget);
  });

  testWidgets(
      'Neuer Spot: Fadenkreuz → Vorschlag antippen → Speichern legt Spot samt Fund an',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);

    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);
    expect(find.text('Neuer Pilz-Spot'), findsOneWidget);

    // Tippen zeigt Vorschläge aus der eingebauten Artenliste …
    await tester.enterText(
        find.widgetWithText(TextField, 'Pilzart (optional)'), 'Steinpil');
    await settle(tester, frames: 4);
    // … Antippen übernimmt den Treffer ins Feld.
    await tester.tap(find.widgetWithText(ListTile, 'Steinpilz').first);
    await settle(tester, frames: 4);

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    expect(backend.spots, hasLength(1));
    expect(backend.spots.single.finds.single.species, 'Steinpilz');
    // Gespeichert wird exakt an der Fadenkreuz-Position (Kartenmitte).
    expect(backend.spots.single.lat, closeTo(51.1634, 0.01));
    expect(find.text('Spot gespeichert 🍄'), findsOneWidget);
    expect(find.byType(MushroomIcon), findsOneWidget);
  });

  testWidgets('Ein Zweitname landet als Hauptbezeichnung — und sagt es',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);

    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);

    // „Herrenpilz" ist der Steinpilz. Der Vorschlag zeigt die
    // Hauptbezeichnung und nennt den getippten Namen als Grund.
    await tester.enterText(
        find.widgetWithText(TextField, 'Pilzart (optional)'), 'Herrenpilz');
    await settle(tester, frames: 4);
    expect(find.widgetWithText(ListTile, 'Steinpilz'), findsOneWidget);
    expect(find.text('auch: Herrenpilz'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Steinpilz').first);
    await settle(tester, frames: 4);

    // Nach der Auswahl steht im Feld „Steinpilz" — ohne die Zeile darunter
    // sähe das aus, als hätte die App die Eingabe verschluckt.
    expect(find.text('auch: Herrenpilz, Fichtensteinpilz'), findsOneWidget);

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    expect(backend.spots.single.finds.single.species, 'Steinpilz');
    await drainSnackbars(tester);
  });

  testWidgets('Auch frei getippt wird der Zweitname zur Hauptbezeichnung',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);

    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);

    // Ohne den Vorschlag anzutippen: eintippen und direkt speichern. Wer
    // den Namen kennt, tut genau das — dann muss die Umsetzung auf die
    // Hauptbezeichnung beim Schreiben greifen, nicht erst bei der Auswahl.
    await tester.enterText(
        find.widgetWithText(TextField, 'Pilzart (optional)'), 'Totentrompete');
    await settle(tester, frames: 4);

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'), warnIfMissed: false);
    await settle(tester);

    expect(backend.spots.single.finds.single.species, 'Herbsttrompete');
    await drainSnackbars(tester);
  });

  testWidgets('Neuer Spot startet ohne vorbelegte Art (#155)', (tester) async {
    // Umgekehrt zur früheren Erwartung: Bis 1.33.0 stand die zuletzt
    // gemeldete Art schon im Feld und musste gelöscht werden, wenn der
    // nächste Fund eine andere Art war — der Normalfall.
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id,
        // Weit weg vom Fadenkreuz: Seit #215 fragt die App nach, wenn in
        // 20 m schon ein eigener Spot liegt — hier geht es aber um die
        // Art-Vorbelegung, nicht um die Nachbarschaft.
        lat: 51.5,
        species: 'Pfifferling',
        foundOn: DateTime(2026, 7, 1));
    await pumpApp(tester, backend);

    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);

    expect(find.widgetWithText(TextField, 'Pfifferling'), findsNothing);
    final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Pilzart (optional)'));
    expect(field.controller?.text, isEmpty);

    // Als Vorschlag bleibt die eigene Art erreichbar — ein Tipp statt
    // Löschen plus Tippen.
    expect(find.widgetWithText(ChoiceChip, 'Pfifferling'), findsOneWidget);
  });

  testWidgets('Wiederbesuch: Fund eintragen ist mit dem letzten Fund vorbelegt',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id,
        species: 'Maronenröhrling',
        count: 3,
        foundOn: DateTime(2026, 6, 15));
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);
    expect(find.text('Dein Spot'), findsOneWidget);
    expect(find.text('Maronenröhrling, 3 Stück'), findsOneWidget);
    // Die Fund-Zeile trägt das Art-Icon statt eines generischen 🍄 (#103).
    expect(find.text('🍄'), findsNothing);
    expect(
        find.descendant(
            of: find.widgetWithText(ListTile, 'Maronenröhrling, 3 Stück'),
            matching: find.byType(MushroomIcon)),
        findsOneWidget);

    await tester.tap(find.text('Fund eintragen'));
    await settle(tester);
    expect(find.widgetWithText(TextField, 'Maronenröhrling'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    expect(backend.spots.single.finds, hasLength(2));
    expect(backend.spots.single.finds.last.species, 'Maronenröhrling');
    // Das Detail-Sheet zeigt jetzt beide Funde.
    expect(find.text('Maronenröhrling, 3 Stück'), findsNWidgets(2));
    expect(
        find.descendant(
            of: find.widgetWithText(ListTile, 'Maronenröhrling, 3 Stück'),
            matching: find.byType(MushroomIcon)),
        findsNWidgets(2));
  });

  testWidgets('Mehrere Arten in einem Rutsch (#211)', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, species: 'Steinpilz');
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);
    await tester.tap(find.text('Fund eintragen'));
    await settle(tester);

    // Erste Art ist aus dem letzten Fund vorbelegt — ablegen und die
    // zweite tippen.
    await tester.ensureVisible(find.text('weitere Art'));
    await tester.tap(find.text('weitere Art'));
    await settle(tester);
    expect(find.widgetWithText(InputChip, 'Steinpilz'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Pilzart (optional)'), 'Pfifferling');
    await settle(tester, frames: 4);
    await tester.enterText(
        find.widgetWithText(TextField, 'Notiz (optional)'), 'am Bachlauf');
    await settle(tester, frames: 4);

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    // Der abgelegte Chip UND die offene Zeile werden geschrieben — wer nur
    // eine Art einträgt, soll „weitere Art" nie anfassen müssen.
    final finds = backend.spots.single.finds;
    expect(finds, hasLength(3)); // der Bestandsfund plus zwei neue
    expect(finds.skip(1).map((f) => f.species), ['Steinpilz', 'Pfifferling']);
    // Datum und Notiz gelten für alle Zeilen: Jede bleibt für sich
    // vollständig, darauf bauen GPX-Export und die Buddy-Sicht auf.
    expect(finds.skip(1).map((f) => f.note), ['am Bachlauf', 'am Bachlauf']);
    expect(finds[1].foundOn, finds[2].foundOn);
  });

  testWidgets('„Nichts gefunden" wird eingetragen und zählt nicht als Fund',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, species: 'Steinpilz', foundOn: DateTime(2025, 9, 1));
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);
    await tester.ensureVisible(find.text('Nichts gefunden'));
    await tester.tap(find.text('Nichts gefunden'));
    await settle(tester);

    // Das Blatt fragt weder nach Art noch nach Anzahl — der Leergang ist
    // eine Aussage über den Ort.
    expect(find.widgetWithText(TextField, 'Pilzart (optional)'), findsNothing);
    expect(find.text('Anzahl'), findsNothing);

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    final leergang = backend.spots.single.finds.last;
    expect(leergang.blank, isTrue);
    expect(leergang.species, isNull);
    expect(leergang.count, isNull);
    // In der Historie steht er, mit eigenem Zeichen statt Pilz-Icon.
    // Auf die ListTile eingegrenzt, nicht auf den Text: Der Knopf trägt
    // dieselbe Beschriftung und dasselbe Icon — eine Prüfung auf den
    // Bildschirm insgesamt wäre immer erfüllt und damit wertlos.
    final zeile = find.widgetWithText(ListTile, 'Nichts gefunden');
    expect(zeile, findsOneWidget);
    expect(
        find.descendant(of: zeile, matching: find.byIcon(Icons.search_off)),
        findsOneWidget);
    expect(find.descendant(of: zeile, matching: find.byType(MushroomIcon)),
        findsNothing);

    // Der Marker behält seinen Steinpilz — das Blatt zeigt weiter die
    // Fundzeile von 2025 mit ihrem Art-Icon.
    expect(
        find.descendant(
            of: find.widgetWithText(ListTile, 'Steinpilz'),
            matching: find.byType(MushroomIcon)),
        findsOneWidget);

    // … und die Statistik zählt weiterhin genau einen Fund.
    await tester.tapAt(const Offset(20, 20)); // Sheet schließen
    await settle(tester);
    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Funde'), 200,
        scrollable: find.byType(Scrollable).first);
    final funde = find.ancestor(
        of: find.text('Funde'), matching: find.byType(Column));
    expect(find.descendant(of: funde.first, matching: find.text('1')),
        findsOneWidget);
  });

  testWidgets('Freigabe-Ausschluss lässt sich am Spot umschalten',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, species: 'Steinpilz');
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);
    await tester.tap(find.text('Von Freigabe ausschließen'));
    await settle(tester);

    expect(backend.spots.single.sharingExcluded, isTrue);
  });

  testWidgets('Spot löschen entfernt den Marker und die Daten',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Alter Spot');
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Alter Spot'));
    await settle(tester);
    await tester.tap(find.byTooltip('Spot löschen'));
    await settle(tester);
    expect(find.text('Spot löschen?'), findsOneWidget);
    await tester.tap(find.text('Löschen'));
    await settle(tester);

    expect(backend.spots, isEmpty);
    expect(find.byTooltip('Alter Spot'), findsNothing);
  });

  testWidgets('Profil zeigt Statistik und schaltet die Detail-Freigabe',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final spotA = backend.addSpot(
        ownerId: me.id, species: 'Steinpilz', foundOn: DateTime(2025, 9, 1));
    backend.addFindRow(spotA,
        species: 'Steinpilz', foundOn: DateTime(2025, 10, 3));
    backend.addSpot(
        ownerId: me.id,
        lat: 51.5,
        species: 'Pfifferling',
        foundOn: DateTime(2025, 8, 2));
    await pumpApp(tester, backend);

    await tester.tap(find.text('Profil'));
    await settle(tester);

    expect(find.text('testpilz'), findsOneWidget);

    // Detail-Freigabe umschalten, solange der Schalter oben sichtbar ist.
    await tester.tap(find.text('Auch Art, Anzahl und Funddatum teilen'));
    await settle(tester);
    expect(me.shareDetails, isFalse);

    // Statistik liegt unter Offline-Karten/Import/Export — hinscrollen.
    await tester.scrollUntilVisible(find.text('Spots'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Spots'), findsOneWidget);
    expect(find.text('Funde'), findsOneWidget);
    // 2 Spots, 3 Funde, 1 mehrfach besuchter Spot
    expect(find.text('2'), findsAtLeastNWidgets(1));
    expect(find.text('3'), findsAtLeastNWidgets(1));

    // Top-Arten liegt noch weiter unten im ListView.
    await tester.scrollUntilVisible(find.text('Top-Arten'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Top-Arten'), findsOneWidget);
    // Jede Art-Zeile zeigt ihr eigenes Icon — vorher fünf gleiche 🍄 (#103).
    expect(
        find.descendant(
          of: find.ancestor(
              of: find.text('Top-Arten'), matching: find.byType(Card)),
          matching: find.byType(MushroomIcon),
        ),
        findsNWidgets(2)); // Steinpilz, Pfifferling

    // Ganz unten: die „Über"-Sektion mit Version und Links.
    await tester.scrollUntilVisible(find.text('Über PilzBuddy'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('GitHub-Projekt & Dokumentation'), findsOneWidget);
    expect(find.text('Web-App'), findsOneWidget);
  });
}
