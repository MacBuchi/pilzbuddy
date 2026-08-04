// Das Wetterdiagramm am Spot: Regenbalken hinten, Temperaturlinien vorn.
//
// **CustomPainter statt fl_chart** — bewusste Abweichung vom Muster der
// Jahresstatistik: fl_chart kennt kein Diagramm mit Balken UND Linien.
// Zwei übereinandergelegte Charts müssten ihre Plotflächen pixelgenau
// decken, und genau diese Deckung wäre die Fehlerquelle. Hier ist
// Balkenmitte = Linienstützpunkt per Konstruktion — beide fragen
// [WeatherChartPainter.centerX].
//
// **Die Geometrie, wie der Betreiber sie vorgegeben hat (2026-08-04):**
// eine kontinuierliche Zeitachse, jeder Balken „um 12 Uhr" seines Tages
// gezeichnet, darüber dünne durchgehende Temperaturlinien; links die
// °C-Skala, rechts die mm-Skala. Lücken (Tage ohne Messung) unterbrechen
// die Linie — eine erfundene Verbindung wäre eine Messung, die es nie gab.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/app_colors.dart';
import '../../../core/axis_scale.dart';
import '../../map/rain_stack.dart';
import '../../map/spot_weather.dart';

/// Ordnet eine Stationsreihe den Diagrammtagen zu — über das **Datum**,
/// nie über den Index: Regenstapel und Stationstabelle werden getrennt
/// veröffentlicht und dürfen um einen Tag auseinanderliegen. Ein
/// Index-Join wäre dann still um einen Tag verschoben — Wetter, das so
/// aussieht, als wäre es richtig.
List<double?> alignedTrack(List<DateTime> chartDays,
    List<DateTime> trackDays, List<double?> values) {
  final byDate = {
    for (final (index, day) in trackDays.indexed)
      (day.year, day.month, day.day): values[index],
  };
  return [
    for (final day in chartDays) byDate[(day.year, day.month, day.day)],
  ];
}

/// Zerlegt eine Reihe an ihren Lücken in zusammenhängende Stücke.
List<List<({int index, double value})>> lineSegments(List<double?> values) {
  final segments = <List<({int index, double value})>>[];
  List<({int index, double value})>? current;
  for (final (index, value) in values.indexed) {
    if (value == null) {
      current = null;
      continue;
    }
    if (current == null) {
      current = [];
      segments.add(current);
    }
    current.add((index: index, value: value));
  }
  return segments;
}

/// Die Beschriftung des rechten Zeitachsen-Endes.
///
/// „gestern" steht nur dort, wo es stimmt: Wer fünf Tage ohne Empfang
/// war, sieht das nackte Datum — ein „gestern" über altem Stand wäre
/// gelogen, und das Datum ist genau die Auskunft, die dann zählt.
String endLabel(DateTime newest, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final date = DateFormat('d.M.').format(newest);
  final matches = newest.year == yesterday.year &&
      newest.month == yesterday.month &&
      newest.day == yesterday.day;
  return matches ? 'gestern, $date' : date;
}

class WeatherChart extends StatelessWidget {
  const WeatherChart({
    super.key,
    required this.course,
    required this.temperature,
  });

  final RainCourse course;
  final SpotTemperature? temperature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dates = [for (final day in course.days) day.date];

    // Die Stationsreihen auf die Diagrammtage gelegt; eine Reihe, die im
    // gezeigten Fenster nur Lücken hätte, entfällt ganz (keine Legende
    // für eine unsichtbare Linie).
    List<double?>? align(List<double?>? track) {
      final temp = temperature;
      if (track == null || temp == null) return null;
      final aligned = alignedTrack(dates, temp.days, track);
      return aligned.any((value) => value != null) ? aligned : null;
    }

    final soil = align(temperature?.soilMean);
    final airMax = align(temperature?.max);
    final airMin = align(temperature?.min);

    double? low, high;
    for (final track in [soil, airMax, airMin]) {
      for (final value in track ?? const <double?>[]) {
        if (value == null) continue;
        low = low == null ? value : math.min(low, value);
        high = high == null ? value : math.max(high, value);
      }
    }
    final axis =
        low == null || high == null ? null : temperatureAxis(low, high);

    final peak = course.peak;
    final mmStep = yAxisStep(peak.toDouble());
    final mmMax = math.max(mmStep, (peak / mmStep).ceilToDouble() * mmStep);

