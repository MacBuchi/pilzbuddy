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
//
// Im Browser gibt es keine Isolates. Dort rechnet seit #689 (B2) ein Web
// Worker (`map_worker.js`, ohne Flutter übersetzt aus
// `lib/map_worker_main.dart`) — mit denselben Spuren, Fächern und
// Rückfällen. Weil dorthin nur Bytes reisen, nennt jede Rechnung ihre
// Codecs ([MapWorkerTask], `features/map/map_worker_tasks.dart`). Lädt der
// Worker nicht, rechnet der Hauptthread wie bis 1.225.x.
import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bounded_compute.dart';
import 'map_worker_task.dart';
import 'map_worker_transport.dart';
import 'map_worker_web_stub.dart'
    if (dart.library.js_interop) 'map_worker_web.dart';

export 'map_worker_task.dart'
    show MapWorkerFn, MapWorkerLoad, MapWorkerSlots, MapWorkerTask;

/// Die Gegenseite kann nicht selbst laden (Isolate, Rückfall, kein
/// Worker) — der Aufrufer lädt dann wie bisher selbst. Kein Befund.
class MapWorkerCannotLoad implements Exception {
  const MapWorkerCannotLoad();
  @override
  String toString() => 'MapWorkerCannotLoad';
}

/// Stirbt das Isolate so oft, rechnet der Rest der Sitzung ohne.
const kMapWorkerMaxDeaths = 3;

/// So lange ohne Auftrag, dann beendet sich das Isolate und gibt seine
/// Fächer frei. Gemessen auf dem Pixel XL: Wald, Höhe und Regenstapel
/// hielten sonst 66 MB mehr in Ruhe, die ganze Sitzung lang. Der
/// nächste Auftrag startet ein neues und kopiert die Fächer EINMAL —
/// statt bei jedem Schwenk wie bis 1.222.4.
const kMapWorkerIdleTimeout = Duration(seconds: 60);

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

typedef _Task = MapWorkerTask<Object?, Object?>;

/// Wohin ein Auftrag gerechnet wird.
abstract class _Backend {
  Future<Object?> execute(
      _Task task, Object? params, Map<String, Object?> slots);
  void dispose();
}

/// Der Zeichen-Weg der App. Über [mapWorkerProvider] holen.
class MapWorker {
  MapWorker._(this._backend, {required this.serialLanes});

  /// Das dauerhafte Isolate — im Browser der Web Worker, und wo es den
  /// nicht gibt, der Rückfall.
  factory MapWorker.isolate(
      {Duration idleTimeout = kMapWorkerIdleTimeout}) {
    if (!kIsWeb) {
      return MapWorker._(
          _ChannelBackend(_IsolateTransport.new, idleTimeout,
              loadsAssets: false),
          serialLanes: true);
    }
    final web = createWebWorkerTransport();
    return MapWorker._(
        web == null
            ? _ComputeBackend()
            : _ChannelBackend(() => web, idleTimeout, loadsAssets: true),
        serialLanes: true);
  }

