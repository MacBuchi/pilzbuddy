import 'package:flutter/material.dart';

/// Stabiler Hash für Strings über App-Neustarts hinweg (String.hashCode
/// ist dafür nicht garantiert) — bestimmt die Icon-Variante eines Spots.
int stableSeed(String input) {
  var hash = 7;
  for (final unit in input.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash;
}

/// Freundlicher kleiner Pilz in vielen Varianten (Hutform, Farbe, Punkte,
/// Wangen — abgeleitet aus [seed]). Freundes-Pilze bekommen einen blauen
/// Punkt am Hut. Steht mit der Stielbasis auf der Unterkante.
class MushroomIcon extends StatelessWidget {
  const MushroomIcon({
    super.key,
    required this.seed,
    this.size = 44,
    this.friend = false,
  });

  final int seed;
  final double size;
  final bool friend;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _MushroomPainter(seed: seed, friend: friend),
    );
  }
}

class _MushroomPainter extends CustomPainter {
  _MushroomPainter({required this.seed, required this.friend});

  final int seed;
  final bool friend;

  static const _capColors = [
    Color(0xFFE53935), // Rot
    Color(0xFF795548), // Braun
    Color(0xFFEF6C00), // Orange
    Color(0xFFC8A165), // Ocker
    Color(0xFF7E57C2), // Violett
    Color(0xFFEC7086), // Rosa
    Color(0xFF9E9D24), // Oliv
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    double u(double v) => v * w;
    Offset p(double x, double y) => Offset(u(x), u(y));

    final capColor = _capColors[seed % _capColors.length];
    final capShape = (seed ~/ 7) % 3;
    final hasDots = (seed ~/ 21) % 2 == 0;
    final hasCheeks = (seed ~/ 42) % 2 == 0;

    // Stiel
    final stem = RRect.fromLTRBR(
        u(0.36), u(0.42), u(0.64), u(0.96), Radius.circular(u(0.13)));
    final stemPath = Path()..addRRect(stem);

    // Hut
    final cap = Path();
    switch (capShape) {
      case 0: // runde Kuppel
        cap
          ..moveTo(u(0.06), u(0.50))
          ..cubicTo(u(0.06), u(0.10), u(0.94), u(0.10), u(0.94), u(0.50))
          ..quadraticBezierTo(u(0.5), u(0.60), u(0.06), u(0.50))
          ..close();
      case 1: // spitz zulaufend
        cap
          ..moveTo(u(0.10), u(0.52))
          ..quadraticBezierTo(u(0.28), u(0.10), u(0.5), u(0.06))
          ..quadraticBezierTo(u(0.72), u(0.10), u(0.90), u(0.52))
          ..quadraticBezierTo(u(0.5), u(0.62), u(0.10), u(0.52))
          ..close();
      default: // flach und breit
        cap
          ..moveTo(u(0.02), u(0.50))
          ..quadraticBezierTo(u(0.14), u(0.22), u(0.5), u(0.20))
          ..quadraticBezierTo(u(0.86), u(0.22), u(0.98), u(0.50))
          ..quadraticBezierTo(u(0.5), u(0.58), u(0.02), u(0.50))
          ..close();
    }

    // Weißer Halo, damit der Pilz auf jedem Kartenhintergrund lesbar bleibt
    final halo = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = u(0.09)
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(stemPath, halo);
    canvas.drawPath(cap, halo);

    // Füllungen
    canvas.drawPath(stemPath, Paint()..color = const Color(0xFFFFF6E3));
    canvas.drawPath(cap, Paint()..color = capColor);

    // Punkte auf dem Hut (in Hutform geclippt)
    if (hasDots) {
      canvas.save();
      canvas.clipPath(cap);
      final dot = Paint()..color = Colors.white.withValues(alpha: 0.92);
      canvas.drawCircle(p(0.32, 0.28), u(0.055), dot);
      canvas.drawCircle(p(0.58, 0.18), u(0.045), dot);
      canvas.drawCircle(p(0.74, 0.36), u(0.05), dot);
      canvas.drawCircle(p(0.44, 0.42), u(0.035), dot);
      canvas.restore();
    }

    // Konturen
    final outline = Paint()
      ..color = const Color(0xFF4E342E).withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = u(0.025);
    canvas.drawPath(stemPath, outline);
    canvas.drawPath(cap, outline);

    // Gesicht auf dem Stiel — immer freundlich
    final face = Paint()..color = const Color(0xFF3E2723);
    canvas.drawCircle(p(0.44, 0.66), u(0.032), face);
    canvas.drawCircle(p(0.56, 0.66), u(0.032), face);
    final smile = Path()
      ..moveTo(u(0.43), u(0.74))
      ..quadraticBezierTo(u(0.5), u(0.81), u(0.57), u(0.74));
    canvas.drawPath(
        smile,
        Paint()
          ..color = const Color(0xFF3E2723)
          ..style = PaintingStyle.stroke
          ..strokeWidth = u(0.028)
          ..strokeCap = StrokeCap.round);
    if (hasCheeks) {
      final cheek = Paint()..color = const Color(0xFFF8BBD0).withValues(alpha: 0.9);
      canvas.drawCircle(p(0.385, 0.72), u(0.028), cheek);
      canvas.drawCircle(p(0.615, 0.72), u(0.028), cheek);
    }

    // Blauer Freundes-Punkt am Hutrand
    if (friend) {
      canvas.drawCircle(p(0.84, 0.14), u(0.115),
          Paint()..color = Colors.white);
      canvas.drawCircle(p(0.84, 0.14), u(0.085),
          Paint()..color = const Color(0xFF1565C0));
    }
  }

  @override
  bool shouldRepaint(covariant _MushroomPainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.friend != friend;
}
