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

import '../../core/errors.dart';
import '../../core/settings.dart';
import '../coach/coach.dart';
import 'map_tour.dart';

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
}

/// Die Anker des Reiters „Pilze".
abstract final class PilzeCoach {
  /// Die erste Art der Liste, ihre Saisonbalken und ihr Ampel-Schalter.
  static const row = 'pilze.row';
  static const rowSeason = 'pilze.row.season';
  static const rowSwitch = 'pilze.row.switch';
  static const search = 'pilze.search';
  static const seasonChip = 'pilze.seasonChip';

  /// Szene: die Seite der ersten Art.
  static const detail = 'pilze.detail';
  static const detailEdibility = 'pilze.detail.edibility';
  static const detailPictures = 'pilze.detail.pictures';
}

/// Die Anker des Reiters „Buddys".
abstract final class BuddysCoach {
  static const gallery = 'buddys.gallery';
  static const invite = 'buddys.invite';
  static const search = 'buddys.search';

  /// Stift und Sprechblase am ersten Buddy.
  static const alias = 'buddys.alias';
  static const message = 'buddys.message';
}

const kSpotsTourScript = CoachScript(
  id: 'spots',
  steps: [
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
      requires: [PilzeCoach.detailPictures],
    ),
  ],
);

const kBuddysTourScript = CoachScript(
  id: 'buddys',
  steps: [
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

/// Startet [script] und merkt sich danach, dass sie gesehen wurde.
void startTabTour(WidgetRef ref, CoachScript script) {
  final seen = ref.read(seenCoachToursProvider.notifier);
  ref
      .read(coachProvider.notifier)
      .start(script, onDone: () => seen.markSeen(script.id));
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

  @override
  Widget build(BuildContext context) {
    final id = widget.script.id;
    final requested = ref.watch(requestedTabTourProvider) == id;
    final seen = ref.watch(seenCoachToursProvider).contains(id);
    // Abhängigkeit, nicht nur Abfrage: Wird der Reiter sichtbar, baut
    // dieses Widget neu, und der Start wird erneut versucht.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && (requested || (!seen && widget.ready))) _schedule();
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
      if (ref.read(coachProvider) != null) return;
      final requested = ref.read(requestedTabTourProvider) == widget.script.id;
      if (requested) {
        ref.read(requestedTabTourProvider.notifier).clear();
      } else if (ref.read(seenCoachToursProvider).contains(widget.script.id) ||
          !widget.ready ||
          !ref.read(mapTourSeenProvider) ||
          !ref.read(safetyNoteSeenProvider)) {
        return;
      }
      startTabTour(ref, widget.script);
    });
  }
}
