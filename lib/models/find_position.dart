/// Die eigene Stelle eines Fundes (#373).
///
/// Ohne sie lösen alle Funde eines Spots auf denselben Punkt auf — egal,
/// wie weit die Pilze wirklich auseinanderstanden.
///
/// **Ein Werttyp statt drei loser Felder**, und das ist der ganze Punkt:
/// Die Position reist durch `NewFind`, `withClientId`, den Ausgangskorb,
/// den GPX-Export und die Fakes. Wer sie an einer dieser Stellen beim
/// Kopieren vergisst, vergisst EINE Zeile statt dreier — und die zwei
/// vergessenen von drei Feldern wären der stille Fall.
///
/// **[accuracyM] ist zugleich die Herkunftsangabe.** Gesetzt heißt
/// „gemessen", leer heißt „auf der Karte gewählt": Ein Fadenkreuz hat
/// keinen Messfehler, den man angeben könnte, und eine erfundene Zahl
/// wäre schlimmer als keine. Deshalb die zwei benannten Konstruktoren —
/// dasselbe Muster, mit dem `NewFind.blank` den Constraint
/// `finds_blank_leer` in Dart spiegelt.
class FindPosition {
  final double lat;
  final double lng;

  /// Der Streuradius in Metern, den das Gerät zum Fix gemeldet hat.
  /// `null` bei einer auf der Karte gewählten Stelle.
  final double? accuracyM;

  /// Ein gemessener Fix. Die Genauigkeit ist Pflicht — ein Fix ohne sie
  /// behauptet eine Präzision, die er nicht hat (`nearby_spots.dart`:
  /// GPS liegt unter Blätterdach 10–20 m daneben).
  const FindPosition.gps({
    required this.lat,
    required this.lng,
    required double accuracy,
  })  : assert(accuracy >= 0, 'Ein negativer Radius ist kein Radius.'),
        accuracyM = accuracy;

  /// Eine auf der Karte gewählte Stelle — ohne Messfehler, also ohne Zahl.
  const FindPosition.picked({required this.lat, required this.lng})
      : accuracyM = null;

  /// Gemessen oder gewählt? Die einzige Frage, die die Oberfläche an die
  /// Herkunft stellt: Nur ein gemessener Wert bekommt ein „±".
  bool get measured => accuracyM != null;

  /// Liest die Position aus einer Zeile mit den Schlüsseln `lat`, `lng`
  /// und `accuracy_m` — aus Supabase, dem Zwischenspeicher oder dem Korb.
  ///
  /// Tolerant wie `blank: json['blank'] as bool? ?? false`: Fehlende
  /// Schlüssel heißen „diese Zeile ist älter als Patch 022", nicht
  /// „kaputt". Eine HALBE Koordinate ergibt `null` — das spiegelt den
  /// Constraint `finds_position_paar`, und es ist die harmlose
  /// Fehlerrichtung: lieber keine Position als eine auf dem Nullmeridian.
  static FindPosition? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final lat = (json['lat'] as num?)?.toDouble();
    final lng = (json['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    final accuracy = (json['accuracy_m'] as num?)?.toDouble();
    if (accuracy == null || accuracy < 0) {
      return FindPosition.picked(lat: lat, lng: lng);
    }
    return FindPosition.gps(lat: lat, lng: lng, accuracy: accuracy);
  }

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        if (accuracyM != null) 'accuracy_m': accuracyM,
      };

  @override
  bool operator ==(Object other) =>
      other is FindPosition &&
      other.lat == lat &&
      other.lng == lng &&
      other.accuracyM == accuracyM;

  @override
  int get hashCode => Object.hash(lat, lng, accuracyM);

  @override
  String toString() =>
      'FindPosition($lat, $lng${accuracyM == null ? '' : ', ±$accuracyM m'})';
}
