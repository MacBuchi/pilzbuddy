import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'errors.dart';

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
/// Vorgabetakt der Pilztour — die Zahl des Betreibers (#338).
const kTourIntervalDefaultSeconds = 15;

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
  /// Stapel kostet beim ersten Mal knapp 2 MB (26 Tage seit dem
  /// Ampel-Fenster, #256), und das gibt man im Wald nicht ungefragt
  /// aus. Wer einmal zugestimmt hat, wird nicht wieder gefragt; danach
  /// ist es eine Datei am Tag.
  bool get rainCourseEnabled;

  Future<void> setRainCourseEnabled(bool value);

  /// Zeigt die App die experimentelle Pilzampel-Vorschau?
  ///
  /// Standardmäßig NEIN. Die Ampel ist UNVALIDIERT (die Rückwärtsprüfung
  /// läuft, docs/pilzampel-validierung.md) und existiert als Vorschau
  /// nur, weil der Betreiber sie sehen will, während die Prüfung läuft
  /// (Entscheidung 2026-08-09). Der Schalter ist zugleich der Notaus:
  /// Fällt die Validierung durch, verschwindet die Vorschau, ohne dass
  /// jemandem etwas versprochen war.
  bool get ampelPreviewEnabled;

  Future<void> setAmpelPreviewEnabled(bool value);

  /// Prüft die App beim Kartenstart, ob an einem eigenen Spot die Ampel
  /// günstig steht (Baustein B, #277)?
  ///
  /// Standardmäßig NEIN, und der Grund ist Rechenzeit, nicht Vorsicht:
  /// Der Nachlauf braucht das Höhengitter, und dessen 3,4 MB beim Start
  /// auszupacken ist genau die Last, die 1.99.4 aus dem Startpfad
  /// entfernt hat. Ein eigener Schalter — nicht der der Ampel-Vorschau —,
  /// damit sie nur zahlt, wer sie bestellt hat. Ohne Höhe rechnen wäre
  /// nicht umsonst: #279 verlangt, dass Fläche und Blatt gleich
  /// korrigieren, und ein Banner, das dem Blatt widerspricht, wäre
  /// schlimmer als keins.
  bool get ampelBannerEnabled;

  Future<void> setAmpelBannerEnabled(bool value);

  /// Lag die Waldebene beim letzten Mal auf der Karte (#349)?
  ///
  /// **Das dreht eine ausdrückliche Entscheidung um** — und zwar zwei
  /// verschiedene. Wald und Höhenlinien waren sitzungslokal, weil „eine
  /// über Nacht vergessene Ebene mehr verwirrt, als der eine Tipp zum
  /// Wiedereinschalten kostet"; Regen und Ampel, weil eine „beim Start
  /// aktive Ebene ein ungefragter Download" wäre.
  ///
  /// Die erste Begründung ist seit #347 hinfällig: Die Zahl am
  /// Ebenen-Knopf sagt auf einen Blick, was an ist — die Verwirrung,
  /// gegen die die Regel stand, gibt es nicht mehr. Die zweite
  /// verwechselt „ungefragt" mit „einmal gefragt": Ein
  /// wiederhergestellter Schalter ist die Antwort von gestern, keine
  /// Entscheidung der App. Genau so hält es [forestFineEnabled] längst,
  /// und dort hängen 26 MB dran statt der 200–600 KB der Regenebene.
  ///
  /// Der Preis bleibt echt und gehört gesagt: Wer die Ampel anlässt,
  /// packt ihre Gitter bei JEDEM Start aus — dieselbe Last, die 1.99.4
  /// aus dem Startpfad genommen hat. Geändert hat sich nur, wer sie
  /// zahlt: ausschließlich, wer den Schalter selbst umgelegt hat.
  bool get forestLayerEnabled;

  Future<void> setForestLayerEnabled(bool value);

  /// Lagen beim letzten Mal Höhenlinien auf der Karte? Begründung siehe
  /// [forestLayerEnabled].
  bool get contourLayerEnabled;

  Future<void> setContourLayerEnabled(bool value);

  /// Leuchtete beim letzten Mal die Pilzampel? Begründung siehe
  /// [forestLayerEnabled].
  ///
  /// Kommt nie allein zurück: Die Ampel ist ein Modus der Waldfläche,
  /// und `setAmpelLayerEnabled` schaltet den Wald mit ein — beide
  /// Schalter wurden gemeinsam gemerkt und kehren gemeinsam wieder.
  bool get ampelLayerEnabled;

  Future<void> setAmpelLayerEnabled(bool value);

  /// Die zuletzt gewählte Regen-Ebene als `RainLayer.name` — `null`
  /// heißt „aus". Begründung siehe [forestLayerEnabled].
  ///
  /// **Als Name und nicht als Index**: Der Index hängt an der Reihenfolge
  /// im Enum, eine später eingeschobene Ebene verschöbe stillschweigend
  /// die Wahl jedes Nutzers. Ein unbekannter Name fällt beim Lesen auf
  /// „aus" zurück. Dass hier eine Zeichenkette steht und kein Enum, hat
  /// denselben Grund wie alles in dieser Datei: `core/` kennt die
  /// Feature-Typen nicht.
  String? get rainLayerName;

  Future<void> setRainLayerName(String? value);

  /// Das zuletzt registrierte FCM-Token dieses Geräts (#277) — `null`,
  /// solange niemand Push eingeschaltet hat.
  ///
  /// **Gemerkt wird das Token, nicht ein „an/aus".** Die Wahrheit darüber,
  /// ob dieses Gerät Meldungen bekommt, steht in `push_devices`; ein
  /// zweites Flag daneben liefe beim ersten Abmelden auseinander. Der Wert
  /// hier ist nur, was die App zum AUSTRAGEN braucht — ohne ihn wüsste sie
  /// beim Abschalten nicht, welche Zeile zu löschen ist.
  String? get pushToken;

  Future<void> setPushToken(String? value);

  /// Bekommt dieses Gerät auch Vorabversionen angeboten? (#269)
  ///
  /// Standardmäßig NEIN, und das ist der ganze Sinn der Trennung: Seit
  /// #262 baut JEDER Merge ein Release, aber als Prerelease — für die
  /// Nutzer unsichtbar, weil `/releases/latest` grundsätzlich keine
  /// Prereleases liefert. Wer den Schalter umlegt, hebt genau diesen
  /// Schutz für sich auf und bekommt Zwischenstände, die niemand
  /// abgenommen hat.
  ///
  /// Gerätelokal wie alle Schalter hier: Es ist eine Einstellung dieses
  /// Telefons, keine des Kontos — auf dem Zweitgerät will man denselben
  /// Menschen nicht zwangsweise im Vorab-Kanal haben.
  bool get prereleaseUpdatesEnabled;

  Future<void> setPrereleaseUpdatesEnabled(bool value);

  /// Darf die Waldkarte feine Waben (≈ 100 m) nachladen? (#253)
  ///
  /// Standardmäßig NEIN, dieselbe Zusage wie beim Regenverlauf: Ein
  /// Block kostet rund 1 MB, und das gibt man im Wald nicht ungefragt
  /// aus. Der Schalter im Waldtypen-Blatt IST die Zustimmung — sein
  /// Text nennt die Kosten. Geladene Blöcke bleiben auf Platte, ohne
  /// Empfang gilt die eingebaute 250-m-Karte.
  bool get forestFineEnabled;

  Future<void> setForestFineEnabled(bool value);

  /// Darf die App veraltete Offline-Karten im freien Netz von selbst
  /// nachladen? (#332)
  ///
  /// Standardmäßig NEIN, und zwar aus einem härteren Grund als bei den
  /// anderen Zustimmungen: Eine Regionskarte ist mehrere hundert MB bis
  /// 1,7 GB groß. Was der Schalter NICHT tut, ist neue Regionen holen —
  /// nur Regionen, die schon auf dem Gerät liegen, auf den neuen Stand
  /// bringen.
  bool get mapAutoUpdateEnabled;

  Future<void> setMapAutoUpdateEnabled(bool value);

  /// Bis wann die Spot-Erinnerung stummgeschaltet ist (Baustein C des
  /// Ampel-Konzepts): Das X am Banner setzt den Zeitpunkt ans Ende des
  /// laufenden ±14-Tage-Fensters — dieselbe Erinnerung soll nicht jeden
  /// Morgen wiederkommen, die des nächsten Fensters aber schon.
  DateTime? get spotMemoryDismissedUntil;

  Future<void> setSpotMemoryDismissedUntil(DateTime value);

  /// Der Takt der Pilztour in Sekunden (#338).
  ///
  /// Gerätelokal, weil er zum Gerät gehört und nicht zum Konto: Ein altes
  /// Telefon mit knappem Akku will einen längeren Takt als ein neues.
  int get tourIntervalSeconds;

  Future<void> setTourIntervalSeconds(int value);

  /// Bis wann das Ampel-Banner stummgeschaltet ist (Baustein B, #277):
  /// Das X setzt den Zeitpunkt ans ENDE DES TAGES.
  ///
  /// Warum genau bis dahin und nicht länger: Der Regenstapel bekommt
  /// täglich einen neuen Tag, die Aussage ist morgen also eine andere.
  /// Länger stummzuschalten hieße, eine geänderte Lage zu verschweigen;
  /// kürzer hieße, dieselbe Lage beim nächsten App-Start zu wiederholen.
  DateTime? get ampelBannerDismissedUntil;

  Future<void> setAmpelBannerDismissedUntil(DateTime value);

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

  static const _ampelPreviewEnabledKey = 'ampel_preview_enabled';

  @override
  bool get ampelPreviewEnabled =>
      _prefs.getBool(_ampelPreviewEnabledKey) ?? false;

  @override
  Future<void> setAmpelPreviewEnabled(bool value) =>
      _prefs.setBool(_ampelPreviewEnabledKey, value);

  static const _ampelBannerEnabledKey = 'ampel_banner_enabled';

  @override
  bool get ampelBannerEnabled =>
      _prefs.getBool(_ampelBannerEnabledKey) ?? false;

  @override
  Future<void> setAmpelBannerEnabled(bool value) =>
      _prefs.setBool(_ampelBannerEnabledKey, value);

  static const _forestLayerEnabledKey = 'forest_layer_enabled';

  @override
  bool get forestLayerEnabled =>
      _prefs.getBool(_forestLayerEnabledKey) ?? false;

  @override
  Future<void> setForestLayerEnabled(bool value) =>
      _prefs.setBool(_forestLayerEnabledKey, value);

  static const _contourLayerEnabledKey = 'contour_layer_enabled';

  @override
  bool get contourLayerEnabled =>
      _prefs.getBool(_contourLayerEnabledKey) ?? false;

  @override
  Future<void> setContourLayerEnabled(bool value) =>
      _prefs.setBool(_contourLayerEnabledKey, value);

  static const _ampelLayerEnabledKey = 'ampel_layer_enabled';

  @override
  bool get ampelLayerEnabled => _prefs.getBool(_ampelLayerEnabledKey) ?? false;

  @override
  Future<void> setAmpelLayerEnabled(bool value) =>
      _prefs.setBool(_ampelLayerEnabledKey, value);

  static const _rainLayerNameKey = 'rain_layer_name';

  @override
  String? get rainLayerName => _prefs.getString(_rainLayerNameKey);

  @override
  Future<void> setRainLayerName(String? value) => value == null
      ? _prefs.remove(_rainLayerNameKey)
      : _prefs.setString(_rainLayerNameKey, value);

  static const _pushTokenKey = 'push_token';

  @override
  String? get pushToken => _prefs.getString(_pushTokenKey);

  @override
  Future<void> setPushToken(String? value) => value == null
      ? _prefs.remove(_pushTokenKey)
      : _prefs.setString(_pushTokenKey, value);

  static const _prereleaseUpdatesEnabledKey = 'prerelease_updates_enabled';

  @override
  bool get prereleaseUpdatesEnabled =>
      _prefs.getBool(_prereleaseUpdatesEnabledKey) ?? false;

  @override
  Future<void> setPrereleaseUpdatesEnabled(bool value) =>
      _prefs.setBool(_prereleaseUpdatesEnabledKey, value);

  static const _forestFineEnabledKey = 'forest_fine_enabled';

  @override
  bool get forestFineEnabled =>
      _prefs.getBool(_forestFineEnabledKey) ?? false;

  @override
  Future<void> setForestFineEnabled(bool value) =>
      _prefs.setBool(_forestFineEnabledKey, value);

  static const _mapAutoUpdateEnabledKey = 'map_auto_update_enabled';

  @override
  bool get mapAutoUpdateEnabled =>
      _prefs.getBool(_mapAutoUpdateEnabledKey) ?? false;

  @override
  Future<void> setMapAutoUpdateEnabled(bool value) =>
      _prefs.setBool(_mapAutoUpdateEnabledKey, value);

  static const _spotMemoryDismissedUntilKey = 'spot_memory_dismissed_until';

  @override
  DateTime? get spotMemoryDismissedUntil {
    final raw = _prefs.getString(_spotMemoryDismissedUntilKey);
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  @override
  Future<void> setSpotMemoryDismissedUntil(DateTime value) =>
      _prefs.setString(
          _spotMemoryDismissedUntilKey, value.toUtc().toIso8601String());

  static const _tourIntervalSecondsKey = 'tour_interval_seconds';

  @override
  int get tourIntervalSeconds =>
      _prefs.getInt(_tourIntervalSecondsKey) ?? kTourIntervalDefaultSeconds;

  @override
  Future<void> setTourIntervalSeconds(int value) =>
      _prefs.setInt(_tourIntervalSecondsKey, value);

  static const _ampelBannerDismissedUntilKey = 'ampel_banner_dismissed_until';

  @override
  DateTime? get ampelBannerDismissedUntil {
    final raw = _prefs.getString(_ampelBannerDismissedUntilKey);
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  @override
  Future<void> setAmpelBannerDismissedUntil(DateTime value) =>
      _prefs.setString(
          _ampelBannerDismissedUntilKey, value.toUtc().toIso8601String());

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

/// Ein gerätelokal gemerkter An/Aus-Schalter (#349).
///
/// **Warum ein Notifier und kein `StateProvider`.** Ein StateProvider
/// lässt sich von überall mit `.notifier).state = x` setzen, und das
/// Merken wäre dann ein zweiter Schritt, den man vergessen kann — die
/// Sorte Fehler, die erst beim übernächsten App-Start auffällt. Hier
/// gibt es nur [set], und das tut beides.
///
/// Muster wie `AmpelBannerEnabledNotifier`: Der Zustand springt sofort,
/// das Merken läuft nach, ein Fehler dabei wird nur protokolliert — eine
/// Ebene, die sich nicht merken lässt, soll trotzdem angehen.
class RememberedFlag extends Notifier<bool> {
  RememberedFlag({
    required this.read,
    required this.write,
    required this.label,
  });

  final bool Function(Settings settings) read;
  final Future<void> Function(Settings settings, bool value) write;

  /// Der Kontext für `logError`, etwa „Waldebene merken".
  final String label;

  @override
  bool build() => read(ref.read(settingsProvider));

  void set(bool value) {
    state = value;
    unawaited(write(ref.read(settingsProvider), value)
        .catchError((Object e, StackTrace s) => logError(label, e, s)));
  }
}
