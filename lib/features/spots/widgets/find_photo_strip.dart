// Fundfotos in der Oberfläche (#532): Streifen, Kachel, Vergrößerung,
// Teilen.
//
// **Der Posteingang ist der Reiter „Spots".** Kein eigener Reiter, kein
// Zähler in der Leiste: Ein Foto hängt an einem Fund, und Funde wohnen
// dort. Der Streifen steht als erste Zeile der Liste, im Spot-Blatt
// noch einmal — nur mit den Fotos dieses Spots — über der Fundliste.
// Beide lesen dieselbe Liste (`findPhotosProvider`).
//
// **Die Kachel lädt die VORSCHAU, die Vergrößerung das Bild.** ~12 KB
// gegen ~150 KB; der Streifen wird bei jedem Öffnen des Reiters
// gesehen, das Bild nur auf Tipp. Das ist der Egress-Hebel auf einem
// Free-Plan mit 5 GB im Monat.
//
// **Teilen sagt vorher, was passiert.** Der Dialog nennt, was
// weggenommen wird (Aufnahmedaten), wer es sieht (wer den Fund sieht),
// wie lange (14 Tage) — und dass ein erkennbarer Ort erkennbar bleibt.
// Das Letzte ist keine Warnung vor der App, sondern vor dem Bild: Es
// zeigt, was es zeigt, und das hat der Nutzer entschieden.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors.dart';
import '../../../core/photo_pipeline.dart';
import '../../../core/widgets/photo_overlay.dart';
import '../../../data/find_photo_repository.dart';
import '../../../data/providers.dart';
import '../../../models/find.dart';
import '../../../models/find_photo.dart';
import '../find_photo_providers.dart';
import 'spot_detail_sheet.dart';

const kFindPhotoStripKey = Key('find-photo-strip');
const kFindPhotoGalleryKey = Key('find-photo-gallery');

Key findPhotoTileKey(String id) => ValueKey('find-photo-$id');
Key shareFindPhotoKey(String findId) => ValueKey('share-photo-$findId');
Key findPhotoNewKey(String id) => ValueKey('find-photo-new-$id');
Key findPhotoRingKey(String id) => ValueKey('find-photo-ring-$id');
Key findPhotoKudosKey(String id) => ValueKey('find-photo-kudos-$id');
const kKudosButtonKey = Key('kudos-button');

/// Die Restzeit in Worten — Kachel, Ring und Großansicht sagen dasselbe.
String findPhotoLifeText(int daysLeft) => daysLeft == 0
    ? 'Läuft heute ab'
    : 'Noch $daysLeft ${daysLeft == 1 ? 'Tag' : 'Tage'} sichtbar';

/// Was der Teilen-Dialog sagt — an einer Stelle, damit Test und Blatt
/// dasselbe meinen.
const kFindPhotoShareNote =
    'Das Bild wird verkleinert und ohne Aufnahmedaten hochgeladen — Ort, '
    'Zeit und Gerät bleiben auf deinem Telefon. Sehen können es Buddys, '
    'die diesen Fund sehen dürfen, $kFindPhotoDays Tage lang; dann wird es '
    'gelöscht.\n\nEin erkennbarer Ort bleibt erkennbar: Das Bild zeigt, '
    'was es zeigt.';

/// Der Streifen — alle Fotos oder, mit [spotId], die eines Spots.
///
/// Leer heißt unsichtbar: kein Titel über nichts. Ein Posteingang ohne
/// Post braucht keinen leeren Rahmen, und die Kamera am eigenen Fund
/// erklärt den Weg hinein.
class FindPhotoStrip extends ConsumerWidget {
  const FindPhotoStrip({super.key, this.spotId});

