// Die Zahlen hinter der Teil-Leiter (#276).
//
// **Ohne Server-Eingriff.** Kein Patch, keine RLS, keine Migration: Die
// App hat alles schon. `mySpotsProvider` bringt die eigenen Spots samt
// `sharingExcluded`, `friendSpotsProvider` die der Buddies samt
// `ownerId` — und zwar genau die, die sie teilen, denn die Policy lässt
// nichts anderes durch. Der Rang eines Buddys ist damit schlicht die
// Anzahl seiner Spots, die bei mir ankommen.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/spot.dart';
import '../spots/spot_providers.dart';
import 'profile_providers.dart';
import 'sharing_rank.dart';

/// Wie viele Spots ICH teile.
///
/// Wartende Einträge aus dem Ausgangskorb (#267) zählen bewusst NICHT
/// mit: Sie sind noch nirgends angekommen, kein Buddy kann sie sehen.
/// Beim Statistik-Zählen gilt das Gegenteil (dort sind sie passiert) —
/// hier geht es um Sichtbarkeit für andere.
final mySharedSpotCountProvider = Provider<int>((ref) {
  final spots = ref.watch(mySpotsProvider).valueOrNull?.spots ?? const [];
  final sharesByDefault =
      ref.watch(myProfileProvider).valueOrNull?.shareSpotsDefault ?? true;
  return sharedSpotCount(spots, sharesByDefault: sharesByDefault);
});

/// Mein Titel — `null`, solange ich nichts teile.
final mySharingTitleProvider =
    Provider<String?>((ref) => sharingTitleOf(ref.watch(mySharedSpotCountProvider)));

/// Wie viele fremde Spots ich sehe. Zusammen mit der Zahl darüber ergibt
/// das den Spiegel.
final seenBuddySpotCountProvider = Provider<int>(
    (ref) => ref.watch(friendSpotsProvider).valueOrNull?.length ?? 0);

/// Steht mein Verhältnis schief genug, um es zu benennen?
final sharingMirrorProvider = Provider<bool>((ref) => showsSharingMirror(
      shared: ref.watch(mySharedSpotCountProvider),
      seen: ref.watch(seenBuddySpotCountProvider),
    ));

/// Je Buddy: wie viele Spots er mit mir teilt.
///
/// Das ist genau die Zahl, die auch sein Rang meint — was hier ankommt,
/// hat er freigegeben.
final buddySharedCountsProvider = Provider<Map<String, int>>((ref) {
  final counts = <String, int>{};
  final spots =
      ref.watch(friendSpotsProvider).valueOrNull ?? const <Spot>[];
  for (final spot in spots) {
    counts[spot.ownerId] = (counts[spot.ownerId] ?? 0) + 1;
  }
  return counts;
});
