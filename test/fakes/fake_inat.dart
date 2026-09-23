// iNaturalist im Test (#553) — ohne Netz.
//
// **Der Server ist ein `MockClient`, nicht ein Fake des `InatApi`.** So
// läuft in jedem Flow-Test der ECHTE Client mit: Adressen, Kopfzeilen,
// Formular und JSON. Ein Fake der Klasse bewiese nur, dass der Fake
// tut, was er soll.
//
// Wo der Server etwas VERHALTEN muss, spiegelt er iNaturalist, und zwar
// nachgelesen im Quelltext von iNaturalist:
//   - Anlegen mit einer uuid, die es für diesen Nutzer schon gibt, legt
//     KEINE zweite Beobachtung an (`observations_controller.rb`, #create:
//     `current_user.observations.where(uuid: …)`).
//   - Die API v1 nimmt das JWT als nackten `Authorization`-Wert, den
//     OAuth-Zugang nur `/users/api_token` (als `Bearer`).
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pilzbuddy/data/find_report_repository.dart';
import 'package:pilzbuddy/data/inat_account.dart';

import 'fake_backend.dart';

class FakeInatAccountStore implements InatAccountStore {
  FakeInatAccountStore([this.account]);

  InatAccount? account;
  int writes = 0;

  @override
  Future<InatAccount?> read() async => account;

  @override
  Future<void> write(InatAccount value) async {
    writes++;
    account = value;
  }

  @override
  Future<void> clear() async => account = null;
}

typedef FakeInatObservation = ({
  int id,
  String uuid,
  Map<String, dynamic> fields,
  List<List<int>> photos,
});

class FakeInatServer {
  FakeInatServer({Map<String, int>? taxa})
      : taxa = taxa ??
            {
              'Boletus edulis': 48701,
              'Cantharellus cibarius': 47348,
            };

  static const accessToken = 'fake-access-token';
  static const jwt = 'fake-jwt';
  static const login = 'pilzfreundin';

  /// Wissenschaftlicher Name → Taxon-id. Nur was hier steht, „kennt"
  /// iNaturalist.
  final Map<String, int> taxa;
  final observations = <FakeInatObservation>[];
  final requests = <http.BaseRequest>[];

  /// Der Zugang ist bei iNaturalist widerrufen.
  bool revoked = false;

  /// Das Hochladen der Fotos scheitert (nach dem Anlegen).
  bool photosFail = false;

  /// Kein Netz — wie ein Funkloch mitten im Melden.
  bool offline = false;

  var _nextId = 1000;

  late final http.Client client = MockClient.streaming((request, body) async {
    requests.add(request);
    final bytes = await body.toBytes();
    final response = _handle(request, bytes);
    return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(response.$2))), response.$1,
        headers: {'content-type': 'application/json'});
  });

  List<String> get paths => [for (final r in requests) r.url.path];

  (int, Object) _handle(http.BaseRequest request, List<int> body) {
    if (offline) throw http.ClientException('kein Netz (Fake)');
    final path = request.url.path;
    final auth = request.headers['Authorization'];
    switch ((request.method, request.url.host, path)) {
      case ('POST', 'www.inaturalist.org', '/oauth/token'):
        final form = Uri.splitQueryString(utf8.decode(body));
        if (form['code'] != 'fake-code' || (form['code_verifier'] ?? '').isEmpty) {
          return (400, {'error': 'invalid_grant'});
        }
        return (200, {'access_token': accessToken, 'token_type': 'Bearer'});
      case ('GET', 'www.inaturalist.org', '/users/api_token'):
        if (revoked || auth != 'Bearer $accessToken') {
          return (401, {'error': 'unauthorized'});
        }
        return (200, {'api_token': jwt});
      case ('GET', 'api.inaturalist.org', '/v1/users/me'):
        if (auth != jwt) return (401, {'error': 'unauthorized'});
        return (200, {
          'results': [
            {'id': 7, 'login': login}
          ]
        });
      case ('GET', 'api.inaturalist.org', '/v1/taxa'):
        final q = request.url.queryParameters['q'];
        return (200, {
          'results': [
            // Ein Treffer, der NICHT gemeint ist, zuerst — die Suche
            // sortiert nach Ähnlichkeit, nicht nach Gleichheit.
            {'id': 1, 'name': '$q var. aberrans'},
            if (taxa[q] case final id?) {'id': id, 'name': q},
          ]
        });
      case ('POST', 'api.inaturalist.org', '/v1/observations'):
        if (auth != jwt) return (401, {'error': 'unauthorized'});
        final fields = (jsonDecode(utf8.decode(body))
            as Map<String, dynamic>)['observation'] as Map<String, dynamic>;
        final uuid = fields['uuid'] as String;
        for (final o in observations) {
          if (o.uuid == uuid) return (200, {'id': o.id, 'uuid': uuid});
        }
        final id = _nextId++;
        observations
            .add((id: id, uuid: uuid, fields: fields, photos: <List<int>>[]));
        return (200, {'id': id, 'uuid': uuid});
      case ('POST', 'api.inaturalist.org', '/v1/observation_photos'):
        if (auth != jwt) return (401, {'error': 'unauthorized'});
        if (photosFail) return (500, {'error': 'boom'});
        final multipart = request as http.MultipartRequest;
        final id = int.parse(multipart.fields['observation_photo[observation_id]']!);
        observations
            .firstWhere((o) => o.id == id)
            .photos
            .add(body); // der ganze Multipart-Körper genügt zum Zählen
        return (200, {'id': _nextId++});
    }
    return (404, {'error': 'not found: ${request.method} $path'});
  }
}

