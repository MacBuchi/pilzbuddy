import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../data/providers.dart';
import '../../models/friend_location.dart';

/// Poll-Intervall der Freundes-Standorte. Als Provider, damit Tests es
/// überschreiben (oder den ganzen Stream ersetzen) können.
final friendLocationsPollProvider =
    Provider<Duration>((ref) => const Duration(seconds: 15));

/// Ende meiner laufenden Standort-Freigabe (UTC), oder null, wenn ich gerade
/// nicht teile. Mutationen laufen wie überall über invalidateSelf + reload.
class MyShareNotifier extends AsyncNotifier<DateTime?> {
  @override
  Future<DateTime?> build() {
    ref.watch(currentUserIdProvider);
    if (ref.read(currentUserIdProvider) == null) return Future.value(null);
    return ref.read(liveShareRepositoryProvider).fetchMyShare();
  }

  /// Standort ab jetzt für [duration] teilen; die erste Position wird sofort
  /// hochgeschoben, damit Freunde einen sofort sehen.
  Future<void> share({
    required Duration duration,
    required double lat,
    required double lng,
  }) async {
    final expiresAt = DateTime.now().toUtc().add(duration);
    await ref.read(liveShareRepositoryProvider).upsertMyLocation(
          lat: lat,
          lng: lng,
          expiresAt: expiresAt,
        );
    ref.invalidateSelf();
    await future;
  }

  Future<void> stop() async {
    await ref.read(liveShareRepositoryProvider).stopSharing();
    ref.invalidateSelf();
    await future;
  }
}

final myShareProvider =
    AsyncNotifierProvider<MyShareNotifier, DateTime?>(MyShareNotifier.new);

/// Ob ich gerade aktiv teile (nicht abgelaufen).
final isSharingProvider = Provider<bool>((ref) {
  final until = ref.watch(myShareProvider).valueOrNull;
  return until != null && until.isAfter(DateTime.now().toUtc());
});

/// Live-Standorte von Freunden, alle paar Sekunden neu geladen. RLS blendet
/// abgelaufene und fremde Freigaben aus; ein Ladefehler behält den letzten
/// Stand (der Stream bricht nie ab).
final friendLocationsProvider =
    StreamProvider<List<FriendLocation>>((ref) async* {
  if (ref.watch(currentUserIdProvider) == null) {
    yield const [];
    return;
  }
  final repo = ref.watch(liveShareRepositoryProvider);
  final interval = ref.watch(friendLocationsPollProvider);
  while (true) {
    try {
      yield await repo.fetchFriendLocations();
    } catch (e, stackTrace) {
      logError('Freundes-Standorte laden', e, stackTrace);
    }
    await Future<void>.delayed(interval);
  }
});
