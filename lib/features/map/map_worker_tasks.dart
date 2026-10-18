// Die Rechnungen des Zeichen-Wegs (#641) samt ihren Codecs (#689, B2).
//
// Eine Rechnung steht hier, nicht neben ihrem Provider: Der Web Worker
// übersetzt diese Datei ohne Flutter, und jeder Provider zieht Flutter
// und Riverpod mit (`test/map_worker_imports_test.dart`, Wurzel dieser
// Datei). Der Worker schlägt eine Rechnung über ihre [MapWorkerTask.id] in
// [mapWorkerTasks] nach — wer eine neue anlegt, trägt sie dort ein, sonst
// rechnet sie im Browser auf dem Hauptthread (und der Test sagt es).
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import '../../core/map_worker_task.dart';
import '../../core/wire.dart';
import '../../data/rain_stack_data.dart';
import '../ampel/ampel_fill.dart' show AmpelLevelGrid, AmpelLevels;
import '../ampel/ampel_model.dart' show AmpelClass, AmpelLogit;
import '../offline_areas/area_edit_png.dart';
import 'contours.dart' show ContourLine;
import 'elevation_contours.dart';
import 'elevation_grid.dart';
import 'forest_fill.dart';
import 'forest_fill_window.dart';
import 'forest_grid.dart';
import 'gbif_fill.dart';
import 'gbif_finds.dart';
import 'protected_areas.dart';
import 'rain_stack.dart';

/// Alle Rechnungen — die Tabelle des Workers.
final mapWorkerTasks = <MapWorkerTask<Object?, Object?>>[
  forestFillTask,
  forestFillFineTask,
  forestAmpelFillTask,
  forestAmpelFillFineTask,
  gbifFillTask,
  areaEditFillTask,
  contoursTask,
  legendRainCourseTask,
];

// ---------------------------------------------------------------------------
// Wald und Ampel.

/// Was je Auftrag hinübergeht — klein; die Gitter liegen in Fächern.
typedef ForestFillParams = ({
  Set<ForestClass> classes,
  FillWindow window,
  List<AmpelClass>? ampelClasses,
  List<String> blocks,
});

/// Die Familie der feinen Waldblöcke (`forestBlock#<datei>`).
const forestBlockFamily = 'forestBlock#';

const _forestSlots = <String, WireCodec<Object?>>{
  'forest': WireSlot(forestGridCodec),
  forestBlockFamily: WireSlot(forestGridCodec),
  'protected': WireSlot(WireNullable(protectedAreasCodec)),
  'ampelLevels': WireSlot(ampelLevelsCodec),
  'elevation': WireSlot(WireNullable(elevationGridCodec)),
};

const forestFillTask = MapWorkerTask<ForestFillParams, Uint8List>(
    'forest', _fill,
    params: forestFillParamsCodec, result: wireBytes, slots: _forestSlots);
const forestFillFineTask = MapWorkerTask<ForestFillParams, Uint8List>(
    'forestFine', _fillFine,
    params: forestFillParamsCodec, result: wireBytes, slots: _forestSlots);
const forestAmpelFillTask = MapWorkerTask<ForestFillParams, Uint8List>(
    'forestAmpel', _fillCombined,
    params: forestFillParamsCodec, result: wireBytes, slots: _forestSlots);
const forestAmpelFillFineTask = MapWorkerTask<ForestFillParams, Uint8List>(
    'forestAmpelFine', _fillCombinedFine,
    params: forestFillParamsCodec, result: wireBytes, slots: _forestSlots);

List<ForestGrid> _blocksOf(MapWorkerSlots slots, ForestFillParams p) =>
    [for (final key in p.blocks) slots.get<ForestGrid>(key)];

Uint8List _fillCombined(MapWorkerSlots slots, ForestFillParams p) =>
    _combined(slots, [slots.get<ForestGrid>('forest')], p);

Uint8List _fillCombinedFine(MapWorkerSlots slots, ForestFillParams p) =>
    _combined(slots, _blocksOf(slots, p), p);

Uint8List _combined(
        MapWorkerSlots slots, List<ForestGrid> grids, ForestFillParams p) =>
    forestAmpelFillPng(grids,
        window: p.window,
        levels: slots.get<AmpelLevels>('ampelLevels'),
        ampelClasses: p.ampelClasses!,
        elevation: slots.get<ElevationGrid?>('elevation'),
        classes: p.classes,
        protected: slots.get<ProtectedAreas?>('protected'));

