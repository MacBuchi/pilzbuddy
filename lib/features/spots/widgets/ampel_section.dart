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
    this.species,
    this.today,
  });

  final double lat;
  final double lon;

  /// Die Art des Spots — `null` in „Was ist hier?", dann gilt die
  /// Gilden-Frage „Steinpilz & Co.".
  final String? species;

  /// Nur für Tests: „heute" für die Saison-Zeile.
  final DateTime? today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(ampelPreviewEnabledProvider)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);

    // Gilden-Tor VOR allem anderen: Für eine ungeprüfte Art wird nicht
    // einmal gerechnet — das Modell ist für Holzbewohner kategorisch
    // falsch, nicht bloß ungenau.
    if (!ampelValidatedFor(species)) {
      return _line(
        theme,
        icon: Icon(Icons.circle_outlined, size: 14, color: theme.hintColor),
        text: TextSpan(
          text: 'Pilzwetter (experimentell): für $species nicht geprüft '
              '— keine Aussage.',
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
    final at = (lat: lat, lon: lon);
    final course = ref.watch(rainCourseProvider(at));
    final temperature = ref.watch(spotTemperatureProvider(at));
    final spotHeight = ref.watch(elevationAtProvider(at));
    if (course.isLoading || temperature.isLoading || spotHeight.isLoading) {
      return const SizedBox.shrink();
    }
    final reading = ampelReadingFrom(
        course.valueOrNull, temperature.valueOrNull,
        spotHeightM: spotHeight.valueOrNull);

    if (reading.isGrau) {
      return _line(
        theme,
        icon: Icon(Icons.circle_outlined, size: 14, color: theme.hintColor),
        text: TextSpan(
          text: 'Pilzwetter (experimentell): keine Aussage — '
              '${reading.reason}.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      );
    }

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
    final label = species ?? 'Steinpilz & Co.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line(
          theme,
          icon: Icon(Icons.circle, size: 14, color: colour),
          text: TextSpan(
            style: theme.textTheme.bodyMedium,
            children: [
              const TextSpan(text: 'Pilzwetter (experimentell): '),
              TextSpan(
                text: ampelLevelWord(level),
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: colour),
              ),
              TextSpan(text: ' für $label'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 22, top: 2),
          child: Text(
            _components(reading),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.hintColor),
          ),
        ),
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
            'Bewertet Bedingungen, nicht Vorkommen — Formel nach '
            'einer 10-Jahres-Studie bei Bielefeld (Preprint 2025).',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.hintColor, fontSize: 11),
          ),
        ),
      ],
    );
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
  String _components(AmpelReading reading) {
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
        : mean > ampelOptimumC
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
      parts.add('Saison: ${share >= 80 ? 'Hauptzeit' : share >= 40 ? 'Nebenzeit' : 'außerhalb der Hauptzeit'}');
    }
    return parts.join(' · ');
  }
}
