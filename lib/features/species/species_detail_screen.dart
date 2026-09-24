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

import '../coach/coach.dart';
import '../help/tab_tours.dart';
import '../../core/app_colors.dart';
import '../../core/app_info.dart' show appVersionProvider;
import '../../core/errors.dart';
import '../../core/photo_pipeline.dart';
import '../../core/photo_providers.dart';
import '../../core/widgets/photo_attachment.dart';
import '../../data/feedback_repository.dart';
import '../../data/providers.dart';
import '../../core/router_branches.dart';
import '../../core/season_curves.dart';
import '../../core/species_edibility.dart';
import '../../core/species_lookalikes.dart';
import '../../core/species_photos.dart';
import '../../core/widgets/mushroom_icon.dart';
import '../../core/widgets/season_bars.dart';
import '../ampel/ampel_model.dart';
import '../ampel/ampel_species_exclusion.dart';
import '../map/gbif_finds_providers.dart';
import '../map/spot_filter.dart' show currentMonthProvider, spotFilterProvider;
import '../profile/profile_providers.dart' show myProfileProvider;
import '../spots/spot_providers.dart' show mySpotListProvider;
import 'species_catalogue.dart';
import 'species_photo_view.dart';

/// Die Karte mit der Einstufung DIESER Art — siehe [_Edibility].
/// Eine Kachel im Bildstreifen, benannt nach dem BILD.
///
/// **Nicht nach der Art.** Eine Art bringt bis zu drei Bilder mit, und
/// drei Geschwister mit demselben `ValueKey` sind kein Schluessel mehr:
/// `getTopLeft` findet dann drei Treffer und bricht ab. Der Asset-Pfad
/// ist je Kachel eindeutig.
Key pictureTileKey(String asset) => ValueKey('bild-$asset');

/// Die Trennung zwischen dem eigenen Pilz und den Partnern.
const kPictureStripDividerKey = ValueKey('bildstreifen-trennung');

/// Die senkrechte Liste der Detailseite.
///
/// **Sie braucht einen Namen, seit es auch waagerecht scrollt.** Die
/// Porträtreihe ist ein zweites `Scrollable` innerhalb desselben
/// Screens; ein Test, der „das Scrollable dieser Seite" sucht, findet
/// seither zwei und scheitert im Zug. Dieselbe Falle wie beim Suchfeld
/// im Reiter „Pilze" (#516).
const kSpeciesDetailListKey = ValueKey('species-detail-list');

const kEdibilityCardKey = ValueKey('species-edibility');

/// Der Ausklapper mit Fleisch, Geruch und Vorkommen.
const kMoreFeaturesKey = ValueKey('merkmale-mehr');

