// Liegt eine Stelle in Südtirol? (#623 Teil B, Zwischenlösung)
//
// Für Südtirol gibt es noch keine Schutzgebietsdaten — die Provinz ist
// gefragt, welche Kategorien das Sammeln verbieten, und die Regel wird
// nicht geraten. Bis dahin sagt der Hinweis beim Eintragen dort nur, WAS
// fehlt: dass eigene Sammelregeln gelten und Schutzgebiete nicht erfasst
// sind (Betreiber, 2026-10-09). Sonst läse sich das Schweigen wie
// „Sammeln erlaubt" — genau die Richtung, die #580 vermeiden will.
//
// Der Umriss ist die Grenze der Provinz Bozen aus OpenStreetMap
// (Relation 47046, ODbL — die Nennung steht auf der Lizenzseite unter
// OpenStreetMap), vereinfacht auf ~1 km (Nominatim,
// `polygon_threshold=0.01`, 117 Punkte). Am Rand kann der Satz also
// einen Kilometer zu früh oder zu spät kommen; er sagt nichts über ein
// Gebiet, nur über das Land, und ist deshalb dort unschädlich.

/// (Breite, Länge) der Provinzgrenze, ein geschlossener Ring ohne
/// Wiederholung des ersten Punkts.
const kSouthTyrolOutline = <(double, double)>[
  (46.684, 10.382),
  (46.637, 10.402),
  (46.641, 10.446),
  (46.615, 10.492),
  (46.544, 10.472),
  (46.531, 10.453),
  (46.508, 10.457),
  (46.492, 10.550),
  (46.444, 10.634),
  (46.461, 10.717),
  (46.487, 10.759),
  (46.443, 10.801),
  (46.444, 10.912),
  (46.484, 10.979),
  (46.441, 11.073),
  (46.489, 11.061),
  (46.514, 11.034),
  (46.531, 11.083),
  (46.502, 11.089),
  (46.482, 11.130),
  (46.504, 11.197),
  (46.462, 11.220),
  (46.427, 11.205),
  (46.397, 11.215),
  (46.359, 11.191),
  (46.342, 11.203),
  (46.303, 11.178),
  (46.283, 11.139),
  (46.256, 11.202),
  (46.238, 11.172),
  (46.220, 11.206),
  (46.259, 11.306),
  (46.283, 11.312),
  (46.299, 11.338),
  (46.265, 11.358),
  (46.265, 11.398),
  (46.300, 11.360),
  (46.335, 11.454),
  (46.364, 11.477),
  (46.345, 11.551),
  (46.381, 11.564),
  (46.390, 11.602),
  (46.471, 11.625),
  (46.483, 11.650),
  (46.502, 11.639),
  (46.506, 11.761),
  (46.533, 11.813),
  (46.509, 11.828),
  (46.545, 11.965),
  (46.533, 11.998),
  (46.584, 12.047),
  (46.608, 12.045),
  (46.643, 12.075),
  (46.675, 12.070),
  (46.622, 12.194),
  (46.594, 12.192),
  (46.630, 12.261),
  (46.617, 12.284),
  (46.633, 12.338),
  (46.623, 12.385),
  (46.643, 12.380),
  (46.680, 12.478),
  (46.716, 12.384),
  (46.775, 12.357),
  (46.783, 12.284),
  (46.815, 12.283),
  (46.841, 12.307),
  (46.884, 12.274),
  (46.891, 12.242),
  (46.874, 12.215),
  (46.906, 12.190),
  (46.914, 12.144),
  (46.937, 12.169),
  (46.962, 12.132),
  (46.982, 12.138),
  (47.007, 12.121),
  (47.025, 12.147),
  (47.027, 12.205),
  (47.059, 12.217),
  (47.069, 12.241),
  (47.092, 12.186),
  (47.033, 11.917),
  (46.969, 11.747),
  (46.993, 11.711),
  (46.992, 11.665),
  (47.013, 11.627),
  (46.984, 11.539),
  (47.011, 11.479),
  (46.965, 11.406),
  (46.991, 11.359),
  (46.992, 11.320),
  (46.962, 11.207),
  (46.966, 11.164),
  (46.940, 11.164),
  (46.931, 11.115),
  (46.912, 11.096),
  (46.890, 11.102),
  (46.853, 11.071),
  (46.822, 11.083),
  (46.805, 11.039),
  (46.765, 11.022),
  (46.775, 10.923),
  (46.763, 10.883),
  (46.782, 10.841),
  (46.775, 10.814),
  (46.796, 10.786),
  (46.788, 10.730),
  (46.823, 10.764),
  (46.875, 10.667),
  (46.837, 10.546),
  (46.849, 10.555),
  (46.859, 10.479),
  (46.804, 10.451),
  (46.788, 10.423),
  (46.753, 10.442),
  (46.734, 10.401),
  (46.709, 10.416),
];

/// Gerade-ungerade-Regel über [kSouthTyrolOutline]; vorab ein Rahmen,
/// damit die 117 Kanten nur für Stellen in der Nähe gerechnet werden.
bool inSouthTyrol(double lat, double lon) {
  if (lat < 46.2 || lat > 47.1 || lon < 10.3 || lon > 12.5) return false;
  var inside = false;
  final n = kSouthTyrolOutline.length;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    final (yi, xi) = kSouthTyrolOutline[i];
    final (yj, xj) = kSouthTyrolOutline[j];
    if ((yi > lat) != (yj > lat) &&
        lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}
