// Die Ausrichtung der Marker in beiden Engines (#409).
//
// Gemeldet an den Standort-Tropfen aus #403: „Markerposition soll an der
// unteren Spitze des Tropfens sein, nicht am oberen Rand." Auf MapLibre
// hing der Marker UNTER seinem Punkt — weil beide Pakete dasselbe
// `Alignment` entgegengesetzt auslegen und die Fassade es unverändert
// durchreichte.
//
// Betroffen war seit 1.43.0 auch der Spot-Marker; nur fiel ein Pilz, der
// 44 px zu tief steht, niemandem auf. Eine Tropfenspitze macht eine
// genauere Aussage, und deshalb wurde es sichtbar.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/map_view/map_view.dart';

void main() {
  group('mapLibreAlignment', () {
    test('spiegelt die Achsen — aus topCenter wird bottomCenter', () {
      // Die Rechnung, aus den Quelltexten der beiden Pakete:
      //   flutter_map:  top = punkt.y - (h - 0.5*h*(y+1))
      //   maplibre:     top = punkt.y -      0.5*h*(y+1)
      // Bei y = -1 liegt der Punkt dort unten, hier oben.
      expect(mapLibreAlignment(Alignment.topCenter), Alignment.bottomCenter);
      expect(mapLibreAlignment(Alignment.bottomCenter), Alignment.topCenter);
    });

    test('center bleibt center — deshalb fiel es so lange nicht auf', () {
      // Bis 1.120.0 benutzte NUR der Spot-Marker etwas anderes als
      // `center`; Tour-Spur und Live-Standorte lagen mittig, und da gibt
      // es keinen Unterschied.
      expect(mapLibreAlignment(Alignment.center), Alignment.center);
    });

    test('zweimal gespiegelt ist wieder der Anfang', () {
      // Die Eigenschaft, die eine Spiegelung ausmacht — und der Schutz
      // davor, dass jemand sie „zur Sicherheit" ein zweites Mal einbaut.
      for (final a in const [
        Alignment.topCenter,
        Alignment.center,
        Alignment.bottomRight,
        Alignment(0.3, -0.7),
      ]) {
        expect(mapLibreAlignment(mapLibreAlignment(a)), a, reason: '$a');
      }
    });
  });

  test('die MapLibre-Seite benutzt die Spiegelung wirklich', () {
    // Eine TEXTPRÜFUNG, und sie weiß es: Die Übersetzung ist eine Zeile
    // in einer Datei, die auf der Test-VM nicht läuft (sie zieht
    // `package:maplibre` und damit einen Plattform-Kanal). Ohne diese
    // Prüfung könnte jemand `marker.alignment` wieder direkt
    // durchreichen, und alle Tests blieben grün — genau der Zustand von
    // 1.43.0 bis 1.122.0.
    //
    // Was sie NICHT beweist: dass MapLibre danach richtig zeichnet. Das
    // sieht nur das Auge auf dem Gerät.
    final source = File('lib/features/map/map_view/maplibre_map_view.dart')
        .readAsStringSync();
    expect(source, contains('mapLibreAlignment(marker.alignment)'));
    expect(source, isNot(contains('alignment: marker.alignment,')),
        reason: 'ungespiegelt durchgereicht ist genau der Fehler');
  });
}