/// Die antippbare Zeile eines Verwechslungspartners.
ValueKey<String> lookalikeRowKey(String species) =>
    ValueKey('lookalike-$species');

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
              key: kSpeciesDetailListKey,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _Header(detail: detail),
                // **Ganz oben, gleich unter dem Namen.** Eine Warnung,
                // zu der man erst scrollen muss, ist im Wald keine.
                // Die Anker der Reiter-Tour (#596).
                CoachAnchor(
                    id: PilzeCoach.detailEdibility,
                    child: _Edibility(detail: detail)),
                // Direkt darunter: „giftig" und „wird verwechselt mit …"
                // müssen zusammen gelesen werden, sonst nützt keins von
                // beidem.
                _Lookalikes(detail: detail),
                // Bilder NACH den Warnungen. Ein Porträt am Seitenkopf
                // läse sich als „so sieht er aus, das genügt" — genau
                // die Erwartung, die der Hinweis darunter zurücknimmt.
                CoachAnchor(
                    id: PilzeCoach.detailPictures,
                    child: _PictureStrip(detail: detail)),
                _PhotoNote(detail: detail),
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
                _ReportButton(species: detail.name),
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

    // **Eingeklappt wird nur, was sonst eine Warnung nach unten
    // schöbe.** Der Steinpilz hat seit 1.171.0 sechs Partner; drei
    // davon sind harmlos, und sie drückten Gallen- und Satansröhrling
    // aus dem ersten Bildschirm (Betreiber, 2026-09-22: „genau das
    // sollten wir kompakter machen").
    //
    // Daraus folgen drei Bedingungen, jede mit eigenem Grund:
    // Die Art selbst darf nicht warnen — auf der Seite eines Giftpilzes
    // sind die Speisepilz-Partner gerade der Punkt, sie erklären,
    // warum jemand ihn im Korb hätte. Es muss überhaupt eine Warnung
    // geben, sonst ist nichts zu schützen und das Einklappen nähme dem
    // Leser nur den Inhalt (die vier Reizker sind genau dieser Fall).
    // Und es muss beides geben, sonst klappt sich der Abschnitt selbst
    // ein. Dieselbe Trennlinie wie in `confusionHint`.
    final warning = <Lookalike>[];
    final harmless = <Lookalike>[];
    for (final p in detail.lookalikes) {
      final level = edibilityFor(p.species)?.level;
      ((level?.isWarning ?? false) ? warning : harmless).add(p);
    }
    final ownWarns = edibilityFor(detail.name)?.level.isWarning ?? false;
    final fold = !ownWarns && warning.isNotEmpty && harmless.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Verwechslungspartner'),
        for (final partner in fold ? warning : detail.lookalikes)
          _LookalikeRow(partner: partner),
        if (fold)
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              // Neutral formuliert: Welche Einstufung eine Art trägt,
              // steht in ihrer Zeile. Eine Überschrift, die
              // „ungefährlich" behauptet, wäre eine Freigabe.
              title: Text('Weitere ähnliche Arten (${harmless.length})',
                  style: theme.textTheme.bodyMedium),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final partner in harmless)
                  _LookalikeRow(partner: partner),
              ],
            ),
          ),
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
    final colour = levelColour(theme, level);
    return InkWell(
      // Benannt, weil der Name des Partners seit den Bildpaaren zweimal
      // in der Zeile steht — hier und als Bildunterschrift.
      key: lookalikeRowKey(partner.species),
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

/// Der Hinweis unter den Bildern — EINMAL je Seite.
///
/// **Die beiden tragenden Sätze stehen außerhalb des Ausklappers.**
/// „Nicht geprüft" und „im Zweifel stehen lassen" muss lesen können, wer
/// es eilig hat; eine eingeklappte Warnung ist Deko. Was verschwindet,
/// ist die BEGRÜNDUNG, nicht die Aussage.
///
/// **Und er gilt für beide Bildarten.** Die Vergleichspaare stehen
/// weiter oben in den Verwechslungszeilen, die Porträts direkt darüber —
/// ein Hinweis je Bildblock wäre derselbe Satz zweimal auf einer Seite.
/// Deshalb fragt er nicht „gibt es Porträts", sondern „steht auf dieser
/// Seite irgendein Bild".
class _PhotoNote extends StatelessWidget {
  const _PhotoNote({required this.detail});

  final SpeciesDetail detail;

  /// Zeigt diese Seite überhaupt ein Bild? Dieselbe Naht wie der
  /// Streifen — zwei Antworten darauf wären ein Hinweis, der mal steht
  /// und mal fehlt.
  bool get _hasPhoto => ownPictures(detail.name).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_hasPhoto) return const SizedBox.shrink();
    final small = theme.textTheme.bodySmall?.copyWith(color: theme.hintColor);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kPhotoDisclaimer,
              style: small?.copyWith(fontWeight: FontWeight.w600)),
          Theme(
            // ExpansionTile zieht sonst eine Trennlinie über die ganze
            // Breite und sieht aus wie ein eigener Abschnitt.
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(kPhotoDisclaimerTitle, style: small),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(kPhotoDisclaimerDetail, style: small)],
            ),
          ),
        ],
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
/// Die Farbe zu einer Einstufung - EINMAL, fuer Zeile und Bildstreifen.
///
/// Zwei Fassungen waeren zwei Meinungen darueber, wie gefaehrlich
/// "ungeniessbar" aussieht. **Speisepilz bekommt die neutrale Farbe**,
/// kein Gruen: Gruen laese sich als Freigabe (`Edibility.isWarning`).
Color levelColour(ThemeData theme, Edibility? level) => switch (level) {
      Edibility.toedlichGiftig || Edibility.giftig => theme.colorScheme.error,
      null || Edibility.speisepilz => theme.colorScheme.onSurface,
      _ => AppColors.warmBrown,
    };

