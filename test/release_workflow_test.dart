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
  final preview = File('.github/workflows/preview.yml').readAsStringSync();

  // Ohne diesen Schritt hat das Projekt WIEDER keinen einzigen Test auf
  // dart2js — und niemandem fiele es auf: `flutter test` bliebe grün,
  // die Datei bliebe liegen, und der Web-Weg wäre still ungeprüft.
  // Dieselbe Begründung wie bei den Selbsttests in tool/ (#151): Was
  // nicht in CI läuft, verrottet.
  group('Die Web-Tests laufen in CI (#385, #386)', () {
    const files = [
      'test/spot_cache_idb_test.dart',
      'test/outbox_idb_test.dart',
    ];

    test('ci.yml ruft sie auf dart2js auf', () {
      expect(ci, contains('flutter test --platform chrome'));
      for (final file in files) {
        expect(ci, contains(file));
      }
    });

    test('und die Dateien gibt es', () {
      for (final file in files) {
        expect(File(file).existsSync(), isTrue, reason: file);
      }
    });
  });

  // Der Artefaktname steht in `release.yml` an FÜNF unabhängigen Stellen
  // (zwei `cp`, zwei `path:`, ein `files:`), und nichts hält sie
  // zusammen. Genau diese Falle hat MitFahrBar einmal erwischt: Der
  // v0.34.1-Lauf starb NACH dem Taggen, weil `cp` die Datei anders nannte
  // als `upload-artifact` sie suchte — sauber kompiliert, jede PR-CI
  // grün, gescheitert erst im echten Release. Zurück blieb ein Tag ohne
  // Release, den die Tag-Entscheidung fortan als „schon veröffentlicht"
  // wertete, und ein Aufräumen von Hand.
  //
  // Eine PR-CI kann das prinzipiell nicht fangen: Der Pfad läuft nur im
  // Release, und er läuft zu spät. Deshalb hier (#226).
  group('Artefaktnamen (#226)', () {
    List<String> copyTargets(String suffix) =>
        RegExp(r'run: cp \S+ "([^"]+)"')
            .allMatches(release)
            .map((m) => m.group(1)!)
            .where((name) => name.endsWith(suffix))
            .toList();

    List<String> uploadPaths(String suffix) =>
        // Bis ans Zeilenende, nicht `\S+`: Der Name enthält
        // `${{ needs.version.outputs.tag }}` — mit Leerzeichen darin.
        RegExp(r'^\s+path: (.+)$', multiLine: true)
            .allMatches(release)
            .map((m) => m.group(1)!.trim())
            .where((name) => name.endsWith(suffix))
            .toList();

    for (final suffix in ['.apk', '.aab']) {
      test('$suffix: benannt und hochgeladen ist derselbe Name', () {
        final copied = copyTargets(suffix);
        final uploaded = uploadPaths(suffix);
        // Genau eine je Sorte — bei mehreren wüsste der Vergleich unten
        // nicht, welche zu welcher gehört, und der Test ginge still
        // durch.
        expect(copied, hasLength(1),
            reason: 'genau eine cp-Zeile je Artefaktsorte erwartet');
        expect(uploaded, hasLength(1),
            reason: 'genau ein upload-artifact je Artefaktsorte erwartet');
        expect(uploaded.single, copied.single,
            reason: 'upload-artifact sucht einen anderen Namen, als cp '
                'erzeugt — der Lauf stirbt nach dem Taggen');
      });
    }

    test('das Release hängt genau die gebaute APK an', () {
      final globs = RegExp(r'^\s+files: (.+)$', multiLine: true)
          .allMatches(release)
          .map((m) => m.group(1)!.trim())
          .toList();
      expect(globs, hasLength(1));
      final pattern = RegExp(
          '^${globs.single.replaceAll('.', r'\.').replaceAll('*', '.*')}\$');
      expect(pattern.hasMatch(copyTargets('.apk').single), isTrue,
          reason: 'Das Muster in `files:` passt nicht auf den gebauten '
              'Namen — das Release entstünde ohne APK, und der '
              'Update-Weg der App fände nichts zum Herunterladen.');
    });
  });

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

  group('Workflow-Dateien', () {
    test('kein secrets-Kontext in if-Bedingungen', () {
      // `secrets` ist in `if:` NICHT verfügbar. GitHub verwirft die
      // ganze Datei dann beim EINLESEN — null Jobs, „workflow file
      // issue", bei jedem Push, ohne dass ein Check am PR rot wird.
      // Genau so ist deploy-functions.yml von seiner Erstellung (#286)
      // bis zum 2026-08-13 kein einziges Mal gelaufen, und derselbe
      // Fehler hat, nach release.yml kopiert, den Build von v1.91.1
      // verhindert. actionlint hat beides durchgewinkt — deshalb dieser
      // Wächter. Der richtige Weg ist ein Feststell-Schritt: Secret in
      // `env:` (erlaubt), Ergebnis in `steps.<id>.outputs`, und DARAUF
      // prüft das `if:`.
      final offenders = <String>[];
      for (final file in Directory('.github/workflows')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.yml'))) {
        var line = 0;
        for (final raw in file.readAsLinesSync()) {
          line++;
          final code = raw.split('#').first;
          if (RegExp(r'\bif:').hasMatch(code) && code.contains('secrets.')) {
            offenders.add('${file.path}:$line');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'if: mit secrets-Kontext macht die DATEI ungültig — '
              'GitHub startet dann gar nichts mehr. Feststell-Schritt '
              'benutzen (siehe release.yml, „Play-Secret vorhanden?").');
    });
  });

  group('Die Web-Vorschau darf sich nicht als echte App ausgeben (#388)', () {
    test('sie markiert sich beim Bauen', () {
      // Ohne dieses Flag fehlten der Streifen „Entwicklungsstand" und der
      // umgedrehte Profil-Verweis — die Vorschau sähe aus wie die echte
      // App, und ein Fehlerbericht daraus beträfe Code, den es nie gab.
      expect(preview, contains('--dart-define=PREVIEW_BUILD=true'));
    });

    test('sie zeigt auf ihre eigene Adresse', () {
      // Falsche base-href heißt: Die Seite lädt ihre eigenen Assets nicht
      // und bleibt weiß — ohne Fehlermeldung.
      expect(preview, contains('--base-href /pilzbuddy-preview/'));
      expect(preview, contains('external_repository: MacBuchi/pilzbuddy-preview'));
    });

    test('und die Beförderung bleibt bei der echten Adresse', () {
      // Der Riegel in die andere Richtung: Würde promote.yml je auf die
      // Vorschau zeigen, ginge die freigegebene App verloren.
      expect(promote, contains('--base-href /pilzbuddy/'));
      expect(promote, isNot(contains('pilzbuddy-preview')));
    });

    test('der Zugang ist ein Deploy Key, kein Konto-Token', () {
      // Ein Deploy Key hängt an genau einem Repo, kann nichts außer
      // pushen und läuft nicht ab. Ein PAT hinge am Konto — und liefe
      // irgendwann ab, wie SUPABASE_ACCESS_TOKEN am 2027-08-11.
      expect(preview, contains('deploy_key:'));
      expect(preview, isNot(contains('personal_token')));
    });
  });

  group('Der Schema Check muss auch ohne DB-Secret entscheiden können', () {
    final migrate = File('tool/db_migrate.sh').readAsStringSync();

    /// Der `schema-check`-Job als Textblock — von seinem Namen bis zum
    /// nächsten Job auf derselben Einrückungsebene.
    String schemaCheckJob() {
      final start = ci.indexOf('  schema-check:');
      expect(start, greaterThan(-1), reason: 'Job schema-check fehlt');
      final rest = ci.substring(start + 1);
      final end = RegExp(r'\n  [a-z-]+:\n').firstMatch(rest);
      return end == null ? rest : rest.substring(0, end.start);
    }

    test('der Job holt die Historie, sonst kann er nichts vergleichen', () {
      // GitHub reicht Dependabot-Läufen die DEPENDABOT-Secrets durch,
      // nicht die von Actions — `SUPABASE_DB_URL` ist dort leer. Ohne
      // Historie kann `db_migrate.sh` dann nicht sehen, dass der PR gar
      // keinen Patch mitbringt, und fällt auf „rot" zurück. Genau so war
      // dieser PFLICHT-Check auf JEDEM Dependabot-PR rot (#368, #369) —
      // mit einer Meldung, die sechzehn längst eingespielte Patches als
      // offen auswies. Nichts daran wäre je aufgefallen, denn an einem
      // normalen PR ist der Check grün.
      expect(schemaCheckJob(), contains('fetch-depth: 0'));
    });

    test('und den Ziel-Branch, gegen den verglichen wird', () {
      expect(schemaCheckJob(), contains('BASE_REF: origin/'));
    });

    test('ohne Secret entscheidet der Ziel-Branch, nicht die Baseline', () {
      // Die Frage „gibt es Patches jenseits der Baseline" ist seit
      // patch_006 immer mit ja zu beantworten — ein Wächter, der nie
      // wieder grün wird. Die richtige Frage ist, ob DIESER Stand einen
      // hinzufügt.
      expect(migrate, contains('--diff-filter=A'));
      expect(migrate, contains(r'"$BASE_REF"...HEAD'));
    });

    // BEWUSST KEIN Test darauf, dass die Begründung gegen ein
    // Dependabot-Secret im Skript stehen bleibt. Der Versuch stand hier
    // und war wertlos: Er prüfte auf das Wort „Dependabot-Secret", und
    // das steckt auch im Plural „Dependabot-Secrets" zwei Absätze höher
    // — die Gegenprobe blieb grün, obwohl die Begründung weg war. Ein
    // Wächter über einen Kommentar ist ohnehin einer über die Form, nicht
    // über das Verhalten. Die Entscheidung trägt der Kommentar selbst.
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
