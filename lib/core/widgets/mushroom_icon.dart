import 'package:flutter/material.dart';

import '../mushroom_species.dart';
import '../app_colors.dart';

/// Stabiler Hash für Strings über App-Neustarts hinweg (String.hashCode
/// ist dafür nicht garantiert) — bestimmt die Icon-Variante eines Spots.
int stableSeed(String input) {
  var hash = 7;
  for (final unit in input.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash;
}

/// Freundlicher kleiner Pilz. Ist eine [group] bekannt, bestimmt sie das
/// Aussehen (Röhrling = braune Kuppel, Pfifferling = gelber Trichter,
/// Wulstling = rot mit Punkten, Bovist = Kugel, Baumpilz = Konsole …) —
/// so erkennt man die Pilzart auf der Karte auf den ersten Blick.
/// Einige bekannte Arten ([species]) bekommen zusätzlich ein eigenes
/// Aussehen (Pfifferling, Herbsttrompete, Reizker, Marone, Hexenröhrlinge,
/// Käppchenmorchel, Morchelbecherling, Böhmische Verpel, Semmelstoppelpilz,
/// Habichtspilz, Krause Glucke, Ziegenbart, Scheidenstreifling). Glucke und
/// Ziegenbart werden ohne Stiel gezeichnet — sie haben keinen.
/// Ohne Gruppe sorgt [seed] für bunte Vielfalt. Der Boden unter dem Pilz
/// zeigt die Herkunft: grün = eigener Spot, blau = von einem Freund.
class MushroomIcon extends StatelessWidget {
  const MushroomIcon({
    super.key,
    required this.seed,
    this.size = 44,
    this.friend = false,
    this.group,
    this.species,
    this.ground = true,
  });

  /// Art-Icon für Listenzeilen. Kein Boden — die Ellipse ist Kartensprache
  /// für Besitz (grün/blau) und in einer Liste bedeutungslos. Der Seed kommt
  /// aus dem Artnamen, damit dieselbe Art in jeder Liste gleich aussieht;
  /// aus der Fund-id gezogen bekämen zwei Steinpilz-Zeilen verschiedene
  /// Brauntöne aus der Röhrlings-Palette. [fallbackSeed] (z. B. die Fund-id)
  /// hält Einträge ohne Art auseinander.
  MushroomIcon.forSpecies(
    String? name, {
    super.key,
    this.size = 28,
    String? fallbackSeed,
  })  : seed = stableSeed(name ?? fallbackSeed ?? ''),
        friend = false,
        group = groupFor(name),
        species = name,
        ground = false;

  final int seed;
  final double size;
  final bool friend;
  final SpeciesGroup? group;

  /// Artname des letzten Funds — schaltet für bekannte Arten die
  /// art-spezifische Form/Farbe frei (Fallback: [group]).
  final String? species;

  /// Boden-Ellipse zeichnen? Auf der Karte ja (zeigt Besitz: grün/blau),
  /// in Porträts wie Avataren nein.
  final bool ground;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _MushroomPainter(
          seed: seed,
          friend: friend,
          group: group,
          species: species,
          ground: ground),
    );
  }
}

enum _CapShape {
  dome,
  cone,
  flat,
  funnel,
  ball,
  shelf,
  chanterelle,
  trumpet,
  semifreeCone, // Käppchenmorchel: kleiner Kegel auf langem Stiel
  thimble, // Böhmische Verpel: Fingerhut-Glocke, hängt am Stielende
  cup, // Morchelbecherling: nach oben offene Schale
  toothed, // Semmelstoppelpilz: welliger Hut mit Stoppeln darunter
  ruffle, // Krause Glucke: krauser Wulst, ohne Stiel
  coral, // Ziegenbart: verzweigte Äste auf gemeinsamem Fuß, ohne Stiel
}

/// Stielzeichnung der Hexenröhrlinge — in echt das Merkmal, an dem man die
/// beiden Arten auseinanderhält.
enum _StemPattern { net, flecks }

class _Style {
  final _CapShape shape;
  final List<Color> capColors;
  final bool whiteDots;
  final bool darkDots; // Morchel-Waben / Schirmling-Schuppen
  final bool rings; // Reizker: konzentrische dunklere Zonen auf dem Hut
  final bool ridges; // Verpel: Längsrunzeln, Scheidenstreifling: Riefenrand
  final bool folds; // Krause Glucke: die krausen Falten im Wulst
  final bool veins; // Becherling: strahlende Adern in der Schale
  final bool poreBand; // Hexenröhrling: rote Poren an der Hutunterkante
  final double stemTop; // obere Stielkante (relativ), für hohe Schirmlinge
  final Color? stemColor; // abweichende Stielfarbe (Pfifferling gelb …)
  final _StemPattern? stemPattern;