/// Die Bilder einer Art: erst sie selbst, dann ihre Verwechslungspartner.
///
/// **Ein Streifen statt verstreuter Paare.** Bis 1.173.0 sass das
/// Vergleichspaar in der Verwechslungszeile - und seit die harmlosen
/// Zeilen einklappen (1.172.0), konnte ein Paar hinter einem Tipp
/// verschwinden. Nebeneinander in einer Reihe ist die Gegenueberstellung
/// immer da, und man scrollt einmal statt an jeder Zeile.
///
/// **Rahmen NUR bei Warnung.** Der eigene Pilz und ein harmloser Partner
/// bekommen einen neutralen Rand; die Abwesenheit der Farbe ist die
/// Auskunft. Ein gruener Rahmen fuer "Speisepilz" waere eine Freigabe in
/// gross - dieselbe Asymmetrie wie beim fehlenden Haekchen.
///
/// **Die Unterschrift traegt die Aussage, nicht die Farbe.** Wer den
/// Streifen ueberfliegt, koennte sonst das Pantherpilz-Bild fuer den
/// Perlpilz halten. Deshalb steht unter jedem Bild der Name, bei den
/// Partnern zusaetzlich die Einstufung, und zwischen "das ist er" und
/// "das ist er nicht" liegt eine sichtbare Trennung.
class _PictureStrip extends StatelessWidget {
  const _PictureStrip({required this.detail});

  final SpeciesDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final own = ownPictures(detail.name);
    if (own.isEmpty) return const SizedBox.shrink();
    final partners = partnerPictures(detail);
    final authors = {
      for (final p in [...own, ...partners.map((e) => e.photo)]) p.author
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Bilder'),
        SizedBox(
          height: 190,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final photo in own) ...[
                if (photo != own.first) const SizedBox(width: 8),
                _StripTile(
                    name: detail.name, photo: photo, level: null, own: true),
              ],
              if (partners.isNotEmpty) ...[
                const SizedBox(width: 12),
                // Die sichtbare Grenze. Links der Pilz, rechts das,
                // was er NICHT ist.
                Container(
                    key: kPictureStripDividerKey,
                    width: 1,
                    color: theme.dividerColor),
                const SizedBox(width: 12),
              ],
              for (final entry in partners) ...[
                if (entry != partners.first) const SizedBox(width: 8),
                _StripTile(
                    name: entry.species,
                    photo: entry.photo,
                    level: edibilityFor(entry.species)?.level,
                    own: false),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text('Fotos: ${authors.join(', ')}',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
      ],
    );
  }
}

/// Ein Bild im Streifen, mit Rand und Unterschrift.
class _StripTile extends StatelessWidget {
  const _StripTile({
    required this.name,
    required this.photo,
    required this.level,
    required this.own,
  });

  final String name;
  final SpeciesPhoto photo;
  final Edibility? level;
  final bool own;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warns = level?.isWarning ?? false;
    final colour = warns ? levelColour(theme, level) : theme.dividerColor;
    return SizedBox(
      key: pictureTileKey(photo.asset),
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // **Antippen vergrößert** (#537). Das Lupensymbol sagt es an,
          // ohne selbst etwas zu laden: „Beobachten ist laden" gilt
          // auch hier, geholt wird erst beim Tipp.
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () =>
                showSpeciesPhoto(context, species: name, photo: photo),
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colour, width: warns ? 3 : 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.asset(
                      photo.asset,
                      width: 144,
                      height: 144,
                      fit: BoxFit.cover,
                      semanticLabel: own
                          ? '$name, Foto'
                          : '$name, Verwechslungspartner, Foto',
                      errorBuilder: (_, _, _) => const SizedBox(width: 144),
                    ),
                  ),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.zoom_in,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          if (warns)
            Text(level!.label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: colour)),
        ],
      ),
    );
  }
}

