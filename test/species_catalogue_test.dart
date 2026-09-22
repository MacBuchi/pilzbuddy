// Die Zusagen des Verzeichnisses im Reiter „Pilze", nachgerechnet über
// die ganze Artenliste — nicht an drei Beispielen.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/species_photos.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
import 'package:pilzbuddy/core/season_curves.dart';
import 'package:pilzbuddy/features/ampel/ampel_model.dart';
import 'package:pilzbuddy/features/species/species_catalogue.dart';
import 'package:pilzbuddy/models/find.dart';
import 'package:pilzbuddy/models/spot.dart';

void main() {
  final known = kBekannteArten.where((s) => !s.isSynonym).toList();

  test('jede bekannte Art steht genau einmal im Verzeichnis', () {
    final names = [
      for (final section in speciesCatalogue(month: 9))
        for (final entry in section.entries) entry.name,
    ];
    expect(names.toSet().length, names.length, reason: 'doppelt: $names');
    expect(names.toSet(), known.map((s) => s.name).toSet());
  });

  test('die Gruppen tragen genau die Mitglieder des Modells', () {
    final sections = speciesCatalogue(month: 9);
    // Reihenfolge wie in `ampelClasses`, danach der Rest.
    expect(sections.map((s) => s.classKey),
        [...ampelClasses.keys, null]);
    for (final section in sections) {
      final expected = section.classKey == null
          ? known
              .where((s) => ampelClassFor(s.name) == null)
              .map((s) => s.name)
              .toSet()
          : {
              for (final e in ampelSpeciesClass.entries)
                if (e.value == section.classKey) e.key,
            };
      expect(section.entries.map((e) => e.name).toSet(), expected,
          reason: section.title);
      for (final entry in section.entries) {
        expect(entry.evidence != null, section.classKey != null,
            reason: '${entry.name}: Belege nur mit Ampel');
      }
    }
    expect(sections.last.title, kCatalogueGreyTitle);
  });

  test('Saison-Hervorhebung und Wortleiter folgen den Kurven', () {
    for (final month in [1, 2, 6, 9, 12]) {
      for (final section in speciesCatalogue(month: month)) {
        for (final entry in section.entries) {
          final curve = seasonCurveFor(entry.name);
          expect(entry.curve, curve, reason: entry.name);
          if (curve == null) {
            expect(entry.share, isNull);
            expect(entry.inSeason, isFalse);
            expect(entry.seasonWord, isNull);
            continue;
          }
          expect(entry.share, curve.months[month - 1]);
          expect(entry.inSeason, speciesInSeason(entry.name, month),
              reason: '${entry.name} im Monat $month');
          expect(entry.seasonWord, seasonShareWord(curve.months[month - 1]));
        }
      }
    }
  });

  test('die Wortleiter kennt vier Stufen, die unterste an der Schwelle', () {
    expect(seasonShareWord(100), 'Hauptzeit');
    expect(seasonShareWord(80), 'Hauptzeit');
    expect(seasonShareWord(79), 'Nebenzeit');
    expect(seasonShareWord(40), 'Nebenzeit');
    expect(seasonShareWord(39), 'Randzeit');
    expect(seasonShareWord(kSeasonNowThreshold), 'Randzeit');
    expect(seasonShareWord(kSeasonNowThreshold - 1), 'kaum gemeldet');
  });

  group('die Detailseite je Art (#511)', () {
    // Ein Leergang trägt KEINE Art (`finds_blank_leer`) — deshalb ist
    // die Art hier nullbar, statt einen unmöglichen Zustand zu bauen.
    Find find(String? species,
            {DateTime? on, bool blank = false, bool isOwn = true}) =>
        Find(
          id: '$species-${on?.day}-$isOwn-$blank',
          spotId: 's',
          species: species,
          foundOn: on ?? DateTime(2026, 8, 2),
          blank: blank,
          isOwn: isOwn,
        );
    Spot spot(String id, List<Find> finds) =>
        Spot(id: id, ownerId: 'me', lat: 51, lng: 10, finds: finds);

    test('jede bekannte Art hat eine Seite, und nur sie', () {
      // Dieselbe Zusage wie beim Verzeichnis, eine Ebene tiefer: Was in
      // der Liste steht, muss sich auch öffnen lassen.
      for (final species in known) {
        final detail = speciesDetailFor(species.name, month: 9);
        expect(detail, isNotNull, reason: species.name);
        expect(detail!.name, species.name);
        expect(detail.sci, species.sci);
        expect(detail.group, species.group);
      }
      expect(speciesDetailFor('Geheimpilz', month: 9), isNull);
      expect(speciesDetailFor('', month: 9), isNull);
    });

    test('ein Zweitname führt auf die Seite der Hauptbezeichnung', () {
      // Sonst gäbe es zwei Seiten für denselben Pilz — und eine davon
      // ohne Kurve, weil die an der Hauptbezeichnung hängt.
      final detail = speciesDetailFor('Marone', month: 9);
      expect(detail?.name, 'Maronenröhrling');
      expect(detail?.synonyms, contains('Marone'));
      // Auch die Schreibweise zieht nach, wie bei canonicalSpecies.
      expect(speciesDetailFor('steinpilz', month: 9)?.name, 'Steinpilz');
    });

    test('Kurve, Klasse und Belege sind dieselben wie in der Liste', () {
      // Zwei Quellen für „hat die Art jetzt Saison" wären eine zu viel:
      // Die Seite ist die Lupe auf die Zeile, nicht eine zweite Meinung.
      for (final month in [2, 9]) {
        for (final section in speciesCatalogue(month: month)) {
          for (final entry in section.entries) {
            final detail = speciesDetailFor(entry.name, month: month)!;
            expect(detail.curve, entry.curve, reason: entry.name);
            expect(detail.share, entry.share, reason: entry.name);
            expect(detail.inSeason, entry.inSeason, reason: entry.name);
            expect(detail.seasonWord, entry.seasonWord, reason: entry.name);
            expect(detail.evidence, entry.evidence, reason: entry.name);
            expect(detail.classKey, section.classKey, reason: entry.name);
          }
        }
      }
    });

    test('gezählt werden EIGENE Funde, nicht die der Buddies', () {
      // Die Trennlinie aus #190, an der auch die Statistik hängt: Der
      // Fund eines Buddys am eigenen Spot ist seine Ausbeute.
      //
      // **Der Leergang ist hier KEINE Gegenprobe**, so naheliegend er
      // aussieht: Er trägt gar keine Art (`finds_blank_leer`) und kann
      // deshalb nie auf einen Artnamen passen — `ownFinds` gegen
      // `ownEntries` getauscht bleibt grün, nachgemessen. Gezählt wird
      // trotzdem über `ownFinds`, weil die Statistik es so tut (#211)
      // und zwei Lesarten von „mein Fund" eine zu viel wären.
      final spots = [
        spot('a', [
          find('Steinpilz', on: DateTime(2026, 8, 1)),
          find('Steinpilz', on: DateTime(2026, 9, 3)),
          find('Steinpilz', on: DateTime(2026, 9, 20), isOwn: false),
          find('Pfifferling', on: DateTime(2026, 7, 1)),
        ]),
        spot('b', [find('Steinpilz', on: DateTime(2026, 6, 6))]),
        // Nur ein Leergang — kein Fund, also auch kein Spot in der Zahl.
        spot('c', [find(null, on: DateTime(2026, 9, 9), blank: true)]),
        spot('d', [find('Pfifferling', on: DateTime(2026, 7, 2))]),
      ];
      final detail = speciesDetailFor('Steinpilz', month: 9, spots: spots)!;
      expect(detail.ownFinds, 3);
      expect(detail.ownSpots, 2);
      expect(detail.lastFound, DateTime(2026, 9, 3),
          reason: 'der Fund des Buddys vom 20.9. ist nicht meiner');

      // Und über den Zweitnamen eingetragen zählt dieselbe Art mit.
      final marone = speciesDetailFor('Maronenröhrling', month: 9, spots: [
        spot('e', [find('Marone'), find('Maronenröhrling')]),
      ])!;
      expect(marone.ownFinds, 2);
      expect(marone.ownSpots, 1);
    });

    test('ohne eigene Funde bleiben die Zahlen null', () {
      final detail = speciesDetailFor('Steinpilz', month: 9)!;
      expect(detail.ownFinds, 0);
      expect(detail.ownSpots, 0);
      expect(detail.lastFound, isNull);
      expect(detail.gbif, isNull, reason: 'ohne Asset keine Meldungen');
    });
  });

  group('die Suche im Reiter', () {
    test('leere Eingabe lässt alles stehen', () {
      for (final species in known) {
        expect(speciesMatchesQuery(species.name, ''), isTrue);
        expect(speciesMatchesQuery(species.name, '   '), isTrue,
            reason: 'nur Leerzeichen ist keine Suche');
      }
    });

    test('findet über Umlaut-Schreibweisen hinweg', () {
      // Der Grund, warum #395 die Faltung gebaut hat: Wer unterwegs ohne
      // Umlaut tippt, schreibt mal „ae", mal gar nichts.
      for (final query in ['Stäubling', 'Staeubling', 'staubling', 'STÄUB']) {
        expect(speciesMatchesQuery('Flaschenstäubling', query), isTrue,
            reason: query);
      }
      expect(speciesMatchesQuery('Grünling', 'grunling'), isTrue);
      expect(speciesMatchesQuery('Krause Glucke', 'krauseglucke'), isTrue,
          reason: 'das Leerzeichen fällt in der Faltung weg');
    });

    test('findet über Zweitnamen und wissenschaftlichen Namen', () {
      // Beides ist in der Liste unsichtbar — wer den Pilz nur als
      // „Marone" kennt oder ihn aus einem Buch abliest, findet ihn sonst
      // nicht.
      expect(speciesMatchesQuery('Maronenröhrling', 'Marone'), isTrue);
      expect(speciesMatchesQuery('Herbsttrompete', 'Totentrompete'), isTrue);
      expect(speciesMatchesQuery('Steinpilz', 'Boletus'), isTrue);
      expect(speciesMatchesQuery('Steinpilz', 'boletus edulis'), isTrue);
      expect(speciesMatchesQuery('Pfifferling', 'Boletus'), isFalse);
    });

    test('Teiltreffer, aber kein Raten', () {
      // Hier tippt jemand in eine Liste, die er vor sich hat. Ein
      // Editierabstand wie bei den Eingabe-Vorschlägen (#395) wäre hier
      // falsch: Eine Suche nach „stein", die auch „Stockschwämmchen"
      // zeigt, ist kein Filter mehr.
      expect(speciesMatchesQuery('Steinpilz', 'stein'), isTrue);
      expect(speciesMatchesQuery('Kiefernsteinpilz', 'stein'), isTrue,
          reason: 'auch mitten im Wort');
      expect(speciesMatchesQuery('Stockschwämmchen', 'stein'), isFalse);
      expect(speciesMatchesQuery('Steinpilz', 'steinpliz'), isFalse,
          reason: 'ein Vertipper rät hier nicht');
    });

    test('leere Eingabe trifft ALLES, nicht nichts', () {
      // Die harmlose Fehlerrichtung: Wer den Sonderfall im Aufrufer
      // vergisst, zeigt zu viel statt eines Verzeichnisses, das leer
      // aussieht und damit kaputt.
      final all = speciesSearch('');
      expect(all.names.length, known.length);
      expect(all.isGuess, isFalse);
    });

    test('derselbe Zweischritt wie im Eingabefeld: erst finden, dann '
        'raten', () {
      // **Der Grund für diesen Test.** Bis 1.164.0 hatte die Suche im
      // Reiter nur den ersten Schritt — „Steinpliz" ergab dort „Keine
      // Art mit diesem Namen", während dasselbe Wort im Blatt „Fund
      // eintragen" längst den Steinpilz vorschlug. Zwei Antworten auf
      // „kennt die App diesen Pilz?", und die strengere stand
      // ausgerechnet im Verzeichnis.
      final found = speciesSearch('steinpilz');
      expect(found.isGuess, isFalse);
      expect(found.names, contains('Steinpilz'));

      final guessed = speciesSearch('steinpliz');
      expect(guessed.isGuess, isTrue, reason: 'geraten, nicht gefunden');
      expect(guessed.names, contains('Steinpilz'));

      // Geraten wird auch über Zweitnamen und wissenschaftliche Namen —
      // sonst fände der Rückfall weniger als der Weg davor.
      expect(speciesSearch('Bofist').names, contains('Riesenbovist'));
      expect(speciesSearch('Boletus edulus').names, contains('Steinpilz'));
    });

    test('geraten wird nur der beste Treffer, und unter vier Zeichen gar '
        'nicht', () {
      // Beide Grenzen gehören dem Eingabefeld (#395) und gelten hier
      // unverändert — sie stehen seit 1.164.0 in `mushroom_species.dart`,
      // damit es sie nur einmal gibt.
      expect(speciesTypoTolerance(3), -1);
      expect(speciesSearch('abc').names, isEmpty);
      // **Gleich nah heißt: alle drei.** `nearContainsDistance` misst
      // gegen das beste TEILSTÜCK, und „pfiferling" liegt bei
      // „Pfifferling", „Trompetenpfifferling" und „Falscher
      // Pfifferling" gleichermaßen einen Fehler daneben. Das ist die
      // richtige Antwort — welchen der drei jemand meinte, weiß die App
      // nicht, und eine Auswahl zu treffen wäre geraten hoch zwei.
      final guessed = speciesSearch('Pfiferling');
      expect(guessed.isGuess, isTrue);
      expect(guessed.names,
          {'Pfifferling', 'Trompetenpfifferling', 'Falscher Pfifferling'});
      // Weiter weg fällt dagegen raus: Der Steinpilz ist kein Tippfehler.
      expect(guessed.names, isNot(contains('Steinpilz')));

      // **Und hier hängt mehr daran als Bequemlichkeit.** „Steipilz"
      // liegt einen Fehler neben den drei Steinpilzen — und innerhalb
      // der Toleranz (hier 2) liegen ACHT Arten. Böte der Rückfall alle
      // an, stünden fünf Pilze in der Liste, die niemand gesucht hat.
      // Nur der beste Abstand zählt, und das ist keine Sparsamkeit:
      // Ein Vorschlag, den man nicht gesucht hat, wirkt beim Antippen.
      final typo = speciesSearch('Steipilz');
      expect(typo.isGuess, isTrue);
      expect(typo.names, {'Steinpilz', 'Sommersteinpilz', 'Kiefernsteinpilz'});

      // Gegenprobe zur Gegenprobe: „Morchell" wird GEFUNDEN, nicht
      // geraten — über die Gattung „Morchella". Dass der
      // wissenschaftliche Name mitgesucht wird, macht den Rückfall hier
      // überflüssig, und das ist die bessere Auskunft. Die tödlich
      // giftige Frühjahrslorchel bleibt so oder so draußen; sie heißt
      // Gyromitra und ist keine Morchel.
      final morchel = speciesSearch('Morchell');
      expect(morchel.isGuess, isFalse);
      expect(morchel.names,
          {'Speisemorchel', 'Spitzmorchel', 'Käppchenmorchel'});
      expect(morchel.names, isNot(contains('Frühjahrslorchel')));
    });

    test('jede Art findet sich unter ihrem eigenen Namen', () {
      // Die Zusage, an der die Suche hängt — sonst gäbe es eine Art, die
      // im Verzeichnis steht und nicht auffindbar ist.
      for (final species in known) {
        expect(speciesMatchesQuery(species.name, species.name), isTrue,
            reason: species.name);
      }
      // Und jeder Zweitname führt auf seine Hauptbezeichnung.
      for (final species in kBekannteArten.where((s) => s.isSynonym)) {
        expect(speciesMatchesQuery(species.sameAs!, species.name), isTrue,
            reason: '${species.name} → ${species.sameAs}');
      }
    });
  });

  test('das Auge folgt den Porträts, nicht den Vergleichspaaren', () {
    // **Eine Art kann ein Bild im PAAR tragen und trotzdem keins
    // eigenes haben.** Für die Frage „wovon fehlen uns noch Fotos"
    // zählt das Paar nicht mit — sonst sähe die Liste vollständiger
    // aus, als sie ist. Das Stockschwämmchen ist genau dieser Fall.
    final alle = [
      for (final section in speciesCatalogue(month: 9)) ...section.entries,
    ];
    final mitBild = alle.where((e) => e.hasPictures).map((e) => e.name);
    expect(mitBild, contains('Fliegenpilz'));
    expect(mitBild, contains('Krause Glucke'));
    expect(speciesPhotos.containsKey('Stockschwämmchen'), isTrue,
        reason: 'trägt ein Bild im Vergleichspaar');
    expect(mitBild, isNot(contains('Stockschwämmchen')),
        reason: 'aber kein eigenes Porträt');
    expect(mitBild.length, speciesPortraits.length);
  });

}
