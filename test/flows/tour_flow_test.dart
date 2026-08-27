// Die Pilztour von der Karte aus (#338): starten, aufzeichnen, beenden,
// eintragen.
//
// Der Kern der Regel („wer gilt als abgesucht") steht netzfrei in
// `tour_track_test.dart`. Hier geht es um den Weg drumherum — dass der
// Knopf aufzeichnet, dass die Spur erscheint, und vor allem: dass das
// Abschluss-Blatt unsere Bewertung ZEIGT, statt sie zu verstecken.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/offline_maps/download_keep_alive.dart';
import 'package:pilzbuddy/features/tour/tour_providers.dart';
import 'package:pilzbuddy/features/tour/tour_task_handler.dart';
import 'package:pilzbuddy/features/tour/tour_track.dart';
import 'package:pilzbuddy/features/tour/widgets/tour_track_marker.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_keep_alive.dart';
import '../fakes/fake_settings.dart';
import '../fakes/fake_tour.dart';
import '../fakes/test_app.dart';

void main() {
  // Telefonformat statt des querformatigen 800x600-Vorgabeschirms: Das
  // Abschluss-Blatt ist ein Bottom Sheet mit Liste, und auf 600 px Höhe
  // rutschen seine Knöpfe unter den Rand — der Tipp geht dann ins Leere.
  Future<void> phoneSized(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  const spotLat = 51.0;
  const spotLng = 11.0;

  (FakeBackend, FakeUser) loggedInWithSpot({
    String name = 'Buchenhang',
    String? species,
    DateTime? foundOn,
  }) {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    backend.addSpot(
        ownerId: me.id,
        lat: spotLat,
        lng: spotLng,
        name: name,
        species: species,
        foundOn: foundOn);
    return (backend, me);
  }

  TourPoint at({double offsetM = 0, double accuracyM = 8}) => TourPoint(
        lat: spotLat + offsetM / 111200,
        lng: spotLng,
        // Die Uhr des Fixes, nicht die des Tests: `tourVisits` rechnet
        // ausschließlich damit.
        at: DateTime.now().toUtc(),
        accuracyM: accuracyM,
      );

  Finder tourButton() => find.byTooltip('Pilztour starten');
  Finder stopButton() => find.byTooltip('Pilztour beenden');

  testWidgets('starten schaltet den Service scharf und zeigt den ersten '
      'Punkt', (tester) async {
    await phoneSized(tester);
    final (backend, me) = loggedInWithSpot();
    final store = FakeTourStore();
    final fix = FakeTourFix();
    final bridge = FakeTourServiceBridge();
    final keepAlive = FakeKeepAlive();
    await pumpApp(tester, backend,
        tourStore: store,
        tourFix: fix,
        tourBridge: bridge,
        keepAlive: keepAlive,
        settings: FakeSettings(tourIntervalSeconds: 5));

    expect(tourButton(), findsOneWidget);
    expect(find.byType(TourTrackDot), findsNothing);

    fix.next = at();
    await tester.tap(tourButton());
    await settle(tester);

    expect(stopButton(), findsOneWidget);
    expect(store.startedAt, isNotNull);

    // **Der Kern von #342:** Gemessen wird im Service-Isolate, nicht
    // hier. Der Main-Isolate stirbt, wenn die App weggewischt wird —
    // eine Aufzeichnung, die an einem `Timer.periodic` hier hängt, hört
    // dann still auf (so in 1.102.0 im Feld gesehen).
    expect(bridge.armed, isTrue,
        reason: 'ohne die Brücke misst das Service-Isolate nicht');
    expect(bridge.uid, me.id);
    expect(keepAlive.repeat, const Duration(seconds: 5),
        reason: 'der Takt gehört dem Service, nicht der App');
    expect(keepAlive.types, {KeepAliveType.location},
        reason: 'als dataSync liefert Android im Hintergrund keine Fixes');

    // Der erste Punkt kommt trotzdem sofort von hier — sonst stünde die
    // Karte bis zum ersten Takt leer da.
    expect(store.points, hasLength(1));
    expect(find.byType(TourTrackDot), findsWidgets);
  });

  testWidgets('was der Service meldet, landet auf der Karte',
      (tester) async {
    await phoneSized(tester);
    final (backend, _) = loggedInWithSpot();
    final store = FakeTourStore();
    final fix = FakeTourFix();
    await pumpApp(tester, backend, tourStore: store, tourFix: fix);

    await tester.tap(tourButton());
    await settle(tester);
    final before =
        tester.widgetList(find.byType(TourTrackDot)).length;

    // Der Weg, den `sendDataToMain` nimmt: eine Zeichenkette hin, ein
    // Punkt zurück.
    final point = at(offsetM: 12);
    final decoded = decodeTourTick(encodeTourTick(point))!;
    expect(decoded.lat, closeTo(point.lat, 1e-9));
    expect(decoded.accuracyM, point.accuracyM);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first));
    container.read(tourProvider.notifier).acceptTick(decoded);
    await settle(tester);

    expect(tester.widgetList(find.byType(TourTrackDot)).length,
        greaterThan(before));
  });

  testWidgets('beenden entschärft die Brücke', (tester) async {
    await phoneSized(tester);
    final (backend, _) = loggedInWithSpot();
    final store = FakeTourStore();
    final bridge = FakeTourServiceBridge();
    final keepAlive = FakeKeepAlive();
    await pumpApp(tester, backend,
        tourStore: store, tourBridge: bridge, keepAlive: keepAlive);

    await tester.tap(tourButton());
    await settle(tester);
    expect(bridge.armed, isTrue);

    await tester.tap(stopButton());
    await settle(tester);

    // Sonst misst der Service weiter, obwohl die Tour beendet ist — und
    // die nächste Tour bekäme die Punkte der vorigen.
    expect(bridge.armed, isFalse);
    expect(keepAlive.repeat, isNull);
    expect(keepAlive.running, isFalse);
  });

  testWidgets('ohne Standort-Freigabe wird nichts aufgezeichnet',
      (tester) async {
    await phoneSized(tester);
    // Eine begonnene Tour, die nie einen Fix bekommt, sähe aus wie eine
    // Aufzeichnung und wäre keine.
    final (backend, _) = loggedInWithSpot();
    final store = FakeTourStore();
    await pumpApp(tester, backend, tourStore: store, extraOverrides: [
      tourPermissionProvider
          .overrideWithValue(() async => TourStartResult.noPermission),
    ]);

    await tester.tap(tourButton());
    await settle(tester);

    expect(store.startedAt, isNull, reason: 'keine Datei ohne Freigabe');
    expect(tourButton(), findsOneWidget, reason: 'der Knopf bleibt „starten"');
    expect(find.textContaining('Standort-Freigabe'), findsOneWidget);
  });

  testWidgets('beenden zeigt die Bewertung — abgesucht angehakt, '
      'vorbeigegangen verblasst und aus', (tester) async {
    await phoneSized(tester);
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    backend.addSpot(
        ownerId: me.id, lat: spotLat, lng: spotLng, name: 'Buchenhang');
    // 30 m weiter: im Vorbeigeh-Band, außerhalb des Fangradius.
    backend.addSpot(
        ownerId: me.id,
        lat: spotLat + 30 / 111200,
        lng: spotLng,
        name: 'Fichtenkante');

    final store = FakeTourStore();
    await pumpApp(tester, backend,
        tourStore: store, settings: FakeSettings(tourIntervalSeconds: 5));

    await tester.tap(tourButton());
    await settle(tester);

    // Eine volle Minute am ersten Spot, direkt in den Speicher gelegt —
    // der Takt selbst ist im Test oben schon geprüft, hier zählt die
    // Bewertung.
    final base = DateTime.now().toUtc();
    store.points
      ..clear()
      ..addAll([
        for (var i = 0; i < 5; i++)
          TourPoint(
              lat: spotLat,
              lng: spotLng,
              at: base.add(Duration(seconds: i * 15)),
              accuracyM: 8),
      ]);

    await tester.tap(stopButton());
    await settle(tester);

    expect(find.text('Pilztour beendet'), findsOneWidget);
    expect(find.textContaining('abgesucht —'), findsOneWidget);
    expect(find.textContaining('nur vorbeigegangen (30 m)'), findsOneWidget);

    // Die Vorbelegung IST die Aussage: erfüllt ⇒ an, gestreift ⇒ aus.
    final switches =
        tester.widgetList<SwitchListTile>(find.byType(SwitchListTile))
            .toList();
    expect(switches, hasLength(2));
    expect(switches[0].value, isTrue, reason: 'der abgesuchte steht oben');
    expect(switches[1].value, isFalse,
        reason: 'ein Vorbeigehen darf nicht vorangekreuzt sein — das wäre '
            'ein Anstupser, Leergänge zu buchen, die nie verdient wurden');
  });

  testWidgets('eintragen bucht genau die angehakten Leergänge',
      (tester) async {
    await phoneSized(tester);
    final (backend, me) = loggedInWithSpot();
    final store = FakeTourStore();
    await pumpApp(tester, backend, tourStore: store);

    await tester.tap(tourButton());
    await settle(tester);
    final base = DateTime.now().toUtc();
    store.points
      ..clear()
      ..addAll([
        for (var i = 0; i < 5; i++)
          TourPoint(
              lat: spotLat,
              lng: spotLng,
              at: base.add(Duration(seconds: i * 15)),
              accuracyM: 8),
      ]);

    await tester.tap(stopButton());
    await settle(tester);
    await tester.tap(find.text('Eintragen'));
    await settle(tester);

    final finds = backend.spots.single.finds;
    expect(finds, hasLength(1));
    expect(finds.single.blank, isTrue,
        reason: 'ein Leergang trägt weder Art noch Anzahl');
    expect(finds.single.authorId, me.id);
    expect(find.textContaining('Leergang eingetragen'), findsOneWidget);
    // Und die Datei ist weg — erst NACH dem Blatt, nie vorher.
    expect(store.clears, 1);
  });

  testWidgets('„Nichts eintragen" bucht nichts, verwirft aber die Tour',
      (tester) async {
    await phoneSized(tester);
    final (backend, _) = loggedInWithSpot();
    final store = FakeTourStore();
    await pumpApp(tester, backend, tourStore: store);

    await tester.tap(tourButton());
    await settle(tester);
    store.points
      ..clear()
      ..addAll([
        for (var i = 0; i < 5; i++)
          TourPoint(
              lat: spotLat,
              lng: spotLng,
              at: DateTime.now().toUtc().add(Duration(seconds: i * 15)),
              accuracyM: 8),
      ]);

    await tester.tap(stopButton());
    await settle(tester);
    await tester.tap(find.text('Nichts eintragen'));
    await settle(tester);

    expect(backend.spots.single.finds, isEmpty);
    expect(store.clears, 1);
  });

  testWidgets('an einem Spot mit Fund von heute wird kein Leergang '
      'angeboten', (tester) async {
    await phoneSized(tester);
    // Fund und „nichts gefunden" am selben Tag und derselben Stelle
    // widersprechen einander — der Fund ist die stärkere Aussage.
    final (backend, _) =
        loggedInWithSpot(species: 'Steinpilz', foundOn: DateTime.now());
    final store = FakeTourStore();
    await pumpApp(tester, backend, tourStore: store);

    await tester.tap(tourButton());
    await settle(tester);
    store.points
      ..clear()
      ..addAll([
        for (var i = 0; i < 5; i++)
          TourPoint(
              lat: spotLat,
              lng: spotLng,
              at: DateTime.now().toUtc().add(Duration(seconds: i * 15)),
              accuracyM: 8),
      ]);

    await tester.tap(stopButton());
    await settle(tester);

    expect(find.text('heute schon eingetragen'), findsOneWidget);
    final tile =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile).first);
    expect(tile.value, isFalse);
    expect(tile.onChanged, isNull, reason: 'nicht anhakbar, nicht nur aus');

    // Und der zweite Riegel, der wirklich trägt: Der Spot IST abgesucht,
    // also steht er in `_checked` auf true — nur die Anzeige zeigt ihn
    // aus. Ohne die Prüfung im Buchen selbst käme trotzdem ein Leergang
    // durch. Genau dieser Fall ist beim ersten Anlauf durch eine
    // Gegenprobe aufgefallen: Der Test hier prüfte nur die Anzeige.
    await tester.tap(find.text('Eintragen'));
    await settle(tester);
    expect(backend.spots.single.finds.where((f) => f.blank), isEmpty,
        reason: 'ein Fund und ein „nichts gefunden" am selben Tag und '
            'derselben Stelle widersprechen einander');
  });

  testWidgets('das Blatt wegzuwischen verwirft die Tour NICHT',
      (tester) async {
    await phoneSized(tester);
    // Drei Stunden Gehen dürfen nicht daran hängen, dass man das Blatt
    // versehentlich wegwischt. Erst eine Entscheidung räumt die Datei.
    final (backend, _) = loggedInWithSpot();
    final store = FakeTourStore();
    await pumpApp(tester, backend, tourStore: store);

    await tester.tap(tourButton());
    await settle(tester);
    store.points
      ..clear()
      ..addAll([
        for (var i = 0; i < 5; i++)
          TourPoint(
              lat: spotLat,
              lng: spotLng,
              at: DateTime.now().toUtc().add(Duration(seconds: i * 15)),
              accuracyM: 8),
      ]);

    await tester.tap(stopButton());
    await settle(tester);
    expect(find.text('Pilztour beendet'), findsOneWidget);

    // Neben das Blatt tippen — das schließt es ohne Ergebnis.
    await tester.tapAt(const Offset(200, 40));
    await settle(tester);

    expect(find.text('Pilztour beendet'), findsNothing);
    expect(store.clears, 0, reason: 'die Aufzeichnung muss liegen bleiben');
    expect(await store.read(uid: backend.spots.single.ownerId), isNotNull);
  });

  testWidgets('eine unterbrochene Tour läuft nach dem Neustart weiter',
      (tester) async {
    await phoneSized(tester);
    // Der Prozess-Kill ist hier der Normalfall (#147): Wer im Wald steht
    // und dessen App weggeräumt wurde, hat die Tour nicht beendet.
    final (backend, me) = loggedInWithSpot();
    final store = FakeTourStore();
    await store.begin(
        uid: me.id,
        startedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)));
    await store.appendPoint(at());

    await pumpApp(tester, backend, tourStore: store);
    await settle(tester);

    expect(stopButton(), findsOneWidget,
        reason: 'die Tour muss sich als laufend zeigen');
    expect(find.byType(TourTrackDot), findsWidgets);
  });

  testWidgets('eine Tour ohne eigene Spots auf dem Weg sagt es',
      (tester) async {
    await phoneSized(tester);
    // Kein Fehler ohne Fehlermeldung: Eine leere Liste sähe sonst nach
    // einer kaputten Aufzeichnung aus.
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    backend.addSpot(
        ownerId: me.id, lat: 52.5, lng: 13.4, name: 'Weit weg');

    final store = FakeTourStore();
    await pumpApp(tester, backend, tourStore: store);
    await tester.tap(tourButton());
    await settle(tester);
    store.points
      ..clear()
      ..add(at());

    await tester.tap(stopButton());
    await settle(tester);

    expect(find.textContaining('lag keiner deiner Spots'), findsOneWidget);
  });
}
