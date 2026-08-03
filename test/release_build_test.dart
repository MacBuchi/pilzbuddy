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

/// Der Befehl, der die veröffentlichte APK baut — zusammengesetzt, weil er
/// im Workflow über mehrere Zeilen läuft (`run: >`).
String _apkBuildCommand(String workflow) {
  final start = workflow.indexOf('flutter build apk');
  expect(start, isNot(-1), reason: 'Kein APK-Build in release.yml gefunden');
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
    final command = _apkBuildCommand(release);

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
    final bundle = release.substring(release.indexOf('flutter build appbundle'));
    final command = bundle.substring(0, bundle.indexOf('\n'));

    expect(command, isNot(contains('--target-platform')),
        reason: 'Ein beschränktes AAB sperrt Play-Geräte aus, die die App '
            'ausführen könnten — dort ist das Splitten Play-Sache.');
    expect(command, isNot(contains('disable-abi-filtering')),
        reason: 'Im AAB soll Flutters eigene Filterung greifen.');
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
    expect(_apkBuildCommand(release), isNot(contains('--split-per-abi')),
        reason: 'split-per-abi verbiegt den versionCode');
  });
}
