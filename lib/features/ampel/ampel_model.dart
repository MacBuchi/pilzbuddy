// Der Modellkern der Pilzampel — DIE austauschbare Stelle.
//
// **Spiegel von `tool/ampel_validate.py`** (Konstanten UND
// Funktionsformen): Das Python-Werkzeug validiert genau dieses Modell
// rückwärts an GBIF-Funden; was hier rechnet, muss deshalb Zahl für
// Zahl dasselbe sein — `test/ampel_model_test.dart` nagelt das mit
// Fixtures fest, die aus dem Werkzeug erzeugt wurden. Änderungen gehören
// IMMER in beide Dateien, und die Validierung behält das letzte Wort:
// Diese Vorschau ist ein Experiment hinter einem Schalter
// (Betreiberentscheidung 2026-08-09, docs/pilzampel-konzept.md),
// fällt das Placebo durch, wird dieser Kern getauscht oder die
// Vorschau entfernt.
//
// Kalibrierung nach docs/pilzampel-konzept.md (Bielefelder Zahlen, ein
// Standort, eine Art, Preprint): Fruchtungsgipfel bei ~13 °C
// Mitteltemperatur über 20 Tage, linear steigend mit dem über 26 Tage
// kumulierten Niederschlag, ältere Tage schwächer gewichtet.
//
// **Seit 1.137.0 ist das nicht mehr EIN Zahlensatz für alles.** Die
// Einheit ist die KLASSE — ein Temperaturfenster, aus dem die beiden
// Stufenschwellen als Quantile folgen. Der Grund ist gemessen, nicht
// gedacht: Dieselbe Schwelle bedeutet unter einem anderen Fenster etwas
// anderes, und zwar drastisch (der Austernseitling kommt mit 0,5 auf
// 1,1 % günstige Fundtage, der Steinpilz auf 58,4 %). Umgekehrt sind
// die Schwellen von Arten, die sich ein Fenster teilen, nicht
// unterscheidbar — je Art ausgeliefert wären sie Rauschen in
// Konstantenform (`docs/pilzampel-schwellen-messung.md`).
//
// Aufgenommen wird eine Klasse erst nach einem **Hold-out**: angepasst
// auf einem Teil der Daten, bestätigt auf Daten, die daran nie
// beteiligt waren. „Fällt in der Tabelle auf" reicht nicht — daran wäre
// die Pfifferling-Spur fast gescheitert, bis Österreich und die Schweiz
// sie bestätigt haben.
//
// Rein Dart ohne Flutter, wie `forest_grid.dart` und aus demselben
// Grund: Die Rechnung soll ohne App testbar sein.
import 'dart:math' as math;

import '../../core/mushroom_species.dart' show canonicalSpecies;

/// Fenster und Konstanten — identisch zum Validierungswerkzeug.
const ampelRainWindow = 26;
const ampelTempWindow = 20;
const ampelTempSigma = 5.0;
const ampelRainSaturationMm = 87.0;

/// Das Fenster, mit dem die KARTE rechnet: Dort ist keine Art bekannt,
/// also gilt die Gildenfrage „Steinpilz & Co.".
const ampelOptimumC = 13.0;

/// Eine Ampel-Klasse ist **ein Temperaturfenster** — die beiden
/// Schwellen sind kein zweiter freier Parameter, sondern fallen daraus:
/// das 50-%- und das 80-%-Quantil der Score-Verteilung, die dieses
/// Fenster an Vergleichstagen erzeugt
/// (`docs/pilzampel-schwellen-messung.md`).
typedef AmpelClass = ({
  /// Wie die Klasse im Blatt und in der Legende heißt — deutsch, und
  /// nach ihren MITGLIEDERN benannt, nicht nach einer Jahreszeit.
  /// „Sommerpilze" behauptete eine ganze Gruppe; drin steht bislang ein
  /// Pfifferling. Der Name wächst mit der Klasse.
  String name,
  double optimumC,
  double verhaltenAbove,
  double guenstigAbove,
});

