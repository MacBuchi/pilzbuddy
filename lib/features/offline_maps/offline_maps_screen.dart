import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'offline_map_providers.dart';
import 'offline_map_repository.dart';
import 'region_catalog.dart';

/// Verwaltung der Offline-Karten: Regionen herunterladen, aktualisieren
/// und löschen. Nur auf Android erreichbar (Einstieg im Profil).
class OfflineMapsScreen extends ConsumerStatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  ConsumerState<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends ConsumerState<OfflineMapsScreen> {
  String _formatSize(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1000) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.round()} MB';
  }

  /// Der Download selbst läuft im app-weiten [mapDownloadsProvider] und
  /// überlebt damit Tab-Wechsel und Navigation (#38) — hier bleiben nur
  /// die Erfolgs-/Fehlermeldungen, falls der Screen noch offen ist.
  Future<void> _download(AvailableMap map) async {
    try {
      await ref.read(mapDownloadsProvider.notifier).start(map);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${map.label} ist jetzt offline verfügbar 🗺️')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Download von ${map.label} fehlgeschlagen. Internet verfügbar?')));
      }
    }
  }

  Future<void> _delete(InstalledMap map) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${map.label} löschen?'),
        content: Text(
            'Die Offline-Karte (${_formatSize(map.sizeBytes)}) wird vom Gerät entfernt.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(installedMapsProvider.notifier).delete(map.key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableAsync = ref.watch(availableMapsProvider);
    final installed =
        ref.watch(installedMapsProvider).valueOrNull ?? const <InstalledMap>[];
    final installedByKey = {for (final m in installed) m.key: m};

    return Scaffold(
      appBar: AppBar(title: const Text('Offline-Karten')),
      body: availableAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _ErrorRetry(
            onRetry: () => ref.invalidate(availableMapsProvider)),
        data: (available) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Lade deine Region herunter, dann funktioniert die Karte '
                  'auch ohne Empfang im Wald. Am besten im WLAN laden — '
                  'die Karten sind mehrere hundert MB groß.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final map in available)
              _mapTile(map, installedByKey[map.key]),
            const SizedBox(height: 16),
            Text(
              'Kartendaten: © OpenStreetMap-Mitwirkende (ODbL), '
              'Protomaps Basemap',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapTile(AvailableMap map, InstalledMap? installedVersion) {
    final progress = ref.watch(mapDownloadsProvider)[map.key];
    final isCurrent = installedVersion?.dateStamp == map.dateStamp;
    final hasUpdate = installedVersion != null && !isCurrent;

    final subtitle = progress != null
        ? 'Lädt … ${(progress * 100).round()} %'
        : installedVersion != null
            ? 'Installiert (Stand ${formatDateStamp(installedVersion.dateStamp)})'
                '${hasUpdate ? ' — Update verfügbar' : ''}'
            : _formatSize(map.sizeBytes);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        installedVersion != null ? Icons.download_done : Icons.map_outlined,
        color: installedVersion != null ? const Color(0xFF2E7D32) : null,
      ),
      title: Text(map.label),
      subtitle: progress != null
          ? Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subtitle),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: progress > 0 ? progress : null),
                ],
              ),
            )
          : Text(subtitle),
      trailing: progress != null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (installedVersion == null || hasUpdate)
                  IconButton(
                    onPressed: () => _download(map),
                    icon: Icon(hasUpdate ? Icons.update : Icons.download),
                    tooltip: hasUpdate
                        ? '${map.label} aktualisieren'
                        : '${map.label} herunterladen',
                  ),
                if (installedVersion != null)
                  IconButton(
                    onPressed: () => _delete(installedVersion),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '${map.label} löschen',
                  ),
              ],
            ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Kartenliste konnte nicht geladen werden. '
                'Internet verfügbar?'),
          ),
          FilledButton.tonal(
              onPressed: onRetry, child: const Text('Nochmal versuchen')),
        ],
      ),
    );
  }
}