  const _Style(this.shape, this.capColors,
      {this.whiteDots = false,
      this.darkDots = false,
      this.rings = false,
      this.ridges = false,
      this.folds = false,
      this.veins = false,
      this.poreBand = false,
      this.stemTop = 0.42,
      this.stemColor,
      this.stemPattern});
}

class _MushroomPainter extends CustomPainter {
  _MushroomPainter({
    required this.seed,
    required this.friend,
    this.group,
    this.species,
    this.ground = true,
  });

  final int seed;
  final bool friend;
  final SpeciesGroup? group;
  final String? species;
  final bool ground;

  /// Art-spezifische Looks für besonders charakteristische Pilze —
  /// Details siehe .claude/skills/pilz-designer. Matcht per Namensteil,
  /// damit auch „Echter Pfifferling" oder „Kiefernreizker" greifen.
  static _Style? _speciesStyleFor(String? name) {
    if (name == null) return null;
    final key = name.toLowerCase();
    if (key.contains('pfifferling')) {
      // Dottergelber Trichter, Hut und Stiel gehen ineinander über.
      return const _Style(_CapShape.chanterelle,
          [Color(0xFFF9A825), Color(0xFFFBC02D)],
          stemColor: Color(0xFFFFD54F));
    }
    if (key.contains('trompete')) {
      // Herbsttrompete: tiefe dunkle Trompete mit ausgestelltem Rand.
      return const _Style(_CapShape.trumpet,
          [Color(0xFF6D5F57), Color(0xFF75655C)],
          stemColor: Color(0xFF8D7F76));
    }
    if (key.contains('reizker')) {
      // Orangene Milchlinge mit konzentrischen Zonen; Farbton je Art.
      final cap = key.contains('lachs')
          ? const Color(0xFFEF8A66) // Lachsreizker: lachsrosa
          : key.contains('fichten')
              ? const Color(0xFFD9702E) // Fichtenreizker: kräftig orange
              : key.contains('kiefern')
                  ? const Color(0xFFC96A2E) // Kiefernreizker: rotbraun-orange
                  : const Color(0xFFE8833A); // Edelreizker: klassisch orange
      return _Style(_CapShape.flat, [cap],
          rings: true, stemColor: const Color(0xFFF8CBA4));
    }
    if (key.contains('marone')) {
      // Marone: kastanienbrauner Hut, gelbliche Röhren/Stiel.
      // „Braunkappe" gehörte früher hierher; sie ist der Riesenträuschling
      // und darf deshalb keinen Röhrlings-Hut mehr bekommen.
      return const _Style(_CapShape.dome,
          [Color(0xFF6B4423), Color(0xFF5D3A21)],
          stemColor: Color(0xFFF5EDCB));
    }
    if (key.contains('hexenröhrling')) {
      // Beide Hexenröhrlinge: olivbrauner Hut über roten Poren, gelber
      // Stiel. Unterschieden werden sie am Stielmuster — genau wie im Wald.
      // Der olive Ton hält sie zugleich vom Steinpilz auseinander; das ist
      // hier die Verwechslung, auf die es ankommt.
      return _Style(_CapShape.dome,
          const [Color(0xFF8D7040), Color(0xFF9A7B4F)],
          poreBand: true,
          stemColor: const Color(0xFFF2C14E),
          stemPattern:
              key.contains('netz') ? _StemPattern.net : _StemPattern.flecks);
    }
    // „becherling" vor „morchel" prüfen: „Morchelbecherling" enthält beides,
    // und die Schale ist die speziellere Form.
    if (key.contains('becherling')) {
      // Morchelbecherling: braune Schale, die offen nach oben steht, mit
      // strahlenden Adern innen und nur einem Stummelfuß darunter.
      return const _Style(_CapShape.cup,
          [Color(0xFFC9A87C), Color(0xFFBE9B6E)],
          veins: true, stemColor: Color(0xFFEFE4CE));
    }
    if (key.contains('verpel')) {
      // Böhmische Verpel: Fingerhut mit Längsrunzeln, hängt frei am oberen
      // Ende eines langen blassen Stiels.
      return const _Style(_CapShape.thimble,
          [Color(0xFF8A6D3B), Color(0xFF7A5F33)],
          ridges: true, stemTop: 0.34, stemColor: Color(0xFFF5EDCB));
    }
    if (key.contains('stoppelpilz')) {
      // Semmelstoppelpilz: semmelfarben — der Name sagt es — und unter dem
      // Hut sitzen Stoppeln statt Lamellen. Das Gruppen-Icon „Lamellenpilz"
      // behauptete beides Gegenteilige: grau und mit Lamellen.
      return const _Style(_CapShape.toothed,
          [Color(0xFFE3B981), Color(0xFFD9A96C), Color(0xFFE8C593)],
          stemColor: Color(0xFFF7EFDC));
    }
    if (key.contains('glucke')) {
      // Krause Glucke: ein krauser, blass gebackener Wulst am Boden —
      // ohne Stiel, weil sie keinen hat.
      return const _Style(_CapShape.ruffle,
          [Color(0xFFEBD9A8), Color(0xFFE0C88F), Color(0xFFF0E3BC)],
          folds: true);
    }
    if (key.contains('ziegenbart')) {
      // Ziegenbart: aufrechte Äste auf gemeinsamem Fuß, ockergelb.
      return const _Style(_CapShape.coral,
          [Color(0xFFE0B355), Color(0xFFD3A247), Color(0xFFE8C778)]);
    }
    if (key.contains('habichtspilz')) {
      // Habichtspilz: derselbe Stoppelhut wie beim Semmelstoppelpilz, aber
      // dunkelbraun und grob geschuppt — daher dieselbe Form, andere Haut.
      return const _Style(_CapShape.toothed,
          [Color(0xFF8A6A45), Color(0xFF77593A)],
          darkDots: true, stemColor: Color(0xFFC9B79B));
    }
    if (key.contains('scheidenstreifling')) {
      // Scheidenstreifling: grauer Wulstling OHNE Hutflocken — die roten
      // Punkte der Gruppe wären hier das falscheste Merkmal überhaupt.
      // Charakteristisch ist stattdessen der geriefte Hutrand.
      return const _Style(_CapShape.dome,
          [Color(0xFF9C9184), Color(0xFF8B8175), Color(0xFFA9A091)],
          ridges: true, stemTop: 0.36, stemColor: Color(0xFFF2ECE0));
    }
    if (key.contains('käppchenmorchel')) {
      // Käppchenmorchel: kleines Wabenkäppchen auf auffällig langem, blassem
      // Stiel — die Speisemorchel ist dagegen fast nur Hut.
      return const _Style(_CapShape.semifreeCone,
          [Color(0xFF7D6552), Color(0xFF6E5949)],
          darkDots: true, stemTop: 0.30, stemColor: Color(0xFFF5EDCB));
    }
    return null;
  }

