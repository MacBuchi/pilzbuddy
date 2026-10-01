// Vom Release-Asset zur fertigen Höhenlinie.
//
// Zwei Provider mit klarer Arbeitsteilung: [rainGridProvider] holt die
// Zahlen (Netz, Platte, still degradierend), [rainContoursProvider]
// rechnet daraus die Linien. Getrennt, weil die Zahlen noch eine zweite
// Aufgabe haben — die Regensumme am Spot, die ohne Linien auskommt.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../data/rain_grid_repository.dart';
import 'rain_contours.dart';
import 'rain_fill.dart';
import 'rain_grid.dart';
import 'rain_layer.dart';
import 'map_overlays.dart';
import 'rain_stack.dart';
import 'rain_sum.dart';
import 'spot_weather.dart';

final rainGridRepositoryProvider = Provider<RainGridRepository>(
    (ref) => RainGridRepository());

/// Wie ein Gitter beschafft wird. Dieselbe Test-Naht wie
/// `rainImageProviderFactory`: Ohne sie ginge jeder Flow-Test, der eine
/// Summenebene wählt, ins Netz — und `flutter test` ist netzfrei.
final rainGridLoaderProvider = Provider<Future<RainGrid?> Function(String)>(
    (ref) => ref.watch(rainGridRepositoryProvider).load);

/// Welche Ebenen ein eigenes Gitter haben. Radar hat keins: Der
/// 5-Minuten-Takt lässt sich nicht vorberechnen, und dort bleibt es beim
/// DWD-Bild in DWD-Farben — die Konvention, die jeder aus Wetter-Apps
/// kennt.
///
/// Für 7 und 14 Tage ist der Schlüssel nur noch ein NAME (Dateiname der
/// Fläche): Das Gitter dazu kommt nicht vom Server, sondern aus dem
/// Radar-Stapel ([rainGridProvider]).
String? rainGridKeyFor(RainLayer layer) => switch (layer) {
      RainLayer.last7d => 'd7',
      RainLayer.last14d => 'd14',
      RainLayer.last30d => 'w4',
      _ => null,
    };

/// Über wie viele Tage die Ebene summiert — `null` für Radar und aus.
int? rainSumDaysFor(RainLayer layer) => switch (layer) {
      RainLayer.last7d => 7,
      RainLayer.last14d => 14,
      RainLayer.last30d => 30,
      _ => null,
    };

/// Die Höhenstufen der Ebene.
List<int> rainLevelsFor(RainLayer layer) => switch (layer) {
      RainLayer.last7d => rainLevels7d,
      RainLayer.last14d => rainLevels14d,
      _ => rainLevels30d,
    };

/// Wer die aktive Regenebene zeichnet — und damit, welche Legende gilt.
///
/// Die EINE Bedingung für beide Engines und beide Legenden. Vorher stand
/// sie vierfach kopiert als `value?.isNotEmpty ?? false` da und las „lädt
/// noch" als „kein Gitter": Jede Erstaktivierung einer Summenebene zeigte
/// erst das DWD-Bild samt DWD-Legende und sprang dann auf die eigenen
/// Farben um — der Umschalt-Moment, den der Betreiber am 2026-08-05
/// gemeldet hat. Nebenbei war das DWD-Bild (187–568 KB) dann umsonst
/// geladen.
enum RainPaint {
  /// Eigene Farben: Gitter da, Bänder berechnet und nicht leer.
  own,

  /// Summenebene gewählt, Gitter lädt noch: NICHTS zeichnen — aber schon
  /// die eigene Legende zeigen, denn die ist statisch ([rainLevelsFor] und
  /// die Farbrampe hängen nicht an den geladenen Daten).
  pending,

  /// DWD-Bild in DWD-Farben: beim Radar immer (der 5-Minuten-Takt lässt
  /// sich nicht vorberechnen), bei den Summen als Rückfalllinie, wenn
  /// kein Gitter zu bekommen war.
  dwd,
}