  /// Über eine eigene Leitung — für den Test, der den Weg des Browsers
  /// (Codecs statt Objekte) auf der VM nachfährt.
  @visibleForTesting
  factory MapWorker.transport(MapWorkerTransport Function() open,
          {Duration idleTimeout = kMapWorkerIdleTimeout,
          bool loadsAssets = false}) =>
      MapWorker._(
          _ChannelBackend(open, idleTimeout, loadsAssets: loadsAssets),
          serialLanes: true);

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
    MapWorkerTask<P, R> task,
    P params, {
    Map<String, Object?> slots = const {},
  }) {
    final l = _lanes.putIfAbsent(lane, _Lane.new);
    final job = MapWorkerJob<R>._(l, () => _execute(task, params, slots));
    if (!serialLanes || l.running == null) {
      _start(l, job);
    } else {
      l.pending?.cancel();
      l.pending = job;
    }
    return job;
  }

  Future<Object?> _execute(
      _Task task, Object? params, Map<String, Object?> slots) async {
    if (_disposed) throw const MapWorkerSuperseded();
    try {
      return await _backend.execute(task, params, slots);
    } on _BackendUnavailable {
      // Das Isolate startet nicht (mehr): Rest der Sitzung ohne.
      _backend.dispose();
      _backend = _ComputeBackend();
      return _backend.execute(task, params, slots);
    }
  }

  /// Kann die Gegenseite Gitter selbst laden ([loadAsset])? Nur der Web
  /// Worker, solange er nicht ausgefallen ist.
  bool get loadsAssets {
    final b = _backend;
    return !_disposed && b is _ChannelBackend && b.loadsAssets;
  }

  /// Lässt die Gegenseite [url] laden, mit [load] dekodieren und das
  /// Gitter als Fach [slot] ablegen (#689, B3). Das zurückgegebene Gitter
  /// gilt danach als drüben: Ein Auftrag, der es als [slot] nennt, schickt
  /// es nicht noch einmal — und nach einer Ruhe oder einem Neustart lädt
  /// die Gegenseite es wieder selbst, statt es vom Hauptthread zu bekommen.
  ///
  /// Wirft [MapWorkerCannotLoad], wenn es keine solche Gegenseite gibt;
  /// was die Dekodierung drüben wirft, kommt als [MapWorkerError].
  Future<R> loadAsset<R>(MapWorkerLoad<R> load,
      {String? slot, required String manifest, required String url}) async {
    final b = _backend;
    if (!loadsAssets || b is! _ChannelBackend) {
      throw const MapWorkerCannotLoad();
    }
    try {
      return await b.load(load, slot, manifest, url) as R;
    } on _BackendUnavailable {
      throw const MapWorkerCannotLoad();
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
    return b is _ChannelBackend ? b.slotTransfers : 0;
  }

  /// Welche Fächer gerade im Isolate liegen — für den Test.
  @visibleForTesting
  Set<String> get debugSlotsHeld {
    final b = _backend;
    return b is _ChannelBackend ? b._sent.keys.toSet() : const {};
  }

  /// Wie oft das Isolate in Ruhe beendet wurde — für den Test.
  @visibleForTesting
  int get debugRetirements {
    final b = _backend;
    return b is _ChannelBackend ? b.retirements : 0;
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
  MapWorkerTask<P, R> task,
  P params, {
  Map<String, Object?> slots = const {},
}) {
  final job =
      ref.read(mapWorkerProvider).submit(lane, task, params, slots: slots);
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
          _Task task, Object? params, Map<String, Object?> slots) =>
      _execute(task.fn, params, slots);

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Rückfall: je Auftrag ein `compute`.

class _ComputeBackend implements _Backend {
  @override
  Future<Object?> execute(
          _Task task, Object? params, Map<String, Object?> slots) =>
      boundedCompute(_runOnce, (fn: task.fn, params: params, slots: slots));

  @override
  void dispose() {}
}

Object? _runOnce(
        ({Function fn, Object? params, Map<String, Object?> slots}) input) =>
    // ignore: avoid_dynamic_calls
    (input.fn as dynamic)(MapWorkerSlots(input.slots), input.params);

// ---------------------------------------------------------------------------
// Die dauerhafte Gegenseite — Isolate oder Web Worker.

class _BackendUnavailable implements Exception {}

/// Wie ein selbst geladenes Fach wiederherzustellen ist — und welches
/// Objekt die App dafür hält.
typedef _Origin = ({
  MapWorkerLoad<Object?> load,
  String manifest,
  String url,
  Object value,
});

class _ChannelBackend implements _Backend {
  _ChannelBackend(this._newTransport, this._idleTimeout,
      {required this.loadsAssets});

  final MapWorkerTransport Function() _newTransport;
  final bool loadsAssets;

  /// Fächer, die die Gegenseite selbst geladen hat. Überdauern Ruhe und
  /// Tod: Danach lädt sie sie neu, statt sie vom Hauptthread zu bekommen.
  final _origins = <String, _Origin>{};
  final Duration _idleTimeout;
  Timer? _idle;
  MapWorkerTransport? _transport;
  Future<void>? _starting;
  int _deaths = 0;
  int _nextId = 0;
  final _open = <int, Completer<Object?>>{};

  /// Was drüben liegt — je Fach das zuletzt gesendete Objekt.
  final _sent = <String, Object?>{};

  /// Wie oft ein Fach hinüberging — nur für den Test.
  int slotTransfers = 0;

  /// Wie oft die Gegenseite in Ruhe beendet wurde — für den Test.
  int retirements = 0;

  @override
  Future<Object?> execute(
      _Task task, Object? params, Map<String, Object?> slots) async {
    if (_deaths >= kMapWorkerMaxDeaths) throw _BackendUnavailable();
    _idle?.cancel();
    await (_starting ??= _spawn());
    final transport = _transport;
    if (transport == null) throw _BackendUnavailable();
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
        transport.drop(key);
        _sent.remove(key);
      }
    }
    for (final entry in slots.entries) {
      if (_sent.containsKey(entry.key) &&
          identical(_sent[entry.key], entry.value)) {
        continue;
      }
      final origin = _origins[entry.key];
      if (origin != null && identical(origin.value, entry.value)) {
        _restore(transport, entry.key, origin);
        _sent[entry.key] = entry.value;
        continue;
      }
      _origins.remove(entry.key);
      transport.slot(task, entry.key, entry.value);
      _sent[entry.key] = entry.value;
      slotTransfers++;
    }
    final id = _nextId++;
    final done = Completer<Object?>();
    _open[id] = done;
    transport.job(id, task, params);
    return done.future.whenComplete(_armIdle);
  }

  /// Lädt ein selbst geladenes Fach drüben neu. Die Gegenseite arbeitet
  /// ihre Nachrichten der Reihe nach ab, der folgende Auftrag findet es
  /// also vor. Scheitert das Laden, geht es beim nächsten Mal wieder als
  /// Fach hinüber.
  void _restore(MapWorkerTransport transport, String slot, _Origin origin) {
    final id = _nextId++;
    final done = Completer<Object?>();
    _open[id] = done;
    done.future.then<void>((_) {}, onError: (Object e) {
      if (e is! MapWorkerError) return; // Tod: beim nächsten Mal neu laden
      if (identical(_origins[slot], origin)) _origins.remove(slot);
      _sent.remove(slot);
    }).whenComplete(_armIdle);
    transport.load(id, origin.load,
        slot: slot, manifest: origin.manifest, url: origin.url, reply: false);
  }

  Future<Object?> load(MapWorkerLoad<Object?> load, String? slot,
      String manifest, String url) async {
    if (_deaths >= kMapWorkerMaxDeaths) throw _BackendUnavailable();
    _idle?.cancel();
    await (_starting ??= _spawn());
    final transport = _transport;
    if (transport == null || !transport.loadsAssets) {
      throw _BackendUnavailable();
    }
    if (slot != null) {
      // Drüben wird das Fach ersetzt — was vorher dort lag, gilt nicht mehr.
      _sent.remove(slot);
      _origins.remove(slot);
    }
    final id = _nextId++;
    final done = Completer<Object?>();
    _open[id] = done;
    transport.load(id, load,
        slot: slot, manifest: manifest, url: url, reply: true);
    final value = await done.future.whenComplete(_armIdle);
    // Ist die Leitung inzwischen eine andere (Tod), liegt das Fach dort
    // nicht — dann hilft die Herkunft, es beim nächsten Auftrag zu laden.
    if (slot != null && value != null) {
      _origins[slot] =
          (load: load, manifest: manifest, url: url, value: value);
      if (identical(_transport, transport)) _sent[slot] = value;
    }
    return value;
  }

  void _armIdle() {
    if (_open.isNotEmpty || _transport == null) return;
    _idle?.cancel();
    _idle = Timer(_idleTimeout, _retire);
  }

  /// Ruhe: Gegenseite beenden, Fächer vergessen. Kein Tod — die Leitung
  /// meldet nach `close` nichts mehr.
  void _retire() {
    if (_open.isNotEmpty) return;
    _transport?.close();
    _transport = null;
    _starting = null;
    _sent.clear();
    retirements++;
  }

  Future<void> _spawn() async {
    final transport = _newTransport();
    try {
      await transport.open((
        result: (id, value) => _open.remove(id)?.complete(value),
        error: (id, message, stack) => _open
            .remove(id)
            ?.completeError(MapWorkerError(message, stack)),
        died: () => _died(transport),
      ));
      _transport = transport;
    } catch (_) {
      // Keine Gegenseite zu haben ist kein Fehler der App: Der Rückfall
      // rechnet weiter (siehe MapWorker._execute).
      transport.close();
      _deaths = kMapWorkerMaxDeaths;
    }
  }

  void _died(MapWorkerTransport transport) {
    // Eine Leitung, die schon ersetzt ist, zählt nicht mehr.
    if (_transport != null && !identical(_transport, transport)) return;
    _deaths++;
    transport.close();
    _transport = null;
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
    _transport?.close();
    _transport = null;
    _deaths = kMapWorkerMaxDeaths;
    for (final done in _open.values) {
      done.completeError(const MapWorkerSuperseded());
    }
    _open.clear();
  }
}

