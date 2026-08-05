import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'gpx_export.dart' show kPilzBuddyGpxNamespace;

/// Ein Fund aus den PilzBuddy-Erweiterungen einer GPX-Datei.
class ImportedFind {
  final String? species;
  final int? count;
  final DateTime foundOn;
  final String? note;

  const ImportedFind(
      {this.species, this.count, required this.foundOn, this.note});
}

/// Ein importierter Punkt aus einer GPX-/KML-Datei.
class ImportedWaypoint {
  final String? name;
  final double lat;
  final double lng;

  /// Zeitstempel des Punkts (GPX `<time>`) — wird beim Anlegen als
  /// Funddatum vorbelegt.
  final DateTime? time;

  /// Die Funde aus den PilzBuddy-Erweiterungen. `null`, wenn der Punkt
  /// keine trägt — das ist der Unterschied zwischen „aus PilzBuddy" und
  /// „aus irgendeiner Karten-App", und daran hängt der ganze
  /// Wiederherstellungspfad. Eine **leere** Liste ist etwas anderes: ein
  /// eigener Spot, der (noch) keinen Fund hat.
  final List<ImportedFind>? finds;

  /// Ob der Spot von der Freigabe ausgenommen war.
  final bool sharingExcluded;

  const ImportedWaypoint({
    this.name,
    required this.lat,
    required this.lng,
    this.time,
    this.finds,
    this.sharingExcluded = false,
  });

  /// Trägt dieser Punkt vollständige PilzBuddy-Daten?
  bool get isRestorable => finds != null;
}

bool _validCoords(double lat, double lng) =>
    lat.isFinite && lng.isFinite && lat.abs() <= 90 && lng.abs() <= 180;

/// Liest Wegpunkte aus GPX, KML oder einem Zip-Container (KMZ,
/// gezipptes GPX). Wirft [FormatException] bei unlesbaren Dateien;
/// einzelne kaputte Punkte werden still übersprungen.
List<ImportedWaypoint> parseWaypoints(String fileName, Uint8List bytes) {
  // Zip-Magic "PK\x03\x04" → KMZ oder gezipptes GPX/KML.
  if (bytes.length > 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final points = <ImportedWaypoint>[];
    for (final file in archive.files) {
      final name = file.name.toLowerCase();
      if (!file.isFile ||
          !(name.endsWith('.gpx') || name.endsWith('.kml'))) {
        continue;
      }
      points.addAll(parseWaypoints(
          file.name, Uint8List.fromList(file.content as List<int>)));
    }
    if (points.isEmpty) {
      throw FormatException('Keine GPX/KML-Datei im Archiv: $fileName');
    }
    return points;
  }

  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
  } on XmlException {
    throw FormatException('Keine lesbare GPX/KML-Datei: $fileName');
  }
  // Namespace-agnostisch über lokale Namen matchen — Exporte anderer
  // Apps nutzen die unterschiedlichsten Namespaces/Präfixe.
  final root = doc.rootElement.name.local.toLowerCase();
  if (root == 'gpx') return _parseGpx(doc);
  if (root == 'kml') return _parseKml(doc);
  throw FormatException('Unbekanntes Format (${doc.rootElement.name})');
}

Iterable<XmlElement> _byLocalName(XmlNode node, String local) =>
    node.descendants.whereType<XmlElement>().where(
        (e) => e.name.local.toLowerCase() == local);

String? _childText(XmlElement element, String local) {
  for (final child in element.childElements) {
    if (child.name.local.toLowerCase() == local) {
      final text = child.innerText.trim();
      return text.isEmpty ? null : text;
    }
  }
  return null;
}

