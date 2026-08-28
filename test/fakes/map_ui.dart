// Die Wege durch die gruppierten Karten-Knöpfe (#347).
//
// Bis dahin hatte jede Ebene ihren eigenen FAB, und die Tests tippten ihn
// direkt an — 36 Stellen. Seit die Ebenen hinter EINEM „Karte"-Knopf
// liegen, wäre daraus überall derselbe Zweischritt geworden; das gehört
// an eine Stelle, sonst kostet die nächste Umsortierung wieder 36
// Änderungen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_app.dart';

/// Das Karten-Blatt öffnen (Ebenen, Offline-Umschaltung, Aktualisieren).
Future<void> openMapLayers(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Ebenen'));
  await settle(tester);
}

/// Von der Karte ins Detailblatt einer Ebene — der Weg, den bis #347 ein
/// eigener FAB je Ebene abkürzte.
///
/// [layer] ist der Zeilentitel im Karten-Blatt: „Waldtypen",
/// „Höhenlinien", „Regen", „Pilzampel".
Future<void> openLayerSheet(WidgetTester tester, String layer) async {
  await openMapLayers(tester);
  await tester.tap(layerRow(layer));
  await settle(tester);
}

/// Die ZEILE einer Ebene im Karten-Blatt.
///
/// Nicht `find.text(layer)`: Die Karten-Legende links unten nennt aktive
/// Ebenen beim selben Namen, und dann gibt es den Text zweimal. Über die
/// `ListTile` als Vorfahr ist die Zeile eindeutig — die Legende hat
/// keine.
Finder layerRow(String layer) =>
    find.ancestor(of: find.text(layer), matching: find.byType(ListTile));

/// Den Schalter einer Ebene umlegen und das Karten-Blatt wieder
/// schließen — damit der Test danach die Karte sieht und nicht das Blatt.
Future<void> toggleLayer(WidgetTester tester, String layer) async {
  await openMapLayers(tester);
  await tester.tap(layerSwitch(layer));
  await settle(tester);
  await closeMapLayers(tester);
}

/// Das Ebenen-Blatt wieder schließen.
Future<void> closeMapLayers(WidgetTester tester) async {
  Navigator.of(tester.element(find.text('Ebenen'))).pop();
  await settle(tester);
}

/// Der Schalter in der Zeile einer Ebene.
Finder layerSwitch(String layer) =>
    find.descendant(of: layerRow(layer), matching: find.byType(Switch));

/// Das Unterwegs-Blatt öffnen (Pilztour, Standort teilen).
Future<void> openTrip(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Unterwegs'));
  await settle(tester);
}

/// Eine Zeile im Unterwegs-Blatt antippen.
Future<void> tapTripRow(WidgetTester tester, String row) async {
  await openTrip(tester);
  await tester.tap(find.text(row));
  await settle(tester);
}

/// Die Pilztour starten.
Future<void> startTour(WidgetTester tester) =>
    tapTripRow(tester, 'Pilztour starten');

/// Der Stopp-Knopf der laufenden Tour — er steht als EIGENER FAB in der
/// Spalte, nicht im Blatt, damit der Ausgang einen Tipp weit weg bleibt.
/// Zugleich der ehrlichste Nachweis, ob eine Tour läuft.
Finder tourStopButton() => find.byTooltip('Pilztour beenden');
