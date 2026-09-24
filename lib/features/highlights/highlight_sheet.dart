// Das Blatt nach einer Beförderung (#596).
//
// **Gemerkt wird VOR dem Zeigen.** Andersherum käme ein Blatt, das der
// Prozess-Kill oder ein Wegwischen mitten im Lesen beendet, bei jedem
// Start wieder — und ein Hinweis, der wiederkommt, nachdem man ihn
// geschlossen hat, ist dieselbe Belästigung wie eine Tour, die nach dem
// Überspringen neu anfängt. Verpasst ist dabei nichts: „Entdecken" hat
// alles.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/app_info.dart';
import '../../core/errors.dart';
import '../../core/settings.dart';
import '../../core/widgets/sheet_close_button.dart';
import '../help/map_tour.dart';
import '../tour/tour_providers.dart';
import 'feature_highlights.dart';
import 'highlight_art.dart';

/// Welche Einträge schon angesehen wurden — der Neu-Punkt in „Entdecken".
class SeenHighlightIds extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.read(settingsProvider).seenHighlightIds;

  void markSeen(Iterable<String> ids) {
    final next = {...state, ...ids};
    if (next.length == state.length) return;
    state = next;
    unawaited(ref
        .read(settingsProvider)
        .setSeenHighlightIds(next)
        .catchError((Object e, StackTrace s) =>
            logError('Neuheiten gesehen merken', e, s)));
  }
}

final seenHighlightIdsProvider =
    NotifierProvider<SeenHighlightIds, Set<String>>(SeenHighlightIds.new);

/// Wie viele Einträge in „Entdecken" noch nicht angesehen sind.
final unseenHighlightCountProvider = Provider<int>((ref) {
  final seen = ref.watch(seenHighlightIdsProvider);
  return kFeatureHighlights.where((h) => !seen.contains(h.id)).length;
});

/// Beim Start der Karte: entscheiden, merken, gegebenenfalls zeigen.
///
/// [mayShow] ist `false`, wenn in diesem Start schon etwas anderes über
/// der Karte liegt (Haftungshinweis, Karten-Tour) — zwei Overlays
/// gleichzeitig wären keins. Gerechnet wird trotzdem: Eine frische
/// Installation muss ihre Version schon beim ERSTEN Start merken, sonst
/// hielte sie sich nach der Tour für einen Bestandsnutzer und bekäme den
/// Rückblick auf eine App, die sie gerade kennengelernt hat.
Future<void> maybeShowHighlights(
  BuildContext context,
  WidgetRef ref, {
  required bool mayShow,
}) async {
  final settings = ref.read(settingsProvider);
  final current = await ref.read(appVersionProvider.future);
  if (!context.mounted) return;
  final plan = planHighlights(
    current: current,
    seenVersion: settings.highlightsSeenVersion,
    mapTourSeen: ref.read(mapTourSeenProvider),
  );
  switch (plan) {
    case HighlightNothing():
      return;
    case HighlightRecord(:final version):
      await _record(settings, version);
    case HighlightShow():
      // Nicht zeigen heißt hier auch nicht merken: Der Rückblick wartet
      // dann auf den nächsten ruhigen Start, statt verloren zu gehen.
      //
      // Eine laufende Pilztour zählt wie ein Overlay: Wer im Wald die App
      // öffnet, will die Karte, keine Neuigkeiten.
      if (!mayShow || ref.read(tourProvider) != null) return;
      await _record(settings, plan.version);
      if (!context.mounted) return;
      ref
          .read(seenHighlightIdsProvider.notifier)
          .markSeen(plan.pages.map((h) => h.id));
      await showHighlightSheet(context, plan);
  }
}

Future<void> _record(Settings settings, String version) =>
    settings.setHighlightsSeenVersion(version).catchError(
        (Object e, StackTrace s) => logError('Neuheiten-Stand merken', e, s));

Future<void> showHighlightSheet(BuildContext context, HighlightShow plan) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => HighlightSheet(plan: plan),
    );

class HighlightSheet extends StatefulWidget {
  const HighlightSheet({super.key, required this.plan});

  final HighlightShow plan;

  @override
  State<HighlightSheet> createState() => _HighlightSheetState();
}

class _HighlightSheetState extends State<HighlightSheet> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Erst den Router greifen, dann schließen: Danach ist der Kontext
  /// des Blatts nicht mehr eingehängt (dieselbe Reihenfolge wie im
  /// Spot-Blatt).
  void _go(String location) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(location);
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final pages = plan.pages;
    final last = _page == pages.length - 1;
    final theme = Theme.of(context);
    final height = math.min(420.0, MediaQuery.sizeOf(context).height * 0.6);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.recap
                      ? 'Das kann PilzBuddy inzwischen'
                      : 'Neu in PilzBuddy',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SheetCloseButton(),
            ],
          ),
          // `Flexible` um die feste Höhe: Auf einem kleinen Schirm gibt
          // sie nach, statt das Blatt über den Rand zu schieben — die
          // Seite selbst scrollt dann.
          Flexible(
            child: SizedBox(
            height: height,
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (final h in pages)
                  _Page(highlight: h, onTry: () => _go(h.target)),
              ],
            ),
          )),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                for (var i = 0; i < pages.length; i++)
                  Container(
                    key: ValueKey('highlight-dot-$i'),
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page
                          ? AppColors.forestGreen
                          : theme.disabledColor,
                    ),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: last
                      ? () => Navigator.of(context).pop()
                      : () => _pages.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut),
                  child: Text(last ? 'Fertig' : 'Weiter'),
                ),
              ],
            ),
          ),
          // Der Weg zu allem Übrigen — auf JEDER Seite, nicht erst auf
          // der letzten: Wer nach Seite eins genug hat, soll trotzdem
          // wissen, dass es mehr gibt und wo.
          Wrap(
            children: [
              TextButton(
                onPressed: () => _go('/profile/entdecken'),
                child: Text(plan.more > 0
                    ? '${plan.more} weitere entdecken'
                    : 'Alle Funktionen und Tipps'),
              ),
              TextButton(
                onPressed: () => _go('/profile/changelog'),
                child: const Text('Alle Änderungen'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.highlight, required this.onTry});

  final FeatureHighlight highlight;
  final VoidCallback onTry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: 8, top: 8),
      child: Column(
        children: [
          HighlightArt(highlight: highlight),
          const SizedBox(height: 16),
          Text(highlight.title,
              textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(highlight.text,
              textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onTry,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('Ausprobieren'),
          ),
        ],
      ),
    );
  }
}
