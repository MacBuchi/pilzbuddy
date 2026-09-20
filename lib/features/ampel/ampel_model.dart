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

/// Der Boden unter dem Regenfaktor vor dem Logarithmus einer
/// Logit-Klasse — wie `REGEN_BODEN` in `tool/ampel_logit_klasse.py`: ein
/// trockenes Fenster ist sehr ungünstig, nicht minus unendlich.
const ampelLogitRainFloor = 1e-3;

/// Das Feuchtefenster einer Logit-Klasse: 26 Tage, wie der Regen.
const ampelMoistureWindow = 26;

/// Der zweite Rechenkern der Ampel (seit 2026-09-20,
/// `docs/pilzampel-holz-winter-plan.md`): ein bedingtes Logit mit fünf
/// Konstanten über `ln F`, `T`, `T²`, `M` und `M·T` — `F` der Regenfaktor,
/// `T` das 20-Tage-Mittel in °C, `M` die Bodenfeuchte der nächsten
/// DWD-Station in % nutzbarer Feldkapazität, 26-Tage-Mittel.
///
/// **Warum kein weiteres Fenster:** Für Holz- und Winterpilze verliert
/// die Glocke bei jedem Optimum gesichert gegen dieses Logit, weil „je
/// kälter, desto besser" mit einer Glocke nicht darstellbar ist. Spiegel
/// von `tool/ampel_logit_klasse.py`, Zahl für Zahl; die Schwellen einer
/// Logit-Klasse liegen auf der Skala von `s`, nicht auf 0…1.
class AmpelLogit {
  const AmpelLogit({
    required this.rain,
    required this.temp,
    required this.temp2,
    required this.moisture,
    required this.moistureTemp,
  });

  final double rain;
  final double temp;
  final double temp2;
  final double moisture;
  final double moistureTemp;

  /// Die lineare Vorhersage `s` aus fertigen Zutaten.
  double score({
    required double rainFactor,
    required double meanC,
    required double moistureMean,
  }) {
    final logRain = math.log(math.max(rainFactor, ampelLogitRainFloor));
    return rain * logRain +
        temp * meanC +
        temp2 * meanC * meanC +
        moisture * moistureMean +
        moistureTemp * moistureMean * meanC;
  }
}

/// Das 26-Tage-Mittel der Bodenfeuchte aus der Stationsreihe (ältester
/// Tag zuerst) — `null`, wenn die Reihe kürzer ist oder im Fenster eine
/// Lücke hat. Kein Mittel aus halben Fenstern: Eine erfundene Feuchte
/// wäre eine erfundene Beobachtung (dieselbe Regel wie `feuchte_mittel`
/// im Werkzeug).
double? ampelMoistureMean(List<double?> bfglOldestFirst) {
  if (bfglOldestFirst.length < ampelMoistureWindow) return null;
  final window =
      bfglOldestFirst.sublist(bfglOldestFirst.length - ampelMoistureWindow);
  var sum = 0.0;
  for (final value in window) {
    if (value == null) return null;
    sum += value;
  }
  return sum / ampelMoistureWindow;
}

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

  /// Das Fenster der Glocke — `null` bei einer Logit-Klasse, die keins
  /// hat. (Kein `double.nan`: Ein Record mit NaN wäre sich selbst nicht
  /// gleich, und `ampelClassKeyOf` fände die Klasse nie wieder.)
  double? optimumC,
  double verhaltenAbove,
  double guenstigAbove,

  /// `null` heißt Glocke; sonst rechnet die Klasse mit diesem Logit und
  /// braucht dafür die Bodenfeuchte der nächsten Station — ohne sie
  /// bleibt sie grau, nirgends wird ein Ersatzwert eingesetzt.
  AmpelLogit? logit,
});

