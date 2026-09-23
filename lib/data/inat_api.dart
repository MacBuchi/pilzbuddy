// Funde an iNaturalist melden (#553) — der Draht nach draußen.
//
// **Warum iNaturalist und nicht GBIF direkt:** GBIF nimmt Datensätze nur
// von Organisationen an, nicht von Einzelpersonen oder kleinen Apps.
// iNaturalist veröffentlicht bestätigte Beobachtungen („Research Grade")
// mit freier Lizenz wöchentlich an GBIF — und bringt die Prüfung durch
// die Community mit, die wir sonst nicht hätten.
//
// **Jeder Nutzer meldet mit SEINEM Konto.** Ein Sammelkonto „PilzBuddy"
// hat iNaturalist bei einer anderen App (QuestaGame) als Verstoß gegen
// die Nutzungsbedingungen gesperrt: Rückfragen der Bestimmer erreichten
// niemanden. Und sein Zugang läge auf einem Server, den wir betreiben
// müssten. Die Entscheidungen stehen vollständig im Text von #553.
//
// **Öffentlicher Client mit PKCE, kein Geheimnis in der App.** Was in
// der APK steht, ist öffentlich; der Verifier entsteht je Anmeldung
// neu und verlässt das Gerät erst beim Einlösen des Codes. Die
// Application ID ist KEIN Geheimnis.
//
// Kein Riverpod, keine Widgets: Die Klasse nimmt einen `http.Client`,
// und die Tests reichen einen `MockClient` hinein (kein Netz in Tests).
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// Die Application ID der PilzBuddy-App bei iNaturalist.
///
/// **Leer, bis der Betreiber die App registriert hat** (Checkliste in
/// #553 — frühestens ab 2026-11-24). Solange sie leer ist, zeigt die App
/// den ganzen Weg nirgends an (`inatAvailableProvider`): Ein Knopf, der
/// in eine Fehlermeldung führt, wäre schlimmer als keiner.
const kInatAppId = '';

/// Schema und Host der Rückleitung. Stehen genau so im Manifest
/// (CallbackActivity) und bei iNaturalist als Redirect-URI —
/// `test/android_manifest_test.dart` hält Dart und Manifest zusammen,
/// die Registrierung hält der Wortlaut in #553 fest.
const kInatCallbackScheme = 'de.mcbuchi.pilzbuddy';
const kInatRedirectUri = '$kInatCallbackScheme://inat';

/// Die beiden Ziele — AUSGESCHRIEBEN, nicht als bloßer Hostname:
/// `test/privacy_policy_test.dart` sucht nach `https://…` im Quelltext,
/// und ein `Uri.https(host, …)` sähe er nicht. Ein Netzziel, das der
/// Wächter übersieht, fehlt am Ende in der Datenschutzerklärung.
const kInatWebBase = 'https://www.inaturalist.org';
const kInatApiBase = 'https://api.inaturalist.org';

Uri _inat(String base, String path, [Map<String, String>? query]) {
  final uri = Uri.parse('$base$path');
  return query == null ? uri : uri.replace(queryParameters: query);
}

/// Die drei Lizenzen, mit denen iNaturalist eine Beobachtung an GBIF
/// weitergibt. CC BY-SA, CC BY-ND und „alle Rechte vorbehalten" kommen
/// dort nie an — sie stehen deshalb gar nicht erst zur Wahl.
enum InatLicense {
  ccByNc('cc-by-nc', 'CC BY-NC', 'Namensnennung, nicht kommerziell'),
  ccBy('cc-by', 'CC BY', 'Namensnennung'),
  cc0('cc0', 'CC0', 'gemeinfrei, ohne Bedingungen');

  const InatLicense(this.code, this.label, this.meaning);

  /// So erwartet iNaturalist den Wert (`license_code`).
  final String code;
  final String label;
  final String meaning;

  static InatLicense fromCode(String? code) => values
      .firstWhere((l) => l.code == code, orElse: () => InatLicense.ccByNc);
}

/// Ein Fehler auf dem Weg zu iNaturalist — mit einem Satz, der dem
/// Nutzer gezeigt werden darf.
class InatException implements Exception {
  const InatException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// Der Zugang gilt nicht mehr — widerrufen auf der iNaturalist-Seite
  /// oder nie gültig gewesen. Dann hilft nur neu verbinden, und das
  /// soll die Meldung sagen, statt „versuch es später".
  bool get needsRelink => statusCode == 401;

  @override
  String toString() => message;
}

/// Was eine Anmeldung braucht: der Verifier bleibt auf dem Gerät, die
/// Challenge geht in die Adresse, `state` schützt gegen eine
/// untergeschobene Rückleitung.
typedef InatPkce = ({String verifier, String challenge, String state});