  static const _fallbackColors = [
    Color(0xFFE53935),
    Color(0xFF795548),
    Color(0xFFEF6C00),
    Color(0xFFC8A165),
    Color(0xFF7E57C2),
    Color(0xFFEC7086),
    Color(0xFF9E9D24),
  ];

  _Style _styleFor(SpeciesGroup? g) {
    switch (g) {
      case SpeciesGroup.roehrlinge:
        return const _Style(_CapShape.dome,
            [Color(0xFF795548), Color(0xFF8D6E63), Color(0xFF5D4037)]);
      case SpeciesGroup.leistlinge:
        return const _Style(_CapShape.funnel,
            [Color(0xFFF9A825), Color(0xFFFBC02D), Color(0xFFF57F17)]);
      case SpeciesGroup.champignons:
        return const _Style(_CapShape.dome,
            [Color(0xFFF0EAD8), Color(0xFFEDE3CE)]);
      case SpeciesGroup.schirmlinge:
        return const _Style(_CapShape.flat,
            [Color(0xFFC8A165), Color(0xFFB78F5C)],
            darkDots: true, stemTop: 0.34);
      case SpeciesGroup.wulstlinge:
        return const _Style(_CapShape.dome,
            [Color(0xFFE53935), Color(0xFFD32F2F), Color(0xFFC62828)],
            whiteDots: true);
      case SpeciesGroup.taeublinge:
        return const _Style(_CapShape.flat, [
          Color(0xFFB53F3F),
          Color(0xFF7E57C2),
          Color(0xFF66A05B),
          Color(0xFFD8A03C),
          Color(0xFFCB6D80),
        ]);
      case SpeciesGroup.morcheln:
        // Hut heller als bei Röhrlingen, damit die Waben-Punkte lesbar sind
        return const _Style(_CapShape.cone,
            [Color(0xFF8D6E63), Color(0xFF7D5F52)],
            darkDots: true);
      case SpeciesGroup.boviste:
        return const _Style(_CapShape.ball, [Color(0xFFF3F1E7)]);
      case SpeciesGroup.baumpilze:
        return const _Style(_CapShape.shelf,
            [Color(0xFFEF6C00), Color(0xFFD18B47), Color(0xFFC77E3D)]);
      case SpeciesGroup.stachelpilze:
        // Rückfall der Gruppe: Stoppelhut in gedeckten Ockertönen. Alle
        // vier heutigen Mitglieder haben einen eigenen Look, das hier
        // greift also nur für später Dazukommende.
        return const _Style(_CapShape.toothed,
            [Color(0xFFD9C39A), Color(0xFFC9B184), Color(0xFFE0CFAA)],
            stemColor: Color(0xFFF3EAD6));
      case SpeciesGroup.sonstige:
        return const _Style(_CapShape.cone,
            [Color(0xFFBCAAA4), Color(0xFFA1887F), Color(0xFF90A4AE)]);
      case null:
        // Unbekannte/eigene Art: bunte Vielfalt aus dem Seed.
        final shape = _CapShape.values[seed ~/ 7 % 3]; // dome/cone/flat
        return _Style(shape, [_fallbackColors[seed % _fallbackColors.length]],
            whiteDots: (seed ~/ 21) % 2 == 0);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    double u(double v) => v * w;
    Offset p(double x, double y) => Offset(u(x), u(y));

    final style = _speciesStyleFor(species) ?? _styleFor(group);
    final capColor = style.capColors[seed % style.capColors.length];
    final hasCheeks = (seed ~/ 42) % 2 == 0;

    final halo = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = u(0.09)
      ..strokeJoin = StrokeJoin.round;
    final outline = Paint()
      ..color = AppColors.barkBrown.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = u(0.025);

    late final Path stemPath;
    final cap = Path();
    // Gesicht: Position hängt von der Form ab
    var faceY = 0.66;

    switch (style.shape) {
      case _CapShape.dome:
      case _CapShape.cone:
      case _CapShape.flat:
      case _CapShape.funnel:
      case _CapShape.chanterelle:
      case _CapShape.trumpet:
      case _CapShape.semifreeCone:
      case _CapShape.thimble:
      case _CapShape.toothed:
        stemPath = Path()
          ..addRRect(RRect.fromLTRBR(u(0.36), u(style.stemTop), u(0.64),
              u(0.96), Radius.circular(u(0.13))));
        switch (style.shape) {
          case _CapShape.dome:
            cap
              ..moveTo(u(0.06), u(0.50))
              ..cubicTo(u(0.06), u(0.10), u(0.94), u(0.10), u(0.94), u(0.50))
              ..quadraticBezierTo(u(0.5), u(0.60), u(0.06), u(0.50))
              ..close();
          case _CapShape.cone:
            cap
              ..moveTo(u(0.10), u(0.52))
              ..quadraticBezierTo(u(0.28), u(0.10), u(0.5), u(0.06))
              ..quadraticBezierTo(u(0.72), u(0.10), u(0.90), u(0.52))
              ..quadraticBezierTo(u(0.5), u(0.62), u(0.10), u(0.52))
              ..close();
          case _CapShape.flat:
            cap
              ..moveTo(u(0.02), u(0.46))
              ..quadraticBezierTo(u(0.14), u(0.18), u(0.5), u(0.16))
              ..quadraticBezierTo(u(0.86), u(0.18), u(0.98), u(0.46))
              ..quadraticBezierTo(u(0.5), u(0.54), u(0.02), u(0.46))
              ..close();
          case _CapShape.funnel:
            // Trichter: oben eingedellt, geschwungener Rand (Leistlinge)
            cap
              ..moveTo(u(0.08), u(0.20))
              ..quadraticBezierTo(u(0.5), u(0.40), u(0.92), u(0.20))
              ..quadraticBezierTo(u(0.94), u(0.44), u(0.70), u(0.52))
              ..quadraticBezierTo(u(0.5), u(0.57), u(0.30), u(0.52))
              ..quadraticBezierTo(u(0.06), u(0.44), u(0.08), u(0.20))
              ..close();
          case _CapShape.chanterelle:
            // Pfifferling: tiefer dottergelber Trichter mit welligem
            // Rand, der weich in den (gelben) Stiel übergeht.
            cap
              ..moveTo(u(0.04), u(0.18))
              ..quadraticBezierTo(u(0.18), u(0.32), u(0.34), u(0.26))
              ..quadraticBezierTo(u(0.5), u(0.38), u(0.66), u(0.26))
              ..quadraticBezierTo(u(0.82), u(0.32), u(0.96), u(0.18))
              ..quadraticBezierTo(u(0.92), u(0.50), u(0.68), u(0.58))
              ..quadraticBezierTo(u(0.5), u(0.63), u(0.32), u(0.58))
              ..quadraticBezierTo(u(0.08), u(0.50), u(0.04), u(0.18))
              ..close();
          case _CapShape.trumpet:
            // Herbsttrompete: schlanke, tiefe Trompete mit ausgestelltem
            // welligem Rand — der ganze Pilz ist ein dunkles Horn.
            cap
              ..moveTo(u(0.14), u(0.10))
              ..quadraticBezierTo(u(0.30), u(0.22), u(0.5), u(0.18))
              ..quadraticBezierTo(u(0.70), u(0.22), u(0.86), u(0.10))
              ..quadraticBezierTo(u(0.86), u(0.42), u(0.64), u(0.54))
              ..quadraticBezierTo(u(0.5), u(0.60), u(0.36), u(0.54))
              ..quadraticBezierTo(u(0.14), u(0.42), u(0.14), u(0.10))
              ..close();
          case _CapShape.semifreeCone:
            // Käppchenmorchel: kleines Käppchen weit oben, unten frei
            // abstehend — der lange Stiel darunter ist das Erkennungsmerkmal.
            cap
              ..moveTo(u(0.22), u(0.36))
              ..quadraticBezierTo(u(0.30), u(0.10), u(0.5), u(0.06))
              ..quadraticBezierTo(u(0.70), u(0.10), u(0.78), u(0.36))
              ..quadraticBezierTo(u(0.5), u(0.46), u(0.22), u(0.36))
              ..close();
          case _CapShape.thimble:
            // Verpel: Fingerhut — höher als breit, gerundete Spitze, der
            // Saum hängt frei über dem Stiel.
            cap
              ..moveTo(u(0.29), u(0.44))
              ..cubicTo(u(0.27), u(0.06), u(0.73), u(0.06), u(0.71), u(0.44))
              ..quadraticBezierTo(u(0.5), u(0.60), u(0.29), u(0.44))
              ..close();
          case _CapShape.toothed:
            // Semmelstoppelpilz: breiter, leicht unregelmäßiger Hut, dessen
            // Unterkante die namensgebenden Stoppeln trägt. Die Zähne
            // stecken im Hut-Pfad selbst — so nehmen Halo, Füllung und
            // Kontur sie ohne Sonderbehandlung mit.
            // Flacher als eine Kuppel und links höher als rechts: der Hut
            // ist in echt niedrig und unregelmäßig gewellt. Gewölbt sähe er
            // aus wie ein Steinpilz mit Zacken.
            cap
              ..moveTo(u(0.03), u(0.42))
              ..cubicTo(u(0.05), u(0.22), u(0.36), u(0.18), u(0.55), u(0.22))
              ..cubicTo(u(0.76), u(0.26), u(0.97), u(0.30), u(0.97), u(0.46));
            const teeth = 8;
            for (var i = 2 * teeth; i >= 0; i--) {
              final t = i / (2 * teeth);
              // Unterkante wie bei den anderen Hüten zur Mitte hin tiefer
              final base = 0.42 + 0.07 * 4 * t * (1 - t) + 0.04 * t;
              cap.lineTo(u(0.03 + t * 0.94), u(i.isEven ? base : base + 0.07));
            }
            cap.close();
          default:
            break;
        }
      case _CapShape.cup:
        // Morchelbecherling: offene Schale auf einem Stummelfuß. Der hintere
        // Rand liegt höher als der vordere, dadurch schaut man hinein.
        stemPath = Path()
          ..addRRect(RRect.fromLTRBR(
              u(0.42), u(0.70), u(0.58), u(0.96), Radius.circular(u(0.07))));
        cap
          ..moveTo(u(0.10), u(0.34))
          ..quadraticBezierTo(u(0.16), u(0.74), u(0.5), u(0.76))
          ..quadraticBezierTo(u(0.84), u(0.74), u(0.90), u(0.34))
          ..quadraticBezierTo(u(0.5), u(0.22), u(0.10), u(0.34))
          ..close();
        // Gesicht auf die Vorderwand, unterhalb der Innenfläche
        faceY = 0.56;
      case _CapShape.ruffle:
        // Krause Glucke: krauser Wulst, der ohne Stiel am Boden sitzt.
        // Ein leerer Pfad ist hier die ganze Umsetzung von „hat keinen
        // Stiel" — Halo, Füllung und Kontur zeichnen dann schlicht nichts.
        stemPath = Path();
        cap
          ..moveTo(u(0.06), u(0.66))
          ..cubicTo(u(0.03), u(0.44), u(0.16), u(0.32), u(0.28), u(0.40))
          ..cubicTo(u(0.28), u(0.20), u(0.50), u(0.16), u(0.52), u(0.34))
          ..cubicTo(u(0.62), u(0.18), u(0.84), u(0.24), u(0.78), u(0.42))
          ..cubicTo(u(0.90), u(0.38), u(0.96), u(0.52), u(0.92), u(0.68))
          // Unterkante bewusst bei 0.87 statt am Boden: die Ellipse darunter
          // zeigt, wem der Spot gehört, und ein bodentiefer Wulst deckt sie zu.
          ..quadraticBezierTo(u(0.88), u(0.86), u(0.50), u(0.87))
          ..quadraticBezierTo(u(0.12), u(0.86), u(0.06), u(0.66))
          ..close();
        faceY = 0.60;
      case _CapShape.coral:
        // Ziegenbart: vier aufrechte Äste auf gemeinsamem Fuß, ebenfalls
        // ohne Stiel. Das Gesicht sitzt unten auf dem Fuß.
        stemPath = Path();
        // Aus mehreren Teilpfaden statt einer Silhouette: Strunk plus fünf
        // Keulen, die einander überlappen. Halo und Kontur umfahren jeden
        // Teilpfad einzeln, und genau die Linien ZWISCHEN den Ästen machen
        // die Koralle aus. Eine einzige geschlossene Kontur — auch mit
        // tiefen Kerben — liest sich immer als Hand.
        cap.addRRect(RRect.fromLTRBR(
            u(0.36), u(0.56), u(0.64), u(0.96), Radius.circular(u(0.12))));
        for (final (tipX, tipY, baseX) in const [
          (0.15, 0.36, 0.42),
          (0.30, 0.22, 0.45),
          (0.50, 0.13, 0.50),
          (0.70, 0.21, 0.55),
          (0.85, 0.35, 0.58),
        ]) {
          const halfW = 0.075;
          // Die Äste enden bei 0.62 — knapp unter der Strunkkante. Reichten
          // sie tiefer, kreuzten sich ihre Konturen quer über dem Gesicht.
          cap
            ..moveTo(u(baseX - halfW), u(0.62))
            ..quadraticBezierTo(
                u(tipX - halfW * 1.4), u(tipY + 0.12), u(tipX), u(tipY))
            ..quadraticBezierTo(u(tipX + halfW * 1.4), u(tipY + 0.12),
                u(baseX + halfW), u(0.62))
            ..close();
        }
        faceY = 0.76;
      case _CapShape.ball:
        // Bovist: große Kugel, Mini-Fuß, Gesicht auf der Kugel
        stemPath = Path()
          ..addRRect(RRect.fromLTRBR(
              u(0.40), u(0.78), u(0.60), u(0.96), Radius.circular(u(0.08))));
        cap.addOval(Rect.fromCircle(center: p(0.5, 0.48), radius: u(0.36)));
        faceY = 0.52;
      case _CapShape.shelf:
        // Baumpilz: Konsole/Fächer an kurzem Sockel, Gesicht auf dem Hut
        stemPath = Path()
          ..addRRect(RRect.fromLTRBR(
              u(0.30), u(0.70), u(0.62), u(0.96), Radius.circular(u(0.10))));
        cap
          ..moveTo(u(0.16), u(0.70))
          ..cubicTo(u(0.10), u(0.22), u(0.96), u(0.16), u(0.94), u(0.52))
          ..quadraticBezierTo(u(0.62), u(0.78), u(0.16), u(0.70))
          ..close();
        faceY = 0.50;
    }

    // Boden-Ellipse zuerst (liegt hinter dem Pilz): grün = eigener Spot,
    // blau = Community/Freund — die Herkunft ist so auf einen Blick klar.
    if (ground) {
      final baseColor =
          friend ? AppColors.friendBlue : AppColors.forestGreen;
      canvas.drawOval(
        Rect.fromCenter(
            center: p(0.5, 0.925), width: u(0.66), height: u(0.15)),
        Paint()..color = baseColor.withValues(alpha: 0.55),
      );
    }

    // Halo → Füllung → Details → Kontur. Die Stiel-Kontur muss VOR die
    // Hut-Füllung: der Stiel reicht bei jeder Form unter den Hut, und eine
    // danach gezogene Kontur läge sichtbar auf dem Hut (#115). Die
    // Hut-Farben sind alle deckend, decken den verborgenen Teil also ab.
    canvas.drawPath(stemPath, halo);
    canvas.drawPath(cap, halo);
    canvas.drawPath(stemPath,
        Paint()..color = style.stemColor ?? AppColors.cream);

    // Stielzeichnung der Hexenröhrlinge: liegt zwischen Füllung und Kontur,
    // damit die Kontur den Rand sauber abschließt.
    if (style.stemPattern != null) {
      canvas.save();
      canvas.clipPath(stemPath);
      final red = const Color(0xFFC62828).withValues(alpha: 0.7);
      switch (style.stemPattern!) {
        case _StemPattern.net:
          final mesh = Paint()
            ..color = red
            ..style = PaintingStyle.stroke
            ..strokeWidth = u(0.016);
          for (var i = -3; i <= 3; i++) {
            final o = i * 0.10;
            canvas.drawLine(p(0.30 + o, 0.38), p(0.62 + o, 0.98), mesh);
            canvas.drawLine(p(0.62 + o, 0.38), p(0.30 + o, 0.98), mesh);
          }
        case _StemPattern.flecks:
          // Tupfen ober- und unterhalb des Gesichts — mittig würden sie
          // mit Augen und Mund um denselben Platz streiten.
          final fleck = Paint()..color = red;
          canvas.drawCircle(p(0.41, 0.50), u(0.026), fleck);
          canvas.drawCircle(p(0.57, 0.47), u(0.023), fleck);
          canvas.drawCircle(p(0.49, 0.56), u(0.020), fleck);
          canvas.drawCircle(p(0.40, 0.86), u(0.024), fleck);
          canvas.drawCircle(p(0.58, 0.82), u(0.022), fleck);
          canvas.drawCircle(p(0.49, 0.93), u(0.019), fleck);
      }
      canvas.restore();
    }

    canvas.drawPath(stemPath, outline);
    canvas.drawPath(cap, Paint()..color = capColor);

    if (style.rings) {
      // Reizker: konzentrische dunklere Zonen auf dem Hut.
      canvas.save();
      canvas.clipPath(cap);
      final ring = Paint()
        ..color = const Color(0xFF9C4A12).withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = u(0.035);
      final ring1 = Path()
        ..moveTo(u(0.10), u(0.40))
        ..quadraticBezierTo(u(0.5), u(0.22), u(0.90), u(0.40));
      final ring2 = Path()
        ..moveTo(u(0.24), u(0.46))
        ..quadraticBezierTo(u(0.5), u(0.33), u(0.76), u(0.46));
      canvas.drawPath(ring1, ring);
      canvas.drawPath(ring2, ring);
      canvas.restore();
    }

    if (style.whiteDots) {
      canvas.save();
      canvas.clipPath(cap);
      final dot = Paint()..color = Colors.white.withValues(alpha: 0.92);
      canvas.drawCircle(p(0.32, 0.26), u(0.055), dot);
      canvas.drawCircle(p(0.58, 0.16), u(0.045), dot);
      canvas.drawCircle(p(0.74, 0.34), u(0.05), dot);
      canvas.drawCircle(p(0.44, 0.40), u(0.035), dot);
      canvas.restore();
    }
    if (style.darkDots) {
      canvas.save();
      canvas.clipPath(cap);
      final dot = Paint()
        ..color = AppColors.faceBrown.withValues(alpha: 0.55);
      if (style.shape == _CapShape.semifreeCone) {
        // Das Käppchen ist deutlich kleiner als ein Morchelkegel — die
        // großen Wabenpositionen lägen zur Hälfte außerhalb und würden
        // weggeclippt, das Käppchen sähe halb leer aus.
        canvas.drawCircle(p(0.38, 0.20), u(0.030), dot);
        canvas.drawCircle(p(0.54, 0.15), u(0.026), dot);
        canvas.drawCircle(p(0.62, 0.28), u(0.030), dot);
        canvas.drawCircle(p(0.44, 0.31), u(0.026), dot);
        canvas.drawCircle(p(0.31, 0.31), u(0.024), dot);
      } else {
        canvas.drawCircle(p(0.34, 0.26), u(0.04), dot);
        canvas.drawCircle(p(0.56, 0.16), u(0.035), dot);
        canvas.drawCircle(p(0.70, 0.32), u(0.04), dot);
        canvas.drawCircle(p(0.46, 0.36), u(0.03), dot);
        canvas.drawCircle(p(0.26, 0.40), u(0.03), dot);
      }
      canvas.restore();
    }

    if (style.ridges) {
      canvas.save();
      canvas.clipPath(cap);
      final ridge = Paint()
        ..color = AppColors.faceBrown.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = u(0.022)
        ..strokeCap = StrokeCap.round;
      if (style.shape == _CapShape.thimble) {
        // Verpel: senkrechte Längsrunzeln über den ganzen Fingerhut. Der
        // Unterschied zur echten Morchel ist genau dieser — Rillen längs
        // statt Waben.
        for (final x in const [0.35, 0.43, 0.51, 0.59, 0.66]) {
          canvas.drawPath(
              Path()
                ..moveTo(u(x), u(0.10))
                ..quadraticBezierTo(u(x - 0.02), u(0.32), u(x), u(0.56)),
              ridge);
        }
      } else {
        // Scheidenstreifling: gerieft ist nur der Hut**rand**. Die Striche
        // laufen strahlend nach außen und enden am Rand, weil der Hut sie
        // wegclippt — auf der Kuppe bleibt es glatt.
        ridge.strokeWidth = u(0.016);
        for (final x in const [
          0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90,
        ]) {
          canvas.drawLine(
              p(0.5 + (x - 0.5) * 0.72, 0.34), p(x, 0.64), ridge);
        }
      }
      canvas.restore();
    }

    if (style.folds) {
      // Krause Glucke: die krausen Falten, die ihr den Namen geben.
      canvas.save();
      canvas.clipPath(cap);
      final fold = Paint()
        ..color = const Color(0xFF8D6E4A).withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = u(0.020)
        ..strokeCap = StrokeCap.round;
      for (final y in const [0.42, 0.58, 0.74]) {
        canvas.drawPath(
            Path()
              ..moveTo(u(0.08), u(y))
              ..quadraticBezierTo(u(0.26), u(y - 0.07), u(0.44), u(y))
              ..quadraticBezierTo(u(0.62), u(y + 0.07), u(0.80), u(y - 0.02))
              ..quadraticBezierTo(u(0.88), u(y - 0.04), u(0.93), u(y)),
            fold);
      }
      canvas.restore();
    }

    if (style.veins) {
      // Becherling: der Blick in die Schale. Dunkle Innenfläche als Ellipse
      // am Rand, darin strahlende Adern.
      final bowl = Rect.fromCenter(
          center: p(0.5, 0.34), width: u(0.80), height: u(0.24));
      canvas.save();
      canvas.clipPath(cap);
      canvas.drawOval(bowl, Paint()..color = const Color(0xFF6D4C41));
      canvas.clipPath(Path()..addOval(bowl));
      final vein = Paint()
        ..color = AppColors.faceBrown.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = u(0.016)
        ..strokeCap = StrokeCap.round;
      for (final (x, y) in const [
        (0.10, 0.34),
        (0.19, 0.25),
        (0.34, 0.21),
        (0.5, 0.20),
        (0.66, 0.21),
        (0.81, 0.25),
        (0.90, 0.34),
        (0.22, 0.43),
        (0.5, 0.48),
        (0.78, 0.43),
      ]) {
        canvas.drawLine(p(0.5, 0.34), p(x, y), vein);
      }
      canvas.restore();
    }

    if (style.poreBand) {
      // Hexenröhrling: rote Poren als Band an der Hutunterkante. Der Strich
      // liegt auf der Unterkante, die äußere Hälfte clippt der Hut weg.
      canvas.save();
      canvas.clipPath(cap);
      canvas.drawPath(
          Path()
            ..moveTo(u(0.06), u(0.50))
            ..quadraticBezierTo(u(0.5), u(0.60), u(0.94), u(0.50)),
          Paint()
            ..color = const Color(0xFFD84315)
            ..style = PaintingStyle.stroke
            ..strokeWidth = u(0.09));
      canvas.restore();
    }

    canvas.drawPath(cap, outline);

    // Gesicht — immer freundlich
    final faceColor = AppColors.faceBrown;
    final face = Paint()..color = faceColor;
    canvas.drawCircle(p(0.44, faceY), u(0.032), face);
    canvas.drawCircle(p(0.56, faceY), u(0.032), face);
    final smile = Path()
      ..moveTo(u(0.43), u(faceY + 0.08))
      ..quadraticBezierTo(
          u(0.5), u(faceY + 0.15), u(0.57), u(faceY + 0.08));
    canvas.drawPath(
        smile,
        Paint()
          ..color = faceColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = u(0.028)
          ..strokeCap = StrokeCap.round);
    if (hasCheeks) {
      final cheek =
          Paint()..color = AppColors.cheekPink.withValues(alpha: 0.9);
      canvas.drawCircle(p(0.385, faceY + 0.06), u(0.028), cheek);
      canvas.drawCircle(p(0.615, faceY + 0.06), u(0.028), cheek);
    }

  }

  @override
  bool shouldRepaint(covariant _MushroomPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.friend != friend ||
      oldDelegate.group != group ||
      oldDelegate.species != species ||
      oldDelegate.ground != ground;
}
