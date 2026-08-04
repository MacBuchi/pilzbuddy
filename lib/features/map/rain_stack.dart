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
import 'rain_grid.dart';

/// Ein Tag des Verlaufs.
class RainDay {
  const RainDay({required this.date, required this.mm});

  /// Der Tag, den diese Summe abdeckt (00–24 UTC beim DWD-Produkt).
  final DateTime date;

  /// Millimeter an diesem Punkt — `null`, wo keine Messung liegt (der
  /// Spot liegt außerhalb des Radarverbunds).
  final int? mm;
}

/// Der Verlauf an einem Punkt, ältester Tag zuerst.
class RainCourse {
  const RainCourse(this.days);

  final List<RainDay> days;

  bool get isEmpty => days.isEmpty;

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
/// Nimmt die Tage **gepackt** und packt einen nach dem anderen aus. Das
/// ist der Grund für diesen Zuschnitt: Alle vierzehn gleichzeitig
/// auszupacken wären gut zehn Megabyte im Speicher für am Ende vierzehn
/// Zahlen — in einer App mit Speicherdruck-Geschichte (#142/#151) kein
/// vertretbarer Preis. So steht nie mehr als ein Tag entpackt da.
///
/// Jeder Tag fragt über [RainGrid.mmAt] selbst, statt Zeile und Spalte
/// einmal auszurechnen und wiederzuverwenden: Das ist die eine Stelle,
/// die weiß, dass die Zeile in Mercator liegt und nicht in Grad — zwei
/// Wege dorthin wären zwei Wege, die auseinanderlaufen können.
///
/// Ein Tag, der sich nicht auspacken lässt, wird zu einem Tag ohne Wert
/// statt zu einem Fehler. Eine kaputte Datei soll den Verlauf nicht
/// mitnehmen; sie macht nur das Fenster, in dem sie liegt, ungültig.
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
}) {
  final sorted = [...days]..sort((a, b) => a.date.compareTo(b.date));
  return RainCourse([
    for (final day in sorted)
      RainDay(
        date: day.date,
        mm: _valueAt(day, width, height, west, east, north, south, lat, lon),
      ),
  ]);
}

int? _valueAt(({DateTime date, List<int> gzipped}) day, int width, int height,
    double west, double east, double north, double south, double lat,
    double lon) {
  try {
    return RainGrid.decode(
      day.gzipped,
      width: width,
      height: height,
      west: west,
      east: east,
      north: north,
      south: south,
      measured: day.date,
    ).mmAt(lat, lon);
  } catch (_) {
    return null;
  }
}
