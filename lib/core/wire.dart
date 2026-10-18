// Ein kleines Binärformat für den Weg in den Web Worker (#689, B2).
//
// Zwischen zwei Isolates reisen Dart-Objekte, wie sie sind. In einen Web
// Worker reist nur, was der Browser klonen kann — Zahlen, Zeichenketten,
// `ArrayBuffer`. Ein Waldgitter oder ein Record kommt dort nicht an. Jede
// Rechnung des Zeichen-Wegs nennt deshalb für ihre Fächer, Eingaben und
// ihr Ergebnis je einen [WireCodec]; geschrieben wird in EINEN Puffer, und
// der geht ohne Kopie hinüber (übergeben, nicht geklont).
//
// Ohne Flutter, wie alles, was der Worker übersetzt
// (`test/map_worker_imports_test.dart`).
import 'dart:convert';
import 'dart:typed_data';

/// Liest und schreibt genau einen Typ. Die Leseseite muss den Typ mit
/// seinen Typargumenten wiederherstellen — `List<ForestGrid>`, nicht
/// `List<Object?>`: Die Rechnungen casten (`slots.get<…>`).
abstract class WireCodec<T> {
  const WireCodec();
  void write(WireWriter w, T value);
  T read(WireReader r);

  /// Ein Wert in einen eigenen Puffer — die Form, in der er reist.
  WireBytes encode(T value) {
    final w = WireWriter();
    write(w, value);
    return w.finish();
  }

  T decode(ByteBuffer buffer, int length) =>
      read(WireReader(buffer, length));
}

/// Ein geschriebener Puffer: [buffer] ist womöglich größer als der Inhalt
/// — so geht er ohne letzte Kopie hinüber.
typedef WireBytes = ({ByteBuffer buffer, int length});

class WireWriter {
  WireWriter([int capacity = 256]) : _bytes = Uint8List(capacity) {
    _data = ByteData.sublistView(_bytes);
  }

  Uint8List _bytes;
  late ByteData _data;
  int _length = 0;

  WireBytes finish() => (buffer: _bytes.buffer, length: _length);

  void _ensure(int more) {
    final need = _length + more;
    if (need <= _bytes.length) return;
    var size = _bytes.length * 2;
    while (size < need) {
      size *= 2;
    }
    _bytes = Uint8List(size)..setRange(0, _length, _bytes);
    _data = ByteData.sublistView(_bytes);
  }

  /// Typisierte Felder werden beim Lesen als Sicht angelegt, und eine
  /// Sicht verlangt eine Startadresse, die ein Vielfaches ihrer
  /// Elementgröße ist.
  void _align(int to) {
    final pad = (to - _length % to) % to;
    _ensure(pad);
    _length += pad;
  }

  void u8(int v) {
    _ensure(1);
    _bytes[_length++] = v;
  }

  void boolean(bool v) => u8(v ? 1 : 0);

  /// Eine ganze Zahl — als 64-Bit-Gleitkommazahl, weil der Worker in
  /// JavaScript läuft und dort jede Zahl eine ist. Exakt bis 2^53.
  void int64(int v) => float64(v.toDouble());

  void float64(double v) {
    _align(8);
    _ensure(8);
    _data.setFloat64(_length, v, Endian.little);
    _length += 8;
  }

  void uint32(int v) {
    _align(4);
    _ensure(4);
    _data.setUint32(_length, v, Endian.little);
    _length += 4;
  }

  void string(String v) => bytes(utf8.encode(v));

  void nullable<T>(T? v, void Function(T) write) {
    boolean(v != null);
    if (v != null) write(v);
  }

  void bytes(Uint8List v) {
    uint32(v.length);
    _ensure(v.length);
    _bytes.setRange(_length, _length + v.length, v);
    _length += v.length;
  }

  void _typed(TypedData v, int elements) {
    uint32(elements);
    _align(8);
    final view = v.buffer.asUint8List(v.offsetInBytes, v.lengthInBytes);
    _ensure(view.length);
    _bytes.setRange(_length, _length + view.length, view);
    _length += view.length;
  }

  void uint16s(Uint16List v) => _typed(v, v.length);
  void int16s(Int16List v) => _typed(v, v.length);
  void int32s(Int32List v) => _typed(v, v.length);
  void float32s(Float32List v) => _typed(v, v.length);
  void float64s(Float64List v) => _typed(v, v.length);

  void list<T>(List<T> v, void Function(T) write) {
    uint32(v.length);
    for (final e in v) {
      write(e);
    }
  }

  void dateTime(DateTime v) {
    boolean(v.isUtc);
    int64(v.microsecondsSinceEpoch);
  }
}

