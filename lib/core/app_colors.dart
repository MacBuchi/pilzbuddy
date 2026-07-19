import 'package:flutter/material.dart';

/// Design-Tokens der PilzBuddy-Palette — DIE eine Quelle für die im
/// Design-Regelwerk (.claude/skills/pilz-designer/SKILL.md) definierten
/// Farben. Gruppen-/Arten-Paletten der Pilz-Icons bleiben bewusst als
/// Artwork-Daten in mushroom_icon.dart — hier stehen nur die überall
/// wiederkehrenden Marken-Töne.
abstract final class AppColors {
  /// Primärgrün: eigene Spots, Theme-Seed, Akzente.
  static const forestGreen = Color(0xFF2E7D32);

  /// Blau für Freundes-Spots (Boden-Ellipse, Anfragen-Banner).
  static const friendBlue = Color(0xFF1565C0);

  /// Weiche Kontur der Pilz-Silhouetten.
  static const barkBrown = Color(0xFF4E342E);

  /// Gesichter, Morchel-Waben, Schirmling-Schuppen.
  static const faceBrown = Color(0xFF3E2723);

  /// Warmes Braun: Feedback-Banner-Text, Karten-Update-Banner.
  static const warmBrown = Color(0xFF6D4C41);

  /// Pilz-Stiele.
  static const cream = Color(0xFFFFF6E3);

  /// Avatar-Porträt-Hintergrund.
  static const creamPortrait = Color(0xFFFDF6E3);

  /// Rosa Wangen der Buddies.
  static const cheekPink = Color(0xFFF8BBD0);

  /// Heller Feedback-Banner-Hintergrund.
  static const sunshine = Color(0xFFFFF8E1);
}
