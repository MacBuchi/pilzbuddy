// Was der Reiter „Pilze" zeigt — als Daten, ohne Widgets.
//
// **Der Katalog kommt aus dem Modellkern, nicht aus abgeschriebenem
// Text.** Welche Art zu welcher Ampel-Gruppe gehört, steht genau einmal
// (`ampelSpeciesClass`); die Saisonkurven liegen im Binary
// (`season_curves.g.dart`); die Evidenzstufe je Art ebenfalls. Hier wird
// nur zusammengesetzt. Eine von Hand gepflegte Liste wäre die Falle, die
// die Ebenen-Legende bis 1.140.0 selbst vorgeführt hat: Sie behauptete
// „für Steinpilz & Co.", während die Fläche längst alle Klassen rechnete.
//
// Rein und ohne Widgets, damit `test/species_catalogue_test.dart` die
// Zusage nachrechnen kann, an der der Reiter hängt: **Jede bekannte Art
// steht genau einmal darin** — entweder unter ihrer Gruppe oder unter
// „Ohne Ampel". Fehlte eine, sähe der Nutzer eine Art auf der Karte, die
// im Verzeichnis nicht vorkommt; stünde eine doppelt, gehörte sie zu
// zwei Gruppen, was das Modell ausschließt.
import '../../core/mushroom_species.dart';
import '../../core/season_curves.dart';
import '../../core/species_edibility.dart';
import '../../models/spot.dart';
import '../ampel/ampel_model.dart';
import '../map/gbif_finds.dart' show GbifSpeciesTotals;

/// Eine Art im Verzeichnis.
class CatalogueEntry {
  const CatalogueEntry({
    required this.name,
    required this.group,
    required this.curve,
    required this.share,
    required this.evidence,
    required this.edibility,
  });

  final String name;
  final SpeciesGroup group;

  /// Essbar oder giftig — `null` gibt es hier nicht, die Tabelle deckt
  /// jede bekannte Art ab (`test/species_edibility_test.dart`). Die
  /// LISTE zeigt davon nur die Warnung ([Edibility.warnsInList]); alles
  /// Weitere steht auf der Detailseite.
  final EdibilityEntry? edibility;

  /// Die belastbare Saisonkurve — `null` heißt „wir wissen es nicht",
  /// dieselbe Grenze wie in [seasonCurveFor].
  final SeasonCurve? curve;

  /// Die Höhe der Kurve im laufenden Monat, 0…100; `null` ohne Kurve.
  final int? share;

  /// `null` bei Arten ohne Ampel.
  final AmpelEvidence? evidence;

  /// Hat die Art jetzt Saison? Dieselbe Schwelle wie Filter und
  /// Banner-Nachlauf ([kSeasonNowThreshold]) — der Reiter hebt genau die
  /// Arten hervor, für die das Banner anschlagen könnte.
  bool get inSeason => share != null && share! >= kSeasonNowThreshold;

  /// „Hauptzeit", „Randzeit" … — `null` ohne Kurve.
  String? get seasonWord => share == null ? null : seasonShareWord(share!);
}

/// Ein Abschnitt: eine Ampel-Gruppe oder der Rest.
class CatalogueSection {
  const CatalogueSection({
    required this.title,
    required this.subtitle,
    required this.classKey,
    required this.entries,
  });

  final String title;
  final String subtitle;

  /// Der Schlüssel aus [ampelClasses], `null` für „Ohne Ampel".
  final String? classKey;
  final List<CatalogueEntry> entries;

  int get inSeasonCount => entries.where((e) => e.inSeason).length;
}

/// Der Titel des Abschnitts ohne Ampel — an einer Stelle, damit Test und
/// Bildschirm dasselbe Wort suchen.
const kCatalogueGreyTitle = 'Ohne Ampel';

