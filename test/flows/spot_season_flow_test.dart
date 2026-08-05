// Die Saisonkurve am Spot, vom Blatt aus.
//
// Der Weg wird ganz gegangen, weil die Teile ihn nicht beweisen: Eine
// richtig gerechnete Kurve nützt nichts, wenn der Abschnitt am falschen
// Spot erscheint, bei einer Freitext-Art etwas erfindet — oder wenn er
// auf Wetterdaten wartet, die im Wald nie kommen.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/spots/widgets/species_season_section.dart';
import 'package:pilzbuddy/features/spots/widgets/spot_rain_section.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  FakeBackend loggedInWithSpot(String? species, {String name = 'Buchenhang'}) {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    backend.addSpot(
      ownerId: me.id,
      lat: 51.0,
      lng: 11.0,
      name: name,
      species: species,
    );
    return backend;
  }

  Future<void> openSpot(WidgetTester tester,
      [String name = 'Buchenhang']) async {
    await tester.tap(find.byTooltip(name));
    await settle(tester);
  }

  testWidgets('nennt Art und Hauptzeit', (tester) async {
    await pumpApp(tester, loggedInWithSpot('Steinpilz'));
    await openSpot(tester);

    expect(find.text('Wann diese Art gemeldet wird'), findsOneWidget);
    // August und September — die Zahlen aus docs/pilzampel-konzept.md,
    // gerechnet von tool/season_curves.py.
    expect(find.textContaining('Steinpilz wird am häufigsten von August bis '
        'September gemeldet.'), findsOneWidget);
  });

  testWidgets('ein einzelner Gipfelmonat bekommt die andere Präposition',
      (tester) async {
    // „von April" wäre falsch, „im April bis Mai" auch — mit einer
    // einzigen Präposition wird eines von beiden schief. Aufgefallen
    // erst im Vorschaubild, keinem Test.
    await pumpApp(tester, loggedInWithSpot('Speisemorchel'));
    await openSpot(tester);

    expect(find.textContaining('Speisemorchel wird am häufigsten im April '
        'gemeldet.'), findsOneWidget);
  });

  testWidgets('steht ohne Netz und ohne Zustimmung da', (tester) async {
    // Die eigentliche Zusage dieses Abschnitts: Die Zahlen liegen im
    // Binary. Der Regenabschnitt daneben fragt erst, ob er rund 1 MB
    // laden darf — die Saisonkurve darf davon nicht abhängen, sonst ist
    // sie genau dort weg, wo sie gebraucht wird.
    await pumpApp(tester, loggedInWithSpot('Steinpilz'));
    await openSpot(tester);

    expect(find.byType(SpeciesSeasonSection), findsOneWidget);
    expect(find.textContaining('Steinpilz wird am häufigsten'), findsOneWidget);
    // Der Nachbar wartet noch auf die Zustimmung.
    expect(find.text('Wetterdaten laden'), findsOneWidget);
  });

  testWidgets('steht über dem Wetter', (tester) async {
    // Die Art gehört zur Fundliste darüber, das Wetter ist die weitere
    // Frage. Vertauscht liest sich das Blatt anders, und niemand merkt es.
    await pumpApp(tester, loggedInWithSpot('Steinpilz'));
    await openSpot(tester);

    final season = tester.getTopLeft(find.byType(SpeciesSeasonSection)).dy;
    final rain = tester.getTopLeft(find.byType(SpotRainSection)).dy;
    expect(season, lessThan(rain));
  });

  testWidgets('ein Zweitname bekommt die Kurve seiner Hauptbezeichnung',
      (tester) async {
    // Gespeichert wird „Maronenröhrling"; wer den Spot als „Marone"
    // angelegt hat, darf nicht ohne Kurve dastehen.
    await pumpApp(tester, loggedInWithSpot('Marone'));
    await openSpot(tester);

    expect(find.textContaining('Maronenröhrling wird am häufigsten'),
        findsOneWidget);
  });

  testWidgets('ein Sammelbegriff sagt, dass er einer ist', (tester) async {
    // „Rotkappe" ist in GBIF eine ganze Gattung. Ohne den Zusatz läse
    // sich die Kurve genauer, als sie ist.
    await pumpApp(tester, loggedInWithSpot('Rotkappe'));
    await openSpot(tester);

    expect(find.textContaining('Rotkappe (mehrere ähnliche Arten)'),
        findsOneWidget);
  });

  testWidgets('eine eigene Art bekommt keine Kurve', (tester) async {
    // Freitext-Arten kennt GBIF nicht — und raten wäre schlimmer als
    // schweigen.
    await pumpApp(tester, loggedInWithSpot('Omas Geheimpilz'));
    await openSpot(tester);

    expect(find.byType(SpeciesSeasonSection), findsOneWidget);
    expect(find.text('Wann diese Art gemeldet wird'), findsNothing);
  });

  testWidgets('ein Spot ohne Fund bekommt keine Kurve', (tester) async {
    await pumpApp(tester, loggedInWithSpot(null));
    await openSpot(tester);

    expect(find.text('Wann diese Art gemeldet wird'), findsNothing);
  });

  testWidgets('eine zu dünn belegte Art bekommt keine Kurve', (tester) async {
    // Der Igelstachelbart steht mit 94 Beobachtungen in der Tabelle. Aus
    // zwölf Monatsfächern davon ließe sich ein Diagramm zeichnen — es
    // wäre nur keine Aussage.
    await pumpApp(tester, loggedInWithSpot('Igelstachelbart'));
    await openSpot(tester);

    expect(find.text('Wann diese Art gemeldet wird'), findsNothing);
  });

  testWidgets('nennt die Quelle und was die Zahlen nicht sind',
      (tester) async {
    // Nicht verhandelbar (docs/pilzampel-konzept.md, „Ehrlichkeit im
    // UI"): Die Kurve beschreibt Meldungen früherer Jahre, nicht dieses
    // Wochenende — und das muss dastehen, nicht im Kleingedruckten.
    await pumpApp(tester, loggedInWithSpot('Steinpilz'));
    await openSpot(tester);

    expect(find.textContaining('GBIF'), findsOneWidget);
    expect(find.textContaining('Das beschreibt frühere Jahre, nicht dieses.'),
        findsOneWidget);
    // Kein Prozentzeichen, keine Wahrscheinlichkeit — die Lehre aus den
    // recherchierten Diensten.
    expect(find.textContaining('%'), findsNothing);
  });
}
