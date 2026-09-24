import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/mushroom_species.dart';
import '../../core/widgets/mushroom_icon.dart';
import 'feature_highlights.dart';

/// Das Bild zu einem Eintrag (#596): das Symbol der Funktion auf der
/// cremefarbenen Scheibe der Avatare, daneben ein Pilz-Buddy, der sanft
/// schaukelt.
///
/// **Aus Widgets gebaut, nicht aus Screenshots.** Ein Screenshot veraltet
/// mit jeder Änderung an der Oberfläche und zeigt dann einen Knopf, den es
/// so nicht mehr gibt; das Symbol hier IST das auf dem Knopf. Und keine
/// Lottie-Datei — eine neue Abhängigkeit für ein Schaukeln, das
/// `BuddyMushrooms` schon kann.
///
/// Schaukeln nach der Designsprache: um die Stielbasis, ±0,05 rad, 4 s.
/// Mit [animate] = false steht er still — in der Liste „Entdecken" wären
/// zwanzig schaukelnde Pilze Unruhe statt Freundlichkeit.
class HighlightArt extends StatefulWidget {
  const HighlightArt({
    super.key,
    required this.highlight,
    this.size = 120,
    this.animate = true,
  });

  final FeatureHighlight highlight;
  final double size;
  final bool animate;

  @override
  State<HighlightArt> createState() => _HighlightArtState();
}

class _HighlightArtState extends State<HighlightArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final buddy = MushroomIcon(
      seed: stableSeed(widget.highlight.id),
      size: s * 0.42,
      group: _groupFor(widget.highlight.tab),
      ground: false,
    );
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFDF6E3),
              border: Border.all(
                  color: AppColors.warmBrown.withValues(alpha: 0.25),
                  width: s * 0.02),
            ),
            alignment: const Alignment(-0.15, -0.15),
            child: Icon(widget.highlight.icon,
                size: s * 0.42, color: AppColors.forestGreen),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: widget.animate
                ? AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) => Transform.rotate(
                      angle: math.sin(_controller.value * 2 * math.pi) * 0.05,
                      alignment: Alignment.bottomCenter,
                      child: child,
                    ),
                    child: buddy,
                  )
                : buddy,
          ),
        ],
      ),
    );
  }

  /// Ein Pilz je Reiter, damit sich die Gruppen der Seite auch im Bild
  /// unterscheiden. Welcher, ist Geschmack — nur kein Wulstling: Der
  /// rote mit weißen Punkten läse sich neben „Nachrichten" als Warnung.
  static SpeciesGroup _groupFor(HighlightTab tab) => switch (tab) {
        HighlightTab.map => SpeciesGroup.roehrlinge,
        HighlightTab.spots => SpeciesGroup.leistlinge,
        HighlightTab.pilze => SpeciesGroup.stachelpilze,
        HighlightTab.buddys => SpeciesGroup.taeublinge,
        HighlightTab.profile => SpeciesGroup.boviste,
      };
}
