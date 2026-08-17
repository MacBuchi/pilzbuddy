// Das Höhengitter auf dem Gerät — Asset im APK, kein Download, keine
// Zustimmung, exakt das Muster von `forest_species_providers.dart`:
// Die Temperaturkorrektur soll dort funktionieren, wo kein Empfang ist.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'elevation_grid.dart';

/// Wie das Gitter beschafft wird — die Test-Naht:
/// `test/fakes/test_app.dart` überschreibt sie auf `null`, sonst läse
/// jeder Flow-Test das echte Asset.
final elevationLoaderProvider =
    Provider<Future<ElevationGrid?> Function()>((ref) => _loadFromAssets);

/// Lädt Manifest + Gitter aus den Assets, packt im Isolate aus.
///
/// `null` bei jedem Fehler — stille Degradation wie überall auf der
/// Karte: Ohne Höhengitter rechnet die Temperatur wie bisher
/// unkorrigiert weiter, und die Stationshöhe steht ja daneben.
Future<ElevationGrid?> _loadFromAssets() async {
  try {
    final manifestRaw =
        await rootBundle.loadString('assets/elevation/elevation_manifest.json');
    final data = await rootBundle.load('assets/elevation/elevation.bin.gz');
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return await compute(_decode, (manifest: manifestRaw, bytes: bytes));
  } catch (_) {
    // Fehlendes/kaputtes Asset ⇒ keine Korrektur. Begründung oben.
    return null;
  }
}

ElevationGrid? _decode(({String manifest, Uint8List bytes}) input) {
  try {
    final manifest = jsonDecode(input.manifest) as Map<String, dynamic>;
    if (manifest['lattice'] != 'hex-odd-r') return null;
    if (manifest['quant_m'] != elevationQuantM) return null;
    return ElevationGrid.decode(
      input.bytes,
      encoding: manifest['encoding'] as String,
      width: manifest['width'] as int,
      height: manifest['height'] as int,
      west: (manifest['west'] as num).toDouble(),
      east: (manifest['east'] as num).toDouble(),
      north: (manifest['north'] as num).toDouble(),
      south: (manifest['south'] as num).toDouble(),
      hexLonStep: (manifest['hex_lon_step'] as num).toDouble(),
      hexLatStep: (manifest['hex_lat_step'] as num).toDouble(),
    );
  } catch (_) {
    return null;
  }
}

/// Das geladene Gitter — einmal je App-Lauf, danach aus dem Cache.
final elevationGridProvider =
    FutureProvider<ElevationGrid?>((ref) => ref.watch(elevationLoaderProvider)());

/// Die Wabenhöhe an einem Punkt — die Form, in der Blatt und Ampel sie
/// brauchen. `null`: keine Korrektur möglich (kein Gitter, außerhalb).
final elevationAtProvider =
    FutureProvider.family<int?, ({double lat, double lon})>((ref, at) async {
  final grid = await ref.watch(elevationGridProvider.future);
  return grid?.heightMetersAt(at.lat, at.lon);
});
