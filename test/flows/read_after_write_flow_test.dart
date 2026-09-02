// Was passiert, wenn das Schreiben klappt und nur das Neuladen danach
// scheitert (#371, aus dem Wochendigest #341).
//
// Bis 1.111.1 fiel beides in denselben `catch`: Der Spot lag auf dem
// Server, der Nutzer las „Internet verfügbar?", und die Karte zeigte ihn
// nicht — `mySpotListProvider` behält bei einem Fehler den Vorwert. Jedes
// Signal sagte „nicht gespeichert", also trug man ihn noch einmal ein.
// Mit frischer `client_id` ist das ein echter zweiter Spot; der Schutz
// aus Patch 016 greift dort nicht, denn er sichert den Wiederholversuch
// DESSELBEN Auftrags, nicht die Handeingabe.
//
// Der Fehlerfall ist mit Absicht ein 504 und keine `SocketException`:
// Nur was NICHT `looksOffline` ist, kommt überhaupt bis zum Aufrufer
// durch — bei fehlendem Empfang spränge der Zwischenspeicher ein.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  const gatewayTimeout = PostgrestException(
      message: '', code: '504', details: 'Gateway Timeout');

  /// Legt über die Oberfläche einen Spot an — derselbe Weg wie in
  /// `spot_flow_test.dart`, weil nur er die Meldung erzeugt, um die es
  /// hier geht.
  Future<void> addSpotViaUi(WidgetTester tester) async {
    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Pilzart (optional)'), 'Steinpil');
    await settle(tester, frames: 4);
    await tester.tap(find.widgetWithText(ListTile, 'Steinpilz').first);
    await settle(tester, frames: 4);
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);
  }

  testWidgets('Scheitert nur das Neuladen, bleibt der Spot gespeichert — '
      'und die App sagt das auch', (tester) async {
    final (backend, _) = loggedInBackend();
    final repo = FakeSpotRepository(backend);
    await pumpApp(tester, backend, extraOverrides: [
      spotRepositoryProvider.overrideWithValue(repo),
    ]);

    // Erst unmittelbar vor dem Speichern scharfstellen, damit der
    // Fehlschlag wirklich den Abruf NACH dem Schreiben trifft.
    repo.failNextFetch = true;
    repo.nextFetchError = gatewayTimeout;

    await addSpotViaUi(tester);

    expect(backend.spots, hasLength(1),
        reason: 'der Spot liegt — das Schreiben war nie das Problem');
    expect(find.textContaining('Spot gespeichert'), findsOneWidget);
    expect(find.textContaining('Internet'), findsNothing,
        reason: 'genau diese Meldung ließ den Nutzer den Spot ein zweites '
            'Mal eintragen — der Doppel-Spot aus #371');
    expect(find.textContaining('sichtbar, sobald die Liste wieder lädt'),
        findsOneWidget,
        reason: 'ohne den Nachsatz stünde „gespeichert" über einer Karte, '
            'auf der nichts Neues zu sehen ist');
  });

  testWidgets('Ein Schreibfehler bleibt ein Fehler', (tester) async {
    // Die Gegenrichtung, und sie ist genauso wichtig: Wer beim Aufräumen
    // ALLE Fehler schluckt, macht aus einem kaputten Deployment eine
    // stille Erfolgsmeldung — dieselbe Grenze, die `looksOffline` beim
    // Zwischenspeicher zieht (#80).
    final (backend, _) = loggedInBackend();
    backend.rejectWrites = true;
    await pumpApp(tester, backend);

    await addSpotViaUi(tester);

    expect(backend.spots, isEmpty);
    expect(find.textContaining('Spot gespeichert'), findsNothing,
        reason: 'hier ist wirklich nichts gespeichert');
  });
}
