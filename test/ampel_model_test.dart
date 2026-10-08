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
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/species_edibility.dart';
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
      // Nur die Glockenklassen: Die Logit-Klassen rechnen auf der Skala
      // von `s`, und „dieselbe Zahl" gibt es zwischen den Skalen nicht.
      final sorted = [
        for (final k in ampelShippedClasses)
          if (k.logit == null) k
      ]..sort((a, b) => a.guenstigAbove.compareTo(b.guenstigAbove));
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
    // (2026-10-08, Holz & Winter seit #676 ohne Feuchte, Herbsttrompete
    // & Co. auf ERA5-Land in m³/m³), nicht von Hand gerechnet.
    final regen20 = [20.0, ...List.filled(25, 0.0)];
    // Ältester Tag zuerst wie die Stationsreihe: 23 kalte Nächte, dann
    // fünf milde — „milder" = 2 − (−1) = +3 °C.
    final mins3 = <double?>[...List.filled(23, -1.0), ...List.filled(5, 2.0)];

    test('der Score, Zahl für Zahl', () {
      final f = ampelRainFactor(regen20);
      expect(ampelMilderOf(mins3), 3.0);
      expect(
          ampelHolzWinterClass.logit.score(
              rainFactor: f, meanC: 8.0, moistureMean: 0.30, milder: 3.0),
          closeTo(0.31311601049493065, 1e-9));
      expect(
          ampelCantharellalesClass.logit.score(
              rainFactor: f, meanC: 8.0, moistureMean: 0.30, milder: 3.0),
          closeTo(2.314944879957129, 1e-9));
      // Trocken: der Boden 1e-3 vor dem Logarithmus, kein -unendlich.
      expect(
          ampelHolzWinterClass.logit.score(
              rainFactor: ampelRainFactor(List.filled(26, 0.0)),
              meanC: 3.0,
              moistureMean: 0.45,
              milder: 3.0),
          closeTo(-0.9043192143197059, 1e-9));
      expect(
          ampelCantharellalesClass.logit.score(
              rainFactor: ampelRainFactor(List.filled(26, 0.0)),
              meanC: 3.0,
              moistureMean: 0.45,
              milder: 3.0),
          closeTo(3.3351300963993076, 1e-9));
      expect(
          ampelCantharellalesClass.logit.score(
              rainFactor: 1.0, meanC: 13.0, moistureMean: 0.20, milder: 0.0),
          closeTo(0.4791404300000006, 1e-9));
      expect(
          ampelHolzWinterClass.logit.score(
              rainFactor: 1.0, meanC: 13.0, moistureMean: 0.20, milder: 0.0),
          closeTo(0.33459399999999984, 1e-9));
      // Kälter zuletzt: −2 °C senkt den Score um 5 × 0,03819.
      expect(
          ampelHolzWinterClass.logit.score(
              rainFactor: f, meanC: 8.0, moistureMean: 0.30, milder: -2.0),
          closeTo(0.12216601049493067, 1e-9));
    });

    test('„milder": 28 Tage, vollständig, die jüngsten fünf gegen den Rest',
        () {
      expect(ampelMilderOf(mins3.sublist(1)), isNull, reason: '27 Tage');
      expect(ampelMilderOf([...mins3.sublist(0, 10), null, ...mins3.sublist(11)]),
          isNull,
          reason: 'eine Lücke im Fenster');
      // Ältere Tage vor dem Fenster zählen nicht — das Fenster sind die
      // LETZTEN 28.
      expect(ampelMilderOf([50.0, 50.0, ...mins3]), 3.0);
      expect(ampelMilderOf(List<double?>.filled(28, 4.0)), 0.0);
      expect(
          ampelMilderOf(
              [...List<double?>.filled(23, -1.0), ...List.filled(5, -3.0)]),
          -2.0,
          reason: 'kälter zuletzt ist negativ');
      // Nur Holz & Winter trägt das Merkmal; die Null der Leistlinge
      // heißt „keine Reihe nötig".
      expect(ampelHolzWinterClass.logit.needsMilder, isTrue);
      expect(ampelCantharellalesClass.logit.needsMilder, isFalse);
      expect(
          ampelHolzWinterClass.logit
              .score(rainFactor: 1.0, meanC: 13.0, moistureMean: 0.20),
          isNull,
          reason: 'ohne Minima kein Score — kein Ersatzwert');
      expect(
          ampelCantharellalesClass.logit
              .score(rainFactor: 1.0, meanC: 13.0, moistureMean: 0.20),
          closeTo(0.4791404300000006, 1e-9));
      // Der Satz in der Zutaten-Zeile.
      expect(ampelMilderWord(2.34),
          'Nächte zuletzt: 2,3 °C milder als in den drei Wochen davor');
      expect(ampelMilderWord(-1.0),
          'Nächte zuletzt: 1,0 °C kälter als in den drei Wochen davor');
      expect(ampelMilderWord(0.04),
          'Nächte zuletzt: wie in den drei Wochen davor');
    });

    test('ohne Minima zählt Holz & Winter nicht mit, die Leistlinge schon',
        () {
      final ohne = ampelBestOf(
          rainFactor: 1.0,
          meanC: 13,
          classes: const [ampelHolzWinterClass],
          moistureMean: 0.30);
      expect(ohne.level, isNull,
          reason: 'keine Antwort ist keine Stufe — die Fläche bleibt '
              'transparent, nicht rot');
      expect(
          ampelScoreFor(ampelHolzWinterClass,
              rainFactor: 1.0, meanC: 13, moistureMean: 0.30),
          isNull);
      expect(
          ampelScoreFor(ampelCantharellalesClass,
              rainFactor: 1.0, meanC: 13, moistureMean: 0.30),
          isNotNull);
    });

    test('ohne Bodenfeuchte zählt eine Logit-Klasse nicht mit, die sie '
        'braucht', () {
      // Ohne Feuchte fällt Herbsttrompete & Co. aus der Wahl, statt mit
      // einem Ersatzwert zu rechnen.
      expect(ampelCantharellalesClass.logit.needsMoisture, isTrue);
      final ohne = ampelBestOf(
          rainFactor: 1.0,
          meanC: 13,
          classes: const [ampelCantharellalesClass]);
      expect(ohne.level, isNull);
      expect(
          ampelScoreFor(ampelCantharellalesClass, rainFactor: 1.0, meanC: 13),
          isNull);
      final mit = ampelBestOf(
          rainFactor: 1.0,
          meanC: 13,
          classes: const [ampelCantharellalesClass],
          moistureMean: 0.30);
      expect(mit.level, isNotNull);
      expect(mit.klass, ampelCantharellalesClass);
    });

    test('Holz & Winter rechnet ohne Bodenfeuchte (#676)', () {
      // Zwei Nullen heißen „keine Reihe nötig" — wie bei „milder". Satter
      // Regen bei 13 °C: günstig, mit oder ohne Feuchte.
      expect(ampelHolzWinterClass.logit.needsMoisture, isFalse);
      final ohne = ampelBestOf(
          rainFactor: 1.0,
          meanC: 13,
          classes: const [ampelHolzWinterClass],
          milder: 0);
      expect(ohne.level, AmpelLevel.guenstig);
      expect(ohne.klass, ampelHolzWinterClass);
      final ohneScore = ampelScoreFor(ampelHolzWinterClass,
          rainFactor: 1.0, meanC: 13, milder: 0);
      expect(ohneScore, isNotNull);
      expect(
          ampelScoreFor(ampelHolzWinterClass,
              rainFactor: 1.0,
              meanC: 13,
              moistureMean: 0.45,
              milder: 0),
          ohneScore,
          reason: 'die Feuchte ändert nichts');
      expect(
          ampelHolzWinterClass.logit
              .score(rainFactor: 1.0, meanC: 13, milder: 0),
          ohneScore);
    });

    test('die Schwellen liegen auf der Skala von s, nicht auf 0…1', () {
      // Herbsttrompete & Co.: verhalten ab 2,652 (seit #676 auf ERA5-Land
      // neu gemessen) — eine Glocke käme da nie hin. Wer die Skalen
      // vergleicht, vergleicht Zentimeter mit Grad.
      expect(ampelCantharellalesClass.verhaltenAbove, greaterThan(1.0));
      expect(ampelLevelOf(2.6, klass: ampelCantharellalesClass),
          AmpelLevel.unguenstig);
      expect(ampelLevelOf(3.0, klass: ampelCantharellalesClass),
          AmpelLevel.verhalten);
      expect(ampelLevelOf(3.4, klass: ampelCantharellalesClass),
          AmpelLevel.guenstig);
    });

    test('die Legende nennt beim Logit die Zutaten, nicht ein Fenster', () {
      expect(ampelClassWindowWord(ampelHerbstClass), '13,0 °C');
      expect(ampelClassWindowWord(ampelHolzWinterClass),
          'Regen, Temperatur und Nächte',
          reason: 'seit #676 ohne Bodenfeuchte — die Legende nennt nur, '
              'was eingeht');
      expect(ampelClassWindowWord(ampelCantharellalesClass),
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

  test('die Ampel gilt nur für Sammelpilze', () {
    // **Betreiber, 2026-09-22: „für giftige / ungenießbare Pilze
    // brauchen wir keine Ampel. Nur Speisepilze kommen in Frage."**
    //
    // Heute stimmt das schon — 16 Arten, alle Speisepilz oder nur
    // gegart. Was fehlte, war der Riegel: Ein Giftpilz in einer
    // Ampel-Gruppe würde eine Vorhersage über etwas treffen, das
    // niemand sammeln soll, und die Günstig-Meldung auf der Karte
    // läse sich als Einladung. Die Gefahr ist real geworden, seit wir
    // Verwechslungspartner ergänzen: Dabei kommen giftige Arten in den
    // Blick, und der Weg von dort in eine Ampel-Gruppe ist eine Zeile.
    for (final entry in ampelSpeciesClass.entries) {
      final level = edibilityFor(entry.key)?.level;
      expect(level, isNotNull, reason: '${entry.key} hat keine Einstufung');
      expect([Edibility.speisepilz, Edibility.nurGegart], contains(level),
          reason: '${entry.key} ist ${level!.label} und gehört damit in '
              'keine Ampel-Gruppe (${entry.value})');
    }
  });

  group('AmpelCellInputs rechnet wie vor #662', () {
    // Die Fassung von 1.222.8, Wort für Wort: Score je Klasse und die
    // Gleichstandsregel. Der Umbau auf vorbereitete Zellzutaten (#662)
    // darf keine einzige Zahl ändern — Gleichheit, nicht closeTo. Einzige
    // Änderung seither: Die Feuchte zählt nur, wo die Klasse sie
    // braucht, und einen Abstand zur Station gibt es nicht mehr (#676).
    double? oldScore(AmpelClass klass,
        {required double rainFactor,
        required double meanC,
        double? moistureMean,
        double? milder}) {
      final logit = klass.logit;
      if (logit == null) {
        return rainFactor * ampelBellOfMean(meanC, optimumC: klass.optimumC!);
      }
      if (logit.needsMoisture && moistureMean == null) return null;
      if (milder == null && logit.needsMilder) return null;
      final logRain = math.log(math.max(rainFactor, ampelLogitRainFloor));
      return logit.rain * logRain +
          logit.temp * meanC +
          logit.temp2 * meanC * meanC +
          logit.moisture * (moistureMean ?? 0) +
          logit.moistureTemp * (moistureMean ?? 0) * meanC +
          logit.milder * (milder ?? 0);
    }

    test('Score, Stufe und Klasse über Zufallszutaten', () {
      final random = math.Random(662);
      final subsets = [
        ampelShippedClasses,
        [for (final c in ampelShippedClasses) if (c.logit != null) c],
        [for (final c in ampelShippedClasses) if (c.logit == null) c],
        ampelShippedClasses.reversed.toList(),
      ];
      for (var n = 0; n < 20000; n++) {
        final rainFactor = random.nextInt(10) == 0
            ? 0.0
            : random.nextDouble() * 1.3;
        final meanC = -5 + random.nextDouble() * 30;
        final moisture =
            random.nextInt(4) == 0 ? null : random.nextDouble() * 0.6;
        final milder =
            random.nextInt(3) == 0 ? null : random.nextDouble() * 6 - 3;
        for (final klass in ampelShippedClasses) {
          expect(
              ampelScoreFor(klass,
                  rainFactor: rainFactor,
                  meanC: meanC,
                  moistureMean: moisture,
                  milder: milder),
              oldScore(klass,
                  rainFactor: rainFactor,
                  meanC: meanC,
                  moistureMean: moisture,
                  milder: milder));
        }
        for (final classes in subsets) {
          AmpelLevel? oldLevel;
          var oldKlass = classes.first;
          for (final klass in classes) {
            final score = oldScore(klass,
                rainFactor: rainFactor,
                meanC: meanC,
                moistureMean: moisture,
                milder: milder);
            if (score == null) continue;
            final level = ampelLevelOf(score, klass: klass);
            if (level.index > (oldLevel?.index ?? -1)) {
              oldLevel = level;
              oldKlass = klass;
            }
          }
          final best = ampelBestOf(
              rainFactor: rainFactor,
              meanC: meanC,
              classes: classes,
              moistureMean: moisture,
              milder: milder);
          expect(best.level, oldLevel);
          expect(best.klass, oldKlass);
          final inputs = AmpelCellInputs(
              rainFactor: rainFactor,
              moistureMean: moisture,
              milder: milder);
          expect(inputs.bestLevel(meanC, classes), oldLevel);
        }
      }
    });
  });
}