  final String? spotId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final all = ref.watch(findPhotosProvider).valueOrNull ?? const <FindPhoto>[];
    final photos = spotId == null
        ? all
        : [for (final p in all) if (p.spotId == spotId) p];
    if (photos.isEmpty) return const SizedBox.shrink();
    final inSheet = spotId != null;
    return Column(
      key: kFindPhotoStripKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inSheet ? 0 : 16, inSheet ? 8 : 12,
              inSheet ? 0 : 16, 6),
          child: Text(
            inSheet
                ? 'Fundfotos'
                : 'Fundfotos — was in den letzten $kFindPhotoDays Tagen '
                    'geteilt wurde',
            style: theme.textTheme.titleSmall,
          ),
        ),
        SizedBox(
          height: 134,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: inSheet ? 0 : 16),
            children: [
              for (final photo in photos) ...[
                if (photo != photos.first) const SizedBox(width: 8),
                FindPhotoTile(
                  photo: photo,
                  // Im Blatt ist man schon am Spot. Sonst führt der Weg
                  // ins Blatt — es braucht nur eine id, keine Karte.
                  onOpenSpot: inSheet
                      ? null
                      : (id) => showSpotDetailSheet(context, id),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Eine Kachel: Vorschau, Art, Absender — dazu der Ring, der die
/// Restzeit zeigt, und bei fremden, noch nicht angesehenen Fotos der
/// Neu-Punkt. Streifen (Reiter „Spots", Spot-Blatt) und Galerie (Reiter
/// „Buddys") benutzen dieselbe.
class FindPhotoTile extends ConsumerWidget {
  const FindPhotoTile({super.key, required this.photo, required this.onOpenSpot});

  final FindPhoto photo;
  final void Function(String spotId)? onOpenSpot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bytes = ref.watch(findPhotoBytesProvider(photo.thumbPath)).valueOrNull;
    final isNew = isNewFindPhoto(photo, ref.watch(seenFindPhotosProvider));
    final who = photo.isOwn ? 'dein Foto' : 'von ${photo.username ?? 'Buddy'}';
    return SizedBox(
      key: findPhotoTileKey(photo.id),
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              // Gesehen ist, was geöffnet wurde — nicht, was im Bild
              // vorbeigescrollt ist.
              ref.read(seenFindPhotosProvider.notifier).markSeen(photo);
              showFindPhoto(context, photo, onOpenSpot: onOpenSpot);
            },
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: bytes == null
                        ? ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(Icons.image_outlined,
                                color: theme.hintColor))
                        : Image.memory(
                            bytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            semanticLabel: '${photo.species ?? 'Fund'}, '
                                'Fundfoto, $who${isNew ? ', neu' : ''}',
                          ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: FindPhotoLifeRing(photo: photo),
                ),
                // Die Zahl, keine Namen — die stehen in der Großansicht.
                if (photo.kudosCount > 0)
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: Container(
                      key: findPhotoKudosKey(photo.id),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.surface.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('🍄 ${photo.kudosCount}',
                          semanticsLabel:
                              '${photo.kudosCount} ${photo.kudosCount == 1 ? 'Pilz' : 'Pilze'}',
                          style: theme.textTheme.labelSmall),
                    ),
                  ),
                if (isNew)
                  Positioned(
                    top: 5,
                    left: 5,
                    child: Container(
                      key: findPhotoNewKey(photo.id),
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(photo.species ?? 'Fund',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall),
          Text(who,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor)),
        ],
      ),
    );
  }
}

/// Ein Ring, der sich über die 14 Tage leert — die Frist als Form statt
/// als Zahl, damit man in der Galerie sieht, was bald geht. Die Zahl
/// steht im Tooltip und in der Großansicht.
///
/// Gerechnet über die volle Restdauer, nicht über [FindPhoto.daysLeft]:
/// Ganze Tage springen, und ein frisches Foto stünde dann schon bei
/// 13/14.
class FindPhotoLifeRing extends StatelessWidget {
  const FindPhotoLifeRing({super.key, required this.photo, this.size = 18});

