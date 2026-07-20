// Lizenz-Compliance: MIT-Datei im Repo, Lizenzseite in der App und die
// Kartendaten-Lizenz, die Flutter von sich aus nicht kennt.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/map_data_license.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  test('Das Repo hat eine LICENSE-Datei mit MIT-Text', () {
    // Ohne LICENSE gilt in einem öffentlichen Repo „alle Rechte
    // vorbehalten" — niemand dürfte den Code legal weiterverwenden.
    final license = File('LICENSE');
    expect(license.existsSync(), isTrue, reason: 'LICENSE fehlt');

    final text = license.readAsStringSync();
    expect(text, contains('MIT License'));
    expect(text, contains('Marcus Bucher'));
    // Die Haftungsfreistellung ist der Teil, der bei Copy-Paste gern fehlt.
    expect(text, contains('WITHOUT WARRANTY OF ANY KIND'));
  });

  test('Kartendaten-Lizenz landet in der LicenseRegistry', () async {
    // Flutter sammelt nur LICENSE-Dateien von pub-Paketen ein; ODbL und
    // Protomaps müssen wir selbst eintragen.
    registerMapDataLicense();

    final entries = await LicenseRegistry.licenses.toList();
    final mapEntry = entries.where(
        (e) => e.packages.any((p) => p.contains('Kartendaten')));
    expect(mapEntry, hasLength(1), reason: 'Kartendaten-Eintrag fehlt');

    final text =
        mapEntry.single.paragraphs.map((p) => p.text).join(' ');
    expect(text, contains('OpenStreetMap'));
    expect(text, contains('ODbL'));
    expect(text, contains('Protomaps'));
  });

  testWidgets('Profil führt zur Lizenzseite', (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);

    await tester.tap(find.text('Profil'));
    await settle(tester);

    // Bis ans Listenende scrollen statt `scrollUntilVisible`: das schiebt
    // den Eintrag nur knapp ins Bild, wo er die untere Navigationsleiste
    // überlappt — der Tap landete dann auf „Freunde".
    for (var i = 0; i < 4; i++) {
      await tester.drag(
          find.byType(Scrollable).first, const Offset(0, -600));
      await settle(tester, frames: 4);
    }
    expect(find.text('Open-Source-Lizenzen'), findsOneWidget);

    await tester.tap(find.text('Open-Source-Lizenzen'));
    await settle(tester, frames: 20);

    // Flutters Lizenzseite zeigt Name und Legalese aus showLicensePage.
    expect(find.text('PilzBuddy'), findsWidgets);
    expect(find.textContaining('MIT-Lizenz'), findsWidgets);
  });
}
