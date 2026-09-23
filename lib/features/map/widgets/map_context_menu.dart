// Das Kontextmenü am langen Tipp auf die Karte (#483).
//
// **Warum der lange Tipp jetzt wieder ab Werk an ist.** Er hatte schon
// eine Bedeutung — er sprang auf die gedrückte Stelle und zoomte auf 16
// — und stand seit #210 AUS, weil er zu leicht versehentlich auslöste:
// „ein Fehlgriff aus der Übersicht warf einen woanders hin". Entschärfen
// ließ er sich nicht, keine der beiden Karten-Bibliotheken lässt
// Haltedauer oder Toleranz einstellen.
//
// Ein Menü ist genau die Entschärfung, die damals fehlte. Ein
// versehentliches Menü wischt man weg; ein versehentlicher Kamerasprung
// kostet die Orientierung. Der Sprung überlebt als DRITTER Eintrag — und
// wird damit vom Unfall zur Wahl. Der Schalter im Profil entfällt.
//
// **Die Form: auffächernde Chips** (Betreiber-Entwurf). Pillen mit
// Symbol vorn und kurzem Text dahinter, nicht nackte Punkte: Für „Was
// ist hier?" gibt es kein selbsterklärendes Symbol, und ein Menü, das
// man raten muss, ist keins.
//
// **Der Text bleibt waagerecht.** Sie steigen versetzt auf statt sich um
// den Punkt zu drehen — gedrehter Text ist in keiner Lage lesbar, und
// eine schräge Pille hat keine rechteckige Trefferfläche mehr.
//
// **Die Richtung folgt dem Platz, nicht einer Konstanten.** Auf einer
// bildschirmfüllenden Karte ist der Rand der Normalfall; ein fester
// Fächer überragte ihn dort. Siehe [MapContextMenuLayout] — die
// Geometrie ist rein und deshalb prüfbar, das Widget zeichnet nur.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'new_spot_style.dart';

import '../../../core/app_colors.dart';

/// Was im Menü gewählt wurde.
///
/// Das Menü entscheidet nichts und öffnet nichts: Es gibt zurück, was
/// gewählt wurde, der Karten-Screen führt es aus — dieselbe Regel wie
/// beim Ebenen-Blatt.
enum MapContextAction {
  /// Einen Spot an der gedrückten Stelle anlegen (#513).
  ///
  /// **Zuerst, weil die Reihenfolge nach Nähe zum Finger geht.** Der
  /// Wunsch kam aus dem Feld: Wer lange auf eine Stelle drückt, will
  /// dort oft einen Spot. Bis 1.177.0 führte der einzige Weg dahin über
  /// das Fadenkreuz in der Bildmitte — man musste die Karte erst
  /// verschieben, bis die Stelle in der Mitte lag.
  addSpot,

  /// Wetter, Pilzampel und Waldtyp an dieser Stelle (#245).
  whatIsHere,

  /// An eine Navi-App übergeben (#367) — wie am Spot.
  navigate,

  /// Die alte Bedeutung des langen Tipps: hierhin und heranzoomen.
  zoomHere,
}

/// Höhe und Abstand einer Chip-Zeile.
///
/// 44 ist die Trefferfläche der Werkzeugleiste und „die eine Zahl, an
/// der nicht gespart wird" — die App wird im Gehen bedient. Ein
/// aufgefächertes Menü darf davon nichts abziehen, nur weil es hübsch
/// aussieht.
const kContextChipHeight = 44.0;
const kContextChipGap = 10.0;

/// Wie weit der Bogen seitlich ausholt, gemessen vom obersten Chip.
///
/// **Ein Bogen, keine schräge Gerade** (Betreiber, #513). Die Chips
/// steigen weiter in festen Stufen — das ist es, was ihr Überlappen
/// verhindert —, aber ihr seitlicher Versatz folgt einem Viertelkreis
/// statt einer Geraden.
///
/// **Ein echter Fächer um den Punkt geht nicht**, und das ist gemessen,
/// nicht vermutet: Chips sind Pillen von rund 190 Punkten Breite. Auf
/// einem Kreis mit genug Radius, dass sich zwei Chips vertikal nicht
/// berühren (~190), läge der unterste fast 200 Punkte seitlich, plus
/// seine eigene Breite — auf keinem Telefon im Bild. Der Bogen ist
/// deshalb flach, und die Rundung liegt in der Verteilung.
const kContextChipArc = 44.0;

