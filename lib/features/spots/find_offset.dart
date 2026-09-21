import '../../core/geo.dart';
import '../../models/find.dart';
import '../../models/spot.dart';
import '../tour/tour_track.dart' show kTourUsableAccuracyM;
import 'nearby_spots.dart' show kNearbySpotMeters;

/// Wo ein Fund gegenüber seinem Spot liegt (#373) — die Antwort auf
/// „welcher von den dreien war wo".
///
/// Rein: Fund und Spot hinein, Zeile heraus. Kein Riverpod, keine Platte,
/// kein Widget — dieselbe Bauform wie `nearby_spots.dart` und
/// `tour_track.dart`, damit die Regel prüfbar bleibt und nicht in einem
/// `build` steckt.

/// Ab dieser Streuung ist ein Fix zu grob, um etwas zu bedeuten.
///
/// Bewusst DIESELBE Zahl wie die Pilztour und nicht eine zweite mit
/// gleichem Wert: Beide beantworten dieselbe Frage — „taugt dieser Fix
/// als Messung?" —, und zwei Konstanten wären zwei Antworten darauf, die
/// beim nächsten Anfassen auseinanderlaufen.
const kFindUsableAccuracyM = kTourUsableAccuracyM;

/// Bis hierher gilt „ich stehe zweifelsfrei am Spot" ⇒ die eigene
/// Position wird vorbelegt. [kNearbySpotMeters] ist die eine Antwort auf
/// „derselbe Ort" (#215); sie hier zu wiederholen wäre eine zweite.
const kFindFixNearM = kNearbySpotMeters;

/// Bis hierher wird die eigene Position überhaupt noch ANGEBOTEN.
///
/// Nicht [kFindFixNearM]: Ein Fund darf legitim am Rand seines Spots
/// stehen, und gerade dort ist seine Stelle am aussagekräftigsten — ein
/// harter 20-m-Riegel sperrte also genau die Fälle aus, für die es das
/// Feature gibt. Wer dagegen 100 m entfernt steht, trägt gerade nicht
/// dort ein, wo er ist; ein übernommener Fix schriebe den falschen Fleck.
/// Dazwischen ist die Wahl möglich, aber nicht vorbelegt, und die
/// Entfernung steht im Klartext daneben.
const kFindFixMaxOffsetM = 100.0;

/// Der Versatz eines Fundes gegenüber seinem Spot.
typedef FindOffset = ({double meters, double bearing, double? accuracyM});

/// `null`, wenn der Fund keine eigene Stelle hat — der Normalfall.
FindOffset? findOffset(Find find, Spot spot) {
  final position = find.position;
  if (position == null) return null;
  return (
    meters: distanceMeters(spot.lat, spot.lng, position.lat, position.lng),
    bearing: bearingDegrees(spot.lat, spot.lng, position.lat, position.lng),
    accuracyM: position.accuracyM,
  );
}

/// Die Zeile für die Fundliste — `null`, wenn es nichts zu sagen gibt.
///
/// Drei Regeln, und alle drei ziehen in dieselbe Richtung: lieber zu
/// wenig behaupten als zu viel.
///
/// 1. **Ist der Abstand nicht größer als die gemeldete Genauigkeit, gibt
///    es keine Richtung.** Sie wäre Rauschen im Gewand einer Messung —
///    dasselbe Argument, mit dem `tour_track.dart` unscharfe Fixes von
///    der Verweildauer ausschließt. Zwei Funde sehen dann wieder gleich
///    aus, und das ist richtig: innerhalb der Messung SIND sie gleich.
/// 2. **Unter einem Meter heißt „am Spot".** Auf `0 m` gerundet läse sich
///    wie ein Fehler.
/// 3. **Ohne Genauigkeit kein „±".** Eine auf der Karte gewählte Stelle
///    hat keinen Messfehler; die Abwesenheit der Klammer IST die
///    Herkunftsangabe.
String? findPositionLabel(Find find, Spot spot) {
  final offset = findOffset(find, spot);
  if (offset == null) return null;
  final accuracy = offset.accuracyM;
  final suffix = accuracy == null ? '' : ' (±${formatMeters(accuracy)})';
  final vague = accuracy != null && offset.meters <= accuracy;
  if (vague || offset.meters < 1) return 'am Spot$suffix';
  return '${formatMeters(offset.meters)} '
      '${compassPoint(offset.bearing)}$suffix';
}

/// Die Fundstellen, die weiter als [kFindFixMaxOffsetM] vom Spot liegen
/// (#475, Mittelweg) — weiteste zuerst. Dieselbe Zahl wie der Riegel
/// beim Eintragen: „100 m entfernt trägt man nicht dort ein, wo man
/// steht" gilt in beide Richtungen, und eine zweite Grenze wäre eine
/// zweite Antwort auf dieselbe Frage.
///
/// Rein, wie alles hier: gerechnet beim Lesen, nichts gespeichert. Ein
/// Fund OHNE eigene Stelle liegt per Definition am Spot und kann nicht
/// abweichen.
List<Find> driftingFinds(Spot spot) {
  final out = <(double, Find)>[];
  for (final find in spot.finds) {
    final offset = findOffset(find, spot);
    if (offset == null || offset.meters <= kFindFixMaxOffsetM) continue;
    out.add((offset.meters, find));
  }
  out.sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final entry in out) entry.$2];
}

/// Ob der Spot wegen abweichender Fundstellen gewarnt werden muss.
///
/// Bestätigt ist ein ZEITPUNKT am Spot (Patch 024): Die Warnung gilt,
/// solange eine abweichende Fundstelle jünger ist als die Bestätigung —
/// oder ihr Alter unbekannt ist (ein wartender Eintrag hat noch keins;
/// im Zweifel warnen). Ein später eingetragener Fund weit weg bringt
/// die Warnung also zurück; ein bestätigter Zustand bleibt ruhig.
bool spotDriftUnconfirmed(Spot spot) {
  final confirmedAt = spot.offsetConfirmedAt;
  for (final find in driftingFinds(spot)) {
    if (confirmedAt == null) return true;
    final createdAt = find.createdAt;
    if (createdAt == null || createdAt.isAfter(confirmedAt)) return true;
  }
  return false;
}
