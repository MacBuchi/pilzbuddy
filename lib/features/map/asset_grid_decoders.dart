// Die Dekodierer der Asset-Gitter, ohne Flutter (#689, B3).
//
// Dieselbe Funktion läuft an drei Orten: auf dem Gerät über
// `boundedCompute`, im Browser im Web Worker (der die Datei selbst lädt,
// `MapWorkerLoad` in map_worker_tasks.dart) und dort, wo es keinen Worker
// gibt, auf dem Hauptthread. Deshalb steht sie hier und nicht beim
// Provider: Dessen Datei zieht Flutter nach sich, und der Worker baut
// dann nicht mehr (test/map_worker_imports_test.dart).
//
// Jede nimmt das Manifest als JSON-Text und die GEPACKTEN Bytes und gibt
// bei einem unbekannten oder kaputten Asset `null` — dieselbe stille
// Degradation wie überall auf der Karte: Ohne Gitter fehlt die Ebene.
import 'dart:convert';
import 'dart:typed_data';

import 'elevation_grid.dart';
import 'forest_grid.dart';
import 'gbif_finds.dart';
import 'protected_areas.dart';

ForestGrid? decodeForestAsset(String manifestJson, Uint8List gzipped) {
  try {
    final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
    // Nur bekannte Gitterformen: Ein unbekanntes `lattice` heißt, das
    // Asset ist neuer als die App — dann lieber keine Ebene als eine
    // falsch zugeordnete (Quadrat-Lesart auf Hex-Daten läge überall
    // ein halbes Hex daneben, still).
    final lattice = manifest['lattice'] as String?;
    if (lattice != null && lattice != 'hex-odd-r') return null;
    return ForestGrid.decode(
      gzipped,
      width: manifest['width'] as int,
      height: manifest['height'] as int,
      west: (manifest['west'] as num).toDouble(),
      east: (manifest['east'] as num).toDouble(),
      north: (manifest['north'] as num).toDouble(),
      south: (manifest['south'] as num).toDouble(),
      referenceYear: manifest['reference_year'] as int,
      hexLonStep:
          lattice == null ? null : (manifest['hex_lon_step'] as num).toDouble(),
      hexLatStep:
          lattice == null ? null : (manifest['hex_lat_step'] as num).toDouble(),
    );
  } catch (_) {
    return null;
  }
}

ElevationGrid? decodeElevationAsset(String manifestJson, Uint8List gzipped) {
  try {
    final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
    if (manifest['lattice'] != 'hex-odd-r') return null;
    if (manifest['quant_m'] != elevationQuantM) return null;
    return ElevationGrid.decode(
      gzipped,
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

GbifFinds? decodeGbifFindsAsset(String manifestJson, Uint8List gzipped) {
  try {
    return GbifFinds.decode(gzipped, manifestJson);
  } catch (_) {
    return null;
  }
}

ProtectedAreas? decodeProtectedAsset(String manifestJson, Uint8List gzipped) {
  try {
    return ProtectedAreas.decode(gzipped, manifestJson);
  } on FormatException {
    return null;
  }
}
