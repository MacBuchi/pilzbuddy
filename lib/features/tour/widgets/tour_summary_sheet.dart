// Das Abschluss-Blatt der Pilztour (#338): unsere Bewertung, sichtbar
// gemacht — und korrigierbar.
//
// **Warum die Bewertung nicht versteckt wird.** Der naheliegende Entwurf
// wäre eine Liste vorangekreuzter Spots und ein Knopf „bestätigen". Das
// wäre ein Anstupser, Leergänge zu buchen, die man nie verdient hat — und
// falsche Leergänge vergiften genau die Stichprobe, für die es die Tour
// gibt (#199). Also stehen beide Hälften da: die abgesuchten
// hervorgehoben und angehakt, die berührten verblasst und aus, jeweils
// MIT dem Grund und der Zahl. Passt alles, ist es ein Tipp; passt etwas
// nicht, sieht man sofort, was.
//
// Der Wortlaut der Gründe ist die Entscheidungsgrundlage, nicht Zierde:
// „nur vorbeigegangen (34 m)" kann man beurteilen, ein ausgegrauter
// Schalter ohne Zahl nicht.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../../../data/spot_repository.dart';
import '../../spots/spot_providers.dart';
import '../tour_track.dart';

/// Zeigt das Blatt und gibt zurück, wie viele Leergänge gebucht wurden —
/// `null`, wenn abgebrochen wurde.
Future<int?> showTourSummarySheet(
  BuildContext context, {
  required List<TourVisit> visits,
  required Duration duration,
  required int pointCount,
}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TourSummarySheet(
        visits: visits,
        duration: duration,
        pointCount: pointCount,
      ),
    );

String tourDurationLabel(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (hours == 0) return '$minutes min';
  return '$hours h $minutes min';
}

/// Der Grund, warum ein Spot NICHT als abgesucht gilt — mit der Zahl, die
/// ihn belegt.
String tourReasonLabel(TourVisit visit) => switch (visit.kind) {
      TourVisitKind.searched =>
        'abgesucht — ${visit.dwell.inMinutes > 0 ? '${visit.dwell.inMinutes} min' : '${visit.dwell.inSeconds} s'} dort',
      TourVisitKind.brief => 'nur kurz da (${visit.dwell.inSeconds} s)',
      TourVisitKind.passedBy =>
        'nur vorbeigegangen (${visit.closestM.round()} m)',
    };

class _TourSummarySheet extends ConsumerStatefulWidget {
  const _TourSummarySheet({
    required this.visits,
    required this.duration,
    required this.pointCount,
  });

  final List<TourVisit> visits;
  final Duration duration;
  final int pointCount;

  @override
  ConsumerState<_TourSummarySheet> createState() => _TourSummarySheetState();
}

class _TourSummarySheetState extends ConsumerState<_TourSummarySheet> {
  /// Spot-id → wird als Leergang gebucht.
  late final Map<String, bool> _checked = {
    for (final visit in widget.visits)
      // Genau die Vorbelegung, die der Betreiber beschrieben hat: Was
      // unsere Kriterien erfüllt, ist an; alles andere ist aus und muss
      // absichtlich angehakt werden.
      visit.spot.id: visit.kind == TourVisitKind.searched,
  };

  bool _saving = false;

  /// Spots, an denen HEUTE schon ein eigener Eintrag hängt, bekommen
  /// keinen Leergang angeboten.
  ///
  /// Ein Fund und ein „nichts gefunden" am selben Tag und derselben
  /// Stelle widersprechen einander — und der Fund ist die stärkere
  /// Aussage. Genau dieser Fall ist der Normalfall: Man trägt unterwegs
  /// ein, was man findet.
  bool _alreadyLogged(TourVisit visit) {
    final today = DateTime.now();
    return visit.spot.ownEntries.any((entry) =>
        entry.foundOn.year == today.year &&
        entry.foundOn.month == today.month &&
        entry.foundOn.day == today.day);
  }

  Future<void> _book() async {
    setState(() => _saving = true);
    final foundOn = DateTime.now();
    var booked = 0;
    try {
      for (final visit in widget.visits) {
        if (_checked[visit.spot.id] != true) continue;
        if (_alreadyLogged(visit)) continue;
        await ref.read(mySpotsProvider.notifier).addFinds(
          spotId: visit.spot.id,
          finds: [NewFind.blank(foundOn: foundOn)],
        );
        booked++;
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) Navigator.of(context).pop(booked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searched = widget.visits
        .where((v) => v.kind == TourVisitKind.searched)
        .length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pilztour beendet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              '${tourDurationLabel(widget.duration)} · '
              '${widget.pointCount} Messpunkte · '
              '$searched von ${widget.visits.length} Spots abgesucht',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 12),
            if (widget.visits.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  // Kein Fehler ohne Fehlermeldung: Eine leere Liste sähe
                  // sonst nach einer kaputten Aufzeichnung aus.
                  'Auf diesem Weg lag keiner deiner Spots. '
                  'Aufgezeichnet wurde trotzdem.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.visits.length,
                  itemBuilder: (context, index) =>
                      _row(theme, widget.visits[index]),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Ein Haken trägt „nichts gefunden" ein — das ist eine '
              'Aussage über die Stelle, keine Lücke.',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 12),
            // `OverflowBar` und keine `Row`: Auf einem 412-dp-Telefon
            // laufen die beiden Beschriftungen nebeneinander über
            // (gemessen: 45 px). Die Knöpfe rutschen dann untereinander,
            // statt am Rand abgeschnitten zu werden.
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              overflowAlignment: OverflowBarAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(0),
                  child: const Text('Nichts eintragen'),
                ),
                FilledButton(
                  onPressed: _saving || widget.visits.isEmpty ? null : _book,
                  child: Text(_saving ? 'Wird eingetragen …' : 'Eintragen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, TourVisit visit) {
    final logged = _alreadyLogged(visit);
    final strong = visit.kind == TourVisitKind.searched;
    // Die verblasste Hälfte: sichtbar, aber erkennbar zweitrangig.
    final opacity = strong || logged ? 1.0 : 0.55;

    return Opacity(
      opacity: opacity,
      child: SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(visit.spot.displayName),
        subtitle: Text(
          logged
              // Der Fund von heute ist die stärkere Aussage — und dass er
              // schon dasteht, gehört gesagt, sonst wirkt der
              // abgeschaltete Schalter wie ein Fehler.
              ? 'heute schon eingetragen'
              : tourReasonLabel(visit),
          style: theme.textTheme.bodySmall?.copyWith(
            color: strong && !logged
                ? AppColors.forestGreen
                : theme.hintColor,
          ),
        ),
        value: logged ? false : (_checked[visit.spot.id] ?? false),
        onChanged: logged || _saving
            ? null
            : (value) =>
                setState(() => _checked[visit.spot.id] = value),
      ),
    );
  }
}
