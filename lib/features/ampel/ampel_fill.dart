// Die Pilzwetter-Rechnung für die Karte (Frage b der Ampel-Vorschau,
// 2026-08-09): „Wo in meiner Umgebung ist es zurzeit besonders gut?" —
// gerechnet aus denselben lokalen Gittern wie die Spot-Ampel. KEINE
// fremden Spots, keine Koordinate verlässt das Gerät.
//
// **Die Ampel färbt nur noch WALD** (Betreiber, 2026-08-10: „ich würde
// die Pilzampel auch nur mit dem Wald überlagern, es gibt keinen Grund,
// warum man andere Bereiche damit einfärben sollte"). Bis 1.75.0 lag sie
// als eigene Fläche über allem — auch über Feldern, Städten und Seen, wo
// die Aussage niemanden interessiert. Seit 1.76.0 gibt es nur noch die
// Kombi-Ebene: Der Wabenzeichner der Waldfläche
// (`forestAmpelFillPng`) lässt die Waben leuchten, wo das Wetter stimmt.
//
// Übrig bleibt hier die RECHNUNG — die Stufe je Zelle, ohne Farbe. Genau
// das ist auch das, was der Betreiber als Zukunftsbild beschrieben hat:
// dieselben Sechsecke, auf Array-Ebene gefärbt, ein Rendern statt zwei
// Ebenen übereinander.
import 'dart:typed_data';

import '../../core/geo.dart' show distanceKm;
import '../../data/rain_grid_repository.dart' show RainStackData;
import '../map/elevation_grid.dart';
import '../map/rain_grid.dart';
import '../map/spot_weather.dart';
import 'ampel_model.dart';
import 'ampel_providers.dart' show ampelMinRainDays, ampelMinTempDays;

/// Deckkraft wie die Regenfläche — dieselbe Messung, dieselbe
/// Obergrenze: Die Karte darunter muss lesbar bleiben.
const ampelFillAlpha = 140;

/// Kantenlänge der Kandidaten-Kacheln in Zellen (~16 km).
///
/// **Keine Auflösungsgrenze.** Die Station wird je ZELLE gesucht, nach
/// derselben Regel wie im Spot-Blatt (`WeatherTable.nearestAir`); die
/// Kachel ist nur der Vorfilter, der das bezahlbar macht: Für sie steht
/// vorab fest, welche Stationen für irgendeine ihrer Zellen überhaupt
/// die nächste sein können, und die Zelle prüft dann diese Handvoll
/// statt aller ~465. Ohne den Vorfilter wäre es eine Viertelmilliarde
/// Distanzen.
///
/// Gemessen am echten Maßstab (800 × 940 Zellen, 465 Stationen, Debug-VM
/// 2026-08-11): 398 ms gegen 371 ms mit einer einzigen Station — die
/// Stationswahl je Zelle kostet also ~27 ms, während die 26
/// Gzip-Entpackungen des Regenstapels den Rest ausmachen.
///
/// Bis 1.79.0 galt EIN Wert je Kachel, gesucht von deren Mittelpunkt
/// aus. Das malte Rechtecke, die dem Text im Blatt widersprachen: Am
/// gemeldeten Punkt bei Garmisch lag die Kachelmitte 8 km entfernt und
/// griff zu einer 264 m höher gelegenen Station — 0,300 statt 0,123,
/// also „verhalten" auf der Karte und „ungünstig" im Blatt (#279).
const ampelTempBlockCells = 16;

/// Sicherheitszuschlag auf die Kandidaten-Schranke, in km.
///
/// [distanceKm] ist äquirektangulär: Der cos-Faktor der Mittelbreite
/// fällt minimal anders aus, je nachdem ob von der Kachelmitte oder von
/// der Zelle gemessen wird. Ein Kilometer deckt das mit großem Abstand —
/// und `ampel_fill_test.dart` beweist die Schranke gegen die rohe Suche,
/// statt sie zu behaupten.
const _candidateMarginKm = 1.0;

/// Das Ergebnis: PNG plus die Grenzen SEINES Gitters und der jüngste
/// Tag (er wird zum Dateinamen — ein neuer Stand braucht eine neue
/// URL, die MapLibre-Strecke ist idempotent darauf).
class AmpelFill {
  const AmpelFill({
    required this.png,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.newest,
  });

  final Uint8List png;
  final double west;
  final double east;
  final double north;
  final double south;
  final DateTime newest;
}

