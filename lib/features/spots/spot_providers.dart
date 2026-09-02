import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../data/outbox.dart';
import '../../data/outbox_runner.dart';
import '../../data/outbox_view.dart';
import '../../data/providers.dart';
import '../../data/spot_repository.dart';
import '../../models/spot.dart';
import 'nearby_spots.dart';
import 'species_suggestions.dart';
import '../../core/read_after_write.dart';

/// Eigene Spots aus Supabase. Mutationen laufen über den Notifier und
/// laden anschließend neu — bei Hobby-Datenmengen völlig ausreichend.
///
/// Der Zustand trägt die Herkunft mit: Ohne Empfang kommen die Spots aus
/// dem Zwischenspeicher, und die Karte sagt das dazu, statt veraltete
/// Daten als aktuell auszugeben. Seit #267 trägt er außerdem den
/// Ausgangskorb — die Einträge, die noch auf die Übertragung warten,
/// stehen als `pending` mit in der Liste.
class MySpotsNotifier extends AsyncNotifier<SpotsWithOutbox>
    with ReadAfterWrite<SpotsWithOutbox> {
  @override
  Future<SpotsWithOutbox> build() async {
    // Bei Login/Logout automatisch neu laden.
    ref.watch(currentUserIdProvider);
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) {
      return (
        spots: const <Spot>[],
        cachedAt: null,
        pending: const <OutboxJob>[]
      );
    }
    final snapshot = await ref.read(spotRepositoryProvider).fetchMySpots();
    // Der Korb wird IMMER gelesen, auch wenn die Spots frisch aus dem
    // Netz kamen: Ein Auftrag kann liegen bleiben, während der Abruf
    // längst wieder geht (etwa nach einer Ablehnung des Servers).
    final pending = await ref.read(outboxProvider).read(uid: uid);
    return (
      spots: withPendingJobs(snapshot.spots, pending, ownerId: uid),
      cachedAt: snapshot.cachedAt,
      pending: pending,
    );
  }

  /// Legt einen Auftrag in den Korb, wenn der Grund fehlender Empfang
  /// war — sonst fliegt der Fehler weiter.
  ///
  /// Die Regel ist dieselbe wie beim Zwischenspeicher: **nur** ein
  /// Netzfehler wird abgefangen. Ein Serverfehler (RLS kaputt, Spalte
  /// umbenannt) muss sichtbar scheitern, sonst sammelte der Korb still
  /// Aufträge, die nie durchgehen, und niemand erführe vom kaputten
  /// Deployment (Lehre aus #80).
  ///
  /// Scheitert auch das Ablegen, wird der URSPRÜNGLICHE Fehler geworfen:
  /// „Keine Verbindung" ist die Wahrheit, die die Nutzerin braucht — der
  /// Korb ist der Rettungsversuch, nicht die Ursache.
  Future<void> _queueIfOffline(
      Object error, StackTrace stackTrace, OutboxJob job) async {
    if (!looksOffline(error)) Error.throwWithStackTrace(error, stackTrace);
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) Error.throwWithStackTrace(error, stackTrace);
    try {
      await ref.read(outboxProvider).append(job, uid: uid);
    } catch (_) {
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Wartet dieser Spot selbst noch auf die Übertragung? Dann ist seine
  /// „id" die Kennung eines Auftrags im Korb.
  bool _isPending(String spotId) =>
      state.valueOrNull?.pending
          .any((job) => job is NewSpotJob && job.id == spotId) ??
      false;

  /// Wirft die lokale Kopie weg — beim Abmelden und beim Löschen des
  /// Kontos.
  ///
  /// Bewusst hier und nicht in `build()`, wenn die Nutzer-id null wird:
  /// Der Passwort-Reset meldet sich zwischendurch ebenfalls ab
  /// (`login_screen.dart` filtert das Ereignis), und dort bleibt es
  /// dasselbe Konto. Und gäbe es beim Start je ein kurzes Fenster ohne
  /// Nutzer-id, würde ein Löschen an dieser Stelle den Zwischenspeicher
  /// bei JEDEM Kaltstart vernichten — also genau dann, wenn er gebraucht
  /// wird. Gegen fremde Konten schützt ohnehin die id-Prüfung beim Lesen.
  /// Der Ausgangskorb geht mit: Er trägt dieselben Fundstellen, nur noch
  /// ungesendet. Beim Abmelden wird vorher gefragt (Profil-Bildschirm) —
  /// hier wird nur ausgeführt.
  Future<void> forgetCache() async {
    await ref.read(spotCacheProvider).clear();
    await ref.read(outboxProvider).clear();
  }

  /// Neuer Spot. Ohne Empfang wandert er in den Ausgangskorb (#267) und
  /// erscheint sofort als wartender Marker auf der Karte.
  ///
  /// Der Auftrag entsteht VOR dem Sendeversuch, mit allen Kennungen: Nur
  /// so trägt schon der erste Versuch die `client_id`, und ein Abriss
  /// nach dem Insert führt beim Nachholen nicht zu einem zweiten Spot am
  /// selben Fleck (Patch 016).
  ///
  /// Gibt zurück, ob die LISTE danach frisch ist. `false` heißt: Der Spot
  /// liegt, aber die Karte zeigt ihn noch nicht — und genau das muss die
  /// Oberfläche sagen können, sonst legt ihn jemand ein zweites Mal an
  /// (#371). Ein Schreibfehler wirft weiterhin.
  Future<bool> addSpot({
    required double lat,
    required double lng,
    String? name,
    required List<NewFind> finds,
  }) async {
    final job = NewSpotJob(
      id: newClientId(),
      createdAt: DateTime.now(),
      lat: lat,
      lng: lng,
      name: name,
      finds: [for (final find in finds) find.withClientId(newClientId())],
    );
    try {
      await ref.read(spotRepositoryProvider).addSpot(
            lat: job.lat,
            lng: job.lng,
            name: job.name,
            finds: job.finds,
            clientId: job.id,
          );
    } catch (error, stackTrace) {
      await _queueIfOffline(error, stackTrace, job);
    }
    return reloadAfterWrite('Spots neu laden');
  }

  /// Einträge an einem Spot — auch an einem, der selbst noch im Korb
  /// liegt: Wer offline einen Spot anlegt und gleich noch eine zweite Art
  /// nachträgt, soll nicht am fehlenden Netz scheitern.
  /// Gibt wie [addSpot] zurück, ob die Liste danach frisch ist.
  Future<bool> addFinds({
    required String spotId,
    required List<NewFind> finds,
  }) async {
    final spotIsPending = _isPending(spotId);
    final job = NewFindsJob(
      id: newClientId(),
      createdAt: DateTime.now(),
      spotId: spotId,
      spotIsPending: spotIsPending,
      finds: [for (final find in finds) find.withClientId(newClientId())],
    );
    if (spotIsPending) {
      // Es gibt nichts, wohin gesendet werden könnte — der Spot selbst
      // wartet noch. Direkt in den Korb, hinter seinen Spot.
      final uid = ref.read(currentUserIdProvider);
      if (uid == null) throw const NotSignedInException();
      await ref.read(outboxProvider).append(job, uid: uid);
    } else {
      try {
        await ref
            .read(spotRepositoryProvider)
            .addFinds(spotId: spotId, finds: job.finds);
      } catch (error, stackTrace) {
        await _queueIfOffline(error, stackTrace, job);
      }
    }
    // Seit #190 kann der Fund an einem FREUNDES-Spot hängen — dann muss
    // dessen Liste neu laden, sonst erscheint er erst beim App-Resume.
    // Immer statt fallweise: Der Notifier kennt die Zuordnung nicht, und
    // ein überflüssiger Refetch bei Hobby-Datenmengen ist billiger als
    // eine Fallunterscheidung.
    ref.invalidate(friendSpotsProvider);
    return reloadAfterWrite('Spots neu laden');
  }

  /// Korrigiert einen einzelnen Eintrag (#240) — und löscht einen
  /// einzelnen (dito). Beide laden danach neu wie [addFinds], und aus
  /// demselben Grund auch die Freundes-Spots: Der Eintrag kann an einem
  /// fremden Spot hängen.
  Future<void> updateFind({
    required String findId,
    required NewFind find,
  }) async {
    await ref
        .read(spotRepositoryProvider)
        .updateFind(findId: findId, find: find);
    ref.invalidate(friendSpotsProvider);
    await reloadAfterWrite('Spots neu laden');
  }

  Future<void> deleteFind(String findId) async {
    await ref.read(spotRepositoryProvider).deleteFind(findId);
    ref.invalidate(friendSpotsProvider);
    await reloadAfterWrite('Spots neu laden');
  }

  /// Stellt mehrere Spots aus einer GPX-Sicherung wieder her (#112).
  ///
  /// Nimmt die ganze Liste und lädt **einmal** am Ende neu — bei
  /// dreißig Spots wären dreißig Read-after-write dreißig volle Abrufe
  /// der Spot-Liste, und nichts davon sieht jemand, bevor der letzte
  /// durch ist.
  ///
  /// Gibt zurück, wie viele angelegt wurden. Ein Fehler in der Mitte
  /// bricht ab und wirft — was bis dahin geschrieben ist, bleibt und
  /// erscheint nach dem Neuladen. Das ist besser als still
  /// weiterzumachen: Wer die Hälfte seiner Sicherung importiert hat,
  /// muss das erfahren.
  Future<int> restoreSpots(List<RestorableSpot> spots) async {
    final repository = ref.read(spotRepositoryProvider);
    var created = 0;
    try {
      for (final spot in spots) {
        await repository.restoreSpot(
          lat: spot.lat,
          lng: spot.lng,
          name: spot.name,
          sharingExcluded: spot.sharingExcluded,
          finds: spot.finds,
        );
        created++;
      }
    } finally {
      await reloadAfterWrite('Spots neu laden');
    }
    return created;
  }

  /// Zwei eigene Spots zu einem machen (#215). Lädt danach neu — die
  /// Karte verliert einen Marker und ein anderer erbt die Funde.
  Future<void> mergeSpots(
      {required String intoId, required String fromId}) async {
    await ref
        .read(spotRepositoryProvider)
        .mergeSpots(intoId: intoId, fromId: fromId);
    await reloadAfterWrite('Spots neu laden');
  }

  /// Arbeitet den Ausgangskorb ab (#267) und lädt danach neu.
  ///
  /// Angestoßen bei der Rückkehr der Verbindung, beim Start und auf
  /// Tippen im Banner. Doppelläufe hält der Runner selbst auseinander.
  Future<OutboxRunResult> sendOutbox() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return (sent: 0, remaining: 0, failed: 0);
    final result = await ref.read(outboxRunnerProvider).run(uid: uid);
    if (result.sent > 0 || result.remaining > 0) {
      await reloadAfterWrite('Spots neu laden');
    }
    return result;
  }

  /// Nimmt einen wartenden Auftrag zurück — der Weg für „doch nicht"
  /// und für einen Auftrag, den der Server dauerhaft ablehnt.
  Future<void> discardJob(String jobId) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final outbox = ref.read(outboxProvider);
    final jobs = await outbox.read(uid: uid);
    await outbox.replaceAll([
      for (final job in jobs)
        if (job.id != jobId &&
            // Funde, die an diesem Spot hingen, verlieren mit ihm ihren
            // Ort — sie mitzunehmen ist ehrlicher, als sie unsichtbar
            // liegen zu lassen.
            !(job is NewFindsJob && job.spotIsPending && job.spotId == jobId))
          job,
    ], uid: uid);
    await reloadAfterWrite('Spots neu laden');
  }

  /// Löscht einen Spot. Wartet er noch auf die Übertragung, gibt es
  /// nichts zu löschen — dann wird sein Auftrag zurückgenommen.
  Future<void> deleteSpot(String spotId) async {
    if (_isPending(spotId)) return discardJob(spotId);
    await ref.read(spotRepositoryProvider).deleteSpot(spotId);
    await reloadAfterWrite('Spots neu laden');
  }

  Future<void> setSharingExcluded(String spotId, bool excluded) async {
    await ref.read(spotRepositoryProvider).setSharingExcluded(spotId, excluded);
    await reloadAfterWrite('Spots neu laden');
  }
}

