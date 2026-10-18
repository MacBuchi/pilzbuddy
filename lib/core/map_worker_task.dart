// Was eine Rechnung des Zeichen-Wegs ist — ohne Flutter, weil der Web
// Worker (#689, B2) dieselbe Beschreibung liest wie die App.
import 'dart:typed_data';

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

/// Ein Gitter, das der Worker SELBST lädt (#689, B3): Er holt die gepackte
/// Datei über ihre Adresse, packt sie aus, dekodiert sie mit [decode] und
/// legt das Ergebnis als Fach ab. Im Browser ist das der Weg, auf dem die
/// großen Asset-Gitter den Hauptthread nie berühren — dort kostet jede
/// Byte-Menge, die zwischen Wasm und JavaScript wandert, Zeit auf ihm,
/// und `compute` rechnet ohnehin dort.
class MapWorkerLoad<R> {
  const MapWorkerLoad(this.id, this.decode, {required this.result});

  /// Eindeutig über alle Ladeaufträge — der Worker schlägt darüber nach.
  final String id;

  /// Manifest (JSON-Text) und die GEPACKTEN Bytes rein, Gitter raus.
  /// Muss top-level sein; auf dem Gerät läuft sie über `boundedCompute`.
  final R Function(String manifest, Uint8List gzipped) decode;
  final WireCodec<R> result;

  Object? call(String manifest, Uint8List gzipped) =>
      decode(manifest, gzipped);

  Function get fn => decode;

  WireBytes encodeResult(Object? value) => result.encode(value as R);
  Object? decodeResult(WireBytes bytes) =>
      result.decode(bytes.buffer, bytes.length);
}
