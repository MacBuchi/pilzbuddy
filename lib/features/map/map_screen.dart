import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;

import '../offline_maps/offline_map_providers.dart';

import '../../core/mushroom_species.dart';
import '../../core/update_check.dart';
import '../../core/widgets/mushroom_icon.dart';
import '../../models/spot.dart';
import '../friends/friend_providers.dart';
import '../spots/spot_providers.dart';
import '../spots/widgets/spot_detail_sheet.dart';
import 'widgets/add_spot_sheet.dart';
import 'widgets/map_banners.dart';

/// Fabrik für den Karten-Kachel-Provider. Tests ersetzen sie durch einen
/// Offline-Fake, damit keine echten OSM-Requests laufen.
final tileProviderFactoryProvider = Provider<TileProvider Function()>(
    (ref) => CancellableNetworkTileProvider.new);

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
  final _mapController = MapController();

  // Fallback: Mitte Deutschlands, bis die GPS-Position bekannt ist.
  static const _fallbackCenter = LatLng(51.1634, 10.4477);
  static const _fallbackZoom = 6.5;

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
  }

  /// Neuer Spot an der aktuellen Fadenkreuz-Position (Kartenmitte).
  Future<void> _addSpotAtCrosshair() async {
    final center = _mapController.camera.center;
    final ownSpecies = ref.read(ownSpeciesProvider);
    final data = await showAddSpotSheet(
      context,
      center,
      ownSpecies: ownSpecies,
      defaultSpecies: ownSpecies.firstOrNull,
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
    } catch (_) {
      _showMessage('Speichern fehlgeschlagen. Internet verfügbar?');
    }
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

  @override
  Widget build(BuildContext context) {
    final mySpots = ref.watch(mySpotsProvider).valueOrNull ?? const <Spot>[];
    final friendSpots =
        ref.watch(friendSpotsProvider).valueOrNull ?? const <Spot>[];
    // Offline-Layer nur, wenn eingeschaltet UND Karte + Style geladen werden
    // konnten — sonst immer Online-OSM (Sicherheitsnetz um den Beta-Renderer).
    final offlineStyle = ref.watch(offlineMapStyleProvider).valueOrNull;
    final hasInstalledMaps =
        (ref.watch(installedMapsProvider).valueOrNull ?? const []).isNotEmpty;
    final offlineActive = offlineStyle != null;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _fallbackCenter,
              initialZoom: _fallbackZoom,
              // Karte bleibt fest nach Norden ausgerichtet — Drehen per
              // Zwei-Finger-Geste verwirrt nur und bringt keinen Mehrwert.
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              // Long-Press richtet das Fadenkreuz auf die gedrückte Stelle aus.
              onLongPress: (tapPosition, latLng) => _mapController.move(
                  latLng, math.max(_mapController.camera.zoom, 16)),
            ),
            children: [
              if (offlineActive)
                vmt.VectorTileLayer(
                  tileProviders: offlineStyle.tileProviders,
                  theme: offlineStyle.theme,
                  // Vector-Modus rendert scharf in jeder Zoomstufe; die
                  // Kartendaten reichen bis Zoom ~15, darüber wird skaliert.
                  layerMode: vmt.VectorTileLayerMode.vector,
                  maximumZoom: 19,
                  // Fehlende Kacheln maximal weit durch niedrigere
                  // Zoomstufen ersetzen (Ränder der Regionskarten und
                  // die eingebaute Übersichts-Basiskarte).
                  maximumTileSubstitutionDifference: 3,
                )
              else
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'de.marcusbucher.pilzbuddy',
                  tileProvider: ref.watch(tileProviderFactoryProvider)(),
                ),
              MarkerLayer(markers: [
                for (final s in friendSpots) _spotMarker(s),
                for (final s in mySpots) _spotMarker(s),
              ]),
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
                final enabled = ref.read(offlineMapEnabledProvider.notifier);
                enabled.state = !enabled.state;
                _showMessage(enabled.state
                    ? 'Offline-Karte aktiv 🗺️'
                    : 'Online-Karte aktiv');
              },
              tooltip:
                  offlineActive ? 'Zur Online-Karte' : 'Zur Offline-Karte',
              child: Icon(offlineActive ? Icons.cloud_queue : Icons.cloud_off),
            ),
            const SizedBox(height: 12),
          ],
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
      ..color = const Color(0xFF2E7D32).withValues(alpha: 0.9)
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
    canvas.drawCircle(center, 1.1, Paint()..color = const Color(0xFF2E7D32));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
