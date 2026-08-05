import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/errors.dart';
import '../../core/mushroom_species.dart';
import '../../data/spot_repository.dart';
import '../../models/spot.dart';
import '../map/widgets/add_spot_sheet.dart';
import '../spots/spot_providers.dart';
import 'waypoint_parser.dart';
import '../../core/app_colors.dart';

/// Ob zwei Punkte als derselbe Spot gelten.
///
/// **Ohne stabile Kennung** — eine Spot-id aus einem fremden Konto sagt
/// hier nichts, und in die Datei gehört sie auch nicht. Bleibt die
/// Stelle: gleiche Koordinate auf fünf Nachkommastellen (gut ein Meter,
/// exportiert wird auf sechs) UND gleicher Name.
///
/// Beides zusammen, nicht eines allein: Zwei Spots dürfen dieselbe
/// Koordinate haben (verschiedene Bäume am selben Wegpunkt), und ein Name
/// wie „Buchenhang" kommt in einem Revier durchaus zweimal vor.
bool sameSpot(
    {required double lat,
    required double lng,
    String? name,
    required Spot other}) {
  bool sameCoord(double a, double b) =>
      (a - b).abs() < 0.00001; // ~1 m
  final otherName = other.name?.trim();
  return sameCoord(lat, other.lat) &&
      sameCoord(lng, other.lng) &&
      (name?.trim() ?? '') == (otherName ?? '');
}

