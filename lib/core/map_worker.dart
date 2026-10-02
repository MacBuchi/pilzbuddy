// Das Zeichen-Isolate der Karte (#641).
//
// Wald-, Ampel- und Fundorte-Fläche, Höhenlinien und der Bearbeiten-Entwurf
// malen bei JEDEM Kamera-Stillstand ein neues Bild. Bis 1.222.4 hieß das je
// Ebene ein neues `compute`: nichts wurde abgebrochen, und jedes nahm seine
// Gitter mit — Wald und Höhe je 13,6 MB, mit allen Ebenen rund 42 MB je
// Schwenk, kopiert AUF DEM HAUPTTHREAD (auch eine unveränderliche Sicht
// wird kopiert, nachgemessen). Auf dem Pixel XL waren beim Schwenken 3 von
// 4 Kernen mit Workern belegt; der ANR aus #641 wartete darauf, dass der
// Hauptthread sein Isolate wieder betreten durfte.
//
// Hier gilt stattdessen:
//
// - **EIN dauerhaftes Isolate.** Es rechnet nacheinander, also nie auf mehr
//   als einem Kern.
// - **Gitter liegen dort in Fächern** und gehen nur hinüber, wenn sich das
//   Objekt geändert hat (`identical`) — einmal je Sitzung statt je Schwenk.
// - **Je Spur gewinnt der neueste Auftrag.** Läuft einer, wartet höchstens
//   EIN weiterer; ein neuerer ersetzt ihn. Ein Auftrag, dessen Provider
//   verworfen ist, wird abgesagt, solange er noch nicht läuft.
// - **Ein Bild kommt ohne Kopie zurück** (`TransferableTypedData`).
//
// Robust ist es in drei Richtungen: Ein Fehler in einer Rechnung trifft
// nur diesen Auftrag. Stirbt das Isolate, scheitern seine offenen Aufträge,
// der nächste startet ein neues und schickt die Fächer erneut. Lässt es
// sich nicht starten oder stirbt es [kMapWorkerMaxDeaths]-mal, rechnet der
// Rest der Sitzung über `boundedCompute` — langsamer, aber nie gar nicht.
// Im Browser gibt es keine Isolates; dort rechnet derselbe Weg im
// Hauptthread, wie `compute` es dort ohnehin tut.
import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bounded_compute.dart';

/// Die Rechnung eines Auftrags. Muss eine top-level- oder statische
/// Funktion sein — sie reist in ein anderes Isolate.
typedef MapWorkerFn<P, R> = R Function(MapWorkerSlots slots, P params);

/// Stirbt das Isolate so oft, rechnet der Rest der Sitzung ohne.
const kMapWorkerMaxDeaths = 3;

/// So lange ohne Auftrag, dann beendet sich das Isolate und gibt seine
/// Fächer frei. Gemessen auf dem Pixel XL: Wald, Höhe und Regenstapel
/// hielten sonst 66 MB mehr in Ruhe, die ganze Sitzung lang. Der
/// nächste Auftrag startet ein neues und kopiert die Fächer EINMAL —
/// statt bei jedem Schwenk wie bis 1.222.4.
const kMapWorkerIdleTimeout = Duration(seconds: 60);

/// Die Fächer, wie die Rechnung sie sieht.
class MapWorkerSlots {
  const MapWorkerSlots(this._slots);
  final Map<String, Object?> _slots;

  T get<T>(String name) => _slots[name] as T;
}

/// Ein Auftrag wurde abgesagt, bevor er lief — ein neuerer derselben Spur
/// hat ihn ersetzt, oder sein Provider ist verworfen. Kein Befund
/// (`worthReporting`).
class MapWorkerSuperseded implements Exception {
  const MapWorkerSuperseded();
  @override
  String toString() => 'MapWorkerSuperseded';
}

/// Die Rechnung im Isolate hat geworfen.
class MapWorkerError implements Exception {
  MapWorkerError(this.message, this.remoteStack);
  final String message;
  final String remoteStack;
  @override
  String toString() => 'MapWorkerError: $message\n$remoteStack';
}

/// Das Isolate ist mitten im Auftrag gestorben.
class MapWorkerDied implements Exception {
  const MapWorkerDied();
  @override
  String toString() => 'MapWorkerDied';
}

