// Die gemeldeten Fundorte (GBIF, #467) auf dem Gerät: Asset laden,
// Bildausschnitt planen, Fläche malen — dasselbe Gerüst wie beim Wald
// (`forest_data_providers.dart`), nur ohne Blöcke und ohne Kombi-Modus.
//
// **Die Ebene folgt dem FILTER.** Welche Arten und welche Ampel-Gruppen
// gezeichnet werden, sagt `SpotFilter` (`species`, `classes`, beide
// „leer = alle") — kein zweiter Artenwähler. Bis hierher stand bei
// `classes`, es sei „der einzige Filter, der auch die FLÄCHE betrifft";
// seit dieser Ebene sind es zwei, und die #154-Regel trägt beide: Was
// die Karte enger macht, steht im Filter-Chip.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import 'forest_data_providers.dart' show mapIdleBoundsProvider;
import 'forest_fill_window.dart';
import 'gbif_fill.dart';
import 'gbif_finds.dart';
import 'map_overlays.dart';
import 'rain_data_providers.dart' show rainGridRepositoryProvider;
import 'spot_filter.dart' show spotFilterProvider;

/// Ob die Fundorte auf der Karte liegen — über den Neustart hinaus
/// gemerkt, wie Wald und Höhenlinien (Begründung bei
/// [Settings.forestLayerEnabled]).
final gbifLayerEnabledProvider = NotifierProvider<RememberedFlag, bool>(
  () => RememberedFlag(
    read: (s) => s.gbifLayerEnabled,
    write: (s, v) => s.setGbifLayerEnabled(v),
    label: 'Fundorte-Ebene merken',
  ),
);

/// Wie das Asset beschafft wird — die Test-Naht, exakt das Muster von
/// `forestGridLoaderProvider`: `test/fakes/test_app.dart` überschreibt
/// sie auf `null`, sonst läse jeder Flow-Test das echte Asset.
final gbifFindsLoaderProvider =
    Provider<Future<GbifFinds?> Function()>((ref) => _loadFromAssets);

/// Lädt Manifest + Spalten aus den Assets, packt im Isolate aus.
///
/// `null` bei jedem Fehler — dieselbe stille Degradation wie überall auf
/// der Karte: Ein kaputtes Asset ist ein Baufehler, den
/// `test/gbif_finds_test.dart` mit dem echten Asset fängt, kein
/// Laufzeitereignis. Ohne Asset fehlt die Ebene, und das Blatt sagt es.
Future<GbifFinds?> _loadFromAssets() async {
  try {
    final manifest =
        await rootBundle.loadString('assets/gbif/gbif_finds_manifest.json');
    final data = await rootBundle.load('assets/gbif/gbif_finds.bin.gz');
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return await compute(_decode, (manifest: manifest, bytes: bytes));
  } catch (_) {
    // Fehlendes/kaputtes Asset ⇒ keine Ebene. Begründung oben.
    return null;
  }
}

GbifFinds? _decode(({String manifest, Uint8List bytes}) input) {
  try {
    return GbifFinds.decode(input.bytes, input.manifest);
  } catch (_) {
    return null;
  }
}

/// Das geladene Asset — einmal je App-Lauf, danach aus dem Cache.
///
/// **Beobachten ist laden** (CLAUDE.md): Wer das hier beobachtet, packt
/// 0,6 MB aus. Deshalb hängt es nur an der eingeschalteten Ebene und am
/// „Was ist hier?"-Blatt — nie an einem Knopf oder der Legende.
final gbifFindsProvider =
    FutureProvider<GbifFinds?>((ref) => ref.watch(gbifFindsLoaderProvider)());

/// Der geplante Bildausschnitt — eigener Notifier mit Gedächtnis wie
/// `ForestFillWindowNotifier`, und bewusst NICHT dessen Fenster: Das
/// hängt am Waldgitter, und diese Ebene soll das Waldgitter nicht laden.
class GbifFillWindowNotifier extends Notifier<FillWindow?> {
  FillWindow? _last;

  @override
  FillWindow? build() {
    final bounds = ref.watch(mapIdleBoundsProvider);
    final finds = ref.watch(gbifFindsProvider).valueOrNull;
    if (bounds == null || finds == null) return _last;
    _last = planFillWindow(
          previous: _last,
          viewport: bounds,
          gridWest: finds.west,
          gridEast: finds.east,
          gridNorth: finds.north,
          gridSouth: finds.south,
        ) ??
        _last;
    return _last;
  }
}