/// Dasselbe Ergebnis eine Stufe früher: die STUFE je Zelle, noch ohne
/// Farbe. Zwei Kunden — die Fläche oben und die Kombi-Ebene „Wald +
/// Pilzwetter" (dort fragt jede Waldwabe ihren Mittelpunkt ab).
///
/// `null` unter denselben Bedingungen wie die Fläche: kein lückenloses
/// 26-Tage-Fenster, keine Stationstabelle.
/// Die Höhenkorrektur passiert NICHT mehr hier: Seit dem Feldbericht
/// aus Berchtesgaden (2026-08-17) trägt das Gitter je Zelle die
/// ZUTATEN (Regenfaktor, Stationsmittel, Stationshöhe), und erst der
/// Abnehmer wertet die Glocke mit SEINER Höhe aus — jede Waldwabe mit
/// ihrer eigenen ([AmpelLevelGrid.levelAt]). Eine 1-km-Regenzelle kann
/// in den Alpen 500 Höhenmeter überspannen; eine je Zelle fertig
/// gerechnete Stufe konnte dort der Punkt-Ablesung des Blatts nie
/// überall zustimmen, egal wie sie korrigiert war.
AmpelLevelGrid? ampelLevelsFrom(RainStackData stack, WeatherTable? table) {
  final info = stack.info;
  final width = info.width;
  final height = info.height;

  // Die 26 Kalendertage bis zum jüngsten, lückenlos — Index == Alter,
  // exakt die Ordnung, die auch `ampelReadingFrom` ans Modell gibt.
  final byDate = <int, ({DateTime date, List<int> gzipped})>{};
  DateTime? newest;
  for (final day in stack.days) {
    if (newest == null || day.date.isAfter(newest)) newest = day.date;
  }
  if (newest == null) return null;
  for (final day in stack.days) {
    final age = newest.difference(day.date).inDays;
    if (age >= 0 && age < ampelRainWindow) byDate[age] = day;
  }
  if (byDate.length < ampelRainWindow) return null;

  // Regen: gewichtete Kumulation je Zelle, ein Tag nach dem anderen im
  // Speicher (die Lehre des Stapels: alle auf einmal wären ~10 MB roh).
  final weighted = Float32List(width * height);
  final known = Uint8List(width * height);
  var weightsTotal = 0.0;
  for (var age = 0; age < ampelRainWindow; age++) {
    final weight = 1.0 - age / ampelRainWindow;
    weightsTotal += weight;
    final RainGrid grid;
    try {
      grid = RainGrid.decode(
        byDate[age]!.gzipped,
        width: width,
        height: height,
        west: info.west,
        east: info.east,
        north: info.north,
        south: info.south,
        measured: byDate[age]!.date,
      );
    } catch (_) {
      // Ein kaputter Tag macht die Ebene unehrlich — weg damit, wie
      // bei der lückigen Reihe.
      return null;
    }
    for (var i = 0; i < width * height; i++) {
      final mm = grid.values[i];
      if (mm == rainNoData) continue;
      weighted[i] += mm * weight;
      known[i]++;
    }
  }

  // Temperatur: Faktor je Station einmal — und zwar für JEDE antretende
  // Station, nicht nur für die mit genug Tagen. Wer antritt, entscheidet
  // `WeatherStation.competes`; wer auch antworten kann, steht getrennt
  // daneben. Genau so hält es das Spot-Blatt: Es nimmt die nächste
  // antretende Station und wird GRAU, wenn deren Reihe zu lückig ist,
  // statt zur übernächsten zu greifen (#279).
  final stations = table?.air ?? const <AirStation>[];
  final stationLat = Float64List(stations.length);
  final stationLon = Float64List(stations.length);
  // Seit der Höhenkorrektur je Station das MITTEL statt des fertigen
  // Faktors: Die Glocke hängt jetzt von der Zellhöhe ab und wird je
  // Zelle ausgewertet (`ampelBellOfMean`) — mit derselben Formel wie
  // im Modell, nicht mit einer zweiten.
  final stationMean = Float64List(stations.length);
  final stationHeight = Int32List(stations.length);
  final stationAnswers = Uint8List(stations.length);
  final competing = <int>[];
  for (var s = 0; s < stations.length; s++) {
    final station = stations[s];
    if (!station.competes) continue;
    final maxs = station.max;
    final mins = station.min;
    final temps = <double?>[
      for (var i = maxs.length - 1; i >= 0; i--)
        (maxs[i] != null && mins[i] != null)
            ? (maxs[i]! + mins[i]!) / 2
            : null,
    ];
    final window = temps.take(ampelTempWindow).whereType<double>().toList();
    stationLat[s] = station.lat;
    stationLon[s] = station.lon;
    // Dasselbe Mittel, das [ampelTemperatureFactor] intern bildet —
    // nur noch nicht durch die Glocke geschickt (das passiert je
    // Zelle, nach der Höhenverschiebung).
    stationMean[s] = window.isEmpty
        ? 0
        : window.reduce((a, b) => a + b) / window.length;
    stationHeight[s] = station.height;
    stationAnswers[s] = window.length >= ampelMinTempDays ? 1 : 0;
    competing.add(s);
  }
  if (competing.isEmpty) return null;

  final blocksX = (width + ampelTempBlockCells - 1) ~/ ampelTempBlockCells;
  final blocksY = (height + ampelTempBlockCells - 1) ~/ ampelTempBlockCells;
  final probe = RainGrid(
    values: Uint8List(0),
    width: width,
    height: height,
    west: info.west,
    east: info.east,
    north: info.north,
    south: info.south,
    measured: newest,
  );

  // Je Kachel die Stationen, die für IRGENDEINE ihrer Zellen die nächste
  // sein können — flach abgelegt, `candidateStart[b]` bis
  // `candidateStart[b + 1]`.
  //
  // Die Schranke ist exakt: Für eine Zelle der Kachel gilt
  // `dist(Zelle, s) >= dist(Mitte, s) - reach`, und die Siegerin liegt
  // höchstens `dMin + reach` entfernt. Wer also gewinnen kann, erfüllt
  // `dist(Mitte, s) <= dMin + 2 * reach`. `reach` ist der echte Abstand
  // Mitte→Ecke DIESER Kachel, deckt also auch die angeschnittene letzte
  // und die mit der Breite wandernde Zellgröße ab.
  final candidateStart = Int32List(blocksX * blocksY + 1);
  final candidates = <int>[];
  final fromCentre = Float64List(stations.length);
  for (var by = 0; by < blocksY; by++) {
    final rowEnd = (by + 1) * ampelTempBlockCells > height
        ? height
        : (by + 1) * ampelTempBlockCells;
    final rowStart = by * ampelTempBlockCells;
    // Mitte aus Kachelanfang und -ENDE — die letzte (angeschnittene)
    // hat ihre Mitte sonst außerhalb des Gitters.
    final lat = probe.latAtRow((rowStart + rowEnd) / 2);
    final cornerLat = probe.latAtRow(rowStart.toDouble());
    for (var bx = 0; bx < blocksX; bx++) {
      final colEnd = (bx + 1) * ampelTempBlockCells > width
          ? width
          : (bx + 1) * ampelTempBlockCells;
      final colStart = bx * ampelTempBlockCells;
      final lon = probe.lonAtColumn((colStart + colEnd) / 2);
      final reach = distanceKm(
          lat, lon, cornerLat, probe.lonAtColumn(colStart.toDouble()));
      var bestKm = double.infinity;
      for (final s in competing) {
        final km = distanceKm(lat, lon, stationLat[s], stationLon[s]);
        fromCentre[s] = km;
        if (km < bestKm) bestKm = km;
      }
      final limit = bestKm + 2 * reach + _candidateMarginKm;
      candidateStart[by * blocksX + bx] = candidates.length;
      for (final s in competing) {
        if (fromCentre[s] <= limit) candidates.add(s);
      }
    }
  }
  candidateStart[blocksX * blocksY] = candidates.length;
  final candidateOf = Int32List.fromList(candidates);

  // Die Zutaten je Zelle. `valid` 0 heißt „keine Aussage" — zu wenige
  // Regentage, keine Station in Reichweite oder eine zu lückige
  // Stationsreihe; auf der Karte ist alles drei transparent, und in
  // der Kombi-Ebene leuchtet dort nichts.
  //
  // Gemessen wird von der ZELLMITTE aus, mit derselben [distanceKm] wie
  // im Blatt — nicht mit einer eigenen, schnelleren Formel: Eine zweite
  // Rechnung wäre genau die Naht, an der die beiden wieder auseinander
  // liefen.
  final cellRain = Float32List(width * height);
  final cellMean = Float32List(width * height);
  final cellStationHeight = Int16List(width * height);
  final cellValid = Uint8List(width * height);
  final cellLon = Float64List(width);
  for (var x = 0; x < width; x++) {
    cellLon[x] = probe.lonAtColumn(x + 0.5);
  }
  for (var y = 0; y < height; y++) {
    final lat = probe.latAtRow(y + 0.5);
    final blockRow = (y ~/ ampelTempBlockCells) * blocksX;
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      if (known[i] < ampelMinRainDays) continue;
      final block = blockRow + x ~/ ampelTempBlockCells;
      var bestKm = double.infinity;
      var best = -1;
      for (var c = candidateStart[block]; c < candidateStart[block + 1]; c++) {
        final s = candidateOf[c];
        final km = distanceKm(lat, cellLon[x], stationLat[s], stationLon[s]);
        if (km < bestKm) {
          bestKm = km;
          best = s;
        }
      }
      if (best < 0 || bestKm > WeatherTable.maxStationKm) continue;
      if (stationAnswers[best] == 0) continue;
      final effective = weighted[i] / weightsTotal * ampelRainWindow;
      cellRain[i] = effective >= ampelRainSaturationMm
          ? 1.0
          : effective / ampelRainSaturationMm;
      cellMean[i] = stationMean[best];
      cellStationHeight[i] = stationHeight[best];
      cellValid[i] = 1;
    }
  }
  return AmpelLevelGrid(
    rainFactor: cellRain,
    meanC: cellMean,
    stationHeightM: cellStationHeight,
    valid: cellValid,
    width: width,
    height: height,
    west: info.west,
    east: info.east,
    north: info.north,
    south: info.south,
    newest: newest,
  );
}

