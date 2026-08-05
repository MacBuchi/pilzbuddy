import 'package:intl/intl.dart';
import 'package:xml/xml.dart';

import '../../models/spot.dart';

/// Der Namensraum der PilzBuddy-Erweiterungen.
///
/// Eine **Kennung**, keine Adresse — hier wird nichts abgerufen. Sie muss
/// nur weltweit eindeutig sein, und dafür ist eine URL unter eigener
/// Domain die übliche Wahl.
///
/// Die Ziffer am Ende ist die Formatversion. Sie steht von Anfang an da,
/// weil sich ein Format ohne Versionsfeld später nur noch raten lässt.
const kPilzBuddyGpxNamespace = 'https://macbuchi.github.io/pilzbuddy/gpx/1';

/// Baut ein GPX 1.1 mit einem Wegpunkt je (eigenem) Spot.
///
/// **Eine Datei für zwei Zwecke** (Issue #112):
///
/// - `name`/`desc`/`time` sind für **fremde Apps** — dieselben Felder wie
///   vorher, Zeichen für Zeichen. Jede Karten-App zeigt damit einen
///   benannten Wegpunkt mit lesbarer Fundhistorie.
/// - `<extensions>` sind für **PilzBuddy selbst**: Art, Anzahl, Datum,
///   Notiz je Fund und das Freigabe-Flag. Damit wird ein Kontowechsel
///   verlustfrei. Fremde Apps ignorieren fremde Erweiterungen — so
///   verlangt es die GPX-Spezifikation, und genau deshalb braucht es
///   keine zweite Datei.
///
/// **Buddy-Funde bleiben draußen**, in beiden Teilen: Sie sind die Daten
/// ihrer Autoren und verlassen die App nicht per Datei (#190).
///
/// Achtung beim Ändern: Der Export enthält **Notizen**. Der Aufrufer
/// sagt das vor dem Teilen an (`profile_screen.dart`) — wer hier Felder
/// hinzufügt, prüft diesen Hinweis mit.
String buildGpx(List<Spot> spots) {
  final dateFormat = DateFormat('d.M.y');
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element('gpx', nest: () {
    builder.attribute('version', '1.1');
    builder.attribute('creator', 'PilzBuddy');
    builder.attribute('xmlns', 'http://www.topografix.com/GPX/1/1');
    builder.namespace(kPilzBuddyGpxNamespace, 'pb');
    for (final spot in spots) {
      builder.element('wpt', nest: () {
        builder.attribute('lat', spot.lat.toStringAsFixed(6));
        builder.attribute('lon', spot.lng.toStringAsFixed(6));
        builder.element('name', nest: spot.displayName);
        final finds =
            spot.findsSorted.where((f) => f.isOwn).toList(growable: false);
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
        builder.element('extensions', nest: () {
          builder.element('spot', namespace: kPilzBuddyGpxNamespace, nest: () {
            builder.attribute('version', '1');
            builder.attribute(
                'sharingExcluded', spot.sharingExcluded ? 'true' : 'false');
            // Der Name auch hier, nicht nur in <name>: Ein Spot ohne
            // eigenen Namen zeigt dort einen erzeugten Anzeigenamen
            // (`displayName`), und den beim Zurücklesen als selbst
            // vergebenen Namen zu speichern wäre eine Erfindung.
            if (spot.name != null && spot.name!.isNotEmpty) {
              builder.attribute('name', spot.name!);
            }
            for (final find in finds) {
              builder.element('find', namespace: kPilzBuddyGpxNamespace,
                  nest: () {
                if (find.species != null && find.species!.isNotEmpty) {
                  builder.attribute('species', find.species!);
                }
                if (find.count != null) {
                  builder.attribute('count', '${find.count}');
                }
                builder.attribute('foundOn', _isoDate(find.foundOn));
                // Als Element, nicht als Attribut: Notizen dürfen
                // mehrzeilig sein, und Zeilenumbrüche in Attributwerten
                // überleben einen XML-Round-Trip nicht zuverlässig.
                if (find.note != null && find.note!.isNotEmpty) {
                  builder.element('note',
                      namespace: kPilzBuddyGpxNamespace, nest: find.note!);
                }
              });
            }
          });
        });
      });
    }
  });
  return builder.buildDocument().toXmlString(
        pretty: true,
        indent: '  ',
        // **Ohne das frisst der Pretty-Printer die Zeilenumbrüche.** Er
        // normalisiert Text zwischen Tags, und aus einer zweizeiligen
        // Notiz wird eine Zeile — beim Zurücklesen ist der Umbruch dann
        // endgültig weg. Bei `<desc>` galt das schon vorher: Die
        // Fundhistorie sollte untereinander stehen, landete aber als
        // Fließtext in jeder Karten-App (gefunden beim Bau des
        // Round-Trip-Tests, #112).
        preserveWhitespace: (node) =>
            node is XmlElement &&
            (node.name.local == 'note' || node.name.local == 'desc'),
      );
}

/// `2024-10-27` — nur der Tag, ohne Zeitzone.
///
/// `found_on` ist ein reines Datum (die Spalte in der Datenbank ist es
/// auch). Als Zeitstempel geschrieben, verschöbe eine Zeitzonen-Umrechnung
/// den Fund beim Zurücklesen um einen Tag.
String _isoDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
