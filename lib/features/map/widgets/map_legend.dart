// Die Legende auf der Karte — für ALLE aktiven Ebenen (#231).
//
// **Warum sie sein muss:** Seit 1.46.0 zeichnet die App die Summen in
// eigenen Farben. Ohne Legende bedeutet ein grüner Fleck genau nichts —
// der Betreiber hat es am 2026-08-04 als Erstes bemängelt, und er hatte
// recht: Im Ebenen-Blatt steht die Erklärung zwar, aber wer die Karte
// ansieht, hat das Blatt zu. Mit der Waldebene (#213) galt dasselbe
// gleich noch einmal — seither ist die Karte hier EINE Karte für beide
// Ebenen statt zweier Kärtchen, die sich um die Ecke drängeln.
//
// **Warum sie klein bleibt:** Die Karte ist der Inhalt. Deshalb links
// UNTEN (dort ist der einzige freie Rand; rechts stehen die Knöpfe, oben
// die Banner), nur bei aktiver Ebene, und ohne Beschriftung jeder
// einzelnen Stufe.
//
// **Zwei Zustände, kein Menü — und kein Weg mehr.** Bis 1.131.0 schaltete
// ein ✕ die Legende WEG, persistent. Zurück führte ein Schalter
// („Legende in Karte anzeigen"), der in drei Blättern stand und jedes Mal
// nur, wenn die jeweilige Ebene an war: Wer die Legende wegtippte und
// danach alle Ebenen ausschaltete, hatte keinen Rückweg. Das ist
// dieselbe Sorte Sackgasse wie #425 („das X mutet für den ganzen Tag")
// und #349 („das Banner schaltet sich beim Antippen selbst stumm") —
// eine Geste nimmt ein Feature weg, und nirgends steht, wie es
// zurückkommt.
//
// Jetzt klappt sie ein statt zu verschwinden: 40 Pixel Schiene mit
// denselben drei Aussagen senkrecht. **Die Schiene IST der Rückweg**,
// deshalb braucht es keinen Schalter mehr in irgendeinem Blatt — und ein
// Zustand, aus dem man nicht mehr herausfindet, kann gar nicht erst
// entstehen.
//
// **Drei Zonen, drei Sorten von Aussage** (aus dem Entwurf): oben
// DISKRET — die Pilzampel als Daumen, weil „hoch/seitlich/runter" ohne
// Skala lesbar ist; in der Mitte KONTINUIERLICH — Regen und Waldtypen
// als Balken mit Messstrich; unten der WERT — die Höhe als Zahl. Sie
// stehen nicht zusammen, weil sie zufällig alle vier Ebenen sind,
// sondern getrennt, weil man sie verschieden liest.
//
// **Seit 1.200.0 eine vierte: die ZÄHLUNG** — die gemeldeten Fundorte
// als dünne Balken je Gruppe im Umkreis von 5 km (Betreiber,
// 2026-09-23). Sie standen vorher als dritter Balken neben Regen und
// Wald, sahen aus wie eine Skala, waren keine, und liefen mit beiden
// zusammen 11 px aus der Schiene. `test/flows/map_legend_flow_test.dart`
// schaltet deshalb ALLE Ebenen zugleich ein und misst jeden Teil gegen
// den Rahmen.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/app_colors.dart';
import '../../../core/errors.dart';
import '../../../core/settings.dart';
import '../../ampel/ampel_map_providers.dart';
import '../../ampel/ampel_model.dart';
import '../../ampel/ampel_providers.dart';
import '../elevation_providers.dart';
import '../forest_block_providers.dart';
import '../elevation_contour_providers.dart';
import '../forest_data_providers.dart';
import '../forest_fill.dart' show ampelGuenstigAlpha, ampelVerhaltenAlpha;
import '../gbif_fill.dart' show gbifClassColour, gbifClassCountsFrom;
import '../gbif_finds_providers.dart'
    show gbifFilterKeyProvider, gbifFindsProvider, gbifLayerEnabledProvider;
import 'gbif_around_section.dart' show gbifAroundRadiusM;
import '../forest_grid.dart';
import '../rain_data_providers.dart';
import '../rain_fill.dart';
import '../map_overlays.dart';
import '../rain_layer.dart';
import '../../ampel/ampel_season_gate.dart' show ampelNowLine;
import '../../ampel/ampel_species_exclusion.dart';
import '../spot_filter.dart'
    show activeAmpelClassesProvider, currentMonthProvider, selectedAmpelClassesProvider;
import 'here_sheet.dart';

/// Ist die Legende ausgeklappt?
///
/// Muster wie `MapLongPressEnabledNotifier`: Zustand springt sofort,
/// Speichern läuft nach, ein Fehler beim Merken wird nur protokolliert —
/// die Karte darf an einer Einstellung nie scheitern.
class MapLegendOpenNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(settingsProvider).mapLegendOpen;

  void set(bool value) {
    state = value;
    unawaited(ref
        .read(settingsProvider)
        .setMapLegendOpen(value)
        .catchError((Object e, StackTrace stackTrace) {
      logError('Karten-Legende merken', e, stackTrace);
    }));
  }

  void toggle() => set(!state);
}

final mapLegendOpenProvider =
    NotifierProvider<MapLegendOpenNotifier, bool>(MapLegendOpenNotifier.new);

/// Die Kartenmitte beim letzten Kamera-Stillstand (#235) — gesetzt vom
/// Karten-Screen über [MapViewConfig.onCameraIdle], `null` bis zum
/// ersten Stillstand. BEWUSST nicht die laufende Kameraposition: Die
/// Fadenkreuz-Werte rechnen nur, wenn die Karte steht.
final mapIdleCenterProvider = StateProvider<LatLng?>((ref) => null);

/// Meldungen je Ampel-Gruppe im Umkreis des Fadenkreuzes — die Zahlen
/// hinter den GBIF-Balken der Legende. `null`, solange nichts zu zählen
/// ist (Ebene aus, kein Stillstand, Asset noch nicht gelesen).
///
/// **Beobachten ist laden**, deshalb zuerst der Schalter: Nur wenn die
/// Ebene an ist, fasst der Provider das Asset an — und dann hat es die
/// Fläche ohnehin schon gelesen. Ein eigener Provider und nicht im
/// `build` der Legende, weil der Umkreis alle ~150 000 Orte abgeht und
/// die Legende bei jeder Ablesung der anderen Ebenen neu baut; so rechnet
/// er nur, wenn Fadenkreuz, Filter oder Bestand sich ändern.
///
/// Derselbe Radius und dieselbe Umkreis-Regel wie „Was ist hier?"
/// ([gbifAroundRadiusM], `GbifFinds.around`) — zwei Zahlen für „5 km"
/// wären zwei Antworten auf dieselbe Frage.
final legendGbifCountsProvider = Provider<Map<String?, int>?>((ref) {
  if (!ref.watch(gbifLayerEnabledProvider)) return null;
  final center = ref.watch(mapIdleCenterProvider);
  if (center == null) return null;
  final filterKey = ref.watch(gbifFilterKeyProvider);
  final finds = ref.watch(gbifFindsProvider).valueOrNull;
  if (finds == null) return null;
  Set<String> split(String joined) =>
      joined.isEmpty ? const {} : joined.split('|').toSet();
  return gbifClassCountsFrom(
      finds.around(center.latitude, center.longitude,
          radiusM: gbifAroundRadiusM),
      species: split(filterKey.species),
      classes: split(filterKey.classes));
});

