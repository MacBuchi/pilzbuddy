import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Ein importierter Punkt aus einer GPX-/KML-Datei.
class ImportedWaypoint {
  final String? name;
  final double lat;
  final double lng;

  const ImportedWaypoint({this.name, required this.lat, required this.lng});
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
    points.add(ImportedWaypoint(
        name: _childText(wpt, 'name'), lat: lat, lng: lng));
  }
  return points;
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
