import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/spot_repository.dart';
import '../../models/spot.dart';
import 'nearby_spots.dart';
import 'species_suggestions.dart';

/// Eigene Spots aus Supabase. Mutationen laufen über den Notifier und
/// laden anschließend neu — bei Hobby-Datenmengen völlig ausreichend.
///
/// Der Zustand trägt die Herkunft mit ([SpotsSnapshot]): Ohne Empfang
/// kommen die Spots aus dem Zwischenspeicher, und die Karte sagt das
/// dazu, statt veraltete Daten als aktuell auszugeben.
class MySpotsNotifier extends AsyncNotifier<SpotsSnapshot> {
  @override
  Future<SpotsSnapshot> build() async {
    // Bei Login/Logout automatisch neu laden.
    ref.watch(currentUserIdProvider);
    if (ref.read(currentUserIdProvider) == null) {
      return (spots: const <Spot>[], cachedAt: null);
    }
    return ref.read(spotRepositoryProvider).fetchMySpots();
  }

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
  Future<void> forgetCache() => ref.read(spotCacheProvider).clear();

  Future<void> addSpot({
    required double lat,
    required double lng,
    String? name,
    required List<NewFind> finds,
  }) async {
    await ref
        .read(spotRepositoryProvider)
        .addSpot(lat: lat, lng: lng, name: name, finds: finds);
    ref.invalidateSelf();
    await future;
  }

  Future<void> addFinds({
    required String spotId,
    required List<NewFind> finds,
  }) async {
    await ref
        .read(spotRepositoryProvider)
        .addFinds(spotId: spotId, finds: finds);
    ref.invalidateSelf();
    // Seit #190 kann der Fund an einem FREUNDES-Spot hängen — dann muss
    // dessen Liste neu laden, sonst erscheint er erst beim App-Resume.
    // Immer statt fallweise: Der Notifier kennt die Zuordnung nicht, und
    // ein überflüssiger Refetch bei Hobby-Datenmengen ist billiger als
    // eine Fallunterscheidung.
    ref.invalidate(friendSpotsProvider);
    await future;
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
    ref.invalidateSelf();
    ref.invalidate(friendSpotsProvider);
    await future;
  }

  Future<void> deleteFind(String findId) async {
    await ref.read(spotRepositoryProvider).deleteFind(findId);
    ref.invalidateSelf();
    ref.invalidate(friendSpotsProvider);
    await future;
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
      ref.invalidateSelf();
      await future;
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
    AsyncNotifierProvider<MySpotsNotifier, SpotsSnapshot>(MySpotsNotifier.new);

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
