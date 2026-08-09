// Die Provider-Kette der feinen Waldstufe (#253): Zustimmung als
// Torwächter, Blöcke unterm Fenster, die kombinierte Sicht — und dass
// der Zeichner fein malt, sobald der Verbund das Fenster deckt.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/settings.dart';
import 'package:pilzbuddy/features/map/forest_block_providers.dart';
import 'package:pilzbuddy/features/map/forest_data_providers.dart';
import 'package:pilzbuddy/features/map/forest_fill_window.dart';
import 'package:pilzbuddy/features/map/forest_grid.dart';
import 'package:pilzbuddy/features/map/map_view/marker_culling.dart'
    show MapViewBounds;

import 'fakes/fake_settings.dart';
import 'forest_blocks_test.dart' show cutHexGrid;
import 'forest_grid_test.dart' show hexOf;

/// Fürs Testen der Zeichner-Pfade: ein festes, KLEINES Fenster statt des
/// Planers — der plant immer die volle Budget-Kante (1536 px), und zwei
/// Megapixel-PNGs je Test sind Wartezeit ohne Aussage. Die Planer-Logik
/// selbst hat ihre eigenen Tests (`forest_fill_window_test.dart`).
class _FixedWindow extends ForestFillWindowNotifier {
  _FixedWindow(this.window);

  final FillWindow window;

  @override
  FillWindow? build() => window;
}

const _smallWindow = FillWindow(
    west: 10.0,
    east: 10.024,
    north: 49.999,
    south: 49.981,
    width: 24,
    height: 18);

void main() {
  // Basis: 6×6 Nadel-Waben (Asset). Feine Stufe: dieselbe Box in
  // Blöcken, überall Laub und ein ANDERES Referenzjahr — jede Antwort
  // verrät damit ihre Quelle.
  ForestGrid base() => hexOf([
        for (var hy = 0; hy < 6; hy++) List<int>.filled(6, 96),
      ]);
  final fine = cutHexGrid([
    for (var hy = 0; hy < 6; hy++) List<int>.filled(6, 11),
  ], referenceYear: 2025);
  const bounds =
      MapViewBounds(west: 10.004, east: 10.018, north: 49.996, south: 49.99);

  ProviderContainer containerWith({
    required bool consent,
    List<String>? catalogLog,
    List<String>? blockLog,
    FillWindow? window,
    Set<String> withhold = const {},
  }) {
    final container = ProviderContainer(overrides: [
      settingsProvider
          .overrideWithValue(FakeSettings(forestFineEnabled: consent)),
      forestGridLoaderProvider.overrideWithValue(() async => base()),
      forestBlockCatalogLoaderProvider.overrideWithValue(() async {
        catalogLog?.add('catalog');
        return fine.catalog;
      }),
      forestBlockGridLoaderProvider.overrideWithValue((catalog, info) async {
        blockLog?.add(info.file);
        if (withhold.contains(info.file)) return null;
        return fine.grids[info.file];
      }),
      if (window != null)
        forestFillWindowProvider.overrideWith(() => _FixedWindow(window)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('ohne Zustimmung wird nicht einmal der Katalog angefasst', () async {
    final catalogLog = <String>[];
    final container = containerWith(consent: false, catalogLog: catalogLog);
    await container.read(forestGridProvider.future);
    container.read(mapIdleBoundsProvider.notifier).state = bounds;
    expect(await container.read(forestBlockSetProvider.future), isNull);
    expect(catalogLog, isEmpty,
        reason: 'der Schalter verspricht: keine Verbindung von sich aus');
  });

  test('mit Zustimmung: Blöcke unterm Fenster, die Sicht antwortet fein',
      () async {
    final container = containerWith(consent: true);
    await container.read(forestGridProvider.future);
    container.read(mapIdleBoundsProvider.notifier).state = bounds;
    expect(container.read(forestFillWindowProvider), isNotNull);

    final set = await container.read(forestBlockSetProvider.future);
    expect(set, isNotNull);
    expect(set!.covers(container.read(forestFillWindowProvider)!), isTrue);

    final view = container.read(forestViewProvider)!;
    expect(view.classAt(49.994, 10.011), ForestClass.broadleaf,
        reason: 'die feine Stufe (Laub) überstimmt das Asset (Nadel)');
    expect(view.referenceYearAt(49.994, 10.011), 2025);
  });

  test('kleines Schieben lädt nicht neu — die Hysterese trägt bis hierher',
      () async {
    final blockLog = <String>[];
    final container = containerWith(consent: true, blockLog: blockLog);
    await container.read(forestGridProvider.future);
    container.read(mapIdleBoundsProvider.notifier).state = bounds;
    await container.read(forestBlockSetProvider.future);
    final loadsAfterFirst = blockLog.length;
    expect(loadsAfterFirst, greaterThan(0));

    // Ein Stück innerhalb des gerenderten Kastens: Das Fenster bleibt
    // DIESELBE Instanz, also darf auch kein Block neu angefragt werden.
    container.read(mapIdleBoundsProvider.notifier).state = const MapViewBounds(
        west: 10.005, east: 10.019, north: 49.995, south: 49.989);
    await container.read(forestBlockSetProvider.future);
    expect(blockLog.length, loadsAfterFirst,
        reason: 'gleiches Fenster ⇒ kein neuer Lade-Lauf');
  });

  test('der Zeichner malt fein, sobald der Verbund das Fenster deckt',
      () async {
    final container = containerWith(consent: true, window: _smallWindow);
    container.read(forestLayerEnabledProvider.notifier).state = true;
    await container.read(forestGridProvider.future);
    await container.read(forestBlockSetProvider.future);

    final fill = await container.read(forestFillProvider.future);
    expect(fill, isNotNull);
    expect(fill!.fine, isTrue);
    expect(fill.referenceYear, 2025,
        reason: 'das Jahr des Katalogs, nicht des Assets');
  });

  test('fehlt auch nur ein Block des Fensters, malt der Zeichner GANZ grob',
      () async {
    // Die Naht-Regel des Zeichners: halb fein, halb grob gibt es nicht.
    // Ein gescheiterter Download heißt fürs BILD komplette Rückkehr zum
    // Asset — die Punktabfragen dürfen die geladenen Blöcke trotzdem
    // nutzen (dafür steht die Sicht, nicht das Bild).
    final container = containerWith(
        consent: true,
        window: _smallWindow,
        withhold: const {'forest_block_x1_y1.bin.gz'});
    container.read(forestLayerEnabledProvider.notifier).state = true;
    await container.read(forestGridProvider.future);
    final set = await container.read(forestBlockSetProvider.future);
    expect(set, isNotNull, reason: 'fünf von sechs Blöcken sind da');

    final fill = await container.read(forestFillProvider.future);
    expect(fill!.fine, isFalse);
    expect(fill.referenceYear, 2024);
  });

  test('ohne Zustimmung malt der Zeichner grob — wie bisher', () async {
    final container = containerWith(consent: false, window: _smallWindow);
    container.read(forestLayerEnabledProvider.notifier).state = true;
    await container.read(forestGridProvider.future);

    // BEWUSST ohne den Verbund vorher aufzulösen: Der Zeichner startet
    // hier, während der Verbund-Provider noch lädt. Mit dem `ref.watch`
    // nach dem await (erster Wurf von #253) kam der Provider genau in
    // dieser Lage NIE zur Ruhe — dieser `await` lief in den Timeout.
    final fill = await container.read(forestFillProvider.future);
    expect(fill, isNotNull);
    expect(fill!.fine, isFalse);
    expect(fill.referenceYear, 2024);
  });
}
