// „Bild anhängen" für Dialoge, die eine Meldung verschicken (#525) —
// und seit #532 Stufe 2 für das Blatt „Fund eintragen", dort mit
// eigener Beschriftung ([label], [attachedNote]).
//
// Holen und entkernen passieren HIER, beim Anhängen, nicht erst beim
// Senden: Ein Bild, das die Pipeline nicht lesen kann, soll sofort
// sagen, warum — und die Vorschau zeigt das Ergebnis, nicht das
// Original. Was der Dialog zurückgibt, ist ein [PreparedPhoto]; einen
// Weg mit rohen Bytes gibt es nicht.
import 'package:flutter/material.dart';

import '../errors.dart';
import '../photo_pipeline.dart';
import '../photo_providers.dart';

const kAttachPhotoKey = Key('attach-photo');
const kAttachPhotoCameraKey = Key('attach-photo-camera');
const kRemovePhotoKey = Key('remove-photo');

class PhotoAttachment extends StatefulWidget {
  const PhotoAttachment({
    super.key,
    required this.pick,
    required this.prepare,
    required this.photo,
    required this.onChanged,
    this.label = 'Bild anhängen',
    this.attachedNote = kFeedbackPhotoAttachedNote,
    this.pickMany,
    this.room = 1,
    this.onPickedMany,
  });

  final PhotoPicker pick;

  /// Mehrere auf einmal aus der Galerie (#585) — nur im freien Feld einer
  /// [PhotoAttachmentList]. `null` heißt: ein Bild je Tipp, wie vorher.
  final MultiPhotoPicker? pickMany;

  /// Wie viele Bilder noch Platz haben — die Obergrenze für [pickMany].
  final int room;

  /// Bekommt ALLE vorbereiteten Bilder eines Mehrfach-Griffs auf einmal.
  final ValueChanged<List<PreparedPhoto>>? onPickedMany;
  final PhotoPreparer prepare;
  final PreparedPhoto? photo;
  final ValueChanged<PreparedPhoto?> onChanged;

  /// Die Beschriftung des Knopfs.
  final String label;

  /// Der Satz neben der Vorschau: was mit dem Bild passiert — und was
  /// nicht. Er hängt am Zweck, deshalb gibt ihn der Aufrufer.
  final String attachedNote;

  @override
  State<PhotoAttachment> createState() => _PhotoAttachmentState();
}

class _PhotoAttachmentState extends State<PhotoAttachment> {
  bool _busy = false;

  /// Beim Mehrfach-Griff: wie weit die Vorbereitung ist („2/3").
  String? _progress;

  /// Galerie mit Mehrfachauswahl (#585). Drei Dinge:
  /// - **Nie mehr als [PhotoAttachment.room]** — im Browser ist die
  ///   Obergrenze nur eine Bitte. Übernommen werden die ersten, und die
  ///   App SAGT, dass es nicht alle sind; still kappen hieße, Bilder
  ///   verschwinden zu lassen, von denen der Nutzer glaubt, er habe sie
  ///   angehängt (dieselbe Falle wie der Art-Hinweis ohne Text, #586).
  /// - **Ein unlesbares Bild nimmt die anderen nicht mit.** Angehängt wird,
  ///   was die Pipeline vorbereiten konnte; gemeldet, was nicht ging.
  /// - Jedes Bild geht einzeln durch [PhotoAttachment.prepare], also
  ///   durch dieselbe Entkernung wie bisher.
  Future<void> _pickMany() async {
    final messenger = ScaffoldMessenger.of(context);
    final room = widget.room;
    setState(() => _busy = true);
    try {
      final all = await widget.pickMany!(room);
      if (all.isEmpty) return; // abgebrochen
      final taken = all.take(room).toList();
      final prepared = <PreparedPhoto>[];
      Object? firstError;
      var failed = 0;
      for (final (i, bytes) in taken.indexed) {
        if (mounted && taken.length > 1) {
          setState(() => _progress = '${i + 1}/${taken.length}');
        }
        try {
          prepared.add(await widget.prepare(bytes));
        } catch (e, s) {
          logError('Bild anhängen', e, s);
          firstError ??= e;
          failed++;
        }
      }
      if (mounted && prepared.isNotEmpty) widget.onPickedMany!(prepared);
      final notes = [
        if (all.length > room)
          'Nur ${room == 1 ? 'das erste Bild' : 'die ersten $room Bilder'} '
              'übernommen — mehr gehen nicht.',
        if (failed > 0)
          '${failed == 1 ? 'Ein Bild' : '$failed Bilder'} ließ sich nicht '
              'anhängen: ${friendlyError(firstError!)}',
      ];
      if (notes.isNotEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(notes.join(' '))));
      }
    } catch (e, s) {
      logError('Bilder anhängen', e, s);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _pick(PhotoSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bytes = await widget.pick(source);
      if (bytes == null) return; // abgebrochen
      final prepared = await widget.prepare(bytes);
      if (mounted) widget.onChanged(prepared);
    } catch (e, s) {
      logError('Bild anhängen', e, s);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photo = widget.photo;
    if (_busy) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text(_progress == null
              ? 'Bild wird vorbereitet …'
              : 'Bilder werden vorbereitet … $_progress'),
        ]),
      );
    }
    if (photo == null) {
      return Row(children: [
        // Nachgeben darf nur die Beschriftung: Im Dialog auf 360 dp
        // bleiben neben der Kamera gut 180 px (#596, im Test 65 px
        // Überlauf).
        Flexible(
          child: OutlinedButton.icon(
            key: kAttachPhotoKey,
            icon: const Icon(Icons.image_outlined, size: 18),
            label: Text(widget.label, overflow: TextOverflow.ellipsis),
            onPressed: widget.pickMany != null && widget.onPickedMany != null
                ? _pickMany
                : () => _pick(PhotoSource.gallery),
          ),
        ),
        IconButton(
          key: kAttachPhotoCameraKey,
          tooltip: 'Foto aufnehmen',
          icon: const Icon(Icons.photo_camera_outlined),
          onPressed: () => _pick(PhotoSource.camera),
        ),
      ]);
    }
    return Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(photo.thumb,
            width: 56, height: 56, fit: BoxFit.cover,
            semanticLabel: 'Angehängtes Bild'),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(widget.attachedNote, style: theme.textTheme.bodySmall),
      ),
      IconButton(
        key: kRemovePhotoKey,
        tooltip: 'Bild entfernen',
        icon: const Icon(Icons.close),
        onPressed: () => widget.onChanged(null),
      ),
    ]);
  }
}

