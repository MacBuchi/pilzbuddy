// Die laufende Pilztour (#338): Takt, Zustand, Foreground-Service.
//
// Der Zustand ist bewusst die AUFGEZEICHNETE Tour selbst (`RecordedTour?`)
// und kein eigenes Statusobjekt: „läuft" heißt genau „es liegt eine Tour
// auf der Platte, die noch nicht abgeschlossen ist". Zwei Wahrheiten —
// eine im Speicher, eine auf der Platte — liefen beim ersten Prozess-Kill
// auseinander, und der Prozess-Kill ist hier der Normalfall (#147).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/errors.dart';
import '../../core/settings.dart';
import '../../data/providers.dart';
import '../offline_maps/download_keep_alive.dart';
import 'tour_store.dart';
import 'tour_track.dart';

/// Woher ein einzelner Fix kommt. Test-Naht: Ohne sie ginge jeder
/// Flow-Test, der eine Tour startet, an echtes Plattform-IO.
typedef TourFix = Future<TourPoint?> Function();

final tourFixProvider = Provider<TourFix>((ref) => _platformFix);

/// Darf aufgezeichnet werden? `null` heißt ja, sonst der Grund.
///
/// Eigene Naht neben [tourFixProvider], weil sie eine andere Frage
/// beantwortet — und weil ein Widget-Test sonst an echten
/// Berechtigungsdialogen hinge, die es dort nicht gibt.
typedef TourPermissionCheck = Future<TourStartResult?> Function();

final tourPermissionProvider =
    Provider<TourPermissionCheck>((ref) => _platformPermission);

Future<TourStartResult?> _platformPermission() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return TourStartResult.noService;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return TourStartResult.noPermission;
    }
    return null;
  } catch (e, stackTrace) {
    logError('Pilztour: Standort prüfen', e, stackTrace);
    return TourStartResult.failed;
  }
}

Future<TourPoint?> _platformFix() async {
  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // Ein Fix, der länger braucht als der Takt, ist für diesen Takt
          // verloren — dann lieber ein Loch in der Reihe als zwei
          // überlappende Anfragen.
          timeLimit: Duration(seconds: 20)),
    );
    return TourPoint(
      lat: position.latitude,
      lng: position.longitude,
      at: position.timestamp.toUtc(),
      accuracyM: position.accuracy,
    );
  } catch (_) {
    // Kein Empfang zum Himmel, Dienst aus, Zeitüberschreitung: ein
    // fehlender Fix ist keine Ausnahme, sondern der Wald.
    return null;
  }
}

final tourStoreProvider = Provider<TourStore>((ref) => FileTourStore());

/// Die wählbaren Takte. Der Betreiber hat 15 s als Vorgabe genannt, mit
/// 5–30 s und 60 s als Spanne (#338).
const kTourIntervals = [5, 15, 30, 60];

/// Der Takt in Sekunden — gerätelokal gemerkt, Muster
/// `rainCourseEnabledProvider`.
final tourIntervalProvider = StateProvider<int>(
    (ref) => ref.watch(settingsProvider).tourIntervalSeconds);

/// Nach dieser Zeit hört eine Tour von selbst auf aufzuzeichnen.
///
/// Der Fall ist nicht theoretisch: Wer das Stoppen vergisst, hätte sonst
/// GPS und Foreground-Service bis zum leeren Akku laufen — und am nächsten
/// Tag eine Tour, die quer durch sein Wohnzimmer führt. Die Tour bleibt
/// danach offen und abschließbar, sie wächst nur nicht weiter.
const kTourMaxDuration = Duration(hours: 12);

/// Was beim Starten herauskam.
enum TourStartResult { started, noPermission, noService, failed }

/// Unter diesem Schlüssel meldet sich die Tour beim Foreground-Service an.
const tourKeepAliveKey = 'pilztour';

class TourNotifier extends Notifier<RecordedTour?> {
  Timer? _timer;

  @override
  RecordedTour? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  bool get isRunning => state != null;

