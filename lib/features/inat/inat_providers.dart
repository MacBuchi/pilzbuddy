// Funde an iNaturalist melden (#553) — die Nähte zur Außenwelt.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../../data/find_report_repository.dart';
import '../../data/inat_account.dart';
import '../../data/inat_api.dart';
import '../../data/providers.dart';
import 'inat_reporter.dart';

/// Die Application ID — im Test überschrieben, in der App
/// [kInatAppId].
final inatAppIdProvider = Provider<String>((ref) => kInatAppId);

/// Gibt es den Weg überhaupt? **Davon hängt ab, ob irgendwo etwas
/// davon zu sehen ist** — ohne verbundenes Konto ohnehin nichts, ohne
/// Application ID nicht einmal der Eintrag im Profil.
///
/// **Nicht im Browser — vorerst.** Dort braucht die Rückleitung eine
/// eigene Seite, die das Fenster schließt und den Code an die App
/// reicht, und iNaturalists Token-Adresse ist aus dem Browser nicht
/// nachgemessen (CORS). Die Redirect-URIs für die Web-Fassung sind bei
/// der Registrierung trotzdem schon eingetragen (#553).
final inatAvailableProvider = Provider<bool>(
    (ref) => !kIsWeb && ref.watch(inatAppIdProvider).isNotEmpty);

final inatHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final inatApiProvider = Provider<InatApi>((ref) => InatApi(
    ref.watch(inatHttpClientProvider),
    appId: ref.watch(inatAppIdProvider)));

/// Öffnet die Anmeldung und liefert die Rückleitung. Die einzige Stelle,
/// an der ein Custom Tab aufgeht — im Test überschrieben.
final inatAuthorizerProvider =
    Provider<Future<Uri> Function(Uri authorizeUrl)>((ref) => (url) async {
          final result = await FlutterWebAuth2.authenticate(
            url: url.toString(),
            callbackUrlScheme: kInatCallbackScheme,
          );
          return Uri.parse(result);
        });

final inatAccountStoreProvider =
    Provider<InatAccountStore>((ref) => SecureInatAccountStore());

final findReportRepositoryProvider = Provider(
    (ref) => FindReportRepository(ref.watch(supabaseClientProvider)));

final inatReporterProvider = Provider((ref) => InatReporter(
      api: ref.watch(inatApiProvider),
      reports: ref.watch(findReportRepositoryProvider),
    ));

/// Das verbundene Konto — `null`, solange keines verbunden ist (oder
/// der Weg gar nicht angeboten wird).
final inatAccountProvider =
    AsyncNotifierProvider<InatAccountNotifier, InatAccount?>(
        InatAccountNotifier.new);

class InatAccountNotifier extends AsyncNotifier<InatAccount?> {
  @override
  Future<InatAccount?> build() async {
    if (!ref.watch(inatAvailableProvider)) return null;
    return ref.read(inatAccountStoreProvider).read();
  }

  /// Verbindet ein Konto. Wirft bei Abbruch oder Fehler — die
  /// Oberfläche sagt, was passiert ist; der alte Zustand bleibt stehen.
  Future<void> connect(InatLicense license) async {
    final account = await connectInat(
      api: ref.read(inatApiProvider),
      authorize: ref.read(inatAuthorizerProvider),
      license: license,
    );
    await ref.read(inatAccountStoreProvider).write(account);
    state = AsyncData(account);
  }

  /// Trennt NUR auf diesem Gerät. Die Freigabe bei iNaturalist bleibt
  /// bestehen, bis der Nutzer sie dort widerruft — das sagt der Dialog.
  Future<void> disconnect() async {
    await ref.read(inatAccountStoreProvider).clear();
    state = const AsyncData(null);
  }

  Future<void> setLicense(InatLicense license) async {
    final account = state.valueOrNull;
    if (account == null) return;
    final updated = account.withLicense(license);
    await ref.read(inatAccountStoreProvider).write(updated);
    state = AsyncData(updated);
  }
}
