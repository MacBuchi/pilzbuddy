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

  const KnownSpecies(this.name, this.group, {this.sameAs});

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
  KnownSpecies('Steinpilz', _roe),
  KnownSpecies('Herrenpilz', _roe, sameAs: 'Steinpilz'),
  KnownSpecies('Fichtensteinpilz', _roe, sameAs: 'Steinpilz'),
  KnownSpecies('Sommersteinpilz', _roe),
  KnownSpecies('Kiefernsteinpilz', _roe),
  KnownSpecies('Bronzeröhrling', _roe),
  KnownSpecies('Maronenröhrling', _roe),
  KnownSpecies('Marone', _roe, sameAs: 'Maronenröhrling'),
  KnownSpecies('Birkenpilz', _roe),
  KnownSpecies('Rotkappe', _roe),
  KnownSpecies('Espenrotkappe', _roe),
  KnownSpecies('Birkenrotkappe', _roe),
  KnownSpecies('Butterpilz', _roe),
  KnownSpecies('Butterröhrling', _roe, sameAs: 'Butterpilz'),
  KnownSpecies('Goldröhrling', _roe),
  KnownSpecies('Sandröhrling', _roe),
  KnownSpecies('Ziegenlippe', _roe),
  KnownSpecies('Rotfußröhrling', _roe),
  KnownSpecies('Rotfüßchen', _roe, sameAs: 'Rotfußröhrling'),
  KnownSpecies('Körnchenröhrling', _roe),
  KnownSpecies('Flockenstieliger Hexenröhrling', _roe),
  KnownSpecies('Netzstieliger Hexenröhrling', _roe), // via In-App-Wunsch
  KnownSpecies('Gallenröhrling', _roe),
  KnownSpecies('Satansröhrling', _roe),
  // Pfifferlingsartige (Leistlinge)
  KnownSpecies('Pfifferling', _lei),
  KnownSpecies('Trompetenpfifferling', _lei),
  KnownSpecies('Herbsttrompete', _lei),
  KnownSpecies('Totentrompete', _lei, sameAs: 'Herbsttrompete'),
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
  KnownSpecies('Riesenschirmling', _sch, sameAs: 'Parasol'),
  KnownSpecies('Schopftintling', _sch),
  KnownSpecies('Spargelpilz', _sch, sameAs: 'Schopftintling'),
  // Wulstlinge (Amanita)
  KnownSpecies('Fliegenpilz', _wul),
  KnownSpecies('Perlpilz', _wul),
  KnownSpecies('Rötender Wulstling', _wul, sameAs: 'Perlpilz'),
  KnownSpecies('Pantherpilz', _wul),
  KnownSpecies('Grüner Knollenblätterpilz', _wul),
  KnownSpecies('Kegelhütiger Knollenblätterpilz', _wul),
  KnownSpecies('Frühjahrsknollenblätterpilz', _wul),
  KnownSpecies('Scheidenstreifling', _wul),
  // Täublinge & Milchlinge
  KnownSpecies('Frauentäubling', _tae),
  KnownSpecies('Speisetäubling', _tae),
  KnownSpecies('Ledertäubling', _tae),
  KnownSpecies('Grüngefelderter Täubling', _tae),
  KnownSpecies('Speitäubling', _tae),
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
  KnownSpecies('Käppchenmorchel', _mor), // via In-App-Wunsch
  KnownSpecies('Morchelbecherling', _mor), // via In-App-Wunsch
  KnownSpecies('Böhmische Verpel', _mor), // via In-App-Wunsch
  // Boviste & Stäublinge
  KnownSpecies('Riesenbovist', _bov),
  KnownSpecies('Riesenstäubling', _bov, sameAs: 'Riesenbovist'),
  KnownSpecies('Flaschenstäubling', _bov),
  KnownSpecies('Flaschenbovist', _bov, sameAs: 'Flaschenstäubling'),
  KnownSpecies('Birnenstäubling', _bov),
  // Baumpilze
  KnownSpecies('Austernseitling', _bau),
  KnownSpecies('Austernpilz', _bau, sameAs: 'Austernseitling'),
  KnownSpecies('Lungenseitling', _bau),
  KnownSpecies('Schwefelporling', _bau),
  KnownSpecies('Leberpilz', _bau),
  KnownSpecies('Judasohr', _bau),
  // Stachel- & Korallenpilze (keine Lamellen, kein Hut-Stiel-Bau)
  KnownSpecies('Krause Glucke', _sta),
  KnownSpecies('Fette Henne', _sta, sameAs: 'Krause Glucke'),
  KnownSpecies('Semmelstoppelpilz', _sta),
  KnownSpecies('Habichtspilz', _sta),
  KnownSpecies('Ziegenbart', _sta),
  KnownSpecies('Igelstachelbart', _sta),
  KnownSpecies('Affenkopfpilz', _sta, sameAs: 'Igelstachelbart'),
  KnownSpecies('Löwenmähne', _sta, sameAs: 'Igelstachelbart'),
  // Sonstige Lamellenpilze & Spezialisten
  KnownSpecies('Stockschwämmchen', _son),
  KnownSpecies('Maipilz', _son),
  KnownSpecies('Mairitterling', _son, sameAs: 'Maipilz'),
  KnownSpecies('Nelkenschwindling', _son),
  KnownSpecies('Rehbrauner Dachpilz', _son),
  KnownSpecies('Riesenträuschling', _son),
  KnownSpecies('Braunkappe', _son, sameAs: 'Riesenträuschling'),
  KnownSpecies('Hallimasch', _son),
  KnownSpecies('Dunkler Hallimasch', _son),
  KnownSpecies('Violetter Rötelritterling', _son),
  KnownSpecies('Fuchsiger Rötelritterling', _son),
  KnownSpecies('Nebelkappe', _son),
  KnownSpecies('Nebelgrauer Trichterling', _son, sameAs: 'Nebelkappe'),
  KnownSpecies('Mönchskopf', _son),
  KnownSpecies('Reifpilz', _son),
  KnownSpecies('Winterrübling', _son, sameAs: 'Samtfußrübling'),
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