final rainPaintProvider = Provider.family<RainPaint, RainLayer>((ref, layer) {
  // `off` und Radar: kein Gitter-Schlüssel → immer dwd, OHNE die
  // Gitter-Provider je zu instanziieren. Bei `off` ist der Wert egal —
  // rainLayerUrl(off) ist null, und die Legenden prüfen die Ebene selbst.
  if (rainGridKeyFor(layer) == null) return RainPaint.dwd;
  // 7 und 14 Tage haben kein DWD-Bild, auf das sie zurückfallen
  // könnten — die Bänder entscheiden dort nichts. Eigene Farben, sobald
  // das Gitter feststeht; fehlt es, liegt eben nichts (und das Blatt
  // zeigt trotzdem die eigene Legende statt einer leeren DWD-Stelle).
  // Über die Bänder zu gehen hieße: ein Feld ohne Bandgrenze (überall
  // dieselbe Stufe) zeichnete gar nichts.
  if (layer.dwdLayer == null) {
    final grid = ref.watch(rainGridProvider(layer));
    return grid.hasValue || grid.hasError ? RainPaint.own : RainPaint.pending;
  }
  final contours = ref.watch(rainContoursProvider(layer));
  // `hasError` VOR `hasValue`: Riverpod behält bei Fehlern den Vorwert —
  // der darf nicht als `own` durchgehen. Ein Fehler entstünde nur aus
  // einem Bug in der Bandberechnung (das Laden selbst degradiert still zu
  // null); dann ist das DWD-Bild die einzige funktionierende Darstellung.
  if (contours.hasError) return RainPaint.dwd;
  // `hasValue` statt `when`: Beim Neuladen mit Vorwert bleibt es wahr —
  // ein Rückfall auf `pending` wäre Flackern bei jedem Reload.
  if (contours.hasValue) {
    return contours.requireValue.isNotEmpty ? RainPaint.own : RainPaint.dwd;
  }
  return RainPaint.pending;
});

/// Das rohe Wertegitter der aktiven Ebene — `null`, wenn es für sie
/// keines gibt oder nichts geladen werden konnte.
///
/// 30 Tage: RADOLAN-W4 vom Server. 7 und 14 Tage: die Summe aus dem
/// Radar-Stapel ([rainSumGrid], im Isolate) — der DWD hat dafür kein
/// Produkt. Über DIESEN Provider laufen danach Bänder, Fläche, Datei und
/// Legende unverändert, für alle drei Zeiträume derselbe Weg.
final FutureProviderFamily<RainGrid?, RainLayer> rainGridProvider =
    FutureProvider.family<RainGrid?, RainLayer>(
  (ref, layer) async {
    final key = rainGridKeyFor(layer);
    if (key == null) return null;
    if (layer == RainLayer.last30d) {
      return ref.watch(rainGridLoaderProvider)(key);
    }
    // Beide Watches VOR den Awaits (#255/#257).
    final stackFuture = ref.watch(radarStackLoadedProvider.future);
    final endFuture = ref.watch(rainSumEndProvider(layer).future);
    final stack = await stackFuture;
    if (stack == null) return null;
    final end = await endFuture;
    return compute(
        _sum, (stack: stack, days: rainSumDaysFor(layer)!, end: end));
  },
);

RainGrid? _sum(({RainStackData stack, int days, DateTime? end}) input) =>
    rainSumGrid(input.stack, input.days, endDay: input.end);

/// Der letzte Tag, über den Radar- und Modellsumme einer Ebene laufen —
/// der ÄLTERE der beiden Stände, damit beide Seiten der Grenze dieselbe
/// Woche meinen (Bildschirmfoto 2026-10-01: Das Modell war einen Tag
/// weiter als das Radar).
///
/// 30 Tage: W4 lässt sich nicht verschieben, also folgt nur das Modell
/// dessen letztem vollen Tag (gemessen wird gegen 6 Uhr UTC, die Summe
/// reicht damit bis gestern). `null` heißt „jeder nimmt seinen jüngsten".
final FutureProviderFamily<DateTime?, RainLayer> rainSumEndProvider =
    FutureProvider.family<DateTime?, RainLayer>((ref, layer) async {
  if (rainSumDaysFor(layer) == null) return null;
  final modelFuture = ref.watch(modelStackLoadedProvider.future);
  final DateTime? upperEnd;
  if (layer == RainLayer.last30d) {
    final w4 = await ref.watch(rainGridProvider(layer).future);
    upperEnd = w4 == null ? null : rainLastFullDay(w4.measured);
  } else {
    final radar = await ref.watch(radarStackLoadedProvider.future);
    upperEnd = radar == null ? null : rainStackNewest(radar);
  }
  final model = await modelFuture;
  final modelEnd = model == null ? null : rainStackNewest(model);
  if (upperEnd == null) return modelEnd;
  if (modelEnd == null) return upperEnd;
  return modelEnd.isBefore(upperEnd) ? modelEnd : upperEnd;
});

