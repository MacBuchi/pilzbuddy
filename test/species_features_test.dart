// Die Bestimmungsmerkmale (#511 Folgeschritt) — die Struktur, nicht die
// Mykologie.
//
// **Was hier NICHT geprüft wird**, und das ist der wichtigste Satz der
// Datei: ob der Gifthäubling wirklich einen glatten Stiel hat. Das steht
// in der Literatur, nicht in Dart, und kein Test der Welt holt es
// heraus. Geprüft wird, was beim Pflegen einer Tabelle schiefgeht — und
// vor allem die REGEL, welche Arten überhaupt Merkmale tragen müssen.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
import 'package:pilzbuddy/core/species_features.dart';
import 'package:pilzbuddy/core/species_lookalikes.dart';

void main() {
  final known = {
    for (final s in kBekannteArten)
      if (!s.isSynonym) s.name
  };

  /// Wer Merkmale tragen MUSS: **JEDE bekannte Art.**
  ///
  /// Bis 1.168.0 war die Pflichtmenge enger — Arten mit einem
  /// Verwechslungspartner plus die giftigen. Die Regel maß am Giftpilz
  /// und nicht am Sammler, und genau daran ist sie gescheitert: Die
  /// vier Reizker sind als Speisepilz eingestuft und hatten keinen
  /// eingetragenen Partner, fielen also durch beide Siebe. Ihre Seite
  /// sagte über den Pilz kein Wort (Betreiber, 2026-09-22: „zu den
  /// Reizkern finde ich gar keine Erkennungsmerkmale"). Betroffen waren
  /// 30 Arten, fast alle Speisepilze — also durchweg das, was jemand
  /// wirklich im Korb hat.
  ///
  /// Eine Art ohne Merkmale ist damit kein Grenzfall mehr, sondern ein
  /// roter Test. Das ist der Preis, und er ist gewollt: Eine Detailseite
  /// ohne eine Zeile über den Pilz ist schlechter als keine Seite.
  final required = known;

  test('die Pflichtmenge ist vollständig beschrieben', () {
    final missing = required.difference(speciesFeatures.keys.toSet());
    expect(missing, isEmpty,
        reason: 'ohne Merkmale: ${(missing.toList()..sort()).join(', ')}');
  });

  test('beschrieben ist nur, was die App kennt', () {
    for (final name in speciesFeatures.keys) {
      expect(known, contains(name), reason: name);
    }
  });

  test('alle sechs Felder sind gefüllt — „trifft nicht zu" wird '
      'ausgeschrieben', () {
    // Ein leeres Feld sähe aus wie eine Lücke. Bei einer Morchel ist
    // „keine Lamellen" die Auskunft, nicht das Fehlen einer.
    for (final entry in speciesFeatures.entries) {
      final f = entry.value;
      for (final (label, value) in [
        ('hut', f.hut),
        ('unterseite', f.unterseite),
        ('stiel', f.stiel),
        ('fleisch', f.fleisch),
        ('geruch', f.geruch),
        ('vorkommen', f.vorkommen),
      ]) {
        expect(value.trim(), isNotEmpty, reason: '${entry.key}: $label');
        expect(value.trim().length, greaterThan(15),
            reason: '${entry.key}: $label ist zu kurz für eine Aussage');
      }
    }
  });

  test('die GESTALT-Felder sind bei keinen zwei Arten wortgleich', () {
    // Der billigste Pflegefehler: eine Zeile kopieren und den Namen
    // vergessen. Bei sechs Feldern über 58 Arten fällt das sonst
    // niemandem auf.
    //
    // **Geprüft werden Hut, Unterseite und Stiel — nicht alle sechs.**
    // Der erste Entwurf nahm alle, und der Test fiel sofort über
    // „Mild, schwach obstig." bei Ziegenlippe und Butterpilz. Zu Recht:
    // Geruch, Fleisch und Vorkommen DÜRFEN sich wiederholen, weil sie
    // sich in der Wirklichkeit wiederholen — zwei Pilze riechen eben
    // beide mild. Eine künstliche Variation hätte den Text schlechter
    // gemacht, nicht die Tabelle besser. Gestalt dagegen ist je Art
    // eigen; zwei gleiche Hutbeschreibungen sind ein Kopierfehler.
    final seen = <String, String>{};
    for (final entry in speciesFeatures.entries) {
      final f = entry.value;
      for (final value in [f.hut, f.unterseite, f.stiel]) {
        final previous = seen[value];
        expect(previous, isNull,
            reason: '${entry.key} und $previous teilen sich wortgleich: '
                '"$value"');
        seen[value] = entry.key;
      }
    }
  });

  test('keine zwei Arten tragen denselben ganzen Satz von Merkmalen', () {
    // Die Ergänzung dazu: Wiederholung in EINEM Feld ist erlaubt, in
    // allen sechs wäre es eine kopierte Art.
    final records = <String>{};
    for (final entry in speciesFeatures.entries) {
      final f = entry.value;
      final key = [f.hut, f.unterseite, f.stiel, f.fleisch, f.geruch,
        f.vorkommen].join('|');
      expect(records.add(key), isTrue, reason: entry.key);
    }
  });

  test('jedes Verwechslungspaar ist von BEIDEN Seiten beschrieben', () {
    // Der eigentliche Zweck der Pflichtmenge: Ein Unterschied lässt sich
    // nur nachlesen, wenn beide Seiten dastehen.
    for (final entry in speciesLookalikes.entries) {
      expect(featuresFor(entry.key), isNotNull, reason: entry.key);
      for (final partner in entry.value) {
        expect(featuresFor(partner.species), isNotNull,
            reason: '${entry.key} → ${partner.species}');
      }
    }
  });

  test('Zweitnamen finden die Merkmale ihrer Hauptbezeichnung', () {
    expect(featuresFor('Marone'), featuresFor('Maronenröhrling'));
    expect(featuresFor('Geheimpilz'), isNull);
    expect(featuresFor(null), isNull);
  });
}
