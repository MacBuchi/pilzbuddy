// Der Reiter „Spots" (#509): die Listenansicht der Karte.
//
// **Was die Liste beantwortet, was die Karte nicht kann.** Die Karte
// zeigt, WO etwas liegt; wer einen Spot wiederfinden will, muss seinen
// Marker treffen. Die Liste zeigt, WANN zuletzt etwas passiert ist —
// und zwar über alle Spots auf einmal, eigene wie geteilte.
//
// **Sortiert wird nach dem jüngsten EINTRAG, nicht nach dem jüngsten
// Fund.** Ein Leergang ist Aktivität: „am 12.9. war ich da, es war
// nichts da" ist genau die Auskunft, die einen Spot nach hinten rutschen
// lässt. Die Trennlinie aus #211 gilt trotzdem weiter — was ein FUND
// ist, entscheidet [Spot.findsSorted], und die Statistik zählt nur die.
//
// **Vorgemerkte Spots (#499) stehen in einer eigenen Gruppe am Ende**,
// nicht oben und nicht dazwischen: Sie haben keinen Eintrag und damit
// kein Datum, mit dem sie sich einsortieren ließen. `spots.created_at`
// dafür zu holen hieße, die Abfrage und damit `schema_check.sh` zu
// ändern — für eine Sortierung innerhalb einer Handvoll Zeilen.
//
// **Und eine DRITTE Gruppe, die es nur wegen der Freigaben gibt.** Ein
// Buddy-Spot ohne `share_details` kommt ohne einen einzigen Eintrag an
// (RLS, Patch 014) — von außen sieht er damit aus wie eine Vormerkung.
// Ihn so zu beschriften wäre erfunden; die Karte umgeht das seit #499
// mit `spot.isOwn && spot.isPlanned` am Marker. Hier steht er deshalb
// unter einer eigenen Überschrift, die sagt, was Sache ist, statt die
// Zeile leer zu lassen: „kein Fehler ohne Fehlermeldung".
//
// Hier rechnet nichts mit Widgets, damit die Sortierung prüfbar bleibt
// (Muster: `species_catalogue.dart`).
import '../../core/mushroom_species.dart';
import '../../models/find.dart';
import '../../models/spot.dart';
import '../map/spot_filter.dart' show spotSpeciesNames;

/// Wessen Spots die Liste zeigt. „Alle" ist die Vorgabe — die Liste ist
/// die Karte als Liste, und die zeigt auch beides.
enum SpotOwnerFilter {
  all('Alle'),
  mine('Meine'),
  buddies('Buddys');

  const SpotOwnerFilter(this.label);

  final String label;
}

/// Eine Zeile: ein Spot mit dem, was man über ihn auf einen Blick
/// wissen will.
///
/// [species] und [lastEntry] beschreiben den SPOT und nehmen deshalb
/// auch fremde Einträge mit — dieselbe Regel wie beim Marker-Icon und
/// beim Blattkopf. Wo es um meine Daten geht, zählt die Statistik, und
/// die sieht nur `ownFinds`.
class SpotRow {
  const SpotRow({
    required this.spot,
    required this.lastEntry,
    required this.entryCount,
    required this.species,
    required this.hasNews,
    required this.waiting,
  });

  final Spot spot;

  /// Der jüngste Eintrag — Fund ODER Leergang. `null` heißt: keiner zu
  /// sehen, also eine Vormerkung oder ein Buddy ohne Detail-Freigabe.
  final Find? lastEntry;

  /// Alle Einträge des Spots, Leergänge eingeschlossen.
  final int entryCount;

  /// Die Arten des Spots, kanonisch und ohne Wiederholung; bei einer
  /// Vormerkung die erwarteten.
  final List<String> species;

  /// Hat hier ein Buddy etwas eingetragen, das ich noch nicht gesehen
  /// habe? Die Entscheidung darüber fällt NICHT hier, sondern in
  /// `newBuddyFindsProvider` — es gibt genau einen „gesehen bis"-Marker,
  /// und der gehört dem Karten-Banner (#202, #425).
  final bool hasNews;

  /// Wartet an diesem Spot noch etwas auf die Übertragung (#267)? Der
  /// Spot selbst oder einer seiner Einträge.
  final bool waiting;

  /// Eine Vormerkung (#499): kein Eintrag, aber jemand hat
  /// aufgeschrieben, wonach er dort sehen will.
  bool get isPlanned =>
      lastEntry == null && (spot.isOwn || spot.expectedSpecies.isNotEmpty);

  /// Ein Buddy-Spot, von dem nichts zu sehen ist — siehe Kopf der Datei.
  bool get isSilent => lastEntry == null && !isPlanned;

