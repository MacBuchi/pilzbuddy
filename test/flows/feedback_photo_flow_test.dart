// Ein Bild am Feedback (#525) — durch die echte Oberfläche.
//
// Dieselbe Pipeline wie bei den Fundfotos, ein anderer Empfänger: Das
// Bild geht in einen Bucket, den nur der Betreiber liest, und wird —
// anders als der Text — nicht veröffentlicht. Geprüft wird an den Bytes
// im Fake-Bucket, dass die Fundstelle nicht mitreist, und an der Zeile,
// dass der Pfad im eigenen Ordner liegt.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/photo_pipeline.dart';
import 'package:pilzbuddy/core/widgets/photo_attachment.dart';
import 'package:pilzbuddy/features/species/species_detail_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/photo_fixtures.dart';
import '../fakes/test_app.dart';

final _feedbackButton = find.byTooltip('Wunsch, Fehler oder Pilzart melden');

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  Future<void> openFeedback(WidgetTester tester) async {
    await tester.tap(_feedbackButton);
    await settle(tester);
    expect(find.text('Wünsch dir was!'), findsOneWidget);
  }

  testWidgets('ein Bild am Bug: nackt im Bucket, Pfad im eigenen Ordner, '
      'nicht öffentlich', (tester) async {
    final (backend, me) = loggedInBackend();
    final picker = FakePhotoPicker(dirtyJpeg());
    await pumpApp(tester, backend, photoPicker: picker);
    await openFeedback(tester);

    await tester.tap(find.byKey(kAttachPhotoKey));
    await settle(tester, frames: 12);
    expect(find.textContaining('nicht öffentlich'), findsOneWidget,
        reason: 'der Anhang sagt, dass er NICHT nach GitHub geht');
    expect(find.textContaining('öffentlich im GitHub-Projekt'), findsOneWidget,
        reason: 'der Text schon — beide Sätze stehen da');
    expect(find.byKey(kRemovePhotoKey), findsOneWidget);

    await tester.tap(find.text('🐛 Bug'));
    await settle(tester, frames: 4);
    await tester.enterText(find.widgetWithText(TextField, 'Was ist passiert?'),
        'Der Marker steht neben dem Weg');
    await tester.tap(find.text('Senden'));
    await settle(tester);

    final row = backend.feedback.single;
    expect(row['type'], 'bug');
    final path = row['photo_path'] as String;
    expect(path, startsWith('${me.id}/'));
    expect(path, endsWith('.jpg'));
    final bytes = backend.feedbackPhotoObjects[path]!;
    expect(jpegForeignMarkers(bytes), isEmpty);
    expect(hasText(bytes, 'Buchenhang'), isFalse);
    expect(hasText(bytes, 'Exif'), isFalse);
    expect(backend.feedbackPhotoObjects, hasLength(1),
        reason: 'nur das Bild, keine Vorschau — die braucht hier niemand');
    await drainSnackbars(tester);
  });

  testWidgets('Bild wieder entfernen: Zeile ohne Pfad, Bucket leer',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, photoPicker: FakePhotoPicker(dirtyJpeg()));
    await openFeedback(tester);
    await tester.tap(find.byKey(kAttachPhotoKey));
    await settle(tester, frames: 12);
    await tester.tap(find.byKey(kRemovePhotoKey));
    await settle(tester);
    expect(find.byKey(kAttachPhotoKey), findsOneWidget, reason: 'wieder leer');

    await tester.enterText(
        find.widgetWithText(TextField, 'Dein Wunsch'), 'Mehr Pilze bitte');
    await tester.tap(find.text('Senden'));
    await settle(tester);
    expect(backend.feedback.single['photo_path'], isNull);
    expect(backend.feedbackPhotoObjects, isEmpty);
    await drainSnackbars(tester);
  });

  testWidgets('Abbruch im Wähler lässt den Dialog stehen, ohne Anhang',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, photoPicker: FakePhotoPicker(null));
    await openFeedback(tester);
    await tester.tap(find.byKey(kAttachPhotoCameraKey));
    await settle(tester);
    expect(find.text('Wünsch dir was!'), findsOneWidget);
    expect(find.byKey(kAttachPhotoKey), findsOneWidget);
    expect(find.byKey(kRemovePhotoKey), findsNothing);
    expect(find.byType(SnackBar), findsNothing, reason: 'nichts zu melden');
  });

  testWidgets('kein Bild ist kein Bild: die Pipeline sagt es, nichts hängt',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend,
        photoPicker: FakePhotoPicker(Uint8List.fromList([1, 2, 3, 4])));
    await openFeedback(tester);
    await tester.tap(find.byKey(kAttachPhotoKey));
    await settle(tester, frames: 12);
    expect(find.textContaining('Bildformat'), findsOneWidget);
    expect(find.byKey(kRemovePhotoKey), findsNothing);
    await drainSnackbars(tester);
  });

  testWidgets('„Hinweis zu dieser Art melden" nimmt ein Bild mit',
      (tester) async {
    final (backend, me) = loggedInBackend();
    await pumpApp(tester, backend, photoPicker: FakePhotoPicker(dirtyJpeg()));
    await openTab(tester, 'Pilze');
    await tester.enterText(
        find.widgetWithText(TextField, 'Art oder wissenschaftlicher Name'),
        'Judasohr');
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Judasohr'));
    await settle(tester);
    await tester.scrollUntilVisible(
        find.text('Hinweis zu dieser Art melden'), 300,
        scrollable: find
            .descendant(
                of: find.byKey(kSpeciesDetailListKey),
                matching: find.byType(Scrollable))
            .first);
    await settle(tester, frames: 4);
    await tester.tap(find.text('Hinweis zu dieser Art melden'));
    await settle(tester);

    await tester.tap(find.byKey(kAttachPhotoKey));
    await settle(tester, frames: 12);
    expect(find.byKey(kRemovePhotoKey), findsOneWidget);
    await tester.enterText(
        find.byType(TextField).last, 'Bei mir sind sie viel dunkler.');
    await tester.tap(find.text('Senden'));
    await settle(tester);

    final row = backend.feedback.single;
    expect(row['type'], 'bug');
    expect(row['message'],
        'Hinweis zur Art „Judasohr": Bei mir sind sie viel dunkler.');
    expect(row['photo_path'], startsWith('${me.id}/'));
    expect(backend.feedbackPhotoObjects, hasLength(1));
    await drainSnackbars(tester);
  });
}
