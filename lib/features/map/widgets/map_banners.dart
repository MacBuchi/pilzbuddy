import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors.dart';
import '../../../core/update_check.dart';
import '../../../data/feedback_repository.dart';
import '../../../data/providers.dart';
import '../../friends/friend_providers.dart';
import '../../offline_maps/offline_map_providers.dart';
import '../../../core/app_colors.dart';

/// Feedback-Banner für diese Sitzung ausgeblendet? Wird nur durch das X
/// gesetzt: nach dem Absenden bleibt das Banner stehen, sonst wirkt es, als
/// wäre die Meldemöglichkeit verschwunden (Issue #72).
final feedbackBannerDismissedProvider = StateProvider<bool>((ref) => false);

/// Update-Banner für diese Sitzung ausgeblendet?
final updateBannerDismissedProvider = StateProvider<bool>((ref) => false);

/// Karten-Update-Banner für diese Sitzung ausgeblendet?
final mapUpdateBannerDismissedProvider = StateProvider<bool>((ref) => false);

/// Banner oben im Hauptfenster: Neuigkeiten (offene Freundschaftsanfragen)
/// und — solange die App jung ist — ein prominentes Feature-Wunsch-Feld.
class MapBanners extends ConsumerWidget {
  const MapBanners({super.key});

  Future<void> _openUpdateDialog(BuildContext context, UpdateInfo info) {
    return showDialog<void>(
      context: context,
      builder: (context) => _UpdateDialog(info: info),
    );
  }

  Future<void> _openFeedbackDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_FeedbackInput>(
      context: context,
      builder: (context) => const _FeedbackDialog(),
    );
    if (result == null) return;

    try {
      if (result.type == FeedbackType.species) {
        await ref
            .read(feedbackRepositoryProvider)
            .submitSpecies(result.text, note: result.note);
      } else {
        await ref
            .read(feedbackRepositoryProvider)
            .submit(result.type, result.text);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(switch (result.type) {
          FeedbackType.species =>
            'Danke! Die Pilzart wird geprüft und kommt dann per Update. 🍄',
          FeedbackType.bug =>
            'Danke für die Meldung — wir schauen uns das an! 🐛',
          FeedbackType.feature => 'Danke für deinen Wunsch! 🍄',
        })));
      }
    } catch (e, stackTrace) {
      logError('Feedback senden', e, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Widget _banner(
    BuildContext context, {
    required Color background,
    required Color foreground,
    required Widget content,
    VoidCallback? onTap,
    VoidCallback? onDismiss,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: DefaultTextStyle(
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium!
                        .copyWith(color: foreground),
                    child: content,
                  ),
                ),
                if (onDismiss != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onDismiss,
                    child: Icon(Icons.close, size: 18, color: foreground),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserIdProvider) ?? '';
    final friendships = ref.watch(friendshipsProvider).valueOrNull ?? [];
    final incoming = friendships.where((f) => f.isIncomingFor(uid)).length;
    final feedbackDismissed = ref.watch(feedbackBannerDismissedProvider);

    final updateInfo = ref.watch(updateInfoProvider).valueOrNull;
    final updateDismissed = ref.watch(updateBannerDismissedProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (updateInfo != null && !updateDismissed)
          _banner(
            context,
            background: AppColors.forestGreen,
            foreground: Colors.white,
            onTap: () => _openUpdateDialog(context, updateInfo),
            onDismiss: () => ref
                .read(updateBannerDismissedProvider.notifier)
                .state = true,
            content: Text(
                '🔄 Update auf v${updateInfo.latestVersion} verfügbar'),
          ),
        // Das „Karten-Abo": installierte Offline-Regionen, für die es eine
        // neuere Version gibt — Antippen öffnet die Verwaltung.
        if (!ref.watch(mapUpdateBannerDismissedProvider))
          Builder(builder: (context) {
            final outdated = ref.watch(outdatedMapsProvider);
            if (outdated.isEmpty) return const SizedBox.shrink();
            return _banner(
              context,
              background: AppColors.warmBrown,
              foreground: Colors.white,
              onTap: () => context.push('/profile/offline-maps'),
              onDismiss: () => ref
                  .read(mapUpdateBannerDismissedProvider.notifier)
                  .state = true,
              content: Text(outdated.length == 1
                  ? '🗺️ Neue Offline-Karte für ${outdated.first.label} '
                      'verfügbar — antippen'
                  : '🗺️ ${outdated.length} neue Offline-Karten verfügbar '
                      '— antippen'),
            );
          }),
        if (incoming > 0)
          _banner(
            context,
            background: AppColors.friendBlue,
            foreground: Colors.white,
            onTap: () => context.go('/friends'),
            content: Text(incoming == 1
                ? '🔔 1 offene Freundschaftsanfrage — antippen'
                : '🔔 $incoming offene Freundschaftsanfragen — antippen'),
          ),
        if (!feedbackDismissed)
          _banner(
            context,
            background: AppColors.sunshine,
            foreground: AppColors.warmBrown,
            onTap: () => _openFeedbackDialog(context, ref),
            onDismiss: () => ref
                .read(feedbackBannerDismissedProvider.notifier)
                .state = true,
            content: const Text('💡 Wunsch, Fehler oder Pilzart melden!'),
          ),
      ],
    );
  }
}

/// Update-Dialog: lädt die APK mit Fortschrittsbalken direkt in der App
/// herunter und öffnet anschließend den Android-Installer. Schlägt das
/// fehl, bleibt der Browser-Download als Fallback.
class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});

  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

enum _UpdatePhase { idle, downloading, installing, error }

