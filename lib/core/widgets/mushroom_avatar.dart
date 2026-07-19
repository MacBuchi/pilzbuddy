import 'package:flutter/material.dart';

import '../mushroom_species.dart';
import 'mushroom_icon.dart';
import '../app_colors.dart';

/// Ein Avatar-Eintrag: bestimmt Seed (Farbe/Punkte/Wangen) und Gruppe
/// (Hutform) des Pilz-Porträts.
class AvatarSpec {
  final int seed;
  final SpeciesGroup? group;

  const AvatarSpec(this.seed, [this.group]);
}

/// Katalog der wählbaren Pilz-Avatare — quer durch alle Hutformen und
/// Farbpaletten, damit jeder Pilzfreund „seinen" Buddy findet.
/// Reihenfolge nie ändern (der Index ist in den Profilen gespeichert),
/// neue Avatare nur hinten anhängen.
const kAvatarCatalog = <AvatarSpec>[
  AvatarSpec(3, SpeciesGroup.roehrlinge), // brauner Klassiker (Default)
  AvatarSpec(21, SpeciesGroup.wulstlinge), // Fliegenpilz mit Wangen
  AvatarSpec(7, SpeciesGroup.leistlinge), // gelber Trichter
  AvatarSpec(9, SpeciesGroup.boviste), // Kugelrund
  AvatarSpec(5, SpeciesGroup.taeublinge), // bunter Täubling
  AvatarSpec(17, SpeciesGroup.schirmlinge), // hoher Schirmling
  AvatarSpec(11, SpeciesGroup.champignons), // Cremeweißer
  AvatarSpec(13, SpeciesGroup.morcheln), // Wabenkegel
  AvatarSpec(15, SpeciesGroup.baumpilze), // orange Konsole
  AvatarSpec(19, SpeciesGroup.sonstige), // Grauer
  AvatarSpec(24, SpeciesGroup.roehrlinge), // heller Röhrling
  AvatarSpec(42, SpeciesGroup.wulstlinge), // dunkelroter Wulstling
  AvatarSpec(26, SpeciesGroup.taeublinge), // Violetter
  AvatarSpec(47, SpeciesGroup.taeublinge), // Grüner
  AvatarSpec(28, SpeciesGroup.leistlinge), // Orangegelber
  AvatarSpec(30, SpeciesGroup.boviste), // Bovist mit Wangen
  AvatarSpec(1), // bunte Freigeister ohne Gruppe:
  AvatarSpec(2), // ...Formen/Farben rein aus dem Seed
  AvatarSpec(4),
  AvatarSpec(6),
  AvatarSpec(8),
  AvatarSpec(10),
  AvatarSpec(12),
  AvatarSpec(16),
];

/// Liefert den Katalog-Eintrag zu einem gespeicherten Index — robust
/// gegen Werte außerhalb des Katalogs (ältere/neuere App-Versionen).
AvatarSpec avatarSpec(int index) =>
    kAvatarCatalog[index >= 0 && index < kAvatarCatalog.length ? index : 0];

/// Rundes Pilz-Porträt: Buddy auf warmem Cremegrund mit zarter Kontur.
/// Ohne Boden-Ellipse — die ist auf der Karte die Besitz-Kennzeichnung.
class MushroomAvatar extends StatelessWidget {
  const MushroomAvatar({super.key, required this.index, this.size = 40});

  final int index;
  final double size;

  @override
  Widget build(BuildContext context) {
    final spec = avatarSpec(index);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.creamPortrait,
        border: Border.all(
          color: AppColors.barkBrown.withValues(alpha: 0.25),
          width: size * 0.03,
        ),
      ),
      padding: EdgeInsets.all(size * 0.10),
      child: MushroomIcon(
        seed: spec.seed,
        group: spec.group,
        size: size * 0.8,
        ground: false,
      ),
    );
  }
}
