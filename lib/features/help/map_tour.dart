// Die geführte Tour über die Karte (#350, neu gebaut für #596).
//
// **Seit 1.205.0 auf der Hinweis-Maschine** (`features/coach/coach.dart`).
// Die erste Fassung kannte nur Löcher auf der Karte — vergrößert und rund,
// gebaut für einzelne runde Knöpfe. Seit die Werkzeuge in EINER Leiste
// sitzen (1.133.0), schnitt sie Stücke aus der Leiste und ragte in den
// Nachbarknopf, und sie zeigte nur, WO ein Knopf ist. Jetzt FÜHRT sie
// vor: Der lange Druck öffnet das Kontextmenü, die Ebenen öffnen ihr
// Blatt (Betreiber, 2026-09-24: „wichtig ist mir, dass das Kontextmenü
// gezeigt wird, nicht nur der erste Button").
//
// **Kurz bleibt die Regel.** Sieben Schritte, und jeder erklärt etwas,
// das man nicht erraten kann. Die übrigen Reiter bekommen eigene kurze
// Touren, statt dass diese hier wächst (#596, zweiter Teil).
//
// **Sie blockiert nie.** „Überspringen" steht in jedem Schritt, und ein
// Tipp irgendwohin geht weiter. Was sie öffnet, schließt sie wieder,
// ohne dass etwas ausgelöst wird.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../coach/coach.dart';
import 'tour_intro_art.dart';

/// Die Leiste unten — die Karten-Tour nennt ihre Bereiche zum Schluss.
abstract final class NavCoach {
  static const bar = 'nav.bar';
  static const spots = 'nav.spots';
  static const pilze = 'nav.pilze';
  static const buddys = 'nav.buddys';
  static const profile = 'nav.profile';
}

/// Die Startseite beim ERSTEN Start (Betreiber, 2026-09-25: „zu Beginn der
/// Tour eine Startseite … man öffnet die App und es geht sofort los").
/// „Nicht jetzt" fragt beim nächsten Start wieder — jedes Mal.
const kWelcomeIntro = CoachStep(
  title: 'Willkommen bei PilzBuddy',
  text: 'Hier merkst du dir deine Pilzstellen, siehst, wann es sich lohnen '
      'könnte, und teilst Funde mit Freunden, wenn du willst. Deine Spots '
      'bleiben privat, bis du sie teilst.',
  art: welcomeArt,
  startLabel: 'Tour starten',
);

/// Dieselbe Stelle für Bestandsnutzer: Seit dem Zurücksetzen in 1.208.0
/// sehen auch sie die Tour, und „Willkommen" wäre für sie falsch.
const kReturningIntro = CoachStep(
  title: 'Eine kurze Tour durch PilzBuddy',
  text: 'Seit deinem letzten Blick ist einiges dazugekommen. In ein paar '
      'Schritten: was wo ist und wie es geht — auf der Karte und danach '
      'in den Bereichen unten.',
  art: welcomeArt,
  startLabel: 'Tour starten',
);

/// Die Startseite, wenn die Karten-Tour aus der Kurzanleitung kommt.
const kMapIntro = CoachStep(
  title: 'Die Karte',
  text: 'Hier legst du Spots an und siehst, was die Gegend verrät: Wald, '
      'Regen, Höhe und die Pilzampel. Die Tour zeigt die Knöpfe — und was '
      'dahinter liegt.',
  art: mapArt,
);

/// Zum Schluss der Karten-Tour die Bereiche unten, je ein Halbsatz — ihre
/// eigenen Touren laufen beim ersten Besuch (Betreiber: „nur kurz
/// erwähnen, nicht die jeweilige Tour starten").
const kNavStep = CoachStep(
  title: 'Unten die Bereiche',
  text: 'Spots: deine Stellen als Liste und Statistik. Pilze: jede Art mit '
      'Saison und Merkmalen. Buddys: Freunde, Fundfotos und Nachrichten. '
      'Profil: Einstellungen und die Kurzanleitung.',
  lit: [NavCoach.bar],
  ring: [NavCoach.spots, NavCoach.pilze, NavCoach.buddys, NavCoach.profile],
);

