import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors.dart';
import '../../../core/settings.dart';
import '../../../core/update_check.dart';
import '../../../core/widgets/form_notice.dart';
import '../../../data/apk_installer.dart';
import '../../../data/feedback_repository.dart';
import '../../../data/outbox.dart';
import '../../../data/providers.dart';
import '../../../models/find.dart';
import '../../../models/spot.dart';
import '../../friends/friend_providers.dart';
import '../../offline_maps/offline_map_providers.dart';
import '../../ampel/ampel_scan.dart';
import '../spot_memory.dart';
import '../../spots/spot_providers.dart';
import '../../spots/widgets/spot_detail_sheet.dart';
import '../../update/update_installer.dart';
import '../../../core/app_colors.dart';

/// Datum ohne Uhrzeit: Der Zwischenspeicher ist tagesgenau interessant
/// („von gestern"), die Minute hilft niemandem.
final _dayMonth = DateFormat('d.M.y');

/// Feedback-Banner für diese Sitzung ausgeblendet? Wird nur durch das X
/// gesetzt: nach dem Absenden bleibt das Banner stehen, sonst wirkt es, als
/// wäre die Meldemöglichkeit verschwunden (Issue #72).
final feedbackBannerDismissedProvider = StateProvider<bool>((ref) => false);

/// Update-Banner für diese Sitzung ausgeblendet?
final updateBannerDismissedProvider = StateProvider<bool>((ref) => false);

/// Karten-Update-Banner für diese Sitzung ausgeblendet?
final mapUpdateBannerDismissedProvider = StateProvider<bool>((ref) => false);

/// Bis wann Buddy-Funde als gesehen gelten (#202) — gerätelokal und
/// über den Neustart hinaus (Muster `rainCourseEnabledProvider`:
/// Startwert aus den Settings, geschrieben wird am Aufrufort).
final lastFindSeenAtProvider = StateProvider<DateTime?>(
    (ref) => ref.watch(settingsProvider).lastFindSeenAt);

/// Die Server-Zeit eines Funds. `foundOn` nur als Rückfall — `created_at`
/// ist in der DB not null, auch alte Cache-Zeilen tragen es.
DateTime _findStamp(Find find) => (find.createdAt ?? find.foundOn).toUtc();

/// Bis wann das Ampel-Banner stummgeschaltet ist — gerätelokal und über
/// den Neustart hinaus, Muster wie [lastFindSeenAtProvider].
final ampelBannerDismissedProvider = StateProvider<DateTime?>(
    (ref) => ref.watch(settingsProvider).ampelBannerDismissedUntil);

/// Bis wann die Spot-Erinnerung stummgeschaltet ist — gerätelokal und
/// über den Neustart hinaus, Muster wie [lastFindSeenAtProvider].
final spotMemoryDismissedProvider = StateProvider<DateTime?>(
    (ref) => ref.watch(settingsProvider).spotMemoryDismissedUntil);

/// Fremde Funde, die seit dem Marker dazukamen — neuester zuerst, von
/// eigenen UND von geteilten Spots (beide Fälle aus Wunsch #202).
///
/// `null`-Marker heißt „nie initialisiert" und defensiv „nichts Neues":
/// `main()` setzt ihn beim ersten Start ([ensureFindSeenMarker]) — ohne
/// den Schutz schriee das Banner nach dem Update über den kompletten
/// Bestand an Besitzer-Funden auf geteilten Spots.
final newBuddyFindsProvider = Provider<List<({Find find, Spot spot})>>((ref) {
  final seenUntil = ref.watch(lastFindSeenAtProvider);
  if (seenUntil == null) return const [];
  final spots = [
    ...ref.watch(mySpotListProvider),
    ...ref.watch(friendSpotsProvider).valueOrNull ?? const <Spot>[],
  ];
  return [
    for (final spot in spots)
      // `findsSorted` siebt die Leergänge aus (#211): Das Banner meldet
      // „Neuer Fund von …" — ein Buddy, der nichts gefunden hat, ist
      // keine Nachricht, die jemanden in den Wald schickt.
      for (final find in spot.findsSorted)
        if (!find.isOwn && _findStamp(find).isAfter(seenUntil))
          (find: find, spot: spot),
  ]..sort((a, b) => _findStamp(b.find).compareTo(_findStamp(a.find)));
});

