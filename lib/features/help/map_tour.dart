// Die geführte Tour über die Karte (#350, Baustein B).
//
// **Warum überhaupt eine Tour, wenn Baustein A schon erklärt.** A
// erklärt am Ort des Bedarfs — und erreicht damit genau die nicht, bei
// denen schon Spots von Buddys auf der Karte liegen: Der leere Zustand
// zeigt sich dort bewusst nicht, weil er ihre Marker verdecken würde.
// Für die App verbreitet sich über Einladungen; dieser Nutzer ist eher
// die Regel als die Ausnahme. Die Tour hängt an nichts, was auf der
// Karte liegt, und schließt genau diese Lücke.
//
// **Fünf Schritte: die Bedienelemente dieses Bildschirms, vollständig.**
// Die Grenze ist der Schirm, nicht eine Zahl — wer einen Knopf sucht, den
// die Tour ausgelassen hat, weiß ja nicht, dass sie ihn ausgelassen hat
// (Betreiber, 2026-08-29: „quasi alle Knöpfe auf der Hauptseite"). Damit
// ist die Spalte gedeckt: Ebenen, Filter, Unterwegs, Meine Position,
// Neuer Spot — dazu das Fadenkreuz, das keiner ist. Ein Test hält die
// Deckung fest, ein sechster Knopf ohne Schritt macht ihn rot.
//
// **Alles Übrige führt in die Kurzanleitung, und zwar über einen KNOPF.**
// Bis 1.109.0 stand hier, der Verweis sei „am Ende verlinkt" — er war es
// nie. Das machte die Kürze zu einem Versprechen ohne Deckung: vier von
// sieben nicht erratbaren Dingen erklärt, der Rest im Nichts. Der eine
// andere Weg dorthin, das grüne Banner, erscheint nur bei VÖLLIG leerer
// Karte — also gerade nicht bei dem Nutzer, für den diese Tour gebaut
// wurde.
//
// Nicht erratbar sind sieben Dinge (Fadenkreuz↔Knopf, Ebenen, Unterwegs,
// Leergang, Freigabe, Offline-Karten, Ampel). Sieben Schritte wären keine
// Tour mehr, sondern ein Handbuch mit Abdunkelung; die drei, die nicht
// auf diesem Schirm liegen, stehen in der Kurzanleitung.
//
// **Sie blockiert nie.** „Überspringen" steht in jedem Schritt, die
// Reiterleiste unten bleibt frei, und ein Tipp irgendwohin geht weiter.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/settings.dart';

/// Die Anker auf der Karte. Eine Instanz je [State] des Karten-Screens,
/// nicht global: Zwei Karten gleichzeitig gibt es nicht, aber ein
/// globaler `GlobalKey` überlebt einen Neuaufbau und zeigt dann auf ein
/// abgehängtes Element — Rechtecke aus dem Nichts.
class MapTourAnchors {
  final crosshair = GlobalKey();
  final add = GlobalKey();
  final layers = GlobalKey();
  final trip = GlobalKey();
  final filter = GlobalKey();
  final locate = GlobalKey();
}

/// Ein Schritt: was hervorgehoben wird, und was dazu gesagt wird.
class MapTourStep {
  const MapTourStep({
    required this.title,
    required this.text,
    required this.anchors,
  });

  final String title;
  final String text;

  /// Welche Anker dieser Schritt freistellt — mehrere sind erlaubt, weil
  /// der erste Schritt zwei Dinge in Beziehung setzt.
  final List<GlobalKey> Function(MapTourAnchors) anchors;
}