/// Punkte aus GPX/KML/KMZ importieren.
///
/// **Zwei Wege, eine Datei** (#112):
///
/// - Eine Datei aus PilzBuddy (mit `<extensions>`) führt in den
///   **Wiederherstellungspfad**: Auswahlliste mit Häkchen, alles auf
///   einmal anlegen, samt Funden, Notizen und Freigabe-Flag.
/// - Alles andere geht den **bisherigen Weg**: Punkt für Punkt das
///   bekannte Anlege-Sheet, vorbefüllt mit Position und Punktname.
///
/// Der zweite Weg bleibt unverändert. Er ist der Grund, warum es den
/// Import überhaupt gibt (Punkte aus fremden Karten-Apps), und eine
/// Sicherung ist der seltenere Fall.
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

  /// Im Wiederherstellungspfad: die angehakten Punkte.
  final _selected = <int>{};
  bool _restoring = false;

  /// Ob die Vorauswahl schon getroffen wurde.
  ///
  /// Sie **darf nicht in `initState` fallen**: Die eigenen Spots stehen
  /// dort noch nicht (`mySpotListProvider` liefert bis zum Laden eine
  /// leere Liste), und ohne sie erkennt die Duplikatprüfung nichts.
  /// Getroffen wird sie deshalb im ersten Aufbau, bei dem die Spots
  /// wirklich da sind — wer die App kalt startet und direkt importiert,
  /// bekäme sonst jeden vorhandenen Spot ein zweites Mal.
  bool _preselected = false;

  @override
  void initState() {
    super.initState();
    _waypoints = widget.initialWaypoints;
  }

  /// Trägt eine Datei PilzBuddy-Daten? Dann die Auswahlliste statt der
  /// Punkt-für-Punkt-Anlage.
  ///
  /// **Irgendein** Punkt genügt: Eine Sicherung ist eine Sicherung, auch
  /// wenn ein Wegpunkt darin krumm ist.
  bool get _isRestore => _waypoints?.any((w) => w.isRestorable) ?? false;

  /// Vorauswahl: alles außer dem, was es schon gibt.
  ///
  /// Duplikate werden **nicht verschwiegen** — sie stehen mit Vermerk in
  /// der Liste und lassen sich anhaken. Zwei Spots an derselben Stelle
  /// sind nicht verboten, und die App soll nicht über den Kopf des
  /// Nutzers hinweg entscheiden. Nur die bequeme Vorgabe ist: nichts
  /// doppelt anlegen.
  ///
  /// Wird aus `build` heraus aufgerufen, sobald die eigenen Spots geladen
  /// sind — deshalb ohne `setState`: Der Aufbau, der sie auslöst, läuft
  /// gerade.
  void _preselect(List<ImportedWaypoint> waypoints) {
    _preselected = true;
    _selected.clear();
    for (var i = 0; i < waypoints.length; i++) {
      if (waypoints[i].isRestorable && !_isDuplicate(waypoints[i])) {
        _selected.add(i);
      }
    }
  }

  bool _isDuplicate(ImportedWaypoint waypoint) =>
      ref.read(mySpotListProvider).any((spot) => sameSpot(
          lat: waypoint.lat,
          lng: waypoint.lng,
          name: waypoint.name,
          other: spot));

  Future<void> _restoreSelected() async {
    final waypoints = _waypoints;
    if (waypoints == null || _selected.isEmpty) return;
    setState(() => _restoring = true);
    final chosen = <RestorableSpot>[
      for (final index in _selected.toList()..sort())
        (
          lat: waypoints[index].lat,
          lng: waypoints[index].lng,
          name: waypoints[index].name,
          sharingExcluded: waypoints[index].sharingExcluded,
          finds: [
            for (final find in waypoints[index].finds ?? const <ImportedFind>[])
              (
                species: find.species,
                count: find.count,
                foundOn: find.foundOn,
                note: find.note,
              ),
          ],
        ),
    ];
    try {
      final created =
          await ref.read(mySpotsProvider.notifier).restoreSpots(chosen);
      if (!mounted) return;
      setState(() {
        _waypoints = null;
        _error = null;
        _restoring = false;
        _preselected = false;
        _selected.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(created == 1
              ? '1 Spot wiederhergestellt.'
              : '$created Spots wiederhergestellt.')));
    } catch (e, stackTrace) {
      logError('Spots wiederherstellen', e, stackTrace);
      if (!mounted) return;
      setState(() => _restoring = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
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
      // schon vorausgewählt — sonst bleibt das Feld leer. Die zuletzt
      // benutzte Art wäre hier dieselbe falsche Annahme wie beim Anlegen
      // auf der Karte (Issue #155).
      defaultSpecies: speciesFromText(waypoint.name),
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

  /// Die Auswahlliste für eine PilzBuddy-Sicherung.
  Widget _buildRestoreList(List<ImportedWaypoint> waypoints) {
    final theme = Theme.of(context);
    // Erst wenn die eigenen Spots wirklich da sind, steht fest, was ein
    // Duplikat ist. `hasValue` statt der leeren Liste: Ein frisches Konto
    // — der Hauptfall dieses Ablaufs — hat legitim null Spots, und das
    // ist nicht dasselbe wie „noch nicht geladen".
    if (!_preselected && ref.watch(mySpotsProvider).hasValue) {
      _preselect(waypoints);
    }
    final duplicates = [
      for (final waypoint in waypoints) _isDuplicate(waypoint),
    ];
    final duplicateCount = duplicates.where((d) => d).length;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PilzBuddy-Sicherung erkannt',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(color: theme.colorScheme.primary)),
                      const SizedBox(height: 4),
                      Text(
                        '${waypoints.length} Spots mit Funden, Notizen und '
                        'Freigabe-Einstellung. Wähle aus, was du '
                        'übernehmen willst.',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (duplicateCount > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          duplicateCount == 1
                              ? '1 Spot hast du schon — er ist nicht '
                                  'angehakt.'
                              : '$duplicateCount Spots hast du schon — sie '
                                  'sind nicht angehakt.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: _restoring
                        ? null
                        : () => setState(() {
                              for (var i = 0; i < waypoints.length; i++) {
                                if (waypoints[i].isRestorable) {
                                  _selected.add(i);
                                }
                              }
                            }),
                    child: const Text('Alle auswählen'),
                  ),
                  TextButton(
                    onPressed:
                        _restoring ? null : () => setState(_selected.clear),
                    child: const Text('Keine'),
                  ),
                ],
              ),
              for (var i = 0; i < waypoints.length; i++)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _selected.contains(i),
                  // Punkte ohne Erweiterungen können in einer Sicherung
                  // mitschwimmen (jemand hat Dateien zusammengeführt).
                  // Sie hier anzubieten würde einen Spot ohne Funde
                  // anlegen und wäre stillschweigend Datenverlust.
                  onChanged: !waypoints[i].isRestorable || _restoring
                      ? null
                      : (checked) => setState(() {
                            if (checked == true) {
                              _selected.add(i);
                            } else {
                              _selected.remove(i);
                            }
                          }),
                  title: Text(waypoints[i].name ?? 'Spot ${i + 1}'),
                  subtitle: Text(_restoreSubtitle(waypoints[i], duplicates[i])),
                  // Bewusst KEIN `secondary`-Symbol für Duplikate: Neben
                  // dem Häkchen sieht jedes Symbol dort wie ein zweites
                  // Kästchen aus (im Vorschaubild aufgefallen). Der
                  // Vermerk steht in der Unterzeile und ist eindeutiger,
                  // als ein Symbol es sein könnte.
                ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed:
                      _selected.isEmpty || _restoring ? null : _restoreSelected,
                  icon: _restoring
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_done),
                  label: Text(_selected.length == 1
                      ? '1 Spot übernehmen'
                      : '${_selected.length} Spots übernehmen'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                ),
                TextButton.icon(
                  onPressed: _restoring ? null : _pickFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Andere Datei wählen'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// „3 Funde · hast du schon · 51.23457, 10.45679"
  ///
  /// Der Duplikat-Vermerk steht **vor** der Koordinate: Er ist der Grund,
  /// warum der Punkt nicht angehakt ist, und muss beim Überfliegen
  /// auffallen. Hinter zwei Zahlenkolonnen tut er das nicht.
  String _restoreSubtitle(ImportedWaypoint waypoint, bool duplicate) {
    final count = waypoint.finds?.length ?? 0;
    final parts = <String>[
      if (!waypoint.isRestorable)
        'ohne PilzBuddy-Daten'
      else if (count == 0)
        'noch kein Fund'
      else
        count == 1 ? '1 Fund' : '$count Funde',
      if (duplicate) 'hast du schon',
      '${waypoint.lat.toStringAsFixed(5)}, '
          '${waypoint.lng.toStringAsFixed(5)}',
    ];
    return parts.join(' · ');
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
          : _isRestore
              ? _buildRestoreList(waypoints)
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
