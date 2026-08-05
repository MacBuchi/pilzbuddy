// Szenario: Punkte importieren — je Punkt einen Spot anlegen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/import_export/import_screen.dart';
import 'package:pilzbuddy/features/import_export/waypoint_parser.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  testWidgets('Importierte Punkte werden einzeln als Spots angelegt',
      (tester) async {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    addTearDown(backend.dispose);

    final waypoints = [
      ImportedWaypoint(
          name: 'Edelreizker Spechbach',
          lat: 51.2,
          lng: 10.4,
          time: DateTime(2024, 10, 27, 16, 25)),
      const ImportedWaypoint(lat: 51.3, lng: 10.5),
    ];

    await tester.pumpWidget(ProviderScope(
      overrides: overridesFor(backend),
      child: MaterialApp(
        home: ImportScreen(initialWaypoints: waypoints),
      ),
    ));
    await settle(tester);

    expect(find.textContaining('2 Punkte gefunden'), findsOneWidget);
    expect(find.text('Edelreizker Spechbach'), findsOneWidget);
    expect(find.text('Punkt 2'), findsOneWidget);

    // Ersten Punkt anlegen — Name, erkannte Art und Funddatum aus dem
    // GPX sind schon vorbefüllt.
    await tester.tap(find.text('Anlegen').first);
    await settle(tester);
    expect(find.text('Neuer Pilz-Spot'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Edelreizker Spechbach'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, 'Edelreizker'), findsOneWidget);
    expect(find.text('27.10.2024'), findsOneWidget);

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'), warnIfMissed: false);
    await settle(tester);

    expect(backend.spots, hasLength(1));
    expect(backend.spots.single.lat, closeTo(51.2, 1e-9));
    expect(backend.spots.single.name, 'Edelreizker Spechbach');
    expect(backend.spots.single.finds.single.species, 'Edelreizker');
    expect(backend.spots.single.finds.single.foundOn,
        DateTime(2024, 10, 27, 16, 25));
    expect(find.text('Angelegt'), findsOneWidget);
    // Der zweite Punkt wartet noch.
    expect(find.text('Anlegen'), findsOneWidget);
  });

  group('Wiederherstellung aus einer PilzBuddy-Sicherung (#112)', () {
    /// Ein Wegpunkt mit vollen PilzBuddy-Daten, wie ihn der Parser aus
    /// den `<extensions>` liefert.
    ImportedWaypoint backup({
      String? name,
      double lat = 51.2,
      double lng = 10.4,
      bool sharingExcluded = false,
      List<ImportedFind> finds = const [],
    }) =>
        ImportedWaypoint(
          name: name,
          lat: lat,
          lng: lng,
          finds: finds,
          sharingExcluded: sharingExcluded,
        );

    Future<void> pumpImport(
        WidgetTester tester, FakeBackend backend, List<ImportedWaypoint> w,
        {ProviderContainer? container}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: overridesFor(backend),
        child: MaterialApp(home: ImportScreen(initialWaypoints: w)),
      ));
      await settle(tester);
    }

    testWidgets('legt Spots samt Funden, Notizen und Freigabe-Flag an',
        (tester) async {
      final backend = FakeBackend();
      backend.signInAs(backend.addUser(username: 'testpilz').id);
      addTearDown(backend.dispose);

      await pumpImport(tester, backend, [
        backup(name: 'Buchenhang', sharingExcluded: true, finds: [
          ImportedFind(
              species: 'Steinpilz',
              count: 5,
              foundOn: DateTime(2026, 7, 12),
              note: 'am umgestürzten Baum'),
          ImportedFind(species: 'Marone', foundOn: DateTime(2026, 8, 1)),
        ]),
        backup(name: 'Fichtenkante', lat: 51.3, lng: 10.5, finds: [
          ImportedFind(species: 'Pfifferling', foundOn: DateTime(2026, 7, 20)),
        ]),
      ]);

      // Der andere Ablauf: kein „Anlegen" je Punkt, sondern Auswahl.
      expect(find.text('PilzBuddy-Sicherung erkannt'), findsOneWidget);
      expect(find.text('Anlegen'), findsNothing);
      expect(find.textContaining('2 Funde'), findsOneWidget);

      await tester.tap(find.text('2 Spots übernehmen'));
      await settle(tester);

      expect(backend.spots, hasLength(2));
      final hang = backend.spots.firstWhere((s) => s.name == 'Buchenhang');
      expect(hang.sharingExcluded, isTrue);
      expect(hang.finds, hasLength(2));
      final steinpilz =
          hang.finds.firstWhere((f) => f.species == 'Steinpilz');
      expect(steinpilz.count, 5);
      expect(steinpilz.foundOn, DateTime(2026, 7, 12));
      expect(steinpilz.note, 'am umgestürzten Baum');
      expect(find.textContaining('2 Spots wiederhergestellt'), findsOneWidget);
    });

    testWidgets('ein Spot ohne Funde bleibt ein Spot ohne Funde',
        (tester) async {
      // Die App kennt Spots ohne Fund („Nur der Standort wurde geteilt").
      // Beim Wiederherstellen einen leeren Fund zu erfinden wäre Datenmüll.
      final backend = FakeBackend();
      backend.signInAs(backend.addUser(username: 'testpilz').id);
      addTearDown(backend.dispose);

      await pumpImport(tester, backend, [backup(name: 'Leerer')]);
      expect(find.textContaining('noch kein Fund'), findsOneWidget);

      await tester.tap(find.text('1 Spot übernehmen'));
      await settle(tester);

      expect(backend.spots.single.finds, isEmpty);
    });

    testWidgets('vorhandene Spots sind markiert und nicht angehakt',
        (tester) async {
      final backend = FakeBackend();
      final me = backend.addUser(username: 'testpilz');
      backend.signInAs(me.id);
      addTearDown(backend.dispose);
      backend.addSpot(
          ownerId: me.id, lat: 51.2, lng: 10.4, name: 'Buchenhang');

      await pumpImport(tester, backend, [
        backup(name: 'Buchenhang', finds: [
          ImportedFind(species: 'Steinpilz', foundOn: DateTime(2026, 7, 12)),
        ]),
        backup(name: 'Neuer', lat: 51.9, lng: 10.9, finds: [
          ImportedFind(species: 'Marone', foundOn: DateTime(2026, 8, 1)),
        ]),
      ]);

      expect(find.textContaining('hast du schon'), findsWidgets);
      // Nur der neue ist vorausgewählt — die Datei zweimal einzuspielen
      // legt so nichts doppelt an.
      expect(find.text('1 Spot übernehmen'), findsOneWidget);

      await tester.tap(find.text('1 Spot übernehmen'));
      await settle(tester);

      expect(backend.spots, hasLength(2));
      expect(backend.spots.where((s) => s.name == 'Buchenhang'), hasLength(1));
    });

    testWidgets('ein Duplikat lässt sich trotzdem anhaken', (tester) async {
      // Die App entscheidet nicht über den Kopf des Nutzers hinweg: Zwei
      // Spots an derselben Stelle sind nicht verboten.
      final backend = FakeBackend();
      final me = backend.addUser(username: 'testpilz');
      backend.signInAs(me.id);
      addTearDown(backend.dispose);
      backend.addSpot(
          ownerId: me.id, lat: 51.2, lng: 10.4, name: 'Buchenhang');

      await pumpImport(tester, backend, [
        backup(name: 'Buchenhang', finds: [
          ImportedFind(species: 'Steinpilz', foundOn: DateTime(2026, 7, 12)),
        ]),
      ]);

      await tester.tap(find.byType(Checkbox));
      await settle(tester);
      await tester.tap(find.text('1 Spot übernehmen'));
      await settle(tester);

      expect(backend.spots.where((s) => s.name == 'Buchenhang'), hasLength(2));
    });

    testWidgets('„Alle auswählen" und „Keine" wirken', (tester) async {
      final backend = FakeBackend();
      final me = backend.addUser(username: 'testpilz');
      backend.signInAs(me.id);
      addTearDown(backend.dispose);
      backend.addSpot(
          ownerId: me.id, lat: 51.2, lng: 10.4, name: 'Buchenhang');

      await pumpImport(tester, backend, [
        backup(name: 'Buchenhang'),
        backup(name: 'Neuer', lat: 51.9, lng: 10.9),
      ]);

      expect(find.text('1 Spot übernehmen'), findsOneWidget);
      await tester.tap(find.text('Alle auswählen'));
      await settle(tester);
      expect(find.text('2 Spots übernehmen'), findsOneWidget);

      await tester.tap(find.text('Keine'));
      await settle(tester);
      expect(find.text('0 Spots übernehmen'), findsOneWidget);
      // Ohne Auswahl gibt es nichts zu tun.
      final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '0 Spots übernehmen'));
      expect(button.onPressed, isNull);
    });

    testWidgets('eine gewöhnliche GPX-Datei nimmt weiter den alten Weg',
        (tester) async {
      // Der Punkt-für-Punkt-Pfad ist der Grund, warum es den Import gibt
      // — eine Sicherung ist der seltenere Fall und darf ihn nicht
      // verdrängen.
      final backend = FakeBackend();
      backend.signInAs(backend.addUser(username: 'testpilz').id);
      addTearDown(backend.dispose);

      await pumpImport(tester, backend,
          [const ImportedWaypoint(name: 'Fremd', lat: 51.2, lng: 10.4)]);

      expect(find.text('PilzBuddy-Sicherung erkannt'), findsNothing);
      expect(find.text('Anlegen'), findsOneWidget);
    });
  });
}
