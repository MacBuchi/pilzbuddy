// Übergibt einen Spot an die Navi-App des Nutzers (#367).
//
// Der Weg ist ein `geo:`-URI, kein Kartendienst im Browser. Das ist die
// einzige Fassung, die im Wald trägt: Sie öffnet den App-Wähler mit
// dem, was wirklich installiert ist — OsmAnd, Locus, OruxMaps, Organic
// Maps, Komoot, Google Maps — und **die App baut dabei selbst keine
// Verbindung auf**. Ein `https://…/maps?q=…` als Rückfallweg wäre ein
// neues Netzziel: Es gehörte in die Datenschutzerklärung, in
// `docs/play-console.md` und ausgerechnet im Funkloch führte es ins
// Leere. Genau dort steht man aber, wenn man diesen Knopf drückt.
//
// **Wer den Ort bekommt, entscheidet der Nutzer im App-Wähler.** Deshalb
// gibt es keinen Bestätigungsdialog davor: Der Wähler IST die
// Bestätigung, und er nennt die Ziel-App beim Namen. Ohne ihn wäre ein
// Dialog nötig — die Koordinate ist die geheime Fundstelle.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Das URI-Schema, mit dem Android nach einer Karten-App fragt.
///
/// Dieselbe Zeichenkette steht im `<queries>`-Block des Manifests — ohne
/// sie sieht die App ab Android 11 keinen Empfänger, der Wähler bliebe
/// leer, und der Knopf fiele stumm auf die Zwischenablage zurück.
/// `test/android_manifest_test.dart` hält beide Seiten zusammen.
const kGeoScheme = 'geo';

/// Nachkommastellen der übergebenen Koordinate.
///
/// Sechs Stellen sind ~11 cm und damit weit unter allem, was ein GPS im
/// Wald kann. Mehr wäre erfundene Genauigkeit und macht aus der Zahl in
/// der Zwischenablage eine unlesbare Kolonne; `double.toString()` liefert
/// bis zu 17 Stellen.
const kCoordinateDigits = 6;

/// Wie lang die Beschriftung höchstens werden darf, bevor sie abgeschnitten
/// wird. Sie ist der Pin-Titel in der Ziel-App, kein Freitextfeld.
const kMaxLabelLength = 60;

/// Lesbare Koordinate für Zwischenablage und Meldung: `50.123456, 8.123456`.
///
/// Genau die Form, die Karten-Apps und Suchfelder als Ortsangabe annehmen.
/// `toStringAsFixed` schreibt unabhängig von der Spracheinstellung einen
/// Punkt — mit einem Komma als Dezimaltrenner wäre die Zeile unbrauchbar.
String formatCoordinates(double lat, double lng) =>
    '${lat.toStringAsFixed(kCoordinateDigits)}, '
    '${lng.toStringAsFixed(kCoordinateDigits)}';

/// Der `geo:`-URI zu einem Ort, wahlweise mit Beschriftung.
///
/// Die Koordinate steht **zweimal** darin, und das ist Absicht: Apps, die
/// `q` auswerten, setzen darüber ihren Pin samt Titel; Apps, die es
/// ignorieren, zentrieren auf den Pfad. Die verbreitete Kurzform
/// `geo:0,0?q=…` schickt die zweite Gruppe in den Golf von Guinea.
Uri geoUriFor({required double lat, required double lng, String? label}) {
  final point = '${lat.toStringAsFixed(kCoordinateDigits)},'
      '${lng.toStringAsFixed(kCoordinateDigits)}';
  final title = _sanitizeLabel(label);
  final query = title == null ? point : '$point($title)';
  return Uri.parse('$kGeoScheme:$point?q=$query');
}

/// Bereitet den Spot-Namen als Pin-Titel auf.
///
/// Die Klammern sind das Trennzeichen des Schemas — eine im Namen würde
/// den URI zerlegen, und `Uri.encodeComponent` lässt sie stehen (sie sind
/// nach RFC 3986 `sub-delims` und damit erlaubt). Sie fallen deshalb hier
/// weg, ebenso Zeilenumbrüche.
String? _sanitizeLabel(String? label) {
  if (label == null) return null;
  var clean = label
      .replaceAll(RegExp(r'[()]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (clean.isEmpty) return null;
  if (clean.length > kMaxLabelLength) {
    clean = '${clean.substring(0, kMaxLabelLength).trimRight()}…';
  }
  return Uri.encodeComponent(clean);
}

/// Was beim Übergeben herausgekommen ist — die Oberfläche sagt es dem
/// Nutzer, denn zwei der drei Fälle sehen sonst nach „nichts passiert" aus.
enum SpotNavigationOutcome {
  /// Der App-Wähler bzw. die Navi-App ist offen. Nichts weiter zu melden:
  /// Die andere App steht jetzt im Vordergrund.
  opened,

  /// Android, aber keine installierte App nimmt `geo:` an.
  copiedNoNaviApp,

  /// Im Browser gibt es keinen App-Wähler.
  copiedInBrowser,
}

/// Öffnet den Ort in einer Navi-App; sonst liegt er in der Zwischenablage.
///
/// Der Rückfall auf die Zwischenablage ist kein Feigenblatt: Ohne ihn
/// hätte der Knopf im Browser und auf einem Gerät ohne Karten-App gar
/// keine Wirkung — ein Druck, der nichts tut, sieht aus wie ein Fehler
/// der App.
Future<SpotNavigationOutcome> openInNavigationApp({
  required double lat,
  required double lng,
  String? label,
  Future<bool> Function(Uri)? launch,
}) async {
  if (!kIsWeb) {
    final open = launch ?? _launchExternally;
    try {
      if (await open(geoUriFor(lat: lat, lng: lng, label: label))) {
        return SpotNavigationOutcome.opened;
      }
    } catch (_) {
      // Kein Programm für `geo:` — url_launcher meldet das je nach
      // Android-Fassung als `false` oder als Ausnahme. Beides ist hier
      // dasselbe und kein Fehler fürs Protokoll: Der Rückfallweg trägt.
    }
  }
  await Clipboard.setData(ClipboardData(text: formatCoordinates(lat, lng)));
  return kIsWeb
      ? SpotNavigationOutcome.copiedInBrowser
      : SpotNavigationOutcome.copiedNoNaviApp;
}

Future<bool> _launchExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
