// Das Bodenfeuchte-Gitter (#676): Mittel über 26 Tage, Fortschreiben
// des jüngsten echten Tags bis gestern, höchstens acht Tage — und keine
// Zahl aus halben Fenstern.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/rain_grid_repository.dart';
import 'package:pilzbuddy/features/map/soil_moisture_grid.dart';

import 'rain_grid_test.dart' show encode;

void main() {
  // Zwei Zellen nebeneinander, 0,1° breit wie das echte Gitter:
  // 10,0–10,1° O und 10,1–10,2° O, eine Zeile über 50,0–50,1° N.
  RainStackData stackOf(Map<DateTime, List<int>> bytesByDay) => RainStackData(
        info: const RainStackInfo(
          width: 2,
          height: 1,
          west: 10,
          east: 10.2,
          north: 50.1,
          south: 50,
          days: [],
        ),
        days: [
          for (final MapEntry(key: date, value: bytes) in bytesByDay.entries)
            (date: date, gzipped: encode([bytes])),
        ],
        kind: RainStackKind.soil,
      );

  /// [count] Tage bis einschließlich [newest], je Zelle ein fester Byte.
  Map<DateTime, List<int>> days(DateTime newest, int count, List<int> bytes) =>
      {
        for (var i = 0; i < count; i++)
          DateTime(newest.year, newest.month, newest.day - i): bytes,
      };

  final end = DateTime(2026, 10, 7);

  test('Mittel über 26 Tage in m³/m³, je Zelle', () {
    final window = soilMoistureWindowFrom(
        stackOf(days(end, 30, [100, 50])), end)!;
    expect(window.meanAt(50.05, 10.05), closeTo(0.300, 1e-6));
    expect(window.meanAt(50.05, 10.15), closeTo(0.150, 1e-6));
    expect(window.latestAt(50.05, 10.05), closeTo(0.300, 1e-6));
    expect(window.carriedDays, 0);
  });

  test('ERA5-Land hängt nach: der jüngste echte Tag wird fortgeschrieben',
      () {
    // Echte Tage bis zum 2.10., das Fenster endet am 7.10. — fünf Tage
    // tragen den Wert des 2.10. Ältere Tage 60 (0,18), der 2.10. 120
    // (0,36): 20 echte × 0,18 + (1 echter + 5 fortgeschriebene) × 0,36.
    final newest = DateTime(2026, 10, 2);
    final stack = stackOf({
      ...days(DateTime(2026, 10, 1), 29, [60, 60]),
      newest: [120, 120],
    });
    final window = soilMoistureWindowFrom(stack, end)!;
    expect(window.newest, newest);
    expect(window.carriedDays, 5);
    expect(window.stale, isFalse);
    expect(window.meanAt(50.05, 10.05),
        closeTo((20 * 0.18 + 6 * 0.36) / 26, 1e-6));
    expect(window.latestAt(50.05, 10.05), closeTo(0.36, 1e-6));
  });

  test('mehr als acht Tage fortgeschrieben: zu alt, keine Zahl', () {
    final eight = soilMoistureWindowFrom(
        stackOf(days(DateTime(2026, 9, 29), 30, [100, 100])), end)!;
    expect(eight.carriedDays, 8);
    expect(eight.meanAt(50.05, 10.05), isNotNull, reason: 'acht gehen noch');
    final nine = soilMoistureWindowFrom(
        stackOf(days(DateTime(2026, 9, 28), 30, [100, 100])), end)!;
    expect(nine.stale, isTrue);
    expect(nine.meanAt(50.05, 10.05), isNull);
    final at = nine.at(50.05, 10.05);
    expect(at.stale, isTrue);
    expect(at.newest, DateTime(2026, 9, 28));
    expect(at.latest, closeTo(0.3, 1e-6),
        reason: 'die Zeile im Blatt nennt den Wert mit seinem Datum weiter');
  });

  test('eine Lücke mitten im Fenster heißt „kein Mittel"', () {
    final all = days(end, 30, [100, 100])
      ..remove(DateTime(2026, 9, 20));
    final window = soilMoistureWindowFrom(stackOf(all), end)!;
    expect(window.meanAt(50.05, 10.05), isNull);
    // Ein Tag VOR dem Fenster darf fehlen.
    final early = days(end, 30, [100, 100])..remove(DateTime(2026, 9, 8));
    expect(soilMoistureWindowFrom(stackOf(early), end)!.meanAt(50.05, 10.05),
        isNotNull);
  });

  test('„keine Daten" an einem Tag nimmt nur diese Zelle', () {
    final all = days(end, 30, [100, 100]);
    all[DateTime(2026, 9, 30)] = [100, soilMoistureNoData];
    final window = soilMoistureWindowFrom(stackOf(all), end)!;
    expect(window.meanAt(50.05, 10.05), isNotNull);
    expect(window.meanAt(50.05, 10.15), isNull);
  });

  test('außerhalb des Gitters keine Antwort', () {
    final window = soilMoistureWindowFrom(
        stackOf(days(end, 30, [100, 100])), end)!;
    expect(window.meanAt(50.05, 9.95), isNull);
    expect(window.meanAt(50.15, 10.05), isNull);
    expect(window.meanAt(49.95, 10.05), isNull);
    expect(window.latestAt(50.05, 10.25), isNull);
  });

  test('Tage nach dem Fensterende zählen nicht', () {
    // Ein Stand von morgen (Uhr des Geräts vorn): Das Fenster endet
    // trotzdem gestern.
    final stack = stackOf({
      ...days(end, 30, [100, 100]),
      DateTime(2026, 10, 8): [200, 200],
    });
    final window = soilMoistureWindowFrom(stack, end)!;
    expect(window.newest, end);
    expect(window.meanAt(50.05, 10.05), closeTo(0.3, 1e-6));
  });

  test('ohne Tage kein Fenster', () {
    expect(soilMoistureWindowFrom(stackOf({}), end), isNull);
  });
}
