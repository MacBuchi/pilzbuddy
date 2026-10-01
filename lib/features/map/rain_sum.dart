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
import 'dart:math' as math;
import 'dart:typed_data';

import '../../data/rain_grid_repository.dart' show RainStackData;
import 'rain_grid.dart';

/// Wie viele Tage der Stapel ab seinem jüngsten LÜCKENLOS trägt.
///
/// Für den Satz im Blatt („noch 28 von 30 Tagen") — dieselbe Zählung,
/// an der [rainSumGrid] scheitert oder nicht.
///
/// [endDay] wie bei [rainSumGrid] — gezählt wird von dort zurück.
int rainStackRunLength(RainStackData stack, {DateTime? endDay}) {
  final dates = {for (final day in stack.days) _dayKey(day.date)};
  if (dates.isEmpty) return 0;
  final newest = endDay ??
      stack.days
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
///
/// [endDay] legt den letzten Tag fest, sonst ist es der jüngste des
/// Stapels. Gebraucht wird das, damit Radar- und Modellsumme an der
/// Grenze über DIESELBEN Tage laufen ([rainSumEndProvider]): Der
/// Modell-Stapel ist oft einen Tag weiter, und eine Woche, die einen Tag
/// später endet, ist eine andere Woche.
RainGrid? rainSumGrid(RainStackData stack, int days, {DateTime? endDay}) {
  if (days <= 0 || stack.days.isEmpty) return null;
  final info = stack.info;
  final newest = endDay ??
      stack.days
          .map((day) => day.date)
          .reduce((a, b) => a.isAfter(b) ? a : b);
  final byKey = {for (final day in stack.days) _dayKey(day.date): day};
  for (var age = 0; age < days; age++) {
    if (!byKey.containsKey(_dayKey(newest) - age)) return null;
  }

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
    measured: DateTime(newest.year, newest.month, newest.day),
  );
}

/// Der jüngste Tag des Stapels — `null` ohne Tage.
DateTime? rainStackNewest(RainStackData stack) => stack.days.isEmpty
    ? null
    : stack.days
        .map((day) => day.date)
        .reduce((a, b) => a.isAfter(b) ? a : b);

/// Breite der Übergangszone am Rand der Radarabdeckung, in Zellen des
/// Radargitters (≈ km).
///
/// Anlass (Betreiber, 2026-10-01, Bildschirmfoto Salzburg/Tirol): Die
/// Radarabdeckung endet in Österreich an geraden Linien — ein Rechteck in
/// der Projektion des Radarverbunds —, und dahinter beginnt das Modell.
/// Über 14 Tage lagen beide dort um das Drei- bis Fünffache auseinander
/// (Salzburg 51 gegen 16 mm), und die Karte zeigte eine scharfe Kante,
/// die nach einem Fehler aussah. 25 km sind breit genug, dass der
/// Übergang weich wird, und schmal genug, dass deutsche Werte unberührt
/// bleiben: Der Rand liegt überall jenseits der Grenze.
const rainEdgeBlendCells = 25;

