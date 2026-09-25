// Das Bild eines Highlights (#596) schaukelt — außer, das System sagt
// „Animationen entfernen".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/highlights/feature_highlights.dart';
import 'package:pilzbuddy/features/highlights/highlight_art.dart';

double angle(WidgetTester tester) => tester
    .widgetList<Transform>(find.descendant(
        of: find.byType(HighlightArt), matching: find.byType(Transform)))
    .map((t) => t.transform.storage[1]) // sin des Drehwinkels
    .fold(0.0, (a, b) => a + b.abs());

Future<Set<double>> angles(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
      home: Center(child: HighlightArt(highlight: kFeatureHighlights.first))));
  final seen = <double>{};
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 300));
    seen.add(angle(tester));
  }
  return seen;
}

void main() {
  testWidgets('schaukelt ab Werk', (tester) async {
    expect((await angles(tester)).length, greaterThan(1));
  });

  testWidgets('steht still bei „Animationen entfernen"', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    expect(await angles(tester), {0.0});
  });
}
