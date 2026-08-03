// Die Regenebene (#156): welcher DWD-Layer, welcher Ausschnitt, welche URL.
//
// Ohne Karten-Abhängigkeit, damit die Regeln ohne Engine prüfbar sind
// (`test/rain_layer_test.dart`): Ein falsch gebautes GetMap merkt man sonst
// erst als leere Fläche auf dem Gerät — der Dienst antwortet dann mit einem
// XML-Fehler, den keine der beiden Engines anzeigt.
//
// **Warum ein FESTES Bild und kein mitwandernder Ausschnitt** (gemessen am
// 2026-08-04, die Entscheidung des Betreibers hing an dieser Zahl): Die
// DWD-Produkte sind ein 1-km-Raster. 20 km auf 512 Pixel angefragt ergeben
// exakt 20×20 Blöcke — mehr Pixel liefern keine weiteren Daten. Ein Bild
// mit [_imageWidth] Pixeln Kantenlänge löst über diese Ausschnitte 450–550 m
// je Pixel auf, ist also feiner als die Daten selbst. Ein mitwandernder
// Ausschnitt fügte damit keine Information hinzu, kostete aber eine
// DWD-Anfrage pro Kartenverschiebung, ein sichtbares Blinken bei jedem
// Quellentausch (maplibre-native beherrscht für WMS keine Kachelvorlage,
// siehe `MapImageOverlay`) — und er schickte das Sichtfenster des Nutzers
// an den DWD. So verlässt nur die Anfrage nach einem Bild das Gerät, das
// für alle Nutzer identisch ist.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Welche Regenebene über der Karte liegt. Bewusst flach: „jetzt" und
/// „in einer Stunde" sind dasselbe Produkt zu anderer Zeit, aber für den
/// Benutzer zwei Auswahlpunkte — als Aufzählung bleibt beides ohne
/// Nebenzustand testbar.
enum RainLayer {
  /// Keine Ebene. Vorgabe, und bewusst NICHT gespeichert: Beim Start
  /// aktiv wäre sie ein 200–600-KB-Download, den niemand angefordert hat
  /// — im Wald am Datenvolumen. Gleiche Regel wie beim Spot-Filter, der
  /// auch nur für die Sitzung gilt.
  off,

  /// `dwd:Niederschlagsradar` — Radarkomposit RV, 5-Minuten-Takt, mm/h.
  now,

  /// Dasselbe Produkt, eine Stunde voraus. Bewusst nur +1 h und nicht die
  /// vollen +2 h, die das Produkt hergibt: Der Vorhersagelauf reicht bis
  /// Laufzeit + 2 h, und die Laufzeit liegt je nach Veröffentlichungs-
  /// verzug bis zu zehn Minuten hinter der Uhr des Geräts. Eine Anfrage
  /// auf „jetzt + 2 h" fällt damit gelegentlich hinten aus dem Fenster,
  /// und der Dienst antwortet mit einem Fehler statt mit einem Bild —
  /// eine Auswahl, die manchmal nichts zeigt, ist schlechter als eine,
  /// die es nicht gibt. „+1 h" liegt in jedem Fall im Fenster.
  inOneHour,

  /// `dwd:SF-Produkt` — gleitende 24-Stunden-Summe angeeichter
  /// Radardaten, stündlich neu.
  last24h,

  /// `dwd:RADOLAN-W4` — auf 30 Tage aufsummierte angeeichte Radardaten,
  /// täglich neu. Das ist die Größe, mit der Pilzsammler tatsächlich
  /// rechnen (Faustwerte aus den Foren: ab etwa 100 mm in 30 Tagen) und
  /// die auch der tschechische Wetterdienst seinem Pilzindex zugrunde
  /// legt.
  last30d,
}

/// Kantenlänge des angefragten Bildes. 1536 statt 1024: Damit liegt die
/// Auflösung bei allen Ausschnitten unter 600 m je Pixel und damit unter
/// der Datenauflösung von 1 km — das Bild verliert nichts. Gemessene
/// Kosten je Anfrage: Radar 187 KB, 30-Tage-Summe 568 KB.
const _imageWidth = 1536;

