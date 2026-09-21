// Die Detailseite je Art (#511) — eine Ebene unter dem Reiter „Pilze".
//
// **Was hier steht, weiß die App schon.** Wissenschaftlicher Name,
// Zweitnamen, Saisonkurve, Ampel-Gruppe, eigene Funde, GBIF-Meldungen:
// alles lag im Binary oder im Cache und hatte bloß keinen Platz in der
// einzeiligen Fakten-Zeile der Liste. Gerechnet wird in
// `species_catalogue.dart`, damit der Test es nachrechnen kann; hier
// wird nur gezeichnet.
//
// **Was hier NICHT steht — und das ist eine Entscheidung, kein
// Versäumnis.** Keine Bestimmungshilfe, keine Merkmale, keine Fotos.
// Der ganze Wortschatz der Saisonkurven ist darauf gebaut, „gemeldet"
// zu sagen und nie „wächst"; eine Seite mit Bild und Beschreibung läse
// sich als Feldführer, und in der Liste stehen Satansröhrling,
// Karbolchampignon, Gallenröhrling, Falscher Pfifferling und der
// Frühjahrsknollenblätterpilz. Für genau diese Arten ist die
// Verwechslung teuer. Deshalb schließt der Fuß der Seite mit dem Satz,
// den sie sonst nur implizit macht.
//
// **Die 0,6 MB der Fundorte werden hier ausgepackt** — beobachten ist
// laden (CLAUDE.md), und das ist an dieser Stelle in Ordnung: Die Seite
// wird bewusst geöffnet, dieselbe Begründung wie im „Was ist
// hier?"-Blatt. In der LISTE nebenan hängt nichts davon.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/app_colors.dart';
import '../../core/router_branches.dart';
import '../../core/season_curves.dart';
import '../../core/species_edibility.dart';
import '../../core/species_lookalikes.dart';
import '../../core/widgets/mushroom_icon.dart';
import '../../core/widgets/season_bars.dart';
import '../ampel/ampel_model.dart';
import '../ampel/ampel_species_exclusion.dart';
import '../map/gbif_finds_providers.dart';
import '../map/spot_filter.dart' show currentMonthProvider, spotFilterProvider;
import '../spots/spot_providers.dart' show mySpotListProvider;
import 'species_catalogue.dart';

/// Die Karte mit der Einstufung DIESER Art — siehe [_Edibility].
const kEdibilityCardKey = ValueKey('species-edibility');

class SpeciesDetailScreen extends ConsumerWidget {
  const SpeciesDetailScreen({super.key, required this.species});

  /// Der Name aus der Adresse — roh, wie er in der Route steht. Ein
  /// Zweitname und eine andere Schreibweise lösen sich in
  /// [speciesDetailFor] auf.
  final String species;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(currentMonthProvider);
    // Beobachten ist laden — Begründung am Kopf der Datei.
    final findsAsync = ref.watch(gbifFindsProvider);
    final detail = speciesDetailFor(
      species,
      month: month,
      spots: ref.watch(mySpotListProvider),
      gbif: findsAsync.valueOrNull?.totalsFor(species),
    );

    return Scaffold(
      appBar: AppBar(title: Text(detail?.name ?? species)),
      body: detail == null
          ? const _Unknown()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _Header(detail: detail),
                // **Ganz oben, gleich unter dem Namen.** Eine Warnung,
                // zu der man erst scrollen muss, ist im Wald keine.
                _Edibility(detail: detail),
                // Direkt darunter: „giftig" und „wird verwechselt mit …"
                // müssen zusammen gelesen werden, sonst nützt keins von
                // beidem.
                _Lookalikes(detail: detail),
                // Erst die Warnungen, dann die Beschreibung: Wer die
                // Seite von oben liest, weiß vor dem ersten Merkmal, ob
                // er es mit einem Giftpilz zu tun hat.
                _Features(detail: detail),
                _Season(detail: detail, month: month),
                _Ampel(detail: detail),
                _OwnFinds(detail: detail),
                _Reported(detail: detail, loading: findsAsync.isLoading),
                const SizedBox(height: 20),
                const _NotAFieldGuide(),
              ],
            ),
    );
  }
}

/// Eine Art, die es nicht gibt — aus einem Lesezeichen oder einer
/// älteren Fassung. Kein Absturz und kein leerer Bildschirm: Ein Satz
/// ist mehr als ein verschwundener Inhalt.
class _Unknown extends StatelessWidget {
  const _Unknown();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Diese Art kennt PilzBuddy nicht. Eigene Arten lassen sich beim '
          'Eintragen frei schreiben — ein Verzeichniseintrag entsteht '
          'daraus nicht.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.detail});

