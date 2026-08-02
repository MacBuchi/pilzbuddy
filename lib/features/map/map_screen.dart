import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;

import '../offline_maps/offline_map_providers.dart';

import '../../core/errors.dart';
import '../../core/mushroom_species.dart';
import '../../core/update_check.dart';
import '../../core/widgets/mushroom_avatar.dart';
import '../../core/widgets/mushroom_icon.dart';
import '../../data/providers.dart';
import '../../models/friend_location.dart';
import '../../models/spot.dart';
import '../friends/friend_providers.dart';
import '../profile/profile_providers.dart';
import '../spots/spot_providers.dart';
import '../spots/widgets/spot_detail_sheet.dart';
import 'finite_camera_constraint.dart';
import 'live_share_providers.dart';
import 'position_provider.dart';
import 'spot_filter.dart';
import 'widgets/add_spot_sheet.dart';
import 'widgets/map_banners.dart';
import 'widgets/share_location_sheet.dart';
import 'widgets/spot_filter_sheet.dart';
import '../../core/app_colors.dart';

/// Fabrik für den Karten-Kachel-Provider. Tests ersetzen sie durch einen
/// Offline-Fake, damit keine echten OSM-Requests laufen.
///
/// `NetworkTileProvider` aus flutter_map selbst statt des früheren
/// `CancellableNetworkTileProvider`: Beides, was dessen Paket beitrug, ist
/// inzwischen eingebaut — überholte Anfragen werden abgebrochen
/// (`abortObsoleteRequests`, Vorgabe) und geladene Kacheln landen in einem
/// Platten-Cache (`BuiltInMapCachingProvider`, Vorgabe, bis 1 GB). Der
/// Cache ist hier der eigentliche Gewinn: Beim zweiten Besuch einer
/// Gegend steht die Karte sofort, und bei schwachem Empfang bleibt das
/// zuletzt Gesehene sichtbar, statt grau zu werden. Das alte Paket ist
/// upstream als „prepare for deprecation" markiert.
final tileProviderFactoryProvider =
    Provider<TileProvider Function()>((ref) => NetworkTileProvider.new);

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
  final _mapController = MapController();

  /// GENAU EINE Provider-Instanz pro Karten-Screen: flutter_map entsorgt
  /// den TileProvider nur beim Layer-Dispose — eine neue Instanz je
  /// Rebuild (Positions-Ticks!) würde bei jeder Bewegung einen
  /// HTTP-Client samt Verbindungen leaken (#Karten-Freezes).
  late final _tileProvider = ref.read(tileProviderFactoryProvider)();

  // Fallback: Mitte Deutschlands, bis die GPS-Position bekannt ist.
  static const _fallbackCenter = LatLng(51.1634, 10.4477);
  static const _fallbackZoom = 6.5;

  // Grenzen des Karten-Zooms — 19 ist die höchste Stufe, für die es sowohl
  // OSM-Kacheln als auch Offline-Vektordaten gibt (siehe VectorTileLayer).
  static const _minZoom = 3.0;
  static const _maxZoom = 19.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mapController.dispose();
    super.dispose();
  }

  /// Android hält die App lange im Hintergrund am Leben — beim
  /// Zurückkehren alles neu laden, damit z. B. neue Freundes-Spots
  /// und Anfragen ohne App-Neustart erscheinen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshData();
  }

  void _refreshData() {
    ref.invalidate(mySpotsProvider);
    ref.invalidate(friendSpotsProvider);
    ref.invalidate(friendshipsProvider);
    ref.invalidate(updateInfoProvider);
    // Karten-Abo: prüfen, ob es neuere Offline-Karten gibt.
    ref.invalidate(availableMapsProvider);
    ref.invalidate(installedMapsProvider);
  }

  Future<Position?> _currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _centerOnMe() async {
    final position = await _currentPosition();
    if (position == null) {
      _showMessage('Standort nicht verfügbar. Berechtigung erteilt?');
      return;
    }
    _mapController.move(LatLng(position.latitude, position.longitude), 15);
    // Berechtigung wurde ggf. gerade erteilt → Live-Marker starten.
    ref.invalidate(positionStreamProvider);
  }

  /// Sheet zum Starten/Verlängern/Beenden des Standort-Teilens.
  Future<void> _openShareSheet() async {
    final expiresAt = ref.read(myShareProvider).valueOrNull;
    final active = ref.read(isSharingProvider);
    final action = await showShareLocationSheet(context,
        active: active, expiresAt: expiresAt);
    if (action == null || !mounted) return;
    final duration = action.duration;
    if (duration == null) {
      await _stopSharing();
    } else {
      await _startSharing(duration);
    }
  }

  Future<void> _startSharing(Duration duration) async {
    // Bevorzugt die bereits laufende Live-Position; sonst einmalig anfragen
    // (fragt ggf. nach der Berechtigung, wie „Meine Position").
    var position = ref.read(positionStreamProvider).valueOrNull;
    position ??= await _currentPosition();
    if (position == null) {
      _showMessage('Standort nicht verfügbar. Berechtigung erteilt?');
      return;
    }
    try {
      await ref.read(myShareProvider.notifier).share(
            duration: duration,
            lat: position.latitude,
            lng: position.longitude,
          );
      // Berechtigung ggf. gerade erteilt → eigenen Live-Marker starten.
      ref.invalidate(positionStreamProvider);
      if (!mounted) return;
      final until = ref.read(myShareProvider).valueOrNull;
      _showMessage(until == null
          ? 'Standort wird geteilt 📍'
          : 'Standort geteilt bis '
              '${TimeOfDay.fromDateTime(until.toLocal()).format(context)} Uhr 📍');
    } catch (e, stackTrace) {
      logError('Standort teilen', e, stackTrace);
      _showMessage(friendlyError(e));
    }
  }

  Future<void> _stopSharing() async {
    try {
      await ref.read(myShareProvider.notifier).stop();
      _showMessage('Standort-Teilen beendet');
    } catch (e, stackTrace) {
      logError('Standort-Teilen beenden', e, stackTrace);
      _showMessage(friendlyError(e));
    }
  }

  /// Bei aktiver Freigabe jede neue Position hochschieben, damit Freunde
  /// die Bewegung sehen. `expires_at` bleibt dabei unverändert.
  void _maybeUploadLocation(Position? position) {
    if (position == null || !ref.read(isSharingProvider)) return;
    final expiresAt = ref.read(myShareProvider).valueOrNull;
    if (expiresAt == null) return;
    ref
        .read(liveShareRepositoryProvider)
        .upsertMyLocation(
          lat: position.latitude,
          lng: position.longitude,
          expiresAt: expiresAt,
        )
        // Ein Positions-Tick, der nach dem Abmelden noch eintrudelt, ist
        // kein Fehler — siehe friendLocationsProvider (Issue #124).
        .catchError((Object e, StackTrace st) {
      if (e is NotSignedInException) return;
      logError('Live-Standort aktualisieren', e, st);
    });
  }

  /// Neuer Spot an der aktuellen Fadenkreuz-Position (Kartenmitte).
  Future<void> _addSpotAtCrosshair() async {
    final center = _mapController.camera.center;
    final ownSpecies = ref.read(ownSpeciesProvider);
    // Ohne `defaultSpecies`: Ein neuer Spot ist meist eine andere Art als
    // der letzte, und die Vorbelegung musste erst gelöscht werden
    // (Issue #155). Beim Wiederbesuch bleibt sie — dort ist die Art des
    // Spots die richtige Annahme (add_find_sheet.dart).
    final data = await showAddSpotSheet(
      context,
      center,
      ownSpecies: ownSpecies,
    );
    if (data == null) return;
    try {
      await ref.read(mySpotsProvider.notifier).addSpot(
            lat: center.latitude,
            lng: center.longitude,
            name: data.name,
            species: data.species,
            count: data.count,
            foundOn: data.foundOn,
            note: data.note,
          );
      _showMessage('Spot gespeichert 🍄');
    } catch (e, stackTrace) {
      logError('Spot speichern', e, stackTrace);
      _showMessage(friendlyError(e));
    }
  }

  /// Beschriftung der Filter-Zeile — nennt beide Bedingungen, sonst
  /// wundert man sich über fehlende Freundes-Spots.
  ///
  /// Ab drei Arten steht die Zahl statt der Namen: Die Zeile teilt sich den
  /// Platz mit den übrigen Bannern, und fünf ausgeschriebene Artnamen
  /// machen daraus einen Absatz.
  String _filterLabel(SpotFilter filter) {
    final names = filter.species.toList()..sort();
    final parts = [
      if (names.length == 1) 'nur ${names.single}',
      if (names.length == 2) 'nur ${names.join(', ')}',
      if (names.length > 2) '${names.length} Arten',
      if (filter.onlyMine) 'nur meine',
    ];
    return '🔍 Gefiltert: ${parts.join(', ')}';
  }

  Marker _spotMarker(Spot spot) {
    return Marker(
      point: spot.position,
      width: 44,
      height: 44,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: () => showSpotDetailSheet(context, spot.id),
        child: Tooltip(
          message: spot.isOwn
              ? spot.displayName
              : '${spot.displayName} (${spot.ownerUsername ?? 'Freund'})',
          child: MushroomIcon(
            seed: stableSeed(spot.id),
            size: 44,
            friend: !spot.isOwn,
            group: groupFor(spot.lastFind?.species),
            species: spot.lastFind?.species,
          ),
        ),
      ),
    );
  }

  /// Live-Standort eines Freundes: sein Avatar mit blauem Ring.
  Marker _friendLocationMarker(FriendLocation loc) {
    return Marker(
      point: loc.position,
      width: 44,
      height: 44,
      child: Tooltip(
        message: '${loc.username ?? 'Freund'} (live)',
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.friendBlue, width: 2.5),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: MushroomAvatar(index: loc.avatar, size: 39),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Gefiltert statt roh (#154): Der Filter gilt für diese Sitzung und
    // steckt in visibleSpotsProvider, damit die Regel testbar bleibt.
    final visible = ref.watch(visibleSpotsProvider);
    final mySpots = visible.mine;
    final friendSpots = visible.friends;
    final filter = ref.watch(spotFilterProvider);
    final friendLocations = ref.watch(friendLocationsProvider).valueOrNull ??
        const <FriendLocation>[];
    final isSharing = ref.watch(isSharingProvider);
    final shareUntil = ref.watch(myShareProvider).valueOrNull;
    // Solange ich teile, jede neue Position hochschieben (Bewegung sichtbar).
    ref.listen(positionStreamProvider,
        (_, next) => _maybeUploadLocation(next.valueOrNull));
    // Offline-Layer nur, wenn eingeschaltet UND Karte + Style geladen werden
    // konnten — sonst immer Online-OSM (Sicherheitsnetz um den Beta-Renderer).
    final offlineStyle = ref.watch(offlineMapStyleProvider).valueOrNull;
    // Die Basiskarte hängt an nichts: kein Schalter, keine Installation.
    // Fehlt sie (Ladefehler), bleibt es beim Hintergrundton.
    final baseStyle = ref.watch(baseMapStyleProvider).valueOrNull;
    final hasInstalledMaps =
        (ref.watch(installedMapsProvider).valueOrNull ?? const []).isNotEmpty;
    final offlineActive = offlineStyle != null;
    // Die Basiskarte NICHT mehr unter die Online-Kacheln legen (#137): Wo
    // eine OSM-Kachel schon liegt und die nächste noch fehlt, standen zwei
    // verschiedene Kartenstile nebeneinander — das sah kaputter aus als die
    // leere Fläche, die es verhindern sollte. Ohne Empfang bleibt sie
    // dagegen drin: Dann kommt gar keine Kachel, es gibt also nichts, womit
    // sie sich mischen könnte — und genau dieser Fall (Wald, kein Netz, noch
    // keine Region geladen) war der Anlass für #118.
    final showBaseMap = offlineActive || ref.watch(noConnectivityProvider);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _fallbackCenter,
              initialZoom: _fallbackZoom,
              // Zoom hart begrenzen: OSM liefert Kacheln nur bis Zoom 19,
              // darüber skaliert flutter_map die z19-Kachel hoch (256 px ×
              // 2^(zoom−19)). Ohne Obergrenze wächst die gerenderte Kachel
              // ins Absurde und die Karte bleibt leer, bis man weit genug
              // herauszoomt. Unten reicht Zoom 3 (Kontinent) locker aus.
              minZoom: _minZoom,
              maxZoom: _maxZoom,
              // Statt flutter_maps Standard-Grau (0xFFE0E0E0): der Landton
              // des Offline-Styles. Wo noch keine Kachel liegt, sieht die
              // Fläche dann nach „Karte lädt" aus und nicht nach „kaputt" —
              // und der Übergang zur fertigen Kachel fällt kaum auf.
              backgroundColor: AppColors.mapBackground,
              // Karte bleibt fest nach Norden ausgerichtet — Drehen per
              // Zwei-Finger-Geste verwirrt nur und bringt keinen Mehrwert.
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              // NaN-/Infinity-Kamerazustände aus Gesten-Grenzfällen an der
              // einzigen Engstelle verwerfen — sonst ANR über die
              // MarkerLayer-Endlosschleife (#151) und graue Kacheln über
              // die Kachelberechnung (#141). Details am Wächter selbst.
              cameraConstraint: const FiniteCameraConstraint(),
              // Long-Press richtet das Fadenkreuz auf die gedrückte Stelle aus.
              onLongPress: (tapPosition, latLng) => _mapController.move(
                  latLng, math.max(_mapController.camera.zoom, 16)),
            ),
            children: [
              // Unterste Schicht: die mitgelieferte DACH-Übersicht. Sie
              // füllt jede Stelle, die die Regionskarte nicht abdeckt —
              // beim Kaltstart und mitten im Wald (#118/#119). Der Renderer
              // holt dafür die z7-Kachel und skaliert sie hoch; scharf
              // wird es, sobald die Schicht darüber geladen hat. Unter den
              // Online-Kacheln liegt sie bewusst NICHT (siehe showBaseMap).
              if (baseStyle != null && showBaseMap)
                vmt.VectorTileLayer(
                  key: const ValueKey('base-map'),
                  tileProviders: baseStyle.tileProviders,
                  theme: baseStyle.theme,
                  // Raster, nicht Vektor (#119): Der Vektor-Modus rendert
                  // bei jeder Zwischen-Zoomstufe neu — laut Paket-Doku
                  // „can result in low frame rates", und diese Schicht
                  // läuft seit #118/#119 bei ALLEN mit, nicht nur bei
                  // Offline-Nutzern. Hier kostet der Wechsel nichts: Die
                  // Daten enden bei Zoom 7 und werden ohnehin immer
                  // hochskaliert, es gibt also keine Schärfe zu verlieren.
                  // Die Detailkarte unten bleibt bewusst auf Vektor.
                  layerMode: vmt.VectorTileLayerMode.raster,
                  maximumTileSubstitutionDifference: 1,
                ),
              if (offlineActive)
                vmt.VectorTileLayer(
                  // Der Schlüssel hängt an der QUELLE, nicht an einem festen
                  // Namen (Issue #144). `vector_map_tiles` vergleicht beim
                  // Aktualisieren nur Theme, Sprites, tileOffset, layerMode
                  // und maximumZoom (`hasRenderDifferences` in options.dart)
                  // — ein Wechsel der `tileProviders` fällt dort durch. Der
                  // Layer behielte also seine Caches und damit die Archive,
                  // die `_offlineTileSourceProvider` beim Neuaufbau schließt
                  // (jeder Resume invalidiert `installedMapsProvider`).
                  // Danach wirft jede Kachel „withResource() may not be
                  // called on a closed Pool", übrig bleibt die hochskalierte
                  // Übersicht, und nur ein App-Neustart half. Ein neuer
                  // Schlüssel erzwingt stattdessen einen frischen Layer mit
                  // frischen Caches auf den neu geöffneten Archiven.
                  key: ValueKey(offlineStyle.tileProviders),
                  tileProviders: offlineStyle.tileProviders,
                  theme: offlineStyle.theme,
                  // Vector-Modus rendert scharf in jeder Zoomstufe; die
                  // Kartendaten reichen bis Zoom ~15, darüber wird skaliert.
                  layerMode: vmt.VectorTileLayerMode.vector,
                  maximumZoom: 19,
                  // Fehlende Kacheln maximal weit durch niedrigere
                  // Zoomstufen ersetzen (Ränder der Regionskarten und
                  // die eingebaute Übersichts-Basiskarte).
                  maximumTileSubstitutionDifference: 1,
                )
              else
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'de.marcusbucher.pilzbuddy',
                  tileProvider: _tileProvider,
                  // Zurück auf die Paketvorgabe (Issue #142). #130 hatte
                  // 3/2 gesetzt, um lieber grob weiterzuzeichnen als auf
                  // die scharfe Kachel zu warten. Der Preis war zu hoch:
                  // Jede gehaltene Kachel ist eine GPU-Textur, und
                  // `flutter_map` gibt sie beim Ausdünnen nicht frei
                  // (`evictImageFromCache = false`). Gemessen wuchs der
                  // Texturspeicher beim Bedienen von 89 auf 257 MB und fiel
                  // erst beim Neustart — in den ANR-Berichten stand er bei
                  // 1,7–1,9 GB. Eine Karte, die nach zehn Minuten die App
                  // abwürgt, ist schlechter als eine, die beim Nachladen
                  // kurz blass ist.
                  keepBuffer: 2,
                  panBuffer: 1,
                ),
              // Eigene Live-Position als Avatar — liegt UNTER den
              // Spot-Markern, damit die tappbar bleiben.
              Builder(builder: (context) {
                final position =
                    ref.watch(positionStreamProvider).valueOrNull;
                if (position == null) return const SizedBox.shrink();
                final avatar =
                    ref.watch(myProfileProvider).valueOrNull?.avatar ?? 0;
                return MarkerLayer(markers: [
                  Marker(
                    point:
                        LatLng(position.latitude, position.longitude),
                    width: 40,
                    height: 40,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.forestGreen, width: 2.5),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black26,
                              blurRadius: 6,
                              offset: Offset(0, 2)),
                        ],
                      ),
                      child: MushroomAvatar(index: avatar, size: 35),
                    ),
                  ),
                ]);
              }),
              // Live-Standorte von Freunden — blau umrandet, unter den
              // Spot-Markern, damit die tappbar bleiben.
              if (friendLocations.isNotEmpty)
                MarkerLayer(markers: [
                  for (final loc in friendLocations) _friendLocationMarker(loc),
                ]),
              MarkerLayer(markers: [
                for (final s in friendSpots) _spotMarker(s),
                for (final s in mySpots) _spotMarker(s),
              ]),
              // Maßstab unten links — rechts sitzen Attribution und FABs.
              const Scalebar(
                alignment: Alignment.bottomLeft,
                padding: EdgeInsets.only(left: 12, bottom: 12),
              ),
              RichAttributionWidget(
                attributions: [
                  const TextSourceAttribution('OpenStreetMap-Mitwirkende'),
                  if (offlineActive)
                    const TextSourceAttribution('Protomaps (Offline-Karte)'),
                ],
              ),
            ],
          ),
          // Dauerhaftes, dezentes Fadenkreuz in der Kartenmitte —
          // „Neuer Spot" speichert genau dort.
          const IgnorePointer(
            child: Center(child: _Crosshair()),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, left: 12, right: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surface
                            .withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                          'Gedrückt halten richtet das Fadenkreuz aus'),
                    ),
                    const MapBanners(),
                    // Ein aktiver Filter versteckt Spots — das muss man
                    // sehen, ohne das Blatt zu öffnen, sonst sucht man eine
                    // Fundstelle, die nur ausgeblendet ist (#154).
                    if (filter.isActive)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: GestureDetector(
                          onTap: () => showSpotFilterSheet(context),
                          child: Container(
                            padding: const EdgeInsets.only(
                                left: 12, right: 4, top: 2, bottom: 2),
                            decoration: BoxDecoration(
                              color: AppColors.forestGreen
                                  .withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    _filterLabel(filter),
                                    style:
                                        const TextStyle(color: Colors.white),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => ref
                                      .read(spotFilterProvider.notifier)
                                      .clear(),
                                  icon: const Icon(Icons.close,
                                      size: 18, color: Colors.white),
                                  tooltip: 'Filter aufheben',
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(6),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (isSharing && shareUntil != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: GestureDetector(
                          onTap: _openShareSheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.friendBlue.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '📍 Du teilst deinen Standort bis '
                              '${TimeOfDay.fromDateTime(shareUntil.toLocal()).format(context)} Uhr — antippen',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Umschalter Online/Offline — erst sichtbar, wenn mindestens
          // eine Offline-Karte heruntergeladen wurde.
          if (hasInstalledMaps) ...[
            FloatingActionButton.small(
              heroTag: 'offline',
              onPressed: () {
                ref.read(offlineMapEnabledProvider.notifier).toggle();
                _showMessage(ref.read(offlineMapEnabledProvider)
                    ? 'Offline-Karte aktiv 🗺️'
                    : 'Online-Karte aktiv');
              },
              tooltip:
                  offlineActive ? 'Zur Online-Karte' : 'Zur Offline-Karte',
              // Icon zeigt den Zustand (durchgestrichener Erdball = offline),
              // der Tooltip die Aktion.
              child: Icon(offlineActive ? Icons.public_off : Icons.public),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton.small(
            heroTag: 'filter',
            onPressed: () => showSpotFilterSheet(context),
            tooltip: 'Karte filtern',
            backgroundColor: filter.isActive ? AppColors.forestGreen : null,
            foregroundColor: filter.isActive ? Colors.white : null,
            child: Icon(filter.isActive
                ? Icons.filter_alt
                : Icons.filter_alt_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.small(
            heroTag: 'refresh',
            onPressed: () {
              _refreshData();
              _showMessage('Karte aktualisiert');
            },
            tooltip: 'Aktualisieren',
            child: const Icon(Icons.refresh),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.small(
            heroTag: 'share-location',
            onPressed: _openShareSheet,
            tooltip: isSharing
                ? 'Standort-Teilen verwalten'
                : 'Standort mit Buddies teilen',
            backgroundColor: isSharing ? AppColors.friendBlue : null,
            foregroundColor: isSharing ? Colors.white : null,
            child: Icon(isSharing
                ? Icons.share_location
                : Icons.share_location_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.small(
            heroTag: 'locate',
            onPressed: _centerOnMe,
            tooltip: 'Meine Position',
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'add',
            onPressed: _addSpotAtCrosshair,
            icon: const Icon(Icons.add_location_alt),
            label: const Text('Neuer Spot'),
          ),
        ],
      ),
    );
  }
}

/// Kleines, dezentes Fadenkreuz: Ring + Haarlinien, grün mit weißem Halo.
class _Crosshair extends StatelessWidget {
  const _Crosshair();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(34, 34),
      painter: _CrosshairPainter(),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final halo = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = AppColors.forestGreen.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    const radius = 9.0;
    const arm = 6.0;

    for (final paint in [halo, line]) {
      canvas.drawCircle(center, radius, paint);
      canvas.drawLine(center - const Offset(0, radius + arm),
          center - const Offset(0, radius + 1.5), paint);
      canvas.drawLine(center + const Offset(0, radius + 1.5),
          center + const Offset(0, radius + arm), paint);
      canvas.drawLine(center - const Offset(radius + arm, 0),
          center - const Offset(radius + 1.5, 0), paint);
      canvas.drawLine(center + const Offset(radius + 1.5, 0),
          center + const Offset(radius + arm, 0), paint);
    }
    canvas.drawCircle(center, 1.8, Paint()..color = Colors.white);
    canvas.drawCircle(center, 1.1, Paint()..color = AppColors.forestGreen);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
