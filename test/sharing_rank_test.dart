// Die Teil-Leiter als reine Rechnung (#276).
//
// Der Maßstab ist nicht „irgendeine Zahl kommt heraus", sondern die drei
// Regeln, auf die sich das Feature stützt: bei null kein Titel, nur echte
// Freigabe zählt, und der Spiegel meldet sich nur beim klaren Fall.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/profile/sharing_rank.dart';
import 'package:pilzbuddy/models/spot.dart';

Spot spotOf({bool excluded = false}) => Spot(
      id: 'x',
      ownerId: 'me',
      lat: 51,
      lng: 11,
      sharingExcluded: excluded,
    );

void main() {
  group('Titel', () {
    test('bei null gibt es KEINEN Titel', () {
      // Kein „Frischling", kein „Schnorrer": Die unterste Sprosse ist
      // ein Ziel, keine Etikettierung.
      expect(sharingTitleOf(0), isNull);
    });

    test('jede Sprosse greift genau ab ihrer Grenze', () {
      expect(sharingTitleOf(1), 'Sporenstreuer');
      expect(sharingTitleOf(9), 'Sporenstreuer');
      expect(sharingTitleOf(10), 'Hyphenspinner');
      expect(sharingTitleOf(24), 'Hyphenspinner');
      expect(sharingTitleOf(25), 'Myzelweber');
      expect(sharingTitleOf(49), 'Myzelweber');
      expect(sharingTitleOf(50), 'Revierkenner');
      expect(sharingTitleOf(99), 'Revierkenner');
      expect(sharingTitleOf(100), 'Waldpate');
      expect(sharingTitleOf(2500), 'Waldpate',
          reason: 'oberhalb der letzten Sprosse bleibt es dabei');
    });

    test('die nächste Sprosse stimmt — und endet oben', () {
      expect(nextSharingRank(0)?.title, 'Sporenstreuer');
      expect(nextSharingRank(1)?.from, 10);
      expect(nextSharingRank(99)?.title, 'Waldpate');
      expect(nextSharingRank(100), isNull,
          reason: 'auf der obersten Sprosse gibt es kein „noch X bis"');
    });
  });

  group('Zählung', () {
    test('ohne den globalen Schalter zählt NICHTS', () {
      // Wer nicht teilt, teilt nicht — auch mit hundert Spots. Alles
      // andere wäre ein Titel für etwas, das kein Buddy je sieht.
      final spots = List.generate(100, (_) => spotOf());
      expect(sharedSpotCount(spots, sharesByDefault: false), 0);
      expect(sharedSpotCount(spots, sharesByDefault: true), 100);
    });

    test('einzeln ausgeschlossene Spots zählen nicht mit', () {
      final spots = [
        spotOf(),
        spotOf(excluded: true),
        spotOf(),
        spotOf(excluded: true),
      ];
      expect(sharedSpotCount(spots, sharesByDefault: true), 2);
    });

    test('ohne Spots ist es null, nicht null-mit-Titel', () {
      expect(sharedSpotCount(const [], sharesByDefault: true), 0);
      expect(sharingTitleOf(sharedSpotCount(const [], sharesByDefault: true)),
          isNull);
    });
  });

  group('Spiegel', () {
    test('meldet sich erst beim klaren Missverhältnis', () {
      expect(showsSharingMirror(shared: 3, seen: 34), isTrue);
      expect(showsSharingMirror(shared: 7, seen: 34), isFalse,
          reason: 'ein Fünftel ist die Grenze — 7×5 = 35 > 34');
      expect(showsSharingMirror(shared: 6, seen: 34), isTrue,
          reason: '6×5 = 30 < 34');
    });

    test('ohne fremde Spots schweigt er', () {
      // Wer noch keine Buddies hat, bekommt keinen Vorwurf zu lesen.
      expect(showsSharingMirror(shared: 0, seen: 0), isFalse);
    });
  });
}
