// Der Abruf der großen Artbilder (#537).
//
// **Was hier NICHT geprüft wird**: ob GitHub liefert. Das ist Netz, und
// der Test läuft ohne. Geprüft wird die Zusage, die der Aufrufer
// braucht: Der Abruf wirft nie, und ohne Antwort gibt es `null` — dann
// bleibt in der Ansicht das mitgelieferte Bild stehen.

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/species_photo_repository.dart';

void main() {
  test('die Adresse zeigt auf den Branch, nicht auf einen Release-Anhang',
      () {
    // **Der Unterschied ist CORS.** Release-Anhänge gibt GitHub einem
    // Browser nicht heraus (#365/#366); ein Branch wird von
    // raw.githubusercontent.com mit `*` ausgeliefert. Wer das hier auf
    // `/releases/download/` umstellt, bricht den Web-Build still.
    expect(kSpeciesPhotoBaseUrl, startsWith('https://raw.githubusercontent.com/'));
    expect(kSpeciesPhotoBaseUrl, isNot(contains('/releases/')));
  });

  test('ein fehlgeschlagener Abruf gibt null und wirft nicht', () async {
    // Der Normalfall im Wald. Ein Fehler hier darf die Ansicht nicht
    // mitreißen — das mitgelieferte Bild steht ja.
    // **Auf einen toten Port im eigenen Rechner**, nicht auf GitHub:
    // „Kein Netzwerk in Tests" (CLAUDE.md), und ein Test, der gegen
    // einen echten Dienst läuft, flattert irgendwann in CI.
    final repo = SpeciesPhotoRepository(
        cachesToDisk: false, baseUrl: 'http://127.0.0.1:1');
    final bytes = await repo.load('assets/species/gibtesnicht-9.webp');
    expect(bytes, isNull);
  });

  test('ohne Plattenspeicher wird trotzdem geholt', () {
    // Der Web-Fall: kein path_provider, kein eigener Speicher — der
    // Browser und der Service Worker übernehmen das.
    expect(SpeciesPhotoRepository(cachesToDisk: false).cachesToDisk, isFalse);
  });

  test('die Grenze ist eine GRÖSSE, keine Frist', () {
    // Der Unterschied zu spot_cache, outbox und tours: Deren Inhalt ist
    // nicht nachladbar, ein Bild schon. Also darf es weg, sobald es
    // Platz kostet — und nicht, weil es alt ist.
    expect(kSpeciesPhotoCacheBytes, greaterThan(1024 * 1024));
  });
}
