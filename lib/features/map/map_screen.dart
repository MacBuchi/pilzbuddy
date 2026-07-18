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

  Future<void> _addSpotAt(LatLng position) async {
    final data = await showAddSpotSheet(context, position);
    if (data == null) return;
    try {
      await ref.read(mySpotsProvider.notifier).addSpot(
            lat: position.latitude,
            lng: position.longitude,
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

  Future<void> _addSpotAtMyPosition() async {
    final position = await _currentPosition();
    if (position == null) {
      _showMessage(
          'Standort nicht verfügbar – halte stattdessen die Karte an der Fundstelle gedrückt.');
      return;
    }
    final latLng = LatLng(position.latitude, position.longitude);
    _mapController.move(latLng, 15);
    if (mounted) await _addSpotAt(latLng);
  }

  Marker _spotMarker(Spot spot) {
    final color = spot.isOwn ? const Color(0xFF2E7D32) : Colors.blue.shade700;
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
              onLongPress: (tapPosition, latLng) => _addSpotAt(latLng),
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
        ],
      ),
      floatingActionButton: Column(
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
            onPressed: _addSpotAtMyPosition,
            icon: const Icon(Icons.add_location_alt),
            label: const Text('Spot hier'),
          ),
        ],
      ),
    );
  }
}