/// **Warum die Klasse die Einheit ist und nicht die Art**
/// (Betreiberentscheidung 2026-09-12): Arten mit demselben Fenster
/// bekommen Schwellen, deren Vertrauensbereiche sich satt überlappen —
/// Steinpilz [0,148, 0,238] gegen Herbsttrompete [0,089, 0,284]. Je Art
/// ausgeliefert wäre das Rauschen in Konstantenform, und am Ende
/// stünden 110 Einträge da, von denen keiner mehr prüfbar ist. Zwischen
/// den Fenstern liegen dagegen Welten (0,512 gegen 0,038 beim
/// Austernseitling).
const ampelHerbstClass = (
  name: 'Steinpilz & Co.',
  optimumC: ampelOptimumC,
  verhaltenAbove: 0.187,
  guenstigAbove: 0.512,
);

/// Der Pfifferling ist ein Sommerfrüchter — Gipfel im Juli, nicht im
/// September. Sein eigenes Fenster hat als einziges den **geografischen
/// Hold-out** bestanden: in Deutschland angepasst, in AT und CH geprüft,
/// AUC 0,584 → 0,689 (+0,104 [+0,055, +0,150]) bei abstandsgleicher
/// Kontrolle 0,510 (`docs/pilzampel-artenfenster-holdout.md`). Ohne
/// diesen Nachweis stünde er hier nicht: Gemessen wurde er, weil er in
/// einer Tabelle auffiel, und das allein ist kein Befund.
const ampelSommerClass = (
  name: 'Pfifferling',
  optimumC: 17.5,
  verhaltenAbove: 0.287,
  guenstigAbove: 0.677,
);

const ampelClasses = <String, AmpelClass>{
  'herbst': ampelHerbstClass,
  'sommer': ampelSommerClass,
};

/// Alle ausgelieferten Klassen, in der Reihenfolge, in der sie bei
/// Gleichstand gewinnen — Herbst zuerst, weil das der Stand war, den die
/// App jahrelang allein gerechnet hat.
const ampelShippedClasses = <AmpelClass>[
  ampelHerbstClass,
  ampelSommerClass,
];

/// Die beste Stufe über ALLE ausgelieferten Klassen — und welche sie
/// trägt.
///
/// **Die Karte kennt keine Art** (Betreiber, 2026-09-12: „Die Pilzampel
/// auf der Karte soll das Maximum für alle Klassen wiedergeben und nicht
/// nur für eine, wie das Herbstfenster."). Sie kann aber jede Klasse
/// rechnen und die beste zeigen; die Aussage lautet dann „für mindestens
/// eine Gruppe wären die Bedingungen günstig".
///
/// **Kein Saison-Tor hier** (dieselbe Entscheidung): Die Saisonkurve
/// hängt an der ART, und die gibt es nur an Fundstellen. Die Fläche sagt
/// deshalb rein etwas über die Bedingungen und nichts über Vorkommen.
///
/// **Bei Gleichstand gewinnt die frühere Klasse, nicht der höhere
/// Score.** Scores verschiedener Klassen sind nicht vergleichbar: Jede
/// Schwelle ist auf ihre eigene Verteilung kalibriert, ein Score von
/// 0,55 heißt im Herbstfenster „günstig" und im Sommerfenster
/// „verhalten". Wer sie gegeneinander stellt, vergleicht Zentimeter mit
/// Grad.
({AmpelLevel level, AmpelClass klass}) ampelBestOf({
  required double rainFactor,
  required double meanC,
}) {
  var best = (
    level: AmpelLevel.unguenstig,
    klass: ampelShippedClasses.first,
  );
  for (final klass in ampelShippedClasses) {
    final level = ampelLevelOf(
        rainFactor * ampelBellOfMean(meanC, optimumC: klass.optimumC),
        klass: klass);
    if (level.index > best.level.index) best = (level: level, klass: klass);
  }
  return best;
}

