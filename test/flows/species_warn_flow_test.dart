// Die Warnung dort, wo der Pilz ist (seit 1.168.0).
//
// Bis dahin lebten Einstufung, Verwechslungspartner und Bildpaare NUR im
// Reiter „Pilze" — an dem Ort, den man aufsuchen muss. Die beiden
// Momente, in denen die Warnung zählt, sind andere: das Eingabefeld beim
// Eintragen und das Spot-Blatt. Dazu der Rückkanal für handgepflegte
// Daten: ein Fehler wird dort gemeldet, wo man ihn sieht.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/species/species_detail_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  final speciesField = find.widgetWithText(TextField, 'Pilzart (optional)');

  testWidgets('das Eingabefeld warnt, sobald der Name feststeht — und '
      'nennt die Einstufung nur, wenn sie warnt', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, species: 'Steinpilz');
    await pumpApp(tester, backend);
    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);
    await tester.tap(find.text('Fund eintragen'));
    await settle(tester);

    // **Solange die Vorschlagskarte offen ist, schweigt der Hinweis** —
    // dieselbe Regel wie beim Symbol im Feld. Der Fall, der das wirklich
    // prüft, ist ein VOLLER Name mit mehreren Treffern: „Steinpilz"
    // lässt Sommer- und Kiefernsteinpilz mit in der Karte stehen, der
    // Name ist also noch keine Entscheidung. (Ein halber Name wie
    // „Perlpi" wäre hier trivial: Für ihn gibt es gar keine Partner —
    // in der Gegenprobe blieb die Bedingung damit unbemerkt.)
    await tester.enterText(speciesField, 'Steinpilz');
    await settle(tester);
    expect(find.byType(Card), findsOneWidget, reason: 'die Karte ist offen');
    expect(find.textContaining('Wird verwechselt mit'), findsNothing);

    // Der Tipp auf den Vorschlag ist die Entscheidung — jetzt der Hinweis.
    await tester.tap(find.descendant(
        of: find.byType(Card), matching: find.text('Steinpilz')));
    await settle(tester);
    expect(
        find.text('Wird verwechselt mit: Gallenröhrling (Ungenießbar), '
            'Satansröhrling (Giftig), Schönfußröhrling (Ungenießbar)'),
        findsOneWidget);

    await tester.enterText(speciesField, 'Perlpilz');
    await settle(tester);
    expect(
        find.text('Wird verwechselt mit: Pantherpilz (Giftig), '
            'Fliegenpilz (Giftig), Grüner Knollenblätterpilz '
            '(Tödlich giftig)'),
        findsOneWidget);

    // Ein Speisepilz als Partner heißt nur beim Namen — keine Freigabe.
    await tester.enterText(speciesField, 'Speitäubling');
    await settle(tester);
    expect(find.text('Wird verwechselt mit: Speisetäubling'), findsOneWidget);

    // Ohne Partner steht dort nichts, kein „keine bekannt".
    await tester.enterText(speciesField, 'Judasohr');
    await settle(tester);
    expect(find.textContaining('Wird verwechselt mit'), findsNothing);
  });

  testWidgets('das Spot-Blatt führt zur Artseite — und die giftige Art '
      'trägt ihr Zeichen schon am Chip', (tester) async {
    final (backend, me) = loggedInBackend();
    final spotId = backend.addSpot(
        ownerId: me.id, species: 'Stockschwämmchen');
    backend.addFindRow(spotId, species: 'Gifthäubling',
        foundOn: DateTime(2026, 9, 1), authorId: me.id);
    await pumpApp(tester, backend);
    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);

    final harmless = find.byKey(const ValueKey('species-chip-Stockschwämmchen'));
    final deadly = find.byKey(const ValueKey('species-chip-Gifthäubling'));
    expect(harmless, findsOneWidget);
    expect(deadly, findsOneWidget);
    expect(
        find.descendant(
            of: deadly, matching: find.byIcon(Icons.warning_amber_rounded)),
        findsOneWidget);
    expect(
        find.descendant(
            of: harmless, matching: find.byIcon(Icons.warning_amber_rounded)),
        findsNothing,
        reason: 'nur gegart ist keine Listen-Warnung — wie im Reiter');

    await tester.tap(harmless);
    await settle(tester);

    // Blatt zu, Artseite auf — und zwar von oben.
    expect(find.text('Fund eintragen'), findsNothing);
    expect(find.byType(SpeciesDetailScreen), findsOneWidget);
    expect(find.text('Kuehneromyces mutabilis'), findsOneWidget);
  });

  testWidgets('eine eigene Freitext-Art bekommt keinen Chip', (tester) async {
    // Für sie gibt es keine Seite — ein Chip ins Leere wäre schlimmer
    // als keiner.
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, species: 'Geheimpilz');
    await pumpApp(tester, backend);
    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);

    expect(find.byKey(const ValueKey('species-chip-Geheimpilz')), findsNothing);
    expect(find.text('Fund eintragen'), findsOneWidget,
        reason: 'das Blatt selbst steht');
  });

  testWidgets('„Hinweis zu dieser Art melden" landet als Bug beim Bot, '
      'mit dem Artnamen im Betreff', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openTab(tester, 'Pilze');
    await tester.enterText(
        find.widgetWithText(TextField, 'Art suchen'), 'Steinpilz');
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Steinpilz'));
    await settle(tester);

    await tester.scrollUntilVisible(
        find.text('Hinweis zu dieser Art melden'), 300,
        // Das ÄUSSERE, senkrechte Scrollable: Seit der Porträtreihe
        // (1.170.0) steckt ein waagerechtes darin, und das ist sein
        // Nachfahre — `descendant` trifft sonst beide.
        scrollable: find
            .descendant(
                of: find.byKey(kSpeciesDetailListKey),
                matching: find.byType(Scrollable))
            .first);
    await settle(tester, frames: 4);
    await tester.tap(find.text('Hinweis zu dieser Art melden'));
    await settle(tester);

    expect(find.text('Hinweis zu „Steinpilz"'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField).last, 'Das Netz ist auch unten weiß.');
    await tester.tap(find.text('Senden'));
    await settle(tester);

    final report = backend.feedback.single;
    expect(report['type'], 'bug', reason: 'ein Datenfehler ist ein Bug');
    expect(report['message'],
        'Hinweis zur Art „Steinpilz": Das Netz ist auch unten weiß.');
    await drainSnackbars(tester);
  });

  testWidgets('Abbrechen und leerer Text senden nichts', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openTab(tester, 'Pilze');
    await tester.enterText(
        find.widgetWithText(TextField, 'Art suchen'), 'Judasohr');
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Judasohr'));
    await settle(tester);
    await tester.scrollUntilVisible(
        find.text('Hinweis zu dieser Art melden'), 300,
        // Das ÄUSSERE, senkrechte Scrollable: Seit der Porträtreihe
        // (1.170.0) steckt ein waagerechtes darin, und das ist sein
        // Nachfahre — `descendant` trifft sonst beide.
        scrollable: find
            .descendant(
                of: find.byKey(kSpeciesDetailListKey),
                matching: find.byType(Scrollable))
            .first);
    await settle(tester, frames: 4);

    await tester.tap(find.text('Hinweis zu dieser Art melden'));
    await settle(tester);
    await tester.tap(find.text('Senden'));
    await settle(tester);
    expect(backend.feedback, isEmpty, reason: 'leer heißt nichts');

    await tester.tap(find.text('Hinweis zu dieser Art melden'));
    await settle(tester);
    await tester.tap(find.text('Abbrechen'));
    await settle(tester);
    expect(backend.feedback, isEmpty);
  });
}
