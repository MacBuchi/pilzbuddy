// Der Reiter „Pilze" — was die App über die Arten weiß, an einer Stelle.
//
// **Warum ein eigener Reiter** (Betreiber, 2026-09-20): Mit vier
// Ampel-Gruppen und zwei Rechenkernen „muss für den Nutzer transparent
// bleiben, was wozu gehört". Bis dahin stand die Zuordnung nur in der
// ausgeklappten Legende der Ampel-Ebene, also hinter zwei Tipps und nur
// bei eingeschalteter Vorschau; die Saisonkurve nur im Blatt eines
// Spots, der die Art schon trägt. Hier steht beides nebeneinander, für
// jede bekannte Art, auch ohne Spot.
//
// **Hervorgehoben ist, was jetzt Saison hat** — nach derselben Schwelle,
// mit der Filter und Banner-Nachlauf rechnen (`kSeasonNowThreshold`).
// Der Reiter sagt damit dasselbe wie die Karte, nur als Liste. Der Monat
// kommt aus `currentMonthProvider`, nicht von der Uhr, damit ein Test
// im Dezember nicht anders ausgeht als im September.
//
// **Fakten, kein Urteil**, wie überall bei den Saisonkurven: „wird
// gemeldet", nicht „wächst". Und keine Prozentzahlen — die Balken sind
// ein relativer Jahresgang, sonst nichts.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/season_curves.dart';
import '../../core/widgets/info_button.dart';
import '../../core/widgets/mushroom_icon.dart';
import '../../core/widgets/season_bars.dart';
import '../ampel/ampel_model.dart';
import '../ampel/ampel_species_exclusion.dart';
import '../map/spot_filter.dart' show currentMonthProvider;
import 'species_catalogue.dart';

/// Die senkrechte Liste des Reiters.
///
/// **Sie braucht einen Namen, seit das Suchfeld ÜBER ihr steht** (seit
/// 1.181.0). Ein `TextField` bringt sein eigenes `Scrollable` mit, und
/// das kommt jetzt zuerst im Baum: `find.byType(Scrollable).first` zog
/// vorher die Liste und zieht seither das Eingabefeld. Dieselbe Falle
/// wie auf der Artseite (#516) und im Reiter-Test (#414).
const kSpeciesListKey = ValueKey('species-list');

class SpeciesScreen extends ConsumerStatefulWidget {
  const SpeciesScreen({super.key});

  @override
  ConsumerState<SpeciesScreen> createState() => _SpeciesScreenState();
}

class _SpeciesScreenState extends ConsumerState<SpeciesScreen> {
  /// Nur die Arten, die jetzt Saison haben.
  ///
  /// **Arten ohne Kurve bleiben auch dann stehen** — dieselbe Regel wie
  /// beim Saison-Filter auf der Karte (#414): `null` heißt „wir wissen
  /// es nicht", und wer nichts weiß, verdeckt nichts. Sie sind als
  /// „keine Saisonkurve" beschriftet, und das ist die Auskunft.
  bool _onlyNow = false;

  /// Die Sucheingabe. **Der Controller lebt im State**, nicht im
  /// `itemBuilder`: Die Liste baut sich bei jedem Tastendruck neu, und
  /// ein dort erzeugtes Feld verlöre Fokus und Cursor.
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(currentMonthProvider);
    final query = _search.text.trim();
    final sections = speciesCatalogue(month: month);
    final all = sections.expand((s) => s.entries).toList();
    final withCurve = all.where((e) => e.curve != null).length;
    final inSeason = sections.fold(0, (n, s) => n + s.inSeasonCount);

