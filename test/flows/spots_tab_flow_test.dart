// Der Reiter „Spots" (#509) — vom Reiter aus, nicht aus dem Modell.
//
// Die Reihenfolge und die Gruppen prüft `test/spot_list_test.dart`; hier
// geht es um das, was nur die zusammengebaute App beantworten kann: dass
// die Zeile das Blatt öffnet, dass das Kartensymbol wirklich auf der
// KARTE landet (und damit `kMapBranchIndex` stimmt), dass die Statistik
// angekommen ist — und dass ein Blick in die Liste die Buddy-Meldung auf
// der Karte NICHT auffrisst.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/core/widgets/mushroom_icon.dart';
import 'package:pilzbuddy/features/spots/spot_providers.dart';
import 'package:pilzbuddy/features/spots/widgets/spot_stats_view.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  /// Fester „heute" — sonst hinge „vor 3 Tagen" am Kalender des Laufs.
  final heute = DateTime(2026, 9, 21);

  Future<void> openSpots(WidgetTester tester, FakeBackend backend,
      {FakeSettings? settings}) async {
    await pumpApp(tester, backend,
        settings: settings,
        extraOverrides: [todayProvider.overrideWithValue(heute)]);
    await openTab(tester, 'Spots');
  }

  Finder statsScroll() => find.descendant(
      of: find.byType(SpotStatsView), matching: find.byType(Scrollable));

  testWidgets('die Liste nennt Ort, letzten Eintrag und Buddy',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id);
    backend.addSpot(
        ownerId: me.id,
        name: 'Buchenhang',
        species: 'Steinpilz',
        count: 5,
        foundOn: DateTime(2026, 9, 18));
    backend.addSpot(
        ownerId: lilli.id,
        lat: 51.5,
        name: 'Alte Eiche',
        species: 'Pfifferling',
        foundOn: DateTime(2026, 9, 20));
    await openSpots(tester, backend);

    // Neueste Aktivität oben — Lillis Fund von gestern vor meinem von
    // vorgestern.
    final zeilen = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    expect(zeilen.indexOf('Alte Eiche'),
        lessThan(zeilen.indexOf('Buchenhang')));

    expect(find.text('gestern'), findsOneWidget);
    expect(find.text('vor 3 Tagen'), findsOneWidget);
    expect(find.text('Steinpilz, 5 Stück'), findsOneWidget);
    // Fremde Einträge nennen ihren Buddy — hier steht er zweimal, am
    // Eintrag und als Besitzer der Stelle.
    expect(find.textContaining('lilli92'), findsWidgets);
  });

  testWidgets('Antippen öffnet das Blatt, das Kartensymbol die Karte',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id,
        name: 'Buchenhang',
        lat: 50.5,
        lng: 12.5,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 20));
    await openSpots(tester, backend);

    // 1. Die Zeile öffnet das Spot-Blatt AN ORT UND STELLE — die
    //    Reiterleiste bleibt, man verliert seinen Platz in der Liste
    //    nicht.
    await tester.tap(find.text('Buchenhang'));
    await settle(tester);
    expect(find.text('Fund eintragen'), findsOneWidget);
    expect(find.byType(FakeMapView), findsNothing);

    await tester.tapAt(const Offset(20, 20));
    await settle(tester);

    // 2. Das Kartensymbol wechselt den Reiter UND zentriert (#345).
    await tester.tap(find.byTooltip('Auf der Karte zeigen'));
    await settle(tester);
    expect(find.text('Neuer Spot'), findsOneWidget,
        reason: 'der Karten-Reiter ist da — kMapBranchIndex stimmt');
    expect(tester.state<FakeMapViewState>(find.byType(FakeMapView)).center,
        const LatLng(50.5, 12.5));
  });

  testWidgets('Vormerkung und Buddy ohne Detail-Freigabe stehen getrennt',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92', shareDetails: false);
    backend.addFriendship(lilli.id, me.id);
    backend.addSpot(ownerId: me.id, name: 'Fichtenschonung');
    backend.addSpot(
        ownerId: lilli.id,
        lat: 51.5,
        name: 'Lillis Stelle',
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 1));
    await openSpots(tester, backend);

    expect(find.text('Vorgemerkt'), findsOneWidget);
    // Der Buddy-Spot ohne Freigabe darf NICHT als Vormerkung dastehen —
    // das wäre eine Absicht, die niemand geäußert hat.
    expect(find.text('Ohne Einträge'), findsOneWidget);
    expect(find.text('Nur der Standort wurde geteilt.'), findsOneWidget);
    expect(find.text('Steinpilz'), findsNothing);
  });

  testWidgets('die Suche filtert über Name und Art', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id,
        name: 'Buchenhang',
        species: 'Flaschenstäubling',
        foundOn: DateTime(2026, 9, 1));
    backend.addSpot(
        ownerId: me.id,
        lat: 51.5,
        name: 'Am Bach',
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 2));
    await openSpots(tester, backend);

    // Andere Schreibweise, derselbe Pilz (#395).
    await tester.enterText(find.byType(TextField), 'Staeubling');
    await settle(tester);
    expect(find.text('Buchenhang'), findsOneWidget);
    expect(find.text('Am Bach'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Trüffel');
    await settle(tester);
    expect(find.textContaining('Kein Spot passt'), findsOneWidget);
  });

  testWidgets('der Statistik-Reiter zeigt Kennzahlen, Saison und Top-Arten',
      (tester) async {
    // Dieselben Daten wie früher im Profil-Test (#509 hat sie hierher
    // geholt), plus ein Fund vom 8. Oktober 2025: Der liegt NACH dem
    // heutigen Tag im Jahresverlauf und darf im Vorjahresvergleich
    // deshalb nicht mitzählen — sonst stünde man jeden Herbst im
    // Rückstand gegen ein volles Vorjahr.
    final (backend, me) = loggedInBackend();
    final spotA = backend.addSpot(
        ownerId: me.id, species: 'Steinpilz', foundOn: DateTime(2026, 9, 1));
    backend.addFindRow(spotA,
        species: 'Steinpilz', foundOn: DateTime(2026, 9, 3));
    final spotB = backend.addSpot(
        ownerId: me.id,
        lat: 51.5,
        species: 'Pfifferling',
        foundOn: DateTime(2025, 8, 2));
    backend.addFindRow(spotB,
        species: 'Pfifferling', foundOn: DateTime(2025, 10, 8));
    await openSpots(tester, backend);
    await tester.tap(find.text('Statistik'));
    await settle(tester);

    expect(find.text('Funde'), findsOneWidget);
    expect(find.text('4'), findsWidgets);
    // Die Saison rechnet bis zum selben Tag: 2026 zwei Funde, 2025 einer.
    expect(find.text('Saison 2026'), findsOneWidget);
    expect(find.text('2 Funde, 1 Art'), findsOneWidget);
    expect(find.textContaining('Im Vorjahr waren es bis zum selben Tag 1.'),
        findsOneWidget);

    await tester.scrollUntilVisible(find.text('Mein Jahresgang'), 200,
        scrollable: statsScroll());
    expect(find.textContaining('Stärkster Monat: September mit 2 Funden'),
        findsOneWidget);

    await tester.scrollUntilVisible(find.text('Top-Arten'), 200,
        scrollable: statsScroll());
    // Jede Art-Zeile zeigt ihr eigenes Icon — vorher fünf gleiche 🍄 (#103).
    expect(
        find.descendant(
          of: find.ancestor(
              of: find.text('Top-Arten'), matching: find.byType(Card)),
          matching: find.byType(MushroomIcon),
        ),
        findsNWidgets(2));
  });

  testWidgets('ein Blick in die Liste schaltet die Buddy-Meldung nicht stumm',
      (tester) async {
    // Die Zusage aus #349/#425: Wer nicht erkennen kann, dass er etwas
    // abgeschaltet hat, hält es für kaputt. Der Reiter LIEST den Marker,
    // gesetzt wird er allein im Banner.
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id);
    final spotId = backend.addSpot(
        ownerId: me.id, species: 'Steinpilz', foundOn: DateTime(2026, 9, 1));
    backend.addFindRow(spotId,
        species: 'Parasol',
        foundOn: DateTime(2026, 9, 20),
        createdAt: DateTime.utc(2026, 9, 20, 12),
        authorId: lilli.id);
    final settings = FakeSettings(lastFindSeenAt: DateTime.utc(2020));
    await openSpots(tester, backend, settings: settings);

    // In der Liste ist die Neuigkeit zu sehen …
    expect(find.text('neu'), findsOneWidget);

    // … und auf der Karte steht das Banner danach unverändert.
    await openTab(tester, 'Karte');
    expect(
        find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? '').contains('Neuer Fund von')),
        findsOneWidget);
    expect(settings.lastFindSeenAt, DateTime.utc(2020));
  });
}