/// Die Anker der Karte — eine Stelle für die Kennungen, damit Skript und
/// Widgets dieselben Wörter benutzen.
abstract final class MapCoach {
  static const crosshair = 'map.crosshair';
  static const add = 'map.add';
  static const toolbar = 'map.toolbar';
  static const layers = 'map.layers';
  static const filter = 'map.filter';
  static const trip = 'map.trip';
  static const locate = 'map.locate';

  /// Szene: das Kontextmenü, geöffnet an der Bildmitte (am Fadenkreuz).
  static const contextMenu = 'map.contextMenu';

  /// Ein Eintrag des Kontextmenüs, je `MapContextAction.name`.
  static String menuEntry(String action) => 'map.menu.$action';

  /// Szene: das Ebenen-Blatt.
  static const layersSheet = 'map.layersSheet';
  static const layersForest = 'map.layers.forest';
  static const layersRain = 'map.layers.rain';
  static const layersGbif = 'map.layers.gbif';

  /// Der Vorhang — nur da, wenn eine Ebene an ist.
  static const hideLayers = 'map.hideLayers';

  /// Szene: das Unterwegs-Blatt, mit der Zeile der Pilztour.
  static const tripSheet = 'map.tripSheet';
  static const tripTour = 'map.trip.tour';

  /// Szene: das Anlege-Blatt am Fadenkreuz, mit „Nur vormerken".
  static const addSheet = 'map.addSheet';
  static const addPlanned = 'map.add.planned';
}

const kMapTourScript = CoachScript(
  id: 'map',
  endLink: ('Kurzanleitung', '/profile/anleitung'),
  steps: [
    kMapIntro,
    CoachStep(
      title: 'So entsteht ein Spot',
      // „fein" und „genau" seit #360 (die Karte startet schon bei der
      // eigenen Position), der Nachsatz seit #407: Gespeichert wird, was
      // im Blatt steht — das Fadenkreuz ist die Vorbelegung.
      text: 'Das Fadenkreuz in der Mitte zeigt, wo der Spot entsteht — '
          'nicht dein Standort. Schieb die Karte fein, bis es genau auf '
          'deiner Stelle liegt, und tipp auf „Neuer Spot"; im Blatt lässt '
          'sich die Stelle noch verschieben.',
      lit: [MapCoach.crosshair, MapCoach.add],
      // Der Ring nur um den Knopf: Um beide gelegt, wäre er ein Kasten
      // von der Bildmitte bis in die Ecke.
      ring: [MapCoach.add],
    ),
    CoachStep(
      title: 'Lange drücken',
      text: 'Schneller geht es direkt am Finger: Halte irgendwo auf der '
          'Karte gedrückt, dann öffnet sich ein Menü für genau diese Stelle.',
      lit: [MapCoach.crosshair],
      ring: [],
      gesture: CoachGesture.longPress,
    ),
    CoachStep(
      title: 'Neuer Spot, genau hier',
      text: 'Der oberste Eintrag legt den Spot an der gedrückten Stelle an '
          '— die Karte muss dafür nicht erst unters Fadenkreuz.',
      scene: MapCoach.contextMenu,
      lit: ['map.menu.addSpot'],
    ),
    CoachStep(
      // Nicht „Was ist hier?": So heißt der Eintrag selbst, und zwei
      // gleiche Wörter auf einem Schirm sind für Nutzer wie Test
      // mehrdeutig.
      title: 'Die anderen drei',
      text: '„Was ist hier?" zeigt Wald, Höhe, Regen und gemeldete Pilze an '
          'dieser Stelle. „Navigation" gibt sie an deine Navi-App, '
          '„Heranzoomen" holt sie nah heran.',
      scene: MapCoach.contextMenu,
      lit: ['map.menu.whatIsHere', 'map.menu.navigate', 'map.menu.zoomHere'],
    ),
    CoachStep(
      title: 'Was die Karte zeigt',
      // Die Legende steht hier und bekommt keinen eigenen Schritt (#436):
      // Ab Werk ist keine Ebene an, beim ersten Start gibt es sie also
      // gar nicht — ein eigener Schritt zeigte auf leere Fläche.
      text: 'Hinter „Ebenen" liegen Waldtypen, Höhenlinien, Regen und die '
          'Pilzampel. Die kleine Zahl am Knopf sagt, wie viele gerade an '
          'sind. Was ihre Farben bedeuten, steht links unten in der '
          'Legende — ein Tipp klappt sie ein und wieder aus.',
      lit: [MapCoach.toolbar],
      ring: [MapCoach.layers],
    ),
    CoachStep(
      title: 'Eine Ebene einschalten',
      text: 'Jede Zeile hat einen Schalter; ein Tipp auf die Zeile selbst '
          'öffnet ihre Einstellungen. Die Ebenen bleiben an, bis du sie '
          'wieder ausschaltest.',
      scene: MapCoach.layersSheet,
      // Nur die Zeile, nicht die ganze Liste: Ausgespart nähme das Blatt
      // auf einem kleinen Schirm fast alles, und die Sprechblase fände
      // keinen Platz mehr (360×640 im Test nachgemessen).
      lit: [MapCoach.layersForest],
    ),
    CoachStep(
      title: 'Unterwegs',
      // „Wozu" statt Buchhaltungswort (#434).
      text: '„Unterwegs" zeichnet deinen Weg als Pilztour auf und fragt '
          'am Ende, wo du gesucht und nichts gefunden hast; dort startest '
          'du auch das Standort-Teilen. Darüber der Filter, darunter der '
          'Knopf, der die Karte zu dir zurückholt.',
      lit: [MapCoach.toolbar],
      ring: [MapCoach.filter, MapCoach.trip, MapCoach.locate],
    ),
    kNavStep,
  ],
);

