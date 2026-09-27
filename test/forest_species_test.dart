// Das Baumarten-Gitter (#227): Format, Halbbyte-Vertrag, Punktabfrage
// und die Aufzählung für die Zeile.
//
// Der wichtigste Test steht ganz unten: dass dieses Gitter auf DEMSELBEN
// Hex-Raster liegt wie das Waldtypen-Gitter. Darauf baut der ganze
// Entwurf — beide werden mit einer einzigen Zuordnung Punkt → Zelle
// nachgeschlagen.
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart';
import 'package:pilzbuddy/features/map/forest_species.dart';

const _lonStep = 0.004;
const _latStep = 0.002;

ForestSpeciesGrid speciesOf(List<List<int>> rows,
        {double west = 10,
        double north = 55,
        double lonStep = _lonStep,
        double latStep = _latStep,
        int referenceYear = 2022}) =>
    ForestSpeciesGrid.decode(
      GZipEncoder().encode(rows.expand((r) => r).toList())!,
      width: rows.first.length,
      height: rows.length,
      west: west,
      east: west + rows.first.length * lonStep,
      north: north,
      south: north - rows.length * latStep,
      referenceYear: referenceYear,
      hexLonStep: lonStep,
      hexLatStep: latStep,
    );

/// Der Mittelpunkt einer Hexzelle — dieselbe Formel wie im Werkzeug und
/// in `forest_grid.dart`.
(double, double) centerOf(ForestSpeciesGrid grid, int hx, int hy) => (
      grid.north - grid.hexLatStep * (hy + 2 / 3),
      grid.west + grid.hexLonStep * (hx + 0.5 + (hy.isOdd ? 0.5 : 0)),
    );

