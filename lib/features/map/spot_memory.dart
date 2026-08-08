// Die Spot-Erinnerung — Baustein C des Ampel-Konzepts
// (docs/pilzampel-konzept.md): „dein Spot war letztes Jahr um diese Zeit
// ergiebig".
//
// Bewusst der ERSTE gebaute Teil des Komplexes, unabhängig vom Ausgang
// der Modell-Validierung: keine Prognose, sondern die eigene Historie —
// das Konzept nennt sie den ehrlichsten Teil. Kein Netz, kein Schema,
// keine neue Berechtigung; die Fundhistorie liegt nach dem App-Start
// ohnehin im Speicher (`mySpotListProvider`) und funktioniert damit auch
// offline im Wald.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/spot.dart';
import '../spots/spot_providers.dart';

/// Wie weit „um diese Zeit" reicht: ±14 Tage um das heutige Datum.
///
/// Dasselbe Fenster wie der Mindestabstand der Ampel-Validierung — nah
/// genug, dass die Saison vergleichbar ist, weit genug, dass ein um eine
/// Woche verschobenes Pilzjahr die Erinnerung nicht verpasst.
const spotMemoryWindowDays = 14;

/// Eine Erinnerung: Spot, Fundzahl im Fenster, die Art (nur wenn alle
/// Fenster-Funde dieselbe tragen) und das jüngste Jahr, aus dem sie
/// stammen.
typedef SpotMemory = ({Spot spot, int count, String? species, int year});

/// Der ergiebigste eigene Spot früherer Jahre im Zeitfenster um [today]
/// — oder `null`, wenn keiner passt.
///
/// Gezählt werden [Spot.ownFinds]: eigene ECHTE Funde. Leergänge sind
/// per Definition keine Erinnerung wert, und fremde Funde auf geteilten
/// Spots sind die Erinnerung des Buddys, nicht die eigene. Funde des
/// LAUFENDEN Jahres zählen nicht — was vor drei Wochen war, weiß man
/// noch; die Erinnerung gilt dem, was ein Jahr oder länger her ist.
///
/// Bei mehreren Kandidaten gewinnt die höhere Fundzahl im Fenster,
/// bei Gleichstand das jüngere Jahr.
SpotMemory? spotMemoryOf(List<Spot> spots, DateTime today) {
  SpotMemory? best;
  for (final spot in spots) {
    final inWindow = [
      for (final find in spot.ownFinds)
        if (find.foundOn.year < today.year &&
            _daysAroundSameDate(find.foundOn, today) <= spotMemoryWindowDays)
          find,
    ];
    if (inWindow.isEmpty) continue;
    final species = inWindow.map((f) => f.species).toSet();
    final year = inWindow.map((f) => f.foundOn.year).reduce(
        (a, b) => a > b ? a : b);
    final candidate = (
      spot: spot,
      count: inWindow.length,
      species: species.length == 1 ? species.single : null,
      year: year,
    );
    if (best == null ||
        candidate.count > best.count ||
        (candidate.count == best.count && candidate.year > best.year)) {
      best = candidate;
    }
  }
  return best;
}

/// Abstand zweier Kalendertage OHNE das Jahr — mit Jahreswende:
/// Der 28. Dezember liegt 8 Tage neben dem 5. Januar, nicht 357.
int _daysAroundSameDate(DateTime a, DateTime b) {
  final sameYear = DateTime.utc(b.year, a.month, a.day);
  final direct = sameYear.difference(DateTime.utc(b.year, b.month, b.day))
      .inDays
      .abs();
  return direct <= 182 ? direct : 365 - direct;
}

/// Die aktuelle Erinnerung — `null`, wenn es nichts zu erinnern gibt.
final spotMemoryProvider = Provider<SpotMemory?>((ref) =>
    spotMemoryOf(ref.watch(mySpotListProvider), DateTime.now()));