/// Abstand des untersten Chips zur gedrückten Stelle — so viel, dass
/// Finger und Menü sich nicht überdecken.
const kContextMenuLift = 26.0;

/// Wohin das Menü aufklappt und wo seine Chips liegen — rein gerechnet.
///
/// Eigene Klasse, weil die Randfälle das Eigentliche sind: Auf einer
/// bildschirmfüllenden Karte drückt man ständig in Randnähe, und ein
/// Menü, das dort hinausragt, ist genau dann kaputt, wenn man es
/// braucht.
class MapContextMenuLayout {
  const MapContextMenuLayout({
    required this.origin,
    required this.screen,
    required this.count,
    this.chipWidth = 190,
  });

  /// Die gedrückte Stelle (global).
  final Offset origin;
  final Size screen;
  final int count;

  /// Die angenommene Breite der breitesten Pille. Grob, und das reicht:
  /// Sie entscheidet nur, ob nach links oder rechts geklappt wird.
  final double chipWidth;

  double get _stackHeight =>
      count * kContextChipHeight + (count - 1) * kContextChipGap;

  /// Klappt das Menü nach OBEN? Sonst nach unten.
  ///
  /// Nach oben ist die Vorgabe — der Finger verdeckt, was darunter
  /// liegt. Nur wenn oben kein Platz ist, geht es nach unten.
  bool get opensUpward =>
      origin.dy - kContextMenuLift - _stackHeight >= 0;

  /// Fächert es nach RECHTS? Sonst nach links.
  ///
  /// Nach rechts ist die Vorgabe; wer in der rechten Bildschirmhälfte
  /// drückt, bekommt den Fächer nach links, weil dort der Platz ist.
  bool get fansRight =>
      origin.dx + chipWidth + kContextChipArc <= screen.width;

  /// Der seitliche Versatz von Chip [index] — der Bogen.
  ///
  /// Ein Viertelkreis: Der unterste Chip liegt am Finger, die weiteren
  /// holen aus und laufen nach oben wieder flach aus. Mit einer Geraden
  /// wäre der Zuwachs je Stufe gleich, und genau das sah aus wie eine
  /// schräge Reihe.
  double arcOffset(int index) {
    if (count < 2) return 0;
    final t = index / (count - 1);
    return kContextChipArc * math.sin(t * math.pi / 2);
  }

  /// Die linke obere Ecke von Chip [index] (0 ist der gedrückten Stelle
  /// am nächsten).
  Offset chipTopLeft(int index) {
    // **Die Stufenhöhe bleibt fest.** Sie ist es, die das Überlappen
    // verhindert; ein Bogen, der auch senkrecht rundet, drängt die
    // oberen Chips ineinander.
    final dy = kContextMenuLift + index * (kContextChipHeight + kContextChipGap);
    final top = opensUpward
        ? origin.dy - dy - kContextChipHeight
        : origin.dy + dy;
    final left = fansRight
        ? origin.dx + arcOffset(index)
        : origin.dx - chipWidth - arcOffset(index);
    return Offset(left, top);
  }

  /// Bleibt alles im Bild? Die Zusage, für die es diese Klasse gibt.
  bool get fitsOnScreen {
    for (var i = 0; i < count; i++) {
      final at = chipTopLeft(i);
      if (at.dy < 0 || at.dy + kContextChipHeight > screen.height) return false;
      if (at.dx < 0 || at.dx + chipWidth > screen.width) return false;
    }
    return true;
  }
}

/// Der Schlüssel eines Eintrags. Seit „Neuer Spot" im Menü genauso
/// heißt wie der Knopf unten rechts, trifft `find.text` zwei Widgets.
Key contextMenuEntryKey(MapContextAction action) =>
    ValueKey('context-menu-${action.name}');

