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
// **Warum Regen jetzt doch einen Schalter hat.** Bis hierher stand hier:
// „Die Ebene hat fünf Zustände, kein Ja/Nein. Ein Schalter müsste sich
// einen zuletzt benutzten Modus ausdenken, den niemand bestellt hat."
// Der Einwand traf einen Schalter OHNE die Zeitraum-Zeile darunter — der
// gemerkte Modus war unsichtbar, und was man nicht sieht, kann man nicht
// erwartet haben. Mit den vier Chips in derselben Zeile steht die Wahl
// daneben: Der Schalter beantwortet „überhaupt Regen?", die Chips
// beantworten „welcher Zeitraum?", und beide Antworten sind sichtbar.
//
// Das Unterblatt bleibt hinter dem › für Darstellung, Abdeckung und
// Quelle — aber niemand muss mehr hinein, um den Zeitraum zu wechseln.
// Vorher waren das fünf Radiozeilen eine Ebene tiefer.
//
// Das Blatt entscheidet nichts und öffnet nichts: Es gibt zurück, was
// gewählt wurde, und der Karten-Screen führt es aus — so bleibt der Weg
// in die Detailblätter an einer Stelle.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../../ampel/ampel_map_providers.dart';
import '../../ampel/ampel_providers.dart';
import '../../offline_maps/offline_map_providers.dart';
import '../elevation_contour_providers.dart';
import '../elevation_providers.dart';
import '../forest_data_providers.dart';
import '../rain_data_providers.dart';
import '../rain_layer.dart';
import 'map_legend.dart' show mapIdleCenterProvider;

