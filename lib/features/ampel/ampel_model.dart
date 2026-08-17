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
// Rein Dart ohne Flutter, wie `forest_grid.dart` und aus demselben
// Grund: Die Rechnung soll ohne App testbar sein.
import 'dart:math' as math;

import '../../core/mushroom_species.dart' show canonicalSpecies;

/// Fenster und Konstanten — identisch zum Validierungswerkzeug.
const ampelRainWindow = 26;
const ampelTempWindow = 20;
const ampelOptimumC = 13.0;
const ampelTempSigma = 5.0;
const ampelRainSaturationMm = 87.0;

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
double ampelBellOfMean(double meanC) {
  final z = (meanC - ampelOptimumC) / ampelTempSigma;
  return math.exp(-(z * z));
}

/// Glocke um 13 °C über das Mittel der letzten 20 Tage, 0…1.
/// Fehltage werden übersprungen (wie im Werkzeug); ganz ohne Werte 0.
double ampelTemperatureFactor(List<double?> dailyC) {
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
  return ampelBellOfMean(sum / count);
}

/// Der Wetter-Score: Feuchte × Temperatur, 0…1.
///
/// BEWUSST ohne Saisonfaktor: Die Validierung vergleicht Fundtag gegen
/// Tage derselben Saison — der Saisonfaktor kürzt sich dort heraus und
/// ist damit UNGEPRÜFT. Die Anzeige nennt die Saison als eigene
/// Fakten-Zeile daneben, rechnet sie aber nicht in die Stufe ein.
double ampelScore(List<double?> rainDailyMm, List<double?> tempDailyC) =>
    ampelRainFactor(rainDailyMm) * ampelTemperatureFactor(tempDailyC);

/// Drei Stufen in Worten — Konzept-Regel „Ehrlichkeit im UI": kein
/// Prozent, keine Scheinpräzision.
enum AmpelLevel { unguenstig, verhalten, guenstig }

/// Die Schwellen sind GESETZT, nicht gemessen — Startwerte für die
/// Vorschau, Kalibrierung erst nach bestandener Validierung (dann aus
/// der Score-Verteilung an Fundtagen). Genau deshalb Konstanten an
/// einer Stelle.
const ampelVerhaltenAbove = 0.2;
const ampelGuenstigAbove = 0.5;

AmpelLevel ampelLevelOf(double score) {
  if (score >= ampelGuenstigAbove) return AmpelLevel.guenstig;
  if (score >= ampelVerhaltenAbove) return AmpelLevel.verhalten;
  return AmpelLevel.unguenstig;
}

/// Das Wort zur Stufe — die EINE Stelle für die Beschriftung.
String ampelLevelWord(AmpelLevel level) => switch (level) {
      AmpelLevel.unguenstig => 'ungünstig',
      AmpelLevel.verhalten => 'verhalten',
      AmpelLevel.guenstig => 'günstig',
    };

/// Die Arten, für die das Modell überhaupt eine Aussage machen darf —
/// exakt die sechs Mykorrhiza-Herbstarten, an denen es validiert wird
/// (`MYCORRHIZAL` im Werkzeug). Alles andere bekommt eine GRAUE Ampel:
/// „Eine Ampel, die für den Hallimasch dasselbe rechnet wie für den
/// Steinpilz, ist nicht ungenau, sondern kategorisch falsch"
/// (Konzept, Artenklassifikation). Lieber grau als erfunden.
const ampelValidatedSpecies = {
  'Steinpilz',
  'Maronenröhrling',
  'Pfifferling',
  'Birkenpilz',
  'Fichtenreizker',
  'Herbsttrompete',
};

/// Darf für [species] eine Stufe gezeigt werden? `null` (keine Art —
/// „Was ist hier?") gilt als Gilden-Frage „Steinpilz & Co." und ist
/// erlaubt; Synonyme werden wie überall über [canonicalSpecies]
/// aufgelöst.
bool ampelValidatedFor(String? species) {
  if (species == null) return true;
  return ampelValidatedSpecies.contains(canonicalSpecies(species));
}
