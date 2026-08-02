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

/// Alle `<exclude>`-Regeln unterhalb von [parent] als (domain, path)-Paare.
Set<(String, String)> _excludes(XmlElement parent) => {
      for (final e in parent.findElements('exclude'))
        (e.getAttribute('domain') ?? '', e.getAttribute('path') ?? ''),
    };

void main() {
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
    }
  });

  test('Backup-Regeln bis Android 11 schließen dasselbe aus', () {
    final excludes = _excludes(
        _load('android/app/src/main/res/xml/full_backup_content.xml')
            .rootElement);

    expect(excludes, contains(('sharedpref', _sessionPrefs)));
    expect(excludes, contains(('file', _mapsDir)));
    expect(excludes, contains(('file', _updatesDir)));
  });
}
