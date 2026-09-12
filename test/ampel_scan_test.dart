// Der Nachlauf über die eigenen Spots (Baustein B, #277) — die REGELN,
// netzfrei und ohne Widget.
//
// Geprüft wird gegen das MODELL selbst, nicht gegen eingetippte
// Erwartungen: Ob ein Spot ins Banner gehört, entscheidet
// `ampelReadingFrom` — dieselbe Funktion, die auch das Spot-Blatt
// benutzt. Ein Test, der die Schwellen nachbaut, wäre eine zweite
// Modellfassung und damit genau das, was diese Bauform vermeidet.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/ampel/ampel_model.dart';
import 'package:pilzbuddy/features/ampel/ampel_providers.dart';
import 'package:pilzbuddy/features/ampel/ampel_scan.dart';
import 'package:pilzbuddy/features/map/elevation_grid.dart';
import 'package:pilzbuddy/features/map/rain_stack.dart';
import 'package:pilzbuddy/models/find.dart';
import 'package:pilzbuddy/models/spot.dart';

import 'ampel_fill_test.dart' show tableOf, tableOfStations;

/// Ein eigener Spot an einer Koordinate, die in der Reichweite der
/// Teststationen aus `ampel_fill_test.dart` liegt.
Spot spotAt({required String id, String? name, double lat = 51,
        double lon = 11.5, List<String> species = const []}) =>
    Spot(
      id: id,
      ownerId: 'me',
      name: name,
      lat: lat,
      lng: lon,
      finds: [
        for (final (i, s) in species.indexed)
          Find(
              id: '$id-$i',
              spotId: id,
              species: s,
              foundOn: DateTime.utc(2025, 9, 1)),
      ],
    );

/// Ein Verlauf mit [mmPerDay] an jedem der 26 Tage, ältester zuerst.
RainCourse courseOf(int mmPerDay, {int days = 26}) => RainCourse([
      for (var i = 0; i < days; i++)
        RainDay(
            date: DateTime.utc(2026, 7, 1).add(Duration(days: i)),
            mm: mmPerDay),
    ]);

/// Ein Höhengitter, das überall dieselbe Höhe meldet — eine Zelle, die
/// den ganzen Testausschnitt überdeckt.
ElevationGrid flatGrid(int meters) => ElevationGrid(
      values: Uint8List.fromList([meters ~/ elevationQuantM]),
      width: 1,
      height: 1,
      west: 5,
      east: 16,
      north: 56,
      south: 46,
      hexLonStep: 11,
      hexLatStep: 10,
    );

