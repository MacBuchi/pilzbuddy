// Unit-Tests für GPX/KML-Import und GPX-Export.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/import_export/gpx_export.dart';
import 'package:pilzbuddy/features/import_export/waypoint_parser.dart';
import 'package:pilzbuddy/models/find.dart';
import 'package:pilzbuddy/models/spot.dart';
import 'package:xml/xml.dart';

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

    test('fremde <extensions> lösen KEINEN Wiederherstellungspfad aus', () {
      // Der Korpus oben trägt Garmin- und Locus-Erweiterungen. Würde die
      // Erkennung am bloßen Vorhandensein von <extensions> hängen, gälte
      // ein fremder Export als PilzBuddy-Sicherung — und der Nutzer
      // landete in einem Ablauf, der ihm Funde verspricht, die es nicht
      // gibt.
      final points = parseWaypoints('spots.gpx', _utf8(_gpx));
      expect(points.every((p) => p.isRestorable), isFalse);
      expect(points.first.finds, isNull);
    });

    test('ein fremdes Präfix auf UNSEREM Namensraum wird erkannt', () {
      // Das Präfix darf jede Datei frei wählen — „pb" ist Gewohnheit,
      // keine Zusage. Erkannt wird an der Namensraum-URI.
      const gpx = '''
<?xml version="1.0"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:irgendwas="https://macbuchi.github.io/pilzbuddy/gpx/1">
  <wpt lat="51.2" lon="10.4"><name>Hang</name><extensions>
    <irgendwas:spot version="1" name="Hang">
      <irgendwas:find species="Steinpilz" foundOn="2026-07-12"/>
    </irgendwas:spot>
  </extensions></wpt>
</gpx>
''';
      final point = parseWaypoints('export.gpx', _utf8(gpx)).single;
      expect(point.isRestorable, isTrue);
      expect(point.finds!.single.species, 'Steinpilz');
    });

    test('ein gleichnamiges Element in FREMDEM Namensraum wird ignoriert',
        () {
      // Die Gegenprobe zum Test darüber: „spot" ist kein seltenes Wort.
      const gpx = '''
<?xml version="1.0"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:other="https://example.com/spots/1">
  <wpt lat="51.2" lon="10.4"><name>Hang</name><extensions>
    <other:spot version="1"><other:find species="Fake" foundOn="2026-07-12"/></other:spot>
  </extensions></wpt>
</gpx>
''';
      final point = parseWaypoints('fremd.gpx', _utf8(gpx)).single;
      expect(point.isRestorable, isFalse);
      expect(point.name, 'Hang');
    });

    test('kaputte Funde werden übersprungen, der Spot bleibt', () {
      // Eine Sicherung, die an einer krummen Zeile ganz scheitert, ist
      // keine.
      const gpx = '''
<?xml version="1.0"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:pb="https://macbuchi.github.io/pilzbuddy/gpx/1">
  <wpt lat="51.2" lon="10.4"><extensions><pb:spot version="1">
    <pb:find species="Ohne Datum"/>
    <pb:find species="Krummes Datum" foundOn="gestern"/>
    <pb:find species="Steinpilz" count="0" foundOn="2026-07-12"/>
    <pb:find species="Marone" count="3" foundOn="2026-08-01"/>
  </pb:spot></extensions></wpt>
</gpx>
''';
      final finds = parseWaypoints('export.gpx', _utf8(gpx)).single.finds!;
      expect(finds.map((f) => f.species), ['Steinpilz', 'Marone']);
      // `count = 0` verletzt die Check-Constraint der Datenbank — als
      // `null` gelesen scheitert der Import nicht erst beim Schreiben.
      expect(finds.first.count, isNull);
      expect(finds[1].count, 3);
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
      // Ein Spot OHNE eigenen Namen kommt ohne Namen zurück. In `<name>`
      // steht für fremde Apps der erzeugte Anzeigename „Pilz-Spot"; den
      // beim Zurücklesen als selbst vergebenen Namen zu speichern wäre
      // eine Erfindung, die nach dem Kontowechsel dauerhaft dastünde.
      expect(reimported[1].name, isNull);
    });

    test('VERLUSTFREI: alles kommt zurück, wie es hineinging (#112)', () {
      // Der Kerntest des Tickets. Ohne ihn ist „verlustfrei" eine
      // Behauptung — und jedes einzelne Feld hier ist eines, das im alten
      // Export (nur name/desc/time) verloren ging.
      final spots = [
        Spot(
          id: 's1',
          ownerId: 'u1',
          name: 'Buchenhang',
          lat: 51.234567,
          lng: 10.456789,
          sharingExcluded: true,
          finds: [
            Find(
                id: 'f1',
                spotId: 's1',
                species: 'Steinpilz',
                count: 5,
                foundOn: DateTime(2026, 7, 12),
                note: 'am umgestürzten Baum\nzweite Zeile'),
            Find(
                id: 'f2',
                spotId: 's1',
                species: 'Maronenröhrling',
                foundOn: DateTime(2026, 8, 1)),
          ],
        ),
      ];

      final point =
          parseWaypoints('export.gpx', _utf8(buildGpx(spots))).single;

      expect(point.isRestorable, isTrue);
      expect(point.name, 'Buchenhang');
      expect(point.lat, closeTo(51.234567, 1e-6));
      expect(point.lng, closeTo(10.456789, 1e-6));
      expect(point.sharingExcluded, isTrue);

      // Nach Datum absteigend, wie die App sie sortiert.
      expect(point.finds, hasLength(2));
      final marone = point.finds!.first;
      expect(marone.species, 'Maronenröhrling');
      expect(marone.count, isNull);
      expect(marone.foundOn, DateTime(2026, 8, 1));

      final steinpilz = point.finds![1];
      expect(steinpilz.species, 'Steinpilz');
      expect(steinpilz.count, 5);
      expect(steinpilz.foundOn, DateTime(2026, 7, 12));
      // Der Zeilenumbruch überlebt. Er tut das nur, weil der
      // Pretty-Printer für <note> abgeschaltet ist — sonst wird aus zwei
      // Zeilen still eine.
      expect(steinpilz.note, 'am umgestürzten Baum\nzweite Zeile');
    });

    test('VERLUSTFREI auch für „Nichts gefunden" (#211)', () {
      // Ein Leergang ist eine eigene Beobachtung. Bliebe er beim Export
      // draußen, wäre die Sicherung genau um das ärmer, was die Pilzampel
      // später braucht.
      final spots = [
        Spot(id: 's1', ownerId: 'u1', lat: 51, lng: 10, finds: [
          Find(
              id: 'f1',
              spotId: 's1',
              species: 'Steinpilz',
              count: 2,
              foundOn: DateTime(2026, 7, 12)),
          Find(
              id: 'f2',
              spotId: 's1',
              foundOn: DateTime(2026, 8, 1),
              note: 'alles abgesammelt',
              blank: true),
        ]),
      ];

      final gpx = buildGpx(spots);
      expect(gpx, contains('blank="true"'));
      // Auch für fremde Karten-Apps lesbar, die nur <desc> zeigen.
      expect(gpx, contains('Nichts gefunden – 1.8.2026'));

      final finds = parseWaypoints('export.gpx', _utf8(gpx)).single.finds!;
      expect(finds, hasLength(2));
      final leergang = finds.first;
      expect(leergang.blank, isTrue);
      expect(leergang.species, isNull);
      expect(leergang.count, isNull);
      expect(leergang.foundOn, DateTime(2026, 8, 1));
      expect(leergang.note, 'alles abgesammelt');
      expect(finds[1].blank, isFalse);
      expect(finds[1].count, 2);
    });

    test('Eine Datei ohne blank-Attribut bleibt ein echter Fund', () {
      // Sicherungen aus der Zeit vor #211 dürfen sich nicht plötzlich in
      // Leergänge verwandeln.
      const alt = '''
<?xml version="1.0"?>
<gpx version="1.1" creator="PilzBuddy"
 xmlns="http://www.topografix.com/GPX/1/1"
 xmlns:pb="$kPilzBuddyGpxNamespace">
  <wpt lat="51.0" lon="10.0"><name>Alt</name><extensions>
    <pb:spot version="1" sharingExcluded="false">
      <pb:find species="Steinpilz" count="3" foundOn="2026-07-12"/>
    </pb:spot>
  </extensions></wpt>
</gpx>
''';
      final find = parseWaypoints('alt.gpx', _utf8(alt)).single.finds!.single;
      expect(find.blank, isFalse);
      expect(find.species, 'Steinpilz');
      expect(find.count, 3);
    });

    test('Ein Leergang mit Art in der Datei wird bereinigt', () {
      // Die Datenbank lässt das nicht zu (`finds_blank_leer`). Eine von
      // Hand gebastelte Datei soll den Import trotzdem nicht sprengen —
      // die widersprüchlichen Felder fallen weg, der Leergang bleibt.
      const krumm = '''
<?xml version="1.0"?>
<gpx version="1.1" creator="PilzBuddy"
 xmlns="http://www.topografix.com/GPX/1/1"
 xmlns:pb="$kPilzBuddyGpxNamespace">
  <wpt lat="51.0" lon="10.0"><extensions>
    <pb:spot version="1">
      <pb:find blank="true" species="Steinpilz" count="3" foundOn="2026-07-12"/>
    </pb:spot>
  </extensions></wpt>
</gpx>
''';
      final find = parseWaypoints('krumm.gpx', _utf8(krumm)).single.finds!.single;
      expect(find.blank, isTrue);
      expect(find.species, isNull);
      expect(find.count, isNull);
    });

    test('das Funddatum verschiebt sich nicht um einen Tag', () {
      // `found_on` ist ein reines Datum. Als Zeitstempel geschrieben,
      // schöbe eine Zeitzonen-Umrechnung den Fund über Mitternacht — bei
      // einem Fund kurz vor oder nach Neujahr sogar ins falsche Jahr.
      for (final date in [
        DateTime(2026, 1, 1),
        DateTime(2026, 6, 30), // Sommerzeit
        DateTime(2026, 12, 31),
      ]) {
        final gpx = buildGpx([
          Spot(id: 's', ownerId: 'u', lat: 51, lng: 10, finds: [
            Find(id: 'f', spotId: 's', species: 'Steinpilz', foundOn: date),
          ]),
        ]);
        final back = parseWaypoints('e.gpx', _utf8(gpx)).single.finds!.single;
        expect(back.foundOn, date, reason: 'Datum verschoben: $date');
      }
    });

    test('die Fundhistorie in <desc> steht untereinander', () {
      // Für fremde Karten-Apps ist <desc> die ganze Information. Der
      // Pretty-Printer machte daraus einen Fließtext — beim Bau des
      // Round-Trip-Tests aufgefallen, Bestandsfehler.
      final gpx = buildGpx([
        Spot(id: 's', ownerId: 'u', lat: 51, lng: 10, finds: [
          Find(
              id: 'f1',
              spotId: 's',
              species: 'Steinpilz',
              foundOn: DateTime(2026, 7, 12)),
          Find(
              id: 'f2',
              spotId: 's',
              species: 'Marone',
              foundOn: DateTime(2026, 8, 1)),
        ]),
      ]);
      expect(gpx, contains('Marone – 1.8.2026\nSteinpilz – 12.7.2026'));
    });

    test('bleibt für fremde Apps lesbar: name/desc/time wie bisher', () {
      // Der zweite Zweck der einen Datei (#112). Die Erweiterungen dürfen
      // die Standardfelder nicht ersetzen, sonst zeigt eine Navi-App
      // leere Wegpunkte.
      final gpx = buildGpx([
        Spot(id: 's', ownerId: 'u', name: 'Hang', lat: 51, lng: 10, finds: [
          Find(
              id: 'f',
              spotId: 's',
              species: 'Steinpilz',
              count: 5,
              foundOn: DateTime(2026, 7, 12)),
        ]),
      ]);
      final doc = XmlDocument.parse(gpx);
      final wpt = doc.findAllElements('wpt').single;
      expect(wpt.getElement('name')?.innerText, 'Hang');
      expect(wpt.getElement('desc')?.innerText, contains('Steinpilz, 5 Stück'));
      expect(wpt.getElement('time'), isNotNull);
      // Und die Erweiterungen liegen dort, wo die GPX-Spezifikation sie
      // erwartet — nicht als freie Kinder von <wpt>.
      expect(wpt.getElement('extensions'), isNotNull);
      expect(wpt.childElements.map((e) => e.name.local),
          isNot(contains('spot')));
    });

    test('fremde Funde bleiben draußen — Buddy-Daten verlassen die App '
        'nicht per Datei', () {
      final spot = Spot(id: 's1', ownerId: 'me', lat: 51, lng: 10, finds: [
        Find(
            id: 'f1',
            spotId: 's1',
            species: 'Steinpilz',
            foundOn: DateTime(2026, 7, 1)),
        Find(
            id: 'f2',
            spotId: 's1',
            species: 'Parasol',
            foundOn: DateTime(2026, 7, 5),
            authorId: 'lilli',
            isOwn: false),
      ]);
      final gpx = buildGpx([spot]);
      expect(gpx, contains('Steinpilz'));
      expect(gpx, isNot(contains('Parasol')));
    });
  });
}
