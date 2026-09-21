// Die Liste des Reiters „Spots" (#509): Reihenfolge, Gruppen, Suche.
//
// Ohne Widgets, weil hier die Aussagen stecken, die man beim Ansehen
// nicht prüfen kann — vor allem die Reihenfolge: Dass ein Leergang als
// Aktivität zählt und ein Buddy-Spot ohne Freigabe NICHT als Vormerkung
// gilt, sieht man einem Bildschirm nicht an.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/spots/spot_list.dart';
import 'package:pilzbuddy/models/find.dart';
import 'package:pilzbuddy/models/spot.dart';

Find find(String? species,
        {DateTime? on, bool blank = false, bool own = true, String? author,
        bool pending = false}) =>
    Find(
      id: 'f-$species-${on?.day}',
      spotId: 's',
      species: species,
      foundOn: on ?? DateTime(2026, 9, 1),
      blank: blank,
      isOwn: own,
      authorUsername: author,
      pending: pending,
    );

Spot spot(
  String name, {
  List<Find> finds = const [],
  bool own = true,
  String? owner,
  List<String> expected = const [],
  bool pending = false,
}) =>
    Spot(
      id: 'id-$name',
      ownerId: own ? 'me' : 'other',
      name: name,
      lat: 51,
      lng: 10,
      isOwn: own,
      ownerUsername: owner,
      finds: finds,
      expectedSpecies: expected,
      pending: pending,
    );

