// Achsen-Arithmetik, geteilt zwischen der Jahresstatistik im Profil und
// dem Wetterdiagramm am Spot. Hierher gezogen (aus profile_screen.dart),
// damit das Spot-Blatt keinen ganzen Screen importieren muss.

/// Höchstens so viele Beschriftungen auf einer Y-Achse.
const _maxYAxisLabels = 5;

/// Der kleinste runde Schritt (1, 2, 5, 10, 20, 50, …), der mindestens
/// [target] groß ist. Unter 1 wird nicht geteilt: Funde sind Stückzahlen,
/// Millimeter und Grad ganzzahlig genug für diese Diagramme.
double _roundStep(double target) {
  if (target <= 1) return 1;
  var magnitude = 1.0;
  while (magnitude * 10 < target) {
    magnitude *= 10;
  }
  for (final factor in const [1, 2, 5]) {
    final step = magnitude * factor;
    if (step >= target) return step;
  }
  return magnitude * 10;
}

/// Achsenschritt für [maxY], der auf einer runden Zahl landet und
/// höchstens [_maxYAxisLabels] Beschriftungen erzeugt.
///
/// Vorher stand hier fest `interval: 1`: bei 50 Funden im besten Jahr wurde
/// jede einzelne Zahl beschriftet, die Achse war zugelaufen (Issue #97).
double yAxisStep(double maxY) => _roundStep(maxY / _maxYAxisLabels);

/// Gehört [value] auf die Achse — also auf ein Vielfaches von [step]?
///
/// fl_chart beschriftet zusätzlich zur Schrittweite die Achsenspitze. Bei
/// maxY = 8,4 und Schritt 2 stünde dort ein zweites „8" wenige Pixel über dem
/// echten — im Store-Screenshot sah das aus wie ein Druckfehler.
bool showsYAxisLabel(double value, double step) {
  final steps = value / step;
  return (steps - steps.round()).abs() < 0.001;
}

/// Die °C-Achse: gerundete Grenzen und ein runder Schritt um [low]..[high].
///
/// Anders als [yAxisStep] beginnt sie nicht bei null — und sie muss
/// NEGATIVE Werte können, denn Frost ist genau die Auskunft, für die es
/// die Temperaturlinien gibt. Die Grenzen sind Vielfache des Schritts,
/// damit die Beschriftungen auf runden Zahlen liegen; gezielt wird auf
/// Spanne/3, weil das Aufrunden der Grenzen bis zu zwei Beschriftungen
/// dazulegt — mehr als fünf werden es so nie.
({double low, double high, double step}) temperatureAxis(
    double low, double high) {
  final step = _roundStep((high - low) / 3);
  var axisLow = (low / step).floorToDouble() * step;
  var axisHigh = (high / step).ceilToDouble() * step;
  if (axisLow == axisHigh) {
    // Alle Werte gleich (ein einziger Messtag): eine Achse ohne Spanne
    // kann nicht teilen — einen Schritt in beide Richtungen öffnen.
    axisLow -= step;
    axisHigh += step;
  }
  return (low: axisLow, high: axisHigh, step: step);
}
