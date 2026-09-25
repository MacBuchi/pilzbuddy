// Der Tagesverlauf am Spot: vierzehn Tagessummen statt einer Zahl.
//
// **Warum überhaupt.** Eine Summe kann nicht unterscheiden, ob die 40 mm
// vor elf Tagen oder gestern fielen — und für Pilze ist genau das der
// Unterschied. „100 mm in 30 Tagen" ist die Forums-Faustregel, aber sie
// ist blind dafür, ob der Boden gerade durchfeuchtet oder längst wieder
// hart ist. Der Verlauf zeigt es, eine Zahl nie.
//
// Rein und ohne I/O: Was hier steht, lässt sich an einem Mini-Gitter von
// Hand nachrechnen. Das Laden liegt in `rain_grid_repository.dart`.
import 'dart:collection';

import '../../data/rain_grid_repository.dart' show RainStackData, RainStackKind;
import 'rain_grid.dart';

/// Ein Tag des Verlaufs.
/// Woher ein Tageswert stammt (seit 1.212.0, #612): aus dem Radar des
/// DWD oder aus dem Modellgitter des Alpenraums (`tool/model_weather.py`).
/// Das Blatt sagt es dazu — ein Modellwert, der aussieht wie ein
/// Messwert, wäre eine Behauptung.
enum RainSource { radar, model }

class RainDay {
  const RainDay(
      {required this.date, required this.mm, this.source = RainSource.radar});

  /// Der Tag, den diese Summe abdeckt (00–24 UTC beim DWD-Produkt).
  final DateTime date;

  /// Millimeter an diesem Punkt — `null`, wo keine Messung liegt (der
  /// Spot liegt außerhalb des Radarverbunds UND außerhalb des Modellgitters).
  final int? mm;

  /// Das Instrument hinter [mm]; ohne Wert bedeutungslos.
  final RainSource source;
}

/// Der Verlauf an einem Punkt, ältester Tag zuerst.
class RainCourse {
  const RainCourse(this.days);

  final List<RainDay> days;

  bool get isEmpty => days.isEmpty;

  /// Tage mit Wert — und wie viele davon aus dem Modell kommen. Beides
  /// zusammen sagt dem Blatt, was es unter das Diagramm schreibt.
  int get measuredDays => days.where((d) => d.mm != null).length;
  int get modelDays => days
      .where((d) => d.mm != null && d.source == RainSource.model)
      .length;

  /// Die letzten [count] Tage als eigener Verlauf. Seit der Stapel die
  /// 26 Ampel-Tage trägt (#256), bleibt die ANZEIGE trotzdem beim
  /// gewohnten 14-Tage-Fenster — 26 Balken auf Handybreite wären
  /// Streichhölzer; die zusätzlichen Tage füttern das Modell, nicht
  /// das Auge.
  RainCourse lastDays(int count) => days.length <= count
      ? this
      : RainCourse(days.sublist(days.length - count));

  /// Der jüngste Tag, den der Verlauf kennt. Das ist **gestern**, nicht
  /// heute: Das DWD-Tagesprodukt summiert abgeschlossene Tage.
  DateTime? get newest => days.isEmpty ? null : days.last.date;

  /// Die Summe der letzten [count] Tage — `null`, sobald einer davon
  /// keine Messung hat.
  ///
  /// Bewusst nicht „Summe der bekannten Tage": Ein Spot am Rand des
  /// Radarverbunds bekäme sonst eine Zahl, die kleiner ist als die
  /// Wirklichkeit, und niemand könnte ihr ansehen, dass sie unvollständig
  /// ist. Lieber keine Zahl als eine zu niedrige.
  int? sumOfLast(int count) {
    if (days.length < count) return null;
    var total = 0;
    for (final day in days.sublist(days.length - count)) {
      if (day.mm == null) return null;
      total += day.mm!;
    }
    return total;
  }

  /// Der größte Tageswert — der Maßstab für die Balken.
  int get peak {
    var most = 0;
    for (final day in days) {
      final mm = day.mm;
      if (mm != null && mm > most) most = mm;
    }
    return most;
  }

  /// Wie viele Tage seit dem letzten nennenswerten Regen vergangen sind,
  /// oder `null`, wenn es im ganzen Verlauf keinen gab.
  ///
  /// 0 heißt „gestern", denn weiter reicht das Tagesprodukt nicht.
  /// [threshold] ist bewusst nicht 0: Ein Millimeter Nieselregen macht
  /// keinen Boden nass, zählte aber als „gestern hat es geregnet".
  int? daysSinceRain({int threshold = 3}) {
    for (var i = days.length - 1; i >= 0; i--) {
      final mm = days[i].mm;
      if (mm != null && mm >= threshold) return days.length - 1 - i;
    }
    return null;
  }
}

/// Liest denselben Punkt aus jedem Tag des Stapels.
///
/// Der Weg des Spot-Blatts: ein Punkt, 26 Tage. Der Zuschnitt — Tage
/// **gepackt** hereinnehmen und einen nach dem anderen auspacken —
/// steckt in [rainCoursesFrom], das hier ist der Sonderfall mit genau
/// einem Punkt. Beide Wege durch dieselbe Funktion, damit sie nicht
/// auseinanderlaufen können.
RainCourse rainCourseFrom(
  List<({DateTime date, List<int> gzipped})> days, {
  required int width,
  required int height,
  required double west,
  required double east,
  required double north,
  required double south,
  required double lat,
  required double lon,
}) =>
    rainCoursesFrom(
      days,
      width: width,
      height: height,
      west: west,
      east: east,
      north: north,
      south: south,
      points: [(lat: lat, lon: lon)],
    ).single;