class MapLegend extends ConsumerWidget {
  const MapLegend({super.key, this.onOpenLayers});

  /// Der Weg ins Ebenen-Blatt aus der Fußzeile der ausgeklappten
  /// Legende. `null` blendet den Verweis aus — die Legende baut sich
  /// keinen zweiten Weg zur Kamera oder zu einem Blatt, sie drückt nur
  /// stellvertretend einen Knopf, den es schon gibt.
  final VoidCallback? onOpenLayers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Liegt der Vorhang, gibt es nichts zu erklären (#464). Die Legende
    // nennt jede aktive Ebene samt Farbskala — sie weiter aufzuzählen,
    // während die Karte nackt ist, wäre die Behauptung von vier Ebenen,
    // von denen keine zu sehen ist.
    //
    // Und sie verschwindet WORTLOS, statt „ausgeblendet" zu schreiben:
    // Der Sinn des Vorhangs ist eine freie Karte. Ein Hinweis darauf,
    // dass gerade nichts im Weg liegt, läge im Weg. Den Zustand trägt
    // der Knopf in der Werkzeugleiste.
    if (ref.watch(mapOverlaysHiddenProvider)) return const SizedBox.shrink();
    final rainLayer = ref.watch(rainLayerProvider);
    // Regen-Sektion nur zu den eigenen Farben — beim Radar und im
    // Rückfall liegt das DWD-Bild in DWD-Farben auf der Karte, dafür
    // wäre diese Skala schlicht falsch; die richtige steht im Blatt.
    final showRain = rainLayer != RainLayer.off &&
        ref.watch(rainPaintProvider(rainLayer)) != RainPaint.dwd;
    final forestClasses = ref.watch(forestClassesProvider);
    final showForest = ref.watch(forestLayerEnabledProvider) &&
        forestClasses.isNotEmpty &&
        ref.watch(forestGridProvider).valueOrNull != null;
    final showAmpel = ref.watch(ampelPreviewEnabledProvider) &&
        ref.watch(ampelLayerEnabledProvider);
    // Bewusst nur der Schalter und NICHT das Gitter: Ein
    // `ref.watch(elevationGridProvider)` hier packte 3,4 MB bei jedem
    // App-Start aus (siehe map_screen.dart). Ist die Ebene an, aber das
    // Gitter fehlt, bleibt die Zeile bei „wird gerechnet …" — und den
    // echten Grund nennt das Blatt.
    final showContours = ref.watch(contourLayerEnabledProvider);
    // Nur der Schalter, nicht das Asset — aus demselben Grund wie bei
    // den Höhenlinien: Beobachten ist laden.
    final showGbif = ref.watch(gbifLayerEnabledProvider);
    if (!showRain && !showForest && !showAmpel && !showContours && !showGbif) {
      return const SizedBox.shrink();
    }

    // Die Fadenkreuz-Werte (#235): gerechnet an der Mitte des LETZTEN
    // Kamera-Stillstands — nicht an der laufenden Position, das wäre
    // eine Rechnung pro Frame während der Geste. Seit #253 über die
    // kombinierte Sicht: Liegt ein feiner Block unterm Fadenkreuz,
    // zählt der Kilometer auf 100-m-Waben.
    final center = ref.watch(mapIdleCenterProvider);
    final contoursTooFarOut = ref.watch(contourTooFarOutProvider);
    final forest = ref.watch(forestViewProvider);
    final around = (showForest && center != null && forest != null)
        ? forest.broadleafFactorAround(center.latitude, center.longitude)
        : null;
    final rainMm = (showRain && center != null)
        ? ref
            .watch(rainGridProvider(rainLayer))
            .valueOrNull
            ?.mmAt(center.latitude, center.longitude)
        : null;
    // Das Pilzwetter am Fadenkreuz — dieselbe pure Rechnung wie im
    // Spot-Blatt, auf denselben Providern. SAMT Spothöhe: Die Legende
    // war nach 1.93.0 der dritte Abnehmer der Ablesung, der die Höhe
    // nicht übergab — die Fläche malte korrigiert „günstig", die
    // Legende sagte am selben Punkt „ungünstig" (Feldbericht
    // Berchtesgaden, 2026-08-17). Wer hier einen vierten Abnehmer
    // baut: `ampelReadingFrom` verlangt die Höhe nicht per Typ, der
    // Flow-Test „die Legende rechnet mit derselben Höhe" ist das Netz.
    AmpelReading? ampelAt;
    var ampelByClass =
        const <({AmpelClass klass, AmpelReading reading, String? now})>[];
    if (showAmpel && center != null) {
      final at = (lat: center.latitude, lon: center.longitude);
      final course = ref.watch(rainCourseProvider(at));
      final temperature = ref.watch(spotTemperatureProvider(at));
      final spotHeight = ref.watch(elevationAtProvider(at));
      if (!course.isLoading &&
          !temperature.isLoading &&
          !spotHeight.isLoading) {
        // **Die Kopfzeile zeigt das Maximum, die Detailzeilen zeigen
        // jede Klasse einzeln** (Betreiber, 2026-09-12 — und nur in der
        // AUSGEKLAPPTEN Legende; `_AmpelSection` steckt ohnehin nur im
        // `_LegendPanel`). Die Fläche malt dasselbe Maximum, die Regel
        // steht in `ampelBestReadingFrom` und nur dort.
        // Beide Zeilen rechnen mit der GEWÄHLTEN Auswahl (Chips im
        // Filter, 1.142.0) — dieselbe Liste, aus der die Fläche ihr
        // Maximum nimmt. Stünde hier `ampelShippedClasses`, nennte die
        // Legende eine Gruppe, die auf der Karte gar nicht mehr
        // leuchtet; #279 verlangt eine Antwort, nicht zwei.
        // Seit 1.157.0 die AKTIVEN Klassen (#495): Auswahl minus
        // Saison-Tor minus ausgenommene Arten — dieselbe Liste wie die
        // Fläche.
        final selected = ref.watch(activeAmpelClassesProvider);
        final month = ref.watch(currentMonthProvider);
        final excluded = ref.watch(ampelExcludedSpeciesProvider);
        ampelAt = ampelBestReadingFrom(
                course.valueOrNull, temperature.valueOrNull,
                classes: selected, spotHeightM: spotHeight.valueOrNull)
            .reading;
        ampelByClass = [
          for (final klass in selected)
            (
              klass: klass,
              reading: ampelReadingFrom(
                  course.valueOrNull, temperature.valueOrNull,
                  klass: klass, spotHeightM: spotHeight.valueOrNull),
              // Wer die Klasse gerade trägt, wenn es nicht der
              // Namensgeber ist: „Austernseitling & Co." heißt im
              // September Krause Glucke und Leberpilz.
              now: ampelNowLine(klass, month: month, excluded: excluded),
            ),
        ];
      }
    }

    // Dieselbe Auswahl wie die Fläche: Eine abgewählte Gruppe liegt nicht
    // auf der Karte, also steht sie auch nicht in der Legende.
    final shownClasses =
        ref.watch(selectedAmpelClassesProvider).map(ampelClassKeyOf).toSet();
    final gbifKeys = <String?>[
      for (final key in ampelClasses.keys)
        if (shownClasses.contains(key)) key,
      if (shownClasses.length == ampelClasses.length) null,
    ];

    final zones = (
      showAmpel: showAmpel,
      ampel: ampelAt,
      ampelByClass: ampelByClass,
      showRain: showRain,
      rainLayer: rainLayer,
      rainMm: rainMm,
      showForest: showForest,
      forestClasses: forestClasses,
      around: around,
      showContours: showContours,
      equidistanceM: ref.watch(contourEquidistanceProvider),
      // Die Höhe am Fadenkreuz kommt aus demselben Provider wie die
      // Spothöhe der Ampel — eine zweite Ablesung könnte abweichen.
      heightM: (showContours && center != null)
          ? ref
              .watch(elevationAtProvider(
                  (lat: center.latitude, lon: center.longitude)))
              .valueOrNull
          : null,
      contoursTooFarOut: contoursTooFarOut,
      showGbif: showGbif,
      gbifKeys: gbifKeys,
      gbifCounts: showGbif ? ref.watch(legendGbifCountsProvider) : null,
    );
    final open = ref.watch(mapLegendOpenProvider);

    return Padding(
      // Über Maßstab und Quellenhinweis, die beide unten links sitzen.
      // Bündig an den linken Rand: Die Schiene soll wie eine Lasche aus
      // dem Rand kommen, nicht wie ein zweiter freistehender Kasten —
      // davon hat die Karte genug.
      padding: const EdgeInsets.only(bottom: 44),
      child: Material(
        color: AppColors.cream.withValues(alpha: 0.94),
        elevation: 2,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
        child: open
            ? _LegendPanel(
                zones: zones,
                center: center,
                onCollapse: () =>
                    ref.read(mapLegendOpenProvider.notifier).toggle(),
                onOpenLayers: onOpenLayers,
              )
            : _LegendRail(
                zones: zones,
                onExpand: () =>
                    ref.read(mapLegendOpenProvider.notifier).toggle(),
              ),
      ),
    );
  }
}

