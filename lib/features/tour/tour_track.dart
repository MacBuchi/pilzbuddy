// Die Pilztour (#338): der aufgezeichnete Weg — und die Regel, die daraus
// ableitet, welche eigenen Spots wirklich ABGESUCHT wurden.
//
// **Warum es das Feature gibt.** Den Leergang („nichts gefunden") kann die
// App seit 1.58.0 speichern (#211), nur trägt ihn niemand ein: Zwei Taps
// sind zwei Taps, an die man sich ausgerechnet dann erinnern muss, wenn
// man gerade enttäuscht ist. Für die Rückwärtsvalidierung der Pilzampel
// ist das die fehlende Hälfte der Stichprobe (#199) — ein begangener
// leerer Spot ist eine Messung, ein nie besuchter ist keine, und nur ein
// Track kann die beiden auseinanderhalten.
//
// **Deshalb ist die Fehlerrichtung hier vorgegeben.** Ein übersehener
// Leergang kostet eine Zeile; ein ERFUNDENER Leergang vergiftet genau die
// Stichprobe, für die das Ganze da ist. Wo diese Datei zwischen „lieber zu
// wenig" und „lieber zu viel" wählen muss, wählt sie zu wenig — und legt
// die Entscheidung dann dem Nutzer vor, statt sie zu verschweigen.
//
// Alles hier ist rein: Punkte und Spots rein, Bewertung raus. Kein Netz,
// keine Platte, keine Provider.
import '../../core/geo.dart';
import '../../models/spot.dart';
import '../spots/nearby_spots.dart';

/// Ein aufgezeichneter Punkt der Tour.
class TourPoint {
  const TourPoint({
    required this.lat,
    required this.lng,
    required this.at,
    required this.accuracyM,
  });

  final double lat;
  final double lng;
  final DateTime at;

  /// Der Streuradius, den das Gerät zu diesem Fix meldet.
  ///
  /// Mitgeführt und nicht weggeworfen, weil er hier über Wahrheit
  /// entscheidet: `nearby_spots.dart` hält fest, dass GPS unter
  /// Blätterdach 10–20 m danebenliegt — und ein 20-m-Radius, gegen einen
  /// Fix mit ±40 m geprüft, ist Rauschen im Gewand einer Messung.
  final double accuracyM;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'at': at.toUtc().toIso8601String(),
        'acc': accuracyM,
      };

  static TourPoint? fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble();
    final lng = (json['lng'] as num?)?.toDouble();
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (lat == null || lng == null || at == null) return null;
    return TourPoint(
      lat: lat,
      lng: lng,
      at: at.toUtc(),
      // Fehlende Genauigkeit heißt „unbrauchbar für die Verweildauer",
      // nicht „perfekt": Die harmlose Fehlerrichtung ist, den Spot in die
      // verblasste Hälfte zu schieben.
      accuracyM: (json['acc'] as num?)?.toDouble() ?? double.infinity,
    );
  }
}

/// Wie die Tour einen Spot bewertet — die drei Zeilen des Abschluss-Blatts.
enum TourVisitKind {
  /// Im Fangradius UND lang genug: als Leergang vorgeschlagen.
  searched,

  /// Im Fangradius, aber zu kurz — „nur kurz da".
  brief,

  /// Nur im doppelten Radius gestreift — „nur vorbeigegangen".
  passedBy,
}

/// Ein Spot, den die Tour berührt hat, samt Begründung.
///
/// [dwell] und [closestM] stehen mit im Ergebnis, weil das Blatt den GRUND
/// zeigt und nicht nur das Urteil: „nur vorbeigegangen (34 m)" ist eine
/// Entscheidungsgrundlage, ein ausgegrauter Schalter ohne Zahl wäre
/// Raten. Und die Korrekturen des Nutzers sind später das einzige
/// ehrliche Material, um [kTourMinDwell] nachzujustieren.
typedef TourVisit = ({
  Spot spot,
  TourVisitKind kind,
  Duration dwell,
  double closestM,
});

/// Wie lange man an einem Spot gewesen sein muss, damit er als abgesucht
/// gilt.
///
/// 60 s ist ein ANFANGSWERT, kein Messergebnis — er gehört an echten
/// Touren geprüft. Die Zahl ist die einzige unterscheidende Achse
/// zwischen „vorbeigegangen" und „abgesucht": Der Radius sagt, wo man
/// war, die Uhr sagt, ob man hingesehen hat.
const kTourMinDwell = Duration(seconds: 60);

/// Bis zu dieser gemeldeten Streuung zählt ein Fix für die Verweildauer.
///
/// Auch das ein Anfangswert. Er muss über [kNearbySpotMeters] liegen,
/// sonst fiele unter Blätterdach fast jeder Fix heraus — und deutlich
/// darunter bleiben, sonst entschiede er nichts mehr.
const kTourUsableAccuracyM = 30.0;

