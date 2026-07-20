// Grundeinstellungen der Kartenansicht: Zoom-Grenzen und Maßstabsanzeige.
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  FakeBackend loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return backend;
  }

  testWidgets('Der Karten-Zoom ist nach oben und unten begrenzt',
      (tester) async {
    // Ohne Obergrenze skaliert flutter_map die z19-Kachel ins Absurde und
    // die Karte bleibt leer, bis man weit herauszoomt (Issue #71).
    await pumpApp(tester, loggedInBackend());

    final options = tester.widget<FlutterMap>(find.byType(FlutterMap)).options;
    expect(options.minZoom, 3);
    expect(options.maxZoom, 19);
  });

  testWidgets('Die Karte zeigt einen Maßstab an', (tester) async {
    await pumpApp(tester, loggedInBackend());
    expect(find.byType(Scalebar), findsOneWidget);
  });
}
