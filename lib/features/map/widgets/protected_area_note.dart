// Der Hinweis beim Eintragen, wenn die Stelle in einem Schutzgebiet
// liegt (#580) — im Blatt „Neuer Spot" und im Blatt „Fund eintragen".
//
// **Ein Satz, keine Sperre, keine Rückfrage** (Betreiber, 2026-09-23:
// „keine Bevormundung"). Wer einträgt, war schon da; der Hinweis ändert
// nichts daran, was gespeichert wird.
//
// **„Wahrscheinlich" und „meist" stehen mit Absicht da.** Die Waben sind
// 250 m groß und Randwaben zählen mit, am Rand kann die Stelle also knapp
// draußen liegen. Und ob Sammeln in einem bestimmten Gebiet verboten
// ist, regelt dessen Verordnung — die kennt die App nicht, die
// Beschilderung vor Ort schon. Eine Rechtsauskunft wäre eine Behauptung,
// die niemand geprüft hat.
//
// **Schweigen heißt NICHT „erlaubt".** Die Daten decken Deutschland,
// Österreich und die Schweiz ab (samt Liechtenstein), in den
// Nachbarländern gibt es keine. Deshalb steht hier nie ein Satz wie
// „kein Schutzgebiet" — der Baustein verschwindet einfach.
//
// **Ausnahme Südtirol** (#623, Zwischenlösung bis zur Antwort der
// Provinz): Dort steht ein Satz, der sagt, WAS fehlt — eigene
// Sammelregeln, keine erfassten Schutzgebiete. Er rät keine Regel und
// nennt kein Gebiet; begründet in `south_tyrol.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../protected_area_providers.dart';
import '../south_tyrol.dart';

const kProtectedAreaNoteKey = Key('protected-area-note');
const kSouthTyrolNoteKey = Key('south-tyrol-note');

class ProtectedAreaNote extends ConsumerWidget {
  const ProtectedAreaNote({super.key, required this.at});

  /// Die Stelle, um die es geht — der Spot oder die Fundstelle.
  final LatLng at;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Beobachten ist laden: Das Blatt ist bewusst geöffnet, dort darf das
    // Asset gelesen werden — einmal je App-Lauf.
    final areas = ref.watch(protectedAreasProvider).valueOrNull;
    final area = areas?.areaAt(at.latitude, at.longitude);
    final theme = Theme.of(context);
    if (area == null) {
      if (!inSouthTyrol(at.latitude, at.longitude)) {
        return const SizedBox.shrink();
      }
      return Padding(
        key: kSouthTyrolNoteKey,
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'In Südtirol gelten eigene Regeln fürs Pilze sammeln '
                '(etwa Sammeltage und Mengen), und Schutzgebiete sind '
                'hier noch nicht erfasst — maßgeblich ist die '
                'Beschilderung vor Ort.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      key: kProtectedAreaNoteKey,
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                // „Schutzgebiet:" und nicht „im …": Der Name kann
                // Kernzone, Schutzzone oder Nationalpark heißen, und
                // „im Kernzone" wäre falsch.
                const TextSpan(text: 'Wahrscheinlich Schutzgebiet: '),
                TextSpan(
                    text: area.label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const TextSpan(
                    text: '. Dort ist Pilze sammeln meist verboten — '
                        'maßgeblich ist die Beschilderung vor Ort.'),
              ]),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
