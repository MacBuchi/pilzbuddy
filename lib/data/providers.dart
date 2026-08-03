import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config_repository.dart';
import 'auth_repository.dart';
import 'feedback_repository.dart';
import 'friend_repository.dart';
import 'live_share_repository.dart';
import 'profile_repository.dart';
import 'spot_cache.dart';
import 'spot_repository.dart';

final supabaseClientProvider =
    Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authRepositoryProvider =
    Provider((ref) => AuthRepository(ref.watch(supabaseClientProvider)));

/// Zwischenspeicher der eigenen Spots — im Web bewusst wirkungslos
/// (`path_provider` hat dort kein App-Verzeichnis), in Tests durch ein
/// temporäres Verzeichnis ersetzt.
final spotCacheProvider = Provider<SpotCache>(
    (ref) => kIsWeb ? const NoSpotCache() : FileSpotCache());

final spotRepositoryProvider = Provider((ref) => SpotRepository(
      ref.watch(supabaseClientProvider),
      cache: ref.watch(spotCacheProvider),
    ));

final profileRepositoryProvider =
    Provider((ref) => ProfileRepository(ref.watch(supabaseClientProvider)));

final friendRepositoryProvider =
    Provider((ref) => FriendRepository(ref.watch(supabaseClientProvider)));

final feedbackRepositoryProvider =
    Provider((ref) => FeedbackRepository(ref.watch(supabaseClientProvider)));

final liveShareRepositoryProvider =
    Provider((ref) => LiveShareRepository(ref.watch(supabaseClientProvider)));

final appConfigRepositoryProvider =
    Provider((ref) => AppConfigRepository(ref.watch(supabaseClientProvider)));

/// Auth-Zustand als Stream — steuert den Router-Redirect und sorgt dafür,
/// dass alle Daten-Provider bei Login/Logout neu laden.
final authStateProvider = StreamProvider<AuthState>(
    (ref) => ref.watch(authRepositoryProvider).onAuthStateChange);

final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).currentUserId;
});
