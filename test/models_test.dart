import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/dates.dart';
import 'package:pilzbuddy/models/find.dart';
import 'package:pilzbuddy/models/friendship.dart';
import 'package:pilzbuddy/models/spot.dart';

void main() {
  group('Find', () {
    test('label kombiniert Art und Anzahl', () {
      final find = Find(
          id: '1', spotId: 's', species: 'Steinpilz', count: 5,
          foundOn: DateTime(2026, 9, 23));
      expect(find.label, 'Steinpilz, 5 Stück');
    });

    test('label ohne Angaben fällt auf "Fund" zurück', () {
      final find = Find(id: '1', spotId: 's', foundOn: DateTime(2026, 9, 23));
      expect(find.label, 'Fund');
    });

    test('isoDate formatiert mit führenden Nullen (DB-Format found_on)', () {
      expect(isoDate(DateTime(2026, 3, 7)), '2026-03-07');
      expect(isoDate(DateTime(999, 12, 31)), '0999-12-31');
    });

    test('fromJson liest alle Felder', () {
      final find = Find.fromJson({
        'id': 'f1',
        'spot_id': 's1',
        'species': 'Pfifferling',
        'count': 12,
        'found_on': '2025-10-01',
        'note': 'unterm Moos',
      }, currentUserId: 'ich');
      expect(find.species, 'Pfifferling');
      expect(find.count, 12);
      expect(find.foundOn, DateTime(2025, 10, 1));
      expect(find.note, 'unterm Moos');
    });

    test('fromJson liest den Autor und setzt isOwn', () {
      final fremd = Find.fromJson({
        'id': 'f1',
        'spot_id': 's1',
        'found_on': '2026-08-01',
        'author_id': 'lilli',
        'author': {'username': 'lilli92', 'avatar': 3},
      }, currentUserId: 'ich');
      expect(fremd.isOwn, isFalse);
      expect(fremd.authorUsername, 'lilli92');
      expect(fremd.authorAvatar, 3);

      final eigen = Find.fromJson({
        'id': 'f2',
        'spot_id': 's1',
        'found_on': '2026-08-01',
        'author_id': 'ich',
      }, currentUserId: 'ich');
      expect(eigen.isOwn, isTrue);
    });

    test('ohne author_id zählt der Fund als eigener (alter Offline-Cache)',
        () {
      // Zeilen, die eine App-Version vor Patch 014 gecacht hat, tragen
      // kein author_id — damals gab es keine fremden Funde. Ohne dieses
      // Fallback wäre der Kaltstart im Wald direkt nach dem Update kaputt.
      final find = Find.fromJson(
          {'id': 'f1', 'spot_id': 's1', 'found_on': '2026-08-01'},
          currentUserId: 'ich');
      expect(find.isOwn, isTrue);
    });
  });

  group('Spot', () {
    Find findOn(DateTime date) =>
        Find(id: date.toString(), spotId: 's', foundOn: date);

    test('findsSorted liefert neueste zuerst, lastFind den neuesten', () {
      final spot = Spot(id: 's', ownerId: 'me', lat: 51, lng: 10, finds: [
        findOn(DateTime(2024, 9, 1)),
        findOn(DateTime(2026, 10, 5)),
        findOn(DateTime(2025, 8, 15)),
      ]);
      expect(spot.findsSorted.map((f) => f.foundOn.year), [2026, 2025, 2024]);
      expect(spot.lastFind!.foundOn, DateTime(2026, 10, 5));
    });

    test('lastOwnFind ignoriert fremde Funde, lastFind nicht', () {
      // lastFind beschreibt den SPOT (Marker-Icon, Blattkopf), lastOwnFind
      // die eigene Vorbelegung — am Freundes-Spot dürfen sich beide
      // unterscheiden.
      final spot = Spot(id: 's', ownerId: 'lilli', lat: 51, lng: 10, finds: [
        Find(
            id: 'a',
            spotId: 's',
            species: 'Steinpilz',
            foundOn: DateTime(2026, 8, 1),
            authorId: 'lilli',
            isOwn: false),
        Find(
            id: 'b',
            spotId: 's',
            species: 'Pfifferling',
            foundOn: DateTime(2026, 7, 1)),
      ]);
      expect(spot.lastFind!.species, 'Steinpilz');
      expect(spot.lastOwnFind!.species, 'Pfifferling');
      expect(spot.ownFinds.map((f) => f.species), ['Pfifferling']);
    });

    test('displayName fällt ohne Namen auf "Pilz-Spot" zurück', () {
      const spot = Spot(id: 's', ownerId: 'me', lat: 51, lng: 10);
      expect(spot.displayName, 'Pilz-Spot');
    });

    test('fromJson setzt isOwn anhand der Nutzer-ID und liest Embeds', () {
      final json = {
        'id': 's1',
        'owner_id': 'freund',
        'name': 'Fichtenhang',
        'lat': 51.5,
        'lng': 10.5,
        'sharing_excluded': false,
        'profiles': {'username': 'testpilz'},
        'finds': [
          {'id': 'f1', 'spot_id': 's1', 'found_on': '2026-09-01'},
        ],
      };
      final fremd = Spot.fromJson(json, currentUserId: 'ich');
      expect(fremd.isOwn, isFalse);
      expect(fremd.ownerUsername, 'testpilz');
      expect(fremd.finds, hasLength(1));

      final eigen = Spot.fromJson(json, currentUserId: 'freund');
      expect(eigen.isOwn, isTrue);
    });
  });

  group('FriendshipEntry', () {
    const entry = FriendshipEntry(
      id: 'fr1',
      status: 'pending',
      requesterId: 'anna',
      addresseeId: 'ben',
      requesterUsername: 'anna_pilz',
      addresseeUsername: 'ben_pilz',
    );

    test('Richtung: eingehend für den Addressee, ausgehend für den Requester',
        () {
      expect(entry.isIncomingFor('ben'), isTrue);
      expect(entry.isIncomingFor('anna'), isFalse);
      expect(entry.isOutgoingFor('anna'), isTrue);
      expect(entry.isAccepted, isFalse);
    });

    test('otherUsername liefert immer den jeweils anderen', () {
      expect(entry.otherUsername('anna'), 'ben_pilz');
      expect(entry.otherUsername('ben'), 'anna_pilz');
    });
  });
}