/// Was die Legende gerade zu sagen hat — einmal gerechnet, von beiden
/// Zuständen gelesen.
///
/// Ein Record und keine zwei Parameterlisten: Schiene und Tafel zeigen
/// DIESELBEN Aussagen in anderer Form. Zwei Listen liefen unweigerlich
/// auseinander, und dann sagte die eingeklappte Legende etwas anderes
/// als die ausgeklappte — über dieselbe Karte.
typedef LegendZones = ({
  bool showAmpel,
  AmpelReading? ampel,

  /// Jede ausgelieferte Klasse einzeln am Fadenkreuz — nur die
  /// AUSGEKLAPPTE Legende zeigt sie (Betreiber, 2026-09-12). Die
  /// eingeklappte Schiene trägt weiter nur den Daumen: Sie ist 40 px
  /// breit, und ein Urteil in Formsprache verträgt keine Aufzählung.
  List<({AmpelClass klass, AmpelReading reading, String? now})> ampelByClass,
  bool showRain,
  RainLayer rainLayer,
  int? rainMm,
  bool showForest,
  Set<ForestClass> forestClasses,
  ({double? factor, double forestShare})? around,
  bool showContours,
  int? equidistanceM,
  int? heightM,
  bool contoursTooFarOut,

  /// Die gemeldeten Fundorte (#467): Ihre Farben sind die Ampel-Gruppen.
  bool showGbif,

  /// Die Gruppen, die die Fläche gerade zeigt, in Tabellenreihenfolge —
  /// `null` steht für „ohne Ampel" und ist nur dabei, wenn ALLE Gruppen
  /// gewählt sind (bei gesetzter Gruppenwahl fallen die grauen Scheiben
  /// heraus).
  List<String?> gbifKeys,

  /// Meldungen je Gruppe im Umkreis — `null` ohne Zählung.
  Map<String?, int>? gbifCounts,
});

/// Die eingeklappte Legende: 40 Pixel, dieselben drei Zonen senkrecht.
///
/// **Sie ist der Rückweg.** Deshalb steht sie immer da, sobald
/// überhaupt eine Ebene liegt — auch wenn von den drei Zonen nur eine
/// etwas zu sagen hat. Eine Schiene, die bei einer einzelnen Ebene
/// verschwände, wäre wieder ein Zustand ohne Ausgang.
class _LegendRail extends StatelessWidget {
  const _LegendRail({required this.zones, required this.onExpand});

  final LegendZones zones;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final bars = <Widget>[
      if (zones.showRain)
        _VerticalScale(
          key: const Key('legend-rail-rain'),
          // Unten wenig, oben viel — die Richtung, in die ein Pegel
          // steigt.
          colours: [
            for (final (index, _) in rainLevelsFor(zones.rainLayer).indexed)
              AppColors.rainLine(index).withAlpha(rainFillAlpha),
          ],
          fraction: zones.rainMm == null
              ? null
              : rainMarkerFraction(
                  zones.rainMm!, rainLevelsFor(zones.rainLayer)),
          topIcon: Icons.water_drop,
          topColour: AppColors.rainLine(rainLevelsFor(zones.rainLayer).length - 1),
          bottomIcon: Icons.water_drop_outlined,
          bottomColour: AppColors.rainLine(0),
          tooltip: zones.rainMm == null
              ? 'Regen'
              : 'Regen · hier ${zones.rainMm} mm',
        ),
      if (zones.showForest)
        _VerticalScale(
          key: const Key('legend-rail-forest'),
          // Oben Laub, unten Nadel — dieselbe Achse wie in der Tafel,
          // dort nur waagerecht von links nach rechts. Deshalb steht
          // die Laubfarbe hier ZULETZT in der Liste: Der Verlauf läuft
          // von unten nach oben.
          colours: [
            for (final forestClass in const [
              ForestClass.conifer,
              ForestClass.mixed,
              ForestClass.broadleaf,
            ])
              forestClassColor(forestClass).withValues(alpha: 0.75),
          ],
          fraction: zones.around?.factor,
          topIcon: Icons.eco,
          topColour: AppColors.forestBroadleaf,
          bottomIcon: Icons.park,
          bottomColour: AppColors.forestConifer,
          tooltip: zones.around?.factor == null
              ? 'Waldtypen'
              : 'Waldtypen · Laubfaktor '
                  '${zones.around!.factor!.toStringAsFixed(2).replaceAll('.', ',')}',
        ),
      // **GBIF steht hier NICHT mehr** (seit 1.200.0). Es stand als
      // dritter Balken daneben — als Farbverlauf der Gruppenfarben, der
      // wie eine Skala „wenig … viel" aussah und keine war. Und mit
      // Regen, Wald und GBIF zugleich lief die Reihe 11 px aus der
      // 40-px-Schiene (Betreiber-Screenshot, 2026-09-23): 3 × 11 + 2 × 7
      // = 47 > 36. Die Fundorte sind eine ZÄHLUNG, keine Skala, und
      // stehen deshalb als eigene Zone darunter ([_RailGbif]).
    ];