/// Das Verzeichnis für den Monat [month] (1…12).
///
/// Reihenfolge: die Gruppen wie in [ampelClasses] (das ist die
/// Auslieferungsreihenfolge, in der sie auch in Legende und Filter
/// stehen), darin und im Rest die Arten wie in [kBekannteArten] — so
/// stehen sie auch in der Artenliste beim Eintragen.
List<CatalogueSection> speciesCatalogue({required int month}) {
  CatalogueEntry entryFor(KnownSpecies species) {
    final curve = seasonCurveFor(species.name);
    return CatalogueEntry(
      name: species.name,
      group: species.group,
      curve: curve,
      share: curve?.months[month - 1],
      evidence: ampelEvidenceFor(species.name),
      edibility: edibilityFor(species.name),
    );
  }

  // Zweitnamen erben über `sameAs` und stehen nicht eigens da.
  final species = kBekannteArten.where((s) => !s.isSynonym).toList();

  final sections = <CatalogueSection>[
    for (final klass in ampelClasses.entries)
      CatalogueSection(
        title: klass.value.name,
        subtitle: klass.value.optimumC == null
            ? 'Ampel aus ${ampelClassWindowWord(klass.value)}'
            : 'Ampel mit Temperaturfenster ${ampelClassWindowWord(klass.value)}',
        classKey: klass.key,
        entries: [
          for (final s in species)
            if (ampelSpeciesClass[s.name] == klass.key) entryFor(s),
        ],
      ),
    CatalogueSection(
      title: kCatalogueGreyTitle,
      subtitle: 'Für diese Arten sagt die Ampel nichts — noch ist an '
          'unabhängigen Daten nicht bestätigt, dass ein eigenes Fenster '
          'besser passt. Lieber grau als erfunden.',
      classKey: null,
      entries: [
        for (final s in species)
          if (ampelClassFor(s.name) == null) entryFor(s),
      ],
    ),
  ];
  return sections;
}

/// Was die Detailseite je Art zeigt (#511) — zusammengesetzt aus dem,
/// was ohnehin im Binary und im Spot-Cache liegt.
///
/// **Kein neues Wissen, nur ein zweiter Blick darauf.** Jedes Feld hier
/// hat schon eine Quelle: der wissenschaftliche Name und die Zweitnamen
/// stehen in `kBekannteArten`, die Kurve in `season_curves.g.dart`, die
/// Klasse in `ampelSpeciesClass`, die eigenen Funde im Cache und die
/// Meldungen im GBIF-Asset. Was NICHT dazugehört und warum, steht am
/// Kopf von `species_detail_screen.dart`.
class SpeciesDetail {
  const SpeciesDetail({
    required this.name,
    required this.group,
    required this.sci,
    required this.synonyms,
    required this.curve,
    required this.share,
    required this.klass,
    required this.classKey,
    required this.evidence,
    required this.edibility,
    required this.ownFinds,
    required this.ownSpots,
    required this.lastFound,
    required this.gbif,
  });

  /// Die Hauptbezeichnung — ein Zweitname in der Adresse landet hier
  /// aufgelöst, sonst gäbe es zwei Seiten für denselben Pilz.
  final String name;
  final SpeciesGroup group;

  /// `null` bei Arten ohne zweifelsfreie GBIF-Zuordnung. Die Seite sagt
  /// das, statt die Zeile wegzulassen: Ohne diesen Namen gibt es auch
  /// keine Kurve, und der Zusammenhang gehört genannt.
  final String? sci;

  /// „auch: Marone" — die Namen, unter denen die Eingabe dieselbe Art
  /// findet. Leer, wenn es keine gibt.
  final List<String> synonyms;

  final SeasonCurve? curve;

  /// Die Höhe der Kurve im laufenden Monat, 0…100; `null` ohne Kurve.
  final int? share;

  /// Die Ampel-Gruppe, `null` bei den grauen Arten.
  final AmpelClass? klass;
  final String? classKey;
  final AmpelEvidence? evidence;

