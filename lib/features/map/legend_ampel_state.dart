// Was die Kopfzeile der Ampel in der Legende rechts sagt (#732).
//
// Bis 1.226.3 stand dort `level == null ? 'rechnet …' : Stufe` — und
// `null` hieß dreierlei: wirklich noch am Laden, gar keine Daten (keine
// Wetter-Zustimmung, Fehler, außerhalb) und „keine Aussage" (graue
// Ablesung). Die Legende sagte damit auch dann „rechnet …", wenn nichts
// mehr rechnete, und das für immer.
//
// Rein und ohne Widgets, damit jede Zeile der Zuordnung einzeln prüfbar
// ist; die Legende zeigt nur, was hier herauskommt.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/map_worker.dart';
import '../ampel/ampel_model.dart';
import '../ampel/ampel_providers.dart';

/// Die Zustände der Kopfzeile.
enum LegendAmpelState {
  /// Eine Zutat (Regen, Temperatur, Höhe) lädt noch — oder ihr Auftrag
  /// wurde von einem neueren abgelöst, der gleich antwortet.
  loading,

  /// Keine Wetter-Zustimmung: Ohne sie lädt kein Stapel, und die Ampel
  /// kann nie rechnen. Die Legende bietet sie an.
  needsConsent,

  /// Der Regenverlauf oder die Temperatur ist gescheitert.
  noData,

  /// Gerechnet, aber grau — der Grund steht in der Ablesung.
  noStatement,

  /// Eine Stufe.
  level,
}

/// Ordnet die Eingänge der Kopfzeile einem [LegendAmpelState] zu.
///
/// Reihenfolge ist Absicht: Ohne Zustimmung antwortet der Regenverlauf
/// sofort mit `null` (leerer Stapel), die Ablesung wäre also grau mit
/// „keine Regendaten" — richtig ist aber „du hast nichts geladen".
/// Laden kommt vor Fehler, weil ein abgelöster Auftrag als Fehler
/// ankommt ([MapWorkerSuperseded]) und doch nur heißt „gleich".
LegendAmpelState legendAmpelStateOf({
  required bool consent,
  required AsyncValue<Object?> course,
  required AsyncValue<Object?> temperature,
  required AsyncValue<Object?> height,
  required AmpelReading? reading,
}) {
  if (!consent) return LegendAmpelState.needsConsent;
  bool pending(AsyncValue<Object?> value) =>
      value.isLoading || value.error is MapWorkerSuperseded;
  if (pending(course) || pending(temperature) || pending(height)) {
    return LegendAmpelState.loading;
  }
  // Die Höhe darf fehlen (außerhalb des Gitters rechnet die Ampel
  // unkorrigiert), ein Fehler dort ist also kein „keine Daten".
  if (course.hasError || temperature.hasError) return LegendAmpelState.noData;
  if (reading == null) return LegendAmpelState.loading;
  if (reading.level == null) return LegendAmpelState.noStatement;
  return LegendAmpelState.level;
}

/// Das Wort rechts in der Kopfzeile. [level] ist nur bei
/// [LegendAmpelState.level] gesetzt.
String legendAmpelWord(LegendAmpelState state, AmpelLevel? level) =>
    switch (state) {
      LegendAmpelState.loading => 'rechnet …',
      LegendAmpelState.needsConsent => 'Wetter laden',
      LegendAmpelState.noData => 'keine Daten',
      LegendAmpelState.noStatement => 'keine Aussage',
      LegendAmpelState.level => ampelLevelWord(level!),
    };
