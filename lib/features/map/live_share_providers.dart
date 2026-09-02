import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../data/providers.dart';
import '../../models/friend_location.dart';
import '../friends/friend_providers.dart';
import '../../core/read_after_write.dart';

/// Poll-Intervall der Freundes-Standorte, solange mindestens eine
/// Freigabe LIVE ist. Als Provider, damit Tests es überschreiben (oder
/// den ganzen Stream ersetzen) können.
final friendLocationsPollProvider =
    Provider<Duration>((ref) => const Duration(seconds: 15));

/// Poll-Intervall, solange NIEMAND teilt (#316): Entdecken darf bis zu
/// 90 s dauern (Betreiber-Entscheidung 2026-08-17) — dem Folgen einer
/// schon entdeckten Freigabe gehört weiter der schnelle Takt oben.
final friendLocationsIdlePollProvider =
    Provider<Duration>((ref) => const Duration(seconds: 90));

/// Ist die App im Vordergrund? Gesetzt vom Karten-Screen
/// (`didChangeAppLifecycleState`) — im Hintergrund pollt niemand für
/// einen Bildschirm, den keiner sieht (#316).
final appInForegroundProvider = StateProvider<bool>((ref) => true);

/// Ende meiner laufenden Standort-Freigabe (UTC), oder null, wenn ich gerade
/// nicht teile. Mutationen laufen wie überall über invalidateSelf + reload.
class MyShareNotifier extends AsyncNotifier<DateTime?>
    with ReadAfterWrite<DateTime?> {
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
    await reloadAfterWrite('Standort-Freigabe neu laden');
  }

  Future<void> stop() async {
    await ref.read(liveShareRepositoryProvider).stopSharing();
    await reloadAfterWrite('Standort-Freigabe neu laden');
  }
}

final myShareProvider =
    AsyncNotifierProvider<MyShareNotifier, DateTime?>(MyShareNotifier.new);

/// Ob ich gerade aktiv teile (nicht abgelaufen).
final isSharingProvider = Provider<bool>((ref) {
  final until = ref.watch(myShareProvider).valueOrNull;
  return until != null && until.isAfter(DateTime.now().toUtc());
});

/// Live-Standorte von Freunden, regelmäßig neu geladen. RLS blendet
/// abgelaufene und fremde Freigaben aus; ein Ladefehler behält den letzten
/// Stand (der Stream bricht nie ab).
///
/// Drei Tore, bevor überhaupt gefragt wird (#316 — „every query that
/// isn't necessary should be saved"):
/// 1. Ohne ANGENOMMENE Freundschaft kann niemand mit mir teilen — kein
///    einziger Poll. Die Antwort steckt in `friendshipsProvider`, der
///    ohnehin geladen ist; scheitert DER (Start im Funkloch), wird
///    vorsichtshalber gepollt wie früher, statt Freigaben still zu
///    verpassen.
/// 2. Im Hintergrund ruht die Schleife ganz — der Screen, für den sie
///    lädt, ist nicht zu sehen. Der Karten-Screen setzt das Tor über
///    [appInForegroundProvider]; beim Zurückkehren baut der Provider
///    sich neu und fragt sofort.
/// 3. Solange die Antwort leer ist, gilt der träge Takt
///    ([friendLocationsIdlePollProvider]); erst eine entdeckte Freigabe
///    schaltet auf den schnellen um.
final friendLocationsProvider =
    StreamProvider<List<FriendLocation>>((ref) async* {
  if (ref.watch(currentUserIdProvider) == null) {
    yield const [];
    return;
  }
  final friendships = ref.watch(friendshipsProvider);
  final known = friendships.valueOrNull;
  if (known != null && !known.any((f) => f.isAccepted)) {
    yield const [];
    return;
  }
  if (known == null && friendships.isLoading) {
    // Noch keine Antwort — der Watch oben baut den Provider neu, sobald
    // sie da ist. Bis dahin gibt es nichts zu zeigen und nichts zu tun.
    yield const [];
    return;
  }
  if (!ref.watch(appInForegroundProvider)) {
    yield const [];
    return;
  }
  final repo = ref.watch(liveShareRepositoryProvider);
  final interval = ref.watch(friendLocationsPollProvider);
  final idle = ref.watch(friendLocationsIdlePollProvider);
  var anyoneSharing = false;
  while (true) {
    try {
      final locations = await repo.fetchFriendLocations();
      anyoneSharing = locations.isNotEmpty;
      yield locations;
    } on NotSignedInException {
      // Abmelden ist kein Fehler. Die Schleife läuft noch einen Moment
      // weiter, während die Sitzung schon weg ist — das hier als
      // Fehlerbericht zu schreiben, füllte den Wochendigest mit einem
      // völlig normalen Vorgang (Issue #124). Still aufhören; der
      // Provider baut sich neu auf, sobald wieder jemand angemeldet ist.
      yield const [];
      return;
    } catch (e, stackTrace) {
      // Kein Empfang ist so wenig ein Fehlerbericht wie das Abmelden
      // darüber: Diese Schleife läuft alle paar Sekunden, ein Funkloch
      // schriebe also im Minutentakt nach `error_reports` — und genau so
      // sah der Wochendigest KW32/KW33 aus. Der letzte Stand bleibt
      // stehen, wie oben zugesagt; sichtbar ist der fehlende Empfang
      // ohnehin am Banner (`noConnectivityProvider`).
      if (!looksOffline(e)) logError('Freundes-Standorte laden', e, stackTrace);
    }
    await Future<void>.delayed(anyoneSharing ? interval : idle);
  }
});