    return InkWell(
      onTap: onExpand,
      borderRadius: const BorderRadius.only(
        topRight: Radius.circular(14),
        bottomRight: Radius.circular(14),
      ),
      child: Tooltip(
        message: 'Legende einblenden',
        child: SizedBox(
          width: 40,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 9, 0, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, zone) in [
                  if (zones.showAmpel)
                    _AmpelThumb(
                      key: const Key('legend-ampel-thumb'),
                      level: zones.ampel?.level,
                      size: 24,
                    ),
                  if (bars.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (index, bar) in bars.indexed) ...[
                          if (index > 0) const SizedBox(width: 7),
                          bar,
                        ],
                      ],
                    ),
                  if (zones.showGbif)
                    _RailGbif(
                        key: const Key('legend-rail-gbif'),
                        keys: zones.gbifKeys,
                        counts: zones.gbifCounts),
                ].indexed) ...[
                  if (index > 0) const _RailRule(),
                  zone,
                ],
                if (zones.showContours &&
                    (zones.showAmpel || bars.isNotEmpty || zones.showGbif))
                  const _RailRule(),
                if (zones.showContours)
                  _RailHeight(
                    heightM: zones.heightM,
                    tooFarOut: zones.contoursTooFarOut,
                  ),
                const SizedBox(height: 4),
                const Text('›',
                    style: TextStyle(
                        fontSize: 13, height: 1, color: AppColors.forestGreen)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Die Fundorte in der Schiene: ein dünner Balken je Gruppe, alle auf
/// EINER Achse, gestreckt auf die häufigste (Betreiber, 2026-09-23).
///
/// **Längen, keine Deckkraft.** Der Vorschlag lag auch als Quadrat auf
/// dem Tisch, das von durchsichtig bis zur Gruppenfarbe füllt — aber
/// Deckkraft vergleicht man schlecht, und bei Orange gegen Grau gar
/// nicht. Zwei Balken nebeneinander vergleicht jeder.
///
/// **Die gemeinsame Achse ist relativ**, und das ist Absicht: Die Frage
/// in der Schiene ist „welche Gruppe ist hier gemeldet", nicht „wie
/// viele". Die Zahl steht in der Tafel. Eine leere Spur bleibt stehen —
/// „0" ist eine Auskunft, ein fehlender Balken wäre eine Lücke.
class _RailGbif extends StatelessWidget {
  const _RailGbif({super.key, required this.keys, required this.counts});

  final List<String?> keys;
  final Map<String?, int>? counts;

  static const _height = 26.0;

  @override
  Widget build(BuildContext context) {
    final max = [for (final k in keys) counts?[k] ?? 0]
        .fold<int>(0, (a, b) => b > a ? b : a);
    return Tooltip(
      message: counts == null
          ? 'Gemeldete Fundorte'
          : max == 0
              ? 'Keine Meldung im Umkreis von 5 km'
              : 'Gemeldet im Umkreis von 5 km',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.place, size: 11, color: gbifClassColour('herbst')),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (index, key) in keys.indexed) ...[
                if (index > 0) const SizedBox(width: 2),
                _RailGbifBar(
                  colour: gbifClassColour(key),
                  fraction: max == 0 ? 0 : (counts?[key] ?? 0) / max,
                  height: _height,
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text('5 km',
              style: TextStyle(
                  fontSize: 7.5,
                  height: 1,
                  color: AppColors.barkBrown.withValues(alpha: 0.8))),
        ],
      ),
    );
  }
}

class _RailGbifBar extends StatelessWidget {
  const _RailGbifBar(
      {required this.colour, required this.fraction, required this.height});

  final Color colour;
  final double fraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Mindestens 2 px, sobald überhaupt gemeldet ist: Sonst sähe eine
    // einzelne Meldung neben hundert aus wie keine.
    final filled =
        fraction <= 0 ? 0.0 : (fraction * height).clamp(2.0, height);
    return Container(
      width: 4,
      height: height,
      alignment: Alignment.bottomCenter,
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(1.5),
      ),
      child: Container(
        width: 4,
        height: filled,
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(1.5),
        ),
      ),
    );
  }
}

/// Die Trennlinie zwischen zwei Zonen der Schiene.
class _RailRule extends StatelessWidget {
  const _RailRule();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
            width: 22,
            height: 1,
            color: AppColors.barkBrown.withValues(alpha: 0.18)),
      );
}

/// Die Höhe in der Schiene: Zahl und Einheit übereinander.
///
/// Die Einheit steht unter der Zahl und nicht daneben, weil 40 Pixel
/// für „220 m" in lesbarer Größe nicht reichen — und die ZAHL ist die
/// Aussage.
class _RailHeight extends StatelessWidget {
  const _RailHeight({required this.heightM, required this.tooFarOut});

  final int? heightM;
  final bool tooFarOut;

  @override
  Widget build(BuildContext context) {
    if (heightM == null) {
      return Icon(Icons.terrain,
          size: 15,
          color: AppColors.contourLine
              .withValues(alpha: tooFarOut ? 0.4 : 1));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$heightM',
            style: const TextStyle(
                fontSize: 11,
                height: 1.1,
                fontWeight: FontWeight.bold,
                color: AppColors.barkBrown)),
        const Text('m',
            style: TextStyle(
                fontSize: 8.5, height: 1.1, color: AppColors.barkBrown)),
      ],
    );
  }
}

/// Ein senkrechter Farbbalken mit Messstrich und Symbolen an beiden
/// Enden — die eingeklappte Fassung von [_RainSection] und
/// [_ForestSection].
///
/// **Die Symbole sind nicht Zierde, sondern der Ersatz für die Achse.**
/// Ausgeklappt steht unter jedem Balken „10 mm … 150+ mm" bzw.
/// „Laub … Nadel". Auf 9 Pixel Breite passt kein Wort; ohne die beiden
/// Symbole wäre der Balken ein hübscher Farbverlauf ohne Richtung.
class _VerticalScale extends StatelessWidget {
  const _VerticalScale({
    super.key,
    required this.colours,
    required this.fraction,
    required this.topIcon,
    required this.topColour,
    required this.bottomIcon,
    required this.bottomColour,
    required this.tooltip,
  });

