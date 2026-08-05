import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/spot_repository.dart';
import '../../models/spot.dart';
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
    // Seit #190 kann der Fund an einem FREUNDES-Spot hängen — dann muss
    // dessen Liste neu laden, sonst erscheint er erst beim App-Resume.
    // Immer statt fallweise: Der Notifier kennt die Zuordnung nicht, und
    // ein überflüssiger Refetch bei Hobby-Datenmengen ist billiger als
    // eine Fallunterscheidung.
    ref.invalidate(friendSpotsProvider);
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
