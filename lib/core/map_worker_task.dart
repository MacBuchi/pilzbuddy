// Was eine Rechnung des Zeichen-Wegs ist — ohne Flutter, weil der Web
// Worker (#689, B2) dieselbe Beschreibung liest wie die App.
import 'wire.dart';

/// Die Rechnung eines Auftrags. Muss eine top-level- oder statische
/// Funktion sein — sie reist in ein anderes Isolate.
typedef MapWorkerFn<P, R> = R Function(MapWorkerSlots slots, P params);

/// Die Fächer, wie die Rechnung sie sieht.
class MapWorkerSlots {
  const MapWorkerSlots(this._slots);
  final Map<String, Object?> _slots;

  T get<T>(String name) => _slots[name] as T;
}

/// Eine Rechnung samt dem, was ein Web Worker zusätzlich braucht: einen
/// Namen statt der Funktion (Funktionen reisen nicht in einen Worker) und
/// je einen Codec für Eingabe, Ergebnis und jedes Fach.
///
/// Im Isolate reisen Eingabe und Fächer wie sie sind; die Codecs liest
/// dort niemand.
class MapWorkerTask<P, R> {
  const MapWorkerTask(
    this.id,
    this.run, {
    required this.params,
    required this.result,
    this.slots = const {},
  });

  /// Eindeutig über alle Rechnungen — der Worker schlägt darüber nach.
  final String id;
  final MapWorkerFn<P, R> run;
  final WireCodec<P> params;
  final WireCodec<R> result;

  /// Je Fachname ein Codec. Ein Name mit `#` am Ende steht für eine
  /// Familie (`forestBlock#`): Er gilt für jedes Fach, das so beginnt.
  final Map<String, WireCodec<Object?>> slots;

  /// Der Codec für das Fach [name].
  WireCodec<Object?> slotCodec(String name) {
    final exact = slots[name];
    if (exact != null) return exact;
    final hash = name.indexOf('#');
    final family = hash < 0 ? null : slots[name.substring(0, hash + 1)];
    if (family != null) return family;
    throw ArgumentError('Fach $name ist für $id nicht beschrieben');
  }

  /// [run] ohne Typargumente — so reist es ins Isolate. Über einen Typ
  /// `MapWorkerTask<Object?, Object?>` gelesen, scheiterte [run] selbst an
  /// der Laufzeitprüfung (der Parameter steht kontravariant).
  Function get fn => run;

  /// Ruft [run] mit den richtigen Typargumenten auf — der Worker kennt sie
  /// nur hier.
  Object? call(MapWorkerSlots slots, Object? params) =>
      run(slots, params as P);

  WireBytes encodeParams(Object? value) => params.encode(value as P);
  Object? decodeParams(WireBytes bytes) =>
      params.decode(bytes.buffer, bytes.length);
  WireBytes encodeResult(Object? value) => result.encode(value as R);
  Object? decodeResult(WireBytes bytes) =>
      result.decode(bytes.buffer, bytes.length);
}
