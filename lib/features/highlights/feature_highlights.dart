// Neuheiten und Tipps (#596) — die Daten und die eine Entscheidung,
// wer wann was sieht. Keine Widgets außer den Symbolen, wie
// `species_catalogue.dart`: Was hier steht, prüft ein Test ohne Bild.
//
// **Eine Liste, zwei Anzeigen.** Das Blatt nach einer Beförderung zeigt
// die jüngsten Highlights (höchstens drei), die Seite „Entdecken" zeigt
// alles. Tipps (die Detailfunktionen, die kaum jemand kennt) stehen nur
// dort — ein Blatt beim Start, das Kleinigkeiten ankündigt, wird nach dem
// zweiten Mal weggewischt, ohne gelesen zu werden.
//
// **Rückwirkend geht es nur über einen Umweg.** Bis 1.204.0 hat kein
// Gerät gespeichert, welche Version es zuletzt kannte. Die Karten-Tour
// hat aber seit 1.107.0 einen Merker, und der trennt die beiden Fälle:
// Wer sie gesehen hat, ist Bestandsnutzer und bekommt EINMAL den
// Rückblick; wer nicht, hat frisch installiert, bekommt die Tour und
// startet ohne Rückstand.
//
// **Wer eine Funktion baut, bringt ihren Eintrag im selben PR mit.**
// Kuratiert wird dann nicht bei der Beförderung: Stehen mehr als drei
// an, zeigt das Blatt die jüngsten, der Rest wartet in „Entdecken".
import 'package:flutter/material.dart';

import '../../core/update_check.dart' show isNewerVersion;

/// Highlight (ins Blatt) oder Tipp (nur „Entdecken").
enum HighlightKind { highlight, tip }

/// Wo die Funktion wohnt — die Gruppen der Seite „Entdecken", in der
/// Reihenfolge der Reiterleiste.
enum HighlightTab {
  map('Karte'),
  spots('Spots'),
  pilze('Pilze'),
  buddys('Buddys'),
  profile('Profil');

  const HighlightTab(this.label);
  final String label;
}

/// Ein Eintrag.
class FeatureHighlight {
  const FeatureHighlight({
    required this.id,
    required this.since,
    required this.kind,
    required this.tab,
    required this.icon,
    required this.title,
    required this.text,
    required this.target,
  });

  /// Stabil für immer: Unter ihr merkt sich das Gerät „gesehen".
  final String id;

  /// Die Version, mit der die Funktion kam. Nie über der eigenen —
  /// ein Test prüft das gegen `pubspec.yaml`.
  final String since;

  final HighlightKind kind;
  final HighlightTab tab;

  /// Das ECHTE Symbol der Funktion, wo es eins gibt — wer „Ebenen"
  /// sucht, sucht das Bild auf dem Knopf, keine Beschreibung davon.
  final IconData icon;

  final String title;

  /// Zwei, höchstens drei Sätze.
  final String text;

  /// Wohin „Ausprobieren" führt: eine Route der App.
  final String target;
}

