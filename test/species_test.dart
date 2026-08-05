import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
import 'package:pilzbuddy/core/widgets/mushroom_avatar.dart';
import 'package:pilzbuddy/features/spots/species_suggestions.dart';
import 'package:pilzbuddy/models/find.dart';

void main() {
  group('speciesFromText (Art im GPX-Punktnamen erkennen)', () {
    test('findet Arten in echten Punktnamen aus Karten-Apps', () {
      expect(speciesFromText('Edelreizker Spechbach'), 'Edelreizker');
      expect(speciesFromText('Steinpilz am Windrad'), 'Steinpilz');
      expect(speciesFromText('Austernseitling am Stamm'), 'Austernseitling');
    });

    test('ein Zweitname im Punktnamen liefert die Hauptbezeichnung', () {
      // Der Import legt daraus einen Fund an; stünde hier der Zweitname,
      // käme er als eigene Art in die Datenbank.
      expect(speciesFromText('Wo du hin guckst, totentrompeten'),
          'Herbsttrompete');
      expect(speciesFromText('6 Maronenbäume'), 'Maronenröhrling');
    });

    test('längster Treffer gewinnt, kein Treffer bleibt null', () {
      expect(speciesFromText('Maronenröhrling im Moos'), 'Maronenröhrling');
      expect(speciesFromText('Wasserturmweg, Bad Rappenau'), isNull);
      expect(speciesFromText('Semmelstoppelpipz'), isNull); // Tippfehler
      expect(speciesFromText(null), isNull);
    });
  });

  group('suggestSpecies', () {
    const own = ['Steinpilz', 'Pfifferling'];
    const builtin = [
      KnownSpecies('Steinpilz', SpeciesGroup.roehrlinge),
      KnownSpecies('Maronenröhrling', SpeciesGroup.roehrlinge),
      KnownSpecies('Fliegenpilz', SpeciesGroup.wulstlinge),
      KnownSpecies('Parasol', SpeciesGroup.schirmlinge),
    ];

    test('eigene Arten kommen vor bekannten', () {
      final result = suggestSpecies('pilz', own, builtin);
      expect(result.first.name, 'Steinpilz');
      expect(result.first.isOwn, isTrue);
      expect(result.map((s) => s.name), contains('Fliegenpilz'));
    });

    test('dedupliziert case-insensitiv über beide Listen', () {
      final result = suggestSpecies('stein', ['steinpilz'], builtin);
      // Ein Eintrag statt zwei — und in der Schreibweise der Artenliste,
      // weil genau die gespeichert wird.
      expect(result.map((s) => s.name), ['Steinpilz']);
    });

    test('Gruppen werden zugeordnet — auch für eigene Arten', () {
      final result = suggestSpecies('fliegen', ['Fliegenpilz'], builtin);
      expect(result.single.isOwn, isTrue);
      // Gruppe kommt per Lookup aus der eingebauten Artenliste
      expect(result.single.group, SpeciesGroup.wulstlinge);
    });

    test('unbekannte eigene Art hat keine Gruppe', () {
      final result = suggestSpecies('geheim', ['Geheimpilz'], builtin);
      expect(result.single.group, isNull);
    });

    test('Contains-Match, nicht nur Präfix', () {
      final result = suggestSpecies('röhrling', own, builtin);
      expect(result.map((s) => s.name), ['Maronenröhrling']);
    });

    test('leere Eingabe liefert Vorschläge bis zum Limit', () {
      final result = suggestSpecies('', own, builtin, limit: 3);
      expect(result, hasLength(3));
      expect(result.sublist(0, 2).map((s) => s.name), own);
    });

    test('kein Treffer → leer', () {
      expect(suggestSpecies('xyz', own, builtin), isEmpty);
    });
  });

  group('groupFor', () {
    test('findet Gruppen case-insensitiv, unbekannt/leer → null', () {
      expect(groupFor('steinpilz'), SpeciesGroup.roehrlinge);
      expect(groupFor('PFIFFERLING'), SpeciesGroup.leistlinge);
      expect(groupFor('Fliegenpilz'), SpeciesGroup.wulstlinge);
      expect(groupFor('Riesenbovist'), SpeciesGroup.boviste);
      expect(groupFor('Geheimpilz'), isNull);
      expect(groupFor(null), isNull);
      expect(groupFor('  '), isNull);
    });

    test('Böhmische Verpel ist eine Lorchel, kein Lamellenpilz', () {
      // Der Feedback-Bot ordnet nach Stichwort ein und kannte „Verpel" nicht;
      // die Art landete deshalb in `sonstige` und bekam ein graues
      // Lamellenpilz-Icon. Diese Zeile hält die Korrektur fest.
      expect(groupFor('Böhmische Verpel'), SpeciesGroup.morcheln);
      expect(groupFor('Morchelbecherling'), SpeciesGroup.morcheln);
      expect(groupFor('Netzstieliger Hexenröhrling'), SpeciesGroup.roehrlinge);
    });

    test('Pilze ohne Lamellen stehen nicht unter „Lamellenpilz"', () {
      // Die Gruppen-Aufschrift steht im Vorschlagsfeld sichtbar am Eintrag.
      // Für diese vier wäre „Lamellenpilz" schlicht falsch — keiner hat
      // welche.
      for (final name in const [
        'Krause Glucke',
        'Semmelstoppelpilz',
        'Habichtspilz',
        'Ziegenbart',
        // Stand bis 1.37.0 bei den Baumpilzen und war eine orange Konsole.
        // Er wächst zwar an Holz, hat aber weder Hut noch Konsolenform —
        // ein Stachelpilz mit hängenden Nadeln.
        'Igelstachelbart',
        'Löwenmähne',
        'Affenkopfpilz',
      ]) {
        expect(groupFor(name), SpeciesGroup.stachelpilze, reason: name);
      }
      expect(SpeciesGroup.stachelpilze.label, isNot('Lamellenpilz'));
    });
  });

  group('Zweitnamen (sameAs)', () {
    test('jedes sameAs zeigt auf einen Eintrag, der selbst keines hat', () {
      final byName = {
        for (final s in kBekannteArten) s.name.toLowerCase(): s,
      };
      for (final s in kBekannteArten.where((s) => s.isSynonym)) {
        final target = byName[s.sameAs!.toLowerCase()];
        expect(target, isNotNull,
            reason: '${s.name}: „${s.sameAs}" steht nicht in der Liste');
        // Keine Ketten: Sonst hinge das Ergebnis davon ab, wie oft
        // aufgelöst wird, und damit von der Reihenfolge der Liste.
        expect(target!.sameAs, isNull,
            reason: '${s.name} → ${target.name} → ${target.sameAs}');
      }
    });

    test('ein Zweitname erbt die Gruppe seiner Hauptbezeichnung', () {
      for (final s in kBekannteArten.where((s) => s.isSynonym)) {
        expect(groupFor(s.name), groupFor(s.sameAs), reason: s.name);
      }
    });

    test('canonicalSpecies löst auf, zieht Schreibweise nach, lässt Eigenes', () {
      expect(canonicalSpecies('Totentrompete'), 'Herbsttrompete');
      expect(canonicalSpecies('  totentrompete '), 'Herbsttrompete');
      expect(canonicalSpecies('Herbsttrompete'), 'Herbsttrompete');
      expect(canonicalSpecies('steinpilz'), 'Steinpilz');
      // Eigene Arten sind Freitext und werden nicht umbenannt.
      expect(canonicalSpecies('Geheimpilz'), 'Geheimpilz');
      expect(canonicalSpecies('  '), isNull);
      expect(canonicalSpecies(null), isNull);
    });

    test('synonymsOf nimmt beide Richtungen entgegen', () {
      expect(synonymsOf('Herbsttrompete'), ['Totentrompete']);
      expect(synonymsOf('Totentrompete'), ['Totentrompete']);
      expect(synonymsOf('Steinpilz'), ['Herrenpilz', 'Fichtensteinpilz']);
      expect(synonymsOf('Pfifferling'), isEmpty);
      expect(synonymsOf('Geheimpilz'), isEmpty);
    });

    test('Braunkappe ist der Riesenträuschling, nicht die Marone', () {
      // Sie stand bis 1.37.0 bei den Röhrlingen und bekam den Maronen-Hut.
      expect(canonicalSpecies('Braunkappe'), 'Riesenträuschling');
      expect(groupFor('Braunkappe'), SpeciesGroup.sonstige);
      expect(canonicalSpecies('Marone'), 'Maronenröhrling');
      expect(groupFor('Marone'), SpeciesGroup.roehrlinge);
    });
  });

  group('Avatar-Katalog', () {
    test('wächst nur am Ende — bestehende Indizes bleiben, wo sie sind', () {
      // Der gewählte Index steht in `profiles.avatar`. Ein Eintrag, der
      // mittendrin eingeschoben wird, gibt jedem Nutzer dahinter ein anderes
      // Porträt. Diese Zeilen nageln die Stellen fest, an denen so ein
      // Einschub zuerst auffiele: den Vorgabe-Eintrag und den Beginn der
      // Freigeister ohne Gruppe.
      expect(kAvatarCatalog.first.group, SpeciesGroup.roehrlinge);
      expect(kAvatarCatalog[15].group, SpeciesGroup.boviste);
      expect(kAvatarCatalog[16].group, isNull);
      expect(kAvatarCatalog[23].group, isNull);
    });
  });

  group('ownSpeciesFromSortedNames', () {
    test('dedupliziert case-insensitiv und behält Reihenfolge', () {
      final result = ownSpeciesFromSortedNames(
          ['Marone', 'steinpilz', null, 'Steinpilz', '  ', 'Pfifferling']);
      // Auf die Hauptbezeichnung gebracht: sonst stünden „Marone" und
      // „Maronenröhrling" als zwei Vorschläge nebeneinander.
      expect(result, ['Maronenröhrling', 'Steinpilz', 'Pfifferling']);
    });
  });

  group('Find.createdAt', () {
    test('wird aus created_at geparst und ist optional', () {
      final mitTimestamp = Find.fromJson({
        'id': 'f1',
        'spot_id': 's1',
        'found_on': '2026-09-01',
        'created_at': '2026-09-01T14:30:00+00:00',
      }, currentUserId: 'ich');
      expect(mitTimestamp.createdAt, isNotNull);
      expect(mitTimestamp.createdAt!.toUtc().hour, 14);

      final ohne = Find.fromJson(
          {'id': 'f2', 'spot_id': 's1', 'found_on': '2026-09-01'},
          currentUserId: 'ich');
      expect(ohne.createdAt, isNull);
    });
  });
}
