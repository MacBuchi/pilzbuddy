// Die mitgelieferte Übersichtskarte, aus Bytes geöffnet (#118 im Browser).
//
// Bis 1.114.2 war der echte Ladepfad UNGETESTET: `base_map_layer_test.dart`
// überschreibt `baseMapStyleProvider`, weil `path_provider` im Test keinen
// Kanal hat. Genau deshalb ist nie aufgefallen, dass der Browser die 8,6 MB
// lädt und eine Zeile später wegwirft — der Umweg über die Platte scheitert
// dort, und ein `catch (_)` schluckt es.
//
// Dieser Test geht die LOGIK, die der Browser geht: Asset → Bytes →
// Archiv → Kachel, ohne Platte und ohne Plattform-Kanal.
//
// **Er läuft dabei aber auf der Dart-VM, nicht auf dart2js** — `kIsWeb` ist
// hier falsch, der Web-Zweig von `_openBundledOverview` also ungetestet.
// Das stand hier zuerst zu vollmundig („den Weg, den der Browser geht").
//
// Nachgemessen am 2026-09-03, warum es dabei bleibt: `flutter test
// --platform chrome` liefert im Test-Runner KEINE Assets — ein
// `rootBundle.load` läuft dort in einen Timeout, nicht einmal in einen
// 404. Was sich in Chrome sehr wohl prüfen ließ: `PmTilesArchive.fromBytes`
// kehrt auf dart2js zurück, der Aufruf selbst ist dort also gangbar.
// Offen bleibt allein, ob das ECHTE 8,6-MB-Archiv im Browser geparst wird
// — und das beantwortet nur die laufende App.
//
// Im ganzen Projekt läuft kein Test auf dart2js. Wer das ändern will,
// braucht für Assets einen anderen Weg als `rootBundle`.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/offline_maps/pmtiles_tile_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Uint8List> overviewBytes() async {
    final data =
        await rootBundle.load('assets/offline_maps/overview_dach.pmtiles');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  test('das mitgelieferte Archiv lässt sich ohne Dateisystem öffnen',
      () async {
    final provider =
        await PmTilesVectorTileProvider.openBytes(await overviewBytes());

    // Die Zoomgrenzen sind die Zusage der Übersicht: Bei 7 enden die
    // Daten, und genau daran erkennt der Renderer, dass er ab da die
    // z7-Kachel hochskalieren muss (SlippyMapTranslator, #119).
    expect(provider.minimumZoom, 0);
    expect(provider.maximumZoom, 7);
  });

  test('eine Kachel über Deutschland kommt wirklich heraus', () async {
    // Das ist der Teil, den die Zoomgrenzen allein nicht beweisen: Auf Web
    // entpackt `pmtiles` mit `package:archive` statt mit `dart:io`s zlib.
    // Kommt hier eine leere oder kaputte Kachel, bliebe die Karte im
    // Browser stumm leer.
    final provider =
        await PmTilesVectorTileProvider.openBytes(await overviewBytes());

    // z5, Kachel über Mitteldeutschland (x=16, y=10 ≈ 0–11° O, 48–55° N).
    final tile = await provider.provide(TileIdentity(5, 16, 10));

    expect(tile, isNotEmpty);
  });

  test('close ist ohne Dateihandle harmlos', () async {
    // Der Aufrufer schließt beim Neuaufbau der Quellen (#144) — der
    // Byte-Weg hat nichts freizugeben, darf daran aber auch nicht sterben.
    final provider =
        await PmTilesVectorTileProvider.openBytes(await overviewBytes());

    await expectLater(provider.close(), completes);
  });
}
