// Kurze Touren je Reiter (#596, zweiter Teil) — auf derselben
// Hinweis-Maschine wie die Karten-Tour (`features/coach/coach.dart`).
//
// **Warum je Reiter und nicht eine lange Tour vorab.** Eine Tour, die
// beim ersten Start alle fünf Reiter erklärt, wird selten zu Ende
// gesehen, und was sie zeigt, bevor man es braucht, ist beim Brauchen
// vergessen. Deshalb läuft jede beim ERSTEN Besuch ihres Reiters: Dann
// ist man gerade dort und fragt sich, was das hier ist.
//
// Vier Dinge, die man wissen muss:
//
// - **Sie wartet auf Inhalt.** Die Spot-Tour zeigt an der ersten Zeile,
//   was eine Zeile kann — in einer leeren Liste gäbe es nichts zu
//   zeigen. Dann bleibt sie ungesehen und läuft beim nächsten Besuch,
//   der eine Zeile hat. Schritte an Dingen, die nicht jeder hat (ein
//   Buddy, Bilder einer Art), fallen einzeln weg (`requires`).
// - **Sie läuft nur, wenn der Reiter SICHTBAR ist.** Die Reiter bleiben
//   nach dem ersten Besuch im Baum (go_router hält sie im
//   `IndexedStack`), und die Spot-Liste lädt gern nach, während man
//   längst woanders ist. Geprüft wird über `TickerMode`, den der
//   Router für verdeckte Reiter abschaltet.
// - **Die Karten-Tour geht vor.** Solange sie nicht gesehen ist (erster
//   Start) oder der Haftungshinweis offen, startet hier nichts — zwei
//   Touren übereinander wären keine.
// - **Gemerkt wird wie bei der Karten-Tour**: durchgesehen ODER
//   übersprungen, gerätelokal, über den Notifier statt über den `ref`
//   des Aufrufers.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/settings.dart';
import '../coach/coach.dart';
import 'map_tour.dart';
import 'tour_intro_art.dart';

/// Die Anker des Reiters „Spots".
abstract final class SpotsCoach {
  /// Die erste Zeile der Liste.
  static const row = 'spots.row';
  static const rowMap = 'spots.row.map';
  static const search = 'spots.search';
  static const statsTab = 'spots.statsTab';

  /// Szene: das Spot-Blatt der ersten Zeile.
  static const sheet = 'spots.sheet';
  static const sheetEntries = 'spots.sheet.entries';

  /// Der Stift im Spot-Blatt — nur am eigenen, schon gesendeten Spot.
  static const sheetEdit = 'spots.sheet.edit';
}

/// Die Anker des Reiters „Pilze".
abstract final class PilzeCoach {
  /// Die erste Art der Liste, ihre Saisonbalken und ihr Ampel-Schalter.
  static const row = 'pilze.row';
  static const rowSeason = 'pilze.row.season';
  static const rowSwitch = 'pilze.row.switch';

  /// Das Auge der ersten Art — nur, wenn sie Bilder hat.
  static const rowEye = 'pilze.row.eye';
  static const search = 'pilze.search';
  static const seasonChip = 'pilze.seasonChip';

  /// Szene: die Seite der ersten Art.
  static const detail = 'pilze.detail';
  static const detailEdibility = 'pilze.detail.edibility';
  static const detailPictures = 'pilze.detail.pictures';

  /// Die Liste der Artseite — der Meldeknopf steht ganz unten und wird
  /// erst beim Scrollen gebaut.
  static const detailList = 'pilze.detail.list';
  static const detailReport = 'pilze.detail.report';

  /// Szene AUF der Artseite: der Meldedialog, mit den Bildern.
  static const report = 'pilze.detail/report';
  static const reportPhotos = 'pilze.report.photos';
}

/// Die Anker des Reiters „Buddys".
abstract final class BuddysCoach {
  static const gallery = 'buddys.gallery';
  static const invite = 'buddys.invite';
  static const search = 'buddys.search';

  /// Stift und Sprechblase am ersten Buddy.
  static const alias = 'buddys.alias';
  static const message = 'buddys.message';

  /// Szene: der Verlauf mit dem ersten Buddy, mit dem Eingabefeld.
  static const chat = 'buddys.chat';
  static const chatInput = 'buddys.chat.input';
}

/// Die Anker des Profils — für die Vorführungen aus „Entdecken".
abstract final class ProfileCoach {
  /// Die Liste; der Ampel-Schalter steht weit unten und wird erst beim
  /// Scrollen gebaut.
  static const list = 'profile.list';
  static const ampel = 'profile.ampel';
}

/// Die Anker der Kurzanleitung.
abstract final class HelpCoach {
  static const list = 'help.list';
  static const tabTours = 'help.tabTours';
}

