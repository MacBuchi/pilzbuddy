// Der Draht zu iNaturalist (#553) — ohne Widgets, gegen den Fake-Server.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/find_report_repository.dart';
import 'package:pilzbuddy/data/inat_account.dart';
import 'package:pilzbuddy/data/inat_api.dart';
import 'package:pilzbuddy/features/inat/inat_report_section.dart';
import 'package:pilzbuddy/features/inat/inat_reporter.dart';
import 'package:pilzbuddy/features/map/forest_species.dart';
import 'package:pilzbuddy/models/find_position.dart';

import 'fakes/fake_backend.dart';
import 'fakes/fake_inat.dart';

void main() {
  group('PKCE', () {
    test('die Challenge ist die aus RFC 7636, Anhang B', () {
      // Das Beispiel aus der Norm — wer hier Padding stehen lässt oder
      // base64 statt base64url nimmt, fällt bei iNaturalist mit
      // „invalid_grant" durch, ohne dass die Meldung sagt, warum.
      expect(inatChallengeFor('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
          'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    });

    test('jede Anmeldung bekommt einen eigenen Verifier im erlaubten Maß',
        () {
      final a = newInatPkce();
      final b = newInatPkce();
      expect(a.verifier, isNot(b.verifier));
      expect(a.state, isNot(b.state));
      expect(a.verifier.length, inInclusiveRange(43, 128));
      expect(a.verifier, matches(RegExp(r'^[A-Za-z0-9\-._~]+$')));
      expect(a.challenge, inatChallengeFor(a.verifier));
    });

    test('die Adresse trägt Challenge, S256 und die Rückleitung', () {
      final pkce = newInatPkce();
      final url = inatAuthorizeUrl(appId: 'abc', pkce: pkce);
      expect(url.host, 'www.inaturalist.org');
      expect(url.path, '/oauth/authorize');
      expect(url.queryParameters, {
        'client_id': 'abc',
        'redirect_uri': 'de.mcbuchi.pilzbuddy://inat',
        'response_type': 'code',
        'code_challenge': pkce.challenge,
        'code_challenge_method': 'S256',
        'state': pkce.state,
      });
      expect(url.toString(), isNot(contains(pkce.verifier)),
          reason: 'der Verifier verlässt das Gerät erst beim Einlösen');
    });

    test('Rückleitung: fremdes state, Ablehnung und fehlender Code '
        'scheitern mit einem Satz', () {
      Uri cb(String q) => Uri.parse('de.mcbuchi.pilzbuddy://inat?$q');
      expect(inatCodeFromCallback(cb('code=c1&state=s'), state: 's'), 'c1');
      expect(() => inatCodeFromCallback(cb('code=c1&state=x'), state: 's'),
          throwsA(isA<InatException>()),
          reason: 'die Aktivität ist exportiert — jeder kann sie aufrufen');
      expect(
          () => inatCodeFromCallback(
              cb('error=access_denied&state=s'), state: 's'),
          throwsA(isA<InatException>()
              .having((e) => e.message, 'message', contains('abgelehnt'))));
      expect(() => inatCodeFromCallback(cb('state=s'), state: 's'),
          throwsA(isA<InatException>()));
    });
  });

  group('API gegen den Fake-Server', () {
    late FakeInatServer server;
    late InatApi api;
    setUp(() {
      server = FakeInatServer();
      api = InatApi(server.client, appId: 'test-app');
    });

    test('Verbinden: Code gegen Zugang, dann Name — Verifier geht mit',
        () async {
      final pkce = newInatPkce();
      final account = await connectInat(
        api: api,
        authorize: (url) async => Uri.parse(
            'de.mcbuchi.pilzbuddy://inat?code=fake-code&state=${pkce.state}'),
        license: InatLicense.ccBy,
        pkce: pkce,
      );
      expect(account.accessToken, FakeInatServer.accessToken);
      expect(account.login, FakeInatServer.login);
      expect(account.license, InatLicense.ccBy);
      expect(server.paths,
          ['/oauth/token', '/users/api_token', '/v1/users/me']);
    });

    test('nur der EXAKTE Name ist ein Treffer', () async {
      expect(await api.taxonId('Boletus edulis'), 48701,
          reason: 'die Varietät steht in der Antwort zuerst');
      expect(await api.taxonId('Lactarius deterrimus'), isNull);
    });

    test('ein widerrufener Zugang heißt „neu verbinden"', () async {
      server.revoked = true;
      await expectLater(
          api.apiToken(FakeInatServer.accessToken),
          throwsA(isA<InatException>()
              .having((e) => e.needsRelink, 'needsRelink', isTrue)
              .having((e) => e.message, 'message', contains('neu'))));
    });
  });

  group('Beobachtung', () {
    test('ohne Notiz, ohne Spot — mit Genauigkeit, Lizenz und '
        'Geoprivacy', () {
      final json = InatObservation(
        uuid: 'u-1',
        taxonId: 48701,
        observedOn: DateTime(2026, 9, 3, 17, 45),
        lat: 47.5,
        lng: 11.25,
        accuracyM: 12,
        obscured: true,
        license: InatLicense.ccByNc,
        description: inatDescription(count: 3, trees: ['Buche', 'Fichte']),
      ).toJson()['observation'] as Map<String, dynamic>;
      expect(json, {
        'uuid': 'u-1',
        'taxon_id': 48701,
        'observed_on_string': '2026-09-03',
        'latitude': 47.5,
        'longitude': 11.25,
        'positional_accuracy': 12,
        'geoprivacy': 'obscured',
        'license_code': 'cc-by-nc',
        'description':
            'Anzahl: 3\nBäume in der Nähe: Buche, Fichte\nGemeldet mit '
                'PilzBuddy.',
      });
    });

    test('Genauigkeit: gemessen wird aufgerundet, sonst 50 m', () {
      expect(inatAccuracyFor(null), kInatUnmeasuredAccuracyM);
      expect(inatAccuracyFor(const FindPosition.picked(lat: 1, lng: 2)),
          kInatUnmeasuredAccuracyM,
          reason: 'auf der Karte gewählt ist nicht gemessen');
      expect(
          inatAccuracyFor(
              const FindPosition.gps(lat: 1, lng: 2, accuracy: 12.2)),
          13);
      expect(
          inatAccuracyFor(const FindPosition.gps(lat: 1, lng: 2, accuracy: 0)),
          5,
          reason: 'eine GPS-Messung ist nie genauer als ein paar Meter');
    });

    test('nur Arten mit wissenschaftlichem Namen sind meldbar', () {
      expect(inatScientificNameFor('Steinpilz'), 'Boletus edulis');
      expect(inatScientificNameFor('Marone'), isNotNull,
          reason: 'Zweitnamen lösen sich auf die Art auf');
      expect(inatScientificNameFor('Omas Wiesenpilz'), isNull);
      expect(inatScientificNameFor(null), isNull);
    });

    test('Bäume: die Karte gibt die Vorauswahl, die Liste kennt alle', () {
      expect(
          inatTreePreset(
              (broadleaf: Broadleaf.beech, conifer: Conifer.spruce)),
          ['Buche', 'Fichte']);
      expect(inatTreePreset(null), isEmpty,
          reason: 'außerhalb Deutschlands kennt die Karte nichts');
      for (final tree in inatTreePreset(
          (broadleaf: Broadleaf.alder, conifer: Conifer.larch))) {
        expect(kInatTreeChoices, contains(tree),
            reason: 'jede Vorauswahl muss als Chip abwählbar sein');
      }
    });
  });

  group('Melden', () {
    late FakeBackend backend;
    late FakeInatServer server;
    late InatReporter reporter;
    late String findId;
    final photo = (
      full: Uint8List.fromList([1, 2, 3]),
      thumb: Uint8List.fromList([4]),
      width: 1,
      height: 1,
    );

    setUp(() {
      backend = FakeBackend();
      final me = backend.addUser(username: 'testpilz');
      backend.signInAs(me.id);
      backend.addSpot(ownerId: me.id, name: 'Hang', species: 'Steinpilz');
      findId = backend.spots.single.finds.single.id;
      server = FakeInatServer();
      reporter = InatReporter(
        api: InatApi(server.client, appId: 'test-app'),
        reports: FakeFindReportRepository(backend),
      );
    });

    Future<int> report({InatReportDraft? draft}) => reporter.report(
          account: FakeInat.linkedAccount(),
          findId: findId,
          species: 'Steinpilz',
          count: 2,
          foundOn: DateTime(2026, 9, 3),
          lat: 47.5,
          lng: 11.25,
          position: null,
          draft: draft ?? InatReportDraft(photos: [photo]),
        );

    test('Zeile vor dem Senden, uuid mit hinaus, danach „reported"',
        () async {
      final id = await report();
      final row = backend.findReports[findId]!.report;
      expect(row.remoteId, id);
      expect(row.status, FindReportStatus.reported);
      final obs = server.observations.single;
      expect(obs.uuid, row.remoteUuid);
      expect(obs.photos, hasLength(1));
    });

    test('scheitern die Fotos, bleibt „sending" MIT id — und der zweite '
        'Versuch legt keine zweite Beobachtung an', () async {
      server.photosFail = true;
      await expectLater(report(), throwsA(isA<InatException>()));
      final row = backend.findReports[findId]!.report;
      expect(row.status, FindReportStatus.sending);
      expect(row.remoteId, server.observations.single.id);

      server.photosFail = false;
      await report();
      expect(server.observations, hasLength(1));
      expect(backend.findReports[findId]!.report.status,
          FindReportStatus.reported);
    });

    test('unbekannte Art oder widerrufener Zugang: nichts wird '
        'geschrieben', () async {
      server.taxa.clear();
      await expectLater(report(), throwsA(isA<InatException>()));
      server.taxa['Boletus edulis'] = 48701;
      server.revoked = true;
      await expectLater(report(), throwsA(isA<InatException>()));
      expect(backend.findReports, isEmpty,
          reason: 'erst Art und Zugang, dann die Zeile');
      expect(server.observations, isEmpty);
    });

    test('ohne Foto wird gar nicht erst gefragt', () async {
      await expectLater(report(draft: const InatReportDraft(photos: [])),
          throwsA(isA<InatException>()));
      expect(server.requests, isEmpty);
    });

    test('nur am EIGENEN Fund — die Policy aus Patch 029', () async {
      final other = backend.addUser(username: 'fremd');
      backend.signInAs(other.id);
      await expectLater(report(), throwsA(isA<StateError>()));
      expect(backend.findReports, isEmpty);
    });
  });

  group('Abgleich', () {
    late FakeBackend backend;
    late FakeInatServer server;
    late InatReporter reporter;
    late FakeFindReportRepository reports;

    setUp(() {
      backend = FakeBackend();
      final me = backend.addUser(username: 'testpilz');
      backend.signInAs(me.id);
      final spot = backend.addSpot(ownerId: me.id, name: 'Hang');
      for (final (i, id) in [1, 2, 3, 4, 5].indexed) {
        final findId = backend.addFindRow(spot,
            species: 'Steinpilz',
            foundOn: DateTime(2026, 9, 1 + i),
            authorId: me.id);
        backend.findReports[findId] = (
          userId: me.id,
          report: FindReport(
              findId: findId,
              remoteUuid: 'u$id',
              // Auch die halbe Meldung hat schon eine id: Die Fotos
              // fehlen. Gerade DIE darf der Abgleich nicht anfassen.
              remoteId: 100 + id,
              status: id == 5
                  ? FindReportStatus.sending
                  : FindReportStatus.reported),
        );
      }
      server = FakeInatServer();
      for (final id in [101, 102, 103, 104, 105]) {
        server.observations.add(
            (id: id, uuid: 'u$id', fields: <String, dynamic>{}, photos: <List<int>>[]));
      }
      reports = FakeFindReportRepository(backend);
      reporter = InatReporter(
          api: InatApi(server.client, appId: 't'), reports: reports);
    });

    test('Stufen je Beobachtung, GBIF nur für bestätigte, sending bleibt',
        () async {
      server
        ..grades[101] = 'research'
        ..grades[102] = 'casual'
        ..gbif[101] = 555
        ..gbif[102] = 666 // darf NICHT gefragt werden — casual
        ..deleted.add(104);
      final out = {
        for (final r in await reporter.refresh(await reports.mine()))
          r.remoteId!: r,
      };
      expect(out[101]!.status, FindReportStatus.research);
      expect(out[101]!.gbifId, 555);
      expect(out[102]!.status, FindReportStatus.casual);
      expect(out[102]!.gbifId, isNull);
      expect(out[103]!.status, FindReportStatus.needsId);
      expect(out[104]!.status, FindReportStatus.withdrawn);
      expect(out[105]!.status, FindReportStatus.sending);
      expect(
          server.requests.where((r) => r.url.host == 'api.gbif.org'),
          hasLength(1));
      // Und es steht in der Datenbank, nicht nur in der Antwort.
      final stored = {
        for (final r in await reports.mine()) r.remoteId!: r,
      };
      expect(stored[101]!.gbifId, 555);
      expect(stored[104]!.status, FindReportStatus.withdrawn);
    });

    test('nichts Offenes, nichts gefragt', () async {
      for (final key in backend.findReports.keys.toList()) {
        final row = backend.findReports[key]!;
        backend.findReports[key] = (
          userId: row.userId,
          report: row.report.status == FindReportStatus.sending
              ? row.report
              : row.report.copyWith(gbifId: 1),
        );
      }
      await reporter.refresh(await reports.mine());
      expect(server.requests, isEmpty);
    });
  });

  test('ein kaputter Kontoeintrag heißt „nicht verbunden"', () {
    expect(InatAccount.fromJson({'login': 'x'}), isNull);
    expect(InatAccount.fromJson('Unsinn'), isNull);
    final roundTrip = InatAccount.fromJson(
        const InatAccount(accessToken: 't', login: 'l', license: InatLicense.cc0)
            .toJson());
    expect(roundTrip?.license, InatLicense.cc0);
  });
}