/// Banner oben im Hauptfenster: Neuigkeiten (offene Freundschaftsanfragen)
/// und — solange die App jung ist — ein prominentes Feature-Wunsch-Feld.
class MapBanners extends ConsumerWidget {
  const MapBanners({super.key});

  /// Markiert die gerade angezeigten Buddy-Funde als gesehen: Der Marker
  /// springt auf die SERVER-Zeit des neuesten Funds — nicht auf die
  /// Geräteuhr, sonst verschluckte eine nachgehende Uhr Funde, die
  /// zwischen Anzeige und Tipp eintrafen. Persistenz-Fehler werden nur
  /// protokolliert; der Banner-Pfad darf nie werfen.
  void _markFindsSeen(WidgetRef ref, List<({Find find, Spot spot})> fresh) {
    if (fresh.isEmpty) return;
    final newest = fresh
        .map((e) => _findStamp(e.find))
        .reduce((a, b) => a.isAfter(b) ? a : b);
    ref.read(lastFindSeenAtProvider.notifier).state = newest;
    unawaited(ref
        .read(settingsProvider)
        .setLastFindSeenAt(newest)
        .catchError((Object e, StackTrace s) =>
            logError('Fund-Marker speichern', e, s)));
  }

  /// Schaltet die Spot-Erinnerung bis zum Ende des laufenden Fensters
  /// stumm: Dieselbe Erinnerung soll nicht jeden Morgen wiederkommen —
  /// die des nächsten Zeitfensters aber schon.
  void _dismissMemory(WidgetRef ref) {
    final until = DateTime.now()
        .toUtc()
        .add(const Duration(days: spotMemoryWindowDays));
    ref.read(spotMemoryDismissedProvider.notifier).state = until;
    unawaited(ref
        .read(settingsProvider)
        .setSpotMemoryDismissedUntil(until)
        .catchError((Object e, StackTrace s) =>
            logError('Erinnerung stummschalten', e, s)));
  }

  /// Das Ampel-Banner bis Mitternacht stummschalten.
  ///
  /// Gerechnet in LOKALER Zeit und erst dann nach UTC gedreht: „Ende des
  /// Tages" ist die Grenze, die der Nutzer meint, und die liegt in
  /// Mitteleuropa ein bis zwei Stunden vor dem UTC-Tagesende.
  void _dismissAmpel(WidgetRef ref) {
    final now = DateTime.now();
    final until =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    ref.read(ampelBannerDismissedProvider.notifier).state = until.toUtc();
    unawaited(ref
        .read(settingsProvider)
        .setAmpelBannerDismissedUntil(until.toUtc())
        .catchError((Object e, StackTrace s) =>
            logError('Ampel-Banner stummschalten', e, s)));
  }

  /// Der Text des Ampel-Banners — im KONJUNKTIV, und das ist keine
  /// Höflichkeit.
  ///
  /// Die Arten-Kontrolle der Rückwärtsvalidierung ist durchgefallen
  /// (`docs/pilzampel-validierung.md`); das Modell hat sich damit keine
  /// Aufforderung verdient. Eine eingeschaltete Fläche ist eine
  /// Einladung, etwas auszuprobieren — ein Banner, das „geh jetzt" sagt,
  /// wäre eine Behauptung. Deshalb „stünde", deshalb kein
  /// Ausrufezeichen, und deshalb steht „experimentell" mit drin.
  String _ampelText(List<AmpelHit> hits) {
    if (hits.length == 1) {
      final place = hits.single.spot.name ?? 'einem Spot';
      return '🍄 An $place stünde die Ampel günstig (experimentell) '
          '— antippen';
    }
    return '🍄 An ${hits.length} Spots stünde die Ampel günstig '
        '(experimentell) — antippen';
  }

  /// Der Text der Erinnerung. Nennt die Art nur, wenn ALLE Funde des
  /// Fensters dieselbe tragen — „Steinpilz" über einem gemischten
  /// Fenster wäre eine Behauptung, die die Daten nicht hergeben.
  String _memoryText(SpotMemory memory) {
    final place = memory.spot.name ?? 'Dein Spot';
    final what = memory.species ?? 'Funde';
    final many = memory.count > 1 ? '${memory.count}× ' : '';
    return '🍄 Erinnerung: $place — um diese Zeit ${memory.year} '
        'hattest du dort $many$what';
  }

