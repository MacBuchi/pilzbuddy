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
  Widget build(BuildContext context) {
    final big = widget.height;
    final small = widget.height * 0.62;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 * math.pi;
        // Sanftes Schaukeln um die Stielbasis, leicht phasenversetzt —
        // wie zwei Freunde, die nebeneinander im Wind stehen.
        final swayBig = math.sin(t) * 0.045;
        final swaySmall = math.sin(t + 1.3) * 0.06;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Transform.rotate(
              angle: swayBig,
              alignment: Alignment.bottomCenter,
              child: MushroomIcon(
                  seed: 42, size: big, group: SpeciesGroup.roehrlinge),
            ),
            const SizedBox(width: 4),
            Transform.rotate(
              angle: swaySmall,
              alignment: Alignment.bottomCenter,
              child: MushroomIcon(
                  seed: 43, size: small, group: SpeciesGroup.wulstlinge),
            ),
          ],
        );
      },
    );
  }
}
