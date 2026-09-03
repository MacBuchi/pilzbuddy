import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/widgets/preview_ribbon.dart';
import 'core/widgets/push_listener.dart';
import 'core/widgets/update_gate.dart';
import 'features/intro/intro_overlay.dart';
import 'core/app_colors.dart';

class PilzBuddyApp extends ConsumerWidget {
  const PilzBuddyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'PilzBuddy',
      routerConfig: router,
      // UpdateGate innen: ist die App zu alt, ersetzt er den Router-Inhalt
      // komplett — die Intro-Animation läuft trotzdem einmal durch.
      // PushListener ganz außen: Eine Meldung kann eintreffen, während
      // jemand im Profil oder in der Freundesliste steht, nicht nur auf
      // der Karte. Ohne ihn verschwinden Nachrichten, die ankommen,
      // während die App vorne ist — Android zeigt sie dann nicht selbst
      // an (#277).
      // PreviewRibbon ganz außen: Der Hinweis, dass dies ein
      // Entwicklungsstand ist, gilt auch über der Update-Sperre und der
      // Intro-Animation — gerade dort, wo sonst nichts von der App zu
      // sehen ist (#388). Im normalen Build reicht er nur durch.
      builder: (context, child) => PreviewRibbon(
        child: PushListener(
          child: IntroOverlay(
              child: UpdateGate(child: child ?? const SizedBox.shrink())),
        ),
      ),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.forestGreen,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
    );
  }
}