class _UpdateDialogState extends State<_UpdateDialog> {
  _UpdatePhase _phase = _UpdatePhase.idle;
  double _progress = 0;
  StreamSubscription<OtaEvent>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() => _phase = _UpdatePhase.downloading);
    try {
      _subscription = OtaUpdate()
          .execute(widget.info.downloadUrl,
              destinationFilename: 'pilzbuddy-update.apk')
          .listen(
        (event) {
          if (!mounted) return;
          switch (event.status) {
            case OtaStatus.DOWNLOADING:
              setState(() {
                _phase = _UpdatePhase.downloading;
                _progress = (double.tryParse(event.value ?? '') ?? 0) / 100;
              });
            case OtaStatus.INSTALLING:
              setState(() => _phase = _UpdatePhase.installing);
            default:
              setState(() => _phase = _UpdatePhase.error);
          }
        },
        onError: (Object _) {
          if (mounted) setState(() => _phase = _UpdatePhase.error);
        },
      );
    } catch (e, stackTrace) {
      logError('Update-Download', e, stackTrace);
      setState(() => _phase = _UpdatePhase.error);
    }
  }

  Future<void> _browserFallback() async {
    await launchUrl(Uri.parse(widget.info.downloadUrl),
        mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return AlertDialog(
      title: Text('Update auf v${info.latestVersion}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            switch (_phase) {
              _UpdatePhase.idle => const Text(
                  'Das Update lädt direkt in der App und öffnet dann den '
                  'Android-Installer — deine Spots bleiben erhalten. '
                  'Beim ersten Mal fragt Android einmalig um Erlaubnis.'),
              _UpdatePhase.downloading => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Lade herunter … ${(_progress * 100).round()} %'),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null),
                  ],
                ),
              _UpdatePhase.installing => const Text(
                  'Download fertig — Android fragt jetzt, ob PilzBuddy '
                  'aktualisiert werden soll. Einfach bestätigen!'),
              _UpdatePhase.error => const Text(
                  'Der Direkt-Download hat nicht geklappt. Du kannst das '
                  'Update stattdessen über den Browser laden — nach dem '
                  'Download in der Benachrichtigung auf die Datei tippen.'),
            },
            if (_phase == _UpdatePhase.idle &&
                info.releaseNotes != null &&
                info.releaseNotes!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Was ist neu:',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(info.releaseNotes!.trim(),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
      actions: [
        if (_phase == _UpdatePhase.idle) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Später'),
          ),
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Jetzt aktualisieren'),
          ),
        ] else if (_phase == _UpdatePhase.error) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schließen'),
          ),
          FilledButton.icon(
            onPressed: _browserFallback,
            icon: const Icon(Icons.open_in_browser, size: 18),
            label: const Text('Im Browser laden'),
          ),
        ] else
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schließen'),
          ),
      ],
    );
  }
}

class _FeedbackInput {
  final FeedbackType type;
  final String text;
  final String? note;

  const _FeedbackInput(this.type, this.text, this.note);
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog();

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  FeedbackType _type = FeedbackType.feature;
  final _textController = TextEditingController();
  final _noteController = TextEditingController();

  bool get _isSpecies => _type == FeedbackType.species;

  @override
  void dispose() {
    _textController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _textController.text.trim();
    if (text.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isSpecies
              ? 'Bitte gib den Namen der Pilzart an.'
              : 'Bitte schreib ein paar Worte mehr. 🙂')));
      return;
    }
    Navigator.of(context).pop(_FeedbackInput(
      _type,
      text,
      _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Wünsch dir was!'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<FeedbackType>(
              segments: const [
                ButtonSegment(
                    value: FeedbackType.feature, label: Text('💡 Feature')),
                ButtonSegment(value: FeedbackType.bug, label: Text('🐛 Bug')),
                ButtonSegment(
                    value: FeedbackType.species, label: Text('🍄 Pilzart')),
              ],
              selected: {_type},
              onSelectionChanged: (selection) =>
                  setState(() => _type = selection.first),
            ),
            const SizedBox(height: 12),
            Text(
              switch (_type) {
                FeedbackType.species =>
                  'Welche Pilzart fehlt in der Auswahlliste? Nach kurzer '
                      'Prüfung kommt sie automatisch mit dem nächsten Update.',
                FeedbackType.bug =>
                  'Was funktioniert nicht? Beschreibe kurz, was du gemacht '
                      'hast und was stattdessen passiert ist.',
                FeedbackType.feature =>
                  'PilzBuddy ist noch ganz frisch — was fehlt dir, was '
                      'nervt, was wäre praktisch? Jede Idee landet direkt '
                      'beim Entwickler.',
              },
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              autofocus: true,
              maxLines: _isSpecies ? 1 : 4,
              maxLength: _isSpecies ? 80 : 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: switch (_type) {
                  FeedbackType.species => 'Name der Pilzart',
                  FeedbackType.bug => 'Was ist passiert?',
                  FeedbackType.feature => 'Dein Wunsch',
                },
                hintText: switch (_type) {
                  FeedbackType.species => 'z. B. Violetter Lacktrichterling',
                  FeedbackType.bug =>
                    'z. B. „Beim Löschen eines Spots bleibt der Marker stehen"',
                  FeedbackType.feature => 'z. B. „Fotos zu Funden wären toll!"',
                },
                border: const OutlineInputBorder(),
              ),
            ),
            if (_isSpecies) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Anmerkung (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'ℹ️ Dein Text erscheint zusammen mit deinem Benutzernamen '
              'öffentlich im GitHub-Projekt der App — bitte keine '
              'persönlichen Daten hineinschreiben.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send, size: 18),
          label: const Text('Senden'),
        ),
      ],
    );
  }
}
