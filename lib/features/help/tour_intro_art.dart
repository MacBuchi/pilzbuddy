// Die Bilder der Tour-Startseiten (#596, Betreiber 2026-09-25: „zu jeder
// Tour eine Startseite … schön liebevoll gestaltet").
//
// **Gezeichnet, nicht als Bild** — aus den Bausteinen, die die App
// ohnehin hat: den Pilz-Buddys (`MushroomIcon`), den Avataren und der
// Designsprache aus `.claude/skills/pilz-designer/`. Screenshots veralteten
// mit jeder Oberflächenänderung, und ein Bild aus einem fremden Stil
// sähe nach Werbung aus statt nach der App.
//
// Jede Szene steht auf derselben Bühne (Cremegrund, eine Wiese unten),
// damit die fünf Startseiten zusammengehören. Bewegt wird nur sanft —
// Schaukeln um die Stielbasis, wie beim Anmelde-Bild —, und nur, solange
// die Startseite nicht `TickerMode` aus hat („Animationen entfernen").
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/mushroom_species.dart';
import '../../core/widgets/buddy_mushrooms.dart';
import '../../core/widgets/mushroom_avatar.dart';
import '../../core/widgets/mushroom_icon.dart';

const _cream = Color(0xFFFDF6E3);
const _meadow = Color(0xFFCFE3C0);
const _meadowDark = Color(0xFFB5D3A2);
const _ink = Color(0xFF4E342E);

/// Die gemeinsame Bühne: abgerundeter Cremegrund mit einer Wiese.
class _Stage extends StatelessWidget {
  const _Stage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 150,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: CustomPaint(
          painter: const _StagePainter(),
          child: child,
        ),
      ),
    );
  }
}

class _StagePainter extends CustomPainter {
  const _StagePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _cream);
    // Zwei weiche Hügel statt einer geraden Kante.
    final back = Path()
      ..moveTo(0, size.height * 0.78)
      ..quadraticBezierTo(size.width * 0.3, size.height * 0.66,
          size.width * 0.62, size.height * 0.76)
      ..quadraticBezierTo(
          size.width * 0.85, size.height * 0.82, size.width, size.height * 0.72)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(back, Paint()..color = _meadowDark);
    final front = Path()
      ..moveTo(0, size.height * 0.86)
      ..quadraticBezierTo(size.width * 0.5, size.height * 0.78, size.width,
          size.height * 0.88)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(front, Paint()..color = _meadow);
  }

  @override
  bool shouldRepaint(_StagePainter old) => false;
}

/// Schaukelt sein Kind sanft um die Unterkante.
class _Sway extends StatefulWidget {
  const _Sway({required this.child, this.phase = 0});

  final Widget child;
  final double phase;
  static const _amount = 0.05;

  @override
  State<_Sway> createState() => _SwayState();
}

class _SwayState extends State<_Sway> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.rotate(
          angle: math.sin(_controller.value * 2 * math.pi + widget.phase) *
              _Sway._amount,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
        child: widget.child,
      );
}

// ─── Die fünf Szenen ────────────────────────────────────────────────

/// Willkommen: die beiden Freunde aus dem App-Icon.
Widget welcomeArt(BuildContext context) => const _Stage(
      child: Align(
        alignment: Alignment(0, 0.62),
        child: BuddyMushrooms(height: 92),
      ),
    );

/// Die Karte: Wege, das Fadenkreuz und drei Spots.
Widget mapArt(BuildContext context) => _Stage(
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _MapPainter())),
          for (final (x, y, seed, group, size) in const [
            (0.16, 0.30, 7, SpeciesGroup.leistlinge, 30.0),
            (0.70, 0.20, 11, SpeciesGroup.roehrlinge, 34.0),
            (0.78, 0.58, 13, SpeciesGroup.wulstlinge, 28.0),
          ])
            Align(
              alignment: Alignment(x * 2 - 1, y * 2 - 1),
              child: _Sway(
                phase: seed.toDouble(),
                child: MushroomIcon(seed: seed, size: size, group: group),
              ),
            ),
        ],
      ),
    );

