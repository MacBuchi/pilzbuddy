// Das verbundene iNaturalist-Konto (#553) — nur auf diesem Gerät.
//
// **Der Zugang geht nie nach Supabase.** Er darf im Namen des Nutzers
// Beobachtungen anlegen; in der Datenbank läge er in jedem Backup und
// wäre für uns lesbar, ohne dass wir ihn je bräuchten. Er liegt im
// Keystore (`flutter_secure_storage`) und ist vom Android-Backup
// ausgenommen (`backup_rules.xml`): Auf einem neuen Gerät verbindet man
// neu — ein Tipp.
//
// Die Lizenz liegt mit im selben Eintrag, nicht in den Einstellungen:
// Sie ist eine Aussage über DIESES Konto, und mit dem Trennen ist sie weg.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'inat_api.dart';

class InatAccount {
  const InatAccount({
    required this.accessToken,
    required this.login,
    this.license = InatLicense.ccByNc,
  });

  final String accessToken;
  final String login;
  final InatLicense license;

  InatAccount withLicense(InatLicense license) =>
      InatAccount(accessToken: accessToken, login: login, license: license);

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'login': login,
        'license': license.code,
      };

  /// `null` bei allem, was nicht passt — ein kaputter Eintrag heißt
  /// „nicht verbunden", nicht Absturz.
  static InatAccount? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final token = json['access_token'];
    final login = json['login'];
    if (token is! String || token.isEmpty || login is! String) return null;
    return InatAccount(
      accessToken: token,
      login: login,
      license: InatLicense.fromCode(json['license'] as String?),
    );
  }
}

abstract class InatAccountStore {
  Future<InatAccount?> read();
  Future<void> write(InatAccount account);
  Future<void> clear();
}

class SecureInatAccountStore implements InatAccountStore {
  SecureInatAccountStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _key = 'inat_account';

  @override
  Future<InatAccount?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      return raw == null ? null : InatAccount.fromJson(jsonDecode(raw));
    } catch (_) {
      // Unlesbar (Keystore-Schlüssel weg, z. B. nach einer Geräte-
      // übertragung trotz Ausschluss) ⇒ „nicht verbunden". Neu verbinden
      // ist der Ausweg, und genau den bietet das Profil dann an.
      return null;
    }
  }

  @override
  Future<void> write(InatAccount account) =>
      _storage.write(key: _key, value: jsonEncode(account.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
