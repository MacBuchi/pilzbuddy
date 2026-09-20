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
import '../ampel/ampel_model.dart';

/// Eine Art im Verzeichnis.
class CatalogueEntry {
  const CatalogueEntry({
    required this.name,
    required this.group,
    required this.curve,
    required this.share,
    required this.evidence,
  });

  final String name;
  final SpeciesGroup group;

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
