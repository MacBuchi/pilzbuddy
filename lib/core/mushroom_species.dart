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
  // Pilze ohne Lamellen und ohne den üblichen Hut-Stiel-Bau: Stoppeln
  // unter dem Hut, Korallen-Äste, krause Wülste. Sie lagen vorher in
  // `sonstige` — und dessen Aufschrift „Lamellenpilz" steht im
  // Vorschlagsfeld sichtbar am Eintrag, war für sie also schlicht falsch.
  stachelpilze('Stachel-/Korallenpilz'),
  sonstige('Lamellenpilz');

  const SpeciesGroup(this.label);

  final String label;
}

class KnownSpecies {
  final String name;
  final SpeciesGroup group;

  /// Zweitname? Dann steht hier die Hauptbezeichnung derselben Art.
  /// Gespeichert wird immer die Hauptbezeichnung ([canonicalSpecies]);
  /// der Zweitname existiert nur, damit die Eingabe ihn findet.
  final String? sameAs;

  /// Der wissenschaftliche Name — der einzige Schlüssel, mit dem sich
  /// eine Art in einer Funddatenbank nachschlagen lässt. Deutsche
  /// Trivialnamen taugen dafür nicht: Sie sind mehrdeutig („Rotkappe"
  /// meint eine ganze Gattung) und regional verschieden.
  ///
  /// Steht hier eine **Gattung** (`Leccinum`, `Armillaria`, `Ramaria`,
  /// `Chlorophyllum`), ist das Absicht — der deutsche Name ist dort ein
  /// Sammelbegriff, und eine einzelne Art unterzuschieben wäre eine
  /// Genauigkeit, die es nicht gibt.
  ///
  /// `null` bei Zweitnamen (sie erben über [sameAs]) und bei Arten, deren
  /// Zuordnung nicht zweifelsfrei ist. Ohne diesen Namen gibt es keine
  /// Saisonkurve — eine falsche wäre schlimmer als keine.
  ///
  /// Gepflegt wird das Feld von Hand und gegen GBIF geprüft; die Regeln
  /// dafür stehen in `docs/pilzampel-saisonkurven.md`. Kurzfassung: Der
  /// Name muss dort **akzeptiert** sein, kein Synonym — GBIF zählt unter
  /// einem Synonym nur die Meldungen, die genau diesen Namen tragen
  /// (`Lactarius volemus`: 54 statt 909).
  final String? sci;

  const KnownSpecies(this.name, this.group, {this.sameAs, this.sci});

