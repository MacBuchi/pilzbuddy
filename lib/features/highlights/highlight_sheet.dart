// Das Blatt nach einer Beförderung (#596).
//
// **Eine Seite, alle Neuheiten untereinander** — das Muster der
// „Neu in …"-Seiten bei Apple und vielen anderen. Bis 1.204.0 war es
// eine Blätterseite mit „Ausprobieren" je Seite, und wer mittendrin
// antippte, verlor den Rest (im Feld gemeldet, Betreiber 2026-09-24).
// Eine Leiste „Weiter ansehen" am Ziel hätte das geflickt; übliche
// Apps lösen es anders, nämlich gar nicht erst: Stehen alle drei auf
// einem Blick, ist nach dem Antippen einer Zeile nichts verloren.
//
// **Gemerkt wird VOR dem Zeigen.** Andersherum käme ein Blatt, das der
// Prozess-Kill oder ein Wegwischen mitten im Lesen beendet, bei jedem
// Start wieder — und ein Hinweis, der wiederkommt, nachdem man ihn
// geschlossen hat, ist dieselbe Belästigung wie eine Tour, die nach dem
// Überspringen neu anfängt. Verpasst ist dabei nichts: „Entdecken" hat
// alles.
import 'dart:async';

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
      // Alles steht auf EINER Seite, also ist beim Öffnen auch alles
      // gesehen — anders als beim Blättern, wo das nur für die erste
      // Seite gälte.
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

class HighlightSheet extends StatelessWidget {
  const HighlightSheet({super.key, required this.plan});

  final HighlightShow plan;

  /// Erst den Router greifen, dann schließen: Danach ist der Kontext
  /// des Blatts nicht mehr eingehängt (dieselbe Reihenfolge wie im
  /// Spot-Blatt).
  static void _go(BuildContext context, String location) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(location);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
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
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SheetCloseButton(),
            ],
          ),
          const SizedBox(height: 4),
          for (final h in plan.pages)
            _Row(
              key: ValueKey('highlight-row-${h.id}'),
              highlight: h,
              onTap: () => _go(context, h.target),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => _go(context, '/profile/entdecken'),
                  child: Text(plan.more > 0
                      ? '${plan.more} weitere entdecken'
                      : 'Alle Funktionen und Tipps'),
                ),
                TextButton(
                  onPressed: () => _go(context, '/profile/changelog'),
                  child: const Text('Alle Änderungen'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fertig'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Eine Neuheit als Zeile: Bild, Titel, Text — die ganze Zeile führt
/// hin. Kein eigener Knopf je Zeile: Drei „Ausprobieren" untereinander
/// wären Lärm, und das Pfeilsymbol sagt dasselbe.
class _Row extends StatelessWidget {
  const _Row({super.key, required this.highlight, required this.onTap});

  final FeatureHighlight highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HighlightArt(highlight: highlight, size: 64),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(highlight.title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(highlight.text, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 4, right: 8, top: 4),
              child: Icon(Icons.chevron_right, color: AppColors.forestGreen),
            ),
          ],
        ),
      ),
    );
  }
}
