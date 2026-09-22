// Das Kontextmenü am langen Tipp, durch die echte Oberfläche (#483).
//
// Der Wunsch des Betreibers: ein ganz kleines Menü mit „was ist hier"
// und „Navigation" — beide Funktionen gab es schon, nur nicht an dieser
// Stelle. Dazu als dritter Eintrag das Heranzoomen, also die alte,
// schalterlose Bedeutung des langen Tipps.
//
// **Warum der Schalter dabei entfallen konnte** (#210 → #483): Die Geste
// stand AUS, weil sie sofort die Kamera warf — „ein Fehlgriff aus der
// Übersicht warf einen woanders hin". Ein Menü fragt erst. Genau das
// prüft der zweite Test hier, und er ist der eigentliche Grund für die
// ganze Änderung.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/core/app_colors.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  testWidgets('Langes Drücken öffnet die vier Chips — ohne Schalter',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);

    expect(find.text('Was ist hier?'), findsNothing);

    await simulateMapLongPress(tester, const LatLng(48.15, 11.55));
    await settle(tester);

    for (final label in [
      'Spot anlegen',
      'Was ist hier?',
      'Navigation',
      'Heranzoomen',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('„Spot anlegen" liegt am Finger und trägt die Farbe des '
      'Knopfs', (tester) async {
    // **Zwei Zusagen in einem Test** (#513). Die Reihenfolge geht nach
    // Nähe zum Finger, und der Wunsch kam aus dem Feld: Wer lange
    // drückt, will dort oft einen Spot. Und die Farbe leitet sich vom
    // „Neuer Spot"-Knopf ab, damit erkennbar ist, dass beide dasselbe
    // tun.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await simulateMapLongPress(tester, const LatLng(48.15, 11.55));
    await settle(tester);

    // Nach oben aufgeklappt heißt: der erste Eintrag liegt am TIEFSTEN.
    final anlegen = tester.getTopLeft(find.text('Spot anlegen')).dy;
    for (final label in ['Was ist hier?', 'Navigation', 'Heranzoomen']) {
      expect(tester.getTopLeft(find.text(label)).dy, lessThan(anlegen),
          reason: label);
    }

    Color? fuellung(String label) => tester
        .widget<Material>(find.ancestor(
            of: find.text(label), matching: find.byType(Material)).first)
        .color;
    expect(fuellung('Spot anlegen'), AppColors.forestGreen);
    expect(fuellung('Was ist hier?'), isNot(AppColors.forestGreen));
  });

  testWidgets('„Spot anlegen" öffnet das Blatt für DIESE Stelle',
      (tester) async {
    // **Die gedrückte Stelle, nicht die Bildmitte.** Genau das war der
    // Wunsch: Bis #513 führte der einzige Weg über das Fadenkreuz, man
    // musste die Karte also erst verschieben, bis die Stelle mittig lag.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);

    await simulateMapLongPress(tester, const LatLng(47.9, 10.2));
    await settle(tester);
    await tester.tap(find.text('Spot anlegen'));
    await settle(tester);

    expect(find.text('Neuer Pilz-Spot'), findsOneWidget);
    // **Bis zum Speichern durchgespielt.** Dass ein Blatt aufgeht,
    // beweist nichts über die Stelle; erst die Koordinate in der
    // Datenbank tut es. Vorher nahm dieser Weg die Bildmitte.
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);

    final spot = backend.spots.single;
    expect(spot.lat, closeTo(47.9, 0.0001));
    expect(spot.lng, closeTo(10.2, 0.0001));
  });

  testWidgets('Daneben tippen schließt es folgenlos', (tester) async {
    // Der Rückweg, der das Menü überhaupt erst ungefährlich macht.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);

    await simulateMapLongPress(tester, const LatLng(48.15, 11.55));
    await settle(tester);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);

    expect(find.text('Was ist hier?'), findsNothing);
  });

  testWidgets('„Was ist hier?" öffnet das Blatt für DIESE Stelle',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);

    await simulateMapLongPress(tester, const LatLng(48.15, 11.55));
    await settle(tester);
    await tester.tap(find.text('Was ist hier?'));
    await settle(tester);

    // Die Koordinate im Blattkopf ist der Beweis, dass es für GENAU
    // diese Stelle aufging — ohne sie prüfte der Test nur, dass
    // irgendein Blatt erschien.
    expect(find.textContaining('48,1500 N · 11,5500 O'), findsOneWidget);
  });

  testWidgets('„Heranzoomen" tut, was der lange Tipp früher sofort tat',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);

    const pressed = LatLng(48.15, 11.55);
    await simulateMapLongPress(tester, pressed);
    await settle(tester);
    await tester.tap(find.text('Heranzoomen'));
    await settle(tester);

    final camera = tester.state<FakeMapViewState>(find.byType(FakeMapView));
    expect(camera.center, pressed);
    expect(camera.zoom, 16);
  });

  testWidgets('Der Profil-Schalter für die Geste ist weg', (tester) async {
    // Ein Schalter ohne Wirkung wäre eine Lüge — und der Grund für
    // seine Existenz (die Geste ist gefährlich) ist entfallen.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);

    await tester.tap(find.text('Profil'));
    await settle(tester);

    expect(find.text('Karte gedrückt halten'), findsNothing);
  });

  testWidgets('Und kein Dauerhinweis mehr über den Bannern', (tester) async {
    // Mit einer Geste, die IMMER an ist, stünde die alte Erklärzeile auf
    // jedem Bildschirm. Sie wohnt jetzt in der Kurzanleitung.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);

    expect(find.textContaining('Gedrückt halten richtet'), findsNothing);
  });
}
