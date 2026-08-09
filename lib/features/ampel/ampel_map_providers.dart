// Die Pilzwetter-Fläche auf der Karte: Schalter, Rechnung, Datei —
// dieselbe Dreiteilung wie Regen- und Waldfläche.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart' show AmpelPalette;
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

/// Liegt die KOMBI-Ebene „Wald + Pilzwetter" (Betreiber-Wunsch
/// 2026-08-09)? Session-lokal wie die Ebenen-Schalter daneben.
///
/// Sie ist kein zweites Bild, sondern ein MODUS der Waldfläche: Die
/// Waben leuchten dort, wo das Wetter stimmt. Deshalb schaltet sie im
/// Blatt die Waldebene mit ein und die reine Ampel-Fläche aus — zwei
/// Deutungs-Flächen übereinander wären wieder Matsch.
final ampelForestCombinedProvider = StateProvider<bool>((ref) => false);

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

/// Die gerechnete Fläche — im Isolate: 26 Gitter auspacken und 550 000
/// Zellen einfärben ist Rechenzeit im Kartenpfad (#151 lässt grüßen).
///
/// `null` heißt still „keine Ebene": Vorschau aus, Ebene aus, Stapel
/// nicht tief genug (erst nach dem 26-Tage-Update, #256) oder keine
/// Stationstabelle. Das Regen-Blatt erklärt den häufigsten Fall.
final ampelFillProvider = FutureProvider<AmpelFill?>((ref) async {
  if (!ref.watch(ampelLayerEnabledProvider)) return null;
  // ALLE Watches VOR den Awaits — die Riverpod-Lehre aus #255/#257.
  final palette = ref.watch(ampelPaletteProvider);
  final grid = await ref.watch(ampelLevelGridProvider.future);
  if (grid == null) return null;
  return compute(_fill, (grid: grid, palette: palette));
});

AmpelFill _fill(({AmpelLevelGrid grid, AmpelPalette palette}) input) =>
    ampelFillOfLevels(input.grid, palette: input.palette);

/// Dieselbe Fläche als Datei — der MapLibre-Weg (`image`-Quelle nimmt
/// eine URL). Der jüngste Stapel-Tag ist der Stand im Dateinamen;
/// [RainGridRepository.writeFill] räumt alte Stände weg.
final ampelFillFileProvider =
    FutureProvider<({String url, AmpelFill fill})?>((ref) async {
  // Beides VOR dem Await beobachten (Riverpod-Lehre) — und die
  // Farbfamilie gehört in den DATEINAMEN: Die MapLibre-Strecke ist
  // idempotent auf der URL. Ein Bild mit neuen Farben unter altem Namen
  // würde schlicht nicht getauscht, und die Karte zeigte still die alte
  // Familie weiter (genau so passiert beim Wald mit der Klassenwahl,
  // siehe `forestFillStamp`).
  final palette = ref.watch(ampelPaletteProvider);
  final repository = ref.watch(rainGridRepositoryProvider);
  final fill = await ref.watch(ampelFillProvider.future);
  if (fill == null) return null;
  final url = await repository.writeFill('ampel', fill.newest, fill.png,
      variant: palette.name);
  return url == null ? null : (url: url, fill: fill);
});
