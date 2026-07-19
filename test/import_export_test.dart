// Unit-Tests für GPX/KML-Import und GPX-Export.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/import_export/gpx_export.dart';
import 'package:pilzbuddy/features/import_export/waypoint_parser.dart';
import 'package:pilzbuddy/models/find.dart';
import 'package:pilzbuddy/models/spot.dart';

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

// Nachbau eines echten Locus-Map-Exports: Namespaces, Garmin-Extensions,
// CDATA-Beschreibung, sym-Element, Zeitstempel.
const _gpx = '''
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<gpx version="1.1" creator="Locus Map, Android"
 xmlns="http://www.topografix.com/GPX/1/1"
 xmlns:gpxx="http://www.garmin.com/xmlschemas/GpxExtensions/v3"
 xmlns:locus="http://www.locusmap.eu">
  <metadata><time>2026-07-19T17:35:09.694Z</time></metadata>
  <wpt lat="53.0793" lon="8.8017">
    <ele>300.00</ele>
    <time>2024-10-27T15:25:21.735Z</time>
    <name>Bürgerpark &amp; Wald</name>
    <desc><![CDATA[mehrere im Wald]]></desc>
    <sym>nature-geyser</sym>
    <extensions>
      <gpxx:WaypointExtension>
        <gpxx:Address><gpxx:City>Bremen</gpxx:City></gpxx:Address>
      </gpxx:WaypointExtension>
    </extensions>
  </wpt>
  <wpt lat="51.5" lon="10.1"/>
  <wpt lat="999" lon="8.8"><name>kaputt</name></wpt>
</gpx>
''';

const _kml = '''
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"><Document>
  <Placemark><name>Fichtenhang</name>
    <Point><coordinates>11.5820,48.1351,519</coordinates></Point>
  </Placemark>
  <Placemark><name>Linie (ignorieren)</name>
    <LineString><coordinates>1,2 3,4</coordinates></LineString>
  </Placemark>
</Document></kml>
''';

void main() {
  group('parseWaypoints', () {
    test('liest Locus-GPX (Extensions, CDATA, sym), überspringt Kaputtes',
        () {
      final points = parseWaypoints('spots.gpx', _utf8(_gpx));
      expect(points, hasLength(2));
      expect(points.first.name, 'Bürgerpark & Wald');
      expect(points.first.lat, closeTo(53.0793, 1e-6));
      expect(points.first.lng, closeTo(8.8017, 1e-6));
      expect(points.first.time,
          DateTime.parse('2024-10-27T15:25:21.735Z').toLocal());
      expect(points[1].name, isNull);
      expect(points[1].time, isNull);
    });

    test('liest KML-Punkt-Placemarks (lon,lat-Reihenfolge!), keine Linien',
        () {
      final points = parseWaypoints('spots.kml', _utf8(_kml));
      expect(points, hasLength(1));
      expect(points.single.name, 'Fichtenhang');
      expect(points.single.lat, closeTo(48.1351, 1e-6));
      expect(points.single.lng, closeTo(11.5820, 1e-6));
    });

    test('liest KMZ/Zip mit enthaltener KML-Datei', () {
      final archive = Archive()
        ..addFile(ArchiveFile('doc.kml', utf8.encode(_kml).length,
            utf8.encode(_kml)));
      final kmz = Uint8List.fromList(ZipEncoder().encode(archive)!);
      final points = parseWaypoints('spots.kmz', kmz);
      expect(points.single.name, 'Fichtenhang');
    });

    test('unlesbare Dateien geben eine verständliche FormatException', () {
      expect(() => parseWaypoints('foto.jpg', _utf8('kein xml')),
          throwsFormatException);
      expect(
          () => parseWaypoints(
              'fremd.xml', _utf8('<?xml version="1.0"?><svg/>')),
          throwsFormatException);
    });
  });

  group('buildGpx', () {
    test('Roundtrip: exportierte Spots lassen sich wieder importieren', () {
      final spots = [
        Spot(
          id: 's1',
          ownerId: 'u1',
          name: 'Hang & Bach <Nord>',
          lat: 53.0793,
          lng: 8.8017,
          finds: [
            Find(
                id: 'f1',
                spotId: 's1',
                species: 'Steinpilz',
                count: 5,
                foundOn: DateTime(2026, 7, 12)),
          ],
        ),
        const Spot(id: 's2', ownerId: 'u1', lat: 48.1, lng: 11.5),
      ];
      final gpx = buildGpx(spots);
      expect(gpx, contains('creator="PilzBuddy"'));
      expect(gpx, contains('Steinpilz, 5 Stück'));

      final reimported = parseWaypoints('export.gpx', _utf8(gpx));
      expect(reimported, hasLength(2));
      expect(reimported.first.name, 'Hang & Bach <Nord>');
      expect(reimported.first.lat, closeTo(53.0793, 1e-5));
      expect(reimported[1].name, 'Pilz-Spot');
    });
  });
}
