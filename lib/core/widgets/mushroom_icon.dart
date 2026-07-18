import 'package:flutter/material.dart';

import '../mushroom_species.dart';

/// Stabiler Hash für Strings über App-Neustarts hinweg (String.hashCode
/// ist dafür nicht garantiert) — bestimmt die Icon-Variante eines Spots.
int stableSeed(String input) {
  var hash = 7;
  for (final unit in input.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash;
}

/// Freundlicher kleiner Pilz. Ist eine [group] bekannt, bestimmt sie das
/// Aussehen (Röhrling = braune Kuppel, Pfifferling = gelber Trichter,
/// Wulstling = rot mit Punkten, Bovist = Kugel, Baumpilz = Konsole …) —
/// so erkennt man die Pilzart auf der Karte auf den ersten Blick.
/// Ohne Gruppe sorgt [seed] für bunte Vielfalt. Freundes-Pilze bekommen
/// einen blauen Punkt am Hut.
class MushroomIcon extends StatelessWidget {
  const MushroomIcon({
    super.key,
    required this.seed,
    this.size = 44,
    this.friend = false,
    this.group,
  });

  final int seed;
  final double size;
  final bool friend;
  final SpeciesGroup? group;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _MushroomPainter(seed: seed, friend: friend, group: group),
    );
  }
}

enum _CapShape { dome, cone, flat, funnel, ball, shelf }

class _Style {
  final _CapShape shape;
  final List<Color> capColors;
  final bool whiteDots;
  final bool darkDots; // Morchel-Waben / Schirmling-Schuppen
  final double stemTop; // obere Stielkante (relativ), für hohe Schirmlinge

  const _Style(this.shape, this.capColors,
      {this.whiteDots = false, this.darkDots = false, this.stemTop = 0.42});
}

class _MushroomPainter extends CustomPainter {
  _MushroomPainter({required this.seed, required this.friend, this.group});

  final int seed;
  final bool friend;
  final SpeciesGroup? group;

  static const _fallbackColors = [
    Color(0xFFE53935),
    Color(0xFF795548),
    Color(0xFFEF6C00),
    Color(0xFFC8A165),
    Color(0xFF7E57C2),
    Color(0xFFEC7086),
    Color(0xFF9E9D24),
  ];

