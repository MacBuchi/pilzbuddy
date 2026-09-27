// Die Baumarten-Gitter auf dem Gerät: DLR für Deutschland (#227) und
// das Rückfall-Gitter aus ForestPaths für den Rest (#624).
//
// Wie beim Waldtypen-Gitter: Asset im APK, kein Download, keine
// Zustimmung. Die Frage „welcher Baum steht hier" stellt sich dort, wo
// kein Empfang ist.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'forest_species.dart';

/// Wie das Gitter beschafft wird — die Test-Naht, exakt das Muster von
/// `forestGridLoaderProvider`: `test/fakes/test_app.dart` überschreibt
/// sie auf `null`, sonst läse jeder Flow-Test das echte Asset.
final forestSpeciesLoaderProvider =
    Provider<Future<ForestSpeciesGrid?> Function()>((ref) => _loadDlr);

/// Dieselbe Naht für das Rückfall-Gitter (#624). Die Tests setzen sie
/// ebenfalls auf `null` — sonst läse jeder Flow-Test ein zweites Asset.
final forestSpeciesEuLoaderProvider =
    Provider<Future<ForestSpeciesGrid?> Function()>(
        (ref) => () => _loadFromAssets(
              'assets/forest/forest_species_eu_manifest.json',
              'assets/forest/forest_species_eu.bin.gz',
            ));

Future<ForestSpeciesGrid?> _loadDlr() => _loadFromAssets(
      'assets/forest/forest_species_manifest.json',
      'assets/forest/forest_species.bin.gz',
    );

/// Lädt Manifest + Gitter aus den Assets, packt im Isolate aus.
///
/// `null` bei jedem Fehler — dieselbe stille Degradation wie überall auf
/// der Karte. Ohne Gitter fehlt die Artenzeile, mehr passiert nicht;
/// die Waldzeile darüber steht unabhängig davon.
Future<ForestSpeciesGrid?> _loadFromAssets(
    String manifestPath, String gridPath) async {
  try {
    final manifestRaw = await rootBundle.loadString(manifestPath);
    final data = await rootBundle.load(gridPath);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return await compute(_decode, (manifest: manifestRaw, bytes: bytes));
  } catch (_) {
    // Fehlendes/kaputtes Asset ⇒ keine Artenzeile. Begründung oben.
    return null;
  }
}

ForestSpeciesGrid? _decode(({String manifest, Uint8List bytes}) input) {
  try {
    final manifest = jsonDecode(input.manifest) as Map<String, dynamic>;
    // Nur das bekannte Format. Ein Asset, das neuer ist als die App,
    // wird abgelehnt statt falsch gelesen — bei der Kodierung ist das
    // nicht theoretisch: Käme je ein Zeilen-Delta dazu (wie bei Wald
    // und Regen), sähe roh entpackt jede Zeile plausibel aus und wäre
    // doch überall falsch.
    if (manifest['lattice'] != 'hex-odd-r') return null;
    if (manifest['encoding'] != 'gzip') return null;
    return ForestSpeciesGrid.decode(
      input.bytes,
      width: manifest['width'] as int,
      height: manifest['height'] as int,
      west: (manifest['west'] as num).toDouble(),
      east: (manifest['east'] as num).toDouble(),
      north: (manifest['north'] as num).toDouble(),
      south: (manifest['south'] as num).toDouble(),
      referenceYear: manifest['reference_year'] as int,
      hexLonStep: (manifest['hex_lon_step'] as num).toDouble(),
      hexLatStep: (manifest['hex_lat_step'] as num).toDouble(),
    );
  } catch (_) {
    return null;
  }
}

/// Das geladene Gitter — einmal je App-Lauf, danach aus dem Cache.
final forestSpeciesGridProvider = FutureProvider<ForestSpeciesGrid?>(
    (ref) => ref.watch(forestSpeciesLoaderProvider)());

/// Das Rückfall-Gitter (#624) — genauso geladen, nur wo es gebraucht
/// wird: Beobachtet wird es erst, wenn das DLR-Gitter an einem Punkt
/// schweigt.
final forestSpeciesEuGridProvider = FutureProvider<ForestSpeciesGrid?>(
    (ref) => ref.watch(forestSpeciesEuLoaderProvider)());