/// Der letzte volle Tag einer gleitenden Summe, die zu [measured] endet.
DateTime rainLastFullDay(DateTime measured) {
  final utc = measured.toUtc();
  return DateTime(utc.year, utc.month, utc.day - 1);
}

/// Die Höhenlinien der aktiven Ebene.
///
/// Gerechnet im Isolate: An echten Daten sind es 45 ms, und das ist
/// wenig — aber es ist Rechenzeit im Kartenpfad einer App, die schon
/// einmal an genau dieser Stelle in einen ANR gelaufen ist (#151).
/// Einmal beim Einschalten, nie je Kamerabewegung.
final rainContoursProvider =
    FutureProvider.family<List<ContourLine>, RainLayer>((ref, layer) async {
  final grid = await ref.watch(rainGridProvider(layer).future);
  if (grid == null) return const [];
  return compute(_contours, (grid: grid, levels: rainLevelsFor(layer)));
});

List<ContourLine> _contours(({RainGrid grid, List<int> levels}) input) =>
    rainContours(input.grid, levels: input.levels);

/// Die eingefärbte Fläche zwischen den Höhenlinien, als PNG — **samt
/// ihrer Ausdehnung**.
///
/// Die Grenzen kommen mit, weil sie NICHT die der DWD-Bildebene sind:
/// Das Gitter ist auf seine Zellen mit Daten beschnitten (w4:
/// 5,73–15,17°), die Bildebene deckt bewusst etwas mehr ab
/// (5,6–15,4°). Wer hier `RainLayer.bounds` einsetzt, verschiebt die
/// Fläche um rund zwanzig Kilometer gegen die Linien — sichtbar erst,
/// wenn man genau hinsieht, und dann falsch.
///
/// Im Isolate, wie die Linien: Es sind 550 000 Zellen, und das ist
/// Rechenzeit im Kartenpfad. Beide Provider hängen am selben Gitter,
/// geladen wird es also einmal und zweimal ausgewertet.
final rainFillProvider = FutureProvider.family<RainFill?, RainLayer>(
    (ref, layer) async {
  // Die Modellsumme NICHT abwarten, sondern nehmen, was da ist: Ohne
  // Empfang kann der Modell-Stapel lange brauchen, und das eigene Gitter
  // soll deshalb nicht warten. Kommt sie später, rechnet der Provider
  // neu — dann mit Übergang. Watch VOR dem Await (#255/#257).
  final model = rainSumDaysFor(layer) == null
      ? null
      : ref.watch(modelRainSumProvider(layer)).valueOrNull;
  final grid = await ref.watch(rainGridProvider(layer).future);
  if (grid == null) return null;
  // Am Rand der Radarabdeckung zum Modell hin übergeblendet
  // ([blendEdge]) — nur das Bild, die Zahl am Spot bleibt roh.
  final png = await compute(
      _fill, (grid: grid, model: model, levels: rainLevelsFor(layer)));
  return RainFill(
    png: png,
    west: grid.west,
    east: grid.east,
    north: grid.north,
    south: grid.south,
    measured: grid.measured,
  );
});

/// Die Fläche und der Ausschnitt, auf den sie gehört.
class RainFill {
  const RainFill({
    required this.png,
    required this.west,
    required this.east,
    required this.north,
    required this.south,
    required this.measured,
  });

