import 'package:pilzbuddy/core/settings.dart';

/// Einstellungen im Speicher. Ein echter SharedPreferences-Kanal existiert
/// im Widget-Test nicht; ein Test, der den Neustart nachstellt, gibt die
/// Instanz einfach an den zweiten `pumpApp`-Aufruf weiter.
class FakeSettings implements Settings {
  FakeSettings({
    this.offlineMapEnabled = false,
    this.mapLegendOpen = true,
    this.rainCourseEnabled = false,
    this.prereleaseUpdatesEnabled = false,
    this.forestFineEnabled = false,
    this.mapAutoUpdateEnabled = false,
    this.ampelPreviewEnabled = false,
    this.ampelBannerEnabled = false,
    this.forestLayerEnabled = false,
    this.contourLayerEnabled = false,
    this.gbifLayerEnabled = false,
    this.ampelLayerEnabled = false,
    this.rainLayerName,
    // **Vorgabe hier TRUE, in der App false.** Sonst bekäme jeder
    // Bestandstest ungefragt die Karten-Tour über den Schirm gelegt —
    // dieselbe Begründung wie bei `lastFindSeenAt` gleich darunter. Wer
    // die Tour prüfen will, gibt `mapTourSeen: false` mit.
    this.mapTourSeen = true,
    // Der Merker von vor 1.208.0 — nur für die Rückblick-Erkennung.
    this.legacyMapTourSeen = false,
    // Wie mapTourSeen auf `true`: Sonst bekäme jeder Bestandstest den
    // Haftungshinweis übergestülpt. Wer ihn prüfen will, gibt
    // `safetyNoteSeen: false` mit.
    this.safetyNoteSeen = true,
    this.tourTrackAsLine = false,
    this.tourIntervalSeconds = kTourIntervalDefaultSeconds,
    // Bewusst null: In echt initialisiert main() den Marker beim ersten
    // Start (ensureFindSeenMarker) — im Harness bleibt er aus, damit kein
    // Bestandstest ungefragt ein Buddy-Fund-Banner bekommt. Tests, die
    // das Banner wollen, geben einen alten Zeitstempel mit.
    this.lastFindSeenAt,
    this.findPhotosEnabled = true,
    Set<String>? seenFindPhotoIds,
    // **Vorgabe hier „alles gesehen", in der App `null`.** Sonst bekäme
    // jeder Bestandstest das Neuheiten-Blatt über die Karte gelegt —
    // dieselbe Begründung wie bei `mapTourSeen`. Wer das Blatt prüfen
    // will, gibt `highlightsSeenVersion: null` (Rückblick) oder eine
    // alte Version mit.
    this.highlightsSeenVersion = FakeSettings.kFakeAllHighlightsSeen,
    Set<String>? seenHighlightIds,
    // **Vorgabe hier „alle gesehen", in der App leer** — wie bei
    // `mapTourSeen`: Sonst legte sich über jeden Test, der einen Reiter
    // öffnet, dessen Tour. Wer sie prüfen will, gibt `{}` mit.
    Set<String>? seenCoachTours,
  })  : seenFindPhotoIds = seenFindPhotoIds ?? {},
        seenHighlightIds = seenHighlightIds ?? {},
        seenCoachTours = seenCoachTours ?? {...kFakeAllTabToursSeen};

  /// Jede Reiter-Tour, die es gibt — ein Test hält die Liste gegen die
  /// Skripte zusammen.
  static const kFakeAllTabToursSeen = {'spots', 'pilze', 'buddys'};

  @override
  Set<String> seenCoachTours;

  @override
  Future<void> setSeenCoachTours(Set<String> value) async {
    seenCoachTours = {...value};
  }

  /// Höher als jede echte Version: Kein Eintrag ist danach neu.
  static const kFakeAllHighlightsSeen = '9999.0.0';

  @override
  String? highlightsSeenVersion;

  @override
  Future<void> setHighlightsSeenVersion(String value) async {
    highlightsSeenVersion = value;
  }

  @override
  Set<String> seenHighlightIds;

