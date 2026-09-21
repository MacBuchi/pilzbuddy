// Die Einstufung essbar/giftig (#511 Folgeschritt) — über die ganze
// Artenliste nachgerechnet, nicht an drei Beispielen.
//
// **Was ein Test hier leisten kann und was nicht.** Ob „Grünling"
// wirklich giftig ist, steht in der Literatur und nicht in Dart; das
// prüft kein Computer nach. Prüfbar sind die Zusagen DRUMHERUM: dass
// jede bekannte Art eine Einstufung hat, dass Zweitnamen dieselbe
// bekommen, dass die Stufen, bei denen der Name allein in die Irre
// führt, einen Freitext tragen — und dass die tödlichen als tödlich
// dastehen. Genau die Fehler, die beim Pflegen der Tabelle passieren.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
import 'package:pilzbuddy/core/species_edibility.dart';

void main() {
  final known = kBekannteArten.where((s) => !s.isSynonym).toList();

  test('jede bekannte Art hat genau eine Einstufung', () {
    // **Die tragende Zusage.** Eine neue Art ohne Eintrag erschiene
    // sonst stillschweigend ohne Einstufung — und eine fehlende Warnung
    // ist die Fehlerrichtung, die wehtut.
    for (final species in known) {
      expect(speciesEdibility[species.name], isNotNull,
          reason: '${species.name} hat keine Einstufung');
    }
    // Und keine Karteileichen: ein umbenannter Pilz darf keine
    // verwaiste Zeile hinterlassen.
    expect(speciesEdibility.keys.toSet(),
        known.map((s) => s.name).toSet());
  });

  test('Zweitnamen erben die Einstufung ihrer Hauptbezeichnung', () {
    // Sonst hinge die Warnung an der Schreibweise.
    for (final species in kBekannteArten.where((s) => s.isSynonym)) {
      expect(edibilityFor(species.name), speciesEdibility[species.sameAs],
          reason: species.name);
    }
    expect(edibilityFor('Marone')?.level, Edibility.speisepilz);
    expect(edibilityFor('steinpilz')?.level, Edibility.speisepilz);
  });

  test('eine eigene Art bekommt keine Einstufung — und das heißt nicht '
      '„unbedenklich"', () {
    expect(edibilityFor('Geheimpilz'), isNull);
    expect(edibilityFor(null), isNull);
    expect(edibilityFor(''), isNull);
  });

  test('wo die Stufe allein in die Irre führt, steht ein Freitext', () {
    // „Uneinheitlich beurteilt" ohne Begründung wäre keine Auskunft,
    // sondern ein Achselzucken.
    for (final e in speciesEdibility.entries) {
      if (e.value.level != Edibility.umstritten) continue;
      expect(e.value.note, isNotNull, reason: e.key);
    }
    // Dasselbe für die tödlichen, die jahrzehntelang als Speisepilz
    // galten: Wer den Namen kennt, kennt die alte Einstufung.
    // Geprüft wird die SUBSTANZ, nicht ein Wort: Der Freitext muss die
    // frühere Einstufung nennen, sonst liest sich die heutige wie eine
    // Selbstverständlichkeit — und wer den Pilz aus dem Korb seiner
    // Großeltern kennt, erfährt nicht, dass sich etwas geändert hat.
    for (final name in ['Kahler Krempling', 'Frühjahrslorchel', 'Grünling']) {
      expect(speciesEdibility[name]!.note, contains('Speisepilz'),
          reason: '$name muss seine Vorgeschichte nennen');
    }
  });

  test('die tödlich giftigen stehen als tödlich giftig da', () {
    const deadly = [
      'Grüner Knollenblätterpilz',
      'Kegelhütiger Knollenblätterpilz',
      'Frühjahrsknollenblätterpilz',
      'Gifthäubling',
      'Kahler Krempling',
      'Frühjahrslorchel',
      'Spitzgebuckelter Raukopf',
      'Orangefuchsiger Raukopf',
    ];
    for (final name in deadly) {
      expect(speciesEdibility[name]?.level, Edibility.toedlichGiftig,
          reason: name);
    }
  });

  test('nur die giftigen Stufen drängen sich in die Liste', () {
    // Die Zeile im Reiter ist voll; knappen Platz bekommt die
    // Fehlerrichtung, die wehtut — nicht jede Bemerkung.
    expect(Edibility.values.where((l) => l.warnsInList),
        [Edibility.giftig, Edibility.toedlichGiftig]);
    // Und „Speisepilz" ist die einzige Stufe ohne Hervorhebung: Ein
    // grüner Balken wäre eine Freigabe, die die App nicht geben kann.
    expect(Edibility.values.where((l) => !l.isWarning),
        [Edibility.speisepilz]);
  });

  test('jede Stufe trägt eine Beschriftung ohne Prozent und ohne '
      'Versprechen', () {
    for (final level in Edibility.values) {
      expect(level.label, isNotEmpty);
      expect(level.label, isNot(contains('%')));
    }
    // „Gilt als" und nicht „ist": Die Stufe gehört der ART, nicht dem
    // Pilz im Korb — derselbe Vorbehalt steht im Satz darunter.
    expect(Edibility.speisepilz.label, startsWith('Gilt als'));
    expect(kEdibilityDisclaimer, contains('ersetzt keine Bestimmung'));
  });
}
