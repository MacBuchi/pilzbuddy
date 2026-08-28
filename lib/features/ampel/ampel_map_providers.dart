// Die Pilzwetter-Fläche auf der Karte: Schalter, Rechnung, Datei —
// dieselbe Dreiteilung wie Regen- und Waldfläche.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/rain_grid_repository.dart' show RainStackData;
import '../../core/settings.dart';
import '../map/forest_data_providers.dart';
import '../map/rain_data_providers.dart';
import '../map/spot_weather.dart';
import 'ampel_fill.dart';
import 'ampel_providers.dart';

/// Leuchtet das Pilzwetter auf der Karte? Seit #349 gemerkt.
///
/// Die alte Regel („eine beim Start aktive Ebene wäre ein ungefragter
/// Download") verwechselte „ungefragt" mit „einmal gefragt" — die
/// Begründung steht bei [Settings.ampelLayerEnabled]. Von den vier
/// Ebenen ist diese die teuerste zum Merken: Sie zieht Wald- und
/// Höhengitter in den Startpfad, für den, der sie anlässt.
///
/// **Der Schalter meint seit 1.76.0 die Waldwaben** (Betreiber:
/// „ich würde die Pilzampel nur mit dem Wald überlagern"). Es ist kein
/// eigenes Bild mehr, sondern ein MODUS der Waldfläche — deshalb
/// schaltet er im Blatt die Waldebene mit ein, und wer die Waldebene
/// abschaltet, nimmt ihn mit.
final ampelLayerEnabledProvider = NotifierProvider<RememberedFlag, bool>(
  () => RememberedFlag(
    read: (s) => s.ampelLayerEnabled,
    write: (s, v) => s.setAmpelLayerEnabled(v),
    label: 'Ampel-Fläche merken',
  ),
);

/// Die Ampel-Fläche schalten — samt ihrer beiden Nebenwirkungen.
///
/// Sie hat seit #347 ZWEI Bedienstellen (Karten-Blatt und Regen-Blatt),
/// und beide müssen dasselbe tun. Ohne Waldebene hätte das Leuchten
/// nichts, worauf es liegen könnte, und ohne die Wetter-Zustimmung keine
/// Daten — zwei Kopien dieser Kette wären zwei Antworten auf denselben
/// Schalter, und die zweite bräche still.
///
/// Die Zustimmung ist bewusst EIN Angebot und kein zweiter Dialog: Die
/// Fläche rechnet aus genau dem Stapel, den auch das Spot-Blatt lädt,
/// und die Kosten nennt der Untertitel am Schalter.
Future<void> setAmpelLayerEnabled(WidgetRef ref, bool value) async {
  ref.read(ampelLayerEnabledProvider.notifier).set(value);
  if (!value) return;
  ref.read(forestLayerEnabledProvider.notifier).set(true);
  if (ref.read(rainCourseEnabledProvider)) return;
  ref.read(rainCourseEnabledProvider.notifier).state = true;
  await ref.read(settingsProvider).setRainCourseEnabled(true);
}

/// Die Ampel-Stufen je Zelle — die gemeinsame Rechnung der Fläche und
/// der Kombi-Ebene. Bewusst OHNE den Ebenen-Schalter in der Bedingung:
/// Beide Kunden hängen daran, und wer nur die Kombi anschaltet, braucht
/// dieselben Zahlen.
final ampelLevelGridProvider = FutureProvider<AmpelLevelGrid?>((ref) async {
  if (!ref.watch(ampelPreviewEnabledProvider)) return null;
  // Beide Watches VOR den Awaits — die Riverpod-Lehre aus #255/#257.
  // Die Höhe fehlt hier mit ABSICHT: Das Gitter trägt seit dem
  // Berchtesgaden-Befund (2026-08-17) die Zutaten je Regenzelle, und
  // erst der Abnehmer rechnet mit SEINER Höhe — der Zeichner je
  // Waldwabe, die Legende am Fadenkreuz-Punkt.
  final stackFuture = ref.watch(rainStackProvider.future);
  final tableFuture = ref.watch(weatherTableProvider.future);
  final stack = await stackFuture;
  if (stack == null) return null;
  final table = await tableFuture;
  return compute(_levels, (stack: stack, table: table));
});

AmpelLevelGrid? _levels(({RainStackData stack, WeatherTable? table}) input) =>
    ampelLevelsFrom(input.stack, input.table);