    final weekday = DateFormat('E', 'de');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 112,
          width: double.infinity,
          child: CustomPaint(
            painter: WeatherChartPainter(
              mm: [for (final day in course.days) day.mm],
              weekdays: [
                for (final date in dates)
                  weekday.format(date).substring(0, 2),
              ],
              startLabel: DateFormat('d.M.').format(dates.first),
              endLabel: endLabel(dates.last, DateTime.now()),
              mmStep: mmStep,
              mmMax: mmMax,
              axis: axis,
              soil: soil,
              airMax: airMax,
              airMin: airMin,
              barColor: AppColors.friendBlue,
              hintColor: theme.hintColor,
              textColor:
                  theme.textTheme.bodySmall?.color ?? Colors.black87,
            ),
          ),
        ),
        if (axis != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            // Drei unbeschriftete Linien wären Rätselraten.
            child: Wrap(
              spacing: 12,
              children: [
                if (soil != null)
                  const _LegendEntry(
                      color: AppColors.tempSoil,
                      thickness: 2.2,
                      label: 'Boden 5 cm'),
                if (airMax != null)
                  const _LegendEntry(
                      color: AppColors.tempAirMax, label: 'Luft max'),
                if (airMin != null)
                  const _LegendEntry(
                      color: AppColors.tempAirMin, label: 'Luft min'),
              ],
            ),
          ),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.color,
    required this.label,
    this.thickness = 1.5,
  });

  final Color color;
  final String label;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: thickness, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(fontSize: 9)),
      ],
    );
  }
}

class WeatherChartPainter extends CustomPainter {
  WeatherChartPainter({
    required this.mm,
    required this.weekdays,
    required this.startLabel,
    required this.endLabel,
    required this.mmStep,
    required this.mmMax,
    required this.axis,
    required this.soil,
    required this.airMax,
    required this.airMin,
    required this.barColor,
    required this.hintColor,
    required this.textColor,
  });

  final List<int?> mm;
  final List<String> weekdays;
  final String startLabel;
  final String endLabel;
  final double mmStep;
  final double mmMax;
  final ({double low, double high, double step})? axis;
  final List<double?>? soil;
  final List<double?>? airMax;
  final List<double?>? airMin;
  final Color barColor;
  final Color hintColor;
  final Color textColor;

  static const _gutter = 30.0;
  static const _topPad = 14.0; // Einheiten über den Achsen
  static const _bottomBand = 26.0; // Wochentage + Datumszeile

  /// Die Fläche, in der Balken und Linien liegen. Ohne Temperatur bleibt
  /// links nur ein Rand — eine leere °C-Spalte sähe aus wie ein Fehler.
  @visibleForTesting
  Rect plotArea(Size size) => Rect.fromLTRB(axis == null ? 6 : _gutter,
      _topPad, size.width - _gutter, size.height - _bottomBand);

  /// „Um 12 Uhr gezeichnet": Tag [index] hat seine Mitte bei
  /// (index + 0,5) / Tage der Plotbreite — Balken UND Linien fragen
  /// diese eine Stelle.
  @visibleForTesting
  double centerX(int index, Size size) {
    final plot = plotArea(size);
    return plot.left + (index + 0.5) * plot.width / mm.length;
  }

  @visibleForTesting
  Rect barRect(int index, Size size) {
    final plot = plotArea(size);
    final value = mm[index];
    // Ein trockener oder ungemessener Tag bekommt einen Stummel statt
    // gar nichts: Eine Lücke sähe aus wie ein fehlender Tag.
    final height = value == null || value == 0 || mmMax == 0
        ? 2.0
        : math.max(2.0, plot.height * value / mmMax);
    final width = plot.width / mm.length * 0.6;
    final center = centerX(index, size);
    return Rect.fromLTWH(
        center - width / 2, plot.bottom - height, width, height);
  }

  @visibleForTesting
  double temperatureY(double value, Size size) {
    final a = axis!;
    final plot = plotArea(size);
    return plot.bottom - plot.height * (value - a.low) / (a.high - a.low);
  }

  @visibleForTesting
  Offset linePoint(int index, double value, Size size) =>
      Offset(centerX(index, size), temperatureY(value, size));