/// Eine Merkmalszeile — dieselbe Form oben wie im Ausklapper.
///
/// **Ein Widget, nicht zwei Kopien.** Das feste Raster ist der Grund,
/// aus dem jemand hier liest: Wer zwei Arten vergleicht, springt
/// zwischen zwei Seiten und liest dieselbe Zeile zweimal. Zwei
/// Fassungen wären zwei Breiten für die Beschriftung.
class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
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
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

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
        // **Die GESTALT steht, der Rest klappt auf.** Gemessen am
        // 2026-09-22 war dieser Abschnitt mit 614 px der höchste der
        // Seite, höher als die Verwechslungspartner — sechs Felder, von
        // denen drei die Form beschreiben und drei dazukommen, wenn man
        // den Pilz schon in der Hand hat.
        //
        // **Hier gilt „eine eingeklappte Warnung ist Deko" NICHT**, und
        // das ist der ganze Grund, warum an dieser Stelle eingeklappt
        // werden darf und bei den warnenden Partnern nicht: Merkmale
        // beschreiben, sie warnen nicht. Die Einstufung steht weit
        // darüber und bleibt sichtbar.
        //
        // Dieselben drei Felder nennt `species_features_test.dart` die
        // GESTALT-Felder — wer die Aufteilung ändert, muss dort
        // nachsehen.
        for (final (label, value) in [
          ('Hut', f.hut),
          ('Unterseite', f.unterseite),
          ('Stiel', f.stiel),
        ])
          _FeatureRow(label: label, value: value),
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: kMoreFeaturesKey,
            title: Text('Fleisch, Geruch und Vorkommen',
                style: theme.textTheme.bodyMedium),
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, value) in [
                ('Fleisch', f.fleisch),
                ('Geruch', f.geruch),
                ('Vorkommen', f.vorkommen),
              ])
                _FeatureRow(label: label, value: value),
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

/// „Hinweis zu dieser Art melden" — der Rückkanal für handgepflegte
/// Daten.
///
/// Vier Tabellen auf dieser Seite sind von Hand geschrieben, und keine
/// davon kann ein Test bestätigen. Wer einen Fehler sieht, sieht ihn
/// HIER — nicht auf der Karte, wo das Feedback-Banner wohnt. Der Knopf
/// nimmt den Artnamen mit, damit die Meldung beim Bot als Bug-Issue mit
/// klarem Betreff ankommt (`tool/feedback_bot.py`, Typ `bug`).
class _ReportButton extends ConsumerWidget {
  const _ReportButton({required this.species});

  final String species;

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_ReportInput>(
      context: context,
      builder: (_) => _ReportDialog(
          species: species,
          username: ref.read(myProfileProvider).valueOrNull?.username,
          pickPhoto: ref.read(photoPickerProvider),
          pickPhotos: ref.read(multiPhotoPickerProvider),
          // Galerie-Größe: Diese Bilder dürfen mit Haken in die
          // Artgalerie, und das Hochgeladene ist die einzige Kopie.
          preparePhoto: ref.read(galleryPhotoPreparerProvider)),
    );
    // Nur `null` (Abbrechen) kommt hier ohne Senden an: Leeren Text
    // lässt der Dialog gar nicht erst durch. Bis 1.201.0 stand hier
    // zusätzlich „Text leer ⇒ still zurück" — und nahm die Fotos mit.
    if (result == null) return;
    final text = result.text;
    try {
      String? version;
      try {
        version = await ref.read(appVersionProvider.future);
      } catch (_) {
        // Ohne Version ist die Meldung immer noch wertvoll — wie beim
        // Feedback-Banner auf der Karte.
      }
      await ref.read(feedbackRepositoryProvider).submit(
          FeedbackType.bug, 'Hinweis zur Art „$species": ${text.trim()}',
          appVersion: version,
          photos: result.photos,
          galleryConsent: result.consent);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Danke — der Hinweis wird geprüft. 🍄')));
      }
    } catch (e, stackTrace) {
      logError('Art-Hinweis senden', e, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.flag_outlined, size: 18),
          label: const Text('Hinweis zu dieser Art melden'),
          onPressed: () => _report(context, ref),
        ),
      );
}

