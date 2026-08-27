// Das Symbol der Pilztour (#343).
//
// **Warum gezeichnet und nicht aus Material genommen.** Der Betreiber:
// „Der Wanderer sollte einen Pilzkorb in der Hand haben und keinen
// Wanderstock." `Icons.hiking` ist genau der Wanderer mit Stock, und
// Material hat keinen mit Korb — `shopping_basket` wäre ein Korb ohne
// Menschen, und das sagt „einkaufen", nicht „losgehen".
//
// **Die Größe bestimmt den Stil.** Der Knopf zeigt das hier bei 24 dp,
// also gilt dieselbe Regel wie bei den Pilz-Symbolen: klare, fette
// Formen, keine Feinheiten. Alles ist EINE Fläche in der aktuellen
// `IconTheme`-Farbe — damit funktioniert es auf dem grauen Knopf wie auf
// dem grünen der laufenden Tour, ohne zweite Fassung.
import 'package:flutter/material.dart';

/// Ein Wanderer im Schritt, der einen Pilzkorb trägt.
class TourIcon extends StatelessWidget {
  const TourIcon({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _TourIconPainter(
          color: theme.color ?? Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _TourIconPainter extends CustomPainter {
  const _TourIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Alles in relativen Koordinaten auf einem 24er-Raster, wie die
    // Material-Symbole daneben — sonst springt die optische Größe
    // zwischen den Knöpfen der Spalte.
    final u = size.width / 24;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Die Figur steht links, der Korb hängt rechts daneben. Der ERSTE
    // Anlauf hatte beide ineinander: Bei 24 px war der Korb kein Korb
    // mehr, sondern ein Sack am Rumpf. Der Abstand ist deshalb keine
    // Ästhetik, sondern die Lesbarkeit.
    // Kopf.
    canvas.drawCircle(Offset(8.2 * u, 4.0 * u), 2.0 * u, fill);

    // Rumpf, leicht nach vorn geneigt — das ist die halbe Bewegung.
    stroke.strokeWidth = 2.3 * u;
    canvas.drawLine(
        Offset(7.8 * u, 7.0 * u), Offset(9.0 * u, 12.4 * u), stroke);

    // Beine im Schritt: das hintere abgewinkelt, das vordere gestreckt.
    // Zwei parallele Striche sähen aus wie Stehen.
    stroke.strokeWidth = 2.1 * u;
    canvas.drawPath(
      Path()
        ..moveTo(9.0 * u, 12.4 * u)
        ..lineTo(6.2 * u, 15.4 * u)
        ..lineTo(3.4 * u, 20.4 * u)
        ..moveTo(9.0 * u, 12.4 * u)
        ..lineTo(11.0 * u, 16.2 * u)
        ..lineTo(10.4 * u, 20.4 * u),
      stroke,
    );

    // Der freie Arm schwingt nach hinten — ohne ihn wirkt die Figur
    // einarmig, und genau das fällt bei 24 px auf.
    stroke.strokeWidth = 1.8 * u;
    canvas.drawLine(
        Offset(7.9 * u, 8.2 * u), Offset(4.4 * u, 11.0 * u), stroke);

    // Der tragende Arm greift zum Korbrand. Er endet AM Rand, nicht
    // darin: So bleibt der Korb ein eigener Gegenstand.
    canvas.drawLine(
        Offset(8.2 * u, 8.2 * u), Offset(13.6 * u, 12.6 * u), stroke);

    // Zwei Pilzköpfe — sie sitzen GANZ ÜBER der Korbkante, nicht darin.
    // Im ersten Anlauf waren sie hineingezeichnet und in derselben Farbe:
    // Damit waren sie unsichtbar und der Korb bekam nur eine Delle. Als
    // Kuppen auf der Kante geben sie der Silhouette zwei Buckel, und
    // genau die machen aus einem Korb einen PILZkorb.
    canvas.drawCircle(Offset(15.9 * u, 13.4 * u), 1.7 * u, fill);
    canvas.drawCircle(Offset(19.3 * u, 13.8 * u), 1.3 * u, fill);

    // Der Korb: ein sich nach unten verjüngender Trog. Die schrägen
    // Wände unterscheiden ihn vom Eimer.
    canvas.drawPath(
      Path()
        ..moveTo(13.4 * u, 14.2 * u)
        ..lineTo(21.6 * u, 14.2 * u)
        ..lineTo(20.2 * u, 20.4 * u)
        ..lineTo(14.8 * u, 20.4 * u)
        ..close(),
      fill,
    );
  }

  @override
  bool shouldRepaint(_TourIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
