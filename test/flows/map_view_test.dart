// Grundeinstellungen der Kartenansicht: Zoom-Grenzen und Maßstabsanzeige.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/app_colors.dart';
import 'package:pilzbuddy/features/map/finite_camera_constraint.dart';

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
    await pumpApp(tester, loggedInBackend(), useRealMap: true);

    final options = tester.widget<FlutterMap>(find.byType(FlutterMap)).options;
    expect(options.minZoom, 3);
    expect(options.maxZoom, 19);
  });

  testWidgets('Die Karte zeigt einen Maßstab an', (tester) async {
    await pumpApp(tester, loggedInBackend(), useRealMap: true);
    expect(find.byType(Scalebar), findsOneWidget);
  });

  testWidgets('Die Karte verwirft nicht-endliche Kamerazustände',
      (tester) async {
    // Ein NaN-Kamerazustand aus einem Gesten-Grenzfall lässt den
    // MarkerLayer endlos Weltkopien erzeugen (ANR, #151) und die
    // Kachelberechnung werfen (graue Flächen, #141). Der Wächter ist die
    // einzige Stelle, die beides verhindert — wer ihn aus den MapOptions
    // entfernt, holt beide Fehler zurück.
    await pumpApp(tester, loggedInBackend(), useRealMap: true);

    final options = tester.widget<FlutterMap>(find.byType(FlutterMap)).options;
    expect(options.cameraConstraint, isA<FiniteCameraConstraint>());
  });

  testWidgets('Doppeltippen zoomt, Drehen bleibt aus', (tester) async {
    // Seit #210 ist der Long-Press ab Werk aus, und der Doppeltipp ist
    // damit der Weg, an einer Stelle heranzuzoomen. Bis dahin prüfte
    // NICHTS die Gesten-Flags — fiele `doubleTapZoom` still weg (etwa
    // weil jemand die Flags aufzählt statt `all` zu nehmen), stünde
    // genau dieser Wunsch wieder da.
    //
    // Das Nicht-Drehen gehört mit in denselben Test: Es ist die erklärte
    // Invariante beider Engines (MapLibre setzt `rotate: false`), und wer
    // die Flags anfasst, soll beides auf einmal sehen.
    await pumpApp(tester, loggedInBackend(), useRealMap: true);

    final flags = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .options
        .interactionOptions
        .flags;
    expect(InteractiveFlag.hasDoubleTapZoom(flags), isTrue);
    expect(InteractiveFlag.hasRotate(flags), isFalse);
    expect(InteractiveFlag.hasDrag(flags), isTrue,
        reason: 'Schieben ist der Weg, das Fadenkreuz zu setzen');
    expect(InteractiveFlag.hasPinchZoom(flags), isTrue);
  });

  testWidgets('Wartende Flächen sind Landton, nicht Grau', (tester) async {
    // flutter_maps Vorgabe ist 0xFFE0E0E0 — das liest sich wie ein Fehler.
    // Wo noch keine Kachel liegt, soll es nach Karte aussehen (#119).
    await pumpApp(tester, loggedInBackend(), useRealMap: true);

    final options = tester.widget<FlutterMap>(find.byType(FlutterMap)).options;
    expect(options.backgroundColor, AppColors.mapBackground);
    expect(options.backgroundColor, isNot(const Color(0xFFE0E0E0)));
  });

  testWidgets('Die Kachel-Puffer bleiben bei der Paketvorgabe',
      (tester) async {
    // #130 hatte sie auf 3/2 erhöht, damit beim Warten die grobe
    // Nachbarstufe weitergezeichnet wird statt einer Lücke (#119). Das
    // wurde in #142 zurückgenommen: Jede gehaltene Kachel ist eine
    // GPU-Textur, und `flutter_map` gibt sie beim Ausdünnen nicht frei —
    // gemessen wuchs der Texturspeicher auf 257 MB, in den ANR-Berichten
    // auf 1,7–1,9 GB. Wer die Werte wieder anhebt, muss vorher messen.
    await pumpApp(tester, loggedInBackend(), useRealMap: true);

    final layer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(layer.keepBuffer, 2);
    expect(layer.panBuffer, 1);
  });
}
