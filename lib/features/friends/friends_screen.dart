import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_info.dart';
import '../../core/errors.dart';
import '../../core/widgets/mushroom_avatar.dart';
import '../../data/providers.dart';
import '../../models/friendship.dart';
import '../profile/profile_providers.dart';
import '../profile/sharing_rank.dart';
import '../profile/sharing_rank_providers.dart';
import '../coach/coach.dart';
import '../help/tab_tours.dart';
import '../spots/widgets/find_photo_strip.dart' show FindPhotoGallery;
import 'buddy_alias.dart';
import 'buddy_alias_dialog.dart';
import 'friend_providers.dart';
import 'message_providers.dart';
import '../../core/app_colors.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _searchController = TextEditingController();
  List<ProfileSearchResult> _results = [];
  bool _searching = false;
  bool _searched = false;

  /// Der erste angenommene Buddy — seinen Verlauf öffnet die
  /// Vorführung „Nachrichten" (#596).
  String? _firstBuddyId;
  VoidCallback? _unregisterScene;

  @override
  void initState() {
    super.initState();
    _unregisterScene = ref
        .read(coachRegistryProvider)
        .registerScene(BuddysCoach.chat, () async {
      final id = _firstBuddyId;
      if (id == null || !mounted) return () {};
      final router = GoRouter.of(context);
      final path = '/friends/chat/$id';
      router.go(path);
      // Zurück nur, wenn der Verlauf noch vorne ist.
      return () {
        if (router.routerDelegate.currentConfiguration.uri.path == path) {
          router.go('/friends');
        }
      };
    });
  }

  @override
  void dispose() {
    _unregisterScene?.call();
    _searchController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() => _searching = true);
    try {
      final results = await ref.read(friendRepositoryProvider).search(query);
      setState(() {
        _results = results;
        _searched = true;
      });
    } catch (e, stackTrace) {
      logError('Freundesuche', e, stackTrace);
      _showMessage(friendlyError(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// Einladung teilen; wo das System-Teilen nicht verfügbar ist
  /// (z. B. Desktop-Browser), landet der Text in der Zwischenablage.
  Future<void> _invite() async {
    final username = ref.read(myProfileProvider).valueOrNull?.username;
    final text = AppInfo.inviteText(username);
    try {
      final result = await SharePlus.instance.share(ShareParams(text: text));
      if (result.status == ShareResultStatus.unavailable) {
        throw StateError('share unavailable');
      }
    } catch (_) {
      // Kein Fehlerfall: Desktop-Browser haben kein System-Teilen.
      await Clipboard.setData(ClipboardData(text: text));
      _showMessage('Einladungstext in die Zwischenablage kopiert.');
    }
  }

  Future<void> _sendRequest(ProfileSearchResult result) async {
    try {
      await ref.read(friendshipsProvider.notifier).sendRequest(result.id);
      _showMessage('Anfrage an ${result.username} gesendet.');
      setState(() => _results = _results.where((r) => r.id != result.id).toList());
    } catch (e, stackTrace) {
      logError('Freundschaftsanfrage', e, stackTrace);
      // Unique-Verletzung = Paar existiert schon — die häufigste Ursache.
      _showMessage(
          'Anfrage nicht möglich – vielleicht seid ihr schon verbunden?');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUserIdProvider) ?? '';
    final friendshipsAsync = ref.watch(friendshipsProvider);
    final friendships = friendshipsAsync.valueOrNull ?? [];

    final incoming = friendships.where((f) => f.isIncomingFor(uid)).toList();
    final outgoing = friendships.where((f) => f.isOutgoingFor(uid)).toList();
    final accepted = friendships.where((f) => f.isAccepted).toList();
    _firstBuddyId = accepted.isEmpty ? null : accepted.first.otherId(uid);
    final buddyCounts = ref.watch(buddySharedCountsProvider);
    final names = ref.watch(buddyNamesViewProvider);

    final requestedIds = {
      for (final f in friendships) ...[f.requesterId, f.addresseeId]
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Buddys')),
      body: TabTourStarter(
        script: kBuddysTourScript,
        // Erst, wenn feststeht, ob es Buddys gibt — sonst fiele der
        // Schritt am ersten Buddy weg, nur weil die Liste noch lädt.
        ready: !friendshipsAsync.isLoading,
        child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(friendshipsProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Ganz oben, weil es das ist, was sich hier ändert: Anfragen
            // und Buddys bleiben wochenlang gleich, Fotos laufen nach 14
            // Tagen ab.
            const CoachAnchor(
                id: BuddysCoach.gallery, child: FindPhotoGallery()),
            CoachAnchor(
              id: BuddysCoach.invite,
              child: OutlinedButton.icon(
                onPressed: _invite,
                icon: const Icon(Icons.share),
                label: const Text('Buddys zu PilzBuddy einladen'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            CoachAnchor(
              id: BuddysCoach.search,
              child: TextField(
              controller: _searchController,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: 'Buddy finden',
                hintText: 'Benutzername oder genaue E-Mail',
                border: const OutlineInputBorder(),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        onPressed: _search, icon: const Icon(Icons.search)),
              ),
            ),
            ),
            if (_searched) ...[
              const SizedBox(height: 8),
              if (_results.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Niemanden gefunden.'),
                )
              else
                for (final result in _results)
                  ListTile(
                    leading: MushroomAvatar(index: result.avatar, size: 40),
                    title: Text(result.username),
                    subtitle: result.displayName != null
                        ? Text(result.displayName!)
                        : null,
                    trailing: requestedIds.contains(result.id)
                        ? const Text('Verbunden')
                        : FilledButton.tonal(
                            onPressed: () => _sendRequest(result),
                            child: const Text('Anfragen'),
                          ),
                  ),
            ],
            if (incoming.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Anfragen an dich',
                  style: Theme.of(context).textTheme.titleMedium),
              for (final f in incoming)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      MushroomAvatar(index: f.otherAvatar(uid), size: 40),
                  title: Text(f.otherUsername(uid)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Erst fragen, dann annehmen (#564): „Man muss ja
                      // wissen, wen man reinnimmt."
                      MessageButton(otherId: f.otherId(uid)),
                      IconButton(
                        onPressed: () =>
                            ref.read(friendshipsProvider.notifier).accept(f.id),
                        icon: const Icon(Icons.check_circle,
                            color: AppColors.forestGreen),
                        tooltip: 'Annehmen',
                      ),
                      IconButton(
                        onPressed: () =>
                            ref.read(friendshipsProvider.notifier).remove(f.id),
                        icon: const Icon(Icons.cancel_outlined),
                        tooltip: 'Ablehnen',
                      ),
                    ],
                  ),
                ),
            ],
            if (outgoing.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Gesendete Anfragen',
                  style: Theme.of(context).textTheme.titleMedium),
              for (final f in outgoing)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      MushroomAvatar(index: f.otherAvatar(uid), size: 40),
                  title: Text(f.otherUsername(uid)),
                  subtitle: const Text('Ausstehend'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MessageButton(otherId: f.otherId(uid)),
                      IconButton(
                        onPressed: () => ref
                            .read(friendshipsProvider.notifier)
                            .remove(f.id),
                        icon: const Icon(Icons.cancel_outlined),
                        tooltip: 'Zurückziehen',
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Text('Meine Buddys',
                style: Theme.of(context).textTheme.titleMedium),
            if (friendshipsAsync.isLoading && friendships.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (accepted.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                    'Noch keine Buddys verbunden. Suche oben nach Benutzername oder E-Mail!'),
              )
            else
              for (final f in accepted)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      MushroomAvatar(index: f.otherAvatar(uid), size: 40),
                  // Mit Alias (#567) steht er oben und der Name darunter —
                  // genau dafür ist er da: wissen, wer „klabusterbärchen 2"
                  // eigentlich ist.
                  title: Text(names.of(f.otherId(uid), f.otherUsername(uid))),
                  // Der Teil-Rang (#276) — nur HIER, bei angenommenen
                  // Buddies. In der Suchergebnis-Liste weiter oben steht
                  // er bewusst nicht: Fremden verriete er, wie aktiv ein
                  // Konto ist, und dafür gibt es keinen Grund.
                  subtitle: switch ((
                    names.aliasOf(f.otherId(uid)) == null
                        ? null
                        : f.otherUsername(uid),
                    sharingTitleOf(buddyCounts[f.otherId(uid)] ?? 0),
                  )) {
                    (null, null) => null,
                    (final name?, null) => Text(name),
                    (null, final title?) => Text(title),
                    (final name?, final title?) => Text('$name · $title'),
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  // Die Tour zeigt beide am ERSTEN Buddy (#596).
                  _firstAnchor(
                      f == accepted.first,
                      BuddysCoach.alias,
                      AliasButton(
                          friendId: f.otherId(uid),
                          username: f.otherUsername(uid))),
                  _firstAnchor(f == accepted.first, BuddysCoach.message,
                      MessageButton(otherId: f.otherId(uid))),
                  IconButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(
                              '${names.of(f.otherId(uid), f.otherUsername(uid))} '
                              'als Buddy entfernen?'),
                          content: const Text(
                              'Ihr seht danach gegenseitig keine geteilten '
                              'Spots mehr, und eure Nachrichten werden '
                              'für beide gelöscht.'),
                          actions: [
                            TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Abbrechen')),
                            FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('Entfernen')),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await ref
                            .read(friendshipsProvider.notifier)
                            .remove(f.id);
                      }
                    },
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: 'Buddy entfernen',
                  ),
                    ],
                  ),
                ),
          ],
        ),
      ),
      ),
    );
  }
}

Widget _firstAnchor(bool first, String id, Widget child) =>
    first ? CoachAnchor(id: id, child: child) : child;

Key messageButtonKey(String otherId) => ValueKey('message-button-$otherId');

/// Der Weg in den Verlauf mit einem Buddy (#564) — mit Zahl, solange
/// Ungelesenes da ist.
class MessageButton extends ConsumerWidget {
  const MessageButton({super.key, required this.otherId});

  final String otherId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadMessagesProvider)[otherId] ?? 0;
    const icon = Icon(Icons.chat_bubble_outline);
    return IconButton(
      key: messageButtonKey(otherId),
      tooltip: unread == 0 ? 'Nachrichten' : '$unread ungelesen',
      onPressed: () => context.go('/friends/chat/$otherId'),
      icon: unread == 0 ? icon : Badge(label: Text('$unread'), child: icon),
    );
  }
}