/// Die Ampel-Stufen als Gitter — dieselbe Geometrie wie das
/// Regen-Gitter, aus dem sie stammen (Mercator-Zeilen!).
class AmpelLevelGrid {
  const AmpelLevelGrid({
    required this.rainFactor,
    required this.meanC,
    required this.stationHeightM,
    required this.valid,
    required this.width,
    required this.height,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.newest,
  });

  /// Je Zelle die ZUTATEN statt einer fertigen Stufe — die Glocke wird
  /// erst beim Abnehmer ausgewertet, mit dessen Höhe ([levelFor]).
  final Float32List rainFactor;

  /// Das UNKORRIGIERTE 20-Tage-Mittel der nächsten Station je Zelle.
  final Float32List meanC;

  /// Die Höhe dieser Station — der Startpunkt der Lapse-Verschiebung.
  final Int16List stationHeightM;

  /// 1 = Aussage möglich; 0 deckt alle drei Gründe ab (Regen lückig,
  /// keine Station, Stationsreihe lückig).
  final Uint8List valid;
  final int width;
  final int height;
  final double west;
  final double east;
  final double north;
  final double south;

  /// Der jüngste Tag des Stapels — der „Stand" für Dateinamen.
  final DateTime newest;

  /// Die Stufe an einem Punkt — `null` außerhalb des Gitters oder wo es
  /// keine Aussage gibt. DIE Auswertung des Zeichners und der Tests:
  /// Wer hier vorbeigeht, malt eine andere Antwort als das Blatt.
  AmpelLevel? levelAt(double lat, double lon, {ElevationGrid? elevation}) {
    final row = rowAt(lat);
    final column = columnAt(lon);
    if (row == null || column == null) return null;
    return levelFor(row, column,
        heightM: elevation?.heightMetersAt(lat, lon));
  }

