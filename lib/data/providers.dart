import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config_repository.dart';
import 'auth_repository.dart';
import 'feedback_repository.dart';
import 'friend_repository.dart';
import 'live_share_repository.dart';
import 'idb_factory.dart';
import 'outbox.dart';
import 'outbox_runner.dart';
import 'profile_repository.dart';
import 'push_repository.dart';
import 'spot_cache.dart';
import 'spot_cache_idb.dart';
import 'spot_repository.dart';

final supabaseClientProvider =
    Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authRepositoryProvider =
    Provider((ref) => AuthRepository(ref.watch(supabaseClientProvider)));

/// Zwischenspeicher der eigenen Spots — als Datei (Android), in
/// IndexedDB (Browser, #385), in Tests durch ein temporäres Verzeichnis
/// oder einen Fake ersetzt.
///
/// Ohne IndexedDB (privater Modus mancher Browser, `file://`) bleibt es
/// beim Verhalten von vorher: kein Zwischenspeicher. Das ist ehrlicher
/// als eine Ablage, die jeden Neustart vergisst.
final spotCacheProvider = Provider<SpotCache>(
    (ref) => chooseSpotCache(web: kIsWeb, idb: browserIdbFactory()));

/// Der Ausgangskorb (#267) — dieselbe Aufteilung wie beim
/// Zwischenspeicher: im Web wirkungslos, in Tests ersetzt. Anders als
/// dort ist die Web-Fassung nicht still, sondern wirft beim Ablegen: Ein
/// Fund, der nirgends liegt, darf nicht als gespeichert gelten.
final outboxProvider =
    Provider<Outbox>((ref) => kIsWeb ? const NoOutbox() : FileOutbox());

final spotRepositoryProvider = Provider((ref) => SpotRepository(
      ref.watch(supabaseClientProvider),
      cache: ref.watch(spotCacheProvider),
    ));

/// Die Wiedervorlage des Korbs. Ein Provider und keine Instanz je
/// Aufruf: Seine Sperre gegen Doppelläufe wirkt nur, solange es EINEN
/// Runner gibt.
final outboxRunnerProvider = Provider<OutboxRunner>((ref) => OutboxRunner(
      repository: ref.watch(spotRepositoryProvider),
      outbox: ref.watch(outboxProvider),
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

final pushRepositoryProvider =
    Provider((ref) => PushRepository(ref.watch(supabaseClientProvider)));

/// Auth-Zustand als Stream — steuert den Router-Redirect und sorgt dafür,
/// dass alle Daten-Provider bei Login/Logout neu laden.
final authStateProvider = StreamProvider<AuthState>(
    (ref) => ref.watch(authRepositoryProvider).onAuthStateChange);

final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).currentUserId;
});
