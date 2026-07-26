// Der Weg vom gefangenen Fehler zum Bericht. Der Versand selbst ist nicht
// testbar ohne Netz — die Verdrahtung und ihre Sicherungen dagegen schon,
// und genau dort steckt das Risiko.
import 'dart:io';

import 'package:executor_lib/executor_lib.dart' show CancellationException;
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

  group('worthReporting — was die globalen Handler aussieben (#136)', () {
    test('Abgebrochene Kachel-Aufträge nicht melden', () {
      // 193 Fälle in einer Woche: Der Kartenrenderer bricht Kacheln ab,
      // sobald sie aus dem Bild wandern. Genau dafür ist die Ausnahme da.
      expect(worthReporting(CancellationException()), isFalse);
    });

    test('Abfragen nach dem Abmelden nicht melden', () {
      expect(worthReporting(const NotSignedInException()), isFalse);
    });

    test('Alles andere weiterhin melden', () {
      // Die Gegenprobe: Der Filter darf nicht zur Stille führen.
      expect(worthReporting(const FormatException('kaputt')), isTrue);
      expect(worthReporting(StateError('kaputt')), isTrue);
      expect(worthReporting(const SocketException('weg')), isTrue);
    });
  });

  test('logError meldet auch Ausgesiebtes, wenn es direkt gerufen wird', () {
    // worthReporting sitzt bewusst NUR in den globalen Handlern: Wer mit
    // eigenem Kontext meldet, hat sich für das Melden entschieden.
    final seen = <String>[];
    setErrorSink((context, _, _) => seen.add(context));

    logError('Kachel laden', CancellationException());

    expect(seen, ['Kachel laden']);
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
