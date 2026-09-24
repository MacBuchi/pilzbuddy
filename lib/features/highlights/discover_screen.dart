// „Entdecken" (#596): alle Funktionen und Tipps, nach Reiter gruppiert.
//
// **Die Seite, die bleibt.** Das Blatt nach einer Beförderung ist einmal
// da und dann weg; hier steht alles dauerhaft — auch die Tipps, die nie
// ins Blatt kommen. Anlass war der Betreiber: „die wenigen Nutzer, die
// wir haben, wissen teils gar nicht von den Detailfunktionen".
//
// **Der Neu-Punkt wird beim ÖFFNEN gelöscht, gezeigt wird er trotzdem.**
// Die Menge wird beim ersten Aufbau festgehalten und erst dann als
// gesehen gemerkt — sonst verschwände der Punkt, bevor man ihn sieht.
// Dieselbe Linie wie die Galerie der Fundfotos: gesetzt beim Öffnen,
// nicht beim Vorbeiscrollen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import 'feature_highlights.dart';
import 'highlight_art.dart';
import 'highlight_sheet.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  late final Set<String> _unseen = {
    for (final h in kFeatureHighlights)
      if (!ref.read(seenHighlightIdsProvider).contains(h.id)) h.id,
  };

  @override
  void initState() {
    super.initState();
    // Nach dem Bild, nicht im Aufbau: Ein Provider darf während `build`
    // nicht verändert werden.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(seenHighlightIdsProvider.notifier)
          .markSeen(kFeatureHighlights.map((h) => h.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Entdecken')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Was PilzBuddy kann — auch das, was man beim Benutzen leicht '
            'übersieht. „Ausprobieren" führt direkt hin.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.hintColor),
          ),
          for (final tab in HighlightTab.values)
            ..._section(context, tab),
        ],
      ),
    );
  }

  List<Widget> _section(BuildContext context, HighlightTab tab) {
    // Highlights vor Tipps, sonst die Reihenfolge der Liste.
    final entries = [
      ...kFeatureHighlights
          .where((h) => h.tab == tab && h.kind == HighlightKind.highlight),
      ...kFeatureHighlights
          .where((h) => h.tab == tab && h.kind == HighlightKind.tip),
    ];
    if (entries.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 4),
        child: Text(tab.label, style: Theme.of(context).textTheme.titleSmall),
      ),
      for (final h in entries)
        _Entry(
          key: ValueKey('discover-${h.id}'),
          highlight: h,
          unseen: _unseen.contains(h.id),
          onTry: () => context.go(h.target),
        ),
    ];
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    super.key,
    required this.highlight,
    required this.unseen,
    required this.onTry,
  });

  final FeatureHighlight highlight;
  final bool unseen;
  final VoidCallback onTry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTip = highlight.kind == HighlightKind.tip;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HighlightArt(highlight: highlight, size: 56, animate: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(highlight.title,
                              style: theme.textTheme.titleSmall),
                          if (isTip) const _Badge('Tipp'),
                          if (unseen) const _Badge('Neu', strong: true),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(highlight.text, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onTry,
                child: const Text('Ausprobieren'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, {this.strong = false});

  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: strong
            ? AppColors.forestGreen
            : AppColors.forestGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: strong ? Colors.white : AppColors.forestGreen)),
    );
  }
}
