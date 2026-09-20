// Die Evidenzstufen — N7 des Nachtrags zu Auftrag 2.
//
// Die Stufe begrenzt die Behauptung, sie schafft sie nicht ab: Keine
// Art verliert ihre Ampel, weil sie auf „vorläufig" steht. Geprüft wird
// hier deshalb beides — dass die Stufe ankommt UND dass sie nichts
// verdeckt.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/ampel/ampel_model.dart';

void main() {
  group('Evidenzstufen', () {
    test('jede Art mit Klasse hat eine Stufe, und umgekehrt', () {
      // **Die tragende Zusicherung.** Eine Art mit Klasse und ohne
      // Stufe zeigte eine Ampel ohne Auskunft darüber, was sie wert
      // ist; eine Stufe ohne Klasse wäre eine Aussage über etwas, das
      // nie erscheint.
      expect(ampelEvidenceBySpecies.keys.toSet(),
          equals(ampelSpeciesClass.keys.toSet()));
    });

    test('die Stufen stammen aus der gemessenen Zuordnung', () {
      // Aus `docs/pilzampel-kontrolldesign.md`, Abschnitt „Evidenzstufen
      // nach N1". Die Herbsttrompete steht auf „vorläufig", weil sie mit
      // 147 Funden unter der 150er-Grenze liegt — nicht, weil ihre
      // Zahlen schlecht wären; sie sind die besten der Tabelle.
      expect(ampelEvidenceFor('Herbsttrompete'),
          AmpelEvidence.vorlaeufig);
      // Der Pfifferling seit dem 2026-09-20: Sein Fenster ist auf 14,5 °C
      // GESETZT, nicht per Hold-out belegt — also „vorläufig", obwohl
      // seine 17,5 °C den Hold-out bestanden hatten.
      expect(ampelEvidenceFor('Pfifferling'), AmpelEvidence.vorlaeufig);
      for (final art in const [
        'Steinpilz',
        'Maronenröhrling',
        'Birkenpilz',
        'Fichtenreizker',
      ]) {
        expect(ampelEvidenceFor(art), AmpelEvidence.belegt, reason: art);
      }
    });

    test('vorläufig bleibt die Minderheit', () {
      // **Der Grund für N7s „keine Warnung pro Art".** Fünf Hinweise auf
      // sechs Arten lesen sich wie „kaputt", und dann wird auch der
      // belastbare Teil abgewertet. Nach der Neuvergabe nach N1 war es
      // eine (Herbsttrompete); seit dem 2026-09-20 sind es zwei, weil
      // das Pfifferling-Fenster gesetzt und nicht belegt ist. Wäre es je
      // die Mehrheit, gehört die Darstellung neu entschieden und nicht
      // stillschweigend weitergeführt.
      final vorlaeufig = ampelEvidenceBySpecies.entries
          .where((e) => e.value == AmpelEvidence.vorlaeufig)
          .map((e) => e.key)
          .toSet();
<<<<<<< HEAD
      // Seit 1.151.0 dazu: aus „Austernseitling & Co." die zwei Arten mit
      // Band um die Null, aus „Herbsttrompete & Co." der Semmelstoppelpilz.
      expect(vorlaeufig, {
        'Herbsttrompete',
        'Pfifferling',
        'Rehbrauner Dachpilz',
        'Krause Glucke',
        'Semmelstoppelpilz',
      });
=======
      expect(vorlaeufig, {'Herbsttrompete', 'Pfifferling'});
>>>>>>> origin/main
      expect(vorlaeufig.length * 2, lessThan(ampelEvidenceBySpecies.length),
          reason: 'die Minderheit — sonst ist die Darstellung neu zu entscheiden');
    });

    test('Arten ohne Ampel haben keine Stufe', () {
      // Hallimasch und Co. stehen nach Phase 1.5 auf „keine Aussage" —
      // sie zeigen aber gar keine Ampel, also gibt es hier nichts
      // einzuordnen. Eine Stufe für sie wäre eine Aussage über eine
      // Zeile, die nie erscheint.
      // Austernseitling, Judasohr und Samtfußrübling standen bis 1.150.0
      // hier — seit „Austernseitling & Co." haben sie eine Klasse.
      for (final art in const ['Hallimasch', 'Stockschwämmchen']) {
        expect(ampelClassFor(art), isNull, reason: art);
        expect(ampelEvidenceFor(art), isNull, reason: art);
      }
      expect(ampelEvidenceFor(null), isNull);
      expect(ampelEvidenceFor('Gibt es nicht'), isNull);
    });

    test('die Schreibweise der Art entscheidet nicht', () {
      // Derselbe Weg wie bei der Klasse: über `canonicalSpecies`. Sonst
      // fiele ein Fund mit abweichender Schreibweise aus der Stufe,
      // während seine Ampel weiterläuft.
      expect(ampelEvidenceFor('steinpilz'), AmpelEvidence.belegt);
      expect(ampelEvidenceFor('  Steinpilz  '), AmpelEvidence.belegt);
    });

    test('jede Stufe hat ein Wort, und es ist keine Warnung', () {
      expect(ampelEvidenceWord(AmpelEvidence.belegt), 'gut belegt');
      expect(ampelEvidenceWord(AmpelEvidence.vorlaeufig),
          'unsichere Datenlage');
      // Kein Ausrufezeichen, kein „Achtung", kein „nicht" — die Zeile
      // ist eine Auskunft und keine Warnung (N7).
      for (final wort in AmpelEvidence.values.map(ampelEvidenceWord)) {
        expect(wort, isNot(contains('!')));
        expect(wort.toLowerCase(), isNot(contains('achtung')));
        expect(wort.toLowerCase(), isNot(contains('warn')));
      }
    });

    test('die Bezugsmenge und der Hebel stehen im Fließtext', () {
      // **Betreiberauflage vom 2026-09-19.** Ohne die Bezugsmenge
      // bedeutet „günstig" nichts Bestimmtes, und ohne den Hebel klingt
      // es nach einer Zusage. Beides gehört neben die Evidenzstufe,
      // nicht in eine Fußnote — geprüft wird deshalb, dass es im
      // Feature-Satz steht und nicht bloß irgendwo im Code.
      final quelle = File('lib/features/spots/widgets/ampel_section.dart')
          .readAsStringSync();
      final satz = quelle
          .split("'Bewertet Bedingungen, nicht Vorkommen")
          .last
          .split(';')
          .first;
      expect(satz, contains('jeder fünfte Tag der Saison'),
          reason: 'die Bezugsmenge fehlt — dann ist „günstig" keine '
              'bestimmte Aussage mehr');
      expect(satz, contains('1,3-mal'),
          reason: 'der Hebel fehlt — er ist die ehrliche Größe hinter '
              'der Anzeige');
      expect(satz, isNot(contains('%')),
          reason: 'Prozente stehen nirgends im Blatt (#298)');
    });

    testWidgets('die Stufe steht in der Fakten-Zeile der Art',
        (tester) async {
      // Der Text wird hier direkt gebaut, weil die volle
      // `AmpelSection` an sechs Providern hängt — geprüft wird die
      // Zusicherung, dass Wort und Feld zusammenkommen.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Text(
            'Belege: ${ampelEvidenceWord(ampelEvidenceFor('Herbsttrompete')!)}',
          ),
        ),
      ));
      expect(find.text('Belege: unsichere Datenlage'), findsOneWidget);
    });
  });
}
