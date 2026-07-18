import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/mushroom_avatar.dart';
import '../../data/providers.dart';
import '../../models/find.dart';
import '../spots/spot_providers.dart';
import 'profile_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final spots = ref.watch(mySpotsProvider).valueOrNull ?? [];
    final profile = profileAsync.valueOrNull;

    final allFinds = [for (final s in spots) ...s.finds];
    final revisited = spots.where((s) => s.finds.length > 1).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          IconButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Abmelden',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (profile != null) ...[
            Row(
              children: [
                // Avatar antippen = neuen Pilz-Buddy aussuchen
                InkWell(
                  borderRadius: BorderRadius.circular(32),
                  onTap: () => _pickAvatar(context, ref, profile.avatar),
                  child: Stack(
                    children: [
                      MushroomAvatar(index: profile.avatar, size: 56),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.edit,
                              size: 11, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(profile.username,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Teilen mit Freunden',
                style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Meine Spots mit Freunden teilen'),
              subtitle: const Text(
                  'Einzelne Spots kannst du auf der Karte davon ausnehmen.'),
              value: profile.shareSpotsDefault,
              onChanged: (value) => ref
                  .read(myProfileProvider.notifier)
                  .updateSharing(shareSpotsDefault: value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auch Art, Anzahl und Funddatum teilen'),
              subtitle:
                  const Text('Ausgeschaltet sehen Freunde nur den Standort.'),
              value: profile.shareDetails,
              onChanged: profile.shareSpotsDefault
                  ? (value) => ref
                      .read(myProfileProvider.notifier)
                      .updateSharing(shareDetails: value)
                  : null,
            ),
            const Divider(height: 32),
          ] else if (profileAsync.isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          Text('Statistik', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatTile(label: 'Spots', value: spots.length.toString()),
              const SizedBox(width: 12),
              _StatTile(label: 'Funde', value: allFinds.length.toString()),
              const SizedBox(width: 12),
              _StatTile(label: 'Mehrfach\nbesucht', value: revisited.toString()),
            ],
          ),
          const SizedBox(height: 20),
          if (allFinds.isNotEmpty) ...[
            _FindsPerYearChart(finds: allFinds),
            const SizedBox(height: 20),
            _TopSpecies(finds: allFinds),
            const SizedBox(height: 20),
            _SeasonList(finds: allFinds),
          ] else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Noch keine Funde – halte auf der Karte gedrückt, um deinen ersten Pilz-Spot anzulegen! 🍄'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom-Sheet mit dem Avatar-Katalog — Tap wählt den neuen Buddy.
Future<void> _pickAvatar(
    BuildContext context, WidgetRef ref, int current) async {
  final selected = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Such dir deinen Pilz-Buddy aus!',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Flexible(
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  for (var i = 0; i < kAvatarCatalog.length; i++)
                    InkWell(
                      borderRadius: BorderRadius.circular(40),
                      onTap: () => Navigator.of(context).pop(i),
                      child: Container(
                        decoration: i == current
                            ? BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: const Color(0xFF2E7D32), width: 3),
                              )
                            : null,
                        child: MushroomAvatar(index: i, size: 64),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (selected != null && selected != current) {
    await ref.read(myProfileProvider.notifier).updateAvatar(selected);
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _FindsPerYearChart extends StatelessWidget {
  const _FindsPerYearChart({required this.finds});

  final List<Find> finds;

  @override
  Widget build(BuildContext context) {
    final byYear = <int, int>{};
    for (final f in finds) {
      byYear[f.foundOn.year] = (byYear[f.foundOn.year] ?? 0) + 1;
    }
    final years = byYear.keys.toList()..sort();
    final maxCount =
        byYear.values.reduce((a, b) => a > b ? a : b).toDouble();
    final barColor = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Funde pro Jahr',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  maxY: maxCount * 1.2,
                  barGroups: [
                    for (final year in years)
                      BarChartGroupData(x: year, barRods: [
                        BarChartRodData(
                          toY: byYear[year]!.toDouble(),
                          color: barColor,
                          width: 22,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                      ]),
                  ],
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true, reservedSize: 30, interval: 1),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(value.toInt().toString(),
                              style:
                                  Theme.of(context).textTheme.bodySmall),
                        ),
                      ),
                    ),
                  ),
                  gridData: const FlGridData(drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopSpecies extends StatelessWidget {
  const _TopSpecies({required this.finds});

  final List<Find> finds;

  @override
  Widget build(BuildContext context) {
    final bySpecies = <String, int>{};
    for (final f in finds) {
      final species = f.species;
      if (species == null || species.isEmpty) continue;
      bySpecies[species] = (bySpecies[species] ?? 0) + (f.count ?? 1);
    }
    if (bySpecies.isEmpty) return const SizedBox.shrink();
    final top = bySpecies.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Top-Arten', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final entry in top.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Text('🍄 '),
                    Expanded(child: Text(entry.key)),
                    Text('${entry.value}×',
                        style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SeasonList extends StatelessWidget {
  const _SeasonList({required this.finds});

  final List<Find> finds;

  static const _seasons = ['Frühling', 'Sommer', 'Herbst', 'Winter'];

  int _seasonIndex(DateTime date) {
    if (date.month >= 3 && date.month <= 5) return 0;
    if (date.month >= 6 && date.month <= 8) return 1;
    if (date.month >= 9 && date.month <= 11) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final counts = List<int>.filled(4, 0);
    for (final f in finds) {
      counts[_seasonIndex(f.foundOn)]++;
    }
    final total = finds.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Funde nach Jahreszeit',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (var i = 0; i < 4; i++)
              if (counts[i] > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 80, child: Text(_seasons[i])),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: counts[i] / total,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${counts[i]}'),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