/// Alles zusammen, wie es `pumpApp(inat: …)` braucht.
class FakeInat {
  FakeInat({InatAccount? account, FakeInatServer? server})
      : store = FakeInatAccountStore(account),
        server = server ?? FakeInatServer();

  /// Ein verbundenes Konto, wie es nach dem Verbinden aussieht.
  static InatAccount linkedAccount() => const InatAccount(
      accessToken: FakeInatServer.accessToken, login: FakeInatServer.login);

  final FakeInatAccountStore store;
  final FakeInatServer server;

  /// Was der Custom Tab geöffnet hat.
  final authorizeUrls = <Uri>[];

  /// Der Nutzer schließt den Tab, ohne zu bestätigen.
  bool cancel = false;

  Future<Uri> authorize(Uri url) async {
    authorizeUrls.add(url);
    // So meldet `flutter_web_auth_2` einen geschlossenen Tab.
    if (cancel) throw PlatformException(code: 'CANCELED');
    final state = url.queryParameters['state'];
    return Uri.parse('de.mcbuchi.pilzbuddy://inat?code=fake-code&state=$state');
  }
}

/// `find_reports` im Fake — mit den Policies aus Patch 029: nur am
/// EIGENEN Fund, nur die eigene Zeile.
class FakeFindReportRepository implements FindReportRepository {
  FakeFindReportRepository(this.backend);

  final FakeBackend backend;

  String get _uid => backend.currentUserId!;

  @override
  Future<FindReport> begin(String findId) async {
    backend.failIfOffline();
    if (backend.findReports[findId] case final row?) {
      if (row.userId == _uid) return row.report;
    }
    final find = backend.findById(findId);
    if (find == null || find.authorId != _uid) {
      throw StateError('RLS: fr_insert (nicht der eigene Fund)');
    }
    final report = FindReport(findId: findId, remoteUuid: 'uuid-$findId');
    backend.findReports[findId] = (userId: _uid, report: report);
    return report;
  }

  @override
  Future<void> setRemoteId(String findId, int remoteId) async {
    backend.failIfOffline();
    final row = _own(findId);
    backend.findReports[findId] = (
      userId: row.userId,
      report: FindReport(
          findId: findId,
          remoteUuid: row.report.remoteUuid,
          remoteId: remoteId,
          status: row.report.status),
    );
  }

  @override
  Future<void> setStatus(String findId, FindReportStatus status) async {
    backend.failIfOffline();
    final row = _own(findId);
    backend.findReports[findId] = (
      userId: row.userId,
      report: FindReport(
          findId: findId,
          remoteUuid: row.report.remoteUuid,
          remoteId: row.report.remoteId,
          status: status),
    );
  }

  FakeFindReportRow _own(String findId) {
    final row = backend.findReports[findId];
    if (row == null || row.userId != _uid) {
      throw StateError('RLS: fr_update (keine eigene Zeile)');
    }
    return row;
  }
}