  @override
  Future<void> setSeenHighlightIds(Set<String> value) async {
    seenHighlightIds = {...value};
  }

  @override
  bool offlineMapEnabled;

  @override
  Future<void> setOfflineMapEnabled(bool value) async {
    offlineMapEnabled = value;
  }

  @override

  @override
  bool mapLegendOpen;

  @override
  Future<void> setMapLegendOpen(bool value) async {
    mapLegendOpen = value;
  }

  @override
  bool rainCourseEnabled;

  @override
  Future<void> setRainCourseEnabled(bool value) async {
    rainCourseEnabled = value;
  }

  @override
  bool prereleaseUpdatesEnabled;

  @override
  Future<void> setPrereleaseUpdatesEnabled(bool value) async {
    prereleaseUpdatesEnabled = value;
  }

  @override
  bool forestFineEnabled;

  @override
  Future<void> setForestFineEnabled(bool value) async {
    forestFineEnabled = value;
  }

  @override
  bool mapAutoUpdateEnabled;

  @override
  Future<void> setMapAutoUpdateEnabled(bool value) async {
    mapAutoUpdateEnabled = value;
  }

  @override
  bool ampelPreviewEnabled;

  @override
  Future<void> setAmpelPreviewEnabled(bool value) async {
    ampelPreviewEnabled = value;
  }

  @override
  bool findPhotosEnabled;

  @override
  Future<void> setFindPhotosEnabled(bool value) async {
    findPhotosEnabled = value;
  }

  @override
  Set<String> seenFindPhotoIds;

  @override
  Future<void> setSeenFindPhotoIds(Set<String> value) async {
    seenFindPhotoIds = {...value};
  }

  @override
  bool ampelBannerEnabled;

  @override
  Future<void> setAmpelBannerEnabled(bool value) async {
    ampelBannerEnabled = value;
  }

  @override
  bool forestLayerEnabled;

  @override
  Future<void> setForestLayerEnabled(bool value) async {
    forestLayerEnabled = value;
  }

  @override
  bool contourLayerEnabled;

  @override
  bool gbifLayerEnabled;

  @override
  Future<void> setGbifLayerEnabled(bool value) async {
    gbifLayerEnabled = value;
  }

  @override
  Set<String> ampelExcludedSpecies = {};

  @override
  Future<void> setAmpelExcludedSpecies(Set<String> value) async {
    ampelExcludedSpecies = {...value};
  }

  @override
  Future<void> setContourLayerEnabled(bool value) async {
    contourLayerEnabled = value;
  }

  @override
  bool ampelLayerEnabled;

  @override
  Future<void> setAmpelLayerEnabled(bool value) async {
    ampelLayerEnabled = value;
  }

  @override
  String? rainLayerName;

  @override
  Future<void> setRainLayerName(String? value) async {
    rainLayerName = value;
  }

  @override
  bool mapTourSeen;

  @override
  final bool legacyMapTourSeen;
  @override
  bool safetyNoteSeen;
  @override
  bool tourTrackAsLine;

  @override
  Future<void> setMapTourSeen(bool value) async {
    mapTourSeen = value;
  }

  @override
  Future<void> setSafetyNoteSeen(bool value) async {
    safetyNoteSeen = value;
  }

  @override
  Future<void> setTourTrackAsLine(bool value) async {
    tourTrackAsLine = value;
  }

  @override
  String? pushToken;

  @override
  Future<void> setPushToken(String? value) async {
    pushToken = value;
  }

  @override


  @override
  DateTime? lastFindSeenAt;

  @override
  Future<void> setLastFindSeenAt(DateTime value) async {
    lastFindSeenAt = value;
  }

  @override
  DateTime? spotMemoryDismissedUntil;

  @override
  Future<void> setSpotMemoryDismissedUntil(DateTime value) async {
    spotMemoryDismissedUntil = value;
  }

  @override
  int tourIntervalSeconds;

  @override
  Future<void> setTourIntervalSeconds(int value) async {
    tourIntervalSeconds = value;
  }

}
