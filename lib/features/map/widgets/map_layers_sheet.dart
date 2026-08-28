// Das Karten-Blatt (#347): alles, was auf der Karte liegen kann, an
// einer Stelle.
//
// **Warum es das gibt.** Die FAB-Spalte war mit zehn Knöpfen 604 px hoch
// auf einem 915-px-Schirm und steckte seit 1.98.0 in einem
// `FittedBox(scaleDown)` — jeder neue Knopf machte die anderen kleiner.
// Fünf der zehn waren dabei gar keine Schalter, sondern TÜREN ZU
// BLÄTTERN: Waldtypen, Höhenlinien, Regen, Filter, Standort teilen. Sie
// kosteten also längst zwei Tipps, und eine Tür weniger davor kostet
// keinen einzigen dazu — sie spart nur Platz.
//
// **Warum der Zustand nicht verloren geht.** Die Legende links unten
// (`map_legend.dart`, ab Werk AN) nennt jede aktive Ebene samt
// Farbskala. Die vier eingefärbten Knöpfe sagten überwiegend das, was
// zwei Zentimeter weiter links schon stand. Für alle, die die Legende
// ausgeschaltet haben, trägt der Zähler am Knopf die Aussage.
//
// **Warum Regen keinen Schalter hat.** Die Ebene hat fünf Zustände, kein
// Ja/Nein. Ein Schalter müsste sich einen „zuletzt benutzten Modus"
// ausdenken, den niemand bestellt hat; die Zeile zeigt stattdessen den
// aktuellen und führt ins Regen-Blatt — zwei Tipps zum Wechseln, genau
// wie vorher.
//
// Das Blatt entscheidet nichts und öffnet nichts: Es gibt zurück, was
// gewählt wurde, und der Karten-Screen führt es aus. Dasselbe Muster wie
// `ampel_hits_sheet.dart` — so bleibt der Weg in die Detailblätter an
// einer Stelle.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../../ampel/ampel_map_providers.dart';
import '../../ampel/ampel_providers.dart';
import '../../offline_maps/offline_map_providers.dart';
import '../elevation_contour_providers.dart';
import '../forest_data_providers.dart';
import '../rain_layer.dart';

/// Was der Karten-Screen nach dem Blatt tun soll.
enum MapLayerDetail { offline, forest, terrain, rain, refresh }

Future<MapLayerDetail?> showMapLayersSheet(BuildContext context) {
  return showModalBottomSheet<MapLayerDetail>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _MapLayersSheet(),
  );
}

/// Wie viele der Ebenen im Blatt gerade an sind — die Zahl im Badge am
/// Knopf.
///
/// Gezählt wird, was in diesem Blatt einen Schalter hat, nicht was
/// „gemalt" wird: Wald und Ampel sind zusammen EINE Fläche (die Ampel
/// ist ein Modus der Waldwaben), aber zwei Schalter. Die Zahl beantwortet
/// „wie viel habe ich angeschaltet" — eine Aussage, die man am Blatt
/// nachzählen kann.
///
/// Beim Offline-Eintrag zählt der WIRKLICHE Zustand
/// (`offlineMapStyleProvider`), nicht der Schalter: Er ist auch dann an,
/// wenn die App bei fehlendem Empfang von selbst umgeschaltet hat — und
/// er ist aus, wenn der Stil sich nicht laden ließ (stiller Rückfall auf
/// OSM). Der Badge soll sagen, was auf der Karte liegt.
int activeMapLayerCount(WidgetRef ref) {
  var n = 0;
  if (ref.watch(offlineMapStyleProvider).valueOrNull != null) n++;
  if (ref.watch(forestLayerEnabledProvider)) n++;
  if (ref.watch(contourLayerEnabledProvider)) n++;
  if (ref.watch(rainLayerProvider) != RainLayer.off) n++;
  if (ref.watch(ampelLayerEnabledProvider)) n++;
  return n;
}

class _MapLayersSheet extends ConsumerWidget {
  const _MapLayersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hasInstalledMaps =
        (ref.watch(installedMapsProvider).valueOrNull ?? const []).isNotEmpty;
    final rainLayer = ref.watch(rainLayerProvider);
    final offlineOnMap =
        ref.watch(offlineMapStyleProvider).valueOrNull != null;
    final autoOffline = ref.watch(noConnectivityProvider);