/// Ein abgegebener Auftrag.
class MapWorkerJob<R> {
  MapWorkerJob._(this._lane, this._run) {
    // Wer absagt und nicht mehr wartet, soll keinen „unbehandelten
    // Fehler" erzeugen; wer wartet, bekommt ihn trotzdem.
    _done.future.ignore();
  }

  final _Lane _lane;
  final Future<Object?> Function() _run;
  final _done = Completer<R>();
  bool _started = false;

  Future<R> get result => _done.future;

  /// Sagt ab, solange der Auftrag noch nicht läuft. Läuft er schon, rechnet
  /// er zu Ende — ein Isolate lässt sich nicht mitten in einer Funktion
  /// anhalten, und das Ergebnis verwirft dann der Aufrufer.
  void cancel() {
    if (_started || _done.isCompleted) return;
    if (identical(_lane.pending, this)) _lane.pending = null;
    _done.completeError(const MapWorkerSuperseded());
  }
}

class _Lane {
  MapWorkerJob<Object?>? running;
  MapWorkerJob<Object?>? pending;
}

/// Wohin ein Auftrag gerechnet wird.
abstract class _Backend {
  Future<Object?> execute(
      Function fn, Object? params, Map<String, Object?> slots);
  void dispose();
}

/// Der Zeichen-Weg der App. Über [mapWorkerProvider] holen.
class MapWorker {
  MapWorker._(this._backend, {required this.serialLanes});

  /// Das dauerhafte Isolate — im Browser der Rückfall.
  factory MapWorker.isolate(
          {Duration idleTimeout = kMapWorkerIdleTimeout}) =>
      kIsWeb
          ? MapWorker._(_ComputeBackend(), serialLanes: true)
          : MapWorker._(_IsolateBackend(idleTimeout), serialLanes: true);

  /// Jeder Auftrag einzeln über `boundedCompute`, mit den Gittern im
  /// Gepäck. [serialLanes] `false` ist der Weg der Widget-Tests: Dort
  /// meldet sich ein `compute` aus der FakeAsync-Zone nie zurück, und
  /// eine wartende Spur hinge dahinter für immer.
  @visibleForTesting
  factory MapWorker.compute({bool serialLanes = true}) =>
      MapWorker._(_ComputeBackend(), serialLanes: serialLanes);

  /// Rechnet über [execute] — für Tests, die zählen wollen, was wirklich
  /// gerechnet wurde.
  @visibleForTesting
  factory MapWorker.custom(
          Future<Object?> Function(
                  Function fn, Object? params, Map<String, Object?> slots)
              execute) =>
      MapWorker._(_CustomBackend(execute), serialLanes: true);

  _Backend _backend;
  final bool serialLanes;
  final _lanes = <String, _Lane>{};
  bool _disposed = false;

  /// Gibt einen Auftrag ab. [slots] nennt die Gitter, die er braucht —
  /// gesendet wird nur, was sich seit dem letzten Mal geändert hat.
  ///
  /// Ein Fachname mit `#` gehört zu einer FAMILIE (`forestBlock#datei`):
  /// Nennt ein Auftrag ein Fach einer Familie, gibt das Isolate alle
  /// anderen dieser Familie frei. So liegen dort nur die Blöcke des
  /// aktuellen Fensters, nicht alle je gesehenen.
  MapWorkerJob<R> submit<P, R>(
    String lane,
    MapWorkerFn<P, R> fn,
    P params, {
    Map<String, Object?> slots = const {},
  }) {
    final l = _lanes.putIfAbsent(lane, _Lane.new);
    final job = MapWorkerJob<R>._(l, () => _execute(fn, params, slots));
    if (!serialLanes || l.running == null) {
      _start(l, job);
    } else {
      l.pending?.cancel();
      l.pending = job;
    }
    return job;
  }

  Future<Object?> _execute(
      Function fn, Object? params, Map<String, Object?> slots) async {
    if (_disposed) throw const MapWorkerSuperseded();
    try {
      return await _backend.execute(fn, params, slots);
    } on _BackendUnavailable {
      // Das Isolate startet nicht (mehr): Rest der Sitzung ohne.
      _backend.dispose();
      _backend = _ComputeBackend();
      return _backend.execute(fn, params, slots);
    }
  }

