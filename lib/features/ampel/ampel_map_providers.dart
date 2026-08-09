// Die Pilzwetter-Fläche auf der Karte: Schalter, Rechnung, Datei —
// dieselbe Dreiteilung wie Regen- und Waldfläche.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/rain_grid_repository.dart' show RainStackData;
import '../map/rain_data_providers.dart';
import '../map/spot_weather.dart';
import 'ampel_fill.dart';
import 'ampel_providers.dart';

/// Leuchtet das Pilzwetter auf der Karte? Session-lokal wie die
/// Regen-Ebene und aus demselben Grund: Eine beim Start aktive Ebene
/// wäre ein ungefragter Download.
///
/// **Der Schalter meint seit 1.76.0 die Waldwaben** (Betreiber:
/// „ich würde die Pilzampel nur mit dem Wald überlagern"). Es ist kein
/// eigenes Bild mehr, sondern ein MODUS der Waldfläche — deshalb
/// schaltet er im Blatt die Waldebene mit ein, und wer die Waldebene
/// abschaltet, nimmt ihn mit.
final ampelLayerEnabledProvider = StateProvider<bool>((ref) => false);

/// Die Ampel-Stufen je Zelle — die gemeinsame Rechnung der Fläche und
/// der Kombi-Ebene. Bewusst OHNE den Ebenen-Schalter in der Bedingung:
/// Beide Kunden hängen daran, und wer nur die Kombi anschaltet, braucht
/// dieselben Zahlen.
final ampelLevelGridProvider = FutureProvider<AmpelLevelGrid?>((ref) async {
  if (!ref.watch(ampelPreviewEnabledProvider)) return null;
  // Beide Watches VOR den Awaits — die Riverpod-Lehre aus #255/#257.
  final stackFuture = ref.watch(rainStackProvider.future);
  final tableFuture = ref.watch(weatherTableProvider.future);
  final stack = await stackFuture;
  if (stack == null) return null;
  final table = await tableFuture;
  return compute(_levels, (stack: stack, table: table));
});

AmpelLevelGrid? _levels(({RainStackData stack, WeatherTable? table}) input) =>
    ampelLevelsFrom(input.stack, input.table);
