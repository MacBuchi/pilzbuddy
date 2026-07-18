import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../models/spot.dart';
import '../spots/spot_providers.dart';
import '../spots/widgets/spot_detail_sheet.dart';
import 'widgets/add_spot_sheet.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _mapController = MapController();

  // Fallback: Mitte Deutschlands, bis die GPS-Position bekannt ist.
  static const _fallbackCenter = LatLng(51.1634, 10.4477);
  static const _fallbackZoom = 6.5;

  /// Fadenkreuz-Modus: Karte wird unter dem fixen Fadenkreuz in der
  /// Mitte verschoben, bis die Position passt.
  bool _picking = false;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
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

  /// Fadenkreuz-Modus starten — zentriert auf [target] (falls gegeben).
  void _startPicking({LatLng? target}) {
    if (target != null) {
      _mapController.move(
          target, math.max(_mapController.camera.zoom, 16));
    }
    setState(() => _picking = true);
  }

  /// FAB „Neuer Spot": erst zur GPS-Position springen (Fallback:
  /// aktuelle Kartenmitte), dann Fadenkreuz zeigen.
  Future<void> _startPickingAtMyPosition() async {
    final position = await _currentPosition();
    if (!mounted) return;
    _startPicking(
        target: position == null
            ? null
            : LatLng(position.latitude, position.longitude));
  }

  Future<void> _confirmPick() async {
    final center = _mapController.camera.center;
    setState(() => _picking = false);
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
    final color = spot.isOwn ? const Color(0xFF2E7D32) : Colors.blue.shade700;
    return Marker(
      point: spot.position,
      width: 44,
      height: 44,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: _picking ? null : () => showSpotDetailSheet(context, spot.id),
        child: Tooltip(
          message: spot.isOwn
              ? spot.displayName
              : '${spot.displayName} (${spot.ownerUsername ?? 'Freund'})',
          child: Icon(Icons.location_on, size: 40, color: color),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mySpots = ref.watch(mySpotsProvider).valueOrNull ?? const <Spot>[];
    final friendSpots =
        ref.watch(friendSpotsProvider).valueOrNull ?? const <Spot>[];

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _fallbackCenter,
              initialZoom: _fallbackZoom,
              onLongPress: (tapPosition, latLng) {
                if (!_picking) _startPicking(target: latLng);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'de.marcusbucher.pilzbuddy',
                tileProvider: CancellableNetworkTileProvider(),
              ),
              MarkerLayer(markers: [
                for (final s in friendSpots) _spotMarker(s),
                for (final s in mySpots) _spotMarker(s),
              ]),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap-Mitwirkende'),
                ],
              ),
            ],
          ),
          if (!_picking)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Karte gedrückt halten = neuer Spot'),
                ),
              ),
            ),
          if (_picking) ...[
            // Fadenkreuz fix in der Kartenmitte
            const IgnorePointer(
              child: Center(
                child: _Crosshair(),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                      'Karte verschieben, bis das Fadenkreuz passt'),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: kElevationToShadow[3],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: () => setState(() => _picking = false),
                        child: const Text('Abbrechen'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _confirmPick,
                        icon: const Icon(Icons.check),
                        label: const Text('Hier speichern'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: _picking
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'locate',
                  onPressed: _centerOnMe,
                  tooltip: 'Meine Position',
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'add',
                  onPressed: _startPickingAtMyPosition,
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text('Neuer Spot'),
                ),
              ],
            ),
    );
  }
}

/// Fadenkreuz: Ring + Haarlinien, grün mit weißem Halo für Sichtbarkeit
/// auf hellen wie dunklen Kartenteilen.
class _Crosshair extends StatelessWidget {
  const _Crosshair();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(56, 56),
      painter: _CrosshairPainter(),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final halo = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = const Color(0xFF2E7D32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    const radius = 14.0;
    const arm = 10.0;

    for (final paint in [halo, line]) {
      canvas.drawCircle(center, radius, paint);
      // vier Haarlinien außerhalb des Rings
      canvas.drawLine(center - const Offset(0, radius + arm),
          center - const Offset(0, radius + 2), paint);
      canvas.drawLine(center + const Offset(0, radius + 2),
          center + const Offset(0, radius + arm), paint);
      canvas.drawLine(center - const Offset(radius + arm, 0),
          center - const Offset(radius + 2, 0), paint);
      canvas.drawLine(center + const Offset(radius + 2, 0),
          center + const Offset(radius + arm, 0), paint);
    }
    // Punkt exakt im Zentrum
    canvas.drawCircle(center, 2.5, Paint()..color = Colors.white);
    canvas.drawCircle(center, 1.5, Paint()..color = const Color(0xFF2E7D32));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
