// Das Pilzampel-Blatt: Schalter, Grenzen, Kosten.
//
// **Warum es das jetzt gibt.** Der Schalter der Ampel-Fläche wohnte bis
// hierher im REGEN-Blatt, und der Pfeil in der Ebenen-Zeile führte
// ebenfalls dorthin. Das war eine Erbschaft: In der ersten Fassung war
// die Ampel ein Modus des Regens. Seit 1.76.0 färbt sie ausschließlich
// die WALDwaben — sie ist ein Modus der Waldfläche, und der Regen ist
// nur noch eine ihrer beiden Zutaten. Wer dem Pfeil folgte, landete
// seither bei der falschen Ebene und fand einen Schalter, der zu einer
// anderen Zeile gehörte.
//
// **Warum die Grenzen hier stehen und nicht in der Zeile.** Die
// Einschränkungen sind lang und sie sind wichtig — nur Deutschland,
// bewertet Bedingungen statt Vorkommen, im Gebirge unsicher, beim ersten
// Mal knapp 2 MB. In der Zeile stünde davon nichts oder alles: nichts
// wäre unehrlich, alles machte die Zeile zum Absatz. Die Zeile trägt
// deshalb die Aussage und die Nebenwirkung, das Blatt die Grenzen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_colors.dart';
import '../../ampel/ampel_map_providers.dart';
import '../../../core/mushroom_species.dart';
import '../../ampel/ampel_model.dart';
import '../spot_filter.dart' show selectedAmpelClassesProvider;

Future<void> showAmpelLayerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _AmpelLayerSheet(),
  );
}

class _AmpelLayerSheet extends ConsumerWidget {
  const _AmpelLayerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Die Gruppenauswahl aus dem Kartenfilter (1.142.0). Das Blatt
    // erklärt die Farben auf der Karte — also muss es sagen, wenn die
    // Karte gerade nur für eine Gruppe spricht. Bedient wird sie hier
    // NICHT: Zwei Bedienstellen für einen Filter wären zwei Antworten
    // auf dieselbe Frage (die Lehre aus `setAmpelLayerEnabled`), und
    // melden kann sich auf der Karte ohnehin nur der Filter-Chip.
    final selected = ref.watch(selectedAmpelClassesProvider);
    final restricted = selected.length < ampelShippedClasses.length;