/// Die Karten-Tour beim ersten Start: mit der Willkommensseite statt der
/// Karten-Startseite. Die Reiter hängt `startWelcomeTour` an — deshalb
/// OHNE den Weg in die Kurzanleitung am Ende: Sonst liefe die Kette
/// gleichzeitig in den nächsten Reiter.
final kWelcomeTourScript = CoachScript(
  id: 'map',
  steps: [kWelcomeIntro, ...kMapTourScript.tourSteps],
);

/// Dasselbe für Bestandsnutzer ([kReturningIntro]).
final kReturningTourScript = CoachScript(
  id: 'map',
  steps: [kReturningIntro, ...kMapTourScript.tourSteps],
);

/// Startet die Tour und merkt sich danach, dass sie gesehen wurde —
/// durchgesehen ODER übersprungen: Wer abbricht, hat entschieden, und
/// eine Tour, die nach dem Überspringen wiederkommt, ist eine Belästigung.
///
/// Gemerkt wird über den NOTIFIER, nicht über [ref]: Aus der
/// Kurzanleitung gestartet, kann das aufrufende Widget weg sein, bevor
/// die Tour endet — und ein `ref` eines abgebauten Widgets wirft.
void startMapTour(WidgetRef ref) {
  final seen = ref.read(mapTourSeenProvider.notifier);
  ref
      .read(coachProvider.notifier)
      .start(kMapTourScript, onDone: () => seen.set(true));
}

/// Hat der Nutzer die Tour schon gesehen? Gerätelokal (Betreiber,
/// 2026-08-29) — dieselbe Ablage wie alle anderen Schalter.
///
/// Der Preis ist bekannt und angenommen: Nach einer Neuinstallation
/// läuft sie wieder. Ein Feld am Konto hätte einen Patch, `schema.sql`
/// und die Saat-Liste gekostet, für eine Frage, die einmal im Leben
/// eines Geräts gestellt wird.
final mapTourSeenProvider = NotifierProvider<RememberedFlag, bool>(
  () => RememberedFlag(
    read: (s) => s.mapTourSeen,
    write: (s, v) => s.setMapTourSeen(v),
    label: 'Karten-Tour merken',
  ),
);

/// Tourspur als Linie statt als Punkte? (#340) Gerätelokal, ab Werk aus.
final tourTrackAsLineProvider = NotifierProvider<RememberedFlag, bool>(
  () => RememberedFlag(
    read: (s) => s.tourTrackAsLine,
    write: (s, v) => s.setTourTrackAsLine(v),
    label: 'Spur-Darstellung merken',
  ),
);

/// Hat dieses Gerät den Haftungshinweis gesehen? (#110)
///
/// Gerätelokal wie [mapTourSeenProvider] und aus demselben Grund.
final safetyNoteSeenProvider = NotifierProvider<RememberedFlag, bool>(
  () => RememberedFlag(
    read: (s) => s.safetyNoteSeen,
    write: (s, v) => s.setSafetyNoteSeen(v),
    label: 'Haftungshinweis merken',
  ),
);
