// Ein Asset-Gitter laden — im Browser über den Web Worker, sonst wie
// bisher (#689, B3).
//
// Im Browser rechnet `compute` auf dem Hauptthread, und jede große
// Byte-Menge zwischen Wasm und JavaScript kostet dort zusätzlich: Gemessen
// auf dem Pixel XL waren Wald und Höhe in den ersten acht Sekunden gut
// 1,5 s, in denen ein Tipp auf das Menü bis zu 0,6 s wartete. Deshalb holt
// der Worker die Datei dort selbst, packt sie aus, dekodiert sie und
// behält sie als Fach; die App bekommt nur die fertige Kopie.
//
// Gibt es keinen Worker (Gerät, alter Browser, Worker fällt aus), lädt
// die App wie bis 1.226.0: Bytes aus dem Bundle, im Browser nativ
// ausgepackt, dekodiert über `boundedCompute`.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/asset_url.dart';
import '../../core/bounded_compute.dart';
import '../../core/gunzip.dart';
import '../../core/map_worker.dart';

/// Lädt [gridPath] mit [manifestPath] über [load]. [slot] ist der
/// Fachname, unter dem die Rechnungen das Gitter lesen — `null` für ein
/// Gitter, das nur die App braucht.
///
/// Wirft, was Bundle oder Dekodierer werfen; die Lader fangen es und
/// liefern `null` (fehlende Ebene statt Fehlermeldung).
Future<R?> loadAssetGrid<R extends Object>(
  MapWorker worker,
  MapWorkerLoad<R?> load, {
  required String manifestPath,
  required String gridPath,
  String? slot,
}) async {
  final manifest = await rootBundle.loadString(manifestPath);
  if (kIsWeb && worker.loadsAssets) {
    try {
      return await worker.loadAsset(load,
          slot: slot, manifest: manifest, url: assetUrl(gridPath));
    } on MapWorkerSuperseded {
      rethrow;
    } catch (_) {
      // Kein Worker, Abruf oder Dekodierung drüben gescheitert: dann wie
      // bisher hier. Ein kaputtes Asset fällt dort genauso auf.
    }
  }
  final data = await rootBundle.load(gridPath);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  await preInflate(bytes); // im Browser nativ ausgepackt (#689)
  return await boundedCompute(
          _decode, (decode: load.decode, manifest: manifest, bytes: bytes))
      as R?;
}

Object? _decode(
        ({Function decode, String manifest, Uint8List bytes}) input) =>
    // ignore: avoid_dynamic_calls
    (input.decode as dynamic)(input.manifest, input.bytes);