  final Uint8List png;
  final double west;
  final double east;
  final double north;
  final double south;

  /// Der Messzeitpunkt des zugrunde liegenden Gitters — er unterscheidet
  /// zwei Flächen derselben Ebene und wird deshalb zum Dateinamen.
  final DateTime measured;
}

/// Dieselbe Fläche, aber als Datei auf Platte — der Weg für MapLibre,
/// dessen `image`-Quelle eine URL nimmt und keine Bytes.
///
/// Bewusst OHNE `family`: Die MapLibre-Ansicht hängt sich per `ref.listen`
/// daran, und ein Familienschlüssel, der beim Ebenenwechsel wechselt,
/// wäre dort ein zweiter Zuhörer statt eines geänderten Werts — die alte
/// Fläche bliebe auf der Karte liegen.
///
/// Auf dem Web-Pfad wird dieser Provider nie beobachtet; dort nimmt
/// flutter_map die Bytes direkt.
final rainFillFileProvider =
    FutureProvider<({String url, RainFill fill})?>((ref) async {
  final layer = ref.watch(drawnRainLayerProvider);
  final key = rainGridKeyFor(layer);
  if (key == null) return null;
  final fill = await ref.watch(rainFillProvider(layer).future);
  if (fill == null) return null;
  final url = await ref
      .watch(rainGridRepositoryProvider)
      .writeFill(key, fill.measured, fill.png);
  return url == null ? null : (url: url, fill: fill);
});

Uint8List _fill(
        ({RainGrid grid, RainGrid? model, List<int> levels}) input) =>
    rainFillPng(blendEdge(input.grid, input.model), levels: input.levels);

// ---------------------------------------------------------------------
// Der Tagesverlauf am Spot
// ---------------------------------------------------------------------

/// Wie der Tagesstapel beschafft wird. Dieselbe Test-Naht wie
/// [rainGridLoaderProvider] — ohne sie ginge jeder Flow-Test, der ein
/// Spot-Blatt öffnet, ins Netz.
final rainStackLoaderProvider =
    Provider<Future<RainStackData?> Function()>((ref) {
  final repository = ref.watch(rainGridRepositoryProvider);
  return () => repository.loadDailyStack();
});

/// Hat die Nutzerin dem Nachladen zugestimmt?
///
/// Aus den Einstellungen gelesen und dort auch geschrieben — die
/// Zustimmung überlebt den Neustart, sonst wäre sie eine Frage, die bei
/// jedem Spot neu käme.
final rainCourseEnabledProvider = StateProvider<bool>(
    (ref) => ref.watch(settingsProvider).rainCourseEnabled);

/// Der Radar-Stapel, geladen OHNE Blick auf die Zustimmung — einmal für
/// alle Abnehmer.
///
/// Zwei Wege führen hierher, und beide sind eine Zustimmung: der Verlauf
/// am Spot über [rainStackProvider] (Dialog „Wetter an diesem Spot") und
/// die Regenebene „7/14 Tage" — wer sie anschaltet, fordert die Tage an,
/// so wie die 30 Tage das W4-Gitter. Getrennt, damit kein Abnehmer den
/// Stapel ein zweites Mal lädt. Beobachtet wird er nur hinter einem der
/// beiden Tore: Beobachten ist laden.
final radarStackLoadedProvider = FutureProvider<RainStackData?>(
    (ref) => ref.watch(rainStackLoaderProvider)());

/// Der geladene Stapel — `null`, solange niemand zugestimmt hat.
final rainStackProvider = FutureProvider<RainStackData?>((ref) async {
  if (!ref.watch(rainCourseEnabledProvider)) return null;
  return ref.watch(radarStackLoadedProvider.future);
});

/// Der Modellstapel des Alpenraums (#612) — dieselbe Test-Naht wie
/// [rainStackLoaderProvider]; das Harness setzt beide auf `null`.
final modelRainStackLoaderProvider =
    Provider<Future<RainStackData?> Function()>((ref) {
  final repository = ref.watch(rainGridRepositoryProvider);
  return () => repository.loadModelStack();
});