const kFeatureHighlights = <FeatureHighlight>[
  // ─── Highlights ──────────────────────────────────────────────────
  FeatureHighlight(
    id: 'nachrichten',
    since: '1.193.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.buddys,
    icon: Icons.chat_bubble_outline,
    title: 'Nachrichten an deine Buddys',
    text: 'Tipp im Reiter „Buddys" auf einen Namen und schreib los. Mit '
        'eingeschalteten Benachrichtigungen kommt eine Antwort auch dann '
        'an, wenn die App zu ist.',
    target: '/friends',
  ),
  FeatureHighlight(
    id: 'pilze-reiter',
    since: '1.153.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.pilze,
    icon: Icons.menu_book_outlined,
    title: 'Jede Art mit eigener Seite',
    text: 'Im Reiter „Pilze" steht zu jeder Art, ob sie essbar oder giftig '
        'ist, woran man sie erkennt und womit man sie verwechseln kann — '
        'mit Bildern und der Saison, in der sie gemeldet wird.',
    target: '/pilze',
  ),
  FeatureHighlight(
    id: 'fundfotos',
    since: '1.185.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.buddys,
    icon: Icons.photo_camera_outlined,
    title: 'Fundfotos für deine Buddys',
    text: 'Häng beim Eintragen ein Foto an deinen Fund. Deine Buddys sehen '
        'es 14 Tage lang oben im Reiter „Buddys" und können mit einem Pilz '
        'antworten. Den Standort nimmt die App vorher aus dem Bild.',
    target: '/friends',
  ),
  FeatureHighlight(
    id: 'pilzampel',
    since: '1.72.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.traffic_outlined,
    title: 'Die Pilzampel',
    // Das Ziel ist das PROFIL, nicht die Karte: Ohne den Schalter
    // „Pilzwetter-Ampel" dort steht sie nicht einmal unter „Ebenen" —
    // genau deshalb kennt sie kaum jemand.
    text: 'Sie schätzt aus Regen, Wärme und Saison, wo es sich gerade '
        'lohnen könnte. Einschalten im Profil unter „Pilzwetter-Ampel", '
        'danach liegt sie unter „Ebenen". Sie bewertet das Wetter, nicht '
        'die Pilze.',
    target: '/profile',
  ),
  FeatureHighlight(
    id: 'wald',
    since: '1.62.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.forest_outlined,
    title: 'Welcher Wald ist das?',
    text: 'Unter „Ebenen" färbt die Karte Laub-, Nadel- und Mischwald ein. '
        'Im Spot-Blatt steht außerdem, welche Bäume dort wachsen — für '
        'Deutschland.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'regen',
    since: '1.45.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.water_drop_outlined,
    title: 'Regen auf der Karte',
    text: 'Unter „Ebenen" liegen das Regenradar für jetzt und die nächste '
        'Stunde und die Summen der letzten 24 Stunden und 30 Tage. Im '
        'Spot-Blatt siehst du den Regen an genau dieser Stelle, Tag für Tag.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'spots-reiter',
    since: '1.161.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.spots,
    icon: Icons.list_alt_outlined,
    title: 'Alle Spots als Liste',
    text: 'Der Reiter „Spots" zeigt deine Stellen und die deiner Buddys, '
        'sortiert nach dem letzten Eintrag, mit Suche — und darunter deine '
        'Statistik übers Jahr.',
    target: '/spots',
  ),
  FeatureHighlight(
    id: 'fundorte',
    since: '1.154.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.blur_circular,
    title: 'Wo andere Pilze gemeldet haben',
    text: 'Unter „Ebenen" zeigt die Karte Meldungen aus GBIF, je Pilzgruppe '
        'eingefärbt. Eine Scheibe heißt „hier gemeldet, auf so viel Meter '
        'genau" — keine Scheibe heißt nicht „nichts da".',
    target: '/',
  ),
  FeatureHighlight(
    id: 'pilztour',
    since: '1.102.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.hiking,
    title: 'Die Pilztour',
    text: 'Unter „Unterwegs" zeichnet sie deinen Weg auf. Am Ende schlägt '
        'sie für abgesuchte Spots „nichts gefunden" vor — und wer seinen '
        'Standort teilt, zeigt den Buddys auch die Spur.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'schutzgebiete',
    since: '1.201.0',
    kind: HighlightKind.highlight,
    tab: HighlightTab.map,
    icon: Icons.shield_outlined,
    title: 'Naturschutzgebiete',
    text: 'Wo Sammeln meist verboten ist, schraffiert die Karte die Wald- '
        'und Ampelfläche, und beim Anlegen eines Spots steht ein Satz dazu. '
        'Was genau gilt, regelt das Gebiet selbst.',
    target: '/',
  ),

  // ─── Tipps ───────────────────────────────────────────────────────
  FeatureHighlight(
    id: 'langer-tipp',
    since: '1.177.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.map,
    icon: Icons.touch_app_outlined,
    title: 'Lange auf die Karte drücken',
    text: 'Öffnet ein Menü: „Neuer Spot" genau an dieser Stelle, „Was ist '
        'hier?", Navigation und Heranzoomen. Die Karte vorher zu '
        'verschieben, bis der Punkt unterm Fadenkreuz liegt, ist nicht '
        'mehr nötig.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'vormerken',
    since: '1.159.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.map,
    icon: Icons.bookmark_add_outlined,
    title: 'Spots vormerken',
    text: 'Beim Anlegen „Nur vormerken, noch kein Fund" wählen: Der Spot '
        'steht blass auf der Karte, mit den Arten, die du dort erwartest. '
        'Der erste Fund macht daraus einen normalen Spot.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'ebenen-weg',
    since: '1.145.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.map,
    icon: Icons.layers_clear_outlined,
    title: 'Ebenen kurz wegblenden',
    text: 'Sobald eine Ebene an ist, steht dieser Knopf in der Leiste. Ein '
        'Tipp nimmt alle Flächen weg, ein zweiter holt genau die zurück, '
        'die vorher an waren.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'spot-korrigieren',
    since: '1.144.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.map,
    icon: Icons.edit_outlined,
    title: 'Spots nachträglich korrigieren',
    text: 'Der Stift oben rechts im Spot-Blatt ändert Name und Stelle — '
        'praktisch, wenn das GPS unter Bäumen zwanzig Meter daneben lag.',
    target: '/',
  ),
  FeatureHighlight(
    id: 'alias',
    since: '1.195.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.buddys,
    icon: Icons.badge_outlined,
    title: 'Eigene Namen für Buddys',
    text: 'Der Stift neben einem Buddy gibt ihm einen Namen, den nur du '
        'siehst — überall in der App, auch in Benachrichtigungen.',
    target: '/friends',
  ),
  FeatureHighlight(
    id: 'bilder-gross',
    since: '1.179.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.pilze,
    icon: Icons.zoom_in,
    title: 'Bilder groß ansehen',
    text: 'Jedes Bild auf einer Artseite lässt sich antippen und mit zwei '
        'Fingern vergrößern — auch ohne Empfang.',
    target: '/pilze',
  ),
  FeatureHighlight(
    id: 'auge',
    since: '1.173.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.pilze,
    icon: Icons.visibility_outlined,
    title: 'Das Auge in der Artenliste',
    text: 'Es steht hinter jeder Art, zu der es Bilder gibt. Umgekehrt '
        'gelesen: Wo es fehlt, fehlt noch ein Foto.',
    target: '/pilze',
  ),
  FeatureHighlight(
    id: 'galerie-foto',
    since: '1.197.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.pilze,
    icon: Icons.add_photo_alternate_outlined,
    title: 'Deine Fotos für die Artgalerie',
    text: 'Unten auf jeder Artseite: „Hinweis zu dieser Art melden", bis zu '
        'drei Bilder anhängen und den Haken für die Galerie setzen. '
        'Freiwillig, ab Werk aus.',
    target: '/pilze',
  ),
  FeatureHighlight(
    id: 'reiter-touren',
    since: '1.206.0',
    kind: HighlightKind.tip,
    tab: HighlightTab.profile,
    icon: Icons.play_circle_outline,
    title: 'Kurze Touren in jedem Reiter',
    text: 'Spots, Pilze und Buddys zeigen beim ersten Besuch, was sie '
        'können. Noch einmal ansehen: Profil → Kurzanleitung.',
    target: '/profile/anleitung',
  ),
];

