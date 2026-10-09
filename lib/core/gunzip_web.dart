import 'dart:typed_data';

import 'package:archive/archive.dart' show GZipDecoder;
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'gunzip_check.dart';

/// Was der Browser schon ausgepackt hat, je gepacktem Objekt (#689).
final _inflated = Expando<Uint8List>('gunzip');

/// Merkt sich [out] als das Ausgepackte von [gzipped] — für den EINEN
/// folgenden [gunzip]-Aufruf mit genau diesem Objekt. Geprüft wird wie
/// dort (Länge gegen den gzip-Abspann); passt sie nicht, bleibt nichts
/// liegen, und [gunzip] packt selbst aus und wirft.
void rememberInflated(Uint8List gzipped, Uint8List out) {
  try {
    checkGzipLength(gzipped, out);
  } on FormatException {
    return;
  }
  _inflated[gzipped] = out;
}

/// Liegt für [gzipped] schon Ausgepacktes bereit? Für den Browser-Test,
/// der zeigen muss, dass der native Weg lief und nicht still der
/// Rückfall (test/CLAUDE.md, „Ein grüner Chrome-Lauf allein beweist
/// nichts").
@visibleForTesting
bool debugInflatedReady(Uint8List gzipped) => _inflated[gzipped] != null;

/// Packt gzip aus — im Browser in Dart, `dart:io` fehlt dort. Hat
/// `preInflate` dasselbe Objekt schon nativ ausgepackt, kommt das
/// zurück (und wird vergessen, sonst hielte das gepackte Objekt die
/// ausgepackte Kopie am Leben).
Uint8List gunzip(List<int> gzipped) {
  if (gzipped is Uint8List) {
    final done = _inflated[gzipped];
    if (done != null) {
      _inflated[gzipped] = null;
      return done;
    }
  }
  final out = GZipDecoder().decodeBytes(gzipped);
  final bytes = out is Uint8List ? out : Uint8List.fromList(out);
  checkGzipLength(gzipped, bytes);
  return bytes;
}
