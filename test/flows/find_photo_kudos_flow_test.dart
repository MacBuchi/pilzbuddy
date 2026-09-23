// Kudos für Fundfotos (#532 Stufe 4, Patch 028) — ein Pilz je Buddy und
// Foto, keine Skala.
//
// Die Fakes spiegeln die drei Policies (`fpk_select`, `fpk_insert`,
// `fpk_delete`); ob die echte Datenbank dasselbe tut, beweist hier
// nichts — das leisten Schema Dry Run und Schema Check.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/widgets/photo_overlay.dart';
import 'package:pilzbuddy/features/spots/find_photo_providers.dart';
import 'package:pilzbuddy/features/spots/widgets/find_photo_strip.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../fakes/fake_backend.dart';
import '../fakes/photo_fixtures.dart';
import '../fakes/test_app.dart';

void main() {
  FakeFindPhotoRow seedPhoto(FakeBackend backend, FakeUser owner,
      String findId, {String id = 'p1'}) {
    final now = DateTime.now().toUtc();
    final key = '${owner.id}/$id';
    final row = FakeFindPhotoRow(
      id: id,
      findId: findId,
      userId: owner.id,
      key: key,
      createdAt: now.subtract(const Duration(hours: 1)),
      expiresAt: now.add(const Duration(days: 10)),
    );
    backend.findPhotos.add(row);
    backend.photoObjects['$key.jpg'] = cleanJpeg(width: 64, height: 48);
    backend.photoObjects['${key}_s.jpg'] = cleanJpeg();
    return row;
  }

  /// testpilz teilt ein Foto, waldfee ist Buddy.
  (FakeBackend, FakeUser, FakeUser, FakeFindPhotoRow) scene() {
    final backend = FakeBackend();
    final owner = backend.addUser(username: 'testpilz');
    final buddy = backend.addUser(username: 'waldfee');
    backend.addFriendship(owner.id, buddy.id);
    backend.addSpot(ownerId: owner.id, name: 'Buchenhang', species: 'Steinpilz');
    final row = seedPhoto(backend, owner, backend.spots.single.finds.single.id);
    return (backend, owner, buddy, row);
  }

  Future<void> openPhoto(WidgetTester tester, String photoId) async {
    await openTab(tester, 'Buddys');
    await tester.tap(find.descendant(
        of: find.byKey(kFindPhotoGalleryKey),
        matching: find.byKey(findPhotoTileKey(photoId))));
    await settle(tester);
    expect(find.byKey(kPhotoViewKey), findsOneWidget);
  }

  testWidgets('ein Buddy gibt einen Pilz — und nimmt ihn zurück',
      (tester) async {
    final (backend, _, buddy, row) = scene();
    backend.signInAs(buddy.id);
    await pumpApp(tester, backend);
    await openPhoto(tester, row.id);

    expect(find.text('Pilz geben'), findsOneWidget);
    await tester.tap(find.byKey(kKudosButtonKey));
    await settle(tester);
    expect(backend.findPhotoKudos, [(photoId: row.id, userId: buddy.id)]);
    expect(find.text('🍄 von dir'), findsOneWidget,
        reason: 'der Zähler zieht in der offenen Ansicht nach');
    expect(find.text('Pilz zurücknehmen'), findsOneWidget);

    await tester.tap(find.byKey(kKudosButtonKey));
    await settle(tester);
    expect(backend.findPhotoKudos, isEmpty);
    expect(find.textContaining('🍄 von'), findsNothing);
    expect(find.text('Pilz geben'), findsOneWidget);
  });

  testWidgets('am eigenen Foto kein Knopf — aber die Namen und die Zahl',
      (tester) async {
    final (backend, owner, buddy, row) = scene();
    backend.findPhotoKudos.add((photoId: row.id, userId: buddy.id));
    backend.signInAs(owner.id);
    await pumpApp(tester, backend);

    await openTab(tester, 'Buddys');
    final chip = find.descendant(
        of: find.byKey(kFindPhotoGalleryKey),
        matching: find.byKey(findPhotoKudosKey(row.id)));
    expect(chip, findsOneWidget);
    expect(find.descendant(of: chip, matching: find.text('🍄 1')),
        findsOneWidget);

    await openPhoto(tester, row.id);
    expect(find.byKey(kKudosButtonKey), findsNothing);
    expect(find.text('🍄 von waldfee'), findsOneWidget);
  });

  testWidgets('wer nicht mein Buddy ist, wird gezählt, nicht genannt',
      (tester) async {
    final (backend, owner, buddy, row) = scene();
    // pilzfee ist Buddy von testpilz, aber nicht von waldfee.
    final stranger = backend.addUser(username: 'pilzfee');
    backend.addFriendship(owner.id, stranger.id);
    backend.findPhotoKudos
      ..add((photoId: row.id, userId: stranger.id))
      ..add((photoId: row.id, userId: buddy.id));
    backend.signInAs(buddy.id);
    await pumpApp(tester, backend);
    await openPhoto(tester, row.id);
    expect(find.text('🍄 von dir und 1 weiteren Buddy'), findsOneWidget);
    expect(find.textContaining('pilzfee'), findsNothing);
  });

  testWidgets('das Foto zurücknehmen nimmt seine Kudos mit', (tester) async {
    final (backend, owner, buddy, row) = scene();
    backend.findPhotoKudos.add((photoId: row.id, userId: buddy.id));
    backend.signInAs(owner.id);
    await pumpApp(tester, backend);
    await openPhoto(tester, row.id);
    await tester.tap(find.text('Zurücknehmen'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Zurücknehmen'));
    await settle(tester);
    expect(backend.findPhotos, isEmpty);
    expect(backend.findPhotoKudos, isEmpty, reason: 'on delete cascade');
  });

  test('die Policies im Fake: nicht ans eigene, nicht ans unsichtbare, '
      'nur einmal', () async {
    final (backend, owner, buddy, row) = scene();
    final stranger = backend.addUser(username: 'fremd');
    final repo = FakeFindPhotoRepository(backend);

    backend.signInAs(owner.id);
    await expectLater(repo.giveKudos(row.id),
        throwsA(isA<PostgrestException>()));

    backend.signInAs(stranger.id);
    await expectLater(repo.giveKudos(row.id),
        throwsA(isA<PostgrestException>()));

    backend.signInAs(buddy.id);
    await repo.giveKudos(row.id);
    await repo.giveKudos(row.id);
    expect(backend.findPhotoKudos, hasLength(1));
    expect(backend.findPhotoKudos.single.userId, buddy.id);

    // Zurücknehmen trifft nur die eigenen.
    backend.signInAs(owner.id);
    await repo.takeBackKudos(row.id);
    expect(backend.findPhotoKudos, hasLength(1));
  });

  group('kudosLine', () {
    const names = {'a': 'Anna', 'b': 'bert', 'c': 'Carla'};
    test('ohne Kudos keine Zeile', () {
      expect(kudosLine(const [], 'me', names), isNull);
    });
    test('dir zuerst, dann alphabetisch, ohne Rücksicht auf Groß/Klein', () {
      expect(kudosLine(const ['c', 'me', 'b', 'a'], 'me', names),
          '🍄 von dir, Anna, bert und Carla');
    });
    test('Unbekannte werden gezählt, Einzahl und Mehrzahl', () {
      expect(kudosLine(const ['x'], 'me', names), '🍄 von 1 weiteren Buddy');
      expect(kudosLine(const ['a', 'x', 'y'], 'me', names),
          '🍄 von Anna und 2 weiteren Buddys');
    });
  });
}
