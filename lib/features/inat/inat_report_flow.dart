// Die Naht zwischen „Fund eintragen" und der Meldung (#553) — für beide
// Wege dorthin (Spot-Blatt und „Dort eintragen" auf der Karte). Zwei
// Kopien wären zwei Stellen, an denen die Reihenfolge auseinanderläuft.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../data/inat_api.dart';
import '../../data/spot_repository.dart';
import '../../models/spot.dart';
import '../map/forest_species_providers.dart';
import '../spots/widgets/add_find_sheet.dart';
import 'inat_providers.dart';
import 'inat_report_section.dart';
import 'inat_reporter.dart';

const kInatReportingMessage = 'Wird an iNaturalist gemeldet …';
const kInatReportedMessage =
    'An iNaturalist gemeldet 🍄 — bestätigt die Community die Art, geht '
    'die Beobachtung weiter an GBIF.';
const kInatQueuedMessage =
    'Fund wartet auf Verbindung — melden lässt er sich am Fund, sobald er '
    'übertragen ist.';

/// Ob das Blatt den Schalter zeigt — `null` heißt: nein.
///
/// **Erst das Konto, dann die Karte.** Die Baumartenkarte wird nur
/// ausgepackt, wenn gemeldet werden KANN — beobachten ist laden, und
/// wer nie verbindet, soll dafür nichts bezahlen.
///
/// Ein wartender Spot bekommt nichts: Sein Fund geht sicher in den
/// Korb, und dort gibt es keine id, an die eine Meldung könnte.
Future<InatOffer?> inatOfferFor(WidgetRef ref, Spot spot) async {
  if (spot.pending || !ref.read(inatAvailableProvider)) return null;
  final account = await ref.read(inatAccountProvider.future);
  if (account == null) return null;
  final grid = await ref.read(forestSpeciesGridProvider.future);
  return (
    presetTrees: inatTreePreset(
        grid?.at(spot.position.latitude, spot.position.longitude)),
  );
}

/// Meldet den ERSTEN der eben eingetragenen Funde.
///
/// **Der Fund ist das Original, die Meldung die Beigabe** — dieselbe
/// Regel wie beim Foto. Scheitert sie, steht der Fund, und die Meldung
/// sagt beides.
Future<void> reportFreshFindToInat(
  WidgetRef ref,
  ScaffoldMessengerState messenger, {
  required List<String> ids,
  required NewFind find,
  required Spot spot,
  required InatReportDraft draft,
}) async {
  if (ids.isEmpty) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text(kInatQueuedMessage)));
    return;
  }
  final account = ref.read(inatAccountProvider).valueOrNull;
  if (account == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(const SnackBar(content: Text(kInatReportingMessage)));
  try {
    await ref.read(inatReporterProvider).report(
          account: account,
          findId: ids.first,
          species: find.species,
          count: find.count,
          foundOn: find.foundOn,
          lat: find.position?.lat ?? spot.position.latitude,
          lng: find.position?.lng ?? spot.position.longitude,
          position: find.position,
          draft: draft,
        );
    messenger
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text(kInatReportedMessage)));
  } on InatException catch (e) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
          content: Text('Fund eingetragen, nicht gemeldet: ${e.message}')));
  } catch (e, s) {
    logError('An iNaturalist melden', e, s);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
          content: Text('Fund eingetragen, nicht gemeldet: '
              '${friendlyError(e)}')));
  }
}
