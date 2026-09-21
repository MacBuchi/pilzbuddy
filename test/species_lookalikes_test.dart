// Die Verwechslungspartner (#511 Folgeschritt) — nachgerechnet über die
// ganze Tabelle.
//
// **Was ein Test hier leisten kann.** Ob der Gifthäubling wirklich einen
// glatten Stiel hat, steht in der Literatur und nicht in Dart. Prüfbar
// ist die STRUKTUR — und die trägt hier mehr als üblich, weil eine
// einseitige oder ins Leere zeigende Warnung schlimmer ist als keine.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
import 'package:pilzbuddy/core/species_edibility.dart';
import 'package:pilzbuddy/core/species_lookalikes.dart';

void main() {
  final known = {
    for (final s in kBekannteArten)
      if (!s.isSynonym) s.name
  };

  test('jeder genannte Partner ist eine Art, die die App kennt', () {
    // Ein Verweis ins Leere wäre schlimmer als keiner: Die Seite böte
    // einen Namen an, zu dem es nichts zu lesen gibt.
    for (final entry in speciesLookalikes.entries) {
      expect(known, contains(entry.key), reason: entry.key);
      for (final partner in entry.value) {
        expect(known, contains(partner.species),
            reason: '${entry.key} → ${partner.species}');
      }
    }
  });

  test('die Beziehung ist SYMMETRISCH', () {
    // **Die tragende Zusage dieser Datei.** Wer auf der Seite des
    // Giftpilzes landet, ist oft gerade der, der dort nicht hinwollte —
    // eine Warnung, die nur in eine Richtung steht, findet nur, wer
    // schon weiß, wonach er sucht.
    final missing = <String>[];
    for (final entry in speciesLookalikes.entries) {
      for (final partner in entry.value) {
        final back = speciesLookalikes[partner.species] ?? const [];
        if (!back.any((p) => p.species == entry.key)) {
          missing.add('${partner.species} nennt ${entry.key} nicht');
        }
      }
    }
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('kein Selbstverweis, keine Doppelung, kein leerer Satz', () {
    for (final entry in speciesLookalikes.entries) {
      expect(entry.value, isNotEmpty,
          reason: '${entry.key}: leere Liste statt gar keinem Eintrag');
      final seen = <String>{};
      for (final partner in entry.value) {
        expect(partner.species, isNot(entry.key),
            reason: '${entry.key} verweist auf sich selbst');
        expect(seen.add(partner.species), isTrue,
            reason: '${entry.key} nennt ${partner.species} zweimal');
        expect(partner.difference.trim(), isNotEmpty,
            reason: '${entry.key} → ${partner.species}');
      }
    }
  });

  test('beide Richtungen sagen NICHT dasselbe', () {
    // Der Satz steht je Richtung, weil er je Richtung eine andere Frage
    // beantwortet: „Der Perlpilz rötet" ist beim Perlpilz eine
    // Bestätigung und beim Pantherpilz ein Ausschluss. Wortgleiche Sätze
    // wären ein Hinweis darauf, dass eine Seite nur kopiert wurde.
    for (final entry in speciesLookalikes.entries) {
      for (final partner in entry.value) {
        final back = speciesLookalikes[partner.species]!
            .firstWhere((p) => p.species == entry.key);
        expect(back.difference, isNot(partner.difference),
            reason: '${entry.key} ↔ ${partner.species}');
      }
    }
  });

  test('die tödlichen Verwechslungen stehen drin', () {
    // Eine Stichprobe mit Zähnen: Das sind die Paare, an denen in
    // Mitteleuropa tatsächlich Menschen gestorben sind.
    const deadlyPairs = [
      ('Stockschwämmchen', 'Gifthäubling'),
      ('Samtfußrübling', 'Gifthäubling'),
      ('Speisemorchel', 'Frühjahrslorchel'),
      ('Spitzmorchel', 'Frühjahrslorchel'),
      ('Perlpilz', 'Pantherpilz'),
      ('Wiesenchampignon', 'Grüner Knollenblätterpilz'),
      ('Flaschenstäubling', 'Grüner Knollenblätterpilz'),
      ('Maipilz', 'Frühjahrsknollenblätterpilz'),
    ];
    for (final (edible, dangerous) in deadlyPairs) {
      expect(lookalikesFor(edible).map((p) => p.species), contains(dangerous),
          reason: '$edible muss vor $dangerous warnen');
    }
  });

  test('jede giftige Art mit Partnern nennt mindestens einen Speisepilz',
      () {
    // Die Richtung, die zählt: Auf der Seite eines Giftpilzes steht, mit
    // WELCHEM Speisepilz er verwechselt wird — sonst erklärt die Warnung
    // nicht, warum jemand ihn überhaupt im Korb hätte.
    for (final entry in speciesLookalikes.entries) {
      final level = speciesEdibility[entry.key]!.level;
      if (level != Edibility.giftig && level != Edibility.toedlichGiftig) {
        continue;
      }
      final edible = entry.value.where((p) {
        final other = speciesEdibility[p.species]!.level;
        return other == Edibility.speisepilz || other == Edibility.nurGegart;
      });
      expect(edible, isNotEmpty, reason: entry.key);
    }
  });

  test('Zweitnamen finden die Partner ihrer Hauptbezeichnung', () {
    expect(lookalikesFor('Marone').map((p) => p.species),
        contains('Gallenröhrling'));
    expect(lookalikesFor('Geheimpilz'), isEmpty);
    expect(lookalikesFor(null), isEmpty);
  });
}