  _Style _styleFor(SpeciesGroup? g) {
    switch (g) {
      case SpeciesGroup.roehrlinge:
        return const _Style(_CapShape.dome,
            [Color(0xFF795548), Color(0xFF8D6E63), Color(0xFF5D4037)]);
      case SpeciesGroup.leistlinge:
        return const _Style(_CapShape.funnel,
            [Color(0xFFF9A825), Color(0xFFFBC02D), Color(0xFFF57F17)]);
      case SpeciesGroup.champignons:
        return const _Style(_CapShape.dome,
            [Color(0xFFF0EAD8), Color(0xFFEDE3CE)]);
      case SpeciesGroup.schirmlinge:
        return const _Style(_CapShape.flat,
            [Color(0xFFC8A165), Color(0xFFB78F5C)],
            darkDots: true, stemTop: 0.34);
      case SpeciesGroup.wulstlinge:
        return const _Style(_CapShape.dome,
            [Color(0xFFE53935), Color(0xFFD32F2F), Color(0xFFC62828)],
            whiteDots: true);
      case SpeciesGroup.taeublinge:
        return const _Style(_CapShape.flat, [
          Color(0xFFB53F3F),
          Color(0xFF7E57C2),
          Color(0xFF66A05B),
          Color(0xFFD8A03C),
          Color(0xFFCB6D80),
        ]);
      case SpeciesGroup.morcheln:
        // Hut heller als bei Röhrlingen, damit die Waben-Punkte lesbar sind
        return const _Style(_CapShape.cone,
            [Color(0xFF8D6E63), Color(0xFF7D5F52)],
            darkDots: true);
      case SpeciesGroup.boviste:
        return const _Style(_CapShape.ball, [Color(0xFFF3F1E7)]);
      case SpeciesGroup.baumpilze:
        return const _Style(_CapShape.shelf,
            [Color(0xFFEF6C00), Color(0xFFD18B47), Color(0xFFC77E3D)]);
      case SpeciesGroup.sonstige:
        return const _Style(_CapShape.cone,
            [Color(0xFFBCAAA4), Color(0xFFA1887F), Color(0xFF90A4AE)]);
      case null:
        // Unbekannte/eigene Art: bunte Vielfalt aus dem Seed.
        final shape = _CapShape.values[seed ~/ 7 % 3]; // dome/cone/flat
        return _Style(shape, [_fallbackColors[seed % _fallbackColors.length]],
            whiteDots: (seed ~/ 21) % 2 == 0);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    double u(double v) => v * w;
    Offset p(double x, double y) => Offset(u(x), u(y));

    final style = _styleFor(group);
    final capColor = style.capColors[seed % style.capColors.length];
    final hasCheeks = (seed ~/ 42) % 2 == 0;

    final halo = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = u(0.09)
      ..strokeJoin = StrokeJoin.round;
    final outline = Paint()
      ..color = const Color(0xFF4E342E).withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = u(0.025);

    late final Path stemPath;
    final cap = Path();
    // Gesicht: Position hängt von der Form ab
    var faceY = 0.66;

    switch (style.shape) {
      case _CapShape.dome:
      case _CapShape.cone:
      case _CapShape.flat:
      case _CapShape.funnel:
        stemPath = Path()
          ..addRRect(RRect.fromLTRBR(u(0.36), u(style.stemTop), u(0.64),
              u(0.96), Radius.circular(u(0.13))));
        switch (style.shape) {
          case _CapShape.dome:
            cap
              ..moveTo(u(0.06), u(0.50))
              ..cubicTo(u(0.06), u(0.10), u(0.94), u(0.10), u(0.94), u(0.50))
              ..quadraticBezierTo(u(0.5), u(0.60), u(0.06), u(0.50))
              ..close();
          case _CapShape.cone:
            cap
              ..moveTo(u(0.10), u(0.52))
              ..quadraticBezierTo(u(0.28), u(0.10), u(0.5), u(0.06))
              ..quadraticBezierTo(u(0.72), u(0.10), u(0.90), u(0.52))
              ..quadraticBezierTo(u(0.5), u(0.62), u(0.10), u(0.52))
              ..close();
          case _CapShape.flat:
            cap
              ..moveTo(u(0.02), u(0.46))
              ..quadraticBezierTo(u(0.14), u(0.18), u(0.5), u(0.16))
              ..quadraticBezierTo(u(0.86), u(0.18), u(0.98), u(0.46))
              ..quadraticBezierTo(u(0.5), u(0.54), u(0.02), u(0.46))
              ..close();
          case _CapShape.funnel:
            // Trichter: oben eingedellt, geschwungener Rand (Pfifferling)
            cap
              ..moveTo(u(0.08), u(0.20))
              ..quadraticBezierTo(u(0.5), u(0.40), u(0.92), u(0.20))
              ..quadraticBezierTo(u(0.94), u(0.44), u(0.70), u(0.52))
              ..quadraticBezierTo(u(0.5), u(0.57), u(0.30), u(0.52))
              ..quadraticBezierTo(u(0.06), u(0.44), u(0.08), u(0.20))
              ..close();
          default:
            break;
        }
      case _CapShape.ball:
        // Bovist: große Kugel, Mini-Fuß, Gesicht auf der Kugel
        stemPath = Path()
          ..addRRect(RRect.fromLTRBR(
              u(0.40), u(0.78), u(0.60), u(0.96), Radius.circular(u(0.08))));
        cap.addOval(Rect.fromCircle(center: p(0.5, 0.48), radius: u(0.36)));
        faceY = 0.52;
      case _CapShape.shelf:
        // Baumpilz: Konsole/Fächer an kurzem Sockel, Gesicht auf dem Hut
        stemPath = Path()
          ..addRRect(RRect.fromLTRBR(
              u(0.30), u(0.70), u(0.62), u(0.96), Radius.circular(u(0.10))));
        cap
          ..moveTo(u(0.16), u(0.70))
          ..cubicTo(u(0.10), u(0.22), u(0.96), u(0.16), u(0.94), u(0.52))
          ..quadraticBezierTo(u(0.62), u(0.78), u(0.16), u(0.70))
          ..close();
        faceY = 0.50;
    }

    // Halo → Füllung → Details → Kontur
    canvas.drawPath(stemPath, halo);
    canvas.drawPath(cap, halo);
    canvas.drawPath(stemPath, Paint()..color = const Color(0xFFFFF6E3));
    canvas.drawPath(cap, Paint()..color = capColor);

    if (style.whiteDots) {
      canvas.save();
      canvas.clipPath(cap);
      final dot = Paint()..color = Colors.white.withValues(alpha: 0.92);
      canvas.drawCircle(p(0.32, 0.26), u(0.055), dot);
      canvas.drawCircle(p(0.58, 0.16), u(0.045), dot);
      canvas.drawCircle(p(0.74, 0.34), u(0.05), dot);
      canvas.drawCircle(p(0.44, 0.40), u(0.035), dot);
      canvas.restore();
    }
    if (style.darkDots) {
      canvas.save();
      canvas.clipPath(cap);
      final dot = Paint()
        ..color = const Color(0xFF3E2723).withValues(alpha: 0.55);
      canvas.drawCircle(p(0.34, 0.26), u(0.04), dot);
      canvas.drawCircle(p(0.56, 0.16), u(0.035), dot);
      canvas.drawCircle(p(0.70, 0.32), u(0.04), dot);
      canvas.drawCircle(p(0.46, 0.36), u(0.03), dot);
      canvas.drawCircle(p(0.26, 0.40), u(0.03), dot);
      canvas.restore();
    }

    canvas.drawPath(stemPath, outline);
    canvas.drawPath(cap, outline);

    // Gesicht — immer freundlich
    final faceColor = const Color(0xFF3E2723);
    final face = Paint()..color = faceColor;
    canvas.drawCircle(p(0.44, faceY), u(0.032), face);
    canvas.drawCircle(p(0.56, faceY), u(0.032), face);
    final smile = Path()
      ..moveTo(u(0.43), u(faceY + 0.08))
      ..quadraticBezierTo(
          u(0.5), u(faceY + 0.15), u(0.57), u(faceY + 0.08));
    canvas.drawPath(
        smile,
        Paint()
          ..color = faceColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = u(0.028)
          ..strokeCap = StrokeCap.round);
    if (hasCheeks) {
      final cheek =
          Paint()..color = const Color(0xFFF8BBD0).withValues(alpha: 0.9);
      canvas.drawCircle(p(0.385, faceY + 0.06), u(0.028), cheek);
      canvas.drawCircle(p(0.615, faceY + 0.06), u(0.028), cheek);
    }

    // Blauer Freundes-Punkt am Hutrand
    if (friend) {
      canvas.drawCircle(p(0.84, 0.14), u(0.115), Paint()..color = Colors.white);
      canvas.drawCircle(
          p(0.84, 0.14), u(0.085), Paint()..color = const Color(0xFF1565C0));
    }
  }

  @override
  bool shouldRepaint(covariant _MushroomPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.friend != friend ||
      oldDelegate.group != group;
}