    return SafeArea(
      child: ConstrainedBox(
        // Wie die Nachbarblätter gedeckelt: Man soll die Wirkung eines
        // Schalters sofort auf der Karte sehen.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Text('Pilzampel',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(width: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.ampelStrong.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      child: Text('experimentell',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.ampelStrong,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
              child: Text(
                // **Korrigiert am 2026-09-12.** Hier stand „für
                // Steinpilz & Co.", und das war seit 1.140.0 falsch: Die
                // Fläche zeigt das Maximum ALLER Klassen. Kein Test hat
                // es gefangen — Tests prüfen Verhalten, nicht
                // Beschreibungen.
                restricted
                    ? 'Lässt die Waldwaben dort leuchten, wo die '
                        'Bedingungen für '
                        '${selected.map((k) => k.name).join(' oder ')} '
                        'gerade stimmen. Die übrigen Gruppen hast du im '
                        'Kartenfilter abgewählt.'
                    : 'Lässt die Waldwaben dort leuchten, wo die '
                        'Bedingungen für mindestens eine Pilzgruppe '
                        'gerade stimmen.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
            const _ClassList(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  SwitchListTile(
                    title: const Text('Ampel-Fläche auf der Karte'),
                    // Dieselbe Nebenwirkung wie in der Ebenen-Zeile, und
                    // aus demselben Grund benannt: Ohne Waldebene hätte
                    // das Leuchten nichts, worauf es liegen könnte.
                    subtitle: const Text('Schaltet die Waldtypen mit an und '
                        'holt sich die Wetterdaten vom Spot (beim ersten '
                        'Mal knapp 2 MB).'),
                    value: ref.watch(ampelLayerEnabledProvider),
                    // Die Kette mit den Nebenwirkungen steht EINMAL, in
                    // `ampel_map_providers.dart` — das Ebenen-Blatt ruft
                    // dieselbe. Zwei Kopien wären zwei Antworten auf
                    // denselben Schalter.
                    onChanged: (value) => setAmpelLayerEnabled(ref, value),
                  ),
                  const Divider(height: 16),
                  const _Limit(
                    icon: Icons.public_off,
                    title: 'Nur Deutschland',
                    text: 'Die Regensummen kommen vom Deutschen '
                        'Wetterdienst und enden an der Grenze. Außerhalb '
                        'bleibt die Waldwabe schlicht Wald.',
                  ),
                  const _Limit(
                    icon: Icons.terrain,
                    title: 'Im Gebirge unsicher',
                    text: 'Die Temperatur kommt von der nächsten '
                        'Wetterstation, und die kann Hunderte Höhenmeter '
                        'tiefer oder höher stehen. Die App rechnet sie auf '
                        'die Wabenhöhe um — aber eine Umrechnung ist keine '
                        'Messung.',
                  ),
                  // Der wichtigste Satz des Blattes, und er steht
                  // zuletzt, weil er den Rest einordnet.
                  //
                  // **Korrigiert am 2026-09-12, aus derselben Ecke wie
                  // die drei Texte aus #456.** Hier stand „An echten
                  // Funden hat sich das Modell bisher nicht bewährt" —
                  // begründet mit der durchgefallenen Arten-Kontrolle,
                  // und die ist aufgelöst: Sie scheiterte an ihrer
                  // AUSWAHL (`docs/pilzampel-artenfenster-messung.md`).
                  // An GBIF-Meldungen trennt das Modell Fund- von
                  // Vergleichstagen deutlich (AUC 0,61…0,76 über sechs
                  // Arten, `docs/pilzampel-validierung.md`). Was NICHT
                  // geprüft ist, ist der eigene Wald — und genau das
                  // sagt der Satz jetzt, statt das Gegenteil zu
                  // behaupten.
                  const _Limit(
                    icon: Icons.science_outlined,
                    title: 'Bewertet Bedingungen, nicht Vorkommen',
                    text: 'Sie sagt, wo Regen und Temperatur gerade '
                        'passen — nicht, wo Pilze stehen. Geprüft ist '
                        'das an Pilzmeldungen aus ganz Deutschland; an '
                        'deinen eigenen Funden nicht.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                'Datenbasis: Deutscher Wetterdienst, Werte verändert',
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

/// Eine Grenze der Aussage — Symbol, Überschrift, ein Satz.
class _Limit extends StatelessWidget {
  const _Limit({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: AppColors.barkBrown),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: Text(text),
    );
  }
}

/// **Welche Arten zu welcher Gruppe gehören** — aufklappbar, weil die
/// Frage erst kommt, wenn die Karte leuchtet (Betreiber, 2026-09-12).
///
/// **Die Liste kommt aus dem Modellkern**, nicht aus abgeschriebenem
/// Text. Genau das war der Fehler, den diese Datei bis heute selbst
/// vorgeführt hat: Sie behauptete „für Steinpilz & Co.", während die
/// Fläche längst das Maximum aller Klassen zeigte. Eine Aufzählung von
/// Hand wäre dieselbe Falle, nur länger.
class _ClassList extends StatelessWidget {
  const _ClassList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Arten je Klasse, in der Reihenfolge der Artenliste — so stehen
    // sie auch im Blatt und in der Suche.
    final members = <String, List<String>>{};
    for (final entry in ampelSpeciesClass.entries) {
      members.putIfAbsent(entry.value, () => []).add(entry.key);
    }
    // Echte Arten ohne Klasse — Zweitnamen erben über `sameAs` und
    // zählen nicht doppelt.
    final greyCount = kBekannteArten
        .where((s) => !s.isSynonym && ampelClassFor(s.name) == null)
        .length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        dense: true,
        title: Text('Welche Gruppen?',
            style: theme.textTheme.titleSmall),
        children: [
          for (final entry in ampelClasses.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.value.name} · '
                    '${entry.value.optimumC.toStringAsFixed(1)
                        .replaceAll('.', ',')} °C',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    (members[entry.key] ?? const []).join(' · '),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                ],
              ),
            ),
          // **Die graue Ampel braucht ihren Grund** — „nicht geprüft"
          // im Spot-Blatt sagt nicht, was fehlt.
          //
          // **Die Zahl ist GEZÄHLT, nicht geschrieben.** Ein Satz, der
          // „Hallimasch, Stockschwämmchen und Austernseitling" aufführt,
          // wäre morgen falsch — sobald eine dieser Klassen ihren
          // Nachweis hat. Genau diese Sorte Satz stand über dieser
          // Zeile und behauptete „für Steinpilz & Co.", während die
          // Fläche längst alle Klassen rechnete.
          if (greyCount > 0)
            Text(
              'Die übrigen $greyCount Arten bekommen eine graue Ampel: '
              'Für sie ist noch nicht an unabhängigen Daten bestätigt, '
              'dass ein eigener Temperaturbereich besser passt. Bis '
              'dahin sagt die Ampel für sie nichts — lieber grau als '
              'erfunden.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor),
            ),
        ],
      ),
    );
  }
}