const kSpotsTourScript = CoachScript(
  id: 'spots',
  steps: [
    CoachStep(
      title: 'Deine Spots',
      chainTitle: 'Weiter mit den Spots?',
      text: 'Alle deine Stellen als Liste, der jüngste Eintrag oben — und '
          'deine Statistik übers Jahr. Hier findest du einen Spot schneller '
          'als auf der Karte.',
      art: spotsArt,
    ),
    CoachStep(
      title: 'Deine Spots als Liste',
      text: 'Hier stehen deine Spots und die, die Buddys mit dir teilen — '
          'oben der mit dem jüngsten Eintrag. Ein Tipp auf die Zeile '
          'öffnet das Spot-Blatt.',
      lit: [SpotsCoach.row],
      ring: [],
      gesture: CoachGesture.tap,
      requires: [SpotsCoach.row],
    ),
    CoachStep(
      title: 'Das Spot-Blatt',
      text: 'Dasselbe Blatt wie auf der Karte: alle Einträge des Spots. '
          'Hier trägst du einen Fund ein — oder „Nichts gefunden", wenn '
          'du da warst und nichts da war.',
      scene: SpotsCoach.sheet,
      lit: [SpotsCoach.sheetEntries],
      requires: [SpotsCoach.row],
    ),
    CoachStep(
      title: 'Zeig mir, wo',
      text: 'Das Kartensymbol wechselt zur Karte und holt den Spot in die '
          'Mitte.',
      lit: [SpotsCoach.row],
      ring: [SpotsCoach.rowMap],
      requires: [SpotsCoach.rowMap],
    ),
    CoachStep(
      title: 'Suchen',
      text: 'Gesucht wird über den Namen des Spots, seine Arten und den '
          'Buddy, dem er gehört.',
      lit: [SpotsCoach.search],
    ),
    CoachStep(
      title: 'Deine Statistik',
      text: 'Die Saison im Vergleich zum Vorjahr — bis zum selben Tag '
          'gerechnet —, dein Jahresgang und deine häufigsten Arten.',
      lit: [SpotsCoach.statsTab],
    ),
  ],
);

const kPilzeTourScript = CoachScript(
  id: 'pilze',
  steps: [
    CoachStep(
      title: 'Die Pilze',
      chainTitle: 'Weiter mit den Pilzen?',
      text: 'Jede Art mit Saison, Merkmalen, Bildern und dem, womit man sie '
          'verwechseln kann — und welche Arten zur Pilzampel gehören.',
      art: pilzeArt,
    ),
    CoachStep(
      title: 'Wann gemeldet wird',
      text: 'Die Balken zeigen, in welchen Monaten eine Art gemeldet wird. '
          'Grün hervorgehoben ist, was jetzt Saison hat.',
      lit: [PilzeCoach.row],
      ring: [PilzeCoach.rowSeason],
      requires: [PilzeCoach.rowSeason],
    ),
    CoachStep(
      title: 'Aus der Ampel nehmen',
      text: 'Suchst du eine Art nicht, schalte sie hier aus — dann zählt '
          'sie nicht mehr für die Pilzampel und ihren Hinweis.',
      lit: [PilzeCoach.row],
      ring: [PilzeCoach.rowSwitch],
      requires: [PilzeCoach.rowSwitch],
    ),
    CoachStep(
      title: 'Suchen und filtern',
      text: 'Gesucht wird auch über Zweitnamen und den wissenschaftlichen '
          'Namen, Tippfehler inklusive. „Saison" zeigt nur, was jetzt '
          'gemeldet wird.',
      lit: [PilzeCoach.search, PilzeCoach.seasonChip],
    ),
    CoachStep(
      title: 'Jede Art hat eine Seite',
      text: 'Ein Tipp auf die Art öffnet alles, was PilzBuddy über sie '
          'weiß.',
      lit: [PilzeCoach.row],
      ring: [],
      gesture: CoachGesture.tap,
      requires: [PilzeCoach.row],
    ),
    CoachStep(
      title: 'Zuerst die Warnung',
      text: 'Ganz oben: essbar oder giftig, und womit die Art verwechselt '
          'wird. Darunter Merkmale, Saison und deine eigenen Funde.',
      scene: PilzeCoach.detail,
      lit: [PilzeCoach.detailEdibility],
      requires: [PilzeCoach.row],
    ),
    CoachStep(
      title: 'Bilder zum Vergleichen',
      text: 'Wisch durch die Bilder, ein Tipp vergrößert sie. Rechts vom '
          'Strich stehen die Verwechslungspartner.',
      scene: PilzeCoach.detail,
      lit: [PilzeCoach.detailPictures],
      ring: [],
      gesture: CoachGesture.swipe,
      // Kein `requires`: Auf einem kleinen Schirm liegt der Streifen
      // unter dem Falz, und die Liste baut ihn erst beim Scrollen — der
      // Schritt fiel dort still weg (360×640, im Test gesehen).
      scrollIn: PilzeCoach.detailList,
    ),
  ],
);