/// **Nur Arten einer BESTÄTIGTEN Klasse stehen hier.** Hallimasch und
/// Stockschwämmchen haben ein gemessenes Fenster (11,5 °C) und in
/// Stufen den größten Gewinn von allen — aber keinen Hold-out; sie sind
/// nach dem Blick auf die Tabelle ausgewählt worden, also genau in der
/// Lage, in der der Pfifferling vor Österreich stand. Der
/// Austernseitling ebenso. Bis das geprüft ist, gilt für sie, was für
/// jede ungeprüfte Art gilt: lieber grau als erfunden.
const ampelSpeciesClass = <String, String>{
  'Steinpilz': 'herbst',
  'Maronenröhrling': 'herbst',
  'Birkenpilz': 'herbst',
  'Fichtenreizker': 'herbst',
  'Herbsttrompete': 'herbst',
  'Pfifferling': 'sommer',
};

/// Gewichtete Niederschlagskumulation, 0…1.
///
/// `dailyMm[0]` ist der VORTAG, `dailyMm[last]` der älteste Tag —
/// dieselbe Ordnung wie im Werkzeug. Ältere Tage zählen linear
/// schwächer: Was vor vier Wochen fiel, ist teils versickert und
/// verdunstet. Fehlende Tage (`null`) zählen wie im Werkzeug als 0 —
/// ob die Reihe vollständig GENUG ist, entscheidet der Aufrufer,
/// nicht diese Funktion.
double ampelRainFactor(List<double?> dailyMm) {
  if (dailyMm.isEmpty) return 0.0;
  var weighted = 0.0;
  var weights = 0.0;
  final days = math.min(dailyMm.length, ampelRainWindow);
  for (var age = 0; age < days; age++) {
    final weight = 1.0 - age / ampelRainWindow;
    weighted += (dailyMm[age] ?? 0.0) * weight;
    weights += weight;
  }
  if (weights == 0) return 0.0;
  // Auf die Skala „so viel wie bei gleichmäßiger Verteilung" bringen.
  final effective = weighted / weights * ampelRainWindow;
  return math.min(effective / ampelRainSaturationMm, 1.0);
}

/// Die Glocke selbst, aus einem fertigen Mittel — herausgelöst, weil
/// die Kartenfläche sie seit der Höhenkorrektur je ZELLE auswertet
/// (Stationsmittel + Lapse-Verschiebung der Zelle), nicht mehr je
/// Station. Numerisch exakt der Weg von [ampelTemperatureFactor];
/// zwei Formeln wären zwei Antworten auf „passt die Temperatur".
double ampelBellOfMean(double meanC, {required double optimumC}) {
  final z = (meanC - optimumC) / ampelTempSigma;
  return math.exp(-(z * z));
}

/// Glocke um [optimumC] über das Mittel der letzten 20 Tage, 0…1.
/// Fehltage werden übersprungen (wie im Werkzeug); ganz ohne Werte 0.
double ampelTemperatureFactor(List<double?> dailyC,
    {required double optimumC}) {
  var sum = 0.0;
  var count = 0;
  final days = math.min(dailyC.length, ampelTempWindow);
  for (var i = 0; i < days; i++) {
    final c = dailyC[i];
    if (c == null) continue;
    sum += c;
    count++;
  }
  if (count == 0) return 0.0;
  return ampelBellOfMean(sum / count, optimumC: optimumC);
}

/// Der Wetter-Score: Feuchte × Temperatur, 0…1.
///
/// BEWUSST ohne Saisonfaktor: Die Validierung vergleicht Fundtag gegen
/// Tage derselben Saison — der Saisonfaktor kürzt sich dort heraus und
/// ist damit UNGEPRÜFT. Die Anzeige nennt die Saison als eigene
/// Fakten-Zeile daneben, rechnet sie aber nicht in die Stufe ein.
double ampelScore(List<double?> rainDailyMm, List<double?> tempDailyC,
        {required double optimumC}) =>
    ampelRainFactor(rainDailyMm) *
    ampelTemperatureFactor(tempDailyC, optimumC: optimumC);

