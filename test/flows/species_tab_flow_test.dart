// Der Reiter „Pilze": Gruppen, Arten, Hervorhebung nach Monat und der
// Filter „Nur jetzt Saison" — vom Reiter aus, nicht aus dem Modell.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/widgets/season_bars.dart';
import 'package:pilzbuddy/features/species/species_catalogue.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

void main() {
  Future<void> openTab(WidgetTester tester, int month) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    await pumpApp(tester, backend, month: month);
    await tester.tap(find.text('Pilze'));
    await settle(tester);
  }

  bool highlighted(WidgetTester tester, String name) =>
      tester.widget<Text>(find.text(name)).style?.fontWeight ==
      FontWeight.w600;

  Future<void> scrollTo(WidgetTester tester, String name) async {
    await tester.scrollUntilVisible(find.text(name), 200,
        scrollable: find.byType(Scrollable).first);
    await settle(tester, frames: 4);
  }

  testWidgets('zeigt die Gruppen aus dem Modell und hebt die Saison hervor',
      (tester) async {
    await openTab(tester, 9);

    expect(find.text('Steinpilz & Co.'), findsOneWidget);
    expect(find.textContaining('Temperaturfenster 13,0 °C'), findsOneWidget);
    // Der Steinpilz ist im September in der Hauptzeit — hervorgehoben,
    // mit Kurve und Belegen.
    expect(highlighted(tester, 'Steinpilz'), isTrue);
    expect(find.text('Hauptzeit · Belege: gut belegt'), findsWidgets);
    expect(find.byType(SeasonBars), findsWidgets);

    // Der Austernseitling hat im September keine Saison.
    await scrollTo(tester, 'Austernseitling & Co.');
    expect(find.textContaining('Regen, Temperatur und Bodenfeuchte'),
        findsOneWidget);
    await scrollTo(tester, 'Austernseitling');
    expect(highlighted(tester, 'Austernseitling'), isFalse);
  });

  testWidgets('der Filter lässt nur die Saison stehen, im Februar den '
      'Austernseitling und nicht den Steinpilz', (tester) async {
    await openTab(tester, 2);
    expect(highlighted(tester, 'Steinpilz'), isFalse);

    await tester.tap(find.text('Nur jetzt Saison'));
    await settle(tester);

    expect(find.text('Steinpilz'), findsNothing);
    // Die Gruppe bleibt als Überschrift stehen — sonst wüsste man
    // nicht, dass sie leer ist und nicht fehlt.
    expect(find.text('Steinpilz & Co.'), findsOneWidget);
    await scrollTo(tester, 'Austernseitling');
    expect(highlighted(tester, 'Austernseitling'), isTrue);
  });

  testWidgets('der Rest ohne Ampel steht am Ende, mit Grund',
      (tester) async {
    await openTab(tester, 9);
    await scrollTo(tester, kCatalogueGreyTitle);
    expect(find.textContaining('Lieber grau als erfunden'), findsOneWidget);
    // Hallimasch hat eine Kurve (Oktober-Gipfel), aber keine Ampel —
    // also Saisonwort ohne Belege.
    await scrollTo(tester, 'Hallimasch');
    expect(find.text('Randzeit'), findsWidgets);
    expect(find.text('Hallimasch'), findsOneWidget);
  });

  testWidgets('der Schalter nimmt eine Art aus der Ampel — und merkt es sich',
      (tester) async {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    final settings = FakeSettings();
    await pumpApp(tester, backend, settings: settings, month: 9);
    await tester.tap(find.text('Pilze'));
    await settle(tester);

    Finder switchOf(String name) => find.descendant(
        of: find.widgetWithText(ListTile, name), matching: find.byType(Switch));

    await scrollTo(tester, 'Steinpilz');
    expect(tester.widget<Switch>(switchOf('Steinpilz')).value, isTrue,
        reason: 'ab Werk zählt jede Art');
    await tester.tap(switchOf('Steinpilz'));
    await settle(tester);
    expect(settings.ampelExcludedSpecies, {'Steinpilz'});
    expect(find.textContaining('von der Ampel ausgenommen'), findsOneWidget);
    expect(tester.widget<Switch>(switchOf('Steinpilz')).value, isFalse);

    // Zurück — der Satz geht wieder.
    await tester.tap(switchOf('Steinpilz'));
    await settle(tester);
    expect(settings.ampelExcludedSpecies, isEmpty);
    expect(find.textContaining('von der Ampel ausgenommen'), findsNothing);

    // Ohne Ampel gibt es nichts auszunehmen: kein Schalter.
    await scrollTo(tester, 'Hallimasch');
    expect(switchOf('Hallimasch'), findsNothing);
  });
}
