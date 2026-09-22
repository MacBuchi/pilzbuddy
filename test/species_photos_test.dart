// Die Artfotos (#511 Folgeschritt) — Lizenz-Pflichten und Paarbildung.
//
// **Was hier NICHT geprüft werden kann**: ob das Bild den Pilz zeigt, den
// es zeigen soll. Das hat ein Mensch angesehen, und zwei Kandidaten sind
// dabei ausgeschieden, weil sie eine andere Art zeigten als ihr
// Dateiname behauptete. Geprüft wird alles andere — und bei CC-BY ist
// „alles andere" die Bedingung, unter der wir die Bilder überhaupt
// ausliefern dürfen.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
import 'package:pilzbuddy/core/species_lookalikes.dart';
import 'package:pilzbuddy/core/species_photos.dart';

void main() {
  final known = {
    for (final s in kBekannteArten)
      if (!s.isSynonym) s.name
  };

  test('jedes Bild gehört zu einer bekannten Art und liegt wirklich da',
      () {
    expect(speciesPhotos, isNotEmpty);
    for (final entry in speciesPhotos.entries) {
      expect(known, contains(entry.key), reason: entry.key);
      final file = File(entry.value.asset);
      expect(file.existsSync(), isTrue,
          reason: '${entry.key}: ${entry.value.asset} fehlt');
      // Eine leere oder abgebrochene Datei wäre im Diff unsichtbar.
      expect(file.lengthSync(), greaterThan(10000), reason: entry.key);
      expect(entry.value.asset, endsWith('.webp'));
    }
  });

  test('jedes Bild trägt Urheber, Lizenz und Fundstelle', () {
    // **Die Bedingung, nicht die Höflichkeit.** Ohne diese drei Angaben
    // dürfen wir ein CC-BY-Bild nicht ausliefern.
    for (final entry in speciesPhotos.entries) {
      final p = entry.value;
      expect(p.author.trim(), isNotEmpty, reason: entry.key);
      expect(p.licence.trim(), isNotEmpty, reason: entry.key);
      expect(p.licenceUrl, startsWith('http'), reason: entry.key);
      expect(p.source, startsWith('https://commons.wikimedia.org/'),
          reason: entry.key);
    }
  });

  test('keine NC- oder ND-Lizenz', () {
    // Die App liegt im Play Store. „Nicht kommerziell" ist dort eine
    // Frage, die man nicht offen lassen will, und „keine Bearbeitung"
    // verbietet schon den Zuschnitt.
    for (final entry in speciesPhotos.entries) {
      final lic = entry.value.licence.toUpperCase();
      expect(lic, isNot(contains('NC')), reason: entry.key);
      expect(lic, isNot(contains('ND')), reason: entry.key);
      expect(
          lic.contains('CC0') ||
              lic.contains('CC BY') ||
              lic.contains('PUBLIC DOMAIN'),
          isTrue,
          reason: '${entry.key}: ${entry.value.licence}');
    }
  });

  test('die Namensnennung der Lizenzseite kommt aus derselben Tabelle',
      () {
    final credits = speciesPhotoCredits();
    for (final entry in speciesPhotos.entries) {
      expect(credits, contains(entry.key));
      expect(credits, contains(entry.value.author));
      expect(credits, contains(entry.value.source));
    }
  });

  test('die Bildunterschrift nennt Urheber UND Lizenz', () {
    final photo = speciesPhotos['Stockschwämmchen']!;
    expect(photoCredit(photo), contains(photo.author));
    expect(photoCredit(photo), contains(photo.licence));
  });

  test('ein Bild hat nur Sinn, wenn der Partner auch eines hat', () {
    // Ein einzelnes Bild beantwortet die Frage nicht, die der Abschnitt
    // stellt — es zeigt, wie EINER von beiden aussieht, und das genügt
    // zum Verwechseln. Jedes Bild muss also mindestens einen
    // Verwechslungspartner haben, der ebenfalls eines hat.
    for (final name in speciesPhotos.keys) {
      final partnersWithPhoto = lookalikesFor(name)
          .where((p) => speciesPhotos.containsKey(p.species));
      expect(partnersWithPhoto, isNotEmpty,
          reason: '$name hat ein Bild, aber keinen bebilderten Partner');
    }
  });

  test('die acht Paare, für die es die Bilder gibt', () {
    const pairs = [
      ('Stockschwämmchen', 'Gifthäubling'),
      ('Samtfußrübling', 'Gifthäubling'),
      ('Speisemorchel', 'Frühjahrslorchel'),
      ('Spitzmorchel', 'Frühjahrslorchel'),
      ('Perlpilz', 'Pantherpilz'),
      ('Wiesenchampignon', 'Grüner Knollenblätterpilz'),
      ('Flaschenstäubling', 'Grüner Knollenblätterpilz'),
      // Die rotporigen Röhrlinge — der Hut entscheidet, und den zeigt
      // ein Foto (Betreiber, 2026-09-22).
      ('Flockenstieliger Hexenröhrling', 'Satansröhrling'),
    ];
    for (final (a, b) in pairs) {
      expect(photoFor(a), isNotNull, reason: a);
      expect(photoFor(b), isNotNull, reason: b);
      // Und das Paar muss auch als Verwechslung eingetragen sein, sonst
      // stünden die Bilder nirgends.
      expect(lookalikesFor(a).map((p) => p.species), contains(b));
    }
  });

  group('Porträts', () {
    test('jedes Porträt gehört zu einer bekannten Art und liegt wirklich da',
        () {
      expect(speciesPortraits, isNotEmpty);
      for (final entry in speciesPortraits.entries) {
        expect(known, contains(entry.key), reason: entry.key);
        for (final photo in entry.value) {
          final file = File(photo.asset);
          expect(file.existsSync(), isTrue,
              reason: '${entry.key}: ${photo.asset} fehlt');
          expect(file.lengthSync(), greaterThan(10000), reason: entry.key);
          expect(photo.asset, endsWith('.webp'));
        }
      }
    });

    test('zwei bis drei Bilder je Art — nicht eines, nicht zwanzig', () {
      // **Die Zahl IST die Regel.** Ein Bild zeigt einen Einzelfall und
      // lädt dazu ein, ihn für die Art zu halten; zu viele machen aus der
      // Seite eine Galerie, durch die niemand scrollt.
      for (final entry in speciesPortraits.entries) {
        expect(entry.value.length, inInclusiveRange(1, 3), reason: entry.key);
      }
    });

    test('kein Asset wird zweimal benutzt', () {
      // Der billigste Pflegefehler: beim Kopieren die Nummer vergessen.
      // Zwei gleiche Bilder nebeneinander sähen aus wie ein Ladefehler.
      final seen = <String, String>{};
      for (final entry in allSpeciesPhotos()) {
        final previous = seen[entry.photo.asset];
        expect(previous, isNull,
            reason: '${entry.species} und $previous teilen sich '
                '${entry.photo.asset}');
        seen[entry.photo.asset] = entry.species;
      }
    });

    test('auch die Porträts tragen Urheber, Lizenz und Herkunft', () {
      for (final entry in speciesPortraits.entries) {
        for (final p in entry.value) {
          expect(p.author.trim(), isNotEmpty, reason: entry.key);
          expect(p.licence.trim(), isNotEmpty, reason: entry.key);
          expect(p.licenceUrl, startsWith('http'), reason: entry.key);
          // Eigene Aufnahmen haben keine Fundstelle im Netz — aber eine
          // Herkunftsangabe müssen sie trotzdem tragen, sonst steht auf
          // der Lizenzseite eine leere Zeile.
          expect(p.source.trim(), isNotEmpty, reason: entry.key);
        }
      }
    });

    test('die Lizenzseite nennt JEDES Bild, auch die Porträts', () {
      // **Die Naht, an der ein Bild verloren geht.** Vor den Porträts
      // las `speciesPhotoCredits` nur eine Tabelle; eine zweite Quelle
      // wäre dort stillschweigend unerwähnt geblieben, und ein nicht
      // genanntes CC-BY-Bild ist ein Lizenzverstoß.
      final credits = speciesPhotoCredits();
      for (final entry in allSpeciesPhotos()) {
        expect(credits, contains(entry.photo.author), reason: entry.species);
      }
      expect(allSpeciesPhotos().length,
          speciesPhotos.length +
              speciesPortraits.values.fold<int>(0, (a, b) => a + b.length));
    });

    test('auch Porträts tragen keine NC- oder ND-Lizenz', () {
      for (final entry in speciesPortraits.entries) {
        for (final p in entry.value) {
          expect(p.licence.toUpperCase(), isNot(contains('NC')),
              reason: entry.key);
          expect(p.licence.toUpperCase(), isNot(contains('ND')),
              reason: entry.key);
        }
      }
    });

    test('Zweitnamen finden die Porträts ihrer Hauptbezeichnung', () {
      expect(portraitsFor('Marone'), portraitsFor('Maronenröhrling'));
      expect(portraitsFor('Geheimpilz'), isEmpty);
      expect(portraitsFor(null), isEmpty);
    });

    test('der sichtbare Hinweis trägt die ganze Aussage', () {
      // Drei Teile, und alle drei stehen AUSSERHALB des Ausklappers:
      // dass ein Bild falsch sein kann, dass niemand vom Fach es
      // geprüft hat, und was daraus folgt. Eingeklappt ist nur das
      // Warum.
      expect(kPhotoDisclaimer, contains('falsch zugeordnet'));
      expect(kPhotoDisclaimer, contains('Pilzsachverständigen'));
      expect(kPhotoDisclaimer, contains('stehen lassen'));
      expect(kPhotoDisclaimerDetail.length,
          greaterThan(kPhotoDisclaimer.length));
    });

    test('der Hinweis spricht nicht von „uns" und nennt keine Quelle', () {
      // **Wer die Bilder zugeordnet hat, ändert für den Leser nichts.**
      // Der erste Entwurf schrieb „Bestimmt haben sie wir, nicht ein
      // Pilzsachverständiger" — grammatisch falsch und um eine Aussage
      // herumgebaut, die niemanden weiterbringt (Betreiber,
      // 2026-09-22).
      //
      // Und er nennt keine Herkunft: Eigene Aufnahmen und
      // Commons-Material stehen im selben Streifen, wer welches Bild
      // gemacht hat, steht in der Zeile darüber, und zwei Hinweise für
      // zwei Herkünfte wären zwei Antworten auf dieselbe Frage.
      // **Auf ganze Wörter, nicht auf Teilzeichenketten.** Der erste
      // Entwurf prüfte `contains('wir')` und fiel über „wirklich".
      final ganz = '$kPhotoDisclaimer $kPhotoDisclaimerDetail';
      for (final wort in ['wir', 'uns', 'Commons']) {
        expect(RegExp('\\b$wort\\b', caseSensitive: false).hasMatch(ganz),
            isFalse, reason: wort);
      }
    });
  });

  test('Zweitnamen finden das Bild ihrer Hauptbezeichnung', () {
    expect(photoFor('Geheimpilz'), isNull);
    expect(photoFor(null), isNull);
    expect(photoFor('stockschwämmchen'), isNotNull);
  });
}
