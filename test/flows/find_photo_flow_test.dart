// Fundfotos für Buddys (#532) — durch die echte Oberfläche.
//
// **Die teuren Fälle sind die, in denen NICHTS zu sehen sein darf**:
// ein Buddy ohne Detail-Freigabe, ein Fremder, ein abgelaufenes Foto,
// ein Schalter auf aus. Und der eine Fall, der den ganzen Bau trägt:
// Was im Bucket landet, ist nackt — geprüft an den Bytes im Fake, nicht
// an einem Rückgabewert.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/photo_pipeline.dart';
import 'package:pilzbuddy/core/widgets/photo_overlay.dart';
import 'package:pilzbuddy/data/find_photo_repository.dart';
import 'package:pilzbuddy/features/spots/find_photo_providers.dart';
import 'package:pilzbuddy/features/spots/widgets/find_photo_strip.dart';
import 'package:pilzbuddy/models/find_photo.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_outbox.dart';
import '../fakes/fake_settings.dart';
import '../fakes/photo_fixtures.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  /// Ein Foto, das [owner] zu [findId] geteilt hat — direkt in Zeilen
  /// und Bucket, wie es nach einem Upload dort läge.
  FakeFindPhotoRow seedPhoto(FakeBackend backend, FakeUser owner,
      String findId, {String id = 'p1', DateTime? expiresAt}) {
    final now = DateTime.now().toUtc();
    final key = '${owner.id}/$id';
    final row = FakeFindPhotoRow(
      id: id,
      findId: findId,
      userId: owner.id,
      key: key,
      createdAt: now.subtract(const Duration(hours: 1)),
      expiresAt: expiresAt ?? now.add(const Duration(days: 10)),
    );
    backend.findPhotos.add(row);
    backend.photoObjects['$key.jpg'] = cleanJpeg(width: 64, height: 48);
    backend.photoObjects['${key}_s.jpg'] = cleanJpeg();
    return row;
  }

  Future<void> openSpot(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await settle(tester);
  }

  /// Tippt die Kamera am Fund, wählt „Galerie" und wartet, bis der
  /// Weg durch ist.
  Future<void> shareViaGallery(WidgetTester tester, String findId) async {
    await tester.tap(find.byKey(shareFindPhotoKey(findId)));
    await settle(tester);
    expect(find.text(kFindPhotoShareNote), findsOneWidget,
        reason: 'der Dialog sagt vorher, was passiert');
    await tester.tap(find.text('Galerie'));
    await settle(tester, frames: 12);
  }

  testWidgets('Teilen legt zwei nackte JPEGs in den Bucket und eine Zeile '
      'in die Tabelle — die Fundstelle bleibt auf dem Gerät', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz');
    final findId = backend.spots.single.finds.single.id;
    final picker = FakePhotoPicker(dirtyJpeg());
    await pumpApp(tester, backend, photoPicker: picker);

    await openSpot(tester, 'Buchenhang');
    expect(find.byKey(kFindPhotoStripKey), findsNothing,
        reason: 'ohne Foto kein Streifen');
    await shareViaGallery(tester, findId);

    expect(picker.sources, [PhotoSource.gallery]);
    final row = backend.findPhotos.single;
    expect(row.findId, findId);
    expect(row.userId, me.id);
    expect(row.key, startsWith('${me.id}/'),
        reason: 'der Ordner ist der Nutzer — die Upload-Policy verlangt es');
    expect(row.expiresAt.difference(row.createdAt).inDays, kFindPhotoDays);

    // **Die Bytes, nicht der Rückgabewert.** Das Rohbild trug GPS-EXIF,
    // XMP und einen Kommentar mit Ortsangabe — nichts davon darf im
    // Bucket liegen.
    expect(backend.photoObjects.keys,
        unorderedEquals(['${row.key}.jpg', '${row.key}_s.jpg']));
    for (final entry in backend.photoObjects.entries) {
      expect(jpegForeignMarkers(entry.value), isEmpty, reason: entry.key);
      expect(hasText(entry.value, 'Buchenhang'), isFalse, reason: entry.key);
      expect(hasText(entry.value, 'Exif'), isFalse, reason: entry.key);
    }

    // Quittung und Streifen im Blatt.
    expect(find.textContaining('Foto geteilt'), findsOneWidget);
    expect(find.byKey(kFindPhotoStripKey), findsOneWidget);
    expect(find.byKey(findPhotoTileKey(row.id)), findsOneWidget);
    expect(find.text('dein Foto'), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('der Posteingang ist der Reiter „Spots"', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz');
    final row = seedPhoto(backend, me, backend.spots.single.finds.single.id);
    await pumpApp(tester, backend);

    await openTab(tester, 'Spots');
    expect(find.byKey(kFindPhotoStripKey), findsOneWidget);
    expect(find.byKey(findPhotoTileKey(row.id)), findsOneWidget);

    // Tipp → groß, mit Art, Herkunft, Frist — und dem Weg zum Spot.
    await tester.tap(find.byKey(findPhotoTileKey(row.id)));
    await settle(tester);
    expect(find.byKey(kPhotoViewKey), findsOneWidget);
    expect(find.textContaining('Noch 9 Tage sichtbar'), findsOneWidget);
    expect(find.textContaining('Buchenhang'), findsWidgets);
    await tester.tap(find.text('Zum Spot'));
    await settle(tester);
    expect(find.byKey(kPhotoViewKey), findsNothing);
    expect(find.text('Fund eintragen'), findsOneWidget,
        reason: 'das Spot-Blatt ist offen');
    // Im Blatt steht das Foto noch einmal — ohne „Zum Spot", man ist ja
    // da. Gesucht IM Blatt: Der Streifen des Reiters liegt dahinter
    // weiter im Baum.
    final inSheet = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byKey(findPhotoTileKey(row.id)));
    expect(inSheet, findsOneWidget);
    await tester.tap(inSheet);
    await settle(tester);
    expect(find.byKey(kPhotoViewKey), findsOneWidget);
    expect(find.text('Zum Spot'), findsNothing);
  });

  testWidgets('der Buddy sieht es mit Detail-Freigabe — und ohne sie nicht',
      (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    final buddy = backend.addUser(username: 'waldfee');
    backend.addFriendship(me.id, buddy.id);
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz');
    final row = seedPhoto(backend, me, backend.spots.single.finds.single.id);
    final repo = FakeFindPhotoRepository(backend);

    backend.signInAs(buddy.id);
    await pumpApp(tester, backend, findPhotos: repo);
    await openTab(tester, 'Spots');
    expect(find.byKey(findPhotoTileKey(row.id)), findsOneWidget);
    expect(find.text('von testpilz'), findsOneWidget);
    expect(repo.loaded, contains('${row.key}_s.jpg'),
        reason: 'die Kachel holt die Vorschau');
    expect(repo.loaded, isNot(contains('${row.key}.jpg')),
        reason: 'das volle Bild erst auf Tipp');
    // Am fremden Fund gibt es keine Kamera — das Foto sagt „so sah MEIN
    // Fund aus", und die Policy ließe es ohnehin nicht zu.
    await tester.tap(find.text('Buchenhang').first);
    await settle(tester);
    expect(find.byKey(shareFindPhotoKey(row.findId)), findsNothing);
  });

  testWidgets('ohne Detail-Freigabe des Besitzers: nichts, auch kein Abruf',
      (tester) async {
    // Der Buddy sieht den Spot (Standort-Ebene), aber nicht den Fund —
    // und damit auch nicht das Foto, das daran hängt. Die Freigabe wird
    // GEERBT, nicht neu entschieden.
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz', shareDetails: false);
    final buddy = backend.addUser(username: 'waldfee');
    backend.addFriendship(me.id, buddy.id);
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz');
    final row = seedPhoto(backend, me, backend.spots.single.finds.single.id);
    final repo = FakeFindPhotoRepository(backend);

    backend.signInAs(buddy.id);
    await pumpApp(tester, backend, findPhotos: repo);
    await openTab(tester, 'Spots');
    expect(find.text('Buchenhang'), findsOneWidget, reason: 'der Spot schon');
    expect(find.byKey(kFindPhotoStripKey), findsNothing);
    expect(find.byKey(findPhotoTileKey(row.id)), findsNothing);
    expect(repo.loaded, isEmpty);
  });

  testWidgets('ein Fremder sieht nichts', (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    final stranger = backend.addUser(username: 'fremd');
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz');
    seedPhoto(backend, me, backend.spots.single.finds.single.id);
    final repo = FakeFindPhotoRepository(backend);

    backend.signInAs(stranger.id);
    await pumpApp(tester, backend, findPhotos: repo);
    await openTab(tester, 'Spots');
    expect(find.byKey(kFindPhotoStripKey), findsNothing);
    expect(repo.loaded, isEmpty);
  });

  testWidgets('abgelaufen ist weg — auch für den, der es geteilt hat',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz');
    seedPhoto(backend, me, backend.spots.single.finds.single.id,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)));
    await pumpApp(tester, backend);
    await openTab(tester, 'Spots');
    expect(find.byKey(kFindPhotoStripKey), findsNothing);
  });

  testWidgets('Schalter aus: keine Buddy-Fotos und kein Download — die '
      'eigenen bleiben', (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    final buddy = backend.addUser(username: 'waldfee');
    backend.addFriendship(me.id, buddy.id);
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz');
    backend.addSpot(
        ownerId: buddy.id, name: 'Fichtenschonung', species: 'Pfifferling',
        lat: 51.2, lng: 10.5);
    final mine = seedPhoto(backend, me, backend.spots.first.finds.single.id);
    final theirs = seedPhoto(backend, buddy, backend.spots.last.finds.single.id,
        id: 'p2');
    final repo = FakeFindPhotoRepository(backend);

    backend.signInAs(me.id);
    await pumpApp(tester, backend,
        findPhotos: repo, settings: FakeSettings(findPhotosEnabled: false));
    await openTab(tester, 'Spots');
    expect(find.byKey(findPhotoTileKey(mine.id)), findsOneWidget);
    expect(find.byKey(findPhotoTileKey(theirs.id)), findsNothing);
    expect(repo.loaded, isNot(contains('${theirs.key}_s.jpg')));

    // Einschalten im Profil — und das Foto des Buddys erscheint.
    await openTab(tester, 'Profil');
    await tester.scrollUntilVisible(
        find.text('Fundfotos von Buddys anzeigen'), 300);
    await tester.tap(find.text('Fundfotos von Buddys anzeigen'));
    await settle(tester);
    await openTab(tester, 'Spots');
    expect(find.byKey(findPhotoTileKey(theirs.id)), findsOneWidget);
  });

  testWidgets('offline scheitert sichtbar — kein Korb, kein Objekt',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz');
    final findId = backend.spots.single.finds.single.id;
    final outbox = FakeOutbox();
    await pumpApp(tester, backend,
        photoPicker: FakePhotoPicker(dirtyJpeg()), outbox: outbox);
    await openSpot(tester, 'Buchenhang');

    backend.offline = true;
    await shareViaGallery(tester, findId);
    expect(find.text('Keine Verbindung — bitte Internet prüfen.'),
        findsOneWidget);
    expect(backend.findPhotos, isEmpty);
    expect(backend.photoObjects, isEmpty);
    expect(outbox.jobs, isEmpty, reason: 'kein dritter Weg in den Korb');
    await drainSnackbars(tester);
  });

  testWidgets('Abbrechen im Wähler: nichts passiert, nichts gemeldet',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz');
    final findId = backend.spots.single.finds.single.id;
    await pumpApp(tester, backend, photoPicker: FakePhotoPicker(null));
    await openSpot(tester, 'Buchenhang');
    await shareViaGallery(tester, findId);
    expect(backend.findPhotos, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('ein Leergang bekommt keine Kamera', (tester) async {
    final (backend, me) = loggedInBackend();
    final spotId = backend.addSpot(ownerId: me.id, name: 'Buchenhang',
        species: 'Steinpilz');
    backend.addFindRow(spotId, blank: true, foundOn: DateTime(2026, 9, 20));
    await pumpApp(tester, backend);
    await openSpot(tester, 'Buchenhang');
    final finds = backend.spots.single.finds;
    final blank = finds.firstWhere((f) => f.blank);
    final real = finds.firstWhere((f) => !f.blank);
    expect(find.byKey(shareFindPhotoKey(real.id)), findsOneWidget);
    expect(find.byKey(shareFindPhotoKey(blank.id)), findsNothing);
  });

  testWidgets('Zurücknehmen löscht Zeile und Objekte', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz');
    final row = seedPhoto(backend, me, backend.spots.single.finds.single.id);
    await pumpApp(tester, backend);
    await openTab(tester, 'Spots');
    await tester.tap(find.byKey(findPhotoTileKey(row.id)));
    await settle(tester);
    await tester.tap(find.text('Zurücknehmen'));
    await settle(tester);
    expect(find.text('Foto zurücknehmen?'), findsOneWidget);
    await tester.tap(find.text('Zurücknehmen').last);
    await settle(tester);
    expect(backend.findPhotos, isEmpty);
    expect(backend.photoObjects, isEmpty);
    expect(find.byKey(kPhotoViewKey), findsNothing);
    expect(find.byKey(kFindPhotoStripKey), findsNothing);
  });

  test('FindPhoto.fromJson kommt ohne Embeds aus', () {
    // Der Fund ist zwischen zwei Abfragen unsichtbar geworden: Dann steht
    // das Foto ohne Art und Spot da, statt dass die Liste scheitert.
    final photo = FindPhoto.fromJson({
      'id': 'p',
      'find_id': 'f',
      'user_id': 'u',
      'key': 'u/p',
      'created_at': '2026-09-22T10:00:00Z',
      'expires_at': '2026-10-06T10:00:00Z',
      'profiles': null,
      'finds': null,
    }, myUid: 'u');
    expect(photo.isOwn, isTrue);
    expect(photo.species, isNull);
    expect(photo.spotId, isNull);
    expect(photo.fullPath, 'u/p.jpg');
    expect(photo.thumbPath, 'u/p_s.jpg');
    expect(photo.daysLeft(DateTime.utc(2026, 9, 30)), 6);
    expect(photo.daysLeft(DateTime.utc(2026, 10, 7)), 0);
    expect(Uint8List(0), isEmpty);
  });
}