/// Die drei Highlights, mit denen der RÜCKBLICK beginnt. Beim Rückblick
/// wäre „die jüngsten" die falsche Regel — dann stünden dort drei
/// Kleinigkeiten der letzten Woche statt der Funktionen, die man kennen
/// sollte. Entschieden mit dem Betreiber, 2026-09-24.
const kRecapLead = ['nachrichten', 'pilze-reiter', 'fundfotos'];

/// Höchstens so viele Seiten im Blatt. Mehr liest niemand, und der
/// Rest steht in „Entdecken".
const kHighlightSheetMax = 3;

/// Was beim Start zu tun ist.
sealed class HighlightPlan {
  const HighlightPlan();
}

/// Nichts zeigen, nichts merken (Version unbekannt).
class HighlightNothing extends HighlightPlan {
  const HighlightNothing();
}

/// Nichts zeigen, aber [version] als gesehen merken — frische
/// Installation oder ein Update ohne neues Highlight.
class HighlightRecord extends HighlightPlan {
  const HighlightRecord(this.version);
  final String version;
}

/// Das Blatt zeigen.
class HighlightShow extends HighlightPlan {
  const HighlightShow({
    required this.version,
    required this.pages,
    required this.recap,
    required this.more,
  });

  /// Die Version, die danach als gesehen gilt.
  final String version;
  final List<FeatureHighlight> pages;

  /// Rückblick (Bestandsnutzer, erstes Mal) statt „neu seit".
  final bool recap;

  /// Wie viele weitere in „Entdecken" warten.
  final int more;
}

/// Die eine Entscheidung. Rein, damit jeder Fall ohne App prüfbar ist.
HighlightPlan planHighlights({
  required String? current,
  required String? seenVersion,
  required bool mapTourSeen,
  List<FeatureHighlight> all = kFeatureHighlights,
  List<String> recapLead = kRecapLead,
}) {
  if (current == null || !_isVersion(current)) return const HighlightNothing();
  final shipped = [
    for (final h in all)
      if (h.kind == HighlightKind.highlight && !isNewerVersion(h.since, current))
        h,
  ];
  if (seenVersion == null) {
    // Frisch installiert: Die Tour erklärt, ein Rückblick auf Dinge, die
    // es vorher nie gab, wäre keiner.
    if (!mapTourSeen) return HighlightRecord(current);
    final lead = [
      for (final id in recapLead)
        ...shipped.where((h) => h.id == id),
    ];
    final pages = [
      ...lead,
      ...shipped.where((h) => !lead.contains(h)),
    ].take(kHighlightSheetMax).toList();
    if (pages.isEmpty) return HighlightRecord(current);
    return HighlightShow(
      version: current,
      pages: pages,
      recap: true,
      more: shipped.length - pages.length,
    );
  }
  // Gemerkt ist schon dieser Stand oder ein jüngerer (etwa nach einem
  // Rückschritt vom Vorabkanal): nichts zeigen und vor allem nichts
  // ZURÜCKschreiben — sonst käme alles dazwischen noch einmal.
  if (!isNewerVersion(current, seenVersion)) return const HighlightNothing();
  final pending = shipped
      .where((h) => isNewerVersion(h.since, seenVersion))
      .toList()
    // Jüngste zuerst; bei gleicher Version bleibt die Reihenfolge der
    // Liste (`sort` ist in Dart nicht stabil, daher der Index).
    ..sort((a, b) {
      if (a.since == b.since) return all.indexOf(a) - all.indexOf(b);
      return isNewerVersion(a.since, b.since) ? -1 : 1;
    });
  if (pending.isEmpty) return HighlightRecord(current);
  final pages = pending.take(kHighlightSheetMax).toList();
  return HighlightShow(
    version: current,
    pages: pages,
    recap: false,
    more: pending.length - pages.length,
  );
}

bool _isVersion(String v) => RegExp(r'^\d+\.\d+\.\d+').hasMatch(v.trim());