const kMapTourSteps = <MapTourStep>[
  MapTourStep(
    title: 'So entsteht ein Spot',
    text: 'Das Fadenkreuz in der Mitte zeigt, wo gespeichert wird — nicht '
        'dein Standort. Schieb die Karte fein, bis es genau auf deiner '
        'Stelle liegt, und tipp auf „Neuer Spot".',
    // Zwei Löcher: Dass diese beiden zusammengehören, IST die Hürde des
    // ersten Starts. Getrennt gezeigt bliebe sie genau so bestehen.
    //
    // „fein" und „genau" sind seit #360 nötig: Die Karte startet bereits
    // bei der eigenen Position, es geht also nur noch um den letzten
    // Meter. Ohne die zwei Wörter widerspräche der Satz dem Schritt, der
    // direkt darauf folgt.
    anchors: _spotAnchors,
  ),
  // Direkt danach, weil er die Kehrseite desselben Gedankens ist: Schritt
  // 1 sagt, dass das Fadenkreuz NICHT der eigene Standort ist — dieser
  // Knopf ist der, der ihn holt.
  MapTourStep(
    title: 'Wo du gerade bist',
    text: 'Die Karte öffnet sich bei deiner Position. Hast du sie '
        'weggeschoben, holt dich dieser Knopf zurück.',
    anchors: _locateAnchors,
  ),
  MapTourStep(
    title: 'Was die Karte zeigt',
    text: 'Hinter „Ebenen" liegen Waldtypen, Höhenlinien, Regen und die '
        'Pilzampel. Die kleine Zahl am Knopf sagt, wie viele gerade an '
        'sind.',
    anchors: _layersAnchors,
  ),
  MapTourStep(
    title: 'Wenn es viele Spots werden',
    text: 'Der Filter blendet Spots nach Art oder Zeit aus. Ein aktiver '
        'Filter steht oben auf der Karte — damit du keinen Spot suchst, '
        'den du nur ausgeblendet hast.',
    anchors: _filterAnchors,
  ),
  // Zuletzt, und das ist eine Entscheidung: „Geh raus und benutz es" ist
  // der bessere Schlusssatz vor „Los geht's" als der Filter. Nebenbei
  // läuft der Scheinwerfer damit ab Schritt 3 die Spalte hinunter
  // (Ebenen → Filter → Unterwegs), statt im vorletzten Sprung wieder
  // hinaufzuspringen.
  MapTourStep(
    title: 'Unterwegs',
    text: 'Die Pilztour zeichnet deinen Weg auf und schlägt dir am Ende '
        'vor, wo du „nichts gefunden" buchst. Daneben teilst du deinen '
        'Standort für ein paar Stunden mit Buddies.',
    anchors: _tripAnchors,
  ),
];

List<GlobalKey> _spotAnchors(MapTourAnchors a) => [a.crosshair, a.add];
List<GlobalKey> _locateAnchors(MapTourAnchors a) => [a.locate];
List<GlobalKey> _layersAnchors(MapTourAnchors a) => [a.layers];
List<GlobalKey> _tripAnchors(MapTourAnchors a) => [a.trip];
List<GlobalKey> _filterAnchors(MapTourAnchors a) => [a.filter];

/// Hat der Nutzer die Tour schon gesehen? Gerätelokal (Betreiber,
/// 2026-08-29) — dieselbe Ablage wie alle anderen Schalter.
///
/// Der Preis ist bekannt und angenommen: Nach einer Neuinstallation
/// läuft sie wieder. Ein Feld am Konto hätte einen Patch, `schema.sql`
/// und die Saat-Liste gekostet, für eine Frage, die einmal im Leben
/// eines Geräts gestellt wird.
final mapTourSeenProvider = NotifierProvider<RememberedFlag, bool>(
  () => RememberedFlag(
    read: (s) => s.mapTourSeen,
    write: (s, v) => s.setMapTourSeen(v),
    label: 'Karten-Tour merken',
  ),
);

/// Der laufende Schritt — `null` heißt: keine Tour.
class MapTourNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  /// Von vorn — auch für den Wiederaufruf aus der Kurzanleitung.
  void start() => state = 0;

  /// Weiter, oder Schluss nach dem letzten Schritt.
  void next() {
    final step = state;
    if (step == null) return;
    if (step + 1 >= kMapTourSteps.length) {
      finish();
      return;
    }
    state = step + 1;
  }

  /// Beenden — durchgesehen ODER übersprungen.
  ///
  /// Beides merkt sich dasselbe: Wer überspringt, hat entschieden, und
  /// eine Tour, die nach dem Überspringen wiederkommt, ist keine
  /// Hilfe mehr, sondern eine Belästigung.
  void finish() {
    state = null;
    if (!ref.read(mapTourSeenProvider)) {
      ref.read(mapTourSeenProvider.notifier).set(true);
    }
  }
}

final mapTourProvider =
    NotifierProvider<MapTourNotifier, int?>(MapTourNotifier.new);

/// Legt die Tour über die Karte. Gehört ÜBER das `Scaffold` — die
/// Knopfspalte hängt an `floatingActionButton` und läge sonst über der
/// Abdunkelung, also sähe jeder Knopf aus wie hervorgehoben.
class MapTourOverlay extends ConsumerStatefulWidget {
  const MapTourOverlay({super.key, required this.anchors});

  final MapTourAnchors anchors;

  @override
  ConsumerState<MapTourOverlay> createState() => _MapTourOverlayState();
}

class _MapTourOverlayState extends ConsumerState<MapTourOverlay> {
  List<Rect> _holes = const [];
  int? _measuredStep;

