// Der Eintrag im Profil (#553): verbinden, Lizenz, trennen.
//
// **Ohne Verbindung ändert sich sonst nirgends etwas.** Der Schalter im
// Blatt „Fund eintragen" erscheint erst, wenn hier ein Konto steht —
// die Vorgabe des Betreibers war, dass der Alltag genau so einfach
// bleibt wie vorher.
//
// **Der Dialog sagt vor dem Verbinden, was hinausgeht.** Insbesondere,
// dass iNaturalist die GENAUE Stelle bekommt, auch wenn öffentlich nur
// ein Gebiet steht: In dieser App ist die Fundstelle das eine, das
// nicht hinausdarf, und hier geht sie hinaus — auf Wunsch, aber nicht
// ohne es zu wissen.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../data/inat_account.dart';
import '../../data/inat_api.dart';
import 'inat_providers.dart';

const kInatProfileTileKey = Key('inat-profile-tile');
const kInatConnectKey = Key('inat-connect');
const kInatDisconnectKey = Key('inat-disconnect');
Key inatLicenseKey(InatLicense license) => ValueKey('inat-license-$license');

/// Was der Verbinden-Dialog sagt — an einer Stelle, damit Test und
/// Dialog dasselbe meinen.
const kInatConsentText =
    'Gemeldet wird nur, was du beim Eintragen ausdrücklich auswählst — '
    'je Fund, mit deinem eigenen Foto und unter deinem Namen bei '
    'iNaturalist. Bestätigt die Community dort die Art, gibt '
    'iNaturalist die Beobachtung an GBIF weiter.\n\n'
    'iNaturalist erhält die GENAUE Fundstelle, auch wenn du „verschleiert" '
    'wählst — öffentlich steht dann nur ein Gebiet von etwa 20 km. '
    'Name des Spots, Notizen und Buddys gehen nicht mit.';

class InatProfileTile extends ConsumerWidget {
  const InatProfileTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(inatAvailableProvider)) return const SizedBox.shrink();
    final account = ref.watch(inatAccountProvider).valueOrNull;
    return ListTile(
      key: kInatProfileTileKey,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.public),
      title: Text(account == null
          ? 'Funde an GBIF melden'
          : 'iNaturalist: verbunden als ${account.login}'),
      subtitle: Text(account == null
          ? 'Über iNaturalist, mit deinem eigenen Konto. Optional — '
              'ohne Verbindung ändert sich nichts.'
          : 'Lizenz ${account.license.label}. Beim Eintragen eines '
              'Fundes kannst du ihn jetzt melden.'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => account == null
          ? _connect(context, ref)
          : _manage(context, ref, account),
    );
  }

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    final license = await showDialog<InatLicense>(
      context: context,
      builder: (context) => const _ConnectDialog(),
    );
    if (license == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(inatAccountProvider.notifier).connect(license);
      final login = ref.read(inatAccountProvider).valueOrNull?.login;
      messenger.showSnackBar(SnackBar(
          content: Text('Mit iNaturalist verbunden'
              '${login == null ? '' : ' als $login'}.')));
    } on PlatformException catch (e) {
      // Custom Tab ohne Bestätigung geschlossen: Das war eine
      // Entscheidung, kein Fehler — keine Meldung.
      if (e.code == 'CANCELED') return;
      logError('iNaturalist verbinden', e);
      messenger.showSnackBar(const SnackBar(
          content: Text('Die Anmeldung bei iNaturalist ließ sich nicht '
              'öffnen.')));
    } on InatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e, stackTrace) {
      logError('iNaturalist verbinden', e, stackTrace);
      messenger.showSnackBar(const SnackBar(
          content: Text('Verbinden hat nicht geklappt. Internet '
              'verfügbar?')));
    }
  }

  Future<void> _manage(
      BuildContext context, WidgetRef ref, InatAccount account) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ManageDialog(account: account),
    );
  }
}

class _LicenseChoice extends StatelessWidget {
  const _LicenseChoice({required this.value, required this.onChanged});

  final InatLicense value;
  final ValueChanged<InatLicense> onChanged;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<InatLicense>(
      groupValue: value,
      onChanged: (license) {
        if (license != null) onChanged(license);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final license in InatLicense.values)
            RadioListTile<InatLicense>(
              key: inatLicenseKey(license),
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: license,
              title: Text(license.label),
              subtitle: Text(license.meaning),
            ),
        ],
      ),
    );
  }
}

class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog();

  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  InatLicense _license = InatLicense.ccByNc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Mit iNaturalist verbinden'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(kInatConsentText),
            const SizedBox(height: 12),
            Text('Lizenz deiner Meldungen', style: theme.textTheme.titleSmall),
            Text('Nur diese drei gibt iNaturalist an GBIF weiter.',
                style: theme.textTheme.bodySmall),
            _LicenseChoice(
              value: _license,
              onChanged: (license) => setState(() => _license = license),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: kInatConnectKey,
          onPressed: () => Navigator.of(context).pop(_license),
          child: const Text('Verbinden'),
        ),
      ],
    );
  }
}

class _ManageDialog extends ConsumerWidget {
  const _ManageDialog({required this.account});

  final InatAccount account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live gelesen, damit die Lizenzwahl sofort anschlägt.
    final current = ref.watch(inatAccountProvider).valueOrNull ?? account;
    return AlertDialog(
      title: Text('iNaturalist: ${current.login}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LicenseChoice(
              value: current.license,
              onChanged: (license) =>
                  ref.read(inatAccountProvider.notifier).setLicense(license),
            ),
            const SizedBox(height: 8),
            Text(
              'Trennen löscht den Zugang auf diesem Gerät. Die Freigabe '
              'bei iNaturalist widerrufst du dort unter „Einstellungen → '
              'Anwendungen"; gemeldete Beobachtungen bleiben deine und '
              'lassen sich nur dort löschen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: kInatDisconnectKey,
          onPressed: () async {
            await ref.read(inatAccountProvider.notifier).disconnect();
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Trennen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fertig'),
        ),
      ],
    );
  }
}
