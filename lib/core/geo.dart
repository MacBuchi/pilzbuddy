import 'dart:math' as math;

/// Entfernung in Kilometern, eben gerechnet.
///
/// Reicht für beide Aufrufer: Über die paar Dutzend Kilometer bis zur
/// nächsten Wetterstation liegt der Fehler gegenüber der Kugelformel weit
/// unter einem Prozent — und auf den 20 m zwischen zwei Spots (#215) ist
/// die Erdkrümmung ohnehin kein Thema. Der `cos`-Faktor auf die Länge ist
/// der Teil, der wirklich zählt; ohne ihn läge man in Deutschland um rund
/// ein Drittel daneben.
double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  const kmPerDegree = 111.2;
  final dy = (lat1 - lat2) * kmPerDegree;
  final dx = (lon1 - lon2) *
      kmPerDegree *
      math.cos((lat1 + lat2) / 2 * math.pi / 180);
  return math.sqrt(dx * dx + dy * dy);
}

/// Dieselbe Rechnung in Metern — der Maßstab, in dem Spots verglichen
/// werden (#215).
double distanceMeters(double lat1, double lon1, double lat2, double lon2) =>
    distanceKm(lat1, lon1, lat2, lon2) * 1000;
