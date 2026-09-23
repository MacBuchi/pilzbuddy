// Die Fotogalerie im Reiter „Buddys" (#532 Stufe 3) — durch die echte
// Oberfläche.
//
// Drei Zusagen: Die Galerie zeigt dieselbe Liste wie der Streifen im
// Reiter „Spots" (keine eigene Abfrage, also auch keine eigenen
// Sichtbarkeitsregeln). Der Neu-Punkt hängt nur an FREMDEN Fotos und
// geht erst beim ÖFFNEN weg. Und der Ring sagt die Restzeit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/widgets/photo_overlay.dart';
import 'package:pilzbuddy/features/spots/widgets/find_photo_strip.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/photo_fixtures.dart';
import '../fakes/test_app.dart';

void main() {
  /// Ich (testpilz) und ein Buddy (waldfee), je ein Spot mit einem Fund.
  (FakeBackend, FakeUser, FakeUser) twoBuddies() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    final buddy = backend.addUser(username: 'waldfee');
    backend.addFriendship(me.id, buddy.id);
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz');
    backend.addSpot(
        ownerId: buddy.id, name: 'Fichtenschonung', species: 'Pfifferling',
        lat: 51.2, lng: 10.5);
    backend.signInAs(me.id);
    return (backend, me, buddy);
  }

  FakeFindPhotoRow seedPhoto(FakeBackend backend, FakeUser owner,
      String findId, {required String id, Duration age = const Duration(hours: 1),
      Duration left = const Duration(days: 10)}) {
    final now = DateTime.now().toUtc();
    final key = '${owner.id}/$id';
    final row = FakeFindPhotoRow(
      id: id,
      findId: findId,
      userId: owner.id,
      key: key,
      createdAt: now.subtract(age),
      expiresAt: now.add(left),
    );
    backend.findPhotos.add(row);
    backend.photoObjects['$key.jpg'] = cleanJpeg(width: 64, height: 48);
    backend.photoObjects['${key}_s.jpg'] = cleanJpeg();
    return row;
  }

  Finder inGallery(Finder matching) =>
      find.descendant(of: find.byKey(kFindPhotoGalleryKey), matching: matching);

  testWidgets('ohne Fotos keine Galerie — kein Titel über nichts',
      (tester) async {
    final (backend, _, _) = twoBuddies();
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');
    expect(find.byKey(kFindPhotoGalleryKey), findsNothing);
    expect(find.text('Buddys zu PilzBuddy einladen'), findsOneWidget);
  });

  testWidgets('eigene und fremde Fotos, jüngste zuerst, über allem anderen',
      (tester) async {
    final (backend, me, buddy) = twoBuddies();
    final mine = seedPhoto(backend, me, backend.spots.first.finds.single.id,
        id: 'mine', age: const Duration(days: 2));
    final theirs = seedPhoto(backend, buddy, backend.spots.last.finds.single.id,
        id: 'theirs', age: const Duration(hours: 3));
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');

    final a = tester.getTopLeft(inGallery(find.byKey(findPhotoTileKey(theirs.id))));
    final b = tester.getTopLeft(inGallery(find.byKey(findPhotoTileKey(mine.id))));
    expect(a.dx, lessThan(b.dx), reason: 'das jüngere steht vorn');
    expect(
        tester.getTopLeft(find.byKey(kFindPhotoGalleryKey)).dy,
        lessThan(tester.getTopLeft(find.text('Buddys zu PilzBuddy einladen')).dy),
        reason: 'ganz oben — es ist das, was sich hier ändert');
  });

  testWidgets('der Neu-Punkt: nur am fremden Foto, weg erst nach dem Öffnen '
      '— und gemerkt, ohne Karteileichen', (tester) async {
    final (backend, me, buddy) = twoBuddies();
    final mine = seedPhoto(backend, me, backend.spots.first.finds.single.id,
        id: 'mine');
    final theirs = seedPhoto(backend, buddy, backend.spots.last.finds.single.id,
        id: 'theirs');
    // Ein längst abgelaufenes Foto steht noch in der Menge.
    final settings = FakeSettings(seenFindPhotoIds: {'laengst-weg'});
    await pumpApp(tester, backend, settings: settings);
    await openTab(tester, 'Buddys');

    expect(find.text('Fundfotos · 1 neu'), findsOneWidget);
    expect(inGallery(find.byKey(findPhotoNewKey(theirs.id))), findsOneWidget);
    expect(inGallery(find.byKey(findPhotoNewKey(mine.id))), findsNothing,
        reason: 'das eigene hat man selbst hochgeladen');

    await tester.tap(inGallery(find.byKey(findPhotoTileKey(theirs.id))));
    await settle(tester);
    expect(find.byKey(kPhotoViewKey), findsOneWidget);
    expect(find.textContaining('von waldfee · Fichtenschonung'),
        findsOneWidget);
    expect(find.textContaining('Noch 9 Tage sichtbar'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    expect(inGallery(find.byKey(findPhotoNewKey(theirs.id))), findsNothing);
    expect(find.text('Fundfotos'), findsOneWidget);
    expect(settings.seenFindPhotoIds, {theirs.id},
        reason: 'gemerkt — und auf lebende Fotos gestutzt');
  });

  testWidgets('schon gesehen bleibt gesehen, auch nach dem Neustart',
      (tester) async {
    final (backend, _, buddy) = twoBuddies();
    final theirs = seedPhoto(backend, buddy, backend.spots.last.finds.single.id,
        id: 'theirs');
    await pumpApp(tester, backend,
        settings: FakeSettings(seenFindPhotoIds: {theirs.id}));
    await openTab(tester, 'Buddys');
    expect(find.byKey(findPhotoTileKey(theirs.id)), findsWidgets);
    expect(find.byKey(findPhotoNewKey(theirs.id)), findsNothing);
    expect(find.text('Fundfotos'), findsOneWidget);
  });

  testWidgets('der Ring sagt die Restzeit — voll bei frischen, fast leer '
      'kurz vor Ablauf', (tester) async {
    final (backend, me, buddy) = twoBuddies();
    final fresh = seedPhoto(backend, me, backend.spots.first.finds.single.id,
        id: 'fresh', left: const Duration(days: 13, hours: 23));
    final old = seedPhoto(backend, buddy, backend.spots.last.finds.single.id,
        id: 'old', left: const Duration(hours: 5));
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');

    double valueOf(FakeFindPhotoRow row) => tester
        .widget<CircularProgressIndicator>(inGallery(find.descendant(
            of: find.byKey(findPhotoRingKey(row.id)),
            matching: find.byType(CircularProgressIndicator))))
        .value!;
    expect(valueOf(fresh), greaterThan(0.99));
    expect(valueOf(old), lessThan(0.02));
    expect(inGallery(find.byTooltip('Noch 13 Tage sichtbar')), findsOneWidget);
    expect(inGallery(find.byTooltip('Läuft heute ab')), findsOneWidget);
  });

  testWidgets('„Zum Spot" führt aus der Galerie ins Spot-Blatt',
      (tester) async {
    final (backend, _, buddy) = twoBuddies();
    final theirs = seedPhoto(backend, buddy, backend.spots.last.finds.single.id,
        id: 'theirs');
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');
    await tester.tap(inGallery(find.byKey(findPhotoTileKey(theirs.id))));
    await settle(tester);
    await tester.tap(find.text('Zum Spot'));
    await settle(tester);
    expect(find.byKey(kPhotoViewKey), findsNothing);
    expect(find.text('Fichtenschonung'), findsWidgets);
    expect(find.text('Fund eintragen'), findsOneWidget,
        reason: 'das Spot-Blatt ist offen');
  });

  testWidgets('Schalter aus: die Galerie zeigt nur die eigenen',
      (tester) async {
    final (backend, me, buddy) = twoBuddies();
    final mine = seedPhoto(backend, me, backend.spots.first.finds.single.id,
        id: 'mine');
    final theirs = seedPhoto(backend, buddy, backend.spots.last.finds.single.id,
        id: 'theirs');
    await pumpApp(tester, backend,
        settings: FakeSettings(findPhotosEnabled: false));
    await openTab(tester, 'Buddys');
    expect(inGallery(find.byKey(findPhotoTileKey(mine.id))), findsOneWidget);
    expect(inGallery(find.byKey(findPhotoTileKey(theirs.id))), findsNothing);
    expect(find.text('Fundfotos'), findsOneWidget, reason: 'nichts „neu"');
  });
}