Uint8List _fill(MapWorkerSlots slots, ForestFillParams p) =>
    forestFillPng(slots.get<ForestGrid>('forest'),
        classes: p.classes,
        window: p.window,
        protected: slots.get<ProtectedAreas?>('protected'));

Uint8List _fillFine(MapWorkerSlots slots, ForestFillParams p) =>
    forestFillPngMulti(_blocksOf(slots, p),
        classes: p.classes,
        window: p.window,
        protected: slots.get<ProtectedAreas?>('protected'));

// ---------------------------------------------------------------------------
// Fundorte, Bereichs-Entwurf, Höhenlinien, Regenverlauf.

typedef GbifFillParams = ({FillWindow window, GbifPaint paint});

const gbifFillTask = MapWorkerTask<GbifFillParams, Uint8List>(
    'gbif', _gbif,
    params: WireFn(_writeGbifParams, _readGbifParams),
    result: wireBytes,
    slots: {'gbifFinds': WireSlot(gbifFindsCodec)});

Uint8List _gbif(MapWorkerSlots slots, GbifFillParams p) =>
    gbifFillPng(slots.get<GbifFinds>('gbifFinds'),
        window: p.window, paint: p.paint);

void _writeGbifParams(WireWriter w, GbifFillParams p) {
  fillWindowCodec.write(w, p.window);
  w.int32s(p.paint.colours);
  w.bytes(p.paint.allowed);
}

GbifFillParams _readGbifParams(WireReader r) => (
      window: fillWindowCodec.read(r),
      paint: (colours: r.int32s(), allowed: r.bytes()),
    );

typedef AreaEditParams = ({FillWindow window, Set<int> adds, Set<int> removes});

const areaEditFillTask = MapWorkerTask<AreaEditParams, Uint8List>(
    'areaEdit', _areaEdit,
    params: WireFn(_writeAreaParams, _readAreaParams),
    result: wireBytes,
    slots: {'areaStored': WireSlot(wireIntSet)});

Uint8List _areaEdit(MapWorkerSlots slots, AreaEditParams p) =>
    areaEditFillPng(
        window: p.window,
        stored: slots.get<Set<int>>('areaStored'),
        adds: p.adds,
        removes: p.removes);

void _writeAreaParams(WireWriter w, AreaEditParams p) {
  fillWindowCodec.write(w, p.window);
  wireIntSet.write(w, p.adds);
  wireIntSet.write(w, p.removes);
}

AreaEditParams _readAreaParams(WireReader r) => (
      window: fillWindowCodec.read(r),
      adds: wireIntSet.read(r),
      removes: wireIntSet.read(r),
    );

typedef ContourParams = ({FillWindow window, double metersPerPixel});

/// Linien UND ihr GeoJSON in einem Auftrag (#689, B2).
const contoursTask = MapWorkerTask<ContourParams, ElevationContours?>(
    'contours', _contours,
    params: WireFn(_writeContourParams, _readContourParams),
    result: WireNullable(elevationContoursCodec),
    slots: {'elevation': WireSlot(elevationGridCodec)});

ElevationContours? _contours(MapWorkerSlots slots, ContourParams p) {
  final contours = contourLinesFor(slots.get<ElevationGrid>('elevation'),
      window: p.window, metersPerPixel: p.metersPerPixel);
  if (contours == null || contours.lines.isEmpty) return contours;
  return ElevationContours(
    lines: contours.lines,
    equidistanceM: contours.equidistanceM,
    key: contours.key,
    geoJson: (
      normal: contourGeoJson(contours.lines, index: false),
      index: contourGeoJson(contours.lines, index: true),
    ),
  );
}

void _writeContourParams(WireWriter w, ContourParams p) {
  fillWindowCodec.write(w, p.window);
  w.float64(p.metersPerPixel);
}

ContourParams _readContourParams(WireReader r) =>
    (window: fillWindowCodec.read(r), metersPerPixel: r.float64());

typedef RainPoint = ({double lat, double lon});

const legendRainCourseTask = MapWorkerTask<RainPoint, RainCourse>(
    'legendRainCourse', _courseAt,
    params: WireFn(_writePoint, _readPoint),
    result: rainCourseCodec,
    slots: {'rainStacks': WireSlot(WireList(rainStackDataCodec))});