  /// Schickt den Ausgangskorb los und sagt, was daraus wurde (#267).
  ///
  /// Ohne Netz ist das kein Fehler, sondern die Lage: Der Auftrag bleibt
  /// liegen, das Banner bleibt stehen. Deshalb wird hier auch nichts
  /// protokolliert — `sendOutbox` wirft nicht, es berichtet.
  Future<void> _sendOutbox(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(mySpotsProvider.notifier).sendOutbox();
    messenger.showSnackBar(SnackBar(
      content: Text(switch (result) {
        (sent: 0, remaining: _, failed: _) =>
          'Noch keine Verbindung — deine Einträge warten weiter.',
        (sent: final sent, remaining: 0, failed: _) => sent == 1
            ? 'Eintrag übertragen 🍄'
            : '$sent Einträge übertragen 🍄',
        (sent: final sent, remaining: final rest, failed: _) =>
          '$sent übertragen, $rest warten noch.',
      }),
    ));
  }

  /// Was tun mit einem Auftrag, den der Server dauerhaft ablehnt? Die
  /// App kann es nicht entscheiden — sie kann nur sagen, woran es lag,
  /// und das Verwerfen anbieten.
  Future<void> _openFailedDialog(
      BuildContext context, WidgetRef ref, List<OutboxJob> failed) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nicht übertragen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Diese Einträge hat der Server abgelehnt. Weitere '
                'Versuche ändern daran nichts.'),
            const SizedBox(height: 12),
            for (final job in failed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_jobLabel(job),
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(job.failure ?? '',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Behalten'),
          ),
          FilledButton(
            onPressed: () async {
              final notifier = ref.read(mySpotsProvider.notifier);
              Navigator.of(context).pop();
              for (final job in failed) {
                await notifier.discardJob(job.id);
              }
            },
            child: const Text('Verwerfen'),
          ),
        ],
      ),
    );
  }

  String _jobLabel(OutboxJob job) {
    final what = job.finds.length == 1
        ? job.finds.single.blank
            ? 'Leergang'
            : job.finds.single.species ?? 'Fund'
        : '${job.finds.length} Einträge';
    return job is NewSpotJob
        ? '${job.name?.isNotEmpty == true ? job.name : 'Neuer Spot'} — $what'
        : what;
  }

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
    final freshFinds = ref.watch(newBuddyFindsProvider);

    // Ohne Empfang kommen die Spots aus dem Zwischenspeicher. Das gehört
    // dazugesagt: Wer im Wald einen Spot vermisst, den er gestern angelegt
    // hat, soll den Grund sehen und nicht an der App zweifeln. Ganz oben
    // und ohne X — es ist kein Hinweis, den man wegwischt, sondern der
    // Zustand der angezeigten Daten.
    final cachedAt = ref.watch(mySpotsCachedAtProvider);

    // Baustein B: die eigenen Spots mit günstiger Ampel — ebenfalls
    // stumm, solange das X-Fenster läuft. `valueOrNull ?? const []`
    // heißt: Solange gerechnet wird, steht kein Banner da; ein
    // Platzhalter für eine Aussage, die vielleicht gar nicht kommt,
    // wäre schlimmer als die Stille.
    final ampelDismissedUntil = ref.watch(ampelBannerDismissedProvider);
    final ampelHits = (ampelDismissedUntil != null &&
            ampelDismissedUntil.isAfter(DateTime.now().toUtc()))
        ? const <AmpelHit>[]
        : ref.watch(ampelScanProvider).valueOrNull ?? const <AmpelHit>[];

    // Die Erinnerung ans Vorjahr — stumm, solange das X-Fenster läuft.
    final dismissedUntil = ref.watch(spotMemoryDismissedProvider);
    final memory = (dismissedUntil != null &&
            dismissedUntil.isAfter(DateTime.now().toUtc()))
        ? null
        : ref.watch(spotMemoryProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (cachedAt != null)
          _banner(
            context,
            background: AppColors.warmBrown,
            foreground: Colors.white,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📴 Ohne Empfang — deine Spots vom '
                    '${_dayMonth.format(cachedAt)}'),
                // Die zweite Zeile ist keine Zierde: Freundes-Spots werden
                // bewusst NICHT zwischengespeichert (fremde Standorte, und
                // deren Freigabe entscheidet der Server bei jeder Abfrage
                // neu). Ohne diesen Satz sähe ihr Fehlen nach einem Fehler
                // aus.
                Text('Freundes-Spots fehlen, bis du wieder Empfang hast.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.white70)),
              ],
            ),
          ),
        // Der Ausgangskorb (#267) — direkt unter dem Empfangs-Hinweis und
        // ohne X: Solange etwas wartet, ist das kein Hinweis, den man
        // wegwischt, sondern der Zustand der eigenen Daten. Antippen
        // versucht es sofort; ohne Netz sagt die Meldung genau das.
        if (ref.watch(pendingEntryCountProvider) > 0)
          Builder(builder: (context) {
            final failed = ref.watch(failedJobsProvider);
            final waiting = ref.watch(pendingEntryCountProvider);
            return _banner(
              context,
              background: failed.isEmpty
                  ? AppColors.warmBrown
                  : Theme.of(context).colorScheme.error,
              foreground: Colors.white,
              onTap: () => failed.isEmpty
                  ? _sendOutbox(context, ref)
                  : _openFailedDialog(context, ref, failed),
              content: Text(failed.isEmpty
                  ? waiting == 1
                      ? '📤 1 Eintrag wartet auf Verbindung — antippen'
                      : '📤 $waiting Einträge warten auf Verbindung — antippen'
                  : failed.length == 1
                      ? '⚠️ 1 Eintrag ließ sich nicht senden — antippen'
                      : '⚠️ ${failed.length} Einträge ließen sich nicht '
                          'senden — antippen'),
            );
          }),
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
            // Läuft der Nachlauf (#332) schon, wäre „antippen" eine
            // Aufforderung zu etwas, das gerade passiert. Gezählt werden
            // deshalb nur die Karten, an denen noch niemand arbeitet.
            final running = ref.watch(mapDownloadsProvider);
            final waiting =
                outdated.where((m) => !running.containsKey(m.key)).toList();
            return _banner(
              context,
              background: AppColors.warmBrown,
              foreground: Colors.white,
              onTap: () => context.push('/profile/offline-maps'),
              onDismiss: () => ref
                  .read(mapUpdateBannerDismissedProvider.notifier)
                  .state = true,
              content: Text(waiting.isEmpty
                  ? '🗺️ Neue Offline-Karte wird geladen — antippen'
                  : waiting.length == 1
                      ? '🗺️ Neue Offline-Karte für ${waiting.first.label} '
                          'verfügbar — antippen'
                      : '🗺️ ${waiting.length} neue Offline-Karten verfügbar '
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
        // Neue Buddy-Funde (#202) — NACH den Anfragen (dort wartet eine
        // Entscheidung, hier nur eine Neuigkeit), in derselben Buddy-
        // Farbe. Antippen öffnet den Spot des neuesten Funds und markiert
        // ALLE aktuellen als gesehen; das X markiert ohne Öffnen.
        if (freshFinds.isNotEmpty)
          _banner(
            context,
            background: AppColors.friendBlue,
            foreground: Colors.white,
            onTap: () {
              _markFindsSeen(ref, freshFinds);
              showSpotDetailSheet(context, freshFinds.first.spot.id);
            },
            onDismiss: () => _markFindsSeen(ref, freshFinds),
            content: Text(freshFinds.length == 1
                ? '🔔 Neuer Fund von '
                    '${freshFinds.first.find.authorUsername ?? 'deinem Buddy'}'
                    ' — antippen'
                : '🔔 ${freshFinds.length} neue Funde deiner Buddys '
                    '— antippen'),
          ),
        // Baustein B des Ampel-Konzepts (#277): das Wetter von heute an
        // den eigenen Spots. Steht über der Erinnerung, weil es die
        // aktuellere Aussage ist — und im erdigen Braun statt im
        // kräftigen Grün der Erinnerung: Die Ampel ist unvalidiert, und
        // die auffälligste Farbe der App gehört nicht der unsichersten
        // Aussage.
        if (ampelHits.isNotEmpty)
          _banner(
            context,
            background: AppColors.warmBrown,
            foreground: Colors.white,
            onTap: () {
              _dismissAmpel(ref);
              showSpotDetailSheet(context, ampelHits.first.spot.id);
            },
            onDismiss: () => _dismissAmpel(ref),
            content: Text(_ampelText(ampelHits)),
          ),
        // Die Spot-Erinnerung (Baustein C des Ampel-Konzepts): keine
        // Prognose, sondern die eigene Historie. Ganz unten in der
        // Reihe — Anfragen und Buddy-Funde sind Neuigkeiten von heute,
        // das hier ist ein Wink aus dem Vorjahr.
        if (memory != null)
          _banner(
            context,
            background: AppColors.forestGreen,
            foreground: Colors.white,
            onTap: () {
              _dismissMemory(ref);
              showSpotDetailSheet(context, memory.spot.id);
            },
            onDismiss: () => _dismissMemory(ref),
            content: Text(_memoryText(memory)),
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

/// Update-Dialog: Release-Notes, Fortschritt und Übergabe an den
/// System-Installer.
///
/// Erscheint nur in der GitHub-Variante (siehe [AppDistribution]) — im
/// Play-Build aktualisiert der Store. Der Browser-Weg bleibt als
/// Rückfalltür: Er ist der einzige, der ohne Zusatzberechtigung und ohne
/// den Method-Channel auskommt, und genau dorthin führt jeder Fehlschlag.
class _UpdateDialog extends ConsumerStatefulWidget {
  const _UpdateDialog({required this.info});

  final UpdateInfo info;

  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<_UpdateDialog> {
  double? _progress;
  bool _busy = false;
  UpdateFailure? _failure;

  Future<void> _openInBrowser() => launchUrl(
        Uri.parse(widget.info.downloadUrl),
        mode: LaunchMode.externalApplication,
      );

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _failure = null;
      _progress = null;
    });

    final failure = await ref.read(updateInstallerProvider).downloadAndInstall(
          widget.info,
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
        );
    if (!mounted) return;

    if (failure == null) {
      // Der System-Installer liegt jetzt vorn; der Dialog hat seinen Zweck
      // erfüllt und soll nicht dahinter stehen bleiben.
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _failure = failure;
    });
  }

  String _failureText(UpdateFailure failure) => switch (failure) {
        UpdateFailure.notAllowed =>
          'Android muss PilzBuddy einmalig erlauben, Apps zu installieren. '
              'Danach geht jedes Update mit einem Tipp.',
        UpdateFailure.downloadFailed =>
          'Der Download hat nicht geklappt. Im Browser klappt er '
              'vielleicht — die Datei danach antippen, um zu installieren.',
        UpdateFailure.installFailed =>
          'Die Installation ließ sich nicht öffnen. Über den Browser '
              'geladen, lässt sich die Datei von Hand antippen.',
      };

  @override
  Widget build(BuildContext context) {
    final notes = widget.info.releaseNotes?.trim();
    final installer = ref.watch(updateInstallerProvider);
    final failure = _failure;

    return AlertDialog(
      title: Text('Update auf v${widget.info.latestVersion}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(installer.supported
                ? 'Wird geladen und danach von Android installiert — deine '
                    'Spots bleiben erhalten.'
                : 'Der Download startet im Browser. Danach in der '
                    'Benachrichtigung auf die Datei tippen, um zu '
                    'installieren — deine Spots bleiben erhalten.'),
            if (_busy) ...[
              const SizedBox(height: 16),
              // Ohne bekannte Größe unbestimmt statt bei 0 % festzustehen.
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 4),
              Text(
                _progress == null
                    ? 'Wird geladen …'
                    : 'Wird geladen … ${(_progress! * 100).round()} %',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (failure != null) ...[
              const SizedBox(height: 12),
              FormNotice(
                  message: _failureText(failure), tone: NoticeTone.error),
              if (failure == UpdateFailure.notAllowed) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(apkInstallerProvider).openSettings(),
                  icon: const Icon(Icons.settings, size: 18),
                  label: const Text('Einstellung öffnen'),
                ),
              ],
            ],
            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Was ist neu:',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(notes, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Später'),
        ),
        // Der Browser-Weg steht immer zur Verfügung, nicht erst nach einem
        // Fehlschlag — wer ihn kennt und bevorzugt, soll ihn finden.
        TextButton.icon(
          onPressed: _busy ? null : _openInBrowser,
          icon: const Icon(Icons.open_in_browser, size: 18),
          label: const Text('Im Browser'),
        ),
        if (installer.supported)
          FilledButton.icon(
            onPressed: _busy ? null : _install,
            icon: const Icon(Icons.system_update, size: 18),
            label: const Text('Jetzt aktualisieren'),
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
