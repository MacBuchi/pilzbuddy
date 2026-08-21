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

  /// Höhenlinien auf der Karte.
  ///
  /// Ein gedecktes Schiefergrau-Blau, bewusst NICHT braun: Die
  /// Wanderwege im Offline-Stil sind seit 1.97.0 ockerbraun, und zwei
  /// braune Liniensysteme übereinander wären auf einen Blick nicht
  /// auseinanderzuhalten. Kühl gegen die warme Karte, kräftig genug
  /// über Waldgrün und blass genug, um Wege nicht zu verdecken.
  static const contourLine = Color(0xFF5B6B7A);

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

  /// Die Waldtypen-Ebene (#213): drei Töne für Laub → Misch → Nadel.
  ///
  /// Seit #231 NICHT mehr alle grün: Die erste Palette (drei Grüntöne)
  /// war im Feld kaum zu unterscheiden, und unter der Regenfläche
  /// (#232) gar nicht mehr. Gewählt am gerenderten Vergleich
  /// (2026-08-08): Laub als Herbst-Ocker, Misch als Gelbgrün, Nadel als
  /// dunkles Blaugrün — jede Klasse bleibt auch unter Regen-Blau
  /// erkennbar. Bewusst NICHT die [rainRamp]: Ein Ton, der auf der
  /// Regenkarte „30 mm" hieß, darf auf der Waldkarte nicht „Misch"
  /// heißen. Abstand zu [forestGreen] (Besitz-Ellipse der Marker!)
  /// halten Ocker- bzw. Blauanteil.
  static const forestBroadleaf = Color(0xFFD98E32); // Herbst-Ocker
  static const forestMixed = Color(0xFF8AB84E); // Gelbgrün
  static const forestConifer = Color(0xFF173F38); // dunkles Blaugrün

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

  /// Die Kombi-Ebene „Wald + Pilzwetter": je Waldklasse ein Paar
  /// (verhalten, günstig), in der Reihenfolge von `ForestClass` ohne
  /// `none` — Laub, Misch, Nadel.
  ///
  /// **Eine gesetzte Tabelle, keine gerechnete Mischung** (Betreiber,
  /// 2026-08-10: „transparent ist nicht das Beste, weil dann die Farben
  /// alles so wischiwaschi werden"). Bis 1.79.0 ERSETZTE das Leuchten
  /// die Wabenfarbe, die Waldklasse war also genau dort weg, wo man sie
  /// wissen will. Der naheliegende Ausweg — den Ampelton anteilig über
  /// die Wabe legen — ist am gerenderten Vergleich durchgefallen:
  /// Violett und der Laub-Ocker ([forestBroadleaf]) sind fast
  /// Komplementärfarben, unter ~60 % Anteil entsättigt „verhalten" dort
  /// ins Rosé-Graue, über ~80 % fallen die drei Klassen wieder auf
  /// einen Ton zusammen. Zwischen beiden Klippen bleibt kein Fenster,
  /// das auf allen drei Waldfarben trägt.
  ///
  /// Deshalb sechs von Hand gesetzte Töne. Sie tragen ZWEI Achsen, und
  /// die Trennung ist der ganze Trick:
  /// - **Waldklasse = Farbton**, ein Verlauf von Violett (Laub, 275°)
  ///   über 254° nach dunklem Königsblau (Nadel, 228°). Der frühere
  ///   Vorschlag hielt alle drei zwischen 268° und 295° — aus dem
  ///   Augenwinkel war das eine Nuance, keine Unterscheidung
  ///   (Betreiber, 2026-08-10).
  /// - **Wetterstufe = Helligkeit und Dichte**, siehe die Alphas in
  ///   `forest_fill.dart`. Der Farbton bleibt innerhalb einer Spalte
  ///   gleich, sonst würden sich die Achsen gegenseitig überschreiben.
  ///
  /// Zum Kartenwasser (`#80deea`, 188° Cyan) bleiben ~40° und ein
  /// großer Helligkeitsabstand — an genau dieser Nähe war die früher
  /// wählbare Türkis-Familie gescheitert.
  static const ampelCombined = <(Color, Color)>[
    (Color(0xFF9B61DD), Color(0xFF840FD8)), // Laub
    (Color(0xFF6858DD), Color(0xFF5412C0)), // Misch
    (Color(0xFF3C61C5), Color(0xFF0E2093)), // Nadel
  ];

  /// Dieselbe Familie als Punkt und Wort im Spot-Blatt — dort ist keine
  /// Waldklasse bekannt, also vertreten zwei Töne die ganze Skala:
  /// [ampelMild] ihr helles violettes, [ampelStrong] ihr tiefes blaues
  /// Ende. Bewusst mit großem Helligkeitsabstand: Auf weißem Grund
  /// trägt eine Zeile Text keinen Farbton-Unterschied, sondern nur
  /// Kontrast (beide erreichen 3:1 bzw. 11:1).
  static const ampelMild = Color(0xFF8B6FE0);
  static const ampelStrong = Color(0xFF34199B);
}

// **Es gibt keine wählbare Ampel-Farbfamilie mehr** (Betreiber,
// 2026-08-10). 1.73.0 hatte drei zur Wahl gestellt, weil der gerenderte
// Vergleich knapp war; entschieden hat ihn dann das Feld: Türkis lag zu
// nah am Kartenwasser, Violett gewann. Was die Wahl endgültig erledigt
// hat, ist die feste Tabelle in [AppColors.ampelCombined] — sechs
// gesetzte Töne je Familie, dazu ein Verlauf von Violett nach Blau, der
// sich in Magenta nicht sinnvoll nachbauen ließe. Zwölf von Hand
// gepflegte Werte für ein Feature mit einer benutzten Familie wären
// Ballast; der Prefs-Schlüssel `ampel_palette` bleibt darum einfach
// liegen und wird nicht mehr gelesen.
