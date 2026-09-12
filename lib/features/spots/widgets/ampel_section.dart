// „Pilzwetter" — die experimentelle Ampel-Vorschau im Spot-Blatt und in
// „Was ist hier?" (Betreiberentscheidung 2026-08-09).
//
// Die UI-Regeln des Konzepts („Ehrlichkeit im UI — nicht verhandelbar")
// gelten hier wörtlich, und `test/flows/ampel_flow_test.dart` wacht
// darüber: Stufen IN WORTEN, nie Prozent; die Ampel nennt Art oder
// Gilde, nie „die Pilze"; sie bewertet BEDINGUNGEN, nicht Vorkommen —
// und das steht im Text, nicht im Kleingedruckten; lieber grau als
// erfunden.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../../../core/season_curves.dart';
import '../../ampel/ampel_model.dart';
import '../../ampel/ampel_providers.dart';
import '../../map/elevation_providers.dart';
import '../../map/rain_data_providers.dart';

class AmpelSection extends ConsumerWidget {
  const AmpelSection({
    super.key,
    required this.lat,
    required this.lon,
    this.species = const [null],
    this.today,
  });

  final double lat;
  final double lon;

  /// Die Arten des Spots, jüngster Fund zuerst — `[null]` in „Was ist
  /// hier?", dann gilt die Gilden-Frage „Steinpilz & Co.".
  ///
  /// Eine LISTE, seit der Hinweis je Art paart: Ein Spot mit
  /// Pfifferling- und Steinpilzfunden hat im Juli und im Oktober etwas
  /// zu sagen, und zwar Verschiedenes.
  final List<String?> species;

