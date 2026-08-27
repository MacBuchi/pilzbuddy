// Die Pilztour im Test (#338): im Speicher statt auf der Platte, und mit
// einer Fix-Quelle, die man selbst steuert.
//
// Ohne diese Fakes ginge JEDER Kartentest an echtes Plattform-IO — der
// Karten-Screen holt beim ersten Frame eine unterbrochene Tour zurück
// (`restore`), und das führt über `getApplicationSupportDirectory` in
// einen Kanal, den es im Widget-Test nicht gibt.
import 'package:pilzbuddy/features/tour/tour_store.dart';
import 'package:pilzbuddy/features/tour/tour_track.dart';

class FakeTourStore implements TourStore {
  String? uid;
  DateTime? startedAt;
  final points = <TourPoint>[];

  /// Lässt [begin] scheitern — der Fall „eine Tour, die gar nicht
  /// aufzeichnen kann, darf nicht starten".
  bool failOnBegin = false;

  int clears = 0;

  @override
  Future<void> begin({
    required String uid,
    required DateTime startedAt,
  }) async {
    if (failOnBegin) throw Exception('kein Platz (Fake)');
    this.uid = uid;
    this.startedAt = startedAt;
    points.clear();
  }

  @override
  Future<void> appendPoint(TourPoint point) async => points.add(point);

  @override
  Future<RecordedTour?> read({required String uid}) async {
    if (startedAt == null || this.uid != uid) return null;
    return (startedAt: startedAt!, points: List.of(points));
  }

  @override
  Future<void> clear() async {
    clears++;
    uid = null;
    startedAt = null;
    points.clear();
  }
}

/// Eine steuerbare Fix-Quelle: Der Test sagt, wo der Nutzer steht.
///
/// Vorgabe ist `null` — „kein Fix" ist im Wald der Normalfall, und ein
/// Test, der eine Position braucht, soll sie ausdrücklich setzen.
class FakeTourFix {
  TourPoint? next;

  /// Wie oft nach einem Fix gefragt wurde — der Takt lässt sich damit
  /// nachweisen, ohne auf Zeit zu warten.
  int calls = 0;

  Future<TourPoint?> call() async {
    calls++;
    return next;
  }
}
