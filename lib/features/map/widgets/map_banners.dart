import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/providers.dart';
import '../../friends/friend_providers.dart';

/// Feature-Wunsch-Banner nur einmal pro App-Start anzeigen,
/// nachdem es weggeklickt oder ein Wunsch abgeschickt wurde.
final featureBannerDismissedProvider = StateProvider<bool>((ref) => false);

/// Banner oben im Hauptfenster: Neuigkeiten (offene Freundschaftsanfragen)
/// und — solange die App jung ist — ein prominentes Feature-Wunsch-Feld.
class MapBanners extends ConsumerWidget {
  const MapBanners({super.key});

  Future<void> _openFeedbackDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_FeedbackInput>(
      context: context,
      builder: (context) => const _FeedbackDialog(),
    );
    if (result == null) return;

    try {
      if (result.isSpecies) {
        await ref
            .read(feedbackRepositoryProvider)
            .submitSpecies(result.text, note: result.note);
      } else {
        await ref.read(feedbackRepositoryProvider).submitFeature(result.text);
      }
      ref.read(featureBannerDismissedProvider.notifier).state = true;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result.isSpecies
                ? 'Danke! Die Pilzart wird geprüft und kommt dann per Update. 🍄'
                : 'Danke für deinen Wunsch! 🍄')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Senden fehlgeschlagen. Internet verfügbar?')));
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
    final featureDismissed = ref.watch(featureBannerDismissedProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (incoming > 0)
          _banner(
            context,
            background: const Color(0xFF1565C0),
            foreground: Colors.white,
            onTap: () => context.go('/friends'),
            content: Text(incoming == 1
                ? '🔔 1 offene Freundschaftsanfrage — antippen'
                : '🔔 $incoming offene Freundschaftsanfragen — antippen'),
          ),
        if (!featureDismissed)
          _banner(
            context,
            background: const Color(0xFFFFF8E1),
            foreground: const Color(0xFF6D4C41),
            onTap: () => _openFeedbackDialog(context, ref),
            onDismiss: () => ref
                .read(featureBannerDismissedProvider.notifier)
                .state = true,
            content:
                const Text('💡 Feature-Wunsch oder Pilzart vorschlagen!'),
          ),
      ],
    );
  }
}

class _FeedbackInput {
  final bool isSpecies;
  final String text;
  final String? note;

  const _FeedbackInput(this.isSpecies, this.text, this.note);
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog();

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  bool _isSpecies = false;
  final _textController = TextEditingController();
  final _noteController = TextEditingController();

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
      _isSpecies,
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
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('💡 Feature')),
                ButtonSegment(value: true, label: Text('🍄 Pilzart')),
              ],
              selected: {_isSpecies},
              onSelectionChanged: (selection) =>
                  setState(() => _isSpecies = selection.first),
            ),
            const SizedBox(height: 12),
            Text(
              _isSpecies
                  ? 'Welche Pilzart fehlt in der Auswahlliste? Nach kurzer '
                      'Prüfung kommt sie automatisch mit dem nächsten Update.'
                  : 'PilzBuddy ist noch ganz frisch — was fehlt dir, was '
                      'nervt, was wäre praktisch? Jede Idee landet direkt '
                      'beim Entwickler.',
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
                labelText: _isSpecies ? 'Name der Pilzart' : 'Dein Wunsch',
                hintText: _isSpecies
                    ? 'z. B. Violetter Lacktrichterling'
                    : 'z. B. „Fotos zu Funden wären toll!"',
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