RainCourse _courseAt(MapWorkerSlots slots, RainPoint at) =>
    rainCoursesFromStacks(slots.get<List<RainStackData>>('rainStacks'),
        points: [at]).single;

void _writePoint(WireWriter w, RainPoint p) => w
  ..float64(p.lat)
  ..float64(p.lon);

RainPoint _readPoint(WireReader r) => (lat: r.float64(), lon: r.float64());

// ---------------------------------------------------------------------------
// Codecs der Typen. Jeder schreibt ALLE Felder — eine Rechnung, die im
// Worker ein vergessenes Feld liest, rechnete dort still etwas anderes.

const fillWindowCodec = WireFn<FillWindow>(_writeWindow, _readWindow);
void _writeWindow(WireWriter w, FillWindow v) => w
  ..float64(v.west)
  ..float64(v.east)
  ..float64(v.north)
  ..float64(v.south)
  ..int64(v.width)
  ..int64(v.height);
FillWindow _readWindow(WireReader r) => FillWindow(
      west: r.float64(),
      east: r.float64(),
      north: r.float64(),
      south: r.float64(),
      width: r.int64(),
      height: r.int64(),
    );

const forestFillParamsCodec =
    WireFn<ForestFillParams>(_writeForestParams, _readForestParams);
void _writeForestParams(WireWriter w, ForestFillParams p) {
  w.list(p.classes.toList(), (c) => w.u8(c.index));
  fillWindowCodec.write(w, p.window);
  w.nullable(p.ampelClasses, (l) => w.list(l, (c) => _writeAmpelClass(w, c)));
  w.list(p.blocks, w.string);
}

ForestFillParams _readForestParams(WireReader r) => (
      classes: {...r.list(() => ForestClass.values[r.u8()])},
      window: fillWindowCodec.read(r),
      ampelClasses: r.nullable(() => r.list(() => _readAmpelClass(r))),
      blocks: r.list(r.string),
    );

void _writeAmpelClass(WireWriter w, AmpelClass c) {
  w
    ..string(c.name)
    ..nullable(c.optimumC, w.float64)
    ..float64(c.verhaltenAbove)
    ..float64(c.guenstigAbove)
    ..nullable(
        c.logit,
        (l) => w
          ..float64(l.rain)
          ..float64(l.temp)
          ..float64(l.temp2)
          ..float64(l.moisture)
          ..float64(l.moistureTemp)
          ..float64(l.milder));
}

AmpelClass _readAmpelClass(WireReader r) => (
      name: r.string(),
      optimumC: r.nullable(r.float64),
      verhaltenAbove: r.float64(),
      guenstigAbove: r.float64(),
      logit: r.nullable(() => AmpelLogit(
            rain: r.float64(),
            temp: r.float64(),
            temp2: r.float64(),
            moisture: r.float64(),
            moistureTemp: r.float64(),
            milder: r.float64(),
          )),
    );

const forestGridCodec = WireFn<ForestGrid>(_writeForest, _readForest);
void _writeForest(WireWriter w, ForestGrid g) => w
  ..bytes(g.values)
  ..int64(g.width)
  ..int64(g.height)
  ..float64(g.west)
  ..float64(g.east)
  ..float64(g.north)
  ..float64(g.south)
  ..int64(g.referenceYear)
  ..nullable(g.hexLonStep, w.float64)
  ..nullable(g.hexLatStep, w.float64);
ForestGrid _readForest(WireReader r) => ForestGrid(
      values: r.bytes(),
      width: r.int64(),
      height: r.int64(),
      west: r.float64(),
      east: r.float64(),
      north: r.float64(),
      south: r.float64(),
      referenceYear: r.int64(),
      hexLonStep: r.nullable(r.float64),
      hexLatStep: r.nullable(r.float64),
    );

const elevationGridCodec =
    WireFn<ElevationGrid>(_writeElevation, _readElevation);
void _writeElevation(WireWriter w, ElevationGrid g) => w
  ..bytes(g.values)
  ..int64(g.width)
  ..int64(g.height)
  ..float64(g.west)
  ..float64(g.east)
  ..float64(g.north)
  ..float64(g.south)
  ..float64(g.hexLonStep)
  ..float64(g.hexLatStep);
