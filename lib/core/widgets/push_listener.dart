// Zeigt Benachrichtigungen an, die eintreffen, während die App vorne ist
// (#277).
//
// **Warum es das überhaupt braucht:** Android zeigt eine
// `notification`-Nutzlast nur an, solange die App NICHT im Vordergrund
// ist. Ist sie es, liefert FCM sie ausschließlich an `onMessage` — und
// ohne Zuhörer verschwindet sie spurlos. Am 2026-08-11 genau so erlebt:
// Gerät eingetragen, FCM quittiert `ok`, und trotzdem kam nichts an.
//
// Liegt im Widget-Baum ganz außen (`app.dart`), damit es überall
// funktioniert und nicht nur auf der Karte — eine Meldung kann eintreffen,
// während jemand im Profil steht.
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors.dart';
import '../push_messaging.dart';

class PushListener extends ConsumerStatefulWidget {
  const PushListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PushListener> createState() => _PushListenerState();
}

class _PushListenerState extends ConsumerState<PushListener> {
  StreamSubscription<RemoteMessage>? _subscription;

  @override
  void initState() {
    super.initState();
    // Nach dem ersten Frame: Vorher gibt es keinen ScaffoldMessenger, an
    // den sich eine SnackBar hängen könnte.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _subscription = ref.read(pushMessageListenerProvider)().listen(_show);
      } catch (e, stackTrace) {
        // Push ist ein Nebenfeature: Ohne Firebase gibt es diesen Strom
        // nicht, und die App läuft trotzdem.
        logError('Vordergrund-Nachrichten verdrahten', e, stackTrace);
      }
    });
  }

  void _show(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null || !mounted) return;
    final body = notification.body;
    if (body == null || body.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(body),
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