final mySpotsProvider = AsyncNotifierProvider<MySpotsNotifier, SpotsWithOutbox>(
    MySpotsNotifier.new);

/// Nur die Spots, ohne Herkunft — das ist, was fast alle Aufrufer wollen.
/// Die Herkunft interessiert allein das Banner auf der Karte.
final mySpotListProvider = Provider<List<Spot>>(
    (ref) => ref.watch(mySpotsProvider).valueOrNull?.spots ?? const <Spot>[]);

/// Eigene Spot-Paare, die dichter als [kNearbySpotMeters] beieinander
/// liegen (#215) — nächstes zuerst.
///
/// Als Provider, damit Profil-Eintrag und Aufräum-Seite dieselbe Liste
/// sehen: Der Eintrag erscheint nur, wenn es wirklich etwas zu tun gibt,
/// und nach dem Zusammenführen verschwindet beides zusammen.
final overlappingSpotPairsProvider = Provider<List<SpotPair>>(
    (ref) => overlappingPairs(ref.watch(mySpotListProvider)));

/// Die Aufträge im Ausgangskorb (#267).
final pendingJobsProvider = Provider<List<OutboxJob>>((ref) =>
    ref.watch(mySpotsProvider).valueOrNull?.pending ?? const <OutboxJob>[]);

