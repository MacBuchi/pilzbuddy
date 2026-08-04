// Marching Squares, Glätten und Vereinfachung.
//
// Die erste Gruppe rechnet ein Gitter von Hand nach, bevor irgendetwas an
// echten Daten läuft: Bei 550 000 Zellen und 170 000 Rohpunkten ist am
// Ergebnis nicht mehr zu sehen, ob die Interpolation, die Verkettung oder
// die Umrechnung in Grad danebenliegt. Sie läuft deshalb mit
// `smooth: false` — geglättet wären es andere Werte als die, die im Test
// stehen.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/rain_contours.dart';
import 'package:pilzbuddy/features/map/rain_grid.dart';

import 'rain_grid_test.dart' show gridOf;

void main() {
  group('Eine Linie, von Hand nachgerechnet', () {
    // Drei gleiche Zeilen mit einem Anstieg nach Osten. Auf Höhe 15 muss
    // genau eine senkrechte Linie herauskommen, und zwar in der Mitte
    // zwischen den Zellen mit 10 und 20.
    final grid = gridOf([
      [0, 10, 20, 30],
      [0, 10, 20, 30],
      [0, 10, 20, 30],
    ], west: 10, east: 14, north: 55, south: 47);

    List<ContourLine> plain(RainGrid g, List<int> levels) => rainContours(g,
        levels: levels,
        toleranceCells: 0,
        minChainCells: 0,
        smooth: false);

    test('liegt an der richtigen Stelle', () {
      final lines = plain(grid, [15]);
      expect(lines, hasLength(1));
      expect(lines.single.mm, 15);
      expect(lines.single.points, hasLength(3));
      // Zellmitten liegen bei Spalte 0,5 / 1,5 / 2,5 / 3,5; 10 und 20
      // sind die Zellen 1 und 2, der Schnitt bei 15 liegt genau dazwischen
      // — also Spalte 2,0 und damit 12,0 Grad.
      for (final point in lines.single.points) {
        expect(point.longitude, closeTo(12.0, 1e-9));
      }
    });

    test('trifft die Breiten der Zellmitten', () {
      final lats = plain(grid, [15]).single.points.map((p) => p.latitude)
          .toList()
        ..sort();
      for (var row = 0; row < 3; row++) {
        expect(lats[2 - row], closeTo(grid.latAtRow(row + 0.5), 1e-9),
            reason: 'Zeile $row');
      }
    });

    test('rückt mit der Höhe an die richtige Stelle', () {
      // Bei 12 mm liegt der Schnitt zwischen den Zellen 10 und 20 bei
      // einem Fünftel — nicht in der Mitte. Ohne diese Zusicherung wäre
      // eine Interpolation, die immer 0,5 nimmt, nicht zu unterscheiden.
      // Zelle 1 hat 10 mm, Zelle 2 hat 20 mm, gesucht ist 12 — der
      // Schnitt liegt bei einem Fünftel, also bei Abtastpunkt 1,2 und
      // damit bei Spalte 1,7. Vier Grad auf vier Spalten: 11,7°.
      final lines = plain(grid, [12]);
      expect(lines.single.points.first.longitude, closeTo(11.7, 1e-9));
    });

    test('verkettet zu EINEM Zug statt zu Bruchstücken', () {
      // Die Verkettung läuft über Kantenkennungen. Über Koordinaten
      // gliche sie Fließkommazahlen, die zwei Nachbarzellen auf
      // verschiedenen Wegen ausrechnen — das zerfiele gelegentlich.
      final tall = gridOf([for (var i = 0; i < 40; i++) [0, 10, 20, 30]]);
      final lines = plain(tall, [15]);
      expect(lines, hasLength(1));
      expect(lines.single.points, hasLength(40));
    });

    test('bleibt EIN Zug, auch wenn er in der Mitte gefunden wird', () {
      // Ein Dach: Die Linie läuft von unten links über die Spitze nach
      // unten rechts. Abgetastet wird zeilenweise von oben, gefunden
      // wird sie also NAHE DER SPITZE — mitten im Zug.
      //
      // Wer von dort aus loslaufen lässt, bekommt zwei Hälften statt
      // eines Zuges. Nicht falsch, aber doppelt so viele Linien und
      // eine schlechtere Vereinfachung. Deshalb laufen die Enden
      // zuerst, und deshalb steht dieser Test hier: Der geradlinige
      // Fall oben kann ihn nicht prüfen, weil dessen erster Fund
      // schon ein Ende ist.
      const o = 0;
      const x = 30;
      // Die Spitze muss eine Zeile Luft nach oben haben — läge sie auf
      // der obersten Zeile, verließe die Linie das Gitter dort, und
      // zwei Züge wären richtig.
      final roof = gridOf([
        [o, o, o, o, o, o, o, o, o],
        [o, o, o, o, x, o, o, o, o],
        [o, o, o, x, x, x, o, o, o],
        [o, o, x, x, x, x, x, o, o],
        [o, x, x, x, x, x, x, x, o],
        [x, x, x, x, x, x, x, x, x],
      ]);
      final lines = rainContours(roof,
          levels: [15], toleranceCells: 0, minChainCells: 0, smooth: false);
      expect(lines, hasLength(1),
          reason: 'zwei Linien heißt: in der Mitte losgelaufen');
    });

    test('findet nichts oberhalb des größten Werts', () {
      expect(plain(grid, [31]), isEmpty);
      expect(plain(grid, [0]), isEmpty);
    });

    test('liefert bei gleicher Eingabe genau dasselbe', () {
      // Die Sattelpunkte 5 und 10 sind mehrdeutig und werden immer
      // gleich aufgelöst. Ohne das wäre kein Test hier reproduzierbar.
      String render(List<ContourLine> lines) => lines
          .map((l) => '${l.mm}:${l.points.map((p) => '${p.latitude},'
              '${p.longitude}').join(';')}')
          .join('|');
      expect(render(plain(grid, [5, 15, 25])),
          render(plain(grid, [5, 15, 25])));
    });
  });

  group('Lücken im Gitter', () {
    test('unterbrechen die Linie, statt geraten zu werden', () {
      // Am Rand des Radarverbunds hört die Linie auf. Eine Zelle mit
      // einer unbekannten Ecke wird übersprungen — würde sie mit 0
      // gerechnet, liefe eine falsche Linie am Datenrand entlang.
      const rows = [0, 10, 20, 30];
      final grid = gridOf([
        rows, rows, rows,
        [0, rainNoData, rainNoData, 30],
        rows, rows, rows,
      ]);
      final lines = rainContours(grid,
          levels: [15], toleranceCells: 0, minChainCells: 0, smooth: false);
      expect(lines, hasLength(2), reason: 'ein Zug ober-, einer unterhalb');
      for (final line in lines) {
        expect(line.points, hasLength(3));
      }
      // Und keiner der beiden überspringt die Lücke.
      final gapLat = grid.latAtRow(3.5);
      for (final line in lines) {
        for (final point in line.points) {
          expect(point.latitude, isNot(closeTo(gapLat, 1e-9)));
        }
      }
    });

    test('ergeben gar nichts, wenn das ganze Gitter leer ist', () {
      final grid = gridOf([
        [rainNoData, rainNoData],
        [rainNoData, rainNoData],
      ]);
      expect(rainContours(grid, levels: [15]), isEmpty);
    });
  });

  group('Vereinfachung', () {
    test('macht aus einer Geraden zwei Punkte, ohne sie wegzuwerfen', () {
      // Die Falle, in die ich beim ersten Anlauf gelaufen bin: Wird die
      // Mindestlänge auf das ERGEBNIS angewandt, verschwindet genau
      // diese Linie — 40 Zellen lang, nach der Vereinfachung zwei
      // Punkte, also scheinbar ein Fragment.
      final grid = gridOf([for (var i = 0; i < 40; i++) [0, 10, 20, 30]]);
      final full = rainContours(grid,
          levels: [15], toleranceCells: 0, smooth: false);
      final simple = rainContours(grid,
          levels: [15], toleranceCells: 2, smooth: false);
      expect(full.single.points, hasLength(40));
      expect(simple.single.points, hasLength(2));
      // Die Enden bleiben, wo sie waren — eine Vereinfachung, die die
      // Linie verkürzt, wäre keine.
      expect(simple.single.points.first.latitude,
          closeTo(full.single.points.first.latitude, 1e-9));
      expect(simple.single.points.last.latitude,
          closeTo(full.single.points.last.latitude, 1e-9));
    });

    test('behält, was weiter als die Toleranz abweicht', () {
      List<List<int>> zigzag(int depth) => [
            for (var y = 0; y < 9; y++)
              [
                for (var x = 0; x < 12; x++)
                  (y == 4 && x >= 3 && x < 3 + depth) ? 30 : (x < 6 ? 0 : 30)
              ]
          ];
      List<ContourLine> run(int depth) => rainContours(gridOf(zigzag(depth)),
          levels: [15], toleranceCells: 2, smooth: false);
      expect(run(4).single.points.length,
          greaterThan(run(0).single.points.length),
          reason: 'die Zacke muss die Vereinfachung überleben');
    });
  });

  group('Verworfene Fragmente', () {
    test('werden gezählt, nicht verschwiegen', () {
      // Zwei einzelne Flecken. Jeder erzeugt einen kurzen geschlossenen
      // Ring — genau die Sprenkel, die auf der Karte nichts aussagen.
      final grid = gridOf([
        [0, 0, 0, 0, 0],
        [0, 30, 0, 0, 0],
        [0, 0, 0, 0, 0],
        [0, 0, 0, 30, 0],
        [0, 0, 0, 0, 0],
      ]);
      final stats = rainContourStats(grid,
          levels: [15], toleranceCells: 2, smooth: false);
      expect(stats.dropped, 2);
      expect(stats.lines, 0);
      expect(stats.rawPoints, greaterThan(0),
          reason: 'gefunden wurden sie schon — sie fielen nur weg');
      expect(
          rainContours(grid, levels: [15], toleranceCells: 2, smooth: false),
          isEmpty);
      // Ohne die Schranke sind sie da.
      expect(
          rainContours(grid,
              levels: [15],
              toleranceCells: 2,
              minChainCells: 0,
              smooth: false),
          isNotEmpty);
    });
  });

  group('Glätten', () {
    test('mittelt über 3×3', () {
      final grid = gridOf([
        [0, 0, 0],
        [0, 90, 0],
        [0, 0, 0],
      ]);
      final smooth = grid.smoothed();
      // Mitte: 90/9 = 10. Ecke: 90/4 ≈ 23 (nur vier Zellen im Fenster).
      expect(smooth.at(1, 1), 10);
      expect(smooth.at(0, 0), 23);
      // Und die Summe bleibt ungefähr erhalten — kein Wert verschwindet.
      expect(smooth.values.fold<int>(0, (a, b) => a + b), greaterThan(80));
    });

    test('lässt Lücken Lücken und zieht die Nachbarn nicht herunter', () {
      // Würden Nichtdaten als 0 mitgemittelt, entstünde am Rand des
      // Radarverbunds ein Gefälle, das es nicht gibt — und damit eine
      // Höhenlinie, die die Grenze der Messung nachzeichnet statt den
      // Regen.
      final grid = gridOf([
        [rainNoData, 60, 60],
        [rainNoData, 60, 60],
        [rainNoData, 60, 60],
      ]);
      final smooth = grid.smoothed();
      expect(smooth.at(0, 1), isNull);
      expect(smooth.at(1, 1), 60);
      expect(smooth.at(2, 1), 60);
    });

    test('ändert die Zahl am Spot NICHT', () {
      // Der Grund, warum das Glätten eine Ansichtssache ist: `mmAt`
      // läuft auf dem ungeglätteten Gitter. Wer 90 mm liest, bekommt
      // die 90 mm seiner Zelle, nicht 10.
      final grid = gridOf([
        [0, 0, 0],
        [0, 90, 0],
        [0, 0, 0],
      ]);
      final before = grid.mmAt(51, 12);
      grid.smoothed();
      expect(grid.mmAt(51, 12), before);
      expect(before, 90);
    });

    test('spart Ketten, statt sie nur zu verschieben', () {
      // Ein Feld mit Sprenkeln: geglättet bleiben deutlich weniger
      // Ketten übrig. An echten Daten gemessen 8 874 → 1 995.
      final rows = [
        for (var y = 0; y < 12; y++)
          [
            for (var x = 0; x < 12; x++)
              (x + y) % 3 == 0 ? 30 : (x * 2 + y)
          ]
      ];
      final grid = gridOf(rows);
      final rough = rainContourStats(grid,
          levels: [15], toleranceCells: 2, minChainCells: 0, smooth: false);
      final gentle = rainContourStats(grid,
          levels: [15], toleranceCells: 2, minChainCells: 0, smooth: true);
      expect(gentle.lines, lessThan(rough.lines));
    });

    test('ist die Vorgabe beim Zeichnen', () {
      // Ohne diese Zusicherung ließe sich das Glätten aus der
      // Zeichenstrecke entfernen, ohne dass ein Test es merkt — und
      // niemand sähe es, außer an 78 % mehr Ketten auf dem Gerät.
      final rows = [
        for (var y = 0; y < 12; y++)
          [
            for (var x = 0; x < 12; x++)
              (x + y) % 3 == 0 ? 30 : (x * 2 + y)
          ]
      ];
      final grid = gridOf(rows);
      final byDefault =
          rainContours(grid, levels: [15], minChainCells: 0);
      final unsmoothed = rainContours(grid,
          levels: [15], minChainCells: 0, smooth: false);
      expect(byDefault.length, lessThan(unsmoothed.length));
    });
  });

  group('Dichte nach Maßstab', () {
    // Der Befund vom Pixel 7 (2026-08-04): Eingezoomt sind die Linien
    // sparsam und klar, in der Deutschlandübersicht zeichnen dieselben
    // Daten ein Geflecht — hunderte Ringe von je wenigen Pixeln.
    const short = ContourLine(mm: 30, points: [], cells: 4);
    const long = ContourLine(mm: 30, points: [], cells: 400);

    test('wirft in der Übersicht die kurzen Ringe weg', () {
      final visible = rainContoursAtZoom([short, long], 6, levels: const [30]);
      expect(visible, [long]);
    });

    test('zeigt eingezoomt auch die kurzen', () {
      final visible = rainContoursAtZoom([short, long], 13, levels: const [30]);
      expect(visible, hasLength(2));
    });

    test('hängt an der Bildschirmlänge, nicht an Zoom-Schwellen', () {
      // Dieselbe Linie muss genau dann sichtbar werden, wenn sie die
      // geforderte Pixellänge erreicht — nicht bei einer geratenen
      // Zoomstufe. Bei doppelter Mindestlänge braucht es eine
      // Zoomstufe mehr, weil jede Stufe die Pixel verdoppelt.
      double firstVisibleZoom(double minPixels) {
        for (var z = 0.0; z < 22; z += 0.05) {
          if (rainContoursAtZoom([short], z, levels: const [30], minPixels: minPixels)
              .isNotEmpty) {
            return z;
          }
        }
        return 22;
      }
      expect(firstVisibleZoom(80) - firstVisibleZoom(40), closeTo(1.0, 0.06));
    });

    test('dünnt die Höhenstufen mit dem Maßstab aus', () {
      // Dieselbe Regel wie auf jeder topografischen Karte: Die
      // Äquidistanz wächst, wenn der Maßstab kleiner wird. Aus der Ferne
      // jede vierte Linie, aus der Nähe alle.
      const levels = [10, 20, 30, 40, 50, 75, 100, 150];
      expect(rainLevelsAtZoom(levels, 13), levels);
      expect(rainLevelsAtZoom(levels, 9), [10, 30, 50, 100]);
      expect(rainLevelsAtZoom(levels, 6), [10, 50]);
      // Und sie beginnt immer bei der untersten Stufe, damit die Karte
      // beim Zoomen nicht die Farben wechselt.
      for (final zoom in [5.0, 7.0, 9.0, 11.0, 14.0]) {
        expect(rainLevelsAtZoom(levels, zoom).first, 10, reason: '$zoom');
      }
    });

    test('lässt bei Null-Schranke alles durch', () {
      expect(rainContoursAtZoom([short, long], 0, levels: const [30], minPixels: 0), hasLength(2));
    });
  });

  group('Höhenstufen', () {
    test('sind aufsteigend und ohne Wertung benannt', () {
      for (final levels in [rainLevels30d, rainLevels24h]) {
        expect(levels, isNotEmpty);
        for (var i = 1; i < levels.length; i++) {
          expect(levels[i], greaterThan(levels[i - 1]));
        }
        expect(levels.first, greaterThan(0),
            reason: '0 mm ist keine Höhenlinie, sondern die Fläche');
        expect(levels.last, lessThan(rainMaxMm),
            reason: 'eine Stufe über dem Quantisierungsdeckel fände nie '
                'etwas');
      }
    });

    test('lösen die deutsche Verteilung auf, statt sie zu bündeln', () {
      // Der Grund, warum es NICHT die DWD-Marken (alle 30 mm) sind: Am
      // 2026-08-03 lag der deutsche Median bei 37 mm, 25 % unter 22 mm
      // und 90 % unter 69 mm. Die gemessenen Perzentile müssen sich auf
      // mehrere Stufen verteilen, sonst ist die Karte einfarbig.
      const measured = [8.1, 12.0, 22.3, 37.1, 52.2, 69.0, 81.7, 112.5];
      final hit = <int>{};
      for (final value in measured) {
        hit.add(rainLevels30d.where((l) => l <= value).length);
      }
      expect(hit.length, greaterThanOrEqualTo(6),
          reason: 'die Stufen bündeln die reale Verteilung zu stark');
    });
  });
}