/// Ein frisches PKCE-Paar (RFC 7636, S256).
InatPkce newInatPkce([Random? random]) {
  final rnd = random ?? Random.secure();
  String token(int bytes) => base64UrlEncode(
          List<int>.generate(bytes, (_) => rnd.nextInt(256)))
      .replaceAll('=', '');
  final verifier = token(48); // 64 Zeichen, erlaubt sind 43–128
  return (
    verifier: verifier,
    challenge: inatChallengeFor(verifier),
    state: token(16),
  );
}

/// `BASE64URL(SHA256(verifier))` ohne Auffüllung — die Challenge zu
/// einem Verifier. Öffentlich, weil der Test sie gegen das Beispiel aus
/// RFC 7636 (Anhang B) prüft.
String inatChallengeFor(String verifier) =>
    base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');

/// Die Adresse, die im Custom Tab geöffnet wird.
Uri inatAuthorizeUrl({required String appId, required InatPkce pkce}) =>
    _inat(kInatWebBase, '/oauth/authorize', {
      'client_id': appId,
      'redirect_uri': kInatRedirectUri,
      'response_type': 'code',
      'code_challenge': pkce.challenge,
      'code_challenge_method': 'S256',
      'state': pkce.state,
    });

/// Holt den Code aus der Rückleitung — oder sagt, warum es keinen gibt.
///
/// Ein fremdes `state` wird abgelehnt: Die Rückleitungs-Aktivität ist
/// exportiert, jeder kann eine Adresse mit unserem Schema aufrufen.
String inatCodeFromCallback(Uri callback, {required String state}) {
  final params = callback.queryParameters;
  if (params['error'] == 'access_denied') {
    throw const InatException('Die Verbindung wurde bei iNaturalist '
        'abgelehnt.');
  }
  if (params['state'] != state) {
    throw const InatException('Die Antwort von iNaturalist passte nicht '
        'zu dieser Anmeldung. Bitte noch einmal verbinden.');
  }
  final code = params['code'];
  if (code == null || code.isEmpty) {
    throw const InatException('iNaturalist hat keinen Anmeldecode '
        'zurückgegeben. Bitte noch einmal verbinden.');
  }
  return code;
}

/// Eine Beobachtung, wie sie hinausgeht.
///
/// **Was NICHT darin steht:** der Name des Spots, Buddys, die Notiz.
/// Die Notiz ist für den Nutzer geschrieben, nicht für die
/// Öffentlichkeit; ein Satz wie „hinter Müllers Scheune" gehört nicht
/// in einen weltweit gespiegelten Datensatz.
class InatObservation {
  const InatObservation({
    required this.uuid,
    required this.taxonId,
    required this.observedOn,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.obscured,
    required this.license,
    this.description,
  });

  /// Unsere Kennung für DIESE Meldung — iNaturalist übernimmt sie. Ein
  /// Wiederholversuch mit derselben uuid legt keine zweite Beobachtung
  /// an; deshalb steht sie in `find_reports`, bevor gesendet wird.
  final String uuid;
  final int taxonId;
  final DateTime observedOn;
  final double lat;
  final double lng;
  final int accuracyM;
  final bool obscured;
  final InatLicense license;
  final String? description;

  Map<String, dynamic> toJson() => {
        'observation': {
          'uuid': uuid,
          'taxon_id': taxonId,
          'observed_on_string': DateFormat('yyyy-MM-dd').format(observedOn),
          'latitude': lat,
          'longitude': lng,
          'positional_accuracy': accuracyM,
          'geoprivacy': obscured ? 'obscured' : 'open',
          'license_code': license.code,
          if (description != null) 'description': description,
        },
      };
}

class InatApi {
  InatApi(this._http, {required this.appId});

  final http.Client _http;
  final String appId;

  static const _json = {'Accept': 'application/json'};

  /// Löst den Code gegen den Zugang ein. Der Zugang läuft nicht ab
  /// (iNaturalist setzt keine Frist) — er gilt, bis er widerrufen wird.
  Future<String> exchangeCode(String code, String verifier) async {
    final response = await _http.post(
      _inat(kInatWebBase, '/oauth/token'),
      headers: _json,
      body: {
        'client_id': appId,
        'code': code,
        'redirect_uri': kInatRedirectUri,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      },
    );
    final token = _decode(response, 'Anmeldung')['access_token'];
    if (token is! String || token.isEmpty) {
      throw const InatException('iNaturalist hat keinen Zugang ausgestellt.');
    }
    return token;
  }

