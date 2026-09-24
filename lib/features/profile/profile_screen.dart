import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:url_launcher/url_launcher.dart';

import '../help/map_tour.dart';
import '../offline_maps/offline_map_providers.dart';
import '../../core/app_distribution.dart';
import '../../core/settings.dart';
import '../../core/app_info.dart';
import '../../core/errors.dart';
import '../../core/update_check.dart';
import '../../core/widgets/form_notice.dart';
import '../../core/widgets/mushroom_avatar.dart';
import '../../core/widgets/password_field.dart';
import '../../data/providers.dart';
import '../ampel/ampel_providers.dart';
import '../ampel/ampel_scan.dart';
import '../tour/tour_providers.dart';
import '../tour/widgets/tour_icon.dart';
import '../import_export/gpx_export.dart';
import '../spots/nearby_spots.dart';
import '../spots/find_photo_providers.dart';
import '../spots/spot_providers.dart';
import 'account_dialogs.dart';
import 'profile_providers.dart';
import 'push_providers.dart';
import 'sharing_rank_tile.dart';
import '../../core/app_colors.dart';
import '../../core/widgets/sheet_close_button.dart';
import '../inat/inat_profile_tile.dart';
import '../highlights/highlight_sheet.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  /// Fragt nach, wenn beim Abmelden noch Einträge im Ausgangskorb liegen
  /// (#267) — sie gehen dabei verloren.
  ///
  /// Ohne wartende Einträge wird nichts gefragt: Abmelden ist ein
  /// alltäglicher Vorgang und braucht keine Rückfrage, nur weil es sie
  /// in einem Sonderfall geben muss.
  Future<bool> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final waiting = ref.read(pendingEntryCountProvider);
    if (waiting == 0) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Noch nicht übertragen'),
        content: Text(waiting == 1
            ? 'Ein Eintrag wartet noch auf die Verbindung. Beim Abmelden '
                'geht er verloren.'
            : '$waiting Einträge warten noch auf die Verbindung. Beim '
                'Abmelden gehen sie verloren.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hierbleiben'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Trotzdem abmelden'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final profile = profileAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          IconButton(
            // Erst die lokale Kopie der Spots wegwerfen, dann abmelden:
            // Danach leitet der Router sofort auf /login um, und `ref`
            // wäre nicht mehr benutzbar.
            onPressed: () async {
              // Der Ausgangskorb gehört zum Konto und wird beim Abmelden
              // mit weggeworfen (#267) — wie der Zwischenspeicher, aus
              // demselben Grund: Die Fundstellen eines abgemeldeten
              // Kontos haben auf dem Gerät nichts verloren. Was noch
              // wartet, ist damit weg, deshalb wird vorher gefragt.
              if (!await _confirmSignOut(context, ref)) return;
              await ref.read(mySpotsProvider.notifier).forgetCache();
              await ref.read(authRepositoryProvider).signOut();
            },
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
            Text('Teilen mit Buddys',
                style: Theme.of(context).textTheme.titleMedium),
            // Rang und Spiegel (#276) stehen VOR dem Schalter: Sie sind
            // der Grund, ihn anzulassen.
            const SharingRankTile(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Meine Spots mit Buddys teilen'),
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
                  const Text('Ausgeschaltet sehen Buddys nur den Standort.'),
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
          // die Online-Karte ohnehin immer da. Über den Provider und nicht
          // über `kIsWeb`, damit der Test beide Seiten fahren kann; der
          // Screen dahinter benutzt dieselbe Quelle und erklärt sich, falls
          // jemand die Adresse direkt aufruft.
          if (ref.watch(offlineMapsSupportedProvider)) ...[
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
          // Der Takt der Pilztour (#338). Kein Schalter, sondern eine
          // Wahl — und gerätelokal, weil sie zum Gerät gehört: Ein altes
          // Telefon mit knappem Akku will einen längeren Takt als ein
          // neues. Die Aufnahme selbst startet auf der Karte; hier steht
          // nur, wie dicht sie misst.
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const TourIcon(),
            title: const Text('Pilztour: Messabstand'),
            subtitle: const Text(
                'Wie oft der Weg festgehalten wird. Enger misst genauer '
                'und kostet mehr Akku.'),
            trailing: DropdownButton<int>(
              value: ref.watch(tourIntervalProvider),
              onChanged: (value) {
                if (value == null) return;
                ref.read(tourIntervalProvider.notifier).state = value;
                unawaited(ref
                    .read(settingsProvider)
                    .setTourIntervalSeconds(value)
                    .catchError((Object e, StackTrace stackTrace) {
                  logError('Tour-Takt merken', e, stackTrace);
                }));
              },
              items: [
                for (final seconds in kTourIntervals)
                  DropdownMenuItem(
                      value: seconds, child: Text('$seconds s')),
              ],
            ),
          ),
          // Ab Werk aus (Betreiberentscheidung 2026-08-09). Die
          // Validierung ist seit 2026-08-13 durch und BESTANDEN — der
          // Text sagt jetzt, was gemessen wurde, statt „läuft noch".
          //
          // „Experimentell" bleibt trotzdem stehen, und zwar wegen der
          // einen Hälfte, die NICHT bestanden hat: Bei zwei von drei
          // Holzbewohnern passt dasselbe Modell genauso gut
          // (`docs/pilzampel-validierung.md`). Ob die Ampel je Art
          // unterschiedlich wirkt, ist damit offen — deshalb rechnet sie
          // für alle gleich, und deshalb steht es auch so da.
          // Die Darstellung der Tourspur (#340). Vorgabe sind Punkte,
          // und das ist eine Aussage über die DATEN: Ihr Abstand zeigt,
          // wo jemand langsam ging — genau die Größe, aus der die
          // Leergänge folgen. Eine Linie ist leichter zu verfolgen und
          // glättet das weg; deshalb wählbar statt gesetzt.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.timeline),
            title: const Text('Tourspur als Linie'),
            subtitle: const Text(
                'Statt einzelner Punkte. Die Punktabstände zeigen, wo du '
                'langsam warst — eine Linie zeigt den Weg.'),
            value: ref.watch(tourTrackAsLineProvider),
            onChanged: (value) =>
                ref.read(tourTrackAsLineProvider.notifier).set(value),
          ),
          // Fundfotos (#532). Ab Werk AN — ein Posteingang, den erst ein
          // Schalter öffnet, ist einer, den niemand findet. Der Schalter
          // ist für die andere Richtung: Aus heißt, dass keine Vorschau
          // geholt wird, nicht nur keine gezeigt. Eigene Fotos bleiben.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.photo_outlined),
            title: const Text('Fundfotos von Buddys anzeigen'),
            subtitle: const Text(
                'Im Reiter „Spots" und im Spot-Blatt, jeweils 14 Tage lang. '
                'Aus heißt: Es werden keine Bilder geladen — deine eigenen '
                'siehst du weiterhin.'),
            value: ref.watch(findPhotosEnabledProvider),
            onChanged: (value) =>
                ref.read(findPhotosEnabledProvider.notifier).set(value),
          ),
          // Funde an iNaturalist und damit an GBIF melden (#553).
          // Unsichtbar, solange die App keine Application ID hat; ohne
          // verbundenes Konto ändert sich sonst nirgends etwas.
          const InatProfileTile(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.science_outlined),
            title: const Text('Pilzwetter-Ampel (experimentell)'),
            // **Korrigiert am 2026-09-12.** Hier stand „Ob sie je Art
            // anders wirkt, ist noch offen; deshalb rechnet sie für alle
            // gleich." Genau das ist inzwischen gemessen und geändert
            // (seit 1.137.0 je Pilzgruppe) — der Satz behauptete das
            // Gegenteil dessen, was die App tut.
            subtitle: const Text(
                'An echten Funden geprüft: An Fundtagen steht sie höher '
                'als an Vergleichstagen am selben Ort. Sie bewertet das '
                'Wetter — nicht, ob dort Pilze stehen. Gerechnet wird je '
                'Pilzgruppe: Pfifferlinge brauchen es wärmer als '
                'Steinpilze. Welche Gruppen es gibt, steht im '
                'Ampel-Blatt auf der Karte.'),
            value: ref.watch(ampelPreviewEnabledProvider),
            onChanged: (value) =>
                ref.read(ampelPreviewEnabledProvider.notifier).set(value),
          ),
          // Baustein B (#277) — und ein EIGENER Schalter, nicht der der
          // Vorschau darüber. Der Nachlauf braucht das Höhengitter, und
          // dessen 3,4 MB beim Start auszupacken ist genau die Last, die
          // 1.99.4 aus dem Startpfad entfernt hat. Sie still unter einem
          // Schalter zurückzuholen, der etwas anderes verspricht, wäre
          // ein Schritt zurück; so zahlt sie nur, wer sie bestellt.
          //
          // Nur sichtbar, wenn die Vorschau an ist: Ohne sie gäbe es
          // kein Blatt, in dem sich die Aussage nachlesen ließe.
          if (ref.watch(ampelPreviewEnabledProvider))
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.notifications_none_outlined),
              title: const Text('Beim Start an meinen Spots nachsehen'),
              subtitle: const Text(
                  'Zeigt beim Öffnen der Karte einen Hinweis, wenn die '
                  'Ampel an einem deiner Spots günstig steht. Rechnet '
                  'auf dem Gerät und kostet dort etwas Zeit beim Start; '
                  'es geht nichts ins Netz.'),
              value: ref.watch(ampelBannerEnabledProvider),
              onChanged: (value) =>
                  ref.read(ampelBannerEnabledProvider.notifier).set(value),
            ),
          // Push (#277). Die Systemberechtigung wird ERST hier erfragt,
          // nicht beim Start: Ein Dialog, bevor die Karte auch nur zu
          // sehen war, ist die zuverlässigste Art, ein „Nein für immer"
          // zu bekommen. Der Schalter zeigt das Ergebnis, nicht den
          // Wunsch — wer ablehnt, sieht ihn zurückspringen.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Benachrichtigungen'),
            // Seit #564 mit einer Ausnahme, und die steht hier, wo man den
            // Schalter umlegt: Nachrichten von Buddys kommen MIT Text.
            subtitle: const Text(
                'Gilt nur für dieses Gerät. Fundort und Spot-Name stehen nie '
                'in einer Meldung — die holt die App erst beim Öffnen. '
                'Nachrichten deiner Buddys erscheinen mit ihrem Text.'),
            value: ref.watch(pushEnabledProvider),
            onChanged: (value) async {
              final problem =
                  await ref.read(pushEnabledProvider.notifier).set(value);
              if (!context.mounted || problem == null) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(problem)));
            },
          ),
          if (ref.watch(pushEnabledProvider))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.send_outlined),
              title: const Text('Testnachricht senden'),
              subtitle: const Text(
                  'Kommt sie an, funktioniert die ganze Kette bis zu '
                  'diesem Gerät.'),
              onTap: () async {
                final problem =
                    await ref.read(pushEnabledProvider.notifier).sendTest();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(problem ?? 'Testnachricht ist unterwegs.')));
              },
            ),
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
          // Nur zeigen, wenn es etwas aufzuräumen gibt (#215) — ein
          // Eintrag, der auf eine leere Seite führt, ist eine Sackgasse.
          if (ref.watch(overlappingSpotPairsProvider).isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.join_full_outlined),
              title: const Text('Dicht beieinander'),
              subtitle: Text(
                  '${ref.watch(overlappingSpotPairsProvider).length} Spot-Paare '
                  'liegen unter ${kNearbySpotMeters.round()} m auseinander'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/profile/spot-cleanup'),
            ),
          ChangeUsernameTile(username: profile?.username),
          const ChangeEmailTile(),
          const _ChangePasswordTile(),
          const SignOutOtherDevicesTile(),
          const Divider(height: 32),
          if (profile == null && profileAsync.isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          // Die Statistik steht seit 1.160.0 im Reiter „Spots" (#509).
          // Hier bleibt ein Verweis und keine Kurzfassung: Zwei Orte mit
          // derselben Aussage laufen auseinander, und das Profil ist für
          // das Konto da, nicht für die Auswertung.
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.insights_outlined),
            title: const Text('Statistik'),
            subtitle: const Text('Jahresgang, Top-Arten und die laufende '
                'Saison stehen im Reiter „Spots"'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/spots'),
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

/// Passwort ändern für Angemeldete (Issue #127). Der Reset-Flow auf dem
/// Login-Screen hilft nur, wer ausgesperrt ist — wer drin ist, hatte bisher
/// keinen Weg.
class _ChangePasswordTile extends ConsumerWidget {
  const _ChangePasswordTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.lock_outline),
      title: const Text('Passwort ändern'),
      subtitle: const Text(
          'Braucht dein aktuelles Passwort — so ist ein fremdes Gerät '
          'allein nicht genug'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => const _ChangePasswordDialog(),
      ),
    );
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _repeatController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _repeatController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _currentController.text.isNotEmpty &&
      _newController.text.length >= minPasswordLength &&
      _newController.text == _repeatController.text;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _currentController.text,
            newPassword: _newController.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dein Passwort ist geändert.')),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = changePasswordErrorMessage(e));
    } catch (e, stackTrace) {
      logError('Passwort ändern', e, stackTrace);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Passwort ändern'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PasswordField(
              controller: _currentController,
              label: 'Aktuelles Passwort',
              textInputAction: TextInputAction.next,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _newController,
              label: 'Neues Passwort (mind. $minPasswordLength Zeichen)',
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _repeatController,
              label: 'Neues Passwort wiederholen',
              onSubmitted: (_) => (_canSave && !_busy) ? _save() : null,
              onChanged: (_) => setState(() {}),
            ),
            PasswordMatchHint(
              password: _newController.text,
              repeated: _repeatController.text,
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
      // Dieselbe Reihenfolge wie beim Abmelden — und hier zwingend: Ein
      // gelöschtes Konto darf keine Fundstellen auf dem Gerät hinterlassen.
      await ref.read(mySpotsProvider.notifier).forgetCache();
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
                'alle Spots samt Fundhistorie, deine Buddy-Verbindungen und ein '
                'laufend geteilter Standort.'),
            const SizedBox(height: 12),
            const Text(
                'Deine Spots verschwinden damit auch von den Karten deiner '
                'Buddys — geteilte Spots sind Kopien deiner Daten, keine '
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
        // Nur wo der Update-Weg überhaupt läuft (#269). Im Web und im
        // Play-Build zeigte der Schalter auf nichts; der Provider hält
        // denselben Riegel, hier steht er gegen einen Schalter, den man
        // sonst umlegen könnte, ohne dass je etwas passiert.
        if (updateChecksApply)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            secondary: const Icon(Icons.science_outlined),
            title: const Text('Vorabversionen erhalten'),
            subtitle: const Text(
                'Bietet auch Zwischenstände an, die noch nicht freigegeben '
                'sind — ungetestet und häufig. Gilt nur für dieses Gerät.'),
            value: ref.watch(prereleaseUpdatesProvider),
            onChanged: (value) =>
                ref.read(prereleaseUpdatesProvider.notifier).set(value),
          ),
        // Der Web-Gegenpart zu „Vorabversionen erhalten" (#388) — aber
        // bewusst KEIN Schalter: Die Vorschau liegt auf einem eigenen
        // Origin, der Wechsel ist also eine Navigation und keine
        // Einstellung. Und weil damit ein eigener `localStorage` gilt,
        // muss der Text die Neuanmeldung ansagen; sonst sieht sie aus wie
        // ein Fehler.
        if (ref.watch(webChannelProvider) == WebChannel.stable)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.science_outlined),
            title: const Text('Entwicklungsversion öffnen'),
            subtitle: const Text(
                'Der neueste Zwischenstand — ungetestet und oft halbfertig. '
                'Öffnet eine eigene Adresse; dort musst du dich neu '
                'anmelden.'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(AppInfo.previewAppUrl),
          ),
        // Und der Rückweg. Er steht nur in der Vorschau, dafür an
        // derselben Stelle — wer hierher gefunden hat, soll auch wieder
        // hinausfinden.
        if (ref.watch(webChannelProvider) == WebChannel.preview)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.verified_outlined),
            title: const Text('Zur freigegebenen Version'),
            subtitle: const Text(
                'Du benutzt gerade einen Entwicklungsstand. Die echte App '
                'liegt unter ihrer gewohnten Adresse.'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(AppInfo.webAppUrl),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.help_outline),
          title: const Text('Kurzanleitung'),
          subtitle: const Text('Wie PilzBuddy benutzt wird — in sechs '
              'Schritten'),
          onTap: () => context.push('/profile/anleitung'),
        ),
        // „Entdecken" (#596) direkt über „Was ist neu": Das eine sagt,
        // was die App kann, das andere, was sich wann geändert hat — wer
        // eins sucht, sucht oft das andere.
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.lightbulb_outline),
          title: const Text('Entdecken'),
          subtitle: Text(switch (ref.watch(unseenHighlightCountProvider)) {
            0 => 'Funktionen und Tipps, mit einem Tipp dorthin',
            1 => '1 Eintrag, den du noch nicht angesehen hast',
            final n => '$n Einträge, die du noch nicht angesehen hast',
          }),
          onTap: () => context.push('/profile/entdecken'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.auto_stories_outlined),
          title: const Text('Was ist neu'),
          subtitle: const Text('Was sich in welcher Version geändert hat'),
          onTap: () => context.push('/profile/changelog'),
        ),
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
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Datenschutzerklärung'),
          subtitle: const Text('Was gespeichert wird — und was öffentlich ist'),
          onTap: () => _open(AppInfo.privacyUrl),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.info_outline),
          title: const Text('Impressum'),
          subtitle: const Text('Wer PilzBuddy anbietet'),
          onTap: () => _open(AppInfo.impressumUrl),
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

  final spots = ref.read(mySpotListProvider);
  if (spots.isEmpty) {
    message('Noch keine eigenen Spots zum Exportieren.');
    return;
  }

  // Seit #112 trägt die Datei die vollen Daten — inklusive der Notizen.
  // Das muss vorher dastehen: Der Export geht über das System-Teilen-
  // Blatt, landet also womöglich in einem Chat. Wer eine Datei
  // weitergibt, soll wissen, was drinsteht; hinterher ist sie weg.
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Spots exportieren'),
      content: Text(
        'Die Datei enthält alle ${spots.length} eigenen Spots mit '
        'Fundorten, Arten, Daten und deinen Notizen — bei manchen Funden '
        'metergenau.\n\n'
        'Sie ist als Sicherung gedacht — damit ziehst du deine Spots in '
        'ein anderes Konto um. Gib sie nur weiter, wenn die Notizen '
        'jemand lesen darf.\n\n'
        'Karten-Apps können die Datei ebenfalls öffnen und zeigen dann '
        'die Fundorte.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Weiter'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

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
        padding: const EdgeInsets.fromLTRB(16, 0, 4, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Such dir deinen Pilz-Buddy aus!',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                const SheetCloseButton(),
              ],
            ),
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
