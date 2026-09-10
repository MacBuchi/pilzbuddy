import 'package:flutter/material.dart';

import '../app_colors.dart';

/// Der Satz, um den es geht (#110).
///
/// **Er steht an EINER Stelle**, weil er sonst an zweien auseinanderläuft:
/// Der Hinweis beim ersten Start und die Zeile in der Kurzanleitung sind
/// dieselbe Aussage, und eine Pilz-App darf sie nicht in zwei Fassungen
/// führen.
///
/// Der Wortlaut ist bewusst nüchtern und nennt den einen Fall, der zählt
/// — essen. „Vorsicht bei der Bestimmung" wäre ein Ratschlag; das hier
/// ist eine Auskunft darüber, was die App NICHT tut.
///
/// **Die erste Hälfte sagt seit 1.134.0, was die App SEHR WOHL tut**
/// (Betreiber: „vielleicht irgendwie so mit reinbringen"). „Die App
/// merkt sich, wo du etwas gefunden hast" verkaufte sie unter Wert —
/// gemerkt hätte es auch ein Notizzettel. Der Kontrast trägt den Satz
/// trotzdem weiter: erst was sie kann, dann der Gedankenstrich, dann
/// die Grenze.
///
/// **„lohnen KÖNNTE", nicht „lohnt".** Die Ampel sagt an jeder anderen
/// Stelle der App „stünde günstig (experimentell)", weil die
/// Rückwärtsvalidierung bei der Arten-Kontrolle durchgefallen ist.
/// Ausgerechnet im Haftungshinweis fester zu formulieren als im Banner
/// wäre die falsche Stelle für Zuversicht.
const kSafetyNote =
    'PilzBuddy bestimmt keine Pilze. Die App verwaltet deine Fundstellen '
    'und schätzt, wo es sich gerade lohnen könnte — sie sagt dir nicht, '
    'was es ist und ob es essbar ist. Was in deinem Korb landet, '
    'entscheidest du; im Zweifel hilft eine Pilzberatung.';

/// Die Zeile für dauerhafte Orte (Kurzanleitung).
///
/// Kein Dialog und kein Ausrufezeichen: Wer hier liest, sucht ohnehin
/// eine Erklärung. Auffällig genug durch die Farbe, unaufdringlich genug,
/// um nicht zur Tapete zu werden.
class SafetyNoteTile extends StatelessWidget {
  const SafetyNoteTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warmBrown.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(kSafetyNote,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// Der einmalige Hinweis beim ersten Start.
///
/// **Einmal je Installation**, gerätelokal gemerkt — dieselbe Abwägung
/// wie bei der Karten-Tour (#350). Ein Hinweis, den man täglich wegklickt,
/// wird zur Tapete; einer, den man einmal bewusst bestätigt, bleibt
/// hängen. Nachlesbar bleibt er in der Kurzanleitung.
Future<void> showSafetyNoteDialog(BuildContext context) => showDialog<void>(
      context: context,
      // Nicht wegtippbar: Ein Hinweis, der sich durch einen Fehlgriff
      // neben den Dialog schließt, ist nicht gezeigt worden.
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Kurz vorweg'),
        content: const Text(kSafetyNote),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
