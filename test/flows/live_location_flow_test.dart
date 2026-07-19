// Szenarien rund ums Live-Standort-Teilen: Sichtbarkeit der Freundes-
// Avatare je nach Freigabe/Ablauf sowie das Starten und Beenden über die UI.
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  testWidgets('Aktive Freigabe eines Freundes zeigt seinen Live-Avatar',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92', avatar: 2);
    backend.addFriendship(lilli.id, me.id);
    backend.addLiveShare(lilli.id);
    await pumpApp(tester, backend);

    expect(find.byTooltip('lilli92 (live)'), findsOneWidget);
  });

  testWidgets('Abgelaufene Freigabe erscheint nicht', (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id);
    backend.addLiveShare(lilli.id,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)));
    await pumpApp(tester, backend);

    expect(find.byTooltip('lilli92 (live)'), findsNothing);
  });

  testWidgets('Freigabe eines Nicht-Freundes bleibt unsichtbar',
      (tester) async {
    final (backend, _) = loggedInBackend();
    final fremder = backend.addUser(username: 'fremder');
    backend.addLiveShare(fremder.id); // keine Freundschaft
    await pumpApp(tester, backend);

    expect(find.byTooltip('fremder (live)'), findsNothing);
  });

  testWidgets('Über den FAB 2 Stunden teilen → Zeile im Backend + Banner',
      (tester) async {
    final (backend, me) = loggedInBackend();
    await pumpApp(tester, backend, position: fakePosition(51.16, 10.45));

    await tester.tap(find.byTooltip('Standort mit Buddies teilen'));
    await settle(tester);
    await tester.tap(find.text('2 Std.'));
    await settle(tester);

    expect(backend.liveLocations.where((r) => r.userId == me.id), isNotEmpty);
    expect(
        find.textContaining('Du teilst deinen Standort bis'), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('Laufende Freigabe über das Sheet beenden', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addLiveShare(me.id);
    await pumpApp(tester, backend, position: fakePosition(51.16, 10.45));

    // Banner sichtbar, weil ich aktiv teile.
    expect(
        find.textContaining('Du teilst deinen Standort bis'), findsOneWidget);

    await tester.tap(find.byTooltip('Standort-Teilen verwalten'));
    await settle(tester);
    await tester.tap(find.text('Teilen beenden'));
    await settle(tester);

    expect(backend.liveLocations.where((r) => r.userId == me.id), isEmpty);
    expect(find.textContaining('Du teilst deinen Standort bis'), findsNothing);
    await drainSnackbars(tester);
  });
}
