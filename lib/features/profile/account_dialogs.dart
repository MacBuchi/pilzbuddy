// Konto-Dialoge des Profils, die nicht Passwort oder Löschen sind.
//
// Eigene Datei mit Absicht: profile_screen.dart trägt schon fast 900
// Zeilen, und die Konto-Verwaltung wächst (Benutzername hier, E-Mail
// folgt mit #193). Muster ist `_ChangePasswordDialog` von dort — Kachel
// öffnet Dialog, Fehler als FormNotice im Dialog, Erfolg als SnackBar
// nach dem Schließen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/widgets/form_notice.dart';
import '../../models/profile.dart';
import 'profile_providers.dart';

/// Kachel „Benutzername ändern" — nur sinnvoll, wenn das Profil geladen
/// ist, sonst gäbe es keinen aktuellen Namen zum Vorbefüllen.
class ChangeUsernameTile extends ConsumerWidget {
  const ChangeUsernameTile({super.key, required this.username});

  final String? username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = username;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.badge_outlined),
      title: const Text('Benutzername ändern'),
      subtitle: const Text('Der Name, unter dem Freunde dich finden'),
      trailing: const Icon(Icons.chevron_right),
      enabled: name != null,
      onTap: name == null
          ? null
          : () => showDialog<void>(
                context: context,
                builder: (_) => _ChangeUsernameDialog(current: name),
              ),
    );
  }
}

class _ChangeUsernameDialog extends ConsumerStatefulWidget {
  const _ChangeUsernameDialog({required this.current});

  final String current;

  @override
  ConsumerState<_ChangeUsernameDialog> createState() =>
      _ChangeUsernameDialogState();
}

class _ChangeUsernameDialogState extends ConsumerState<_ChangeUsernameDialog> {
  late final _controller = TextEditingController(text: widget.current);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _trimmed => _controller.text.trim();

  bool get _canSave =>
      _trimmed.length >= minUsernameLength && _trimmed != widget.current;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(myProfileProvider.notifier)
          .updateUsername(_trimmed);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dein Benutzername ist geändert.')),
      );
    } catch (e, stackTrace) {
      // Der vergebene Name ist der erwartbare Fall und KEIN Fall für
      // error_reports — nur Unerwartetes wird gemeldet.
      if (usernameChangeErrorMessage(e) == friendlyError(e)) {
        logError('Benutzername ändern', e, stackTrace);
      }
      if (mounted) setState(() => _error = usernameChangeErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Benutzername ändern'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Neuer Benutzername',
                helperText: 'Mindestens $minUsernameLength Zeichen',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => (_canSave && !_busy) ? _save() : null,
            ),
            const SizedBox(height: 8),
            Text(
              // Die Suche läuft über das Namens-Präfix — das gehört
              // gesagt, bevor jemand seinen bekannten Namen aufgibt.
              'Freunde finden dich künftig unter dem neuen Namen.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              FormNotice(message: _error!, tone: NoticeTone.error),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: (!_canSave || _busy) ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Speichern'),
        ),
      ],
    );
  }
}
