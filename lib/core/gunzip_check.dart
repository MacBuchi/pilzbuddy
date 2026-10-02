import 'dart:typed_data';

/// Wirft, wenn [out] nicht die Länge hat, die der gzip-Abspann von
/// [gzipped] nennt (ISIZE, die letzten vier Bytes, Länge mod 2³²).
///
/// Beide Entpacker — `dart:io` wie `package:archive` — liefern bei einem
/// abgeschnittenen Strom STILL den Teil, der bis dahin kam (nachgemessen,
/// #641). Ein abgebrochener Download sähe damit gültig aus. Der Abspann
/// ist die eine Angabe im Format, die das Ende bezeugt.
void checkGzipLength(List<int> gzipped, Uint8List out) {
  if (gzipped.length < 18) {
    throw const FormatException('gzip: zu kurz');
  }
  final n = gzipped.length;
  final isize = gzipped[n - 4] |
      (gzipped[n - 3] << 8) |
      (gzipped[n - 2] << 16) |
      (gzipped[n - 1] << 24);
  if (isize != (out.length & 0xFFFFFFFF)) {
    throw FormatException(
        'gzip: ${out.length} Bytes ausgepackt, der Abspann nennt $isize — '
        'abgeschnitten oder beschädigt');
  }
}
