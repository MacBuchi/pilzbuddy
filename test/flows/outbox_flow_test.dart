// Der Ausgangskorb (#267) im Zusammenspiel: eintragen ohne Empfang,
// sehen, dass es wartet, und es später loswerden.
//
// Der Fund entsteht hier über die echte Oberfläche (Fadenkreuz →
// Anlege-Blatt), weil genau dort entschieden wird, ob ein Netzfehler die
// Nutzerin erreicht oder der Korb übernimmt.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/outbox.dart';
import 'package:pilzbuddy/features/spots/spot_providers.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_outbox.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  /// Legt über das Anlege-Blatt einen Spot am Fadenkreuz an.
  Future<void> addSpotAtCrosshair(WidgetTester tester,
      {String species = 'Steinpilz'}) async {
    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Pilzart (optional)'), species);
    await settle(tester);
    // Das Blatt ist höher als der Testschirm — sonst geht der Tipp ins
    // Leere und der Test „besteht", ohne je etwas gespeichert zu haben.
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);
  }

  testWidgets('ohne Empfang wandert der Fund in den Korb, statt zu scheitern',
      (tester) async {
    final (backend, _) = loggedInBackend();
    final outbox = FakeOutbox();
    await pumpApp(tester, backend, outbox: outbox);
    backend.offline = true;

    await addSpotAtCrosshair(tester);

    expect(outbox.jobs, hasLength(1));
    final job = outbox.jobs.single as NewSpotJob;
    expect(job.finds.single.species, 'Steinpilz');
    expect(job.finds.single.clientId, isNotNull,
        reason: 'ohne Kennung wäre die Wiedervorlage nicht wiederholbar');
    expect(backend.spots, isEmpty, reason: 'beim Server kam nichts an');

    // Und die Nutzerin sieht es: Banner oben, wartender Marker auf der
    // Karte.
    expect(find.textContaining('1 Eintrag wartet auf Verbindung'),
        findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('mit Verbindung geht der Korb raus und verschwindet',
      (tester) async {
    final (backend, _) = loggedInBackend();
    final outbox = FakeOutbox();
    await pumpApp(tester, backend, outbox: outbox);
    backend.offline = true;
    await addSpotAtCrosshair(tester);
    await drainSnackbars(tester);

    // Wieder Empfang, Banner antippen.
    backend.offline = false;
    await tester.tap(find.textContaining('1 Eintrag wartet auf Verbindung'));
    await settle(tester);

    expect(outbox.jobs, isEmpty);
    expect(backend.spots, hasLength(1));
    expect(backend.spots.single.finds.single.species, 'Steinpilz');
    expect(backend.spots.single.clientId, isNotNull,
        reason: 'die Kennung geht mit — sie ist der Dublettenschutz');
    expect(find.textContaining('wartet auf Verbindung'), findsNothing);
    await drainSnackbars(tester);
  });

  testWidgets('eine Wiederholung legt keinen zweiten Spot an',
      (tester) async {
    // Der Fall, für den Patch 016 da ist: Der Insert war erfolgreich, die
    // Antwort ging verloren. Hier nachgestellt, indem derselbe Auftrag
    // ein zweites Mal in den Korb gelegt und erneut gesendet wird.
    final (backend, _) = loggedInBackend();
    final outbox = FakeOutbox();
    await pumpApp(tester, backend, outbox: outbox);
    backend.offline = true;
    await addSpotAtCrosshair(tester);
    final job = outbox.jobs.single;
    await drainSnackbars(tester);

    backend.offline = false;
    await tester.tap(find.textContaining('wartet auf Verbindung'));
    await settle(tester);
    expect(backend.spots, hasLength(1));

    // Derselbe Auftrag noch einmal — als hätte die App den Erfolg nie
    // gesehen. Losgeschickt wird er vom App-Start, dem zweiten Auslöser
    // der Wiedervorlage.
    await outbox.append(job, uid: backend.currentUserId!);
    await pumpApp(tester, backend, outbox: outbox);
    await settle(tester);

    expect(backend.spots, hasLength(1),
        reason: 'derselbe Auftrag darf keinen zweiten Spot erzeugen');
    expect(backend.spots.single.finds, hasLength(1),
        reason: 'und auch keinen zweiten Fund');
    await drainSnackbars(tester);
  });

  testWidgets('ein wartender Spot lässt sich verwerfen', (tester) async {
    final (backend, _) = loggedInBackend();
    final outbox = FakeOutbox();
    await pumpApp(tester, backend, outbox: outbox);
    backend.offline = true;
    await addSpotAtCrosshair(tester);
    await drainSnackbars(tester);

    // Über den Marker ins Blatt und dort verwerfen.
    await tester.tap(find.byTooltip('Pilz-Spot — wartet auf Verbindung'));
    await settle(tester);
    await tester.tap(find.byTooltip('Eintrag verwerfen'));
    await settle(tester);
    expect(find.text('Eintrag verwerfen?'), findsOneWidget);
    await tester.tap(find.text('Löschen'));
    await settle(tester);

    expect(outbox.jobs, isEmpty);
    expect(find.textContaining('wartet auf Verbindung'), findsNothing);
    await drainSnackbars(tester);
  });

  testWidgets('lässt sich der Auftrag nicht ablegen, sagt die App es',
      (tester) async {
    // Volle Platte: Der Fund ist NIRGENDS gespeichert. Ihn als
    // „gespeichert" zu melden wäre die schlimmste aller Varianten.
    final (backend, _) = loggedInBackend();
    final outbox = FakeOutbox(failOnAppend: true);
    await pumpApp(tester, backend, outbox: outbox);
    backend.offline = true;

    await addSpotAtCrosshair(tester);

    expect(outbox.jobs, isEmpty);
    expect(find.textContaining('Keine Verbindung'), findsOneWidget,
        reason: 'gemeldet wird der ursprüngliche Grund, nicht der '
            'gescheiterte Rettungsversuch');
    await drainSnackbars(tester);
  });

  testWidgets('ein Serverfehler landet NICHT im Korb', (tester) async {
    // Die Regel, die den Korb ehrlich hält: Nur fehlender Empfang führt
    // hinein. Ein abgelehnter Schreibvorgang muss sichtbar scheitern —
    // sonst sammelte der Korb still Aufträge, die nie durchgehen, und
    // niemand erführe von einem kaputten Deployment (Lehre aus #80).
    final (backend, _) = loggedInBackend();
    final outbox = FakeOutbox();
    await pumpApp(tester, backend, outbox: outbox);
    backend.rejectWrites = true;

    await addSpotAtCrosshair(tester);

    expect(outbox.jobs, isEmpty,
        reason: 'ein Serverfehler ist kein Funkloch');
    expect(backend.spots, isEmpty);
    expect(find.textContaining('nicht mehr mit dir geteilt'), findsOneWidget,
        reason: 'die Nutzerin sieht den Fehler, statt auf eine Übertragung '
            'zu warten, die nie kommt');
    await drainSnackbars(tester);
  });

  testWidgets('Abmelden fragt nach, solange etwas wartet', (tester) async {
    final (backend, _) = loggedInBackend();
    final outbox = FakeOutbox();
    await pumpApp(tester, backend, outbox: outbox);
    backend.offline = true;
    await addSpotAtCrosshair(tester);
    await drainSnackbars(tester);

    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.tap(find.byTooltip('Abmelden'));
    await settle(tester);

    expect(find.text('Noch nicht übertragen'), findsOneWidget);
    await tester.tap(find.text('Hierbleiben'));
    await settle(tester);
    expect(backend.currentUserId, isNotNull);
    expect(outbox.jobs, hasLength(1));
  });

  // Der Browser darf seinen Speicher unter Druck räumen — anders als eine
  // Datei auf Android. Weil der Korb das ORIGINAL trägt, wäre der Fund
  // dann weg, und zwar lautlos. Deshalb sagt die App es (#386).
  group('Zusicherung des Speichers', () {
    const warnung = 'Dein Browser sichert diesen Speicher nicht zu';

    testWidgets('nicht zugesichert und etwas wartet: der Streifen steht da',
        (tester) async {
      final (backend, _) = loggedInBackend();
      await pumpApp(tester, backend, outbox: FakeOutbox(), extraOverrides: [
        storageDurableProvider.overrideWith((ref) => false),
      ]);
      backend.offline = true;

      expect(find.textContaining(warnung), findsNothing,
          reason: 'Solange nichts wartet, gibt es nichts zu verlieren — '
              'ein Warnhinweis ohne Anlass verbraucht die Aufmerksamkeit, '
              'die der echte Fall braucht.');

      await addSpotAtCrosshair(tester);

      expect(find.textContaining(warnung), findsOneWidget);
      await drainSnackbars(tester);
    });

    testWidgets('zugesichert: kein Streifen, auch wenn etwas wartet',
        (tester) async {
      final (backend, _) = loggedInBackend();
      // Der Normalfall auf Android: Der Stub sagt `true`, dort erscheint
      // der Streifen nie. Ohne diese Richtung hielte der Test nur die
      // halbe Zusage.
      await pumpApp(tester, backend, outbox: FakeOutbox(), extraOverrides: [
        storageDurableProvider.overrideWith((ref) => true),
      ]);
      backend.offline = true;

      await addSpotAtCrosshair(tester);

      expect(find.textContaining('1 Eintrag wartet auf Verbindung'),
          findsOneWidget);
      expect(find.textContaining(warnung), findsNothing);
      await drainSnackbars(tester);
    });
  });

  testWidgets('ohne wartende Einträge fragt das Abmelden nichts',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);

    await tester.tap(find.text('Profil'));
    await settle(tester);
    await tester.tap(find.byTooltip('Abmelden'));
    await settle(tester);

    expect(find.text('Noch nicht übertragen'), findsNothing);
    expect(backend.currentUserId, isNull);
  });
}
