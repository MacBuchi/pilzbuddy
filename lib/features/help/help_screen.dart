// Die Kurzanleitung (#350, Baustein A).
//
// **Warum ein Bildschirm aus Widgets und keine mitgelieferte Textdatei.**
// „Was ist neu" liest `CHANGELOG.md` als Asset, und dieselbe Mechanik
// hätte hier nahegelegen. Sie kann aber genau das nicht, worauf es einer
// Anleitung ankommt: das ECHTE Symbol zeigen. Wer „Ebenen" sucht, sucht
// ein Bild, keine Beschreibung eines Bildes — und dieselben Icons, die
// hier stehen, stehen auf der Karte. Zweiter Grund: Eine `.md` unter
// `assets/` liegt im Binary, wäre für den Version Guard aber eine
// `*.md`-Datei und damit von der Bump-Pflicht ausgenommen — genau die
// Falle, die CLAUDE.md für `CHANGELOG.md` beschreibt.
//
// **Der Umfang ist die Entscheidung.** Erklärt wird, was man nicht
// erraten kann; alles Übrige findet man beim Benutzen. Sechs Abschnitte
// sind die Obergrenze — eine Anleitung, die man scrollen muss, liest
// niemand zu Ende.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/mushroom_species.dart';
import '../../core/widgets/mushroom_icon.dart';
import '../../core/widgets/safety_note.dart';
import '../tour/widgets/tour_icon.dart';
import 'map_tour.dart';

/// Ein Abschnitt der Anleitung: Symbol, Überschrift, ein bis drei Sätze.
class HelpStep {
  const HelpStep({required this.icon, required this.title, required this.text});

  /// Bewusst ein Widget und kein `IconData`: Der Pilz und der Wanderer
  /// mit Korb sind gezeichnet, nicht aus Material entnommen.
  final Widget icon;
  final String title;
  final String text;
}