ElevationGrid _readElevation(WireReader r) => ElevationGrid(
      values: r.bytes(),
      width: r.int64(),
      height: r.int64(),
      west: r.float64(),
      east: r.float64(),
      north: r.float64(),
      south: r.float64(),
      hexLonStep: r.float64(),
      hexLatStep: r.float64(),
    );

const protectedAreasCodec =
    WireFn<ProtectedAreas>(_writeProtected, _readProtected);
void _writeProtected(WireWriter w, ProtectedAreas p) => w
  ..int64(p.width)
  ..int64(p.height)
  ..float64(p.west)
  ..float64(p.north)
  ..float64(p.lonStep)
  ..float64(p.latStep)
  ..list(p.rows, w.uint16s)
  ..list(
      p.areas,
      (a) => w
        ..u8(a.kind.index)
        ..string(a.name))
  ..nullable(p.extract, w.string);
ProtectedAreas _readProtected(WireReader r) => ProtectedAreas(
      width: r.int64(),
      height: r.int64(),
      west: r.float64(),
      north: r.float64(),
      lonStep: r.float64(),
      latStep: r.float64(),
      rows: r.list(r.uint16s),
      areas: r.list(() => ProtectedArea(
          kind: ProtectedKind.values[r.u8()], name: r.string())),
      extract: r.nullable(r.string),
    );

const ampelLevelsCodec = WireFn<AmpelLevels>(_writeLevels, _readLevels);
void _writeLevels(WireWriter w, AmpelLevels l) => w.list(
    l.grids,
    (g) => w
      ..float32s(g.rainFactor)
      ..float32s(g.meanC)
      ..int16s(g.stationHeightM)
      ..bytes(g.valid)
      ..nullable(g.moistureMean, w.float32s)
      ..nullable(g.moistureValid, w.bytes)
      ..nullable(g.milder, w.float32s)
      ..nullable(g.milderValid, w.bytes)
      ..int64(g.width)
      ..int64(g.height)
      ..float64(g.west)
      ..float64(g.east)
      ..float64(g.north)
      ..float64(g.south)
      ..dateTime(g.newest));
AmpelLevels _readLevels(WireReader r) => AmpelLevels(r.list(() =>
    AmpelLevelGrid(
      rainFactor: r.float32s(),
      meanC: r.float32s(),
      stationHeightM: r.int16s(),
      valid: r.bytes(),
      moistureMean: r.nullable(r.float32s),
      moistureValid: r.nullable(r.bytes),
      milder: r.nullable(r.float32s),
      milderValid: r.nullable(r.bytes),
      width: r.int64(),
      height: r.int64(),
      west: r.float64(),
      east: r.float64(),
      north: r.float64(),
      south: r.float64(),
      newest: r.dateTime(),
    )));

const gbifFindsCodec = WireFn<GbifFinds>(_writeGbif, _readGbif);
void _writeGbif(WireWriter w, GbifFinds f) => w
  ..bytes(f.speciesIndex)
  ..uint16s(f.latQ)
  ..uint16s(f.lonQ)
  ..uint16s(f.uncertaintyM)
  ..bytes(f.count)
  ..bytes(f.yearOffset)
  ..list(
      f.species,
      (s) => w
        ..string(s.name)
        ..string(s.sci)
        ..int64(s.observations))
  ..list(
      f.datasets,
      (d) => w
        ..string(d.key)
        ..string(d.title)
        ..int64(d.observations))
  ..list(
      f.countries.entries.toList(),
      (e) => w
        ..string(e.key)
        ..int64(e.value))
  ..float64(f.west)
  ..float64(f.east)
  ..float64(f.north)
  ..float64(f.south)
  ..int64(f.observations)
  ..int64(f.unknownUncertaintyM)
  ..nullable(f.doi, w.string)
  ..nullable(f.fetchedOn, w.string);
