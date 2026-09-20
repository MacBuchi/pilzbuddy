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
      expect(ampelTemperatureFactor(List.filled(20, 13.0),
              optimumC: ampelOptimumC),
          closeTo(1.0, 1e-10));
      // Symmetrie der Glocke: 8° und 18° sind gleich weit vom Optimum.
      expect(ampelTemperatureFactor(List.filled(20, 8.0),
              optimumC: ampelOptimumC),
          closeTo(0.3678794412, 1e-9));
      expect(ampelTemperatureFactor(List.filled(20, 18.0),
              optimumC: ampelOptimumC),
          closeTo(0.3678794412, 1e-9));
      expect(ampelTemperatureFactor(List.filled(20, 27.0),
              optimumC: ampelOptimumC),
          closeTo(0.0003936690, 1e-9));
      // Fehltage werden übersprungen, nicht als 0 gezählt — sonst
      // fröre jede Messlücke die Ampel ein.
      expect(
          ampelTemperatureFactor(
              [for (var i = 0; i < 5; i++) ...[12.0, null, 14.0, null]],
              optimumC: ampelOptimumC),
          closeTo(1.0, 1e-10));
      expect(ampelTemperatureFactor([10.0, 12.0, 14.0],
              optimumC: ampelOptimumC),
          closeTo(0.9607894392, 1e-9));
      expect(ampelTemperatureFactor(List.filled(20, null),
              optimumC: ampelOptimumC), 0.0);
    });
  });

  test('Score kombiniert — Fixture aus dem Werkzeug', () {
    expect(
        ampelScore([...List.filled(10, 8.0), ...List.filled(16, 0.0)],
            List.filled(20, 11.0), optimumC: ampelOptimumC),
        closeTo(0.8521437890, 1e-9));
  });

  group('Stufen', () {
    test('drei Worte, und die Schwellen gehören der Klasse', () {
      const k = ampelHerbstClass;
      expect(ampelLevelOf(0.0, klass: k), AmpelLevel.unguenstig);
      expect(ampelLevelOf(k.verhaltenAbove, klass: k), AmpelLevel.verhalten);
      expect(ampelLevelOf(k.guenstigAbove, klass: k), AmpelLevel.guenstig);
      expect(ampelLevelOf(1.0, klass: k), AmpelLevel.guenstig);
      // Die Worte sind die des Konzepts — und enthalten kein Prozent.
      for (final level in AmpelLevel.values) {
        expect(ampelLevelWord(level), isNot(contains('%')));
      }
      expect(ampelLevelWord(AmpelLevel.guenstig), 'günstig');
    });

    test('dieselbe Zahl heißt in zwei Klassen Verschiedenes', () {
      // **Das ist der ganze Grund für Klassen.** Eine feste Schwelle
      // gilt für EINE Werteverteilung; unter einem anderen Fenster
      // bedeutet dieselbe Zahl etwas anderes. Gemessen:
      // Der Austernseitling kommt mit 0,5 auf 1,1 % günstige Fundtage,
      // der Steinpilz auf 58,4 % (docs/pilzampel-ampel-vergleich.md).
      //
      // **Die Zahl dazwischen wird aus den Konstanten gerechnet, nicht
      // hingeschrieben.** Bis zur Neukalibrierung vom 2026-09-19 stand
      // hier 0,6 zwischen 0,512 und 0,677; seither liegt der Spalt
      // woanders UND andersherum — der Pfifferling ist jetzt die
      // großzügigere Klasse. Eine feste Zahl prüfte danach nichts mehr,
      // ohne rot zu werden.
<<<<<<< HEAD
      // Nur die Glockenklassen: Die Logit-Klassen rechnen auf der Skala
      // von `s`, und „dieselbe Zahl" gibt es zwischen den Skalen nicht.
      final sorted = [
        for (final k in ampelShippedClasses)
          if (k.logit == null) k
      ]..sort((a, b) => a.guenstigAbove.compareTo(b.guenstigAbove));
=======
      final sorted = [...ampelShippedClasses]
        ..sort((a, b) => a.guenstigAbove.compareTo(b.guenstigAbove));
>>>>>>> origin/main
      final (frueher, spaeter) = (sorted.first, sorted.last);
      expect(frueher.guenstigAbove, lessThan(spaeter.guenstigAbove),
          reason: 'stünden beide gleich, prüfte dieser Test nichts');
      final dazwischen =
          (frueher.guenstigAbove + spaeter.guenstigAbove) / 2;

      expect(ampelLevelOf(dazwischen, klass: frueher),
          AmpelLevel.guenstig,
          reason: '${frueher.name} wird ab ${frueher.guenstigAbove} '
              'günstig');
      expect(ampelLevelOf(dazwischen, klass: spaeter),
          AmpelLevel.verhalten,
          reason: '${spaeter.name} erst ab ${spaeter.guenstigAbove} — '
              'dieselbe Zahl, andere Stufe');
    });
  });

  group('Gruppenauswahl (Chips im Filter)', () {
    test('leer heißt alle, Unbekanntes heißt auch alle', () {
      expect(ampelClassesOf(const {}), ampelShippedClasses,
          reason: 'dieselbe Regel wie bei der Artenauswahl des Filters');
      expect(ampelClassesOf(const {'gibtesnicht'}), ampelShippedClasses,
          reason: 'eine Auswahl, die auf nichts zeigt, ist keine Aussage');
    });

    test('die Reihenfolge kommt aus der Auslieferung, nicht aus der Wahl', () {
      // An ihr hängt die Gleichstandsregel in ampelBestOf: Bei gleicher
      // Stufe gewinnt die frühere Klasse. Käme die Reihenfolge aus der
      // Nutzerauswahl, entschiede die Tippreihenfolge, welche Gruppe im
      // Blatt genannt wird.
      expect(ampelClassesOf(const {'sommer', 'herbst'}),
          const [ampelHerbstClass, ampelSommerClass]);
      expect(ampelClassesOf(const {'cantharellales', 'herbst'}),
          const [ampelHerbstClass, ampelCantharellalesClass]);
      expect(ampelClassesOf(ampelClasses.keys.toSet()), ampelShippedClasses);
    });

    test('jeder Schlüssel findet zu seiner Klasse zurück', () {
      for (final entry in ampelClasses.entries) {
        expect(ampelClassKeyOf(entry.value), entry.key,
            reason: 'sonst stünde ein „?" im Dateinamen der Fläche');
      }
    });

    test('eine abgewählte Gruppe nimmt ihre Stufe mit', () {
      // 17,5 °C bei sattem Regen: im Pfifferling-Fenster (14,5 °C seit
      // 2026-09-20) Glocke exp(-0,36) = 0,70 ≥ 0,669 — günstig. Im
      // Herbstfenster liegt dieselbe Lage bei 0,445 und damit nur bei
      // „verhalten" (Glocke exp(-0,81)).
      const sommertag = (rainFactor: 1.0, meanC: 17.5);
      expect(
          ampelBestOf(
                  rainFactor: sommertag.rainFactor,
                  meanC: sommertag.meanC,
                  classes: ampelShippedClasses)
              .level,
          AmpelLevel.guenstig);
      expect(
          ampelBestOf(
                  rainFactor: sommertag.rainFactor,
                  meanC: sommertag.meanC,
                  classes: ampelShippedClasses)
              .klass,
          ampelSommerClass);
      expect(
          ampelBestOf(
                  rainFactor: sommertag.rainFactor,
                  meanC: sommertag.meanC,
                  classes: const [ampelHerbstClass])
              .level,
          AmpelLevel.verhalten,
          reason: 'wer den Pfifferling abwählt, sieht seinen Tag nicht mehr');
    });

    test('und das gilt in beide Richtungen', () {
      // Umgekehrt: Ein kühler Herbsttag, auf die Sommergruppe eingeengt.
      // 11 °C: Herbstglocke exp(-0,16) = 0,85 ≥ 0,742 — günstig; im
      // Pfifferling-Fenster (14,5 °C) exp(-0,49) = 0,61 < 0,669 — nur
      // „verhalten". (Bis 2026-09-20 stand hier 13 °C; unter 14,5 liegt
      // das für den Pfifferling selbst schon im Günstigen.)
      expect(
          ampelBestOf(rainFactor: 1.0, meanC: 11, classes: ampelShippedClasses)
              .level,
          AmpelLevel.guenstig);
      expect(
          ampelBestOf(
                  rainFactor: 1.0,
                  meanC: 11,
                  classes: const [ampelSommerClass])
              .level,
          AmpelLevel.verhalten);
    });
  });

  group('Logit-Klassen spiegeln tool/ampel_logit_klasse.py', () {
    // Fixtures aus `python3 tool/ampel_logit_klasse.py --fixtures`
    // (2026-09-20), nicht von Hand gerechnet.
    final regen20 = [20.0, ...List.filled(25, 0.0)];
    final m60 = List<double?>.filled(26, 60.0);

    test('der Score, Zahl für Zahl', () {
      final f = ampelRainFactor(regen20);
      expect(
          ampelHolzWinterClass.logit
              .score(rainFactor: f, meanC: 8.0, moistureMean: 60.0),
          closeTo(0.5378604756070783, 1e-9));
      expect(
          ampelCantharellalesClass.logit
              .score(rainFactor: f, meanC: 8.0, moistureMean: 60.0),
          closeTo(1.5311455016768087, 1e-9));
      // Trocken: der Boden 1e-3 vor dem Logarithmus, kein -unendlich.
      expect(
          ampelHolzWinterClass.logit.score(
              rainFactor: ampelRainFactor(List.filled(26, 0.0)),
              meanC: 3.0,
              moistureMean: 90.0),
          closeTo(-0.8652195435044383, 1e-9));
      expect(
          ampelCantharellalesClass.logit
              .score(rainFactor: 1.0, meanC: 13.0, moistureMean: 40.0),
          closeTo(0.9432299999999996, 1e-9));
      expect(ampelMoistureMean(m60), 60.0);
    });

    test('das Feuchtefenster: 26 Tage, vollständig, die jüngsten', () {
      expect(ampelMoistureMean(List<double?>.filled(25, 60)), isNull,
          reason: 'zu kurz');
      expect(
          ampelMoistureMean([...List<double?>.filled(25, 60), null]), isNull,
          reason: 'eine Lücke im Fenster');
      // Ältere Tage vor dem Fenster zählen nicht — die Reihe ist ältester
      // Tag zuerst, das Fenster sind die LETZTEN 26.
      expect(ampelMoistureMean([0.0, ...List<double?>.filled(26, 60)]), 60.0);
    });

    test('ohne Bodenfeuchte zählt eine Logit-Klasse nicht mit', () {
      // Satter Regen bei 13 °C und 60 % nFK: günstig. Ohne Feuchte fällt
      // die Klasse aus der Wahl, statt mit einem Ersatzwert zu rechnen.
      final ohne = ampelBestOf(
          rainFactor: 1.0, meanC: 13, classes: const [ampelHolzWinterClass]);
      expect(ohne.level, AmpelLevel.unguenstig);
      expect(ampelScoreFor(ampelHolzWinterClass, rainFactor: 1.0, meanC: 13),
          isNull);
      final mit = ampelBestOf(
          rainFactor: 1.0,
          meanC: 13,
          classes: const [ampelHolzWinterClass],
          moistureMean: 60);
      expect(mit.level, AmpelLevel.guenstig);
      expect(mit.klass, ampelHolzWinterClass);
    });

    test('die Schwellen liegen auf der Skala von s, nicht auf 0…1', () {
      // Herbsttrompete & Co.: verhalten ab 2,191 — eine Glocke käme da nie
      // hin. Wer die Skalen vergleicht, vergleicht Zentimeter mit Grad.
      expect(ampelCantharellalesClass.verhaltenAbove, greaterThan(1.0));
      expect(ampelLevelOf(2.5, klass: ampelCantharellalesClass),
          AmpelLevel.verhalten);
      expect(ampelLevelOf(3.0, klass: ampelCantharellalesClass),
          AmpelLevel.guenstig);
    });

    test('die Legende nennt beim Logit die Zutaten, nicht ein Fenster', () {
      expect(ampelClassWindowWord(ampelHerbstClass), '13,0 °C');
      expect(ampelClassWindowWord(ampelHolzWinterClass),
          'Regen, Temperatur und Bodenfeuchte');
    });
  });

  group('Klassen-Tor', () {
    test('nur Arten einer bestätigten Klasse bekommen eine Stufe', () {
      expect(ampelClassFor('Steinpilz'), ampelHerbstClass);
      expect(ampelClassFor('Fichtenreizker'), ampelHerbstClass);
      // Der Pfifferling ist Sommerfrüchter und hat als EINZIGE Art ein
      // eigenes, im geografischen Hold-out bestätigtes Fenster.
      expect(ampelClassFor('Pfifferling'), ampelSommerClass,
          reason: 'sonst rechnet die App ihn wieder als Herbstpilz');
      // Holzbewohner bleiben grau — nicht weil an ihnen nichts zu
      // rechnen wäre (sie gewinnen in Stufen am meisten), sondern weil
      // ihr Fenster keinen Hold-out hat.
      expect(ampelClassFor('Hallimasch'), isNull);
      // Seit 1.151.0: die beiden Logit-Klassen — und die Herbsttrompete
      // ist aus „Steinpilz & Co." zu den Leistlingen gezogen.
      expect(ampelClassFor('Austernseitling'), ampelHolzWinterClass);
      expect(ampelClassFor('Judasohr'), ampelHolzWinterClass);
      expect(ampelClassFor('Herbsttrompete'), ampelCantharellalesClass);
      expect(ampelClassFor('Semmelstoppelpilz'), ampelCantharellalesClass);
      // Freitext-Arten kennen wir nicht → grau.
      expect(ampelClassFor('Omas Lieblingspilz'), isNull);
    });

    test('jede gelistete Art zeigt auf eine Klasse, die es gibt', () {
      // Ein Tippfehler im Schlüssel wäre sonst eine stille graue Ampel
      // für eine Art, die eigentlich eine Stufe bekommen soll.
      for (final entry in ampelSpeciesClass.entries) {
        expect(ampelClasses.containsKey(entry.value), isTrue,
            reason: '${entry.key} zeigt auf Klasse „${entry.value}"');
      }
    });

    test('Synonyme laufen über die Hauptbezeichnung', () {
      // „Marone" ist das gebräuchliche Synonym des Maronenröhrlings —
      // die Auflösung übernimmt canonicalSpecies, wie überall.
      expect(ampelClassFor('Marone'), ampelHerbstClass,
          reason: 'sonst hinge die Ampel an der Schreibweise');
    });

    test('ohne Art gilt die Gilden-Frage „Steinpilz & Co."', () {
      expect(ampelValidatedFor(null), isTrue);
      expect(ampelClassFor(null), ampelHerbstClass,
          reason: 'dasselbe Fenster, mit dem auch die Karte rechnet');
    });
  });
}