/// Der geladene Modellstapel — dieselbe Zustimmung wie das Radar: „Wetter
/// an diesem Spot" ist EIN Angebot, und woher die Zahl kommt, sagt das
/// Blatt, nicht ein zweiter Dialog.
final modelRainStackProvider = FutureProvider<RainStackData?>((ref) async {
  if (!ref.watch(rainCourseEnabledProvider)) return null;
  return ref.watch(modelStackLoadedProvider.future);
});

/// Der Modell-Stapel ohne Tor — dieselbe Trennung wie
/// [radarStackLoadedProvider], aus demselben Grund.
final modelStackLoadedProvider = FutureProvider<RainStackData?>(
    (ref) => ref.watch(modelRainStackLoaderProvider)());

// ---------------------------------------------------------------------
// Die Summen im Alpenraum
// ---------------------------------------------------------------------

/// Die Summe der letzten [days] Tage aus dem Modell-Stapel — `null`,
/// solange er sie nicht lückenlos trägt.
///
/// Warum es das gibt: RADOLAN-W4 und der Radar-Stapel enden an der
/// deutschen Grenze, in Tirol war die Ebene „30 Tage" leer (Betreiber,
/// 2026-10-01). Die Modellmaske spart Deutschland aus, die beiden
/// Flächen überdecken sich also nicht — dieselbe Teilung wie bei der
/// Ampel, nur ohne dass eine Zelle wählen muss.
final modelRainSumProvider =
    FutureProvider.family<RainGrid?, RainLayer>((ref, layer) async {
  final days = rainSumDaysFor(layer);
  if (days == null) return null;
  final stackFuture = ref.watch(modelStackLoadedProvider.future);
  final endFuture = ref.watch(rainSumEndProvider(layer).future);
  final stack = await stackFuture;
  if (stack == null) return null;
  final end = await endFuture;
  return compute(_sum, (stack: stack, days: days, end: end));
});

/// Wie viele Modelltage lückenlos liegen — für den Satz im Blatt, wenn
/// die Summe noch fehlt. `null`, wenn es gar keinen Stapel gibt.
///
/// Gezählt ab dem gemeinsamen letzten Tag ([rainSumEndProvider]) — vom
/// jüngsten Modelltag aus gezählt stünde „30 von 30" neben einer Fläche,
/// die fehlt, weil ein Tag am anderen Ende noch nicht da ist.
final modelStackRunProvider =
    FutureProvider.family<int?, RainLayer>((ref, layer) async {
  final stackFuture = ref.watch(modelStackLoadedProvider.future);
  final endFuture = ref.watch(rainSumEndProvider(layer).future);
  final stack = await stackFuture;
  if (stack == null) return null;
  return rainStackRunLength(stack, endDay: await endFuture);
});

/// Die Modellfläche der GEZEICHNETEN Ebene — `null` bei Radar, aus,
/// oder solange die Tage fehlen.
///
/// UNGEGLÄTTET, anders als die Radarfläche: Eine Zelle sind hier 12 km,
/// ein 3×3-Mittel verschmierte über 36 km und zöge Täler an den Grat.
/// Weich wird das Bild trotzdem — durch das lineare Resampling beider
/// Engines.
final modelRainFillProvider = FutureProvider<RainFill?>((ref) async {
  final layer = ref.watch(drawnRainLayerProvider);
  if (rainSumDaysFor(layer) == null) return null;
  // Beide Watches VOR den Awaits (#255/#257).
  final modelFuture = ref.watch(modelRainSumProvider(layer).future);
  final upperFuture = ref.watch(rainGridProvider(layer).future);
  final grid = await modelFuture;
  if (grid == null) return null;
  // Wo Radar oder W4 schon etwas sagen, schweigt das Modell — sonst
  // lägen an der Grenze zwei Flächen übereinander ([maskCovered]).
  final upper = await upperFuture;
  final png = await compute(_rawFill,
      (grid: grid, upper: upper, levels: rainLevelsFor(layer)));
  return RainFill(
    png: png,
    west: grid.west,
    east: grid.east,
    north: grid.north,
    south: grid.south,
    measured: grid.measured,
  );
});