GbifFinds _readGbif(WireReader r) => GbifFinds(
      speciesIndex: r.bytes(),
      latQ: r.uint16s(),
      lonQ: r.uint16s(),
      uncertaintyM: r.uint16s(),
      count: r.bytes(),
      yearOffset: r.bytes(),
      species: r.list(() =>
          (name: r.string(), sci: r.string(), observations: r.int64())),
      datasets: r.list(() =>
          (key: r.string(), title: r.string(), observations: r.int64())),
      countries: {
        for (final e in r.list(() => MapEntry(r.string(), r.int64())))
          e.key: e.value,
      },
      west: r.float64(),
      east: r.float64(),
      north: r.float64(),
      south: r.float64(),
      observations: r.int64(),
      unknownUncertaintyM: r.int64(),
      doi: r.nullable(r.string),
      fetchedOn: r.nullable(r.string),
    );

const rainStackDataCodec = WireFn<RainStackData>(_writeStack, _readStack);
void _writeDays(WireWriter w, List<({DateTime date, List<int> gzipped})> l) =>
    w.list(
        l,
        (d) => w
          ..dateTime(d.date)
          ..bytes(d.gzipped is Uint8List
              ? d.gzipped as Uint8List
              : Uint8List.fromList(d.gzipped)));
List<({DateTime date, List<int> gzipped})> _readDays(WireReader r) =>
    r.list(() => (date: r.dateTime(), gzipped: r.bytes()));
void _writeStack(WireWriter w, RainStackData s) {
  final i = s.info;
  w
    ..int64(i.width)
    ..int64(i.height)
    ..float64(i.west)
    ..float64(i.east)
    ..float64(i.north)
    ..float64(i.south)
    ..list(
        i.days,
        (d) => w
          ..dateTime(d.date)
          ..string(d.file)
          ..nullable(d.sha256, w.string)
          ..nullable(d.origin, w.string)
          ..nullable(d.originSha256, w.string));
  _writeDays(w, s.days);
  w.u8(s.kind.index);
  _writeDays(w, s.origins);
}

RainStackData _readStack(WireReader r) => RainStackData(
      info: RainStackInfo(
        width: r.int64(),
        height: r.int64(),
        west: r.float64(),
        east: r.float64(),
        north: r.float64(),
        south: r.float64(),
        days: r.list(() => RainStackDay(
              date: r.dateTime(),
              file: r.string(),
              sha256: r.nullable(r.string),
              origin: r.nullable(r.string),
              originSha256: r.nullable(r.string),
            )),
      ),
      days: _readDays(r),
      kind: RainStackKind.values[r.u8()],
      origins: _readDays(r),
    );

const rainCourseCodec = WireFn<RainCourse>(_writeCourse, _readCourse);
void _writeCourse(WireWriter w, RainCourse c) => w.list(
    c.days,
    (d) => w
      ..dateTime(d.date)
      ..nullable(d.mm, w.int64)
      ..u8(d.source.index)
      ..int64(d.origin));
RainCourse _readCourse(WireReader r) => RainCourse(r.list(() => RainDay(
      date: r.dateTime(),
      mm: r.nullable(r.int64),
      source: RainSource.values[r.u8()],
      origin: r.int64(),
    )));

/// Punkte als EINE Zahlenfolge statt je ein Objekt — bei 40 000 Punkten
/// der Unterschied zwischen einem Feld und 80 000 Einträgen.
const elevationContoursCodec =
    WireFn<ElevationContours>(_writeContours, _readContours);
void _writeContours(WireWriter w, ElevationContours c) {
  w.list(c.lines, (l) {
    final flat = Float64List(l.points.length * 2);
    for (var i = 0; i < l.points.length; i++) {
      flat[2 * i] = l.points[i].latitude;
      flat[2 * i + 1] = l.points[i].longitude;
    }
    w
      ..int64(l.level)
      ..float64s(flat)
      ..int64(l.cells)
      ..boolean(l.index);
  });
  w
    ..int64(c.equidistanceM)
    ..string(c.key)
    ..nullable(
        c.geoJson,
        (g) => w
          ..string(g.normal)
          ..string(g.index));
}

ElevationContours _readContours(WireReader r) {
  final lines = r.list(() {
    final level = r.int64();
    final flat = r.float64s();
    return ContourLine(
      level: level,
      points: List.generate(
          flat.length ~/ 2, (i) => LatLng(flat[2 * i], flat[2 * i + 1]),
          growable: false),
      cells: r.int64(),
      index: r.boolean(),
    );
  });
  return ElevationContours(
    lines: lines,
    equidistanceM: r.int64(),
    key: r.string(),
    geoJson: r.nullable(() => (normal: r.string(), index: r.string())),
  );
}
