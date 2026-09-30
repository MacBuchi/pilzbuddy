// „Kartenbereiche" (#630, Stufe 2): Karte für ohne Empfang speichern —
// auf Android UND im Browser, anders als die Regionskarten. Zwei Wege zu
// einem Bereich (der aktuelle Kartenausschnitt, die Umgebung der eigenen
// Spots), die Größe vorher als Messung, und die Liste dessen, was auf dem
// Gerät liegt: Name, Größe, Kartenstand, auf der Karte zeigen,
// aktualisieren, löschen. Bereiche werden nie verdrängt; was bleibt, muss
// man sehen und loswerden können.
//
// Zeichnen und Radieren auf der Karte (TrailBuddys Werkzeugleiste) sind
// Stufe 2b.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/router_branches.dart';
import '../../data/browser_storage.dart';
import '../map/forest_data_providers.dart' show mapIdleBoundsProvider;
import '../map/map_focus.dart';
import '../map/online_map.dart';
import '../spots/spot_providers.dart';
import 'area_downloader.dart';
import 'area_plan.dart';
import 'area_providers.dart';
import 'area_store.dart';

String _buildLabel(String build) => build.length == 8
    ? '${build.substring(6, 8)}.${build.substring(4, 6)}.${build.substring(0, 4)}'
    : build;

class AreasScreen extends ConsumerWidget {
  const AreasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areasAsync = ref.watch(storedAreasProvider);
    final download = ref.watch(areaDownloadProvider);
    final canSave = ref.watch(newMapEnabledProvider);
    final bounds = ref.watch(mapIdleBoundsProvider);
    final spots = ref.watch(mySpotListProvider);
    final areas = areasAsync.valueOrNull ?? const <StoredArea>[];
    var total = 0;
    for (final a in areas) {
      total += a.bytes;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Kartenbereiche')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Speichere die Karte für eine Gegend auf diesem Gerät — dann '
            'bleibt sie ohne Empfang scharf, bis Zoomstufe 13 samt '
            'Forst- und Wanderwegen. Das geht auch in der Web-App.',
          ),
          const SizedBox(height: 12),
          if (!canSave)
            const Card(
              key: ValueKey('areas-need-new-map'),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Neue Bereiche speichern geht, solange sie Vorschau ist, '
                  'nur mit „Neue Karte (Vorschau)" im Profil — die Kacheln '
                  'kommen von demselben Kartenserver.',
                ),
              ),
            )
          else ...[
            FilledButton.icon(
              key: const ValueKey('areas-save-view'),
              icon: const Icon(Icons.crop_free),
              label: const Text('Aktuellen Kartenausschnitt speichern'),
              onPressed: download.busy || bounds == null
                  ? null
                  : () => _save(
                      context,
                      ref,
                      RectShape(AreaBounds(
                          south: bounds.south,
                          west: bounds.west,
                          north: bounds.north,
                          east: bounds.east)),
                      'Ausschnitt'),
            ),
            if (bounds == null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Öffne dafür erst einmal die Karte.'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('areas-save-spots'),
              icon: const Icon(Icons.place_outlined),
              label: Text('Umgebung meiner Spots speichern '
                  '(${kAreaSpotRadiusKm.round()} km)'),
              onPressed: download.busy || spots.isEmpty
                  ? null
                  : () {
                      final shape = AreaShape.aroundPoints(
                          [for (final s in spots) LatLng(s.lat, s.lng)]);
                      if (shape != null) {
                        _save(context, ref, shape, 'Um meine Spots');
                      }
                    },
            ),
          ],
          if (download.phase == AreaDownloadPhase.planning)
            const ListTile(
              leading: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              title: Text('Größe wird gemessen …'),
            ),
          if (download.phase == AreaDownloadPhase.running)
            ListTile(
              key: const ValueKey('areas-running'),
              title: Text('„${download.name}" wird gespeichert …'),
              subtitle: LinearProgressIndicator(
                  value: download.progress?.fraction),
              trailing: TextButton(
                onPressed: () =>
                    ref.read(areaDownloadProvider.notifier).cancel(),
                child: const Text('Abbrechen'),
              ),
            ),
          if (download.phase == AreaDownloadPhase.failed)
            ListTile(
              key: const ValueKey('areas-failed'),
              leading: const Icon(Icons.error_outline),
              title: Text(download.error ?? 'Nicht gespeichert.'),
              trailing: IconButton(
                tooltip: 'Schließen',
                icon: const Icon(Icons.close),
                onPressed: () =>
                    ref.read(areaDownloadProvider.notifier).reset(),
              ),
            ),
          const Divider(height: 32),
          Text(
            areas.isEmpty
                ? 'Noch kein Bereich gespeichert.'
                : 'Gespeichert (${formatBytes(total)}) — nur auf diesem '
                    'Gerät, nie von selbst gelöscht. Ein Browser darf seinen '
                    'Speicher allerdings räumen.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final a in areas) _AreaTile(a, canUpdate: canSave),
        ],
      ),
    );
  }

  /// Messen, fragen, speichern. Die Größe ist eine Messung aus dem
  /// Verzeichnis des Archivs — der Dialog sagt sie, bevor ein Byte fließt.
  Future<void> _save(BuildContext context, WidgetRef ref, AreaShape shape,
      String defaultName) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(areaDownloadProvider.notifier);
    final AreaPlan plan;
    try {
      plan = await notifier.plan(shape);
    } on AreaTooLarge catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Zu groß (${e.tiles} Kacheln, höchstens '
              '$kAreaMaxTiles) — zoome näher heran oder speichere zwei '
              'Bereiche.')));
      return;
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Der Kartenserver ist gerade nicht erreichbar.')));
      return;
    }
    if (!context.mounted) return;
    if (plan.tiles.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Hier gibt es keine Kartendaten zum Speichern.')));
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _ConfirmDialog(plan: plan, defaultName: defaultName),
    );
    if (name == null) return;
    final area = await notifier.start(plan, name: name);
    // Beim ersten gespeicherten Bereich um dauerhaften Speicher bitten
    // (Muster Ausgangskorb): erst hier, nicht beim Start — Firefox fragt
    // dafür nach, und eine Nachfrage ohne Anlass wäre eine Zumutung. Auf
    // Android sagt der Stub „ja".
    if (area != null) await requestDurableStorage();
  }
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({required this.plan, required this.defaultName});

  final AreaPlan plan;
  final String defaultName;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  late final _name = TextEditingController(text: widget.defaultName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bereich speichern?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${formatBytes(widget.plan.bytes)} · '
              '${widget.plan.tiles.length} Kacheln, bis Zoomstufe '
              '${widget.plan.maxZoom}. Am besten im WLAN laden.'),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('area-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen')),
        FilledButton(
            onPressed: () {
              final name = _name.text.trim();
              Navigator.of(context)
                  .pop(name.isEmpty ? widget.defaultName : name);
            },
            child: const Text('Speichern')),
      ],
    );
  }
}