/// Wie viele Einträge insgesamt warten — die Zahl im Banner.
final pendingEntryCountProvider =
    Provider<int>((ref) => pendingEntryCount(ref.watch(pendingJobsProvider)));

/// Aufträge, die der Server dauerhaft abgelehnt hat. Sie brauchen eine
/// Entscheidung von Hand und verschwinden nicht von allein.
final failedJobsProvider =
    Provider<List<OutboxJob>>((ref) => failedJobs(ref.watch(pendingJobsProvider)));

/// Zeitpunkt der zwischengespeicherten Daten — `null`, solange die Spots
/// frisch aus dem Netz kommen.
final mySpotsCachedAtProvider = Provider<DateTime?>(
    (ref) => ref.watch(mySpotsProvider).valueOrNull?.cachedAt);

/// Von Freunden geteilte Spots. Wird nach Freundschafts-Änderungen
/// invalidiert (siehe FriendsScreen) und lädt bei Login/Logout neu.
final friendSpotsProvider = FutureProvider<List<Spot>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Future.value([]);
  return ref.watch(spotRepositoryProvider).fetchFriendSpots();
});

/// Eigene Pilzarten, zuletzt benutzt zuerst — abgeleitet aus den EIGENEN
/// Funden (Buddy-Funde auf eigenen Spots sind nicht „meine Arten").
/// Erster Eintrag = Default-Vorauswahl für neue Spots/Funde.
final ownSpeciesProvider = Provider<List<String>>((ref) {
  final spots = ref.watch(mySpotListProvider);
  final finds = [for (final s in spots) ...s.ownFinds]..sort((a, b) {
      final aTime = a.createdAt ?? a.foundOn;
      final bTime = b.createdAt ?? b.foundOn;
      return bTime.compareTo(aTime);
    });
  return ownSpeciesFromSortedNames(finds.map((f) => f.species));
});