/// Drei Stufen in Worten — Konzept-Regel „Ehrlichkeit im UI": kein
/// Prozent, keine Scheinpräzision.
enum AmpelLevel { unguenstig, verhalten, guenstig }

/// Die Schwellen sind seit 1.137.0 **gemessen, nicht gesetzt** —
/// `docs/pilzampel-schwellen-messung.md`. Sie stehen nicht mehr als
/// zwei Zahlen für alles hier, sondern in jeder Klasse einzeln, weil
/// dieselbe Zahl unter einem anderen Fenster etwas anderes bedeutet:
/// Der Austernseitling kommt mit 0,5 auf 1,1 % günstige Fundtage, der
/// Steinpilz auf 58,4 %.
///
/// **Zwei Dinge, die man dazu wissen muss.**
///
/// Sie beschreiben die Jahre AB 2019 und altern. Genau das ist der
/// Grund, warum es sie gibt: Die ausgelieferte 0,5 wurde vor 2019 an
/// rund 30 % der Vergleichstage überschritten und seither nur noch an
/// rund 20 % — die Ampel ist im Feld still pessimistischer geworden,
/// ohne dass je eine Zeile geändert wurde. Wer sie anfasst, misst nach
/// (`tool/ampel_validate.py --thresholds`) und schreibt das Datum dazu.
///
/// Und wie oft die Ampel überhaupt „günstig" sagt, ist eine
/// Produktentscheidung, keine Messung. Sie steckt im Quantil (80 %) und
/// lautet seit dem 2026-09-12 „gleich häufig wie bisher", damit die
/// Umstellung die Treffsicherheit ändert und nicht beides auf einmal.
AmpelLevel ampelLevelOf(double score, {required AmpelClass klass}) {
  if (score >= klass.guenstigAbove) return AmpelLevel.guenstig;
  if (score >= klass.verhaltenAbove) return AmpelLevel.verhalten;
  return AmpelLevel.unguenstig;
}

/// Das Wort zur Stufe — die EINE Stelle für die Beschriftung.
String ampelLevelWord(AmpelLevel level) => switch (level) {
      AmpelLevel.unguenstig => 'ungünstig',
      AmpelLevel.verhalten => 'verhalten',
      AmpelLevel.guenstig => 'günstig',
    };

/// Die Klasse zu einer Art — `null` heißt „keine Aussage", also graue
/// Ampel. `null` als [species] ist dagegen die Gilden-Frage („Was ist
/// hier?") und bekommt das Herbstfenster, mit dem auch die Karte
/// rechnet. Synonyme löst wie überall [canonicalSpecies] auf, sonst
/// hinge die Ampel an der Schreibweise.
///
/// **Korrektur am 2026-09-12 zur früheren Begründung.** Hier stand, das
/// Modell sei für Holzbewohner „nicht ungenau, sondern kategorisch
/// falsch". Das ist gemessen widerlegt: Hallimasch und
/// Stockschwämmchen haben in Stufen den GRÖSSTEN Gewinn aller neun
/// Arten (+53,2 und +44,0 pp), sobald sie ihr eigenes Fenster bekommen
/// — sie teilen schlicht nicht das der Mykorrhiza-Arten. Grau bleiben
/// sie aus einem anderen Grund: Ihr Fenster hat keinen Hold-out, und
/// ausgewählt wurden sie, weil sie in einer Tabelle auffielen.
AmpelClass? ampelClassFor(String? species) {
  if (species == null) return ampelHerbstClass;
  final key = ampelSpeciesClass[canonicalSpecies(species)];
  return key == null ? null : ampelClasses[key];
}

/// Darf für [species] überhaupt eine Stufe gezeigt werden?
bool ampelValidatedFor(String? species) => ampelClassFor(species) != null;
