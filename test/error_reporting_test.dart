// Der Weg vom gefangenen Fehler zum Bericht. Der Versand selbst ist nicht
// testbar ohne Netz — die Verdrahtung und ihre Sicherungen dagegen schon,
// und genau dort steckt das Risiko.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/errors.dart';

void main() {
  tearDown(() => setErrorSink(null));

  test('logError reicht Kontext, Fehler und Stacktrace weiter', () {
    final seen = <(String, Object, StackTrace?)>[];
    setErrorSink((context, error, stack) => seen.add((context, error, stack)));

    final stack = StackTrace.current;
    logError('Spot speichern', const FormatException('kaputt'), stack);

    expect(seen, hasLength(1));
    expect(seen.single.$1, 'Spot speichern');
    expect(seen.single.$2, isA<FormatException>());
    expect(seen.single.$3, same(stack));
  });

  test('Ein werfender Sink reißt logError nicht mit', () {
    // Das ist die eigentliche Gefahr: scheitert das Melden und würde der
    // Fehler wieder über logError laufen, schaukelt sich das auf. Der
    // Aufrufer darf davon nichts merken.
    setErrorSink((_, _, _) => throw StateError('Melden gescheitert'));

    expect(() => logError('Egal', Exception('x')), returnsNormally);
  });

  test('Ohne Sink bleibt logError reines Logging', () {
    setErrorSink(null);
    expect(() => logError('Egal', Exception('x')), returnsNormally);
  });

  test('Ein abgemeldeter Sink bekommt nichts mehr', () {
    var calls = 0;
    setErrorSink((_, _, _) => calls++);
    logError('Eins', Exception('x'));
    setErrorSink(null);
    logError('Zwei', Exception('x'));

    expect(calls, 1);
  });
}