  /// Datum, nach dem sortiert wird.
  DateTime? get lastAt => lastEntry?.foundOn;
}

/// Die Liste, fertig sortiert und gefiltert.
///
/// [spotsWithNews] sind die Spot-ids aus `newBuddyFindsProvider`.
({List<SpotRow> active, List<SpotRow> planned, List<SpotRow> silent}) spotList({
  required List<Spot> mine,
  required List<Spot> friends,
  SpotOwnerFilter owner = SpotOwnerFilter.all,
  String query = '',
  Set<String> spotsWithNews = const {},
}) {
  final rows = <SpotRow>[];
  for (final spot in [...mine, ...friends]) {
    if (owner == SpotOwnerFilter.mine && !spot.isOwn) continue;
    if (owner == SpotOwnerFilter.buddies && spot.isOwn) continue;
    if (!_matches(spot, query)) continue;
    final entries = spot.entriesSorted;
    rows.add(SpotRow(
      spot: spot,
      lastEntry: entries.isEmpty ? null : entries.first,
      entryCount: entries.length,
      species: _speciesOf(spot),
      hasNews: spotsWithNews.contains(spot.id),
      waiting: spot.pending || entries.any((e) => e.pending),
    ));
  }

  final active = [for (final row in rows) if (row.lastEntry != null) row];
  final planned = [for (final row in rows) if (row.isPlanned) row];
  final silent = [for (final row in rows) if (row.isSilent) row];
  // Gleiches Datum kommt häufiger vor, als man denkt: Ein Fund trägt
  // nur den TAG. Der Name als zweites Kriterium hält die Reihenfolge
  // über Neuaufbauten hinweg stabil — ohne ihn tauschten zwei Spots
  // vom selben Tag bei jedem Abruf die Plätze.
  active.sort((a, b) {
    final byDate = b.lastAt!.compareTo(a.lastAt!);
    return byDate != 0 ? byDate : _byName(a, b);
  });
  planned.sort(_byName);
  silent.sort(_byName);
  return (active: active, planned: planned, silent: silent);
}

/// „heute", „gestern", „vor 3 Tagen" — oder `null`, wenn das Datum weit
/// genug zurückliegt, dass es als Datum gehört.
///
/// Die Grenze liegt bei einer Woche: Danach sagt „vor 9 Tagen" weniger
/// als „12.9.2026", weil man ab da ohnehin nachrechnet. Ein Datum in der
/// Zukunft (nachgetragener Fund mit vertipptem Jahr) bekommt ebenfalls
/// sein Datum — „vor -4 Tagen" wäre der sichtbare Teil eines Tippfehlers.
String? relativeDay(DateTime date, DateTime today) {
  final days = DateTime(today.year, today.month, today.day)
      .difference(DateTime(date.year, date.month, date.day))
      .inDays;
  if (days < 0 || days >= 7) return null;
  if (days == 0) return 'heute';
  if (days == 1) return 'gestern';
  return 'vor $days Tagen';
}

int _byName(SpotRow a, SpotRow b) =>
    a.spot.displayName.toLowerCase().compareTo(b.spot.displayName.toLowerCase());

/// Die Arten eines Spots, kanonisch, in der Reihenfolge ihres jüngsten
/// Auftretens.
List<String> _speciesOf(Spot spot) {
  final seen = <String>{};
  final names = <String>[];
  for (final raw in spotSpeciesNames(spot)) {
    final name = canonicalSpecies(raw);
    if (name == null) continue;
    if (!seen.add(name.toLowerCase())) continue;
    names.add(name);
  }
  return names;
}

/// Sucht in Spot-Name, Arten und Buddy-Name.
///
/// Die Arten laufen über [foldSpeciesName] (#395): Wer „Staeubling"
/// tippt, sucht den Stäubling. Name und Buddy bleiben bei einfacher
/// Kleinschreibung — sie sind keine Artnamen, und die Faltung würfe dort
/// Leerzeichen weg, die man beim Tippen mit eingibt.
bool _matches(Spot spot, String query) {
  final needle = query.trim();
  if (needle.isEmpty) return true;
  final plain = needle.toLowerCase();
  if (spot.displayName.toLowerCase().contains(plain)) return true;
  if ((spot.ownerUsername ?? '').toLowerCase().contains(plain)) return true;
  final folded = foldSpeciesName(needle);
  if (folded.isEmpty) return false;
  for (final name in _speciesOf(spot)) {
    if (foldSpeciesName(name).contains(folded)) return true;
  }
  return false;
}
