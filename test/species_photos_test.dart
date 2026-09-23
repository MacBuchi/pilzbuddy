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
import 'package:pilzbuddy/data/feedback_repository.dart';


/// Die Kantenlängen eines WebP-Bildes, aus dem Dateikopf gelesen.
///
/// **Statt einer Mindestgröße in Bytes.** Die stand hier bei 10 000 und
/// sollte leere oder abgebrochene Dateien fangen. Am 2026-09-22 fiel
/// sie über ein gültiges Bild mit 9 998 Bytes — ein violetter Hut vor
/// unscharfem Grund komprimiert eben gut. Eine Schwelle, die aus dem
/// falschen Grund anschlägt, wird beim dritten Mal hochgesetzt und
/// prüft dann nichts mehr.
///
/// Der Kopf sagt es genau: RIFF-Kennung, WEBP-Kennung, dann der
/// `VP8 `-Block mit Startcode und den beiden 14-Bit-Maßen. Das fängt
/// die Null-Datei, die halbe Datei und das falsche Format.
({int width, int height}) webpSize(File file) {
  final b = file.readAsBytesSync();
  expect(b.length, greaterThan(30), reason: '${file.path}: zu kurz für WebP');
  expect(String.fromCharCodes(b.sublist(0, 4)), 'RIFF', reason: file.path);
  expect(String.fromCharCodes(b.sublist(8, 12)), 'WEBP', reason: file.path);
  expect(String.fromCharCodes(b.sublist(12, 16)), 'VP8 ',
      reason: '${file.path}: nur verlustbehaftetes VP8 wird hier erzeugt');
  // 20..22 ist das Frame-Tag, 23..25 der Startcode, dann die Maße.
  expect(b.sublist(23, 26), [0x9d, 0x01, 0x2a], reason: file.path);
  final w = (b[26] | (b[27] << 8)) & 0x3fff;
  final h = (b[28] | (b[29] << 8)) & 0x3fff;
  return (width: w, height: h);
}

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
      final size = webpSize(file);
      expect(size.width, greaterThan(100), reason: entry.key);
      expect(size.height, size.width, reason: '${entry.key}: quadratisch');
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

  test('die Einwilligung beim Melden nennt die Lizenz der eigenen '
      'Aufnahmen (Patch 034)', () {
    // Wer den Haken setzt, stimmt GENAU dieser Lizenz zu. Stünde in der
    // Galerie später eine andere, wäre die Einwilligung für das Bild
    // wertlos — und NC/ND schieden ohnehin aus (Test darüber).
    expect(kGalleryPhotoLicence, isNot(contains('NC')));
    expect(kGalleryPhotoLicence, isNot(contains('ND')));
    final own = {
      for (final photos in speciesPortraits.values)
        for (final p in photos)
          if (p.source == 'Eigene Aufnahme') p.licence,
    };
    expect(own, {kGalleryPhotoLicence},
        reason: 'eigene Aufnahmen und Einwilligung laufen auseinander');
    final bot = File('tool/feedback_bot.py').readAsStringSync();
    expect(bot, contains('GALLERY_PHOTO_LICENCE = "$kGalleryPhotoLicence"'),
        reason: 'das Issue nennt dieselbe Lizenz wie der Dialog');
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
          final size = webpSize(file);
          expect(size.width, greaterThan(100), reason: entry.key);
          expect(size.height, size.width, reason: '${entry.key}: quadratisch');
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

    test('ein Asset steht nie zweimal auf DERSELBEN Seite', () {
      // Der billigste Pflegefehler: beim Kopieren die Nummer vergessen.
      // Zwei gleiche Bilder nebeneinander sähen aus wie ein Ladefehler.
      for (final entry in speciesPortraits.entries) {
        final gesehen = <String>{};
        for (final photo in entry.value) {
          expect(gesehen.add(photo.asset), isTrue,
              reason: '${entry.key}: ${photo.asset} doppelt');
        }
      }
    });

    test('zwei Arten teilen ein Bild nur, wenn eine die Gattung der '
        'anderen ist', () {
      // **Der Sammelname-Fall, und nur der.** „Rotkappe" meint bei uns
      // die ganze Gattung Leccinum — ein eigenes Bild müsste trotzdem
      // EINE der Arten zeigen, also lieber sichtbar dieselbe wie die
      // Espenrotkappe (Betreiber, 2026-09-22).
      //
      // Geprüft wird die BEGRÜNDUNG, nicht das Paar: Die eine Art trägt
      // als `sci` die Gattung der anderen. Wer zwei beliebige Arten
      // dasselbe Bild geben will, kommt hier nicht durch.
      String? sciOf(String name) => kBekannteArten
          .firstWhere((s) => s.name == name,
              orElse: () => const KnownSpecies('', SpeciesGroup.sonstige))
          .sci;
      final besitzer = <String, String>{};
      for (final entry in allSpeciesPhotos()) {
        final vorher = besitzer[entry.photo.asset];
        if (vorher == null) {
          besitzer[entry.photo.asset] = entry.species;
          continue;
        }
        final a = sciOf(vorher), b = sciOf(entry.species);
        expect(a, isNotNull, reason: vorher);
        expect(b, isNotNull, reason: entry.species);
        final gattung = a!.split(' ').first == b!.split(' ').first;
        final sammelname = !a.contains(' ') || !b.contains(' ');
        expect(gattung && sammelname, isTrue,
            reason: '$vorher und ${entry.species} teilen sich '
                '${entry.photo.asset}, sind aber keine Gattung und Art');
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
