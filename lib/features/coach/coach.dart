// Die Hinweis-Maschine (#596): zeigt am ECHTEN Bildschirm, wie etwas
// geht — mit Aussparung, Ring, Sprechblase und, bei Gesten, einem
// animierten Finger.
//
// **Warum eine Maschine für die ganze App und nicht die alte Kartentour
// weiter.** Die Tour (#350) kannte nur Löcher auf der Karte, vergrößert
// und rund — gebaut für einzelne runde Knöpfe. Seit die Werkzeuge in
// EINER Leiste sitzen (1.133.0), schnitt sie Stücke aus der Leiste und
// ragte in den Nachbarknopf (Screenshots aus der PWA, 2026-09-24). Und
// sie konnte nur zeigen, WO ein Knopf ist, nie was dahinter kommt; der
// Betreiber wollte ausdrücklich, dass etwa der lange Druck das
// KONTEXTMENÜ öffnet und dessen Einträge erklärt, „sonst verweist
// einfach fast alles auf die Karte".
//
// Vier Dinge, die man wissen muss:
//
// - **Die Ebene liegt über allem** (`MaterialApp.builder`, `app.dart`):
//   über dem Navigator, also auch über Dialogen und Blättern. Nur so kann
//   sie im Kontextmenü (`showGeneralDialog`) und im Ebenen-Blatt
//   hervorheben. Sie schluckt jeden Tipp — eine Vorführung löst nie
//   etwas aus.
// - **Anker und Szenen haben Kennungen**, und wer sie besitzt, meldet
//   sie an: `CoachAnchor(id: 'map.layers', …)` um den Knopf, eine Szene
//   `map.contextMenu` beim Karten-Screen. Das Skript sagt WAS geöffnet
//   wird, der Screen weiß WIE. Eine Szene gibt ihren Schließer zurück;
//   die Maschine schließt, sobald ein Schritt eine andere Szene will,
//   und am Ende immer. Übrig bleibt nichts, und das Menü meldet dabei
//   `null` — also keine Aktion.
// - **Gemessen wird über die ganze Transformation**
//   (`getTransformTo`), nicht über `localToGlobal & size`: Die
//   Knopfleiste steckt in einem `FittedBox(scaleDown)`, und ein Blatt
//   fährt animiert herein. Gemessen wird bei jedem Bild.
// - **Die Aussparung hat die Form des Elements**, der Ring sagt, welches
//   gemeint ist. Eine vergrößerte runde Aussparung je Knopf war genau
//   der Fehler der alten Tour.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';

/// Wie der Finger vorführt, was zu tun ist.
enum CoachGesture { none, tap, longPress, swipe }

/// Ein Schritt.
class CoachStep {
  const CoachStep({
    required this.title,
    required this.text,
    this.lit = const [],
    this.ring,
    this.scene,
    this.gesture = CoachGesture.none,
    this.requires = const [],
  });

  final String title;
  final String text;

  /// Was ausgespart wird (Anker-Kennungen). Leer heißt: nur abdunkeln.
  final List<String> lit;

  /// Worum der Ring liegt. `null` heißt: um alles Ausgesparte; eine
  /// leere Liste heißt: kein Ring (etwa, wenn der Finger zeigt).
  final List<String>? ring;

  /// Welche Szene dieser Schritt braucht (ein Menü, ein Blatt). Schritte
  /// mit derselben Szene teilen sie; ein Wechsel schließt die alte.
  final String? scene;

  /// Ein Finger auf der Mitte von Ring bzw. Aussparung.
  final CoachGesture gesture;

  /// Anker, ohne die der Schritt wegfällt — etwa die erste Zeile einer
  /// leeren Liste oder die Bilder einer Art ohne Bilder. Geprüft wird,
  /// wenn der Schritt dran ist; ohne die Angabe wartete die Maschine rund
  /// zwei Sekunden auf etwas, das nie kommt. Gehört ein Anker zu einer
  /// Szene, die dieser Schritt erst öffnet, steht er hier NICHT — der ist
  /// beim Prüfen noch gar nicht da.
  final List<String> requires;
}

/// Ein Ablauf aus Schritten.
class CoachScript {
  const CoachScript({
    required this.id,
    required this.steps,
    this.endLink,
  });

  final String id;
  final List<CoachStep> steps;

