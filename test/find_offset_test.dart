// Wie aus zwei Koordinaten eine Zeile wird, die mehrere Funde an EINEM
// Spot unterscheidbar macht (#373).
//
// Das ist der eigentliche Zweck des Features: Drei Funde mit eigenen
// Koordinaten, die in der Liste weiterhin nur „Steinpilz, 5 Stück"
// untereinander zeigen, ändern für den Nutzer nichts.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/spots/find_offset.dart';
import 'package:pilzbuddy/models/find.dart';
import 'package:pilzbuddy/models/find_position.dart';
import 'package:pilzbuddy/models/spot.dart';

void main() {
  // 51,1634 N — ein Breitengrad ist dort ~111,2 km, ein Längengrad
  // ~69,7 km. Die Versätze unten sind daraus gerechnet.
  const spot = Spot(id: 's1', ownerId: 'me', lat: 51.1634, lng: 10.4477);

  Find findAt(FindPosition? position, {String id = 'f1'}) => Find(
        id: id,
        spotId: 's1',
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 12),
        position: position,
      );

  group('findPositionLabel', () {
    test('zwei Funde an einem Spot bekommen unterscheidbare Zeilen', () {
      // ~14 m nach Nordosten und ~9 m nach Südwesten.
      final northEast = findAt(const FindPosition.gps(
          lat: 51.16349, lng: 10.44784, accuracy: 5));
      final southWest = findAt(const FindPosition.gps(
          lat: 51.16334, lng: 10.44761, accuracy: 6));

      final a = findPositionLabel(northEast, spot);
      final b = findPositionLabel(southWest, spot);

      expect(a, contains('nordöstlich'));
      expect(b, contains('südwestlich'));
      expect(a, isNot(b),
          reason: 'sonst ist das ganze Feature für den Nutzer unsichtbar');
    });

    test('nennt Entfernung UND Richtung UND Genauigkeit', () {
      final find = findAt(const FindPosition.gps(
          lat: 51.16349, lng: 10.44784, accuracy: 5));

      expect(findPositionLabel(find, spot), matches(r'^\d+ m \S+lich \(±5 m\)$'));
    });

    test('ist der Abstand nicht größer als die Streuung, gibt es keine '
        'Richtung', () {
      // 14 m Versatz bei ±20 m gemeldeter Genauigkeit: Die Richtung wäre
      // Rauschen im Gewand einer Messung.
      final find = findAt(const FindPosition.gps(
          lat: 51.16349, lng: 10.44784, accuracy: 20));

      expect(findPositionLabel(find, spot), 'am Spot (±20 m)');
    });

    test('eine auf der Karte gewählte Stelle trägt kein ±', () {
      final find =
          findAt(const FindPosition.picked(lat: 51.16349, lng: 10.44784));

      final label = findPositionLabel(find, spot)!;
      expect(label, contains('nordöstlich'));
      expect(label, isNot(contains('±')),
          reason: 'ein Fadenkreuz hat keinen Messfehler');
    });

    test('unter einem Meter heißt „am Spot", nicht „0 m"', () {
      final find = findAt(
          const FindPosition.picked(lat: 51.1634, lng: 10.4477));

      expect(findPositionLabel(find, spot), 'am Spot');
    });

    test('ohne eigene Stelle gibt es nichts zu sagen', () {
      expect(findPositionLabel(findAt(null), spot), isNull);
      expect(findOffset(findAt(null), spot), isNull);
    });
  });

  group('die Schwellen', () {
    test('vorbelegen ist enger als anbieten', () {
      // Zwei Zahlen mit zwei Aufgaben: Ein Fund darf legitim am Rand
      // seines Spots stehen — ein harter 20-m-Riegel sperrte genau die
      // Fälle aus, für die es das Feature gibt.
      expect(kFindFixNearM, lessThan(kFindFixMaxOffsetM));
    });

    test('die Schärfe-Schwelle ist DIESELBE wie bei der Pilztour', () {
      // Zwei Konstanten mit gleichem Wert wären zwei Antworten auf
      // dieselbe Frage, die beim nächsten Anfassen auseinanderlaufen.
      expect(kFindUsableAccuracyM, 30.0);
      expect(kFindUsableAccuracyM, greaterThan(kFindFixNearM),
          reason: 'sonst fiele unter Blätterdach fast jeder Fix heraus');
    });
  });
}
