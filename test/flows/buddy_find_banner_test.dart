// Das Buddy-Fund-Banner (#202): Die Karte sagt, wenn ein Buddy einen
// Fund eingetragen hat — auf eigenen wie auf geteilten Spots. Der
// „gesehen bis"-Marker ist gerätelokal; verglichen wird gegen die
// SERVER-Zeit der Funde (created_at), nicht gegen die Geräteuhr.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_map_view.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

/// Findet ein Banner über seinen Text, egal wie tief es eingebettet ist
/// (Muster aus offline_spots_test).
Finder bannerWith(String fragment) => find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').contains(fragment));

/// Das X im Banner mit [fragment] — über die NÄCHSTE Material-Hülle,
/// weil auch das Feedback-Banner ein Schließen-Kreuz trägt.
Finder bannerClose(String fragment) => find.descendant(
      of: find
          .ancestor(of: bannerWith(fragment), matching: find.byType(Material))
          .first,
      matching: find.byIcon(Icons.close),
    );

void main() {
  (FakeBackend, FakeUser, FakeUser) withFriend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    final lilli = backend.addUser(username: 'lilli92');
    backend.signInAs(me.id);
    backend.addFriendship(lilli.id, me.id);
    return (backend, me, lilli);
  }

  /// Marker weit in der Vergangenheit — alles Fremde zählt als neu.
  FakeSettings seenLongAgo() =>
      FakeSettings(lastFindSeenAt: DateTime.utc(2020));

  testWidgets('Buddy-Fund auf dem EIGENEN Spot bringt das Banner',
      (tester) async {
    final (backend, me, lilli) = withFriend();
    final spotId = backend.addSpot(
        ownerId: me.id, species: 'Steinpilz', foundOn: DateTime(2026, 7, 1));
    backend.addFindRow(spotId,
        species: 'Parasol',
        foundOn: DateTime(2026, 8, 1),
        createdAt: DateTime.utc(2026, 8, 1, 12),
        authorId: lilli.id);
    await pumpApp(tester, backend, settings: seenLongAgo());

    expect(bannerWith('🔔 Neuer Fund von lilli92 — antippen'), findsOneWidget);
  });

  testWidgets('Auch am geteilten Freundes-Spot — und Mehrzahl zählt',
      (tester) async {
    final (backend, me, lilli) = withFriend();
    final spotId = backend.addSpot(
        ownerId: lilli.id,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 8, 1));
    backend.addFindRow(spotId,
        species: 'Pfifferling',
        foundOn: DateTime(2026, 8, 2),
        createdAt: DateTime.utc(2026, 8, 2, 9),
        authorId: lilli.id);
    await pumpApp(tester, backend, settings: seenLongAgo());

    expect(bannerWith('🔔 2 neue Funde deiner Buddys — antippen'),
        findsOneWidget);
  });

  testWidgets('Ein Leergang des Buddys bringt kein Banner (#211)',
      (tester) async {
    // Das Banner schickt jemanden in den Wald („Neuer Fund von …").
    // Dass ein Buddy NICHTS gefunden hat, ist keine solche Nachricht —
    // sonst meldet die App jeden erfolglosen Spaziergang als Neuigkeit.
    final (backend, me, lilli) = withFriend();
    final spotId = backend.addSpot(
        ownerId: me.id, species: 'Steinpilz', foundOn: DateTime(2026, 7, 1));
    backend.addFindRow(spotId,
        foundOn: DateTime(2026, 8, 1),
        createdAt: DateTime.utc(2026, 8, 1, 12),
        authorId: lilli.id,
        blank: true);
    await pumpApp(tester, backend, settings: seenLongAgo());

    // Derselbe Aufbau mit einem echten Fund meldet sich sehr wohl — das
    // ist der erste Test in dieser Datei.
    expect(bannerWith('🔔'), findsNothing);
  });

  testWidgets('Eigene Funde zählen nie', (tester) async {
    final (backend, me, _) = withFriend();
    backend.addSpot(
        ownerId: me.id, species: 'Steinpilz', foundOn: DateTime(2026, 8, 1));
    await pumpApp(tester, backend, settings: seenLongAgo());

    expect(bannerWith('Neuer Fund'), findsNothing);
    expect(bannerWith('neue Funde'), findsNothing);
  });

  testWidgets('Ohne initialisierten Marker bleibt das Banner aus',
      (tester) async {
    // Der Erstlauf-Schutz: In echt setzt main() den Marker beim ersten
    // Start; solange er fehlt, gilt defensiv „nichts Neues" — sonst
    // schriee das Banner über den kompletten Bestand.
    final (backend, me, lilli) = withFriend();
    final spotId = backend.addSpot(
        ownerId: me.id, species: 'Steinpilz', foundOn: DateTime(2026, 7, 1));
    backend.addFindRow(spotId,
        species: 'Parasol',
        createdAt: DateTime.utc(2026, 8, 1, 12),
        authorId: lilli.id);
    await pumpApp(tester, backend); // FakeSettings-Default: Marker null

    expect(bannerWith('Neuer Fund'), findsNothing);
  });

  testWidgets('Antippen öffnet den Spot des neuesten Funds und merkt sich '
      'den Stand', (tester) async {
    final (backend, me, lilli) = withFriend();
    final spotId = backend.addSpot(
        ownerId: me.id,
        // Bewusst NICHT der Startpunkt der Karte (51.1634/10.4477): Sonst
        // wäre die Kamera-Prüfung unten leer, weil sie schon dort steht.
        lat: 50.5,
        lng: 12.5,
        name: 'Buchenhang',
        species: 'Steinpilz',
        foundOn: DateTime(2026, 7, 1));
    backend.addFindRow(spotId,
        species: 'Parasol',
        foundOn: DateTime(2026, 8, 1),
        createdAt: DateTime.utc(2026, 8, 1, 12),
        authorId: lilli.id);
    final settings = seenLongAgo();
    await pumpApp(tester, backend, settings: settings);

    await tester.tap(bannerWith('Neuer Fund von lilli92'));
    await settle(tester);

    // Das Spot-Blatt ist offen …
    expect(find.text('Buchenhang'), findsOneWidget);
    expect(find.text('Fund eintragen'), findsOneWidget);
    // … der Marker steht auf der SERVER-Zeit des neuesten Funds …
    expect(settings.lastFindSeenAt, DateTime.utc(2026, 8, 1, 12));
    // … die Karte steht darunter auf dem Spot (#345) — ein Hinweis, der
    // einen Ort nennt, aber nicht hinführt, ist eine halbe Nachricht …
    expect(
        tester.state<FakeMapViewState>(find.byType(FakeMapView)).center,
        const LatLng(50.5, 12.5));
    // … und das Banner ist weg.
    expect(bannerWith('Neuer Fund'), findsNothing);
  });

  testWidgets('Das X markiert als gesehen, ohne zu öffnen', (tester) async {
    final (backend, me, lilli) = withFriend();
    final spotId = backend.addSpot(
        ownerId: me.id, species: 'Steinpilz', foundOn: DateTime(2026, 7, 1));
    backend.addFindRow(spotId,
        species: 'Parasol',
        createdAt: DateTime.utc(2026, 8, 1, 12),
        authorId: lilli.id);
    final settings = seenLongAgo();
    await pumpApp(tester, backend, settings: settings);

    await tester.tap(bannerClose('Neuer Fund von lilli92'));
    await settle(tester);

    expect(bannerWith('Neuer Fund'), findsNothing);
    expect(find.text('Fund eintragen'), findsNothing,
        reason: 'das X öffnet kein Blatt');
    expect(settings.lastFindSeenAt, DateTime.utc(2026, 8, 1, 12));
  });
}
