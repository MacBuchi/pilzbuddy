import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/coach/coach.dart';
import '../features/help/map_tour.dart' show NavCoach;
import '../data/providers.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/changelog/changelog_screen.dart';
import '../features/help/help_screen.dart';
import '../features/highlights/discover_screen.dart';
import '../features/friends/conversation_screen.dart';
import '../features/friends/friends_screen.dart';
import '../features/friends/message_providers.dart';
import '../features/import_export/import_screen.dart';
import '../features/map/map_screen.dart';
import '../features/offline_maps/offline_maps_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/species/species_detail_screen.dart';
import '../features/species/species_screen.dart';
import '../features/spots/spot_cleanup_screen.dart';
import '../features/spots/spots_screen.dart';

/// Stößt den Router-Redirect an, sobald sich der Auth-Zustand ändert.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  // `passwordRecovery` bewusst nicht durchlassen: Ein eingelöster
  // Reset-Code erzeugt eine gültige Sitzung, BEVOR das neue Passwort
  // gesetzt ist. Würde der Router darauf reagieren, läge die Karte
  // mitten im Reset offen und die Nutzerin wäre angemeldet, ohne ihr
  // Passwort zu kennen. Der Login-Screen bleibt deshalb stehen, bis
  // `updateUser` das Passwort wirklich geändert hat — dessen
  // `userUpdated`-Ereignis öffnet die App dann (siehe
  // AuthRepository.resetPasswordWithCode).
  final refresh = _AuthRefresh(authRepository.onAuthStateChange
      .where((state) => state.event != AuthChangeEvent.passwordRecovery));
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = authRepository.currentSession != null;
      final onAuthPage = state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup';
      if (!loggedIn) return onAuthPage ? null : '/login';
      if (onAuthPage) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),

      GoRoute(
          path: '/signup', builder: (context, state) => const SignupScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (context, state) => const MapScreen()),
          ]),
          // Der Reiter „Spots" (#509) steht direkt neben der Karte,
          // weil er dieselben Daten zeigt — nur als Liste, sortiert
          // nach dem, was die Karte nicht kann: der Zeit.
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/spots',
                builder: (context, state) => const SpotsScreen()),
          ]),
          // Der Reiter „Pilze" (seit 1.153.0) steht neben der Karte,
          // weil er ihre Legende ist: Welche Art gehört zu welcher
          // Ampel-Gruppe, und wann wird sie gemeldet.
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/pilze',
                builder: (context, state) => const SpeciesScreen(),
                // Die Detailseite je Art (#511) als Unterroute, wie die
                // Seiten des Profil-Tabs: Die Reiterleiste bleibt
                // stehen, und der Weg zurück ist der übliche.
                routes: [
                  GoRoute(
                      path: ':name',
                      // **Der Schlüssel ist Pflicht, nicht Kosmetik.**
                      // Ohne ihn ist die Seite der nächsten Art für
                      // Flutter dasselbe Widget, das Element wird
                      // weiterverwendet — und die `ListView` behält ihre
                      // Scrollposition. Wer von einem
                      // Verwechslungspartner aus weitertippt, landete
                      // dann mitten auf dessen Seite statt oben bei
                      // Namen und Einstufung, also genau dort, wo die
                      // Auskunft steht, wegen der er getippt hat.
                      builder: (context, state) {
                        final name = state.pathParameters['name'] ?? '';
                        return SpeciesDetailScreen(
                            key: ValueKey(name), species: name);
                      }),
                ]),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/friends',
                builder: (context, state) => const FriendsScreen(),
                // Der Verlauf mit einem Buddy (#564) als Unterroute: Die
                // Reiterleiste bleibt, und der Weg zurück ist der
                // übliche. Der Schlüssel aus demselben Grund wie bei den
                // Artseiten — sonst übernähme der nächste Verlauf das
                // Element samt Textfeld des vorigen.
                routes: [
                  GoRoute(
                      path: 'chat/:id',
                      builder: (context, state) {
                        final id = state.pathParameters['id'] ?? '';
                        return ConversationScreen(
                            key: ValueKey(id), otherId: id);
                      }),
                ]),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
                // Unterrouten des Profil-Tabs (statt imperativem
                // Navigator.push, Issue #56) — die Tab-Leiste bleibt
                // sichtbar, Downloads laufen beim Tab-Wechsel weiter.
                routes: [
                  GoRoute(
                      path: 'offline-maps',
                      builder: (context, state) =>
                          const OfflineMapsScreen()),
                  GoRoute(
                      path: 'import',
                      builder: (context, state) => const ImportScreen()),
                  GoRoute(
                      path: 'spot-cleanup',
                      builder: (context, state) => const SpotCleanupScreen()),
                  GoRoute(
                      path: 'changelog',
                      builder: (context, state) => const ChangelogScreen()),
                  GoRoute(
                      path: 'anleitung',
                      builder: (context, state) => const HelpScreen()),
                  GoRoute(
                      path: 'entdecken',
                      builder: (context, state) => const DiscoverScreen()),
                ]),
          ]),
        ],
      ),
    ],
  );
});

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Die Tastatur ÜBERLAGERT, sie schiebt nicht (#397).
      //
      // Ab Werk schrumpft ein Scaffold seinen Body um `viewInsets.bottom`.
      // Hier heißt das: Karte, Legende, Knopfspalte UND die Reiterleiste
      // wandern hoch, sobald irgendwo ein Textfeld den Fokus bekommt —
      // obwohl in dieser Hülle gar kein Eingabefeld liegt. Die Felder
      // stecken alle in eigenen Routen (Blätter, Dialoge), und die
      // rechnen ihr `viewInsets` selbst ein (`add_spot_sheet.dart`,
      // `add_find_sheet.dart`, `edit_find_sheet.dart`); der Reiter
      // „Freunde" hat einen eigenen Scaffold, der weiter ausweicht.
      //
      // Der eigentliche Anlass ist aber der seltene Fall aus dem
      // Feldbericht: Bleibt das Inset nach dem Schließen der Tastatur
      // stehen, schrumpft der Scaffold WEITER — und was man dann sieht,
      // ist das untere Drittel in `colorScheme.surface`, also weiß. Die
      // Ursache dieses hängenden Insets ist nicht gefunden (nicht
      // reproduzierbar); diese Zeile nimmt ihr die sichtbare Wirkung, und
      // zwar strukturell: Was nicht schrumpft, kann keinen Streifen
      // hinterlassen.
      resizeToAvoidBottomInset: false,
      body: navigationShell,
      bottomNavigationBar: CoachAnchor(
        id: NavCoach.bar,
        child: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        // Die Anker der Karten-Tour (#596): Sie nennt die Bereiche
        // zum Schluss, der Ring liegt je Bereich.
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Karte'),
          CoachAnchor(
              id: NavCoach.spots,
              child: NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'Spots')),
          CoachAnchor(
              id: NavCoach.pilze,
              child: NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Pilze')),
          // Ungelesene Nachrichten (#564) als Punkt am Reiter.
          CoachAnchor(
              id: NavCoach.buddys,
              child: NavigationDestination(
                  icon: BuddysNavIcon(selected: false),
                  selectedIcon: BuddysNavIcon(selected: true),
                  label: 'Buddys')),
          CoachAnchor(
              id: NavCoach.profile,
              child: NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil')),
        ],
      )),
    );
  }
}

/// Das Symbol des Reiters „Buddys" — mit Punkt, solange ungelesene
/// Nachrichten da sind (#564). Beobachten ist laden: Das ist die EINE
/// Stelle, an der die Nachrichten schon beim Start geholt werden; eine
/// Zeile je Nachricht aus 30 Tagen, und ohne sie gäbe es den Punkt nicht.
class BuddysNavIcon extends ConsumerWidget {
  const BuddysNavIcon({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread =
        ref.watch(unreadMessagesProvider).values.fold(0, (a, b) => a + b);
    final icon = Icon(selected ? Icons.group : Icons.group_outlined);
    if (unread == 0) return icon;
    return Badge(
      key: const Key('buddys-unread-badge'),
      label: Text('$unread'),
      child: icon,
    );
  }
}
