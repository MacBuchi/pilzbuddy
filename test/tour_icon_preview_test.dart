// Kontaktbogen für das Tour-Symbol (#343) — dieselbe Disziplin wie beim
// Pilz-Vorschaubogen: rendern und ANSEHEN, nicht nur analysieren.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/tour/widgets/tour_icon.dart';

void main() {
  testWidgets('Vorschau', (tester) async {
    const dir = String.fromEnvironment('PILZ_PREVIEW_DIR');
    if (dir.isEmpty) return;
    await tester.binding.setSurfaceSize(const Size(420, 130));
    await tester.pumpWidget(MaterialApp(
      home: ColoredBox(
        color: const Color(0xFFEFEFEF),
        child: Center(
          child: RepaintBoundary(
            child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final s in [18.0, 24.0, 36.0, 64.0, 96.0])
                IconTheme(
                  data: const IconThemeData(color: Color(0xFF2E2E2E)),
                  child: TourIcon(size: s),
                ),
              // Und einmal weiß auf Grün — der Zustand „Tour läuft".
              const ColoredBox(
                color: Color(0xFF2E7D32),
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: IconTheme(
                    data: IconThemeData(color: Colors.white),
                    child: TourIcon(size: 24),
                  ),
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    final image = await (tester.firstRenderObject(find.byType(RepaintBoundary))
            as RenderRepaintBoundary)
        .toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/tour_icon.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
