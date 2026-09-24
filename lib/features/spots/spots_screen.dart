// Der Reiter „Spots" (#509) — die Karte als Liste, plus die Statistik,
// die bis 1.160.0 im Profil stand.
//
// **Warum ein eigener Reiter.** Die Karte beantwortet WO, der Reiter
// „Pilze" beantwortet, WAS WANN gemeldet wird. Was fehlte, ist die
// eigene Zeitachse: welche Orte habe ich, was war dort zuletzt los, und
// was hat ein Buddy eingetragen. Bis dahin führte zu einem Spot genau
// ein Weg — seinen Marker auf der Karte zu treffen.
//
// **Zwei Ziele je Zeile, mit Absicht.** Antippen öffnet das Spot-Blatt
// an Ort und Stelle (dasselbe Blatt wie auf der Karte, es kennt schon
// alles); das Kartensymbol springt zur Karte und zentriert den Spot.
// „Details ansehen" und „zeig mir wo" sind zwei verschiedene Wünsche,
// und wer in einer langen Liste liest, will nicht bei jedem Tipp die
// Liste verlieren.
//
// **Der Reiter schaltet die Buddy-Neuigkeit NICHT stumm.** Der Marker
// `lastFindSeenAt` gehört dem Karten-Banner; hier wird er nur gelesen.
// Ein Blick in die Liste, der die Meldung auffrisst, ist genau die
// Beschwerde aus #349 und #425 — wer nicht erkennen kann, dass er etwas
// abgeschaltet hat, hält es für kaputt.
//
// **Der Karten-Filter bleibt bei der Karte.** Hier stehen eigene,
// leichte Regler. Ein Filter, der sich an zwei Orten verschieden
// auswirkt, wäre schlimmer als zwei getrennte — auf der Karte muss er
// sich melden (#154), hier sieht man die ganze Liste.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../core/router_branches.dart';
import '../../core/widgets/mushroom_avatar.dart';
import '../../core/widgets/mushroom_icon.dart';
import '../../models/spot.dart';
import '../coach/coach.dart';
import '../friends/buddy_alias.dart';
import '../help/tab_tours.dart';
import '../map/map_focus.dart';
import '../map/widgets/map_banners.dart' show newBuddyFindsProvider;
import 'spot_list.dart';
import 'spot_providers.dart';
import 'widgets/find_photo_strip.dart';
import 'widgets/spot_detail_sheet.dart';
import 'widgets/spot_stats_view.dart';

/// Die Spots, an denen ein Buddy etwas eingetragen hat, das ich noch
/// nicht gesehen habe. Zusammengefasst aus dem Provider des Banners —
/// es gibt genau EINE Definition von „neu".
final spotsWithNewsProvider = Provider<Set<String>>((ref) => {
      for (final entry in ref.watch(newBuddyFindsProvider)) entry.spot.id,
    });

class SpotsScreen extends StatelessWidget {
  const SpotsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Spots'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Liste'),
              CoachAnchor(id: SpotsCoach.statsTab, child: Tab(text: 'Statistik')),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_SpotListTab(), SpotStatsView()],
        ),
      ),
    );
  }
}

class _SpotListTab extends ConsumerStatefulWidget {
  const _SpotListTab();

  @override
  ConsumerState<_SpotListTab> createState() => _SpotListTabState();
}

class _SpotListTabState extends ConsumerState<_SpotListTab> {
  final _search = TextEditingController();
  SpotOwnerFilter _owner = SpotOwnerFilter.all;

  /// Der Spot der ersten Zeile — ihn öffnet die Tour (#596).
  String? _firstSpotId;
  VoidCallback? _unregisterScene;

  @override
  void initState() {
    super.initState();
    _unregisterScene = ref
        .read(coachRegistryProvider)
        .registerScene(SpotsCoach.sheet, () async {
      final id = _firstSpotId;
      if (id == null || !mounted) return () {};
      final navigator = Navigator.of(context);
      var open = true;
      unawaited(
          showSpotDetailSheet(context, id).whenComplete(() => open = false));
      return () {
        if (open) navigator.pop();
      };
    });
  }