// ---------------------------------------------------------------------------
// Das Isolate.

class _IsolateTransport implements MapWorkerTransport {
  Isolate? _isolate;
  SendPort? _toWorker;
  ReceivePort? _fromWorker;

  @override
  Future<void> open(MapWorkerReplies replies) async {
    final from = _fromWorker = ReceivePort();
    final handshake = Completer<SendPort>();
    from.listen((message) {
      if (message is SendPort) {
        if (!handshake.isCompleted) handshake.complete(message);
        return;
      }
      if (message == null) {
        // onExit. Vor dem Händedruck gestorben: Wer auf den Start wartet,
        // soll es erfahren, statt für immer zu warten.
        if (!handshake.isCompleted) {
          handshake.completeError(const MapWorkerDied());
        }
        replies.died();
        return;
      }
      final m = message as List;
      final id = m[0] as int;
      if (m[1] == true) {
        final value = m[2];
        replies.result(
            id,
            value is TransferableTypedData
                ? value.materialize().asUint8List()
                : value);
      } else {
        replies.error(id, m[2] as String, m[3] as String);
      }
    });
    _isolate = await Isolate.spawn(_workerMain, from.sendPort,
        onExit: from.sendPort, debugName: 'map_worker');
    _toWorker = await handshake.future;
  }

  @override
  void slot(_Task task, String name, Object? value) =>
      _toWorker?.send(['slot', name, value]);

  @override
  void drop(String name) => _toWorker?.send(['drop', name]);

  @override
  bool get loadsAssets => false;

  @override
  void load(int id, MapWorkerLoad<Object?> load,
          {String? slot,
          required String manifest,
          required String url,
          required bool reply}) =>
      throw UnsupportedError('Das Isolate lädt nicht selbst');

  @override
  void job(int id, _Task task, Object? params) =>
      _toWorker?.send(['job', id, task.fn, params]);

  /// Der Port wird VOR dem Beenden geschlossen — die Ausgangsmeldung
  /// zählt so nicht als Tod.
  @override
  void close() {
    _fromWorker?.close();
    _fromWorker = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _toWorker = null;
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