/// **Warum die Klasse die Einheit ist und nicht die Art**
/// (Betreiberentscheidung 2026-09-12): Arten mit demselben Fenster
/// bekommen Schwellen, deren Vertrauensbereiche sich satt überlappen —
/// Steinpilz [0,148, 0,238] gegen Herbsttrompete [0,089, 0,284]. Je Art
/// ausgeliefert wäre das Rauschen in Konstantenform, und am Ende
/// stünden 110 Einträge da, von denen keiner mehr prüfbar ist. Zwischen
/// den Fenstern liegen dagegen Welten (0,512 gegen 0,038 beim
/// Austernseitling).
///
/// **Die Schwellen sind am 2026-09-19 neu gesetzt worden** (Auftrag 3 A,
/// `docs/pilzampel-schwellen-designb-p1.md`) — vorher 0,187 und 0,512.
/// Geändert hat sich nicht das Modell, sondern die Tage, gegen die
/// gemessen wird: Die alten Zahlen waren an Vergleichstagen 26 bis 45
/// Tage NEBEN dem Fund geeicht, also zum Teil außerhalb der Saison, wo
/// die Glocke ohnehin niedrig steht. Gegen Tage am selben Ort zur
/// selben Jahreszeit anderer Jahre gemessen, stand die Ampel dadurch an
/// 35 bis 38 Prozent der Saisontage auf „günstig" — gedacht war etwa
/// jeder fünfte.
const ampelHerbstClass = (
  name: 'Steinpilz & Co.',
  optimumC: ampelOptimumC,
  // Seit 2026-09-20 mit vier Mitgliedern gemessen (die Herbsttrompete
  // ist zu „Herbsttrompete & Co." gezogen): 0,393 / 0,747 statt 0,389 /
  // 0,742 — innerhalb des Bandes, aber die Regel heißt: wer die Klasse
  // ändert, misst neu und schreibt das Datum dazu.
  verhaltenAbove: 0.393,
  guenstigAbove: 0.747,
  logit: null,
);

/// Der Pfifferling ist ein Sommerfrüchter — Gipfel im Juli, nicht im
/// September. Sein eigenes Fenster hat als einziges den **geografischen
/// Hold-out** bestanden: in Deutschland angepasst, in AT und CH geprüft,
/// AUC 0,584 → 0,689 (+0,104 [+0,055, +0,150]) bei abstandsgleicher
/// Kontrolle 0,510 (`docs/pilzampel-artenfenster-holdout.md`). Ohne
/// diesen Nachweis stünde er hier nicht: Gemessen wurde er, weil er in
/// einer Tabelle auffiel, und das allein ist kein Befund.
///
/// **Seit dem 2026-09-20 steht das Fenster auf 14,5 °C — eine
/// Betreiberentscheidung, kein Befund.** Das Labor (Design B, DE + AT/CH)
/// sah das Vorzeichen fünfmal von fünf positiv, aber nie gesichert:
/// DE-Test +0,035 [−0,012, +0,079], AT/CH +0,066 [+0,004, +0,135], und
/// die AUC auf dem DE-Test ging leicht zurück
/// (`docs/pilzampel-holz-winter-plan.md`, §1B). „Kleine Schritte" — und
/// deshalb steht der Pfifferling seither auf `vorlaeufig`: Die Klasse
/// hat ihren bestätigten Hold-out mit der Änderung verlassen. Die
/// Schwellen sind unter dem neuen Fenster neu gemessen (Design B, P1,
/// `docs/pilzampel-schwellen-designb-p1.md`; unter 17,5 °C waren es
/// 0,385 und 0,729).
const ampelSommerClass = (
  name: 'Pfifferling',
  optimumC: 14.5,
  verhaltenAbove: 0.348,
  guenstigAbove: 0.669,
  logit: null,
);

