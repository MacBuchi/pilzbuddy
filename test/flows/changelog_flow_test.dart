// Der Weg zur Versionshistorie: Profil → „Was ist neu". Der Test lädt die
// echte CHANGELOG.md aus dem Asset-Bundle — fehlt der Eintrag in
// pubspec.yaml, schlägt er fehl, statt die Lücke erst auf dem Gerät zu
// zeigen.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/changelog/changelog_parser.dart';
import 'package:pilzbuddy/features/changelog/changelog_screen.dart';

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
    // Der Bildschirm holt CHANGELOG.md über `rootBundle` — echtes
    // Datei-IO, das an der Fake-Uhr vorbeiläuft: Der FutureBuilder bleibt
    // im Ladezustand, egal wie viele Frames gepumpt werden. Bis 1.79.0
    // ging das gut, weil das Asset zufällig früh genug da war; ein
    // zusätzlicher await an ganz anderer Stelle (der Ausgangskorb im
    // Spot-Provider, #267) hat die Reihenfolge gekippt und den Test rot
    // gemacht, ohne dass am Bildschirm etwas kaputt war.
    //
    // Reihenfolge ist hier alles: erst pumpen (der Bildschirm entsteht
    // und stößt das Laden an), dann echte Zeit vergehen lassen, dann
    // wieder pumpen. `runAsync` direkt nach dem Tipp liefe ins Leere —
    // da hat noch niemand das Asset angefordert.
    await settle(tester, frames: 20);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester, frames: 5);

    // Der neueste Block steht oben und ist ohne Scrollen sichtbar. Die
    // Überschrift kommt aus der Datei statt fest im Test zu stehen — sonst
    // bricht dieser Test bei jedem Release, das einen Block ergänzt.
    final newest = parseChangelog(File(changelogAsset).readAsStringSync())
        .firstWhere((line) => line.kind == ChangelogLineKind.section);
    expect(find.text(newest.text), findsOneWidget);

    // Titel und Vorspann der Datei gehören nicht auf diesen Bildschirm —
    // sie erklären Lesern auf GitHub den Weg hierher.
    expect(find.text('Änderungen in PilzBuddy'), findsNothing);
  });
}