  /// Ein Weg weiter im LETZTEN Schritt, etwa in die Kurzanleitung:
  /// (Beschriftung, Route).
  final (String, String)? endLink;
}

/// Öffnet eine Szene und gibt zurück, wie sie wieder zu schließen ist.
typedef CoachSceneOpener = Future<VoidCallback> Function();

/// Wer was anbietet: Anker (Widgets) und Szenen (Menüs, Blätter).
///
/// Kein Zustand im Riverpod-Sinn — hier ändert sich nichts, worauf ein
/// Widget warten müsste; die Überlagerung misst ohnehin je Bild.
class CoachRegistry {
  final _anchors = <String, GlobalKey>{};
  final _scenes = <String, CoachSceneOpener>{};

  GlobalKey? anchor(String id) => _anchors[id];

  CoachSceneOpener? scene(String id) => _scenes[id];

  /// Meldet eine Szene an; der Rückgabewert meldet sie wieder ab.
  VoidCallback registerScene(String id, CoachSceneOpener open) {
    _scenes[id] = open;
    return () {
      if (_scenes[id] == open) _scenes.remove(id);
    };
  }

  void _addAnchor(String id, GlobalKey key) => _anchors[id] = key;

  void _removeAnchor(String id, GlobalKey key) {
    if (_anchors[id] == key) _anchors.remove(id);
  }
}

final coachRegistryProvider = Provider<CoachRegistry>((ref) => CoachRegistry());