  /// Die API v1 nimmt keinen OAuth-Zugang, sondern ein JWT, das 24
  /// Stunden gilt. Es wird je Meldung frisch geholt statt gespeichert —
  /// ein Aufruf mehr, dafür nie ein abgelaufenes.
  Future<String> apiToken(String accessToken) async {
    final response = await _http.get(
      _inat(kInatWebBase, '/users/api_token'),
      headers: {..._json, 'Authorization': 'Bearer $accessToken'},
    );
    final token = _decode(response, 'Anmeldung')['api_token'];
    if (token is! String || token.isEmpty) {
      throw const InatException('iNaturalist hat die Anmeldung nicht '
          'bestätigt. Bitte neu verbinden.', statusCode: 401);
    }
    return token;
  }

  /// Der Benutzername — für „Verbunden als …" im Profil.
  Future<String> login(String jwt) async {
    final response = await _http.get(
      _inat(kInatApiBase, '/v1/users/me'),
      headers: {..._json, 'Authorization': jwt},
    );
    final results = _decode(response, 'Konto')['results'];
    final login = results is List && results.isNotEmpty
        ? (results.first as Map<String, dynamic>)['login']
        : null;
    if (login is! String) {
      throw const InatException('iNaturalist hat das Konto nicht genannt.');
    }
    return login;
  }

  /// Die Taxon-id zu einem wissenschaftlichen Namen — `null`, wenn
  /// iNaturalist ihn nicht kennt.
  ///
  /// **Nur der exakte Name zählt.** Die Suche liefert Treffer nach
  /// Ähnlichkeit, und „Boletus edulis" findet auch „Boletus
  /// edulis var. …"; eine Beobachtung unter dem falschen Taxon wäre
  /// genau der Fehler, den die Prüfung dort erst mühsam korrigieren muss.
  Future<int?> taxonId(String scientificName) async {
    final response = await _http.get(
      _inat(kInatApiBase, '/v1/taxa', {
        'q': scientificName,
        'is_active': 'true',
        'per_page': '30',
      }),
      headers: _json,
    );
    final results = _decode(response, 'Artensuche')['results'];
    if (results is! List) return null;
    final wanted = scientificName.trim().toLowerCase();
    for (final raw in results) {
      final taxon = raw as Map<String, dynamic>;
      if ((taxon['name'] as String?)?.toLowerCase() == wanted) {
        return taxon['id'] as int?;
      }
    }
    return null;
  }

  /// Legt die Beobachtung an und gibt ihre id zurück.
  Future<int> createObservation(String jwt, InatObservation observation) async {
    final response = await _http.post(
      _inat(kInatApiBase, '/v1/observations'),
      headers: {
        ..._json,
        'Content-Type': 'application/json',
        'Authorization': jwt,
      },
      body: jsonEncode(observation.toJson()),
    );
    final id = _decode(response, 'Beobachtung')['id'];
    if (id is! int) {
      throw const InatException('iNaturalist hat die Beobachtung nicht '
          'bestätigt.');
    }
    return id;
  }

  /// Hängt ein Foto an. Es kommt aus `preparePhoto` — ohne Aufnahmedaten;
  /// der Ort reist als Feld der Beobachtung, nicht im Bild.
  Future<void> addPhoto(String jwt, int observationId, Uint8List jpeg) async {
    final request = http.MultipartRequest(
        'POST', _inat(kInatApiBase, '/v1/observation_photos'))
      ..headers.addAll({..._json, 'Authorization': jwt})
      ..fields['observation_photo[observation_id]'] = '$observationId'
      ..files.add(http.MultipartFile.fromBytes('file', jpeg,
          filename: 'pilzbuddy.jpg'));
    final response = await http.Response.fromStream(await _http.send(request));
    _decode(response, 'Foto');
  }

  Map<String, dynamic> _decode(http.Response response, String step) {
    final status = response.statusCode;
    if (status == 401 || status == 403) {
      throw const InatException(
          'iNaturalist hat den Zugang abgelehnt. Bitte im Profil neu '
          'verbinden.',
          statusCode: 401);
    }
    if (status == 429) {
      throw InatException(
          'iNaturalist bittet um eine Pause. Bitte später noch einmal.',
          statusCode: status);
    }
    if (status < 200 || status >= 300) {
      throw InatException('iNaturalist hat mit Fehler $status geantwortet '
          '($step).', statusCode: status);
    }
    try {
      final body = jsonDecode(response.body);
      return body is Map<String, dynamic> ? body : const {};
    } on FormatException {
      throw InatException('Die Antwort von iNaturalist war nicht lesbar '
          '($step).', statusCode: status);
    }
  }
}
