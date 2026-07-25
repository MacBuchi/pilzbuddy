// Grundeinstellungen der Kartenansicht: Zoom-Grenzen und Maßstabsanzeige.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart';

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

  testWidgets('Wartende Flächen sind Landton, nicht Grau', (tester) async {
    // flutter_maps Vorgabe ist 0xFFE0E0E0 — das liest sich wie ein Fehler.
    // Wo noch keine Kachel liegt, soll es nach Karte aussehen (#119).
    await pumpApp(tester, loggedInBackend());

    final options = tester.widget<FlutterMap>(find.byType(FlutterMap)).options;
    expect(options.backgroundColor, AppColors.mapBackground);
    expect(options.backgroundColor, isNot(const Color(0xFFE0E0E0)));
  });

  testWidgets('Die Kachel-Puffer sind größer als die Vorgabe',
      (tester) async {
    // Mehr behaltene Kacheln = beim Warten wird die grobe Nachbarstufe
    // hochskaliert weitergezeichnet, statt eine Lücke zu zeigen (#119).
    await pumpApp(tester, loggedInBackend());

    final layer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(layer.keepBuffer, greaterThan(2));
    expect(layer.panBuffer, greaterThan(1));
  });
}
