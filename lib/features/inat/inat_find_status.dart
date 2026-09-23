// Der Stand einer Meldung am Fund (#553 Stufe 2).
//
// > Man sollte im Fund sehen, ob er gemeldet / akzeptiert wurde, und
// > melden sollte auch im Nachhinein funktionieren. (Betreiber)
//
// **Zwei Teile, je mit eigener Aufgabe:** Die ZEILE im Untertitel sagt
// den Stand in Worten — lesbar ohne Tipp. Der KNOPF daneben führt
// weiter: zur Beobachtung, oder zum Melden, wo noch nichts gemeldet ist.
//
// **Ohne Konto und ohne Meldung: nichts.** Wer nie verbunden hat, sieht
// an keinem Fund etwas Neues — dieselbe Auflage wie im Eintrage-Blatt.
// Eine Meldung von früher bleibt aber sichtbar, auch nach dem Trennen:
// Sie steht bei iNaturalist ja weiter.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/find_report_repository.dart';
import '../../data/inat_api.dart';
import '../../models/find.dart';
import '../../models/spot.dart';
import 'inat_providers.dart';
import 'inat_report_flow.dart';
import 'inat_reporter.dart';

Key inatFindButtonKey(String findId) => ValueKey('inat-find-$findId');

/// Die Adresse der Beobachtung — auf Tipp, nie von selbst.
Uri inatObservationUrl(int id) => Uri.parse('$kInatWebBase/observations/$id');

/// Der Stand in Worten, für die Zeile am Fund — `null` ohne Meldung.
String? inatStatusLine(FindReport? report) {
  if (report == null) return null;
  if (report.gbifId != null) return 'bei GBIF';
  return switch (report.status) {
    FindReportStatus.sending => 'iNaturalist: nicht vollständig gemeldet',
    FindReportStatus.reported ||
    FindReportStatus.needsId =>
      'iNaturalist: wartet auf Bestätigung',
    FindReportStatus.research => 'iNaturalist: bestätigt — geht an GBIF',
    FindReportStatus.casual => 'iNaturalist: unbestätigt, nicht für GBIF',
    FindReportStatus.withdrawn => 'iNaturalist: gelöscht',
  };
}

IconData _iconFor(FindReport report) {
  if (report.gbifId != null) return Icons.public;
  return switch (report.status) {
    FindReportStatus.sending => Icons.sync_problem,
    FindReportStatus.reported ||
    FindReportStatus.needsId =>
      Icons.hourglass_empty,
    FindReportStatus.research => Icons.verified_outlined,
    FindReportStatus.casual => Icons.remove_circle_outline,
    FindReportStatus.withdrawn => Icons.delete_outline,
  };
}

/// Der Knopf am eigenen Fund.
class InatFindButton extends ConsumerWidget {
  const InatFindButton({super.key, required this.find, required this.spot});

  final Find find;
  final Spot spot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Leergänge brauchen hier keine eigene Prüfung: Sie tragen nie eine
    // Art (`finds_blank_leer`), fallen also unten bei der Art heraus.
    // Eine zweite Bedingung dafür war in der Gegenprobe toter Code.
    if (!ref.watch(inatAvailableProvider) || find.pending) {
      return const SizedBox.shrink();
    }
    final report = ref.watch(myFindReportsProvider).valueOrNull?[find.id];
    final linked = ref.watch(inatAccountProvider).valueOrNull != null;
    final hint = Theme.of(context).hintColor;

    // Noch nicht gemeldet: nur mit Konto und nur bei einer Art, die sich
    // melden lässt. Ein Knopf, der in „geht nicht" führt, wäre Lärm an
    // jedem Freitext-Fund.
    if (report == null) {
      if (!linked || inatScientificNameFor(find.species) == null) {
        return const SizedBox.shrink();
      }
      return IconButton(
        key: inatFindButtonKey(find.id),
        tooltip: 'An iNaturalist melden',
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.public_outlined, size: 20, color: hint),
        onPressed: () => reportExistingFindToInat(context, ref, find, spot),
      );
    }

    // Halb gemeldet: vervollständigen — mit Konto. Ohne Konto bleibt
    // nur der Stand in der Zeile.
    if (report.status == FindReportStatus.sending) {
      if (!linked) return const SizedBox.shrink();
      return IconButton(
        key: inatFindButtonKey(find.id),
        tooltip: 'Meldung vervollständigen',
        visualDensity: VisualDensity.compact,
        icon: Icon(_iconFor(report),
            size: 20, color: Theme.of(context).colorScheme.error),
        onPressed: () => reportExistingFindToInat(context, ref, find, spot),
      );
    }

    final id = report.remoteId;
    return IconButton(
      key: inatFindButtonKey(find.id),
      tooltip: inatStatusLine(report),
      visualDensity: VisualDensity.compact,
      icon: Icon(_iconFor(report), size: 20, color: hint),
      onPressed: id == null || report.status == FindReportStatus.withdrawn
          ? null
          : () => launchUrl(inatObservationUrl(id),
              mode: LaunchMode.externalApplication),
    );
  }
}