class WireReader {
  WireReader(this._buffer, this._end)
      : _bytes = _buffer.asUint8List(0, _end),
        _data = _buffer.asByteData(0, _end);

  final ByteBuffer _buffer;
  final int _end;
  final Uint8List _bytes;
  final ByteData _data;
  int _at = 0;

  bool get done => _at == _end;

  void _align(int to) => _at += (to - _at % to) % to;

  int u8() => _bytes[_at++];
  bool boolean() => u8() != 0;
  int int64() => float64().toInt();

  double float64() {
    _align(8);
    final v = _data.getFloat64(_at, Endian.little);
    _at += 8;
    return v;
  }

  int uint32() {
    _align(4);
    final v = _data.getUint32(_at, Endian.little);
    _at += 4;
    return v;
  }

  String string() => utf8.decode(bytes());

  T? nullable<T>(T Function() read) => boolean() ? read() : null;

  /// Eine SICHT in den Puffer, keine Kopie — der Puffer gehört nach dem
  /// Übergeben ohnehin dem Leser.
  Uint8List bytes() {
    final n = uint32();
    final v = _buffer.asUint8List(_at, n);
    _at += n;
    return v;
  }

  int _typedStart(int elements, int size) {
    _align(8);
    final start = _at;
    _at += elements * size;
    return start;
  }

  Uint16List uint16s() {
    final n = uint32();
    return _buffer.asUint16List(_typedStart(n, 2), n);
  }

  Int16List int16s() {
    final n = uint32();
    return _buffer.asInt16List(_typedStart(n, 2), n);
  }

  Int32List int32s() {
    final n = uint32();
    return _buffer.asInt32List(_typedStart(n, 4), n);
  }

  Float32List float32s() {
    final n = uint32();
    return _buffer.asFloat32List(_typedStart(n, 4), n);
  }

  Float64List float64s() {
    final n = uint32();
    return _buffer.asFloat64List(_typedStart(n, 8), n);
  }

  List<T> list<T>(T Function() read) =>
      List<T>.generate(uint32(), (_) => read(), growable: false);

  DateTime dateTime() {
    final utc = boolean();
    return DateTime.fromMicrosecondsSinceEpoch(int64(), isUtc: utc);
  }
}

/// Ein Codec aus zwei Funktionen — die Form, in der die Rechnungen ihre
/// Codecs schreiben.
class WireFn<T> extends WireCodec<T> {
  const WireFn(this._write, this._read);
  final void Function(WireWriter, T) _write;
  final T Function(WireReader) _read;

  @override
  void write(WireWriter w, T value) => _write(w, value);
  @override
  T read(WireReader r) => _read(r);
}

/// [inner] oder `null`.
class WireNullable<T extends Object> extends WireCodec<T?> {
  const WireNullable(this.inner);
  final WireCodec<T> inner;

  @override
  void write(WireWriter w, T? value) =>
      w.nullable(value, (v) => inner.write(w, v));
  @override
  T? read(WireReader r) => r.nullable(() => inner.read(r));
}

/// Eine Liste von [inner].
class WireList<T> extends WireCodec<List<T>> {
  const WireList(this.inner);
  final WireCodec<T> inner;

  @override
  void write(WireWriter w, List<T> value) =>
      w.list(value, (v) => inner.write(w, v));
  @override
  List<T> read(WireReader r) => r.list(() => inner.read(r));
}

/// [inner] als `WireCodec<Object?>` — die Fächer-Tabelle einer Rechnung
/// mischt Typen.
class WireSlot<T> extends WireCodec<Object?> {
  const WireSlot(this.inner);
  final WireCodec<T> inner;

  @override
  void write(WireWriter w, Object? value) => inner.write(w, value as T);
  @override
  Object? read(WireReader r) => inner.read(r);
}

/// Ein Bild oder sonst rohe Bytes.
const wireBytes = WireFn<Uint8List>(_writeBytes, _readBytes);
void _writeBytes(WireWriter w, Uint8List v) => w.bytes(v);
Uint8List _readBytes(WireReader r) => r.bytes();

const wireString = WireFn<String>(_writeString, _readString);
void _writeString(WireWriter w, String v) => w.string(v);
String _readString(WireReader r) => r.string();

/// Eine Menge ganzer Zahlen (Kachelschlüssel) — als Int-Folge in 64 Bit.
const wireIntSet = WireFn<Set<int>>(_writeIntSet, _readIntSet);
void _writeIntSet(WireWriter w, Set<int> v) {
  final out = Float64List(v.length);
  var i = 0;
  for (final e in v) {
    out[i++] = e.toDouble();
  }
  w.float64s(out);
}

Set<int> _readIntSet(WireReader r) => {for (final e in r.float64s()) e.toInt()};