  /// Die Farben von UNTEN nach OBEN.
  final List<Color> colours;

  /// Wo der Messwert liegt, 0 = unten … 1 = oben. `null` lässt den
  /// Strich weg — dieselbe Regel wie in der Tafel: Kein Strich ohne
  /// Ablesung, sonst behauptet er eine Stufe, die niemand gemessen hat.
  final double? fraction;

  final IconData topIcon;
  final Color topColour;
  final IconData bottomIcon;
  final Color bottomColour;
  final String tooltip;

  static const _height = 46.0;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(topIcon, size: 11, color: topColour),
          const SizedBox(height: 3),
          SizedBox(
            width: 9,
            height: _height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: colours,
                    ),
                  ),
                  child: const SizedBox(width: 9, height: _height),
                ),
                if (fraction != null)
                  Positioned(
                    left: -2,
                    right: -2,
                    bottom: (fraction!.clamp(0.0, 1.0) * _height)
                        .clamp(1.0, _height - 1),
                    child: Container(height: 2, color: AppColors.barkBrown),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Icon(bottomIcon, size: 11, color: bottomColour),
        ],
      ),
    );
  }
}

/// Die ausgeklappte Legende.
class _LegendPanel extends StatelessWidget {
  const _LegendPanel({
    required this.zones,
    required this.center,
    required this.onCollapse,
    required this.onOpenLayers,
  });

