// Die Detailseite je Art (#511) — vom Reiter aus, nicht aus dem Modell.
//
// Was hier festgehalten wird, sind fünf Zusagen: Die Zeile lässt sich
// öffnen; die Seite sagt, was die Zeile nicht sagen konnte; sie schaltet
// die Ampel über DENSELBEN Schalter wie die Liste; der Weg auf die Karte
// stellt den Filter und wechselt den Reiter; und die 0,6 MB der
// Fundorte werden erst hier gelesen, nicht schon in der Liste.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pilzbuddy/core/widgets/season_bars.dart';
import 'package:pilzbuddy/features/map/gbif_finds_providers.dart';
import 'package:pilzbuddy/features/species/species_detail_screen.dart';
import 'package:pilzbuddy/features/species/species_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  /// Zum Reiter „Pilze" und dort auf eine Art tippen.
  ///
  /// Gescrollt wird im Reiter selbst — `Scrollable.first` wäre die
  /// Karte nebenan, die im IndexedStack am Leben bleibt.
  Future<void> openSpecies(WidgetTester tester, String name) async {
    await openTab(tester, 'Pilze');
    await tester.scrollUntilVisible(find.text(name), 200,
        scrollable: find.descendant(
            of: find.byType(SpeciesScreen), matching: find.byType(Scrollable)));
    await settle(tester, frames: 4);
    await tester.tap(find.text(name));
    await settle(tester);
  }

  /// Auf der Detailseite zu etwas scrollen. Fünf Abschnitte passen auf
  /// keinen Testschirm, und eine `ListView` baut nur, was in Sichtweite
  /// ist — der Zielbereich muss benannt werden, sonst greift der Zug an
  /// der Liste im Reiter dahinter.
  Future<void> scrollDetail(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 200,
        scrollable: find.descendant(
            of: find.byType(SpeciesDetailScreen),
            matching: find.byType(Scrollable)));
    await settle(tester, frames: 4);
  }

  testWidgets('die Zeile öffnet die Seite — mit dem Namen, den die Liste '
      'nicht zeigen konnte', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Steinpilz');

    expect(find.byType(SpeciesDetailScreen), findsOneWidget);
    // Der wissenschaftliche Name ist der einzige eindeutige Schlüssel —
    // in der Liste stand er nirgends.
    expect(find.text('Boletus edulis'), findsOneWidget);
    // Und die Zweitnamen: Wer den Pilz nur als „Herrenpilz" kennt, soll
    // sehen, dass die App ihn kennt.
    expect(find.text('auch: Herrenpilz, Fichtensteinpilz'), findsOneWidget);
    // Der Satz, den eine Detailseite braucht und eine Zeile nicht.
    await scrollDetail(tester, find.textContaining('bestimmt keine Pilze'));
    expect(find.textContaining('bestimmt keine Pilze'), findsOneWidget);
  });

  testWidgets('die Saison steht groß da, mit dem Satz des Spot-Blatts',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Steinpilz');

    // Zwölf Balken MIT Monatsbuchstaben — in der Liste sind sie 84 px
    // breit und unbeschriftet, und genau das ist der Unterschied.
    final bars = tester.widget<SeasonBars>(
        find.descendant(
            of: find.byType(SpeciesDetailScreen),
            matching: find.byType(SeasonBars)));
    expect(bars.showLetters, isTrue);
    expect(bars.currentMonth, 8, reason: 'September, aus currentMonthProvider');

    expect(find.text('September: Hauptzeit'), findsOneWidget);
    expect(find.textContaining('wird am häufigsten von August bis September'),
        findsOneWidget);
    // Die Quelle gehört dazu — die Kurve beschreibt frühere Jahre.
    expect(find.textContaining('verrechnet gegen den allgemeinen Meldeeifer'),
        findsOneWidget);
  });

  testWidgets('eine geborgte Kurve sagt, dass sie geborgt ist',
      (tester) async {
    // **Der eigentliche Wächter dieser Datei.** `borrowedFrom` stand bis
    // 1.160.0 NUR im Spot-Blatt — im Reiter „Pilze" las sich die Kurve
    // des Igelstachelbarts als Aussage über ihn, obwohl sie 1147
    // Meldungen über die ganze Gattung sind.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Igelstachelbart');

    expect(find.textContaining('Saison nach verwandten Arten: Stachelbärte'),
        findsOneWidget);
  });

  testWidgets('eigene Funde zählen, Buddy-Funde nicht', (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id);
    final spotId = backend.addSpot(
        ownerId: me.id,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 3));
    backend.addFindRow(spotId,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 20),
        authorId: lilli.id);
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Steinpilz');

    await scrollDetail(tester, find.textContaining('zuletzt am'));
    expect(find.text('1 Fund an 1 Spot, zuletzt am 3.9.2026.'), findsOneWidget,
        reason: 'lillis Fund vom 20.9. ist ihre Ausbeute, nicht meine');
  });

  testWidgets('„Auf der Karte zeigen" stellt den Filter und wechselt den '
      'Reiter', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, species: 'Steinpilz');
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Steinpilz');

    await scrollDetail(tester, find.text('Auf der Karte zeigen'));
    await tester.tap(find.text('Auf der Karte zeigen'));
    await settle(tester);

    // Auf der Karte, und der Filter MELDET sich (#154) — ein Filter,
    // den die App selbst setzt, ohne es zu sagen, ist genau der Fall,
    // vor dem die Regel warnt.
    expect(find.text('🔍 Gefiltert: nur Steinpilz'), findsOneWidget);
    expect(find.byType(SpeciesDetailScreen), findsNothing);
  });

  testWidgets('der Schalter ist derselbe wie in der Liste', (tester) async {
    // Zwei Wahrheiten über „zählt diese Art für die Ampel" wären eine zu
    // viel: Der Schalter auf der Seite schreibt in denselben Provider,
    // und die Zeile sagt es danach.
    final (backend, _) = loggedInBackend();
    final settings = FakeSettings();
    await pumpApp(tester, backend, settings: settings);
    await openSpecies(tester, 'Steinpilz');

    await scrollDetail(tester, find.text('Für die Ampel mitzählen'));
    await tester.tap(find.text('Für die Ampel mitzählen'));
    await settle(tester);
    expect(settings.ampelExcludedSpecies, {'Steinpilz'});

    // `pageBack()` sucht den englischen „Back"-Tooltip — die App ist
    // deutsch (dieselbe Stelle wie in offline_maps_flow_test.dart).
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.textContaining('von der Ampel ausgenommen'), findsOneWidget);
  });

  testWidgets('eine Art, die es nicht gibt, sagt das — statt abzustürzen',
      (tester) async {
    // Die Adresse trägt den Namen, und die kann aus einem Lesezeichen
    // kommen oder aus einer Fassung, die eine Art noch nicht hatte.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openTab(tester, 'Pilze');

    GoRouter.of(tester.element(find.byType(SpeciesScreen)))
        .go('/pilze/Geheimpilz');
    await settle(tester);

    expect(find.textContaining('kennt PilzBuddy nicht'), findsOneWidget);
  });

  testWidgets('die Liste liest die Fundorte NICHT, die Seite schon',
      (tester) async {
    // Beobachten ist laden (CLAUDE.md): 0,6 MB beim Öffnen eines
    // Reiters wären dieselbe Last, die 1.99.4 aus dem Startpfad genommen
    // hat. Auf einer bewusst geöffneten Seite sind sie in Ordnung.
    var calls = 0;
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, extraOverrides: [
      gbifFindsLoaderProvider.overrideWithValue(() async {
        calls++;
        return null;
      }),
    ]);

    await openTab(tester, 'Pilze');
    expect(calls, 0, reason: 'der Reiter allein packt nichts aus');

    await openSpecies(tester, 'Steinpilz');
    expect(calls, 1);
  });

  testWidgets('auf Telefonbreite passt auch der längste Name',
      (tester) async {
    // Die Seite ist die erste im Reiter, die eine volle Spalte Text
    // trägt — und Überlauf sieht man im Widget-Test nur, wenn man in
    // der Breite misst, in der die App benutzt wird. Gemessen wird
    // gegen `tester.view`, nicht mit `setSurfaceSize`: Das ändert die
    // MediaQuery nicht (#414).
    //
    // „Frühjahrsknollenblätterpilz" ist zugleich der Fall OHNE Kurve —
    // der bekommt bewusst keine, weil die Gattungskurve für ihn in die
    // Gegenrichtung zeigte und Scheingenauigkeit bei einem tödlich
    // giftigen Pilz teurer ist als eine Lücke.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Frühjahrsknollenblätterpilz');

    expect(tester.takeException(), isNull);
    expect(find.text('Amanita verna'), findsOneWidget);
    expect(find.textContaining('keine belastbare Kurve'), findsOneWidget);
    await scrollDetail(tester, find.textContaining('bestimmt keine Pilze'));
    expect(tester.takeException(), isNull);
  });
}
