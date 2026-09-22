// Ein Artbild formatfüllend ansehen (#537).
//
// **Der Tipp vergrößert IMMER, auch ohne Empfang.** Gezeigt wird sofort
// das mitgelieferte 400er; ist eine Verbindung da, ersetzt das große es,
// sobald es angekommen ist. Andersherum — erst laden, dann zeigen —
// wäre die Lupe ein Versprechen, das im Wald nicht hält, und genau dort
// wird die App benutzt.
//
// **Die Nennung reist mit.** Bei CC-BY ist sie die Bedingung, unter der
// wir das Bild überhaupt zeigen dürfen, und eine Ansicht, die das Bild
// größer macht als überall sonst, ist nicht der Ort, sie wegzulassen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/species_photos.dart';
import '../../data/providers.dart';

/// Öffnet [photo] formatfüllend.
Future<void> showSpeciesPhoto(
  BuildContext context, {
  required String species,
  required SpeciesPhoto photo,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => _SpeciesPhotoView(species: species, photo: photo),
  );
}

class _SpeciesPhotoView extends ConsumerStatefulWidget {
  const _SpeciesPhotoView({required this.species, required this.photo});

  final String species;
  final SpeciesPhoto photo;

  @override
  ConsumerState<_SpeciesPhotoView> createState() => _SpeciesPhotoViewState();
}

class _SpeciesPhotoViewState extends ConsumerState<_SpeciesPhotoView> {
  ImageProvider? _sharp;

  @override
  void initState() {
    super.initState();
    // **Erst beim Öffnen, nie vorher.** „Beobachten ist laden" gilt hier
    // wie beim Höhengitter: Das Lupensymbol an der Kachel darf nichts
    // anstoßen, nur der Tipp darf es.
    _loadSharp();
  }

  Future<void> _loadSharp() async {
    final bytes =
        await ref.read(speciesPhotoRepositoryProvider).load(widget.photo.asset);
    if (!mounted || bytes == null) return;
    setState(() => _sharp = MemoryImage(bytes));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              // Irgendwohin tippen schließt — wie beim Kontextmenü.
              onTap: () => Navigator.of(context).pop(),
              child: Center(
                child: InteractiveViewer(
                  maxScale: 4,
                  child: Image(
                    // Solange das große nicht da ist, steht das
                    // mitgelieferte. Es ist weich, aber es ist da.
                    image: _sharp ?? AssetImage(widget.photo.asset),
                    fit: BoxFit.contain,
                    semanticLabel: '${widget.species}, Foto',
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.species,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: Colors.white)),
                Text(photoCredit(widget.photo),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white70)),
                const SizedBox(height: 8),
                // **Derselbe Satz wie unter dem Streifen.** Ein Bild
                // formatfüllend sieht mehr nach Beweis aus als eine
                // Kachel; der Vorbehalt darf hier nicht fehlen.
                Text(kPhotoDisclaimer,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.white70)),
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Schließen',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