void main() {
  group('ampelScanOf', () {
    test('meldet nur GÜNSTIG, nicht „verhalten"', () {
      // 5 mm/Tag sättigt den Regenfaktor, 1 mm/Tag landet bei ~0,30 —
      // die Stufen dazu bestimmt das Modell, nicht dieser Test.
      final spots = [spotAt(id: 'satt'), spotAt(id: 'mager')];
      final hits = ampelScanOf(
        spots: spots,
        courses: [courseOf(5), courseOf(1)],
        table: tableOf(),
        elevation: null,
        month: 9,
      );

      // Gegenprobe gegen das Modell: Genau die Spots, deren Ablesung
      // `guenstig` sagt, dürfen im Banner stehen.
      final expected = [
        for (final (index, spot) in spots.indexed)
          if (ampelReadingFrom([courseOf(5), courseOf(1)][index],
                      tableOf().at(spot.lat, spot.lng),
                      klass: ampelHerbstClass)
                  .level ==
              AmpelLevel.guenstig)
            spot.id,
      ];
      expect([for (final hit in hits) hit.spot.id], expected);
      expect(expected, ['satt'], reason: 'sonst prüft der Test nichts');
    });

    test('bester zuerst — das Banner öffnet EINEN Spot', () {
      // Drei sattgeregnete Spots, deren Temperaturen ALLE noch günstig
      // sind (13 °C ist das Optimum der Glocke; 11 und 9 liegen darunter,
      // aber über der Schwelle). Das ist der Punkt: Lägen zwei davon
      // außerhalb, bliebe nur ein Treffer übrig, und die Sortierung wäre
      // trivial erfüllt — dann prüfte der Test nichts. Genau so ist er
      // beim ersten Anlauf durch eine Gegenprobe gefallen.
      final table = tableOfStations([
        (lat: 51.0, lon: 11.0, meanC: 9, measured: 20),
        (lat: 51.0, lon: 11.5, meanC: 13, measured: 20),
        (lat: 51.0, lon: 12.0, meanC: 11, measured: 20),
      ]);
      final hits = ampelScanOf(
        spots: [
          spotAt(id: 'lau', lat: 51.0, lon: 11.0),
          spotAt(id: 'optimal', lat: 51.0, lon: 11.5),
          spotAt(id: 'mittel', lat: 51.0, lon: 12.0),
        ],
        courses: [courseOf(5), courseOf(5), courseOf(5)],
        table: table,
        elevation: null,
        month: 9,
      );

      expect(hits, hasLength(3),
          reason: 'alle drei müssen Treffer sein, sonst prüft die '
              'Sortierung nichts');
      expect([for (final hit in hits) hit.spot.id],
          ['optimal', 'mittel', 'lau']);
      for (var i = 1; i < hits.length; i++) {
        expect(hits[i - 1].reading.score!,
            greaterThan(hits[i].reading.score!),
            reason: 'die Liste ist nicht absteigend sortiert');
      }
    });

    test('eine graue Ablesung ist kein Treffer', () {
      // Kein Verlauf heißt „keine Regendaten für diesen Punkt" — eine
      // ehrliche Antwort, aber kein Grund, jemanden loszuschicken.
      final hits = ampelScanOf(
        spots: [spotAt(id: 'ohne')],
        courses: const [null],
        table: tableOf(),
        elevation: null,
        month: 9,
      );
      expect(hits, isEmpty);
    });

    test('fehlt der Verlauf ganz, fällt der Spot heraus statt zu werfen',
        () {
      // Kürzere Verlaufsliste als Spotliste: Der Nachlauf darf daran
      // nicht scheitern — eine RangeError im Kartenstart wäre ein
      // Fehlerbericht statt eines fehlenden Banners.
      final hits = ampelScanOf(
        spots: [spotAt(id: 'a'), spotAt(id: 'b')],
        courses: [courseOf(5)],
        table: tableOf(),
        elevation: null,
        month: 9,
      );
      expect([for (final hit in hits) hit.spot.id], ['a']);
    });

    test('ohne Station gibt es keinen Treffer', () {
      final hits = ampelScanOf(
        spots: [spotAt(id: 'a')],
        courses: [courseOf(5)],
        table: null,
        elevation: null,
        month: 9,
      );
      expect(hits, isEmpty);
    });

    test('leere Spotliste ist kein Sonderfall', () {
      expect(
        ampelScanOf(
            spots: const [],
            courses: const [],
            table: tableOf(),
            elevation: null,
        month: 9,
      ),
        isEmpty,
      );
    });

    test('die Höhe wird durchgereicht — dieselbe Korrektur wie im Blatt',
        () {
      // 1600 m gegen eine Station auf 300 m: −8,45 K. Aus 13 °C an der
      // Station (dem Optimum der Glocke) werden 4,55 °C, der
      // Temperaturfaktor fällt auf ~0,24 — unter die Günstig-Schwelle
      // von 0,5. Die Höhe ist mit Absicht DEUTLICH gewählt: Bei 1200 m
      // landet der Faktor auf 0,505 und damit haarscharf über der
      // Schwelle, der Test bewiese dann nichts.
      final course = courseOf(5);
      final table = tableOf();
      final grid = flatGrid(1600);

      // Erst der Nachschlag selbst — sonst prüft der Rest nur, dass
      // irgendein Wert durchgereicht wird.
      expect(grid.heightMetersAt(51, 11.5), 1600);

      // Ohne Gitter: günstig. Mit Gitter: nicht mehr. Genau dieser
      // Unterschied IST die Korrektur.
      expect(
        ampelScanOf(
            spots: [spotAt(id: 'hoch')],
            courses: [course],
            table: table,
            elevation: null,
        month: 9,
      ),
        hasLength(1),
        reason: 'ohne Korrektur müsste der Spot günstig stehen',
      );
      expect(
        ampelScanOf(
            spots: [spotAt(id: 'hoch')],
            courses: [course],
            table: table,
            elevation: grid,
        month: 9,
      ),
        isEmpty,
        reason: 'die Höhenkorrektur kommt im Nachlauf nicht an',
      );

      // Und es ist wirklich die Korrektur, nicht ein Grauwerden:
      final corrected =
          ampelReadingFrom(course, table.at(51, 11.5),
              klass: ampelHerbstClass, spotHeightM: 1600);
      expect(corrected.isGrau, isFalse,
          reason: 'die Ablesung ist grau geworden — dann sagt der Test '
              'nichts über die Korrektur');
      expect(corrected.level, isNot(AmpelLevel.guenstig));
      expect(corrected.spotHeightM, 1600);
      // Der Regen bleibt gesättigt; gefallen ist ausschließlich die
      // Temperatur. Welche Stufe daraus wird, ist Sache des Modells und
      // steht in `ampel_fill_test.dart` — hier zählt der Mechanismus.
      expect(corrected.rainFactor, closeTo(1, 0.001));
      expect(corrected.tempFactor, lessThan(ampelHerbstClass.guenstigAbove));
    });
  });

  group('das Saison-Tor (Betreiber, 2026-09-12)', () {
    // Die Kurven, an denen die Fälle hängen — aus `season_curves.g.dart`,
    // Schwelle `kSeasonNowThreshold` = 15:
    //   Steinpilz    Mai 2 · Juli 67 · Sept 96 · Nov 32
    //   Pfifferling  Juli 100 · Sept 40 · Nov 10
    List<AmpelHit> scan(List<Spot> spots, int month, {double meanC = 13}) =>
        ampelScanOf(
          spots: spots,
          courses: [for (final _ in spots) courseOf(5)],
          table: tableOf(meanC: meanC),
          elevation: null,
          month: month,
        );

    test('außerhalb der Saison schweigt der Hinweis', () {
      // Regen gesättigt, Temperatur im Optimum — allein der Monat
      // entscheidet. Ohne das Tor stünde hier im Mai „günstig", und die
      // Erinnerung schickte jemanden für Steinpilze in den Frühling.
      final spots = [spotAt(id: 'a', species: const ['Steinpilz'])];
      expect(scan(spots, 9), hasLength(1),
          reason: 'im September ist Hauptzeit');
      expect(scan(spots, 5), isEmpty,
          reason: 'im Mai steht der Steinpilz bei 2 von 100');
    });

    test('bei zwei Arten zählt die, die gerade Saison hat', () {
      // November: Steinpilz 32, Pfifferling 10 — nur einer ist über der
      // Schwelle, und der Treffer trägt seinen Namen.
      final hits = scan(
          [spotAt(id: 'a', species: const ['Pfifferling', 'Steinpilz'])], 11);
      expect(hits.single.species, 'Steinpilz');
    });

    test('jede Art bringt ihre eigene Klasse in die Paarung mit', () {
      // **Der Fall, für den das Ganze gebaut ist.** Juli, 17,5 °C: Für
      // den Steinpilz ist das zu warm (Herbstfenster, Score 0,445 →
      // „verhalten"), für den Pfifferling ist es genau sein Optimum.
      // Beide haben Saison; entschieden wird über die KLASSE, und der
      // Treffer sagt, für wen er gilt.
      final hits = scan(
          [spotAt(id: 'a', species: const ['Steinpilz', 'Pfifferling'])], 7,
          meanC: 17.5);
      expect(hits.single.species, 'Pfifferling');
    });

    test('im Zweifel zeigen: ohne eingetragene Art bleibt der Spot', () {
      // Ein Spot ohne Fund ist die Gildenfrage — es gibt keine Kurve,
      // über die zu urteilen wäre. Dieselbe Regel wie im Saison-Filter
      // (#414): Vor einer Fundstelle zu stehen, die die App versteckt,
      // ist der teure Fehler.
      final hits = scan([spotAt(id: 'a')], 1);
      expect(hits.single.species, isNull);
    });

    test('eine Art ohne bestätigte Klasse schlägt nie an', () {
      expect(scan([spotAt(id: 'a', species: const ['Hallimasch'])], 9),
          isEmpty);
    });
  });

}