  final LegendZones zones;
  final LatLng? center;
  final VoidCallback onCollapse;
  final VoidCallback? onOpenLayers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Schmaler und enger als bis 1.199.0 (236 px, 12/10 Rand): Mit allen
    // Ebenen deckte die Tafel auf einem 411-dp-Telefon 57 % der Breite
    // und reichte bis ans Fadenkreuz („zu wuchtig", Betreiber,
    // 2026-09-23). Die breitesten Zeilen sind die Ampel-Tabelle
    // (58 + 3 × 32 px) und die Regenskala; beide passen. 192 und nicht
    // mehr: Bei 208 stieß der rechte Rand auf einem 411-dp-Telefon ans
    // Fadenkreuz in der Bildschirmmitte.
    //
    // **Scrollbar, sobald sie nicht in die Höhe passt.** Mit allen fünf
    // Ebenen braucht die Tafel rund 360 px — im Querformat oder auf
    // einem kleinen Telefon ist das mehr, als zwischen Bannern und
    // Maßstab liegt, und dann schnitt die Spalte unten ab (ein Test mit
    // allen Ebenen auf 800 × 600 hat es gezeigt). Passt alles, verhält
    // sich die Scrollfläche wie ein gewöhnlicher Kasten.
    return SizedBox(
      width: 192,
      child: SingleChildScrollView(
        child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Keine Zahl mehr („Legende · 3 Ebenen"): Sie zählte GBIF
                // nicht mit und sagte bei vier Ebenen „3" — und wer die
                // Tafel ansieht, sieht die Abschnitte ohnehin.
                Expanded(
                  child: Text(
                    'Legende',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                // Kein ✕ mehr, sondern ein ‹: Das Zeichen sagt, was
                // passiert. Ein ✕ verspricht „weg", und genau das
                // Versprechen war die Sackgasse.
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    tooltip: 'Legende einklappen',
                    icon: const Icon(Icons.chevron_left,
                        color: AppColors.forestGreen),
                    onPressed: onCollapse,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            if (zones.showAmpel) ...[
              // Mit der Ampel wird die Waldskala zur dritten Zeile IHRER
              // Tabelle: Wo nichts leuchtet, bleibt die Wabe in
              // Waldfarbe, und die Spalten Laub · Misch · Nadel sind
              // dieselben. Zwei Abschnitte mit derselben Achse waren der
              // größte Posten der Höhe.
              _AmpelSection(
                  reading: zones.ampel,
                  byClass: zones.ampelByClass,
                  forest: zones.showForest
                      ? (classes: zones.forestClasses, around: zones.around)
                      : null),
              const SizedBox(height: 8),
            ],
            if (zones.showRain) ...[
              _RainSection(layer: zones.rainLayer, mm: zones.rainMm),
              const SizedBox(height: 8),
            ],
            if (zones.showForest && !zones.showAmpel) ...[
              _ForestSection(
                  classes: zones.forestClasses, around: zones.around),
              const SizedBox(height: 8),
            ],
            if (zones.showGbif) ...[
              _GbifSection(keys: zones.gbifKeys, counts: zones.gbifCounts),
              const SizedBox(height: 8),
            ],
            if (zones.showContours) ...[
              _HeightBlock(
                heightM: zones.heightM,
                equidistanceM: zones.equidistanceM,
                tooFarOut: zones.contoursTooFarOut,
              ),
              const SizedBox(height: 8),
            ],
            // Bis 1.199.0 stand hier eine Trennlinie mit Abstand — eine
            // eigene Zeile nur fürs Absetzen der Verweise.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // „Was ist hier?" war bis 1.131.0 ein Tipp auf die
                // Werte selbst — unsichtbar, solange man ihn nicht
                // zufällig traf. Jetzt steht er da.
                if (center != null)
                  // `Flexible` an BEIDEN Verweisen: Die Tafel ist 236
                  // Pixel breit, und „Was ist hier? →" plus „Ebenen"
                  // laufen darin über — beim Bauen als
                  // RenderFlex-Überlauf von 45 Pixeln aufgeschlagen.
                  // Ein Überlauf ist kein Schönheitsfehler, sondern ein
                  // Verweis, den niemand trifft.
                  Flexible(
                    child: InkWell(
                      onTap: () => showHereSheet(context, center!),
                      child: Text('Was ist hier? →',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                  )
                else
                  const SizedBox.shrink(),
                if (onOpenLayers != null)
                  Flexible(
                    child: InkWell(
                      onTap: onOpenLayers,
                      child: Text('Ebenen',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.barkBrown
                                  .withValues(alpha: 0.7))),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Die Pilzampel als DAUMEN — hoch, seitlich, runter.
///
/// **Warum kein Ampelbild.** Drei Lampen beantworten die Frage nicht,
/// die man hat: Welche der drei ist gut? Man muss die Reihenfolge
/// kennen, um sie zu lesen. Ein Daumen trägt sein Urteil in der Form,
/// und eingeklappt ist er damit die ganze Aussage — ohne dass eine
/// Skala danebenstehen muss.
///
/// Material hat keinen seitlichen Daumen; der ist ein um 90° gedrehter
/// `thumb_up`. Die Farben sind dieselben, mit denen die Waben leuchten,
/// damit Symbol und Fläche dasselbe sagen.
class _AmpelThumb extends StatelessWidget {
  const _AmpelThumb({super.key, required this.level, this.size = 20});

  final AmpelLevel? level;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, turns, colour) = switch (level) {
      AmpelLevel.guenstig => (Icons.thumb_up, 0.0, AppColors.ampelStrong),
      AmpelLevel.verhalten => (Icons.thumb_up, -0.25, AppColors.ampelMild),
      AmpelLevel.unguenstig => (Icons.thumb_down, 0.0, AppColors.warmBrown),
      // Solange gerechnet wird, gibt es kein Urteil — und ein
      // waagerechter Daumen wäre eins.
      null => (Icons.hourglass_empty, 0.0, AppColors.barkBrown),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Center(
        child: RotatedBox(
          quarterTurns: (turns * 4).round(),
          child: Icon(icon, size: size * 0.62, color: colour),
        ),
      ),
    );
  }
}

/// Die Höhe als WERT — abgesetzt von den Skalen darüber.
///
/// Sie stand bis 1.131.0 in derselben Reihe wie Ampel, Regen und Wald,
/// als wäre sie dieselbe Sorte Aussage. Ist sie nicht: Die drei darüber
/// sind Einordnungen auf einer Skala, das hier ist eine Zahl. Deshalb
/// unten, abgesetzt und groß.
class _HeightBlock extends StatelessWidget {
  const _HeightBlock({
    required this.heightM,
    required this.equidistanceM,
    required this.tooFarOut,
  });

  final int? heightM;
  final int? equidistanceM;
  final bool tooFarOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = tooFarOut
        ? 'erst näher dran'
        : equidistanceM == null
            ? 'wird gerechnet …'
            : 'Linien alle $equidistanceM m';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.contourLine.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.terrain, size: 14, color: AppColors.contourLine),
          const SizedBox(width: 8),
          if (heightM != null) ...[
            Text('$heightM m',
                style: const TextStyle(
                    fontSize: 14,
                    height: 1,
                    fontWeight: FontWeight.bold,
                    color: AppColors.barkBrown)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              heightM == null ? 'Höhenlinien · $note' : 'Höhe hier\n$note',
              style: _tick(theme),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wo auf der Stufenskala ein Messwert liegt, als Anteil 0..1 — `null`
/// unterhalb der ersten Stufe (dort ist die Karte farblos, ein Strich
/// am Skalenanfang behauptete sonst „mindestens Stufe eins").
///
/// Innerhalb eines Bandes linear, oberhalb der letzten Stufe ans Ende
/// geklemmt — die Skala endet dort ohnehin mit „+".
double? rainMarkerFraction(int mm, List<int> levels) {
  if (levels.isEmpty || mm < levels.first) return null;
  for (var i = levels.length - 1; i >= 0; i--) {
    if (mm >= levels[i]) {
      if (i == levels.length - 1) return 1;
      final band = (mm - levels[i]) / (levels[i + 1] - levels[i]);
      return (i + band) / levels.length;
    }
  }
  return null;
}

/// Die Pilzwetter-Zeile der Legende: das Wort am Fadenkreuz plus das
/// RASTER der Leuchtfarben — „ungünstig" hat bewusst keine Zeile, denn
/// dort leuchtet nichts, die Wabe bleibt schlicht Wald („keine Stufe
/// heißt aussichtslos").
///
/// **Ein Raster und keine zwei Chips mehr** (seit 1.80.0): Solange alle
/// leuchtenden Waben denselben Ton trugen, reichten zwei Farbtupfer.
/// Jetzt trägt der Farbton die Waldklasse und die Deckkraft die Stufe —
/// eine Legende mit nur zwei Chips würde das Blau über Nadelwald
/// unerklärt lassen, und wer die Skala nicht kennt, liest Blau als
/// „mehr" statt als „Nadelwald".
class _AmpelSection extends StatelessWidget {
  const _AmpelSection(
      {required this.reading, required this.byClass, this.forest});

  /// Das Maximum über die Klassen — dieselbe Antwort, die die Fläche
  /// malt.
  final AmpelReading? reading;

  /// Jede ausgelieferte Klasse einzeln, für die Detailzeilen.
  final List<({AmpelClass klass, AmpelReading reading, String? now})>
      byClass;

  /// Die Waldskala als dritte Zeile (seit 1.200.0) — `null`, wenn die
  /// Waldebene aus ist. Dieselben Farben, dieselbe Deckkraft und
  /// derselbe Messstrich wie [_ForestSection]; nur ohne eigene
  /// Überschrift und ohne „Laub … Nadel", denn die Spalten darüber
  /// heißen schon so.
  final ({
    Set<ForestClass> classes,
    ({double? factor, double forestShare})? around,
  })? forest;

  /// Die Spalten in der Reihenfolge von [AppColors.ampelCombined] —
  /// dieselbe wie `ForestClass` ohne `none`.
  static const _classWords = ['Laub', 'Misch', 'Nadel'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = reading?.level;
    final small = theme.textTheme.labelSmall
        ?.copyWith(fontSize: 9, color: AppColors.barkBrown);
    // Graue Ablesungen fallen heraus: Grau heißt „keine Aussage", und
    // eine Klasse ohne Aussage neben einer mit läse sich wie ein
    // Unterschied zwischen den Klassen. Grau liegt aber am ORT und
    // trifft dann alle.
    final details = [
      for (final entry in byClass)
        if (entry.reading.level != null) entry,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Kopfzeile: links WAS, rechts der Wert am Fadenkreuz — dasselbe
        // Muster wie bei Regen und Wald darunter. Vorher stand beides in
        // einem Satz; damit war der Wert dort, wo man ihn zuletzt sucht,
        // nämlich mitten im Text.
        //
        // Der Daumen steht auch hier, nicht nur in der Schiene: Wer
        // einklappt, soll dasselbe Zeichen wiedererkennen und nicht
        // erst lernen, wofür es steht.
        Row(
          children: [
            _AmpelThumb(
                key: const Key('legend-ampel-thumb'),
                level: level,
                size: 20),
            const SizedBox(width: 6),
            // Der Titel darf kürzen, der Wert nie: In 192 px stehen
            // Daumen, „Pilzampel · exp." und „hier: ungünstig" nicht
            // nebeneinander (rund 189 px in Roboto) — genau dann liefe die
            // Zeile über, wenn die Ampel abrät. „hier:" ist deshalb
            // weggefallen; den Ortsbezug trägt der Daumen davor.
            Expanded(
              child: Text('Pilzampel · exp.',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                      fontSize: 10.5)),
            ),
            const SizedBox(width: 4),
            Text(
              level == null ? 'rechnet …' : ampelLevelWord(level),
              key: const Key('legend-ampel-here'),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: AppColors.barkBrown, fontSize: 10.5),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 58),
            for (final word in _classWords)
              SizedBox(width: 32, child: Text(word, style: small)),
          ],
        ),
        // Genau die Töne und Stärken, mit denen der Zeichner die Waben
        // leuchten lässt — die Legende erklärt die Karte.
        for (final (word, alpha, strong, rowLevel) in [
          ('verhalten', ampelVerhaltenAlpha, false, AmpelLevel.verhalten),
          ('günstig', ampelGuenstigAlpha, true, AmpelLevel.guenstig),
        ])
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 58,
                  // Derselbe Daumen wie oben, klein vor der Zeile: Das
                  // Raster entschlüsselt die FARBEN auf der Karte, die
                  // Kopfzeile sagt den ZUSTAND hier — zwei verschiedene
                  // Fragen. Der Daumen verbindet sie, statt sie
                  // nebeneinanderzustellen.
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RotatedBox(
                        quarterTurns: rowLevel == AmpelLevel.verhalten ? -1 : 0,
                        child: Icon(Icons.thumb_up,
                            size: 10,
                            color: rowLevel == AmpelLevel.verhalten
                                ? AppColors.ampelMild
                                : AppColors.ampelStrong),
                      ),
                      const SizedBox(width: 4),
                      Flexible(child: Text(word, style: small)),
                    ],
                  ),
                ),
                for (final pair in AppColors.ampelCombined)
                  SizedBox(
                    width: 32,
                    child: Container(
                      width: 26,
                      height: 11,
                      decoration: BoxDecoration(
                        color: (strong ? pair.$2 : pair.$1)
                            .withValues(alpha: alpha / 255),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (forest case final forest?) ...[
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 58, child: Text('Wald', style: small)),
                // 32 wie die Spalten darüber: Die Skala liegt unter
                // Laub · Misch · Nadel, nicht daneben.
                _ForestScale(
                    classes: forest.classes,
                    factor: forest.around?.factor,
                    segmentWidth: 32,
                    height: 11),
              ],
            ),
          ),
          // Über die volle Breite, nicht unter der Skala eingerückt: Dort
          // brach „1 km: Laubfaktor 0,90 · Wald 100 %" um.
          if (forestAroundLine(forest.around) case final line?)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(line, style: small?.copyWith(fontSize: 8.5)),
            ),
        ],
        // **Je Klasse eine Zeile — nur hier, in der ausgeklappten
        // Legende** (Betreiber, 2026-09-12). Die Kopfzeile oben nennt
        // das Maximum, das auch die Fläche malt; erst hier steht, WELCHE
        // Gruppe es trägt. Ohne diese Zeilen behauptet die Karte „hier
        // ist günstig", ohne sagen zu können, für wen — und seit es
        // Klassen gibt, ist das eine Auslassung und keine Kürze.
        if (details.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('am Fadenkreuz',
              style: small?.copyWith(color: theme.hintColor)),
          for (final entry in details) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(entry.klass.name,
                        style: small, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 6),
                  Text(ampelLevelWord(entry.reading.level!),
                      style: small?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: switch (entry.reading.level!) {
                            AmpelLevel.unguenstig => AppColors.barkBrown,
                            AmpelLevel.verhalten => AppColors.ampelMild,
                            AmpelLevel.guenstig => AppColors.ampelStrong,
                          })),
                ],
              ),
            ),
            if (entry.now case final now?)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(now,
                    style: small?.copyWith(color: theme.hintColor),
                    overflow: TextOverflow.ellipsis),
              ),
          ],
        ],
        // **Hier steht bewusst KEINE Evidenzstufe** (N7, versucht und
        // zurückgenommen am 2026-09-19). Zwei Gründe, und der zweite
        // wiegt schwerer:
        //
        // Eine Klasse hat keine Stufe — ihre Mitglieder sind verschieden
        // gut belegt, in der Herbstklasse steht die Herbsttrompete auf
        // „vorläufig" und vier Arten auf „belegt". Und die Legende hat
        // dafür kein Höhenbudget: Eine zusätzliche Zeile lief um 19 px
        // über, was `ampel_flow_test.dart` sofort gemeldet hat.
        //
        // Die Zeile auf Feature-Ebene steht deshalb dort, wo eine Art
        // genannt wird — unter den Ampel-Zeilen im Spot-Blatt und in
        // „Was ist hier?" (`ampel_section.dart`).
      ],
    );
  }
}