/// Die Abschnitte der Kurzanleitung.
///
/// **Offen und nicht als lokale `const` in `build`**, damit
/// `help_texts_test.dart` einen EINZELNEN Abschnitt prüfen kann statt
/// die Datei als Text. Der Unterschied ist keine Kosmetik: Die Prüfung
/// „die Spot-Erklärung nennt das Blatt" war über die ganze Datei aus dem
/// falschen Grund grün — „Blatt" steht auch im Unterwegs-Abschnitt.
/// Dieselbe Form wie `kMapTourSteps`.
const kHelpSteps = <HelpStep>[
  HelpStep(
    icon: Icon(Icons.add_location_alt, color: AppColors.forestGreen),
    title: 'Einen Spot anlegen',
    // **Der Satz war seit #407 falsch.** Er endete auf „Gespeichert
    // wird genau der Punkt unter dem Fadenkreuz" — seither lässt
    // sich die Stelle im Blatt aber noch verschieben, und „Meine
    // Position" legt sie auf den eigenen Standort. Eine Anleitung,
    // die eine Möglichkeit ausdrücklich ausschließt, die es gibt,
    // ist schlimmer als eine, die sie verschweigt.
    //
    // „Vorbelegt" statt „zwei Optionen": Ein Umschalter ist es
    // nicht (`spot_position_field.dart`), und wer einen sucht,
    // findet keinen.
    text: 'Tipp unten rechts auf „Neuer Spot". Vorbelegt ist die Stelle '
        'unter dem Fadenkreuz in der Kartenmitte — nicht dein Standort. '
        'Im Blatt kannst du sie auf der kleinen Karte noch genau '
        'schieben oder mit „Meine Position" auf deinen Standort legen.',
  ),
  HelpStep(
    icon: MushroomIcon(
        seed: 7, size: 24, group: SpeciesGroup.roehrlinge, ground: false),
    title: 'Fund und Leergang eintragen',
    // **Wozu der Leergang gut ist, stand nirgends** (Betreiber,
    // 2026-09-10: „eigener Nutzen hat Vorrang … und zur
    // Verbesserung der Pilzampel"). Ohne das Wozu klingt er nach
    // Buchführung, die die App einem aufträgt.
    //
    // **Der Ampel-Halbsatz sagt MESSEN, nicht füttern**, und das
    // ist keine Wortklauberei: Die eigenen Einträge fließen
    // ausdrücklich NICHT in die Rechnung — #199 hebt sie als
    // unabhängigen Prüfstein auf, und wer sie einrechnet, kann mit
    // ihnen nicht mehr prüfen, ob die Rechnung stimmt
    // (`docs/artenkarte-konzept.md`). „Verbessern" bleibt trotzdem
    // wahr: Was man nicht messen kann, kann man auch nicht
    // verbessern. Der Zweck steht seit 1.134.0 in
    // `web/datenschutz.html`.
    text: 'Tipp einen Spot an, um ihn zu öffnen. „Fund eintragen" hält '
        'fest, was du gefunden hast, „Nichts gefunden" den Leergang. '
        'Erst beide zusammen ergeben die Fundhistorie eines Spots — '
        'fünfmal da gewesen und einmal fündig ist etwas anderes als '
        'einmal da gewesen und einmal fündig; an ihr misst sich auch, '
        'ob die Pilzampel recht hat.',
  ),
  HelpStep(
    icon: Icon(Icons.layers_outlined, color: AppColors.warmBrown),
    title: 'Was die Karte zeigt',
    text: 'Hinter „Ebenen" liegen Waldtypen, Höhenlinien, Regen und die '
        'Pilzampel. Die kleine Zahl am Knopf sagt, wie viele gerade an '
        'sind; was ihre Farben bedeuten, steht links unten in der '
        'Legende — ein Tipp klappt sie ein und wieder aus. Mit '
        '„Filter" blendest du Spots nach Art oder Zeit aus.',
  ),
  HelpStep(
    icon: TourIcon(size: 24),
    title: 'Unterwegs',
    text: 'Die Pilztour zeichnet deinen Weg auf. Beendest du sie, fragt '
        'sie dich, wo du gesucht und nichts gefunden hast — auch das '
        'gehört zur Geschichte eines Spots. Im selben Blatt teilst du '
        'deinen Standort für ein paar Stunden mit Buddies.',
  ),
  HelpStep(
    icon: Icon(Icons.group_outlined, color: AppColors.forestGreen),
    title: 'Mit Buddies teilen',
    text: 'Unter „Freunde" suchst du nach Benutzername oder E-Mail. Ob '
        'deine Spots geteilt werden — und ob mit Art und Anzahl — '
        'entscheidest du im Profil, und für einzelne Spots im Spot '
        'selbst.',
  ),
  HelpStep(
    icon: Icon(Icons.wifi_off, color: AppColors.warmBrown),
    title: 'Ohne Empfang',
    text: 'Deine Spots liest die App auch offline. Neue Spots und Funde '
        'wandern in einen Ausgangskorb und gehen los, sobald du wieder '
        'Empfang hast. Damit auch die Karte etwas zeigt, lädst du im '
        'Profil unter „Offline-Karten" deine Region herunter — am '
        'besten zu Hause im WLAN.',
  ),
];

/// Zeigt in wenigen Schritten, wie PilzBuddy benutzt wird.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    return Scaffold(
      appBar: AppBar(title: const Text('Kurzanleitung')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Das Wichtigste in sechs Schritten. Alles andere findest du '
            'beim Ausprobieren.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 12),
          // Dauerhaft nachlesbar (#110). Ganz oben und nicht am Ende:
          // Wer die Kurzanleitung öffnet, soll ihn nicht erst finden
          // müssen.
          const SafetyNoteTile(),
          const SizedBox(height: 12),
          for (final step in kHelpSteps) _StepTile(step: step),
          const SizedBox(height: 24),
          // Der Wiederaufruf der Tour (#350). Er steht HIER und nicht als
          // eigener Eintrag im Profil: Wer die Tour sucht, sucht eine
          // Erklärung — und die Kurzanleitung ist der Ort, an dem er
          // ohnehin landet. Ein zweiter Profil-Eintrag daneben wäre
          // dieselbe Antwort ein zweites Mal.
          //
          // Die Karte muss dafür sichtbar werden: Die Tour hängt an den
          // Ankern des Karten-Screens und zeigt sonst nichts.
          OutlinedButton.icon(
            onPressed: () {
              ref.read(mapTourProvider.notifier).start();
              context.go('/');
            },
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Tour auf der Karte zeigen'),
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step});

  final HelpStep step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Feste Breite statt eines ListTile-`leading`: Der gezeichnete
          // Pilz bringt seine eigene Kantenlänge mit, und ohne Rahmen
          // stünden die Überschriften unterschiedlich weit eingerückt.
          SizedBox(width: 32, child: Center(child: step.icon)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(step.text,
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