  final SpeciesDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MushroomIcon(
          seed: stableSeed(detail.name),
          size: 56,
          group: detail.group,
          species: detail.name,
          ground: false,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(detail.name, style: theme.textTheme.titleLarge),
              // Der wissenschaftliche Name ist der einzige eindeutige
              // Schlüssel — deutsche Namen sind regional und meinen
              // manchmal eine ganze Gattung. Kursiv, wie es sich gehört.
              //
              // Fehlt er, steht hier KEIN Ersatzsatz: Ohne ihn gibt es
              // auch keine Kurve und keine GBIF-Zeile, und beide
              // Abschnitte sagen das schon. Dreimal dieselbe Auskunft
              // auf einer Seite ist zweimal zu viel.
              if (detail.sci case final sci?)
                Text(sci,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontStyle: FontStyle.italic)),
              if (detail.synonyms.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  // Dieselbe Form wie im Spot-Blatt („auch: …"): Wer den
                  // Pilz nur unter dem zweiten Namen kennt, soll sehen,
                  // dass die App ihn kennt.
                  child: Text('auch: ${detail.synonyms.join(', ')}',
                      style: theme.textTheme.bodySmall),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Gruppe: ${detail.group.label}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Essbar oder giftig — mit Absicht der erste Abschnitt.
///
/// **Kein Grün für „Speisepilz".** Die Farbe gehört der Warnung: Ein
/// grüner Balken über einem Namen läse sich als Freigabe, und freigeben
/// kann die App nichts — sie weiß nicht, was jemand in der Hand hält.
/// Deshalb tragen nur die Stufen ab „nur gegart" Farbe, und der Satz
/// darunter sagt genau das noch einmal.
class _Edibility extends StatelessWidget {
  const _Edibility({required this.detail});

  final SpeciesDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = detail.edibility;
    if (entry == null) return const SizedBox.shrink();
    final level = entry.level;
    // Rot für giftig, Bernstein für alles dazwischen, neutral für den
    // Speisepilz.
    final colour = switch (level) {
      Edibility.toedlichGiftig || Edibility.giftig => theme.colorScheme.error,
      Edibility.speisepilz => theme.colorScheme.onSurface,
      _ => AppColors.warmBrown,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        // Benannt, damit ein Test die EIGENE Einstufung von der eines
        // Verwechslungspartners unterscheiden kann — beide tragen
        // dasselbe Warnzeichen, und nur eine gehört diesem Pilz.
        key: kEdibilityCardKey,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: level.isWarning
              ? colour.withValues(alpha: 0.08)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (level.isWarning)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.warning_amber_rounded,
                        size: 20, color: colour),
                  ),
                Expanded(
                  child: Text(
                    level.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                        color: colour, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (entry.note case final note?) ...[
              const SizedBox(height: 6),
              Text(note, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 6),
            Text(kEdibilityDisclaimer,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
          ],
        ),
      ),
    );
  }
}

/// Womit diese Art verwechselt wird.
///
/// **Jeder Partner ist antippbar** — er ist selbst eine Art mit eigener
/// Seite, und wer hier landet, will als Nächstes meistens genau dorthin.
/// Und jede Zeile trägt die EINSTUFUNG des Partners: „Pantherpilz" allein
/// sagt nichts, „Pantherpilz · Giftig" beantwortet die Frage, wegen der
/// man hinsieht.
class _Lookalikes extends StatelessWidget {
  const _Lookalikes({required this.detail});

  final SpeciesDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (detail.lookalikes.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Verwechslungspartner'),
        for (final partner in detail.lookalikes)
          _LookalikeRow(partner: partner),
        const SizedBox(height: 6),
        Text(
          // **Leer ist nicht dasselbe wie sicher.** Der Satz steht auch
          // unter einer vollen Liste: Vollständigkeit ist hier nie
          // behauptet.
          'Aufgeführt ist, was häufig verwechselt wird — die Liste ist '
          'nicht vollständig, und ein Merkmal allein entscheidet nie.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
    );
  }
}

class _LookalikeRow extends StatelessWidget {
  const _LookalikeRow({required this.partner});

