// Die Regel hinter #215: Wann sind zwei Fundorte in Wirklichkeit einer?
// Reine Funktionen, deshalb hier ohne Oberfläche geprüft — die Abläufe
// darüber liegen in test/flows/.
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/features/spots/nearby_spots.dart';
import 'package:pilzbuddy/models/find.dart';
import 'package:pilzbuddy/models/spot.dart';

/// Ein Punkt [meters] nördlich von 51,0/10,0 — die Richtung ohne
/// Breitengrad-Stauchung, damit die Testzahlen lesbar bleiben.
double _northOf(double meters) => 51.0 + meters / 111200;

Spot _spot(String id, double lat,
        {bool isOwn = true, List<Find> finds = const []}) =>
    Spot(
      id: id,
      ownerId: isOwn ? 'me' : 'lilli',
      lat: lat,
      lng: 10.0,
      isOwn: isOwn,
      finds: finds,
    );

Find _find(String id, {bool isOwn = true}) => Find(
      id: id,
      spotId: 's',
      foundOn: DateTime(2026, 8, 1),
      isOwn: isOwn,
      authorId: isOwn ? 'me' : 'lilli',
    );

void main() {
  group('nearestOwnSpot', () {
    test('findet den nächsten Spot im Umkreis', () {
      final spots = [
        _spot('fern', _northOf(18)),
        _spot('nah', _northOf(5)),
      ];
      final hit = nearestOwnSpot(spots, const LatLng(51.0, 10.0));
      expect(hit!.spot.id, 'nah');
      expect(hit.meters, closeTo(5, 0.1));
    });

    test('außerhalb des Umkreises gibt es keinen Treffer', () {
      // 25 m: die Stelle, an der aus „derselbe Fundort" ein neuer wird.
      final spots = [_spot('weit', _northOf(25))];
      expect(nearestOwnSpot(spots, const LatLng(51.0, 10.0)), isNull);
      // Und mit größerem Umkreis wäre es einer — die Grenze zählt, nicht
      // die Geometrie.
      expect(nearestOwnSpot(spots, const LatLng(51.0, 10.0), meters: 30),
          isNotNull);
    });

    test('Freundes-Spots zählen nicht', () {
      // Sonst hinge der Fund plötzlich am Spot eines Buddys, nur weil man
      // dort steht.
      final spots = [_spot('vom-buddy', _northOf(3), isOwn: false)];
      expect(nearestOwnSpot(spots, const LatLng(51.0, 10.0)), isNull);
    });

    test('ohne Spots kein Treffer', () {
      expect(nearestOwnSpot(const [], const LatLng(51.0, 10.0)), isNull);
    });
  });

  group('overlappingPairs', () {
    test('jedes Paar genau einmal, nächstes zuerst', () {
      final spots = [
        _spot('a', _northOf(0)),
        _spot('b', _northOf(15)),
        _spot('c', _northOf(3)),
      ];
      final pairs = overlappingPairs(spots);
      // a/b (15 m), a/c (3 m), b/c (12 m) — drei Paare, nicht sechs.
      expect(pairs, hasLength(3));
      expect(pairs.first.meters, closeTo(3, 0.1));
      expect(pairs.map((p) => p.meters),
          [closeTo(3, 0.1), closeTo(12, 0.1), closeTo(15, 0.1)]);
    });

    test('weit auseinander heißt kein Paar', () {
      final spots = [_spot('a', _northOf(0)), _spot('b', _northOf(40))];
      expect(overlappingPairs(spots), isEmpty);
    });

    test('Freundes-Spots kommen nicht vor', () {
      final spots = [
        _spot('meiner', _northOf(0)),
        _spot('vom-buddy', _northOf(2), isOwn: false),
      ];
      expect(overlappingPairs(spots), isEmpty);
    });
  });

  group('canMerge', () {
    test('eigene Funde an beiden Spots: ja', () {
      final pair = (
        a: _spot('a', _northOf(0), finds: [_find('f1')]),
        b: _spot('b', _northOf(3), finds: [_find('f2')]),
        meters: 3.0,
      );
      expect(canMerge(pair), isTrue);
    });

    test('ein fremder Fund sperrt das Paar', () {
      // Die RLS ließe ihn nicht mitwandern, und die Lösch-Kaskade nähme
      // ihn still mit — Datenverlust bei jemand anderem.
      final pair = (
        a: _spot('a', _northOf(0), finds: [_find('f1')]),
        b: _spot('b', _northOf(3),
            finds: [_find('f2'), _find('vom-buddy', isOwn: false)]),
        meters: 3.0,
      );
      expect(canMerge(pair), isFalse);
    });

    test('Spots ganz ohne Funde lassen sich zusammenführen', () {
      final pair = (
        a: _spot('a', _northOf(0)),
        b: _spot('b', _northOf(3)),
        meters: 3.0,
      );
      expect(canMerge(pair), isTrue);
    });
  });
}
