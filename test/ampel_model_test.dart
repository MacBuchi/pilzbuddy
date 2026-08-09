// Der Ampel-Modellkern (Vorschau, 2026-08-09): Zahl für Zahl derselbe
// wie `tool/ampel_validate.py` — sonst validiert das Werkzeug ein
// anderes Modell, als die App rechnet.
//
// Die Fixture-Werte sind AUS DEM WERKZEUG erzeugt (2026-08-09), nicht
// von Hand gerechnet. Neu erzeugen nach jeder Modelländerung:
//   python3 - <<'EOF'
//   import importlib.util
//   spec = importlib.util.spec_from_file_location('av', 'tool/ampel_validate.py')
//   av = importlib.util.module_from_spec(spec); spec.loader.exec_module(av)
//   print(av.rain_factor([20.0]+[0.0]*25))  # usw.
//   EOF
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/ampel/ampel_model.dart';

void main() {
  group('rainFactor spiegelt das Werkzeug', () {
    test('Fixtures aus tool/ampel_validate.py', () {
      // Gleichmäßig 87/26 mm je Tag: exakt die Sättigung.
      expect(ampelRainFactor(List.filled(26, 87 / 26)), closeTo(1.0, 1e-10));
      expect(ampelRainFactor(List.filled(26, 0.0)), 0.0);
      // 20 mm NUR am Vortag gegen 20 mm NUR am ältesten Tag: die
      // Altersgewichtung ist der Unterschied — wer sie umdreht oder
      // weglässt, reißt beide Werte.
      expect(ampelRainFactor([20.0, ...List.filled(25, 0.0)]),
          closeTo(0.4427415922, 1e-9));
      expect(ampelRainFactor([...List.filled(25, 0.0), 20.0]),
          closeTo(0.0170285228, 1e-9));
      // Fehltage zählen als 0, wie im Werkzeug (dort sichern komplette
      // Reihen die Qualität; hier tut es der Adapter davor).
      final gappy = <double?>[
        for (var i = 0; i < 8; i++) ...[5.0, null, 5.0],
        null,
        null,
      ];
      expect(ampelRainFactor(gappy), closeTo(0.9876543210, 1e-9));
    });

    test('leer und zu kurz', () {
      expect(ampelRainFactor(const []), 0.0);
      // Kürzere Reihe: nur die vorhandenen Tage, gleiche Gewichte —
      // dieselbe Rechnung wie im Werkzeug mit kurzer Liste.
      expect(ampelRainFactor([10.0]), greaterThan(0.0));
    });
  });

  group('temperatureFactor spiegelt das Werkzeug', () {
    test('Fixtures aus tool/ampel_validate.py', () {
      expect(ampelTemperatureFactor(List.filled(20, 13.0)),
          closeTo(1.0, 1e-10));
      // Symmetrie der Glocke: 8° und 18° sind gleich weit vom Optimum.
      expect(ampelTemperatureFactor(List.filled(20, 8.0)),
          closeTo(0.3678794412, 1e-9));
      expect(ampelTemperatureFactor(List.filled(20, 18.0)),
          closeTo(0.3678794412, 1e-9));
      expect(ampelTemperatureFactor(List.filled(20, 27.0)),
          closeTo(0.0003936690, 1e-9));
      // Fehltage werden übersprungen, nicht als 0 gezählt — sonst
      // fröre jede Messlücke die Ampel ein.
      expect(
          ampelTemperatureFactor(
              [for (var i = 0; i < 5; i++) ...[12.0, null, 14.0, null]]),
          closeTo(1.0, 1e-10));
      expect(ampelTemperatureFactor([10.0, 12.0, 14.0]),
          closeTo(0.9607894392, 1e-9));
      expect(ampelTemperatureFactor(List.filled(20, null)), 0.0);
    });
  });

  test('Score kombiniert — Fixture aus dem Werkzeug', () {
    expect(
        ampelScore([...List.filled(10, 8.0), ...List.filled(16, 0.0)],
            List.filled(20, 11.0)),
        closeTo(0.8521437890, 1e-9));
  });

  group('Stufen', () {
    test('drei Worte, feste Schwellen', () {
      expect(ampelLevelOf(0.0), AmpelLevel.unguenstig);
      expect(ampelLevelOf(ampelVerhaltenAbove), AmpelLevel.verhalten);
      expect(ampelLevelOf(ampelGuenstigAbove), AmpelLevel.guenstig);
      expect(ampelLevelOf(1.0), AmpelLevel.guenstig);
      // Die Worte sind die des Konzepts — und enthalten kein Prozent.
      for (final level in AmpelLevel.values) {
        expect(ampelLevelWord(level), isNot(contains('%')));
      }
      expect(ampelLevelWord(AmpelLevel.guenstig), 'günstig');
    });
  });

  group('Gilden-Tor', () {
    test('nur die sechs validierten Arten bekommen eine Stufe', () {
      expect(ampelValidatedFor('Steinpilz'), isTrue);
      expect(ampelValidatedFor('Fichtenreizker'), isTrue);
      // Holzbewohner: das Modell ist für sie KATEGORISCH falsch —
      // Konzept, Artenklassifikation. Grau, nicht gerechnet.
      expect(ampelValidatedFor('Hallimasch'), isFalse);
      expect(ampelValidatedFor('Austernseitling'), isFalse);
      // Freitext-Arten kennen wir nicht → grau.
      expect(ampelValidatedFor('Omas Lieblingspilz'), isFalse);
    });

    test('Synonyme laufen über die Hauptbezeichnung', () {
      // „Marone" ist das gebräuchliche Synonym des Maronenröhrlings —
      // die Auflösung übernimmt canonicalSpecies, wie überall.
      expect(ampelValidatedFor('Marone'), isTrue,
          reason: 'sonst hinge die Ampel an der Schreibweise');
    });

    test('ohne Art gilt die Gilden-Frage „Steinpilz & Co."', () {
      expect(ampelValidatedFor(null), isTrue);
    });
  });
}
