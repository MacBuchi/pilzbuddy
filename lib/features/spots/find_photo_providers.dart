// Fundfotos (#532): was die Oberfläche beobachtet.
//
// **Ein Provider, eine Abfrage.** Streifen im Reiter „Spots", Fotos im
// Spot-Blatt und die Vergrößerung lesen dieselbe Liste
// ([findPhotosProvider], ≤ ein paar Dutzend Zeilen) und filtern daraus.
// Er hängt an den Spot-Providern: Laden die neu (Login, Freundschaft,
// eigener Eintrag), lädt er mit — ein eigener Takt wäre ein zweiter
// Poll für dieselbe Frage.
//
// **Beobachten ist laden** gilt für die BYTES: [findPhotoBytesProvider]
// holt ein Bild erst, wenn eine Kachel es anzeigt, und die Vergrößerung
// holt das volle erst beim Öffnen.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/settings.dart';
import '../../data/providers.dart';
import '../../models/find_photo.dart';
import 'spot_providers.dart';

// Wähler und Pipeline wohnen seit #525 in `core/photo_providers.dart`,
// weil das Feedback sie ebenfalls braucht.
export '../../core/photo_providers.dart';

/// Fundfotos von Buddys anzeigen — und laden? Muster
/// `AmpelBannerEnabledNotifier`: Zustand springt sofort, Speichern läuft
/// nach.
class FindPhotosEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(settingsProvider).findPhotosEnabled;

  void set(bool value) {
    state = value;
    unawaited(ref
        .read(settingsProvider)
        .setFindPhotosEnabled(value)
        .catchError((Object e, StackTrace stackTrace) {
      logError('Fundfotos-Schalter merken', e, stackTrace);
    }));
  }
}

final findPhotosEnabledProvider =
    NotifierProvider<FindPhotosEnabledNotifier, bool>(
        FindPhotosEnabledNotifier.new);

/// Alle Fotos, die ich sehen darf — jüngste zuerst, eigene wie fremde,
/// und nur die, deren Frist läuft.
///
/// **Der Schalter filtert HIER**, nicht erst in der Kachel: Steht er auf
/// aus, kommen fremde Fotos gar nicht in die Liste, und damit fragt
/// keine Kachel je nach ihren Bytes. Das ist die Zusage „aus heißt
/// kein Download". Eigene bleiben — die hat man selbst hochgeladen.
///
/// **Die Frist auch hier**, obwohl die Freundes-Policy sie schon zieht:
/// Eigene Zeilen liefert der Server bis zum Abräumen durch den Bot
/// (bis zu zwei Stunden), und ein Foto, das dem Buddy schon fehlt,
/// soll dem Sender nicht als „noch da" erscheinen.
final findPhotosProvider = FutureProvider<List<FindPhoto>>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  // Mitladen, wenn die Spots neu laden: Ein eigener Eintrag kann ein
  // Foto bekommen haben, eine Freundschaft kann Fotos bringen oder
  // nehmen.
  ref.watch(mySpotsProvider);
  ref.watch(friendSpotsProvider);
  final buddies = ref.watch(findPhotosEnabledProvider);
  final photos = await ref.read(findPhotoRepositoryProvider).fetchVisible();
  return [
    for (final p in photos)
      if (p.isActive && (p.isOwn || buddies)) p,
  ];
});

/// Die schon angesehenen Buddy-Fotos — der Neu-Punkt ist ihr Gegenteil.
///
/// **Gerätelokal, nicht in der Datenbank.** „Gesehen" ist hier eine
/// Frage an dieses Telefon, wie der Merker des Buddy-Fund-Banners; eine
/// Tabelle dafür wäre eine Lesequittung, die niemand bestellt hat.
///
/// Eigene Fotos gelten immer als gesehen ([isNewFindPhoto]) und stehen
/// deshalb gar nicht erst in der Menge.
class SeenFindPhotos extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.read(settingsProvider).seenFindPhotoIds;

  /// Merkt [photo] als gesehen und stutzt die Menge dabei auf die Fotos,
  /// die es noch gibt — sonst wüchse sie mit jedem abgelaufenen Bild.
  void markSeen(FindPhoto photo) {
    if (photo.isOwn || state.contains(photo.id)) return;
    final live = {
      for (final p in ref.read(findPhotosProvider).valueOrNull ??
          const <FindPhoto>[])
        p.id,
    };
    final next = {
      for (final id in state)
        if (live.contains(id)) id,
      photo.id,
    };
    state = next;
    unawaited(ref
        .read(settingsProvider)
        .setSeenFindPhotoIds(next)
        .catchError((Object e, StackTrace s) =>
            logError('Gesehene Fundfotos merken', e, s)));
  }
}

final seenFindPhotosProvider =
    NotifierProvider<SeenFindPhotos, Set<String>>(SeenFindPhotos.new);

/// Trägt [photo] den Neu-Punkt? Nur fremde, noch nicht angesehene.
bool isNewFindPhoto(FindPhoto photo, Set<String> seen) =>
    !photo.isOwn && !seen.contains(photo.id);

/// Die Bytes zu einem Pfad im Bucket — `null`, solange (oder weil) sie
/// nicht da sind.
///
/// `autoDispose`: Was keine Kachel mehr zeigt, darf aus dem Speicher;
/// auf der Platte liegt es weiter (`BoundedFileCache`).
final findPhotoBytesProvider =
    FutureProvider.autoDispose.family<Uint8List?, String>((ref, path) {
  return ref.watch(findPhotoRepositoryProvider).loadBytes(path);
});