    // Ein Suchlauf für die ganze Liste, nicht einer je Zeile: Der
    // Tippfehler-Ausgleich muss wissen, ob IRGENDWO ein Treffer war.
    final search = speciesSearch(query);
    final rows = <_Row>[];
    var matches = 0;
    for (final section in sections) {
      var entries =
          section.entries.where((e) => search.names.contains(e.name));
      if (_onlyNow) {
        entries = entries.where((e) => e.inSeason || e.curve == null);
      }
      final shown = entries.toList();
      matches += shown.length;
      // **Bei einer Suche fällt die leere Gruppe weg, beim Saison-Filter
      // nicht.** Die beiden beantworten verschiedene Fragen: „Welche
      // meiner Gruppen hat gerade Saison?" braucht die Überschrift, um
      // „keine" zeigen zu können; „wo steht der Steinpilz?" braucht sie
      // nicht — dort wären elf leere Überschriften der Treffer.
      if (shown.isEmpty && query.isNotEmpty) continue;
      rows.add(_Row.header(section));
      rows.addAll(shown.map(_Row.entry));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pilze')),
      // **Die Regler stehen ÜBER der Liste, nicht darin** (Betreiber,
      // 2026-09-22). Bis 1.181.0 war der ganze Kopf die erste Zeile der
      // `ListView` und scrollte mit: Wer in der Liste nach unten ging,
      // verlor das Suchfeld, und zum Tippen musste er zurück nach oben.
      // Die Spot-Liste macht es seit 1.161.0 richtig; hier ist es
      // nachgezogen.
      body: Column(
        children: [
          _Controls(
            month: month,
            inSeason: inSeason,
            withCurve: withCurve,
            onlyNow: _onlyNow,
            onToggle: (value) => setState(() => _onlyNow = value),
            search: _search,
            query: query,
            matches: matches,
            isGuess: search.isGuess,
            onSearch: () => setState(() {}),
          ),
          Expanded(
            child: query.isNotEmpty && matches == 0
                ? _NoMatch(total: all.length)
                : ListView.builder(
                    key: kSpeciesListKey,
                    // Zeilen + Quelle.
                    itemCount: rows.length + 1,
                    itemBuilder: (context, index) {
                      if (index == rows.length) return const _Source();
                      final row = rows[index];
                      return row.section != null
                          ? _SectionHeader(section: row.section!)
                          : _EntryTile(entry: row.entry!, month: month);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Eine Zeile der Liste: Abschnittskopf ODER Art.
class _Row {
  const _Row.header(this.section) : entry = null;
  const _Row.entry(this.entry) : section = null;

  final CatalogueSection? section;
  final CatalogueEntry? entry;
}

/// Der feste Kopf: eine Zeile Auskunft, das Suchfeld, ein Chip.
///
/// **Der Erklärabsatz steckt im „i"** (Betreiber, 2026-09-22). Er stand
/// bis 1.181.0 als sechszeiliger Text über dem Suchfeld und kostete
/// gemessen 220 der 444 px, die über der ersten Art lagen — gelesen
/// wird er einmal, im Weg steht er immer. Die ZAHL bleibt sichtbar:
/// Sie ändert sich mit dem Monat und ist der Grund, aus dem jemand den
/// Reiter überhaupt öffnet.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.month,
    required this.inSeason,
    required this.withCurve,
    required this.onlyNow,
    required this.onToggle,
    required this.search,
    required this.query,
    required this.matches,
    required this.isGuess,
    required this.onSearch,
  });

  final int month;
  final int inSeason;
  final int withCurve;
  final bool onlyNow;
  final ValueChanged<bool> onToggle;
  final TextEditingController search;
  final String query;
  final int matches;
  final bool isGuess;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  // **Bei einer Suche zählt die Zeile die Treffer.** Die
                  // Saison-Zahl beschreibt das ganze Verzeichnis; über
                  // einer gefilterten Liste stünde sie da wie eine
                  // Auskunft über das, was man gerade sieht.
                  query.isEmpty
                      ? 'Im ${kMonthNames[month - 1]} haben $inSeason von '
                          '$withCurve Arten Saison.'
                      : isGuess && matches > 0
                          ? 'Keine Art heißt so. Meintest du …?'
                          : matches == 1
                              ? 'Eine Art gefunden.'
                              : '$matches Arten gefunden.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const InfoButton(
                title: 'Der Reiter „Pilze"',
                text: 'Hier steht, welche Arten zu welcher Pilzampel '
                    'gehören und wann sie gemeldet werden. Hervorgehoben '
                    'ist, was jetzt Saison hat.\n\n'
                    'Der Schalter an einer Art nimmt sie aus der Ampel. '
                    'Eine Gruppe rechnet nur, solange mindestens eine '
                    'ihrer Arten Saison hat.\n\n'
                    'Gesucht wird über den deutschen Namen, Zweitnamen '
                    'und den wissenschaftlichen Namen.',
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: search,
                    onChanged: (_) => onSearch(),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search),
                      // **Ohne `helperText`.** Wonach gesucht werden
                      // kann, stand als eigene Zeile unter dem Feld und
                      // machte es 68 statt 48 px hoch; jetzt steht es im
                      // „i" daneben. Sichtbar bleibt es dadurch, dass
                      // der Platzhalter den zweiten Namen nennt.
                      hintText: 'Art oder wissenschaftlicher Name',
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Suche löschen',
                              onPressed: () {
                                search.clear();
                                onSearch();
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // **Der Chip steht NEBEN dem Feld, nicht darunter.** Eine
                // eigene Zeile kostete 40 px, die der Liste fehlen.
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Saison'),
                  tooltip: 'Nur Arten, die jetzt Saison haben',
                  selected: onlyNow,
                  onSelected: onToggle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Die leere Liste — sie erklärt sich, statt nur leer zu sein.
class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Text(
        'Keine Art mit diesem Namen. PilzBuddy kennt $total Arten — eigene '
        'lassen sich beim Eintragen frei schreiben, sie stehen dann aber '
        'nicht in diesem Verzeichnis.',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section});

  final CatalogueSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
          Text(section.subtitle,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
        ],
      ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry, required this.month});

  final CatalogueEntry entry;
  final int month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = entry.inSeason;
    // Der Schalter je Art (#495): nur bei Arten, für die die Ampel
    // überhaupt spricht — bei „Ohne Ampel" gäbe es nichts auszunehmen.
    final inAmpel = ampelClassFor(entry.name) != null;
    final excluded = inAmpel &&
        ref.watch(ampelExcludedSpeciesProvider).contains(entry.name);
    // Saison und Belege in einer Zeile — dieselben Wörter wie in der
    // Fakten-Zeile des Spot-Blatts (`ampel_section.dart`).
    final facts = [
      entry.seasonWord ?? 'keine Saisonkurve',
      if (entry.evidence case final evidence?)
        'Belege: ${ampelEvidenceWord(evidence)}',
      if (excluded) 'von der Ampel ausgenommen',
    ].join(' · ');
    return ListTile(
      dense: true,
      // **Die Farbe gehört an die Kachel, nicht in einen Container
      // darum.** Mit `onTap` malt `ListTile` Tinte auf das nächste
      // `Material` — ein farbiger Container davor verdeckt sie, und
      // Flutter bricht mit genau dieser Meldung ab.
      tileColor: now ? AppColors.forestGreen.withValues(alpha: 0.08) : null,
      // Eine Ebene tiefer steht, wofür in dieser Zeile kein Platz ist
      // (#511): wissenschaftlicher Name, Zweitnamen, die volle Kurve
      // mit Monatsbuchstaben, eigene Funde und die GBIF-Meldungen.
      // Der Name reist als Pfadstück — `Uri.encodeComponent`, weil
      // „Krause Glucke" ein Leerzeichen trägt.
      onTap: () =>
          context.go('/pilze/${Uri.encodeComponent(entry.name)}'),
      leading: MushroomIcon(
        seed: stableSeed(entry.name),
        size: 30,
        group: entry.group,
        species: entry.name,
        ground: false,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              entry.name,
              overflow: TextOverflow.ellipsis,
              style: now
                  ? const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.forestGreen)
                  : null,
            ),
          ),
          // **Nur die giftigen, und nur als Zeichen.** Die Zeile ist
          // voll; knappen Platz bekommt die Fehlerrichtung, die wehtut.
          // Was genau, steht eine Ebene tiefer.
          if (entry.edibility?.level.warnsInList ?? false)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Tooltip(
                message: entry.edibility!.level.label,
                child: Icon(Icons.warning_amber_rounded,
                    size: 16, color: theme.colorScheme.error),
              ),
            ),
          // **Nach der Warnung, nie davor.** Das Auge ist Buchführung
          // und keine Aussage über den Pilz: Es sagt, dass wir Bilder
          // haben. Der eigentliche Zweck ist die Umkehrung — auf einen
          // Blick zu sehen, wovon noch welche fehlen, damit ein
          // Waldgang darauf zielen kann.
          if (entry.hasPictures)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Tooltip(
                message: 'Bilder vorhanden',
                child: Icon(Icons.visibility_outlined,
                    size: 15, color: theme.hintColor),
              ),
            ),
        ],
      ),
      subtitle: Text(facts, style: theme.textTheme.bodySmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.curve != null)
            SizedBox(
              width: 84,
              child: SeasonBars(
                months: entry.curve!.months,
                currentMonth: month - 1,
                height: 18,
                showLetters: false,
              ),
            ),
          if (inAmpel) ...[
            const SizedBox(width: 4),
            // AN heißt „zählt für die Ampel" — die Vorgabe. Aus nimmt
            // die Art aus Banner, Spot-Blatt und dem Saison-Tor der
            // Fläche; die Fundorte-Scheiben zeigt sie weiter.
            Semantics(
              label: '${entry.name} in der Ampel',
              child: Switch(
                value: !excluded,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) => ref
                    .read(ampelExcludedSpeciesProvider.notifier)
                    .toggle(entry.name),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Source extends StatelessWidget {
  const _Source();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Text(
        'Die Kurven zeigen, in welchen Monaten eine Art in Deutschland, '
        'Österreich und der Schweiz gemeldet wird (GBIF), verrechnet '
        'gegen den allgemeinen Meldeeifer — frühere Jahre, nicht dieses. '
        'Hervorgehoben ist eine Art, wenn ihr laufender Monat mindestens '
        '$kSeasonNowThreshold Prozent ihres stärksten Monats erreicht. '
        'Was „gut belegt" und „unsichere Datenlage" heißt, steht in der '
        'Legende der Ampel-Ebene.',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
      ),
    );
  }
}
