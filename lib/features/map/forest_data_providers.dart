// Das Waldtypen-Gitter auf dem Gerät (#213).
//
// Anders als beim Regen gibt es hier keinen Download und keine
// Zustimmung: Das Gitter liegt als Asset im APK — die Frage „in welchen
// Wald fahre ich" stellt sich gern dort, wo kein Empfang ist, und ein
// Asset kostet niemanden Datenvolumen.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'forest_fill.dart';
import 'forest_fill_window.dart';
import 'forest_grid.dart';
import 'map_view/marker_culling.dart' show MapViewBounds;
import 'rain_data_providers.dart' show rainGridRepositoryProvider;

/// Ob die Waldebene auf der Karte liegt. Session-lokal wie der
/// Regen-Layer und der Filter (#154) — eine über Nacht vergessene Ebene
/// verwirrt mehr, als der eine Tipp zum Wiedereinschalten kostet.
final forestLayerEnabledProvider = StateProvider<bool>((ref) => false);

/// Welche Waldklassen als Teil-Ebenen eingeblendet sind (#231).
///
/// Standard: alle drei. Session-lokal wie der Schalter darüber — und
/// der eigentliche Zweck ist #232: Neben der Regenfläche lässt man nur
/// die Klasse stehen, die einen interessiert, statt dass die ganze
/// Karte unter zwei Schleiern abstumpft.
final forestClassesProvider =
    StateProvider<Set<ForestClass>>((ref) => allForestClasses);

/// Wie das Gitter beschafft wird — die Test-Naht, exakt das Muster der
/// drei Regen-Loader: `test/fakes/test_app.dart` überschreibt sie auf
/// `null`, sonst läse jeder Flow-Test echte Assets.
final forestGridLoaderProvider =
    Provider<Future<ForestGrid?> Function()>((ref) => _loadFromAssets);

/// Lädt Manifest + Gitter aus den Assets, packt im Isolate aus.
///
/// `null` bei jedem Fehler — dieselbe stille Degradation wie überall auf
/// der Karte: Ein kaputtes Asset ist ein Baufehler, den `flutter test`
/// mit dem echten Asset fängt (Phase C), kein Laufzeitereignis, das dem
/// Sammler eine Fehlermeldung wert wäre. Ohne Gitter fehlt die Ebene
/// still, der FAB erscheint gar nicht erst.
Future<ForestGrid?> _loadFromAssets() async {
  try {
    final manifestRaw =
        await rootBundle.loadString('assets/forest/forest_manifest.json');
    final data = await rootBundle.load('assets/forest/forest_grid.bin.gz');
    final bytes = data.buffer
        .asUint8List(data.offsetInBytes, data.lengthInBytes);
    return await compute(_decode, (manifest: manifestRaw, bytes: bytes));
  } catch (_) {
    // Fehlendes/kaputtes Asset ⇒ keine Ebene. Begründung oben.
    return null;
  }
}

ForestGrid? _decode(({String manifest, Uint8List bytes}) input) {
  try {
    final manifest = jsonDecode(input.manifest) as Map<String, dynamic>;
    return ForestGrid.decode(
      input.bytes,
      width: manifest['width'] as int,
      height: manifest['height'] as int,
      west: (manifest['west'] as num).toDouble(),
      east: (manifest['east'] as num).toDouble(),
      north: (manifest['north'] as num).toDouble(),
      south: (manifest['south'] as num).toDouble(),
      referenceYear: manifest['reference_year'] as int,
    );
  } catch (_) {
    return null;
  }
}

/// Das geladene Gitter — einmal je App-Lauf, danach aus dem Cache.
final forestGridProvider = FutureProvider<ForestGrid?>(
    (ref) => ref.watch(forestGridLoaderProvider)());

/// Das Sichtfenster beim letzten Kamera-Stillstand — gesetzt vom
/// Karten-Screen über `MapViewConfig.onCameraIdle`, das Geschwister der
/// Stillstands-Mitte (`mapIdleCenterProvider` in `widgets/map_legend.dart`).
/// Hier und nicht dort, weil sein einziger Kunde der Wald-Bildausschnitt
/// ist (#249).
final mapIdleBoundsProvider = StateProvider<MapViewBounds?>((ref) => null);

/// Der geplante Bildausschnitt der Waldfläche (#249).
///
/// Ein Notifier statt eines abgeleiteten Providers, weil die Hysterese
/// GEDÄCHTNIS braucht: Kleines Schieben innerhalb des gerenderten
/// Kastens gibt DIESELBE Instanz zurück, und Riverpod lässt dann alles
/// stromabwärts in Ruhe — sonst wäre jeder Kamera-Stillstand ein
/// Isolate-Lauf mit Megapixel-PNG.
class ForestFillWindowNotifier extends Notifier<FillWindow?> {
  FillWindow? _last;

  @override
  FillWindow? build() {
    final bounds = ref.watch(mapIdleBoundsProvider);
    final grid = ref.watch(forestGridProvider).valueOrNull;
    if (bounds == null || grid == null) return _last;
    _last = planFillWindow(
          previous: _last,
          viewport: bounds,
          gridWest: grid.west,
          gridEast: grid.east,
          gridNorth: grid.north,
          gridSouth: grid.south,
        ) ??
        _last;
    return _last;
  }
}

