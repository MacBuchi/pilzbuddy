/// Die bekanntesten Pilzarten (deutsche Namen), eingeordnet in anschauliche
/// Gruppen. Die Gruppe bestimmt auch das Aussehen des Karten-Icons —
/// ein Röhrlings-Spot sieht aus wie ein Steinpilz, ein Leistlings-Spot
/// wie ein gelber Trichter. Eigene Arten des Users entstehen automatisch
/// aus seinen Funden (Freitext bleibt immer möglich).
enum SpeciesGroup {
  roehrlinge('Röhrling'),
  leistlinge('Pfifferlingsartig'),
  champignons('Champignon'),
  schirmlinge('Schirmling'),
  wulstlinge('Wulstling'),
  taeublinge('Täubling/Milchling'),
  morcheln('Morchel/Lorchel'),
  boviste('Bovist'),
  baumpilze('Baumpilz'),
  sonstige('Lamellenpilz');

  const SpeciesGroup(this.label);

  final String label;
}

class KnownSpecies {
  final String name;
  final SpeciesGroup group;

  const KnownSpecies(this.name, this.group);
}

const _roe = SpeciesGroup.roehrlinge;
const _lei = SpeciesGroup.leistlinge;
const _cha = SpeciesGroup.champignons;
const _sch = SpeciesGroup.schirmlinge;
const _wul = SpeciesGroup.wulstlinge;
const _tae = SpeciesGroup.taeublinge;
const _mor = SpeciesGroup.morcheln;
const _bov = SpeciesGroup.boviste;
const _bau = SpeciesGroup.baumpilze;
const _son = SpeciesGroup.sonstige;

const kBekannteArten = <KnownSpecies>[
  // Röhrlinge
  KnownSpecies('Steinpilz', _roe),
  KnownSpecies('Sommersteinpilz', _roe),
  KnownSpecies('Kiefernsteinpilz', _roe),
  KnownSpecies('Bronzeröhrling', _roe),
  KnownSpecies('Maronenröhrling', _roe),
  KnownSpecies('Marone', _roe),
  KnownSpecies('Braunkappe', _roe),
  KnownSpecies('Birkenpilz', _roe),
  KnownSpecies('Rotkappe', _roe),
  KnownSpecies('Espenrotkappe', _roe),
  KnownSpecies('Birkenrotkappe', _roe),
  KnownSpecies('Butterpilz', _roe),
  KnownSpecies('Goldröhrling', _roe),
  KnownSpecies('Sandröhrling', _roe),
  KnownSpecies('Ziegenlippe', _roe),
  KnownSpecies('Flockenstieliger Hexenröhrling', _roe),
  KnownSpecies('Gallenröhrling', _roe),
  KnownSpecies('Satansröhrling', _roe),
  // Pfifferlingsartige (Leistlinge)
  KnownSpecies('Pfifferling', _lei),
  KnownSpecies('Trompetenpfifferling', _lei),
  KnownSpecies('Herbsttrompete', _lei),
  KnownSpecies('Falscher Pfifferling', _lei),
  // Champignons
  KnownSpecies('Wiesenchampignon', _cha),
  KnownSpecies('Stadtchampignon', _cha),
  KnownSpecies('Anischampignon', _cha),
  KnownSpecies('Waldchampignon', _cha),
  KnownSpecies('Karbolchampignon', _cha),
  // Schirmlinge
  KnownSpecies('Parasol', _sch),
  KnownSpecies('Safranschirmling', _sch),
  KnownSpecies('Riesenschirmling', _sch),
  KnownSpecies('Schopftintling', _sch),
  // Wulstlinge (Amanita)
  KnownSpecies('Fliegenpilz', _wul),
  KnownSpecies('Perlpilz', _wul),
  KnownSpecies('Pantherpilz', _wul),
  KnownSpecies('Grüner Knollenblätterpilz', _wul),
  KnownSpecies('Kegelhütiger Knollenblätterpilz', _wul),
  KnownSpecies('Frühjahrsknollenblätterpilz', _wul),
  // Täublinge & Milchlinge
  KnownSpecies('Frauentäubling', _tae),
  KnownSpecies('Speisetäubling', _tae),
  KnownSpecies('Ledertäubling', _tae),
  KnownSpecies('Fichtenreizker', _tae),
  KnownSpecies('Edelreizker', _tae),
  KnownSpecies('Lachsreizker', _tae),
  KnownSpecies('Kiefernreizker', _tae),
  KnownSpecies('Mohrenkopfmilchling', _tae),
  KnownSpecies('Brätling', _tae),
  // Morcheln & Lorcheln
  KnownSpecies('Speisemorchel', _mor),
  KnownSpecies('Spitzmorchel', _mor),
  KnownSpecies('Frühjahrslorchel', _mor),
  // Boviste & Stäublinge
  KnownSpecies('Riesenbovist', _bov),
  KnownSpecies('Flaschenstäubling', _bov),
  // Baumpilze
  KnownSpecies('Austernseitling', _bau),
  KnownSpecies('Schwefelporling', _bau),
  KnownSpecies('Leberpilz', _bau),
  KnownSpecies('Igelstachelbart', _bau),
  KnownSpecies('Judasohr', _bau),
  // Sonstige Lamellenpilze & Spezialisten
  KnownSpecies('Krause Glucke', _son),
  KnownSpecies('Semmelstoppelpilz', _son),
  KnownSpecies('Stockschwämmchen', _son),
  KnownSpecies('Hallimasch', _son),
  KnownSpecies('Dunkler Hallimasch', _son),
  KnownSpecies('Violetter Rötelritterling', _son),
  KnownSpecies('Fuchsiger Rötelritterling', _son),
  KnownSpecies('Nebelkappe', _son),
  KnownSpecies('Mönchskopf', _son),
  KnownSpecies('Reifpilz', _son),
  KnownSpecies('Winterrübling', _son),
  KnownSpecies('Samtfußrübling', _son),
  KnownSpecies('Gifthäubling', _son),
  KnownSpecies('Grünblättriger Schwefelkopf', _son),
  KnownSpecies('Kahler Krempling', _son),
  KnownSpecies('Spitzgebuckelter Raukopf', _son),
  KnownSpecies('Orangefuchsiger Raukopf', _son),
  KnownSpecies('Riesenrötling', _son),
  KnownSpecies('Tigerritterling', _son),
  KnownSpecies('Ziegelroter Risspilz', _son),
  KnownSpecies('Grünling', _son),
  KnownSpecies('Violetter Lacktrichterling', _son), // via In-App-Wunsch
];

/// Gruppe einer Art nachschlagen (case-insensitiv), z. B. um auch eigene
/// Einträge des Users einzuordnen. `null` = unbekannte/eigene Art.
SpeciesGroup? groupFor(String? name) {
  if (name == null) return null;
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return null;
  for (final s in kBekannteArten) {
    if (s.name.toLowerCase() == key) return s.group;
  }
  return null;
}
