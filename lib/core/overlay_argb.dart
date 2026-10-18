// Die Farben der Kartenflächen als ARGB-Zahlen — ohne Flutter.
//
// Gemalt werden Wald, Ampel und Fundorte im Browser künftig in einem Web
// Worker (#689, B2), der ohne Flutter übersetzt wird; dort gibt es kein
// `Color`. Diese Datei ist darum die eine Quelle der Werte, und
// `AppColors` baut seine `Color`s daraus. Begründungen für jeden Ton
// stehen weiter bei `AppColors`.

/// Die Flächenfarben als `0xAARRGGBB`.
abstract final class OverlayArgb {
  static const forestBroadleaf = 0xFFD98E32; // Herbst-Ocker
  static const forestMixed = 0xFF8AB84E; // Gelbgrün
  static const forestConifer = 0xFF173F38; // dunkles Blaugrün

  /// Wald + Pilzwetter: je Waldklasse (Laub, Misch, Nadel) ein Paar
  /// (verhalten, günstig) — siehe `AppColors.ampelCombined`.
  static const ampelCombined = <(int, int)>[
    (0xFF9B61DD, 0xFF840FD8), // Laub
    (0xFF6858DD, 0xFF5412C0), // Misch
    (0xFF3C61C5, 0xFF0E2093), // Nadel
  ];

  /// Die Scheiben der GBIF-Fundorte je Ampel-Klasse — siehe
  /// `AppColors.gbifClassColours`.
  static const gbifClassColours = <String, int>{
    'herbst': 0xFFC62828, // Steinpilz & Co. — Rot
    'sommer': 0xFFF9A825, // Pfifferling — Gelb
    'holz_winter': 0xFF1E88E5, // Austernseitling & Co. — Blau
    'cantharellales': 0xFF00897B, // Herbsttrompete & Co. — Türkis
  };

  /// Arten ohne Ampel-Klasse.
  static const gbifNoClass = 0xFF616161;

  /// Die Fundorte-Farbe einer Ampel-Klasse, grau ohne Klasse.
  static int gbifClassColour(String? classKey) => classKey == null
      ? gbifNoClass
      : gbifClassColours[classKey] ?? gbifNoClass;
}

/// Rot, Grün, Blau eines ARGB-Werts als Bytes.
int argbRed(int argb) => (argb >> 16) & 0xFF;
int argbGreen(int argb) => (argb >> 8) & 0xFF;
int argbBlue(int argb) => argb & 0xFF;
