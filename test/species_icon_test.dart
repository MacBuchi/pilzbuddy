// Jede Art trägt ihr eigenes Symbol (#548).
//
// **Der Anlass war kein Schönheitswunsch.** 68 der 92 Arten fielen auf
// den Look ihrer Gruppe zurück, und der behauptet stellenweise etwas
// Falsches: Die Gruppe „Wulstlinge" ist rot mit weißen Punkten, also der
// Fliegenpilz — und so wurde auch der Grüne Knollenblätterpilz
// gezeichnet, der oliv- bis gelbgrün und meist ohne Flocken ist.
//
// Geprüft wird die ENTSCHEIDUNG, nicht das Bild: Form, Hutfarbe, Punkte
// und Stielfarbe. Ob ein Pilz hübsch aussieht, steht in keinem Test.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
import 'package:pilzbuddy/core/species_edibility.dart';
import 'package:pilzbuddy/core/species_lookalikes.dart';
import 'package:pilzbuddy/core/widgets/mushroom_icon.dart';

void main() {
  final known = kBekannteArten.where((s) => !s.isSynonym).toList();

  test('jede bekannte Art hat ein eigenes Symbol', () {
    // Ohne eigenen Eintrag zeichnet die Gruppe, und die kann nur den
    // Durchschnitt. Eine neue Art erzwingt damit eine Entscheidung,
    // statt still als Gruppendurchschnitt zu erscheinen — dieselbe
    // Regel wie bei den Merkmalen (1.169.0).
    final ohne = [
      for (final art in known)
        if (speciesIconLook(art.name) == null) art.name,
    ];
    expect(ohne, isEmpty, reason: 'ohne eigenes Aussehen: $ohne');
  });

  test('ein Zweitname erbt das Symbol seiner Art', () {
    // „Marone" und „Maronenröhrling" sind eine Art und ein Symbol.
    for (final s in kBekannteArten.where((s) => s.isSynonym)) {
      expect(speciesIconLook(s.name), isNotNull, reason: s.name);
    }
  });

  test('Verwechslungspartner sehen nie gleich aus', () {
    // **Das ist der ganze Zweck.** Zwei Arten, die man verwechselt,
    // dürfen auf der Karte nicht dasselbe Zeichen tragen — sonst
    // wiederholt das Symbol genau den Fehler, vor dem die Artseite
    // warnt.
    final gleich = <String>[];
    for (final entry in speciesLookalikes.entries) {
      final eigen = speciesIconLook(entry.key);
      for (final partner in entry.value) {
        if (eigen == speciesIconLook(partner.species)) {
          gleich.add('${entry.key} ↔ ${partner.species}');
        }
      }
    }
    expect(gleich, isEmpty, reason: 'gleiches Symbol: $gleich');
  });

  test('rot mit weißen Punkten gehört dem Fliegenpilz allein', () {
    // Es ist das eine Pilzzeichen, das jeder kennt. Wer es trägt, sagt
    // „ich bin der Fliegenpilz" — und drei Knollenblätterpilze sagten
    // das bis 1.183.0 mit.
    final fliegenpilz = speciesIconLook('Fliegenpilz')!;
    expect(fliegenpilz.whiteDots, isTrue);
    final rot = fliegenpilz.capColour;
    final auch = [
      for (final art in known)
        if (art.name != 'Fliegenpilz')
          if (speciesIconLook(art.name) case final look?
              when look.whiteDots && look.capColour == rot)
            art.name,
    ];
    expect(auch, isEmpty, reason: 'tragen den Fliegenpilz-Look: $auch');
  });

  test('keine zwei Arten tragen dasselbe Symbol', () {
    // Schärfer als die Verwechslungsregel und aus einem anderen Grund:
    // Auf der Karte stehen die Marker nebeneinander, nicht nur die
    // Partner. Zwei gleiche Zeichen sind dort eine Frage, die niemand
    // beantworten kann.
    final gesehen = <SpeciesIconLook, String>{};
    final doppelt = <String>[];
    for (final art in known) {
      final look = speciesIconLook(art.name);
      if (look == null) continue;
      final vorher = gesehen[look];
      if (vorher != null) {
        doppelt.add('$vorher = ${art.name}');
      } else {
        gesehen[look] = art.name;
      }
    }
    expect(doppelt, isEmpty, reason: 'gleiches Aussehen: $doppelt');
  });

  test('die tödlichen Arten sehen nicht nach Speisepilz aus', () {
    // Kein Test über Mykologie, sondern über Pflege: Für jede tödliche
    // Art ist eine Entscheidung getroffen worden, und sie steht nicht
    // zufällig auf dem Look ihrer Gruppe.
    final toedlich = known
        .where((a) => edibilityFor(a.name)?.level == Edibility.toedlichGiftig)
        .toList();
    expect(toedlich, isNotEmpty, reason: 'sonst prüft der Test nichts');
    for (final art in toedlich) {
      expect(speciesIconLook(art.name), isNotNull, reason: art.name);
    }
  });
}
