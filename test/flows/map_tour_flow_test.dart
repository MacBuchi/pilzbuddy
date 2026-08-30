// Die geführte Tour über die Karte (#350, Baustein B).
//
// Vier Zusagen stehen hier, und keine davon ist der Wortlaut:
//
//   1. Sie läuft beim ersten Start an — und danach nie wieder.
//   2. Überspringen zählt wie Durchsehen.
//   3. Das Loch sitzt auf dem ECHTEN Knopf, nicht auf einer festen Zahl.
//   4. Sie sperrt niemanden ein.
//   5. Sie lässt keinen Knopf der Hauptseite aus.
//   6. Am Ende führt ein Knopf in die Kurzanleitung — bis 1.109.0 war
//      dieser Verweis eine Behauptung im Kopfkommentar und sonst nichts.
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

/// Die Schritte in ihrer Reihenfolge. Einmal hier, weil zwei Tests sie
/// durchlaufen — und weil die REIHENFOLGE eine Aussage ist: Ab Schritt 3
/// läuft der Scheinwerfer die Knopfspalte hinunter, und geendet wird auf
/// „Unterwegs", nicht auf dem Filter.
const kTourTitles = [
  'So entsteht ein Spot',
  'Wo du gerade bist',
  'Was die Karte zeigt',
  'Wenn es viele Spots werden',
  'Unterwegs',
];

