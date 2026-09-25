// „Zeig es mir" (#596, dritter Teil): je Eintrag in „Entdecken" eine
// kurze Vorführung auf der Hinweis-Maschine.
//
// **Sie endet IN der Funktion, nicht davor** (Betreiber, 2026-09-24: „sonst
// verweist einfach fast alles auf die Karte"). Wer „Regen auf der Karte"
// sehen will, bekommt das Ebenen-Blatt mit der Regenzeile, nicht den Knopf,
// hinter dem es liegt; wer die Artgalerie sucht, den Meldedialog mit den
// Bildern. Was eine Vorführung öffnet, schließt sie wieder — ohne dass
// etwas ausgelöst wird.
//
// Drei Dinge, die man wissen muss:
//
// - **Jeder Eintrag bringt seine Vorführung mit.**
//   `test/flows/highlight_demos_flow_test.dart` verlangt eine für jede
//   Kennung in `kFeatureHighlights` und fährt jede durch — dieselbe
//   Regel wie für den Eintrag selbst: wer die Funktion baut, bringt ihn im
//   selben PR mit.
// - **Was nicht jeder hat, hat einen Ersatzschritt.** Ohne Buddy gibt es
//   keinen Stift am ersten Buddy; dann zeigt die Vorführung das Suchfeld
//   (`requires` und `unless` in `CoachStep`). Genau einer der beiden
//   Schritte läuft.
// - **Schritttitel dürfen nicht wie etwas auf dem Schirm heißen** — zweimal
//   passiert („Was ist hier?", „Buddy finden"): Der Test fände dann das
//   Element statt der Blase.
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../coach/coach.dart';
import '../help/map_tour.dart';
import '../help/tab_tours.dart';

/// Eine Vorführung: wo sie beginnt und was sie zeigt.
class HighlightDemo {
  const HighlightDemo({required this.route, required this.script});

  /// Die Route, auf die zuerst gewechselt wird.
  final String route;
  final CoachScript script;

  /// Die Geste, die die Karte in „Entdecken" als kleines Bild zeigt: die
  /// erste, die die Vorführung benutzt, sonst ein Tipp.
  CoachGesture get gesture => script.steps
      .map((s) => s.gesture)
      .firstWhere((g) => g != CoachGesture.none, orElse: () => CoachGesture.tap);
}

CoachScript _demo(String id, List<CoachStep> steps) =>
    CoachScript(id: 'demo.$id', steps: steps);

// Bausteine, die mehrere Vorführungen teilen.

const _pilzeOpenFirst = CoachStep(
  title: 'Eine Art öffnen',
  text: 'Ein Tipp auf eine Art öffnet ihre Seite.',
  lit: [PilzeCoach.row],
  ring: [],
  gesture: CoachGesture.tap,
  requires: [PilzeCoach.row],
);

const _spotsOpenFirst = CoachStep(
  title: 'Einen Spot öffnen',
  text: 'Ein Tipp auf die Zeile öffnet das Spot-Blatt — dasselbe wie auf '
      'der Karte.',
  lit: [SpotsCoach.row],
  ring: [],
  gesture: CoachGesture.tap,
  requires: [SpotsCoach.row],
);

const _findBuddyFirst = CoachStep(
  title: 'Erst einen Buddy finden',
  text: 'Das geht mit deinen Buddys. Such hier nach einem Benutzernamen oder '
      'einer genauen E-Mail-Adresse — oder lade jemanden ein.',
  lit: [BuddysCoach.search],
  unless: [BuddysCoach.message],
);

