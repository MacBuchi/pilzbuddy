// Der Reiter „Pilze": Gruppen, Arten, Hervorhebung nach Monat und der
// Filter „Nur jetzt Saison" — vom Reiter aus, nicht aus dem Modell.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/mushroom_species.dart';
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
    // Seit 1.160.0 mit der vierten Zutat „milder" — die Gruppe nennt sie.
    expect(
        find.textContaining('Regen, Temperatur, Bodenfeuchte und Nächte'),
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

  testWidgets('die Suche macht die Liste enger und sagt, wie viel übrig ist',
      (tester) async {
    await openTab(tester, 9);

    await tester.enterText(
        find.widgetWithText(TextField, 'Art suchen'), 'marone');
    await settle(tester);

    // Der Zweitname führt auf die Hauptbezeichnung — in der Liste steht
    // nur die.
    expect(find.text('Maronenröhrling'), findsOneWidget);
    expect(find.text('Eine Art gefunden.'), findsOneWidget);

    // **Und die übrigen Gruppen sind WEG, nicht bloß unterhalb des
    // Bildschirms.** Der Unterschied ist im Widget-Test alles: Eine
    // `ListView.builder` baut nur, was in Sichtweite ist, und ein
    // nacktes `findsNothing` wäre hier auch dann grün, wenn elf leere
    // Überschriften darunter stünden — in der Gegenprobe genau so
    // gemessen. Deshalb über die ganze Liste eingesammelt.
    final titles = speciesCatalogue(month: 9).map((s) => s.title).toList();
    final seen = <String>{};
    for (var i = 0; i < 10; i++) {
      for (final title in titles) {
        if (find.text(title).evaluate().isNotEmpty) seen.add(title);
      }
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester, frames: 4);
    }
    expect(seen, {'Steinpilz & Co.'},
        reason: 'nur die Gruppe mit dem Treffer behält ihre Überschrift');
  });

  testWidgets('sie findet auch über den wissenschaftlichen Namen',
      (tester) async {
    // Der steht in der Liste nirgends — wer ihn aus einem Buch abliest,
    // fände die Art sonst nicht.
    await openTab(tester, 9);

    await tester.enterText(
        find.widgetWithText(TextField, 'Art suchen'), 'Cantharellus');
    await settle(tester);

    // Auf die ZEILE gezielt: Die Ampel-Gruppe heißt hier wie die Art,
    // der nackte Text stünde also zweimal im Baum.
    expect(find.widgetWithText(ListTile, 'Pfifferling'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Steinpilz'), findsNothing);
  });

  testWidgets('ein Vertipper bekommt einen Vorschlag — und sieht, dass es '
      'einer ist', (tester) async {
    // Dieselbe Antwort wie im Blatt „Fund eintragen": Wer „Steinpliz"
    // tippt, bekommt den Steinpilz. Bis 1.164.0 stand hier „Keine Art
    // mit diesem Namen" — also genau der Satz, aus dem #395 entstanden
    // ist, nur an der anderen Stelle.
    await openTab(tester, 9);

    await tester.enterText(
        find.widgetWithText(TextField, 'Art suchen'), 'steinpliz');
    await settle(tester);

    expect(find.widgetWithText(ListTile, 'Steinpilz'), findsOneWidget);
    // **Und die Liste sagt, dass sie rät.** Ein geratener Treffer, der
    // aussieht wie ein gefundener, ist eine Behauptung über die Eingabe
    // des Nutzers — dieselbe Auflage wie bei den Vorschlägen im
    // Eingabefeld.
    expect(find.text('Keine Art heißt so. Meintest du …?'), findsOneWidget);
    expect(find.textContaining('Arten gefunden'), findsNothing);
  });

  testWidgets('ohne Treffer sagt sie es, statt leer dazustehen',
      (tester) async {
    await openTab(tester, 9);

    await tester.enterText(
        find.widgetWithText(TextField, 'Art suchen'), 'Trüffel');
    await settle(tester);

    expect(find.textContaining('Keine Art mit diesem Namen'), findsOneWidget);
    // Die Zahl ist gezählt, nicht geschrieben — auch hier im Test: Mit
    // dem Schönfußröhrling (1.167.0) wurden es 92, und ein fest
    // geschriebenes „91" war der einzige rote Test des Tages.
    final known = kBekannteArten.where((s) => !s.isSynonym).length;
    expect(find.textContaining('kennt $known Arten'), findsOneWidget);
    expect(find.text('0 Arten gefunden.'), findsOneWidget);
  });

  testWidgets('das X stellt die ganze Liste wieder her', (tester) async {
    // Ein Filter ohne Rückweg ist der Fall aus #425: Wer nicht erkennen
    // kann, wie er ihn loswird, hält die App für kaputt.
    await openTab(tester, 9);
    await tester.enterText(
        find.widgetWithText(TextField, 'Art suchen'), 'marone');
    await settle(tester);
    expect(find.text('Steinpilz'), findsNothing);

    await tester.tap(find.byTooltip('Suche löschen'));
    await settle(tester);

    expect(find.text('Steinpilz'), findsOneWidget);
    expect(find.text('Steinpilz & Co.'), findsOneWidget);
  });

  testWidgets('das Auge steht bei den Arten mit Bildern — und nie vor '
      'der Warnung', (tester) async {
    await openTab(tester, 9);
    // Über die Suche, nicht über einen Zug: Eine `ListView.builder`
    // baut nur, was in Sichtweite ist.
    await tester.enterText(
        find.widgetWithText(TextField, 'Art suchen'), 'Fliegenpilz');
    await settle(tester);

    final zeile = find.widgetWithText(ListTile, 'Fliegenpilz');
    expect(zeile, findsOneWidget);
    final auge = find.descendant(
        of: zeile, matching: find.byIcon(Icons.visibility_outlined));
    final warnung = find.descendant(
        of: zeile, matching: find.byIcon(Icons.warning_amber_rounded));
    expect(auge, findsOneWidget, reason: 'der Fliegenpilz hat drei Bilder');
    expect(warnung, findsOneWidget, reason: 'und er ist giftig');
    // **Die Reihenfolge ist die Zusage.** Buchführung darf der Warnung
    // nicht den Platz nehmen.
    expect(tester.getTopLeft(warnung).dx, lessThan(tester.getTopLeft(auge).dx));
  });

  testWidgets('ohne Bilder steht dort nichts', (tester) async {
    await openTab(tester, 9);
    await tester.enterText(
        find.widgetWithText(TextField, 'Art suchen'), 'Judasohr');
    await settle(tester);

    final zeile = find.widgetWithText(ListTile, 'Judasohr');
    expect(zeile, findsOneWidget, reason: 'die Zeile steht da');
    expect(
        find.descendant(
            of: zeile, matching: find.byIcon(Icons.visibility_outlined)),
        findsNothing);
  });

}