List<ImportedWaypoint> _parseGpx(XmlDocument doc) {
  final points = <ImportedWaypoint>[];
  for (final wpt in _byLocalName(doc, 'wpt')) {
    final lat = double.tryParse(wpt.getAttribute('lat') ?? '');
    final lng = double.tryParse(wpt.getAttribute('lon') ?? '');
    if (lat == null || lng == null || !_validCoords(lat, lng)) continue;
    final time = DateTime.tryParse(_childText(wpt, 'time') ?? '');
    final spot = _pilzBuddySpot(wpt);
    points.add(ImportedWaypoint(
      // Aus den Erweiterungen kommt der SELBST vergebene Name (dort
      // fehlt er, wenn der Spot keinen hat); `<name>` trägt dagegen
      // immer etwas, notfalls einen erzeugten Anzeigenamen.
      name: spot == null
          ? _childText(wpt, 'name')
          : spot.getAttribute('name'),
      lat: lat,
      lng: lng,
      time: time?.toLocal(),
      finds: spot == null ? null : _parseFinds(spot),
      sharingExcluded: spot?.getAttribute('sharingExcluded') == 'true',
    ));
  }
  return points;
}

/// Das `<pb:spot>`-Element eines Wegpunkts — oder `null`, wenn die Datei
/// nicht aus PilzBuddy stammt.
///
/// **Erkannt wird an der Namensraum-URI, niemals am Präfix oder am bloßen
/// Vorhandensein von `<extensions>`.** Locus Map und Garmin hängen dort
/// ihre eigenen Erweiterungen hinein (Adressen, Symbole); ein Treffer
/// darauf würde einen fremden Export als PilzBuddy-Sicherung ausgeben und
/// den Nutzer in den falschen Ablauf schicken. Das Präfix wiederum darf
/// jede Datei frei wählen — `pb:` ist eine Gewohnheit, keine Zusage.
XmlElement? _pilzBuddySpot(XmlElement wpt) {
  for (final element in wpt.descendants.whereType<XmlElement>()) {
    if (element.name.local == 'spot' &&
        element.name.namespaceUri == kPilzBuddyGpxNamespace) {
      return element;
    }
  }
  return null;
}

/// Die Funde aus einem `<pb:spot>`. Einzelne kaputte Einträge werden
/// übersprungen — dieselbe Haltung wie beim Rest des Parsers: Eine
/// Sicherung, die an einer krummen Zeile ganz scheitert, ist keine.
List<ImportedFind> _parseFinds(XmlElement spot) {
  final finds = <ImportedFind>[];
  for (final element in spot.descendants.whereType<XmlElement>()) {
    if (element.name.local != 'find' ||
        element.name.namespaceUri != kPilzBuddyGpxNamespace) {
      continue;
    }
    final foundOn = DateTime.tryParse(element.getAttribute('foundOn') ?? '');
    if (foundOn == null) continue;
    final count = int.tryParse(element.getAttribute('count') ?? '');
    finds.add(ImportedFind(
      species: element.getAttribute('species'),
      // Die Datenbank verlangt `count > 0` — eine 0 oder ein negativer
      // Wert aus einer verbogenen Datei würde den Import erst beim
      // Schreiben scheitern lassen.
      count: count != null && count > 0 ? count : null,
      foundOn: foundOn,
      note: _childText(element, 'note'),
    ));
  }
  return finds;
}

List<ImportedWaypoint> _parseKml(XmlDocument doc) {
  final points = <ImportedWaypoint>[];
  for (final placemark in _byLocalName(doc, 'placemark')) {
    // Nur Punkt-Placemarks — Linien/Polygone sind keine Pilz-Spots.
    final point = _byLocalName(placemark, 'point').firstOrNull;
    if (point == null) continue;
    final coords = _byLocalName(point, 'coordinates').firstOrNull;
    if (coords == null) continue;
    final parts = coords.innerText.trim().split(',');
    if (parts.length < 2) continue;
    final lng = double.tryParse(parts[0].trim());
    final lat = double.tryParse(parts[1].trim());
    if (lat == null || lng == null || !_validCoords(lat, lng)) continue;
    points.add(ImportedWaypoint(
        name: _childText(placemark, 'name'), lat: lat, lng: lng));
  }
  return points;
}
