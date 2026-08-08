// Die Regenfläche in der MapLibre-Engine.
//
// Die Ansicht selbst ist im Widget-Test nicht erreichbar (Platform-Views
// rendern dort nicht) — deshalb liegt alles Prüfbare im Applier, und der
// bekommt hier einen Style-Controller, der mitschreibt statt zu zeichnen.
// Dieselbe Arbeitsteilung wie beim Style-Composer.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:pilzbuddy/features/map/forest_data_providers.dart'
    show ForestFillImage;
import 'package:pilzbuddy/features/map/forest_fill.dart'
    show allForestClasses;
import 'package:pilzbuddy/features/map/map_view/maplibre_forest_fill.dart';
import 'package:pilzbuddy/features/map/map_view/maplibre_image_fill.dart'
    show fillRemovalNeedsNudge;
import 'package:pilzbuddy/features/map/map_view/maplibre_rain_fill.dart';
import 'package:pilzbuddy/features/map/rain_data_providers.dart';

/// Ein Style-Controller, der nur Buch führt.
class RecordingStyle extends ml.StyleController {
  RecordingStyle({this.rejectBelow = false});

  /// Ahmt die Engine nach, solange es die Linienebene noch nicht gibt:
  /// `addLayerBelow` mit unbekannter Id scheitert.
  final bool rejectBelow;

  final calls = <String>[];
  final sources = <ml.Source>[];
  final layers = <ml.StyleLayer>[];
  final below = <String, String?>{};

  @override
  Future<void> addSource(ml.Source source) async {
    calls.add('addSource:${source.id}');
    sources.add(source);
  }

  @override
  Future<void> addLayer(
    ml.StyleLayer layer, {
    String? belowLayerId,
    String? aboveLayerId,
    int? atIndex,
  }) async {
    if (belowLayerId != null && rejectBelow) {
      throw Exception('No layer with id $belowLayerId');
    }
    calls.add('addLayer:${layer.id}');
    layers.add(layer);
    below[layer.id] = belowLayerId;
  }

  @override
  Future<void> removeLayer(String id) async {
    calls.add('removeLayer:$id');
    layers.removeWhere((l) => l.id == id);
  }

  @override
  Future<void> removeSource(String id) async {
    calls.add('removeSource:$id');
    sources.removeWhere((s) => s.id == id);
  }

  /// Die zuletzt über [updateGeoJsonSource] gesetzten Daten — die
  /// Beschriftung tauscht bei jedem Zoomwechsel nur diese aus.
  String? updated;

  @override
  Future<void> updateGeoJsonSource(
      {required String id, required String data}) async {
    updated = data;
  }

  @override
  Future<void> addImage(String id, Uint8List bytes) async {}

  @override
  Future<void> removeImage(String id) async {}

  @override
  Future<List<String>> getAttributions() async => const [];

  @override
  List<String> getAttributionsSync() => const [];

  @override
  List<String> getLayerIds() => [for (final layer in layers) layer.id];

  @override
  void setProjection(ml.MapProjection projection) {}

  @override
  void dispose() {}
}

