// Die Zusagen des Verzeichnisses im Reiter „Pilze", nachgerechnet über
// die ganze Artenliste — nicht an drei Beispielen.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
import 'package:pilzbuddy/core/season_curves.dart';
import 'package:pilzbuddy/features/ampel/ampel_model.dart';
import 'package:pilzbuddy/features/species/species_catalogue.dart';

void main() {
  final known = kBekannteArten.where((s) => !s.isSynonym).toList();

  test('jede bekannte Art steht genau einmal im Verzeichnis', () {
    final names = [
      for (final section in speciesCatalogue(month: 9))
        for (final entry in section.entries) entry.name,
    ];
    expect(names.toSet().length, names.length, reason: 'doppelt: $names');
    expect(names.toSet(), known.map((s) => s.name).toSet());
  });

  test('die Gruppen tragen genau die Mitglieder des Modells', () {
    final sections = speciesCatalogue(month: 9);
    // Reihenfolge wie in `ampelClasses`, danach der Rest.
    expect(sections.map((s) => s.classKey),
        [...ampelClasses.keys, null]);
    for (final section in sections) {
      final expected = section.classKey == null
          ? known
              .where((s) => ampelClassFor(s.name) == null)
              .map((s) => s.name)
              .toSet()
          : {
              for (final e in ampelSpeciesClass.entries)
                if (e.value == section.classKey) e.key,
            };
      expect(section.entries.map((e) => e.name).toSet(), expected,
          reason: section.title);
      for (final entry in section.entries) {
        expect(entry.evidence != null, section.classKey != null,
            reason: '${entry.name}: Belege nur mit Ampel');
      }
    }
    expect(sections.last.title, kCatalogueGreyTitle);
  });

  test('Saison-Hervorhebung und Wortleiter folgen den Kurven', () {
    for (final month in [1, 2, 6, 9, 12]) {
      for (final section in speciesCatalogue(month: month)) {
        for (final entry in section.entries) {
          final curve = seasonCurveFor(entry.name);
          expect(entry.curve, curve, reason: entry.name);
          if (curve == null) {
            expect(entry.share, isNull);
            expect(entry.inSeason, isFalse);
            expect(entry.seasonWord, isNull);
            continue;
          }
          expect(entry.share, curve.months[month - 1]);
          expect(entry.inSeason, speciesInSeason(entry.name, month),
              reason: '${entry.name} im Monat $month');
          expect(entry.seasonWord, seasonShareWord(curve.months[month - 1]));
        }
      }
    }
  });

  test('die Wortleiter kennt vier Stufen, die unterste an der Schwelle', () {
    expect(seasonShareWord(100), 'Hauptzeit');
    expect(seasonShareWord(80), 'Hauptzeit');
    expect(seasonShareWord(79), 'Nebenzeit');
    expect(seasonShareWord(40), 'Nebenzeit');
    expect(seasonShareWord(39), 'Randzeit');
    expect(seasonShareWord(kSeasonNowThreshold), 'Randzeit');
    expect(seasonShareWord(kSeasonNowThreshold - 1), 'kaum gemeldet');
  });
}
