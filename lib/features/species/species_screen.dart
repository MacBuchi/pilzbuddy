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

import '../../core/app_colors.dart';
import '../../core/season_curves.dart';
import '../../core/widgets/mushroom_icon.dart';
import '../../core/widgets/season_bars.dart';
import '../ampel/ampel_model.dart';
import '../ampel/ampel_species_exclusion.dart';
import '../map/spot_filter.dart' show currentMonthProvider;
import 'species_catalogue.dart';

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

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(currentMonthProvider);
    final sections = speciesCatalogue(month: month);
    final withCurve = sections
        .expand((s) => s.entries)
        .where((e) => e.curve != null)
        .length;
    final inSeason = sections.fold(0, (n, s) => n + s.inSeasonCount);

    final rows = <_Row>[];
    for (final section in sections) {
      final entries = _onlyNow
          ? section.entries.where((e) => e.inSeason || e.curve == null)
          : section.entries;
      rows.add(_Row.header(section));
      rows.addAll(entries.map(_Row.entry));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pilze')),
      body: ListView.builder(
        // Kopf + Zeilen + Quelle.
        itemCount: rows.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _Intro(
              month: month,
              inSeason: inSeason,
              withCurve: withCurve,
              onlyNow: _onlyNow,
              onToggle: (value) => setState(() => _onlyNow = value),
            );
          }
          if (index == rows.length + 1) return const _Source();
          final row = rows[index - 1];
          return row.section != null
              ? _SectionHeader(section: row.section!)
              : _EntryTile(entry: row.entry!, month: month);
        },
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

class _Intro extends StatelessWidget {
  const _Intro({
    required this.month,
    required this.inSeason,
    required this.withCurve,
    required this.onlyNow,
    required this.onToggle,
  });

  final int month;
  final int inSeason;
  final int withCurve;
  final bool onlyNow;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welche Arten zu welcher Pilzampel gehören, und wann sie '
                'gemeldet werden. Im ${kMonthNames[month - 1]} haben '
                '$inSeason von $withCurve Arten mit Saisonkurve Saison — '
                'sie sind hervorgehoben. Der Schalter nimmt eine Art aus '
                'der Ampel; eine Gruppe rechnet nur, solange eine ihrer '
                'Arten Saison hat.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          FilterChip(
            label: const Text('Nur jetzt Saison'),
            selected: onlyNow,
            onSelected: onToggle,
          ),
        ],
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
    return Container(
      color: now ? AppColors.forestGreen.withValues(alpha: 0.08) : null,
      child: ListTile(
        dense: true,
        leading: MushroomIcon(
          seed: stableSeed(entry.name),
          size: 30,
          group: entry.group,
          species: entry.name,
          ground: false,
        ),
        title: Text(
          entry.name,
          style: now
              ? const TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.forestGreen)
              : null,
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