/// Längere Lücken zählen GAR NICHT als Verweildauer.
///
/// Ohne diese Schranke machte ein Riss in der Aufzeichnung — Prozess
/// eingefroren, GPS verloren, Tunnel — aus zwanzig Minuten Unwissen
/// zwanzig Minuten „gesucht". Die Zeit zwischen zwei weit
/// auseinanderliegenden Punkten ist keine Messung, sondern ihr Fehlen.
const kTourMaxGap = Duration(minutes: 2);

/// Der Faktor auf [kNearbySpotMeters] für das „vorbeigegangen"-Band.
///
/// Bewusst ein FAKTOR und keine zweite Konstante (Betreiber, 2026-08-27):
/// `kNearbySpotMeters` bleibt die eine Antwort auf „derselbe Ort";
/// verschiebt sie sich je, wandert das Band mit. Zwei unabhängige Radien
/// wären zwei Antworten auf dieselbe Frage.
const kTourPassByFactor = 2.0;

/// Welche eigenen Spots die Tour berührt hat — abgesuchte zuerst, danach
/// nach Nähe.
///
/// Nur EIGENE Spots: An einem fremden Spot einen Leergang zu buchen, weil
/// man zufällig dort vorbeikam, wäre eine Aussage über die Fundstelle
/// eines anderen. Dieselbe Regel wie in [nearestOwnSpot].
List<TourVisit> tourVisits(
  List<TourPoint> points,
  List<Spot> spots, {
  double radiusM = kNearbySpotMeters,
  Duration minDwell = kTourMinDwell,
  double usableAccuracyM = kTourUsableAccuracyM,
  Duration maxGap = kTourMaxGap,
}) {
  final own = [
    for (final spot in spots)
      if (spot.isOwn) spot,
  ];
  if (own.isEmpty || points.isEmpty) return const [];
  final passByM = radiusM * kTourPassByFactor;

  final visits = <TourVisit>[];
  for (final spot in own) {
    // Die kürzeste Entfernung zählt über ALLE Punkte, auch die unscharfen.
    // Sonst verschwände ein Spot, an dem jemand unter dichtem Kronendach
    // wirklich gesucht hat, ganz aus dem Blatt — und die Tour ließe
    // ausgerechnet die Messung fallen, für die es sie gibt. Er steht dann
    // verblasst da, mit sichtbarem Grund, einen Tipp vom Eintragen
    // entfernt.
    var closest = double.infinity;
    for (final point in points) {
      final metres =
          distanceMeters(point.lat, point.lng, spot.lat, spot.lng);
      if (metres < closest) closest = metres;
    }
    if (closest > passByM) continue;

    final dwell = _dwellAt(
      points,
      spot,
      radiusM: radiusM,
      usableAccuracyM: usableAccuracyM,
      maxGap: maxGap,
    );
    final kind = closest > radiusM
        ? TourVisitKind.passedBy
        : dwell >= minDwell
            ? TourVisitKind.searched
            : TourVisitKind.brief;
    visits.add(
        (spot: spot, kind: kind, dwell: dwell, closestM: closest));
  }

  visits.sort((a, b) {
    // Abgesuchte zuerst — sie tragen den Vorschlag. Danach das Nähere
    // nach oben: Je dichter man dran war, desto eher hat der Nutzer eine
    // Erinnerung daran.
    final byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) return byKind;
    return a.closestM.compareTo(b.closestM);
  });
  return visits;
}

/// Die zusammengerechnete Zeit im Fangradius.
///
/// Gezählt wird ein Zeitabschnitt nur, wenn **beide** Enden im Radius
/// liegen und **beide** Fixes scharf genug sind. Das zählt an den Rändern
/// eher zu wenig als zu viel — und das ist die Richtung, die diese Datei
/// überall wählt: Ein übersehener Leergang kostet eine Zeile, ein
/// erfundener verdirbt die Stichprobe.
Duration _dwellAt(
  List<TourPoint> points,
  Spot spot, {
  required double radiusM,
  required double usableAccuracyM,
  required Duration maxGap,
}) {
  var total = Duration.zero;
  for (var i = 0; i + 1 < points.length; i++) {
    final a = points[i];
    final b = points[i + 1];
    if (a.accuracyM > usableAccuracyM || b.accuracyM > usableAccuracyM) {
      continue;
    }
    if (distanceMeters(a.lat, a.lng, spot.lat, spot.lng) > radiusM) continue;
    if (distanceMeters(b.lat, b.lng, spot.lat, spot.lng) > radiusM) continue;
    final gap = b.at.difference(a.at);
    // Negative Abstände (Uhr zurückgestellt) sind keine Verweildauer.
    if (gap <= Duration.zero || gap > maxGap) continue;
    total += gap;
  }
  return total;
}
