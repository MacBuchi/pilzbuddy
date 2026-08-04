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

  /// Die Höhenlinien der Regensummen, von trocken nach nass.
  ///
  /// **Warum eine eigene Rampe:** Die des DWD (weiß → blau → grün → gelb
  /// → rot → violett) ist eine meteorologische Konvention für
  /// Regen*intensität*. Auf einer Pilzkarte geht es um Bodenfeuchte, und
  /// dort liest sich sandig → grün → blau als „trocken → nass", ohne dass
  /// Rot Alarm suggeriert, wo viel Regen genau das Gute ist.
  ///
  /// Verankert an den beiden Tönen, die die App ohnehin führt:
  /// [forestGreen] in der Mitte, [friendBlue] weit oben. Die Reihenfolge
  /// ist die Rampe — Stufe i bekommt Farbe i, [rainLine] deckelt.
  ///
  /// Bewusst keine Wertung: Keine Stufe ist rot, keine grün-als-Ampel.
  /// Das Regenband ist eine Messwertebene.
  static const rainRamp = <Color>[
    Color(0xFFC8A165), // sandig
    Color(0xFFA8A05C),
    Color(0xFF86A055),
    Color(0xFF5E9A4E),
    forestGreen, // die Marke in der Mitte
    Color(0xFF1E8A7A), // Türkis
    friendBlue,
    Color(0xFF303F9F), // tiefes Indigo
  ];

  /// Die Farbe der i-ten Höhenlinie. Mehr Stufen als Farben werden am
  /// oberen Ende gedeckelt statt umzulaufen — eine Rampe, die von vorn
  /// beginnt, hieße „viel Regen sieht aus wie wenig".
  static Color rainLine(int index) =>
      rainRamp[index.clamp(0, rainRamp.length - 1)];

  /// Die Temperaturlinien im Wetterdiagramm am Spot. Boden ist der
  /// erdige Marken-Braunton und die pilz-relevante Hauptlinie; die
  /// Luftwerte bekommen einen warmen und einen kühlen Ton, der sich von
  /// den [friendBlue]-Regenbalken darunter absetzt.
  static const tempSoil = warmBrown;
  static const tempAirMax = Color(0xFFD84315);
  static const tempAirMin = Color(0xFF00838F);

  /// Fläche unter der Karte, solange dort noch keine Kachel liegt.
  ///
  /// Derselbe Landton wie die `earth`-Ebene des Offline-Styles
  /// (`assets/map_style/protomaps_light_de.json`) — eine wartende Fläche
  /// soll nach Karte aussehen, nicht nach Fehler. Ändert sich der Style,
  /// gehört dieser Wert nachgezogen.
  static const mapBackground = Color(0xFFE2DFDA);
}