void main() {
  ({String url, RainFill fill}) fillAt(String url,
          {DateTime? measured,
          double west = 5.73,
          double east = 15.17,
          double north = 55.06,
          double south = 47.07}) =>
      (
        url: url,
        fill: RainFill(
          png: Uint8List(0),
          west: west,
          east: east,
          north: north,
          south: south,
          measured: measured ?? DateTime.utc(2026, 8, 4),
        ),
      );

  test('hängt Quelle und Ebene ein', () async {
    final style = RecordingStyle();
    final url =
        await applyRainFill(style, fill: fillAt('file:///a.png'), appliedUrl: null);

    expect(url, 'file:///a.png');
    expect(style.calls,
        ['addSource:$rainFillSourceId', 'addLayer:$rainFillLayerId']);
    expect(style.below[rainFillLayerId], isNull,
        reason: 'seit 1.48.0 liegt nichts Eigenes mehr über der Fläche — '
            'die Höhenlinien sind weg, die Marker sind Flutter-Widgets');
  });

  test('tauscht einen neuen Messstand aus, statt ihn danebenzulegen',
      () async {
    final style = RecordingStyle();
    await applyRainFill(style, fill: fillAt('file:///alt.png'), appliedUrl: null);
    style.calls.clear();

    final url = await applyRainFill(style,
        fill: fillAt('file:///neu.png'), appliedUrl: 'file:///alt.png');

    expect(url, 'file:///neu.png');
    expect(style.calls, [
      'removeLayer:$rainFillLayerId',
      'removeSource:$rainFillSourceId',
      'addSource:$rainFillSourceId',
      'addLayer:$rainFillLayerId',
    ]);
    expect(style.sources.single, isA<ml.ImageSource>());
    expect((style.sources.single as ml.ImageSource).url, 'file:///neu.png');
  });

  test('rührt nichts an, wenn derselbe Stand schon liegt', () async {
    // Ein Rebuild je Kamerabewegung darf die Bildquelle nicht jedes Mal
    // neu aufbauen — das ist ein Dekodier-Auftrag für 550 000 Zellen.
    final style = RecordingStyle();
    final url = await applyRainFill(style,
        fill: fillAt('file:///a.png'), appliedUrl: 'file:///a.png');

    expect(url, 'file:///a.png');
    expect(style.calls, isEmpty);
  });

  test('nimmt Ebene UND Quelle weg, wenn die Regenebene ausgeht', () async {
    // Nur die Ebene zu entfernen ließe die Bildquelle im Style stehen —
    // sie hält das dekodierte Bild und damit den Speicher.
    final style = RecordingStyle();
    await applyRainFill(style, fill: fillAt('file:///a.png'), appliedUrl: null);
    style.calls.clear();

    final url =
        await applyRainFill(style, fill: null, appliedUrl: 'file:///a.png');

    expect(url, isNull);
    expect(style.calls,
        ['removeLayer:$rainFillLayerId', 'removeSource:$rainFillSourceId']);
    expect(style.sources, isEmpty);
    expect(style.layers, isEmpty);
  });

  test('nach dem Entfernen braucht die Engine einen Stups — nach dem '
      'Hinzufügen nicht', () {
    // maplibre-native zeichnet nach dem Entfernen einer Ebene nicht von
    // selbst neu; der Stups muss HINTER dem tatsächlichen Entfernen
    // kommen, nicht beim Provider-Wechsel davor (#230: „Ebene aus" ließ
    // die Fläche stehen, bis jemand zoomte).
    // Entfernen und Ersetzen: Stups.
    expect(fillRemovalNeedsNudge(before: 'file:///a.png', after: null),
        isTrue);
    expect(
        fillRemovalNeedsNudge(
            before: 'file:///a.png', after: 'file:///b.png'),
        isTrue);
    // Erstes Hinzufügen und Unverändert: die ladende Quelle stößt
    // selbst an bzw. es gibt nichts anzustoßen.
    expect(fillRemovalNeedsNudge(before: null, after: 'file:///a.png'),
        isFalse);
    expect(
        fillRemovalNeedsNudge(
            before: 'file:///a.png', after: 'file:///a.png'),
        isFalse);
    expect(fillRemovalNeedsNudge(before: null, after: null), isFalse);
  });

  ForestFillImage forestFillImageAt() => ForestFillImage(
        png: Uint8List(0),
        west: 5.8,
        east: 17.3,
        north: 55.1,
        south: 45.7,
        referenceYear: 2024,
        classes: allForestClasses,
      );

  test('der Wald legt sich UNTER eine liegende Regenfläche (#232)',
      () async {
    // Regen ist die flüchtige Information — er bleibt obenauf lesbar.
    // Ohne belowLayerId landete ein später eingeschalteter Wald über
    // dem Regen, weil neue Ebenen schlicht angehängt werden.
    final style = RecordingStyle();
    await applyRainFill(style, fill: fillAt('file:///r.png'),
        appliedUrl: null);

    await applyForestFill(style,
        fill: (url: 'file:///w.png', fill: forestFillImageAt()),
        appliedUrl: null,
        belowLayerId: rainFillLayerId);
    expect(style.below[forestFillLayerId], rainFillLayerId);

    // Ohne liegenden Regen wird KEIN belowLayerId übergeben — ein
    // Verweis auf eine fehlende Ebene wäre plattformabhängig.
    final alone = RecordingStyle(rejectBelow: true);
    await applyForestFill(alone,
        fill: (url: 'file:///w.png', fill: forestFillImageAt()),
        appliedUrl: null);
    expect(alone.below[forestFillLayerId], isNull);
  });

  test('verortet die Fläche auf den Grenzen des GITTERS', () async {
    // Nicht auf denen der DWD-Bildebene: Das Gitter ist auf seine Zellen
    // mit Daten beschnitten, die Bildebene deckt mehr ab — der
    // Unterschied wären rund zwanzig Kilometer Versatz gegen die eigenen
    // Linien.
    final style = RecordingStyle();
    await applyRainFill(style,
        fill: fillAt('file:///a.png',
            west: 5.73, east: 15.17, north: 55.06, south: 47.07),
        appliedUrl: null);

    final source = style.sources.single as ml.ImageSource;
    expect(source.coordinates.topLeft.lon, 5.73);
    expect(source.coordinates.topLeft.lat, 55.06);
    expect(source.coordinates.bottomRight.lon, 15.17);
    expect(source.coordinates.bottomRight.lat, 47.07);
  });

  test('lässt die Durchsichtigkeit im Bild, nicht in der Ebene', () async {
    // Die Deckkraft steckt schon in den Bildpunkten (rainFillAlpha).
    // Zweimal abgeschwächt wäre die Fläche nicht mehr zu sehen.
    final style = RecordingStyle();
    await applyRainFill(style, fill: fillAt('file:///a.png'), appliedUrl: null);

    expect(style.layers.single.paint['raster-opacity'], 1.0);
  });

  test('zeichnet die Bandränder weich', () async {
    // Bewusste Kehrtwende gegenüber dem DWD-Bild, das hart bleibt: Seit
    // die Fläche die Aussage trägt (1.48.0, keine Linien mehr), traten
    // bei 55 % Deckkraft die 1-km-Treppenstufen an jeder Bandgrenze
    // hervor — grob, und im Widerspruch zu den geglätteten Konturen, aus
    // denen die Beschriftung in der Karte kommt. Zwei Darstellungen
    // desselben Felds dürfen nicht verschieden aussehen.
    //
    // Die Genauigkeit leidet nicht: Der Wert am Spot kommt aus dem rohen
    // Gitter, nicht aus diesem Bild.
    final style = RecordingStyle();
    await applyRainFill(style, fill: fillAt('file:///a.png'), appliedUrl: null);

    expect(style.layers.single.paint['raster-resampling'], 'linear');
  });
}