  /// Essbar oder giftig, samt Freitext — siehe `species_edibility.dart`.
  final EdibilityEntry? edibility;

  /// **Nur EIGENE Funde**, dieselbe Grenze wie in der Statistik (#211):
  /// gezählt wird über `Spot.ownFinds`, nicht über `spot.finds`. Ein
  /// Buddy-Fund am eigenen Spot ist seine Ausbeute, nicht meine.
  final int ownFinds;

  /// An wie vielen Spots — die zweite Zahl, weil acht Funde an einem
  /// Spot etwas anderes sind als acht an acht.
  final int ownSpots;
  final DateTime? lastFound;

  /// Was GBIF meldet — `null` heißt „noch nicht geladen ODER nicht im
  /// Asset"; die beiden auseinanderzuhalten ist Sache der Seite.
  final GbifSpeciesTotals? gbif;

  bool get inSeason => share != null && share! >= kSeasonNowThreshold;
  String? get seasonWord => share == null ? null : seasonShareWord(share!);
}

/// Die Detailseite zu [name] — `null`, wenn die App die Art nicht kennt.
///
/// **`null` ist ein echter Fall und kein Fehler:** Die Route trägt den
/// Namen in der Adresse (`/pilze/Steinpilz`), und die kann aus einem
/// Lesezeichen kommen, aus dem Web oder aus einer Fassung, die eine Art
/// noch nicht hatte. Die Seite sagt dann, dass sie die Art nicht kennt,
/// statt mit einem `!` abzustürzen.
SpeciesDetail? speciesDetailFor(
  String name, {
  required int month,
  List<Spot> spots = const [],
  GbifSpeciesTotals? gbif,
}) {
  // Über die Hauptbezeichnung, wie überall: „Marone" und
  // „Maronenröhrling" sind eine Art und eine Seite.
  final entry = knownSpeciesFor(name);
  if (entry == null) return null;

  final curve = seasonCurveFor(entry.name);
  final klass = ampelClassFor(entry.name);

  var finds = 0;
  var spotCount = 0;
  DateTime? last;
  for (final spot in spots) {
    var here = 0;
    for (final find in spot.ownFinds) {
      if (canonicalSpecies(find.species) != entry.name) continue;
      here++;
      if (last == null || find.foundOn.isAfter(last)) last = find.foundOn;
    }
    if (here == 0) continue;
    finds += here;
    spotCount++;
  }

  return SpeciesDetail(
    name: entry.name,
    group: entry.group,
    sci: entry.sci,
    synonyms: synonymsOf(entry.name),
    curve: curve,
    share: curve?.months[month - 1],
    klass: klass,
    classKey: klass == null ? null : ampelClassKeyOf(klass),
    evidence: ampelEvidenceFor(entry.name),
    edibility: edibilityFor(entry.name),
    ownFinds: finds,
    ownSpots: spotCount,
    lastFound: last,
    gbif: gbif,
  );
}

/// Passt [name] zur Sucheingabe [query]?
///
/// **Gesucht wird über dieselbe Faltung wie beim Eintragen** (#395):
/// klein, ohne Umlaut-Schreibweise, ohne Binde- und Leerzeichen. „staub",
/// „Staeubling" und „Stäubling" finden denselben Pilz, und das ist der
/// ganze Zweck — 40 der 110 Namen tragen einen Umlaut oder ein ß.
///
/// **Gesucht wird in drei Namen**: der Hauptbezeichnung, den Zweitnamen
/// und dem wissenschaftlichen. Der letzte ist kein Schmuck — er ist der
/// einzige eindeutige Schlüssel, und wer ihn aus einem Buch abliest,
/// soll die Art damit finden.
///
/// **Teiltreffer, kein Editierabstand.** Anders als bei den Vorschlägen
/// im Eingabefeld tippt hier jemand, der eine Liste vor sich hat und
/// sie enger machen will; eine Liste, die bei „stein" auch
/// „Stockschwämmchen" zeigt, wäre kein Filter mehr.
bool speciesMatchesQuery(String name, String query) {
  final needle = foldSpeciesName(query);
  if (needle.isEmpty) return true;
  if (foldSpeciesName(name).contains(needle)) return true;
  for (final synonym in synonymsOf(name)) {
    if (foldSpeciesName(synonym).contains(needle)) return true;
  }
  final sci = knownSpeciesFor(name)?.sci;
  return sci != null && foldSpeciesName(sci).contains(needle);
}