final forestFillWindowProvider =
    NotifierProvider<ForestFillWindowNotifier, FillWindow?>(
        ForestFillWindowNotifier.new);

/// Das eingefärbte PNG samt seiner Grenzen — gerechnet im Isolate, und
/// nur wenn die Ebene an ist: Wer sie nie einschaltet, zahlt weder
/// Rechenzeit noch Speicher.
///
/// Seit #249 wird nur der geplante BILDAUSSCHNITT gemalt (höchstens
/// [fillWindowBudget] Pixel Kantenlänge, ~9 MB Puffer) statt ganz DACH
/// (52 MB). Während der Neurechnung behält `valueOrNull` den alten Stand
/// — das alte Bild bleibt also stehen, bis das neue fertig ist, statt
/// bei jeder Verschiebung durchzublitzen.
final forestFillProvider = FutureProvider<ForestFillImage?>((ref) async {
  if (!ref.watch(forestLayerEnabledProvider)) return null;
  final classes = ref.watch(forestClassesProvider);
  if (classes.isEmpty) return null; // alles abgewählt = nichts zu zeichnen
  final window = ref.watch(forestFillWindowProvider);
  if (window == null) return null; // noch kein Kamera-Stillstand
  final grid = await ref.watch(forestGridProvider.future);
  if (grid == null) return null;
  final png =
      await compute(_fill, (grid: grid, classes: classes, window: window));
  return ForestFillImage(
    png: png,
    west: window.west,
    east: window.east,
    north: window.north,
    south: window.south,
    referenceYear: grid.referenceYear,
    classes: classes,
    windowKey: window.key,
  );
});

Uint8List _fill(
        ({ForestGrid grid, Set<ForestClass> classes, FillWindow window})
            input) =>
    forestFillPng(input.grid, classes: input.classes, window: input.window);


/// Der „Stand" für den Dateinamen der Fläche — kodiert Jahr UND
/// Klassenwahl.
///
/// Die MapLibre-Strecke ist idempotent auf der URL: Ein PNG mit anderer
/// Klassenwahl unter demselben Namen würde schlicht nicht getauscht,
/// und die Karte zeigte still die alte Auswahl. Deshalb wandert die
/// Wahl als Bitmaske in den Tag des Stempels (1 + Maske ⇒ 2.–8. Januar
/// des Referenzjahres); [RainGridRepository.writeFill] räumt dabei wie
/// immer die vorigen Stände desselben Prefixes weg.
DateTime forestFillStamp(int referenceYear, Set<ForestClass> classes) {
  var mask = 0;
  if (classes.contains(ForestClass.broadleaf)) mask |= 1;
  if (classes.contains(ForestClass.mixed)) mask |= 2;
  if (classes.contains(ForestClass.conifer)) mask |= 4;
  return DateTime.utc(referenceYear, 1, 1 + mask);
}

/// Dieselbe Fläche als Datei auf Platte — der Weg für MapLibre, dessen
/// `image`-Quelle eine URL nimmt und keine Bytes.
///
/// Bewusst OHNE `family`, wie beim Regen: Die MapLibre-Ansicht hängt
/// sich per `ref.listen` daran, und ein wechselnder Familienschlüssel
/// wäre dort ein zweiter Zuhörer statt eines geänderten Werts.
///
/// Geschrieben wird über [RainGridRepository.writeFill] — das ist der
/// Dateiablage-Teil des Regen-Repositories und bewusst wiederverwendet:
/// Er kennt bereits das Muster „Stand im Namen, alte Stände wegräumen,
/// bei jedem Aufruf neu schreiben" (Farb-/Deckkraft-Änderungen einer
/// neuen App-Version kämen sonst nie an, am Emulator so passiert).
/// Als „Stand" dient das Referenzjahr des Gitters.
final forestFillFileProvider =
    FutureProvider<({String url, ForestFillImage fill})?>((ref) async {
  final fill = await ref.watch(forestFillProvider.future);
  if (fill == null) return null;
  final url = await ref.watch(rainGridRepositoryProvider).writeFill(
      'forest', forestFillStamp(fill.referenceYear, fill.classes), fill.png,
      variant: fill.windowKey);
  return url == null ? null : (url: url, fill: fill);
});

/// Das fertige Bild mit den Grenzen SEINES Gitters — nicht irgendeiner
/// Konstante: Wenn CI die Bounding Box je ändert, wandert das Bild mit
/// (die Lehre aus dem Regen-Fill, wo Bild- und Gitter-Grenzen um ~20 km
/// auseinanderlagen).
class ForestFillImage {
  const ForestFillImage({
    required this.png,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.referenceYear,
    required this.classes,
    required this.windowKey,
  });

  final Uint8List png;
  final double west;
  final double east;
  final double north;
  final double south;
  final int referenceYear;

  /// Die Klassenwahl, mit der dieses PNG gerechnet wurde — sie gehört
  /// zum Bild wie seine Grenzen und bestimmt den Datei-Stand
  /// ([forestFillStamp]), sonst tauscht MapLibre das Bild nicht.
  final Set<ForestClass> classes;

  /// Der Schlüssel des gemalten Ausschnitts ([FillWindow.key], #249) —
  /// aus demselben Grund im Dateinamen wie die Klassenwahl im Stempel:
  /// Ein neuer Ausschnitt unter altem Namen würde von MapLibre schlicht
  /// nicht getauscht.
  final String windowKey;
}
