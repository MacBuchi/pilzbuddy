// Eine gemeinsame Obergrenze für Hintergrund-Isolates (#641).
//
// Jedes `compute` startet ein eigenes Isolate in derselben Isolate-Gruppe
// wie die Oberfläche. Auf dem Pixel XL (4 Kerne) waren beim Schwenken mit
// mehreren Ebenen 3 von 4 Kernen mit solchen Workern belegt, 6–14 je
// Sekunde (Perfetto, 2026-10-02). Die Gruppe hat begrenzt viele
// Mutator-Plätze, und eine Speicherbereinigung hält alle an — der ANR aus
// #641 stand genau dort (`IsolateGroup::IncreaseMutatorCount`): Der
// Hauptthread wartete darauf, sein eigenes Isolate wieder betreten zu
// dürfen.
//
// Deshalb geht JEDE Einmal-Rechnung der App über [boundedCompute]: Es
// laufen höchstens [kComputeLimit] zugleich, der Rest wartet in der
// Reihenfolge des Eintreffens. Die Rechnungen beim Kartenschwenken laufen
// gar nicht hier, sondern im dauerhaften Zeichen-Isolate
// (`map_worker.dart`). `test/bounded_compute_guard_test.dart` verbietet
// nacktes `compute`/`Isolate.run` in `lib/` außerhalb dieser beiden
// Dateien — eine neue Stelle soll nicht still an der Grenze vorbeigehen.
import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Höchstens so viele Einmal-Rechnungen zugleich. Zwei: Mit Oberfläche und
/// Zeichen-Isolate sind das vier Dart-Mutatoren, auf einem Vierkerner also
/// keiner, der auf einen Kern warten muss.
const kComputeLimit = 2;

/// Ein Zähler mit Warteschlange. Eigene Klasse, damit der Test die Grenze
/// an einer eigenen Instanz prüfen kann.
class ComputeGate {
  ComputeGate(this.limit);

  /// `null` heißt ohne Grenze.
  final int? limit;
  int _running = 0;
  final _waiting = Queue<Completer<void>>();

  /// Wie viele gerade laufen — für den Test.
  int get running => _running;

  Future<R> run<R>(Future<R> Function() task) async {
    final max = limit;
    if (max != null && _running >= max) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    } else {
      _running++;
    }
    try {
      return await task();
    } finally {
      // Der Platz geht direkt an den Nächsten, ohne den Zähler zu senken
      // — sonst könnte sich zwischen zwei Microtasks ein Neuer vordrängeln.
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }
}

/// Die eine Grenze der App.
///
/// Unter `flutter test` OHNE Grenze: Ein `compute`, das in der
/// FakeAsync-Zone eines Widget-Tests startet, meldet sich nie zurück (so
/// gemessen, siehe `gbif_layer_flow_test.dart`). Mit Grenze hielte es
/// seinen Platz für immer, und jede spätere Rechnung im selben Test hinge.
/// Geprüft wird die Grenze deshalb an einer eigenen [ComputeGate].
final ComputeGate appComputeGate = ComputeGate(_appLimit());

int? _appLimit() {
  if (kIsWeb) return null; // dort rechnet `compute` ohnehin im Hauptthread
  if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
  return kComputeLimit;
}

/// `compute` mit der gemeinsamen Grenze — sonst unverändert.
Future<R> boundedCompute<M, R>(ComputeCallback<M, R> callback, M message,
        {String? debugLabel}) =>
    appComputeGate
        .run(() => compute(callback, message, debugLabel: debugLabel));
