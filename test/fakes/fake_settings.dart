import 'package:pilzbuddy/core/settings.dart';

/// Einstellungen im Speicher. Ein echter SharedPreferences-Kanal existiert
/// im Widget-Test nicht; ein Test, der den Neustart nachstellt, gibt die
/// Instanz einfach an den zweiten `pumpApp`-Aufruf weiter.
class FakeSettings implements Settings {
  FakeSettings({
    this.offlineMapEnabled = false,
    this.classicMapEnabled = false,
    this.rainCourseEnabled = false,
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
  bool rainCourseEnabled;

  @override
  Future<void> setRainCourseEnabled(bool value) async {
    rainCourseEnabled = value;
  }
}