const _dwdWms = 'https://maps.dwd.de/geoserver/dwd/wms';
const _dwdOws = 'https://maps.dwd.de/geoserver/dwd/ows';

/// Der Ausschnitt einer Ebene in Längen-/Breitengraden.
typedef RainBounds = ({double west, double south, double east, double north});

/// Der Ausschnitt des Radars — derselbe wie bei der mitgelieferten
/// DACH-Übersicht, damit die Ebene überall dort etwas zeigt, wo die
/// Karte ohne Empfang etwas zeigt.
const _radarBounds =
    (west: 5.5, south: 45.5, east: 17.5, north: 55.5);

/// Deutschland-Ausschnitt für die beiden Summenprodukte. Enger als die
/// Angabe des Dienstes (die bis Frankreich reicht), weil außerhalb
/// Deutschlands ohnehin keine Daten liegen: Derselbe Bilddurchmesser
/// deckt so einen kleineren Bereich ab und löst feiner auf.
const _germanyBounds =
    (west: 5.6, south: 47.0, east: 15.4, north: 55.2);

extension RainLayerInfo on RainLayer {
  /// Der Layername beim DWD — `null` für [RainLayer.off].
  String? get dwdLayer => switch (this) {
        RainLayer.off => null,
        RainLayer.now || RainLayer.inOneHour => 'dwd:Niederschlagsradar',
        RainLayer.last24h => 'dwd:SF-Produkt',
        RainLayer.last30d => 'dwd:RADOLAN-W4',
      };

  RainBounds get bounds => switch (this) {
        RainLayer.now || RainLayer.inOneHour => _radarBounds,
        _ => _germanyBounds,
      };

  String get label => switch (this) {
        RainLayer.off => 'Aus',
        RainLayer.now => 'Jetzt',
        RainLayer.inOneHour => 'In einer Stunde',
        RainLayer.last24h => 'Letzte 24 Stunden',
        RainLayer.last30d => 'Letzte 30 Tage',
      };

  String get description => switch (this) {
        RainLayer.off => 'Karte ohne Regen',
        RainLayer.now => 'Radar, alle fünf Minuten neu',
        RainLayer.inOneHour => 'Radarvorhersage',
        RainLayer.last24h => 'Gleitende Summe, stündlich neu',
        RainLayer.last30d => 'Summe, täglich neu — die Größe, an der man '
            'sieht, ob der Boden durchfeuchtet ist',
      };

  /// Wo diese Ebene überhaupt Daten hat. Steht im Blatt, weil sonst ein
  /// leerer oder grauer Bildschirm nach einem Fehler der App aussieht:
  /// Die Radarabdeckung ist am 2026-08-04 punktweise nachgemessen —
  /// Salzburg, Innsbruck, Zürich, Bern und Chur liegen drin, Wien, Graz,
  /// Klagenfurt und Genf nicht.
  String get coverage => switch (this) {
        RainLayer.off => '',
        RainLayer.now || RainLayer.inOneHour =>
          'Deutschland und Grenzgebiete. Im Osten Österreichs und im Westen '
              'der Schweiz reicht das Radar nicht hin — dort bleibt die '
              'Fläche grau.',
        _ => 'Nur Deutschland.',
      };

  /// Halbtransparent: Der Regen liegt ÜBER der Landschaft, nicht statt
  /// ihrer.
  ///
  /// Die Summenprodukte sind deutlich blasser als das Radar, und der
  /// Unterschied ist am Gerät entschieden (Pixel 7 Pro, 2026-08-04):
  /// Das Radar malt nur dort, wo es gerade regnet, und lässt den Rest
  /// der Karte frei — 0,6 stört dort niemanden. Die Summen färben
  /// dagegen JEDEN Punkt Deutschlands ein; bei 0,5 waren Wege und
  /// Beschriftung beim Hineinzoomen nicht mehr zu lesen, und eine Ebene,
  /// die einen daran hindert, zum Spot zu finden, ist keine Hilfe.
  double get opacity => switch (this) {
        RainLayer.now || RainLayer.inOneHour => 0.6,
        _ => 0.4,
      };
}

