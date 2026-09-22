// Foto beim Eintragen (#532 Stufe 2) — durch die echte Oberfläche.
//
// Vorher ging ein Fundfoto nur über die kleine Kamera am FERTIGEN Fund.
// Jetzt bietet das Blatt „Fund eintragen" es gleich an. Die teuren
// Fälle sind wieder die, in denen etwas NICHT passieren darf: ein Foto
// am falschen Fund, ein Foto an einem Fund im Korb, ein Leergang mit
// Kamera — und ein gescheiterter Upload, der den Fund mitreißt.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/photo_pipeline.dart';
import 'package:pilzbuddy/core/widgets/photo_attachment.dart';
import 'package:pilzbuddy/data/outbox.dart';
import 'package:pilzbuddy/features/spots/widgets/add_find_sheet.dart';
import 'package:pilzbuddy/features/spots/widgets/find_photo_strip.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_outbox.dart';
import '../fakes/map_ui.dart';
import '../fakes/photo_fixtures.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  Future<void> openAddSheet(WidgetTester tester,
      {String spot = 'Buchenhang', String button = 'Fund eintragen'}) async {
    await tester.tap(find.byTooltip(spot));
    await settle(tester);
    await tester.tap(find.text(button));
    await settle(tester);
  }

  Future<void> attachFromGallery(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(kAttachPhotoKey));
    expect(find.text('Foto für Buddys teilen'), findsOneWidget);
    expect(find.text(kFindPhotoShareNote), findsOneWidget,
        reason: 'vorher steht da, was mit dem Bild passiert');
    await tester.tap(find.byKey(kAttachPhotoKey));
    await settle(tester, frames: 12);
    expect(find.text(kFindPhotoShareNote), findsNothing,
        reason: 'angehängt ersetzt der kurze Satz am Bild den langen');
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester, frames: 12);
  }

  testWidgets('Foto im Blatt: der neue Fund bekommt es, nackt, und die '
      'Quittung sagt es', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 1));
    final picker = FakePhotoPicker(dirtyJpeg());
    await pumpApp(tester, backend, photoPicker: picker);

    await openAddSheet(tester);
    await attachFromGallery(tester);
    await save(tester);

    final finds = backend.spots.single.finds;
    expect(finds, hasLength(2));
    final fresh = finds.last;
    final row = backend.findPhotos.single;
    expect(row.findId, fresh.id,
        reason: 'am NEUEN Fund, nicht am alten vom 1. September');
    for (final entry in backend.photoObjects.entries) {
      expect(jpegForeignMarkers(entry.value), isEmpty, reason: entry.key);
      expect(hasText(entry.value, 'Exif'), isFalse, reason: entry.key);
    }
    expect(find.text(kFindPhotoSharedMessage), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('mehrere Arten: das Foto hängt am ersten, und das Blatt '
      'sagt es vorher', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 1));
    await pumpApp(tester, backend, photoPicker: FakePhotoPicker(dirtyJpeg()));

    await openAddSheet(tester);
    await attachFromGallery(tester);
    expect(find.byKey(kFindPhotoMultiNote), findsNothing,
        reason: 'bei einer Art ist eindeutig, woran es hängt');
    // Steinpilz vorbelegt → ablegen, dann eine zweite Art.
    await tester.ensureVisible(find.text('weitere Art'));
    await tester.tap(find.text('weitere Art'));
    await settle(tester);
    await tester.enterText(speciesField(), 'Pfifferling');
    await settle(tester);
    expect(find.byKey(kFindPhotoMultiNote), findsOneWidget);
    expect(find.text('Das Foto hängt am ersten Fund (Steinpilz).'),
        findsOneWidget);
    await save(tester);

    final fresh = backend.spots.single.finds.skip(1).toList();
    expect([for (final f in fresh) f.species], ['Steinpilz', 'Pfifferling']);
    expect(backend.findPhotos.single.findId, fresh.first.id);
    await drainSnackbars(tester);
  });

  testWidgets('ohne Empfang: Fund in den Korb, Foto nicht — und die '
      'Meldung sagt, wie es weitergeht', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz');
    final outbox = FakeOutbox();
    await pumpApp(tester, backend,
        photoPicker: FakePhotoPicker(dirtyJpeg()), outbox: outbox);

    await openAddSheet(tester);
    await attachFromGallery(tester);
    backend.offline = true;
    await save(tester);

    expect(outbox.jobs.single, isA<NewFindsJob>(),
        reason: 'der Fund ist das Original — er geht in den Korb');
    expect(backend.findPhotos, isEmpty);
    expect(backend.photoObjects, isEmpty);
    expect(outbox.jobs, hasLength(1), reason: 'kein dritter Korb-Weg');
    expect(find.text(kFindPhotoQueuedMessage), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('scheitert nur der Upload, steht der Fund trotzdem',
      (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz');
    await pumpApp(tester, backend, photoPicker: FakePhotoPicker(dirtyJpeg()));

    await openAddSheet(tester);
    await attachFromGallery(tester);
    backend.photoUploadFails = true;
    await save(tester);

    expect(backend.spots.single.finds, hasLength(2));
    expect(backend.findPhotos, isEmpty);
    expect(find.textContaining('Fund eingetragen, das Foto nicht'),
        findsOneWidget);
    expect(find.textContaining('am Fund nachreichen'), findsOneWidget);
    await drainSnackbars(tester);
  });

  testWidgets('entfernt vor dem Speichern: kein Foto', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz');
    await pumpApp(tester, backend, photoPicker: FakePhotoPicker(dirtyJpeg()));

    await openAddSheet(tester);
    await attachFromGallery(tester);
    await tester.tap(find.byKey(kRemovePhotoKey));
    await settle(tester);
    await save(tester);

    expect(backend.spots.single.finds, hasLength(2));
    expect(backend.findPhotos, isEmpty);
    expect(find.text(kFindPhotoSharedMessage), findsNothing);
    await drainSnackbars(tester);
  });

  testWidgets('ein Leergang bietet kein Foto an', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, name: 'Buchenhang', species: 'Steinpilz');
    await pumpApp(tester, backend, photoPicker: FakePhotoPicker(dirtyJpeg()));

    await openAddSheet(tester, button: 'Nichts gefunden');
    expect(find.byKey(kAttachPhotoKey), findsNothing);
    expect(find.text(kFindPhotoShareNote), findsNothing);
  });

  testWidgets('ein wartender Spot bietet kein Foto an — sein Fund geht '
      'sicher in den Korb', (tester) async {
    final (backend, _) = loggedInBackend();
    final outbox = FakeOutbox();
    await pumpApp(tester, backend,
        photoPicker: FakePhotoPicker(dirtyJpeg()), outbox: outbox);
    backend.offline = true;
    await tester.tap(find.text('Neuer Spot'));
    await settle(tester);
    await tester.enterText(speciesField(), 'Steinpilz');
    await settle(tester);
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await settle(tester);
    await drainSnackbars(tester);
    expect(outbox.jobs.single, isA<NewSpotJob>());

    await openAddSheet(tester, spot: 'Pilz-Spot — wartet auf Verbindung');
    expect(find.text('Fund eintragen'), findsWidgets,
        reason: 'das Blatt ist offen');
    expect(find.byKey(kAttachPhotoKey), findsNothing);
  });
}