const kBuddysTourScript = CoachScript(
  id: 'buddys',
  steps: [
    CoachStep(
      title: 'Deine Buddys',
      chainTitle: 'Weiter mit den Buddys?',
      text: 'Freunde, mit denen du Spots teilst, wenn du willst — dazu ihre '
          'Fundfotos und eure Nachrichten.',
      art: buddysArt,
    ),
    CoachStep(
      title: 'Fundfotos deiner Buddys',
      text: 'Was Buddys an geteilten Funden fotografiert haben, 14 Tage '
          'lang. Der Ring zeigt, wie lange ein Foto noch bleibt.',
      lit: [BuddysCoach.gallery],
      requires: [BuddysCoach.gallery],
    ),
    CoachStep(
      title: 'Jemanden einladen',
      text: 'Schickt einen Link zu PilzBuddy über deine Messenger-App — '
          'mit deinem Benutzernamen, damit man dich gleich findet.',
      lit: [BuddysCoach.invite],
    ),
    CoachStep(
      // Nicht „Buddy finden": So heißt das Suchfeld selbst (#596, dieselbe
      // Falle wie beim Kontextmenü der Karten-Tour).
      title: 'Nach Buddys suchen',
      text: 'Gefunden wird über den Benutzernamen oder die genaue '
          'E-Mail-Adresse. Spots seht ihr voneinander erst, wenn die '
          'Anfrage angenommen ist.',
      lit: [BuddysCoach.search],
    ),
    CoachStep(
      title: 'Name und Nachrichten',
      text: 'Der Stift gibt einem Buddy einen eigenen Namen, den nur du '
          'siehst. Die Sprechblase öffnet eure Nachrichten.',
      lit: [BuddysCoach.alias, BuddysCoach.message],
      requires: [BuddysCoach.alias, BuddysCoach.message],
    ),
  ],
);

/// Alle Reiter-Touren — für den Test, der sie gegen die Fakes hält.
const kTabTourScripts = [kSpotsTourScript, kPilzeTourScript, kBuddysTourScript];

class SeenCoachTours extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.read(settingsProvider).seenCoachTours;

  bool hasSeen(String id) => state.contains(id);

  void markSeen(String id) {
    if (state.contains(id)) return;
    final next = {...state, id};
    state = next;
    unawaited(ref.read(settingsProvider).setSeenCoachTours(next).catchError(
        (Object e, StackTrace s) => logError('Reiter-Tour merken', e, s)));
  }
}

final seenCoachToursProvider =
    NotifierProvider<SeenCoachTours, Set<String>>(SeenCoachTours.new);

/// Eine ausdrücklich gewünschte Tour (aus der Kurzanleitung). Sie läuft
/// auch, wenn sie schon gesehen ist, und startet, sobald ihr Reiter
/// sichtbar wird — der Wechsel dorthin dauert ein Bild.
class RequestedTabTour extends Notifier<String?> {
  @override
  String? build() => null;

  void request(String id) => state = id;

  void clear() => state = null;
}

final requestedTabTourProvider =
    NotifierProvider<RequestedTabTour, String?>(RequestedTabTour.new);

/// Touren, bei denen in DIESER Sitzung „Nicht jetzt" oder „Später"
/// gewählt wurde. Nur im Speicher: Beim nächsten Start fragen sie wieder
/// (Betreiber, 2026-09-25: „jedes Mal"), in derselben Sitzung nicht bei
/// jedem Reiterwechsel.
class DeclinedTabTours extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String id) => state = {...state, id};
}

final declinedTabToursProvider =
    NotifierProvider<DeclinedTabTours, Set<String>>(DeclinedTabTours.new);

/// Die Reiter-Touren in der Reihenfolge der Leiste, mit ihrer Route.
const kTabTours = [
  (kSpotsTourScript, '/spots'),
  (kPilzeTourScript, '/pilze'),
  (kBuddysTourScript, '/friends'),
];

/// Startet [script] und merkt sich danach, dass sie gesehen wurde.
void startTabTour(WidgetRef ref, CoachScript script) {
  final seen = ref.read(seenCoachToursProvider.notifier);
  final declined = ref.read(declinedTabToursProvider.notifier);
  ref.read(coachProvider.notifier).start(script,
      onDone: () => seen.markSeen(script.id),
      onDecline: () => declined.add(script.id));
}