/// Dieselbe Fläche als Datei für MapLibre — Muster [rainFillFileProvider].
/// Der Zeitraum steht im Dateinamen: 7 und 14 Tage haben denselben
/// jüngsten Tag, und gleicher Name hieße altes Bild.
final modelRainFillFileProvider =
    FutureProvider<({String url, RainFill fill})?>((ref) async {
  final layer = ref.watch(drawnRainLayerProvider);
  final fill = await ref.watch(modelRainFillProvider.future);
  if (fill == null) return null;
  final url = await ref.watch(rainGridRepositoryProvider).writeFill(
      'model_${rainGridKeyFor(layer)}', fill.measured, fill.png);
  return url == null ? null : (url: url, fill: fill);
});

Uint8List _rawFill(
        ({RainGrid grid, RainGrid? upper, List<int> levels}) input) =>
    rainFillPng(maskCovered(input.grid, input.upper),
        levels: input.levels, smooth: false);

/// Beide Stapel in VORRANG-Reihenfolge, Radar zuerst — leer ohne
/// Zustimmung oder wenn keiner ladbar ist. Alle Abnehmer (Verlauf am
/// Spot, gebündelte Verläufe, Ampel-Fläche) lesen DIESE Liste, damit es
/// genau einen Vorrang gibt.
final rainStacksProvider = FutureProvider<List<RainStackData>>((ref) async {
  // Beide Watches VOR den Awaits (#255/#257).
  final radarFuture = ref.watch(rainStackProvider.future);
  final modelFuture = ref.watch(modelRainStackProvider.future);
  final radar = await radarFuture;
  final model = await modelFuture;
  return [?radar, ?model];
});

/// Der Regenverlauf an einem Punkt.
///
/// Im Isolate: Es sind vierzehn Gitter auszupacken, und das ist
/// Rechenzeit in einem Blatt, das sich sofort öffnen soll. Der
/// Familienschlüssel ist der Punkt selbst, also wird je Spot einmal
/// gerechnet und danach aus dem Provider-Cache geliefert.
final rainCourseProvider =
    FutureProvider.family<RainCourse?, ({double lat, double lon})>(
        (ref, at) async {
  final stacks = await ref.watch(rainStacksProvider.future);
  if (stacks.isEmpty) return null;
  return compute(_course, (stacks: stacks, lat: at.lat, lon: at.lon));
});

/// Die Regenverläufe an MEHREREN Punkten — **eine** Dekodierung je Tag
/// für alle zusammen.
///
/// Warum eine eigene Familie neben [rainCourseProvider] und nicht N
/// Aufrufe von ihm: Der Einzelweg packt je Punkt alle 26 Tagesgitter aus,
/// um je Tag ein Byte zu lesen. Neunzehn Spots waren so 494
/// Dekodierungen und 2926 ms, gebündelt sind es 26 und 150 ms
/// (`docs/map-performance.md`, Nachtrag 2026-08-23). Für EIN Spot-Blatt
/// ist der Einzelweg richtig und bleibt, wo er ist.
///
/// Der Familienschlüssel ist eine zusammengefügte Zeichenkette und keine
/// Liste: Zwei inhaltlich gleiche Listen sind für `==` verschieden, und
/// Riverpod würde die Familie bei jedem Neuaufbau neu rechnen.
final rainCoursesProvider =
    FutureProvider.family<List<RainCourse>?, String>((ref, key) async {
  final stacks = await ref.watch(rainStacksProvider.future);
  if (stacks.isEmpty) return null;
  final points = pointsFromKey(key);
  if (points.isEmpty) return const [];
  return compute(_courses, (stacks: stacks, points: points));
});

/// Punkte → Familienschlüssel. Auf sechs Nachkommastellen gerundet (~11
/// cm): Genauer wäre der Schlüssel empfindlicher als das 1-km-Raster,
/// das dahinter abgetastet wird.
String pointsKey(List<({double lat, double lon})> points) => [
      for (final p in points)
        '${p.lat.toStringAsFixed(6)},${p.lon.toStringAsFixed(6)}',
    ].join(';');

