import 'package:pilzbuddy/core/settings.dart';

/// Einstellungen im Speicher. Ein echter SharedPreferences-Kanal existiert
/// im Widget-Test nicht; ein Test, der den Neustart nachstellt, gibt die
/// Instanz einfach an den zweiten `pumpApp`-Aufruf weiter.
class FakeSettings implements Settings {
  FakeSettings({
    this.offlineMapEnabled = false,
    this.classicMapEnabled = false,
    this.mapLongPressEnabled = false,
    this.mapLegendEnabled = true,
    this.rainCourseEnabled = false,
    this.prereleaseUpdatesEnabled = false,
    this.forestFineEnabled = false,
    this.mapAutoUpdateEnabled = false,
    this.ampelPreviewEnabled = false,
    this.ampelBannerEnabled = false,
    this.forestLayerEnabled = false,
    this.contourLayerEnabled = false,
    this.ampelLayerEnabled = false,
    this.rainLayerName,
    this.tourIntervalSeconds = kTourIntervalDefaultSeconds,
    // Bewusst null: In echt initialisiert main() den Marker beim ersten
    // Start (ensureFindSeenMarker) — im Harness bleibt er aus, damit kein
    // Bestandstest ungefragt ein Buddy-Fund-Banner bekommt. Tests, die
    // das Banner wollen, geben einen alten Zeitstempel mit.
    this.lastFindSeenAt,
    this.ampelBannerDismissedUntil,
  });

  @override
  bool offlineMapEnabled;

  @override
  Future<void> setOfflineMapEnabled(bool value) async {
    offlineMapEnabled = value;
  }

  @override
  bool classicMapEnabled;

  @override
  Future<void> setClassicMapEnabled(bool value) async {
    classicMapEnabled = value;
  }

  @override
  bool mapLongPressEnabled;

  @override
  Future<void> setMapLongPressEnabled(bool value) async {
    mapLongPressEnabled = value;
  }

  @override
  bool mapLegendEnabled;

  @override
  Future<void> setMapLegendEnabled(bool value) async {
    mapLegendEnabled = value;
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

  @override
  DateTime? ampelBannerDismissedUntil;

  @override
  Future<void> setAmpelBannerDismissedUntil(DateTime value) async {
    ampelBannerDismissedUntil = value;
  }
}