final kHighlightDemos = <String, HighlightDemo>{
  // ─── Highlights ────────────────────────────────────────────────
  'nachrichten': HighlightDemo(
    route: '/friends',
    script: _demo('nachrichten', const [
      CoachStep(
        title: 'Zum Verlauf',
        text: 'Die Sprechblase neben einem Buddy öffnet eure Nachrichten. '
            'Steht eine Zahl daran, ist etwas ungelesen.',
        lit: [BuddysCoach.message],
        ring: [],
        gesture: CoachGesture.tap,
        requires: [BuddysCoach.message],
      ),
      CoachStep(
        title: 'Schreib los',
        text: 'Bis zu 500 Zeichen. Mit eingeschalteten Benachrichtigungen '
            'kommt eine Antwort auch an, wenn die App zu ist.',
        scene: BuddysCoach.chat,
        lit: [BuddysCoach.chatInput],
        requires: [BuddysCoach.message],
      ),
      _findBuddyFirst,
    ]),
  ),
  'pilze-reiter': HighlightDemo(
    route: '/pilze',
    script: _demo('pilze-reiter', [
      _pilzeOpenFirst,
      ...kPilzeTourScript.steps.skip(4),
    ]),
  ),
  'fundfotos': HighlightDemo(
    route: '/friends',
    script: _demo('fundfotos', const [
      CoachStep(
        title: 'Fundfotos deiner Buddys',
        text: 'Was Buddys an geteilten Funden fotografiert haben, 14 Tage '
            'lang. Der Ring zeigt, wie lange ein Foto noch bleibt.',
        lit: [BuddysCoach.gallery],
        requires: [BuddysCoach.gallery],
      ),
      CoachStep(
        title: 'Noch keine Fundfotos',
        text: 'Teilt ein Buddy ein Foto zu einem Fund, steht es hier ganz '
            'oben. Dein eigenes hängst du beim Eintragen eines Funds an; den '
            'Standort nimmt die App vorher aus dem Bild.',
        unless: [BuddysCoach.gallery],
      ),
    ]),
  ),
  'pilzampel': HighlightDemo(
    route: '/profile',
    script: _demo('pilzampel', const [
      CoachStep(
        title: 'Hier einschalten',
        text: 'Mit diesem Schalter liegt die Ampel unter „Ebenen". Sie '
            'bewertet das Wetter — nicht, ob dort Pilze stehen.',
        lit: [ProfileCoach.ampel],
        scrollIn: ProfileCoach.list,
      ),
    ]),
  ),
  'wald': HighlightDemo(
    route: '/',
    script: _demo('wald', const [
      CoachStep(
        title: 'Laub, Nadel, Misch',
        text: 'Der Schalter färbt die Waldwaben ein. Welche Bäume an einem '
            'Spot wachsen, steht in dessen Blatt — für Deutschland.',
        scene: MapCoach.layersSheet,
        lit: [MapCoach.layersForest],
      ),
    ]),
  ),
  'regen': HighlightDemo(
    route: '/',
    script: _demo('regen', const [
      CoachStep(
        title: 'Regen einblenden',
        text: 'Radar für jetzt und die nächste Stunde, dazu die Summen über '
            '24 Stunden und 30 Tage. Im Spot-Blatt steht der Regen an genau '
            'dieser Stelle.',
        scene: MapCoach.layersSheet,
        lit: [MapCoach.layersRain],
      ),
    ]),
  ),
  'spots-reiter': HighlightDemo(
    route: '/spots',
    script: _demo('spots-reiter', kSpotsTourScript.steps),
  ),
  'fundorte': HighlightDemo(
    route: '/',
    script: _demo('fundorte', const [
      CoachStep(
        title: 'Meldungen aus GBIF',
        text: 'Je Pilzgruppe gefärbt, jede Scheibe so groß wie die '
            'Ungenauigkeit der Meldung. Keine Scheibe heißt „nicht '
            'gemeldet", nicht „nichts da".',
        scene: MapCoach.layersSheet,
        lit: [MapCoach.layersGbif],
      ),
    ]),
  ),
  'pilztour': HighlightDemo(
    route: '/',
    script: _demo('pilztour', const [
      CoachStep(
        title: 'Unterwegs öffnen',
        text: 'Pilztour und Standort-Teilen liegen hinter diesem Knopf.',
        lit: [MapCoach.toolbar],
        ring: [MapCoach.trip],
        gesture: CoachGesture.tap,
      ),
      CoachStep(
        title: 'Weg aufzeichnen',
        text: 'Ein Tipp startet die Aufzeichnung. Am Ende schlägt sie für '
            'abgesuchte Spots „nichts gefunden" vor — und wer seinen '
            'Standort teilt, zeigt den Buddys auch die Spur.',
        scene: MapCoach.tripSheet,
        lit: [MapCoach.tripTour],
      ),
    ]),
  ),
  'schutzgebiete': HighlightDemo(
    route: '/',
    script: _demo('schutzgebiete', const [
      CoachStep(
        title: 'Schraffiert heißt geschützt',
        text: 'Liegt eine Wabe wahrscheinlich in einem Naturschutzgebiet, ist '
            'sie schraffiert statt gefüllt — bei Wald und Pilzampel. Was dort '
            'gilt, regelt das Gebiet selbst.',
        scene: MapCoach.layersSheet,
        lit: [MapCoach.layersForest],
      ),
    ]),
  ),

  // ─── Tipps ─────────────────────────────────────────────────────
  'langer-tipp': HighlightDemo(
    route: '/',
    script: _demo('langer-tipp', [
      kMapTourScript.steps[1],
      const CoachStep(
        title: 'Vier Wege von hier',
        text: '„Neuer Spot" genau an dieser Stelle, „Was ist hier?", '
            'Navigation und Heranzoomen.',
        scene: MapCoach.contextMenu,
        lit: [
          'map.menu.addSpot',
          'map.menu.whatIsHere',
          'map.menu.navigate',
          'map.menu.zoomHere',
        ],
      ),
    ]),
  ),
  'vormerken': HighlightDemo(
    route: '/',
    script: _demo('vormerken', const [
      CoachStep(
        title: 'Einen Spot anlegen',
        text: 'Wie immer über „Neuer Spot" oder den langen Druck.',
        lit: [MapCoach.crosshair, MapCoach.add],
        ring: [MapCoach.add],
        gesture: CoachGesture.tap,
      ),
      CoachStep(
        title: 'Für später notieren',
        text: 'Mit diesem Schalter bekommt der Spot keinen Fund, nur die '
            'Arten, die du dort erwartest. Er steht blass auf der Karte, bis '
            'du etwas einträgst.',
        scene: MapCoach.addSheet,
        lit: [MapCoach.addPlanned],
      ),
    ]),
  ),
  'ebenen-weg': HighlightDemo(
    route: '/',
    script: _demo('ebenen-weg', const [
      CoachStep(
        title: 'Alles kurz weg',
        text: 'Ein Tipp nimmt alle Flächen von der Karte, ein zweiter holt '
            'genau die zurück, die vorher an waren.',
        lit: [MapCoach.toolbar],
        ring: [MapCoach.hideLayers],
        gesture: CoachGesture.tap,
        requires: [MapCoach.hideLayers],
      ),
      CoachStep(
        title: 'Erst eine Ebene an',
        text: 'Der Knopf zum Wegblenden erscheint in der Leiste, sobald unter '
            '„Ebenen" etwas eingeschaltet ist.',
        lit: [MapCoach.toolbar],
        ring: [MapCoach.layers],
        unless: [MapCoach.hideLayers],
      ),
    ]),
  ),
  'spot-korrigieren': HighlightDemo(
    route: '/spots',
    script: _demo('spot-korrigieren', const [
      _spotsOpenFirst,
      CoachStep(
        title: 'Name und Stelle ändern',
        text: 'Der Stift ändert Name und Stelle — praktisch, wenn das GPS '
            'unter Bäumen zwanzig Meter daneben lag.',
        scene: SpotsCoach.sheet,
        lit: [SpotsCoach.sheetEdit],
        requires: [SpotsCoach.row],
      ),
      CoachStep(
        title: 'Noch kein Spot',
        text: 'Sobald du einen Spot angelegt hast, ändert der Stift in seinem '
            'Blatt Name und Stelle.',
        unless: [SpotsCoach.row],
      ),
    ]),
  ),
  'alias': HighlightDemo(
    route: '/friends',
    script: _demo('alias', const [
      CoachStep(
        title: 'Ein eigener Name',
        text: 'Der Stift gibt einem Buddy einen Namen, den nur du siehst — '
            'überall in der App, auch in Benachrichtigungen.',
        lit: [BuddysCoach.alias],
        ring: [],
        gesture: CoachGesture.tap,
        requires: [BuddysCoach.alias],
      ),
      _findBuddyFirst,
    ]),
  ),
  'bilder-gross': HighlightDemo(
    route: '/pilze',
    script: _demo('bilder-gross', const [
      _pilzeOpenFirst,
      CoachStep(
        title: 'Antippen zum Vergrößern',
        text: 'Jedes Bild lässt sich antippen und mit zwei Fingern '
            'vergrößern — auch ohne Empfang.',
        scene: PilzeCoach.detail,
        lit: [PilzeCoach.detailPictures],
        ring: [],
        gesture: CoachGesture.tap,
        requires: [PilzeCoach.row],
        scrollIn: PilzeCoach.detailList,
      ),
    ]),
  ),
  'auge': HighlightDemo(
    route: '/pilze',
    script: _demo('auge', const [
      CoachStep(
        title: 'Bilder vorhanden',
        text: 'Das Auge steht hinter jeder Art, zu der es Bilder gibt. Wo es '
            'fehlt, fehlt noch ein Foto.',
        lit: [PilzeCoach.row],
        ring: [PilzeCoach.rowEye],
        requires: [PilzeCoach.rowEye],
      ),
      CoachStep(
        title: 'Wo das Auge steht',
        text: 'Hinter dem Namen einer Art, zu der es Bilder gibt. Wo es '
            'fehlt, fehlt noch ein Foto.',
        lit: [PilzeCoach.row],
        unless: [PilzeCoach.rowEye],
      ),
    ]),
  ),
  'galerie-foto': HighlightDemo(
    route: '/pilze',
    script: _demo('galerie-foto', const [
      _pilzeOpenFirst,
      CoachStep(
        title: 'Ganz unten',
        text: 'Am Ende jeder Artseite: der Weg, einen Hinweis zur Art zu '
            'schicken.',
        scene: PilzeCoach.detail,
        lit: [PilzeCoach.detailReport],
        scrollIn: PilzeCoach.detailList,
        requires: [PilzeCoach.row],
      ),
      CoachStep(
        title: 'Bilder für die Galerie',
        text: 'Bis zu drei Bilder. Mit Bild erscheint ein Haken für die '
            'Artgalerie — freiwillig, ab Werk aus.',
        scene: PilzeCoach.report,
        lit: [PilzeCoach.reportPhotos],
        requires: [PilzeCoach.row],
      ),
    ]),
  ),
  'reiter-touren': HighlightDemo(
    route: '/profile/anleitung',
    script: _demo('reiter-touren', const [
      CoachStep(
        title: 'Noch einmal ansehen',
        text: 'Spots, Pilze und Buddys zeigen beim ersten Besuch, was sie '
            'können. Hier startest du jede Tour neu.',
        lit: [HelpCoach.tabTours],
        scrollIn: HelpCoach.list,
      ),
    ]),
  ),
};

/// Wechselt zur Route der Vorführung und startet sie, sobald der Reiter
/// steht.
///
/// **Erst nach ein paar Bildern**, nicht sofort: `requires` fragt beim
/// Start, ob die Anker DA sind, und die des Zielreiters meldet erst sein
/// Aufbau an. Bis dahin ist der Start vorgemerkt (`reserve`), damit die
/// Tour des Reiters nicht dazwischenkommt.
Future<void> startHighlightDemo(
    GoRouter router, CoachNotifier coach, HighlightDemo demo) async {
  coach.reserve();
  router.go(demo.route);
  for (var i = 0; i < 3; i++) {
    await WidgetsBinding.instance.endOfFrame;
  }
  coach.start(demo.script);
}
