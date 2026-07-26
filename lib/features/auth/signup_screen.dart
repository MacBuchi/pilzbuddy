import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/widgets/form_notice.dart';
import '../../core/widgets/password_field.dart';
import '../../data/providers.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  /// Gesetzt, sobald das Konto angelegt ist, die Adresse aber noch
  /// bestätigt werden muss. Dann zeigt der Screen keine Felder mehr,
  /// sondern was als Nächstes zu tun ist.
  String? _awaitingConfirmationFor;
  final _codeController = TextEditingController();

  /// Rückmeldung in der Bestätigungsansicht — dort ist sie inline besser
  /// aufgehoben als in einer SnackBar: Der Nutzer wechselt zwischen App und
  /// Postfach, und eine SnackBar ist beim Zurückkommen längst weg (#131).
  String? _notice;
  NoticeTone _noticeTone = NoticeTone.info;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// Rückmeldung auf dem Formular. Bewusst weiter eine SnackBar: Dort ist
  /// sie etabliert, und der Nutzer bleibt beim Ausfüllen im Screen.
  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _setNotice(String message, NoticeTone tone) => setState(() {
        _notice = message;
        _noticeTone = tone;
      });

  Future<void> _signUp() async {
    final username = _usernameController.text.trim();
    if (username.length < 3) {
      _showMessage('Der Benutzername braucht mindestens 3 Zeichen.');
      return;
    }
    if (_passwordController.text.length < minPasswordLength) {
      _showMessage(
          'Das Passwort braucht mindestens $minPasswordLength Zeichen.');
      return;
    }
    setState(() => _busy = true);
    try {
      final email = _emailController.text.trim();
      final needsConfirmation =
          await ref.read(authRepositoryProvider).signUp(
                email: email,
                password: _passwordController.text,
                username: username,
              );
      // Erst nach erfolgreicher Registrierung darf der Passwortmanager
      // speichern.
      TextInput.finishAutofillContext();
      // Mit Bestätigungspflicht liefert signUp keine Sitzung — dann
      // bewegt sich der Router nicht, und ohne diesen Zustand stünde der
      // Screen einfach stumm da (Issue #129). Ohne Pflicht ist der Nutzer
      // angemeldet und der Router schickt zur Karte; dann bleibt hier
      // alles wie bisher.
      if (needsConfirmation && mounted) {
        setState(() => _awaitingConfirmationFor = email);
      }
    } on AuthException catch (e) {
      if (mounted) _showMessage(signupErrorMessage(e));
    } catch (e, stackTrace) {
      logError('Registrierung', e, stackTrace);
      if (mounted) _showMessage(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final email = _awaitingConfirmationFor;
    if (email == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).resendConfirmation(email);
      if (mounted) {
        _setNotice('Die Bestätigungsmail ist noch einmal unterwegs.',
            NoticeTone.success);
      }
    } on AuthException catch (e) {
      // Häufigster Fall: zu schnell hintereinander (Rate Limit) — den nennt
      // confirmErrorMessage beim Namen.
      if (mounted) _setNotice(confirmErrorMessage(e), NoticeTone.error);
    } catch (e, stackTrace) {
      logError('Bestätigungsmail erneut senden', e, stackTrace);
      if (mounted) _setNotice(friendlyError(e), NoticeTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final email = _awaitingConfirmationFor;
    if (email == null) return;
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _setNotice('Bitte den Code aus der Mail eingeben.', NoticeTone.error);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .confirmEmailWithCode(email: email, code: code);
      // Erfolg meldet an; der Router übernimmt und führt zur Karte.
    } on AuthException catch (e) {
      if (mounted) _setNotice(confirmErrorMessage(e), NoticeTone.error);
    } catch (e, stackTrace) {
      logError('Adresse bestätigen', e, stackTrace);
      if (mounted) _setNotice(friendlyError(e), NoticeTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _confirmationHint(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.mark_email_unread_outlined,
              size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('Fast geschafft!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            'Wir haben einen Code an $_awaitingConfirmationFor geschickt. '
            'Gib ihn hier ein, dann geht es direkt weiter.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _busy ? null : _confirm(),
            decoration: const InputDecoration(
              labelText: 'Code aus der Mail',
              border: OutlineInputBorder(),
            ),
          ),
          if (_notice != null) ...[
            const SizedBox(height: 16),
            FormNotice(message: _notice!, tone: _noticeTone),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _confirm,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Adresse bestätigen'),
          ),
          TextButton(
            onPressed: _busy ? null : _resend,
            child: const Text('Mail nicht angekommen? Erneut senden'),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrieren')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _awaitingConfirmationFor != null
                ? _confirmationHint(context)
                : _signUpForm(context),
          ),
        ),
      ),
    );
  }

  Widget _signUpForm(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Siehe login_screen.dart: ohne AutofillGroup kein Autofill.
          AutofillGroup(
            onDisposeAction: AutofillContextAction.cancel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newUsername],
                  decoration: const InputDecoration(
                    labelText: 'Benutzername',
                    helperText: 'Darüber können Freunde dich finden.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'E-Mail',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                PasswordField(
                  controller: _passwordController,
                  label: 'Passwort (mind. $minPasswordLength Zeichen)',
                  autofillHints: const [AutofillHints.newPassword],
                  onSubmitted: (_) => _busy ? null : _signUp(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _signUp,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Konto erstellen'),
          ),
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text('Schon ein Konto? Anmelden'),
          ),
        ],
      );
}