  void _start<R>(_Lane lane, MapWorkerJob<R> job) {
    job._started = true;
    if (serialLanes) lane.running = job;
    job._run().then((value) {
      if (!job._done.isCompleted) job._done.complete(value as R);
    }, onError: (Object e, StackTrace s) {
      if (!job._done.isCompleted) job._done.completeError(e, s);
    }).whenComplete(() {
      if (!serialLanes || !identical(lane.running, job)) return;
      lane.running = null;
      final next = lane.pending;
      lane.pending = null;
      if (next != null) _start(lane, next);
    });
  }

  /// Wie oft ein Gitter ins Isolate ging — für den Test.
  @visibleForTesting
  int get debugSlotTransfers {
    final b = _backend;
    return b is _IsolateBackend ? b.slotTransfers : 0;
  }

  /// Welche Fächer gerade im Isolate liegen — für den Test.
  @visibleForTesting
  Set<String> get debugSlotsHeld {
    final b = _backend;
    return b is _IsolateBackend ? b._sent.keys.toSet() : const {};
  }

  /// Wie oft das Isolate in Ruhe beendet wurde — für den Test.
  @visibleForTesting
  int get debugRetirements {
    final b = _backend;
    return b is _IsolateBackend ? b.retirements : 0;
  }

  /// Rechnet die Sitzung über den Rückfall statt über das Isolate?
  @visibleForTesting
  bool get debugUsesFallback => _backend is _ComputeBackend;

  void dispose() {
    _disposed = true;
    for (final lane in _lanes.values) {
      lane.pending?.cancel();
    }
    _backend.dispose();
  }
}

/// Gibt einen Auftrag aus einem Provider heraus ab und sagt ihn ab, wenn
/// der Provider verworfen wird, bevor er lief.
Future<R> runOnMapWorker<P, R>(
  Ref ref,
  String lane,
  MapWorkerFn<P, R> fn,
  P params, {
  Map<String, Object?> slots = const {},
}) {
  final job =
      ref.read(mapWorkerProvider).submit(lane, fn, params, slots: slots);
  ref.onDispose(job.cancel);
  return job.result;
}

/// Der eine Zeichen-Weg der Sitzung.
final mapWorkerProvider = Provider<MapWorker>((ref) {
  final worker = MapWorker.isolate();
  ref.onDispose(worker.dispose);
  return worker;
});

class _CustomBackend implements _Backend {
  _CustomBackend(this._execute);
  final Future<Object?> Function(
      Function fn, Object? params, Map<String, Object?> slots) _execute;

  @override
  Future<Object?> execute(
          Function fn, Object? params, Map<String, Object?> slots) =>
      _execute(fn, params, slots);

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Rückfall: je Auftrag ein `compute`.

class _ComputeBackend implements _Backend {
  @override
  Future<Object?> execute(
          Function fn, Object? params, Map<String, Object?> slots) =>
      boundedCompute(_runOnce, (fn: fn, params: params, slots: slots));

  @override
  void dispose() {}
}

Object? _runOnce(
        ({Function fn, Object? params, Map<String, Object?> slots}) input) =>
    // ignore: avoid_dynamic_calls
    (input.fn as dynamic)(MapWorkerSlots(input.slots), input.params);

// ---------------------------------------------------------------------------
// Das Isolate.

class _BackendUnavailable implements Exception {}

class _IsolateBackend implements _Backend {
  _IsolateBackend(this._idleTimeout);

  final Duration _idleTimeout;
  Timer? _idle;
  Isolate? _isolate;
  SendPort? _toWorker;
  ReceivePort? _fromWorker;
  Future<void>? _starting;
  Completer<SendPort>? _handshake;
  int _deaths = 0;
  int _nextId = 0;
  final _open = <int, Completer<Object?>>{};

  /// Was im Isolate liegt — je Fach das zuletzt gesendete Objekt.
  final _sent = <String, Object?>{};

  /// Wie oft ein Fach hinüberging — nur für den Test.
  @visibleForTesting
  int slotTransfers = 0;

