import 'package:intl/intl.dart';
import 'package:xml/xml.dart';

import '../../models/spot.dart';

/// Baut ein GPX 1.1 mit einem Wegpunkt je (eigenem) Spot. Name und
/// Fundhistorie wandern in name/desc, das jüngste Funddatum in time —
/// damit lässt sich die Datei in jeder Karten-App weiterverwenden.
String buildGpx(List<Spot> spots) {
  final dateFormat = DateFormat('d.M.y');
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element('gpx', nest: () {
    builder.attribute('version', '1.1');
    builder.attribute('creator', 'PilzBuddy');
    builder.attribute('xmlns', 'http://www.topografix.com/GPX/1/1');
    for (final spot in spots) {
      builder.element('wpt', nest: () {
        builder.attribute('lat', spot.lat.toStringAsFixed(6));
        builder.attribute('lon', spot.lng.toStringAsFixed(6));
        builder.element('name', nest: spot.displayName);
        final finds = spot.findsSorted;
        if (finds.isNotEmpty) {
          builder.element('desc',
              nest: finds
                  .map((f) => '${f.label} – ${dateFormat.format(f.foundOn)}')
                  .join('\n'));
          final newest = finds.first;
          builder.element('time',
              nest: (newest.createdAt ?? newest.foundOn)
                  .toUtc()
                  .toIso8601String());
        }
      });
    }
  });
  return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
}
