import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../map/forest_preload_providers.dart';
import 'offline_map_providers.dart';
import 'offline_map_repository.dart';
import 'region_catalog.dart';
import '../../core/app_colors.dart';

/// Verwaltung der Offline-Karten: Regionen herunterladen, aktualisieren
/// und löschen. Der Einstieg im Profil steht nur auf Android.
///
/// Die ROUTE gibt es trotzdem überall, und deshalb erklärt sich der Screen
/// im Browser selbst, statt eine leere Liste zu zeigen: Wer die Adresse
/// direkt aufruft (oder ein altes Lesezeichen hat), bekämpfe sonst einen
/// Fehler, den es nicht gibt. „Kein Fehler ohne Fehlermeldung" gilt auch
/// für „geht hier nicht".
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
    } catch (e, stackTrace) {
      logError('Karten-Download ${map.key}', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Download von ${map.label}: ${friendlyError(e)}')));
      }
    }
  }

  /// Der Wald-Vorlauf (#264). Läuft wie der Karten-Download im
  /// app-weiten Provider und überlebt damit das Verlassen des Screens.
  Future<void> _preloadForest() async {
    try {
      final complete = await ref.read(forestPreloadProvider.notifier).start();
      if (mounted && complete) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Feine Waldkarte ist jetzt offline verfügbar 🌲')));
      }
    } catch (e, stackTrace) {
      logError('Wald-Vorlauf', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Feine Waldkarte: ${friendlyError(e)}')));
      }
    }
  }

  Future<void> _deleteForest(int bytes) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Feine Waldkarte löschen?'),
        content: Text('Die feinen Waldblöcke (${_formatSize(bytes)}) werden '
            'vom Gerät entfernt. Die Waldtypen-Ebene zeigt dann wieder '
            'die eingebaute Karte mit Waben von ≈ 250 m.'),
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
      await ref.read(forestPreloadProvider.notifier).delete();
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
    if (!ref.watch(offlineMapsSupportedProvider)) {
      return const _NotOnThisPlatform();
    }
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
            // Der Auto-Nachlauf (#332) steht hier und nicht im Profil:
            // Direkt darüber stehen die Größen, um die es geht.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.update),
              title: const Text('Im WLAN von selbst aktualisieren'),
              subtitle: const Text(
                  'Bringt Regionen auf den neuen Stand, die schon auf dem '
                  'Gerät liegen — neue lädt er nie. Nur in einem WLAN ohne '
                  'Datenkosten; ein Handy-Hotspot zählt für Android nicht '
                  'dazu. Fällt es weg, hält der Download an und macht '
                  'später weiter.'),
              value: ref.watch(mapAutoUpdateEnabledProvider),
              onChanged: (value) =>
                  ref.read(mapAutoUpdateEnabledProvider.notifier).set(value),
            ),
            const Divider(height: 32),
            Text('Waldkarte',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              // Der ehrliche Unterschied zu den Regionskarten: Das hier
              // ist keine Karte zum Ansehen, sondern die Datengrundlage
              // der Waldtypen-Ebene — und sie kommt sonst erst
              // unterwegs, also dort, wo kein Empfang ist.
              'Die Waldtypen-Ebene rechnet mit Waben von ≈ 250 m. Die '
              'feine Stufe (≈ 100 m) lädt die App sonst erst unterwegs '
              'nach, wenn du nah genug herangezoomt hast. Hier holst du '
              'sie im Voraus — für Deutschland, Österreich und die '
              'Schweiz.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            _forestTile(),
            const SizedBox(height: 16),
            Text(
              'Kartendaten: © OpenStreetMap-Mitwirkende (ODbL), '
              'Protomaps Basemap. Waldtypen: © Europäische Union, '
              'Copernicus Land Monitoring Service',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapTile(AvailableMap map, InstalledMap? installedVersion) {
    final download = ref.watch(mapDownloadsProvider)[map.key];
    final isCurrent = installedVersion?.dateStamp == map.dateStamp;
    final hasUpdate = installedVersion != null && !isCurrent;

    final subtitle = download != null
        ? download.waitingForNetwork
            ? 'Wartet auf Netz … '
                '(${(download.progress * 100).round()} % geladen)'
            : 'Lädt … ${(download.progress * 100).round()} %'
        : installedVersion != null
            ? 'Installiert (Stand ${formatDateStamp(installedVersion.dateStamp)})'
                '${hasUpdate ? ' — Update verfügbar' : ''}'
            : _formatSize(map.sizeBytes);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        installedVersion != null ? Icons.download_done : Icons.map_outlined,
        color: installedVersion != null ? AppColors.forestGreen : null,
      ),
      title: Text(map.label),
      subtitle: download != null
          ? Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subtitle),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                      value: download.waitingForNetwork ||
                              download.progress <= 0
                          ? null
                          : download.progress),
                ],
              ),
            )
          : Text(subtitle),
      trailing: download != null
          ? IconButton(
              onPressed: () =>
                  ref.read(mapDownloadsProvider.notifier).cancel(map.key),
              icon: const Icon(Icons.close),
              tooltip: '${map.label} anhalten',
            )
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

  /// Die Kachel der feinen Waldstufe — dieselbe Optik wie eine
  /// Regionskarte, damit hier nichts Neues gelernt werden muss.
  ///
  /// Der Status ist `null`, solange die Zustimmung fehlt (dann wurde der
  /// Katalog nie geholt, #253). Die Kachel nennt dann die ungefähre
  /// Größe; genau wird sie mit dem ersten Tippen, das zugleich die
  /// Zustimmung ist.
  Widget _forestTile() {
    final download = ref.watch(forestPreloadProvider);
    final status = ref.watch(forestPreloadStatusProvider).valueOrNull;
    final complete = status != null && status.blocks >= status.totalBlocks;
    final partial = status != null && status.blocks > 0 && !complete;

    final subtitle = download != null
        ? download.waitingForNetwork
            ? 'Wartet auf Netz … '
                '(${(download.progress * 100).round()} % geladen)'
            : 'Lädt … ${(download.progress * 100).round()} %'
        : complete
            ? 'Vollständig geladen (${_formatSize(status.bytes)})'
            : partial
                ? '${status.blocks} von ${status.totalBlocks} Teilen '
                    '(${_formatSize(status.bytes)}) — Rest fehlt noch'
                : status != null
                    ? _formatSize(status.totalBytes)
                    : 'rund $forestPreloadApproxMb MB';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        complete ? Icons.download_done : Icons.forest_outlined,
        color: complete ? AppColors.forestGreen : null,
      ),
      title: const Text('Feine Waldkarte (≈ 100 m)'),
      subtitle: download != null
          ? Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subtitle),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                      value: download.waitingForNetwork ||
                              download.progress <= 0
                          ? null
                          : download.progress),
                ],
              ),
            )
          : Text(subtitle),
      trailing: download != null
          ? IconButton(
              onPressed: () =>
                  ref.read(forestPreloadProvider.notifier).cancel(),
              icon: const Icon(Icons.close),
              tooltip: 'Feine Waldkarte anhalten',
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!complete)
                  IconButton(
                    onPressed: _preloadForest,
                    icon: const Icon(Icons.download),
                    tooltip: partial
                        ? 'Feine Waldkarte vervollständigen'
                        : 'Feine Waldkarte herunterladen',
                  ),
                if (status != null && status.blocks > 0)
                  IconButton(
                    onPressed: () => _deleteForest(status.bytes),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Feine Waldkarte löschen',
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

/// Was der Browser hier zu sehen bekommt.
///
/// Bewusst mit dem GRUND und nicht nur mit „geht nicht": Die Karten sind
/// Anhänge eines fremden GitHub-Releases, und die gibt ein Browser wegen
/// CORS nicht heraus — daran kann die App nichts ändern. Der Hinweis auf
/// die Android-App ist die einzige ehrliche Antwort.
class _NotOnThisPlatform extends StatelessWidget {
  const _NotOnThisPlatform();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline-Karten')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.map_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                'Offline-Karten gibt es nur in der Android-App.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Die Regionskarten sind mehrere hundert Megabyte groß und '
                'liegen auf einem Server, der sie an einen Browser nicht '
                'herausgibt. Im Browser bleibt die Online-Karte — und wenn '
                'der Empfang wegbricht, eine grobe Übersichtskarte.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
