// Validiert die eingebaute Übersichts-Basiskarte (Asset): gültiges
// PMTiles-Format, erwarteter Zoombereich, DACH-Abdeckung. Schützt davor,
// dass eine korrupte oder falsche Datei ins Repo gerät.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmtiles/pmtiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Übersichts-Basiskarte ist gültig und deckt DACH bis Zoom 7 ab',
      () async {
    final data =
        await rootBundle.load('assets/offline_maps/overview_dach.pmtiles');
    // Klein genug für ein App-Asset bleiben (Warnschwelle 15 MB).
    expect(data.lengthInBytes, lessThan(15 * 1024 * 1024));

    final archive = await PmTilesArchive.fromBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    expect(archive.header.minZoom, 0);
    expect(archive.header.maxZoom, 7);

    // Stichprobe: Kachel über Mitteldeutschland muss vorhanden sein.
    final tile = await archive.tile(ZXY(6, 33, 21).toTileId());
    expect(tile.bytes(), isNotEmpty);
  });
}