/// [upper] (Radar oder W4) mit dem Rand zu [lower] (Modell) übergeblendet
/// — **nur zum Zeichnen**, wie das Glätten.
///
/// Je Zelle das Gewicht w = Abstand zur nächsten Zelle ohne Daten durch
/// [band] (gedeckelt bei 1); gezeichnet wird w·Radar + (1−w)·Modell. Am
/// Rand der Abdeckung steht also schon fast der Modellwert, und die
/// Modellfläche dahinter ([maskCovered]) schließt ohne Sprung an. Hat das
/// Modell an einer Zelle nichts (Deutschland, Nordsee, Frankreich),
/// bleibt der Radarwert — dort gibt es nichts, wohin geblendet würde.
///
/// Die Zahl am Spot bleibt davon unberührt: Sie kommt aus dem ROHEN
/// Gitter ([RainGrid.mmAt]), wie beim Glätten. Der Abstand ist eine
/// 3-4-Chamfer-Distanz in zwei Durchgängen — genau genug für eine
/// Überblendung, und linear in der Zellenzahl.
RainGrid blendEdge(RainGrid upper, RainGrid? lower,
    {int band = rainEdgeBlendCells}) {
  if (lower == null || band <= 0) return upper;
  final w = upper.width;
  final h = upper.height;
  final src = upper.values;
  // Chamfer-Distanz zur nächsten Zelle ohne Daten (Gitterrand zählt
  // NICHT als Rand: Dort endet nur das Bild, nicht die Messung).
  const far = 1 << 30;
  final dist = Int32List(w * h);
  for (var i = 0; i < w * h; i++) {
    dist[i] = src[i] == rainNoData ? 0 : far;
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      var d = dist[i];
      if (d == 0) continue;
      if (x > 0) d = math.min(d, dist[i - 1] + 3);
      if (y > 0) {
        d = math.min(d, dist[i - w] + 3);
        if (x > 0) d = math.min(d, dist[i - w - 1] + 4);
        if (x < w - 1) d = math.min(d, dist[i - w + 1] + 4);
      }
      dist[i] = d;
    }
  }
  for (var y = h - 1; y >= 0; y--) {
    for (var x = w - 1; x >= 0; x--) {
      final i = y * w + x;
      var d = dist[i];
      if (d == 0) continue;
      if (x < w - 1) d = math.min(d, dist[i + 1] + 3);
      if (y < h - 1) {
        d = math.min(d, dist[i + w] + 3);
        if (x < w - 1) d = math.min(d, dist[i + w + 1] + 4);
        if (x > 0) d = math.min(d, dist[i + w - 1] + 4);
      }
      dist[i] = d;
    }
  }

  final out = Uint8List.fromList(src);
  final limit = band * 3;
  for (var y = 0; y < h; y++) {
    double? lat;
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final d = dist[i];
      if (d == 0 || d >= limit) continue;
      lat ??= upper.latAtRow(y + 0.5);
      final model = lower.mmAt(lat, upper.lonAtColumn(x + 0.5));
      if (model == null) continue;
      final weight = d / limit;
      out[i] = (weight * src[i] + (1 - weight) * model).round();
    }
  }
  return RainGrid(
    values: out,
    width: w,
    height: h,
    west: upper.west,
    east: upper.east,
    north: upper.north,
    south: upper.south,
    measured: upper.measured,
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

/// Die Fläche des Alpenraums (#646): der gemessene Alpenstapel, wo er
/// etwas sagt, sonst das Modell — und zwar nur dort, wo auch Radar oder
/// W4 ([upper]) schweigen. Dieselbe Vorrangregel wie am Spot
/// (`rainCoursesFromStacks`), nur für Summen: Alpenstapel, dann Radar,
/// dann Modell.
///
/// Ohne Alpenstapel bleibt es bei der Modellfläche von 1.220.0 —
/// [maskCovered] unter dem Radar, in der 12-km-Geometrie des Modells.
/// Mit ihm liegt die Fläche in SEINER Geometrie (1 km), und das Modell
/// wird bilinear hineingelesen: Nach Zelle gelesen stünden dort
/// 12-km-Klötze, die die Engine nicht mehr weichzeichnen kann, weil das
/// Bild jetzt 1 km auflöst.
///
/// Wo der Alpenstapel einen Wert hat, wird [upper] nicht gefragt — die
/// Radarfläche spart diese Zellen ihrerseits aus (`maskCovered` mit dem
/// Alpenstapel als oberer Fläche). Beide Seiten zusammen decken jede
/// Zelle höchstens einmal.
RainGrid? alpineFillGrid(
    {required RainGrid? alps, required RainGrid? model, RainGrid? upper}) {
  if (alps == null) return model == null ? null : maskCovered(model, upper);
  final w = alps.width;
  final h = alps.height;
  final out = Uint8List.fromList(alps.values);
  if (model != null) {
    for (var y = 0; y < h; y++) {
      final lat = alps.latAtRow(y + 0.5);
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (out[i] != rainNoData) continue;
        final lon = alps.lonAtColumn(x + 0.5);
        if (upper?.mmAt(lat, lon) != null) continue;
        final value = bilinearMmAt(model, lat, lon);
        if (value != null) out[i] = value;
      }
    }
  }
  return RainGrid(
    values: out,
    width: w,
    height: h,
    west: alps.west,
    east: alps.east,
    north: alps.north,
    south: alps.south,
    measured: alps.measured,
  );
}

/// Der Wert an einem Punkt, zwischen den vier nächsten Zellmitten
/// gemittelt (in Mercator, wie das Gitter liegt). Fehlt eine der vier,
/// gilt die Zelle, in der der Punkt liegt — am Rand der Daten lieber
/// ein Klotz als ein Wert, der eine Lücke als 0 mm mitmittelt.
int? bilinearMmAt(RainGrid grid, double lat, double lon) {
  final nearest = grid.mmAt(lat, lon);
  if (nearest == null) return null;
  final top = mercatorY(grid.north);
  final bottom = mercatorY(grid.south);
  final fx = (lon - grid.west) / (grid.east - grid.west) * grid.width - 0.5;
  final fy = (mercatorY(lat) - top) / (bottom - top) * grid.height - 0.5;
  final x0 = fx.floor();
  final y0 = fy.floor();
  if (x0 < 0 || y0 < 0 || x0 + 1 >= grid.width || y0 + 1 >= grid.height) {
    return nearest;
  }
  final a = grid.at(x0, y0);
  final b = grid.at(x0 + 1, y0);
  final c = grid.at(x0, y0 + 1);
  final d = grid.at(x0 + 1, y0 + 1);
  if (a == null || b == null || c == null || d == null) return nearest;
  final tx = fx - x0;
  final ty = fy - y0;
  final value = (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty;
  return value.round().clamp(0, rainMaxMm);
}
