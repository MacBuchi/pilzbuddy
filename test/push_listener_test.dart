// Der Vordergrund-Zuhörer (#277).
//
// Android zeigt eine `notification`-Nutzlast nur an, solange die App
// NICHT vorne ist — im Vordergrund landet sie ausschließlich in
// `onMessage`. Diese SnackBar ist also die einzige Anzeige, die es dann
// gibt, und was sie verdeckt, sieht niemand.
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/push_messaging.dart';
import 'package:pilzbuddy/core/widgets/push_listener.dart';

void main() {
  late StreamController<RemoteMessage> incoming;

  setUp(() => incoming = StreamController<RemoteMessage>.broadcast());
  tearDown(() => incoming.close());

  Future<ScaffoldMessengerState> pumpListener(WidgetTester tester) async {
    late ScaffoldMessengerState messenger;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pushMessageListenerProvider.overrideWithValue(() => incoming.stream),
      ],
      child: MaterialApp(
        builder: (context, child) =>
            PushListener(child: child ?? const SizedBox.shrink()),
        home: Builder(builder: (context) {
          messenger = ScaffoldMessenger.of(context);
          return const Scaffold(body: SizedBox.shrink());
        }),
      ),
    ));
    await tester.pump(); // erster Frame — erst danach hängt der Zuhörer
    return messenger;
  }

  RemoteMessage messageWith(String? body) => RemoteMessage(
      notification: RemoteNotification(title: 'PilzBuddy', body: body));

  testWidgets('eine eintreffende Meldung erscheint als SnackBar',
      (tester) async {
    await pumpListener(tester);
    incoming.add(messageWith('Lilli war am Buchenhang.'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Lilli war am Buchenhang.'), findsOneWidget);
  });

  testWidgets('sie verdrängt eine stehende Rückmeldung', (tester) async {
    // Der Fall vom Pixel: Der Testknopf zeigt „Testnachricht ist
    // unterwegs.", und weil `showSnackBar` sich hinten anstellt, stand
    // die vier Sekunden lang VOR der Meldung, die sie ankündigte.
    final messenger = await pumpListener(tester);
    messenger.showSnackBar(const SnackBar(
        content: Text('Testnachricht ist unterwegs.'),
        duration: Duration(seconds: 4)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Testnachricht ist unterwegs.'), findsOneWidget);

    incoming.add(messageWith('Test — so sieht eine Benachrichtigung aus.'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Test — so sieht eine Benachrichtigung aus.'),
        findsOneWidget);
    expect(find.text('Testnachricht ist unterwegs.'), findsNothing,
        reason: 'die Quittung darf die Meldung nicht überdauern');
  });

  testWidgets('ohne Text passiert nichts', (tester) async {
    // Eine reine Daten-Nachricht hat keine `notification` — dann gibt es
    // auch nichts anzuzeigen, und eine leere SnackBar wäre Lärm.
    await pumpListener(tester);
    incoming.add(messageWith(null));
    incoming.add(const RemoteMessage());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SnackBar), findsNothing);
  });
}