void main() {
  test('neueste Aktivität zuerst — ein Leergang zählt mit', () {
    final alt = spot('Alte Eiche',
        finds: [find('Steinpilz', on: DateTime(2026, 9, 1))]);
    final leer = spot('Buchenhang',
        finds: [
          find('Marone', on: DateTime(2026, 8, 1)),
          find(null, on: DateTime(2026, 9, 10), blank: true),
        ]);
    final list = spotList(mine: [alt, leer], friends: const []);
    expect(list.active.map((r) => r.spot.displayName),
        ['Buchenhang', 'Alte Eiche']);
    expect(list.active.first.lastEntry!.blank, isTrue);
  });

  test('gleicher Tag: alphabetisch, damit die Liste nicht springt', () {
    final tag = DateTime(2026, 9, 12);
    final list = spotList(
      mine: [
        spot('Zwei Eichen', finds: [find('Marone', on: tag)]),
        spot('Ahornweg', finds: [find('Steinpilz', on: tag)]),
      ],
      friends: const [],
    );
    expect(list.active.map((r) => r.spot.displayName),
        ['Ahornweg', 'Zwei Eichen']);
  });

  test('eigener Spot ohne Eintrag ist eine Vormerkung', () {
    final list = spotList(
      mine: [spot('Fichtenschonung', expected: ['Marone'])],
      friends: const [],
    );
    expect(list.active, isEmpty);
    // Kanonisch: „Marone" ist der Maronenröhrling — dieselbe Umsetzung
    // wie beim Schreiben eines Fundes.
    expect(list.planned.single.species, ['Maronenröhrling']);
    expect(list.silent, isEmpty);
  });

  test('Buddy-Spot ohne sichtbaren Eintrag ist KEINE Vormerkung', () {
    // Ohne `share_details` liefert die RLS keine Funde (Patch 014) — der
    // Spot sähe aus wie eine Vormerkung, und die Liste behauptete eine
    // Absicht, die niemand geäußert hat.
    final list = spotList(
      mine: const [],
      friends: [spot('Lillis Stelle', own: false, owner: 'lilli92')],
    );
    expect(list.planned, isEmpty);
    expect(list.silent.single.spot.displayName, 'Lillis Stelle');
  });

  test('eine geteilte Vormerkung des Buddys bleibt eine Vormerkung', () {
    final list = spotList(
      mine: const [],
      friends: [
        spot('Lillis Plan',
            own: false, owner: 'lilli92', expected: ['Steinpilz']),
      ],
    );
    expect(list.silent, isEmpty);
    expect(list.planned.single.species, ['Steinpilz']);
  });

  test('der Besitzer-Filter trennt eigene und geteilte Spots', () {
    final mine = [spot('Meiner', finds: [find('Marone')])];
    final friends = [
      spot('Ihrer',
          own: false, owner: 'lilli92', finds: [find('Steinpilz', own: false)])
    ];
    expect(
        spotList(mine: mine, friends: friends, owner: SpotOwnerFilter.mine)
            .active
            .map((r) => r.spot.displayName),
        ['Meiner']);
    expect(
        spotList(mine: mine, friends: friends, owner: SpotOwnerFilter.buddies)
            .active
            .map((r) => r.spot.displayName),
        ['Ihrer']);
    expect(spotList(mine: mine, friends: friends).active, hasLength(2));
  });

  group('Suche', () {
    final mine = [
      spot('Buchenhang Nord', finds: [find('Flaschenstäubling')]),
      spot('Am Bach', finds: [find('Steinpilz')]),
    ];
    final friends = [
      spot('Lillis Stelle',
          own: false, owner: 'lilli92', finds: [find('Marone', own: false)]),
    ];

    List<String> names(String query) =>
        spotList(mine: mine, friends: friends, query: query)
            .active
            .map((r) => r.spot.displayName)
            .toList();

    test('findet über den Namen', () => expect(names('bach'), ['Am Bach']));

    test('findet über die Art — auch in anderer Schreibweise', () {
      // Dieselbe Faltung wie die Artensuche (#395): „Staeubling" und
      // „Stäubling" sind derselbe Pilz.
      expect(names('Staeubling'), ['Buchenhang Nord']);
      expect(names('flaschen-stäubling'), ['Buchenhang Nord']);
    });

    test('findet über den Buddy', () => expect(names('lilli'), ['Lillis Stelle']));

    test('leere Suche zeigt alles', () => expect(names('   '), hasLength(3)));

    test('kein Treffer heißt leere Liste, nicht alles',
        () => expect(names('Trüffel'), isEmpty));
  });

  test('Arten stehen kanonisch und ohne Wiederholung da', () {
    final list = spotList(
      mine: [
        spot('Doppelt', finds: [
          find('Herbsttrompete', on: DateTime(2026, 9, 3)),
          find('Totentrompete', on: DateTime(2026, 9, 2)),
          find(null, on: DateTime(2026, 9, 1), blank: true),
        ]),
      ],
      friends: const [],
    );
    final row = list.active.single;
    expect(row.species, ['Herbsttrompete']);
    expect(row.entryCount, 3, reason: 'der Leergang ist ein Eintrag');
  });

  test('wartende Einträge und Neuigkeiten stehen an der Zeile', () {
    final warten = spot('Korb', finds: [find('Marone', pending: true)]);
    final neu = spot('Bei Lilli',
        own: false,
        owner: 'lilli92',
        finds: [find('Steinpilz', own: false, author: 'lilli92')]);
    final list = spotList(
        mine: [warten], friends: [neu], spotsWithNews: {neu.id});
    final rows = {
      for (final row in list.active) row.spot.displayName: row,
    };
    expect(rows['Korb']!.waiting, isTrue);
    expect(rows['Korb']!.hasNews, isFalse);
    expect(rows['Bei Lilli']!.hasNews, isTrue);
    expect(rows['Bei Lilli']!.waiting, isFalse);
  });

  group('relativeDay', () {
    final today = DateTime(2026, 9, 21);

    test('die letzten Tage bekommen Worte', () {
      expect(relativeDay(today, today), 'heute');
      expect(relativeDay(DateTime(2026, 9, 20), today), 'gestern');
      expect(relativeDay(DateTime(2026, 9, 18), today), 'vor 3 Tagen');
    });

    test('ab einer Woche gilt das Datum', () {
      expect(relativeDay(DateTime(2026, 9, 15), today), 'vor 6 Tagen');
      expect(relativeDay(DateTime(2026, 9, 14), today), isNull);
    });

    test('ein Datum in der Zukunft rechnet nicht rückwärts', () {
      expect(relativeDay(DateTime(2026, 9, 22), today), isNull);
    });
  });
}
