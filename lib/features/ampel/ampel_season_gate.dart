// Das Saison-Tor je Klasse (#495) — rein, ohne Riverpod.
//
// Eine Klasse ist ein Temperaturfenster, gemessen im Case-Crossover:
// Fundtag gegen Vergleichstage DERSELBEN Saison. Die Saison kürzt sich
// dabei heraus; die Klasse sagt „Bedingungen passen innerhalb der
// Saison", nie „es ist die Saison". Und die Klassen sind gemischt:
// „Austernseitling & Co." trägt im September Krause Glucke und
// Leberpilz (Saisonanteil 100), der Austernseitling selbst liegt bei 3.
// Deshalb fragt die Fläche seit 1.157.0 je Klasse, ob überhaupt eine
// ihrer Arten gerade gemeldet wird — als TOR, nicht als Faktor (der
// Score bleibt, wie er validiert ist), und als Maximum über die
// Mitglieder (Betreiber, 2026-09-21). Bis dahin galt „kein Saison-Tor
// auf der Fläche", weil die Fläche keine Art kennt; das Maximum über
// die Mitglieder ist die Antwort darauf.
//
// Im Zweifel zeigen (#414-Regel): Eine Art ohne Kurve gilt als „hat
// Saison", eine Klasse ohne Kurven bleibt an.
import '../../core/season_curves.dart';
import 'ampel_model.dart';

/// Die Arten einer Klasse, in der Reihenfolge von [ampelSpeciesClass].
List<String> ampelMembersOf(String classKey) => [
      for (final entry in ampelSpeciesClass.entries)
        if (entry.value == classKey) entry.key,
    ];

/// Die Arten einer Klasse, die im Monat [month] Saison haben (oder keine
/// Kurve tragen) und nicht in [excluded] stehen.
List<String> ampelMembersInSeason(String classKey,
        {required int month, Set<String> excluded = const {}}) =>
    [
      for (final name in ampelMembersOf(classKey))
        if (!excluded.contains(name) &&
            (speciesInSeason(name, month) ?? true))
          name,
    ];

/// Ob eine Klasse gerade mitspielt: mindestens eine nicht ausgenommene
/// Art hat Saison. Sind alle Arten ausgenommen, ist die Klasse aus —
/// das ist der Weg, eine Gruppe ohne den Kartenfilter loszuwerden.
bool ampelClassActive(String classKey,
        {required int month, Set<String> excluded = const {}}) =>
    ampelMembersInSeason(classKey, month: month, excluded: excluded)
        .isNotEmpty;

/// Die aktiven Klassen aus einer Auswahl — dieselbe Reihenfolge, damit
/// „bei Gleichstand gewinnt die frühere Klasse" unverändert gilt.
List<AmpelClass> ampelActiveClasses(List<AmpelClass> selected,
        {required int month, Set<String> excluded = const {}}) =>
    [
      for (final klass in selected)
        if (ampelClassKeyOf(klass) case final key?)
          if (ampelClassActive(key, month: month, excluded: excluded)) klass,
    ];

/// Die Art, nach der die Klasse heißt („Austernseitling & Co." →
/// Austernseitling). Für die Frage, ob der Name gerade irreführt.
String ampelEponymOf(AmpelClass klass) => klass.name.split(' & ').first;

/// „jetzt: Krause Glucke, Leberpilz" — oder `null`, wenn der Namensgeber
/// selbst Saison hat und der Name also stimmt. Höchstens drei Namen,
/// der Rest als Zahl: Die Legende ist schmal.
String? ampelNowLine(AmpelClass klass,
    {required int month, Set<String> excluded = const {}}) {
  final key = ampelClassKeyOf(klass);
  if (key == null) return null;
  final now = ampelMembersInSeason(key, month: month, excluded: excluded);
  if (now.isEmpty || now.contains(ampelEponymOf(klass))) return null;
  final shown = now.take(3).join(', ');
  final rest = now.length - 3;
  return 'jetzt: $shown${rest > 0 ? ' +$rest' : ''}';
}
