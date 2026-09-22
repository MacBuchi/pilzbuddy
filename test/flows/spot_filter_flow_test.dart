// Filtern auf der Karte (#154): Knopf → Blatt → Auswahl → weniger Marker.
// Die Regeln selbst stehen in `spot_filter_test.dart`; hier geht es darum,
// dass ein aktiver Filter sichtbar ist und sich wieder aufheben lässt —
// ein unbemerkt versteckter Spot ist der eigentliche Schaden.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/widgets/mushroom_icon.dart';
import 'package:pilzbuddy/core/widgets/info_button.dart';
import 'package:pilzbuddy/features/map/widgets/ampel_class_chips.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
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

  group('Ampel-Gruppen als Chips (Betreiber, 2026-09-12)', () {
    testWidgets('ohne die Vorschau stehen sie gar nicht im Blatt',
        (tester) async {
      // Ohne Vorschau rechnet die Ampel nirgends — weder Fläche noch
      // Nachlauf. Ein Bedienelement ohne Wirkung nähme der Artenliste
      // nur Platz weg, und die hat hier weniger als eine
      // Bildschirmzeile.
      final (backend, _) = backendWithSpots();
      await pumpApp(tester, backend);
      await onPhone(tester);
      await tester.tap(find.byTooltip('Karte filtern'));
      await settle(tester);
      expect(find.descendant(of: find.byKey(kAmpelClassChipsKey), matching: find.byType(FilterChip)), findsNothing);
    });

    testWidgets('mit der Fundorte-Ebene stehen sie auch ohne Vorschau im '
        'Blatt', (tester) async {
      // Seit 1.155.0 bewirkt die Auswahl auch ohne Ampel etwas: Sie
      // blendet Scheiben der Fundorte-Ebene aus. Ohne die Chips hier
      // wäre die Auswahl aus dem Fundorte-Blatt vom Filter aus nicht
      // erreichbar — und nicht zurücknehmbar.
      final (backend, _) = backendWithSpots();
      await pumpApp(tester, backend,
          settings: FakeSettings(gbifLayerEnabled: true));
      await onPhone(tester);
      await tester.tap(find.byTooltip('Karte filtern'));
      await settle(tester);
      expect(find.descendant(of: find.byKey(kAmpelClassChipsKey), matching: find.byType(FilterChip)), findsNWidgets(4));
      expect(find.textContaining('Gruppen für Ampel und Fundorte'), findsOneWidget,
          reason: 'der Satz über den Chips nennt, was sie hier bewirken');
    });

    testWidgets('abwählen engt die Ampel ein — und die Karte sagt es',
        (tester) async {
      final (backend, _) = backendWithSpots();
      await pumpApp(tester, backend,
          settings: FakeSettings(ampelPreviewEnabled: true));
      await onPhone(tester);
      await tester.tap(find.byTooltip('Karte filtern'));
      await settle(tester);

      // Ab Werk sind beide an — und das ist KEIN aktiver Filter.
      // Vier Gruppen seit 1.151.0 — alle bis auf „Steinpilz & Co." ab.
      expect(find.descendant(of: find.byKey(kAmpelClassChipsKey), matching: find.byType(FilterChip)), findsNWidgets(4));
      expect(find.textContaining('Gefiltert'), findsNothing);

      for (final name in const [
        'Pfifferling',
        'Austernseitling & Co.',
        'Herbsttrompete & Co.',
      ]) {
        await tester.ensureVisible(find.widgetWithText(FilterChip, name));
        await tester.tap(find.widgetWithText(FilterChip, name));
        await settle(tester);
      }
      // Die letzte gewählte Gruppe lässt sich nicht abwählen: Der Chip
      // ist deaktiviert, statt folgenlos zu bleiben — und die Zeile
      // darunter sagt, warum.
      final letzter = tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Steinpilz & Co.'));
      expect(letzter.onSelected, isNull);
      expect(find.text('Mindestens eine Gruppe bleibt an.'), findsOneWidget);

      Navigator.of(tester.element(find.text('Karte filtern'))).pop();
      await settle(tester);
      // #154: Was die Ampel einengt, muss auf der Karte stehen — hier
      // versteckt der Filter keinen Spot, aber er ändert die Fläche.
      expect(find.textContaining('Gefiltert: Ampel: Steinpilz & Co.'),
          findsOneWidget);
      expect(find.byType(MushroomIcon), findsNWidgets(3),
          reason: 'die Gruppenwahl versteckt keine Spots');
    });
  });

  testWidgets('das Blatt bleibt unter 320 px auf dem Telefon',
      (tester) async {
    // **Die Zusage misst die HÖHE, nicht die Zeilen** — und das ist
    // keine Bequemlichkeit. Der Testrahmen rendert mit einer
    // Prüfschrift, deren Zeichen alle gleich breit sind und rund doppelt
    // so breit wie Roboto: „Ampel günstig" ist hier 179 px und auf dem
    // Gerät etwa 94. Eine Zusage „die drei Chips stehen in einer Zeile"
    // wäre damit eine Aussage über die Schrift des Testrahmens, nicht
    // über die App (Lehre aus #414: „ein Test, der dort scheitert, misst
    // die Testhülle").
    //
    // Die Höhe trägt trotzdem: Gemessen sind die 299 px MIT dem
    // ungünstigen Umbruch auf drei Zeilen, auf dem Gerät ist es weniger.
    // Vorher waren es 435 px, davon 210 für drei `SwitchListTile`.
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    backend.addSpot(ownerId: me.id, name: 'Hang', species: 'Steinpilz');
    await pumpApp(tester, backend);
    await onPhone(tester);
    await tester.tap(find.byTooltip('Karte filtern'));
    await settle(tester);

    for (final label in ['Nur meine', 'Ampel günstig', 'Saison']) {
      expect(find.widgetWithText(FilterChip, label), findsOneWidget,
          reason: label);
    }
    expect(tester.getRect(find.byType(BottomSheet)).height, lessThan(320),
        reason: 'die drei Filter sollen keine Schaltzeilen mehr sein');
  });

  testWidgets('„Nur meine Spots" blendet die der Freundin aus',
      (tester) async {
    final (backend, _) = backendWithSpots();
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Karte filtern'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Nur meine'));
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

    // Der Monat kommt aus dem Harness (`month:`), nicht von der Uhr —
    // sonst wäre dieser Test im September grün und im Dezember rot.

    testWidgets('im Juli bleibt der Pfifferling, im Dezember der andere',
        (tester) async {
      await pumpApp(tester, backendWithSeasons(),
          month: 7);

      expect(find.byType(MushroomIcon), findsNWidgets(2));
      await tester.tap(find.byTooltip('Karte filtern'));
      await settle(tester);
      // Zahl und Monat stehen am Chip, damit er sagt, was er tun wird,
      // bevor man ihn antippt — seit 1.181.0 als Tooltip statt als
      // Untertitel, die Aussage ist dieselbe geblieben.
      expect(
          tester
              .widget<FilterChip>(find.widgetWithText(FilterChip, 'Saison'))
              .tooltip,
          '1 Fundstelle im Juli');
      await tester.tap(find.widgetWithText(FilterChip, 'Saison'));
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
          month: 5);
      await tester.tap(find.byTooltip('Karte filtern'));
      await settle(tester);

      // **Seit 1.181.0 trägt den Grund der Chip, nicht ein Untertitel.**
      // Die Zusage aus #399 ist dieselbe geblieben — gesperrt UND
      // begründet —, nur die Stelle hat gewechselt: Tooltip am Chip und
      // erster Absatz im „i". Beide werden hier geprüft, denn einer
      // allein wäre der halbe Nachweis.
      final chip = tester.widget<FilterChip>(
          find.widgetWithText(FilterChip, 'Saison'));
      expect(chip.onSelected, isNull, reason: 'gesperrt');
      expect(chip.tooltip, contains('Im Mai hat keine deiner Arten Saison'));

      await tester.tap(find.byType(InfoButton));
      await settle(tester);
      expect(
          find.textContaining('Im Mai hat keine deiner Arten Saison'),
          findsOneWidget,
          reason: 'der Grund steht im „i" ganz oben');
    });
  });

}