/// Was der Karten-Screen nach dem Blatt tun soll.
///
/// `ampel` ist seit dem Entwirren neu: Die Pilzampel führte bis dahin
/// ins REGEN-Blatt, weil ihr Schalter dort wohnte — eine Erbschaft aus
/// der Zeit, als sie ein Modus des Regens war. Sie ist seit 1.76.0 ein
/// Modus der WALDfläche; der Weg ins Regen-Blatt war seither eine
/// falsche Fährte.
enum MapLayerDetail { offline, forest, terrain, rain, ampel, refresh }

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
            // „Aktualisieren" steht in der Kopfzeile, nicht in der
            // Liste. Der Grund ist eine Frage der Sorte: Jede Zeile
            // darunter ist eine EBENE mit einem Zustand, den man
            // umlegt; Aktualisieren ist ein Befehl, der sofort
            // ausgeführt ist und nichts hinterlässt. Als sechste
            // Listenzeile las es sich wie eine Ebene, die man
            // anschalten kann — der frühere Kommentar an dieser Stelle
            // nannte sie selbst „den schwächsten Eintrag dieses
            // Blattes, und das ist bekannt".
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Ebenen',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(color: theme.colorScheme.primary)),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(MapLayerDetail.refresh),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Aktualisieren'),
                  ),
                ],
              ),
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
                    // Die Ablesung am Fadenkreuz steht in der Zeile —
                    // dieselbe Zahl wie in der Legende, damit Blatt und
                    // Karte nicht zwei Wahrheiten haben.
                    //
                    // **Nur bei EINGESCHALTETER Ebene**, und das ist
                    // keine Kosmetik: `elevationAtProvider` beobachtet
                    // das Höhengitter, und beobachten IST laden (3,4 MB,
                    // CLAUDE.md). Ausgerechnet dieses Blatt öffnet man,
                    // um die Höhenlinien erst anzuschalten — der Wert
                    // ungeprüft hier hineingeschrieben packte das Gitter
                    // bei jedem Öffnen aus.
                    subtitle: _contourSubtitle(ref),
                    value: ref.watch(contourLayerEnabledProvider),
                    onChanged: (value) => ref
                        .read(contourLayerEnabledProvider.notifier)
                        .set(value),
                    detail: MapLayerDetail.terrain,
                    colour: AppColors.contourLine,
                  ),
                  const _RainRow(),
                  if (ref.watch(ampelPreviewEnabledProvider))
                    _LayerRow(
                      title: 'Pilzampel',
                      badge: 'experimentell',
                      subtitle: 'Färbt die Waldwaben, wo es für Steinpilz '
                          '& Co. gerade stimmt',
                      // Die Kopplung wird BENANNT, nicht versteckt: Der
                      // Schalter zieht die Waldebene mit hoch (ohne sie
                      // hätte das Leuchten nichts, worauf es liegen
                      // könnte) und holt sich die Wetter-Zustimmung.
                      //
                      // Nicht „schaltet Regen mit an": Die Ampel rechnet
                      // aus dem Regen-STAPEL und der Temperatur, nicht
                      // aus der Regen-EBENE — die kann dabei aus
                      // bleiben, und `setAmpelLayerEnabled` fasst sie
                      // auch nicht an.
                      footnote: 'rechnet aus Regen + Temperatur · '
                          'schaltet die Waldtypen mit an',
                      value: ref.watch(ampelLayerEnabledProvider),
                      // Die Kette mit den Nebenwirkungen steht EINMAL,
                      // in `ampel_map_providers.dart`.
                      onChanged: (value) => setAmpelLayerEnabled(ref, value),
                      detail: MapLayerDetail.ampel,
                      colour: AppColors.ampelStrong,
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

/// Der Untertitel der Höhenlinien-Zeile — mit der Ablesung, sobald die
/// Ebene an ist.
///
/// Drei Fälle, weil die Ebene drei Antworten hat: zu weit draußen (dann
/// zeichnet sie gar nicht), noch am Rechnen, und fertig. „Alle 50 m" bei
/// einer Karte ohne Linien wäre eine Behauptung über etwas, das nicht
/// da ist.
String _contourSubtitle(WidgetRef ref) {
  if (!ref.watch(contourLayerEnabledProvider)) {
    return 'Gelände, auf dem Gerät gerechnet';
  }
  if (ref.watch(contourTooFarOutProvider)) {
    return 'Gelände · erst näher dran';
  }
  final equidistance = ref.watch(contourEquidistanceProvider);
  if (equidistance == null) return 'Gelände · wird gerechnet …';
  final centre = ref.watch(mapIdleCenterProvider);
  final height = centre == null
      ? null
      : ref
          .watch(elevationAtProvider(
              (lat: centre.latitude, lon: centre.longitude)))
          .valueOrNull;
  final base = 'Gelände · alle $equidistance m';
  return height == null ? base : '$base · hier $height m';
}

/// Die Regen-Zeile: Schalter, Ablesung und die vier Zeiträume als Chips.
///
/// Eigenes Widget statt eines weiteren Falls in [_LayerRow]: Die
/// Zeitraum-Zeile ist der einzige Zusatz im ganzen Blatt, und ein
/// optionaler Slot in der gemeinsamen Zeile hieße, dass jede andere Zeile
/// eine Möglichkeit mitträgt, die sie nie nutzt.
class _RainRow extends ConsumerWidget {
  const _RainRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final layer = ref.watch(rainLayerProvider);
    final on = layer != RainLayer.off;

    // Die Ablesung am Fadenkreuz — mit derselben Bedingung wie die
    // Legende: NUR zu den eigenen Farben. Beim Radar liegt das Bild des
    // DWD unverändert auf der Karte, ein Millimeterwert aus unserem
    // Gitter stünde dann neben einer Skala, die er nicht meint.
    final centre = ref.watch(mapIdleCenterProvider);
    final mm = (on &&
            centre != null &&
            ref.watch(rainPaintProvider(layer)) != RainPaint.dwd)
        ? ref
            .watch(rainGridProvider(layer))
            .valueOrNull
            ?.mmAt(centre.latitude, centre.longitude)
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Icon(Icons.circle,
              size: 14,
              color: on ? AppColors.friendBlue : theme.disabledColor),
          title: const Text('Regen'),
          subtitle: Text(!on
              ? 'Aus'
              : mm == null
                  ? layer.label
                  : '${layer.label} · hier $mm mm'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: on,
                // Aus heißt aus; an heißt „der Zeitraum von vorhin".
                // Beim allerersten Anschalten gibt es kein Vorhin — dann
                // die 30 Tage, denn das ist die Größe, an der man sieht,
                // ob der Boden durchfeuchtet ist (siehe `description`).
                onChanged: (_) =>
                    ref.read(rainLayerProvider.notifier).toggle(),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: () => Navigator.of(context).pop(MapLayerDetail.rain),
        ),
        // Bündig unter dem Titel, nicht unter dem Punkt: Die Chips
        // gehören zur Regen-Zeile, nicht zur Liste.
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final choice in RainLayer.values)
                if (choice != RainLayer.off)
                  ChoiceChip(
                    label: Text(choice.shortLabel),
                    // Ist die Ebene aus, ist KEIN Chip ausgewählt: `layer`
                    // ist dann `off`, und dafür gibt es keinen Chip. Das
                    // ist Absicht und nicht bloß Folge — der gemerkte
                    // Zeitraum aus `_lastChoice` steht ausdrücklich NICHT
                    // hier. Ein hervorgehobener Chip über einer
                    // ausgeschalteten Ebene behauptete, es läge etwas auf
                    // der Karte; er beschreibt aber nur, was der Schalter
                    // täte, wenn man ihn umlegte.
                    selected: choice == layer,
                    onSelected: (_) =>
                        ref.read(rainLayerProvider.notifier).set(choice),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                  ),
            ],
          ),
        ),
      ],
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
    this.badge,
    this.footnote,
  });

  final String title;
  final String subtitle;
  final bool value;
  final void Function(bool) onChanged;
  final MapLayerDetail detail;
  final Color colour;

  /// Ein kurzes Wort neben dem Titel („experimentell").
  ///
  /// Es steht NEBEN dem Titel und nicht im Untertitel, weil es keine
  /// Beschreibung ist, sondern eine Einschränkung der Aussage — sie
  /// gilt für alles, was darunter steht.
  final String? badge;

  /// Was diese Ebene beim Anschalten mit anderen tut.
  ///
  /// Eine Nebenwirkung, die man erst nach dem Umlegen bemerkt, ist eine
  /// Überraschung; benannt ist sie eine Erklärung. Deshalb steht sie in
  /// der Zeile und nicht im Detailblatt.
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      isThreeLine: footnote != null,
      leading: Icon(Icons.circle,
          size: 14, color: value ? colour : theme.disabledColor),
      title: badge == null
          ? Text(title)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(title)),
                const SizedBox(width: 7),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    child: Text(badge!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colour,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                ),
              ],
            ),
      subtitle: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle),
          if (footnote != null) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.water_drop,
                    size: 12, color: AppColors.friendBlue.withValues(alpha: 0.8)),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(footnote!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.barkBrown)),
                ),
              ],
            ),
          ],
        ],
      ),
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
