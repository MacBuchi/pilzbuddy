// Ein Bild überlagert mit Rand ansehen — für Artbilder (#537) wie für
// Fundfotos (#532).
//
// **Überlagert mit Rand, nicht formatfüllend** (Betreiber, 2026-09-22).
// Der Rand ist kein Schmuck: Er IST der vierte Ausgang. Ein Tipp daneben
// trifft den Hintergrund des Dialogs, und der schließt von selbst —
// ohne dass die Ansicht dafür eine Zeile Code bekommt. Formatfüllend
// gab es dieses Außen nicht.
//
// Der Preis ist ehrlich: Das Bild wird um die Ränder kleiner. Bei 16 px
// seitlich sind das rund 8 % der Breite, und dafür sieht man, dass etwas
// DARUNTER liegt, zu dem man zurückkommt.
//
// **Drei Wege hinaus**, wie bei den Blättern (siehe
// `sheet_close_button.dart`): das x, die Zurück-Geste und das Wischen.
// Hier kommt der Tipp irgendwohin als vierter dazu — ein Bild ohne
// Bedienelemente lädt dazu ein, und wer es versucht, soll nicht ins
// Leere tippen. Knöpfe in [PhotoOverlay.actions] gewinnen gegen den
// Tipp, weil das innere Ziel in der Gestenarena zuerst steht.
import 'package:flutter/material.dart';

import 'sheet_close_button.dart';

/// Die Fläche, die das Wischen entgegennimmt.
///
/// Sie liegt bewusst über der GANZEN Karte und nicht über dem Bild: Ein
/// Bild, das noch nicht entschlüsselt ist, hat die Größe null, und dann
/// wäre die einzige Fläche, auf der man wischen kann, ein Punkt in der
/// Bildschirmmitte. Im Test war das zu sehen, sobald er allein lief —
/// mit warmem Bildspeicher ging er durch, kalt nicht.
const kPhotoViewKey = Key('species-photo-view');

/// Ab dieser Strecke gilt ein Zug nach unten oder oben als „weg damit".
///
/// **Gemessen wird der Weg, nicht das Tempo.** Ein Geschwindigkeitsmaß
/// bräuchte eine eigene Verfolgung der Zeigerspur, und es entschiede
/// dasselbe: Ein Wisch legt diese Strecke ohnehin zurück, ein Verrutschen
/// beim Lesen nicht.
const kPhotoDismissDistance = 96.0;

/// Öffnet [child] — ein [PhotoOverlay] — als Dialog über dunklem Grund.
Future<void> showPhotoOverlay(BuildContext context, WidgetBuilder builder) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: builder,
  );
}

class PhotoOverlay extends StatefulWidget {
  const PhotoOverlay({
    super.key,
    required this.image,
    required this.semanticLabel,
    required this.caption,
    this.aspectRatio,
    this.actions = const [],
  });

  /// Was gezeigt wird — darf sich ändern, wenn das scharfe Bild kommt.
  /// `null`, solange noch gar nichts da ist: dann dreht sich an seiner
  /// Stelle ein Kreis, und die Karte steht trotzdem schon.
  final ImageProvider? image;
  final String semanticLabel;

  /// Was unter dem Bild steht: Name, Nennung, Vorbehalt.
  final Widget caption;

  /// Reserviert die Fläche, bevor das Bild entschlüsselt ist. Ohne das
  /// wäre die Karte bis dahin nur so hoch wie ihre Unterschrift und
  /// spränge danach auf. `null`, wenn das Seitenverhältnis erst das Bild
  /// verrät.
  final double? aspectRatio;

  /// Knöpfe unter der Unterschrift.
  final List<Widget> actions;

  @override
  State<PhotoOverlay> createState() => _PhotoOverlayState();
}

class _PhotoOverlayState extends State<PhotoOverlay> {
  final _zoom = TransformationController();

  /// Wie weit der Finger das Bild seit dem Aufsetzen mitgenommen hat.
  double _dragY = 0;
  double _startY = 0;
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = widget.image;
    final image = provider == null
        ? const SizedBox(
            height: 200, child: Center(child: CircularProgressIndicator()))
        : InteractiveViewer(
            transformationController: _zoom,
            maxScale: 4,
            child: Image(
              image: provider,
              fit: BoxFit.contain,
              semanticLabel: widget.semanticLabel,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          );
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
                      child: widget.aspectRatio == null
                          ? image
                          : AspectRatio(
                              aspectRatio: widget.aspectRatio!,
                              child: image),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          widget.caption,
                          if (widget.actions.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Wrap(
                                  spacing: 8, children: widget.actions),
                            ),
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
                    background:
                        theme.colorScheme.surface.withValues(alpha: 0.8),
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
