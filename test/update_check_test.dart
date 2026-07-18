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
  });
}
