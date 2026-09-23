// Bilder am Feedback (#525, bis zu drei seit #569) — durch die echte
// Oberfläche.
//
// Dieselbe Pipeline wie bei den Fundfotos, ein anderer Empfänger: Das
// Bild geht in einen Bucket, den nur der Betreiber liest, und wird —
// anders als der Text — nicht veröffentlicht. Geprüft wird an den Bytes
// im Fake-Bucket, dass die Fundstelle nicht mitreist, und an der Zeile,
// dass der Pfad im eigenen Ordner liegt.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pilzbuddy/core/photo_pipeline.dart';
import 'package:pilzbuddy/core/widgets/photo_attachment.dart';
import 'package:pilzbuddy/data/feedback_repository.dart';
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
    final picker = FakePhotoPicker(dirtyJpeg(width: 3000, height: 2250));
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
    await tester.pump(); // „Senden“ wird erst mit dem nächsten Frame aktiv
    await tester.tap(find.text('Senden'));
    await settle(tester);

    final row = backend.feedback.single;
    expect(row['type'], 'bug');
    expect(row['photo_path'], isNull,
        reason: 'die alte Spalte gehört den Clients bis 1.195.x');
    final path = (row['photo_paths'] as List<String>).single;
    expect(path, startsWith('${me.id}/'));
    expect(path, endsWith('.jpg'));
    final bytes = backend.feedbackPhotoObjects[path]!;
    expect(jpegForeignMarkers(bytes), isEmpty);
    expect(hasText(bytes, 'Buchenhang'), isFalse);
    expect(hasText(bytes, 'Exif'), isFalse);
    expect(img.decodeJpg(bytes)!.width, kPhotoMaxEdge,
        reason: 'allgemeines Feedback bleibt klein — Screenshots, keine '
            'Galerie');
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
    await tester.pump(); // „Senden“ wird erst mit dem nächsten Frame aktiv
    await tester.tap(find.text('Senden'));
    await settle(tester);
    expect(backend.feedback.single['photo_paths'], isNull);
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

  testWidgets('„Hinweis zu dieser Art melden" nimmt ein Bild mit — in '
      'Galerie-Größe', (tester) async {
    final (backend, me) = loggedInBackend();
    await pumpApp(tester, backend,
        photoPicker: FakePhotoPicker(dirtyJpeg(width: 3000, height: 2250)));
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
    await tester.pump(); // „Senden“ wird erst mit dem nächsten Frame aktiv
    await tester.tap(find.text('Senden'));
    await settle(tester);

    final row = backend.feedback.single;
    expect(row['type'], 'bug');
    expect(row['message'],
        'Hinweis zur Art „Judasohr": Bei mir sind sie viel dunkler.');
    final path = (row['photo_paths'] as List<String>).single;
    expect(path, startsWith('${me.id}/'));
    expect(backend.feedbackPhotoObjects, hasLength(1));
    // Das Hochgeladene ist bei einem fremden Melder die einzige Kopie —
    // mit 1024 blieben der 1200er Galerie aus 4:3 nur 768 px im Quadrat.
    final bytes = backend.feedbackPhotoObjects[path]!;
    final uploaded = img.decodeJpg(bytes)!;
    expect((uploaded.width, uploaded.height), (kGalleryPhotoMaxEdge, 1536));
    expect(jpegForeignMarkers(bytes), isEmpty,
        reason: 'größer heißt nicht weniger entkernt');
    expect(hasText(bytes, 'Buchenhang'), isFalse);
    await drainSnackbars(tester);
  });

  Future<void> attach(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(kAttachPhotoKey));
    await settle(tester);
    await tester.tap(find.byKey(kAttachPhotoKey));
    await settle(tester, frames: 12);
  }

  testWidgets('bis zu drei Bilder — danach kein freies Feld mehr',
      (tester) async {
    final (backend, me) = loggedInBackend();
    await pumpApp(tester, backend, photoPicker: FakePhotoPicker(dirtyJpeg()));
    await openFeedback(tester);

    await attach(tester);
    expect(find.text('Weiteres Bild'), findsOneWidget,
        reason: 'nach dem ersten ein Feld für das nächste');
    await attach(tester);
    await attach(tester);
    expect(find.byKey(kRemovePhotoKey), findsNWidgets(kFeedbackMaxPhotos));
    expect(find.byKey(kAttachPhotoKey), findsNothing,
        reason: 'ein viertes lehnte die Datenbank ab (Patch 033)');
    expect(find.textContaining('nicht öffentlich'), findsOneWidget,
        reason: 'der Satz einmal, nicht dreimal');

    await tester.enterText(
        find.widgetWithText(TextField, 'Dein Wunsch'), 'Drei Ansichten');
    await tester.pump(); // „Senden“ wird erst mit dem nächsten Frame aktiv
    await tester.tap(find.text('Senden'));
    await settle(tester);

    final paths = backend.feedback.single['photo_paths'] as List<String>;
    expect(paths, hasLength(3));
    expect(paths.toSet(), hasLength(3), reason: 'drei Objekte, nicht eins');
    for (final path in paths) {
      expect(path, startsWith('${me.id}/'));
      expect(backend.feedbackPhotoObjects[path], isNotNull);
    }
    await drainSnackbars(tester);
  });

  testWidgets('ein Bild aus der Mitte entfernen: die anderen bleiben, das '
      'Feld kommt zurück', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, photoPicker: FakePhotoPicker(dirtyJpeg()));
    await openFeedback(tester);
    await attach(tester);
    await attach(tester);
    await attach(tester);

    await tester.tap(find.byKey(kRemovePhotoKey).at(1));
    await settle(tester);
    expect(find.byKey(kRemovePhotoKey), findsNWidgets(2));
    expect(find.byKey(kAttachPhotoKey), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Dein Wunsch'), 'Zwei reichen');
    await tester.pump(); // „Senden“ wird erst mit dem nächsten Frame aktiv
    await tester.tap(find.text('Senden'));
    await settle(tester);
    expect(backend.feedback.single['photo_paths'], hasLength(2));
    await drainSnackbars(tester);
  });

  Future<void> openSpeciesReport(WidgetTester tester) async {
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
  }

  testWidgets('Galerie-Einwilligung (Patch 034): erst mit Bild, nennt den '
      'Namen, ab Werk aus', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, photoPicker: FakePhotoPicker(dirtyJpeg()));
    await openSpeciesReport(tester);

    expect(find.byKey(kGalleryConsentKey), findsNothing,
        reason: 'ohne Bild gibt es nichts freizugeben');
    await attach(tester);
    expect(find.byKey(kGalleryConsentKey), findsOneWidget);
    expect(
        tester.widget<CheckboxListTile>(find.byKey(kGalleryConsentKey)).value,
        isFalse,
        reason: 'ab Werk aus');
    expect(find.textContaining('„testpilz" als Urheber'), findsOneWidget,
        reason: 'der Name, der öffentlich würde, steht ausgeschrieben da');
    expect(find.textContaining(kGalleryPhotoLicence), findsOneWidget);

    await tester.tap(find.byKey(kGalleryConsentKey));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Mein Fund');
    await tester.pump(); // „Senden“ wird erst mit dem nächsten Frame aktiv
    await tester.tap(find.text('Senden'));
    await settle(tester);
    expect(backend.feedback.single['photo_consent'], isTrue);
    await drainSnackbars(tester);
  });

  testWidgets('ohne Haken keine Einwilligung — und das letzte Bild weg '
      'nimmt den Haken mit', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, photoPicker: FakePhotoPicker(dirtyJpeg()));
    await openSpeciesReport(tester);
    await attach(tester);
    await tester.tap(find.byKey(kGalleryConsentKey));
    await settle(tester);

    await tester.tap(find.byKey(kRemovePhotoKey));
    await settle(tester);
    expect(find.byKey(kGalleryConsentKey), findsNothing);
    await attach(tester);
    expect(
        tester.widget<CheckboxListTile>(find.byKey(kGalleryConsentKey)).value,
        isFalse,
        reason: 'ein Haken für ein Bild, das es nicht mehr gibt, gilt '
            'nicht für das nächste');

    await tester.enterText(find.byType(TextField).first, 'Mein Fund');
    await tester.pump(); // „Senden“ wird erst mit dem nächsten Frame aktiv
    await tester.tap(find.text('Senden'));
    await settle(tester);
    expect(backend.feedback.single['photo_consent'], isFalse);
    await drainSnackbars(tester);
  });

  testWidgets('Art-Hinweis: „Senden" ist nur aktiv, wenn danach wirklich '
      'gesendet wird — auch mit Fotos', (tester) async {
    // Feldtest 2026-09-23: drei Schwefelporling-Fotos, kein Text,
    // „Senden" — und nichts kam an. Ohne Text schloss der Dialog und
    // verwarf die Fotos, ohne ein Wort.
    final (backend, _) = loggedInBackend();
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

    bool sendEnabled() =>
        tester.widget<FilledButton>(find.byKey(kReportSendKey)).onPressed !=
        null;
    expect(sendEnabled(), isFalse, reason: 'leer: nichts zu senden');

    await tester.tap(find.byKey(kAttachPhotoKey));
    await settle(tester, frames: 12);
    expect(sendEnabled(), isFalse,
        reason: 'ein Foto allein sagt nicht, was daran auffällt');
    expect(find.textContaining('was auf dem Bild auffällt'), findsOneWidget,
        reason: 'der Grund steht VOR dem Tipp da');

    await tester.enterText(find.byType(TextField).last, 'ok');
    await settle(tester);
    expect(sendEnabled(), isFalse, reason: 'unter $kFeedbackMinChars Zeichen');

    await tester.enterText(
        find.byType(TextField).last, 'Hut viel gelber als auf den Bildern');
    await settle(tester);
    expect(sendEnabled(), isTrue);
    await tester.tap(find.byKey(kReportSendKey));
    await settle(tester);
    expect(backend.feedback, hasLength(1));
    expect(backend.feedbackPhotoObjects, hasLength(1),
        reason: 'und die Fotos kommen mit');
    await drainSnackbars(tester);
  });

  testWidgets('„Wünsch dir was!": „Senden" bleibt grau, bis genug dasteht',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openFeedback(tester);

    bool sendEnabled() => tester
            .widget<ButtonStyleButton>(find.ancestor(
                of: find.text('Senden'),
                matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)))
            .onPressed !=
        null;
    expect(sendEnabled(), isFalse);
    expect(find.text('Ein paar Worte, dann lässt sich senden.'),
        findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Dein Wunsch'), 'Fotos zu Funden');
    await settle(tester);
    expect(sendEnabled(), isTrue);
    expect(find.text('Ein paar Worte, dann lässt sich senden.'), findsNothing);
  });
}
