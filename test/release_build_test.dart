// Bewacht die Bauweise der Release-Artefakte — Dinge, die kein Widget-Test
// bemerkt und die erst am fertigen Download auffallen würden.
//
// Anlass: In 1.43.0 bestanden 22,4 MB der 66,8-MB-APK aus nativen
// Bibliotheken für Architekturen, auf denen die App gar nicht startet
// (`libmaplibre.so` dreimal, zweimal ohne passende `libflutter.so`).
// `--target-platform android-arm64` beschränkt nämlich nur Flutters eigene
// Artefakte; die nativen Teile der Plugins packt Gradle unabhängig davon
// ein. Niemand hätte den Rückfall bemerkt — die APK wäre nur wieder
// stillschweigend ein Drittel größer.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Der Build-Befehl, der mit [needle] beginnt — zusammengesetzt, weil er im
/// Workflow über mehrere Zeilen läuft (`run: >`).
///
/// Zeilenweise zu lesen wäre der naheliegende Weg und still falsch: Sobald
/// ein Befehl auf `run: >` umgestellt wird, sieht ein `indexOf('\n')` nur
/// noch dessen erste Zeile — jede Zusicherung über die weiteren Schalter
/// wäre dann grün, ohne etwas zu prüfen.
String _buildCommand(String workflow, String needle) {
  final start = workflow.indexOf(needle);
  expect(start, isNot(-1), reason: 'Kein "$needle" in release.yml gefunden');
  final rest = workflow.substring(start);
  // Bis zum nächsten YAML-Schlüssel auf Schritt-Ebene ("      - " / "      #").
  final end = rest.indexOf(RegExp(r'\n\s*(- |#)'));
  return rest
      .substring(0, end == -1 ? rest.length : end)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

void main() {
  final release = File('.github/workflows/release.yml').readAsStringSync();

  test('Die APK wird nur für arm64 gebaut — mit BEIDEN Schaltern', () {
    final command = _buildCommand(release, 'flutter build apk');

    expect(command, contains('--target-platform android-arm64'),
        reason: 'Ohne die Beschränkung enthält die APK Flutter-Engine und '
            'App-Code dreifach.');

    // Der zweite Schalter ist der, den man beim Aufräumen für überflüssig
    // hält: Ohne ihn setzt der Flutter-Gradle-Plugin die ABI-Filter selbst,
    // per `abiFilters.clear()` auf alle drei (FlutterPlugin.kt,
    // configureAbiWithoutSplits) — und überschreibt damit den Filter aus
    // android/app/build.gradle.kts. Die toten 22 MB wären zurück.
    expect(command, contains('-Pdisable-abi-filtering=true'),
        reason: 'Ohne diesen Schalter überschreibt der Flutter-Plugin den '
            'ABI-Filter aus build.gradle.kts wieder mit allen drei ABIs.');
  });

  test('Das AAB bleibt universal — Play splittet selbst pro Gerät', () {
    final command = _buildCommand(release, 'flutter build appbundle');

    expect(command, isNot(contains('--target-platform')),
        reason: 'Ein beschränktes AAB sperrt Play-Geräte aus, die die App '
            'ausführen könnten — dort ist das Splitten Play-Sache.');
    expect(command, isNot(contains('disable-abi-filtering')),
        reason: 'Im AAB soll Flutters eigene Filterung greifen.');
  });

  test('Jeder Vertriebsweg baut seinen Flavor — und holt dessen Datei ab', () {
    // Der Flavor entscheidet, ob REQUEST_INSTALL_PACKAGES im Artefakt
    // steht: `play` nimmt sie per `tools:node="remove"` heraus (Play
    // verbietet Selbst-Updates), `github` braucht sie, weil genau dieser
    // Weg sich aus dem GitHub-Release aktualisiert.
    final apk = _buildCommand(release, 'flutter build apk');
    final aab = _buildCommand(release, 'flutter build appbundle');

    expect(apk, contains('--flavor github'),
        reason: 'Ohne Flavor bricht der Build ab, sobald welche existieren');
    expect(aab, contains('--flavor play'),
        reason: 'Ein AAB aus dem github-Flavor trägt eine Berechtigung, zu '
            'der im Play-Build keine Funktion gehört — genau daran '
            'scheitern Play-Reviews');

    // PLAY_BUILD und der Flavor sind zwei Hälften derselben Entscheidung:
    // das Flag schaltet den Dart-Pfad ab, der Flavor die Berechtigung. Wer
    // nur eine setzt, liefert eine halb abgeschaltete Funktion aus.
    expect(aab, contains('--dart-define=PLAY_BUILD=true'),
        reason: 'Ohne das Flag zeigt der Play-Build Update-Hinweise, die '
            'dort unzulässig sind');
    expect(apk, isNot(contains('PLAY_BUILD')),
        reason: 'Die GitHub-APK behält ihren Update-Hinweis');

    // Der Flavor steht auch im Ausgabepfad. Ein `cp` auf den alten,
    // flavorlosen Namen bricht erst NACH dem Taggen ab — und ein Tag ohne
    // Release ist nur von Hand zu heilen (Mitfahrbar v0.34.1).
    expect(release, contains('flutter-apk/app-github-release.apk'),
        reason: 'Mit Flavor heißt die Datei app-<flavor>-release.apk');
    expect(release, contains('bundle/playRelease/app-play-release.aab'),
        reason: 'Mit Flavor liegt das Bundle in bundle/<flavor>Release/');
  });

  test('build.gradle.kts leitet den ABI-Filter aus --target-platform ab', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('target-platform'),
        reason: 'Der Filter hängt an derselben Eigenschaft, die Flutter für '
            '--target-platform ohnehin an Gradle durchreicht — dadurch '
            'greift er beim AAB (das die Eigenschaft nicht setzt) nicht.');
    expect(gradle, contains('abiFilters'));

    // --split-per-abi wäre der naheliegende Griff und die Falle: Der
    // Flutter-Plugin überschreibt dabei den versionCode mit
    // `ABI-Nummer * 1000 + versionCode`. Aus 85 würde 2085 — dauerhaft
    // (Android aktualisiert nur aufwärts) und verschieden vom AAB.
    expect(gradle, isNot(contains('splits')),
        reason: 'split-per-abi verbiegt den versionCode');
    expect(_buildCommand(release, 'flutter build apk'),
        isNot(contains('--split-per-abi')),
        reason: 'split-per-abi verbiegt den versionCode');
  });
}
