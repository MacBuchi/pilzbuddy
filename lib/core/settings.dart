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
  /// Ist die Legende aktiver Ebenen AUSGEKLAPPT? (#231)
  ///
  /// Standardmäßig JA — eine Fläche ohne Legende bedeutet nichts, das
  /// war die erste Feld-Rückmeldung zur Regenfläche (2026-08-04) und
  /// zur Waldebene gleich noch einmal.
  ///
  /// **Bis 1.131.0 hieß das hier „liegt sie auf der Karte", und das ✕
  /// schaltete sie WEG.** Zurück führte nur ein Schalter, der in drei
  /// Blättern stand — und jedes Mal nur, wenn die jeweilige Ebene an
  /// war. Wer die Legende wegtippte und danach alle Ebenen ausschaltete,
  /// hatte keinen Rückweg mehr. Dieselbe Sorte Sackgasse wie #425 und
  /// #349: ein Tipp nimmt ein Feature weg, und nirgends steht, wie man
  /// es zurückholt.
  ///
  /// Jetzt gibt es kein Weg mehr, nur ein Zu: Eingeklappt bleibt eine
  /// 40 Pixel schmale Schiene stehen, und die IST der Rückweg. Ein
  /// Zustand, aus dem man nicht mehr herausfindet, kann damit gar nicht
  /// entstehen.
  ///
  /// Der Prefs-Schlüssel heißt weiter `map_legend_enabled` — er trägt
  /// denselben Wert für dieselbe Geste, und ein neuer Name kostete jedem
  /// Bestandsgerät seine Entscheidung.
  bool get mapLegendOpen;

  Future<void> setMapLegendOpen(bool value);

  // Der Schalter „Karte gedrückt halten" (#210) ist mit #483 entfallen,
  // und mit ihm der Prefs-Schlüssel 'map_long_press_enabled'. Er stand
  // AUS, weil die Geste sofort die Kamera warf; seit sie erst ein Menü
  // öffnet, ist sie ungefährlich und ab Werk an. Der alte Schlüssel
  // liegt auf Bestandsgeräten herum und wird nie wieder gelesen.


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

  /// Lagen beim letzten Mal die gemeldeten Fundorte (GBIF, #467) auf der
  /// Karte? Begründung siehe [forestLayerEnabled]. Der Preis ist ein
  /// Asset von 0,6 MB, das beim Start ausgepackt wird — nur für den, der
  /// den Schalter selbst umgelegt hat.
  bool get gbifLayerEnabled;

  Future<void> setGbifLayerEnabled(bool value);

  /// Arten, die der Nutzer von der Pilzampel ausgenommen hat (#495,
  /// Schalter je Art im Reiter „Pilze"). Gerätelokal wie die
  /// Ebenen-Schalter; leer ab Werk.
  Set<String> get ampelExcludedSpecies;

  Future<void> setAmpelExcludedSpecies(Set<String> value);

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

  /// Hat der Nutzer die geführte Tour über die Karte gesehen (#350)?
  ///
  /// Standardmäßig NEIN — sie läuft beim ersten Start von selbst an und
  /// danach nie wieder, es sei denn, jemand ruft sie aus der
  /// Kurzanleitung erneut auf. Übersprungen zählt wie durchgesehen: Wer
  /// abbricht, hat entschieden.
  ///
  /// Gerätelokal (Betreiber, 2026-08-29) und nicht am Konto. Der Preis
  /// ist bekannt und angenommen: Nach einer Neuinstallation läuft sie
  /// wieder — so wie beim Paketnamen-Wechsel in 1.88.0 für alle. Ein
  /// Feld am Konto hätte Patch, `schema.sql` und Saat-Liste gekostet,
  /// für eine Frage, die einmal im Leben eines Geräts gestellt wird.
  bool get mapTourSeen;

  Future<void> setMapTourSeen(bool value);

  /// Hat dieses Gerät die Karten-Tour VOR dem Zurücksetzen in 1.208.0
  /// gesehen? Nur gelesen, nie geschrieben.
  ///
  /// **Der Merker hat zwei Aufgaben, und nur eine sollte zurück.** Die
  /// neue Tour (#596) sollen alle sehen, also liest [mapTourSeen] seit
  /// 1.208.0 einen neuen Schlüssel. Aber der Rückblick erkennt
  /// Bestandsnutzer genau an diesem Merker — zurückgesetzt hielte er
  /// jeden für eine Neuinstallation, und der Rückblick fiele weg. Für
  /// DIESE Frage zählt deshalb auch der alte Schlüssel.
  bool get legacyMapTourSeen;

  /// Die Tourspur als Linie statt als Punkte? (#340)
  ///
  /// Vorgabe **Punkte**, und das ist keine Geschmacksfrage: Ihr Abstand
  /// sagt, wo jemand langsam ging oder stand — genau die Größe, aus der
  /// `tourVisits` die Leergänge ableitet. Eine Linie glättet das weg.
  /// Sie ist leichter zu verfolgen, wenn mehrere Spuren übereinander
  /// liegen, deshalb der Schalter.
  bool get tourTrackAsLine;

  Future<void> setTourTrackAsLine(bool value);

  /// Hat dieses Gerät den Haftungshinweis schon gesehen? (#110)
  ///
  /// Gerätelokal wie [mapTourSeen] und aus demselben Grund: Die Frage
  /// wird einmal im Leben einer Installation gestellt, und ein Feld am
  /// Konto kostete Patch, `schema.sql` und Saat-Liste. Dass er nach einer
  /// Neuinstallation wiederkommt, ist bei diesem Hinweis eher richtig als
  /// falsch.
  bool get safetyNoteSeen;

  Future<void> setSafetyNoteSeen(bool value);

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
  /// Bis zu welchem Zeitpunkt Buddy-Funde als gesehen gelten (#202).
  ///
  /// Gerätelokal mit Absicht: Der Hinweis ist eine Bequemlichkeit dieses
  /// Geräts, kein Konto-Zustand. Verglichen wird gegen die SERVER-Zeit
  /// der Funde (`created_at`), nicht gegen die Geräteuhr. `null` heißt
  /// „nie initialisiert" — das Banner bleibt dann aus, siehe
  /// [ensureFindSeenMarker].
  DateTime? get lastFindSeenAt;

  Future<void> setLastFindSeenAt(DateTime value);

  /// Fundfotos von Buddys anzeigen — und damit laden (#532)?
  ///
  /// Ab Werk JA, anders als die meisten Schalter hier: Ein Foto kommt
  /// nur, weil ein Buddy es ausdrücklich für seine Buddys geteilt hat,
  /// und ein Posteingang, den erst ein Schalter öffnet, ist einer, den
  /// niemand findet. Der Schalter ist für die andere Richtung da — wer
  /// unterwegs kein Datenvolumen für Bilder ausgeben will, stellt ihn
  /// aus, und dann wird KEINE Vorschau geholt, nicht nur keine gezeigt.
  /// Eigene Fotos bleiben sichtbar; die hat man selbst hochgeladen.
  /// Gerätelokal, wie alle Schalter hier.
  bool get findPhotosEnabled;

  Future<void> setFindPhotosEnabled(bool value);

  /// Welche Fundfotos von Buddys schon angesehen wurden — daran hängt der
  /// Neu-Punkt der Galerie im Reiter „Buddys". Gerätelokal wie
  /// [lastFindSeenAt]; die Menge wird beim Setzen auf die noch lebenden
  /// Fotos gestutzt, wächst also nie über die 14-Tage-Frist hinaus.
  Set<String> get seenFindPhotoIds;

  Future<void> setSeenFindPhotoIds(Set<String> value);

  /// Bis zu welcher Version dieses Gerät die Neuheiten kennt (#596).
  ///
  /// `null` heißt „nie gemerkt" — und ist damit genau die Frage, an der
  /// der Rückblick hängt: Vor 1.204.0 hat das kein Gerät gespeichert,
  /// also ist jeder Bestandsnutzer beim ersten Start damit `null`.
  /// Gerätelokal wie [mapTourSeen] und aus demselben Grund.
  String? get highlightsSeenVersion;

  Future<void> setHighlightsSeenVersion(String value);

  /// Welche Einträge der Seite „Entdecken" schon angesehen wurden — daran
  /// hängt ihr Neu-Punkt. Die Kennungen sind wenige und fest, die Menge
  /// wächst also nicht.
  Set<String> get seenHighlightIds;

  Future<void> setSeenHighlightIds(Set<String> value);

  /// Welche Reiter-Touren (#596) schon gelaufen sind — durchgesehen ODER
  /// übersprungen. Die Karten-Tour steht weiter in [mapTourSeen]: Ihr
  /// Merker ist älter, und ein Umzug hätte sie jedem Bestandsnutzer noch
  /// einmal gezeigt.
  Set<String> get seenCoachTours;

  Future<void> setSeenCoachTours(Set<String> value);
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

  // Zwei Schlüssel liegen auf Bestandsgeräten herum und werden NIE
  // wieder gelesen: 'maplibre_enabled' (Beta-Opt-in, 1.39.0–1.42.0) und
  // 'classic_map_enabled' (das Opt-out danach, 1.43.0–1.145.0). Seit
  // #433 gibt es auf Android nur noch MapLibre. Aufräumen lohnt nicht —
  // ein `remove` beim Start wäre Code, der genau einmal etwas tut und
  // danach für immer nichts.

  @override
  bool get offlineMapEnabled => _prefs.getBool(_offlineMapEnabledKey) ?? false;

  @override
  Future<void> setOfflineMapEnabled(bool value) =>
      _prefs.setBool(_offlineMapEnabledKey, value);

  static const _rainCourseEnabledKey = 'rain_course_enabled';

  static const _mapLegendEnabledKey = 'map_legend_enabled';

  @override
  bool get mapLegendOpen => _prefs.getBool(_mapLegendEnabledKey) ?? true;

  @override
  Future<void> setMapLegendOpen(bool value) =>
      _prefs.setBool(_mapLegendEnabledKey, value);

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

  static const _gbifLayerEnabledKey = 'gbif_layer_enabled';

  @override
  bool get gbifLayerEnabled =>
      _prefs.getBool(_gbifLayerEnabledKey) ?? false;

  @override
  Future<void> setGbifLayerEnabled(bool value) =>
      _prefs.setBool(_gbifLayerEnabledKey, value);

  static const _ampelExcludedSpeciesKey = 'ampel_excluded_species';

  @override
  Set<String> get ampelExcludedSpecies =>
      (_prefs.getStringList(_ampelExcludedSpeciesKey) ?? const []).toSet();

  @override
  Future<void> setAmpelExcludedSpecies(Set<String> value) =>
      _prefs.setStringList(_ampelExcludedSpeciesKey, value.toList()..sort());

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

  // `_2` seit 1.208.0: alle sehen die neue Tour (Betreiber, 2026-09-25).
  static const _mapTourSeenKey = 'map_tour_seen_2';
  static const _legacyMapTourSeenKey = 'map_tour_seen';

  @override
  bool get mapTourSeen => _prefs.getBool(_mapTourSeenKey) ?? false;

  @override
  bool get legacyMapTourSeen =>
      _prefs.getBool(_legacyMapTourSeenKey) ?? false;

  @override
  Future<void> setMapTourSeen(bool value) =>
      _prefs.setBool(_mapTourSeenKey, value);

  static const _tourTrackAsLineKey = 'tour_track_as_line';

  @override
  bool get tourTrackAsLine => _prefs.getBool(_tourTrackAsLineKey) ?? false;

  @override
  Future<void> setTourTrackAsLine(bool value) =>
      _prefs.setBool(_tourTrackAsLineKey, value);

  static const _safetyNoteSeenKey = 'safety_note_seen';

  @override
  bool get safetyNoteSeen => _prefs.getBool(_safetyNoteSeenKey) ?? false;

  @override
  Future<void> setSafetyNoteSeen(bool value) =>
      _prefs.setBool(_safetyNoteSeenKey, value);

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

  // Der Schlüssel `ampel_banner_dismissed_until` ist mit #425 entfallen:
  // Das X des Ampel-Banners schaltet nur noch für die laufende Sitzung
  // stumm (`ampelBannerMutedProvider`), und ein Zustand, der den
  // Neustart nicht überlebt, gehört nicht in die Einstellungen. Auf
  // Bestandsgeräten liegt der Wert weiter in den SharedPreferences und
  // wird nie wieder gelesen — eine Migration dafür wäre teurer als der
  // eine ungenutzte String. Wer den Namen neu belegt, erbt fremde Daten.

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

  static const _findPhotosEnabledKey = 'find_photos_enabled';

  @override
  bool get findPhotosEnabled =>
      _prefs.getBool(_findPhotosEnabledKey) ?? true;

  @override
  Future<void> setFindPhotosEnabled(bool value) =>
      _prefs.setBool(_findPhotosEnabledKey, value);

  static const _seenFindPhotoIdsKey = 'seen_find_photo_ids';

  @override
  Set<String> get seenFindPhotoIds =>
      (_prefs.getStringList(_seenFindPhotoIdsKey) ?? const []).toSet();

  @override
  Future<void> setSeenFindPhotoIds(Set<String> value) =>
      _prefs.setStringList(_seenFindPhotoIdsKey, value.toList()..sort());

  // **`_2`: einmal zurückgesetzt** (1.204.2, Betreiber 2026-09-24). Den
  // Rückblick hatten bis dahin nur Vorschau und Vorabkanal gesehen — in
  // der Blätter-Fassung von 1.204.0, die nach dem ersten „Ausprobieren"
  // verschwand. Ein neuer Name macht jedes Gerät wieder zu „nie
  // gemerkt"; der alte Schlüssel liegt herum und wird nie wieder gelesen.
  // Stabile Nutzer merken davon nichts, sie haben 1.204 nie gesehen.
  // `_3` seit 1.208.0: zweites Zurücksetzen für alle (Betreiber,
  // 2026-09-25), zusammen mit Touren und „Neu"-Punkten.
  static const _highlightsSeenVersionKey = 'highlights_seen_version_3';

  @override
  String? get highlightsSeenVersion =>
      _prefs.getString(_highlightsSeenVersionKey);

  @override
  Future<void> setHighlightsSeenVersion(String value) =>
      _prefs.setString(_highlightsSeenVersionKey, value);

  // `_2`/`_3` aus demselben Grund: „Entdecken" zeigt sein „Neu" wieder.
  static const _seenHighlightIdsKey = 'seen_highlight_ids_3';

  @override
  Set<String> get seenHighlightIds =>
      (_prefs.getStringList(_seenHighlightIdsKey) ?? const []).toSet();

  @override
  Future<void> setSeenHighlightIds(Set<String> value) =>
      _prefs.setStringList(_seenHighlightIdsKey, value.toList()..sort());

  static const _seenCoachToursKey = 'seen_coach_tours_2';

  @override
  Set<String> get seenCoachTours =>
      (_prefs.getStringList(_seenCoachToursKey) ?? const []).toSet();

  @override
  Future<void> setSeenCoachTours(Set<String> value) =>
      _prefs.setStringList(_seenCoachToursKey, value.toList()..sort());
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
