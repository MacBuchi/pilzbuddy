import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../models/friendship.dart';
import '../spots/spot_providers.dart';
import '../../core/read_after_write.dart';

class FriendshipsNotifier extends AsyncNotifier<List<FriendshipEntry>>
    with ReadAfterWrite<List<FriendshipEntry>> {
  @override
  Future<List<FriendshipEntry>> build() {
    ref.watch(currentUserIdProvider);
    if (ref.read(currentUserIdProvider) == null) return Future.value([]);
    return ref.read(friendRepositoryProvider).fetchFriendships();
  }

  Future<void> sendRequest(String addresseeId) async {
    await ref.read(friendRepositoryProvider).sendRequest(addresseeId);
    await reloadAfterWrite('Freundschaften neu laden');
  }

  Future<void> accept(String friendshipId) async {
    await ref.read(friendRepositoryProvider).accept(friendshipId);
    await reloadAfterWrite('Freundschaften neu laden');
    // Neue Freundschaft = eventuell neue sichtbare Spots.
    ref.invalidate(friendSpotsProvider);
  }

  Future<void> remove(String friendshipId) async {
    await ref.read(friendRepositoryProvider).remove(friendshipId);
    await reloadAfterWrite('Freundschaften neu laden');
    ref.invalidate(friendSpotsProvider);
  }
}

final friendshipsProvider =
    AsyncNotifierProvider<FriendshipsNotifier, List<FriendshipEntry>>(
        FriendshipsNotifier.new);
