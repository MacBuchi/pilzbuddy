// Der Sichtfenster-Planer der Waldfläche (#249): Wann wird neu gemalt,
// wann trägt das alte Bild noch?
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/forest_data_providers.dart';
import 'package:pilzbuddy/features/map/forest_fill_window.dart';
import 'package:pilzbuddy/features/map/map_view/marker_culling.dart';

import 'forest_grid_test.dart' show forestOf;

void main() {
  // Die echte DACH-Box des Gitters.
  const gridWest = 5.8, gridEast = 17.3, gridNorth = 55.1, gridSouth = 45.7;

  FillWindow? plan(MapViewBounds viewport, {FillWindow? previous}) =>
      planFillWindow(
        previous: previous,
        viewport: viewport,
        gridWest: gridWest,
        gridEast: gridEast,
        gridNorth: gridNorth,
        gridSouth: gridSouth,
      );

  test('erster Plan: Sichtfenster plus 50 % Rand, Budget eingehalten', () {
    final window = plan(const MapViewBounds(
        west: 10, east: 11, south: 50.5, north: 51.5))!;
    expect(window.west, closeTo(9.5, 1e-9));
    expect(window.east, closeTo(11.5, 1e-9));
    expect(window.south, closeTo(50.0, 1e-9));
    expect(window.north, closeTo(52.0, 1e-9));
    // Budget: die längste Kante ist exakt der Deckel, keine größer.
    expect(
        [window.width, window.height].reduce((a, b) => a > b ? a : b),
        fillWindowBudget);
    // Bei 2° Länge zu 2° Breite ist die Mercator-Höhe größer (Breite
    // schrumpft mit cos φ) — das Bild ist höher als breit.
    expect(window.height, greaterThan(window.width));
  });

  test('kleines Schieben im Rand: DERSELBE Plan, kein Neumalen', () {
    const start = MapViewBounds(west: 10, east: 11, south: 50.5, north: 51.5);
    final first = plan(start)!;
    // Ein Viertel Fensterbreite nach Osten — noch im 50-%-Rand.
    const shifted =
        MapViewBounds(west: 10.25, east: 11.25, south: 50.5, north: 51.5);
    expect(plan(shifted, previous: first), isNull,
        reason: '`null` heißt: das alte Fenster trägt noch — der '
            'Aufrufer behält die Instanz, stromabwärts rechnet niemand');
  });

  test('Schieben aus dem Kasten hinaus plant neu', () {
    const start = MapViewBounds(west: 10, east: 11, south: 50.5, north: 51.5);
    final first = plan(start)!;
    const far =
        MapViewBounds(west: 13, east: 14, south: 50.5, north: 51.5);
    final second = plan(far, previous: first);
    expect(second, isNotNull);
    expect(second!.west, greaterThan(first.east),
        reason: 'der neue Kasten liegt um das neue Sichtfenster');
  });

  test('tiefes Hineinzoomen plant neu — für die Schärfe', () {
    const start = MapViewBounds(west: 10, east: 11, south: 50.5, north: 51.5);
    final first = plan(start)!;
    // Ein Zehntel der Spanne, mittig im alten Kasten: enthalten, aber
    // das alte Bild wäre auf ein Vielfaches gestreckt.
    const zoomed = MapViewBounds(
        west: 10.45, east: 10.55, south: 50.95, north: 51.05);
    final second = plan(zoomed, previous: first);
    expect(second, isNotNull);
    expect(second!.east - second.west, lessThan(1),
        reason: 'der neue Kasten ist eng um das kleine Sichtfenster');
  });

  test('am Gitterrand wird beschnitten statt hinausgemalt', () {
    final window = plan(const MapViewBounds(
        west: 5.0, east: 7.0, south: 54.5, north: 56.0))!;
    expect(window.west, gridWest);
    expect(window.north, gridNorth);
  });

  test('ohne Schnitt mit dem Gitter gibt es nichts', () {
    expect(
        plan(const MapViewBounds(
            west: -3, east: -1, south: 50, north: 51)),
        isNull);
    // Und ein bestehender Plan wird dadurch nicht ersetzt (`null` =
    // behalten; das alte Bild ist ohnehin außer Sicht).
    final first = plan(const MapViewBounds(
        west: 10, east: 11, south: 50.5, north: 51.5))!;
    expect(
        plan(const MapViewBounds(west: -3, east: -1, south: 50, north: 51),
            previous: first),
        isNull);
  });

  test('der Notifier hält die Instanz — das Gedächtnis der Hysterese', () async {
    // Die Naht zwischen Planer und Providern: Gibt der Planer `null`
    // zurück, muss stromabwärts DIESELBE Instanz stehen — sonst rechnet
    // der Fill-Provider trotz „behalten" neu, und die Hysterese wäre
    // nur Dekoration.
    final container = ProviderContainer(overrides: [
      forestGridLoaderProvider.overrideWithValue(() async => forestOf([
            [11, 96],
            [96, 11],
          ], west: 5.8, east: 17.3, north: 55.1, south: 45.7)),
    ]);
    addTearDown(container.dispose);
    await container.read(forestGridProvider.future);

    container.read(mapIdleBoundsProvider.notifier).state =
        const MapViewBounds(west: 10, east: 11, south: 50.5, north: 51.5);
    final first = container.read(forestFillWindowProvider);
    expect(first, isNotNull);

    container.read(mapIdleBoundsProvider.notifier).state =
        const MapViewBounds(west: 10.25, east: 11.25, south: 50.5, north: 51.5);
    expect(identical(container.read(forestFillWindowProvider), first), isTrue,
        reason: 'kleines Schieben: dieselbe Instanz, kein Neumalen');

    container.read(mapIdleBoundsProvider.notifier).state =
        const MapViewBounds(west: 13, east: 14, south: 50.5, north: 51.5);
    expect(identical(container.read(forestFillWindowProvider), first), isFalse,
        reason: 'weit geschoben: neuer Plan');
  });

  test('der Schlüssel unterscheidet Ausschnitte deterministisch', () {
    final a = plan(const MapViewBounds(
        west: 10, east: 11, south: 50.5, north: 51.5))!;
    final b = plan(const MapViewBounds(
        west: 13, east: 14, south: 50.5, north: 51.5))!;
    expect(a.key, isNot(b.key));
    final again = plan(const MapViewBounds(
        west: 10, east: 11, south: 50.5, north: 51.5))!;
    expect(a.key, again.key,
        reason: 'gleicher Ausschnitt, gleicher Name — sonst schriebe '
            'jeder Stillstand eine neue Datei');
  });
}
