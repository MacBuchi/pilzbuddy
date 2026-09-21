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

  test('Zweitnamen finden das Bild ihrer Hauptbezeichnung', () {
    expect(photoFor('Geheimpilz'), isNull);
    expect(photoFor(null), isNull);
    expect(photoFor('stockschwämmchen'), isNotNull);
  });
}
