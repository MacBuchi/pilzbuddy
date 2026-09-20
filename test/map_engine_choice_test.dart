// Die Engine-Wahl der MapView-Fassade: **Android MapLibre, Web
// flutter_map** — seit #433 ohne Schalter dazwischen.
//
// Der Profil-Schalter davor war ein Opt-out auf die alte Engine, gedacht
// als befristete Rückfalllinie. Die Frist ist um: MapLibre steht seit
// 1.43.0 vorn, und in zehn Wochendigests steht kein einziger Fund gegen
// ihn (der eine karten-nahe Treffer ist der Kamera-Wächter, der seine
// Arbeit tut).
//
// **Was NICHT verschwindet, ist `flutter_map_view.dart`.** Der
// Android-Build trägt es weiter, weil `maplibre_map_view.dart` selbst
// darauf zurückfällt, wenn der Style nicht baut — ohne Style lieber die
// alte Karte als gar keine. Genau das prüft der letzte Test hier.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/core/settings.dart';
import 'package:pilzbuddy/features/map/map_view/map_view.dart';
import 'package:pilzbuddy/features/map/map_view/maplibre_map_view.dart';

import 'fakes/fake_settings.dart';

void main() {
  final config = const MapViewConfig(
    initialCenter: LatLng(51.1634, 10.4477),
    initialZoom: 6.5,
    minZoom: 3,
    maxZoom: 19,
    backgroundColor: AppColors.mapBackground,
  );

  MapViewBuilder builderFor(ProviderContainer container) =>
      container.read(mapViewBuilderProvider);

  test('Ohne Schalter: Android bekommt MapLibre', () {
    // `kIsWeb` ist eine Kompilierzeit-Konstante, und dieser Test läuft
    // auf der VM — dort ist sie falsch, die Fassade wählt also den
    // Android-Zweig. Der Web-Zweig ist von hier aus prinzipiell nicht
    // erreichbar; ihn deckt `test/spot_cache_idb_test.dart`-artig nur
    // ein echter dart2js-Lauf ab, und dafür lohnt er nicht.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = MapViewController(
        initialCenter: config.initialCenter, initialZoom: 6.5);

    expect(builderFor(container)(config, controller, const MapViewMarkers()),
        isA<MapLibreMapView>());
  });

  test('Die Wahl hängt an keiner Einstellung mehr', () {
    // Die Gegenprobe zum Rückbau: Ein Provider, der noch an
    // `settingsProvider` hinge, würde hier einen anderen Wert liefern,
    // sobald man die Einstellungen austauscht. Tut er nicht — er liest
    // gar nichts mehr.
    final a = ProviderContainer(
        overrides: [settingsProvider.overrideWithValue(FakeSettings())]);
    final b = ProviderContainer(overrides: [
      settingsProvider.overrideWithValue(FakeSettings(mapLegendOpen: false)),
    ]);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final controller = MapViewController(
        initialCenter: config.initialCenter, initialZoom: 6.5);

    expect(builderFor(a)(config, controller, const MapViewMarkers()).runtimeType,
        builderFor(b)(config, controller, const MapViewMarkers()).runtimeType);
  });

  test('Die alte Engine bleibt als Rückfall IM Android-Build', () {
    // Die Zusage, die den Rückbau begrenzt — und die Korrektur an der
    // Annahme im Issue: Es wird nichts kleiner. Baut der Style nicht,
    // zeigt die MapLibre-Ansicht die flutter_map-Karte statt einer
    // leeren Fläche. Wer diese Zeile entfernt, macht aus einem
    // Style-Fehler eine Karte, die es nicht gibt.
    final native = File('lib/features/map/map_view/maplibre_map_view.dart')
        .readAsStringSync();
    expect(native, contains('return FlutterMapView('),
        reason: 'ohne Style lieber die alte Karte als gar keine');
  });

  test('Kein Schalter mehr im Profil und keine Einstellung dazu', () {
    // Ein Rückbau, der die Oberfläche stehen lässt, ist keiner: Der
    // Schalter hätte dann keine Wirkung mehr und wäre eine Lüge.
    final profile =
        File('lib/features/profile/profile_screen.dart').readAsStringSync();
    final settings = File('lib/core/settings.dart').readAsStringSync();

    expect(profile, isNot(contains('Karten-Engine')));
    expect(settings, isNot(contains('classicMapEnabled')));
    expect(File('lib/features/map/map_view/map_engine.dart').existsSync(),
        isFalse,
        reason: 'der Notifier der Engine-Wahl ist ersatzlos weg');
  });

  test('Beide Engines verankern den Quellenhinweis unten links', () {
    // **Warum am Quelltext und nicht am Widget-Baum.** Die
    // MapLibre-Strecke ist eine native GL-Fläche; sie lässt sich im
    // Widget-Test nicht aufbauen, also gibt es dort kein
    // `tester.widget<SourceAttribution>`. Dasselbe Loch hat die Fassade
    // schon zweimal Geld gekostet — der `alignment`-Fehler (#409) blieb
    // von 1.43.0 bis 1.122.0 unbemerkt, WEIL nur eine der beiden Seiten
    // geprüft war. Eine Textsuche ist grob, aber sie ist mehr als
    // nichts, und sie fällt auf, sobald jemand eine Seite anfasst.
    //
    // Geprüft wird die Zusage, nicht die Formatierung: Beide Dateien
    // müssen `bottomLeft` an ihrem Attributions-Widget tragen, und
    // KEINE darf noch `bottomRight` dafür setzen.
    final classic =
        File('lib/features/map/map_view/flutter_map_view.dart')
            .readAsStringSync();
    final native =
        File('lib/features/map/map_view/maplibre_map_view.dart')
            .readAsStringSync();

    expect(classic, contains('AttributionAlignment.bottomLeft'),
        reason: 'unten rechts läge der Hinweis unter „Neuer Spot"');
    expect(classic, isNot(contains('AttributionAlignment.bottomRight')));
    expect(native, contains('SourceAttribution('));
    expect(
        RegExp(r'SourceAttribution\(\s*\n\s*alignment: Alignment\.bottomLeft')
            .hasMatch(native),
        isTrue,
        reason: 'die native Strecke muss dieselbe Ecke nehmen');
  });
}