/// **Austernseitling & Co. — die Holz- und Winterpilze**, seit 2026-09-20
/// der erste Logit-Kern. Belegt auf drei Hürden (Labor 15/16/18, Design B):
/// DE-Testblöcke +0,402 [+0,255, +0,596], AT/CH-Testblöcke +0,206
/// [+0,081, +0,352], gegen die Klimatologie +0,020 [+0,000, +0,038] —
/// jeweils Log-Likelihood je Stratum gegen die 13-°C-Glocke. Der große
/// Gewinn gegenüber heute entsteht, weil die Glocke Winterarten
/// kategorisch falsch bewertet; der Gewinn gegenüber der reinen
/// Saisonkurve ist klein. Konstanten aus `18-testteil-dach.md` (Fit auf
/// allen DACH-Erkundungsstrata), Schwellen Design B auf P1
/// (`docs/pilzampel-logit-schwellen.md`).
const ampelHolzWinterClass = (
  name: 'Austernseitling & Co.',
  optimumC: null,
  verhaltenAbove: 0.454,
  guenstigAbove: 0.606,
  logit: AmpelLogit(
    rain: 0.1882,
    temp: 0.1321,
    temp2: -0.00446,
    moisture: 0.00220,
    moistureTemp: -0.000442,
  ),
);

/// **Herbsttrompete & Co. — die Leistlinge und der Stoppelpilz**
/// (Cantharellales; der Pfifferling gehört botanisch dazu, in den Daten
/// aber zu sich selbst). Auf den DE-Testblöcken angenommen (+0,417
/// [+0,131, +0,769]), **reist aber nicht** nach AT/CH (+0,047 [−0,058,
/// +0,129]) — dort liegt die nächste Bodenfeuchtestation ohnehin jenseits
/// der 100 km, die Klasse bleibt dort grau. Nur für Deutschland belegt;
/// aufgenommen, weil die App vor allem dort läuft (Betreiber 2026-09-20).
/// Die Herbsttrompete ist dafür aus „Steinpilz & Co." ausgezogen, wo sie
/// gegen dieses Logit gesichert verlor.
const ampelCantharellalesClass = (
  name: 'Herbsttrompete & Co.',
  optimumC: null,
  verhaltenAbove: 2.191,
  guenstigAbove: 2.952,
  logit: AmpelLogit(
    rain: 0.1039,
    temp: 0.1547,
    temp2: -0.01399,
    moisture: 0.00333,
    moistureTemp: 0.002237,
  ),
);

const ampelClasses = <String, AmpelClass>{
  'herbst': ampelHerbstClass,
  'sommer': ampelSommerClass,
  'holz_winter': ampelHolzWinterClass,
  'cantharellales': ampelCantharellalesClass,
};

/// Alle ausgelieferten Klassen, in der Reihenfolge, in der sie bei
/// Gleichstand gewinnen — Herbst zuerst, weil das der Stand war, den die
/// App jahrelang allein gerechnet hat.
const ampelShippedClasses = <AmpelClass>[
  ampelHerbstClass,
  ampelSommerClass,
  ampelHolzWinterClass,
  ampelCantharellalesClass,
];

/// Die gewählten Klassen, in Auslieferungsreihenfolge — die Übersetzung
/// von der Nutzerauswahl (Schlüssel aus [ampelClasses]) in das, womit
/// gerechnet wird.
///
/// **Leer heißt ALLE**, wie bei der Artenauswahl des Filters: Ein
/// Filter, der nichts durchlässt, wäre auf der Karte nicht von „keine
/// Daten" zu unterscheiden. Die Reihenfolge kommt aus
/// [ampelShippedClasses] und nicht aus der Auswahl — an ihr hängt die
/// Gleichstandsregel in [ampelBestOf].
///
/// Nennt die Auswahl nur Schlüssel, die es nicht (mehr) gibt, kommen
/// ebenfalls alle zurück: Eine Auswahl, die auf nichts zeigt, ist keine
/// Aussage, sondern eine Lücke — und die Karte antwortet dann wie
/// vorher.
List<AmpelClass> ampelClassesOf(Set<String> keys) {
  if (keys.isEmpty) return ampelShippedClasses;
  final chosen = [
    for (final entry in ampelClasses.entries)
      if (keys.contains(entry.key)) entry.value,
  ];
  return chosen.isEmpty ? ampelShippedClasses : chosen;
}

