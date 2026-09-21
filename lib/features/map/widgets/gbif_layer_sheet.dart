// Blatt zur Fundorte-Ebene (#467): Schalter, was die Scheiben sagen,
// Abdeckung je Land, Farben je Ampel-Gruppe, Quelle.
//
// Hinter dem › des Ebenen-Blatts wie Wald und Gelände. Was hier steht,
// ist die EINSCHRÄNKUNG der Aussage — und die gehört an die Ebene, nicht
// in eine Hilfeseite: „gemeldet" heißt nicht „wächst", und keine Scheibe
// heißt „keine Meldung", nicht „nichts da".
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../gbif_fill.dart';
import '../gbif_finds_providers.dart';
import '../spot_filter.dart' show spotFilterProvider;
import 'ampel_class_chips.dart';

Future<void> showGbifLayerSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _GbifLayerSheet(),
    );

class _GbifLayerSheet extends ConsumerWidget {
  const _GbifLayerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(gbifLayerEnabledProvider);
    final classFiltered = ref.watch(spotFilterProvider).classes.isNotEmpty;
    // Wie beim Wald: Das Asset wird HIER zum ersten Mal angefasst, nicht
    // am Knopf. Wer das Blatt öffnet, will die Ebene; dafür darf es
    // 0,6 MB kosten.
    final findsAsync = ref.watch(gbifFindsProvider);
    final finds = findsAsync.valueOrNull;
    final missing = findsAsync.hasValue && finds == null;
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall?.copyWith(color: theme.hintColor);

    String number(int n) {
      final s = n.toString();
      final out = StringBuffer();
      for (var i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) out.write(' ');
        out.write(s[i]);
      }
      return out.toString();
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.66,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text('Gemeldete Fundorte',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: theme.colorScheme.primary)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                // Der ehrliche Satz: Jede Scheibe ist eine Meldung, so
                // groß wie ihre Genauigkeit. Sie sagt nichts darüber, ob
                // dort heute etwas steht — und nichts über Stellen, an
                // denen niemand meldet.
                'Wo Menschen eine unserer Arten bei GBIF gemeldet haben. '
                'Jede Scheibe ist eine Meldung, so groß wie ihre '
                'Genauigkeit: ein Punkt in Deutschland, ein Quadrat in der '
                'Schweiz, ein Rasterpunkt in Österreich. Keine Scheibe '
                'heißt „keine Meldung", nicht „nichts da".',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  SwitchListTile(
                    title: const Text('Fundorte einblenden'),
                    subtitle: missing
                        ? const Text('Die Fundorte lassen sich nicht laden '
                            '— ohne sie gibt es keine Ebene')
                        : const Text('Folgt dem Kartenfilter: Art und '
                            'Ampel-Gruppe'),
                    value: enabled && !missing,
                    onChanged: missing
                        ? null
                        : (value) => ref
                            .read(gbifLayerEnabledProvider.notifier)
                            .set(value),
                  ),
                  const Divider(height: 16),
                  // Die Gruppen als Chips (seit 1.155.0) — mit den Farben
                  // aus derselben Tabelle wie beim Malen, damit Blatt und
                  // Fläche nie zwei Töne zeigen. Es ist DIE Auswahl des
                  // Kartenfilters, kein eigener Wähler (#154): Was hier
                  // weg ist, ist auch für die Ampel weg, und die Karte
                  // sagt es.
                  const AmpelClassChips(
                    intro: 'Welche Gruppen die Karte zeigt — dieselbe '
                        'Auswahl wie im Kartenfilter, sie gilt auch für '
                        'die Ampel:',
                    withColours: true,
                  ),
                  const _ColourRow(
                      colour: null, label: 'Arten ohne Ampel'),
                  // Eine Art ohne Gruppe hat keinen Chip: Sobald eine
                  // Gruppe abgewählt ist, fällt sie mit heraus — wie
                  // beim Ampel-Filter der Spots. Das steht hier, statt
                  // die grauen Scheiben still verschwinden zu lassen.
                  if (classFiltered)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(44, 0, 20, 4),
                      child: Text(
                        'ausgeblendet, solange eine Gruppe abgewählt ist',
                        style: hint,
                      ),
                    ),
                  if (finds != null) ...[
                    const Divider(height: 16),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text(
                        // Die Abdeckung je Land — sonst sähe die dünne
                        // Punktdecke in Österreich nach einem Fehler
                        // aus. Die Schweiz ist flächig, aber grob.
                        '${number(finds.observations)} Meldungen an '
                        '${number(finds.length)} Orten · '
                        '${[
                          for (final e in finds.countries.entries)
                            '${e.key} ${number(e.value)}'
                        ].join(' · ')}',
                        style: hint,
                      ),
                    ),
                  ],
                  // Die Quelle SCROLLT MIT (seit 1.155.0): Als fester
                  // Fuß unter der Liste nahm sie ihr auf einem Telefon
                  // ein Drittel der Höhe, und die Chips lagen hinter
                  // ihr — gemessen im Flow-Test: Liste 192 px, Chips
                  // 18 px darunter, ein Tipp traf den Fußtext.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Text(
                      // CC-BY-Pflicht und Herkunft: Die Quell-Datensätze
                      // einzeln stehen auf der Lizenzseite.
                      'Daten: GBIF-Meldungen unter CC0 und CC BY 4.0, Stand '
                      '${finds?.fetchedOn ?? '2026-09-16'}'
                      '${finds?.doi == null ? '' : ' (doi.org/${finds!.doi})'}. '
                      'Quell-Datensätze unter „Über PilzBuddy" → Lizenzen.',
                      style: hint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Eine Farbzeile der Legende dieses Blatts.
class _ColourRow extends StatelessWidget {
  const _ColourRow({required this.colour, required this.label});

  final Color? colour;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: (colour ?? gbifClassColour(null)).withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(label, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
