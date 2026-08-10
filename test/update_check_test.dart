import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/update_check.dart';

void main() {
  group('isNewerVersion', () {
    test('erkennt neuere Versionen', () {
      expect(isNewerVersion('1.5.0', '1.4.2'), isTrue);
      expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(isNewerVersion('1.4.3', '1.4.2'), isTrue);
    });

    test('numerischer Vergleich, kein String-Vergleich', () {
      expect(isNewerVersion('1.10.0', '1.9.0'), isTrue);
      expect(isNewerVersion('1.9.0', '1.10.0'), isFalse);
    });

    test('gleiche oder ältere Version → false', () {
      expect(isNewerVersion('1.4.2', '1.4.2'), isFalse);
      expect(isNewerVersion('1.4.1', '1.4.2'), isFalse);
      expect(isNewerVersion('0.9.0', '1.0.0'), isFalse);
    });

    test('robust bei unvollständigen Angaben', () {
      expect(isNewerVersion('1.5', '1.4.9'), isTrue);
      expect(isNewerVersion('1.4', '1.4.0'), isFalse);
      expect(isNewerVersion('kaputt', '1.0.0'), isFalse);
    });

    // Früher fiel 1.5.1-rc1 still auf 1.5.0 zurück, weil int.tryParse
    // ('1-rc1') null liefert — der Suffix hat den Vergleich verfälscht
    // statt ignoriert zu werden (Issue #80).
    test('Vorabversions- und Build-Suffixe zählen nicht mit', () {
      expect(isNewerVersion('1.5.1-rc1', '1.5.0'), isTrue);
      expect(isNewerVersion('1.5.1-rc1', '1.5.1'), isFalse);
      expect(isNewerVersion('1.26.4+55', '1.26.4'), isFalse);
      expect(isNewerVersion('1.26.5+56', '1.26.4+55'), isTrue);
      expect(isNewerVersion('2.0.0-beta.1', '1.9.9'), isTrue);
    });
  });

  // Der Vorab-Kanal (#269) fragt `/releases` statt `/releases/latest` ab
  // und muss aus der Liste selbst wählen — GitHub sortiert absteigend
  // nach Erstellungszeit, filtert dort aber nichts weg.
  group('firstPublishedRelease', () {
    Map<String, dynamic> release(String tag,
            {bool draft = false, bool pre = false}) =>
        {'tag_name': tag, 'draft': draft, 'prerelease': pre};

    test('nimmt den jüngsten Eintrag — auch ein Prerelease', () {
      // Genau der Sinn des Kanals: Seit #262 ist der jüngste Stand
      // fast immer ein Prerelease, und den will man hier sehen.
      final first = firstPublishedRelease([
        release('v1.81.0', pre: true),
        release('v1.80.0', pre: false),
      ]);
      expect(first?['tag_name'], 'v1.81.0');
    });

    test('überspringt Entwürfe', () {
      // Ein Entwurf ist nicht öffentlich abrufbar: Der Download liefe
      // ins Leere und der Hinweis nennte eine Version, die es für
      // niemanden gibt.
      final first = firstPublishedRelease([
        release('v1.82.0', draft: true),
        release('v1.81.0', pre: true),
      ]);
      expect(first?['tag_name'], 'v1.81.0');
    });

    test('ein fehlendes draft-Feld heißt veröffentlicht', () {
      // Nicht jede Antwort trägt jedes Feld — fehlt es, darf der
      // Eintrag nicht stillschweigend verschwinden.
      final first = firstPublishedRelease([
        <String, dynamic>{'tag_name': 'v1.81.0'},
      ]);
      expect(first?['tag_name'], 'v1.81.0');
    });

    test('leere Liste und Fremdkörper ergeben null statt einer Ausnahme', () {
      expect(firstPublishedRelease(const []), isNull);
      expect(firstPublishedRelease(const ['unfug', 42]), isNull);
      expect(firstPublishedRelease([release('v1.0.0', draft: true)]), isNull);
    });
  });
}
