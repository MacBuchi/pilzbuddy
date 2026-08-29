// Die geführte Tour über die Karte (#350, Baustein B).
//
// Vier Zusagen stehen hier, und keine davon ist der Wortlaut:
//
//   1. Sie läuft beim ersten Start an — und danach nie wieder.
//   2. Überspringen zählt wie Durchsehen.
//   3. Das Loch sitzt auf dem ECHTEN Knopf, nicht auf einer festen Zahl.
//   4. Sie sperrt niemanden ein.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/help/map_tour.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

Finder fab(String tag) => find.byWidgetPredicate(
    (widget) => widget is FloatingActionButton && widget.heroTag == tag);

/// Die Löcher, die gerade wirklich gemalt werden.
List<Rect> holes(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<SpotlightPainter>()
    .single
    .holes;

void main() {
  FakeBackend signedIn() {
    final backend = FakeBackend();
    backend.signInAs(backend.addUser(username: 'testpilz').id);
    return backend;
  }

  /// Ein Gerät, das die Tour noch nicht gesehen hat. `FakeSettings`
  /// stellt bewusst das Gegenteil ein (sonst bekäme jeder Bestandstest
  /// die Tour übergestülpt), hier wird es ausdrücklich zurückgenommen.
  FakeSettings fresh() => FakeSettings(mapTourSeen: false);

  testWidgets('läuft beim ersten Start an und nennt Fadenkreuz UND Knopf',
      (tester) async {
    // Die Hürde des ersten Starts ist nicht der Knopf, sondern dass
    // Fadenkreuz und Knopf zusammengehören — deshalb stellt Schritt 1
    // BEIDE frei und nicht nacheinander eines davon.
    await pumpApp(tester, signedIn(), settings: fresh());

    expect(find.text('So entsteht ein Spot'), findsOneWidget);
    expect(find.text('1 von 4'), findsOneWidget);
    expect(holes(tester), hasLength(2));
  });

  testWidgets('das Loch sitzt auf dem ECHTEN Knopf', (tester) async {
    // **Der Wächter, ohne den die Tour still danebenzeigen kann.** Die
    // Knopfspalte steckt seit 1.98.0 in einem `FittedBox(scaleDown)`:
    // Ihre Maße hängen an der Bildschirmhöhe, und eine feste Zahl wäre
    // dort am falschesten, wo der Schirm klein ist. Deshalb wird gegen
    // `getRect` des Knopfs geprüft, nicht gegen eine Konstante.
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApp(tester, signedIn(), settings: fresh());

    await tester.tap(find.text('Weiter'));
    await settle(tester);
    expect(find.text('Was die Karte zeigt'), findsOneWidget);
    expect(holes(tester).single, tester.getRect(fab('layers')));

    await tester.tap(find.text('Weiter'));
    await settle(tester);
    expect(holes(tester).single, tester.getRect(fab('trip')));

    await tester.tap(find.text('Weiter'));
    await settle(tester);
    expect(holes(tester).single, tester.getRect(fab('filter')));
  });

  testWidgets('vier Schritte, dann ist sie durch — und kommt nicht wieder',
      (tester) async {
    final settings = fresh();
    await pumpApp(tester, signedIn(), settings: settings);

    for (final title in [
      'So entsteht ein Spot',
      'Was die Karte zeigt',
      'Unterwegs',
      'Wenn es viele Spots werden',
    ]) {
      expect(find.text(title), findsOneWidget, reason: 'Schritt „$title"');
      await tester.tap(find.text(title == 'Wenn es viele Spots werden'
          ? 'Los geht\'s'
          : 'Weiter'));
      await settle(tester);
    }

    expect(find.text('So entsteht ein Spot'), findsNothing);
    expect(settings.mapTourSeen, isTrue);

    // Der Neustart braucht einen leeren Frame dazwischen — ein zweiter
    // `pumpApp` allein hält dasselbe `ProviderScope`-Element und damit
    // den ganzen Container am Leben.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, signedIn(), settings: settings);
    expect(find.text('So entsteht ein Spot'), findsNothing);
  });

  testWidgets('Überspringen zählt wie Durchsehen', (tester) async {
    // Wer abbricht, hat entschieden. Eine Tour, die nach dem
    // Überspringen wiederkommt, ist keine Hilfe mehr.
    final settings = fresh();
    await pumpApp(tester, signedIn(), settings: settings);

    expect(find.text('Überspringen'), findsOneWidget);
    await tester.tap(find.text('Überspringen'));
    await settle(tester);

    expect(find.text('So entsteht ein Spot'), findsNothing);
    expect(settings.mapTourSeen, isTrue);
  });

  testWidgets('sie sperrt nicht ein — die Reiter bleiben erreichbar',
      (tester) async {
    // Deshalb liegt das Overlay INNERHALB des Karten-Zweigs und nicht
    // app-weit: Die Reiterleiste gehört der Hülle und bleibt frei.
    await pumpApp(tester, signedIn(), settings: fresh());
    expect(find.text('So entsteht ein Spot'), findsOneWidget);

    await tester.tap(find.text('Profil'));
    await settle(tester);
    expect(find.text('So entsteht ein Spot'), findsNothing,
        reason: 'auf einem anderen Reiter hat die Karten-Tour nichts zu '
            'suchen');
  });

  testWidgets('aus der Kurzanleitung neu startbar', (tester) async {
    // Wer sie übersprungen hat, soll sie wiederfinden — und zwar dort,
    // wo er ohnehin nach einer Erklärung sucht.
    final settings = FakeSettings(mapTourSeen: true);
    await pumpApp(tester, signedIn(), settings: settings);
    expect(find.text('So entsteht ein Spot'), findsNothing);

    await tester.tap(find.text('Profil'));
    await settle(tester);
    final tile = find.text('Kurzanleitung');
    for (var i = 0; i < 8 && tile.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester, frames: 4);
    }
    await tester.ensureVisible(tile);
    await settle(tester);
    await tester.tap(tile);
    await settle(tester);

    final start = find.text('Tour auf der Karte zeigen');
    for (var i = 0; i < 8 && start.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
      await settle(tester, frames: 4);
    }
    await tester.ensureVisible(start);
    await settle(tester);
    await tester.tap(start);
    await settle(tester);

    // Zurück auf der Karte, und die Tour läuft.
    expect(find.text('So entsteht ein Spot'), findsOneWidget);
    expect(holes(tester), hasLength(2));
  });
}