    return SafeArea(
      child: ConstrainedBox(
        // Wie die Blätter dahinter: gedeckelt, damit die Karte sichtbar
        // bleibt — man soll die Wirkung eines Schalters sofort sehen.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text('Ebenen',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: theme.colorScheme.primary)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  if (hasInstalledMaps)
                    _LayerRow(
                      title: 'Offline-Karte',
                      // Der Schalter zeigt die WAHL, der Untertitel den
                      // Zustand — und die beiden können auseinanderfallen:
                      // Ohne Empfang schaltet die App von selbst um
                      // (#118), und ein Stil, der sich nicht laden lässt,
                      // fällt still auf OSM zurück. Bisher stand dafür nur
                      // ein Symbol da; wer den Unterschied nicht kannte,
                      // sah eine Karte, die nicht zum Knopf passte.
                      subtitle: switch ((offlineOnMap, autoOffline)) {
                        (true, true) => 'Aktiv, weil kein Empfang',
                        (true, false) => 'Heruntergeladene Regionen statt OSM',
                        (false, _) => 'Karten aus dem Netz',
                      },
                      value: ref.watch(offlineMapEnabledProvider),
                      onChanged: (_) =>
                          ref.read(offlineMapEnabledProvider.notifier).toggle(),
                      detail: MapLayerDetail.offline,
                      colour: AppColors.warmBrown,
                    ),
                  _LayerRow(
                    title: 'Waldtypen',
                    subtitle: 'Laub, Nadel und Mischwald als Waben',
                    value: ref.watch(forestLayerEnabledProvider),
                    onChanged: (value) => ref
                        .read(forestLayerEnabledProvider.notifier)
                        .set(value),
                    detail: MapLayerDetail.forest,
                    colour: AppColors.forestMixed,
                  ),
                  _LayerRow(
                    title: 'Höhenlinien',
                    subtitle: 'Gelände, auf dem Gerät gerechnet',
                    value: ref.watch(contourLayerEnabledProvider),
                    onChanged: (value) => ref
                        .read(contourLayerEnabledProvider.notifier)
                        .set(value),
                    detail: MapLayerDetail.terrain,
                    colour: AppColors.contourLine,
                  ),
                  // Fünf Zustände, kein Ja/Nein — deshalb eine Zeile, die
                  // den aktuellen zeigt und ins Blatt führt.
                  ListTile(
                    leading: Icon(
                      rainLayer == RainLayer.off
                          ? Icons.water_drop_outlined
                          : Icons.water_drop,
                      color: rainLayer == RainLayer.off
                          ? theme.hintColor
                          : AppColors.friendBlue,
                    ),
                    title: const Text('Regen'),
                    subtitle: Text(rainLayer == RainLayer.off
                        ? 'Aus'
                        : rainLayer.label),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.of(context).pop(MapLayerDetail.rain),
                  ),
                  if (ref.watch(ampelPreviewEnabledProvider))
                    _LayerRow(
                      title: 'Pilzampel',
                      subtitle: 'Experimentell — färbt die Waldwaben',
                      value: ref.watch(ampelLayerEnabledProvider),
                      // Die Kette mit den Nebenwirkungen steht EINMAL,
                      // in `ampel_map_providers.dart` — das Regen-Blatt
                      // ruft dieselbe.
                      onChanged: (value) => setAmpelLayerEnabled(ref, value),
                      detail: MapLayerDetail.rain,
                      colour: AppColors.ampelStrong,
                    ),
                  const Divider(height: 8),
                  // Der schwächste Eintrag dieses Blattes, und das ist
                  // bekannt: „Aktualisieren" ist weder Ebene noch Filter.
                  // Er landet hier mangels besserem Ort — die App lädt
                  // bei Resume, bei Empfangsrückkehr und nach jeder
                  // Änderung ohnehin neu, ihn ganz zu streichen wäre
                  // vertretbar. Das ist aber eine eigene Entscheidung.
                  ListTile(
                    leading: const Icon(Icons.refresh),
                    title: const Text('Karte aktualisieren'),
                    onTap: () =>
                        Navigator.of(context).pop(MapLayerDetail.refresh),
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

/// Eine Ebene: Schalter UND Weg ins Detailblatt.
///
/// Die Zeile hat deshalb zwei Trefferflächen — den Schalter rechts und
/// den Rest. Das ist das Muster der Android-Einstellungen: umlegen ohne
/// Umweg, Einzelheiten eine Ebene tiefer.
class _LayerRow extends StatelessWidget {
  const _LayerRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.detail,
    required this.colour,
  });

  final String title;
  final String subtitle;
  final bool value;
  final void Function(bool) onChanged;
  final MapLayerDetail detail;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.circle,
          size: 14,
          color: value ? colour : Theme.of(context).disabledColor),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(value: value, onChanged: onChanged),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => Navigator.of(context).pop(detail),
    );
  }
}