  bool get isSynonym => sameAs != null;
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
const _sta = SpeciesGroup.stachelpilze;
const _son = SpeciesGroup.sonstige;

const kBekannteArten = <KnownSpecies>[
  // Röhrlinge
  KnownSpecies('Steinpilz', _roe, sci: 'Boletus edulis'),
  KnownSpecies('Herrenpilz', _roe, sameAs: 'Steinpilz'),
  KnownSpecies('Fichtensteinpilz', _roe, sameAs: 'Steinpilz'),
  KnownSpecies('Sommersteinpilz', _roe, sci: 'Boletus reticulatus'),
  KnownSpecies('Kiefernsteinpilz', _roe, sci: 'Boletus pinophilus'),
  KnownSpecies('Bronzeröhrling', _roe, sci: 'Boletus aereus'),
  KnownSpecies('Maronenröhrling', _roe, sci: 'Imleria badia'),
  KnownSpecies('Marone', _roe, sameAs: 'Maronenröhrling'),
  KnownSpecies('Birkenpilz', _roe, sci: 'Leccinum scabrum'),
  KnownSpecies('Rotkappe', _roe, sci: 'Leccinum'),
  KnownSpecies('Espenrotkappe', _roe, sci: 'Leccinum aurantiacum'),
  KnownSpecies('Birkenrotkappe', _roe, sci: 'Leccinum versipelle'),
  KnownSpecies('Butterpilz', _roe, sci: 'Suillus luteus'),
  KnownSpecies('Butterröhrling', _roe, sameAs: 'Butterpilz'),
  KnownSpecies('Goldröhrling', _roe, sci: 'Suillus grevillei'),
  KnownSpecies('Sandröhrling', _roe, sci: 'Suillus variegatus'),
  KnownSpecies('Ziegenlippe', _roe, sci: 'Xerocomus subtomentosus'),
  KnownSpecies('Rotfußröhrling', _roe, sci: 'Xerocomellus chrysenteron'),
  KnownSpecies('Rotfüßchen', _roe, sameAs: 'Rotfußröhrling'),
  KnownSpecies('Körnchenröhrling', _roe, sci: 'Suillus granulatus'),
  KnownSpecies('Flockenstieliger Hexenröhrling', _roe, sci: 'Neoboletus luridiformis'),
  KnownSpecies('Netzstieliger Hexenröhrling', _roe, sci: 'Suillellus luridus'), // via In-App-Wunsch
  KnownSpecies('Gallenröhrling', _roe, sci: 'Tylopilus felleus'),
  KnownSpecies('Satansröhrling', _roe, sci: 'Rubroboletus satanas'),
  // Pfifferlingsartige (Leistlinge)
  KnownSpecies('Pfifferling', _lei, sci: 'Cantharellus cibarius'),
  KnownSpecies('Trompetenpfifferling', _lei, sci: 'Craterellus tubaeformis'),
  KnownSpecies('Herbsttrompete', _lei, sci: 'Craterellus cornucopioides'),
  KnownSpecies('Totentrompete', _lei, sameAs: 'Herbsttrompete'),
  KnownSpecies('Falscher Pfifferling', _lei, sci: 'Hygrophoropsis aurantiaca'),
  // Champignons
  KnownSpecies('Wiesenchampignon', _cha, sci: 'Agaricus campestris'),
  KnownSpecies('Stadtchampignon', _cha, sci: 'Agaricus bitorquis'),
  KnownSpecies('Anischampignon', _cha, sci: 'Agaricus arvensis'),
  KnownSpecies('Waldchampignon', _cha, sci: 'Agaricus sylvaticus'),
  KnownSpecies('Karbolchampignon', _cha, sci: 'Agaricus xanthodermus'),
  // Schirmlinge
  KnownSpecies('Parasol', _sch, sci: 'Macrolepiota procera'),
  KnownSpecies('Safranschirmling', _sch, sci: 'Chlorophyllum'),
  KnownSpecies('Riesenschirmling', _sch, sameAs: 'Parasol'),
  KnownSpecies('Schopftintling', _sch, sci: 'Coprinus comatus'),
  KnownSpecies('Spargelpilz', _sch, sameAs: 'Schopftintling'),
  // Wulstlinge (Amanita)
  KnownSpecies('Fliegenpilz', _wul, sci: 'Amanita muscaria'),
  KnownSpecies('Perlpilz', _wul, sci: 'Amanita rubescens'),
  KnownSpecies('Rötender Wulstling', _wul, sameAs: 'Perlpilz'),
  KnownSpecies('Pantherpilz', _wul, sci: 'Amanita pantherina'),
  KnownSpecies('Grüner Knollenblätterpilz', _wul, sci: 'Amanita phalloides'),
  KnownSpecies('Kegelhütiger Knollenblätterpilz', _wul, sci: 'Amanita virosa'),
  KnownSpecies('Frühjahrsknollenblätterpilz', _wul, sci: 'Amanita verna'),
  KnownSpecies('Scheidenstreifling', _wul, sci: 'Amanita vaginata'),
  // Täublinge & Milchlinge
  KnownSpecies('Frauentäubling', _tae, sci: 'Russula cyanoxantha'),
  KnownSpecies('Speisetäubling', _tae, sci: 'Russula vesca'),
  KnownSpecies('Ledertäubling', _tae, sci: 'Russula integra'),
  KnownSpecies('Grüngefelderter Täubling', _tae, sci: 'Russula virescens'),
  KnownSpecies('Speitäubling', _tae, sci: 'Russula emetica'),
  KnownSpecies('Fichtenreizker', _tae, sci: 'Lactarius deterrimus'),
  KnownSpecies('Edelreizker', _tae, sci: 'Lactarius deliciosus'),
  KnownSpecies('Lachsreizker', _tae, sci: 'Lactarius salmonicolor'),
  KnownSpecies('Kiefernreizker', _tae, sci: 'Lactarius sanguifluus'),
  KnownSpecies('Mohrenkopfmilchling', _tae, sci: 'Lactarius lignyotus'),
  KnownSpecies('Brätling', _tae, sci: 'Lactifluus volemus'),
  // Morcheln & Lorcheln
  KnownSpecies('Speisemorchel', _mor, sci: 'Morchella esculenta'),
  KnownSpecies('Spitzmorchel', _mor, sci: 'Morchella elata'),
  KnownSpecies('Frühjahrslorchel', _mor, sci: 'Gyromitra esculenta'),
  KnownSpecies('Käppchenmorchel', _mor, sci: 'Morchella semilibera'), // via In-App-Wunsch
  KnownSpecies('Morchelbecherling', _mor, sci: 'Disciotis venosa'), // via In-App-Wunsch
  KnownSpecies('Böhmische Verpel', _mor, sci: 'Verpa bohemica'), // via In-App-Wunsch
  // Boviste & Stäublinge
  KnownSpecies('Riesenbovist', _bov, sci: 'Calvatia gigantea'),
  KnownSpecies('Riesenstäubling', _bov, sameAs: 'Riesenbovist'),
  KnownSpecies('Flaschenstäubling', _bov, sci: 'Lycoperdon perlatum'),
  KnownSpecies('Flaschenbovist', _bov, sameAs: 'Flaschenstäubling'),
  KnownSpecies('Birnenstäubling', _bov, sci: 'Apioperdon pyriforme'),
  // Baumpilze
  KnownSpecies('Austernseitling', _bau, sci: 'Pleurotus ostreatus'),
  KnownSpecies('Austernpilz', _bau, sameAs: 'Austernseitling'),
  KnownSpecies('Lungenseitling', _bau, sci: 'Pleurotus pulmonarius'),
  KnownSpecies('Schwefelporling', _bau, sci: 'Laetiporus sulphureus'),
  KnownSpecies('Leberpilz', _bau, sci: 'Fistulina hepatica'),
  KnownSpecies('Judasohr', _bau, sci: 'Auricularia auricula-judae'),
  // Stachel- & Korallenpilze (keine Lamellen, kein Hut-Stiel-Bau)
  KnownSpecies('Krause Glucke', _sta, sci: 'Sparassis crispa'),
  KnownSpecies('Fette Henne', _sta, sameAs: 'Krause Glucke'),
  KnownSpecies('Semmelstoppelpilz', _sta, sci: 'Hydnum repandum'),
  KnownSpecies('Habichtspilz', _sta, sci: 'Sarcodon imbricatus'),
  KnownSpecies('Ziegenbart', _sta, sci: 'Ramaria'),
  KnownSpecies('Igelstachelbart', _sta, sci: 'Hericium erinaceus'),
  KnownSpecies('Affenkopfpilz', _sta, sameAs: 'Igelstachelbart'),
  KnownSpecies('Löwenmähne', _sta, sameAs: 'Igelstachelbart'),
  // Sonstige Lamellenpilze & Spezialisten
  KnownSpecies('Stockschwämmchen', _son, sci: 'Kuehneromyces mutabilis'),
  KnownSpecies('Maipilz', _son, sci: 'Calocybe gambosa'),
  KnownSpecies('Mairitterling', _son, sameAs: 'Maipilz'),
  KnownSpecies('Nelkenschwindling', _son, sci: 'Marasmius oreades'),
  KnownSpecies('Rehbrauner Dachpilz', _son, sci: 'Pluteus cervinus'),
  KnownSpecies('Riesenträuschling', _son, sci: 'Stropharia rugosoannulata'),
  KnownSpecies('Braunkappe', _son, sameAs: 'Riesenträuschling'),
  KnownSpecies('Hallimasch', _son, sci: 'Armillaria'),
  KnownSpecies('Dunkler Hallimasch', _son, sci: 'Armillaria ostoyae'),
  KnownSpecies('Violetter Rötelritterling', _son, sci: 'Lepista nuda'),
  KnownSpecies('Fuchsiger Rötelritterling', _son, sci: 'Paralepista flaccida'),
  KnownSpecies('Nebelkappe', _son, sci: 'Clitocybe nebularis'),
  KnownSpecies('Nebelgrauer Trichterling', _son, sameAs: 'Nebelkappe'),
  KnownSpecies('Mönchskopf', _son, sci: 'Infundibulicybe geotropa'),
  KnownSpecies('Reifpilz', _son, sci: 'Cortinarius caperatus'),
  KnownSpecies('Winterrübling', _son, sameAs: 'Samtfußrübling'),
  KnownSpecies('Samtfußrübling', _son, sci: 'Flammulina velutipes'),
  KnownSpecies('Gifthäubling', _son, sci: 'Galerina marginata'),
  KnownSpecies('Grünblättriger Schwefelkopf', _son, sci: 'Hypholoma fasciculare'),
  KnownSpecies('Kahler Krempling', _son, sci: 'Paxillus involutus'),
  KnownSpecies('Spitzgebuckelter Raukopf', _son, sci: 'Cortinarius rubellus'),
  KnownSpecies('Orangefuchsiger Raukopf', _son, sci: 'Cortinarius orellanus'),
  KnownSpecies('Riesenrötling', _son, sci: 'Entoloma sinuatum'),
  KnownSpecies('Tigerritterling', _son, sci: 'Tricholoma pardinum'),
  KnownSpecies('Ziegelroter Risspilz', _son, sci: 'Inosperma erubescens'),
  KnownSpecies('Grünling', _son, sci: 'Tricholoma equestre'),
  KnownSpecies('Violetter Lacktrichterling', _son, sci: 'Laccaria amethystina'), // via In-App-Wunsch
  KnownSpecies('VaginalPilz', _son), // via In-App-Wunsch
];

/// Findet eine bekannte Pilzart in einem Freitext (z. B. dem Punktnamen
/// eines GPX-Imports wie „Edelreizker Spechbach"). Bei mehreren Treffern
/// gewinnt der längste — „Maronenröhrling" schlägt „Marone". Erkennt auch
/// einfache Plurale („Totentrompeten", „Steinpilze"). Zweitnamen werden
/// gefunden, zurück kommt aber die Hauptbezeichnung.
String? speciesFromText(String? text) {
  if (text == null) return null;
  final key = text.toLowerCase();
  KnownSpecies? best;
  for (final s in kBekannteArten) {
    final name = s.name.toLowerCase();
    if (key.contains(name) &&
        (best == null || name.length > best.name.length)) {
      best = s;
    }
  }
  return best == null ? null : (best.sameAs ?? best.name);
}

/// Eintrag zu einem Artnamen (case-insensitiv), `null` für eigene Arten.
KnownSpecies? _entryFor(String? name) {
  if (name == null) return null;
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return null;
  for (final s in kBekannteArten) {
    if (s.name.toLowerCase() == key) return s;
  }
  return null;
}

/// Gruppe einer Art nachschlagen (case-insensitiv), z. B. um auch eigene
/// Einträge des Users einzuordnen. `null` = unbekannte/eigene Art.
/// Ein Zweitname erbt die Gruppe seiner Hauptbezeichnung — sonst könnten
/// zwei Namen derselben Art verschiedene Icons bekommen.
SpeciesGroup? groupFor(String? name) {
  final entry = _entryFor(name);
  if (entry == null) return null;
  if (entry.sameAs == null) return entry.group;
  return _entryFor(entry.sameAs)?.group ?? entry.group;
}

/// Die Hauptbezeichnung einer Art: löst Zweitnamen auf („Totentrompete" →
/// „Herbsttrompete") und zieht die Schreibweise der Liste nach („steinpilz"
/// → „Steinpilz"). **Unbekannte Namen bleiben unverändert** — die eigenen
/// Arten der Nutzer sind Freitext und dürfen nicht umbenannt werden.
///
/// Wird beim Schreiben angewandt (`SpotRepository.addFind`), damit in der
/// Datenbank nur Hauptbezeichnungen landen, und beim Auswerten, damit
/// ältere Funde mit den neuen zusammenfallen.
String? canonicalSpecies(String? name) {
  if (name == null) return null;
  final trimmed = name.trim();
  if (trimmed.isEmpty) return null;
  final entry = _entryFor(trimmed);
  if (entry == null) return trimmed;
  return entry.sameAs ?? entry.name;
}

/// Die Zweitnamen einer Art — für den Hinweis „auch: …". Nimmt Haupt- wie
/// Zweitnamen entgegen; leer, wenn es keine gibt.
List<String> synonymsOf(String? name) {
  final canonical = canonicalSpecies(name);
  if (canonical == null) return const [];
  final key = canonical.toLowerCase();
  return [
    for (final s in kBekannteArten)
      if (s.sameAs?.toLowerCase() == key) s.name,
  ];
}
