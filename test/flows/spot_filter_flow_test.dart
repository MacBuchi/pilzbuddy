// Filtern auf der Karte (#154): Knopf → Blatt → Auswahl → weniger Marker.
// Die Regeln selbst stehen in `spot_filter_test.dart`; hier geht es darum,
// dass ein aktiver Filter sichtbar ist und sich wieder aufheben lässt —
// ein unbemerkt versteckter Spot ist der eigentliche Schaden.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/widgets/mushroom_icon.dart';
import 'package:pilzbuddy/features/map/spot_filter.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  /// Ich mit zwei Spots (Marone, Pfifferling), eine Freundin mit einem.
  (FakeBackend, FakeUser) backendWithSpots() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    final lilli = backend.addUser(username: 'lilli');
    backend.signInAs(me.id);
    backend.addFriendship(lilli.id, me.id);
    backend.addSpot(
        ownerId: me.id, species: 'Marone', foundOn: DateTime(2026, 7, 1));
    backend.addSpot(
        ownerId: me.id, species: 'Pfifferling', foundOn: DateTime(2026, 7, 2));
    backend.addSpot(
        ownerId: lilli.id,
        lat: 51.1644,
        species: 'Marone',
        foundOn: DateTime(2026, 7, 3));
    return (backend, me);
  }

  /// Gemessen wird gegen ein Telefon, nicht gegen die 800×600 des
  /// Test-Standards: Das Blatt deckelt sich auf zwei Drittel der
  /// Bildschirmhöhe, und in 600 dp bleibt der Artenliste hinter drei
  /// Schaltern weniger Platz als auf jedem echten Gerät. Ein Test, der
  /// dort scheitert, misst die Testhülle statt die App (#414).
  ///
  /// **Über `tester.view`, nicht über `setSurfaceSize`** — gemessen: Das
  /// Blatt deckelt sich an `MediaQuery.sizeOf`, und die kommt aus der
  /// View. `setSurfaceSize` ändert nur die Zeichenfläche, die MediaQuery
  /// blieb bei 800×600, und das Blatt bei 396 dp.
  Future<void> onPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await settle(tester);
  }

  testWidgets('Nach Art filtern lässt nur die passenden Marker stehen',
      (tester) async {
    final (backend, _) = backendWithSpots();
    await pumpApp(tester, backend);
    await onPhone(tester);

    expect(find.byType(MushroomIcon), findsNWidgets(3));

    await tester.tap(find.byTooltip('Karte filtern'));
    await settle(tester);

    // Das Blatt zählt Fundstellen je Art — zwei Maronen (meine und Lillis).
    expect(find.text('2 Fundstellen'), findsOneWidget);
    expect(find.text('1 Fundstelle'), findsOneWidget);

    // Die Spots liegen als „Marone" im Backend — angelegt am Repository
    // vorbei, also so, wie Bestandsdaten aus der Zeit vor 1.37.0 aussehen.
    // Das Blatt zeigt trotzdem die Hauptbezeichnung; genau daran hängt,
    // dass alte Funde nicht neben den neuen als eigene Art landen.
    expect(find.text('Marone'), findsNothing);
    await tester.tap(find.text('Maronenröhrling'));
    await settle(tester);
    Navigator.of(tester.element(find.text('Karte filtern'))).pop();
    await settle(tester);

    // Meine Marone und Lillis — der Pfifferling ist weg.
    expect(find.byType(MushroomIcon), findsNWidgets(2));
  });

  testWidgets('Ein aktiver Filter ist auf der Karte zu sehen und aufhebbar',
      (tester) async {
    final (backend, _) = backendWithSpots();
    await pumpApp(tester, backend);
    await onPhone(tester);

    await tester.tap(find.byTooltip('Karte filtern'));
    await settle(tester);
    await tester.tap(find.text('Pfifferling'));
    await settle(tester);
    // Das Blatt schließen (Auswahl wirkt sofort, ohne „Übernehmen").
    Navigator.of(tester.element(find.text('Karte filtern'))).pop();
    await settle(tester);

    // Nur noch der Pfifferling-Spot.
    expect(find.byType(MushroomIcon), findsOneWidget);
    // …und die Karte sagt, warum.
    expect(find.textContaining('Gefiltert: nur Pfifferling'), findsOneWidget);

    await tester.tap(find.byTooltip('Filter aufheben'));
    await settle(tester);
    expect(find.byType(MushroomIcon), findsNWidgets(3));
    expect(find.textContaining('Gefiltert'), findsNothing);
  });

  testWidgets('Zwei Arten anhaken zeigt beide, „Alle Arten" hebt es auf',
      (tester) async {
    final (backend, me) = backendWithSpots();
    // Eine dritte Art, damit sich „beide" von „alle" unterscheiden lässt.
    backend.addSpot(
        ownerId: me.id,
        lat: 51.1654,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 7, 4));
    await pumpApp(tester, backend);
    await onPhone(tester);
    expect(find.byType(MushroomIcon), findsNWidgets(4));

    await tester.tap(find.byTooltip('Karte filtern'));
    await settle(tester);
    await tester.tap(find.text('Maronenröhrling'));
    await settle(tester);
    await tester.tap(find.text('Pfifferling'));
    await settle(tester);
    Navigator.of(tester.element(find.text('Karte filtern'))).pop();
    await settle(tester);

    // Zwei Maronen + ein Pfifferling; der Steinpilz fehlt.
    expect(find.byType(MushroomIcon), findsNWidgets(3));
    // Bei zwei Arten stehen beide Namen da, alphabetisch.
    expect(find.textContaining('Gefiltert: nur Maronenröhrling, Pfifferling'),
        findsOneWidget);

    // „Alle Arten" räumt die ganze Auswahl weg — ein Tipp, nicht zwei.
    await tester.tap(find.byTooltip('Karte filtern'));
    await settle(tester);
    await tester.tap(find.text('Alle Arten'));
    await settle(tester);
    Navigator.of(tester.element(find.text('Karte filtern'))).pop();
    await settle(tester);

    expect(find.byType(MushroomIcon), findsNWidgets(4));
    expect(find.textContaining('Gefiltert'), findsNothing);
  });

  testWidgets('Ab drei Arten nennt die Karte die Zahl statt der Namen',
      (tester) async {
    // Sonst wächst die Zeile über die Karte; sie teilt sich den Platz mit
    // den übrigen Bannern.
    final (backend, me) = backendWithSpots();
    backend.addSpot(
        ownerId: me.id,
        lat: 51.1654,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 7, 4));
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Karte filtern'));
    await settle(tester);
    for (final name in ['Maronenröhrling', 'Pfifferling', 'Steinpilz']) {
      // Scrollen, weil die Artenliste im Blatt seit #399 eine Zeile
      // weniger Platz hat („Nur wo die Ampel günstig steht").
      await tester.ensureVisible(find.text(name));
      await settle(tester);
      await tester.tap(find.text(name));
      await settle(tester);
    }
    Navigator.of(tester.element(find.text('Karte filtern'))).pop();
    await settle(tester);

    expect(find.textContaining('Gefiltert: 3 Arten'), findsOneWidget);
    expect(find.textContaining('Pfifferling'), findsNothing);
  });

  testWidgets('„Nur meine Spots" blendet die der Freundin aus',
      (tester) async {
    final (backend, _) = backendWithSpots();
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Karte filtern'));
    await settle(tester);
    await tester.tap(find.text('Nur meine Spots'));
    await settle(tester);
    Navigator.of(tester.element(find.text('Karte filtern'))).pop();
    await settle(tester);

    expect(find.byType(MushroomIcon), findsNWidgets(2));
    expect(find.textContaining('Gefiltert: nur meine'), findsOneWidget);
  });

  testWidgets('Ohne Filter gibt es keine Hinweiszeile', (tester) async {
    // Die Zeile kostet Platz über der Karte — sie erscheint nur, wenn sie
    // etwas zu sagen hat.
    final (backend, _) = backendWithSpots();
    await pumpApp(tester, backend);

    expect(find.textContaining('Gefiltert'), findsNothing);
    expect(find.byTooltip('Filter aufheben'), findsNothing);
  });

  group('Nur was jetzt Saison hat (#414)', () {
    /// Zwei eigene Spots mit gegenläufigen Kurven: Pfifferling (Juli 100,
    /// Dezember 6) und Austernseitling (Juli 3, Dezember 100).
    FakeBackend backendWithSeasons() {
      final backend = FakeBackend();
      final me = backend.addUser(username: 'testpilz');
      backend.signInAs(me.id);
      backend.addSpot(
          ownerId: me.id,
          species: 'Pfifferling',
          foundOn: DateTime(2026, 7, 1));
      backend.addSpot(
          ownerId: me.id,
          lat: 51.1644,
          species: 'Austernseitling',
          foundOn: DateTime(2026, 12, 1));
      return backend;
    }

    /// Der Monat kommt aus einem Provider, nicht von der Uhr — sonst
    /// wäre dieser Test im September grün und im Dezember rot.
    List<Override> inMonth(int month) =>
        [currentMonthProvider.overrideWithValue(month)];

    testWidgets('im Juli bleibt der Pfifferling, im Dezember der andere',
        (tester) async {
      await pumpApp(tester, backendWithSeasons(),
          extraOverrides: inMonth(7));

      expect(find.byType(MushroomIcon), findsNWidgets(2));
      await tester.tap(find.byTooltip('Karte filtern'));
      await settle(tester);
      // Der Untertitel nennt Zahl und Monat, damit der Schalter sagt, was
      // er tun wird, bevor man ihn umlegt.
      expect(find.text('1 Fundstelle im Juli'), findsOneWidget);
      await tester.tap(find.text('Nur was jetzt Saison hat'));
      await settle(tester);
      Navigator.of(tester.element(find.text('Karte filtern'))).pop();
      await settle(tester);

      expect(find.byType(MushroomIcon), findsOneWidget);
      // **Und die Karte sagt, WARUM einer fehlt.** Genau hier ist #414
      // durchgerutscht: Der Schalter zählte zwar zum aktiven Filter (das
      // prüfte `spot_filter_test.dart` sogar), stand aber in keiner
      // Aufzählung — auf der Karte las man „🔍 Gefiltert:" und danach
      // nichts. Ein Chip, der einen Doppelpunkt zeigt und schweigt, ist
      // schlechter als keiner: Er sagt, dass etwas versteckt wird, aber
      // nicht was.
      expect(find.textContaining('Gefiltert: jetzt Saison'), findsOneWidget);
    });

    testWidgets('im Mai hat keiner von beiden Saison — der Schalter sperrt',
        (tester) async {
      // Pfifferling 5, Austernseitling 2. Ein Schalter, der auf eine leere
      // Karte führt, wäre von „kaputt" nicht zu unterscheiden (#399), und
      // `onChanged: null` allein ist keine Auskunft — deshalb sagt der
      // Untertitel, WARUM.
      await pumpApp(tester, backendWithSeasons(),
          extraOverrides: inMonth(5));
      await tester.tap(find.byTooltip('Karte filtern'));
      await settle(tester);

      expect(find.text('Im Mai hat keine deiner Arten Saison'),
          findsOneWidget);
      final tile = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Nur was jetzt Saison hat'));
      expect(tile.onChanged, isNull);
    });
  });

}