class _AreaTile extends ConsumerWidget {
  const _AreaTile(this.area, {required this.canUpdate});

  final StoredArea area;

  /// Aktualisieren holt vom Kartenserver, also nur mit dem Schalter.
  final bool canUpdate;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('„${area.name}" löschen?'),
        content: Text('${formatBytes(area.bytes)} werden vom Gerät gelöscht. '
            'Ohne Empfang bleibt dort dann nur die Übersichtskarte.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(storedAreasProvider.notifier).delete(area.id);
  }

  /// Dieselbe Form mit dem aktuellen Kartenstand noch einmal holen —
  /// unter derselben Id, der alte Bereich wird ersetzt. Angeboten, nicht
  /// aufgezwungen; ob das Netz frei ist, entscheidet, wer tippt.
  Future<void> _update(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(areaDownloadProvider.notifier);
    try {
      final plan = await notifier.plan(area.shape);
      await notifier.start(plan, name: area.name, id: area.id);
    } on AreaTooLarge {
      messenger.showSnackBar(const SnackBar(
          content: Text('Der Bereich ist für den neuen Stand zu groß.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Der Kartenserver ist gerade nicht erreichbar.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(areaDownloadProvider.select((s) => s.busy));
    return ListTile(
      key: ValueKey('area-${area.id}'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.map_outlined),
      title: Text(area.name),
      subtitle: Text('${formatBytes(area.bytes)} · ${area.tiles} Kacheln · '
          'Stand ${_buildLabel(area.build)}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (canUpdate)
          IconButton(
            key: ValueKey('area-update-${area.id}'),
            tooltip: 'Neu laden (aktueller Kartenstand)',
            icon: const Icon(Icons.update),
            onPressed: busy ? null : () => _update(context, ref),
          ),
        IconButton(
          key: ValueKey('area-delete-${area.id}'),
          tooltip: 'Bereich löschen',
          icon: const Icon(Icons.delete_outline),
          onPressed: busy ? null : () => _delete(context, ref),
        ),
      ]),
      onTap: () {
        // Erst der Reiter, dann der Wunsch (#345).
        StatefulNavigationShell.maybeOf(context)?.goBranch(kMapBranchIndex);
        ref.read(mapFocusProvider.notifier).focusOn(area.bounds.center);
      },
    );
  }
}
