import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gerätelokale Einstellungen — alles, was auf *diesem* Gerät gilt und
/// nicht ins Konto gehört.
///
/// Bewusst schmal: Was die Nutzerin überallhin begleiten soll (Teilen-Regeln,
/// Avatar), steht in Supabase und wird dort von RLS geschützt. Hier liegt
/// nur, was ohne Konto und ohne Netz beantwortbar sein muss.
///
/// Als Schnittstelle, damit Tests sie wie die Repositories mit einer Fake
/// belegen können (`test/fakes/fake_settings.dart`) — ein echter
/// SharedPreferences-Kanal existiert im Widget-Test nicht.
abstract interface class Settings {
  /// Hat die Nutzerin die Offline-Karte von Hand eingeschaltet?
  bool get offlineMapEnabled;

  Future<void> setOfflineMapEnabled(bool value);

  /// Bisherige Karten-Engine (flutter_map) statt der neuen (MapLibre)?
  /// Seit der Abnahme des Direktvergleichs (docs/map-performance.md) ist
  /// MapLibre auf Android Standard; dieser Schalter ist das Opt-out und
  /// bleibt mindestens eine Release-Reihe als Rückfalllinie.
  bool get classicMapEnabled;

  Future<void> setClassicMapEnabled(bool value);

  /// Darf der Regenverlauf am Spot Daten nachladen?
  ///
  /// Standardmäßig NEIN — dieselbe Zusage wie bei der Regenebene: Der
  /// Stapel kostet beim ersten Mal rund 0,9 MB, und das gibt man im Wald
  /// nicht ungefragt aus. Wer einmal zugestimmt hat, wird nicht wieder
  /// gefragt; danach ist es eine Datei am Tag.
  bool get rainCourseEnabled;

  Future<void> setRainCourseEnabled(bool value);
}

/// Umsetzung auf SharedPreferences (Android: XML im App-Verzeichnis).
class PrefsSettings implements Settings {
  const PrefsSettings(this._prefs);

  final SharedPreferences _prefs;

  static const _offlineMapEnabledKey = 'offline_map_enabled';

  /// Bewusst ein NEUER Schlüssel: Der Beta-Schalter (1.39.0–1.42.0)
  /// speicherte ein Opt-in unter 'maplibre_enabled', und ein dort
  /// hinterlegtes false hieß nur „Beta nicht angefasst" — es darf die
  /// neue Standard-Engine nicht abschalten. Das Opt-out ist eine
  /// frische, bewusste Entscheidung; der alte Schlüssel wird ignoriert.
  static const _classicMapEnabledKey = 'classic_map_enabled';

  @override
  bool get offlineMapEnabled => _prefs.getBool(_offlineMapEnabledKey) ?? false;

  @override
  Future<void> setOfflineMapEnabled(bool value) =>
      _prefs.setBool(_offlineMapEnabledKey, value);

  static const _rainCourseEnabledKey = 'rain_course_enabled';

  @override
  bool get classicMapEnabled => _prefs.getBool(_classicMapEnabledKey) ?? false;

  @override
  Future<void> setClassicMapEnabled(bool value) =>
      _prefs.setBool(_classicMapEnabledKey, value);

  @override
  bool get rainCourseEnabled => _prefs.getBool(_rainCourseEnabledKey) ?? false;

  @override
  Future<void> setRainCourseEnabled(bool value) =>
      _prefs.setBool(_rainCourseEnabledKey, value);
}

/// Wird in `main()` mit den geladenen Einstellungen überschrieben, in Tests
/// vom Harness (`test/fakes/test_app.dart`).
///
/// Absichtlich synchron statt `FutureProvider`: Die Kartenquelle steht damit
/// schon im ersten Frame fest. Ein asynchrones Nachladen ließe die Karte
/// online starten und erst danach umschalten — sichtbar als kurzer Griff
/// nach Kacheln, die es im Wald nicht gibt.
final settingsProvider = Provider<Settings>((ref) {
  throw StateError('settingsProvider muss überschrieben werden — '
      'siehe main() und test/fakes/test_app.dart');
});
