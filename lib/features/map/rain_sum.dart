// Regensummen über mehrere Tage, gerechnet aus einem Tagesstapel.
//
// Warum es das gibt (Betreiber, 2026-10-01): Die Ebene „30 Tage“ war im
// Alpenraum leer — RADOLAN-W4 ist ein Deutschland-Produkt —, und für 7
// und 14 Tage hat der DWD gar keins. Die Tagesgitter liegen aber ohnehin
// auf dem Gerät: der Radar-Stapel für Deutschland, der Modell-Stapel
// (#612) für den Alpenraum. Die Summe ist eine Addition je Zelle.
//
// Reines Dart ohne Flutter, wie `rain_grid.dart`, damit
// `test/rain_sum_test.dart` die Regeln ohne Karte prüft.
import 'dart:typed_data';

import '../../data/rain_grid_repository.dart' show RainStackData;
import 'rain_grid.dart';

/// Wie viele Tage der Stapel ab seinem jüngsten LÜCKENLOS trägt.
///
/// Für den Satz im Blatt („noch 28 von 30 Tagen") — dieselbe Zählung,
/// an der [rainSumGrid] scheitert oder nicht.
int rainStackRunLength(RainStackData stack) {
  final dates = {for (final day in stack.days) _dayKey(day.date)};
  if (dates.isEmpty) return 0;
  final newest = stack.days
      .map((day) => day.date)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  var run = 0;
  while (dates.contains(_dayKey(newest) - run)) {
    run++;
  }
  return run;
}

/// Die Summe der jüngsten [days] Tage je Zelle — `null`, wenn der Stapel
/// diese Tage nicht lückenlos trägt oder ein Tag nicht auszupacken ist.
///
/// Dieselbe Regel wie `RainCourse.sumOfLast` am Spot: Eine Summe über
/// ein Fenster mit Lücke wäre eine erfundene Zahl, die zu klein ist —
/// und „zu trocken" ist hier genau die Aussage, nach der man sucht.
/// Aus demselben Grund wird eine ZELLE, der an einem der Tage ein Wert
/// fehlt, zu [rainNoData] und nicht zu einer Teilsumme.
///
/// Gekappt bei [rainMaxMm] wie die Quantisierung im Werkzeug. Gemessen
/// wird ab dem jüngsten Tag des Stapels, nicht ab heute: Ohne Empfang
/// zeigt die Ebene den letzten Stand, und [RainGrid.measured] sagt
/// welchen.
///
/// Die Tageswerte sind schon auf ganze Millimeter gerundet; über 30 Tage
/// summiert sich das im Mittel heraus und bleibt im schlimmsten Fall
/// unter 15 mm — weniger als eine Stufe der Ebene.
RainGrid? rainSumGrid(RainStackData stack, int days) {
  if (days <= 0 || rainStackRunLength(stack) < days) return null;
  final info = stack.info;
  final newest = stack.days
      .map((day) => day.date)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final byKey = {for (final day in stack.days) _dayKey(day.date): day};

  final cells = info.width * info.height;
  final sum = Uint16List(cells);
  final missing = Uint8List(cells);
  for (var age = 0; age < days; age++) {
    final day = byKey[_dayKey(newest) - age]!;
    final RainGrid grid;
    try {
      // Ein Tag nach dem anderen ausgepackt, wie in `ampelLevelsFrom`:
      // alle auf einmal wären beim Radar über 20 MB.
      grid = RainGrid.decode(
        day.gzipped,
        width: info.width,
        height: info.height,
        west: info.west,
        east: info.east,
        north: info.north,
        south: info.south,
        measured: day.date,
      );
    } catch (_) {
      // Ein kaputter Tag ist eine Lücke — dieselbe Antwort wie oben.
      return null;
    }
    final values = grid.values;
    for (var i = 0; i < cells; i++) {
      final value = values[i];
      if (value == rainNoData) {
        missing[i] = 1;
      } else {
        sum[i] += value;
      }
    }
  }

  final out = Uint8List(cells);
  for (var i = 0; i < cells; i++) {
    out[i] = missing[i] == 1
        ? rainNoData
        : (sum[i] > rainMaxMm ? rainMaxMm : sum[i]);
  }
  return RainGrid(
    values: out,
    width: info.width,
    height: info.height,
    west: info.west,
    east: info.east,
    north: info.north,
    south: info.south,
    measured: newest,
  );
}

/// [lower] ohne die Zellen, deren Mitte [upper] schon abdeckt — die
/// Vorrangregel „Radar zuerst" (#612) für zwei FLÄCHEN.
///
/// Die Modellmaske spart Deutschland nur nach einer Grenzlinie aus; das
/// Radar und W4 reichen aber darüber hinaus (gemessen 2026-10-01:
/// Salzburg und Bregenz haben W4-Werte, Berchtesgaden Modellwerte). Ohne
/// das lägen dort zwei halbdurchsichtige Flächen übereinander, ein
/// dunklerer Streifen in zwei Farben. Gefragt wird je Zellmitte über
/// [RainGrid.mmAt] — dieselbe Frage, die der Spot stellt.
RainGrid maskCovered(RainGrid lower, RainGrid? upper) {
  if (upper == null) return lower;
  final values = Uint8List.fromList(lower.values);
  for (var y = 0; y < lower.height; y++) {
    final lat = lower.latAtRow(y + 0.5);
    for (var x = 0; x < lower.width; x++) {
      final i = y * lower.width + x;
      if (values[i] == rainNoData) continue;
      if (upper.mmAt(lat, lower.lonAtColumn(x + 0.5)) != null) {
        values[i] = rainNoData;
      }
    }
  }
  return RainGrid(
    values: values,
    width: lower.width,
    height: lower.height,
    west: lower.west,
    east: lower.east,
    north: lower.north,
    south: lower.south,
    measured: lower.measured,
  );
}

/// Kalendertag als fortlaufende Zahl — über das DATUM, nicht über
/// Stunden: `subtract(Duration(days: 1))` liefe an der Zeitumstellung
/// auf 23 Uhr des Vorvortags.
int _dayKey(DateTime date) {
  final utc = DateTime.utc(date.year, date.month, date.day);
  return utc.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}
