// Die Detailseite je Art (#511) — vom Reiter aus, nicht aus dem Modell.
//
// Was hier festgehalten wird, sind fünf Zusagen: Die Zeile lässt sich
// öffnen; die Seite sagt, was die Zeile nicht sagen konnte; sie schaltet
// die Ampel über DENSELBEN Schalter wie die Liste; der Weg auf die Karte
// stellt den Filter und wechselt den Reiter; und die 0,6 MB der
// Fundorte werden erst hier gelesen, nicht schon in der Liste.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pilzbuddy/core/widgets/season_bars.dart';
import 'package:pilzbuddy/core/species_edibility.dart';
import 'package:pilzbuddy/core/species_photos.dart';
import 'package:pilzbuddy/features/map/gbif_finds_providers.dart';
import 'package:pilzbuddy/features/species/species_detail_screen.dart';
import 'package:pilzbuddy/features/species/species_screen.dart';

import '../fakes/fake_backend.dart';
import '../fakes/fake_settings.dart';
import '../fakes/test_app.dart';

void main() {
  (FakeBackend, FakeUser) loggedInBackend() {
    final backend = FakeBackend();
    final me = backend.addUser(username: 'testpilz');
    backend.signInAs(me.id);
    return (backend, me);
  }

  /// Zum Reiter „Pilze" und dort auf eine Art tippen.
  ///
  /// **Gesucht statt gescrollt.** Seit der Reiter ein Suchfeld hat, ist
  /// das nicht nur kürzer, es ist auch das einzig Eindeutige: Ein
  /// `TextField` bringt seinen eigenen `Scrollable` mit, und der im
  /// Reiter ist damit nicht mehr der einzige. Getippt wird auf die
  /// ZEILE mit dem genauen Namen — „Steinpilz" lässt auch
  /// „Sommersteinpilz" stehen.
  Future<void> openSpecies(WidgetTester tester, String name) async {
    await openTab(tester, 'Pilze');
    await tester.enterText(
        find.widgetWithText(TextField, 'Art suchen'), name);
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, name));
    await settle(tester);
  }

  /// Auf der Detailseite zu etwas scrollen. Fünf Abschnitte passen auf
  /// keinen Testschirm, und eine `ListView` baut nur, was in Sichtweite
  /// ist — der Zielbereich muss benannt werden, sonst greift der Zug an
  /// der Liste im Reiter dahinter.
  Future<void> scrollDetail(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 200,
        // **Das ÄUSSERE Scrollable, ausdrücklich.** Seit der
        // Porträtreihe steckt in der senkrechten Liste ein zweites,
        // waagerechtes — und das ist ein Nachfahre des ersten, ein
        // `descendant` trifft also beide. Der äußere kommt in der
        // Baumreihenfolge zuerst.
        scrollable: find
            .descendant(
                of: find.byKey(kSpeciesDetailListKey),
                matching: find.byType(Scrollable))
            .first);
    await settle(tester, frames: 4);
  }

  testWidgets('die Zeile öffnet die Seite — mit dem Namen, den die Liste '
      'nicht zeigen konnte', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Steinpilz');

    expect(find.byType(SpeciesDetailScreen), findsOneWidget);
    // Der wissenschaftliche Name ist der einzige eindeutige Schlüssel —
    // in der Liste stand er nirgends.
    expect(find.text('Boletus edulis'), findsOneWidget);
    // Und die Zweitnamen: Wer den Pilz nur als „Herrenpilz" kennt, soll
    // sehen, dass die App ihn kennt.
    expect(find.text('auch: Herrenpilz, Fichtensteinpilz'), findsOneWidget);
    // Der Satz, den eine Detailseite braucht und eine Zeile nicht.
    await scrollDetail(tester, find.textContaining('bestimmt keine Pilze'));
    expect(find.textContaining('bestimmt keine Pilze'), findsOneWidget);
  });

  testWidgets('die Saison steht groß da, mit dem Satz des Spot-Blatts',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Steinpilz');

    // Seit die Seite Einstufung, Verwechslungspartner und Merkmale
    // trägt, liegt die Kurve unter dem Bildschirmrand.
    await scrollDetail(tester, find.text('Wann diese Art gemeldet wird'));

    // Zwölf Balken MIT Monatsbuchstaben — in der Liste sind sie 84 px
    // breit und unbeschriftet, und genau das ist der Unterschied.
    final bars = tester.widget<SeasonBars>(
        find.descendant(
            of: find.byType(SpeciesDetailScreen),
            matching: find.byType(SeasonBars)));
    expect(bars.showLetters, isTrue);
    expect(bars.currentMonth, 8, reason: 'September, aus currentMonthProvider');

    expect(find.text('September: Hauptzeit'), findsOneWidget);
    expect(find.textContaining('wird am häufigsten von August bis September'),
        findsOneWidget);
    // Die Quelle gehört dazu — die Kurve beschreibt frühere Jahre.
    expect(find.textContaining('verrechnet gegen den allgemeinen Meldeeifer'),
        findsOneWidget);
  });

  testWidgets('eine geborgte Kurve sagt, dass sie geborgt ist',
      (tester) async {
    // **Der eigentliche Wächter dieser Datei.** `borrowedFrom` stand bis
    // 1.160.0 NUR im Spot-Blatt — im Reiter „Pilze" las sich die Kurve
    // des Igelstachelbarts als Aussage über ihn, obwohl sie 1147
    // Meldungen über die ganze Gattung sind.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Igelstachelbart');

    // Seit 1.169.0 steht über der Kurve die Merkmalstabelle, die Zeile
    // liegt damit unter dem Falz — eine `ListView` baut nur, was in
    // Sichtweite ist.
    final line =
        find.textContaining('Saison nach verwandten Arten: Stachelbärte');
    await scrollDetail(tester, line);
    expect(line, findsOneWidget);
  });

  testWidgets('eigene Funde zählen, Buddy-Funde nicht', (tester) async {
    final (backend, me) = loggedInBackend();
    final lilli = backend.addUser(username: 'lilli92');
    backend.addFriendship(lilli.id, me.id);
    final spotId = backend.addSpot(
        ownerId: me.id,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 3));
    backend.addFindRow(spotId,
        species: 'Steinpilz',
        foundOn: DateTime(2026, 9, 20),
        authorId: lilli.id);
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Steinpilz');

    await scrollDetail(tester, find.textContaining('zuletzt am'));
    expect(find.text('1 Fund an 1 Spot, zuletzt am 3.9.2026.'), findsOneWidget,
        reason: 'lillis Fund vom 20.9. ist ihre Ausbeute, nicht meine');
  });

  testWidgets('„Auf der Karte zeigen" stellt den Filter und wechselt den '
      'Reiter', (tester) async {
    final (backend, me) = loggedInBackend();
    backend.addSpot(ownerId: me.id, species: 'Steinpilz');
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Steinpilz');

    await scrollDetail(tester, find.text('Auf der Karte zeigen'));
    await tester.tap(find.text('Auf der Karte zeigen'));
    await settle(tester);

    // Auf der Karte, und der Filter MELDET sich (#154) — ein Filter,
    // den die App selbst setzt, ohne es zu sagen, ist genau der Fall,
    // vor dem die Regel warnt.
    expect(find.text('🔍 Gefiltert: nur Steinpilz'), findsOneWidget);
    expect(find.byType(SpeciesDetailScreen), findsNothing);
  });

  testWidgets('der Schalter ist derselbe wie in der Liste', (tester) async {
    // Zwei Wahrheiten über „zählt diese Art für die Ampel" wären eine zu
    // viel: Der Schalter auf der Seite schreibt in denselben Provider,
    // und die Zeile sagt es danach.
    final (backend, _) = loggedInBackend();
    final settings = FakeSettings();
    await pumpApp(tester, backend, settings: settings);
    await openSpecies(tester, 'Steinpilz');

    await scrollDetail(tester, find.text('Für die Ampel mitzählen'));
    await tester.tap(find.text('Für die Ampel mitzählen'));
    await settle(tester);
    expect(settings.ampelExcludedSpecies, {'Steinpilz'});

    // `pageBack()` sucht den englischen „Back"-Tooltip — die App ist
    // deutsch (dieselbe Stelle wie in offline_maps_flow_test.dart).
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.textContaining('von der Ampel ausgenommen'), findsOneWidget);
  });

  testWidgets('eine Art, die es nicht gibt, sagt das — statt abzustürzen',
      (tester) async {
    // Die Adresse trägt den Namen, und die kann aus einem Lesezeichen
    // kommen oder aus einer Fassung, die eine Art noch nicht hatte.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openTab(tester, 'Pilze');

    GoRouter.of(tester.element(find.byType(SpeciesScreen)))
        .go('/pilze/Geheimpilz');
    await settle(tester);

    expect(find.textContaining('kennt PilzBuddy nicht'), findsOneWidget);
  });

  testWidgets('die Liste liest die Fundorte NICHT, die Seite schon',
      (tester) async {
    // Beobachten ist laden (CLAUDE.md): 0,6 MB beim Öffnen eines
    // Reiters wären dieselbe Last, die 1.99.4 aus dem Startpfad genommen
    // hat. Auf einer bewusst geöffneten Seite sind sie in Ordnung.
    var calls = 0;
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend, extraOverrides: [
      gbifFindsLoaderProvider.overrideWithValue(() async {
        calls++;
        return null;
      }),
    ]);

    await openTab(tester, 'Pilze');
    expect(calls, 0, reason: 'der Reiter allein packt nichts aus');

    await openSpecies(tester, 'Steinpilz');
    expect(calls, 1);
  });

  testWidgets('auf Telefonbreite passt auch der längste Name',
      (tester) async {
    // Die Seite ist die erste im Reiter, die eine volle Spalte Text
    // trägt — und Überlauf sieht man im Widget-Test nur, wenn man in
    // der Breite misst, in der die App benutzt wird. Gemessen wird
    // gegen `tester.view`, nicht mit `setSurfaceSize`: Das ändert die
    // MediaQuery nicht (#414).
    //
    // „Frühjahrsknollenblätterpilz" ist zugleich der Fall OHNE Kurve —
    // der bekommt bewusst keine, weil die Gattungskurve für ihn in die
    // Gegenrichtung zeigte und Scheingenauigkeit bei einem tödlich
    // giftigen Pilz teurer ist als eine Lücke.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Frühjahrsknollenblätterpilz');

    expect(tester.takeException(), isNull);
    expect(find.text('Amanita verna'), findsOneWidget);
    await scrollDetail(tester, find.textContaining('keine belastbare Kurve'));
    expect(find.textContaining('keine belastbare Kurve'), findsOneWidget);
    await scrollDetail(tester, find.textContaining('bestimmt keine Pilze'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('die Einstufung steht oben, nicht unten', (tester) async {
    // Eine Warnung, zu der man erst scrollen muss, ist im Wald keine —
    // deshalb ohne `scrollDetail`: Sie muss schon beim Öffnen da sein.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Grüner Knollenblätterpilz');

    expect(find.text('Tödlich giftig'), findsOneWidget);
    expect(find.textContaining('erst Stunden später'), findsOneWidget);
    // Und der Vorbehalt gehört dazu: Die Stufe gilt der Art, nicht dem
    // Pilz im Korb.
    expect(find.textContaining('ersetzt keine Bestimmung'), findsOneWidget);
  });

  testWidgets('ein Speisepilz bekommt kein grünes Häkchen', (tester) async {
    // **Die Asymmetrie, an der alles hängt.** Ein zu vorsichtiges
    // „ungenießbar" kostet eine Mahlzeit, ein zu großzügiges „essbar"
    // eine Leber. Also trägt nur die Warnung Farbe und ein Zeichen —
    // „Speisepilz" steht da wie eine Auskunft, nicht wie eine Freigabe.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Steinpilz');

    expect(find.text('Gilt als Speisepilz'), findsOneWidget);
    // **Auf die eigene Einstufung gezielt.** Seit es
    // Verwechslungspartner gibt, trägt die Seite sehr wohl Warnzeichen
    // — die des Gallenröhrlings und des Satansröhrlings. Die gehören
    // ihnen, nicht dem Steinpilz.
    expect(
        find.descendant(
            of: find.byKey(kEdibilityCardKey),
            matching: find.byIcon(Icons.warning_amber_rounded)),
        findsNothing);
    expect(Edibility.speisepilz.isWarning, isFalse);
  });

  testWidgets('die Liste warnt bei den giftigen, sonst nicht',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openTab(tester, 'Pilze');

    Finder row(String name) => find.widgetWithText(ListTile, name);
    Finder rowIcon(String name) => find.descendant(
        of: row(name), matching: find.byIcon(Icons.warning_amber_rounded));

    /// **Jede Verneinung braucht ihren Anker.** Eine `ListView.builder`
    /// baut nur, was in Sichtweite ist — „diese Zeile trägt kein
    /// Zeichen" ist sonst trivial wahr, weil die Zeile gar nicht da
    /// ist. In der Gegenprobe genau so gemessen: „warnt bei allem"
    /// blieb grün. Die Suche holt die Zeile nach oben und der `expect`
    /// belegt, dass sie wirklich da ist.
    Future<void> searchFor(String name) async {
      await tester.enterText(
          find.widgetWithText(TextField, 'Art suchen'), name);
      await settle(tester);
      expect(row(name), findsOneWidget, reason: '$name muss gebaut sein');
    }

    await searchFor('Steinpilz');
    expect(rowIcon('Steinpilz'), findsNothing,
        reason: 'ein Speisepilz trägt kein Zeichen');

    // Ungenießbar ist nicht giftig — der Gallenröhrling drängt sich
    // nicht in die volle Zeile.
    await searchFor('Gallenröhrling');
    expect(rowIcon('Gallenröhrling'), findsNothing);

    await searchFor('Satansröhrling');
    expect(rowIcon('Satansröhrling'), findsOneWidget);
  });

  testWidgets('die Verwechslungspartner stehen unter der Einstufung — mit '
      'ihrer eigenen', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Stockschwämmchen');

    // Das Paar, an dem in Mitteleuropa Menschen gestorben sind.
    expect(find.byKey(lookalikeRowKey('Gifthäubling')), findsOneWidget);
    // **Die Einstufung des Partners gehört in dieselbe Zeile.**
    // „Gifthäubling" allein sagt jemandem, der ihn nicht kennt, nichts.
    expect(find.text('Tödlich giftig'), findsOneWidget);
    expect(find.textContaining('unterhalb des Rings deutlich SCHUPPIG'),
        findsOneWidget);
    // Und die Liste behauptet nirgends, vollständig zu sein.
    expect(find.textContaining('nicht vollständig'), findsOneWidget);
  });

  testWidgets('ein Partner führt auf seine eigene Seite', (tester) async {
    // Wer hier landet, will als Nächstes meistens genau dorthin — und
    // die Seite des Gifthäublings muss dann zurück auf das
    // Stockschwämmchen zeigen (die Symmetrie, die der Modelltest
    // erzwingt, als Weg durch die Oberfläche).
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Stockschwämmchen');

    await scrollDetail(tester, find.byKey(lookalikeRowKey('Gifthäubling')));
    await tester.tap(find.byKey(lookalikeRowKey('Gifthäubling')));
    await settle(tester);

    // **Und zwar OBEN.** Ohne einen Schlüssel je Art hält Flutter die
    // Seite für dieselbe, verwendet das Element weiter — und die
    // `ListView` behält ihre Scrollposition. Man landete dann mitten
    // auf der Seite des Gifthäublings, nicht bei seinem Namen und
    // seiner Einstufung.
    expect(find.text('Galerina marginata'), findsOneWidget,
        reason: 'jetzt steht die Seite des Gifthäublings da — von oben');
    expect(find.text('Tödlich giftig'), findsWidgets);
    expect(find.byKey(lookalikeRowKey('Stockschwämmchen')), findsOneWidget,
        reason: 'und sie warnt zurück');
  });

  testWidgets('eine Art ohne bekannte Verwechslung schweigt',
      (tester) async {
    // Leer heißt „uns ist keine häufige Verwechslung bekannt" — ein
    // leerer Abschnitt mit Überschrift läse sich als „es gibt keine".
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Judasohr');

    expect(find.text('Verwechslungspartner'), findsNothing);
  });

  testWidgets('die Merkmale stehen im festen Raster, unter den Warnungen',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Stockschwämmchen');

    await scrollDetail(tester, find.text('Merkmale'));
    // Alle sechs Felder, immer dieselben Überschriften — daran hängt,
    // dass sich zwei Arten überhaupt vergleichen lassen.
    for (final label in [
      'Hut',
      'Unterseite',
      'Stiel',
      'Fleisch',
      'Geruch',
      'Vorkommen'
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Und das Merkmal, das beim Stockschwämmchen wirklich entscheidet.
    expect(find.textContaining('DARUNTER deutlich dunkel SCHUPPIG'),
        findsOneWidget);
    expect(find.textContaining('Ein einzelnes Merkmal entscheidet nie'),
        findsOneWidget);
  });

  testWidgets('auch ein Speisepilz ohne Verwechslungspartner zeigt seine '
      'Merkmale', (tester) async {
    // **Die Umkehrung der alten Zusage.** Bis 1.168.0 trugen nur Arten
    // mit Verwechslungspartner und die giftigen eine Beschreibung, und
    // genau hier stand, dass der Rest schweigt. Das war der Fehler: Das
    // Judasohr ist ein Speisepilz ohne eingetragenen Partner, seine
    // Seite sagte über den Pilz kein Wort. Seit 1.169.0 ist die
    // Pflichtmenge jede bekannte Art.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Judasohr');

    await scrollDetail(tester, find.text('Merkmale'));
    expect(find.text('Merkmale'), findsOneWidget);
    // Und zwar mit Inhalt, nicht als leere Überschrift: die gallertige
    // Beschaffenheit ist das Merkmal, an dem das Judasohr hängt.
    expect(find.textContaining('GALLERTARTIG'), findsOneWidget);
  });

  testWidgets('das Bildpaar steht in der Verwechslungszeile — mit '
      'Namensnennung', (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Stockschwämmchen');

    // Beide Bilder, nebeneinander in derselben Zeile.
    expect(
        find.image(const AssetImage(
            'assets/species/stockschwaemmchen.webp')),
        findsOneWidget);
    expect(find.image(const AssetImage('assets/species/gifthaeubling.webp')),
        findsOneWidget);
    // Und der Screenreader hört, was das Bild ist — Inhalt, kein Schmuck.
    expect(find.bySemanticsLabel('Gifthäubling, Foto'), findsOneWidget);
    // **Die Namensnennung steht AM Bild**, nicht nur auf der
    // Lizenzseite — bei CC-BY ist das die Bedingung.
    expect(find.text(photoCredit(speciesPhotos['Stockschwämmchen']!)),
        findsOneWidget);
    expect(find.text(photoCredit(speciesPhotos['Gifthäubling']!)),
        findsOneWidget);
  });

  testWidgets('ohne Bild für den Partner bleibt die Zeile bildlos',
      (tester) async {
    // Ein einzelnes Bild zeigt, wie EINER von beiden aussieht — und das
    // genügt zum Verwechseln. Der Steinpilz hat keines, der
    // Gallenröhrling auch nicht; die Zeile steht trotzdem.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Steinpilz');

    expect(find.text('Gallenröhrling'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(SpeciesDetailScreen),
            matching: find.byType(Image)),
        findsNothing);
  });

  testWidgets('einseitig bebildert heißt: gar kein Bild', (tester) async {
    // **Der Fall, den es in den Daten wirklich gibt.** Der Grüne
    // Knollenblätterpilz hat ein Bild, sein Partner Frauentäubling
    // nicht — dort bleibt die Zeile bildlos, während die Zeile zum
    // Wiesenchampignon zwei zeigt. Ein einzelnes Bild zeigt, wie EINER
    // von beiden aussieht, und das genügt zum Verwechseln.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Grüner Knollenblätterpilz');

    await scrollDetail(tester, find.byKey(lookalikeRowKey('Frauentäubling')));
    expect(
        find.descendant(
            of: find.byKey(lookalikeRowKey('Frauentäubling')),
            matching: find.byType(Image)),
        findsNothing);

    await scrollDetail(
        tester, find.byKey(lookalikeRowKey('Wiesenchampignon')));
    expect(
        find.descendant(
            of: find.byKey(lookalikeRowKey('Wiesenchampignon')),
            matching: find.byType(Image)),
        findsNWidgets(2));
  });

  testWidgets('die Porträtreihe steht unter den Warnungen, mit Nennung',
      (tester) async {
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Fliegenpilz');

    await scrollDetail(tester, find.text('Bilder'));
    expect(find.text('Bilder'), findsOneWidget);
    // Alle drei Bilder der Reihe, nicht nur das erste: Die Serie IST die
    // Aussage — eine Art sieht je nach Alter verschieden aus.
    for (var i = 1; i <= 3; i++) {
      expect(find.image(AssetImage('assets/species/fliegenpilz-$i.webp')),
          findsOneWidget);
    }
    // Die Nennung kommt aus der Tabelle, nicht aus dem Code.
    expect(find.text('Fotos: MacBuchi'), findsOneWidget);
  });

  testWidgets('der Hinweis steht da, seine Begründung erst auf Tippen',
      (tester) async {
    // **Die beiden tragenden Sätze stehen außerhalb des Ausklappers.**
    // Eine eingeklappte Warnung ist Deko; was verschwinden darf, ist die
    // Begründung (Betreiber, 2026-09-22).
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Fliegenpilz');

    await scrollDetail(tester, find.text(kPhotoDisclaimer));
    expect(find.text(kPhotoDisclaimer), findsOneWidget);
    expect(find.text(kPhotoDisclaimerDetail), findsNothing);

    await tester.tap(find.text(kPhotoDisclaimerTitle));
    await settle(tester);
    expect(find.text(kPhotoDisclaimerDetail), findsOneWidget);
  });

  testWidgets('der Hinweis gilt auch, wo es nur ein Bildpaar gibt',
      (tester) async {
    // Er hängt an „steht hier irgendein Bild", nicht an „gibt es
    // Porträts" — sonst stünde unter den Vergleichsbildern nichts.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Stockschwämmchen');

    expect(portraitsFor('Stockschwämmchen'), isEmpty);
    await scrollDetail(tester, find.text(kPhotoDisclaimer));
    expect(find.text(kPhotoDisclaimer), findsOneWidget);
  });

  testWidgets('ohne jedes Bild steht auch kein Hinweis', (tester) async {
    // Die Gegenprobe: Ein Satz über Bilder auf einer Seite ohne Bilder
    // wäre ein Hinweis auf nichts.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Brätling');

    expect(portraitsFor('Brätling'), isEmpty);
    expect(photoFor('Brätling'), isNull);
    // **Die negative Aussage braucht einen Anker.** Ein erster Entwurf
    // zog bis „Merkmale" und prüfte dann auf Abwesenheit — und war damit
    // blind: Nach dem Zug steht „Merkmale" am oberen Rand, alles darüber
    // ist nicht mehr gebaut, und `findsNothing` wäre auch bei einem
    // vorhandenen Hinweis grün. In der Gegenprobe genau so gemessen.
    //
    // Geprüft wird deshalb ein Bildausschnitt, in dem BEIDE Nachbarn
    // stehen: die Einstufung darüber und die Merkmale darunter. Der
    // Hinweis läge dazwischen.
    await scrollDetail(tester, find.text(kEdibilityDisclaimer));
    expect(find.text(kEdibilityDisclaimer), findsOneWidget);
    expect(find.text('Merkmale'), findsOneWidget);
    expect(find.text(kPhotoDisclaimer), findsNothing);
    expect(find.text('Bilder'), findsNothing);
  });

  testWidgets('kein Bild am Seitenkopf — erst die Warnung, dann das Bild',
      (tester) async {
    // **Die Entscheidung, die beide Bildarten trägt.** Seit 1.170.0 gibt
    // es Porträts, aber NICHT über der Einstufung: Ein Bild am Seitenkopf
    // läse sich als „so sieht er aus, das genügt" — genau die Erwartung,
    // die der Hinweis darunter zurücknimmt.
    final (backend, _) = loggedInBackend();
    await pumpApp(tester, backend);
    await openSpecies(tester, 'Perlpilz');

    // Gemessen statt gezählt: Es gibt Bilder auf dieser Seite — aber
    // KEINES über der Einstufung. Ein bloßes „findsNothing" wäre auch
    // dann grün, wenn es überhaupt keine gäbe.
    final images = find.byType(Image);
    expect(images, findsWidgets);
    final card = tester.getTopLeft(find.byKey(kEdibilityCardKey)).dy;
    for (var i = 0; i < images.evaluate().length; i++) {
      expect(tester.getTopLeft(images.at(i)).dy, greaterThan(card),
          reason: 'ein Bild steht über der Einstufung');
    }
  });
}
