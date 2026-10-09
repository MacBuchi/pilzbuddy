import 'dart:typed_data';

/// Außerhalb des Browsers gibt es keine Objekt-URLs; die Datei-Strecke
/// in `RainGridRepository.writeFill` gilt.
String? objectUrlFor(String slot, Uint8List bytes, {required String type}) =>
    null;
