import 'package:flutter/material.dart';

import '../../core/mushroom_species.dart';
import '../../core/widgets/mushroom_icon.dart';
import '../../core/app_colors.dart';

/// Kurze Start-Animation: freundliche Pilze wachsen nacheinander aus dem
/// Boden, dann blendet das Overlay aus. Tippen überspringt sie.
class IntroOverlay extends StatefulWidget {
  const IntroOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<IntroOverlay> createState() => _IntroOverlayState();
}

class _IntroOverlayState extends State<IntroOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  bool _done = false;

  // (Seed, Größe, Gruppe) der wachsenden Pilze — bewusst gemischte Formen
  static const _mushrooms = [
    (3, 58.0, SpeciesGroup.leistlinge),
    (7, 92.0, SpeciesGroup.roehrlinge),
    (11, 68.0, SpeciesGroup.wulstlinge),
    (17, 80.0, SpeciesGroup.taeublinge),
  ];

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _done = true);
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _skip() {
    if (!_done) setState(() => _done = true);
  }

  Animation<double> _growth(int index) => CurvedAnimation(
        parent: _controller,
        curve: Interval(
          0.08 + index * 0.14,
          0.42 + index * 0.14,
          curve: Curves.elasticOut,
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;

    final fadeOut = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.85, 1.0, curve: Curves.easeOut),
    );
    final titleIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.55, curve: Curves.easeOut),
    );

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: GestureDetector(
            onTap: _skip,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Opacity(
                opacity: 1 - fadeOut.value,
                child: Container(
                  color: const Color(0xFFF1F8E9),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < _mushrooms.length; i++)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: ScaleTransition(
                                scale: _growth(i),
                                alignment: Alignment.bottomCenter,
                                child: MushroomIcon(
                                  seed: _mushrooms[i].$1,
                                  size: _mushrooms[i].$2,
                                  group: _mushrooms[i].$3,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      FadeTransition(
                        opacity: titleIn,
                        child: Text(
                          'PilzBuddy',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                color: AppColors.forestGreen,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