  @override
  void dispose() {
    _unregisterScene?.call();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(mySpotListProvider);
    final friends =
        ref.watch(friendSpotsProvider).valueOrNull ?? const <Spot>[];
    final today = ref.watch(todayProvider);
    final list = spotList(
      mine: mine,
      friends: friends,
      owner: _owner,
      query: _search.text,
      spotsWithNews: ref.watch(spotsWithNewsProvider),
      aliases: ref.watch(buddyNamesViewProvider).aliases,
    );

    final rows = <_Item>[
      for (final row in list.active) _Item.row(row),
      if (list.planned.isNotEmpty)
        const _Item.header('Vorgemerkt',
            'Angelegt, um dort nachzusehen — noch ohne Eintrag.'),
      for (final row in list.planned) _Item.row(row),
      if (list.silent.isNotEmpty)
        const _Item.header('Ohne Einträge',
            'Wer nur den Standort teilt, zeigt keine Arten und keine '
            'Daten.'),
      for (final row in list.silent) _Item.row(row),
    ];
    // Der Posteingang der Fundfotos (#532) als erste Zeile — in der
    // Liste, nicht darüber: Ein Streifen im Kopf stünde auf jedem
    // Bildschirm und nähme der Liste 140 px. Und nur, wenn es Zeilen
    // gibt: Ein Foto hängt an einem Fund, ein Fund an einem Spot.
    final items = <_Item>[
      if (rows.isNotEmpty) const _Item.photos(),
      ...rows,
    ];
    final firstRow = items.indexWhere((item) => item.row != null);
    _firstSpotId = firstRow < 0 ? null : items[firstRow].row!.spot.id;

    return TabTourStarter(
      script: kSpotsTourScript,
      // Ohne Zeile gäbe es nichts vorzuführen (Kopf von `tab_tours.dart`).
      ready: firstRow >= 0,
      child: Column(
      children: [
        _Controls(
          search: _search,
          owner: _owner,
          // Der Dreier-Schalter erscheint erst, wenn es überhaupt
          // geteilte Spots gibt: Ein Regler, der auf eine leere Liste
          // führt, ist von kaputt nicht zu unterscheiden (#399).
          showOwnerFilter: friends.isNotEmpty,
          onOwner: (value) => setState(() => _owner = value),
          onSearch: () => setState(() {}),
        ),
        Expanded(
          child: items.isEmpty
              ? _Empty(
                  hasSpots: mine.isNotEmpty || friends.isNotEmpty,
                  query: _search.text)
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    if (item.photos) return const FindPhotoStrip();
                    return item.row != null
                        ? _SpotTile(
                            row: item.row!,
                            today: today,
                            coach: index == firstRow)
                        : _SectionHeader(
                            title: item.title!, hint: item.hint!);
                  },
                ),
        ),
      ],
      ),
    );
  }
}

/// Eine Zeile der Liste: Abschnittskopf ODER Spot (Muster aus
/// `species_screen.dart`).
class _Item {
  const _Item.row(this.row)
      : title = null,
        hint = null,
        photos = false;
  const _Item.header(this.title, this.hint)
      : row = null,
        photos = false;
  const _Item.photos()
      : row = null,
        title = null,
        hint = null,
        photos = true;

  final SpotRow? row;
  final String? title;
  final String? hint;

  /// Der Fundfoto-Streifen (#532).
  final bool photos;
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.search,
    required this.owner,
    required this.showOwnerFilter,
    required this.onOwner,
    required this.onSearch,
  });

  final TextEditingController search;
  final SpotOwnerFilter owner;
  final bool showOwnerFilter;
  final ValueChanged<SpotOwnerFilter> onOwner;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          CoachAnchor(
            id: SpotsCoach.search,
            child: TextField(
            controller: search,
            onChanged: (_) => onSearch(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: 'Name, Art oder Buddy',
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Suche leeren',
                      onPressed: () {
                        search.clear();
                        onSearch();
                      },
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          ),
          if (showOwnerFilter) ...[
            const SizedBox(height: 8),
            SegmentedButton<SpotOwnerFilter>(
              showSelectedIcon: false,
              segments: [
                for (final value in SpotOwnerFilter.values)
                  ButtonSegment(value: value, label: Text(value.label)),
              ],
              selected: {owner},
              onSelectionChanged: (selection) => onOwner(selection.first),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          Text(hint,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor)),
        ],
      ),
    );
  }
}

final _dateFormat = DateFormat('d.M.y');

class _SpotTile extends ConsumerWidget {
  const _SpotTile({required this.row, required this.today, this.coach = false});

  final SpotRow row;
  final DateTime today;

  /// Die erste Zeile trägt die Anker der Tour.
  final bool coach;

