// Beispiele für die Reiter-Touren (#596) — was ein Konto ohne Spots,
// Buddys oder Fotos während der Tour statt der leeren Liste sieht.
//
// **Warum überhaupt.** Die Spot-Tour zeigt an der ersten Zeile, was eine
// Zeile kann. Ohne Spot fielen diese Schritte weg, und von der Tour blieb
// das Suchfeld (Betreiber, 2026-09-25: „was tun, wenn der Nutzer gar
// keinen Spot und Freund hat und keine Fotos geteilt sind? Er sollte ja
// dennoch einen Eindruck bekommen").
//
// Drei Dinge, die man wissen muss:
//
// - **Gezeichnet, nie gespeichert.** Kein `Spot`, kein `Find`, keine
//   `Friendship`: Die Beispiele sind Widgets aus festen Texten und gehen
//   durch keinen Provider, keinen Cache und keine Datenbank. Ein
//   Beispiel-Spot als echtes Modell käme sonst in Statistik, Ampel oder
//   GPX-Export an — genau die Stellen, an denen ein erfundener Fund
//   schadet.
// - **Immer als „Beispiel" gekennzeichnet**, auch für den Bildschirmleser.
//   Wer nach der Tour einen Spot „Buchenhang" sucht, hat sonst etwas
//   gesehen, das es nicht gibt.
// - **Nur solange die Tour läuft, und nur, wo Echtes fehlt**
//   (`coachExamplesProvider`). Mit dem ersten eigenen Spot ist das
//   Beispiel weg, und die Tour zeigt die echte Zeile — die Anker sind
//   dieselben.
import 'package:flutter/material.dart';

import '../../core/widgets/mushroom_avatar.dart';
import '../../core/widgets/mushroom_icon.dart';
import '../coach/coach.dart';
import 'tab_tours.dart';

const kTourExampleBadgeKey = Key('tour-example-badge');
const kExampleSpotKey = Key('tour-example-spot');
const kExampleSpotSheetKey = Key('tour-example-spot-sheet');
const kExampleBuddyKey = Key('tour-example-buddy');
const kExampleGalleryKey = Key('tour-example-gallery');

/// Das Schild „Beispiel".
class TourExampleBadge extends StatelessWidget {
  const TourExampleBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: kTourExampleBadgeKey,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('Beispiel',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onTertiaryContainer)),
    );
  }
}

// Ein Tipp tut nichts: Während der Tour schluckt die Überlagerung ihn
// ohnehin, und danach ist das Beispiel weg. Ein `null` machte die Knöpfe
// grau — dann sähe das Beispiel anders aus als das Echte.
void _nothing() {}

/// Die Beispielzeile im Reiter „Spots" — gebaut wie `_SpotTile`.
class ExampleSpotTile extends StatelessWidget {
  const ExampleSpotTile({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CoachAnchor(
      id: SpotsCoach.row,
      child: Padding(
        key: kExampleSpotKey,
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MushroomIcon.forSpecies('Steinpilz',
                fallbackSeed: 'tour-example', size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Buchenhang',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium),
                      ),
                      Text('vor 3 Tagen', style: theme.textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('Steinpilz, 3 Stück',
                      style: theme.textTheme.bodyMedium),
                  // Das Schild in der kleinen Zeile, nicht neben dem Namen:
                  // Dort teilte es sich die Breite mit dem Datum, und auf
                  // 360 dp lief die Zeile über (im Test gesehen).
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        const TourExampleBadge(),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text('3 Einträge',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.hintColor)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const CoachAnchor(
              id: SpotsCoach.rowMap,
              child: IconButton(
                icon: Icon(Icons.map_outlined),
                tooltip: 'Auf der Karte zeigen',
                onPressed: _nothing,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Öffnet das Beispiel-Blatt; gibt zurück, wie es zu schließen ist —
/// die Form einer Tour-Szene.
VoidCallback showExampleSpotSheet(BuildContext context) {
  final navigator = Navigator.of(context);
  var open = true;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ExampleSpotSheet(),
  ).whenComplete(() => open = false);
  return () {
    if (open) navigator.pop();
  };
}

class _ExampleSpotSheet extends StatelessWidget {
  const _ExampleSpotSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall?.copyWith(color: theme.hintColor);
    Widget entry(String label, String when, {bool blank = false}) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: blank
              ? Icon(Icons.search_off, color: theme.disabledColor)
              : MushroomIcon.forSpecies('Steinpilz',
                  fallbackSeed: 'tour-example'),
          title: Text(label,
              style: blank ? TextStyle(color: theme.hintColor) : null),
          subtitle: Text(when),
        );
    return Padding(
      key: kExampleSpotSheetKey,
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text('Buchenhang',
                    style: theme.textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              const TourExampleBadge(),
            ],
          ),
          const SizedBox(height: 4),
          Text('So sieht ein Spot aus, sobald du einen angelegt hast.',
              style: hint),
          const SizedBox(height: 8),
          entry('Steinpilz, 3 Stück', 'vor 3 Tagen'),
          entry('Nichts gefunden', 'vor 10 Tagen', blank: true),
          entry('Steinpilz, 5 Stück', 'letzten Herbst'),
          const SizedBox(height: 8),
          CoachAnchor(
            id: SpotsCoach.sheetEntries,
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _nothing,
                    icon: const Icon(Icons.add),
                    label: const Text('Fund eintragen'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _nothing,
                    icon: const Icon(Icons.search_off, size: 18),
                    label: const Text('Nichts gefunden'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Der Beispiel-Buddy unter „Meine Buddys".
class ExampleBuddyTile extends StatelessWidget {
  const ExampleBuddyTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const ListTile(
      key: kExampleBuddyKey,
      contentPadding: EdgeInsets.zero,
      leading: MushroomAvatar(index: 3, size: 40),
      title: Row(
        children: [
          Flexible(
              child: Text('Waldläuferin', overflow: TextOverflow.ellipsis)),
          SizedBox(width: 8),
          TourExampleBadge(),
        ],
      ),
      subtitle: Text('So steht ein Buddy da, sobald ihr verbunden '
          'seid.'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CoachAnchor(
            id: BuddysCoach.alias,
            child: IconButton(
              tooltip: 'Alias vergeben',
              icon: Icon(Icons.edit_outlined),
              onPressed: _nothing,
            ),
          ),
          CoachAnchor(
            id: BuddysCoach.message,
            child: IconButton(
              tooltip: 'Nachrichten',
              icon: Icon(Icons.chat_bubble_outline),
              onPressed: _nothing,
            ),
          ),
        ],
      ),
    );
  }
}

/// Die Beispiel-Galerie über den Buddys — mit eigenen Aufnahmen aus den
/// Artbildern, also nichts, was ein Buddy geteilt hätte.
class ExampleFindPhotoGallery extends StatelessWidget {
  const ExampleFindPhotoGallery({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tile(String asset, String species, double left) => SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(asset,
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                    semanticLabel: '$species, Beispielfoto'),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 18,
                  height: 18,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                  ),
                  child: CircularProgressIndicator(
                    value: left,
                    strokeWidth: 2.5,
                    backgroundColor: theme.colorScheme.outlineVariant,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        );
    return Column(
      key: kExampleGalleryKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Fundfotos', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            const TourExampleBadge(),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Hier stehen die Fotos, die du und deine Buddys zu Funden teilen.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            tile('assets/species/steinpilz-1.webp', 'Steinpilz', 0.8),
            tile('assets/species/maronenroehrling-1.webp', 'Maronenröhrling',
                0.35),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