final gbifFillWindowProvider =
    NotifierProvider<GbifFillWindowNotifier, FillWindow?>(
        GbifFillWindowNotifier.new);

/// Der Filter-Anteil, der die Fläche bestimmt — als Record mit
/// zusammengefügten Zeichenketten, nicht als Mengen: Zwei inhaltlich
/// gleiche Mengen sind für `==` verschieden, und die Fläche würde bei
/// jedem Neuaufbau neu gemalt (dieselbe Falle wie beim Karten-Nachlauf).
typedef GbifFilterKey = ({String species, String classes});

final gbifFilterKeyProvider = Provider<GbifFilterKey>((ref) {
  final filter = ref.watch(spotFilterProvider);
  return (
    species: (filter.species.toList()..sort()).join('|'),
    classes: (filter.classes.toList()..sort()).join('|'),
  );
});

/// Das gemalte PNG samt Grenzen — im Isolate, und nur wenn die Ebene an
/// ist. Während der Neurechnung behält `valueOrNull` den alten Stand.
final gbifFillProvider = FutureProvider<GbifFillImage?>((ref) async {
  if (!ref.watch(gbifLayerEnabledProvider)) return null;
  // Der Vorhang (#464) — VOR jedem Asset-Zugriff, wie beim Wald.
  if (ref.watch(mapOverlaysHiddenProvider)) return null;
  final window = ref.watch(gbifFillWindowProvider);
  if (window == null) return null;
  // Watch-vor-Await, wie überall hier.
  final filterKey = ref.watch(gbifFilterKeyProvider);
  final finds = await ref.watch(gbifFindsProvider.future);
  if (finds == null) return null;
  final species = filterKey.species.isEmpty
      ? const <String>{}
      : filterKey.species.split('|').toSet();
  final classes = filterKey.classes.isEmpty
      ? const <String>{}
      : filterKey.classes.split('|').toSet();
  final paint = gbifPaintFor(finds, species: species, classes: classes);
  final png = await compute(
      _fill, (finds: finds, window: window, paint: paint));
  return GbifFillImage(
    png: png,
    west: window.west,
    east: window.east,
    north: window.north,
    south: window.south,
    windowKey: window.key,
    filterKey: filterKey,
    fetchedOn: finds.fetchedOn,
  );
});

Uint8List _fill(
        ({GbifFinds finds, FillWindow window, GbifPaint paint}) input) =>
    gbifFillPng(input.finds, window: input.window, paint: input.paint);

/// Dieselbe Fläche als Datei — der Weg für MapLibre (`image`-Quelle
/// nimmt eine URL). Über [RainGridRepository.writeFill] wie der Wald;
/// als „Stand" dient das Abrufdatum des Downloads.
final gbifFillFileProvider =
    FutureProvider<({String url, GbifFillImage fill})?>((ref) async {
  final fill = await ref.watch(gbifFillProvider.future);
  if (fill == null) return null;
  final url = await ref.watch(rainGridRepositoryProvider).writeFill(
      'gbif', gbifFillStamp(fill.fetchedOn), fill.png,
      variant: gbifFillVariant(fill));
  return url == null ? null : (url: url, fill: fill);
});

/// Der Datei-Stand: das Abrufdatum des GBIF-Downloads, sonst ein fester
/// Tag — ein neuer Download bekommt so einen neuen Namen.
DateTime gbifFillStamp(String? fetchedOn) =>
    DateTime.tryParse(fetchedOn ?? '') ?? DateTime.utc(2026, 1, 1);

/// Fenster und Filter im Dateinamen — die MapLibre-Strecke ist
/// idempotent auf der URL: gleicher Name, altes Bild (dieselbe Falle wie
/// bei Klassenwahl und Fenster des Waldes).
String gbifFillVariant(GbifFillImage fill) {
  final filter = '${fill.filterKey.species}#${fill.filterKey.classes}';
  return '${fill.windowKey}_f${filter.hashCode.toRadixString(16)}';
}

class GbifFillImage {
  const GbifFillImage({
    required this.png,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.windowKey,
    required this.filterKey,
    required this.fetchedOn,
  });

  final Uint8List png;
  final double west;
  final double east;
  final double north;
  final double south;
  final String windowKey;
  final GbifFilterKey filterKey;
  final String? fetchedOn;
}