/// Macht [child] für Hinweise auffindbar.
///
/// Der Schlüssel entsteht HIER, nicht beim Aufrufer: Ein globaler
/// `GlobalKey` überlebte einen Neuaufbau und zeigte dann auf ein
/// abgehängtes Element — dieselbe Lehre wie bei der ersten Kartentour.
class CoachAnchor extends ConsumerStatefulWidget {
  const CoachAnchor({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  ConsumerState<CoachAnchor> createState() => _CoachAnchorState();
}

class _CoachAnchorState extends ConsumerState<CoachAnchor> {
  final _key = GlobalKey();
  late final CoachRegistry _registry = ref.read(coachRegistryProvider);

  @override
  void initState() {
    super.initState();
    _registry._addAnchor(widget.id, _key);
  }

  @override
  void didUpdateWidget(CoachAnchor old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      _registry._removeAnchor(old.id, _key);
      _registry._addAnchor(widget.id, _key);
    }
  }

  @override
  void dispose() {
    _registry._removeAnchor(widget.id, _key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}

/// Ein laufender Ablauf.
class CoachRun {
  const CoachRun(this.script, this.index);
  final CoachScript script;
  final int index;
  CoachStep get step => script.steps[index];
  bool get isLast => index + 1 >= script.steps.length;
}

class CoachNotifier extends Notifier<CoachRun?> {
  String? _scene;
  VoidCallback? _closeScene;
  VoidCallback? _onDone;

  /// Zählt Szenenwechsel, damit ein spät fertiges Öffnen eines bereits
  /// verlassenen Schritts nichts mehr anrichtet.
  int _generation = 0;

  @override
  CoachRun? build() => null;

  /// Startet [script]. [onDone] läuft beim Ende — durchgesehen ODER
  /// übersprungen: Wer abbricht, hat entschieden.
  void start(CoachScript script, {VoidCallback? onDone}) {
    _closeCurrentScene();
    _onDone = onDone;
    _go(CoachRun(script, 0));
  }

  void next() {
    final run = state;
    if (run == null) return;
    if (run.isLast) {
      finish();
      return;
    }
    _go(CoachRun(run.script, run.index + 1));
  }

  void finish() {
    if (state == null) return;
    _closeCurrentScene();
    state = null;
    final done = _onDone;
    _onDone = null;
    done?.call();
  }

  void _go(CoachRun run) {
    final registry = ref.read(coachRegistryProvider);
    // Ein Anker ohne Fläche zählt als fehlend: Ein Abschnitt ohne Inhalt
    // steht oft als `SizedBox.shrink` da, und eine Aussparung der Größe
    // null wäre ein Schritt über nichts.
    bool present(String id) {
      final box = registry.anchor(id)?.currentContext?.findRenderObject();
      return box is RenderBox && box.hasSize && !box.size.isEmpty;
    }

    while (!run.step.requires.every(present)) {
      if (run.isLast) {
        finish();
        return;
      }
      run = CoachRun(run.script, run.index + 1);
    }
    final wanted = run.step.scene;
    if (wanted != _scene) {
      _closeCurrentScene();
      if (wanted != null) _openScene(wanted);
    }
    state = run;
  }

  void _openScene(String id) {
    final open = ref.read(coachRegistryProvider).scene(id);
    _scene = id;
    if (open == null) return;
    final generation = ++_generation;
    unawaited(open().then((close) {
      if (generation == _generation && _scene == id) {
        _closeScene = close;
      } else {
        close(); // der Schritt ist schon vorbei
      }
    }));
  }

  void _closeCurrentScene() {
    _generation++;
    final close = _closeScene;
    _closeScene = null;
    _scene = null;
    close?.call();
  }
}

final coachProvider =
    NotifierProvider<CoachNotifier, CoachRun?>(CoachNotifier.new);

/// Die Überlagerung. Gehört ÜBER den Navigator (`app.dart`).
class CoachOverlay extends ConsumerStatefulWidget {
  const CoachOverlay({
    super.key,
    required this.onNavigate,
    this.backButtonDispatcher,
  });

  /// Für den Weg weiter im letzten Schritt ([CoachScript.endLink]) — die
  /// Überlagerung liegt über dem Router und kennt ihn nicht selbst.
  final void Function(String route) onNavigate;

  /// Der Zurück-Verteiler des Routers. **Zurück beendet die Tour, nicht
  /// die App**: Die Überlagerung liegt ÜBER dem Router, und der bekäme
  /// die Taste sonst zuerst — auf der Karte hieße das, PilzBuddy zu
  /// verlassen. Solange eine Tour läuft, meldet sie sich hier mit
  /// Vorrang an, danach wieder ab (ein Abfangen, das stehen bleibt,
  /// sperrte den Nutzer in der App ein).
  final BackButtonDispatcher? backButtonDispatcher;

  @override
  ConsumerState<CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends ConsumerState<CoachOverlay>
    with SingleTickerProviderStateMixin {
  /// Treibt Ring, Finger und das Nachmessen: Ein Blatt fährt animiert
  /// herein, und die Aussparung soll ihm folgen.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  final _box = GlobalKey();
  List<Rect> _lit = const [];
  List<Rect> _ring = const [];
  CoachRun? _measured;

  /// Wie viele Bilder das Ziel des Schritts schon fehlt. Schließt jemand
  /// das Menü mit „Zurück", ist es weg — dann geht es weiter, statt
  /// ewig auf leere Fläche zu zeigen.
  int _missingFrames = 0;
  static const _maxMissingFrames = 120;

  ChildBackButtonDispatcher? _back;

  Future<bool> _onBack() {
    ref.read(coachProvider.notifier).finish();
    return SynchronousFuture(true);
  }

  void _listenBack(bool running) {
    if (running && _back == null) {
      final root = widget.backButtonDispatcher;
      if (root == null) return;
      _back = root.createChildBackButtonDispatcher()
        ..addCallback(_onBack)
        ..takePriority();
    } else if (!running && _back != null) {
      _back!.removeCallback(_onBack);
      widget.backButtonDispatcher?.forget(_back!);
      _back = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _clock.addListener(_measure);
  }

  @override
  void dispose() {
    _listenBack(false);
    _clock.dispose();
    super.dispose();
  }

  List<Rect> _rectsOf(List<String> ids) {
    final registry = ref.read(coachRegistryProvider);
    final overlay = _box.currentContext?.findRenderObject() as RenderBox?;
    if (overlay == null || !overlay.attached) return const [];
    final out = <Rect>[];
    for (final id in ids) {
      final box = registry.anchor(id)?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      out.add(MatrixUtils.transformRect(
          box.getTransformTo(overlay), Offset.zero & box.size));
    }
    return out;
  }

  void _measure() {
    final run = ref.read(coachProvider);
    if (run == null || !mounted) return;
    final step = run.step;
    final lit = _rectsOf(step.lit);
    final ring = step.ring == null ? lit : _rectsOf(step.ring!);
    final complete = lit.length == step.lit.length &&
        (step.ring == null || ring.length == step.ring!.length);
    if (!complete) {
      if (++_missingFrames > _maxMissingFrames) {
        _missingFrames = 0;
        ref.read(coachProvider.notifier).next();
      }
    } else {
      _missingFrames = 0;
    }
    if (complete && run != _measured) _revealOffscreen(step.lit, lit);
    if (run == _measured && _same(lit, _lit) && _same(ring, _ring)) return;
    setState(() {
      _measured = run;
      _lit = complete ? lit : const [];
      _ring = complete ? ring : const [];
    });
  }

  /// Holt ein Ziel ins Bild, das in seiner Liste außerhalb liegt — im
  /// Spot-Blatt stehen die Eintrage-Knöpfe unter einer langen
  /// Fundliste. Einmal je Schritt; danach misst jedes Bild nach, und die
  /// Aussparung fährt mit.
  void _revealOffscreen(List<String> ids, List<Rect> rects) {
    final bounds = Offset.zero & (_box.currentContext?.size ?? Size.zero);
    final registry = ref.read(coachRegistryProvider);
    for (var i = 0; i < rects.length && i < ids.length; i++) {
      if (bounds.contains(rects[i].topLeft) &&
          bounds.contains(rects[i].bottomRight - const Offset(1, 1))) {
        continue;
      }
      final context = registry.anchor(ids[i])?.currentContext;
      if (context == null || Scrollable.maybeOf(context) == null) continue;
      // Weit oben, damit darunter Platz für die Blase bleibt.
      unawaited(Scrollable.ensureVisible(context,
          alignment: 0.15, duration: const Duration(milliseconds: 300)));
    }
  }

  static bool _same(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i].topLeft - b[i].topLeft).distance > 0.5 ||
          (a[i].width - b[i].width).abs() > 0.5 ||
          (a[i].height - b[i].height).abs() > 0.5) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(coachProvider);
    _listenBack(run != null);
    if (run == null) {
      if (_clock.isAnimating) _clock.stop();
      _measured = null;
      _lit = const [];
      _ring = const [];
      return const SizedBox.shrink();
    }
    if (!_clock.isAnimating) _clock.repeat();
    // Solange der Schritt nicht vermessen ist, wird nur abgedunkelt —
    // keine Aussparung an einer geratenen Stelle. Das dauert ein Bild,
    // bei einer Szene so lange, bis sie steht.
    final measured = _measured == run;
    final lit = measured ? _lit : const <Rect>[];
    final ring = measured ? _ring : const <Rect>[];
    return Positioned.fill(
      child: LayoutBuilder(
        key: _box,
        builder: (context, constraints) => GestureDetector(
          // Schluckt, was es abdunkelt, und jeder Tipp geht weiter: Ein
          // Tipp, der durchfiele, löste genau das aus, was der Schritt
          // gerade erst erklärt.
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(coachProvider.notifier).next(),
          child: AnimatedBuilder(
            animation: _clock,
            builder: (context, _) => Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: CoachPainter(
                      lit: lit,
                      ring: ring,
                      pulse: _clock.value,
                    ),
                  ),
                ),
                if (measured && run.step.gesture != CoachGesture.none)
                  _finger(run.step.gesture, ring.isNotEmpty ? ring : lit,
                      constraints.biggest),
                _bubble(context, run, lit, ring, constraints.biggest),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _finger(CoachGesture gesture, List<Rect> rects, Size size) {
    final target = rects.isEmpty
        ? size.center(Offset.zero)
        : rects.reduce((a, b) => a.expandToInclude(b)).center;
    return Positioned(
      left: target.dx - 60,
      top: target.dy - 60,
      width: 120,
      height: 120,
      child: IgnorePointer(
        child: CustomPaint(
          painter: FingerPainter(gesture: gesture, t: _clock.value),
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context, CoachRun run, List<Rect> lit,
      List<Rect> ring, Size size) {
    final all = [...lit, ...ring];
    final union = all.isEmpty ? null : all.reduce((a, b) => a.expandToInclude(b));
    // Auf die andere Seite des Hervorgehobenen: Eine Sprechblase über dem,
    // was sie erklärt, ist eine Sprechblase über nichts. Bei einer Geste
    // bleibt dazu Platz für den Finger.
    // Die Hand ragt gut 90 px schräg unter ihr Ziel.
    final pad = run.step.gesture == CoachGesture.none ? 20.0 : 84.0;
    final spaceAbove = union == null ? size.height : union.top;
    final spaceBelow = union == null ? size.height : size.height - union.bottom;
    final below = spaceBelow >= spaceAbove;
    // Mindestens so hoch, dass Titel, Zähler und Knöpfe passen — der
    // Text scrollt, die Knöpfe nie (bei 360×640 waren 157 und 210 zu
    // wenig: Im Test ist die Schrift breit, die Knöpfe brechen in zwei
    // Zeilen um).
    const minRoom = 240.0;
    final free = (below ? spaceBelow : spaceAbove) - pad - 24;
    // Passt sie weder darüber noch darunter — ein hohes, schmales Ziel
    // wie die Knopfleiste auf einem kleinen Schirm —, steht sie DANEBEN.
    // Bis 1.205.0 ragte sie dort oben aus dem Bild (360×640, im Test erst
    // gesehen, als er prüfte, dass die Blase im Bild liegt).
    final leftRoom = union == null ? 0.0 : union.left - 24;
    final rightRoom = union == null ? 0.0 : size.width - union.right - 24;
    final side = union != null &&
            free < minRoom &&
            math.max(leftRoom, rightRoom) >= 200
        ? (leftRoom >= rightRoom ? AxisDirection.left : AxisDirection.right)
        : null;
    final room = side != null ? size.height : math.max(free, minRoom);
    final pointAt = ring.isNotEmpty
        ? ring.reduce((a, b) => a.expandToInclude(b)).center
        : union?.center;
    final step = run.step;
    final link = run.isLast ? run.script.endLink : null;
    final placement = _BubblePlacement();
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _BubbleLayout(
          target: union,
          pointAt: pointAt,
          side: side,
          below: below,
          pad: pad,
          insets: MediaQuery.paddingOf(context),
          placement: placement,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: room),
          child: CustomPaint(
            // Der Pfeil zeigt auf den Ring — dann ist klar, worüber der
            // Text spricht, auch wenn mehreres ausgespart ist.
            painter: pointAt == null
                ? null
                : _ArrowPainter(
                    placement: placement,
                    towardsX: pointAt.dx - 16,
                    up: below,
                    // Die Flächenfarbe einer M3-Karte, sonst hätte der
                    // Pfeil einen anderen Ton als die Blase.
                    colour: Theme.of(context).colorScheme.surfaceContainerLow),
            child: Card(
              key: const ValueKey('coach-bubble'),
              elevation: 6,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.title,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    // Nur der Text scrollt, Zähler und Knöpfe bleiben
                    // immer sichtbar (so schon in der alten Tour).
                    Flexible(
                      child: SingleChildScrollView(child: Text(step.text)),
                    ),
                    const SizedBox(height: 12),
                    Text('${run.index + 1} von ${run.script.steps.length}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).hintColor)),
                    const SizedBox(height: 4),
                    // `Wrap`, keine `Row`: Deutsche Beschriftungen sind
                    // lang (in der alten Tour 50–81 px Überlauf gemessen).
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      children: [
                        if (link != null)
                          TextButton(
                            onPressed: () {
                              ref.read(coachProvider.notifier).finish();
                              widget.onNavigate(link.$2);
                            },
                            child: Text(link.$1),
                          )
                        else if (!run.isLast)
                          TextButton(
                            onPressed: () =>
                                ref.read(coachProvider.notifier).finish(),
                            child: const Text('Überspringen'),
                          ),
                        FilledButton(
                          onPressed: () =>
                              ref.read(coachProvider.notifier).next(),
                          child: Text(run.isLast ? 'Los geht\'s' : 'Weiter'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Abdunkelung mit Aussparungen und pulsierendem Ring.
///
/// Öffentlich, damit ein Test beides gegen die ECHTEN Maße der Widgets
/// halten kann (`tester.getRect`).
class CoachPainter extends CustomPainter {
  const CoachPainter({required this.lit, required this.ring, this.pulse = 0});

  final List<Rect> lit;
  final List<Rect> ring;
  final double pulse;

  static const radius = Radius.circular(12);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xA6000000));
    final clear = Paint()..blendMode = BlendMode.clear;
    for (final r in lit) {
      // Knapp um das Element, nicht vergrößert: Mehr Rand griffe in den
      // Nachbarknopf — der Fehler der alten Tour.
      canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(2), radius), clear);
    }
    canvas.restore();
    if (ring.isEmpty) return;
    final r = ring.reduce((a, b) => a.expandToInclude(b));
    final grow = 3 + 4 * math.sin(pulse * math.pi);
    final rrect = RRect.fromRectAndRadius(r.inflate(grow), radius);
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = Colors.white.withValues(alpha: 0.9));
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = AppColors.forestGreen);
  }

  @override
  bool shouldRepaint(CoachPainter old) =>
      old.pulse != pulse || old.lit != lit || old.ring != ring;
}

/// Wo der Finger in einem Durchlauf gerade ist. Rein und öffentlich, damit
/// ein Test den Ablauf prüfen kann, ohne Pixel zu lesen: Gedrückt wird
/// AUF dem Ziel, und nur dort.
@immutable
class FingerMotion {
  const FingerMotion({
    required this.tipShift,
    required this.lift,
    required this.pressed,
    required this.progress,
    required this.opacity,
  });

  /// Wie weit die Kuppe vom Ziel weg ist — nur beim Wischen nicht null.
  final Offset tipShift;

  /// 0 = auf dem Schirm, 1 = abgehoben.
  final double lift;

  final bool pressed;

  /// 0…1: wie weit die Geste ist (Kreis beim langen Druck, Welle beim
  /// Tipp, Strecke beim Wischen).
  final double progress;

  final double opacity;

  /// Halbe Wischstrecke.
  static const swipeReach = 40.0;

  static double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  static double _in(double v) => Curves.easeOutCubic.transform(v);

  /// Drei Phasen je Geste: herankommen, drücken, abheben. Zwischen den
  /// Durchläufen ist die Hand weg — sonst sähe der Neustart aus wie ein
  /// Sprung.
  factory FingerMotion.of(CoachGesture gesture, double t) {
    final (down, up) = switch (gesture) {
      CoachGesture.tap => (0.3, 0.45),
      CoachGesture.longPress => (0.15, 0.85),
      CoachGesture.swipe => (0.2, 0.75),
      CoachGesture.none => (1.0, 1.0),
    };
    final lift = t < down
        ? 1 - _in(_seg(t, 0, down))
        : t < up
            ? 0.0
            : _in(_seg(t, up, math.min(1, up + 0.2)));
    final opacity = _seg(t, 0, 0.1) * (1 - _seg(t, 0.88, 1));
    return switch (gesture) {
      CoachGesture.tap => FingerMotion(
          tipShift: Offset.zero,
          lift: lift,
          pressed: t >= down && t < up,
          // Die Welle läuft über das Loslassen hinaus aus.
          progress: _seg(t, down, 0.75),
          opacity: opacity,
        ),
      CoachGesture.swipe => FingerMotion(
          // Von rechts nach links, wie man durch Bilder blättert.
          tipShift: Offset(
              swipeReach -
                  2 * swipeReach * Curves.easeInOut.transform(_seg(t, 0.25, up)),
              0),
          lift: lift,
          pressed: t >= down && t < up,
          progress: _seg(t, 0.25, up),
          opacity: opacity,
        ),
      _ => FingerMotion(
          tipShift: Offset.zero,
          lift: lift,
          pressed: t >= down && t < up,
          progress: _seg(t, down, up),
          opacity: opacity,
        ),
    };
  }
}

/// Die Hand, die vorführt (Betreiber, 2026-09-24: „der Finger könnte
/// etwas besser sein" — die erste Fassung waren zwei abgerundete
/// Rechtecke).
///
/// Gezeichnet, nicht als Bild: Sie folgt so dem Ziel pixelgenau und
/// braucht kein Asset. Im Stil der Pilz-Buddys — warmes Weiß, weiche
/// braune Kontur, ein grüner Ärmel —, damit sie zur App gehört und nicht
/// nach Betriebssystem aussieht. Ausgestreckter Zeigefinger mit Nagel,
/// die übrigen Finger eingerollt, der Daumen angelegt; schräg von unten
/// rechts, so wie eine rechte Hand auf den Schirm kommt.
class FingerPainter extends CustomPainter {
  const FingerPainter({required this.gesture, required this.t});

  final CoachGesture gesture;

  /// 0…1, ein Durchlauf.
  final double t;

  static const _skin = Color(0xFFFFF6EC);
  static const _nail = Color(0xFFF6DCCB);
  static const _edge = Color(0xFF4E342E);

  @override
  void paint(Canvas canvas, Size size) {
    final motion = FingerMotion.of(gesture, t);
    if (motion.opacity <= 0) return;
    final target = size.center(Offset.zero);
    final tip = target + motion.tipShift;
    _paintTrace(canvas, target, tip, motion);

    canvas.saveLayer(null,
        Paint()..color = Colors.white.withValues(alpha: motion.opacity));
    // Abgehoben schwebt die Hand zum Betrachter hin: etwas größer, etwas
    // weiter weg vom Ziel, mit längerem Schatten. Gedrückt wird sie eine
    // Spur kleiner — daran sieht man die Berührung.
    final scale = motion.pressed ? 0.94 : 1 + 0.1 * motion.lift;
    canvas.translate(tip.dx + 12 * motion.lift, tip.dy + 18 * motion.lift);
    canvas.rotate(-0.45);
    canvas.scale(scale);
    _paintHand(canvas, elevation: motion.pressed ? 2 : 3 + 5 * motion.lift);
    canvas.restore();
  }

  /// Was die Geste auf dem Schirm hinterlässt — UNTER der Hand.
  void _paintTrace(
      Canvas canvas, Offset target, Offset tip, FingerMotion motion) {
    final p = motion.progress;
    final dot = Paint()..color = AppColors.forestGreen;
    switch (gesture) {
      case CoachGesture.longPress when motion.pressed:
        // Der Kreis füllt sich — so lange dauert „lange".
        canvas.drawCircle(
            tip, 26, Paint()..color = Colors.white.withValues(alpha: 0.35));
        canvas.drawArc(
            Rect.fromCircle(center: tip, radius: 26),
            -math.pi / 2,
            2 * math.pi * p,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5
              ..strokeCap = StrokeCap.round
              ..color = AppColors.forestGreen);
        canvas.drawCircle(tip, 7, dot);
      case CoachGesture.tap when p > 0 && p < 1:
        canvas.drawCircle(
            tip,
            10 + 26 * p,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..color = Colors.white.withValues(alpha: 0.7 * (1 - p)));
        if (motion.pressed) canvas.drawCircle(tip, 7, dot);
      case CoachGesture.swipe when motion.pressed:
        final start = target + const Offset(FingerMotion.swipeReach, 0);
        canvas.drawLine(
            start,
            tip,
            Paint()
              ..strokeWidth = 12
              ..strokeCap = StrokeCap.round
              ..color = Colors.white.withValues(alpha: 0.4));
        canvas.drawCircle(tip, 7, dot);
      default:
        break;
    }
  }

  /// Die Hand in eigenen Maßen: Kuppe bei (0, 0), der Zeigefinger läuft
  /// nach unten.
  void _paintHand(Canvas canvas, {required double elevation}) {
    RRect box(double l, double t, double r, double b, double radius) =>
        RRect.fromLTRBR(l, t, r, b, Radius.circular(radius));

    final finger = box(-9, 0, 9, 50, 9);
    final curls = [
      box(7, 32, 21, 50, 7),
      box(17, 36, 30, 54, 6.5),
      box(26, 41, 37, 58, 5.5),
    ];
    final palm = box(-11, 38, 36, 84, 16);
    final thumb = Path()..addRRect(box(-7, -14, 7, 14, 7));
    final thumbPlaced = thumb.transform(
        (Matrix4.translationValues(-14, 60, 0)..rotateZ(0.5)).storage);
    var hand = Path()..addRRect(finger);
    for (final part in [
      Path()..addRRect(palm),
      thumbPlaced,
      for (final c in curls) Path()..addRRect(c),
    ]) {
      hand = Path.combine(PathOperation.union, hand, part);
    }
    final cuff = box(-10, 78, 37, 98, 6);

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..color = _edge.withValues(alpha: 0.85);
    final fine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = _edge.withValues(alpha: 0.45);

    canvas.drawShadow(
        Path.combine(PathOperation.union, hand, Path()..addRRect(cuff)),
        Colors.black,
        elevation,
        false);
    // Der Ärmel zuerst — die Hand liegt darüber, sichtbar bleibt der
    // Bund.
    canvas.drawRRect(cuff, Paint()..color = AppColors.forestGreen);
    canvas.drawRRect(cuff, edge);
    canvas.drawPath(hand, Paint()..color = _skin);
    canvas.drawPath(hand, edge);

    // Nagel und Gelenkfalten: Erst sie machen aus der Form einen Finger.
    final nail = box(-5, 3, 5, 15, 4.5);
    canvas.drawRRect(nail, Paint()..color = _nail);
    canvas.drawRRect(nail, fine);
    canvas.drawLine(const Offset(-4, 22), const Offset(4, 22), fine);
    canvas.drawLine(const Offset(-4, 33), const Offset(4, 33), fine);
    // Die Trennung der eingerollten Finger, nur oben — weiter unten
    // gehen sie in die Handfläche über.
    canvas.save();
    canvas.clipRect(const Rect.fromLTRB(9, 0, 60, 47));
    for (final c in curls.skip(1)) {
      canvas.drawRRect(c, fine);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FingerPainter old) => old.t != t || old.gesture != gesture;
}

/// Wo die Blase gelandet ist — das Layout schreibt, der Pfeil liest es im
/// selben Bild.
class _BubblePlacement {
  bool shifted = false;
}

/// Setzt die Blase neben ihr Ziel und schiebt sie ins Bild, wenn sie
/// dort hinausragte.
///
/// **Erst messen, dann schieben.** Eine Regel VOR dem Messen („reicht
/// der Platz nicht, an den Rand") schob die Blase auch dann auf das Ziel,
/// wenn sie in Wirklichkeit gepasst hätte — sie ist meist kürzer als ihre
/// Obergrenze. Ohne Schieben ragte sie auf der Artseite unten aus dem
/// Bild, und „Weiter" war nicht zu erreichen (#596, beides im Test).
class _BubbleLayout extends SingleChildLayoutDelegate {
  _BubbleLayout({
    required this.target,
    required this.pointAt,
    required this.side,
    required this.below,
    required this.pad,
    required this.insets,
    required this.placement,
  });

  final Rect? target;
  final Offset? pointAt;

  /// Neben das Ziel statt darüber oder darunter; `null` heißt senkrecht.
  final AxisDirection? side;
  final bool below;
  final double pad;
  final EdgeInsets insets;
  final _BubblePlacement placement;

  static const _margin = 16.0;

  static const _gap = 8.0;

  double _width(Size size) => switch ((side, target)) {
        (AxisDirection.left, final t?) => t.left - _margin - _gap,
        (AxisDirection.right, final t?) => size.width - t.right - _margin - _gap,
        _ => size.width - 2 * _margin,
      };

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = _width(constraints.biggest);
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight:
          math.max(0, constraints.maxHeight - insets.vertical - 2 * _margin),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    final t = target;
    final lowest = insets.top + _margin;
    final highest =
        math.max(lowest, size.height - insets.bottom - _margin - child.height);
    if (side != null && t != null) {
      // Auf Höhe dessen, was gemeint ist; ohne Pfeil, der zeigt nur
      // senkrecht.
      placement.shifted = true;
      final centre = pointAt?.dy ?? t.center.dy;
      return Offset(
        side == AxisDirection.left ? _margin : t.right + _gap,
        (centre - child.height / 2).clamp(lowest, highest),
      );
    }
    final wanted = t == null
        ? size.height / 3
        : below
            ? t.bottom + pad
            : t.top - pad - child.height;
    final y = wanted.clamp(lowest, highest);
    placement.shifted = (y - wanted).abs() > 0.5;
    return Offset(_margin, y);
  }

  @override
  bool shouldRelayout(_BubbleLayout old) =>
      old.target != target ||
      old.pointAt != pointAt ||
      old.side != side ||
      old.below != below ||
      old.pad != pad ||
      old.insets != insets;
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({
    required this.placement,
    required this.towardsX,
    required this.up,
    required this.colour,
  });

  /// Geschoben zeigt der Pfeil nicht mehr auf sein Ziel — dann keiner.
  final _BubblePlacement placement;

  /// Wohin, in Koordinaten dieses Kastens.
  final double towardsX;

  /// Pfeil oben (Blase unter dem Ziel) oder unten.
  final bool up;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    if (placement.shifted) return;
    final x = towardsX.clamp(24.0, size.width - 24.0);
    final path = Path();
    if (up) {
      path
        ..moveTo(x - 10, 1)
        ..lineTo(x, -11)
        ..lineTo(x + 10, 1);
    } else {
      path
        ..moveTo(x - 10, size.height - 1)
        ..lineTo(x, size.height + 11)
        ..lineTo(x + 10, size.height - 1);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.placement != placement ||
      old.towardsX != towardsX ||
      old.up != up ||
      old.colour != colour;
}
