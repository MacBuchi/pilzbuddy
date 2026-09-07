import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_colors.dart';
import 'mushroom_avatar.dart';

/// Ein Standort-Marker in Tropfenform: der Avatar im Kopf, die Spitze auf
/// der Koordinate (#403).
///
/// **Warum eine Spitze.** Bis 1.119.1 war der Live-Standort ein Kreis,
/// der MITTIG über seiner Koordinate hing. Ein 44-px-Kreis deckt bei
/// gewöhnlichem Zoom gut fünfzig Meter ab — man sah, dass jemand „da
/// ungefähr" ist, nicht wo. Die Spot-Marker machen es längst richtig
/// (`alignment: Alignment.topCenter`, der Pilz steht auf seiner Stelle);
/// die beiden Standort-Marker waren die einzigen, die schwebten.
///
/// **Warum die Farbe im Körper und nicht im Ring.** Grün = meins, Blau =
/// Buddy ist die Sprache der Boden-Ellipse an den Spots. Als 2,5-px-Ring
/// um ein Pilz-Porträt herum war sie zu leise: Zwei Nutzer mit ähnlichem
/// Avatar sahen gleich aus. Der eingefärbte Tropfen trägt dieselbe
/// Aussage über die ganze Fläche.
///
/// **Der weiße Halo ist Pflicht**, nicht Zierde — ohne ihn verschwindet
/// ein grüner Tropfen im Wald und ein blauer im Wasser (Design-Sprache:
/// „White halo + soft outline").
class LocationPin extends StatelessWidget {
  const LocationPin({
    super.key,
    required this.avatar,
    required this.color,
    this.headSize = 38,
  });

  /// Index in `kAvatarCatalog`.
  final int avatar;

  /// Die Besitz-Farbe: [AppColors.forestGreen] für den eigenen Standort,
  /// [AppColors.friendBlue] für einen Buddy.
  final Color color;

  /// Durchmesser des Kopfes. Die Gesamthöhe folgt daraus über
  /// [pinHeightFactor].
  final double headSize;

  /// Wie viel höher als breit ein Tropfen ist. Die Spitze braucht Platz,
  /// und aus diesem Faktor folgt die Höhe des Markers auf der Karte —
  /// beide Seiten müssen dieselbe Zahl benutzen, sonst sitzt die Spitze
  /// nicht auf der Koordinate.
  static const double pinHeightFactor = 1.32;

  @override
  Widget build(BuildContext context) {
    final height = headSize * pinHeightFactor;
    return SizedBox(
      width: headSize,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _PinPainter(color)),
          ),
          // Der Avatar sitzt im Kopf, nicht in der Mitte des Markers:
          // Der Rest ist Spitze.
          Positioned(
            left: headSize * 0.11,
            top: headSize * 0.11,
            child: MushroomAvatar(index: avatar, size: headSize * 0.78),
          ),
        ],
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  const _PinPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _pinPath(size);

    // Halo zuerst, damit er hinter der Füllung liegt.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.09
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.025
        ..color = AppColors.barkBrown.withValues(alpha: 0.75),
    );
  }

  /// Kopf plus die beiden Tangenten zur Spitze.
  ///
  /// Die Tangenten statt zweier gerader Linien vom Kreisrand: Nur so geht
  /// der Kopf ohne Knick in die Spitze über. Der Winkel folgt aus dem
  /// Abstand — `cos β = r / d` — und `arcTo` zeichnet den GROSSEN Bogen
  /// (oben herum), weil der kleine innerhalb der Spitze läge.
  static Path _pinPath(Size size) {
    final r = size.width / 2;
    final center = Offset(size.width / 2, r);
    final tip = Offset(size.width / 2, size.height);
    final d = tip.dy - center.dy;
    // Bei zu flachem Marker gibt es keine Tangente — dann bleibt der
    // Kreis. Kann nur eintreten, wenn jemand pinHeightFactor unter 1
    // setzt; ein Kreis ist dort die harmlose Antwort.
    if (d <= r) {
      return Path()..addOval(Rect.fromCircle(center: center, radius: r));
    }
    final beta = math.acos(r / d);
    return Path()
      ..moveTo(tip.dx, tip.dy)
      ..arcTo(Rect.fromCircle(center: center, radius: r),
          math.pi / 2 + beta, 2 * math.pi - 2 * beta, false)
      ..close();
  }

  @override
  bool shouldRepaint(_PinPainter oldDelegate) => oldDelegate.color != color;
}