  final Lookalike partner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = edibilityFor(partner.species)?.level;
    final colour = switch (level) {
      Edibility.toedlichGiftig || Edibility.giftig => theme.colorScheme.error,
      null || Edibility.speisepilz => theme.colorScheme.onSurface,
      _ => AppColors.warmBrown,
    };
    return InkWell(
      onTap: () =>
          context.go('/pilze/${Uri.encodeComponent(partner.species)}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (level?.isWarning ?? false)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.warning_amber_rounded,
                        size: 16, color: colour),
                  ),
                Flexible(
                  child: Text(
                    partner.species,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (level != null) ...[
                  Text(' · ', style: theme.textTheme.bodySmall),
                  Text(level.label,
                      style: theme.textTheme.bodySmall?.copyWith(color: colour)),
                ],
                const Spacer(),
                Icon(Icons.chevron_right, size: 18, color: theme.hintColor),
              ],
            ),
            Text(partner.difference, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Die sechs Bestimmungsmerkmale.
///
/// **Ein festes Raster, immer in derselben Reihenfolge.** Das ist nicht
/// Ordnungsliebe: Wer zwei Arten vergleicht, springt zwischen zwei Seiten
/// hin und her und liest dieselbe Zeile zweimal. Freitext in wechselnder
/// Reihenfolge macht genau das unmöglich — und Vergleichen ist der
/// einzige Grund, aus dem jemand hier liest.
class _Features extends StatelessWidget {
  const _Features({required this.detail});

  final SpeciesDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = detail.features;
    if (f == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Merkmale'),
        for (final (label, value) in [
          ('Hut', f.hut),
          ('Unterseite', f.unterseite),
          ('Stiel', f.stiel),
          ('Fleisch', f.fleisch),
          ('Geruch', f.geruch),
          ('Vorkommen', f.vorkommen),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 86,
                  child: Text(label,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: Text(value, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
        Text(
          // Der Satz, der DIESEM Abschnitt gehört — die anderen
          // Vorbehalte auf der Seite sagen etwas anderes.
          'Beschrieben ist, woran die Art in der Literatur erkannt wird. '
          'Ein einzelnes Merkmal entscheidet nie.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
    );
  }
}

/// Überschrift eines Abschnitts — eine Form für alle fünf.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 6),
      child: Text(title,
          style: theme.textTheme.titleSmall
              ?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

class _Season extends StatelessWidget {
  const _Season({required this.detail, required this.month});

  final SpeciesDetail detail;
  final int month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final curve = detail.curve;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Wann diese Art gemeldet wird'),
        if (curve == null)
          Text(
            'Für diese Art gibt es keine belastbare Kurve — zu wenige '
            'Meldungen oder keine zweifelsfreie Zuordnung. Das heißt '
            'nicht, dass sie selten ist; es heißt, dass wir es nicht '
            'wissen.',
            style: theme.textTheme.bodySmall,
          )
        else ...[
          // Groß und MIT Monatsbuchstaben — in der Liste sind die zwölf
          // Balken 7 px auseinander und tragen keine Beschriftung. Das
          // ist der Unterschied, der die Seite trägt.
          SeasonBars(months: curve.months, currentMonth: month - 1),
          const SizedBox(height: 8),
          Text(
            '${kMonthNames[month - 1]}: ${detail.seasonWord}',
            style: TextStyle(
                fontWeight: detail.inSeason ? FontWeight.w600 : null,
                color: detail.inSeason ? AppColors.forestGreen : null),
          ),
          const SizedBox(height: 4),
          // Derselbe Satz wie im Spot-Blatt, aus derselben Funktion:
          // geborgte Kurve, Sammelbegriff und flacher Gang stehen dort
          // schon richtig eingeschränkt.
          Text(seasonSentence(detail.name, curve),
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(seasonSourceLine(curve),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor, fontSize: 11)),
        ],
      ],
    );
  }
}

class _Ampel extends ConsumerWidget {
  const _Ampel({required this.detail});

  final SpeciesDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final klass = detail.klass;
    if (klass == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Pilzampel'),
          Text(
            'Für diese Art sagt die Ampel nichts. Ein eigenes Fenster ist '
            'an unabhängigen Daten nicht bestätigt — lieber grau als '
            'erfunden.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    }
    final excluded = ref.watch(ampelExcludedSpeciesProvider).contains(detail.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Pilzampel'),
        Text('Gruppe „${klass.name}"', style: theme.textTheme.bodyMedium),
        Text(
          klass.optimumC == null
              ? 'Rechnet aus ${ampelClassWindowWord(klass)}.'
              : 'Temperaturfenster ${ampelClassWindowWord(klass)}.',
          style: theme.textTheme.bodySmall,
        ),
        if (detail.evidence case final evidence?)
          Text('Belege: ${ampelEvidenceWord(evidence)}',
              style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        // Derselbe Schalter wie in der Liste, derselbe Provider — zwei
        // Wahrheiten über „zählt diese Art" wären eine zu viel. Hier
        // steht dazu, was er bewirkt; in der Zeile war dafür kein Platz.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: !excluded,
          title: const Text('Für die Ampel mitzählen'),
          subtitle: Text(
            'Aus nimmt die Art aus dem Hinweis auf der Karte, aus dem '
            'Spot-Blatt und aus dem Saison-Tor der Ampel-Fläche. Die '
            'gemeldeten Fundorte zeigt die Karte weiter.',
            style: theme.textTheme.bodySmall,
          ),
          onChanged: (_) => ref
              .read(ampelExcludedSpeciesProvider.notifier)
              .toggle(detail.name),
        ),
      ],
    );
  }
}

class _OwnFinds extends ConsumerWidget {
  const _OwnFinds({required this.detail});

  final SpeciesDetail detail;

  /// Karte auf diese Art einstellen und hin.
  ///
  /// **Ein Weg für beide Zahlen.** Der Artenfilter wirkt auf die eigenen
  /// Spots UND auf die gemeldeten GBIF-Scheiben (#467) — zwei Knöpfe
  /// wären zwei Antworten auf dieselbe Frage. Reihenfolge wie in der
  /// Spot-Liste: erst der Reiter, dann der Wunsch.
  void _showOnMap(BuildContext context, WidgetRef ref) {
    StatefulNavigationShell.maybeOf(context)?.goBranch(kMapBranchIndex);
    ref.read(spotFilterProvider.notifier).showOnlySpecies(detail.name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final last = detail.lastFound;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Deine Funde'),
        Text(
          detail.ownFinds == 0
              ? 'Noch kein eigener Fund dieser Art.'
              : '${detail.ownFinds} ${detail.ownFinds == 1 ? 'Fund' : 'Funde'} '
                  'an ${detail.ownSpots} '
                  '${detail.ownSpots == 1 ? 'Spot' : 'Spots'}'
                  '${last == null ? '' : ', zuletzt am ${DateFormat('d.M.y').format(last)}'}.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.map_outlined),
            label: const Text('Auf der Karte zeigen'),
            onPressed: () => _showOnMap(context, ref),
          ),
        ),
      ],
    );
  }
}

class _Reported extends StatelessWidget {
  const _Reported({required this.detail, required this.loading});

  final SpeciesDetail detail;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gbif = detail.gbif;
    final String text;
    if (gbif != null) {
      text = '${gbif.observations} Meldungen an ${gbif.places} Orten in '
          'Deutschland, Österreich und der Schweiz'
          '${gbif.newestYear == null ? '' : ', zuletzt ${gbif.newestYear}'}. '
          'Die Karte zeichnet jede davon als Scheibe in der Größe ihrer '
          'Unschärfe.';
    } else if (loading) {
      text = 'Fundorte werden gelesen …';
    } else {
      // **Zwei verschiedene Auskünfte, und die Seite darf sie nicht
      // verwechseln**: Eine Art ohne wissenschaftlichen Namen steht im
      // Asset nie — das ist eine Lücke bei uns, keine bei den Meldern.
      //
      // Heute trägt jede der 91 ausgelieferten Arten einen (gemessen in
      // der Gegenprobe zu #511), dieser Zweig ist also unbenutzt. Er
      // bleibt, weil `sci` bewusst nullbar ist: Eine Art ohne
      // zweifelsfreie Zuordnung aufzunehmen ist erlaubt, und dann darf
      // hier nicht „lässt sich nicht laden" stehen.
      text = detail.sci == null
          ? 'Ohne zweifelsfreie Zuordnung fragt PilzBuddy GBIF für diese '
              'Art gar nicht ab.'
          : 'Die gemeldeten Fundorte lassen sich nicht laden.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Gemeldete Fundorte (GBIF)'),
        Text(text, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// Der Satz, den die Seite sonst nur implizit macht.
///
/// Eine Detailseite weckt die Erwartung, die eine Listenzeile nicht
/// weckt — deshalb steht er hier und nicht im Reiter davor.
class _NotAFieldGuide extends StatelessWidget {
  const _NotAFieldGuide();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'PilzBuddy bestimmt keine Pilze. Ob du diese Art vor dir hast, '
      'sagt dir die App nicht — sie zeigt nur, was über sie gemeldet '
      'wurde und was du selbst eingetragen hast.',
      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
    );
  }
}
