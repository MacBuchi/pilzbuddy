// Die Temperatur am Spot — aus der nächsten Wetterstation, lokal gesucht.
//
// **Warum Stationen und kein Raster:** Der DWD rechnet zwar 1-km-Raster
// für Boden- und Lufttemperatur, aber nur als Monatspakete, und das
// neueste war am 4. August der Juli (gemessen). Für „wie warm war es
// hier" ist das unbrauchbar. Die Stationsmessungen sind dagegen am selben
// Morgen aktualisiert.
//
// **Warum das erlaubt ist, obwohl es eine Zuordnung braucht:** Die Suche
// läuft auf dem Gerät, über eine Tabelle, die für alle gleich aussieht.
// Keine Anfrage nennt einen Spot — dieselbe Regel wie beim Regengitter.
//
// **Warum die nächste Station und kein Mittel über mehrere:** Die
// entscheidungsrelevante Zahl ist „war es zu kalt?" — ein Tiefstwert.
// Wer −1,2 °C, +0,5 °C und +1,0 °C von drei Stationen mischt, zeigt
// +0,1 °C und verschweigt den Frost. Außerdem soll neben der Linie eine
// benennbare Station stehen, kein Mini-Modell. Robust wird es
// stationsweise: Wer zu viele Lücken hat, wird übersprungen — es gewinnt
// die übernächste, keine Mischung.
//
// **Die ehrliche Grenze:** Temperatur ist waagerecht glatt, die Höhe ist
// es nicht. 0,65 K je 100 m, und im Mittelgebirge sind 300 m Unterschied
// zur Station normal — also gut 2 K. Das DIAGRAMM zeigt weiterhin die
// rohen Stationswerte (beschriftet mit Station und Stationshöhe): Es
// sind Messwerte, und so bleiben sie welche. Die PILZAMPEL dagegen
// rechnet seit dem Höhengitter (`elevation_grid.dart`) auf Spothöhe um
// — ihre Zahl steht mit eigener Beschriftung in ihrer eigenen Zeile,
// die Validierung hat immer schon Spothöhen-Temperaturen gesehen.
import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';

import '../../core/geo.dart';

/// Eine Wetterstation: Ort, Höhe — und wie viele Tage sie im Fenster
/// wirklich gemessen hat.
abstract class WeatherStation {
  const WeatherStation({
    required this.name,
    required this.lat,
    required this.lon,
    required this.height,
  });

  final String name;
  final double lat;
  final double lon;

  /// Stationshöhe in Metern über NN — steht neben dem Wert, weil sie der
  /// größte Unsicherheitsbeitrag ist.
  final int height;

  /// An wie vielen Tagen des Fensters liegt ein vollständiger Messwert
  /// vor? Entscheidet, ob die Station als „nächste" überhaupt antritt.
  int get measuredDays;

  /// Tritt diese Station bei der Nachbarsuche überhaupt an?
  ///
  /// DIE Definition — nicht nachbauen. Die Ampel-Fläche
  /// (`ampelLevelsFrom`) sucht ihre Station je Zelle selbst, weil sie es
  /// hunderttausendfach tut; sie muss dabei aber nach derselben Regel
  /// sieben wie das Spot-Blatt, sonst zeigen Farbe und Text an derselben
  /// Koordinate verschiedene Stufen (Issue #279).
  bool get competes => measuredDays >= WeatherTable.minMeasuredDays;
}

/// Eine Station des Luftnetzes: Tageshöchst- und Tagestiefstwerte in °C,
/// ältester Tag zuerst, `null` wo nichts gemeldet wurde.
class AirStation extends WeatherStation {
  const AirStation({
    required super.name,
    required super.lat,
    required super.lon,
    required super.height,
    required this.max,
    required this.min,
  });

  final List<double?> max;
  final List<double?> min;

  @override
  int get measuredDays => [
        for (final (index, value) in max.indexed)
          if (value != null && min[index] != null) true
      ].length;
}

/// Eine Station des Bodennetzes: Tagesmittel in 5 cm Tiefe in °C — die
/// Schicht, in der das Myzel lebt.
class SoilStation extends WeatherStation {
  const SoilStation({
    required super.name,
    required super.lat,
    required super.lon,
    required super.height,
    required this.soil,
  });

  final List<double?> soil;

  @override
  int get measuredDays => soil.whereType<double>().length;
}

/// Die Stationstabelle: die Tage, die alle Reihen abdecken, und die
/// beiden Netze — Luft (~465 Stationen) und Boden (~293) sind getrennte
/// Messnetze, die nächste Station darf also je Netz eine andere sein.
class WeatherTable {
  const WeatherTable({
    required this.days,
    required this.air,
    required this.soil,
  });

  final List<DateTime> days;
  final List<AirStation> air;
  final List<SoilStation> soil;

  /// Mindestens 10 der 14 Tage müssen gemessen sein, sonst tritt die
  /// Station nicht an: Eine Linie, die überwiegend aus Lücken besteht,
  /// sieht aus wie ein Fehler der App — und die übernächste Station ist
  /// im Median nur wenige Kilometer weiter weg.
  static const minMeasuredDays = 10;