/// Was eine Sucheingabe im Verzeichnis trifft.
///
/// [isGuess] heißt: Der Contains-Vergleich hat NICHTS geliefert, und was
/// hier steht, ist geraten. **Die Oberfläche muss das sagen** — dieselbe
/// Auflage wie bei [SpeciesSuggestion.isGuess] im Eingabefeld: Ein
/// geratener Treffer, der aussieht wie ein gefundener, ist eine
/// Behauptung über die Eingabe des Nutzers.
typedef SpeciesSearch = ({Set<String> names, bool isGuess});

/// Die Arten, die zu [query] passen — Hauptbezeichnungen.
///
/// **Derselbe Zweischritt wie im Blatt „Fund eintragen"**
/// (`suggestSpecies`), und das ist seit 1.164.0 Absicht statt Zufall:
/// erst Teiltreffer über die gefaltete Form, und NUR wenn der leer
/// ausgeht, der Tippfehler-Ausgleich. Zwei verschiedene Antworten auf
/// „kennt die App diesen Pilz?" wären eine zu viel — wer „Steinpliz"
/// ins Eingabefeld tippt, bekommt den Steinpilz angeboten; im
/// Verzeichnis stand bis dahin „Keine Art mit diesem Namen", also genau
/// der Satz, aus dem #395 entstanden ist.
///
/// **Leere Eingabe trifft ALLES.** Nicht nichts: Ein Aufrufer, der den
/// Sonderfall vergisst, zeigte sonst eine leere Liste, und ein
/// Verzeichnis, das nichts enthält, sieht kaputt aus. Die harmlose
/// Fehlerrichtung ist „zu viel".
SpeciesSearch speciesSearch(String query) {
  final known = kBekannteArten.where((s) => !s.isSynonym);
  final needle = foldSpeciesName(query);
  if (needle.isEmpty) {
    return (names: {for (final s in known) s.name}, isGuess: false);
  }

  final hits = {
    for (final s in known)
      if (speciesMatchesQuery(s.name, query)) s.name,
  };
  if (hits.isNotEmpty) return (names: hits, isGuess: false);

  // Ab hier wird geraten. Angeboten wird ausschließlich der geringste
  // gefundene Abstand — wie im Eingabefeld: Wer „Steinpiltz" tippt, will
  // die Steinpilze sehen und nicht dahinter alles, was zufällig auch in
  // die Nähe passt.
  final tolerance = speciesTypoTolerance(needle.length);
  if (tolerance < 0) return (names: const {}, isGuess: true);
  final distances = <String, int>{};
  for (final species in known) {
    // Über dieselben drei Namen wie der Contains-Vergleich, sonst fände
    // der Rückfall weniger als der Weg davor.
    for (final name in [
      species.name,
      ...synonymsOf(species.name),
      ?species.sci,
    ]) {
      final distance = nearContainsDistance(needle, foldSpeciesName(name));
      if (distance > tolerance) continue;
      final best = distances[species.name];
      if (best == null || distance < best) distances[species.name] = distance;
    }
  }
  if (distances.isEmpty) return (names: const {}, isGuess: true);
  final closest = distances.values.reduce((a, b) => a < b ? a : b);
  return (
    names: {
      for (final e in distances.entries)
        if (e.value == closest) e.key,
    },
    isGuess: true
  );
}
