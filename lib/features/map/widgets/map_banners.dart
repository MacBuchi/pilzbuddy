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
    final controller = TextEditingController();
    final sent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Text('💡 ', style: TextStyle(fontSize: 20)),
            Expanded(child: Text('Wünsch dir ein Feature')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'PilzBuddy ist noch ganz frisch — was fehlt dir, was nervt, '
                'was wäre praktisch? Jede Idee landet direkt beim Entwickler.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'z. B. „Fotos zu Funden wären toll!"',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Senden'),
          ),
        ],
      ),
    );

    final message = controller.text.trim();
    controller.dispose();
    if (sent != true) return;
    if (message.length < 3) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Bitte schreib ein paar Worte mehr. 🙂')));
      }
      return;
    }
    try {
      await ref.read(feedbackRepositoryProvider).submit(message);
      ref.read(featureBannerDismissedProvider.notifier).state = true;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Danke für deinen Wunsch! 🍄')));
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
            content: const Text('💡 Wünsch dir ein Feature für PilzBuddy!'),
          ),
      ],
    );
  }
}
