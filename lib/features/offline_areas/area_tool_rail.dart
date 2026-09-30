// Die Werkzeugleiste der Kartenbereiche (#630, Stufe 2b; übernommen aus
// TrailBuddy, dort die Leiste „Ebenen"). Geöffnet von der Seite
// „Kartenbereiche", geschlossen über das X oder die Zurück-Taste — mit
// Rückfrage, wenn im Entwurf noch etwas steht. Solange sie offen ist,
// ist abgedunkelt, was nicht auf dem Gerät liegt, und der Entwurf liegt
// schraffiert darüber (area_edit_fill.dart).
//
// Sie steht dort, wo sonst die Knopfspalte der Karte steht, und ersetzt
// sie: Während man Bereiche bearbeitet, legt man keinen Spot an, und
// zwei Spalten nebeneinander wären auf einem Telefon ein halber Schirm.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../data/browser_storage.dart';
import '../map/forest_data_providers.dart' show mapIdleBoundsProvider;
import '../map/online_map.dart';
import 'area_downloader.dart';
import 'area_draw.dart';
import 'area_plan.dart';
import 'area_providers.dart';
import 'area_trim.dart';

/// Öffnet die Leiste mit leerem Entwurf.
void openAreaTools(WidgetRef ref) {
  ref.read(areaDraftProvider.notifier).start();
  ref.read(areaToolsOpenProvider.notifier).state = true;
}

/// Schließt die Leiste — mit Rückfrage, wenn der Entwurf etwas trägt.
Future<void> closeAreaTools(BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(areaDraftProvider.notifier);
  if (notifier.hasChanges && !await confirmDiscardDraft(context)) return;
  notifier.discard();
  ref.read(areaToolsOpenProvider.notifier).state = false;
}

Future<bool> confirmDiscardDraft(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Entwurf verwerfen?'),
        content:
            const Text('Die gewählten Kacheln sind noch nicht gespeichert.'),
        actions: [
          TextButton(
            key: const ValueKey('draft-keep'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Weiter bearbeiten'),
          ),
          FilledButton(
            key: const ValueKey('draft-discard'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Verwerfen'),
          ),
        ],
      ),
    ) ??
    false;

class AreaToolRail extends ConsumerStatefulWidget {
  const AreaToolRail({super.key});

  @override
  ConsumerState<AreaToolRail> createState() => _AreaToolRailState();
}

class _AreaToolRailState extends ConsumerState<AreaToolRail> {
  BackButtonDispatcher? _root;
  ChildBackButtonDispatcher? _back;

  // Die Zurück-Taste schließt die Leiste, statt die App zu verlassen —
  // die Karte ist die Wurzel ihres Reiters, dort hieße Zurück „raus".
  // Muster der Hinweis-Maschine (coach.dart): mit Vorrang anmelden,
  // solange die Leiste steht, danach wieder abmelden.
  Future<bool> _onBack() {
    if (mounted) closeAreaTools(context, ref);
    return SynchronousFuture(true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_back != null) return;
    final root = _root = Router.maybeOf(context)?.backButtonDispatcher;
    if (root == null) return;
    _back = root.createChildBackButtonDispatcher()
      ..addCallback(_onBack)
      ..takePriority();
  }

  @override
  void dispose() {
    final back = _back;
    if (back != null) {
      back.removeCallback(_onBack);
      _root?.forget(back);
    }
    super.dispose();
  }

  void _snapshot() {
    final bounds = ref.read(mapIdleBoundsProvider);
    if (bounds == null) return;
    final keys = tilesInBounds(AreaBounds(
        south: bounds.south,
        west: bounds.west,
        north: bounds.north,
        east: bounds.east));
    if (keys == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Der Ausschnitt ist zu groß — zoome näher heran.')));
      return;
    }
    ref.read(areaDraftProvider.notifier).addAll(keys);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(areaDraftProvider);
    final notifier = ref.read(areaDraftProvider.notifier);
    final canAdd = ref.watch(newMapEnabledProvider);
    final busy = ref.watch(areaDownloadProvider.select((s) => s.busy));
    final empty = draft == null || draft.isEmpty;

    Widget button(String key, String tip, IconData icon, VoidCallback? onTap,
            {bool selected = false, bool primary = false}) =>
        IconButton(
          key: ValueKey(key),
          tooltip: tip,
          isSelected: selected,
          padding: EdgeInsets.zero,
          // 44 px wie jeder Kartenknopf (`_Tool` in map_screen.dart).
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          style: IconButton.styleFrom(
            backgroundColor: selected
                ? AppColors.forestGreen
                : primary && onTap != null
                    ? AppColors.forestGreen
                    : null,
            foregroundColor:
                selected || (primary && onTap != null) ? Colors.white : null,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onTap,
          icon: Icon(icon),
        );

    Widget tool(AreaDrawTool t, String key, String tip, IconData icon,
            {bool enabled = true}) =>
        button(key, tip, icon, enabled && !busy ? () => notifier.arm(t) : null,
            selected: draft?.tool == t);

    const gap = SizedBox(height: 8);
    return Material(
      key: const ValueKey('area-tool-rail'),
      elevation: 3,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(26),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            button('area-snapshot', 'Ausschnitt dazunehmen', Icons.crop_free,
                canAdd && !busy ? _snapshot : null),
            tool(AreaDrawTool.add, 'area-draw-add', 'Fläche dazunehmen',
                Icons.add_circle_outline,
                enabled: canAdd),
            tool(AreaDrawTool.remove, 'area-draw-remove', 'Fläche wegnehmen',
                Icons.remove_circle_outline),
            button('area-undo', 'Rückgängig', Icons.undo,
                (draft?.history.isEmpty ?? true) || busy
                    ? null
                    : notifier.undo),
            gap,
            button('area-save', 'Speichern', Icons.download_done,
                empty || busy ? null : () => _save(draft),
                primary: true),
            button('area-close', 'Schließen', Icons.close,
                () => closeAreaTools(context, ref)),
          ],
        ),
      ),
    );
  }

  /// Misst, was dazukommt (braucht den Kartenhost) und was wegfällt
  /// (lokal), fragt, schreibt dann erst die Bereiche ohne die
  /// wegfallenden Kacheln neu und lädt danach.
  Future<void> _save(AreaDraft draft) async {
    final messenger = ScaffoldMessenger.of(context);
    final areas = ref.read(storedAreasProvider.notifier);
    final download = ref.read(areaDownloadProvider.notifier);
    final drafts = ref.read(areaDraftProvider.notifier);
    // Der Download überlebt ein Schließen der Leiste; danach ist `ref`
    // dieses Widgets tot, der Container nicht.
    final container = ProviderScope.containerOf(context, listen: false);
    TrimPlan trim = const TrimPlan([]);
    AreaPlan? plan;
    try {
      trim = await areas.planTrim(draft.removes);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Die gespeicherten Bereiche ließen sich nicht lesen.')));
      return;
    }
    if (draft.adds.isNotEmpty) {
      try {
        plan = await download.plan(draft.addShape);
      } on AreaTooLarge catch (e) {
        messenger.showSnackBar(SnackBar(
            content: Text('Zu groß (${e.tiles} Kacheln, höchstens '
                '$kAreaMaxTiles) — nimm weniger dazu oder speichere in '
                'zwei Schritten.')));
        return;
      } catch (_) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Der Kartenserver ist gerade nicht erreichbar.')));
        return;
      }
    }
    if (!mounted) return;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _SaveDialog(plan: plan, trim: trim),
    );
    if (name == null) return;
    if (!trim.isEmpty) {
      await areas.applyTrim(trim);
      drafts.dropRemoves();
    }
    if (plan != null && plan.tiles.isNotEmpty) {
      final area = await download.start(plan, name: name);
      if (area == null) {
        if (container.read(areaDownloadProvider).error case final error?) {
          messenger.showSnackBar(SnackBar(content: Text(error)));
        }
        return;
      }
      await requestDurableStorage();
    }
    drafts.clear();
  }
}

