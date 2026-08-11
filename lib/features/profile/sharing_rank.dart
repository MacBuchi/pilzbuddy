// Die Teil-Leiter (#276): Wer Spots mit seinen Buddies teilt, bekommt
// einen Titel.
//
// **Belohnen statt bestrafen.** Das Issue schlug ursprünglich eine
// Schranke vor — man sähe nur so viele fremde Spots, wie man selbst
// teilt. Verworfen (Betreiber, 2026-08-11), und der Grund lohnt das
// Aufschreiben: Eine Schranke trifft am härtesten den Neuen. Null
// geteilte Spots hieße leerste Karte, ausgerechnet im Moment der
// geringsten Bindung — er sähe nicht, was die App kann, teilte deshalb
// nichts und sähe weiter nichts. Der Riegel gegen Schnorrer existiert
// ohnehin schon: Man muss jemanden als Buddy annehmen.
//
// Rein Dart ohne Flutter, wie `ampel_model.dart` und `forest_grid.dart`
// und aus demselben Grund: Die Rechnung soll ohne App prüfbar sein.
import '../../models/spot.dart';

/// Eine Sprosse: ab wie vielen geteilten Spots, und wie sie heißt.
typedef SharingRank = ({int from, String title});

/// Die Leiter. Grob gestuft mit Absicht — so reißt ein einzelner
/// nachträglich ausgeschlossener Spot selten eine Grenze.
///
/// Unten das Bild, das die ganze Idee trägt (das Netz IST ein Myzel,
/// Teilen knüpft Fäden), oben etwas Warmes und sofort Verständliches.
const sharingRanks = <SharingRank>[
  (from: 1, title: 'Sporenstreuer'),
  (from: 10, title: 'Hyphenspinner'),
  (from: 25, title: 'Myzelweber'),
  (from: 50, title: 'Revierkenner'),
  (from: 100, title: 'Waldpate'),
];

/// Der Titel zu einer Anzahl — `null` bei null geteilten Spots.
///
/// **Bei null gibt es bewusst KEINEN Titel.** Kein „Frischling", kein
/// „Schnorrer": Die unterste Sprosse ist ein Ziel, keine Etikettierung.
/// Wer nichts teilt, wird nicht benannt, sondern eingeladen.
String? sharingTitleOf(int sharedSpots) {
  String? title;
  for (final rank in sharingRanks) {
    if (sharedSpots >= rank.from) title = rank.title;
  }
  return title;
}

/// Die nächste Sprosse — `null`, wenn die oberste erreicht ist.
SharingRank? nextSharingRank(int sharedSpots) {
  for (final rank in sharingRanks) {
    if (sharedSpots < rank.from) return rank;
  }
  return null;
}

/// Wie viele Spots jemand WIRKLICH teilt.
///
/// Zwei Bedingungen, und beide sind nötig, damit die Zahl nicht lügt:
/// Der globale Schalter muss an sein (`share_spots_default`) — sonst
/// sieht kein Buddy irgendetwas, egal wie viele Spots existieren — und
/// der einzelne Spot darf nicht ausgeschlossen sein.
int sharedSpotCount(Iterable<Spot> spots, {required bool sharesByDefault}) {
  if (!sharesByDefault) return 0;
  return spots.where((s) => !s.sharingExcluded).length;
}

/// Steht das Verhältnis schief genug, um es ehrlich zu benennen?
///
/// Der Spiegel („du siehst 34 und teilst 3") ist der Ersatz für die
/// verworfene Schranke: derselbe soziale Druck, aber niemandem wird
/// etwas weggenommen. Die Fünftel-Grenze ist gesetzt, nicht gemessen —
/// sie soll den klaren Fall treffen und nicht jeden, der gerade erst
/// anfängt.
bool showsSharingMirror({required int shared, required int seen}) =>
    seen > 0 && shared * 5 < seen;
