// Die Symbole rund um „Unterwegs" (#343).
//
// **Warum gezeichnet und nicht aus Material genommen.** Der Betreiber:
// „Der Wanderer sollte einen Pilzkorb in der Hand haben und keinen
// Wanderstock." `Icons.hiking` ist genau der Wanderer mit Stock, und
// Material hat keinen mit Korb — `shopping_basket` wäre ein Korb ohne
// Menschen, und das sagt „einkaufen", nicht „losgehen".
//
// **Warum es seit 1.133.0 DREI Symbole sind statt einem.** Der Knopf auf
// der Karte steht für „Unterwegs" und damit für BEIDE Funktionen —
// Pilztour und Standort-Teilen. Ein Wanderer mit Korb sagt davon nur
// die eine. [TourIcon] trägt deshalb jetzt einen gepunkteten Weg mit
// einem Pilz daneben: der Weg das Unterwegs, der Pilz das Thema.
//
// Im Blatt wird dann getrennt, und dort darf jedes Symbol genau eine
// Sache sagen: [MushroomBasketIcon] für die Tour, [SharePinIcon] für das
// Teilen. Kein Symbol muss zwei Dinge gleichzeitig bedeuten.
//
// Der Wanderer selbst ist damit weg. Seine Begründung war richtig und
// ist es geblieben — sie galt nur einem Symbol, das zwei Aufgaben
// gleichzeitig trug. Der Korb, um den es dem Betreiber ging, steht jetzt
// unverdeckt im Blatt.
//
// **Die Größe bestimmt den Stil.** Der Knopf zeigt das hier bei 24 dp,
// also gilt dieselbe Regel wie bei den Pilz-Symbolen: klare, fette
// Formen, keine Feinheiten. Alles ist EINE Fläche in der aktuellen
// `IconTheme`-Farbe — damit funktioniert es auf hellem wie auf farbigem
// Grund, ohne zweite Fassung.
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ein gepunkteter Weg, daneben ein Pilz — „ich bin unterwegs, und zwar
/// deswegen".
class TourIcon extends StatelessWidget {
  const TourIcon({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) => _Painted(size: size, painter: _tour);

  static void _tour(Canvas canvas, double u, Paint fill, Paint stroke) {
    // **Drei gesetzte Punkte statt eines abgetasteten Pfades.** Der
    // erste Anlauf lief `PathMetric` über eine Kurve und setzte alle
    // 3,7 Einheiten einen Punkt — auf dem Kontaktbogen bei 24 dp (der
    // ECHTEN Knopfgröße) war das Ergebnis nicht als Weg zu erkennen,
    // sondern als Schmutz neben dem Pilz: Die Punkte waren zu klein,
    // standen zu dicht und liefen in den Hut hinein.
    //
    // Gesetzte Punkte lösen beides. Sie stehen weit genug auseinander,
    // um bei 24 dp einzeln zu bleiben, und ihr ABSTAND ist gewollt und
    // nicht das Ergebnis einer Kurvenlänge. Dass sie nach hinten
    // kleiner werden, ist die ganze Perspektive, die es braucht — sie
    // gibt dem Weg eine Richtung, ohne einen Pfeil zu brauchen.
    //
    // Die Diagonale ist die zweite Hälfte: Punkte unten links, Pilz
    // oben rechts. Ohne sie berührte der oberste Punkt den Hutrand, und
    // eine Berührung bei 24 dp ist eine Verschmelzung.
    for (final (x, y, r) in const [
      (3.9, 20.6, 2.25),
      (7.1, 17.0, 1.7),
      (9.3, 12.9, 1.25),
    ]) {
      canvas.drawCircle(Offset(x * u, y * u), r * u, fill);
    }

    // Der Pilz: Hut als flache Kuppe auf einer waagerechten Kante,
    // Stiel darunter. Kein Gesicht — bei 24 dp wären Augen zwei Pixel
    // und damit wieder Schmutz.
    canvas.drawPath(
      Path()
        ..moveTo(10.8 * u, 10.9 * u)
        ..lineTo(22.6 * u, 10.9 * u)
        ..lineTo(22.6 * u, 9.7 * u)
        ..cubicTo(22.6 * u, 6.2 * u, 19.9 * u, 3.7 * u, 16.7 * u, 3.7 * u)
        ..cubicTo(13.5 * u, 3.7 * u, 10.8 * u, 6.2 * u, 10.8 * u, 9.7 * u)
        ..close(),
      fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(14.9 * u, 10.9 * u)
        ..lineTo(18.5 * u, 10.9 * u)
        ..lineTo(18.5 * u, 16.4 * u)
        ..cubicTo(18.5 * u, 17.8 * u, 17.7 * u, 18.6 * u, 16.7 * u, 18.6 * u)
        ..cubicTo(15.7 * u, 18.6 * u, 14.9 * u, 17.8 * u, 14.9 * u, 16.4 * u)
        ..close(),
      fill,
    );
  }
}

/// Das Körbchen mit zwei Pilzköpfen — die Pilztour im Blatt.
///
/// Die Köpfe sitzen GANZ ÜBER der Korbkante, nicht darin. Im ersten
/// Anlauf (1.102.0) waren sie hineingezeichnet und in derselben Farbe:
/// Damit waren sie unsichtbar und der Korb bekam nur eine Delle. Als
/// Kuppen auf der Kante geben sie der Silhouette zwei Buckel, und genau
/// die machen aus einem Korb einen PILZkorb.
class MushroomBasketIcon extends StatelessWidget {
  const MushroomBasketIcon({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) => _Painted(size: size, painter: _basket);

  static void _basket(Canvas canvas, double u, Paint fill, Paint stroke) {
    // Der Henkel — er macht aus dem Trog einen Korb, den man trägt.
    stroke.strokeWidth = 1.8 * u;
    canvas.drawPath(
      Path()
        ..moveTo(8 * u, 9 * u)
        ..cubicTo(8 * u, 6.1 * u, 9.8 * u, 4 * u, 12 * u, 4 * u)
        ..cubicTo(14.2 * u, 4 * u, 16 * u, 6.1 * u, 16 * u, 9 * u),
      stroke,
    );
    // Zwei Kuppen über der Kante.
    canvas.drawPath(
      Path()
        ..moveTo(6.6 * u, 9.2 * u)
        ..cubicTo(6.6 * u, 7.5 * u, 8 * u, 6.3 * u, 9.6 * u, 6.3 * u)
        ..cubicTo(11.2 * u, 6.3 * u, 12.6 * u, 7.5 * u, 12.6 * u, 9.2 * u)
        ..close(),
      fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(13.3 * u, 9.2 * u)
        ..cubicTo(13.3 * u, 7.9 * u, 14.3 * u, 7 * u, 15.5 * u, 7 * u)
        ..cubicTo(16.7 * u, 7 * u, 17.7 * u, 7.9 * u, 17.7 * u, 9.2 * u)
        ..close(),
      fill,
    );
    // Die Kante und der sich verjüngende Trog — die schrägen Wände
    // unterscheiden ihn vom Eimer.
    canvas.drawRRect(
      RRect.fromLTRBR(3.2 * u, 9.2 * u, 20.8 * u, 11.6 * u,
          Radius.circular(1.2 * u)),
      fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(5.2 * u, 12.2 * u)
        ..lineTo(18.8 * u, 12.2 * u)
        ..lineTo(17.3 * u, 20.4 * u)
        ..lineTo(6.7 * u, 20.4 * u)
        ..close(),
      fill,
    );
  }
}

/// Ein Pin mit gestricheltem Rand — das Standort-Teilen im Blatt.
///
/// **Der Strich trägt die Aussage.** Ein voller Pin hieße „hier bin
/// ich"; gestrichelt heißt „hier bin ich, vorübergehend". Das Teilen
/// läuft bis zu einer Uhrzeit und hört dann von selbst auf — genau das
/// unterscheidet es von einem Spot, und genau das soll das Symbol sagen.
class SharePinIcon extends StatelessWidget {
  const SharePinIcon({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) => _Painted(size: size, painter: _pin);

  static void _pin(Canvas canvas, double u, Paint fill, Paint stroke) {
    stroke.strokeWidth = 2 * u;
    _dashed(
      canvas,
      Path()
        ..moveTo(12 * u, 2.5 * u)
        ..cubicTo(7.9 * u, 2.5 * u, 4.5 * u, 5.8 * u, 4.5 * u, 9.9 * u)
        ..cubicTo(4.5 * u, 15.5 * u, 12 * u, 22 * u, 12 * u, 22 * u)
        ..cubicTo(12 * u, 22 * u, 19.5 * u, 15.5 * u, 19.5 * u, 9.9 * u)
        ..cubicTo(19.5 * u, 5.8 * u, 16.1 * u, 2.5 * u, 12 * u, 2.5 * u),
      stroke,
      dash: 3 * u,
      gap: 3 * u,
    );
    canvas.drawCircle(Offset(12 * u, 10.5 * u), 3 * u, fill);
  }
}

/// Der gemeinsame Rahmen: 24er-Raster, aktuelle `IconTheme`-Farbe.
///
/// Alles rechnet in relativen Koordinaten auf einem 24er-Raster wie die
/// Material-Symbole daneben — sonst springt die optische Größe zwischen
/// den Knöpfen einer Reihe.
class _Painted extends StatelessWidget {
  const _Painted({required this.size, required this.painter});

  final double size;
  final void Function(Canvas, double, Paint, Paint) painter;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _IconPainter(
          colour: theme.color ?? Theme.of(context).colorScheme.onSurface,
          draw: painter,
        ),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  const _IconPainter({required this.colour, required this.draw});

  final Color colour;
  final void Function(Canvas, double, Paint, Paint) draw;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = colour
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    draw(canvas, size.width / 24, fill, stroke);
  }

  @override
  bool shouldRepaint(_IconPainter oldDelegate) =>
      oldDelegate.colour != colour || oldDelegate.draw != draw;
}

/// Einen Pfad gestrichelt zeichnen.
///
/// Flutter kann das nicht von sich aus — `PathMetric.extractPath` ist
/// der Weg, den auch die Kartenbibliotheken gehen. Die Schleife läuft
/// über ALLE Metriken, nicht nur die erste: Ein Pfad mit mehreren
/// `moveTo` hat mehrere, und die stillschweigend wegzulassen ergäbe ein
/// halbes Symbol.
void _dashed(Canvas canvas, Path path, Paint paint,
    {required double dash, required double gap}) {
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final next = math.min(distance + dash, metric.length);
      canvas.drawPath(metric.extractPath(distance, next), paint);
      distance = next + gap;
    }
  }
}
