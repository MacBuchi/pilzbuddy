// Die Saisonkurven: Auflösung über die Artenliste, die beiden
// Qualitätsschwellen und die Gipfelbestimmung.
//
// Der Teil, der hier NICHT geprüft werden kann, ist die Rechnung selbst —
// die liegt in `tool/season_curves.py` und hat dort ihren eigenen,
// netzfreien Selbsttest gegen die Zahlen aus `docs/pilzampel-konzept.md`.
// Hier geht es um das, was die App daraus macht.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
import 'package:pilzbuddy/core/season_curves.dart';
import 'package:pilzbuddy/core/season_curves.g.dart';

SeasonCurve curve(List<int> months,
        {int observations = 5000, int peakSupport = 500}) =>
    SeasonCurve(
      sci: 'Testus fungus',
      taxonKey: 1,
      isGenus: false,
      observations: observations,
      peakSupport: peakSupport,
      months: months,
      raw: months,
    );

/// Ein Jahresgang mit einem Gipfel in den genannten Monaten (1 = Januar).
List<int> peakingIn(List<int> monthNumbers) => [
      for (var month = 1; month <= 12; month++)
        monthNumbers.contains(month) ? 100 : 10,
    ];

void main() {
  group('Gipfelbestimmung', () {
    test('Ein einzelner Gipfelmonat', () {
      expect(curve(peakingIn([5])).peakLabel, 'Mai');
      expect(curve(peakingIn([5])).peakMonths, [4]);
    });

    test('Zusammenhängende Monate werden zusammengefasst', () {
      expect(curve(peakingIn([8, 9])).peakLabel, 'August bis September');
    });

    test('Der Gipfel darf über den Jahreswechsel laufen', () {
      // Der Austernseitling ist der Grund für diese Zeile: Sein Gipfel
      // liegt im Dezember und Januar. Eine Rechnung, die bei Index 11
      // aufhört, behauptet, seine Zeit sei der Dezember — und verliert
      // den stärkeren Nachbarmonat.
      final oyster = curve(peakingIn([12, 1]));
      expect(oyster.peakMonths, [11, 0]);
      expect(oyster.peakLabel, 'Dezember bis Januar');
    });

    test('Bei zwei getrennten Gipfeln gewinnt der höhere, nicht der frühere',
        () {
      // Ohne diese Regel gewinnt der Januar-Ausläufer, nur weil er im
      // Kalender vorn steht.
      final months = List.filled(12, 0);
      months[0] = 85; // Januar, knapp über der 80-%-Schwelle
      months[9] = 100; // Oktober, der eigentliche Gipfel
      expect(curve(months).peakMonths, [9]);
      expect(curve(months).peakLabel, 'Oktober');
    });

    test('Eine flache Kurve nennt keinen Gipfel', () {
      final flat = curve(List.filled(12, 90));
      expect(flat.isFlat, isTrue);
      expect(flat.peakLabel, isNull);
    });

    test('Flach ist nicht dasselbe wie leer', () {
      // Beide liefern kein Etikett, aber das UI muss sie unterscheiden
      // können: „ganzjährig gemeldet" ist eine Aussage, „keine Daten"
      // nicht.
      expect(curve(List.filled(12, 0)).isFlat, isFalse);
      expect(curve(List.filled(12, 0)).peakLabel, isNull);
    });
  });

  group('Qualitätsschwellen', () {
    test('Zu wenige Beobachtungen ⇒ keine Kurve', () {
      expect(curve(peakingIn([9]), observations: kMinObservations - 1).isReliable,
          isFalse);
      expect(curve(peakingIn([9]), observations: kMinObservations).isReliable,
          isTrue);
    });

    test('Ein schwach gestützter Gipfel ⇒ keine Kurve, trotz vieler Funde',
        () {
      // Der Fall, den die Gesamtzahl allein nicht fängt: 5000 Meldungen
      // im Jahr, aber der Gipfelmonat trägt davon nur zwölf. Die
      // Effort-Korrektur hebt dünne Wintermonate an — ohne diese
      // Schwelle stünde da ein voller Balken auf zwölf Meldungen.
      final weak = curve(peakingIn([12]), observations: 5000, peakSupport: 12);
      expect(weak.observations, greaterThan(kMinObservations));
      expect(weak.isReliable, isFalse);
    });
  });

  group('Nachschlagen', () {
    test('Eine bekannte Art findet ihre Kurve', () {
      final porcini = seasonCurveFor('Steinpilz');
      expect(porcini, isNotNull);
      expect(porcini!.sci, 'Boletus edulis');
      // August und September — die Zahlen aus docs/pilzampel-konzept.md.
      expect(porcini.peakLabel, 'August bis September');
    });

    test('Ein Zweitname erbt die Kurve seiner Hauptbezeichnung', () {
      // „Totentrompete" wird als „Herbsttrompete" gespeichert; wer den
      // Spot unter dem anderen Namen angelegt hat, muss dieselbe Kurve
      // sehen.
      expect(seasonCurveFor('Totentrompete')?.sci,
          seasonCurveFor('Herbsttrompete')?.sci);
      expect(seasonCurveFor('Marone')?.sci, 'Imleria badia');
    });

    test('Groß- und Kleinschreibung spielt keine Rolle', () {
      expect(seasonCurveFor('steinpilz')?.sci, 'Boletus edulis');
    });

    test('Freitext-Arten haben keine Kurve', () {
      expect(seasonCurveFor('Omas Geheimpilz'), isNull);
      expect(seasonCurveFor(null), isNull);
      expect(seasonCurveFor('  '), isNull);
    });

    test('Zu dünn belegte Arten kommen nicht durch', () {
      // Der Igelstachelbart steht mit 94 Beobachtungen in der Tabelle —
      // gebaut, aber bewusst nicht angezeigt.
      expect(kSeasonCurves['Igelstachelbart'], isNotNull);
      expect(seasonCurveFor('Igelstachelbart'), isNull);
    });
  });

  group('Die generierte Tabelle', () {
    test('Jede Kurve gehört zu einer bekannten Art', () {
      final known = {for (final s in kBekannteArten) s.name};
      for (final name in kSeasonCurves.keys) {
        expect(known, contains(name),
            reason: '$name hat eine Kurve, steht aber nicht in der Artenliste');
      }
    });

    test('Jede Art mit wissenschaftlichem Namen hat eine Kurve', () {
      // Wer `sci` einträgt, aber das Skript nicht laufen lässt, merkt es
      // sonst erst, wenn jemand den Spot öffnet.
      for (final species in kBekannteArten) {
        if (species.sci == null) continue;
        expect(kSeasonCurves, contains(species.name),
            reason: '${species.name} hat `sci`, aber keine Kurve — '
                'tool/season_curves.py neu laufen lassen');
        expect(kSeasonCurves[species.name]!.sci, species.sci,
            reason: '${species.name}: Kurve und Artenliste nennen '
                'verschiedene wissenschaftliche Namen');
      }
    });

    test('Zweitnamen tragen keinen eigenen wissenschaftlichen Namen', () {
      // Sonst käme dieselbe Art zweimal in der Tabelle an, und das Skript
      // fragte GBIF doppelt.
      for (final species in kBekannteArten) {
        if (species.sameAs == null) continue;
        expect(species.sci, isNull,
            reason: '${species.name} ist ein Zweitname von '
                '${species.sameAs} und erbt dessen Kurve');
      }
    });

    test('Jede Kurve hat zwölf Monate und ein Maximum von 100', () {
      for (final entry in kSeasonCurves.entries) {
        expect(entry.value.months, hasLength(12), reason: entry.key);
        expect(entry.value.raw, hasLength(12), reason: entry.key);
        expect(entry.value.months.reduce((a, b) => a > b ? a : b), 100,
            reason: '${entry.key}: Kurve ist nicht auf 100 normiert');
      }
    });

    test('Gattungs-Zuordnungen sind als solche markiert', () {
      // „Rotkappe" und „Hallimasch" sind Sammelbegriffe. Die Markierung
      // ist das, woran das UI erkennt, dass es nicht von einer einzelnen
      // Art spricht.
      expect(kSeasonCurves['Rotkappe']!.isGenus, isTrue);
      expect(kSeasonCurves['Hallimasch']!.isGenus, isTrue);
      expect(kSeasonCurves['Steinpilz']!.isGenus, isFalse);
    });
  });
}
