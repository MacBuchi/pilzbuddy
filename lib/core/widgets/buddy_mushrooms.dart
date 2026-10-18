import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../mushroom_species.dart';
import 'mushroom_icon.dart';

/// Die zwei befreundeten Pilze aus dem App-Icon (großer Röhrling +
/// kleiner Fliegenpilz), die sanft im Wind schaukeln — für die
/// Anmelde-/Registrierungsseite.
class BuddyMushrooms extends StatefulWidget {
  const BuddyMushrooms({super.key, this.height = 120});

  final double height;

  @override
  State<BuddyMushrooms> createState() => _BuddyMushroomsState();
}

class _BuddyMushroomsState extends State<BuddyMushrooms>
    with SingleTickerProviderStateMixin {
  /// Ein Schwung von 2 s, dann stehen die Pilze still (#689, B3) — so
  /// lange sieht man sie: Die Seiten mit den Pilzen sind nach etwa zwei
  /// Sekunden „durch“ (Betreiber, 2026-10-18).
  /// Endlos geschaukelt hielt die Anmeldeseite den Hauptthread im Web zu
  /// 62–67 % belegt (Pixel XL), ruhend zu 1 % — und Flutter rastert dort
  /// jedes Bild neu, eine Neuzeichen-Grenze allein hilft kaum.
  static const swings = 1;
  static const swingDuration = Duration(seconds: 2);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: swingDuration * swings,
  )..forward();

  /// Antippen weckt die Pilze für eine neue Runde.
  void _wake() {
    if (!_controller.isAnimating) _controller.forward(from: 0);
  }

  /// Wie weit die Pilze bei Fortschritt [v] (0…1) ausschlagen dürfen:
  /// ein Viertelschwung zum Anlaufen, im letzten Schwung sanft auslaufend
  /// bis senkrecht — sonst stünde der kleine Pilz schief still (er
  /// schaukelt phasenversetzt).
  static double _amplitude(double v) {
    final s = v * swings;
    final rise = s < 0.25 ? math.sin(s / 0.25 * math.pi / 2) : 1.0;
    final fall =
        s < swings - 1 ? 1.0 : 0.5 * (1 + math.cos(math.pi * (s - swings + 1)));
    return rise * fall;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final big = widget.height;
    final small = widget.height * 0.62;

    // Zwei Grenzen, damit das Schaukeln billig bleibt (#689, B3): Die
    // äußere hält die Seite (Anmeldeformular, Update-Text) aus dem
    // Neuzeichnen heraus, die inneren halten das fertige Pilzbild fest —
    // je Bild ändert sich nur noch der Drehwinkel. Vorher zeichnete jeder
    // Takt beide Pilze samt Seite neu; im Web hielt das den Hauptthread
    // zu ~60 % beschäftigt, ein Tipp auf der Anmeldeseite wartete 72–96 ms.
    return GestureDetector(
      onTap: _wake,
      child: RepaintBoundary(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Sanftes Schaukeln um die Stielbasis, leicht phasenversetzt —
          // wie zwei Freunde, die nebeneinander im Wind stehen.
          _sway(
            amount: 0.045,
            phase: 0,
            child: MushroomIcon(
                seed: 42, size: big, group: SpeciesGroup.roehrlinge),
          ),
          const SizedBox(width: 4),
          _sway(
            amount: 0.06,
            phase: 1.3,
            child: MushroomIcon(
                seed: 43, size: small, group: SpeciesGroup.wulstlinge),
          ),
        ],
      ),
      ),
    );
  }

  Widget _sway(
          {required double amount,
          required double phase,
          required Widget child}) =>
      AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.rotate(
          angle: math.sin(_controller.value * swings * 2 * math.pi + phase) *
              amount *
              _amplitude(_controller.value),
          alignment: Alignment.bottomCenter,
          child: child,
        ),
        child: RepaintBoundary(child: child),
      );
}