  /// Springt zur Karte und zentriert den Spot — derselbe Weg, den die
  /// Banner nehmen (#345): erst den Reiter wechseln, dann den Wunsch
  /// stellen. Andersherum liefe die Kamerabewegung, während die Karte
  /// noch im Hintergrund steht.
  void _showOnMap(BuildContext context, WidgetRef ref) {
    StatefulNavigationShell.maybeOf(context)?.goBranch(kMapBranchIndex);
    ref
        .read(mapFocusProvider.notifier)
        .focusOn(LatLng(row.spot.lat, row.spot.lng));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spot = row.spot;
    final last = row.lastEntry;
    final date = last == null
        ? null
        : relativeDay(last.foundOn, today) ?? _dateFormat.format(last.foundOn);

    final mapButton = IconButton(
      icon: const Icon(Icons.map_outlined),
      tooltip: 'Auf der Karte zeigen',
      onPressed: () => _showOnMap(context, ref),
    );
    final tile = InkWell(
      onTap: () => showSpotDetailSheet(context, spot.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MushroomIcon.forSpecies(
              row.species.isEmpty ? null : row.species.first,
              fallbackSeed: spot.id,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(spot.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium),
                      ),
                      if (date != null)
                        Text(date, style: theme.textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(_subtitle(ref.watch(buddyNamesViewProvider)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium),
                  _Meta(row: row, names: ref.watch(buddyNamesViewProvider)),
                ],
              ),
            ),
            coach
                ? CoachAnchor(id: SpotsCoach.rowMap, child: mapButton)
                : mapButton,
          ],
        ),
      ),
    );
    return coach ? CoachAnchor(id: SpotsCoach.row, child: tile) : tile;
  }

  String _subtitle(BuddyNames names) {
    final last = row.lastEntry;
    if (last != null) {
      final who = last.isOwn
          ? ''
          : ' · ${names.of(last.authorId, last.authorUsername)}';
      return '${last.label}$who';
    }
    if (row.isSilent) return 'Nur der Standort wurde geteilt.';
    return row.species.isEmpty
        ? 'Noch keine Art notiert'
        : 'Erwartet: ${row.species.join(', ')}';
  }
}

/// Die kleine Zeile unter dem Eintrag: Umfang, Herkunft, Zustand.
class _Meta extends StatelessWidget {
  const _Meta({required this.row, required this.names});

  final SpotRow row;
  final BuddyNames names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        theme.textTheme.bodySmall?.copyWith(color: theme.hintColor);
    final facts = <String>[
      if (row.species.length > 1) '${row.species.length} Arten',
      if (row.entryCount > 1) '${row.entryCount} Einträge',
    ];
    final owner = row.spot.isOwn
        ? null
        : names.aliasOf(row.spot.ownerId) ?? row.spot.ownerUsername;
    if (facts.isEmpty && owner == null && !row.waiting && !row.hasNews) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          if (owner != null) ...[
            MushroomAvatar(index: row.spot.ownerAvatar, size: 16),
            const SizedBox(width: 4),
            Text(owner, style: style),
            if (facts.isNotEmpty) Text(' · ', style: style),
          ],
          if (facts.isNotEmpty)
            Flexible(
              child: Text(facts.join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
          // Wartet und Neu stehen hinten und tragen ihr eigenes Symbol —
          // dieselbe Sprache wie auf der Karte (Uhr für den
          // Ausgangskorb) und im Banner (Glocke für den Buddy-Fund).
          if (row.waiting) ...[
            const SizedBox(width: 6),
            Icon(Icons.schedule, size: 14, color: theme.hintColor),
            const SizedBox(width: 2),
            Text('wartet', style: style),
          ],
          if (row.hasNews) ...[
            const SizedBox(width: 6),
            const Icon(Icons.circle, size: 8, color: AppColors.friendBlue),
            const SizedBox(width: 3),
            Text('neu',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.friendBlue)),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.hasSpots, required this.query});

  final bool hasSpots;
  final String query;

  @override
  Widget build(BuildContext context) {
    // Derselbe Wortlaut wie der leere Kartenzustand — eine Handlung,
    // eine Formulierung (#350).
    final text = !hasSpots
        ? '🍄 Noch kein eigener Spot — schieb die Karte, bis das '
            'Fadenkreuz in der Mitte auf deiner Stelle liegt, und tipp '
            'auf „Neuer Spot".'
        : query.trim().isEmpty
            ? 'Hier ist nichts — mit dieser Auswahl gibt es keinen Spot.'
            : 'Kein Spot passt zu „${query.trim()}".';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
