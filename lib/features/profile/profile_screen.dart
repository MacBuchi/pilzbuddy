import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_distribution.dart';
import '../../core/app_info.dart';
import '../../core/errors.dart';
import '../../core/update_check.dart';
import '../../core/widgets/mushroom_avatar.dart';
import '../../data/providers.dart';
import '../../models/find.dart';
import '../import_export/gpx_export.dart';
import '../spots/spot_providers.dart';
import 'profile_providers.dart';
import '../../core/app_colors.dart';

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
            const SizedBox.shrink(),
          // Offline-Karten gibt es nur in der Android-App — im Web ist
          // die Online-Karte ohnehin immer da.
          if (!kIsWeb) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.map_outlined),
              title: const Text('Offline-Karten'),
              subtitle:
                  const Text('Deine Region herunterladen — Karte ohne Empfang'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/profile/offline-maps'),
            ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Punkte importieren'),
            subtitle: const Text(
                'GPX/KML aus anderen Karten-Apps — je Punkt einen Spot anlegen'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile/import'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('Eigene Spots als GPX exportieren'),
            subtitle: const Text(
                'Alle deine Spots samt Fundhistorie für andere Karten-Apps'),
            onTap: () => _exportGpx(context, ref),
          ),
          const Divider(height: 32),
          if (profile == null && profileAsync.isLoading)
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
          const Divider(height: 40),
          const _AboutSection(),
          const Divider(height: 40),
          _DeleteAccountTile(username: profile?.username),
        ],
      ),
    );
  }
}

/// Konto endgültig löschen — bewusst ganz unten und optisch abgesetzt.
class _DeleteAccountTile extends ConsumerWidget {
  const _DeleteAccountTile({required this.username});

  final String? username;

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final name = username;
    if (name == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => _DeleteAccountDialog(username: name),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      // Der Router schickt nach dem Abmelden automatisch auf /login.
    } catch (e, stackTrace) {
      logError('Konto löschen', e, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = Theme.of(context).colorScheme.error;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(Icons.no_accounts_outlined, color: error),
      title: Text('Konto löschen', style: TextStyle(color: error)),
      subtitle: const Text(
          'Entfernt dich und alle deine Spots endgültig — ohne Karenzzeit.'),
      // Ohne geladenes Profil fehlt der Benutzername für die Bestätigung.
      enabled: username != null,
      onTap: () => _confirmAndDelete(context, ref),
    );
  }
}

/// Bestätigung durch Abtippen des Benutzernamens. Ein Ja/Nein-Dialog wäre
/// für eine unwiderrufliche Aktion zu leicht versehentlich zu treffen.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.username});

  final String username;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _matches => _controller.text.trim() == widget.username;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Konto endgültig löschen?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Sofort und unwiderruflich gelöscht werden: dein Profil, '
                'alle Spots samt Fundhistorie, deine Freundschaften und ein '
                'laufend geteilter Standort.'),
            const SizedBox(height: 12),
            const Text(
                'Deine Spots verschwinden damit auch von den Karten deiner '
                'Freunde — geteilte Spots sind Kopien deiner Daten, keine '
                'eigenen.'),
            const SizedBox(height: 12),
            Text(
              'Bereits abgeschicktes Feedback bleibt bestehen: es steht mit '
              'deinem Benutzernamen öffentlich im GitHub-Projekt und lässt '
              'sich von hier aus nicht zurückholen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text('Tippe „${widget.username}" ein, um zu bestätigen:'),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Benutzername',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: (!_matches || _busy)
              ? null
              : () {
                  setState(() => _busy = true);
                  Navigator.of(context).pop(true);
                },
          child: const Text('Endgültig löschen'),
        ),
      ],
    );
  }
}

/// Dezente „Über"-Sektion am Ende des Profils: Version, Update-Status
/// und die öffentlichen Links der App.
class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).valueOrNull ?? '–';
    final updateInfo = ref.watch(updateInfoProvider).valueOrNull;
    final updateStatus = kIsWeb
        ? 'Die Web-App ist immer aktuell.'
        : !AppDistribution.showsUpdateHints
            // Play-Build: der Store aktualisiert selbst, die App prüft nichts.
            ? 'Updates kommen über den Play Store.'
            : updateInfo != null
                ? 'Neueste Version: v${updateInfo.latestVersion} — Update über '
                    'das Banner auf der Karte.'
                : 'Du bist auf dem aktuellen Stand.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Über PilzBuddy',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Version $version — $updateStatus',
            style: Theme.of(context).textTheme.bodySmall),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.code),
          title: const Text('GitHub-Projekt & Dokumentation'),
          subtitle: const Text(AppInfo.githubUrl),
          onTap: () => _open(AppInfo.githubUrl),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.public),
          title: const Text('Web-App'),
          subtitle: const Text(AppInfo.webAppUrl),
          onTap: () => _open(AppInfo.webAppUrl),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.description_outlined),
          title: const Text('Open-Source-Lizenzen'),
          subtitle: const Text('PilzBuddy steht unter der MIT-Lizenz'),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'PilzBuddy',
            applicationVersion: version,
            applicationLegalese: '© 2026 Marcus Bucher — MIT-Lizenz',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Kartendaten: © OpenStreetMap-Mitwirkende',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Eigene Spots als GPX teilen; wo das System-Teilen nicht verfügbar ist
/// (z. B. Desktop-Browser), landet das GPX in der Zwischenablage.
Future<void> _exportGpx(BuildContext context, WidgetRef ref) async {
  void message(String text) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(text)));
    }
  }

  final spots = ref.read(mySpotsProvider).valueOrNull ?? [];
  if (spots.isEmpty) {
    message('Noch keine eigenen Spots zum Exportieren.');
    return;
  }
  final gpx = buildGpx(spots);
  try {
    final result = await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(
          utf8.encode(gpx),
          name: 'pilzbuddy-spots.gpx',
          mimeType: 'application/gpx+xml',
        ),
      ],
      fileNameOverrides: ['pilzbuddy-spots.gpx'],
    ));
    if (result.status == ShareResultStatus.unavailable) {
      throw StateError('share unavailable');
    }
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: gpx));
    message('GPX in die Zwischenablage kopiert '
        '(${spots.length} Spots).');
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
                                    color: AppColors.forestGreen, width: 3),
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