  /// Die Gitterzeile zu einer Breite — `null` außerhalb.
  ///
  /// **Zeilen in MERCATOR**, wie beim Regen: In Grad gerechnet läge die
  /// Zuordnung am Südrand um Kilometer daneben (dieselbe Falle wie
  /// #247).
  ///
  /// Getrennt von [columnAt], weil die Kombi-Ebene über WABENZEILEN
  /// läuft: Die Breite ist dort je Zeile konstant, die Länge ändert sich
  /// je Wabe. So kostet die Zeile einmal zwei Logarithmen statt einmal
  /// je Wabe — bei Millionen Waben ist das der Unterschied zwischen
  /// „läuft" und „ruckelt".
  int? rowAt(double lat) {
    if (lat > north || lat < south) return null;
    final top = mercatorY(north);
    final fraction = (mercatorY(lat) - top) / (mercatorY(south) - top);
    final row = (fraction * height).floor();
    return row < 0 || row >= height ? null : row;
  }

  /// Die Gitterspalte zu einer Länge — `null` außerhalb.
  int? columnAt(double lon) {
    if (lon < west || lon > east) return null;
    final column = ((lon - west) / (east - west) * width).floor();
    return column < 0 || column >= width ? null : column;
  }

  /// Die Stufe einer Zelle — ohne Bereichsprüfung, wie [RainGrid.at].
  ///
  /// [heightM] ist die Höhe des ABNEHMERS (Waldwabe, Fadenkreuz-Punkt);
  /// `null` heißt unkorrigiert — exakt die Semantik von
  /// `ampelReadingFrom` ohne Spothöhe. Die Rechnung ist Zahl für Zahl
  /// die des Blatts: Mittel verschieben, dieselbe Glocke.
  AmpelLevel? levelFor(int row, int column, {int? heightM}) {
    final i = row * width + column;
    if (valid[i] == 0) return null;
    var mean = meanC[i].toDouble();
    if (heightM != null) {
      mean += lapseCorrectionK(
          stationHeightM: stationHeightM[i], targetHeightM: heightM);
    }
    return ampelLevelOf(rainFactor[i] * ampelBellOfMean(mean));
  }
}
