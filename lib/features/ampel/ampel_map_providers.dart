// Die Pilzwetter-Fläche auf der Karte: Schalter, Rechnung, Datei —
// dieselbe Dreiteilung wie Regen- und Waldfläche.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/rain_grid_repository.dart' show RainStackData;
import '../map/rain_data_providers.dart';
import '../map/spot_weather.dart';
import 'ampel_fill.dart';
import 'ampel_providers.dart';

/// Liegt die Pilzwetter-Fläche auf der Karte? Session-lokal wie die
/// Regen-Ebene und aus demselben Grund: Eine beim Start aktive Ebene
/// wäre ein ungefragter Download. Eingeschaltet wird sie im
/// Regen-Blatt — und dort auch wieder aus, wenn eine Regenfläche
/// gewählt wird (zwei Flächen übereinander wären Matsch).
final ampelLayerEnabledProvider = StateProvider<bool>((ref) => false);

/// Die gerechnete Fläche — im Isolate: 26 Gitter auspacken und 550 000
/// Zellen einfärben ist Rechenzeit im Kartenpfad (#151 lässt grüßen).
///
/// `null` heißt still „keine Ebene": Vorschau aus, Ebene aus, Stapel
/// nicht tief genug (erst nach dem 26-Tage-Update, #256) oder keine
/// Stationstabelle. Das Regen-Blatt erklärt den häufigsten Fall.
final ampelFillProvider = FutureProvider<AmpelFill?>((ref) async {
  if (!ref.watch(ampelPreviewEnabledProvider)) return null;
  if (!ref.watch(ampelLayerEnabledProvider)) return null;
  // Beide Watches VOR den Awaits — die Riverpod-Lehre aus #255/#257.
  final stackFuture = ref.watch(rainStackProvider.future);
  final tableFuture = ref.watch(weatherTableProvider.future);
  final stack = await stackFuture;
  if (stack == null) return null;
  final table = await tableFuture;
  return compute(_fill, (stack: stack, table: table));
});

AmpelFill? _fill(({RainStackData stack, WeatherTable? table}) input) =>
    ampelFillFrom(input.stack, input.table);

/// Dieselbe Fläche als Datei — der MapLibre-Weg (`image`-Quelle nimmt
/// eine URL). Der jüngste Stapel-Tag ist der Stand im Dateinamen;
/// [RainGridRepository.writeFill] räumt alte Stände weg.
final ampelFillFileProvider =
    FutureProvider<({String url, AmpelFill fill})?>((ref) async {
  final fill = await ref.watch(ampelFillProvider.future);
  if (fill == null) return null;
  final url = await ref
      .watch(rainGridRepositoryProvider)
      .writeFill('ampel', fill.newest, fill.png);
  return url == null ? null : (url: url, fill: fill);
});