void main() {
  group('Format', () {
    test('packt schlicht gzip aus — OHNE Zeilen-Delta', () {
      // Der Unterschied zu Wald und Regen. Käme hier je ein Delta an,
      // sähe die erste Zelle jeder Zeile richtig aus und alles danach
      // wäre still falsch.
      final grid = speciesOf([
        [0x11, 0x11, 0x20],
        [0xFF, 0x05, 0x05],
      ]);
      expect(grid.values, [0x11, 0x11, 0x20, 0xFF, 0x05, 0x05]);
    });

    test('falsche Länge wird abgelehnt, nicht zurechtgebogen', () {
      expect(
        () => ForestSpeciesGrid.decode(
          GZipEncoder().encode([1, 2, 3])!,
          width: 2,
          height: 2,
          west: 10,
          east: 11,
          north: 55,
          south: 54,
          referenceYear: 2022,
          hexLonStep: _lonStep,
          hexLatStep: _latStep,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Halbbyte-Vertrag', () {
    test('oben Laub, unten Nadel', () {
      final grid = speciesOf([
        [0x11, 0x25, 0x40, 0x03],
      ]);
      expect(grid.at(centerOf(grid, 0, 0).$1, centerOf(grid, 0, 0).$2),
          (broadleaf: Broadleaf.beech, conifer: Conifer.spruce));
      expect(grid.at(centerOf(grid, 1, 0).$1, centerOf(grid, 1, 0).$2),
          (broadleaf: Broadleaf.oak, conifer: Conifer.larch));
      expect(grid.at(centerOf(grid, 2, 0).$1, centerOf(grid, 2, 0).$2),
          (broadleaf: Broadleaf.alder, conifer: null));
      expect(grid.at(centerOf(grid, 3, 0).$1, centerOf(grid, 3, 0).$2),
          (broadleaf: null, conifer: Conifer.fir));
    });

    test('alle fünf Nadel- und vier Laubarten sind erreichbar', () {
      // Fängt eine verschobene Tabelle: Die Reihenfolge der enum-Werte
      // IST der Vertrag mit `tool/forest_species.py`.
      final grid = speciesOf([
        [0x01, 0x02, 0x03, 0x04, 0x05, 0x10, 0x20, 0x30, 0x40],
      ]);
      final read = [
        for (var hx = 0; hx < 9; hx++)
          grid.at(centerOf(grid, hx, 0).$1, centerOf(grid, hx, 0).$2)
      ];
      expect([for (final n in read) n?.conifer], [
        Conifer.spruce, Conifer.pine, Conifer.fir, Conifer.douglas,
        Conifer.larch, null, null, null, null,
      ]);
      expect([for (final n in read) n?.broadleaf], [
        null, null, null, null, null,
        Broadleaf.beech, Broadleaf.oak, Broadleaf.birch, Broadleaf.alder,
      ]);
    });

    test('keine Aussage, Kronenverlust und „Bäume ohne Namen" schweigen',
        () {
      final grid = speciesOf([
        [speciesNoData, speciesCanopyLoss, 0x00],
      ]);
      for (var hx = 0; hx < 3; hx++) {
        final (lat, lon) = centerOf(grid, hx, 0);
        expect(grid.at(lat, lon), isNull, reason: 'Zelle $hx');
      }
      // Die Bytes bleiben unterscheidbar — der Kronenverlust ist
      // reserviert, nicht verworfen (#227).
      expect(grid.byteAt(centerOf(grid, 1, 0).$1, centerOf(grid, 1, 0).$2),
          speciesCanopyLoss);
      expect(grid.byteAt(centerOf(grid, 2, 0).$1, centerOf(grid, 2, 0).$2),
          0x00);
    });

    test('die Sonderwerte können keine echte Kombination verdecken', () {
      // Das Gegenstück zur selben Zusicherung in
      // `tool/forest_species.py`. Wüchse eine der beiden Tabellen bis
      // 15 Arten, verdeckte 0xFE plötzlich eine gültige Kombination —
      // und die Zelle schwiege, statt zu antworten. Heute ist der
      // Abstand groß; geprüft wird er trotzdem, weil er der Grund für
      // die Sonderbehandlung in `at` ist.
      final highest = (Broadleaf.values.length << 4) | Conifer.values.length;
      expect(highest, lessThan(speciesCanopyLoss));
      expect(speciesCanopyLoss, lessThan(speciesNoData));
    });

    test('unbekannte Halbbytes werden ignoriert statt geraten', () {
      // Ein Asset, das neuer ist als die App: Nibble 7 gibt es (noch)
      // nicht. Lieber keinen Namen als einen falschen.
      final grid = speciesOf([
        [0x70, 0x07, 0x71],
      ]);
      expect(grid.at(centerOf(grid, 0, 0).$1, centerOf(grid, 0, 0).$2),
          isNull);
      expect(grid.at(centerOf(grid, 1, 0).$1, centerOf(grid, 1, 0).$2),
          isNull);
      expect(grid.at(centerOf(grid, 2, 0).$1, centerOf(grid, 2, 0).$2),
          (broadleaf: null, conifer: Conifer.spruce));
    });
  });

  group('Punktabfrage', () {
    test('knapp außerhalb der Bounding Box: null, nicht die Randzelle', () {
      // **Knapp** ist hier der Punkt. Weit außerhalb liefert schon
      // `hexNearestCell` nichts, weil keine Kandidatzelle im Gitter
      // liegt — ein Test mit großem Abstand ginge deshalb auch ohne
      // Bereichsprüfung durch (von der Gegenprobe aufgedeckt). Gebraucht
      // wird sie für die knappe Überschreitung: Dort gäbe es sehr wohl
      // eine nächste Zelle, und die läge außerhalb der Abdeckung.
      final grid = speciesOf([
        [0x11, 0x11],
        [0x11, 0x11],
      ]);
      final inside = centerOf(grid, 0, 0);
      expect(grid.byteAt(inside.$1, inside.$2), 0x11,
          reason: 'die Prüfung darf nicht zu viel wegschneiden');
      expect(grid.byteAt(grid.north + _latStep * 0.25, inside.$2), isNull);
      expect(grid.byteAt(grid.south - _latStep * 0.25, inside.$2), isNull);
      expect(grid.byteAt(inside.$1, grid.west - _lonStep * 0.25), isNull);
      expect(grid.byteAt(inside.$1, grid.east + _lonStep * 0.25), isNull);
    });

    test('versetzte Zeilen: ungerade Zeilen liegen ein halbes Hex weiter',
        () {
      // Fängt eine als Quadratgitter gelesene Hex-Datei — die läge in
      // jeder zweiten Zeile ein halbes Hex daneben.
      final grid = speciesOf([
        [0x10, 0x10, 0x10],
        [0x01, 0x01, 0x01],
      ]);
      final (lat, lon) = centerOf(grid, 1, 1);
      expect(grid.at(lat, lon), (broadleaf: null, conifer: Conifer.spruce));
      expect(lon, closeTo(grid.west + _lonStep * 2.0, 1e-9),
          reason: 'ungerade Zeile ist um ein halbes Hex versetzt');
    });
  });

  group('Aufzählung', () {
    const both = (broadleaf: Broadleaf.beech, conifer: Conifer.spruce);

    test('die Reihenfolge folgt dem Nadelanteil', () {
      expect(speciesPhrase(both, coniferPercent: 80), 'Fichte und Buche');
      expect(speciesPhrase(both, coniferPercent: 20), 'Buche und Fichte');
      expect(speciesPhrase(both, coniferPercent: 50), 'Fichte und Buche',
          reason: 'genau die Hälfte zählt als Nadelwald');
    });

    test('ohne Nadelanteil steht das Laub vorn', () {
      // Kein Anteil bekannt heißt nicht „Nadelwald" — der Vorgabewert
      // darf keine Aussage erfinden.
      expect(speciesPhrase(both), 'Buche und Fichte');
    });

    test('eine Art allein steht ohne „und"', () {
      expect(
          speciesPhrase((broadleaf: null, conifer: Conifer.pine),
              coniferPercent: 90),
          'Kiefer');
      expect(
          speciesPhrase((broadleaf: Broadleaf.oak, conifer: null),
              coniferPercent: 10),
          'Eiche');
    });
  });

  test('dasselbe Hex-Raster wie das Waldtypen-Gitter', () {
    // **Die Zusicherung, auf der der ganze Entwurf steht.** Beide Gitter
    // werden mit EINER Zuordnung Punkt → Zelle nachgeschlagen; driften
    // ihre Maße auseinander, zeigt das Spot-Blatt die Arten der falschen
    // Wabe an — still, denn beide Antworten sehen plausibel aus.
    //
    // Geprüft wird an derselben Stelle mit denselben Schrittweiten: Die
    // Zelle, die das Waldgitter liefert, muss die Zelle sein, die das
    // Artengitter liefert.
    final species = speciesOf([
      [0x00, 0x01, 0x02, 0x03],
      [0x04, 0x05, 0x10, 0x20],
      [0x30, 0x40, 0x11, 0x22],
    ]);
    for (var hy = 0; hy < 3; hy++) {
      for (var hx = 0; hx < 4; hx++) {
        final (lat, lon) = centerOf(species, hx, hy);
        final cell = hexNearestCell(
          u: (lon - species.west) / species.hexLonStep,
          v: (species.north - lat) / species.hexLatStep,
          width: species.width,
          height: species.height,
        );
        expect(cell, (hx, hy), reason: 'Mittelpunkt von ($hx,$hy)');
        expect(species.byteAt(lat, lon), species.values[hy * 4 + hx]);
      }
    }
  });

  group('Vorrang und Rückfall (#624)', () {
    // Zwei Gitter über denselben Waben: gemessen (DLR, nur Deutschland)
    // und geschätzt (ForestPaths). Die Wabe (0,0) ist der Prüfpunkt.
    ForestSpeciesGrid dlr(int byte) => speciesOf([
          [byte, byte],
        ]);
    ForestSpeciesGrid eu(int byte) => speciesOf([
          [byte, byte],
        ], referenceYear: 2020);
    final (lat, lon) = centerOf(dlr(0), 0, 0);

    test('das DLR-Gitter gewinnt, wo es eine Art nennt', () {
      final r = forestSpeciesReadingAt(dlr(0x21), eu(0x11), lat, lon)!;
      expect(r.estimated, isFalse);
      expect(r.names.broadleaf, Broadleaf.oak);
      expect(r.referenceYear, 2022);
    });

    test('„Bäume ohne nennbare Art" und Kronenverlust sind AUSSAGEN', () {
      // Dort springt die Schätzung nicht ein — die bessere Quelle hat
      // gesprochen, und 2020 über einer Kahlfläche von 2022 wäre ein
      // Rückschritt.
      expect(forestSpeciesReadingAt(dlr(0x00), eu(0x11), lat, lon), isNull);
      expect(forestSpeciesReadingAt(dlr(speciesCanopyLoss), eu(0x11), lat, lon),
          isNull);
    });

    test('wo DLR schweigt, spricht die Schätzung — und sagt es', () {
      final r =
          forestSpeciesReadingAt(dlr(speciesNoData), eu(0x11), lat, lon)!;
      expect(r.estimated, isTrue);
      expect(r.names, (broadleaf: Broadleaf.beech, conifer: Conifer.spruce));
      expect(r.referenceYear, 2020);
      // Außerhalb des DLR-Gitters, und ganz ohne DLR-Gitter, genauso.
      expect(forestSpeciesReadingAt(null, eu(0x02), lat, lon)!.names.conifer,
          Conifer.pine);
    });

    test('die Schätzung nennt NIE Lärche, Eiche, Birke, Erle, Tanne', () {
      // Das Werkzeug schreibt nichts davon hinein; der Leser verlässt
      // sich trotzdem nicht darauf. 0x25 = Eiche + Lärche, 0x43 = Erle
      // + Tanne: nichts Nennbares übrig ⇒ keine Zeile.
      expect(forestSpeciesReadingAt(null, eu(0x25), lat, lon), isNull);
      expect(forestSpeciesReadingAt(null, eu(0x43), lat, lon), isNull);
      // 0x31 = Birke + Fichte: die Fichte bleibt, die Birke fällt weg.
      final r = forestSpeciesReadingAt(null, eu(0x31), lat, lon)!;
      expect(r.names, (broadleaf: null, conifer: Conifer.spruce));
    });

    test('ohne beide Gitter keine Aussage', () {
      expect(forestSpeciesReadingAt(null, null, lat, lon), isNull);
      expect(forestSpeciesReadingAt(dlr(speciesNoData), null, lat, lon),
          isNull);
    });
  });
}
