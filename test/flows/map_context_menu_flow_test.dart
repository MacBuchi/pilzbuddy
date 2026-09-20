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
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

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

  testWidgets('Langes Drücken öffnet die drei Chips — ohne Schalter',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);

    expect(find.text('Was ist hier?'), findsNothing);

    await simulateMapLongPress(tester, const LatLng(48.15, 11.55));
    await settle(tester);

    expect(find.text('Was ist hier?'), findsOneWidget);
    expect(find.text('Navigation'), findsOneWidget);
    expect(find.text('Heranzoomen'), findsOneWidget);
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
