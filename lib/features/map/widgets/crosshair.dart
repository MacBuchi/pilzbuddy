import 'package:flutter/material.dart';

import '../../../core/app_colors.dart';

/// Das dezente Fadenkreuz: Ring, vier Haarlinien, grün mit weißem Halo.
///
/// Bis 1.113.0 privat in `map_screen.dart`. Öffentlich, seit es an zwei
/// Stellen steht — in der Kartenmitte („Neuer Spot" speichert genau dort)
/// und in der Mini-Karte des Fund-Blatts (#373). Eine zweite,
/// abgezeichnete Fassung wären zwei Symbole für dieselbe Bedeutung, und
/// die liefen beim nächsten Anfassen auseinander.
///
/// Der Halo ist kein Schmuck: Ohne ihn verschwindet die grüne Linie auf
/// einer Wald- oder Wiesenkachel.
class Crosshair extends StatelessWidget {
  const Crosshair({super.key, this.size = 34});

  /// Kantenlänge in logischen Pixeln. Alles darin skaliert mit — in einem
  /// 180 dp hohen Kasten verdeckte die volle Größe zu viel vom Ausschnitt.
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: CrosshairPainter(scale: size / 34),
    );
  }
}

class CrosshairPainter extends CustomPainter {
  const CrosshairPainter({this.scale = 1});

  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final halo = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5 * scale
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = AppColors.forestGreen.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * scale
      ..strokeCap = StrokeCap.round;

    final radius = 9.0 * scale;
    final arm = 6.0 * scale;
    final gap = 1.5 * scale;

    for (final paint in [halo, line]) {
      canvas.drawCircle(center, radius, paint);
      canvas.drawLine(center - Offset(0, radius + arm),
          center - Offset(0, radius + gap), paint);
      canvas.drawLine(center + Offset(0, radius + gap),
          center + Offset(0, radius + arm), paint);
      canvas.drawLine(center - Offset(radius + arm, 0),
          center - Offset(radius + gap, 0), paint);
      canvas.drawLine(center + Offset(radius + gap, 0),
          center + Offset(radius + arm, 0), paint);
    }
    canvas.drawCircle(center, 1.8 * scale, Paint()..color = Colors.white);
    canvas.drawCircle(
        center, 1.1 * scale, Paint()..color = AppColors.forestGreen);
  }

  @override
  bool shouldRepaint(covariant CrosshairPainter oldDelegate) =>
      oldDelegate.scale != scale;
}