/// Mehrere Bilder, bis [max] (#569) — je Bild ein [PhotoAttachment],
/// darunter ein freies Feld, solange Platz ist. Dasselbe Muster wie bei
/// den Fotos für iNaturalist.
///
/// Der Satz zum Anhang steht nur am ERSTEN Bild: dreimal derselbe Satz
/// über „nicht öffentlich" liest niemand dreimal, er schiebt nur das
/// Formular aus dem Bild.
class PhotoAttachmentList extends StatelessWidget {
  const PhotoAttachmentList({
    super.key,
    required this.pick,
    required this.prepare,
    required this.photos,
    required this.onChanged,
    required this.max,
    this.label = 'Bild anhängen',
    this.moreLabel = 'Weiteres Bild',
    this.attachedNote = kFeedbackPhotoAttachedNote,
    this.pickMany,
  });

  final PhotoPicker pick;

  /// Galerie mit Mehrfachauswahl bis zum freien Platz (#585) — `null`
  /// hält es bei einem Bild je Tipp.
  final MultiPhotoPicker? pickMany;
  final PhotoPreparer prepare;
  final List<PreparedPhoto> photos;
  final ValueChanged<List<PreparedPhoto>> onChanged;
  final int max;
  final String label;
  final String moreLabel;
  final String attachedNote;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < photos.length; i++)
          PhotoAttachment(
            key: ValueKey('photo-attachment-$i'),
            pick: pick,
            prepare: prepare,
            photo: photos[i],
            label: label,
            attachedNote: i == 0 ? attachedNote : '',
            onChanged: (photo) => onChanged([
              for (var j = 0; j < photos.length; j++)
                if (j != i) photos[j] else ?photo,
            ]),
          ),
        if (photos.length < max)
          PhotoAttachment(
            key: ValueKey('photo-attachment-${photos.length}'),
            pick: pick,
            prepare: prepare,
            photo: null,
            label: photos.isEmpty ? label : moreLabel,
            attachedNote: attachedNote,
            pickMany: pickMany,
            room: max - photos.length,
            onPickedMany: (picked) => onChanged([...photos, ...picked]),
            onChanged: (photo) {
              if (photo != null) onChanged([...photos, photo]);
            },
          ),
      ],
    );
  }
}

/// Die Frist als Text — die Zahl wohnt bei `FeedbackRepository`, hier
/// steht sie nur, damit das Widget keine Datenschicht importiert.
const kFeedbackPhotoDaysText = '90';

/// Was der Anhang am Feedback NICHT tut — das Gegenteil des Textes
/// darüber, und deshalb nicht in demselben Satz.
const kFeedbackPhotoAttachedNote =
    'Ohne Aufnahmedaten, nicht öffentlich — nur der Entwickler sieht '
    'die Bilder, $kFeedbackPhotoDaysText Tage lang.';
