// Bewacht Android-Konfiguration, die man beim Editieren leicht verliert und
// die kein Widget-Test bemerkt — allen voran die Backup-Ausschlüsse: ohne
// sie wandert der Supabase-Session-Token in die Google-Cloud.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// Datei, in der ausschließlich der Supabase-Session-Token liegt
/// (`flutter.sb-<projekt>-auth-token`, am Gerät nachgeprüft).
const _sessionPrefs = 'FlutterSharedPreferences.xml';

/// Verzeichnis der heruntergeladenen Regionskarten (44 MB … 1,7 GB).
const _mapsDir = 'offline_maps';

/// Verzeichnis der geladenen Update-APK (~60 MB, reiner Zwischenschritt).
const _updatesDir = 'updates';

/// Verzeichnis der zwischengespeicherten eigenen Spots — die geheimen
/// Fundstellen samt Koordinaten (`SpotCache.dirName`).
const _spotCacheDir = 'spot_cache';

XmlDocument _load(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path fehlt');
  return XmlDocument.parse(file.readAsStringSync());
}

/// Die im Manifest deklarierten Berechtigungen — ohne die per
/// `tools:node="remove"` wieder entfernten.
Set<String> _permissions() => {
      for (final e in _load('android/app/src/main/AndroidManifest.xml')
          .rootElement
          .findElements('uses-permission'))
        if (e.getAttribute('tools:node') != 'remove')
          e.getAttribute('android:name') ?? '',
    };

