// Die Höhenlinien in der MapLibre-Engine.
//
// Die Ansicht selbst ist im Widget-Test nicht erreichbar (Platform-Views
// rendern dort nicht) — deshalb liegt alles Prüfbare im Applier, und der
// bekommt hier denselben mitschreibenden Style-Controller wie die
// Flächen.
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:pilzbuddy/features/map/map_view/maplibre_contour_lines.dart';
import 'package:pilzbuddy/features/map/map_view/maplibre_image_fill.dart'
    show fillRemovalNeedsNudge;

import 'maplibre_rain_fill_test.dart' show RecordingStyle;

void main() {
  ContourGeoJson geoJsonOf(String key) => (
        normal: '{"type":"FeatureCollection","features":[]}',
        index: '{"type":"FeatureCollection","features":[]}',
        key: key,
      );

  test('hängt beide Ebenen ein — Quelle vor Ebene', () async {
    final style = RecordingStyle();
    final key = await applyContourLines(style,
        geoJson: geoJsonOf('a'), appliedKey: null);

    expect(key, 'a');
    expect(style.calls, [
      'addSource:$contourSourceId',
      'addLayer:$contourLayerId',
      'addSource:$contourIndexSourceId',
      'addLayer:$contourIndexLayerId',
    ]);
  });

  test('dieselbe Kennung rührt nichts an', () async {
    final style = RecordingStyle();
    await applyContourLines(style, geoJson: geoJsonOf('a'), appliedKey: 'a');
    expect(style.calls, isEmpty,
        reason: 'sonst legte jeder Kamera-Stillstand die Ebenen neu an');
  });

  test('neue Kennung tauscht aus, statt zu stapeln', () async {
    final style = RecordingStyle();
    await applyContourLines(style, geoJson: geoJsonOf('a'), appliedKey: null);
    style.calls.clear();
    final key = await applyContourLines(style,
        geoJson: geoJsonOf('b'), appliedKey: 'a');

    expect(key, 'b');
    expect(style.calls.take(4), [
      'removeLayer:$contourIndexLayerId',
      'removeLayer:$contourLayerId',
      'removeSource:$contourIndexSourceId',
      'removeSource:$contourSourceId',
    ]);
    expect(style.layers.map((l) => l.id),
        [contourLayerId, contourIndexLayerId]);
    expect(style.sources.map((s) => s.id),
        [contourSourceId, contourIndexSourceId]);
  });

  test('null nimmt Ebenen UND Quellen weg — und braucht einen Stups',
      () async {
    final style = RecordingStyle();
    await applyContourLines(style, geoJson: geoJsonOf('a'), appliedKey: null);
    style.calls.clear();
    final key =
        await applyContourLines(style, geoJson: null, appliedKey: 'a');

    expect(key, isNull);
    expect(style.layers, isEmpty);
    expect(style.sources, isEmpty);
    // maplibre-native zeichnet nach dem Entfernen nicht von selbst neu.
    expect(fillRemovalNeedsNudge(before: 'a', after: null), isTrue);
    expect(fillRemovalNeedsNudge(before: null, after: 'a'), isFalse);
  });

  test('jeder Paint-Wert ist ein Skalar — keine Ausdrücke', () async {
    // `maplibre` 0.3.5 schickt Paint-Werte durch `toJObject()`, das nur
    // String, Zahl, Bool, Liste und Map kennt. Ein Style-Ausdruck käme
    // dort als `Object[]` an und nicht als Ausdruck — die Ebene sähe
    // dann anders aus, ohne dass irgendwo ein Fehler stünde. Deshalb
    // zwei Ebenen mit je einer festen Breite statt einer mit `case`.
    final style = RecordingStyle();
    await applyContourLines(style, geoJson: geoJsonOf('a'), appliedKey: null);
    for (final layer in style.layers.cast<ml.LineStyleLayer>()) {
      for (final entry in layer.paint.entries) {
        expect(entry.value, anyOf(isA<String>(), isA<num>(), isA<bool>()),
            reason: '${layer.id}.${entry.key} ist kein Skalar');
      }
    }
  });

  test('die Hauptlinien liegen kräftiger und oben', () async {
    final style = RecordingStyle();
    await applyContourLines(style, geoJson: geoJsonOf('a'), appliedKey: null);
    final layers = style.layers.cast<ml.LineStyleLayer>().toList();
    final normal = layers.firstWhere((l) => l.id == contourLayerId);
    final index = layers.firstWhere((l) => l.id == contourIndexLayerId);

    expect((index.paint['line-width']! as num),
        greaterThan(normal.paint['line-width']! as num));
    expect((index.paint['line-opacity']! as num),
        greaterThan(normal.paint['line-opacity']! as num));
    // Zuletzt hinzugefügt heißt obenauf: Die Hauptlinie darf von einer
    // Nebenlinie nicht überzeichnet werden.
    expect(layers.last.id, contourIndexLayerId);
  });

  test('die Quellen tragen die Namensnennung', () async {
    final style = RecordingStyle();
    await applyContourLines(style, geoJson: geoJsonOf('a'), appliedKey: null);
    for (final source in style.sources.cast<ml.GeoJsonSource>()) {
      expect(source.attribution, contains('Copernicus'));
    }
  });
}
