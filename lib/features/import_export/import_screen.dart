import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/errors.dart';
import '../../core/mushroom_species.dart';
import '../map/widgets/add_spot_sheet.dart';
import '../spots/spot_providers.dart';
import 'waypoint_parser.dart';
import '../../core/app_colors.dart';

/// Punkte aus GPX/KML/KMZ importieren: Datei wählen, dann für jeden
/// gefundenen Punkt einzeln den Pilz-Spot anlegen (bekanntes
/// Anlege-Sheet, vorbefüllt mit Position und Punktname).
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key, this.initialWaypoints});

  /// Für Tests: Punkte direkt vorgeben statt eine Datei zu wählen.
  final List<ImportedWaypoint>? initialWaypoints;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  List<ImportedWaypoint>? _waypoints;
  final _created = <int>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _waypoints = widget.initialWaypoints;
  }

  Future<void> _pickFile() async {
    // Android blendet im SAF-Picker alles aus, was nicht zu den
    // MIME-Typen passt — und für .gpx/.kml gibt es keine registrierten
    // Typen, die Dateien wären ausgegraut. Deshalb dort ohne Filter
    // (der Parser validiert ohnehin); nur im Web filtern wir bequem
    // nach Endungen.
    const typeGroups = kIsWeb
        ? [
            XTypeGroup(
              label: 'Karten-Dateien',
              extensions: ['gpx', 'kml', 'kmz', 'zip'],
            ),
          ]
        : [XTypeGroup(label: 'Alle Dateien', mimeTypes: ['*/*'])];
    final file = await openFile(acceptedTypeGroups: typeGroups);
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      final points = parseWaypoints(file.name, bytes);
      setState(() {
        _error = points.isEmpty
            ? 'Keine Punkte in ${file.name} gefunden.'
            : null;
        _waypoints = points.isEmpty ? null : points;
        _created.clear();
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } catch (e, stackTrace) {
      logError('Import-Datei lesen', e, stackTrace);
      setState(() => _error = 'Datei konnte nicht gelesen werden.');
    }
  }

  Future<void> _createSpot(int index, ImportedWaypoint waypoint) async {
    final ownSpecies = ref.read(ownSpeciesProvider);
    final data = await showAddSpotSheet(
      context,
      LatLng(waypoint.lat, waypoint.lng),
      ownSpecies: ownSpecies,
      // Steht die Art im Punktnamen („Edelreizker Spechbach"), ist sie
      // schon vorausgewählt — sonst wie üblich die zuletzt benutzte.
      defaultSpecies:
          speciesFromText(waypoint.name) ?? ownSpecies.firstOrNull,
      initialName: waypoint.name,
      initialFoundOn: waypoint.time,
    );
    if (data == null) return;
    try {
      await ref.read(mySpotsProvider.notifier).addSpot(
            lat: waypoint.lat,
            lng: waypoint.lng,
            name: data.name,
            species: data.species,
            count: data.count,
            foundOn: data.foundOn,
            note: data.note,
          );
      setState(() => _created.add(index));
    } catch (e, stackTrace) {
      logError('Import-Spot speichern', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final waypoints = _waypoints;
    return Scaffold(
      appBar: AppBar(title: const Text('Punkte importieren')),
      body: waypoints == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Importiere Punkte aus anderen Karten-Apps '
                      '(GPX, KML, KMZ oder gezippt). Danach legst du '
                      'für jeden Punkt deinen Pilz-Spot an.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Datei wählen'),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.error)),
                      ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '${waypoints.length} Punkte gefunden — lege für '
                      'jeden den Pilz an. Position und Name sind schon '
                      'vorausgefüllt.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                for (var i = 0; i < waypoints.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _created.contains(i)
                          ? Icons.check_circle
                          : Icons.place_outlined,
                      color: _created.contains(i)
                          ? AppColors.forestGreen
                          : null,
                    ),
                    title: Text(waypoints[i].name ?? 'Punkt ${i + 1}'),
                    subtitle: Text(
                        '${waypoints[i].lat.toStringAsFixed(5)}, '
                        '${waypoints[i].lng.toStringAsFixed(5)}'),
                    trailing: _created.contains(i)
                        ? const Text('Angelegt')
                        : FilledButton.tonal(
                            onPressed: () =>
                                _createSpot(i, waypoints[i]),
                            child: const Text('Anlegen'),
                          ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Andere Datei wählen'),
                ),
              ],
            ),
    );
  }
}
