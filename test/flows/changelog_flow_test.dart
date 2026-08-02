// Der Weg zur Versionshistorie: Profil → „Was ist neu". Der Test lädt die
// echte CHANGELOG.md aus dem Asset-Bundle — fehlt der Eintrag in
// pubspec.yaml, schlägt er fehl, statt die Lücke erst auf dem Gerät zu
// zeigen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  testWidgets('Profil führt zur Versionshistorie', (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    await pumpApp(tester, backend);

    await tester.tap(find.text('Profil'));
    await settle(tester);

    // Ans Listenende scrollen (siehe license_flow_test): `scrollUntilVisible`
    // schiebt den Eintrag nur knapp ins Bild, wo ihn die Navigationsleiste
    // überlappt.
    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await settle(tester, frames: 4);
    }
    expect(find.text('Was ist neu'), findsOneWidget);

    await tester.tap(find.text('Was ist neu'));
    await settle(tester, frames: 20);

    // Der neueste Block steht oben und ist ohne Scrollen sichtbar.
    expect(find.text('Versionshistorie in der App'), findsOneWidget);
    expect(find.textContaining('Version 1.33.0'), findsOneWidget);

    // Titel und Vorspann der Datei gehören nicht auf diesen Bildschirm —
    // sie erklären Lesern auf GitHub den Weg hierher.
    expect(find.text('Änderungen in PilzBuddy'), findsNothing);
  });
}