/// Die GetMap-URL der Ebene — `null`, wenn keine Ebene aktiv ist.
///
/// [now] ist die aktuelle Zeit; nur [RainLayer.inOneHour] verwendet sie.
/// Alle anderen Ebenen fragen OHNE `TIME` an und bekommen damit den
/// Standardwert des Dienstes — der ist immer vorhanden, auch wenn die Uhr
/// des Geräts falsch geht.
String? rainLayerUrl(RainLayer layer, {required DateTime now}) {
  final dwdLayer = layer.dwdLayer;
  if (dwdLayer == null) return null;
  final b = layer.bounds;
  final minX = _mercatorX(b.west);
  final maxX = _mercatorX(b.east);
  final minY = _mercatorY(b.south);
  final maxY = _mercatorY(b.north);
  // Bildhöhe aus dem Seitenverhältnis IN MERCATOR, nicht in Grad: Sonst
  // steht das Bild in der Höhe gestaucht auf der Karte, und der Regen
  // läge um bis zu 50 km neben dem Ort, an dem er fällt.
  final height = (_imageWidth * (maxY - minY) / (maxX - minX)).round();
  final query = <String, String>{
    'service': 'WMS',
    'version': '1.3.0',
    'request': 'GetMap',
    'layers': dwdLayer,
    'styles': '',
    'format': 'image/png',
    'transparent': 'true',
    'crs': 'EPSG:3857',
    'width': '$_imageWidth',
    'height': '$height',
    'bbox': '${minX.round()},${minY.round()},'
        '${maxX.round()},${maxY.round()}',
    if (layer == RainLayer.inOneHour) 'time': _forecastTime(now),
  };
  return Uri.parse(_dwdWms).replace(queryParameters: query).toString();
}

/// Die fertige Legende des DWD zur Ebene — `null` ohne Ebene.
///
/// Bewusst vom Dienst geholt statt selbst gezeichnet: Sie kann dann nicht
/// von der Einfärbung abweichen, die daneben auf der Karte liegt. Und sie
/// benennt die graue Fläche ausdrücklich als „Keine Daten" — genau die
/// Frage, die ein Nutzer östlich von Wien stellen wird.
String? rainLegendUrl(RainLayer layer) {
  final dwdLayer = layer.dwdLayer;
  if (dwdLayer == null) return null;
  return Uri.parse(_dwdOws).replace(queryParameters: <String, String>{
    'service': 'WMS',
    'version': '1.3.0',
    'request': 'GetLegendGraphic',
    'format': 'image/png',
    'layer': dwdLayer,
  }).toString();
}

/// Der Vorhersagezeitpunkt: auf die 5-Minuten-Schritte des Produkts
/// abgerundet und in UTC — der Dienst kennt nur diese Schritte, und eine
/// Zeit dazwischen beantwortet er je nach Einstellung mit einem Fehler.
String _forecastTime(DateTime now) {
  final utc = now.toUtc();
  final floored = DateTime.utc(
      utc.year, utc.month, utc.day, utc.hour, utc.minute - utc.minute % 5);
  final target = floored.add(const Duration(hours: 1));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${target.year}-${two(target.month)}-${two(target.day)}'
      'T${two(target.hour)}:${two(target.minute)}:00Z';
}

const _earthHalfCircumference = 20037508.34;

double _mercatorX(double lon) => lon * _earthHalfCircumference / 180;

double _mercatorY(double lat) =>
    math.log(math.tan((90 + lat) * math.pi / 360)) /
    (math.pi / 180) *
    _earthHalfCircumference /
    180;

/// Die gewählte Ebene — nur für diese Sitzung, siehe [RainLayer.off].
final rainLayerProvider = StateProvider<RainLayer>((ref) => RainLayer.off);

/// Wie aus einer URL ein Bild wird. Dieselbe Test-Naht wie
/// `tileProviderFactoryProvider`: Widget-Tests bleiben netzfrei, indem sie
/// hier ein transparentes 1×1-PNG einhängen.
final rainImageProviderFactory =
    Provider<ImageProvider Function(String url)>((ref) => NetworkImage.new);