/// Und zurück. Ein unlesbares Stück ergibt eine leere Liste statt eines
/// Fehlers — der Schlüssel entsteht ausschließlich aus [pointsKey].
List<({double lat, double lon})> pointsFromKey(String key) {
  if (key.isEmpty) return const [];
  final points = <({double lat, double lon})>[];
  for (final part in key.split(';')) {
    final halves = part.split(',');
    if (halves.length != 2) continue;
    final lat = double.tryParse(halves[0]);
    final lon = double.tryParse(halves[1]);
    if (lat == null || lon == null) continue;
    points.add((lat: lat, lon: lon));
  }
  return points;
}

List<RainCourse> _courses(
        ({List<RainStackData> stacks, List<({double lat, double lon})> points})
            input) =>
    rainCoursesFromStacks(input.stacks, points: input.points);

RainCourse _course(
        ({List<RainStackData> stacks, double lat, double lon}) input) =>
    rainCoursesFromStacks(input.stacks,
        points: [(lat: input.lat, lon: input.lon)]).single;

/// Wie die Stationstabelle beschafft wird. Dieselbe Test-Naht wie
/// [rainStackLoaderProvider] — ohne sie ginge jeder Flow-Test, der ein
/// Spot-Blatt mit erteilter Zustimmung öffnet, ins Netz.
final weatherTableLoaderProvider =
    Provider<Future<List<int>?> Function()>((ref) {
  final repository = ref.watch(rainGridRepositoryProvider);
  return () => repository.loadWeatherTable();
});

/// Die geladene Stationstabelle — `null`, solange niemand zugestimmt hat.
///
/// Dieselbe Zustimmung wie der Regenverlauf, kein zweiter Dialog: „Wetter
/// an diesem Spot" ist EIN Angebot, und die 45 KB Stationswerte ändern
/// an dessen Größenordnung nichts. Geparst wird im Isolate — ~760
/// Stationen à 14 Tage sind wenig, aber es ist Arbeit in einem Blatt,
/// das sich sofort öffnen soll.
final weatherTableProvider = FutureProvider<WeatherTable?>((ref) async {
  if (!ref.watch(rainCourseEnabledProvider)) return null;
  final bytes = await ref.watch(weatherTableLoaderProvider)();
  if (bytes == null) return null;
  return compute(weatherTableFrom, bytes);
});

/// Die Temperatur an einem Punkt: je Netz (Luft, Boden) die nächste
/// Station mit genug gemessenen Tagen — oder `null`, wenn keine in
/// Reichweite ist. Kein Mitteln über Stationen; die Begründung steht in
/// `spot_weather.dart`.
final spotTemperatureProvider =
    FutureProvider.family<SpotTemperature?, ({double lat, double lon})>(
        (ref, at) async {
  final table = await ref.watch(weatherTableProvider.future);
  return table?.at(at.lat, at.lon);
});

/// Die 30-Tage-Summe an einem Punkt, aus dem vorhandenen W4-Gitter.
///
/// Warum nicht aus dem Stapel: dreißig Tagesraster wären rund 1,5 MB,
/// und der DWD rechnet diese Summe ohnehin selbst. Warum überhaupt: Es
/// ist die Zahl der Forums-Faustregel (≥100 mm in 30 Tagen) und die
/// Größe, auf der der tschechische Wetterdienst seinen Pilzindex baut.
final rainMonthAtProvider =
    FutureProvider.family<int?, ({double lat, double lon})>((ref, at) async {
  if (!ref.watch(rainCourseEnabledProvider)) return null;
  final grid = await ref.watch(rainGridProvider(RainLayer.last30d).future);
  final measured = grid?.mmAt(at.lat, at.lon);
  if (measured != null) return measured;
  // Außerhalb Deutschlands: die Summe des Modell-Stapels, dieselbe Zahl,
  // die die Ebene dort zeichnet. Sonst stünde in Tirol eine Fläche auf
  // der Karte und im Blatt nichts.
  final model =
      await ref.watch(modelRainSumProvider(RainLayer.last30d).future);
  return model?.mmAt(at.lat, at.lon);
});