  final FindPhoto photo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now().toUtc();
    const total = Duration(days: kFindPhotoDays);
    final left = photo.expiresAt.difference(now);
    final share =
        (left.inSeconds / total.inSeconds).clamp(0.0, 1.0).toDouble();
    return Tooltip(
      message: findPhotoLifeText(photo.daysLeft(now)),
      child: Container(
        key: findPhotoRingKey(photo.id),
        width: size,
        height: size,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.85),
          shape: BoxShape.circle,
        ),
        child: CircularProgressIndicator(
          value: share,
          strokeWidth: 2.5,
          backgroundColor: theme.colorScheme.outlineVariant,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Die Galerie im Reiter „Buddys" (#532 Stufe 3): alle laufenden Fotos,
/// eigene wie fremde, jüngste zuerst.
///
/// **Keine eigene Abfrage** — dieselbe Liste wie der Streifen im Reiter
/// „Spots" (`findPhotosProvider`). Leer heißt unsichtbar, wie dort.
class FindPhotoGallery extends ConsumerWidget {
  const FindPhotoGallery({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final photos =
        ref.watch(findPhotosProvider).valueOrNull ?? const <FindPhoto>[];
    if (photos.isEmpty) return const SizedBox.shrink();
    final seen = ref.watch(seenFindPhotosProvider);
    final fresh = photos.where((p) => isNewFindPhoto(p, seen)).length;
    return Column(
      key: kFindPhotoGalleryKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(fresh == 0 ? 'Fundfotos' : 'Fundfotos · $fresh neu',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(
          'Was du und deine Buddys in den letzten $kFindPhotoDays Tagen '
          'geteilt habt. Der Ring zeigt, wie lange ein Foto noch bleibt.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final photo in photos)
              FindPhotoTile(
                photo: photo,
                onOpenSpot: (id) => showSpotDetailSheet(context, id),
              ),
          ],
        ),
        // Der Abstand gehört der Galerie: Ohne Fotos fällt er mit weg.
        const SizedBox(height: 20),
      ],
    );
  }
}

/// Öffnet [photo] groß — erst die Vorschau, das Bild ersetzt sie.
Future<void> showFindPhoto(
  BuildContext context,
  FindPhoto photo, {
  void Function(String spotId)? onOpenSpot,
}) {
  return showPhotoOverlay(
      context, (_) => _FindPhotoView(photo: photo, onOpenSpot: onOpenSpot));
}

class _FindPhotoView extends ConsumerWidget {
  const _FindPhotoView({required this.photo, required this.onOpenSpot});

  final FindPhoto photo;
  final void Function(String spotId)? onOpenSpot;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Foto zurücknehmen?'),
        content: const Text(
            'Deine Buddys sehen es dann nicht mehr. Auf deinem Telefon '
            'bleibt das Original.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Zurücknehmen')),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(findPhotoRepositoryProvider).delete(photo);
      ref.invalidate(findPhotosProvider);
      navigator.pop();
    } catch (e, s) {
      logError('Fundfoto zurücknehmen', e, s);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  /// Einen Pilz geben oder zurücknehmen — und danach neu lesen statt
  /// den Zähler vorzuziehen (read-after-write, wie überall).
  Future<void> _toggleKudos(
      BuildContext context, WidgetRef ref, bool given) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(findPhotoRepositoryProvider);
    try {
      if (given) {
        await repo.takeBackKudos(photo.id);
      } else {
        await repo.giveKudos(photo.id);
      }
    } catch (e, s) {
      logError('Kudos', e, s);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
      return;
    }
    ref.invalidate(findPhotosProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final myUid = ref.watch(currentUserIdProvider);
    // Die Kudos kommen aus der LISTE, nicht aus dem übergebenen Foto —
    // sonst bliebe der Zähler nach dem Tipp stehen, bis man schließt.
    final live = (ref.watch(findPhotosProvider).valueOrNull ??
            const <FindPhoto>[])
        .where((p) => p.id == photo.id)
        .firstOrNull ??
        photo;
    final kudos =
        kudosLine(live.kudosFrom, myUid, ref.watch(buddyNamesProvider));
    final given = myUid != null && live.hasKudosFrom(myUid);
    // **Sofort die Vorschau, die der Streifen längst hat** — und das
    // volle Bild, sobald es da ist. Dieselbe Linie wie bei den
    // Artbildern: Der Tipp zeigt IMMER etwas, auch ohne Empfang.
    final thumb = ref.watch(findPhotoBytesProvider(photo.thumbPath)).valueOrNull;
    final full = ref.watch(findPhotoBytesProvider(photo.fullPath)).valueOrNull;
    final bytes = full ?? thumb;
    final hint = theme.textTheme.bodySmall?.copyWith(color: theme.hintColor);
    final who = photo.isOwn ? 'dein Foto' : 'von ${photo.username ?? 'Buddy'}';
    final dateFormat = DateFormat('d. MMMM yyyy', 'de');
    final now = DateTime.now();
    final days = photo.daysLeft(now);
    return PhotoOverlay(
      image: bytes == null ? null : MemoryImage(bytes),
      semanticLabel: '${photo.species ?? 'Fund'}, Fundfoto, $who',
      caption: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(photo.species ?? 'Fund', style: theme.textTheme.titleMedium),
          Text([
            who,
            if (photo.spotName != null) photo.spotName!,
            if (photo.foundOn != null)
              'Fund vom ${dateFormat.format(photo.foundOn!)}',
          ].join(' · '), style: hint),
          Row(children: [
            FindPhotoLifeRing(photo: photo, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                  days == 0
                      ? '${findPhotoLifeText(days)}.'
                      : '${findPhotoLifeText(days)}, dann wird es gelöscht.',
                  style: hint),
            ),
          ]),
          if (kudos != null) Text(kudos, style: hint),
        ],
      ),
      actions: [
        // Ein Pilz je Buddy — kein Zähler zum Hochtippen, und nicht fürs
        // eigene Foto (die Policy lehnt es ohnehin ab).
        if (!photo.isOwn)
          TextButton.icon(
            key: kKudosButtonKey,
            icon: const Text('🍄', style: TextStyle(fontSize: 18)),
            label: Text(given ? 'Pilz zurücknehmen' : 'Pilz geben'),
            onPressed: () => _toggleKudos(context, ref, given),
          ),
        if (photo.spotId != null && onOpenSpot != null)
          TextButton.icon(
            icon: const Icon(Icons.place_outlined),
            label: const Text('Zum Spot'),
            onPressed: () {
              final id = photo.spotId!;
              Navigator.of(context).pop();
              onOpenSpot!(id);
            },
          ),
        if (photo.isOwn)
          TextButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Zurücknehmen'),
            onPressed: () => _delete(context, ref),
          ),
      ],
    );
  }
}

