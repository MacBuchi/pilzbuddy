// Reißleine für die temporäre Absturzsuche (siehe
// lib/debug/sentry_crash_hunt.dart).
//
// Dieser Test ist ABSICHTLICH ROT, solange `sentry_flutter` in der
// pubspec steht. Er ist die Bremse davor, den Sonderbuild zu vergessen und
// einen Absturzdienst mit auszuliefern: Jeder Versions-Bump auf `main`
// veröffentlicht die APK öffentlich, und #111 hat einen Absturzdienst für
// die ausgelieferte App bewusst abgelehnt (laufende Kosten, weiterer
// Auftragsverarbeiter in der Datenschutzerklärung, der dort nicht steht).
//
// Grün wird er wieder, wenn die Abhängigkeit und
// `lib/debug/sentry_crash_hunt.dart` entfernt sind. Ein Merge dieses
// Branches nach `main` scheitert damit an CI — genau so gewollt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Kein Absturzdienst in der ausgelieferten App', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec.contains('sentry'), isFalse,
        reason: 'sentry_flutter steckt noch in der pubspec. Das ist in '
            'Ordnung, SOLANGE dieser Branch nicht nach main geht: Der '
            'Sonderbuild wird lokal gebaut und per adb installiert, nie '
            'veröffentlicht. Vor dem Ausbau: pubspec-Eintrag weg, '
            'lib/debug/sentry_crash_hunt.dart löschen, den Block in '
            'main.dart entfernen — dann wird dieser Test grün.');
  });

  test('Die Debug-Datei existiert nur zusammen mit der Abhängigkeit', () {
    // Der umgekehrte Fehler: Datei bleibt liegen, Abhängigkeit ist weg —
    // dann bricht der Build mit einem unauffindbaren Import.
    final debugFile = File('lib/debug/sentry_crash_hunt.dart');
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(debugFile.existsSync(), pubspec.contains('sentry'),
        reason: 'Datei und Abhängigkeit gehören zusammen — beide da oder '
            'beide weg.');
  });
}
