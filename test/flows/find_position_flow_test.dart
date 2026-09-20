// Die eigene Stelle eines Fundes, durch die echte Oberfläche (#373).
//
// Die Leitfrage ist überall dieselbe: Wann darf die App behaupten, sie
// wisse, wo der Fund lag? Ein übersehener Ort kostet eine Angabe; ein
// ERFUNDENER schreibt das Wohnzimmer auf einen Fund im Wald. Deshalb
// zieht jede Regel hier in dieselbe Richtung — lieber zu wenig.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/features/map/widgets/mini_map.dart';
import 'package:pilzbuddy/features/spots/find_offset.dart';
import 'package:pilzbuddy/models/find_position.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  const spotLat = 51.1634;
  const spotLng = 10.4477;

  /// Öffnet das Spot-Blatt und trägt einen Fund ein.
  Future<void> addFindViaUi(WidgetTester tester,
      {String? tapFirst}) async {
    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.text('Fund eintragen'));
    await settle(tester);
    if (tapFirst != null) {
      await tester.tap(find.text(tapFirst));
      await settle(tester);
    }
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);
  }

  testWidgets('Wer am Spot steht, bekommt seine Stelle vorbelegt — und der '
      'Fund trägt sie', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: spotLat, lng: spotLng);
    // 8 m nordöstlich, ±5 m: scharf genug und zweifelsfrei am Spot.
    await pumpApp(tester, backend,
        position: fakePosition(spotLat + 0.00005, spotLng + 0.00008));

    await addFindViaUi(tester);

    final saved = backend.spots.single.finds.single;
    expect(saved.position, isNotNull,
        reason: 'am Spot stehend soll man die Stelle nicht erst antippen');
    expect(saved.position!.accuracyM, 5);
    expect(saved.position!.measured, isTrue);
  });

  testWidgets('Das Blatt fragt beim Öffnen NIE nach der Berechtigung',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: spotLat, lng: spotLng);
    final fix = FakePositionFix(fakePosition(spotLat, spotLng));
    await pumpApp(tester, backend,
        position: fakePosition(spotLat, spotLng), positionFix: fix);

    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.text('Fund eintragen'));
    await settle(tester);

    // Die Vorbelegung liest den laufenden Strom, der bewusst nie fragt.
    // Der Systemdialog gehört hinter einen sichtbaren Tipp — das ist die
    // Zusage im Abschnitt „Prominent Disclosure" von docs/play-console.md.
    expect(fix.calls, 0);
  });

  testWidgets('Ein Fix weit weg wird nicht angeboten — und der Fund '
      'speichert trotzdem', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: spotLat, lng: spotLng);
    // Rund 340 m nördlich: Wer so weit weg steht, trägt gerade nicht
    // dort ein, wo er ist.
    await pumpApp(tester, backend,
        position: fakePosition(spotLat + 0.00306, spotLng));

    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.text('Fund eintragen'));
    await settle(tester);

    // Der Grund steht im Klartext da — ein toter Knopf ohne Erklärung
    // sähe aus wie ein Fehler.
    expect(find.textContaining('vom Spot entfernt'), findsOneWidget);

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    expect(backend.spots.single.finds.single.position, isNull);
  });

  testWidgets('Ein zu grober Fix zählt nicht als Messung', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: spotLat, lng: spotLng);
    // Direkt am Spot, aber ±64 m: ein 20-m-Radius, gegen so einen Fix
    // geprüft, wäre Rauschen im Gewand einer Messung.
    await pumpApp(tester, backend,
        position: fakePosition(spotLat, spotLng,
            accuracy: kFindUsableAccuracyM + 34));

    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.text('Fund eintragen'));
    await settle(tester);

    expect(find.textContaining('zu ungenau'), findsOneWidget);

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    expect(backend.spots.single.finds.single.position, isNull);
  });

  testWidgets('Ohne jeden Fix wird der Fund normal gespeichert',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: spotLat, lng: spotLng);
    await pumpApp(tester, backend); // kein Standort, wie überall sonst

    await addFindViaUi(tester);

    expect(backend.spots.single.finds, hasLength(1));
    expect(backend.spots.single.finds.single.position, isNull,
        reason: 'die Stelle ist optional — der Fund ist es nicht');
  });

  testWidgets('Auch ein Leergang trägt seine Stelle', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: spotLat, lng: spotLng);
    await pumpApp(tester, backend,
        position: fakePosition(spotLat + 0.00005, spotLng + 0.00008));

    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.text('Nichts gefunden'));
    await settle(tester);
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    final saved = backend.spots.single.finds.single;
    expect(saved.blank, isTrue);
    expect(saved.position, isNotNull,
        reason: '„ich war hier und da stand nichts" hängt am stärksten '
            'an einem Ort');
  });

  testWidgets('Die Fundliste macht zwei Funde unterscheidbar',
      (tester) async {
    final (backend, me) = loggedInBackend();
    final spotId = backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: spotLat, lng: spotLng);
    backend.addFindRow(spotId,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 12),
        position: const FindPosition.gps(
            lat: 51.16349, lng: 10.44784, accuracy: 5));
    backend.addFindRow(spotId,
        species: 'Marone',
        foundOn: DateTime(2026, 9, 12),
        position: const FindPosition.gps(
            lat: 51.16334, lng: 10.44761, accuracy: 6));
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);

    expect(find.textContaining('nordöstlich'), findsOneWidget);
    expect(find.textContaining('südwestlich'), findsOneWidget);
  });

  testWidgets('„Am Spot" baut gar keine Karte', (tester) async {
    // Der Normalfall. Ein Kartenausschnitt kostete dort Speicher und
    // Kacheln für eine Aussage, die schon als Text dasteht — und er ist
    // der Grund, warum die bestehenden Suiten unberührt bleiben.
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: spotLat, lng: spotLng);
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.text('Fund eintragen'));
    await settle(tester);

    expect(find.text('Am Spot'), findsOneWidget);
    expect(find.byType(FlutterMap), findsNothing);
  });

  testWidgets('„Auf Karte" zeigt den Ausschnitt und übernimmt die Mitte',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: spotLat, lng: spotLng);
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.text('Fund eintragen'));
    await settle(tester);
    await tester.tap(find.text('Auf Karte'));
    await settle(tester);

    expect(find.byType(FlutterMap), findsOneWidget);

    // Karte unter dem Fadenkreuz wegschieben — die Mitte ist die Wahl.
    await tester.drag(find.byType(FlutterMap), const Offset(0, -40));
    await settle(tester);
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    final saved = backend.spots.single.finds.single.position!;
    expect(saved.measured, isFalse,
        reason: 'ein Fadenkreuz hat keinen Messfehler');
    expect(saved.lat, isNot(spotLat),
        reason: 'das Verschieben muss ankommen');
  });

  testWidgets('Eine Korrektur lässt die Stelle stehen', (tester) async {
    final (backend, me) = loggedInBackend();
    final spotId = backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: spotLat, lng: spotLng);
    backend.addFindRow(spotId,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 12),
        position: const FindPosition.gps(
            lat: 51.16349, lng: 10.44784, accuracy: 5));
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await settle(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Notiz (optional)'), 'am Wurzelteller');
    await settle(tester);
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    final saved = backend.spots.single.finds.single;
    expect(saved.note, 'am Wurzelteller');
    // Eine GEMESSENE Stelle überlebt jede Korrektur. Seit #466 nicht
    // mehr deshalb, weil `updateFind` die Spalten ausließe — es schreibt
    // sie mit —, sondern weil das Blatt sie unverändert zurückgibt. Die
    // Zusage ist dieselbe, der Grund ist ein anderer, und genau deshalb
    // muss dieser Test stehen bleiben.
    expect(saved.position?.accuracyM, 5);
  });

  testWidgets('Eine gemessene Stelle bekommt keine Karte zum Verschieben',
      (tester) async {
    // Die Grenze aus #466: Ein Fix ist eine Messung. Ihn zwei Tage
    // später vom Sofa aus zu rücken ersetzte sie durch eine Erinnerung.
    final (backend, me) = loggedInBackend();
    final spotId = backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: spotLat, lng: spotLng);
    backend.addFindRow(spotId,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 12),
        position: const FindPosition.gps(
            lat: 51.16349, lng: 10.44784, accuracy: 5));
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await settle(tester);

    expect(find.byType(MiniMap), findsNothing);
    // Stattdessen steht sie weiter als Auskunft da.
    expect(find.textContaining('Lag '), findsOneWidget);
  });

  testWidgets('Eine gewählte Stelle lässt sich verschieben', (tester) async {
    // Die Gegenrichtung, und der eigentliche Zweck: Was auf der Karte
    // gewählt wurde, ist eine Angabe wie der Ort des Spots — und der ist
    // seit #466 korrigierbar. Beides anders zu behandeln wäre dieselbe
    // Aussage mit zwei Antworten.
    final (backend, me) = loggedInBackend();
    final spotId = backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: spotLat, lng: spotLng);
    backend.addFindRow(spotId,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 12),
        position: const FindPosition.picked(lat: 51.16349, lng: 10.44784));
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await settle(tester);

    final map = tester.widget<MiniMap>(find.byType(MiniMap));
    expect(map.mode, MiniMapMode.pick);
    expect(map.reference.latitude, closeTo(spotLat, 1e-9),
        reason: 'der Ring liegt auf dem SPOT — er ist der Bezugspunkt');
    // Kein Weg zu einem frischen Fix: Der misst, wo man jetzt steht,
    // nicht wo der Fund lag.
    expect(find.text('Meine Position'), findsNothing);

    map.onCenterChanged!(const LatLng(51.1636, 10.4480));
    await settle(tester);
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    final saved = backend.spots.single.finds.single.position!;
    expect(saved.lat, closeTo(51.1636, 1e-9));
    expect(saved.lng, closeTo(10.4480, 1e-9));
    expect(saved.measured, isFalse,
        reason: 'ein Fadenkreuz hat keinen Messfehler — auch beim Rücken');
  });

  testWidgets('Eine gewählte Stelle ohne Zutun bleibt, wo sie ist',
      (tester) async {
    // Die teuerste Falle dieser Änderung: `updateFind` schreibt die
    // Spalten jetzt MIT. Ein Blatt, das sie beim Speichern vergisst,
    // löscht sie — und das sähe aus wie „hat nie eine gehabt".
    final (backend, me) = loggedInBackend();
    final spotId = backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: spotLat, lng: spotLng);
    backend.addFindRow(spotId,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 12),
        position: const FindPosition.picked(lat: 51.16349, lng: 10.44784));
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await settle(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Notiz (optional)'), 'am Wurzelteller');
    await settle(tester);
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    final saved = backend.spots.single.finds.single;
    expect(saved.note, 'am Wurzelteller');
    expect(saved.position?.lat, closeTo(51.16349, 1e-9));
    expect(saved.position?.lng, closeTo(10.44784, 1e-9));
  });

  testWidgets('Ein Fund ohne eigene Stelle bekommt hier keine',
      (tester) async {
    // Eine Stelle nachträglich zu ERFINDEN ist nicht Korrigieren — und
    // sie ginge in die Stichprobe ein, die #199 als unabhängigen
    // Prüfstein aufhebt.
    final (backend, me) = loggedInBackend();
    final spotId = backend.addSpot(
        ownerId: me.id, name: 'Buchenhang', lat: spotLat, lng: spotLng);
    backend.addFindRow(spotId,
        species: 'Steinpilz', foundOn: DateTime(2026, 9, 12));
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await settle(tester);

    expect(find.byType(MiniMap), findsNothing);

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);
    expect(backend.spots.single.finds.single.position, isNull);
  });
}