/// Der Schlüssel einer Klasse — für die Auswahl, die in Schlüsseln
/// rechnet. `null` kann hier nicht herauskommen, solange die Klasse aus
/// [ampelClasses] stammt.
String? ampelClassKeyOf(AmpelClass klass) {
  for (final entry in ampelClasses.entries) {
    if (entry.value == klass) return entry.key;
  }
  return null;
}

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
/// **[classes] ist PFLICHT und kein Vorgabewert.** Seit 1.142.0 kann
/// der Nutzer Klassen abwählen (Chips im Filter), und die Auswahl gilt
/// auch für die Fläche. Ein Standard „alle" wäre an jeder neuen
/// Aufrufstelle die stille Antwort „zeig mehr, als der Chip sagt" —
/// genau die Sorte Fehler, vor der #154 warnt, nur in die andere
/// Richtung. Wer alle meint, schreibt [ampelShippedClasses] hin.
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
  required List<AmpelClass> classes,
  double? moistureMean,
}) {
  var best = (
    level: AmpelLevel.unguenstig,
    klass: classes.first,
  );
  for (final klass in classes) {
    final score = ampelScoreFor(klass,
        rainFactor: rainFactor, meanC: meanC, moistureMean: moistureMean);
    // Eine Logit-Klasse ohne Bodenfeuchte sagt nichts — sie zählt hier
    // nicht mit, statt mit einem Ersatzwert zu rechnen.
    if (score == null) continue;
    final level = ampelLevelOf(score, klass: klass);
    if (level.index > best.level.index) best = (level: level, klass: klass);
  }
  return best;
}

/// Der Score EINER Klasse aus fertigen Zutaten — Glocke oder Logit.
/// `null`, wenn eine Logit-Klasse ohne Bodenfeuchte gefragt wird.
double? ampelScoreFor(
  AmpelClass klass, {
  required double rainFactor,
  required double meanC,
  double? moistureMean,
}) {
  final logit = klass.logit;
  if (logit == null) {
    return rainFactor * ampelBellOfMean(meanC, optimumC: klass.optimumC!);
  }
  if (moistureMean == null) return null;
  return logit.score(
      rainFactor: rainFactor, meanC: meanC, moistureMean: moistureMean);
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
  'Pfifferling': 'sommer',
  // Seit 2026-09-20 die beiden Logit-Klassen (`docs/pilzampel-holz-winter-plan.md`).
  'Austernseitling': 'holz_winter',
  'Judasohr': 'holz_winter',
  'Krause Glucke': 'holz_winter',
  'Leberpilz': 'holz_winter',
  'Lungenseitling': 'holz_winter',
  'Rehbrauner Dachpilz': 'holz_winter',
  'Samtfußrübling': 'holz_winter',
  'Schwefelporling': 'holz_winter',
  // Die Herbsttrompete stand bis 1.150.0 in `herbst`.
  'Herbsttrompete': 'cantharellales',
  'Semmelstoppelpilz': 'cantharellales',
  'Trompetenpfifferling': 'cantharellales',
};

/// Wie gut die Ampel für eine Art belegt ist.
///
/// **Die Stufe begrenzt die Behauptung, sie schafft sie nicht ab**
/// (Auftrag 2, Abschnitt 5). Keine Art verliert ihre Ampel, weil sie
/// hier unten steht.
///
/// Vergeben nach den vier Bedingungen aus N1 des Nachtrags
/// (`docs/pilzampel-kontrolldesign.md`): Jahres-Bootstrap in Design B
/// ohne die 0,50, Abstand zur artgematchten Referenz mit
/// Vertrauensbereich ohne die Null, ≥ 150 Funde, Kontrollen innerhalb
/// 2 SE. Gemessen wird in **Design B** — gleicher Ort, gleiches Datum
/// in anderen Jahren —, weil sich dort die Jahreszeit vollständig
/// herauskürzt.
///
/// **Es gibt nur zwei Werte, und das ist kein Versehen.** „Keine
/// Aussage" bräuchte eine Art, die eine Ampel zeigt, obwohl nichts
/// gemessen ist — und genau die gibt es nicht: [ampelSpeciesClass] ist
/// das Tor davor. Wer je eine dritte Klasse ausliefert, braucht dann
/// auch den dritten Wert.
enum AmpelEvidence {
  /// Alle vier Bedingungen erfüllt.
  belegt,