typedef _ReportInput = ({
  String text,
  List<PreparedPhoto> photos,
  bool consent,
});

const kGalleryConsentKey = Key('gallery-consent');
const kReportSendKey = Key('species-report-send');

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.species,
    required this.username,
    required this.pickPhoto,
    required this.pickPhotos,
    required this.preparePhoto,
  });

  final String species;

  /// Der Name, der als Urheber genannt würde — im Häkchen AUSGESCHRIEBEN,
  /// damit man sieht, was öffentlich würde. `null`, solange das Profil
  /// nicht geladen ist.
  final String? username;
  final PhotoPicker pickPhoto;

  /// Mehrere auf einmal aus der Galerie (#585) — Hut, Unterseite, Stiel
  /// in einem Griff.
  final MultiPhotoPicker pickPhotos;
  final PhotoPreparer preparePhoto;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _text = TextEditingController();

  /// Bilder dazu (#525, bis zu drei seit #569): der Fund, der der
  /// Merkmalstabelle widerspricht — Hut, Unterseite, Stiel; ein Bild
  /// allein zeigt selten das Merkmal, um das es geht.
  List<PreparedPhoto> _photos = const [];

  /// Einwilligung für die Artgalerie (Patch 034) — ab Werk AUS, und sie
  /// fällt mit dem letzten Bild weg: Ein Haken, der stehen bleibt, gälte
  /// sonst für das nächste Bild, das niemand mehr angesehen hat.
  bool _consent = false;

  /// Erst mit Text geht die Meldung wirklich raus — vorher ist „Senden"
  /// grau ([kFeedbackMinChars]). Bis 1.201.0 war der Knopf immer aktiv,
  /// und ohne Text verschwand die Meldung samt Fotos wortlos.
  bool get _canSend => _text.text.trim().length >= kFeedbackMinChars;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Hinweis zu „${widget.species}"'),
        // Scrollbar: Mit drei Bildern ist der Dialog auf einem kleinen
        // Telefon mit offener Tastatur höher als der Platz.
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              // Knopf und Hinweis hängen an jedem Zeichen.
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Was stimmt nicht — Einstufung, Merkmal, '
                    'Verwechslung, Bild?',
                // Der Grund für den grauen Knopf, VOR dem Tipp. Mit Bild
                // besonders: Ein Foto allein sagt nicht, was daran
                // auffällt.
                helperText: _canSend
                    ? null
                    : _photos.isEmpty
                        ? 'Ein paar Worte, dann lässt sich senden.'
                        : 'Schreib kurz dazu, was auf dem Bild auffällt — '
                            'dann lässt sich senden.',
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            PhotoAttachmentList(
              pick: widget.pickPhoto,
              pickMany: widget.pickPhotos,
              prepare: widget.preparePhoto,
              photos: _photos,
              max: kFeedbackMaxPhotos,
              onChanged: (photos) => setState(() {
                _photos = photos;
                if (photos.isEmpty) _consent = false;
              }),
            ),
            if (_photos.isNotEmpty)
              CheckboxListTile(
                key: kGalleryConsentKey,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: _consent,
                onChanged: (v) => setState(() => _consent = v ?? false),
                title: Text(
                    'Ich habe ${_photos.length == 1 ? 'das Foto' : 'die Fotos'} '
                    'selbst gemacht. PilzBuddy darf '
                    '${_photos.length == 1 ? 'es' : 'sie'} in der Artgalerie '
                    'zeigen — unter $kGalleryPhotoLicence, mit '
                    '${widget.username == null ? 'meinem Benutzernamen' : '„${widget.username}"'} '
                    'als Urheber.'),
                subtitle: const Text('Freiwillig. Ohne Haken sieht nur der '
                    'Entwickler die Bilder. Ob eines übernommen wird, '
                    'entscheidet er nach Ansicht.'),
              ),
          ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: kReportSendKey,
            onPressed: _canSend
                ? () => Navigator.of(context).pop((
                      text: _text.text,
                      photos: _photos,
                      consent: _consent && _photos.isNotEmpty,
                    ))
                : null,
            child: const Text('Senden'),
          ),
        ],
      );
}