/// Ein Eintrag, wie er im Menü steht.
typedef _Entry = ({
  MapContextAction action,
  IconData icon,
  String label,
  /// Hervorgehoben — gefüllt in der Farbe des „Neuer Spot"-Knopfs.
  ///
  /// **Genau einer**, sonst hebt sich nichts mehr ab. Farbe und Name
  /// kommen aus `new_spot_style.dart`, derselben Quelle wie der Knopf
  /// unten rechts — erkennbar dasselbe (Betreiber, #513). Bis 1.192.0
  /// stand hier eine eigene Konstante, und beide sahen verschieden aus.
  bool prominent,
});

const _entries = <_Entry>[
  // Reihenfolge nach Nähe zum Finger: Was man am häufigsten will, liegt
  // am nächsten. „Neuer Spot" ist seit #513 der erste — der Wunsch kam
  // aus dem Feld. „Was ist hier?" ist der Grund, warum man sonst
  // irgendwo hindrückt; „heranzoomen" ist die alte Nebenbedeutung.
  (
    action: MapContextAction.addSpot,
    icon: kNewSpotIcon,
    label: kNewSpotLabel,
    prominent: true,
  ),
  (
    action: MapContextAction.whatIsHere,
    icon: Icons.help_outline,
    // Wortgleich mit der Legende (#245) — ein zweites Wort für dieselbe
    // Sache wäre schlimmer als ein längeres Chip.
    label: 'Was ist hier?',
    prominent: false,
  ),
  (
    action: MapContextAction.navigate,
    icon: Icons.directions_outlined,
    label: 'Navigation',
    prominent: false,
  ),
  (
    action: MapContextAction.zoomHere,
    icon: Icons.zoom_in,
    label: 'Heranzoomen',
    prominent: false,
  ),
];

/// Öffnet das Menü an [at] und gibt zurück, was gewählt wurde — `null`,
/// wenn daneben getippt oder zurück gegangen wurde.
Future<MapContextAction?> showMapContextMenu(
  BuildContext context,
  Offset at,
) {
  return showGeneralDialog<MapContextAction>(
    context: context,
    // Halbdurchsichtig statt schwarz: Man soll sehen, WO man gedrückt
    // hat — das Menü beantwortet eine Frage über genau diese Stelle.
    barrierColor: Colors.black.withValues(alpha: 0.18),
    barrierDismissible: true,
    barrierLabel: 'Menü schließen',
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => _MapContextMenu(origin: at),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
}

class _MapContextMenu extends StatelessWidget {
  const _MapContextMenu({required this.origin});

  final Offset origin;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final layout = MapContextMenuLayout(
      origin: origin,
      screen: screen,
      count: _entries.length,
    );
    return Stack(
      children: [
        // Die gedrückte Stelle bleibt markiert, solange das Menü steht.
        // Ohne sie wäre „Was ist hier?" eine Antwort auf eine Frage, die
        // man nicht mehr sieht.
        Positioned(
          left: origin.dx - 11,
          top: origin.dy - 11,
          child: const IgnorePointer(
            child: Icon(Icons.my_location, size: 22, color: AppColors.forestGreen),
          ),
        ),
        for (final (index, entry) in _entries.indexed)
          Positioned(
            left: layout.chipTopLeft(index).dx,
            top: layout.chipTopLeft(index).dy,
            child: _Chip(
              entry: entry,
              // Gestaffelt: Sie kommen nacheinander heraus, das ist das
              // „Auffächern". Der unterste zuerst — er liegt am Finger.
              delay: Duration(milliseconds: 40 * index),
            ),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.entry, required this.delay});

  final _Entry entry;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.scale(scale: 0.85 + 0.15 * t, alignment: Alignment.centerLeft, child: child),
      ),
      child: Material(
        key: contextMenuEntryKey(entry.action),
        color: entry.prominent
            ? newSpotColors(theme).background
            : theme.colorScheme.surface,
        elevation: 3,
        borderRadius: BorderRadius.circular(kContextChipHeight / 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(kContextChipHeight / 2),
          onTap: () => Navigator.of(context).pop(entry.action),
          child: SizedBox(
            height: kContextChipHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(entry.icon,
                      size: 22,
                      color: entry.prominent
                          ? newSpotColors(theme).foreground
                          : theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(entry.label,
                      style: theme.textTheme.bodyLarge?.copyWith(
                          color: entry.prominent
                              ? newSpotColors(theme).foreground
                              : null,
                          fontWeight:
                              entry.prominent ? FontWeight.w600 : null)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
