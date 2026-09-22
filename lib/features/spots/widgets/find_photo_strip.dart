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
import '../../../core/widgets/photo_overlay.dart';
import '../../../data/find_photo_repository.dart';
import '../../../data/providers.dart';
import '../../../models/find.dart';
import '../../../models/find_photo.dart';
import '../find_photo_providers.dart';
import 'spot_detail_sheet.dart';

const kFindPhotoStripKey = Key('find-photo-strip');

Key findPhotoTileKey(String id) => ValueKey('find-photo-$id');
Key shareFindPhotoKey(String findId) => ValueKey('share-photo-$findId');

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
                _PhotoTile(
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

class _PhotoTile extends ConsumerWidget {
  const _PhotoTile({required this.photo, required this.onOpenSpot});

  final FindPhoto photo;
  final void Function(String spotId)? onOpenSpot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bytes = ref.watch(findPhotoBytesProvider(photo.thumbPath)).valueOrNull;
    final who = photo.isOwn ? 'dein Foto' : 'von ${photo.username ?? 'Buddy'}';
    return SizedBox(
      key: findPhotoTileKey(photo.id),
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => showFindPhoto(context, photo, onOpenSpot: onOpenSpot),
            child: ClipRRect(
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
                        semanticLabel:
                            '${photo.species ?? 'Fund'}, Fundfoto, $who',
                      ),
              ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
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
          Text(
              days == 0
                  ? 'Läuft heute ab.'
                  : 'Noch $days ${days == 1 ? 'Tag' : 'Tage'} sichtbar, '
                      'dann wird es gelöscht.',
              style: hint),
        ],
      ),
      actions: [
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
    await ref
        .read(findPhotoRepositoryProvider)
        .share(findId: find.id, photo: prepared);
    ref.invalidate(findPhotosProvider);
    messenger
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
          content: Text('Foto geteilt — $kFindPhotoDays Tage für deine '
              'Buddys sichtbar.')));
  } catch (e, s) {
    logError('Fundfoto teilen', e, s);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}
