// Der Weg vom Update-Banner bis zum System-Installer. Der Dialog ist die
// Stelle, an der ein Fehlschlag sichtbar werden muss statt still zu enden —
// sonst tippt jemand „Jetzt aktualisieren" und nichts passiert.
//
// Was hier NICHT geprüft wird, ist der Download selbst: Der läuft gegen
// echte Dateien und steht in `update_installer_test.dart`.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/update_check.dart';
import 'package:pilzbuddy/features/update/update_installer.dart';

import '../fakes/fake_apk_installer.dart';
import '../fakes/fake_backend.dart';
import '../fakes/fake_update_installer.dart';
import '../fakes/test_app.dart';

const _info = UpdateInfo(
  latestVersion: '9.9.9',
  downloadUrl: 'https://example.invalid/pilzbuddy-9.9.9.apk',
  releaseNotes: 'Karte wird schneller',
);

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  List<Override> withUpdate(FakeUpdateInstaller installer) => [
        updateInfoProvider.overrideWith((ref) => Future.value(_info)),
        updateInstallerProvider.overrideWithValue(installer),
      ];

  Future<void> openDialog(WidgetTester tester) async {
    expect(find.textContaining('Update auf v9.9.9 verfügbar'), findsOneWidget);
    await tester.tap(find.textContaining('Update auf v9.9.9 verfügbar'));
    await settle(tester);
  }

  testWidgets('Banner → Dialog → Update wird angestoßen', (tester) async {
    final installer = FakeUpdateInstaller();
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, extraOverrides: withUpdate(installer));

    await openDialog(tester);
    // Die Release-Notes des Servers stehen im Dialog.
    expect(find.text('Karte wird schneller'), findsOneWidget);

    await tester.tap(find.text('Jetzt aktualisieren'));
    await settle(tester, frames: 10);

    expect(installer.started?.latestVersion, '9.9.9');
    // Nach der Übergabe liegt Androids Installer vorn — der Dialog darf
    // nicht dahinter stehen bleiben.
    expect(find.text('Jetzt aktualisieren'), findsNothing);
  });

  testWidgets('Fehlende Freigabe wird erklärt statt still zu scheitern',
      (tester) async {
    final apk = FakeApkInstaller(allowed: false);
    final installer = FakeUpdateInstaller(failure: UpdateFailure.notAllowed);
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        apkInstaller: apk, extraOverrides: withUpdate(installer));

    await openDialog(tester);
    await tester.tap(find.text('Jetzt aktualisieren'));
    await settle(tester, frames: 10);

    expect(find.textContaining('einmalig erlauben'), findsOneWidget);
    // Der Dialog bleibt offen — sonst verschwände die Erklärung sofort.
    expect(find.text('Jetzt aktualisieren'), findsOneWidget);

    // Und der Weg dorthin ist einen Tipp entfernt, statt in den
    // Systemeinstellungen gesucht werden zu müssen.
    await tester.tap(find.text('Einstellung öffnen'));
    await settle(tester);
    expect(apk.settingsOpened, 1);
  });

  testWidgets('Ein gescheiterter Download lässt den Browser-Weg stehen',
      (tester) async {
    final installer =
        FakeUpdateInstaller(failure: UpdateFailure.downloadFailed);
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, extraOverrides: withUpdate(installer));

    await openDialog(tester);
    await tester.tap(find.text('Jetzt aktualisieren'));
    await settle(tester, frames: 10);

    expect(find.textContaining('nicht geklappt'), findsOneWidget);
    // Der Browser braucht weder Kanal noch Berechtigung und ist deshalb
    // der Rückfallweg — er muss sichtbar bleiben.
    expect(find.text('Im Browser'), findsOneWidget);
  });

  testWidgets('Ohne In-App-Installation bleibt nur der Browser',
      (tester) async {
    // Web und alte Builds ohne den Method-Channel: Der Dialog darf dann
    // keinen Knopf anbieten, der nichts tun kann.
    final installer = FakeUpdateInstaller(supported: false);
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, extraOverrides: withUpdate(installer));

    await openDialog(tester);
    expect(find.text('Jetzt aktualisieren'), findsNothing);
    expect(find.text('Im Browser'), findsOneWidget);
    expect(find.textContaining('startet im Browser'), findsOneWidget);
  });
}
