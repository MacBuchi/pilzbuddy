// Aliase für Buddys (#567) — durch die echte Oberfläche.
//
// Die teuren Fälle: ein Alias, der eine Umbenennung nicht überlebt (dann
// war er zwecklos); einer, der an einer Stelle fehlt (dann steht dort
// plötzlich ein Fremder); einer, den der Buddy zu sehen bekommt; und
// einer, der das Ende der Freundschaft überdauert.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/friends/buddy_alias_dialog.dart';
import 'package:pilzbuddy/features/friends/friends_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late FakeUser me;
  late FakeUser andi;

  setUp(() {
    backend = FakeBackend();
    me = backend.addUser(username: 'testpilz');
    andi = backend.addUser(username: 'stinkmorchel 1');
    backend.signInAs(me.id);
  });

  Future<void> openBuddys(WidgetTester tester) async {
    await openTab(tester, 'Buddys');
    await tester.ensureVisible(find.byKey(aliasButtonKey(andi.id)));
    await settle(tester);
  }

  Future<void> giveAlias(WidgetTester tester, String alias) async {
    await tester.tap(find.byKey(aliasButtonKey(andi.id)));
    await settle(tester);
    await tester.enterText(find.byKey(kAliasFieldKey), alias);
    await tester.tap(find.byKey(kAliasSaveKey));
    await settle(tester, frames: 12);
  }

  testWidgets('vergeben: oben der Alias, darunter der Name — und er '
      'überlebt die Umbenennung', (tester) async {
    backend.addFriendship(me.id, andi.id);
    await pumpApp(tester, backend);
    await openBuddys(tester);

    await giveAlias(tester, '  Andi  ');
    expect(backend.aliases[(owner: me.id, friend: andi.id)], 'Andi');
    expect(find.text('Andi'), findsOneWidget);
    expect(find.text('stinkmorchel 1'), findsOneWidget,
        reason: 'der echte Name steht darunter');

    // Andi benennt sich um. Das ist der ganze Zweck des Features.
    andi.username = 'klabusterbärchen 2';
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, backend);
    await openBuddys(tester);
    expect(find.text('Andi'), findsOneWidget);
    expect(find.text('klabusterbärchen 2'), findsOneWidget);
  });

  testWidgets('der Verlaufskopf trägt beide Namen', (tester) async {
    backend.addFriendship(me.id, andi.id);
    backend.aliases[(owner: me.id, friend: andi.id)] = 'Andi';
    await pumpApp(tester, backend);
    await openBuddys(tester);
    await tester.tap(find.byKey(messageButtonKey(andi.id)));
    await settle(tester, frames: 12);

    final appBar = find.byType(AppBar);
    expect(find.descendant(of: appBar, matching: find.text('Andi')),
        findsOneWidget);
    expect(
        find.descendant(of: appBar, matching: find.text('stinkmorchel 1')),
        findsOneWidget);
  });

  testWidgets('überall sonst steht der Alias — Spot-Liste, Suche, Blatt',
      (tester) async {
    backend.addFriendship(andi.id, me.id);
    backend.aliases[(owner: me.id, friend: andi.id)] = 'Andi';
    backend.addSpot(
        ownerId: andi.id,
        name: 'Alte Eiche',
        species: 'Pfifferling',
        foundOn: DateTime.now().subtract(const Duration(days: 1)));
    await pumpApp(tester, backend);
    await openTab(tester, 'Spots');

    expect(find.textContaining('Andi'), findsWidgets);
    expect(find.textContaining('stinkmorchel'), findsNothing,
        reason: 'eine Stelle mit dem alten Namen wäre die, die auffällt');

    // Die Suche findet ihn unter dem Alias.
    await tester.enterText(find.byType(TextField), 'andi');
    await settle(tester);
    expect(find.text('Alte Eiche'), findsOneWidget);

    await tester.tap(find.text('Alte Eiche'));
    await settle(tester);
    expect(find.text('Gefunden von Andi'), findsOneWidget);
  });

  testWidgets('den Alias eines ANDEREN sieht niemand', (tester) async {
    // Andi hat MIR einen gegeben. Der gehört ihm (Policy `fa_select`).
    backend.addFriendship(me.id, andi.id);
    backend.aliases[(owner: andi.id, friend: me.id)] = 'Pilzkönig';
    await pumpApp(tester, backend);
    await openBuddys(tester);
    expect(find.textContaining('Pilzkönig'), findsNothing);
    expect(find.text('stinkmorchel 1'), findsOneWidget);
  });

  testWidgets('leer speichern entfernt den Alias', (tester) async {
    backend.addFriendship(me.id, andi.id);
    backend.aliases[(owner: me.id, friend: andi.id)] = 'Andi';
    await pumpApp(tester, backend);
    await openBuddys(tester);

    await giveAlias(tester, '   ');
    expect(backend.aliases, isEmpty);
    expect(find.text('Andi'), findsNothing);
    expect(find.text('stinkmorchel 1'), findsOneWidget);
  });

  testWidgets('Ende der Freundschaft nimmt die Aliase beider Seiten mit',
      (tester) async {
    backend.addFriendship(me.id, andi.id);
    backend.aliases[(owner: me.id, friend: andi.id)] = 'Andi';
    backend.aliases[(owner: andi.id, friend: me.id)] = 'Pilzkönig';
    await pumpApp(tester, backend);
    await openBuddys(tester);

    await tester.tap(find.byTooltip('Buddy entfernen'));
    await settle(tester);
    expect(find.text('Andi als Buddy entfernen?'), findsOneWidget);
    await tester.tap(find.text('Entfernen'));
    await settle(tester, frames: 12);
    expect(backend.aliases, isEmpty);
  });

  testWidgets('bei offener Anfrage gibt es keinen Alias', (tester) async {
    // Die Policy verlangt einen bestätigten Buddy — sonst ließe sich
    // jedem Konto aus der Namenssuche ein Etikett anheften.
    backend.addFriendship(andi.id, me.id, status: 'pending');
    await pumpApp(tester, backend);
    await openTab(tester, 'Buddys');
    expect(find.text('stinkmorchel 1'), findsOneWidget);
    expect(find.byKey(aliasButtonKey(andi.id)), findsNothing);

    await tester.tap(find.byKey(messageButtonKey(andi.id)));
    await settle(tester, frames: 12);
    expect(find.byKey(aliasButtonKey(andi.id)), findsNothing);
  });
}