  /// Holt eine unterbrochene Tour zurück und zeichnet weiter auf.
  ///
  /// Aufgerufen beim Kartenstart. Wer im Wald steht und dessen App
  /// zwischendurch weggeräumt wurde, hat die Tour nicht beendet — sie
  /// einfach fallen zu lassen wäre der Fehler, gegen den die Datei da ist.
  Future<void> restore() async {
    if (state != null) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final tour = await ref.read(tourStoreProvider).read(uid: uid);
    if (tour == null) return;
    state = tour;
    if (_withinMaxDuration(tour)) {
      await _startKeepAlive();
      _startTimer();
    }
  }

  Future<TourStartResult> start() async {
    if (state != null) return TourStartResult.started;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return TourStartResult.failed;

    // Erst die Berechtigung, dann die Datei: Eine begonnene Tour, die
    // nie einen Fix bekommt, sähe aus wie eine Aufzeichnung und wäre
    // keine.
    final denial = await ref.read(tourPermissionProvider)();
    if (denial != null) return denial;

    final startedAt = DateTime.now().toUtc();
    try {
      await ref.read(tourStoreProvider).begin(uid: uid, startedAt: startedAt);
    } catch (e, stackTrace) {
      logError('Pilztour beginnen', e, stackTrace);
      return TourStartResult.failed;
    }

    state = (startedAt: startedAt, points: const []);
    await _startKeepAlive();
    _startTimer();
    // Der erste Fix sofort — sonst steht die Karte bis zum ersten Takt
    // leer da und man zweifelt an der Aufnahme.
    unawaited(_tick());
    return TourStartResult.started;
  }

  /// Beendet die Aufzeichnung und gibt zurück, was aufgenommen wurde.
  ///
  /// Die Datei bleibt bewusst liegen: Erst das Abschluss-Blatt entscheidet,
  /// was daraus wird. Wer hier schon löschte, verlöre die Tour, wenn das
  /// Blatt abstürzt oder der Nutzer es wegwischt.
  Future<RecordedTour?> stop() async {
    final tour = state;
    _timer?.cancel();
    _timer = null;
    await ref.read(downloadKeepAliveCoordinatorProvider).stop(tourKeepAliveKey);
    state = null;
    if (tour == null) return null;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return tour;
    // Von der Platte, nicht aus dem Speicher: Wenn der Prozess
    // zwischendurch neu gestartet ist, steht dort mehr.
    return await ref.read(tourStoreProvider).read(uid: uid) ?? tour;
  }

  /// Wirft die abgeschlossene Tour weg — nach dem Buchen oder auf Wunsch.
  Future<void> discard() => ref.read(tourStoreProvider).clear();

  void _startTimer() {
    _timer?.cancel();
    final seconds = ref.read(tourIntervalProvider);
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => _tick());
  }

  Future<void> _startKeepAlive() =>
      ref.read(downloadKeepAliveCoordinatorProvider).start(
            tourKeepAliveKey,
            'Der Weg wird aufgezeichnet',
            title: 'Pilztour läuft',
            // `location` und nicht `dataSync`: Android 14 prüft je Typ,
            // und ohne ihn liefert der Dienst im Hintergrund keine
            // Standorte mehr — also genau dann nicht, wenn das Telefon in
            // der Tasche steckt.
            types: const {KeepAliveType.location},
          );

  bool _withinMaxDuration(RecordedTour tour) =>
      DateTime.now().toUtc().difference(tour.startedAt) < kTourMaxDuration;

  Future<void> _tick() async {
    final tour = state;
    if (tour == null) return;
    if (!_withinMaxDuration(tour)) {
      // Vergessen zu stoppen: Die Aufnahme endet, die Tour bleibt offen.
      _timer?.cancel();
      _timer = null;
      await ref
          .read(downloadKeepAliveCoordinatorProvider)
          .stop(tourKeepAliveKey);
      return;
    }
    final point = await ref.read(tourFixProvider)();
    if (point == null) return;
    // Erst auf die Platte, dann in den Zustand: Der Zustand ist eine
    // Ansicht der Datei, nicht umgekehrt.
    await ref.read(tourStoreProvider).appendPoint(point);
    final current = state;
    if (current == null) return;
    state = (
      startedAt: current.startedAt,
      points: [...current.points, point],
    );
  }
}

final tourProvider =
    NotifierProvider<TourNotifier, RecordedTour?>(TourNotifier.new);
