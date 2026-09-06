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

  group('foldSpeciesName (#395)', () {
    test('keine zwei Arten fallen beim Falten zusammen', () {
      // DIE Zusage, an der die Faltung hängt: `_entryFor` schlägt über den
      // gefalteten Namen nach. Fielen zwei verschiedene Pilze auf denselben
      // Schlüssel, lieferte die App stillschweigend den falschen — und
      // zwar auch beim SCHREIBEN, über `canonicalSpecies`.
      final byKey = <String, List<String>>{};
      for (final s in kBekannteArten) {
        byKey.putIfAbsent(foldSpeciesName(s.name), () => []).add(s.name);
      }
      final collisions = {
        for (final entry in byKey.entries)
          if (entry.value.length > 1) entry.key: entry.value,
      };
      expect(collisions, isEmpty, reason: 'Kollisionen: $collisions');
    });

    test('Bindestrich, Leerzeichen und Umlaut-Schreibweise fallen weg', () {
      const canonical = 'flaschenstaubling';
      for (final spelling in const [
        'Flaschenstäubling',
        'Flaschen-Stäubling',
        'Flaschen Stäubling',
        'Flaschenstaeubling',
        'Flaschenstaubling',
        'FLASCHENSTÄUBLING',
      ]) {
        expect(foldSpeciesName(spelling), canonical, reason: spelling);
      }
      // „ß" und „ss" ebenso — „Weisser" und „Weißer" sind dasselbe Wort.
      expect(foldSpeciesName('Weißer'), foldSpeciesName('Weisser'));
    });

    test('leere und zeichenlose Eingaben ergeben einen leeren Schlüssel', () {
      // `_entryFor` steigt darauf aus — sonst fände „---" die erste Art
      // mit leerem Schlüssel.
      expect(foldSpeciesName('   '), isEmpty);
      expect(foldSpeciesName('- /'), isEmpty);
    });
  });

  group('Schreibweisen finden die Art (#395)', () {
    test('das Vorschlagsfeld findet sie trotz Bindestrich und ohne Umlaut',
        () {
      // Der Feldbericht: „Flaschen-Stäubling" getippt, nichts gefunden,
      // Art als fehlend gemeldet — dabei stand sie seit jeher in der
      // Liste. 40 der 110 Arten tragen einen Umlaut oder ß.
      for (final typed in const [
        'Flaschen-Stäubling',
        'Flaschen Stäubling',
        'Flaschenstaeubling',
        'Staubling',
        'Knollenblatterpilz',
      ]) {
        final result = suggestSpecies(typed, const [], kBekannteArten);
        expect(result, isNotEmpty, reason: typed);
        // Und zwar GEFUNDEN, nicht geraten. Die Gegenprobe hat es
        // gezeigt: Ohne diese Zeile blieb der Test grün, wenn man die
        // Faltung aus dem Vergleich nahm — der Tippfehler-Ausgleich fing
        // die Schreibweisen auf und die Oberfläche schriebe „Meintest du
        // …?" über die völlig richtige Eingabe des Nutzers.
        expect(result.every((s) => !s.isGuess), isTrue, reason: typed);
      }
      expect(suggestSpecies('Flaschen-Stäubling', const [], kBekannteArten)
          .single.name, 'Flaschenstäubling');
    });

    test('auch der Schreibweg normalisiert — sonst entstünde eine Dublette',
        () {
      // `canonicalSpecies` läuft in `SpotRepository.addFind`. Ohne die
      // Faltung wäre „Flaschen-Stäubling" eine eigene Art des Nutzers
      // neben der bekannten, mit eigenem Icon und eigener Statistik.
      expect(canonicalSpecies('Flaschen-Stäubling'), 'Flaschenstäubling');
      expect(canonicalSpecies('flaschenbovist'), 'Flaschenstäubling');
      expect(groupFor('Knollenblatterpilz'), isNull,
          reason: 'kein Eintrag heißt so — nur die drei mit Vorsilbe');
      expect(groupFor('Grüner Knollenblatterpilz'), SpeciesGroup.wulstlinge);
      // Eigene Arten bleiben unangetastet.
      expect(canonicalSpecies('Mein Geheimpilz'), 'Mein Geheimpilz');
    });
  });

  group('Tippfehler-Ausgleich (#395)', () {
    test('„Bofist" findet den Bovist — und ist als geraten markiert', () {
      final result = suggestSpecies('Flaschenbofist', const [], kBekannteArten);
      expect(result.single.name, 'Flaschenstäubling');
      expect(result.single.isGuess, isTrue,
          reason: 'die Oberfläche schreibt darüber „Meintest du …?"');
    });

    test('gängige Vertipper landen bei ihrer Art', () {
      const cases = {
        'bofist': 'Riesenbovist',
        'Judasor': 'Judasohr',
        'Marrone': 'Maronenröhrling',
        'Parasoll': 'Parasol',
        'Hallimash': 'Hallimasch',
        'Steinpiltz': 'Steinpilz',
        'pfiferling': 'Pfifferling',
      };
      cases.forEach((typed, expected) {
        final names =
            suggestSpecies(typed, const [], kBekannteArten).map((s) => s.name);
        expect(names, contains(expected), reason: typed);
      });
    });

    test('auch ein kurzer Vertipper landet noch', () {
      // Die Grenze lag zuerst bei sechs Zeichen, weil „hallo" sonst den
      // Hallimasch vorschlug. Das war das falsche Kriterium: In einem
      // Artenfeld ist „hallo" höchstwahrscheinlich ein vertipptes
      // „Halli…" (Betreiber, 2026-09-06). Die Kosten sind unsymmetrisch —
      // eine überflüssige Zeile tippt man nicht an, eine leere Liste
      // dagegen liest sich als „die Art fehlt", und genau daraus ist #395
      // entstanden.
      for (final typed in const ['Halo', 'hallo', 'Hallimash']) {
        expect(
            suggestSpecies(typed, const [], kBekannteArten).map((s) => s.name),
            contains('Hallimasch'),
            reason: typed);
      }
    });

    test('unter vier Zeichen wird nicht geraten', () {
      // Die eine Grenze, die bleibt: Ein Fehler auf drei Zeichen heißt,
      // ein Drittel der Eingabe ist falsch — das ist kein
      // Tippfehlermodell mehr. Darunter liefert der Contains-Vergleich
      // ohnehin fast immer Treffer.
      for (final tooShort in const ['abc', 'xyz', 'qw', 'Hal']) {
        // Gefunden werden darf weiterhin: „Hal" steckt in „Hallimasch",
        // und der Contains-Vergleich kennt keine Mindestlänge. Nur GERATEN
        // wird hier nicht.
        expect(
            suggestSpecies(tooShort, const [], kBekannteArten)
                .where((s) => s.isGuess),
            isEmpty,
            reason: tooShort);
      }
      expect(suggestSpecies('abc', const [], kBekannteArten), isEmpty);
    });

    test('weit entferntes bleibt still — gemessen, nicht versprochen', () {
      // KEINE Zusage „Unsinn schweigt immer": „Auto" und „Regen" liegen
      // zufällig einen Fehler neben einem Wortstück und liefern sehr wohl
      // einen Vorschlag. Das ist angenommen — im Vorschlagsfeld kostet er
      // nichts. Was diese Zeilen festhalten, ist der gemessene Befund,
      // dass die lockere Schwelle trotzdem kaum Rauschen erzeugt: 23 von
      // 25 geprüften Nicht-Arten bleiben still.
      for (final nonsense in const [
        'qwertz',
        'Fahrrad',
        'Waldrand',
        'Lichtung',
        'Baumstumpf',
        'Brombeere',
        'Spechbach',
        'Waldspaziergang',
        'Vogelgezwitscher',
        'Nordhang',
      ]) {
        expect(suggestSpecies(nonsense, const [], kBekannteArten), isEmpty,
            reason: nonsense);
      }
    });

    test('auch ein Vertipper füllt den Bildschirm nicht', () {
      // „Champingnon" liegt einen Fehler neben allen fünf Champignons.
      // Ohne die Schranke stünden bei einem Vertipper beliebig viele
      // Zeilen — und der Sinn der Liste ist, die wahrscheinlichsten zu
      // zeigen, nicht alle.
      final result =
          suggestSpecies('Champingnon', const [], kBekannteArten, limit: 3);
      expect(result, hasLength(3));
      expect(result.every((s) => s.isGuess), isTrue);
    });

    test('geraten wird NUR, wenn die normale Suche nichts fand', () {
      // Sonst stünde „Meintest du …?" über echten Treffern.
      final found = suggestSpecies('Steinpilz', const [], kBekannteArten);
      expect(found, isNotEmpty);
      expect(found.every((s) => !s.isGuess), isTrue);
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

    test('der Samtfußrübling bleibt ein Lamellenpilz', () {
      // Er wächst büschelig an Holz — und genau daran ist der
      // Igelstachelbart schon einmal falsch einsortiert worden. „An Holz"
      // macht keinen Baumpilz: Die Gruppe kommt von der Hutunterseite, und
      // die trägt hier Lamellen. Hängt an der Einordnung auch sein Icon
      // (orange Kappe auf dünnem dunklem Stiel, #208).
      expect(groupFor('Samtfußrübling'), SpeciesGroup.sonstige);
      expect(groupFor('Winterrübling'), SpeciesGroup.sonstige,
          reason: 'Zweitname erbt die Gruppe');
      expect(SpeciesGroup.sonstige.label, 'Lamellenpilz');
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
