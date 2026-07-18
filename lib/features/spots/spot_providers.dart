import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../models/spot.dart';

/// Eigene Spots aus Supabase. Mutationen laufen über den Notifier und
/// laden anschließend neu — bei Hobby-Datenmengen völlig ausreichend.
class MySpotsNotifier extends AsyncNotifier<List<Spot>> {
  @override
  Future<List<Spot>> build() {
    // Bei Login/Logout automatisch neu laden.
    ref.watch(currentUserIdProvider);
    if (ref.read(currentUserIdProvider) == null) return Future.value([]);
    return ref.read(spotRepositoryProvider).fetchMySpots();
  }

  Future<void> addSpot({
    required double lat,
    required double lng,
    String? name,
    String? species,
    int? count,
    required DateTime foundOn,
    String? note,
  }) async {
    await ref.read(spotRepositoryProvider).addSpot(
          lat: lat,
          lng: lng,
          name: name,
          species: species,
          count: count,
          foundOn: foundOn,
          note: note,
        );
    ref.invalidateSelf();
    await future;
  }

  Future<void> addFind({
    required String spotId,
    String? species,
    int? count,
    required DateTime foundOn,
    String? note,
  }) async {
    await ref.read(spotRepositoryProvider).addFind(
          spotId: spotId,
          species: species,
          count: count,
          foundOn: foundOn,
          note: note,
        );
    ref.invalidateSelf();
    await future;
  }

  Future<void> deleteSpot(String spotId) async {
    await ref.read(spotRepositoryProvider).deleteSpot(spotId);
    ref.invalidateSelf();
    await future;
  }

  Future<void> setSharingExcluded(String spotId, bool excluded) async {
    await ref.read(spotRepositoryProvider).setSharingExcluded(spotId, excluded);
    ref.invalidateSelf();
    await future;
  }
}

final mySpotsProvider =
    AsyncNotifierProvider<MySpotsNotifier, List<Spot>>(MySpotsNotifier.new);

/// Von Freunden geteilte Spots. Wird nach Freundschafts-Änderungen
/// invalidiert (siehe FriendsScreen) und lädt bei Login/Logout neu.
final friendSpotsProvider = FutureProvider<List<Spot>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value([]);
  return ref.watch(spotRepositoryProvider).fetchFriendSpots();
});