  /// Der Effekt ist da, aber eine Bedingung wackelt.
  vorlaeufig,
}

/// Stand 2026-09-18, `docs/pilzampel-kontrolldesign.md`.
///
/// Die Herbsttrompete steht auf `vorlaeufig`, weil sie mit 147 Funden
/// unter der 150er-Grenze liegt und ihre Spiegel-Kontrolle in Design A
/// bei 0,395 außerhalb der Toleranz steht. Ihre Zahlen sind die besten
/// der Tabelle — nur trägt eine dünne Zahl kein Urteil.
///
/// **Diese Liste MUSS deckungsgleich mit [ampelSpeciesClass] sein.**
/// Eine Art mit Klasse und ohne Stufe zeigte eine Ampel ohne Auskunft
/// darüber, was sie wert ist; eine Stufe ohne Klasse wäre eine Aussage
/// über etwas, das nie erscheint. `test/ampel_evidence_test.dart` hält
/// beide Richtungen zusammen.
const ampelEvidenceBySpecies = <String, AmpelEvidence>{
  'Steinpilz': AmpelEvidence.belegt,
  'Maronenröhrling': AmpelEvidence.belegt,
  'Birkenpilz': AmpelEvidence.belegt,
  'Fichtenreizker': AmpelEvidence.belegt,
  // Seit dem 2026-09-20: Fenster auf 14,5 °C gesetzt, ohne Hold-out
  // dafür — siehe [ampelSommerClass].
  'Pfifferling': AmpelEvidence.vorlaeufig,
  // Austernseitling & Co. — je Art auf dem Testteil (Labor 18, DE + AT/CH):
  // ▲ mit Band ohne Null heißt belegt, Band mit Null heißt vorläufig.
  'Samtfußrübling': AmpelEvidence.belegt,
  'Judasohr': AmpelEvidence.belegt,
  'Austernseitling': AmpelEvidence.belegt,
  'Schwefelporling': AmpelEvidence.belegt,
  'Lungenseitling': AmpelEvidence.belegt,
  'Leberpilz': AmpelEvidence.belegt,
  'Rehbrauner Dachpilz': AmpelEvidence.vorlaeufig,
  'Krause Glucke': AmpelEvidence.vorlaeufig,
  // Herbsttrompete & Co. — nur DE-Test (Labor 15): Trompetenpfifferling
  // +0,206 [+0,048, +0,334] belegt; Semmelstoppelpilz +0,149 [+0,000,
  // +0,261] am Rand, Herbsttrompete mit 147 Funden unter der Grenze —
  // beide vorläufig.
  'Herbsttrompete': AmpelEvidence.vorlaeufig,
  'Semmelstoppelpilz': AmpelEvidence.vorlaeufig,
  'Trompetenpfifferling': AmpelEvidence.belegt,
};

/// Die Stufe einer Art — `null`, wo es keine Ampel gibt.
AmpelEvidence? ampelEvidenceFor(String? species) => species == null
    ? null
    : ampelEvidenceBySpecies[canonicalSpecies(species)];

/// Der Satz dazu, in Alltagssprache.
///
/// **Keine Warnung, eine Auskunft** (N7): Fünf Warnungen auf sechs
/// Arten lesen sich wie „kaputt", und dann wird auch der belastbare
/// Teil abgewertet. Deshalb steht bei jeder Art dasselbe Feld, und nur
/// sein Inhalt unterscheidet sich.
String ampelEvidenceWord(AmpelEvidence evidence) => switch (evidence) {
      AmpelEvidence.belegt => 'gut belegt',
      AmpelEvidence.vorlaeufig => 'unsichere Datenlage',
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

/// Wie die Legende das Fenster einer Klasse nennt: die Zahl bei der
/// Glocke, die Zutaten beim Logit.
String ampelClassWindowWord(AmpelClass klass) => klass.optimumC == null
    ? 'Regen, Temperatur und Bodenfeuchte'
    : '${klass.optimumC!.toStringAsFixed(1).replaceAll('.', ',')} °C';

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