class _RainSection extends ConsumerWidget {
  const _RainSection({required this.layer, required this.mm});

  final RainLayer layer;

  /// Der Wert am Fadenkreuz (#235) — `null` ohne Gitter oder außerhalb.
  final int? mm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levels = rainLevelsFor(layer);
    final theme = Theme.of(context);
    final barWidth = 16.0 * levels.length;
    final fraction = mm == null ? null : rainMarkerFraction(mm!, levels);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // Der Messwert direkt im Titel — die Zahl zum Strich unten.
          mm == null ? layer.label : '${layer.label} · hier $mm mm',
          // Grün wie die anderen Überschriften seit dem
          // Betreiber-Vorschlag 2026-08-05; die Ticks darunter bleiben
          // barkBrown — Text auf Cream, beide Themen.
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: barWidth,
          height: 11,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (index, _) in levels.indexed)
                      Container(
                        width: 16,
                        height: 9,
                        color: AppColors.rainLine(index)
                            .withAlpha(rainFillAlpha),
                      ),
                  ],
                ),
              ),
              // Der Strich zum Fadenkreuz-Wert (#235).
              if (fraction != null)
                Positioned(
                  key: const Key('legend-rain-marker'),
                  left: (fraction * barWidth).clamp(1.0, barWidth - 1) - 1,
                  top: -1,
                  child: Container(
                      width: 2, height: 13, color: AppColors.barkBrown),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: barWidth,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Nur die Enden der Skala. Jede Stufe zu beziffern hieße
              // acht Zahlen auf 130 Bildpunkten — die stünden
              // übereinander, und die genauen Werte stehen ohnehin an den
              // Bandgrenzen in der Karte. An der BALKENBREITE ausgerichtet
              // statt mit einem festen Abstand von 34 px: Der rechnete mit
              // der Breite der Beschriftung und lief in einer
              // breiteren Schrift über.
              Text('${levels.first}', style: _tick(theme)),
              Text('${levels.last}+ mm', style: _tick(theme)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Die eingeblendeten Waldklassen — nur die gewählten (#231): Eine
/// Legende, die Farben erklärt, die gerade gar nicht auf der Karte
/// liegen, wäre eine kleine Lüge.
/// Die Wald-Sektion als SKALA von Laub (links) nach Nadel (rechts) —
/// seit #235 mit dem Messstrich des Fadenkreuz-Umkreises direkt darauf.
/// Abgewählte Klassen (#231) bleiben als blasse Segmente stehen: Die
/// Skala ist die Achse des Laubfaktors, sie darf keine Lücken haben —
/// aber sie sagt ehrlich, welche Farben gerade NICHT auf der Karte
/// liegen.
class _ForestSection extends StatelessWidget {
  const _ForestSection({required this.classes, required this.around});

  final Set<ForestClass> classes;

  /// Ergebnis von [ForestGrid.broadleafFactorAround] am Fadenkreuz —
  /// `null` ohne Stillstand oder außerhalb der Abdeckung.
  final ({double? factor, double forestShare})? around;

  static const _segmentWidth = 36.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const barWidth = _segmentWidth * 3;
    final line = forestAroundLine(around);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          line == null ? 'Waldtypen' : 'Waldtypen · $line',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 3),
        _ForestScale(
            classes: classes,
            factor: around?.factor,
            segmentWidth: _segmentWidth,
            height: 11),
        const SizedBox(height: 2),
        SizedBox(
          width: barWidth,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Laub', style: _tick(theme)),
              Text('Nadel', style: _tick(theme)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Der Umkreis-Satz zur Waldskala — `null` ohne Ablesung.
///
/// Der Umkreis steht dabei: „Laubfaktor 0,43" ohne Bezugsgröße liest
/// sich wie eine Aussage über den Punkt unter dem Fadenkreuz — gemeint
/// ist die Umgebung.
String? forestAroundLine(({double? factor, double forestShare})? around) =>
    switch (around) {
      null => null,
      (factor: null, forestShare: _) => '1 km: kein Wald',
      (:final factor?, :final forestShare) => '1 km: Laubfaktor '
          '${factor.toStringAsFixed(2).replaceAll('.', ',')}'
          ' · Wald ${(forestShare * 100).round()} %',
    };

/// Die Waldskala Laub → Nadel mit dem Messstrich des Laubfaktors (#235)
/// — dieselbe Skala im eigenen Abschnitt und als Zeile der
/// Ampel-Tabelle. Abgewählte Klassen (#231) bleiben als blasse
/// Segmente stehen: Die Skala ist die Achse des Laubfaktors, sie darf
/// keine Lücken haben — aber sie sagt ehrlich, welche Farben gerade
/// NICHT auf der Karte liegen.
class _ForestScale extends StatelessWidget {
  const _ForestScale({
    required this.classes,
    required this.factor,
    required this.segmentWidth,
    required this.height,
  });

  final Set<ForestClass> classes;
  final double? factor;
  final double segmentWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final barWidth = segmentWidth * 3;
    return SizedBox(
      width: barWidth,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final forestClass in const [
                  ForestClass.broadleaf,
                  ForestClass.mixed,
                  ForestClass.conifer,
                ])
                  Container(
                    width: segmentWidth,
                    height: height - 2,
                    color: forestClassColor(forestClass).withValues(
                        alpha: classes.contains(forestClass) ? 0.55 : 0.15),
                  ),
              ],
            ),
          ),
          // Der Messstrich (#235): Faktor 1 = Laub = linkes Ende.
          if (factor != null)
            Positioned(
              key: const Key('legend-forest-marker'),
              left: ((1 - factor!) * barWidth).clamp(1.0, barWidth - 1) - 1,
              top: -1,
              child: Container(
                  width: 2, height: height + 2, color: AppColors.barkBrown),
            ),
        ],
      ),
    );
  }
}