class _SaveDialog extends StatefulWidget {
  const _SaveDialog({required this.plan, required this.trim});

  final AreaPlan? plan;
  final TrimPlan trim;

  @override
  State<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<_SaveDialog> {
  final _name = TextEditingController(text: 'Gezeichnet');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final trim = widget.trim;
    final loads = plan != null && plan.tiles.isNotEmpty;
    final deleted = [
      for (final t in trim.trims)
        if (t.shape == null) t.area.name
    ];
    return AlertDialog(
      title: const Text('Änderungen speichern?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loads)
            Text('Dazu: ${formatBytes(plan.bytes)} · ${plan.tiles.length} '
                'Kacheln, bis Zoomstufe ${plan.maxZoom}. Am besten im WLAN '
                'laden.'),
          if (plan != null && plan.tiles.isEmpty)
            const Text('Wo dazugezeichnet wurde, hat der Kartenserver keine '
                'Kacheln.'),
          if (!trim.isEmpty) ...[
            if (loads) const SizedBox(height: 8),
            Text('Weg: ${formatBytes(trim.freedBytes)} werden frei '
                '(${trim.freedTiles} Kacheln), ohne Netz.'),
            if (deleted.isNotEmpty)
              Text('Ganz gelöscht: ${deleted.join(', ')}.'),
          ],
          if (loads) ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('area-draft-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen')),
        FilledButton(
            key: const ValueKey('area-draft-save'),
            onPressed: () {
              final name = _name.text.trim();
              Navigator.of(context).pop(name.isEmpty ? 'Gezeichnet' : name);
            },
            child: const Text('Speichern')),
      ],
    );
  }
}

/// Die Zeile oben auf der Karte, solange die Leiste offen ist: was der
/// nächste Strich tut, sonst wie es geht, und der laufende Download.
class AreaToolHint extends ConsumerWidget {
  const AreaToolHint({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(areaDraftProvider);
    final download = ref.watch(areaDownloadProvider);
    final canAdd = ref.watch(newMapEnabledProvider);
    final String text = switch (draft?.tool) {
      AreaDrawTool.add => 'Mit dem Finger umfahren, was dazukommen soll',
      AreaDrawTool.remove =>
        'Mit dem Finger umfahren oder überwischen, was weg soll',
      null => canAdd
          ? 'Hell ist gespeichert. Werkzeug wählen, dann umfahren — '
              'dazwischen lässt sich die Karte verschieben.'
          : 'Hell ist gespeichert. Wegnehmen geht immer, dazunehmen nur '
              'mit „Neue Karte" im Profil.',
    };
    return Material(
      key: const ValueKey('area-draw-hint'),
      elevation: 3,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: Theme.of(context).textTheme.bodyMedium),
            if (download.phase == AreaDownloadPhase.running) ...[
              const SizedBox(height: 6),
              Text('„${download.name}" wird gespeichert …',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: download.progress?.fraction),
            ],
          ],
        ),
      ),
    );
  }
}
