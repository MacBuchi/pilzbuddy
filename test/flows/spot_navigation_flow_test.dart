// Der Weg vom Spot in die Navi-App (#367), durch die echte Oberfläche.
//
// Gemockt wird der Kanal von url_launcher, nicht die eigene Funktion:
// So steht in der Erwartung der URI, der das Gerät wirklich verlässt.
// Ohne Mock ginge es gar nicht — die Antwort eines nicht bedienten
// Kanals löst sich unter dem `FakeAsync` eines Widget-Tests nie auf, und
// der Knopfdruck bliebe folgenlos stehen. Genau daran hängt auch der
// Wert des Tests: Zöge url_launcher seinen Kanal um, liefe der Druck ins
// Leere und beide Tests würden rot.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

/// Der Kanal, über den `launchUrl` die Übergabe an Android schickt.
const _launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  late List<String> launched;
  late List<String> clipboard;

  /// Stellt die Antwort ein, die Android geben würde: [handled] `false`
  /// heißt „keine installierte App nimmt `geo:` an".
  void mockLauncher({required bool handled}) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_launcherChannel, (call) async {
      launched.add((call.arguments as Map)['url'] as String);
      return handled;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  }

  setUp(() {
    launched = [];
    clipboard = [];
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_launcherChannel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('Der Knopf übergibt Koordinate und Namen an die Navi-App',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: 51.1634, lng: 10.4477);
    await pumpApp(tester, backend);
    mockLauncher(handled: true);

    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.byTooltip('In Navi-App öffnen'));
    await settle(tester);

    expect(launched, [
      'geo:51.163400,10.447700?q=51.163400,10.447700(Buchenhang)',
    ]);
    expect(clipboard, isEmpty);
    // Der App-Wähler steht jetzt im Vordergrund — eine SnackBar dahinter
    // wäre für niemanden.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Nimmt niemand das an, liegt die Koordinate in der '
      'Zwischenablage — und die App sagt es', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: 51.1634, lng: 10.4477);
    await pumpApp(tester, backend);
    mockLauncher(handled: false);

    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.byTooltip('In Navi-App öffnen'));
    await settle(tester);

    expect(clipboard, ['51.163400, 10.447700'],
        reason: 'ein Knopf, der nichts tut, sieht aus wie ein Fehler');
    expect(find.textContaining('Keine Navi-App gefunden'), findsOneWidget);
    expect(find.textContaining('51.163400, 10.447700'), findsOneWidget);
  });

  testWidgets('Auch am Spot eines Buddys — dorthin will man genauso',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id);
    backend.addSpot(ownerId: lilli.id, lat: 47.8, lng: 12.9);
    await pumpApp(tester, backend);
    mockLauncher(handled: true);

    await tester.tap(find.byTooltip('Pilz-Spot (lilli92)'));
    await settle(tester);

    // Löschen bleibt dem Besitzer — hinfahren nicht.
    expect(find.byTooltip('Spot löschen'), findsNothing);
    await tester.tap(find.byTooltip('In Navi-App öffnen'));
    await settle(tester);

    expect(launched,
        ['geo:47.800000,12.900000?q=47.800000,12.900000(Pilz-Spot)']);
  });
}
