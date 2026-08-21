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

  test('hängt alle drei Ebenen ein — Quelle vor Ebene', () async {
    final style = RecordingStyle();
    final key = await applyContourLines(style,
        geoJson: geoJsonOf('a'), appliedKey: null);

    expect(key, 'a');
    expect(style.calls, [
      'addSource:$contourSourceId',
      'addLayer:$contourLayerId',
      'addSource:$contourIndexSourceId',
      'addLayer:$contourIndexLayerId',
      'addLayer:$contourLabelLayerId',
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
    expect(style.calls.take(5), [
      'removeLayer:$contourLabelLayerId',
      'removeLayer:$contourIndexLayerId',
      'removeLayer:$contourLayerId',
      'removeSource:$contourIndexSourceId',
      'removeSource:$contourSourceId',
    ]);
    expect(style.layers.map((l) => l.id),
        [contourLayerId, contourIndexLayerId, contourLabelLayerId]);
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
    bool scalar(Object? value) =>
        value is String || value is num || value is bool;
    for (final layer in style.layers) {
      for (final entry in layer.paint.entries) {
        expect(scalar(entry.value), isTrue,
            reason: '${layer.id}.${entry.key} ist kein Skalar');
      }
      for (final entry in layer.layout.entries) {
        // Listen sind erlaubt, aber nur aus Skalaren: `text-font` ist
        // eine, ein Style-Ausdruck wäre eine mit einem Operator vorn.
        final value = entry.value;
        expect(
            scalar(value) || (value is List && value.every(scalar)),
            isTrue,
            reason: '${layer.id}.${entry.key} ist kein Skalar');
        if (value is List) {
          expect(value.first, isNot(anyOf('get', 'case', 'match', 'concat')),
              reason: '${layer.id}.${entry.key} sieht nach einem Ausdruck '
                  'aus — der käme als Object[] in der Engine an');
        }
      }
    }
  });

  test('die Hauptlinien liegen kräftiger und oben', () async {
    final style = RecordingStyle();
    await applyContourLines(style, geoJson: geoJsonOf('a'), appliedKey: null);
    final layers = style.layers.whereType<ml.LineStyleLayer>().toList();
    final normal = layers.firstWhere((l) => l.id == contourLayerId);
    final index = layers.firstWhere((l) => l.id == contourIndexLayerId);

    expect((index.paint['line-width']! as num),
        greaterThan(normal.paint['line-width']! as num));
    expect((index.paint['line-opacity']! as num),
        greaterThan(normal.paint['line-opacity']! as num));
    // Zuletzt hinzugefügt heißt obenauf: Die Hauptlinie darf von einer
    // Nebenlinie nicht überzeichnet werden.
    expect(layers.last.id, contourIndexLayerId);
    // Und beide sind zurückgenommen: Die Ebene ist eine Zugabe, keine
    // zweite Karte (Betreiber, 2026-08-21 — „too much").
    expect(normal.paint['line-opacity']! as num, lessThan(0.4));
    expect(index.paint['line-opacity']! as num, lessThan(0.7));
  });

  test('die Zahlen sitzen auf den Hauptlinien und stehen nie auf dem Kopf',
      () async {
    // Ohne Zahl sagt eine Höhenlinie nur „hier ist es steiler als dort",
    // nicht ob es hinauf oder hinunter geht (Betreiber, 2026-08-21).
    final style = RecordingStyle();
    await applyContourLines(style, geoJson: geoJsonOf('a'), appliedKey: null);
    final labels = style.layers.firstWhere((l) => l.id == contourLabelLayerId);

    expect(labels, isA<ml.SymbolStyleLayer>());
    // Auf der Quelle der HAUPTlinien: jede fünfte bekommt eine Zahl,
    // die Zwischenlinien zählt man ab.
    expect((labels as ml.StyleLayerWithSource).sourceId,
        contourIndexSourceId);
    expect(labels.layout['symbol-placement'], 'line');
    expect(labels.layout['text-field'], '{m}',
        reason: 'die Eigenschaft, die contourGeoJson schreibt');
    expect(labels.layout['text-font'], [contourLabelFont]);
    expect(labels.layout['text-keep-upright'], isTrue);
    // Ohne Hof verschwindet die Zahl auf der Linie, die unter ihr
    // durchläuft.
    expect((labels.paint['text-halo-width']! as num), greaterThan(0));

    // Und ganz oben: Eine Zahl unter einer Linie ist keine Zahl.
    expect(style.layers.last.id, contourLabelLayerId);
  });

  test('die Quellen tragen die Namensnennung', () async {
    final style = RecordingStyle();
    await applyContourLines(style, geoJson: geoJsonOf('a'), appliedKey: null);
    for (final source in style.sources.cast<ml.GeoJsonSource>()) {
      expect(source.attribution, contains('Copernicus'));
    }
  });
}
