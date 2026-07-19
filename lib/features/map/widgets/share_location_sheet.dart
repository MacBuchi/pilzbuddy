import 'package:flutter/material.dart';

import '../../../core/app_colors.dart';

/// Auswahl des Nutzers im Standort-Teilen-Sheet.
enum ShareAction { share1h, share2h, share4h, stop }

extension ShareActionDuration on ShareAction {
  /// Teilen-Dauer, oder null für „beenden".
  Duration? get duration => switch (this) {
        ShareAction.share1h => const Duration(hours: 1),
        ShareAction.share2h => const Duration(hours: 2),
        ShareAction.share4h => const Duration(hours: 4),
        ShareAction.stop => null,
      };
}

/// Bottom-Sheet zum Starten/Verlängern/Beenden des Live-Standort-Teilens.
/// Gibt die Wahl zurück oder null, wenn abgebrochen wurde.
Future<ShareAction?> showShareLocationSheet(
  BuildContext context, {
  required bool active,
  DateTime? expiresAt,
}) {
  return showModalBottomSheet<ShareAction>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final until = expiresAt == null
          ? null
          : TimeOfDay.fromDateTime(expiresAt.toLocal()).format(context);
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.share_location,
                        color: AppColors.friendBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        active
                            ? 'Du teilst deinen Standort'
                            : 'Standort mit Buddies teilen',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  active && until != null
                      ? 'Deine Freunde sehen dich noch bis $until Uhr live '
                          'auf der Karte.'
                      : 'Deine Freunde sehen dich für die gewählte Dauer live '
                          'auf der Karte. Du kannst jederzeit beenden.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text(active ? 'Verlängern:' : 'Dauer wählen:',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _durationButton(context, '1 Std.', ShareAction.share1h),
                    const SizedBox(width: 8),
                    _durationButton(context, '2 Std.', ShareAction.share2h),
                    const SizedBox(width: 8),
                    _durationButton(context, '4 Std.', ShareAction.share4h),
                  ],
                ),
                if (active) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        Navigator.of(context).pop(ShareAction.stop),
                    icon: const Icon(Icons.location_off),
                    label: const Text('Teilen beenden'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget _durationButton(BuildContext context, String label, ShareAction action) {
  return Expanded(
    child: FilledButton(
      onPressed: () => Navigator.of(context).pop(action),
      child: Text(label),
    ),
  );
}
