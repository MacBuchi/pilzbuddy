// Die Erklärtexte der App — Tour, Kurzanleitung, Unterwegs-Blatt.
//
// **Warum es diese Datei gibt.** Beim Umbau von 1.133.1 fiel auf, dass
// die Formulierungen an DREI Stellen stehen und keine einzige davon von
// einem Test gehalten wurde: Man konnte sie ändern, verschlechtern oder
// auseinanderlaufen lassen, ohne dass irgendetwas rot wurde. Genau so ist
// #434 entstanden („Formulierung liest sich komisch") — dieselbe
// verschachtelte Erklärung in drei Fassungen.
//
// Geprüft wird nicht der Wortlaut Zeichen für Zeichen; das wäre ein Test,
// den man bei jeder Verbesserung mitschreibt und der deshalb nichts
// beweist. Geprüft werden die zwei Zusagen, die man wirklich verlieren
// kann: dass alle drei Stellen DASSELBE sagen, und dass die Tour die
// Legende nennt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/widgets/safety_note.dart';
import 'package:pilzbuddy/features/help/help_screen.dart';
import 'package:pilzbuddy/features/help/map_tour.dart';

void main() {
  /// Die drei Stellen, an denen „Unterwegs" erklärt wird.
  const sources = <String, String>{
    'Tour': 'lib/features/help/map_tour.dart',
    'Kurzanleitung': 'lib/features/help/help_screen.dart',
    'Unterwegs-Blatt': 'lib/features/map/widgets/map_trip_sheet.dart',
  };

  /// Die Datei OHNE Kommentarzeilen.
  ///
  /// **Der erste Anlauf las die Rohdatei — und schlug auf dem Kommentar
  /// an, der den alten Wortlaut zitiert.** Das ist die falsche Richtung:
  /// Ein Wächter, der das Zitieren der abgelösten Fassung bestraft,
  /// treibt einen dazu, die Begründung wegzulassen. Geprüft gehört, was
  /// der Nutzer LIEST, nicht was daneben steht.
  ///
  /// Grob, aber für dieses Projekt ausreichend: Der Dart-Code hier
  /// benutzt durchweg `//`, keine `/* */`-Blöcke.
  String read(String path) => File(path)
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  test('Alle drei Erklärungen der Pilztour sagen dasselbe', () {
    // Die gemeinsame Wendung. Sie ist der Kern der Aussage — was die Tour
    // am Ende von dir wissen will —, und sie ist das, was beim
    // Auseinanderlaufen als Erstes verloren geht: Bis 1.133.0 stand an
    // den drei Stellen dreimal etwas anderes.
    //
    // Bewusst eine WENDUNG und nicht der ganze Satz: Die drei Stellen
    // haben verschieden viel Platz, die Tour-Sprechblase am wenigsten.
    // Ein Test auf den vollen Wortlaut erzwänge dieselbe Länge überall
    // und damit den schlechtesten gemeinsamen Nenner.
    for (final entry in sources.entries) {
      expect(read(entry.value), contains('gesucht und nichts gefunden'),
          reason: '${entry.key} erklärt die Pilztour anders als die '
              'anderen beiden');
    }
  });

  test('Keine Erklärung verlangt vom Nutzer, etwas zu „buchen"', () {
    // Der Wortlaut aus #434: „schlägt dir am Ende vor, an welchen Spots
    // du „nichts gefunden" buchst". Zwei Fehler in einem Satz — zwei
    // Sätze ineinandergeschachtelt, und für etwas, das man im Wald tut,
    // ein Wort aus der Buchhaltung.
    //
    // Das SUBSTANTIV „Leergang" bleibt erlaubt: Es steht als Quittung
    // nach dem Eintragen („2 Leergänge eingetragen") und ist damit ein
    // eingeführter Begriff der App. Was hier nicht wiederkommen soll,
    // ist das Verb.
    for (final entry in sources.entries) {
      expect(read(entry.value), isNot(contains('buchst')),
          reason: '${entry.key} lässt den Nutzer wieder „buchen"');
    }
  });

  test('Die Tour nennt die Legende', () {
    // Der Nebensatz aus #436: „Das kann dann natürlich auch in der Tour
    // erklärt werden."
    //
    // **Und zwar im Ebenen-Schritt, nicht in einem eigenen.** Alle vier
    // Ebenen stehen ab Werk aus, und die Tour läuft beim ersten Start —
    // in dem Augenblick gibt es die Legende gar nicht, `MapLegend`
    // liefert ohne aktive Ebene `SizedBox.shrink()`. Ein eigener Schritt
    // zeigte auf leere Fläche; hier steht der Satz dort, wo man die
    // erste Ebene einschaltet.
    final layersStep = kMapTourSteps
        .firstWhere((step) => step.title == 'Was die Karte zeigt');
    expect(layersStep.text, contains('Legende'));
    expect(layersStep.text, contains('links unten'),
        reason: 'ohne den Ort ist der Hinweis eine Suchaufgabe');
    expect(layersStep.text, contains('klappt'),
        reason: 'das Einklappen ist das, was man ohne Hinweis nicht '
            'findet — die ausgeklappte Legende sieht man ja');
  });

  test('Die Spot-Erklärung nagelt die Stelle nicht aufs Fadenkreuz fest', () {
    // **Der Satz war zwei Jahre lang wahr und dann still falsch.** Bis
    // #407 wurde tatsächlich genau der Punkt unter dem Fadenkreuz
    // gespeichert; seither liegt im Blatt eine kleine Karte, auf der er
    // sich verschieben lässt, und „Meine Position" legt ihn auf den
    // eigenen Standort. Der alte Wortlaut schloss beides ausdrücklich
    // aus — eine Anleitung, die eine vorhandene Möglichkeit verneint,
    // ist schlimmer als eine, die sie verschweigt.
    //
    // Geprüft wird beides: dass die alte Absolutform nicht zurückkommt,
    // und dass an ihrer Stelle das Blatt genannt ist.
    //
    // **Geprüft wird der EINZELNE Abschnitt, nicht die Datei.** Der
    // erste Anlauf suchte „Blatt" im ganzen Text — und war damit aus dem
    // falschen Grund grün, weil der Unterwegs-Abschnitt das Wort ohnehin
    // enthält. Dafür liegen die Abschnitte jetzt als `kHelpSteps` offen.
    final texte = {
      'Tour': kMapTourSteps
          .firstWhere((step) => step.title == 'So entsteht ein Spot')
          .text,
      'Kurzanleitung': kHelpSteps
          .firstWhere((step) => step.title == 'Einen Spot anlegen')
          .text,
    };
    for (final entry in texte.entries) {
      expect(entry.value, isNot(contains('Gespeichert wird genau der Punkt')),
          reason: '${entry.key} verneint wieder, was seit #407 geht');
      expect(entry.value, contains('Blatt'),
          reason: '${entry.key} sagt nicht, wo sich die Stelle noch '
              'ändern lässt');
    }
  });

  test('Der Haftungshinweis nennt weiter die Grenze', () {
    // Seit 1.134.0 sagt die erste Hälfte, was die App KANN („verwaltet
    // deine Fundstellen und schätzt, wo es sich gerade lohnen könnte").
    // Genau deshalb steht dieser Test hier: Wer den Satz das nächste Mal
    // anfasst, soll nicht die zweite Hälfte mit wegkürzen. Sie ist der
    // Grund, aus dem es den Hinweis überhaupt gibt (#110).
    expect(kSafetyNote, contains('bestimmt keine Pilze'));
    expect(kSafetyNote, contains('essbar'));
    // Der Konjunktiv ist keine Feinheit: Die Ampel sagt überall sonst
    // „stünde günstig (experimentell)", weil die Rückwärtsvalidierung bei
    // der Arten-Kontrolle durchgefallen ist.
    expect(kSafetyNote, contains('könnte'),
        reason: 'der Haftungshinweis verspricht mehr als das Ampel-Banner');
  });

  test('Was die App über die Ampel-Prüfung sagt, steht auch im Datenschutz',
      () {
    // Die Kurzanleitung sagt seit 1.134.0, an den Leergängen messe sich,
    // „ob die Pilzampel recht hat" — das ist ein ZWECK für die Daten des
    // Nutzers, und ein Zweck gehört in die Erklärung. Dieselbe Regel wie
    // bei einem neuen Netzziel (`privacy_policy_test.dart`), nur eine
    // Ebene höher: dort geht es um das Wohin, hier um das Wozu.
    final leergang = kHelpSteps
        .firstWhere((step) => step.title == 'Fund und Leergang eintragen');
    if (leergang.text.contains('Pilzampel')) {
      expect(File('web/datenschutz.html').readAsStringSync(),
          contains('ob die Pilzampel richtig liegt'),
          reason: 'die App nennt einen Zweck, den die Erklärung nicht kennt');
    }
  });
}
