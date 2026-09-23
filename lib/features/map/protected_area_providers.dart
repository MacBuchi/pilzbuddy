// Laden der Schutzgebiete (#580) — Muster wie beim Waldgitter.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'protected_areas.dart';

/// Wie die Schutzgebiete beschafft werden — die Test-Naht:
/// `test/fakes/test_app.dart` überschreibt sie auf `null`, sonst läse
/// jeder Flow-Test das echte Asset.
final protectedAreasLoaderProvider =
    Provider<Future<ProtectedAreas?> Function()>((ref) => _loadFromAssets);

/// Lädt Manifest und Läufe aus den Assets, packt im Isolate aus.
///
/// `null` bei jedem Fehler — ohne Schutzgebiete malt die Fläche wie vor
/// 1.201.0 und der Hinweis beim Eintragen bleibt weg. Das ist die
/// harmlose Richtung NICHT: Ein fehlender Hinweis sieht aus wie „hier
/// ist keins". Deshalb prüft `test/protected_areas_asset_test.dart`, dass
/// das echte Asset lädt — ein kaputtes Asset ist ein Baufehler und soll
/// in CI auffallen, nicht im Wald.
Future<ProtectedAreas?> _loadFromAssets() async {
  try {
    final manifest = await rootBundle
        .loadString('assets/protected/protected_manifest.json');
    final data =
        await rootBundle.load('assets/protected/protected_grid.bin.gz');
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return await compute(_decode, (manifest: manifest, bytes: bytes));
  } catch (_) {
    // Fehlendes/kaputtes Asset ⇒ keine Schutzgebiete. Begründung oben.
    return null;
  }
}

ProtectedAreas? _decode(({String manifest, Uint8List bytes}) input) {
  try {
    return ProtectedAreas.decode(input.bytes, input.manifest);
  } on FormatException {
    return null;
  }
}

/// Die geladenen Schutzgebiete — einmal je App-Lauf.
///
/// **Beobachten ist laden**: Wer das beobachtet, packt 0,6 MB Läufe und
/// 0,6 MB Namen aus. Die Fläche tut es nur, wenn Wald oder Ampel
/// ohnehin malen; der Hinweis nur im offenen Eintrage-Blatt.
final protectedAreasProvider = FutureProvider<ProtectedAreas?>(
    (ref) => ref.watch(protectedAreasLoaderProvider)());