/// Kotlin-Quelltext ohne Kommentare.
///
/// „Kommt nicht vor"-Prüfungen brauchen das: Ein File, das seine eigene
/// Entscheidung begründet, nennt den verbotenen Namen zwangsläufig — der
/// Kommentar in `build.gradle.kts` erklärt, warum dort KEIN
/// `applicationIdSuffix` steht, und ließ genau deshalb den Test scheitern.
/// Dieselbe Lehre wie `sqlOnly` in Mitfahrbars Schema-Test.
String _codeOnly(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//.*'), '');

/// Alle `<exclude>`-Regeln unterhalb von [parent] als (domain, path)-Paare.
Set<(String, String)> _excludes(XmlElement parent) => {
      for (final e in parent.findElements('exclude'))
        (e.getAttribute('domain') ?? '', e.getAttribute('path') ?? ''),
    };

void main() {
  test('Der Benachrichtigungs-Kanal ist deklariert, angelegt und laut', () {
    // Die drei Stellen müssen zusammenpassen, und keine davon fällt beim
    // Editieren auf: Ohne Manifest-Zeile legt FCM still einen eigenen,
    // leisen Kanal an (dann nur ein Symbol in der Statusleiste, kein
    // Banner — am 2026-08-12 auf dem Pixel so gesehen); ohne
    // `createNotificationChannel` zeigt das Manifest auf nichts; und
    // unterhalb von IMPORTANCE_HIGH gibt es kein Banner.
    //
    // Der native Code hat sonst KEIN Netz (CLAUDE.md) — deshalb prüft
    // dieser Test ausnahmsweise Kotlin-Quelltext.
    const idName = 'notification_channel_id';
    final manifest = _load('android/app/src/main/AndroidManifest.xml');
    final declared = manifest.rootElement
        .findAllElements('meta-data')
        .where((e) =>
            e.getAttribute('android:name') ==
            'com.google.firebase.messaging.default_notification_channel_id')
        .map((e) => e.getAttribute('android:value'))
        .toList();
    expect(declared, ['@string/$idName'],
        reason: 'Manifest nennt den Kanal nicht (oder mehrfach)');

    final strings = File('android/app/src/main/res/values/strings.xml');
    expect(strings.existsSync(), isTrue, reason: 'strings.xml fehlt');
    expect(strings.readAsStringSync(), contains('name="$idName"'),
        reason: 'Die Zeichenkette, auf die das Manifest zeigt, fehlt');

    final activity = File('android/app/src/main/kotlin/com/'
            'pilzbuddy/MainActivity.kt')
        .readAsStringSync();
    expect(activity, contains('createNotificationChannel'),
        reason: 'Der Kanal wird nirgends angelegt');
    expect(activity, contains('R.string.$idName'),
        reason: 'Der angelegte Kanal trägt eine andere ID als das Manifest');
    expect(activity, contains('NotificationManager.IMPORTANCE_HIGH'),
        reason: 'Unter IMPORTANCE_HIGH erscheint kein Banner — und die '
            'Stufe lässt sich später NICHT mehr ändern, nur über eine '
            'neue Kanal-ID');
  });

  test('Update installiert mit genau einer Berechtigung', () {
    // Der Auslöser für #88 war nie eigener Code, sondern das Manifest von
    // `ota_update`: es zog INSTALL_PACKAGES (Signatur-Berechtigung!),
    // REQUEST_INSTALL_PACKAGES, READ/WRITE_EXTERNAL_STORAGE und
    // RECEIVE_BOOT_COMPLETED in JEDEN Build — 14 Berechtigungen statt 8.
    // Deshalb wacht dieser Test weiter über die Abhängigkeit: Sie brächte
    // alles auf einmal zurück.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('ota_update'), isFalse,
        reason: 'ota_update zieht INSTALL_PACKAGES & Co. in jeden Build');

    // Über die deklarierten Namen statt über den Dateitext: Ein `contains`
    // findet sonst die Berechtigung im Kommentar, der erklärt, warum sie
    // gerade NICHT drinsteht.
    final declared = _permissions();

    // Der eigene Weg (#161) kommt mit REQUEST_INSTALL_PACKAGES aus: Er
    // *bietet* dem System eine Datei an, der Installationsdialog gehört
    // Android. Die drei hier braucht er nicht, und sie sind die teuren —
    // INSTALL_PACKAGES kann eine normale App nie bekommen und ist in jeder
    // Review ein roter Punkt.
    for (final permission in const [
      'android.permission.INSTALL_PACKAGES',
      'android.permission.WRITE_EXTERNAL_STORAGE',
      'android.permission.READ_EXTERNAL_STORAGE',
    ]) {
      expect(declared, isNot(contains(permission)),
          reason: '$permission gehört nicht ins Manifest');
    }
    expect(declared, contains('android.permission.REQUEST_INSTALL_PACKAGES'),
        reason: 'Ohne sie scheitert das In-App-Update wortlos');
  });

  test('Der Play-Flavor nimmt REQUEST_INSTALL_PACKAGES wieder heraus', () {
    // Die andere Hälfte des Tests darüber. Der Dart-Pfad ist im Play-Build
    // seit jeher aus (`AppDistribution.showsUpdateHints`), die
    // Manifest-Zeile war es nicht — sie läge im hochgeladenen AAB, und eine
    // Berechtigung ohne zugehörige Funktion ist in der Play-Review die
    // schlechtestmögliche Antwort (Selbst-Updates verstoßen dort gegen
    // „Device and Network Abuse").
    //
    // Geprüft wird die Quelldatei, nicht das gemergte Manifest: Das
    // entsteht erst in Gradle, und ein Dart-Test hat keinen Build. Dass das
    // Zusammenführen wirklich aufgeht, baut die CI im Job „Build Android
    // APK" nach — dort läuft bewusst der `play`-Flavor.
    const permission = 'android.permission.REQUEST_INSTALL_PACKAGES';
    const path = 'android/app/src/play/AndroidManifest.xml';

    // Zwei aufeinanderfolgende Bindestriche sind in einem XML-Kommentar
    // verboten. Darts xml-Paket nimmt sie trotzdem an — Androids
    // ManifestMerger nicht: Er bricht mit „Error parsing" ab, und zwar erst
    // nach über vier Minuten Gradle. Dieser Test lief dabei grün, weil er
    // denselben nachsichtigen Parser benutzt wie der Rest der Suite.
    // Deshalb hier zusätzlich am Rohtext geprüft.
    for (final match
        in RegExp(r'<!--(.*?)-->', dotAll: true).allMatches(
            File(path).readAsStringSync())) {
      expect(match.group(1), isNot(contains('--')),
          reason: '$path: „--" im Kommentar — daran scheitert der '
              'ManifestMerger, nicht dieser Parser');
    }

    final play = _load(path).rootElement;

    final removed = {
      for (final e in play.findElements('uses-permission'))
        if (e.getAttribute('tools:node') == 'remove')
          e.getAttribute('android:name'),
    };
    expect(removed, contains(permission),
        reason: 'Ohne diese Zeile trägt das AAB eine Berechtigung, zu der '
            'im Play-Build keine Funktion gehört');

    // Der Flavor darf nichts ANDERES mitbringen: Jede weitere Zeile gälte
    // nur für den Play-Build und driftete still von dem ab, was auf den
    // Geräten der GitHub-Nutzer läuft.
    expect(play.childElements.map((e) => e.name.local).toSet(), {
      'uses-permission',
    }, reason: 'Der Play-Flavor soll genau eine Sache tun');
  });

  test('Beide Flavors bauen dieselbe App', () {
    // Ein `applicationIdSuffix` wäre die naheliegende Ergänzung und der
    // teuerste Fehler an dieser Stelle: Android sähe zwei verschiedene
    // Apps, der Wechsel von der GitHub-APK zum Play-Build verlöre die
    // Installation, und beide ständen nebeneinander auf dem Gerät (genau
    // das ist Mitfahrbar beim Bundle-ID-Umzug passiert, #87). Der
    // Signaturwechsel durch Play App Signing verlangt ohnehin schon ein
    // Deinstallieren — ein zweiter Grund muss nicht dazukommen.
    final gradle =
        _codeOnly(File('android/app/build.gradle.kts').readAsStringSync());

    for (final flavor in const ['github', 'play']) {
      expect(gradle, contains('create("$flavor")'),
          reason: 'Flavor $flavor fehlt — die Workflows rufen ihn auf');
    }
    expect(gradle, isNot(contains('applicationIdSuffix')),
        reason: 'Ein Suffix macht aus einem Vertriebsweg eine zweite App');
  });

  test('FileProvider gibt nur den Update-Ordner heraus', () {
    // Ab Android 7 darf eine `file://`-URI nicht mehr herausgereicht
    // werden. Der Pfad ist bewusst eng: Im selben Verzeichnis liegen die
    // Offline-Karten und der Session-Token.
    final app = _load('android/app/src/main/AndroidManifest.xml')
        .rootElement
        .findElements('application')
        .single;
    final provider = app.findElements('provider').single;
    expect(provider.getAttribute('android:name'),
        'androidx.core.content.FileProvider');
    expect(provider.getAttribute('android:exported'), 'false',
        reason: 'Ein exportierter FileProvider gäbe die Datei jedem preis');
    expect(provider.getAttribute('android:grantUriPermissions'), 'true');

    final paths = _load('android/app/src/main/res/xml/file_paths.xml')
        .rootElement;
    final entries = paths.childElements
        .map((e) => (e.name.local, e.getAttribute('path')))
        .toSet();
    expect(entries, {('files-path', 'updates/')},
        reason: 'Nur der Update-Ordner darf heraus');
  });

  test('Manifest verweist auf beide Backup-Regelwerke', () {
    final app = _load('android/app/src/main/AndroidManifest.xml')
        .rootElement
        .findElements('application')
        .single;

    // dataExtractionRules gilt ab Android 12, fullBackupContent darunter —
    // fehlt eines, ist die jeweilige Android-Generation ungeschützt.
    expect(app.getAttribute('android:dataExtractionRules'),
        '@xml/backup_rules');
    expect(app.getAttribute('android:fullBackupContent'),
        '@xml/full_backup_content');
  });

  test('Backup-Regeln ab Android 12 schließen Session und Karten aus', () {
    final rules = _load('android/app/src/main/res/xml/backup_rules.xml')
        .rootElement;

    // Cloud-Backup und Direktübertragung aufs neue Gerät sind getrennte
    // Abschnitte — ein Token darf über keinen von beiden abfließen.
    for (final section in ['cloud-backup', 'device-transfer']) {
      final excludes = _excludes(rules.findElements(section).single);
      expect(excludes, contains(('sharedpref', _sessionPrefs)),
          reason: '$section: Session-Token nicht ausgeschlossen');
      expect(excludes, contains(('file', _mapsDir)),
          reason: '$section: Offline-Karten nicht ausgeschlossen');
      expect(excludes, contains(('file', _updatesDir)),
          reason: '$section: Update-APK nicht ausgeschlossen — 60 MB '
              'sprengen das 25-MB-Kontingent und lassen das ganze Backup '
              'scheitern');
      expect(excludes, contains(('file', _spotCacheDir)),
          reason: '$section: Spot-Zwischenspeicher nicht ausgeschlossen — '
              'darin stehen die geheimen Fundstellen samt Koordinaten, und '
              'Googles Cloud ist in der Datenschutzerklärung kein Empfänger');
    }
  });

  test('Backup-Regeln bis Android 11 schließen dasselbe aus', () {
    final excludes = _excludes(
        _load('android/app/src/main/res/xml/full_backup_content.xml')
            .rootElement);

    expect(excludes, contains(('sharedpref', _sessionPrefs)));
    expect(excludes, contains(('file', _mapsDir)));
    expect(excludes, contains(('file', _updatesDir)));
    expect(excludes, contains(('file', _spotCacheDir)));
  });
}
