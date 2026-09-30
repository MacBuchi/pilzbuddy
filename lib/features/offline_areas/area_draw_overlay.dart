// Die Zeichenfläche über der Karte (#630, Stufe 2b; übernommen aus
// TrailBuddy): liegt nur dort, solange ein Werkzeug auf den nächsten
// Strich wartet, fängt dann JEDE Berührung ab (die Karte darunter steht
// still — sonst verschöbe der Strich die Karte, die er gerade beschreibt)
// und meldet den fertigen Strich als Kacheln. Danach ist das Werkzeug weg
// und die Karte wieder frei (area_draw.dart).
//
// Gerechnet wird mit dem Sichtfenster vom letzten Stillstand
// (`mapIdleBoundsProvider`): Während die Fläche liegt, kann sich die
// Karte nicht bewegen, das Fenster stimmt also. Die Fläche liegt im
// selben Stack wie die Karte und hat deshalb deren Größe.
import 'package:flutter/material.dart';

import '../map/map_view/marker_culling.dart' show MapViewBounds;
import 'area_draw.dart';

/// Ein Punkt kommt erst dazu, wenn der Finger so weit gewandert ist —
/// sonst hätte ein langsamer Strich tausende Punkte.
const kAreaStrokeStepPx = 4.0;

const _inkLight = Color(0xE6FFFFFF);
const _inkDark = Color(0xD9131A16);

class AreaDrawOverlay extends StatefulWidget {
  const AreaDrawOverlay({
    super.key,
    required this.bounds,
    required this.tool,
    required this.onStroke,
  });

  final MapViewBounds bounds;
  final AreaDrawTool tool;

  /// Die Kacheln des Strichs — null, wenn er zu groß war.
  final void Function(Set<int>? keys) onStroke;

  @override
  State<AreaDrawOverlay> createState() => _AreaDrawOverlayState();
}

class _AreaDrawOverlayState extends State<AreaDrawOverlay> {
  final _points = <Offset>[];

  void _add(Offset p) {
    if (_points.isEmpty || (p - _points.last).distance >= kAreaStrokeStepPx) {
      setState(() => _points.add(p));
    }
  }

  void _end(Size size) {
    final pts = List.of(_points);
    setState(_points.clear);
    if (pts.length < 2) return;
    final ring = [
      for (final p in pts) unprojectFromBounds(widget.bounds, size, p)
    ];
    widget.onStroke(tilesTouchedByRing(ring));
  }

  @override
  Widget build(BuildContext context) {
    final add = widget.tool == AreaDrawTool.add;
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      return GestureDetector(
        key: const ValueKey('area-draw-surface'),
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => _add(d.localPosition),
        onPanUpdate: (d) => _add(d.localPosition),
        onPanEnd: (_) => _end(size),
        onPanCancel: () => setState(_points.clear),
        child: CustomPaint(
          size: size,
          painter: _StrokePainter(
            List.of(_points),
            // Die Regel der Fläche: dazu hell, weg dunkel.
            color: add ? _inkLight : _inkDark,
          ),
        ),
      );
    });
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.points, {required this.color});

  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    // Geschlossen gezeigt, wie er gerechnet wird: Ende zum Anfang.
    final closed = Path.from(path)..close();
    canvas.drawPath(closed, Paint()..color = color.withValues(alpha: 0.15));
    // Darunter ein Saum in der Gegenhelligkeit: Der Strich läuft über
    // Abgedunkeltes UND Helles und soll auf beidem stehen.
    final halo = color.computeLuminance() > 0.5 ? _inkDark : _inkLight;
    for (final (c, w) in [(halo.withValues(alpha: 0.6), 5.0), (color, 3.0)]) {
      canvas.drawPath(
        path,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) =>
      old.points.length != points.length || old.color != color;
}