TextStyle? _tick(ThemeData theme) => theme.textTheme.labelSmall
    ?.copyWith(color: AppColors.barkBrown, fontSize: 9);

/// Die Farbe einer Waldklasse — EINE Stelle für Blatt, Legende und
/// Fläche, damit nichts auseinanderläuft.
Color forestClassColor(ForestClass forestClass) => switch (forestClass) {
      ForestClass.broadleaf => AppColors.forestBroadleaf,
      ForestClass.mixed => AppColors.forestMixed,
      ForestClass.conifer => AppColors.forestConifer,
      ForestClass.none => AppColors.forestGreen, // nie gezeichnet
    };

// **`_ContourSection` ist entfallen.** Sie war die Höhenzeile in der
// Reihe mit Ampel, Regen und Wald — als wäre eine Höhe dieselbe Sorte
// Aussage wie eine Einordnung auf einer Skala. `_HeightBlock` weiter
// oben hat sie abgelöst und setzt sie ab: eigener Kasten, große Zahl,
// unten. Die Äquidistanz kommt weiter aus dem ERGEBNIS und nicht aus
// der Zoomregel — reißt die Punktschranke, liegt Gröberes auf der
// Karte, als gewünscht war.

/// Die Fundorte-Legende (#467): eine Farbe je Ampel-Gruppe, dazu Grau
/// für Arten ohne Gruppe. Dieselbe Tabelle wie beim Malen — und nur
/// die Gruppen, die der Filter gerade zeigt: Eine abgewählte Gruppe
/// liegt nicht auf der Karte, also steht sie auch nicht in der Legende
/// (dieselbe Regel wie bei der Ampel). Die grauen Scheiben fallen mit
/// jeder Abwahl heraus, ihr Punkt also auch.
class _GbifSection extends StatelessWidget {
  const _GbifSection({required this.keys, required this.counts});

  final List<String?> keys;

  /// Meldungen je Gruppe im Umkreis — `null`, solange nicht gezählt ist.
  /// Dann stehen die Gruppen ohne Balken da, wie vor 1.200.0.
  final Map<String?, int>? counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.labelSmall
        ?.copyWith(fontSize: 9, color: AppColors.barkBrown);
    final max = [for (final k in keys) counts?[k] ?? 0]
        .fold<int>(0, (a, b) => b > a ? b : a);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Gemeldete Fundorte (GBIF)',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontSize: 10,
                  )),
            ),
            if (counts != null) Text('5 km', style: small),
          ],
        ),
        // Der Satz „Scheibe = eine Meldung, so groß wie ihre
        // Genauigkeit" stand bis 1.199.0 hier, über zwei Zeilen. Er
        // steht im Blatt der Ebene, und dort liest ihn, wer die Ebene
        // einschaltet; hier erklärte er bei jedem Blick dasselbe.
        for (final key in keys)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: gbifClassColour(key).withValues(alpha: 0.75),
                      shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                      key == null ? 'ohne Ampel' : ampelClasses[key]!.name,
                      style: small,
                      overflow: TextOverflow.ellipsis),
                ),
                if (counts != null) ...[
                  _GbifBar(
                      colour: gbifClassColour(key),
                      fraction: max == 0 ? 0 : (counts![key] ?? 0) / max),
                  SizedBox(
                    width: 22,
                    child: Text('${counts![key] ?? 0}',
                        textAlign: TextAlign.right, style: small),
                  ),
                ],
              ],
            ),
          ),
        if (counts != null && max == 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('keine Meldung im Umkreis',
                style: small?.copyWith(color: theme.hintColor)),
          ),
      ],
    );
  }
}

/// Ein waagerechter Balken der GBIF-Tafel — dieselbe relative Achse wie
/// in der Schiene ([_RailGbif]), nur liegend und mit Zahl daneben.
class _GbifBar extends StatelessWidget {
  const _GbifBar({required this.colour, required this.fraction});

  final Color colour;
  final double fraction;

  static const _width = 36.0;

  @override
  Widget build(BuildContext context) {
    final filled = fraction <= 0 ? 0.0 : (fraction * _width).clamp(2.0, _width);
    return Container(
      width: _width,
      height: 6,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(1.5),
      ),
      child: Container(
        width: filled,
        height: 6,
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(1.5),
        ),
      ),
    );
  }
}
