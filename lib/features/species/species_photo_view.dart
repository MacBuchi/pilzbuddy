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
//
// **Drei Wege hinaus**, wie bei den Blättern (siehe
// `core/widgets/sheet_close_button.dart`): das x, die Zurück-Geste und
// das Wischen. Hier kommt der Tipp irgendwohin als vierter dazu — ein
// Bild ohne Bedienelemente lädt dazu ein, und wer es versucht, soll
// nicht ins Leere tippen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/species_photos.dart';
import '../../core/widgets/sheet_close_button.dart';
import '../../data/providers.dart';

/// Die Fläche, die das Wischen entgegennimmt.
///
/// Sie liegt bewusst über dem GANZEN Bildschirm und nicht über dem Bild:
/// Ein Bild, das noch nicht entschlüsselt ist, hat die Größe null, und
/// dann wäre die einzige Fläche, auf der man wischen kann, ein Punkt in
/// der Bildschirmmitte. Im Test war das zu sehen, sobald er allein lief
/// — mit warmem Bildspeicher ging er durch, kalt nicht.
const kPhotoViewKey = Key('species-photo-view');

/// Ab dieser Strecke gilt ein Zug nach unten oder oben als „weg damit".
///
/// **Gemessen wird der Weg, nicht das Tempo.** Ein Geschwindigkeitsmaß
/// bräuchte eine eigene Verfolgung der Zeigerspur, und es entschiede
/// dasselbe: Ein Wisch legt diese Strecke ohnehin zurück, ein Verrutschen
/// beim Lesen nicht.
const kPhotoDismissDistance = 96.0;

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
  final _zoom = TransformationController();

  /// Wie weit der Finger das Bild seit dem Aufsetzen mitgenommen hat.
  double _dragY = 0;
  double _startY = 0;
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    // **Erst beim Öffnen, nie vorher.** „Beobachten ist laden" gilt hier
    // wie beim Höhengitter: Das Lupensymbol an der Kachel darf nichts
    // anstoßen, nur der Tipp darf es.
    _loadSharp();
    _zoom.addListener(_onZoom);
  }

  @override
  void dispose() {
    _zoom
      ..removeListener(_onZoom)
      ..dispose();
    super.dispose();
  }

  void _onZoom() => setState(() {});

  /// Ist hineingezoomt, gehört das Ziehen dem Bild.
  ///
  /// Andernfalls hätte man den Ausschnitt gewählt und verlöre ihn beim
  /// ersten Versuch, ihn zu verschieben.
  bool get _zoomedIn => _zoom.value.getMaxScaleOnAxis() > 1.01;

  Future<void> _loadSharp() async {
    final bytes =
        await ref.read(speciesPhotoRepositoryProvider).load(widget.photo.asset);
    if (!mounted || bytes == null) return;
    setState(() => _sharp = MemoryImage(bytes));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // **Überlagert mit Rand, nicht formatfüllend** (Betreiber,
    // 2026-09-22). Der Rand ist kein Schmuck: Er IST der vierte Ausgang.
    // Ein Tipp daneben trifft den Hintergrund des Dialogs, und der
    // schließt von selbst — ohne dass die Ansicht dafür eine Zeile Code
    // bekommt. Formatfüllend gab es dieses Außen nicht.
    //
    // Der Preis ist ehrlich: Das Bild wird um die Ränder kleiner. Bei
    // 16 px seitlich sind das rund 8 % der Breite, und dafür sieht man,
    // dass etwas DARUNTER liegt, zu dem man zurückkommt.
    return Transform.translate(
      // Die ganze Karte folgt dem Finger, nicht nur das Bild darin.
      offset: Offset(0, _dragY),
      child: Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
        clipBehavior: Clip.antiAlias,
        child: Listener(
          key: kPhotoViewKey,
          // **`opaque`, nicht die Vorgabe.** `Listener` und
          // `GestureDetector` reichen die Treffprüfung sonst an ihr Kind
          // weiter — und das Kind ist das Bild, das erst nach dem
          // Entschlüsseln eine Größe hat und bei einem Ladefehler nie
          // eine bekommt. Auf der Fläche daneben blieben Tipp und Wisch
          // dann folgenlos; genau so war es in 1.179.0.
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            _pointers++;
            _startY = e.position.dy;
          },
          onPointerMove: (e) {
            if (_zoomedIn || _pointers != 1) return;
            setState(() => _dragY = e.position.dy - _startY);
          },
          onPointerUp: (e) {
            _pointers = 0;
            if (_dragY.abs() >= kPhotoDismissDistance) {
              Navigator.of(context).pop();
              return;
            }
            setState(() => _dragY = 0);
          },
          onPointerCancel: (_) {
            _pointers = 0;
            setState(() => _dragY = 0);
          },
          child: GestureDetector(
            // Irgendwohin auf die Karte tippen schließt — wie beim
            // Kontextmenü, und wie ein Tipp daneben.
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      // **Das Quadrat ist reserviert, bevor das Bild da
                      // ist.** Alle Artbilder sind quadratisch
                      // zugeschnitten (`tool/species_photos.py`); ohne
                      // die Reservierung wäre die Karte bis zum
                      // Entschlüsseln nur so hoch wie ihre Unterschrift
                      // und spränge danach auf.
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: InteractiveViewer(
                          transformationController: _zoom,
                          maxScale: 4,
                          child: Image(
                            // Solange das große nicht da ist, steht das
                            // mitgelieferte. Es ist weich, aber es ist
                            // da.
                            image: _sharp ?? AssetImage(widget.photo.asset),
                            fit: BoxFit.contain,
                            semanticLabel: '${widget.species}, Foto',
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.species,
                              style: theme.textTheme.titleMedium),
                          Text(photoCredit(widget.photo),
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.hintColor)),
                          const SizedBox(height: 6),
                          // **Derselbe Satz wie unter dem Streifen.** Ein
                          // groß gezeigtes Bild sieht mehr nach Beweis
                          // aus als eine Kachel; der Vorbehalt darf hier
                          // nicht fehlen.
                          Text(kPhotoDisclaimer,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.hintColor)),
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: SheetCloseButton(
                    tooltip: 'Schließen',
                    // Auf dem Bild, nicht auf der Fläche darunter: Ohne
                    // eigenen Grund verschwände das Zeichen auf einem
                    // hellen Foto.
                    background: theme.colorScheme.surface.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
