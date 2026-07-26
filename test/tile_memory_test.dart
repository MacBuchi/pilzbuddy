// Das Kachel-Budget (Issue #142).
//
// Gerechnet wird wie bei MapLibre: Kacheln im Sichtfeld × vorgehaltene
// Zoomstufen. Der Test nagelt die Ableitung fest, nicht eine Zahl — sonst
// steht in einem Jahr eine Konstante da, die niemand mehr begründen kann.
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/tile_memory.dart';

void main() {
  // Der Bild-Cache hängt am Binding; ohne das gibt es kein `instance`.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Das Budget folgt der Bildschirmgröße', () {
    // Pixel 7 Pro: 1080×2340 ⇒ 5×10 = 50 Kacheln im Sichtfeld, ×3 Stufen.
    final klein = tileImageBudget(const Size(1080, 2340));
    // Tablet-Format: mehr Fläche ⇒ mehr Kacheln ⇒ größeres Budget.
    final gross = tileImageBudget(const Size(1600, 2560));

    expect(klein.maxImages, 150);
    expect(gross.maxImages, greaterThan(klein.maxImages));
  });

  test('Die Leitplanken greifen nach unten und nach oben', () {
    // Ein winziges Sichtfeld darf das Budget nicht auf null drücken —
    // sonst wird jede sichtbare Kachel neu dekodiert (Flackern).
    final winzig = tileImageBudget(const Size(100, 100));
    expect(winzig.maxImages, 100);
    expect(winzig.maxBytes, 32 << 20);

    // Und ein riesiges nicht ins Uferlose: sonst ist der Sinn dahin.
    final riesig = tileImageBudget(const Size(8000, 8000));
    expect(riesig.maxImages, 400);
    expect(riesig.maxBytes, 96 << 20);
  });

  test('Angewendet ist das Budget kleiner als Flutters Vorgabe', () {
    // Die Vorgabe ist 1000 Bilder / 100 MB und wird mit Icons und Avataren
    // geteilt. Bliebe sie stehen, wäre die Änderung wirkungslos.
    applyTileImageBudget(const Size(1080, 2340));
    final cache = PaintingBinding.instance.imageCache;

    expect(cache.maximumSize, lessThan(1000));
    expect(cache.maximumSizeBytes, lessThan(100 << 20));
    expect(cache.maximumSize, 150);
  });

  test('Ohne bekannte Bildschirmgröße gilt trotzdem ein Budget', () {
    applyTileImageBudget(null);
    expect(PaintingBinding.instance.imageCache.maximumSize, lessThan(1000));
  });
}