  @override
  Future<Object?> execute(
      Function fn, Object? params, Map<String, Object?> slots) async {
    if (_deaths >= kMapWorkerMaxDeaths) throw _BackendUnavailable();
    await (_starting ??= _spawn());
    final port = _toWorker;
    if (port == null) throw _BackendUnavailable();
    final families = {
      for (final key in slots.keys)
        if (key.contains('#')) key.substring(0, key.indexOf('#') + 1),
    };
    if (families.isNotEmpty) {
      final stale = [
        for (final key in _sent.keys)
          if (!slots.containsKey(key) && families.any(key.startsWith)) key,
      ];
      for (final key in stale) {
        port.send(['drop', key]);
        _sent.remove(key);
      }
    }
    for (final entry in slots.entries) {
      if (_sent.containsKey(entry.key) &&
          identical(_sent[entry.key], entry.value)) {
        continue;
      }
      port.send(['slot', entry.key, entry.value]);
      _sent[entry.key] = entry.value;
      slotTransfers++;
    }
    final id = _nextId++;
    final done = Completer<Object?>();
    _open[id] = done;
    port.send(['job', id, fn, params]);
    return done.future.whenComplete(_armIdle);
  }

  void _armIdle() {
    if (_open.isNotEmpty || _isolate == null) return;
    _idle?.cancel();
    _idle = Timer(_idleTimeout, _retire);
  }

  /// Ruhe: Isolate beenden, Fächer vergessen. Kein Tod — der Port wird
  /// VOR dem Beenden geschlossen, die Ausgangsmeldung zählt also nicht.
  void _retire() {
    if (_open.isNotEmpty) return;
    _fromWorker?.close();
    _fromWorker = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _toWorker = null;
    _starting = null;
    _handshake = null;
    _sent.clear();
    retirements++;
  }

  /// Wie oft das Isolate in Ruhe beendet wurde — für den Test.
  int retirements = 0;

  Future<void> _spawn() async {
    final from = ReceivePort();
    final handshake = _handshake = Completer<SendPort>();
    from.listen((message) {
      if (message is SendPort) {
        if (!handshake.isCompleted) handshake.complete(message);
        return;
      }
      if (message == null) {
        _died(); // onExit
        return;
      }
      final m = message as List;
      final done = _open.remove(m[0] as int);
      if (done == null) return;
      if (m[1] == true) {
        final value = m[2];
        done.complete(value is TransferableTypedData
            ? value.materialize().asUint8List()
            : value);
      } else {
        done.completeError(MapWorkerError(m[2] as String, m[3] as String));
      }
    });
    try {
      _isolate = await Isolate.spawn(_workerMain, from.sendPort,
          onExit: from.sendPort, debugName: 'map_worker');
      _fromWorker = from;
      _toWorker = await handshake.future;
    } catch (_) {
      // Kein Isolate zu haben ist kein Fehler der App: Der Rückfall
      // rechnet weiter (siehe MapWorker._execute).
      from.close();
      _deaths = kMapWorkerMaxDeaths;
    }
  }

  void _died() {
    _deaths++;
    // Vor dem Händedruck gestorben: Wer auf den Start wartet, soll es
    // erfahren, statt für immer zu warten.
    final handshake = _handshake;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(const MapWorkerDied());
    }
    _fromWorker?.close();
    _fromWorker = null;
    _toWorker = null;
    _isolate = null;
    _starting = null;
    _sent.clear();
    final open = _open.values.toList();
    _open.clear();
    for (final done in open) {
      done.completeError(const MapWorkerDied());
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _fromWorker?.close();
    _fromWorker = null;
    _toWorker = null;
    _deaths = kMapWorkerMaxDeaths;
    for (final done in _open.values) {
      done.completeError(const MapWorkerSuperseded());
    }
    _open.clear();
  }
}

void _workerMain(SendPort toMain) {
  final inbox = ReceivePort();
  toMain.send(inbox.sendPort);
  final slots = <String, Object?>{};
  final view = MapWorkerSlots(slots);
  inbox.listen((message) {
    final m = message as List;
    switch (m[0]) {
      case 'slot':
        slots[m[1] as String] = m[2];
      case 'drop':
        slots.remove(m[1] as String);
      case 'job':
        final id = m[1] as int;
        try {
          // ignore: avoid_dynamic_calls
          final Object? result = (m[2] as dynamic)(view, m[3]);
          toMain.send([
            id,
            true,
            result is Uint8List
                ? TransferableTypedData.fromList([result])
                : result,
          ]);
        } catch (e, s) {
          toMain.send([id, false, e.toString(), s.toString()]);
        }
    }
  });
}
