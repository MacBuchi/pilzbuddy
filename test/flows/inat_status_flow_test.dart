// Stand am Fund und nachträglich melden (#553 Stufe 2) — durch die
// echte Oberfläche.
//
// Die Auflage bleibt dieselbe wie in Stufe 1: Wer nie verbindet, sieht
// an keinem Fund etwas. Dazu zwei neue teure Fälle — ein Abgleich, der
// je Fund einzeln fragt (oder bei jedem Öffnen), und ein zweiter
// Versuch, der eine zweite Beobachtung anlegt.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/widgets/photo_attachment.dart';
import 'package:pilzbuddy/data/find_report_repository.dart';
import 'package:pilzbuddy/features/inat/inat_find_status.dart';
import 'package:pilzbuddy/features/inat/inat_report_section.dart';
import 'package:pilzbuddy/features/inat/inat_report_sheet.dart';
import 'package:pilzbuddy/features/spots/widgets/find_photo_strip.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_inat.dart';
import '../fakes/photo_fixtures.dart';
import '../fakes/test_app.dart';

void main() {
  late FakeBackend backend;
  late String spotId;
  late String steinpilz;

  setUp(() {
    backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    spotId = backend.addSpot(
        ownerId: me.id,
        name: 'Buchenhang',
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 1));
    steinpilz = backend.spots.single.finds.single.id;
  });

  /// Eine Meldung von früher, wie sie in `find_reports` steht.
  void seedReport(String findId,
      {int? remoteId,
      FindReportStatus status = FindReportStatus.reported,
      int? gbifId}) {
    backend.findReports[findId] = (
      userId: backend.currentUserId!,
      report: FindReport(
          findId: findId,
          remoteUuid: 'uuid-$findId',
          remoteId: remoteId,
          status: status,
          gbifId: gbifId),
    );
  }

  Future<void> openSpot(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Buchenhang'));
    await settle(tester, frames: 12);
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
  }

  int gradeRequests(FakeInat inat) => inat.server.requests
      .where((r) => r.method == 'GET' && r.url.path == '/v1/observations')
      .length;

  testWidgets('ohne Konto und ohne Meldung: an keinem Fund etwas Neues',
      (tester) async {
    final inat = FakeInat();
    await pumpApp(tester, backend, inat: inat);
    await openSpot(tester);

    // Anker: die Kamera derselben Zeile ist da — die Zeile ist gebaut.
    expect(find.byKey(shareFindPhotoKey(steinpilz)), findsOneWidget);
    expect(find.byKey(inatFindButtonKey(steinpilz)), findsNothing);
    expect(find.textContaining('iNaturalist'), findsNothing);
    expect(inat.server.requests, isEmpty);
  });

  testWidgets('der Stand kommt mit EINER Abfrage für alle Funde — und nur '
      'einmal je Sitzung', (tester) async {
    final second = backend.addFindRow(spotId,
        species: 'Pfifferling',
        foundOn: DateTime(2026, 9, 2),
        authorId: backend.currentUserId);
    final third = backend.addFindRow(spotId,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 3),
        authorId: backend.currentUserId);
    final inat = FakeInat(account: FakeInat.linkedAccount());
    seedReport(steinpilz, remoteId: 501);
    seedReport(second, remoteId: 502);
    seedReport(third, remoteId: 503);
    inat.server
      ..observations.addAll([
        for (final id in [501, 502, 503])
          (id: id, uuid: 'u$id', fields: <String, dynamic>{}, photos: <List<int>>[]),
      ])
      ..grades[501] = 'research'
      ..grades[502] = 'research'
      ..gbif[502] = 777
      ..deleted.add(503);
    await pumpApp(tester, backend, inat: inat);
    await openSpot(tester);

    expect(gradeRequests(inat), 1, reason: 'eine Liste, nicht je Fund');
    expect(find.textContaining('iNaturalist: bestätigt — geht an GBIF'),
        findsOneWidget);
    expect(find.textContaining('bei GBIF'), findsOneWidget);
    expect(find.textContaining('iNaturalist: gelöscht'), findsOneWidget);
    expect(backend.findReports[steinpilz]!.report.status,
        FindReportStatus.research);
    expect(backend.findReports[second]!.report.gbifId, 777);
    expect(backend.findReports[third]!.report.status,
        FindReportStatus.withdrawn);

    await closeSheet(tester);
    await openSpot(tester);
    expect(gradeRequests(inat), 1,
        reason: 'der Stand ändert sich in Tagen, nicht je Blatt');
  });

  testWidgets('angekommen und gelöscht fragt niemand mehr', (tester) async {
    final second = backend.addFindRow(spotId,
        species: 'Pfifferling',
        foundOn: DateTime(2026, 9, 2),
        authorId: backend.currentUserId);
    seedReport(steinpilz,
        remoteId: 501, status: FindReportStatus.research, gbifId: 9);
    seedReport(second, remoteId: 502, status: FindReportStatus.withdrawn);
    final inat = FakeInat(account: FakeInat.linkedAccount());
    await pumpApp(tester, backend, inat: inat);
    await openSpot(tester);

    expect(inat.server.requests, isEmpty);
    expect(find.textContaining('bei GBIF'), findsOneWidget);
  });

  testWidgets('nachträglich melden: eigenes Blatt ohne Schalter, Foto '
      'Pflicht, danach steht der Stand am Fund', (tester) async {
    final inat = FakeInat(account: FakeInat.linkedAccount());
    await pumpApp(tester, backend,
        inat: inat, photoPicker: FakePhotoPicker(dirtyJpeg()));
    await openSpot(tester);

    await tester.tap(find.byKey(inatFindButtonKey(steinpilz)));
    await settle(tester, frames: 12);
    expect(find.text('An iNaturalist melden'), findsWidgets);
    expect(find.byKey(kInatReportSwitchKey), findsNothing,
        reason: 'wer das Blatt öffnet, will melden');
    expect(find.byKey(kInatUseBuddyPhotoKey), findsNothing);

    await tester.ensureVisible(find.byKey(kInatReportSheetSendKey));
    await tester.tap(find.byKey(kInatReportSheetSendKey));
    await settle(tester);
    expect(find.byKey(kInatNoPhotoKey), findsOneWidget);
    expect(inat.server.requests, isEmpty);

    await tester.ensureVisible(find.byKey(kAttachPhotoKey).first);
    await tester.tap(find.byKey(kAttachPhotoKey).first);
    await settle(tester, frames: 12);
    await tester.ensureVisible(find.byKey(kInatReportSheetSendKey));
    await tester.tap(find.byKey(kInatReportSheetSendKey));
    await settle(tester, frames: 16);

    final obs = inat.server.observations.single;
    expect(obs.fields['observed_on_string'], '2026-09-01',
        reason: 'das Datum des FUNDES, nicht von heute');
    expect(obs.photos, hasLength(1));
    expect(backend.findReports[steinpilz]!.report.remoteId, obs.id);
    expect(find.textContaining('iNaturalist: wartet auf Bestätigung'),
        findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('halb gemeldet: vervollständigen legt KEINE zweite '
      'Beobachtung an', (tester) async {
    final inat = FakeInat(account: FakeInat.linkedAccount());
    // Der härteste Fall: Die Beobachtung steht bei iNaturalist, ihre id
    // kam aber nie in der Zeile an (Abbruch direkt nach dem Anlegen).
    // Nur die uuid verhindert jetzt die zweite.
    seedReport(steinpilz, status: FindReportStatus.sending);
    inat.server.observations.add((
      id: 501,
      uuid: 'uuid-$steinpilz',
      fields: <String, dynamic>{},
      photos: <List<int>>[],
    ));
    await pumpApp(tester, backend,
        inat: inat, photoPicker: FakePhotoPicker(dirtyJpeg()));
    await openSpot(tester);
    expect(find.textContaining('nicht vollständig gemeldet'), findsOneWidget);
    expect(gradeRequests(inat), 0,
        reason: 'sending holt nur ein neuer Versuch nach, kein Abgleich');

    await tester.tap(find.byKey(inatFindButtonKey(steinpilz)));
    await settle(tester, frames: 12);
    await tester.ensureVisible(find.byKey(kAttachPhotoKey).first);
    await tester.tap(find.byKey(kAttachPhotoKey).first);
    await settle(tester, frames: 12);
    await tester.ensureVisible(find.byKey(kInatReportSheetSendKey));
    await tester.tap(find.byKey(kInatReportSheetSendKey));
    await settle(tester, frames: 16);

    expect(inat.server.observations, hasLength(1));
    expect(inat.server.observations.single.photos, hasLength(1));
    expect(backend.findReports[steinpilz]!.report.remoteId, 501);
    expect(backend.findReports[steinpilz]!.report.status,
        isNot(FindReportStatus.sending));
    await drainSnackbars(tester);
  });

  testWidgets('keine Knöpfe an Leergang und Freitext-Art', (tester) async {
    final blank = backend.addFindRow(spotId,
        blank: true,
        foundOn: DateTime(2026, 9, 4),
        authorId: backend.currentUserId);
    final freetext = backend.addFindRow(spotId,
        species: 'Omas Wiesenpilz',
        foundOn: DateTime(2026, 9, 5),
        authorId: backend.currentUserId);
    final inat = FakeInat(account: FakeInat.linkedAccount());
    await pumpApp(tester, backend, inat: inat);
    await openSpot(tester);

    Finder button(String id) => find.byKey(inatFindButtonKey(id));
    expect(button(steinpilz), findsOneWidget, reason: 'Anker');
    expect(button(blank), findsNothing);
    expect(button(freetext), findsNothing);
  });

  testWidgets('nach dem Trennen bleibt der Stand stehen, das Melden geht',
      (tester) async {
    final second = backend.addFindRow(spotId,
        species: 'Pfifferling',
        foundOn: DateTime(2026, 9, 2),
        authorId: backend.currentUserId);
    seedReport(steinpilz, remoteId: 501);
    final inat = FakeInat();
    inat.server.observations.add(
        (id: 501, uuid: 'u', fields: <String, dynamic>{}, photos: <List<int>>[]));
    await pumpApp(tester, backend, inat: inat);
    await openSpot(tester);

    expect(find.textContaining('iNaturalist: wartet auf Bestätigung'),
        findsOneWidget, reason: 'bei iNaturalist steht sie ja weiter');
    expect(
        find.byKey(inatFindButtonKey(second)),
        findsNothing);
  });

  testWidgets('ohne Empfang gilt der gespeicherte Stand', (tester) async {
    seedReport(steinpilz, remoteId: 501, status: FindReportStatus.research);
    final inat = FakeInat(account: FakeInat.linkedAccount())
      ..server.offline = true;
    await pumpApp(tester, backend, inat: inat);
    await openSpot(tester);

    expect(find.textContaining('iNaturalist: bestätigt'), findsOneWidget);
    expect(backend.findReports[steinpilz]!.report.status,
        FindReportStatus.research);
  });
}
