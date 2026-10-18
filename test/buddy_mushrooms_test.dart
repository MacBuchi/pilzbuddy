// Die schaukelnden Pilze (Anmeldung, Update-Sperre, Tour-Start) dürfen
// beim Schaukeln weder sich selbst noch die Seite neu zeichnen (#689, B3):
// Im Web hielt das den Hauptthread zu ~60 % beschäftigt.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/widgets/buddy_mushrooms.dart';
import 'package:pilzbuddy/core/widgets/mushroom_icon.dart';

/// Was die Grenze zuletzt gezeichnet hat. Zeichnet sie neu, entsteht eine
/// neue Bildschicht; bleibt sie liegen, wird die alte nur wiederverwendet.
/// (Die Zähler `debug…PaintCount` taugen dafür nicht: Der asymmetrische
/// zählt auch den Fall „nur der Elternteil zeichnete" — also genau den
/// Erfolg.)
Layer? _picture(RenderRepaintBoundary b) => b.debugLayer!.firstChild;

/// Die nächste Neuzeichen-Grenze über [finder] — dort landet jedes
/// Neuzeichnen, das ihn betrifft.
RenderRepaintBoundary _boundaryAbove(WidgetTester tester, Finder finder) {
  RenderObject? node = tester.renderObject(finder);
  while (node is! RenderRepaintBoundary) {
    node = node!.parent;
  }
  return node;
}

void main() {
  testWidgets(
      'Schaukeln zeichnet weder die Pilze noch die Seite neu — '
      'nur der Winkel ändert sich', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          BuddyMushrooms(height: 110),
          Text('Seite'),
        ]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    final icon = find.byType(MushroomIcon).first;
    final paint =
        find.descendant(of: icon, matching: find.byType(CustomPaint)).first;
    final mushroomBoundary = _boundaryAbove(tester, paint);
    final pageBoundary = _boundaryAbove(tester, find.text('Seite'));
    final mushroomPicture = _picture(mushroomBoundary);
    final pagePicture = _picture(pageBoundary);
    final before = tester.getTopLeft(icon);

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Die Animation lief wirklich — sonst bewiese der Rest nichts.
    expect(tester.getTopLeft(icon), isNot(before));
    expect(_picture(mushroomBoundary), same(mushroomPicture),
        reason: 'das Pilzbild wird je Takt neu gezeichnet');
    expect(_picture(pageBoundary), same(pagePicture),
        reason: 'die Seite wird je Takt neu gezeichnet');
  });

  testWidgets(
      'nach einem Schwung stehen die Pilze still und gerade — '
      'Antippen weckt sie für eine Runde', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: BuddyMushrooms(height: 110))),
    ));
    // Im ersten Bild ist der Ausschlag 0 — das ist „gerade“. Beide Pilze,
    // denn der kleine schwingt versetzt und bliebe ohne Auslaufen schief
    // stehen.
    final icons = find.byType(MushroomIcon);
    List<Offset> pose() => [
          for (final e in icons.evaluate())
            tester.getTopLeft(find.byWidget(e.widget)),
        ];
    final upright = pose();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isTrue,
        reason: 'die Pilze schaukeln nach dem Öffnen');
    expect(pose(), isNot(upright));

    await tester.pump(const Duration(seconds: 2));
    // Kein Bild mehr angefordert: Die Seite kostet in Ruhe nichts.
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'die Animation läuft nach dem Schwung weiter');
    expect(pose(), upright, reason: 'ein Pilz bleibt schief stehen');

    await tester.tap(icons.first);
    await tester.pump(); // das erste Bild startet die Uhr der Animation
    await tester.pump(const Duration(milliseconds: 500));
    expect(pose(), isNot(upright), reason: 'Antippen weckt die Pilze nicht');
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(pose(), upright);
  });
}