/// Der erste Start: Willkommensseite, Karten-Tour, danach die Reiter —
/// jeder mit seiner Startseite als FRAGE („Weiter mit den Spots?").
///
/// **Gefragt wird an jeder Grenze, nicht einmal am Anfang** (Betreiber:
/// „alles an einem Stück kann auch gut sein, man sollte aber den Nutzer
/// fragen"). Wer „Später" wählt, beendet die Kette; die übrigen Touren
/// kommen dann beim ersten Besuch ihres Reiters. „Nicht jetzt" auf der
/// Willkommensseite fragt beim nächsten Start wieder.
///
/// Notifier und Router werden VORHER gegriffen: Die Kette läuft über
/// mehrere Reiter, und der `ref` des Karten-Screens ist dabei vielleicht
/// schon nicht mehr zu gebrauchen.
void startWelcomeTour(WidgetRef ref, GoRouter router) {
  final coach = ref.read(coachProvider.notifier);
  final mapSeen = ref.read(mapTourSeenProvider.notifier);
  final seen = ref.read(seenCoachToursProvider.notifier);
  final declined = ref.read(declinedTabToursProvider.notifier);
  final returning = ref.read(settingsProvider).legacyMapTourSeen;
  coach.start(returning ? kReturningTourScript : kWelcomeTourScript,
      onDone: () {
    mapSeen.set(true);
    unawaited(_continueChain(coach, router, seen, declined, kTabTours));
  });
}

Future<void> _continueChain(
  CoachNotifier coach,
  GoRouter router,
  SeenCoachTours seen,
  DeclinedTabTours declined,
  List<(CoachScript, String)> rest,
) async {
  final open = [
    for (final tour in rest)
      if (!seen.hasSeen(tour.$1.id)) tour,
  ];
  if (open.isEmpty) return;
  final (script, route) = open.first;
  coach.reserve();
  router.go(route);
  // Bis der Reiter steht und seine Anker gemeldet hat — wie bei
  // `startHighlightDemo`.
  for (var i = 0; i < 3; i++) {
    await WidgetsBinding.instance.endOfFrame;
  }
  coach.start(script,
      chained: true,
      onDone: () {
        seen.markSeen(script.id);
        unawaited(
            _continueChain(coach, router, seen, declined, open.sublist(1)));
      },
      onDecline: () => declined.add(script.id));
}

/// Startet die Tour seines Reiters, sobald es passt. Gehört einmal in
/// den Reiter, um dessen Inhalt.
class TabTourStarter extends ConsumerStatefulWidget {
  const TabTourStarter({
    super.key,
    required this.script,
    this.ready = true,
    required this.child,
  });

  final CoachScript script;

  /// Gibt es schon etwas zu zeigen? Siehe Kopf der Datei.
  final bool ready;

  final Widget child;

  @override
  ConsumerState<TabTourStarter> createState() => _TabTourStarterState();
}

class _TabTourStarterState extends ConsumerState<TabTourStarter> {
  bool _scheduled = false;

  /// Lief beim Eintreffen schon etwas (eine Vorführung aus „Entdecken"),
  /// wartet die Tour bis zum nächsten Besuch des Reiters — sonst fiele sie
  /// über das Ende der Vorführung her, die man gerade bestellt hat.
  bool _yielded = false;

  @override
  Widget build(BuildContext context) {
    final id = widget.script.id;
    final requested = ref.watch(requestedTabTourProvider) == id;
    final seen = ref.watch(seenCoachToursProvider).contains(id) ||
        ref.watch(declinedTabToursProvider).contains(id);
    // Abhängigkeit, nicht nur Abfrage: Wird der Reiter sichtbar, baut
    // dieses Widget neu, und der Start wird erneut versucht.
    final visible = TickerMode.valuesOf(context).enabled;
    if (!visible) _yielded = false;
    if (visible && (requested || (!seen && widget.ready && !_yielded))) {
      _schedule();
    }
    return widget.child;
  }

  /// Nach dem Bild, weil die Anker erst dann vermessbar sind.
  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      if (!TickerMode.valuesOf(context).enabled) return;
      // Liegt eine Unterseite darüber (etwa eine Artseite), ist der
      // Reiter zwar aktiv, aber nicht zu sehen.
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      final requested = ref.read(requestedTabTourProvider) == widget.script.id;
      if (ref.read(coachProvider.notifier).busy) {
        if (!requested) _yielded = true;
        return;
      }
      if (requested) {
        ref.read(requestedTabTourProvider.notifier).clear();
      } else if (ref.read(seenCoachToursProvider).contains(widget.script.id) ||
          ref.read(declinedTabToursProvider).contains(widget.script.id) ||
          !widget.ready ||
          !ref.read(mapTourSeenProvider) ||
          !ref.read(safetyNoteSeenProvider)) {
        return;
      }
      startTabTour(ref, widget.script);
    });
  }
}