/// Dasselbe für MEHRERE Punkte — und zwar mit **einer** Dekodierung je
/// Tag statt einer je Tag und Punkt.
///
/// Der Anlass, gemessen am 2026-08-23 (`test/perf_grid_decode_measure.dart`,
/// Zahlen in `docs/map-performance.md`): Ein Tagesgitter sind 752 000
/// Zellen, und [rainCourseFrom] packte für jeden Punkt alle 26 davon
/// vollständig aus — um je Tag EIN Byte zu lesen. Neunzehn Spots waren
/// damit 494 Dekodierungen für 494 gelesene Bytes, knapp drei Sekunden
/// auf einem schnellen Rechner. So sind es 26 Dekodierungen, unabhängig
/// von der Zahl der Punkte.
///
/// **Die Speicher-Eigenschaft des Einzelwegs bleibt erhalten**, und das
/// ist keine Nebensache: Es steht weiterhin nie mehr als EIN Tag
/// entpackt da (752 KB), weil die Schleife über die Tage außen liegt und
/// die Punkte innen. Alle 26 gleichzeitig wären 18 MB — in einer App mit
/// Speicherdruck-Geschichte (#142/#151) kein vertretbarer Preis, und
/// genau deshalb ist die Reihenfolge der beiden Schleifen hier eine
/// Aussage und kein Zufall.
///
/// Dieselbe Bauform benutzt die Ampel-Fläche längst
/// (`ampel_fill.dart`): je Tag einmal dekodieren, daraus alle Zellen
/// abtasten. Der Spot-Weg war der einzige, der ihr nicht folgte.
///
/// Die Reihenfolge der Rückgabe entspricht der von [points].
List<RainCourse> rainCoursesFrom(
  List<({DateTime date, List<int> gzipped})> days, {
  required int width,
  required int height,
  required double west,
  required double east,
  required double north,
  required double south,
  required List<({double lat, double lon})> points,
}) {
  final sorted = [...days]..sort((a, b) => a.date.compareTo(b.date));
  final perPoint = [for (final _ in points) <RainDay>[]];

  for (final day in sorted) {
    // Ein Tag, der sich nicht auspacken lässt, wird zu einem Tag ohne
    // Wert statt zu einem Fehler. Eine kaputte Datei soll den Verlauf
    // nicht mitnehmen; sie macht nur das Fenster, in dem sie liegt,
    // ungültig — und zwar für alle Punkte gleichermaßen.
    RainGrid? grid;
    try {
      grid = RainGrid.decode(
        day.gzipped,
        width: width,
        height: height,
        west: west,
        east: east,
        north: north,
        south: south,
        measured: day.date,
      );
    } catch (_) {
      grid = null;
    }

    for (var i = 0; i < points.length; i++) {
      perPoint[i].add(RainDay(date: day.date, mm: _valueAt(grid, points[i])));
    }
  }

  return [for (final days in perPoint) RainCourse(days)];
}

/// Mehrere Stapel in VORRANG-Reihenfolge — das Radar zuerst, dann das
/// Modellgitter des Alpenraums (#612, seit 1.212.0). Je Tag und Punkt
/// gewinnt der erste Stapel, der einen Wert hat; ein Tag, den keiner
/// kennt, bleibt `null`. Die Vereinigung der Tage beider Stapel bildet
/// die Achse: Das Modell hat oft den jüngsten Tag früher als das Radar,
/// und ein Spot in Südtirol liegt in gar keinem Radar-Tag.
///
/// Warum nicht EIN zusammengeführtes Gitter: Die beiden haben
/// verschiedene Geometrien (1 km gegen 12 km), und ein Umrastern wäre
/// eine dritte Antwort auf „wie viel Regen an diesem Punkt".
List<RainCourse> rainCoursesFromStacks(
  List<RainStackData> stacks, {
  required List<({double lat, double lon})> points,
}) {
  if (stacks.isEmpty) return [for (final _ in points) const RainCourse([])];
  final perStack = [
    for (final stack in stacks)
      rainCoursesFrom(
        stack.days,
        width: stack.info.width,
        height: stack.info.height,
        west: stack.info.west,
        east: stack.info.east,
        north: stack.info.north,
        south: stack.info.south,
        points: points,
      ),
  ];
  final dates = SplayTreeSet<DateTime>();
  for (final courses in perStack) {
    for (final day in courses.first.days) {
      dates.add(day.date);
    }
  }
  final merged = <RainCourse>[];
  for (var p = 0; p < points.length; p++) {
    final byDate = [
      for (final courses in perStack)
        {for (final day in courses[p].days) day.date: day.mm},
    ];
    merged.add(RainCourse([
      for (final date in dates)
        () {
          for (var s = 0; s < stacks.length; s++) {
            final mm = byDate[s][date];
            if (mm != null) {
              return RainDay(
                  date: date,
                  mm: mm,
                  source: stacks[s].kind == RainStackKind.model
                      ? RainSource.model
                      : RainSource.radar);
            }
          }
          return RainDay(date: date, mm: null);
        }(),
    ]));
  }
  return merged;
}

/// Jeder Punkt fragt über [RainGrid.mmAt] selbst, statt Zeile und Spalte
/// einmal auszurechnen und wiederzuverwenden: Das ist die eine Stelle,
/// die weiß, dass die Zeile in Mercator liegt und nicht in Grad — zwei
/// Wege dorthin wären zwei Wege, die auseinanderlaufen können.
int? _valueAt(RainGrid? grid, ({double lat, double lon}) at) {
  if (grid == null) return null;
  try {
    return grid.mmAt(at.lat, at.lon);
  } catch (_) {
    return null;
  }
}