  /// Nur für Tests: „heute" für die Saison-Zeile.
  final DateTime? today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(ampelPreviewEnabledProvider)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);

    // Klassen-Tor VOR allem anderen: Für Arten ohne bestätigte Klasse
    // wird nicht einmal gerechnet.
    //
    // **Korrektur am 2026-09-12 zur früheren Begründung.** Hier stand,
    // das Modell sei für Holzbewohner „kategorisch falsch". Gemessen
    // ist das Gegenteil: Hallimasch und Stockschwämmchen gewinnen mit
    // ihrem eigenen Fenster von allen neun Arten am meisten. Sie
    // bleiben grau, weil dieses Fenster keinen Hold-out hat — nicht,
    // weil an ihnen nichts zu rechnen wäre.
    // **Ohne Art gilt jede ausgelieferte Klasse, nicht nur der Herbst**
    // (Betreiber, 2026-09-12). „Was ist hier?" fragt an einem blanken
    // Punkt — dort gibt es keine Art, und die Karte zeigt seit 1.140.0
    // das Maximum aller Klassen. Zeigte das Blatt weiter nur eine,
    // widerspräche es der Fläche, auf die man gerade getippt hat (#279).
    // [label] steht im Satz, [species] schlägt die Saisonkurve nach —
    // und für eine KLASSE ist das bewusst `null`: Eine Kurve hängt an
    // der Art, eine Klasse hat keine. Beides in einem Feld zu führen
    // ginge gut, bis jemand „Steinpilz & Co." nachschlägt und die
    // fehlende Zeile für einen Datenfehler hält.
    final entries = <({String label, String? species, AmpelClass klass})>[];
    for (final s in species) {
      if (s == null) {
        for (final klass in ampelShippedClasses) {
          entries.add((label: klass.name, species: null, klass: klass));
        }
        continue;
      }
      final klass = ampelClassFor(s);
      if (klass != null) {
        entries.add((label: s, species: s, klass: klass));
      }
    }
    if (entries.isEmpty) {
      final names = species.whereType<String>().toList();
      return _line(
        theme,
        icon: Icon(Icons.circle_outlined, size: 14, color: theme.hintColor),
        text: TextSpan(
          text: 'Pilzwetter (experimentell): für '
              '${names.isEmpty ? 'diese Art' : names.join(' und ')} '
              'nicht geprüft — keine Aussage.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      );
    }

    if (!ref.watch(rainCourseEnabledProvider)) {
      return _line(
        theme,
        icon: Icon(Icons.circle_outlined, size: 14, color: theme.hintColor),
        text: TextSpan(
          text: 'Pilzwetter (experimentell): braucht die Wetterdaten '
              'unten.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      );
    }

    // Die Ablesung ist PURE Arithmetik über den bestehenden
    // Wetter-Providern — gerechnet wird erst, wenn alle geantwortet
    // haben (auch „Fehler" ist eine Antwort; daraus wird ein ehrliches
    // Grau, kein Platzhalter). Die Höhe kommt aus dem mitgelieferten
    // Gitter; `null` heißt schlicht „unkorrigiert rechnen" — dieselbe
    // stille Degradation wie beim Gitter selbst.
    //
    // **Regen, Temperatur und Höhe hängen am ORT, nicht an der Art** —
    // sie werden einmal geholt, und nur Glocke und Schwelle
    // unterscheiden die Arten. Mehrere Zeilen kosten deshalb nichts als
    // Arithmetik.
    final at = (lat: lat, lon: lon);
    final course = ref.watch(rainCourseProvider(at));
    final temperature = ref.watch(spotTemperatureProvider(at));
    final spotHeight = ref.watch(elevationAtProvider(at));
    if (course.isLoading || temperature.isLoading || spotHeight.isLoading) {
      return const SizedBox.shrink();
    }

    // **Eine Zeile je Art, beste zuerst.** Bis 1.137.0 stand hier genau
    // eine, für den jüngsten Fund — und seit der Hinweis je Art paart
    // (Klasse günstig UND Saison), könnte das Banner wegen einer Art
    // anschlagen, über die das Blatt darunter kein Wort verliert. Ein
    // Banner, dem sein eigenes Blatt widerspricht, ist schlimmer als
    // keins (#279, eine Ebene tiefer).
    // **NICHT nach Score sortiert.** Scores verschiedener Klassen sind
    // nicht vergleichbar — jede Schwelle ist auf ihre eigene Verteilung
    // kalibriert. Sortiert wird nach der STUFE, und bei Gleichstand
    // bleibt die Reihenfolge der Liste: jüngster Fund zuerst, bzw. die
    // Reihenfolge der ausgelieferten Klassen.
    final readings = [
      for (final entry in entries)
        (
          label: entry.label,
          species: entry.species,
          klass: entry.klass,
          reading: ampelReadingFrom(course.valueOrNull,
              temperature.valueOrNull,
              klass: entry.klass,
              spotHeightM: spotHeight.valueOrNull),
        ),
    ]..sort((a, b) {
        final left = a.reading.level, right = b.reading.level;
        if (left == null || right == null) return 0;
        return right.index.compareTo(left.index);
      });

    // Grau ist eine Aussage über den ORT (keine Regendaten, keine
    // Station) und trifft damit alle Arten gleich — einmal sagen reicht.
    final grau = readings.first.reading;
    if (grau.isGrau) {
      return _line(
        theme,
        icon: Icon(Icons.circle_outlined, size: 14, color: theme.hintColor),
        text: TextSpan(
          text: 'Pilzwetter (experimentell): keine Aussage — '
              '${grau.reason}.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in readings)
          ..._blockFor(theme, entry.label, entry.species, entry.klass,
              entry.reading),
        Padding(
          padding: const EdgeInsets.only(left: 22, top: 2),
          child: Text(
            // Die Konzept-Regel gehört in den TEXT, nicht ins
            // Kleingedruckte — hier ist beides dasselbe. Und die
            // Formel ist nicht von uns: Quelle nennen (Betreiber,
            // 2026-08-15); die volle Zitation samt DOI und
            // Vorbehalten steht auf der Lizenzseite
            // (`map_data_license.dart`). „Unvalidierte Vorschau"
            // stand hier bis 1.91.x — seit dem Placebo-Urteil
            // (#298) wäre das die falsche Bescheidenheit.
            //
            // EINMAL unter allen Zeilen: Der Satz gilt dem Modell, nicht
            // der Art, und unter jeder Zeile wiederholt wäre er Lärm.
            'Bewertet Bedingungen, nicht Vorkommen — Formel nach '
            'einer 10-Jahres-Studie bei Bielefeld (Preprint 2025).',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.hintColor, fontSize: 11),
          ),
        ),
      ],
    );
  }

  /// Stufe und Fakten-Zeile einer Art.
  List<Widget> _blockFor(ThemeData theme, String label, String? species,
      AmpelClass klass, AmpelReading reading) {
    final level = reading.level!;
    final colour = switch (level) {
      // Bewusst kein Rot: „Keine Stufe heißt aussichtslos" (Konzept).
      // „Ungünstig" bleibt der erdige Braunton der Marke — die
      // gewählte Familie färbt nur, was die Karte auch hervorhebt,
      // sonst hieße ein kräftiger Ton hier „schau her" und dort
      // „lohnt nicht".
      AmpelLevel.unguenstig => AppColors.barkBrown,
      AmpelLevel.verhalten => AppColors.ampelMild,
      AmpelLevel.guenstig => AppColors.ampelStrong,
    };
    return [
      _line(
        theme,
        icon: Icon(Icons.circle, size: 14, color: colour),
        text: TextSpan(
          style: theme.textTheme.bodyMedium,
          children: [
            const TextSpan(text: 'Pilzwetter (experimentell): '),
            TextSpan(
              text: ampelLevelWord(level),
              style: TextStyle(fontWeight: FontWeight.w700, color: colour),
            ),
            TextSpan(text: ' für $label'),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 22, top: 2),
        child: Text(
          _components(reading, klass, species),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ),
    ];
  }

  Widget _line(ThemeData theme,
          {required Widget icon, required TextSpan text}) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: icon),
            const SizedBox(width: 8),
            Expanded(child: Text.rich(text)),
          ],
        ),
      );

  /// Die Komponenten als FAKTEN-Zeile — Worte statt Zahlenbrei, aber
  /// mit dem Temperaturmittel, damit die Stufe nachvollziehbar bleibt.
  /// Die Saison steht DANEBEN und rechnet nicht in die Stufe hinein:
  /// Die Validierung hat sie bewusst herausgekürzt, geprüft ist nur der
  /// Wetterbeitrag.
  String _components(
      AmpelReading reading, AmpelClass klass, String? species) {
    final rain = reading.rainFactor!;
    final rainWord = rain >= 0.66
        ? 'gut'
        : rain >= 0.33
            ? 'mäßig'
            : 'zu trocken';
    final mean = reading.tempMeanC!;
    var meanText =
        '${mean.toStringAsFixed(1).replaceAll('.', ',')} °C';
    // Erst ab ~0,3 K (≈ 50 m Differenz) eine Erwähnung wert: Im
    // Flachland ist die Umrechnung eine Nullnummer, und der Satz würde
    // nur Fragen aufwerfen. Die Zahl selbst ist IMMER die korrigierte.
    if ((reading.heightCorrectionK ?? 0).abs() >= 0.3) {
      meanText = '$meanText auf Spothöhe ${reading.spotHeightM} m';
    }
    final tempWord = reading.tempFactor! >= 0.6
        ? 'passt ($meanText)'
        // **Gegen das Fenster der KLASSE, nicht gegen 13 °C.** Sonst
        // stünde beim Pfifferling (17,5 °C) bei 15 °C „zu warm“,
        // während seine Stufe gleichzeitig sagt, es sei zu kühl — die
        // Fakten-Zeile widerspräche der Ampel darüber.
        : mean > klass.optimumC
            ? 'zu warm ($meanText)'
            : 'zu kühl ($meanText)';
    final parts = [
      'Regen ($ampelRainWindow Tage): $rainWord',
      'Temperatur: $tempWord',
    ];
    final curve = seasonCurveFor(species);
    if (curve != null) {
      final month = (today ?? DateTime.now()).month;
      final share = curve.months[month - 1];
      // **Die unterste Stufe hängt an [kSeasonNowThreshold]** — derselben
      // Zahl, mit der der Banner-Nachlauf entscheidet, ob eine Art jetzt
      // überhaupt auftaucht. Vorher endete die Skala bei 40, und
      // zwischen 15 und 40 stand hier „außerhalb der Hauptzeit",
      // während das Banner für dieselbe Art anschlug: zwei Schwellen
      // für dieselbe Frage, und die Anzeige widersprach dem Hinweis.
      final season = share >= 80
          ? 'Hauptzeit'
          : share >= 40
              ? 'Nebenzeit'
              : share >= kSeasonNowThreshold
                  ? 'Randzeit'
                  : 'kaum gemeldet';
      parts.add('Saison: $season');
    }
    return parts.join(' · ');
  }
}
