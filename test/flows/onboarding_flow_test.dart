// Die Kontexthilfe für neue Nutzer (#350, Baustein A).
//
// Was hier festgehalten wird, ist nicht der Wortlaut, sondern drei
// Zusagen: Der leere Zustand erklärt die EINE Handlung, die man nicht
// erraten kann; er verschwindet, sobald sie geglückt ist; und er
// verdeckt dabei nichts, was man antippen wollen könnte.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/data/outbox_view.dart' show SpotsWithOutbox;
import 'package:pilzbuddy/features/help/help_screen.dart';
import 'package:pilzbuddy/features/spots/spot_providers.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

/// Spots, die nie fertig laden — für den Fall „noch am Laden".
class _NeverLoadingSpots extends MySpotsNotifier {
  @override
  Future<SpotsWithOutbox> build() => Completer<SpotsWithOutbox>().future;
}

/// Der leere Kartenzustand — an seinem Anfang erkannt, nicht am ganzen Satz.
Finder get hint => find.textContaining('Noch kein eigener Spot');

/// Öffnet einen Eintrag im Profil-Tab — Muster wie in
/// change_username_flow_test.dart: erst heranscrollen, dann tippen.
Future<void> openProfileEntry(WidgetTester tester, String title) async {
  await tester.tap(find.text('Profil'));
  await settle(tester);
  final tile = find.text(title);
  for (var i = 0; i < 8 && tile.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await settle(tester, frames: 4);
  }
  await tester.ensureVisible(tile);
  await settle(tester);
  await tester.tap(tile);
  await settle(tester);
}

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  testWidgets('die leere Karte sagt, wie der erste Spot entsteht',
      (tester) async {
    // Bis 1.106.1 sah ein frisch angemeldeter Nutzer eine Deutschlandkarte,
    // fünf Knöpfe — und kein Wort dazu. Die Hürde ist nicht der Knopf,
    // sondern dass Fadenkreuz und Knopf zusammengehören; deshalb müssen
    // beide im Text vorkommen.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);

    expect(hint, findsOneWidget);
    expect(find.textContaining('Fadenkreuz'), findsWidgets);
    expect(find.textContaining('Neuer Spot'), findsWidgets);
  });

  testWidgets('solange die Spots laden, schweigt er', (tester) async {
    // Ohne diese Bedingung blitzte der Hinweis bei JEDEM Start kurz auf —
    // auch bei jemandem mit 200 Spots, denn `mySpotListProvider` liefert
    // während des Ladens eine leere Liste. Ein „du hast noch nichts",
    // das man Leuten mit vollem Konto vor die Nase setzt, ist schlimmer
    // als gar keins.
    //
    // Der Beweis braucht einen Ladezustand, der NICHT vorbeigeht — der
    // Fake antwortet sonst im selben Frame, und der Test liefe am Fehler
    // vorbei.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, extraOverrides: [
      mySpotsProvider.overrideWith(_NeverLoadingSpots.new),
    ]);

    expect(hint, findsNothing);
  });

  testWidgets('mit dem ersten Spot verschwindet er von selbst',
      (tester) async {
    // Kein X, sondern ein Zustand — dieselbe Regel wie beim
    // Empfangs-Hinweis. Das Verschwinden IST die Rückmeldung „geschafft".
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, species: 'Steinpilz');
    await pumpApp(tester, backend);

    expect(hint, findsNothing);
  });

  testWidgets('Freundes-Spots schalten ihn ab — sonst verdeckt er sie',
      (tester) async {
    // **Der eigentliche Wächter dieser Datei.** Das Banner liegt über der
    // Karte; nachgemessen (24,22)–(776,82). Ein Marker, der dort steht,
    // ist nicht mehr antippbar — im ersten Anlauf lag ein Freundes-Spot
    // bei (0,0)–(44,44), und der Tipp darauf öffnete die Kurzanleitung
    // statt des Spots. Wer geteilte Spots sieht, hat etwas zum Antippen;
    // ausgerechnet dem einen Hinweis vorzusetzen, der „hier ist nichts"
    // sagt, wäre in beide Richtungen falsch.
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id);
    backend.addSpot(ownerId: lilli.id, species: 'Steinpilz');
    await pumpApp(tester, backend);

    expect(hint, findsNothing);

    // Und der Beweis, dass es nicht nur um die Sichtbarkeit geht: Der
    // Marker lässt sich wirklich öffnen.
    await tester.tap(find.byTooltip('Pilz-Spot (lilli92)'));
    await settle(tester);
    expect(find.text('Fund eintragen'), findsOneWidget);
  });

  testWidgets('Antippen führt in die Kurzanleitung', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);

    await tester.tap(hint);
    await settle(tester);

    expect(find.text('Einen Spot anlegen'), findsOneWidget);
  });

  testWidgets('die Kurzanleitung steht auch im Profil und nennt sechs '
      'Schritte', (tester) async {
    // Sie muss ohne den leeren Zustand erreichbar sein: Wer schon Spots
    // hat, sieht das Banner nie wieder.
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, species: 'Steinpilz');
    await pumpApp(tester, backend);

    await openProfileEntry(tester, 'Kurzanleitung');

    // Gescrollt statt geraten: Sechs Abschnitte passen auf keinen
    // Testschirm, und `ListView` baut nur, was in Sichtweite ist.
    const titles = [
      'Einen Spot anlegen',
      'Fund und Leergang eintragen',
      'Was die Karte zeigt',
      'Unterwegs',
      'Mit Buddies teilen',
      'Ohne Empfang',
    ];
    final seen = <String>{};
    for (var i = 0; i < 8; i++) {
      for (final title in titles) {
        if (find
            .descendant(
                of: find.byType(HelpScreen), matching: find.text(title))
            .evaluate()
            .isNotEmpty) {
          seen.add(title);
        }
      }
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -250));
      await settle(tester, frames: 4);
    }
    expect(seen, containsAll(titles));
  });

  testWidgets('das Profil rät nicht zu einer abgeschalteten Geste',
      (tester) async {
    // **Der Fund, der diesen Test veranlasst hat.** Der einzige
    // Erklärsatz, den die App bis 1.106.1 hatte, stand im Profil und
    // lautete „halte auf der Karte gedrückt, um deinen ersten Pilz-Spot
    // anzulegen". Seit #210 ist das ein Schalter — und er steht ab Werk
    // auf AUS. Der Rat führte beim neuen Nutzer also ins Leere.
    //
    // Geprüft wird beides: dass die abgeschaltete Geste nicht mehr
    // empfohlen wird UND dass der Weg genannt ist, den es ab Werk
    // wirklich gibt.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await tester.tap(find.text('Profil'));
    await settle(tester);

    // Erst heranscrollen: Ohne das wäre „findsNothing" auch dann wahr,
    // wenn der falsche Satz nur unterhalb des Bildrands stünde.
    final card = find.textContaining('Noch keine Funde');
    for (var i = 0; i < 8 && card.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await settle(tester, frames: 4);
    }
    expect(card, findsOneWidget);

    expect(find.textContaining('gedrückt'), findsNothing);
    expect(find.textContaining('Neuer Spot'), findsWidgets);
  });

  testWidgets('der Leergang wird am frischen Spot erklärt', (tester) async {
    // „Fund ≠ Eintrag" ist eine Unterscheidung, die die App erfunden hat;
    // CLAUDE.md führt sie als Fehlerquelle sogar für uns selbst.
    final (backend, me) = loggedInBackend();
    // Ohne Namen und ohne Art: Der Marker-Tooltip IST der Anzeigename,
    // und der ist dann „Pilz-Spot".
    backend.addSpot(ownerId: me.id);
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);
    expect(find.textContaining('dass du da warst und nichts da war'),
        findsOneWidget);
  });

  testWidgets('am Spot MIT Historie schweigt die Zeile', (tester) async {
    // Ab dem zwanzigsten Mal wäre sie Lärm — und sie stünde in einem
    // Blatt, dessen Höhe #351 gerade begrenzt hat.
    //
    // **Eigener Test und nicht die zweite Hälfte des vorigen**: Ein
    // zweiter `pumpApp` im selben Test lädt die Spots NICHT neu (Flutter
    // erkennt denselben ProviderScope wieder und hält den Container am
    // Leben). Der Fall wäre also nie eingetreten, und der Test hätte das
    // Gegenteil von dem geprüft, was er behauptet.
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, species: 'Steinpilz');
    await pumpApp(tester, backend);

    await tester.tap(find.byTooltip('Pilz-Spot'));
    await settle(tester);
    expect(find.text('Fund eintragen'), findsOneWidget,
        reason: 'das Blatt muss offen sein, sonst prüft der Test nichts');
    expect(find.textContaining('dass du da warst und nichts da war'),
        findsNothing);
  });
}
