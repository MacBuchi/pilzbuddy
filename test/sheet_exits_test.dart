// Drei Wege aus einem Blatt heraus, und zwar überall (Betreiber,
// 2026-09-22: „zusätzliche popups … sollten je mit einem 'x' als auch
// mit dem zurück button sowie mit wischgeste schließbar sein").
//
// **Kein Griffbalken.** `showDragHandle: true` wäre der sichtbare
// Hinweis auf das Wischen und kostet rund 38 px am Kopf: Das
// Regen-Blatt verlor darüber seine Legende aus dem Aufbau, das
// Filter-Blatt lief um 1,1 px über. Der Ausweg, der sich selbst
// erklärt, ist das x; das Wischen bleibt und wird hier darüber
// gesichert, dass es niemand abschaltet.
//
// **Zwei Prüfungen, weil zwei Dinge schiefgehen können.** Der
// Widget-Test hält fest, was das x TUT; der Quelltext-Wächter hält fest,
// dass es an jedem Blatt STEHT. Ein neues Blatt kostet sonst niemanden
// etwas — es sieht aus wie die anderen, und erst im Wald merkt jemand,
// dass er nicht mehr herauskommt.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/widgets/sheet_close_button.dart';

/// Blätter, die bewusst KEIN x tragen — mit dem Grund daneben.
///
/// Die Liste ist der Ort, an dem eine Ausnahme begründet wird. Wer ein
/// Blatt hier einträgt, schreibt dazu, warum; wer es vergisst, wird vom
/// Wächter gefragt.
const _ohneSchliessen = <String, String>{
  // Formulare. Dort steht am Fuß, was der Knopf tut („Speichern",
  // „Eintragen"), und ein x daneben wäre ein zweiter Abbruch neben dem
  // ersten. Weggewischt werden können sie ohnehin.
  'add_spot_sheet.dart': 'Formular mit eigenen Knöpfen am Fuß',
  'add_find_sheet.dart': 'Formular mit eigenen Knöpfen am Fuß',
  'edit_find_sheet.dart': 'Formular mit eigenen Knöpfen am Fuß',
  'edit_spot_sheet.dart': 'Formular mit eigenen Knöpfen am Fuß',
  // Nachträglich an iNaturalist melden (#553): ein Formular wie das
  // Eintrage-Blatt, dessen Abschnitt es wiederverwendet; „Melden" am Fuß.
  'inat_report_sheet.dart': 'Formular mit eigenem Knopf am Fuß',
  'tour_summary_sheet.dart': 'Entscheidungsblatt am Ende der Tour',
  // **Die eine Stelle, an der ein x teuer wäre.** In der Kopfzeile
  // stehen schon Navi, Bearbeiten und Löschen; ein viertes Symbol
  // daneben hieße, dass „Schließen" und „Spot löschen" einen
  // Daumenbreit auseinanderliegen. Der Griffbalken trägt das Blatt.
  'spot_detail_sheet.dart': 'Kopfzeile trägt bereits Löschen',
  // Das Beispiel-Blatt der Spot-Tour: offen nur, solange die Tour läuft,
  // und die schließt es selbst. Ein x wäre dort ohnehin nicht zu treffen
  // — die Überlagerung schluckt jeden Tipp; heraus führen „Weiter",
  // „Überspringen" und Zurück.
  'tour_examples.dart': 'Nur während einer Tour offen, die Tour schließt es',
};

/// Was NIE in einem Blatt stehen darf.
///
/// Beide Schalter nehmen einen der drei Ausgänge weg, und zwar
/// lautlos: `enableDrag: false` das Wischen, `isDismissible: false` den
/// Tipp daneben. Ein Blatt, das eine Entscheidung erzwingen will,
/// nimmt einen Dialog.
const _verboteneSchalter = <String>['enableDrag: false', 'isDismissible: false'];

List<File> _sheetQuellen() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => f.readAsStringSync().contains('showModalBottomSheet'))
    .toList();

void main() {
  testWidgets('das x schließt das Blatt, in dem es steht', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const SizedBox(
                height: 200,
                child: Row(children: [Text('Inhalt'), SheetCloseButton()]),
              ),
            ),
            child: const Text('auf'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
    expect(find.text('Inhalt'), findsOneWidget);

    await tester.tap(find.byType(SheetCloseButton));
    await tester.pumpAndSettle();
    expect(find.text('Inhalt'), findsNothing);
  });

  testWidgets('die Trefferfläche bleibt bei 44', (tester) async {
    // **44 bleiben 44** (dieselbe Zusage wie in der Werkzeugleiste der
    // Karte). Ein `IconButton` schrumpft mit `visualDensity.compact`
    // still unter das Maß, wenn man die Grenzen wegnimmt — im Bild
    // sieht man davon nichts, im Gehen schon.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: SheetCloseButton())),
    ));
    final box = tester.getSize(find.byType(SheetCloseButton));
    expect(box.width, greaterThanOrEqualTo(44));
    expect(box.height, greaterThanOrEqualTo(44));
  });

  test('jedes Blatt trägt Griffbalken und x — oder eine Begründung', () {
    final quellen = _sheetQuellen();
    // Reißleine: Findet der Wächter nichts, prüft er nichts.
    expect(quellen.length, greaterThanOrEqualTo(15));

    final fehltX = <String>[];
    final zugesperrt = <String>[];
    for (final f in quellen) {
      final name = f.uri.pathSegments.last;
      final quelle = f.readAsStringSync();
      if (!_ohneSchliessen.containsKey(name) &&
          !quelle.contains('SheetCloseButton')) {
        fehltX.add(name);
      }
      for (final schalter in _verboteneSchalter) {
        if (quelle.contains(schalter)) zugesperrt.add('$name ($schalter)');
      }
    }
    expect(fehltX, isEmpty,
        reason: 'ohne x kommt nur heraus, wer die Wischgeste kennt — '
            'entweder ein SheetCloseButton in die Kopfzeile oder ein '
            'Eintrag mit Grund in _ohneSchliessen');
    expect(zugesperrt, isEmpty,
        reason: 'diese Blätter nehmen einen der drei Ausgänge weg');
  });

  test('keine Karteileiche in den Ausnahmelisten', () {
    // Ein Blatt, das es nicht mehr gibt, nimmt seine Begründung mit.
    // Sonst steht hier irgendwann eine Liste, die niemand mehr liest.
    final namen =
        _sheetQuellen().map((f) => f.uri.pathSegments.last).toSet();
    expect(_ohneSchliessen.keys.where((n) => !namen.contains(n)), isEmpty);
  });
}
