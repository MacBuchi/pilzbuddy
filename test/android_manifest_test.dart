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

XmlDocument _load(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path fehlt');
  return XmlDocument.parse(file.readAsStringSync());
}

/// Alle `<exclude>`-Regeln unterhalb von [parent] als (domain, path)-Paare.
Set<(String, String)> _excludes(XmlElement parent) => {
      for (final e in parent.findElements('exclude'))
        (e.getAttribute('domain') ?? '', e.getAttribute('path') ?? ''),
    };

void main() {
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
    }
  });

  test('Backup-Regeln bis Android 11 schließen dasselbe aus', () {
    final excludes = _excludes(
        _load('android/app/src/main/res/xml/full_backup_content.xml')
            .rootElement);

    expect(excludes, contains(('sharedpref', _sessionPrefs)));
    expect(excludes, contains(('file', _mapsDir)));
  });
}
