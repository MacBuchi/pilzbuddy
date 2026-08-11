// Rang und Spiegel in der Oberfläche (#276).
//
// Das Feature belohnt Teilen, statt Nichtteilen zu bestrafen — deshalb
// prüfen diese Tests vor allem, wo NICHTS steht: kein Titel bei null,
// kein Rang in der Freundessuche, kein Spiegel ohne Missverhältnis.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pilzbuddy/features/profile/sharing_rank_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  Future<void> openProfile(WidgetTester tester) async {
    await tester.tap(find.text('Profil'));
    await settle(tester);
  }

  testWidgets('ohne geteilte Spots steht dort eine Einladung, kein Etikett',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, settings: FakeSettings());
    await openProfile(tester);

    expect(find.text('Noch kein Rang'), findsOneWidget);
    expect(find.textContaining('Teile deinen ersten Spot'), findsOneWidget);
    // Der Ton ist der Punkt: Wer nichts teilt, wird eingeladen und nicht
    // benannt.
    expect(find.textContaining('Frischling'), findsNothing);
    expect(find.textContaining('Schnorrer'), findsNothing);
  });

  testWidgets('ein geteilter Spot macht zum Sporenstreuer', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id);
    await pumpApp(tester, backend, settings: FakeSettings());
    await openProfile(tester);

    expect(find.text('Sporenstreuer'), findsOneWidget);
    expect(find.textContaining('noch 9 bis Hyphenspinner'), findsOneWidget);
  });

  testWidgets('wer nicht teilt, hat keinen Rang — trotz Spots',
      (tester) async {
    // Der globale Schalter aus: Kein Buddy sieht etwas, also gibt es
    // auch nichts zu würdigen.
    final (backend, me) = loggedInBackend();
    for (var i = 0; i < 12; i++) {
      backend.addSpot(ownerId: me.id);
    }
    backend.users.firstWhere((u) => u.id == me.id).shareSpotsDefault = false;
    await pumpApp(tester, backend, settings: FakeSettings());
    await openProfile(tester);

    expect(find.text('Noch kein Rang'), findsOneWidget);
    expect(find.text('Hyphenspinner'), findsNothing);
  });

  testWidgets('der Spiegel meldet sich beim Missverhältnis', (tester) async {
    // Ein Buddy teilt zehn, ich teile einen: 1×5 < 10.
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id);
    for (var i = 0; i < 10; i++) {
      backend.addSpot(ownerId: lilli.id);
    }
    backend.addSpot(ownerId: me.id);
    await pumpApp(tester, backend, settings: FakeSettings());
    await openProfile(tester);

    expect(find.textContaining('Du siehst 10 Spots'), findsOneWidget);
    expect(find.textContaining('teilst selbst 1'), findsOneWidget);
  });

  testWidgets('bei ausgeglichenem Verhältnis schweigt er', (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id);
    for (var i = 0; i < 4; i++) {
      backend.addSpot(ownerId: lilli.id);
      backend.addSpot(ownerId: me.id);
    }
    await pumpApp(tester, backend, settings: FakeSettings());
    await openProfile(tester);

    expect(find.textContaining('Du siehst'), findsNothing,
        reason: 'wer mithält, bekommt keinen Vorhalt');
  });

  testWidgets('der Rang eines Buddys steht in der Freundesliste',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id);
    for (var i = 0; i < 10; i++) {
      backend.addSpot(ownerId: lilli.id);
    }
    await pumpApp(tester, backend, settings: FakeSettings());
    await tester.tap(find.text('Freunde'));
    await settle(tester);

    final tile = find.ancestor(
        of: find.text('lilli92'), matching: find.byType(ListTile));
    expect(tile, findsOneWidget);
    expect(
        find.descendant(of: tile, matching: find.text('Hyphenspinner')),
        findsOneWidget);
  });

  testWidgets('ein Fremder hat gar keinen zählbaren Rang', (tester) async {
    // **Warum es hier keinen UI-Test gibt.** Der erste Anlauf prüfte, dass
    // in der Freundessuche kein Titel steht — und ging auch dann durch,
    // als ich den Titel dort versuchsweise EINBAUTE. Die Gegenprobe hat
    // ihn als zahnlos entlarvt.
    //
    // Der Grund ist die eigentliche Zusicherung: Der Rang wird aus den
    // Spots gerechnet, die bei mir ankommen, und von einem Fremden kommt
    // nichts an. Es gibt also nichts zu verraten — die Sicherheit steckt
    // in der Datenlage, nicht in einer Auslassung im Widget-Baum. Genau
    // das hält dieser Test fest, und er FIELE, wenn jemand die Zahl
    // künftig aus einer Serverspalte zöge statt aus den Spots.
    final (backend, me) = loggedInBackend();
    final fremd = backend.addUser(username: 'waldfee');
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id);
    for (var i = 0; i < 30; i++) {
      backend.addSpot(ownerId: fremd.id);
    }
    for (var i = 0; i < 10; i++) {
      backend.addSpot(ownerId: lilli.id);
    }
    // Eigene Spots dazu: Die Zählung ist die der BUDDIES, meine eigenen
    // haben darin nichts verloren.
    for (var i = 0; i < 7; i++) {
      backend.addSpot(ownerId: me.id);
    }
    await pumpApp(tester, backend, settings: FakeSettings());
    final counts = ProviderScope.containerOf(
            tester.element(find.byType(Scaffold).first))
        .read(buddySharedCountsProvider);

    expect(counts[lilli.id], 10, reason: 'vom Buddy kommen die Spots an');
    expect(counts.containsKey(me.id), isFalse,
        reason: 'meine eigenen sieben Spots sind kein Buddy-Rang');
    expect(counts.containsKey(fremd.id), isFalse,
        reason: 'von einem Fremden weiß die App nichts — trotz seiner 30 '
            'Spots. Deshalb kann in der Suche auch nichts stehen.');
  });
}
