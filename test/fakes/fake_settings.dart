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
    this.forestFineEnabled = false,
    this.ampelPreviewEnabled = false,
    // Bewusst null: In echt initialisiert main() den Marker beim ersten
    // Start (ensureFindSeenMarker) — im Harness bleibt er aus, damit kein
    // Bestandstest ungefragt ein Buddy-Fund-Banner bekommt. Tests, die
    // das Banner wollen, geben einen alten Zeitstempel mit.
    this.lastFindSeenAt,
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
  bool forestFineEnabled;

  @override
  Future<void> setForestFineEnabled(bool value) async {
    forestFineEnabled = value;
  }

  @override
  bool ampelPreviewEnabled;

  @override
  Future<void> setAmpelPreviewEnabled(bool value) async {
    ampelPreviewEnabled = value;
  }

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
}
