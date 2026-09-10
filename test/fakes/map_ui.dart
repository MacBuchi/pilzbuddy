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
Future<void> closeMapLayers(WidgetTester tester) => closeSheet(tester, 'Ebenen');

/// Ein Blatt über seine Überschrift wieder schließen.
///
/// Gesucht wird ausdrücklich IM Blatt: Seit die Legende einen
/// „Ebenen"-Verweis in ihrer Fußzeile trägt, gibt es diesen Text zweimal
/// auf dem Schirm, und `find.text` warf „Too many elements". Über den
/// `BottomSheet` als Vorfahr ist die Überschrift eindeutig — dieselbe
/// Begründung wie bei [layerRow] eine Ebene höher.
Future<void> closeSheet(WidgetTester tester, String title) async {
  Navigator.of(tester.element(find.descendant(
    of: find.byType(BottomSheet),
    matching: find.text(title),
  ))).pop();
  await settle(tester);
}

/// Ein Zeitraum-Chip in der Regen-Zeile des Ebenen-Blatts.
///
/// Seit dem Entwirren steht der Zeitraum in der Zeile selbst — vorher
/// waren es fünf Radiozeilen im Regen-Blatt, also ein Blatt tiefer.
Finder rainChip(String label) => find.widgetWithText(ChoiceChip, label);

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
///
/// Die Karte heißt seit 1.133.0 fest „Pilztour" — der Schalter darauf
/// trägt den Zustand, statt dass die Überschrift zwischen „starten" und
/// „beenden" wechselt. Derselbe Tipp beendet sie also auch.
Future<void> startTour(WidgetTester tester) =>
    tapTripRow(tester, 'Pilztour');

/// Der Ausgang der laufenden Tour — er steht als eigenes Element in der
/// Spalte, nicht im Blatt, damit er einen Tipp weit weg bleibt. Zugleich
/// der ehrlichste Nachweis, ob eine Tour läuft.
///
/// Seit 1.133.0 ist das eine PILLE mit Laufzeit statt eines zweiten
/// grünen Kreises: Zustand und Ausgang in einem Element. Der Tooltip ist
/// derselbe geblieben, damit die Tests keine zweite Wahrheit brauchen.
Finder tourStopButton() => find.byTooltip('Pilztour beenden');
