/// Die Riegel der zwei Release-Kanäle (#262).
///
/// Jeder Merge veröffentlicht ein **Prerelease**; die Nutzer sehen nur,
/// was `promote.yml` freigibt. Beide Riegel sind je ein einziges Wort
/// YAML — geht eines verloren, kompiliert alles, jede PR-CI bleibt grün,
/// und auffallen würde es erst daran, dass wieder acht Update-Hinweise
/// an einem Tag ankommen (so geschehen am 2026-08-09, acht Releases von
/// 1.69.0 bis 1.76.0).
///
/// Dieselbe Linie wie `android_manifest_test.dart` und
/// `privacy_policy_test.dart`: Konfigurationsfehler fängt nur ein
/// Konfigurations-Regressionstest.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final release = File('.github/workflows/release.yml').readAsStringSync();
  final promote = File('.github/workflows/promote.yml').readAsStringSync();
  final ci = File('.github/workflows/ci.yml').readAsStringSync();

  group('Release-Kanäle (#262)', () {
    test('jeder Merge veröffentlicht als Prerelease, nie als latest', () {
      expect(release, contains('prerelease: true'),
          reason: 'Ohne die Markierung erscheint jeder Merge in '
              '`/releases/latest` — und der Update-Check der App fragt '
              'genau das ab.');
      expect(release, contains('make_latest: false'),
          reason: 'GitHub setzt das neueste Release sonst TROTZ '
              'Prerelease-Flag als „latest". Beide Zeilen gehören '
              'zusammen; eine allein genügt nicht.');
    });

    test('nur die Beförderung schaltet stabil', () {
      expect(promote, contains('--prerelease=false'));
      expect(promote, contains('--latest'));
      expect(promote, contains('workflow_dispatch'),
          reason: 'Die Beförderung ist ein bewusster Handgriff — kein '
              'Automatismus, sonst wäre die Trennung wieder weg.');
    });

    test('Pages deployt nur die Beförderung, und zwar aus dem Tag', () {
      expect(release, isNot(contains('actions-gh-pages')),
          reason: 'Das Web hängt an EINER Adresse. Deployte jeder Merge, '
              'bekämen Web-Nutzer jede Zwischenversion und die Trennung '
              'gälte nur für Android.');
      expect(promote, contains('actions-gh-pages'));
      expect(promote, contains(r'git checkout "${{ steps.pick.outputs.tag }}"'),
          reason: 'Aus main gebaut läge auf der Web-Adresse der '
              'Entwicklungsstand, während Android auf stabil zeigt.');
      expect(promote, contains('--base-href /pilzbuddy/'),
          reason: 'Ohne den Präfix lädt die Seite unter '
              'macbuchi.github.io/pilzbuddy/ ihre Ressourcen von der '
              'Wurzel — weiße Seite.');
      expect(promote, contains('404.html'),
          reason: 'SPA-Fallback: Ohne die Kopie sind alle Deep-Links tot.');
    });

    test('die Notizen sammeln seit dem letzten STABILEN Stand', () {
      expect(promote, contains('tool/release_notes.py'));
      expect(promote, contains('--since'),
          reason: 'Ohne Untergrenze stünde in den Notizen nur der Block '
              'der beförderten Version — alles dazwischen fehlte.');
      expect(promote, contains('isPrerelease | not'),
          reason: 'Die Untergrenze ist das letzte STABILE Release, nicht '
              'das vorherige Prerelease.');
    });

    test('der Sammler wird auch geprüft', () {
      expect(ci, contains('tool/release_notes.py --self-test'),
          reason: 'Ein Selbsttest, den niemand ausführt, verrottet still '
              '— dieselbe Lehre wie bei den anderen Werkzeugen.');
    });
  });

  group('Aussperr-Grenze (#80 unter zwei Kanälen)', () {
    final schemaCheck = File('tool/schema_check.sh').readAsStringSync();

    test('die Mindestversion wird am stabilen Stand gemessen', () {
      // Migrationen spielen beim MERGE ein, der Client kommt erst mit der
      // Beförderung. Ein Patch, der die Mindestversion auf die
      // Entwicklungsversion hebt, sperrt sofort alle aus, die auf stabil
      // sind — der frühere Maßstab (pubspec.yaml) hätte das durchgelassen.
      expect(schemaCheck, contains('releases/latest'),
          reason: 'Der Maßstab ist der letzte stabile Release-Stand.');
      expect(schemaCheck, contains('stable_version'),
          reason: 'Und er wird auch wirklich verglichen.');
    });

    test('ein wackeliger API-Aufruf blockiert keinen Merge', () {
      expect(schemaCheck, contains('Kein stabiles Release gefunden'),
          reason: 'Ohne Rückfallweg stünde die ganze CI still, sobald die '
              'GitHub-API hustet.');
    });
  });
}