  /// Misst die Anker NACH dem Bild.
  ///
  /// Nicht während des Aufbaus: Die Knopfspalte steckt in einem
  /// `FittedBox(scaleDown)`, ihre Maße hängen also an der
  /// Bildschirmhöhe und stehen erst nach dem Layout fest. Feste Zahlen
  /// wären hier auf jedem zweiten Gerät falsch.
  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final step = ref.read(mapTourProvider);
      if (step == null) return;
      final rects = <Rect>[];
      for (final key in kMapTourSteps[step].anchors(widget.anchors)) {
        final box = key.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) continue;
        rects.add(box.localToGlobal(Offset.zero) & box.size);
      }
      if (_measuredStep == step && _sameRects(rects, _holes)) return;
      setState(() {
        _holes = rects;
        _measuredStep = step;
      });
    });
  }

  static bool _sameRects(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final step = ref.watch(mapTourProvider);
    // Jede Änderung neu vermessen — auch der Wechsel von „aus" nach
    // Schritt 0, denn dann existieren die Anker gerade erst.
    ref.listen<int?>(mapTourProvider, (_, _) => _measure());
    if (step == null) return const SizedBox.shrink();
    _measure();

    final tourStep = kMapTourSteps[step];
    // Solange nichts vermessen ist, wird nur abgedunkelt — kein Loch an
    // einer geratenen Stelle. Das dauert genau ein Bild.
    final union = _holes.isEmpty
        ? null
        : _holes.reduce((a, b) => a.expandToInclude(b));

    return Positioned.fill(
      // **Die eigene Kantenlänge, nicht die des Bildschirms.** Bis
      // 1.109.0 stand hier `MediaQuery.sizeOf(context)`. Dieser Kasten
      // liegt aber im Karten-Zweig, also UNTER der Reiterleiste der
      // Hülle: Auf einem 412×915-Schirm ist er 835 hoch, MediaQuery
      // meldet 915. Die Blase hängt an `bottom: höhe - loch.top + 16`,
      // war damit 80 dp zu tief angesetzt und deckte in Schritt 1 das
      // Fadenkreuz zu — gemessen, nicht vermutet. Dieselbe Lehre wie
      // beim Spot-Blatt (#358): Der Kasten weiß seine Maße, der
      // Bildschirm weiß sie nicht.
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          // Der ganze Schirm geht weiter. Und er schluckt, was er
          // abdunkelt: Ein Tipp, der zur Karte durchfiele, verschöbe
          // genau das, was der Schritt gerade erklärt.
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(mapTourProvider.notifier).next(),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: SpotlightPainter(holes: _holes)),
              ),
              _bubble(context, step, tourStep, union, constraints.biggest),
            ],
          ),
        ),
      ),
    );
  }

  /// Beendet die Tour und führt in die Kurzanleitung.
  ///
  /// Erst beenden, dann navigieren: Sonst stünde die Tour beim
  /// Zurückkommen noch auf ihrem letzten Schritt und dunkelte die Karte
  /// erneut ab. Und der Merker gehört gesetzt — wer hier abbiegt, hat die
  /// Tour gesehen.
  ///
  /// `push` und nicht `go`, wie beim Banner der leeren Karte
  /// (`map_banners.dart`): Der Zurück-Pfeil führt damit auf die Karte,
  /// nicht ins Profil, in dem dieser Nutzer nie war.
  void _openGuide(BuildContext context) {
    ref.read(mapTourProvider.notifier).finish();
    context.push('/profile/anleitung');
  }

  Widget _bubble(BuildContext context, int step, MapTourStep tourStep,
      Rect? union, Size size) {
    // Auf die andere Seite des Lochs: Eine Sprechblase über dem, was sie
    // erklärt, ist eine Sprechblase über nichts.
    //
    // Dieselbe Regel wie bisher, nur in der Größe geschrieben, die
    // ohnehin gebraucht wird: „Loch-Mitte in der oberen Hälfte" und
    // „unten ist mehr Platz als oben" sind identisch
    // (`(top+bottom)/2 < h/2` ⟺ `top < h−bottom`) — der Deckel weiter
    // unten braucht die beiden Zahlen aber einzeln. Wer hier eine
    // Verhaltensänderung vermutet: Es ist keine, und ein Test kann
    // zwischen den Fassungen deshalb auch nicht unterscheiden.
    final spaceAbove = union?.top ?? size.height;
    final spaceBelow = union == null ? size.height : size.height - union.bottom;
    // Ohne Messung sind beide Werte gleich, `below` ist dann also wahr —
    // der `bottom`-Zweig unten kann `union` nie null sehen.
    final below = spaceBelow >= spaceAbove;
    // Und was nicht hineinpasst, wird nicht hinausgeschoben. Auf einem
    // 360×640-Schirm blieben oberhalb des Fadenkreuzes 263 dp für eine
    // Karte von gut 300 — die Knöpfe standen damit über dem oberen Rand
    // und waren nicht mehr tippbar (im Test nachgemessen). Jetzt begrenzt
    // die Karte sich auf den vorhandenen Platz; scrollen tut dann der
    // TEXT, nie die Knopfzeile.
    final room = math.max((below ? spaceBelow : spaceAbove) - 32, 160.0);
    final last = step + 1 >= kMapTourSteps.length;
    return Positioned(
      left: 16,
      right: 16,
      top: below ? (union == null ? size.height / 2 : union.bottom + 16) : null,
      bottom: below ? null : size.height - union!.top + 16,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: room),
        child: Card(
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tourStep.title,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              // `Flexible` + Scrollen NUR für den Text: Zähler und
              // Knopfzeile bleiben immer sichtbar, was auch immer die
              // Systemschrift mit der Länge anstellt.
              Flexible(
                child: SingleChildScrollView(child: Text(tourStep.text)),
              ),
              const SizedBox(height: 12),
              // **Zähler auf eigener Zeile.** In einer Reihe mit beiden
              // Knöpfen lief die Zeile auf einem 412-dp-Schirm um 81 px
              // über — nachgemessen, nicht geschätzt. Deutsche
              // Beschriftungen sind lang, und „Überspringen" plus
              // „Los geht's" plus Zähler passen nebeneinander auf kein
              // Telefon.
              Text('${step + 1} von ${kMapTourSteps.length}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).hintColor)),
              const SizedBox(height: 4),
              // `Wrap` und keine `Row`: „Überspringen" neben „Los
              // geht's" ist selbst auf einem 412-dp-Schirm knapp
              // (nachgemessen: 50 px Überlauf), und bei großer
              // Systemschrift wird daraus überall einer. Passen sie
              // nicht nebeneinander, rutscht der zweite eine Zeile
              // tiefer — statt dass jemand einen abgeschnittenen Knopf
              // vor sich hat.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  // „Überspringen" steht in jedem Schritt AUSSER dem
                  // letzten: Wer aussteigen will, soll nicht erst zu Ende
                  // geführt werden — im letzten Schritt gibt es aber
                  // nichts mehr zu überspringen. Die beiden Knöpfe taten
                  // dort buchstäblich dasselbe (`next()` ruft im letzten
                  // Schritt selbst `finish()`), der Platz stand also leer.
                  //
                  // Er trägt jetzt den Weg, den der Kopfkommentar dieser
                  // Datei seit 1.108.0 versprochen hat: Drei der sieben
                  // nicht erratbaren Dinge liegen nicht auf diesem Schirm,
                  // und ohne diesen Knopf sagt ihnen niemand, wo sie
                  // stehen.
                  if (last)
                    TextButton(
                      onPressed: () => _openGuide(context),
                      child: const Text('Kurzanleitung'),
                    )
                  else
                    TextButton(
                      onPressed: () =>
                          ref.read(mapTourProvider.notifier).finish(),
                      child: const Text('Überspringen'),
                    ),
                  FilledButton(
                    onPressed: () => ref.read(mapTourProvider.notifier).next(),
                    child: Text(last ? 'Los geht\'s' : 'Weiter'),
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// Die Abdunkelung mit Löchern.
///
/// Öffentlich, damit ein Test die Löcher gegen die ECHTEN Maße der
/// Knöpfe halten kann: Die Spalte steckt in einem
/// `FittedBox(scaleDown)`, ihre Größe hängt also an der Bildschirmhöhe.
/// Ein Loch aus festen Zahlen säße auf jedem zweiten Gerät daneben, und
/// das sähe man keinem Diff an.
class SpotlightPainter extends CustomPainter {
  const SpotlightPainter({required this.holes});

  /// Die freigestellten Rechtecke in Bildschirmkoordinaten.

  final List<Rect> holes;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    // `saveLayer` ist Pflicht: `BlendMode.clear` wirkt sonst auf alles,
    // was schon auf der Leinwand steht — also auf die Karte darunter.
    canvas.saveLayer(area, Paint());
    canvas.drawRect(area, Paint()..color = AppColors.warmBrown.withValues(alpha: 0.72));
    final cut = Paint()..blendMode = BlendMode.clear;
    for (final hole in holes) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(hole.inflate(8), const Radius.circular(18)),
        cut,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SpotlightPainter old) =>
      !_MapTourOverlayState._sameRects(old.holes, holes);
}
