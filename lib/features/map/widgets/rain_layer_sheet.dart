import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../../ampel/ampel_map_providers.dart';
import '../../ampel/ampel_providers.dart';
import '../rain_data_providers.dart';
import '../rain_fill.dart';
import '../rain_layer.dart';
import 'map_legend.dart';

/// Blatt zur Wahl der Regenebene (#156).
///
/// Hinter einem Knopf statt als dauerhafte Leiste — dieselbe Begründung
/// wie beim Filter-Blatt: Die Karte ist der Inhalt, und eine Leiste über
/// ihr kostet auf jedem Bildschirm Höhe, auch bei allen, die nie Regen
/// einblenden.
Future<void> showRainLayerSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _RainLayerSheet(),
    );

class _RainLayerSheet extends ConsumerWidget {
  const _RainLayerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(rainLayerProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        // Höchstens zwei Drittel: Die Karte soll hinter dem Blatt sichtbar
        // bleiben, damit man die Wirkung der Wahl sofort sieht.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.66,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text('Regen',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: theme.colorScheme.primary)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                // Kein Urteil, sondern Messwerte — die Ampel kommt erst,
                // wenn sie sich an echten Funden bewährt hat.
                'Messwerte des Deutschen Wetterdienstes. Wie viel Regen '
                'gefallen ist und wann — den Rest weißt du besser.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  // Einzeilig, und die Erläuterung steht nur zur
                  // gewählten Ebene darunter: Mit Untertitel an jedem
                  // Eintrag rutschte „Letzte 30 Tage" auf kleinen
                  // Bildschirmen aus dem Blatt — ausgerechnet der
                  // Eintrag, für den es dieses Blatt gibt.
                  for (final layer in RainLayer.values)
                    ListTile(
                      // Von Hand statt RadioListTile: Dessen `groupValue`
                      // und `onChanged` sind zugunsten eines
                      // RadioGroup-Vorfahren abgekündigt, den das in CI
                      // gepinnte Flutter noch nicht kennt. Ein Häkchen
                      // tut hier dasselbe.
                      leading: Icon(
                        layer == current
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: layer == current
                            ? AppColors.friendBlue
                            : theme.hintColor,
                      ),
                      title: Text(layer.label),
                      selected: layer == current,
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      // Seit #232 OHNE Wald-Abschaltung: Der Regen liegt
                      // ÜBER der Waldfläche, und die Teil-Ebenen im
                      // Wald-Blatt halten die Kombination lesbar. Seit
                      // 1.76.0 gilt das auch für die Ampel — sie IST
                      // die Waldfläche, es gibt keine zweite Fläche
                      // mehr, die sich mit dem Regen beißen könnte.
                      onTap: () =>
                          ref.read(rainLayerProvider.notifier).set(layer),
                    ),
                  if (ref.watch(ampelPreviewEnabledProvider)) ...[
                    const Divider(height: 16),
                    // Die Umgebungs-Frage der Ampel-Vorschau: „Wo lohnt
                    // sich der Wald gerade?" Seit 1.76.0 färbt sie NUR
                    // den Wald ein (Betreiber: „es gibt keinen Grund,
                    // warum man andere Bereiche damit einfärben
                    // sollte") — also ein Modus der Waldfläche, kein
                    // eigenes Bild. Nur sichtbar mit dem
                    // Experimentell-Schalter im Profil.
                    SwitchListTile(
                      dense: true,
                      title:
                          const Text('Pilzwetter-Ampel (experimentell)'),
                      // Der Höhen-Satz ist kein Beiwerk: Die Temperatur
                      // ist der Wert der NÄCHSTEN Station, und im
                      // Gebirge stehen Nachbarstationen Hunderte
                      // Höhenmeter auseinander — bei Garmisch entscheidet
                      // das über die Stufe (#279). Ein Geländemodell auf
                      // dem Gerät gibt es nicht, also wird die Grenze
                      // benannt statt kaschiert.
                      subtitle: const Text(
                          'Lässt die Waldwaben dort leuchten, wo die '
                          'Bedingungen für Steinpilz & Co. gerade '
                          'stimmen — nur Deutschland, bewertet '
                          'Bedingungen, nicht Vorkommen. Im Gebirge '
                          'unsicher: Die Temperatur kommt von der '
                          'nächsten Wetterstation, und die kann Hunderte '
                          'Höhenmeter tiefer oder höher stehen. Nutzt die '
                          'Wetterdaten vom Spot (beim ersten Mal knapp '
                          '2 MB).'),
                      value: ref.watch(ampelLayerEnabledProvider),
                      // Die Kette samt Nebenwirkungen (Waldebene an,
                      // Wetter-Zustimmung) steht seit #347 EINMAL in
                      // `ampel_map_providers.dart` — das Karten-Blatt
                      // ruft dieselbe. Zwei Kopien wären zwei Antworten
                      // auf denselben Schalter.
                      onChanged: (value) => setAmpelLayerEnabled(ref, value),
                    ),
                  ],
                  if (current != RainLayer.off) ...[
                    const Divider(height: 16),
                    _Details(layer: current),
                    SwitchListTile(
                      dense: true,
                      title: const Text('Legende in Karte anzeigen'),
                      value: ref.watch(mapLegendEnabledProvider),
                      onChanged: (value) => ref
                          .read(mapLegendEnabledProvider.notifier)
                          .set(value),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                // GeoNutzV verlangt bei veränderten Daten den Hinweis
                // darauf — die Summen kommen als Rohwerte und werden von
                // uns quantisiert, geglättet und neu eingefärbt. Beim
                // Radar liegt das Bild des DWD unverändert auf der Karte.
                current == RainLayer.last24h || current == RainLayer.last30d
                    ? 'Datenbasis: Deutscher Wetterdienst, '
                        'Werte verändert'
                    : 'Daten: Deutscher Wetterdienst',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Was die gewählte Ebene zeigt, wo sie gilt, und ihre Legende.
class _Details extends ConsumerWidget {
  const _Details({required this.layer});

  final RainLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final url = rainLegendUrl(layer);
    // Welche Legende stimmt, entscheidet der Dreizustand — dieselbe
    // Quelle wie in beiden Engines, damit das Blatt nie etwas anderes
    // erklärt als die Karte zeigt. Bei `pending` steht die eigene
    // Legende SOFORT da: Sie ist statisch und verspricht, was gleich
    // gezeichnet wird. Nur der Rückfall zeigt die DWD-Legende.
    final paint = ref.watch(rainPaintProvider(layer));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(layer.description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(layer.coverage, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          if (paint != RainPaint.dwd)
            _OwnLegend(levels: rainLevelsFor(layer))
          else if (url != null)
            DecoratedBox(
              // Heller Grund unter der Legende: Der DWD liefert sie mit
              // schwarzer Schrift auf Weiß — im dunklen Thema wäre sie
              // sonst ein weißer Block mit unlesbarem Rand.
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Image(
                  image: ref.read(rainImageProviderFactory)(url),
                  height: 220,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  // Die Legende kommt aus dem Netz wie die Ebene selbst.
                  // Ohne Empfang gibt es beides nicht — dann ein Satz
                  // statt eines kaputten Bildsymbols.
                  errorBuilder: (context, error, stack) => Text(
                    'Legende nicht geladen',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Die Legende zu unseren eigenen Höhenlinien.
///
/// Selbst gebaut statt DWD-Bild, weil die Karte hier nicht mehr in
/// DWD-Farben zeichnet — eine fremde Legende neben eigenen Farben wäre
/// schlimmer als gar keine.
///
/// Von oben nach unten absteigend wie jede Höhenskala. Jede Zeile zeigt,
/// was sie auf der Karte auch ist: die Fläche in ihrer Deckkraft, unten
/// begrenzt von der Linie derselben Stufe.
class _OwnLegend extends StatelessWidget {
  const _OwnLegend({required this.levels});

  final List<int> levels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      // Heller Grund wie beim DWD-Bild: Die Flächen sind absichtlich
      // durchsichtig, sie brauchen etwas darunter, sonst sieht man im
      // dunklen Thema nichts.
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, level) in levels.indexed.toList().reversed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.rainLine(index)
                            .withAlpha(rainFillAlpha),
                        border: Border(
                          bottom: BorderSide(
                              color: AppColors.rainLine(index), width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('ab $level mm',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.barkBrown)),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              // Wichtig genug für eine eigene Zeile: Ohne Farbe heißt
              // „weniger als die unterste Stufe" und NICHT „keine Daten".
              // Wo Daten fehlen, fehlen auch die Linien.
              'Ohne Farbe: weniger als ${levels.first} mm.\n'
              'Weit herausgezoomt zeigt die Karte nur jede zweite oder '
              'vierte Linie — sonst läge Deutschland unter einem Netz.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.barkBrown.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}