  @override
  void paint(Canvas canvas, Size size) {
    if (mm.isEmpty) return;
    final plot = plotArea(size);

    // Regenbalken — dieselbe Farbsprache wie der bisherige Verlauf.
    for (final (index, value) in mm.indexed) {
      final paint = Paint()
        ..color = value == null
            ? hintColor.withValues(alpha: 0.25)
            : barColor.withValues(alpha: value == 0 ? 0.3 : 0.85);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            barRect(index, size), const Radius.circular(1.5)),
        paint,
      );
    }

    // mm-Achse rechts, an der Balkenskala.
    _text(canvas, 'mm', 8, hintColor,
        Offset(plot.right + 4, plot.top - 12));
    for (var value = mmStep; value <= mmMax + 0.001; value += mmStep) {
      final y = plot.bottom - plot.height * value / mmMax;
      _text(canvas, value.toStringAsFixed(0), 9, hintColor,
          Offset(plot.right + 4, y - 5));
    }

    final a = axis;
    if (a != null) {
      // °C-Achse links.
      _text(canvas, '°C', 8, hintColor, Offset(plot.left - _gutter + 2,
          plot.top - 12));
      for (var value = a.low; value <= a.high + 0.001; value += a.step) {
        final y = temperatureY(value, size);
        _text(canvas, value.toStringAsFixed(0), 9, hintColor,
            Offset(plot.left - 4, y - 5),
            rightAlign: true);
      }

      // Frostgrenze: fein gestrichelt, nur wenn die Spanne 0° überquert.
      if (a.low < 0 && a.high > 0) {
        final y = temperatureY(0, size);
        final paint = Paint()
          ..color = hintColor.withValues(alpha: 0.6)
          ..strokeWidth = 1;
        for (var x = plot.left; x < plot.right; x += 7) {
          canvas.drawLine(
              Offset(x, y), Offset(math.min(x + 4, plot.right), y), paint);
        }
      }

      // Linien: Luftwerte dünn, Boden als Hauptlinie obenauf.
      _drawTrack(canvas, size, airMin, AppColors.tempAirMin, 1.5);
      _drawTrack(canvas, size, airMax, AppColors.tempAirMax, 1.5);
      _drawTrack(canvas, size, soil, AppColors.tempSoil, 2.2);
    }

    // Zeitachse: Wochentagskürzel unter den Balkenmitten …
    for (final (index, label) in weekdays.indexed) {
      final painter = _painterFor(label, 9, textColor);
      painter.paint(canvas,
          Offset(centerX(index, size) - painter.width / 2, plot.bottom + 2));
    }
    // … und an den Enden das Datum — damit die Richtung der Skala
    // unmissverständlich ist (Betreiber-Befund am Regendiagramm).
    _text(canvas, startLabel, 10, hintColor,
        Offset(plot.left, plot.bottom + 13));
    _text(canvas, endLabel, 10, hintColor,
        Offset(plot.right, plot.bottom + 13),
        rightAlign: true);
  }

  void _drawTrack(Canvas canvas, Size size, List<double?>? track,
      Color color, double width) {
    if (track == null) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final segment in lineSegments(track)) {
      if (segment.length == 1) {
        // Ein einzelner Messtag zwischen Lücken: Ein Strich der Länge
        // null wäre unsichtbar — ein Punkt zeigt, dass gemessen wurde.
        canvas.drawCircle(
            linePoint(segment.single.index, segment.single.value, size),
            width,
            Paint()..color = color);
        continue;
      }
      final path = Path();
      for (final (i, point) in segment.indexed) {
        final offset = linePoint(point.index, point.value, size);
        if (i == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  TextPainter _painterFor(String text, double fontSize, Color color) =>
      TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(fontSize: fontSize, color: color)),
        textDirection: TextDirection.ltr,
      )..layout();

  void _text(Canvas canvas, String text, double fontSize, Color color,
      Offset at, {bool rightAlign = false}) {
    final painter = _painterFor(text, fontSize, color);
    painter.paint(
        canvas, rightAlign ? at - Offset(painter.width, 0) : at);
  }

  @override
  bool shouldRepaint(WeatherChartPainter oldDelegate) =>
      oldDelegate.mm != mm ||
      oldDelegate.soil != soil ||
      oldDelegate.airMax != airMax ||
      oldDelegate.airMin != airMin ||
      oldDelegate.axis != axis ||
      oldDelegate.endLabel != endLabel;
}
