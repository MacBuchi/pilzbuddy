// Der Update-Weg in der App. Jeder Fehlschlag muss in einem *Grund* enden,
// nicht in einer Ausnahme: Der Dialog schickt daraufhin in den Browser, und
// dieser Rückfallweg ist der einzige, der ohne Berechtigung auskommt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pilzbuddy/core/update_check.dart';
import 'package:pilzbuddy/features/update/update_installer.dart';

import 'fakes/fake_apk_installer.dart';

const _info = UpdateInfo(
  latestVersion: '9.9.9',
  downloadUrl: 'https://example.invalid/pilzbuddy-9.9.9.apk',
  releaseNotes: 'Testnotizen',
);

/// Liefert [body] als Antwort; `length` weicht davon ab, wenn ein
/// abgeschnittener Download nachgestellt werden soll.
http.Client _client(List<int> body, {int? length, int status = 200}) =>
    MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream.value(body),
        status,
        contentLength: length ?? body.length,
      );
    });

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('pilzbuddy_update'));
  tearDown(() => temp.deleteSync(recursive: true));

  UpdateInstaller installerWith(FakeApkInstaller apk, http.Client client) =>
      UpdateInstaller(
          installer: apk, client: client, directory: () async => temp);

  test('Erfolg: Datei landet im updates-Ordner und geht an den Installer',
      () async {
    final apk = FakeApkInstaller();
    final progress = <double>[];
    final failure = await installerWith(apk, _client(List.filled(2048, 7)))
        .downloadAndInstall(_info, onProgress: progress.add);

    expect(failure, isNull);
    expect(apk.installedPath, endsWith('/updates/pilzbuddy-9.9.9.apk'));
    expect(File(apk.installedPath!).lengthSync(), 2048);
    // Der Pfad muss im updates-Ordner liegen, sonst gibt der FileProvider
    // ihn nicht heraus (file_paths.xml erlaubt nur den).
    expect(progress.last, 1.0);
  });

  test('Ohne Freigabe wird gar nicht erst geladen', () async {
    final apk = FakeApkInstaller(allowed: false);
    final failure = await installerWith(apk, _client(List.filled(8, 1)))
        .downloadAndInstall(_info);

    expect(failure, UpdateFailure.notAllowed);
    expect(apk.installedPath, isNull);
    // Nichts angefasst: 60 MB zu laden, um dann an der Freigabe zu
    // scheitern, wäre die teuerste Art, es zu erfahren.
    expect(temp.listSync(), isEmpty);
  });

  test('HTTP-Fehler endet als downloadFailed, nicht als Ausnahme', () async {
    final apk = FakeApkInstaller();
    final failure = await installerWith(apk, _client(const [], status: 404))
        .downloadAndInstall(_info);

    expect(failure, UpdateFailure.downloadFailed);
    expect(apk.installedPath, isNull);
  });

  test('Abgeschnittener Download wird verworfen', () async {
    // Sonst quittiert Android die halbe Datei mit „App nicht installiert",
    // ohne zu sagen, warum.
    final apk = FakeApkInstaller();
    final failure =
        await installerWith(apk, _client(List.filled(10, 1), length: 100))
            .downloadAndInstall(_info);

    expect(failure, UpdateFailure.downloadFailed);
    expect(apk.installedPath, isNull);
    expect(Directory('${temp.path}/updates').listSync(), isEmpty,
        reason: 'Die unvollständige Datei muss weg sein');
  });

  test('Ein nicht zu öffnender Installer meldet installFailed', () async {
    final apk = FakeApkInstaller(installSucceeds: false);
    final failure = await installerWith(apk, _client(List.filled(64, 3)))
        .downloadAndInstall(_info);

    expect(failure, UpdateFailure.installFailed);
  });

  test('Ein alter Rest wird vor dem nächsten Download weggeräumt', () async {
    final dir = Directory('${temp.path}/updates')..createSync(recursive: true);
    File('${dir.path}/pilzbuddy-1.0.0.apk').writeAsBytesSync(List.filled(9, 0));

    await installerWith(FakeApkInstaller(), _client(List.filled(32, 5)))
        .downloadAndInstall(_info);

    expect(dir.listSync().map((e) => e.path.split('/').last),
        ['pilzbuddy-9.9.9.apk'],
        reason: 'Jede APK wiegt ~60 MB — Reste dürfen nicht liegen bleiben');
  });
}