void main() {
  /// Ein Gerät dieser Maße — Oberfläche UND `MediaQuery`.
  ///
  /// `setSurfaceSize` allein ändert nur die Fläche; `MediaQuery` meldet
  /// weiter 800×600, und dann rechnet der geprüfte Code mit einem
  /// Bildschirm, den es im Test nicht gibt. Genau daran ist in #358 eine
  /// gemessene Zahl falsch ins Repo gewandert.
  void useScreen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

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
    expect(find.text('1 von 5'), findsOneWidget);
    expect(holes(tester), hasLength(2));
  });

  testWidgets('das Loch sitzt auf dem ECHTEN Knopf', (tester) async {
    // **Der Wächter, ohne den die Tour still danebenzeigen kann.** Die
    // Knopfspalte steckt seit 1.98.0 in einem `FittedBox(scaleDown)`:
    // Ihre Maße hängen an der Bildschirmhöhe, und eine feste Zahl wäre
    // dort am falschesten, wo der Schirm klein ist. Deshalb wird gegen
    // `getRect` des Knopfs geprüft, nicht gegen eine Konstante.
    useScreen(tester, const Size(412, 915));
    await pumpApp(tester, signedIn(), settings: fresh());

    await tester.tap(find.text('Weiter'));
    await settle(tester);
    expect(find.text('Wo du gerade bist'), findsOneWidget);
    expect(holes(tester).single, tester.getRect(fab('locate')));

    await tester.tap(find.text('Weiter'));
    await settle(tester);
    expect(find.text('Was die Karte zeigt'), findsOneWidget);
    expect(holes(tester).single, tester.getRect(fab('layers')));

    await tester.tap(find.text('Weiter'));
    await settle(tester);
    expect(holes(tester).single, tester.getRect(fab('filter')));

    await tester.tap(find.text('Weiter'));
    await settle(tester);
    expect(holes(tester).single, tester.getRect(fab('trip')));
  });

  testWidgets('fünf Schritte, dann ist sie durch — und kommt nicht wieder',
      (tester) async {
    final settings = fresh();
    await pumpApp(tester, signedIn(), settings: settings);

    for (final title in kTourTitles) {
      expect(find.text(title), findsOneWidget, reason: 'Schritt „$title"');
      await tester.tap(
          find.text(title == kTourTitles.last ? 'Los geht\'s' : 'Weiter'));
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

  testWidgets('die Zurück-Taste beendet die Tour, nicht die App',
      (tester) async {
    // Eine bildschirmfüllende Abdunkelung, die auf Zurück nicht reagiert,
    // ist eine Falle: Auf der Karte ist Zurück der Weg AUS der App, wer
    // also den Reflex hat, die Tour damit wegzuwischen, legt PilzBuddy in
    // den Hintergrund.
    final settings = fresh();
    await pumpApp(tester, signedIn(), settings: settings);
    expect(find.text(kTourTitles.first), findsOneWidget);

    await tester.binding.handlePopRoute();
    await settle(tester);

    expect(find.text(kTourTitles.first), findsNothing);
    // Zurück zählt wie Überspringen: Wer abbricht, hat entschieden.
    expect(settings.mapTourSeen, isTrue);
    // Und die App steht noch da, wo sie stand.
    expect(find.byTooltip('Ebenen'), findsOneWidget);
  });

  testWidgets('ohne laufende Tour fängt niemand die Zurück-Taste ab',
      (tester) async {
    // Die andere Hälfte, und die wiegt schwerer: Ein Abfangen, das
    // stehen bleibt, sperrt den Nutzer für den Rest der Sitzung in der
    // App ein — ohne dass irgendetwas auf dem Schirm verriete, warum.
    await pumpApp(tester, signedIn(), settings: FakeSettings());
    expect(find.text(kTourTitles.first), findsNothing);
    expect(
        find.descendant(
            of: find.byType(MapTourOverlay), matching: find.byType(PopScope)),
        findsNothing);
  });

  testWidgets('auf einem anderen Reiter fängt die Tour die Zurück-Taste '
      'nicht ab', (tester) async {
    // Die Karte lebt im `IndexedStack` weiter, wenn man den Reiter
    // wechselt — mit ihr das `PopScope`. Verdeckt darf es nichts
    // schlucken: Sonst beendete ein Zurück im Profil still eine Tour, die
    // der Nutzer dort gar nicht sieht. Nachgemessen, nicht angenommen.
    final settings = fresh();
    await pumpApp(tester, signedIn(), settings: settings);
    await tester.tap(find.text('Profil'));
    await settle(tester);

    await tester.binding.handlePopRoute();
    await settle(tester);

    expect(settings.mapTourSeen, isFalse,
        reason: 'im Profil gedrückt, im Profil gewirkt');
    // Und die Tour steht unversehrt da, wo sie stand.
    await tester.tap(find.text('Karte'));
    await settle(tester);
    expect(find.text(kTourTitles.first), findsOneWidget);
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

  testWidgets('kein Knopf der Hauptseite bleibt ungenannt', (tester) async {
    // Der Wächter für den Betreiber-Wunsch (2026-08-29): „quasi alle
    // Knöpfe auf der Hauptseite abgedeckt". Wer sucht, was die Tour
    // ausgelassen hat, weiß ja nicht, dass sie es ausgelassen hat —
    // deshalb ist die Deckung eine Zusage und keine Geschmacksfrage. Ein
    // sechster Knopf in der Spalte ohne eigenen Schritt macht das hier
    // rot.
    useScreen(tester, const Size(412, 915));
    await pumpApp(tester, signedIn(), settings: fresh());

    final seen = <Rect>[];
    for (final title in kTourTitles) {
      expect(find.text(title), findsOneWidget, reason: 'Schritt „$title"');
      seen.addAll(holes(tester));
      if (title == kTourTitles.last) break;
      await tester.tap(find.text('Weiter'));
      await settle(tester);
    }

    for (final tag in ['layers', 'filter', 'trip', 'locate', 'add']) {
      expect(seen, contains(tester.getRect(fab(tag))),
          reason: 'der Knopf „$tag" kommt in keinem Schritt vor');
    }
  });

  testWidgets('die Sprechblase liegt nie auf dem, was sie erklärt',
      (tester) async {
    // Eine Sprechblase über dem Loch ist eine Sprechblase über nichts.
    // Die Seitenwahl hängt an `union.center.dy` gegen die halbe
    // Schirmhöhe — eine Regel, die genau dann kippt, wenn ein Loch nahe
    // der Mitte liegt oder der Schirm klein wird. Beides steht hier,
    // statt es einmal von Hand angesehen zu haben.
    for (final size in [const Size(412, 915), const Size(360, 640)]) {
      useScreen(tester, size);
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, signedIn(), settings: fresh());

      for (final title in kTourTitles) {
        expect(find.text(title), findsOneWidget,
            reason: 'Schritt „$title" bei ${size.width}×${size.height}');
        final bubble = tester.getRect(find.descendant(
            of: find.byType(MapTourOverlay), matching: find.byType(Card)));
        for (final hole in holes(tester)) {
          expect(bubble.overlaps(hole), isFalse,
              reason: 'Schritt „$title" bei ${size.width}×${size.height}: '
                  'Blase $bubble deckt das Loch $hole zu');
        }
        if (title == kTourTitles.last) break;
        await tester.tap(find.text('Weiter'));
        await settle(tester);
      }
    }
  });

  testWidgets('der letzte Schritt führt weiter in die Kurzanleitung',
      (tester) async {
    // Die Zusage aus dem Kopfkommentar, die bis 1.109.0 keine war: Die
    // Tour erklärt nur, was auf diesem Schirm liegt — Leergang, Freigabe
    // und Offline-Karten stehen in der Kurzanleitung, und ohne diesen
    // Knopf sagt das niemandem jemand. Der eine andere Weg dorthin, das
    // grüne Banner, erscheint nur bei völlig leerer Karte.
    final settings = fresh();
    final backend = signedIn();
    // Ein Buddy-Spot auf der Karte: genau der Nutzer, für den die Tour
    // gebaut wurde — und bei dem das Banner mit dem Verweis NICHT steht.
    final buddy = backend.addUser(username: 'buddy');
    backend.addSpot(ownerId: buddy.id, lat: 50.5, lng: 12.5, name: 'Hang');
    await pumpApp(tester, backend, settings: settings);

    for (var i = 0; i < kTourTitles.length - 1; i++) {
      await tester.tap(find.text('Weiter'));
      await settle(tester);
    }
    expect(find.text(kTourTitles.last), findsOneWidget);
    // Im letzten Schritt gibt es nichts mehr zu überspringen — der Platz
    // trägt den Verweis.
    expect(find.text('Überspringen'), findsNothing);

    await tester.tap(find.text('Kurzanleitung'));
    await settle(tester);

    expect(find.text('Kurzanleitung'), findsWidgets, reason: 'Titelzeile');
    expect(find.textContaining('Das Wichtigste in sechs Schritten'),
        findsOneWidget);
    // Und die Tour ist damit durch: Wer hier abbiegt, hat sie gesehen.
    expect(settings.mapTourSeen, isTrue);
    expect(find.text(kTourTitles.last), findsNothing);
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