  /// Jenseits davon ist die „nächste Station" kein Nachbarschaftswert
  /// mehr, sondern das Wetter einer anderen Gegend. Innerhalb
  /// Deutschlands liegt die nächste Luftstation nie weiter als ~52 km
  /// (gemessen 2026-08-04); die Grenze schneidet also nur Spots im
  /// Ausland ab — dort entfällt die Zeile, statt zu raten.
  static const maxStationKm = 100.0;

  /// Die nächste brauchbare Station je Netz — samt Entfernung.
  ///
  /// Reihum über alle Einträge: Das ist eine Schleife über eine kurze
  /// Liste, einmal beim Öffnen eines Spot-Blatts. Ein Index wäre mehr
  /// Code als Gewinn. Bei Gleichstand gewinnt die frühere in der Liste —
  /// deterministisch, derselbe Spot sieht immer dieselbe Station.
  ({T station, double km})? _nearest<T extends WeatherStation>(
      List<T> stations, double lat, double lon) {
    T? best;
    var bestKm = double.infinity;
    for (final station in stations) {
      if (!station.competes) continue;
      final km = distanceKm(lat, lon, station.lat, station.lon);
      if (km < bestKm) {
        bestKm = km;
        best = station;
      }
    }
    if (best == null || bestKm > maxStationKm) return null;
    return (station: best, km: bestKm);
  }

  /// Die nächste brauchbare Luftstation — der öffentliche Einstieg in
  /// die Regel oben. Die Ampel-Fläche prüft sich im Test gegen genau
  /// diese Funktion (#279).
  ({AirStation station, double km})? nearestAir(double lat, double lon) =>
      _nearest(air, lat, lon);

  /// Was am Spot gezeigt wird — `null`, wenn kein Netz eine brauchbare
  /// Station in Reichweite hat.
  SpotTemperature? at(double lat, double lon) {
    final airPick = nearestAir(lat, lon);
    final soilPick = _nearest(soil, lat, lon);
    if (airPick == null && soilPick == null) return null;
    return SpotTemperature(days: days, air: airPick, soil: soilPick);
  }
}

/// Was am Spot angezeigt wird: je Netz die Station, ihre Entfernung und
/// die Tageswerte. Luft und Boden dürfen einzeln fehlen — die Linien, die
/// es gibt, werden gezeichnet, die anderen entfallen ohne Platzhalter.
class SpotTemperature {
  const SpotTemperature({
    required this.days,
    required this.air,
    required this.soil,
  });

  final List<DateTime> days;
  final ({AirStation station, double km})? air;
  final ({SoilStation station, double km})? soil;

  List<double?>? get max => air?.station.max;
  List<double?>? get min => air?.station.min;
  List<double?>? get soilMean => soil?.station.soil;

  /// Der wärmste und der kälteste Wert über alle Linien — der Maßstab
  /// für die °C-Achse.
  ({double low, double high})? get span {
    double? low, high;
    for (final track in [max, min, soilMean]) {
      for (final value in track ?? const <double?>[]) {
        if (value == null) continue;
        low = low == null ? value : math.min(low, value);
        high = high == null ? value : math.max(high, value);
      }
    }
    return low == null || high == null ? null : (low: low, high: high);
  }

  bool get isEmpty => span == null;
}

/// Packt aus, was `tool/spot_weather.py` geschrieben hat — `null`, wenn
/// die Datei kaputt oder das Format fremd ist (dann eben keine
/// Temperatur, die App läuft weiter).
WeatherTable? weatherTableFrom(List<int> gzippedJson) {
  try {
    final json = jsonDecode(
            utf8.decode(GZipDecoder().decodeBytes(gzippedJson)))
        as Map<String, dynamic>;
    final days = [
      for (final day in json['days'] as List) DateTime.parse(day as String),
    ];
    if (days.isEmpty) return null;
    // Eine Reihe, deren Länge nicht zu den Tagen passt, wäre still um
    // Tage verschoben — solche Stationen werden übersprungen, nicht
    // zurechtgebogen.
    List<double?>? track(dynamic raw) {
      if (raw is! List || raw.length != days.length) return null;
      return [
        for (final value in raw)
          value == null ? null : (value as num).toDouble(),
      ];
    }

    final air = <AirStation>[];
    for (final entry in json['stations'] as List) {
      final station = entry as Map<String, dynamic>;
      final max = track(station['max']);
      final min = track(station['min']);
      if (max == null || min == null) continue;
      air.add(AirStation(
        name: station['name'] as String,
        lat: (station['lat'] as num).toDouble(),
        lon: (station['lon'] as num).toDouble(),
        height: station['h'] as int,
        max: max,
        min: min,
      ));
    }
    final soil = <SoilStation>[];
    // Ältere Tabellenstände kennen den Abschnitt noch nicht — dann gibt
    // es eben nur Luftlinien.
    for (final entry in json['soil'] as List? ?? const []) {
      final station = entry as Map<String, dynamic>;
      final values = track(station['soil']);
      if (values == null) continue;
      soil.add(SoilStation(
        name: station['name'] as String,
        lat: (station['lat'] as num).toDouble(),
        lon: (station['lon'] as num).toDouble(),
        height: station['h'] as int,
        soil: values,
      ));
    }
    if (air.isEmpty && soil.isEmpty) return null;
    return WeatherTable(days: days, air: air, soil: soil);
  } catch (_) {
    // Kaputte Datei, fremdes Format: kein Fall für error_reports — die
    // Temperatur ist eine Zugabe im Spot-Blatt, kein Kernpfad.
    return null;
  }
}
