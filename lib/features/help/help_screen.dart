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
import '../tour/widgets/tour_icon.dart';
import 'map_tour.dart';

/// Ein Abschnitt der Anleitung: Symbol, Überschrift, ein bis drei Sätze.
class _Step {
  const _Step({required this.icon, required this.title, required this.text});

  /// Bewusst ein Widget und kein `IconData`: Der Pilz und der Wanderer
  /// mit Korb sind gezeichnet, nicht aus Material entnommen.
  final Widget icon;
  final String title;
  final String text;
}

/// Zeigt in wenigen Schritten, wie PilzBuddy benutzt wird.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const steps = <_Step>[
      _Step(
        icon: Icon(Icons.add_location_alt, color: AppColors.forestGreen),
        title: 'Einen Spot anlegen',
        text: 'In der Mitte der Karte sitzt ein kleines Fadenkreuz. Schieb '
            'die Karte, bis es auf deiner Stelle liegt, und tipp unten '
            'rechts auf „Neuer Spot". Gespeichert wird genau der Punkt '
            'unter dem Fadenkreuz — nicht dein Standort.',
      ),
      _Step(
        icon: MushroomIcon(
            seed: 7, size: 24, group: SpeciesGroup.roehrlinge, ground: false),
        title: 'Fund und Leergang eintragen',
        text: 'Tipp einen Spot an, um ihn zu öffnen. „Fund eintragen" hält '
            'fest, was du gefunden hast. „Nichts gefunden" hält fest, dass '
            'du da warst und nichts da war — das gehört zur Geschichte '
            'eines Spots genauso.',
      ),
      _Step(
        icon: Icon(Icons.layers_outlined, color: AppColors.warmBrown),
        title: 'Was die Karte zeigt',
        text: 'Hinter „Ebenen" liegen Waldtypen, Höhenlinien, Regen und die '
            'Pilzampel. Die kleine Zahl am Knopf sagt, wie viele gerade an '
            'sind; welche das sind, steht links unten. Mit „Filter" '
            'blendest du Spots nach Art oder Zeit aus.',
      ),
      _Step(
        icon: TourIcon(size: 24),
        title: 'Unterwegs',
        text: 'Die Pilztour zeichnet deinen Weg auf und schlägt dir am Ende '
            'vor, an welchen Spots du „nichts gefunden" buchst. Daneben '
            'kannst du deinen Standort für ein paar Stunden mit Buddies '
            'teilen.',
      ),
      _Step(
        icon: Icon(Icons.group_outlined, color: AppColors.forestGreen),
        title: 'Mit Buddies teilen',
        text: 'Unter „Freunde" suchst du nach Benutzername oder E-Mail. Ob '
            'deine Spots geteilt werden — und ob mit Art und Anzahl — '
            'entscheidest du im Profil, und für einzelne Spots im Spot '
            'selbst.',
      ),
      _Step(
        icon: Icon(Icons.wifi_off, color: AppColors.warmBrown),
        title: 'Ohne Empfang',
        text: 'Deine Spots liest die App auch offline. Neue Spots und Funde '
            'wandern in einen Ausgangskorb und gehen los, sobald du wieder '
            'Empfang hast. Damit auch die Karte etwas zeigt, lädst du im '
            'Profil unter „Offline-Karten" deine Region herunter — am '
            'besten zu Hause im WLAN.',
      ),
    ];

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
          const SizedBox(height: 8),
          for (final step in steps) _StepTile(step: step),
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

  final _Step step;

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
