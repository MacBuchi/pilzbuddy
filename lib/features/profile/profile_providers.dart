import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../models/profile.dart';

class MyProfileNotifier extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() {
    ref.watch(currentUserIdProvider);
    if (ref.read(currentUserIdProvider) == null) return Future.value(null);
    return ref.read(profileRepositoryProvider).fetchMyProfile();
  }

  Future<void> updateSharing({
    bool? shareSpotsDefault,
    bool? shareDetails,
  }) async {
    await ref.read(profileRepositoryProvider).updateSharing(
          shareSpotsDefault: shareSpotsDefault,
          shareDetails: shareDetails,
        );
    ref.invalidateSelf();
    await future;
  }
}

final myProfileProvider =
    AsyncNotifierProvider<MyProfileNotifier, Profile?>(MyProfileNotifier.new);
