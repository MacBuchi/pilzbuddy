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

  /// Liegt die Legende aktiver Ebenen auf der Karte? (#231)
  ///
  /// Standardmäßig JA — eine Fläche ohne Legende bedeutet nichts, das
  /// war die erste Feld-Rückmeldung zur Regenfläche (2026-08-04) und
  /// zur Waldebene gleich noch einmal. Das X an der Legende schaltet
  /// diese Einstellung aus (persistent); wieder an geht sie im
  /// Ebenen-Blatt.
  bool get mapLegendEnabled;

  Future<void> setMapLegendEnabled(bool value);

  /// Richtet langes Draufhalten das Fadenkreuz aus? (#210)
  ///
  /// Standardmäßig NEIN. Die Geste sprang auf die gedrückte Stelle **und**
  /// auf Zoom 16; ein Fehlgriff aus der Übersicht warf einen damit
  /// woanders hin und viel zu nah heran. Entschärfen ließ sie sich nicht:
  /// Weder flutter_map noch MapLibre lassen Haltedauer oder
  /// Bewegungstoleranz einstellen. Zum Heranzoomen gibt es den Doppeltipp,
  /// den beide Engines ohnehin können.
  ///
  /// Gespeichert wird das FEATURE, nicht sein Opt-out — anders als bei
  /// [classicMapEnabled]. Dort war „aus" der Sonderfall, hier ist es der
  /// Normalzustand, und ein doppelt verneinter Schlüssel wäre beim Lesen
  /// eine Stolperfalle.
  bool get mapLongPressEnabled;

  Future<void> setMapLongPressEnabled(bool value);

  /// Darf der Regenverlauf am Spot Daten nachladen?
  ///
  /// Standardmäßig NEIN — dieselbe Zusage wie bei der Regenebene: Der
  /// Stapel kostet beim ersten Mal rund 0,9 MB, und das gibt man im Wald
  /// nicht ungefragt aus. Wer einmal zugestimmt hat, wird nicht wieder
  /// gefragt; danach ist es eine Datei am Tag.
  bool get rainCourseEnabled;

  Future<void> setRainCourseEnabled(bool value);

  /// Bis zu welchem Zeitpunkt Buddy-Funde als gesehen gelten (#202).
  ///
  /// Gerätelokal mit Absicht: Der Hinweis ist eine Bequemlichkeit dieses
  /// Geräts, kein Konto-Zustand. Verglichen wird gegen die SERVER-Zeit
  /// der Funde (`created_at`), nicht gegen die Geräteuhr. `null` heißt
  /// „nie initialisiert" — das Banner bleibt dann aus, siehe
  /// [ensureFindSeenMarker].
  DateTime? get lastFindSeenAt;

  Future<void> setLastFindSeenAt(DateTime value);
}

/// Erstlauf-Schutz für das Buddy-Fund-Banner: Ohne Marker gälte ALLES als
/// neu — auf geteilten Spots liegen seit jeher fremde (Besitzer-)Funde,
/// und das Banner schriee beim ersten Start nach dem Update über den
/// kompletten Bestand. Deshalb setzt `main()` den Marker einmalig auf
/// „jetzt"; ab da zählt nur, was danach dazukommt.
Future<void> ensureFindSeenMarker(Settings settings, {DateTime? now}) async {
  if (settings.lastFindSeenAt != null) return;
  await settings.setLastFindSeenAt(now ?? DateTime.now().toUtc());
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

  static const _mapLongPressEnabledKey = 'map_long_press_enabled';

  static const _mapLegendEnabledKey = 'map_legend_enabled';

  @override
  bool get mapLegendEnabled => _prefs.getBool(_mapLegendEnabledKey) ?? true;

  @override
  Future<void> setMapLegendEnabled(bool value) =>
      _prefs.setBool(_mapLegendEnabledKey, value);

  @override
  bool get classicMapEnabled => _prefs.getBool(_classicMapEnabledKey) ?? false;

  @override
  bool get mapLongPressEnabled =>
      _prefs.getBool(_mapLongPressEnabledKey) ?? false;

  @override
  Future<void> setMapLongPressEnabled(bool value) =>
      _prefs.setBool(_mapLongPressEnabledKey, value);

  @override
  Future<void> setClassicMapEnabled(bool value) =>
      _prefs.setBool(_classicMapEnabledKey, value);

  @override
  bool get rainCourseEnabled => _prefs.getBool(_rainCourseEnabledKey) ?? false;

  @override
  Future<void> setRainCourseEnabled(bool value) =>
      _prefs.setBool(_rainCourseEnabledKey, value);

  // Die erste Nicht-Bool-Einstellung: als ISO-8601-UTC-String, dasselbe
  // Format, das auch die Fehlerberichte schreiben.
  static const _lastFindSeenAtKey = 'last_find_seen_at';

  @override
  DateTime? get lastFindSeenAt {
    final raw = _prefs.getString(_lastFindSeenAtKey);
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  @override
  Future<void> setLastFindSeenAt(DateTime value) =>
      _prefs.setString(_lastFindSeenAtKey, value.toUtc().toIso8601String());
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
