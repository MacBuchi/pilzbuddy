import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/providers.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/friends/friends_screen.dart';
import '../features/import_export/import_screen.dart';
import '../features/map/map_screen.dart';
import '../features/offline_maps/offline_maps_screen.dart';
import '../features/profile/profile_screen.dart';

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
  final refresh = _AuthRefresh(authRepository.onAuthStateChange);
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
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/friends',
                builder: (context, state) => const FriendsScreen()),
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
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Karte'),
          NavigationDestination(icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group), label: 'Freunde'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}
