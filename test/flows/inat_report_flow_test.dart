// Funde an iNaturalist melden (#553) — durch die echte Oberfläche.
//
// Die Auflage des Betreibers ist die eigentliche Prüfung: optional, und
// wer es nicht benutzt, merkt nichts davon. Deshalb stehen die Fälle, in
// denen NICHTS passieren darf, vorn — kein Eintrag ohne Application ID,
// kein Schalter ohne Konto, kein Abruf ohne Einschalten, kein Buddy-Foto
// ohne Haken.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/widgets/photo_attachment.dart';
import 'package:pilzbuddy/data/find_report_repository.dart';
import 'package:pilzbuddy/data/inat_api.dart';
import 'package:pilzbuddy/data/outbox.dart';
import 'package:pilzbuddy/features/inat/inat_profile_tile.dart';
import 'package:pilzbuddy/features/inat/inat_report_flow.dart';
import 'package:pilzbuddy/features/inat/inat_report_section.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_inat.dart';
import '../fakes/fake_outbox.dart';
import '../fakes/map_ui.dart';
import '../fakes/photo_fixtures.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 1));
    return (backend, me);
  }

  Future<void> openAddSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester);
    await tester.tap(find.text('Fund eintragen'));
    await settle(tester);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester, frames: 12);
  }

  Future<void> switchOn(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(kInatReportSwitchKey));
    await tester.tap(find.byKey(kInatReportSwitchKey));
    await settle(tester);
  }

  /// Ein Foto im iNaturalist-Abschnitt — nicht das für Buddys.
  Future<void> attachInatPhoto(WidgetTester tester) async {
    final button = find.descendant(
        of: find.byKey(kInatReportSectionKey),
        matching: find.byKey(kAttachPhotoKey));
    await tester.ensureVisible(button.first);
    await tester.tap(button.first);
    await settle(tester, frames: 12);
  }

  Future<void> openProfileTile(WidgetTester tester) async {
    await openTab(tester, 'Profil');
    await tester.scrollUntilVisible(find.byKey(kInatProfileTileKey), 300);
  }

  testWidgets('ohne Application ID: kein Eintrag im Profil, kein Schalter '
      'im Blatt', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, photoPicker: FakePhotoPicker(dirtyJpeg()));

    await openAddSheet(tester);
    expect(find.byKey(kInatReportSwitchKey), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    await openTab(tester, 'Profil');
    // Der ANKER ist der Eintrag DANACH: Eine Liste baut nur, was im Bild
    // ist — bis zum Fundfoto-Schalter gescrollt, läge die Stelle des
    // iNaturalist-Eintrags womöglich noch darunter, und `findsNothing`
    // wäre grün, egal was dort stünde. In der Gegenprobe genau so.
    await tester.scrollUntilVisible(
        find.text('Pilzwetter-Ampel (experimentell)'), 300);
    expect(find.text('Fundfotos von Buddys anzeigen'), findsOneWidget);
    expect(find.byKey(kInatProfileTileKey), findsNothing,
        reason: 'zwischen den beiden Schaltern stünde er');
  });

  testWidgets('ohne verbundenes Konto: Eintrag im Profil ja, Schalter im '
      'Blatt nein', (tester) async {
    final (backend, _) = loggedInBackend();
    final inat = FakeInat();
    await pumpApp(tester, backend,
        inat: inat, photoPicker: FakePhotoPicker(dirtyJpeg()));

    await openAddSheet(tester);
    expect(find.byKey(kInatReportSwitchKey), findsNothing,
        reason: 'der Alltag bleibt genau so einfach wie vorher');
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    await openProfileTile(tester);
    expect(find.text('Funde an GBIF melden'), findsOneWidget);
    expect(inat.server.requests, isEmpty,
        reason: 'vor dem Verbinden geht nichts an iNaturalist');
  });

  testWidgets('verbinden: erst der Dialog, dann der Tab — Lizenz und Name '
      'kommen an', (tester) async {
    final (backend, _) = loggedInBackend();
    final inat = FakeInat();
    await pumpApp(tester, backend, inat: inat);

    await openProfileTile(tester);
    await tester.tap(find.byKey(kInatProfileTileKey));
    await settle(tester);
    expect(find.text(kInatConsentText), findsOneWidget);
    expect(inat.authorizeUrls, isEmpty,
        reason: 'der Tab öffnet erst NACH der Erklärung');
    await tester.tap(find.byKey(inatLicenseKey(InatLicense.ccBy)));
    await settle(tester);
    await tester.tap(find.byKey(kInatConnectKey));
    await settle(tester, frames: 12);

    final url = inat.authorizeUrls.single;
    expect(url.queryParameters['code_challenge_method'], 'S256');
    expect(url.queryParameters['redirect_uri'], kInatRedirectUri);
    expect(inat.store.account?.login, FakeInatServer.login);
    expect(inat.store.account?.license, InatLicense.ccBy);
    expect(find.text('iNaturalist: verbunden als ${FakeInatServer.login}'),
        findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('Tab ohne Bestätigung geschlossen: nichts verbunden, keine '
      'Fehlermeldung', (tester) async {
    final (backend, _) = loggedInBackend();
    final inat = FakeInat()..cancel = true;
    await pumpApp(tester, backend, inat: inat);

    await openProfileTile(tester);
    await tester.tap(find.byKey(kInatProfileTileKey));
    await settle(tester);
    await tester.tap(find.byKey(kInatConnectKey));
    await settle(tester, frames: 12);

    expect(inat.store.account, isNull);
    expect(find.byType(SnackBar), findsNothing,
        reason: 'Schließen ist eine Entscheidung, kein Fehler');
    expect(find.text('Funde an GBIF melden'), findsOneWidget);
  });

  testWidgets('verbunden, aber Schalter aus: Speichern geht wie vorher, '
      'nichts geht an iNaturalist', (tester) async {
    final (backend, _) = loggedInBackend();
    final inat = FakeInat(account: FakeInat.linkedAccount());
    await pumpApp(tester, backend,
        inat: inat, photoPicker: FakePhotoPicker(dirtyJpeg()));

    await openAddSheet(tester);
    final toggle =
        tester.widget<SwitchListTile>(find.byKey(kInatReportSwitchKey));
    expect(toggle.value, isFalse, reason: 'Vorgabe AUS');
    expect(find.byKey(kInatObscuredKey), findsNothing,
        reason: 'hinter dem Schalter liegt alles andere');
    await save(tester);

    expect(backend.spots.single.finds, hasLength(2));
    expect(inat.server.requests, isEmpty);
    expect(backend.findReports, isEmpty);
    await drainSnackbars(tester);
  });

  testWidgets('melden: ohne Foto bleibt das Blatt offen, mit Foto geht '
      'die Beobachtung hinaus — ohne Notiz', (tester) async {
    final (backend, _) = loggedInBackend();
    final inat = FakeInat(account: FakeInat.linkedAccount());
    await pumpApp(tester, backend,
        inat: inat, photoPicker: FakePhotoPicker(dirtyJpeg()));

    await openAddSheet(tester);
    await switchOn(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Notiz (optional)'),
        'hinter Müllers Scheune');
    await save(tester);
    expect(find.byKey(kInatNoPhotoKey), findsOneWidget);
    expect(backend.spots.single.finds, hasLength(1),
        reason: 'nicht still ohne die gewählte Meldung speichern');

    await attachInatPhoto(tester);
    await tester.ensureVisible(find.byKey(inatTreeKey('Buche')));
    await tester.tap(find.byKey(inatTreeKey('Buche')));
    await settle(tester);
    await save(tester);

    final fresh = backend.spots.single.finds.last;
    final row = backend.findReports[fresh.id]!.report;
    expect(row.status, FindReportStatus.reported);
    final obs = inat.server.observations.single;
    expect(obs.uuid, row.remoteUuid);
    expect(obs.fields['taxon_id'], 48701);
    expect(obs.fields['geoprivacy'], 'obscured', reason: 'Vorgabe');
    expect(obs.fields['license_code'], 'cc-by-nc');
    expect(obs.fields['positional_accuracy'], 50,
        reason: 'am Spot, nicht gemessen');
    expect(obs.fields['description'], contains('Buche'));
    expect(obs.fields.toString(), isNot(contains('Müller')),
        reason: 'die Notiz bleibt bei uns');
    expect(obs.fields.toString(), isNot(contains('Buchenhang')),
        reason: 'der Name des Spots auch');
    expect(obs.photos, hasLength(1));
    expect(find.text(kInatReportedMessage), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('das Buddy-Foto geht nur mit Haken mit', (tester) async {
    final (backend, _) = loggedInBackend();
    final inat = FakeInat(account: FakeInat.linkedAccount());
    await pumpApp(tester, backend,
        inat: inat, photoPicker: FakePhotoPicker(dirtyJpeg()));

    Future<void> reportWithBuddyPhoto({required bool tick}) async {
      // Nach dem ersten Speichern steht das Spot-Blatt noch offen.
      if (find.text('Fund eintragen').evaluate().isEmpty) {
        await openAddSheet(tester);
      } else {
        await tester.ensureVisible(find.text('Fund eintragen'));
        await tester.tap(find.text('Fund eintragen'));
        await settle(tester);
      }
      final buddyButton = find.text('Foto für Buddys teilen');
      await tester.ensureVisible(buddyButton);
      await tester.tap(buddyButton);
      await settle(tester, frames: 12);
      await switchOn(tester);
      final checkbox =
          tester.widget<CheckboxListTile>(find.byKey(kInatUseBuddyPhotoKey));
      expect(checkbox.value, isFalse, reason: 'nie vorausgewählt');
      if (tick) {
        await tester.tap(find.byKey(kInatUseBuddyPhotoKey));
        await settle(tester);
      }
      await attachInatPhoto(tester);
      await save(tester);
      await drainSnackbars(tester);
    }

    await reportWithBuddyPhoto(tick: false);
    expect(inat.server.observations.last.photos, hasLength(1));
    await reportWithBuddyPhoto(tick: true);
    expect(inat.server.observations.last.photos, hasLength(2));
    expect(backend.findPhotos, hasLength(2),
        reason: 'für die Buddys wurde es beide Male geteilt');
  });

  testWidgets('Freitext-Art: der Schalter ist aus und sagt warum',
      (tester) async {
    final (backend, _) = loggedInBackend();
    final inat = FakeInat(account: FakeInat.linkedAccount());
    await pumpApp(tester, backend,
        inat: inat, photoPicker: FakePhotoPicker(dirtyJpeg()));

    await openAddSheet(tester);
    await switchOn(tester);
    expect(find.byKey(kInatObscuredKey), findsOneWidget);
    await tester.enterText(speciesField(), 'Omas Wiesenpilz');
    await settle(tester);
    final toggle =
        tester.widget<SwitchListTile>(find.byKey(kInatReportSwitchKey));
    expect(toggle.onChanged, isNull);
    expect(toggle.value, isFalse);
    expect(find.textContaining('Freitext-Arten kennt'), findsOneWidget);
    await save(tester);
    expect(inat.server.requests, isEmpty);
    await drainSnackbars(tester);
  });

  testWidgets('scheitern die Fotos, steht der Fund — die Meldung sagt '
      'beides', (tester) async {
    final (backend, _) = loggedInBackend();
    final inat = FakeInat(account: FakeInat.linkedAccount());
    inat.server.photosFail = true;
    await pumpApp(tester, backend,
        inat: inat, photoPicker: FakePhotoPicker(dirtyJpeg()));

    await openAddSheet(tester);
    await switchOn(tester);
    await attachInatPhoto(tester);
    await save(tester);

    final fresh = backend.spots.single.finds.last;
    expect(backend.findReports[fresh.id]!.report.status,
        FindReportStatus.sending);
    expect(find.textContaining('Fund eingetragen, nicht gemeldet'),
        findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('widerrufener Zugang: Hinweis auf neu verbinden, keine Zeile',
      (tester) async {
    final (backend, _) = loggedInBackend();
    final inat = FakeInat(account: FakeInat.linkedAccount());
    inat.server.revoked = true;
    await pumpApp(tester, backend,
        inat: inat, photoPicker: FakePhotoPicker(dirtyJpeg()));

    await openAddSheet(tester);
    await switchOn(tester);
    await attachInatPhoto(tester);
    await save(tester);

    expect(backend.spots.single.finds, hasLength(2));
    expect(backend.findReports, isEmpty);
    expect(find.textContaining('neu verbinden'), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('ohne Empfang: Fund in den Korb, keine Meldung — und kein '
      'dritter Korb-Weg', (tester) async {
    final (backend, _) = loggedInBackend();
    final inat = FakeInat(account: FakeInat.linkedAccount());
    final outbox = FakeOutbox();
    await pumpApp(tester, backend,
        inat: inat,
        outbox: outbox,
        photoPicker: FakePhotoPicker(dirtyJpeg()));

    await openAddSheet(tester);
    await switchOn(tester);
    await attachInatPhoto(tester);
    backend.offline = true;
    await save(tester);

    expect(outbox.jobs.single, isA<NewFindsJob>());
    expect(inat.server.requests, isEmpty);
    expect(find.text(kInatQueuedMessage), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('trennen: der Zugang ist weg, der Schalter auch',
      (tester) async {
    final (backend, _) = loggedInBackend();
    final inat = FakeInat(account: FakeInat.linkedAccount());
    await pumpApp(tester, backend,
        inat: inat, photoPicker: FakePhotoPicker(dirtyJpeg()));

    await openProfileTile(tester);
    await tester.tap(find.byKey(kInatProfileTileKey));
    await settle(tester);
    await tester.tap(find.byKey(kInatDisconnectKey));
    await settle(tester);
    expect(inat.store.account, isNull);
    expect(find.text('Funde an GBIF melden'), findsOneWidget);

    await openTab(tester, 'Karte');
    await openAddSheet(tester);
    expect(find.byKey(kInatReportSwitchKey), findsNothing);
  });
}
