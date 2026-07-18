/// Die bekanntesten Pilzarten (deutsche Namen) mit Kategorie für die
/// Vorschlagsliste. Eigene Arten des Users entstehen automatisch aus
/// seinen Funden (Freitext bleibt immer möglich).
enum SpeciesCategory {
  speisepilz('Speisepilz'),
  giftpilz('Giftpilz');

  const SpeciesCategory(this.label);

  final String label;
}

class KnownSpecies {
  final String name;
  final SpeciesCategory category;

  const KnownSpecies(this.name, this.category);
}

const _e = SpeciesCategory.speisepilz;
const _g = SpeciesCategory.giftpilz;

const kBekannteArten = <KnownSpecies>[
  // Beliebte Speisepilze
  KnownSpecies('Steinpilz', _e),
  KnownSpecies('Sommersteinpilz', _e),
  KnownSpecies('Kiefernsteinpilz', _e),
  KnownSpecies('Bronzeröhrling', _e),
  KnownSpecies('Pfifferling', _e),
  KnownSpecies('Trompetenpfifferling', _e),
  KnownSpecies('Maronenröhrling', _e),
  KnownSpecies('Birkenpilz', _e),
  KnownSpecies('Rotkappe', _e),
  KnownSpecies('Espenrotkappe', _e),
  KnownSpecies('Birkenrotkappe', _e),
  KnownSpecies('Butterpilz', _e),
  KnownSpecies('Goldröhrling', _e),
  KnownSpecies('Sandröhrling', _e),
  KnownSpecies('Ziegenlippe', _e),
  KnownSpecies('Flockenstieliger Hexenröhrling', _e),
  KnownSpecies('Parasol', _e),
  KnownSpecies('Safranschirmling', _e),
  KnownSpecies('Wiesenchampignon', _e),
  KnownSpecies('Stadtchampignon', _e),
  KnownSpecies('Anischampignon', _e),
  KnownSpecies('Waldchampignon', _e),
  KnownSpecies('Krause Glucke', _e),
  KnownSpecies('Herbsttrompete', _e),
  KnownSpecies('Semmelstoppelpilz', _e),
  KnownSpecies('Austernseitling', _e),
  KnownSpecies('Stockschwämmchen', _e),
  KnownSpecies('Hallimasch', _e),
  KnownSpecies('Dunkler Hallimasch', _e),
  KnownSpecies('Violetter Rötelritterling', _e),
  KnownSpecies('Nebelkappe', _e),
  KnownSpecies('Mönchskopf', _e),
  KnownSpecies('Reifpilz', _e),
  KnownSpecies('Perlpilz', _e),
  KnownSpecies('Speisemorchel', _e),
  KnownSpecies('Spitzmorchel', _e),
  KnownSpecies('Schopftintling', _e),
  KnownSpecies('Riesenbovist', _e),
  KnownSpecies('Flaschenstäubling', _e),
  KnownSpecies('Judasohr', _e),
  KnownSpecies('Samtfußrübling', _e),
  KnownSpecies('Winterrübling', _e),
  KnownSpecies('Fichtenreizker', _e),
  KnownSpecies('Edelreizker', _e),
  KnownSpecies('Lachsreizker', _e),
  KnownSpecies('Mohrenkopfmilchling', _e),
  KnownSpecies('Brätling', _e),
  KnownSpecies('Frauentäubling', _e),
  KnownSpecies('Speisetäubling', _e),
  KnownSpecies('Ledertäubling', _e),
  KnownSpecies('Schwefelporling', _e),
  KnownSpecies('Leberpilz', _e),
  KnownSpecies('Igelstachelbart', _e),
  KnownSpecies('Riesenschirmling', _e),
  // Bekannte Gift- und Verwechslungspilze (fürs Dokumentieren)
  KnownSpecies('Fliegenpilz', _g),
  KnownSpecies('Grüner Knollenblätterpilz', _g),
  KnownSpecies('Kegelhütiger Knollenblätterpilz', _g),
  KnownSpecies('Frühjahrsknollenblätterpilz', _g),
  KnownSpecies('Pantherpilz', _g),
  KnownSpecies('Karbolchampignon', _g),
  KnownSpecies('Gifthäubling', _g),
  KnownSpecies('Grünblättriger Schwefelkopf', _g),
  KnownSpecies('Kahler Krempling', _g),
  KnownSpecies('Satansröhrling', _g),
  KnownSpecies('Gallenröhrling', _g),
  KnownSpecies('Spitzgebuckelter Raukopf', _g),
  KnownSpecies('Orangefuchsiger Raukopf', _g),
  KnownSpecies('Riesenrötling', _g),
  KnownSpecies('Tigerritterling', _g),
  KnownSpecies('Ziegelroter Risspilz', _g),
  KnownSpecies('Fuchsiger Rötelritterling', _g),
  KnownSpecies('Falscher Pfifferling', _g),
  KnownSpecies('Frühjahrslorchel', _g),
  KnownSpecies('Grünling', _g),
];

/// Kategorie einer Art nachschlagen (case-insensitiv), z. B. um auch
/// eigene Einträge des Users einzuordnen. `null` = unbekannte/eigene Art.
SpeciesCategory? categoryFor(String name) {
  final key = name.trim().toLowerCase();
  for (final s in kBekannteArten) {
    if (s.name.toLowerCase() == key) return s.category;
  }
  return null;
}
