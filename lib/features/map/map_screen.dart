import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

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
import '../spots/nearby_spots.dart';
import '../spots/spot_providers.dart';
import '../spots/widgets/add_find_sheet.dart';
import '../spots/widgets/spot_detail_sheet.dart';
import 'live_share_providers.dart';
import 'forest_data_providers.dart';
import 'map_gestures.dart';
import 'map_view/camera_tour.dart';
import 'map_view/map_view.dart';
import 'position_provider.dart';
import 'rain_layer.dart';
import 'spot_filter.dart';
import 'widgets/add_spot_sheet.dart';
import 'widgets/map_banners.dart';
import 'widgets/forest_layer_sheet.dart';
import 'widgets/rain_layer_sheet.dart';
import 'widgets/map_legend.dart';
import 'widgets/share_location_sheet.dart';
import 'widgets/spot_filter_sheet.dart';
import '../../core/app_colors.dart';

/// Antwort auf „hier liegt schon ein Spot" (#215).
enum _NearbyChoice { existingSpot, newSpot }

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
  // Fallback: Mitte Deutschlands, bis die GPS-Position bekannt ist.
  static const _fallbackCenter = LatLng(51.1634, 10.4477);
  static const _fallbackZoom = 6.5;

  // Grenzen des Karten-Zooms — 19 ist die höchste Stufe, für die es sowohl
  // OSM-Kacheln als auch Offline-Vektordaten gibt (Engine-Detailkommentare
  // in map_view/flutter_map_view.dart).
  static const _minZoom = 3.0;
  static const _maxZoom = 19.0;

  /// Engine-unabhängiger Kamerazugriff; die Engine hängt sich beim Einbau
  /// selbst ein (map_view.dart).
  final _map = MapViewController(
    initialCenter: _fallbackCenter,
    initialZoom: _fallbackZoom,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Der Ausgangskorb (#267) beim Start: Wer gestern im Wald etwas
    // eingetragen hat, soll es heute nicht von Hand losschicken müssen.
    // Nach dem ersten Frame, damit der Start nicht daran hängt; ohne
    // Empfang bleibt einfach alles liegen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(mySpotsProvider.notifier).sendOutbox());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    _map.move(LatLng(position.latitude, position.longitude), 15);
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

  /// Fragt nach, wenn schon ein eigener Spot in Reichweite liegt (#215).
  ///
  /// Gibt zurück, ob weiter ein NEUER Spot entstehen soll. Ist die Antwort
  /// „dort eintragen", übernimmt diese Methode gleich den Fund und liefert
  /// `false` — der Aufrufer ist dann fertig.
  ///
  /// Erst fragen, dann das Blatt öffnen: Die beiden Wege brauchen
  /// verschiedene Formulare (Fund am bestehenden Spot vs. neuer Spot), und
  /// ein Hinweis im schon offenen Anlege-Blatt hieße, das falsche steht
  /// bereits da.
  Future<bool> _confirmNewSpotNear(LatLng center) async {
    final near = nearestOwnSpot(ref.read(mySpotListProvider), center);
    if (near == null) return true;

    final choice = await showDialog<_NearbyChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hier liegt schon ein Spot'),
        content: Text(
            '${near.meters.round()} m entfernt liegt „${near.spot.displayName}". '
            'Gehört dein Fund dorthin?'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_NearbyChoice.newSpot),
            child: const Text('Trotzdem neuer Spot'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_NearbyChoice.existingSpot),
            child: const Text('Dort eintragen'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return false;
    if (choice == _NearbyChoice.newSpot) return true;

    await _addFindTo(near.spot);
    return false;
  }

  /// „Dort eintragen": derselbe Weg wie „Fund eintragen" im Spot-Blatt.
  Future<void> _addFindTo(Spot spot) async {
    final ownSpecies = ref.read(ownSpeciesProvider);
    final finds = await showAddFindSheet(
      context,
      lastFind: spot.lastOwnFind,
      ownSpecies: ownSpecies,
      fallbackSpecies: ownSpecies.firstOrNull,
    );
    if (finds == null) return;
    try {
      await ref
          .read(mySpotsProvider.notifier)
          .addFinds(spotId: spot.id, finds: finds);
      _showMessage('Fund bei „${spot.displayName}" eingetragen 🍄');
    } catch (e, stackTrace) {
      logError('Fund eintragen', e, stackTrace);
      _showMessage(friendlyError(e));
    }
  }

  /// Neuer Spot an der aktuellen Fadenkreuz-Position (Kartenmitte).
  Future<void> _addSpotAtCrosshair() async {
    final center = _map.center;
    if (!await _confirmNewSpotNear(center)) return;
    if (!mounted) return;
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
            finds: data.finds,
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

  MapViewMarker _spotMarker(Spot spot) {
    return MapViewMarker(
      point: spot.position,
      width: 44,
      height: 44,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: () => showSpotDetailSheet(context, spot.id),
        child: Tooltip(
          message: spot.pending
              ? '${spot.displayName} — wartet auf Verbindung'
              : spot.isOwn
                  ? spot.displayName
                  : '${spot.displayName} (${spot.ownerUsername ?? 'Freund'})',
          child: MushroomIcon(
            seed: stableSeed(spot.id),
            size: 44,
            friend: !spot.isOwn,
            // Wartet noch auf die Übertragung (#267): halb durchsichtig
            // mit Uhr. Er muss zu sehen sein, sonst legt man denselben
            // Spot ein zweites Mal an — aber er darf nicht wie ein
            // gesicherter aussehen.
            pending: spot.pending,
            group: groupFor(spot.lastFind?.species),
            species: spot.lastFind?.species,
          ),
        ),
      ),
    );
  }

  /// Live-Standort eines Freundes: sein Avatar mit blauem Ring.
  MapViewMarker _friendLocationMarker(FriendLocation loc) {
    return MapViewMarker(
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

  /// Eigene Live-Position als Avatar — liegt UNTER den Spot-Markern,
  /// damit die tappbar bleiben.
  MapViewMarker _myPositionMarker(Position position, int avatar) {
    return MapViewMarker(
      point: LatLng(position.latitude, position.longitude),
      width: 40,
      height: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.forestGreen, width: 2.5),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: MushroomAvatar(index: avatar, size: 35),
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
    // Verbindung zurück ⇒ Ausgangskorb losschicken (#267). Genau hier
    // und nicht am App-Resume: Wer aus dem Wald nach Hause kommt, ohne
    // die App zu schließen, hat kein Resume — aber sehr wohl einen
    // Wechsel von „kein Netz" auf WLAN.
    ref.listen<bool>(noConnectivityProvider, (previous, next) {
      if (previous == true && next == false) {
        unawaited(ref.read(mySpotsProvider.notifier).sendOutbox());
      }
    });
    // Solange ich teile, jede neue Position hochschieben (Bewegung sichtbar).
    ref.listen(positionStreamProvider,
        (_, next) => _maybeUploadLocation(next.valueOrNull));
    // Eigene Live-Position (Marker erscheint erst mit GPS-Fix).
    final myPosition = ref.watch(positionStreamProvider).valueOrNull;
    final myAvatar = ref.watch(myProfileProvider).valueOrNull?.avatar ?? 0;
    // Für FAB-Zustand/Umschalter — die Engine wertet die Provider für ihre
    // Schichten selbst aus (map_view/flutter_map_view.dart).
    final offlineActive =
        ref.watch(offlineMapStyleProvider).valueOrNull != null;
    final hasInstalledMaps =
        (ref.watch(installedMapsProvider).valueOrNull ?? const []).isNotEmpty;
    final rainActive = ref.watch(rainLayerProvider) != RainLayer.off;
    final forestActive = ref.watch(forestLayerEnabledProvider);
    // Der Wald-FAB erscheint erst, wenn das Gitter geladen werden
    // konnte — im Ladefenster (Bruchteil einer Sekunde) fehlt er kurz,
    // das ist billiger als ein Knopf, der ins Leere führt.
    final forestAvailable =
        ref.watch(forestGridProvider).valueOrNull != null;
    final longPressEnabled = ref.watch(mapLongPressEnabledProvider);

    return Scaffold(
      body: Stack(
        children: [
          MapView(
            controller: _map,
            config: MapViewConfig(
              initialCenter: _fallbackCenter,
              initialZoom: _fallbackZoom,
              minZoom: _minZoom,
              maxZoom: _maxZoom,
              backgroundColor: AppColors.mapBackground,
              // Long-Press richtet das Fadenkreuz auf die gedrückte Stelle
              // — ab Werk aus (#210), Begründung am Schalter im Profil.
              // `null` heißt für beide Engines schon „nichts tun", die
              // Geste wird also gar nicht erst weitergereicht.
              onLongPress: longPressEnabled
                  ? (latLng) => _map.move(latLng, math.max(_map.zoom, 16))
                  : null,
              // Fadenkreuz-Werte (#235) und Wald-Bildausschnitt (#249):
              // beides rechnet an diesem Stillstand, nie während der
              // Geste.
              onCameraIdle: (center, bounds) {
                ref.read(mapIdleCenterProvider.notifier).state = center;
                ref.read(mapIdleBoundsProvider.notifier).state = bounds;
              },
            ),
            markers: MapViewMarkers(
              myPosition: [
                if (myPosition != null) _myPositionMarker(myPosition, myAvatar),
              ],
              friendLocations: [
                for (final loc in friendLocations) _friendLocationMarker(loc),
              ],
              spots: [
                for (final s in friendSpots) _spotMarker(s),
                for (final s in mySpots) _spotMarker(s),
              ],
            ),
          ),
          // Dauerhaftes, dezentes Fadenkreuz in der Kartenmitte —
          // „Neuer Spot" speichert genau dort.
          const IgnorePointer(
            child: Center(child: _Crosshair()),
          ),
          // Die Legende zu den aktiven Ebenen (#231), links unten über
          // dem Maßstab. Nicht mehr in einem IgnorePointer: Das X zum
          // Ausblenden braucht den Tipp — die Karte dahinter verliert
          // nur die kleine Kartenfläche der Legende selbst.
          const SafeArea(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: MapLegend(),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, left: 12, right: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Nur solange es die Geste gibt (#210): Eine
                    // dauerhafte Zeile, die eine abgeschaltete Bedienung
                    // erklärt, wäre schlicht falsch — und sie kostet auf
                    // jedem Bildschirm Platz über den Bannern.
                    if (longPressEnabled)
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
          // Die Waldtypen-Ebene (#213) — nur wenn das Gitter da ist:
          // Ein Knopf auf ein fehlendes Asset wäre ein Fehler ohne
          // Fehlermeldung.
          if (forestAvailable) ...[
            FloatingActionButton.small(
              heroTag: 'forest',
              onPressed: () => showForestLayerSheet(context),
              tooltip: 'Waldtypen',
              backgroundColor:
                  forestActive ? AppColors.forestMixed : null,
              foregroundColor: forestActive ? Colors.white : null,
              child:
                  Icon(forestActive ? Icons.forest : Icons.forest_outlined),
            ),
            const SizedBox(height: 12),
          ],
          // Genau EIN neuer Dauerknopf für die Regenebene (#156) — die
          // Karte trägt nicht mehr; Zeitraum und Legende stecken im
          // Blatt dahinter, wie beim Filter.
          FloatingActionButton.small(
            heroTag: 'rain',
            onPressed: () => showRainLayerSheet(context),
            tooltip: 'Regen',
            backgroundColor: rainActive ? AppColors.friendBlue : null,
            foregroundColor: rainActive ? Colors.white : null,
            child: Icon(
                rainActive ? Icons.water_drop : Icons.water_drop_outlined),
          ),
          const SizedBox(height: 12),
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
          // Messhaken des Engine-Direktvergleichs: deterministische
          // Kamerafahrt gegen die Fassade — identisch auf beiden
          // Engines. `!kReleaseMode`, nicht `kDebugMode`: Die
          // Perfetto-Läufe (Stufe 7) messen im PROFILE-Build, dort
          // muss der Knopf da sein; nur das Release bleibt sauber.
          if (!kReleaseMode) ...[
            const SizedBox(height: 12),
            CameraTourButton(controller: _map),
          ],
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