class _MapPainter extends CustomPainter {
  const _MapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Waldflecken, dann zwei Wege — wie die Karte selbst: erst Fläche,
    // dann Linie.
    final forest = Paint()..color = AppColors.forestMixed.withValues(alpha: 0.28);
    canvas.drawOval(
        Rect.fromLTWH(size.width * 0.05, size.height * 0.1, 90, 50), forest);
    canvas.drawOval(
        Rect.fromLTWH(size.width * 0.58, size.height * 0.05, 80, 60), forest);
    final path = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = AppColors.warmBrown.withValues(alpha: 0.55);
    canvas.drawPath(
        Path()
          ..moveTo(-10, size.height * 0.62)
          ..cubicTo(size.width * 0.3, size.height * 0.40, size.width * 0.5,
              size.height * 0.75, size.width + 10, size.height * 0.35),
        path);
    canvas.drawPath(
        Path()
          ..moveTo(size.width * 0.42, -10)
          ..quadraticBezierTo(size.width * 0.5, size.height * 0.4,
              size.width * 0.38, size.height * 0.9),
        path..strokeWidth = 2);
    // Das Fadenkreuz in der Mitte — dort entsteht ein Spot.
    final c = Offset(size.width * 0.46, size.height * 0.46);
    final cross = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.forestGreen;
    canvas.drawCircle(c, 9, cross);
    for (final d in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
      canvas.drawLine(c + d * 12, c + d * 17, cross);
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => false;
}

/// Spots: eine kleine Liste, daneben ein Buddy.
Widget spotsArt(BuildContext context) => _Stage(
      child: Stack(
        children: [
          Positioned(
            left: 22,
            top: 18,
            child: Column(
              children: [
                for (final (seed, group) in const [
                  (21, SpeciesGroup.roehrlinge),
                  (22, SpeciesGroup.leistlinge),
                  (23, SpeciesGroup.taeublinge),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _ListRow(seed: seed, group: group),
                  ),
              ],
            ),
          ),
          const Positioned(
            right: 20,
            bottom: 18,
            child: _Sway(
              child: MushroomIcon(
                  seed: 42, size: 62, group: SpeciesGroup.roehrlinge),
            ),
          ),
        ],
      ),
    );

class _ListRow extends StatelessWidget {
  const _ListRow({required this.seed, required this.group});

  final int seed;
  final SpeciesGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _ink.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          MushroomIcon(seed: seed, size: 20, group: group, ground: false),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Bar(width: 70, colour: _ink.withValues(alpha: 0.55)),
                const SizedBox(height: 4),
                _Bar(width: 44, colour: _ink.withValues(alpha: 0.22)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.colour});

  final double width;
  static const height = 4.0;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
            color: colour, borderRadius: BorderRadius.circular(height)),
      );
}

/// Pilze: drei Arten, jede mit ihrer kleinen Saisonkurve.
Widget pilzeArt(BuildContext context) => _Stage(
      child: Align(
        alignment: const Alignment(0, 0.35),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, group, curve) in const [
              (0, SpeciesGroup.leistlinge, [1, 2, 5, 8, 9, 7, 3]),
              (1, SpeciesGroup.roehrlinge, [1, 2, 4, 7, 9, 9, 5]),
              (2, SpeciesGroup.wulstlinge, [0, 1, 3, 6, 9, 8, 4]),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Sway(
                      phase: i * 1.7,
                      child: MushroomIcon(
                          seed: 30 + i, size: 48, group: group, ground: false),
                    ),
                    const SizedBox(height: 6),
                    _SeasonMini(curve: curve),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

class _SeasonMini extends StatelessWidget {
  const _SeasonMini({required this.curve});

  final List<int> curve;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, v) in curve.indexed)
            Container(
              width: 5,
              height: 3 + v * 1.6,
              margin: const EdgeInsets.symmetric(horizontal: 0.8),
              decoration: BoxDecoration(
                color: i == 4
                    ? AppColors.forestGreen
                    : AppColors.forestGreen.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      );
}

/// Buddys: zwei Freunde, zwischen ihnen eine Nachricht.
Widget buddysArt(BuildContext context) => const _Stage(
      child: Stack(
        children: [
          Positioned(
            left: 26,
            bottom: 22,
            child: _Sway(child: MushroomAvatar(index: 3, size: 58)),
          ),
          Positioned(
            right: 26,
            bottom: 22,
            child: _Sway(phase: 1.4, child: MushroomAvatar(index: 8, size: 58)),
          ),
          Positioned(
            left: 78,
            top: 20,
            child: CustomPaint(
              painter: _BubblePainter(),
              child: SizedBox(
                width: 84,
                height: 46,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, 10, 12, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Bar(width: 56, colour: Color(0x994E342E)),
                      SizedBox(height: 5),
                      _Bar(width: 36, colour: Color(0x554E342E)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

class _BubblePainter extends CustomPainter {
  const _BubblePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height - 8),
        const Radius.circular(12));
    final path = Path()
      ..addRRect(body)
      ..moveTo(size.width * 0.3, size.height - 9)
      ..lineTo(size.width * 0.22, size.height)
      ..lineTo(size.width * 0.44, size.height - 9)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = AppColors.friendBlue.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(_BubblePainter old) => false;
}