/// Ein Foto zu [find] teilen: fragen, holen, entkernen, hochladen.
///
/// **Offline scheitert das sichtbar**, wie Korrigieren und Löschen —
/// kein dritter Weg in den Ausgangskorb (#532, entschieden im Issue).
/// Ein Foto ist ein Extra-Schritt nach dem Eintragen, und ein
/// Binärauftrag im Korb wäre eine eigene Idempotenz-Geschichte.
Future<void> shareFindPhoto(
    BuildContext context, WidgetRef ref, Find find) async {
  final source = await showDialog<PhotoSource>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Foto teilen'),
      content: const Text(kFindPhotoShareNote),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen')),
        TextButton.icon(
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Galerie'),
          onPressed: () => Navigator.pop(ctx, PhotoSource.gallery),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Kamera'),
          onPressed: () => Navigator.pop(ctx, PhotoSource.camera),
        ),
      ],
    ),
  );
  if (source == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await ref.read(photoPickerProvider)(source);
    if (bytes == null) return; // abgebrochen — nichts zu melden
    messenger.showSnackBar(const SnackBar(
        content: Text('Foto wird vorbereitet …'),
        duration: Duration(seconds: 30)));
    final prepared = await ref.read(photoPreparerProvider)(bytes);
    await uploadFindPhoto(ref, messenger, findId: find.id, photo: prepared);
  } catch (e, s) {
    logError('Fundfoto teilen', e, s);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

const kFindPhotoSharedMessage =
    'Foto geteilt — $kFindPhotoDays Tage für deine Buddys sichtbar.';

/// Ein schon entkerntes Foto an [findId] hängen und quittieren — der
/// gemeinsame Schluss von [shareFindPhoto] und dem Blatt „Fund
/// eintragen". Wirft weiter; was dann gesagt wird, weiß der Aufrufer.
Future<void> uploadFindPhoto(
  WidgetRef ref,
  ScaffoldMessengerState messenger, {
  required String findId,
  required PreparedPhoto photo,
}) async {
  await ref
      .read(findPhotoRepositoryProvider)
      .share(findId: findId, photo: photo);
  ref.invalidate(findPhotosProvider);
  messenger
    ..clearSnackBars()
    ..showSnackBar(const SnackBar(content: Text(kFindPhotoSharedMessage)));
}

/// Nach „Fund eintragen" mit angehängtem Foto (#532 Stufe 2).
///
/// **Der Fund ist das Original, das Foto die Beigabe.** Scheitert der
/// Upload, steht der Fund trotzdem — die Meldung sagt deshalb beides,
/// und der Weg zum Nachreichen ist die Kamera am Fund. Liegt der Fund im
/// Korb ([ids] leer), gibt es noch keine id, an die das Foto könnte;
/// einen dritten Korb-Weg für Bilder gibt es bewusst nicht.
Future<void> shareFreshFindPhoto(
  WidgetRef ref,
  ScaffoldMessengerState messenger, {
  required List<String> ids,
  required PreparedPhoto photo,
}) async {
  if (ids.isEmpty) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text(kFindPhotoQueuedMessage)));
    return;
  }
  try {
    await uploadFindPhoto(ref, messenger, findId: ids.first, photo: photo);
  } catch (e, s) {
    logError('Fundfoto beim Eintragen teilen', e, s);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
          content: Text('Fund eingetragen, das Foto nicht: '
              '${friendlyError(e)} Du kannst es am Fund nachreichen.')));
  }
}

const kFindPhotoQueuedMessage =
    'Fund wartet auf Verbindung — das Foto lässt sich am Fund '
    'nachreichen, sobald er übertragen ist.';
