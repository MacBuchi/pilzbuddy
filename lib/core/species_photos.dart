// Die Bildpaare zu den Verwechslungen (#511 Folgeschritt).
//
// **Bilder stehen NUR dort, wo es etwas zu verwechseln gibt.** Nicht am
// Seitenkopf, nicht als Schmuck: Ein Foto je Art läse sich als Porträt
// und damit als Bestimmungshilfe — ein einzelnes Bild kann einen Perlpilz
// nicht von einem Pantherpilz trennen. Zwei nebeneinander stellen genau
// die Frage, um die es geht. Dieselbe Asymmetrie wie bei der Einstufung:
// Das Bild dient der Warnung, nicht der Freigabe.
//
// **Die Auswahl ist von Hand getroffen und angesehen.** Jedes Bild wurde
// daraufhin geprüft, ob es das Merkmal ZEIGT, das der Unterschiedssatz
// nennt — der schuppige Stiel des Stockschwämmchens, die Scheide des
// Knollenblätterpilzes, die rosa Lamellen des Champignons. Zwei
// Kandidaten sind dabei ausgeschieden, weil sie eine ANDERE Art zeigten,
// als ihr Dateiname behauptete; auf Commons ist die Bestimmung nicht
// garantiert. Wer hier ein Bild tauscht, muss es ansehen.
//
// **Namensnennung ist Pflicht, nicht Höflichkeit.** Alle Bilder stehen
// unter CC0, CC BY oder CC BY-SA. Die Nennung steht an ZWEI Stellen: als
// Bildunterschrift am Bild selbst und auf der Lizenzseite
// (`map_data_license.dart`, aus dieser Tabelle erzeugt, damit sie nicht
// auseinanderlaufen kann).
//
// Quelle der Dateien: Wikimedia Commons, geholt und zugeschnitten mit
// `tool/species_photos.py` (700x700, WebP q80; quadratisch, weil ein
// Paar nebeneinander sonst zwei verschiedene Formate hätte).
import 'mushroom_species.dart';

/// Ein Bild samt allem, was die Lizenz verlangt.
typedef SpeciesPhoto = ({
  String asset,
  String author,
  String licence,
  String licenceUrl,
  String source,
});

/// Die Bilder, nach Hauptbezeichnung.
const speciesPhotos = <String, SpeciesPhoto>{
  'Stockschwämmchen': (
    asset: 'assets/species/stockschwaemmchen.webp',
    author: 'Achim Lammerts (Syntaxys)',
    licence: 'CC BY-SA 4.0',
    licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
    source: 'https://commons.wikimedia.org/wiki/File:2025-10-11_D500-920_Achim-Lammerts_Kuehneromyces-mutabilis.jpg',
  ),
  'Gifthäubling': (
    asset: 'assets/species/gifthaeubling.webp',
    author: 'André De Kesel',
    licence: 'CC0',
    licenceUrl: 'http://creativecommons.org/publicdomain/zero/1.0/deed.en',
    source: 'https://commons.wikimedia.org/wiki/File:Galerina_marginata_-_Bundelmosklokje.jpg',
  ),
  'Samtfußrübling': (
    asset: 'assets/species/samtfussruebling.webp',
    author: 'JackyM59',
    licence: 'CC BY-SA 4.0',
    licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
    source: 'https://commons.wikimedia.org/wiki/File:Collybie_%C3%A0_pied_velout%C3%A9_(Flammulina_velutipes).jpg',
  ),
  'Speisemorchel': (
    asset: 'assets/species/speisemorchel.webp',
    author: 'Achim Lammerts (Syntaxys)',
    licence: 'CC BY-SA 4.0',
    licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
    source: 'https://commons.wikimedia.org/wiki/File:2026-04-04_Z5-3750E_Achim-Lammerts_Morchella-esculenta.jpg',
  ),
  'Spitzmorchel': (
    asset: 'assets/species/spitzmorchel.webp',
    author: 'Lukas Large from Stourbridge, United Kingdom',
    licence: 'CC BY-SA 2.0',
    licenceUrl: 'https://creativecommons.org/licenses/by-sa/2.0',
    source: 'https://commons.wikimedia.org/wiki/File:Lukas_Large_-_Morchella_elata_(53588923052).jpg',
  ),
  'Frühjahrslorchel': (
    asset: 'assets/species/fruehjahrslorchel.webp',
    author: 'Lukas from London, England',
    licence: 'CC BY-SA 2.0',
    licenceUrl: 'https://creativecommons.org/licenses/by-sa/2.0',
    source: 'https://commons.wikimedia.org/wiki/File:Gyromitra_esculenta_(27717088958).jpg',
  ),
  'Perlpilz': (
    asset: 'assets/species/perlpilz.webp',
    author: 'Dr. Hans-Günter Wagner',
    licence: 'CC BY-SA 2.0',
    licenceUrl: 'https://creativecommons.org/licenses/by-sa/2.0',
    source: 'https://commons.wikimedia.org/wiki/File:Amanita_rubescens_(2)_(48337725171).jpg',
  ),
  'Pantherpilz': (
    asset: 'assets/species/pantherpilz.webp',
    author: 'xulescu_g',
    licence: 'CC BY-SA 2.0',
    licenceUrl: 'https://creativecommons.org/licenses/by-sa/2.0',
    source: 'https://commons.wikimedia.org/wiki/File:Amanita_pantherina_(42556666615).jpg',
  ),
  'Wiesenchampignon': (
    asset: 'assets/species/wiesenchampignon.webp',
    author: 'Dr. Hans-Günter Wagner',
    licence: 'CC BY-SA 2.0',
    licenceUrl: 'https://creativecommons.org/licenses/by-sa/2.0',
    source: 'https://commons.wikimedia.org/wiki/File:Agaricus_campestris_(48647010296).jpg',
  ),
  'Grüner Knollenblätterpilz': (
    asset: 'assets/species/gruenerknollenblaetterpilz.webp',
    author: 'Björn S...',
    licence: 'CC BY-SA 2.0',
    licenceUrl: 'https://creativecommons.org/licenses/by-sa/2.0',
    source: 'https://commons.wikimedia.org/wiki/File:Amanita_phalloides_(29069664382).jpg',
  ),
  'Flaschenstäubling': (
    asset: 'assets/species/flaschenstaeubling.webp',
    author: 'Achim Lammerts (Syntaxys)',
    licence: 'CC BY-SA 4.0',
    licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
    source: 'https://commons.wikimedia.org/wiki/File:2025-10-15_D500-1015_Achim-Lammerts_Lycoperdon-perlatum.jpg',
  ),
  'Flockenstieliger Hexenröhrling': (
    asset: 'assets/species/flockenstieligerhexenroehrling.webp',
    author: 'George Chernilevsky',
    licence: 'Public domain',
    // Gemeinfrei gestellt vom Urheber; Commons liefert dafür keine
    // Lizenz-URL, die Freigabe steht auf der Dateiseite.
    licenceUrl: 'https://creativecommons.org/publicdomain/mark/1.0/',
    source: 'https://commons.wikimedia.org/wiki/File:Boletus_erythropus_2010_G3.jpg',
  ),
  'Satansröhrling': (
    asset: 'assets/species/satansroehrling.webp',
    author: 'Björn S...',
    licence: 'CC BY-SA 2.0',
    licenceUrl: 'https://creativecommons.org/licenses/by-sa/2.0',
    source: 'https://commons.wikimedia.org/wiki/File:Frankenwarte_10.08.2016_Satan%27s_Bolete_-_Rubroboletus_satanas_(29135732512).jpg',
  ),
};

/// Das Bild zu einem Artnamen — `null`, wenn es keines gibt.
///
/// **Die meisten Arten haben keines**, und das ist der Normalfall: Bilder
/// gibt es zu den Paaren, bei denen eine Verwechslung teuer ist.
/// Zweitnamen lösen sich auf wie überall.
/// Die Porträts je Art — zwei bis drei Bilder, waagerecht durchblätterbar.
///
/// **Das ist bewusst etwas anderes als [speciesPhotos].** Dort gilt „zwei
/// oder keines", weil ein einzelnes Bild eine Verwechslung nicht
/// auflösen kann. Hier geht es nicht ums Unterscheiden, sondern ums
/// Wiedererkennen: wie die Art überhaupt aussieht. Dafür ist ein Bild zu
/// wenig und zwanzig sind zu viel — zwei bis drei zeigen, wie stark sich
/// Farbe und Form mit Alter und Wetter ändern (Betreiber, 2026-09-22:
/// „wir können auch 2-3 Bilder je nehmen").
///
/// **Alle Aufnahmen stammen vom Betreiber selbst.** Das ist der Grund,
/// warum es sie überhaupt gibt: Auf Commons ist die Bestimmung nicht
/// garantiert, und Lehrbuchbilder zeigen die Lehrbuchform. Genau daran
/// hat sich in 1.169.0 eine Merkmalszeile als zu absolut erwiesen — der
/// Fichtenreizker auf dem eigenen Foto trug die Stielgrübchen, die die
/// Tabelle dem Edelreizker allein zuschrieb.
///
/// **Die Reihenfolge ist die Aussage.** Das erste Bild ist das Porträt,
/// die weiteren zeigen eine andere Ansicht oder ein anderes Alter: beim
/// Parasol Seitenansicht, Doppelring und junger Paukenschläger, beim
/// Falschen Pfifferling drei Blickwinkel auf dieselbe Gruppe.
const speciesPortraits = <String, List<SpeciesPhoto>>{
  'Fliegenpilz': [
    (
      asset: 'assets/species/fliegenpilz-1.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/fliegenpilz-2.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/fliegenpilz-3.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
  ],
  'Fichtenreizker': [
    (
      asset: 'assets/species/fichtenreizker-1.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/fichtenreizker-2.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/fichtenreizker-3.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
  ],
  'Stadtchampignon': [
    (
      asset: 'assets/species/stadtchampignon-1.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/stadtchampignon-2.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
  ],
  'Schopftintling': [
    (
      asset: 'assets/species/schopftintling-1.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/schopftintling-2.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
  ],
  'Birnenstäubling': [
    (
      asset: 'assets/species/birnenstaeubling-1.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
  ],
  'Grünblättriger Schwefelkopf': [
    (
      asset: 'assets/species/gruenblaettrigerschwefelkopf-1.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/gruenblaettrigerschwefelkopf-2.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
  ],
  'Austernseitling': [
    (
      asset: 'assets/species/austernseitling-1.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/austernseitling-2.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/austernseitling-3.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
  ],
  'Parasol': [
    (
      asset: 'assets/species/parasol-1.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/parasol-2.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/parasol-3.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
  ],
  'Hallimasch': [
    (
      asset: 'assets/species/hallimasch-1.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/hallimasch-2.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/hallimasch-3.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
  ],
  'Steinpilz': [
    (
      asset: 'assets/species/steinpilz-1.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/steinpilz-2.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
  ],
  'Maronenröhrling': [
    (
      asset: 'assets/species/maronenroehrling-1.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/maronenroehrling-2.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
  ],
  'Falscher Pfifferling': [
    (
      asset: 'assets/species/falscherpfifferling-1.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/falscherpfifferling-2.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/falscherpfifferling-3.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
  ],
  'Krause Glucke': [
    (
      asset: 'assets/species/krauseglucke-1.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      // **Die Hand ist Absicht.** Sonst gilt sie als Fremdkörper im
      // Bild, hier trägt sie das Merkmal: Die Krause Glucke wird
      // kopfgroß, und an einem Ballen ohne Bezugsgröße sieht man das
      // nicht.
      asset: 'assets/species/krauseglucke-2.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
  ],
  'Herbsttrompete': [
    (
      asset: 'assets/species/herbsttrompete-1.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
  ],
  'Samtfußrübling': [
    (
      asset: 'assets/species/samtfussruebling-1.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/samtfussruebling-2.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
    (
      asset: 'assets/species/samtfussruebling-3.webp',
      author: 'MacBuchi',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'Eigene Aufnahme',
    ),
  ],
  // ── Aus Wikimedia Commons, bis eigene Bilder da sind ─────────────
  //
  // **Jedes hier ist ein Platzhalter.** Sie stehen da, weil eine
  // Verwechslungszeile ohne Gegenstück nur die halbe Frage stellt: Bei
  // allen 16 hatte der Partner schon ein Bild und diese Art nicht. Wer
  // eine davon selbst fotografiert, ersetzt den Eintrag — der
  // Fotokatalog im privaten Repo führt, welche noch offen sind.
  'Bronzeröhrling': [
    (
      asset: 'assets/species/bronzeroehrling-1.webp',
      author: 'Paffka, Bearbeitung Xth-Floor',
      licence: 'CC BY-SA 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/3.0',
      source: 'https://commons.wikimedia.org/wiki/File:Boletus_aereusBG_crop.jpg',
    ),
  ],
  'Edelreizker': [
    (
      asset: 'assets/species/edelreizker-1.webp',
      author: 'Ian Sutton from Collinsville and Oberon, Australia',
      licence: 'CC BY 2.0',
      licenceUrl: 'https://creativecommons.org/licenses/by/2.0',
      source: 'https://commons.wikimedia.org/wiki/File:Lactarius_deliciosus_1_(1).jpg',
    ),
  ],
  'Frauentäubling': [
    (
      asset: 'assets/species/frauentaeubling-1.webp',
      author: 'Holger Krisp',
      licence: 'CC BY 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by/3.0',
      source: 'https://commons.wikimedia.org/wiki/File:Frauen-T%C3%A4ubling_Russula_cyanoxantha.jpg',
    ),
  ],
  'Gallenröhrling': [
    (
      asset: 'assets/species/gallenroehrling-1.webp',
      author: 'Holger Krisp',
      licence: 'CC BY 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by/3.0',
      source: 'https://commons.wikimedia.org/wiki/File:Gemeine_Gallenr%C3%B6hrling_Tylopilus_felleus.jpg',
    ),
  ],
  'Grüngefelderter Täubling': [
    (
      asset: 'assets/species/gruengefeldertertaeubling-1.webp',
      author: 'Bubbah63',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'https://commons.wikimedia.org/wiki/File:Gol%C4%8Duba%C4%8Da_3.JPG',
    ),
  ],
  'Karbolchampignon': [
    (
      asset: 'assets/species/karbolchampignon-1.webp',
      author: 'Ron Pastorino (Mushroom Observer)',
      licence: 'CC BY-SA 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/3.0',
      source: 'https://commons.wikimedia.org/wiki/File:2012-04-19_Agaricus_xanthodermus_Genev_213787.jpg',
    ),
  ],
  'Kegelhütiger Knollenblätterpilz': [
    (
      asset: 'assets/species/kegelhuetigerknollenblaetterpilz-1.webp',
      author: 'Quartl',
      licence: 'CC BY-SA 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/3.0',
      source: 'https://commons.wikimedia.org/wiki/File:Amanita_virosa_qtl1.jpg',
    ),
  ],
  'Kiefernsteinpilz': [
    (
      asset: 'assets/species/kiefernsteinpilz-1.webp',
      author: 'LitvinovSS, Bearbeitung Ak ccm',
      licence: 'CC BY 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by/3.0',
      source: 'https://commons.wikimedia.org/wiki/File:Boletus_pinophilus_cropped.jpg',
    ),
  ],
  'Lachsreizker': [
    (
      asset: 'assets/species/lachsreizker-1.webp',
      author: 'Holger Krisp',
      licence: 'CC BY 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by/3.0',
      source: 'https://commons.wikimedia.org/wiki/File:Lachs-Reizker_(Lactarius_salmonicolor).JPG',
    ),
  ],
  'Lungenseitling': [
    (
      asset: 'assets/species/lungenseitling-1.webp',
      author: 'Amanita77',
      licence: 'CC BY-SA 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/3.0',
      source: 'https://commons.wikimedia.org/wiki/File:Pleurotus_pulmonarius.001.COPY.jpg',
    ),
  ],
  'Netzstieliger Hexenröhrling': [
    (
      asset: 'assets/species/netzstieligerhexenroehrling-1.webp',
      author: 'George Chernilevsky',
      licence: 'Public domain',
      licenceUrl: 'https://creativecommons.org/publicdomain/mark/1.0/',
      source: 'https://commons.wikimedia.org/wiki/File:Boletus_luridus_2011_G1.jpg',
    ),
  ],
  'Pfifferling': [
    (
      asset: 'assets/species/pfifferling-1.webp',
      author: 'Heisenberg-pl',
      licence: 'CC BY-SA 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/3.0',
      source: 'https://commons.wikimedia.org/wiki/File:Cantharellus_cibarius_20090717-02.jpg',
    ),
  ],
  'Scheidenstreifling': [
    (
      asset: 'assets/species/scheidenstreifling-1.webp',
      author: 'Stu\'s Images',
      licence: 'CC BY-SA 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/3.0',
      source: 'https://commons.wikimedia.org/wiki/File:Amanita_vaginata,_Grisette,_UK.jpg',
    ),
  ],
  'Schönfußröhrling': [
    (
      asset: 'assets/species/schoenfussroehrling-1.webp',
      author: 'Jerzy Opioła',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'https://commons.wikimedia.org/wiki/File:Boletus_calopus_a1.jpg',
    ),
  ],
  'Sommersteinpilz': [
    (
      asset: 'assets/species/sommersteinpilz-1.webp',
      author: 'Archenzo, Bearbeitung Ak ccm',
      licence: 'CC BY-SA 3.0',
      licenceUrl: 'http://creativecommons.org/licenses/by-sa/3.0/',
      source: 'https://commons.wikimedia.org/wiki/File:2006-10-07_Boletus_aestivalis_cropped.jpg',
    ),
  ],
  'Trompetenpfifferling': [
    (
      asset: 'assets/species/trompetenpfifferling-1.webp',
      author: 'Ben Mitchell - Wildeep',
      licence: 'Public domain',
      licenceUrl: 'https://creativecommons.org/publicdomain/mark/1.0/',
      source: 'https://commons.wikimedia.org/wiki/File:Cantharellus_tubaeformis2.JPG',
    ),
  ],
  // ── Warnarten, ebenfalls von Commons ─────────────────────────────
  //
  // **Eine Seite, die warnt, sollte zeigen wovor.** Diese 14 waren nach
  // der ersten Tranche die letzten Arten mit einer Einstufung, die
  // warnt, und ohne jedes Bild. Auch sie sind Platzhalter.
  'Böhmische Verpel': [
    (
      asset: 'assets/species/boehmischeverpel-1.webp',
      author: 'Ireen Trummer',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'https://commons.wikimedia.org/wiki/File:Kurrel.JPG',
    ),
  ],
  'Frühjahrsknollenblätterpilz': [
    (
      asset: 'assets/species/fruehjahrsknollenblaetterpilz-1.webp',
      author: 'Sinisa Radic',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'https://commons.wikimedia.org/wiki/File:Amanita_verna_2.jpg',
    ),
  ],
  'Fuchsiger Rötelritterling': [
    (
      asset: 'assets/species/fuchsigerroetelritterling-1.webp',
      author: 'NorbertNagel',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'https://commons.wikimedia.org/wiki/File:2025_-_Fuchsiger_Roetelritterling_-_Tawny_Funnel_Cap_-_01.jpg',
    ),
  ],
  'Grünling': [
    (
      asset: 'assets/species/gruenling-1.webp',
      author: 'Aorg1961',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'https://commons.wikimedia.org/wiki/File:G%C4%85ska_zielonka_3148095286_71aaf31eab_o.jpg',
    ),
  ],
  'Kahler Krempling': [
    (
      asset: 'assets/species/kahlerkrempling-1.webp',
      author: 'Achim Lammerts (Syntaxys)',
      licence: 'CC BY-SA 4.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/4.0',
      source: 'https://commons.wikimedia.org/wiki/File:2025-10-15_D500-0990_Achim-Lammerts_Paxillus-involutus.jpg',
    ),
  ],
  'Nebelkappe': [
    (
      asset: 'assets/species/nebelkappe-1.webp',
      author: 'Archenzo, Bearbeitung Ak ccm',
      licence: 'CC BY-SA 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/3.0',
      source: 'https://commons.wikimedia.org/wiki/File:2008-11-22_Clitocybe_nebularis.jpg',
    ),
  ],
  'Orangefuchsiger Raukopf': [
    (
      asset: 'assets/species/orangefuchsigerraukopf-1.webp',
      author: 'Thomas Pruß',
      licence: 'CC BY-SA 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/3.0',
      source: 'https://commons.wikimedia.org/wiki/File:Cortinarius_orellanus_(1).JPG',
    ),
  ],
  'Riesenrötling': [
    (
      asset: 'assets/species/riesenroetling-1.webp',
      author: 'Gerhard Koller',
      licence: 'CC BY-SA 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/3.0',
      source: 'https://commons.wikimedia.org/wiki/File:Entoloma_sinuatum_40542.jpg',
    ),
  ],
  'Safranschirmling': [
    (
      asset: 'assets/species/safranschirmling-1.webp',
      author: 'Strobilomyces',
      licence: 'CC BY-SA 3.0',
      licenceUrl: 'http://creativecommons.org/licenses/by-sa/3.0/',
      source: 'https://commons.wikimedia.org/wiki/File:Chlorophyllum_olivieri_20061022wa.jpg',
    ),
  ],
  'Speitäubling': [
    (
      asset: 'assets/species/speitaeubling-1.webp',
      author: 'Dohduhdah',
      licence: 'Public domain',
      licenceUrl: 'https://creativecommons.org/publicdomain/mark/1.0/',
      source: 'https://commons.wikimedia.org/wiki/File:Mushroom-IMG_4384.JPG',
    ),
  ],
  'Spitzgebuckelter Raukopf': [
    (
      asset: 'assets/species/spitzgebuckelterraukopf-1.webp',
      author: 'Andreas Kunze',
      licence: 'CC BY-SA 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/3.0',
      source: 'https://commons.wikimedia.org/wiki/File:2006-07-12_Cortinarius_rubellus_1.jpg',
    ),
  ],
  'Tigerritterling': [
    (
      asset: 'assets/species/tigerritterling-1.webp',
      author: 'Ron Pastorino (Mushroom Observer)',
      licence: 'CC BY-SA 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/3.0',
      source: 'https://commons.wikimedia.org/wiki/File:2008-11-26_Tricholoma_pardinum_Qu%C3%A9l_30173.jpg',
    ),
  ],
  'Ziegelroter Risspilz': [
    (
      asset: 'assets/species/ziegelroterrisspilz-1.webp',
      author: 'Andreas Kunze',
      licence: 'CC BY-SA 3.0',
      licenceUrl: 'https://creativecommons.org/licenses/by-sa/3.0',
      source: 'https://commons.wikimedia.org/wiki/File:2010-04-27_Inocybe_erubescens.jpg',
    ),
  ],
  'Ziegenbart': [
    (
      asset: 'assets/species/ziegenbart-1.webp',
      author: 'Jason Hollinger',
      licence: 'CC BY 2.0',
      licenceUrl: 'https://creativecommons.org/licenses/by/2.0',
      source: 'https://commons.wikimedia.org/wiki/File:2010-09-17_Ramaria_botrytis.jpg',
    ),
  ],
};

/// Die Porträts zu einem Artnamen — leer, wenn keine gepflegt sind.
List<SpeciesPhoto> portraitsFor(String? species) {
  final canonical = canonicalSpecies(species);
  return canonical == null ? const [] : speciesPortraits[canonical] ?? const [];
}

/// Der Satz, der IMMER unter den Bildern steht.
///
/// **Die ganze Aussage steht außerhalb des Ausklappers**, seit 1.176.0
/// auch „können falsch zugeordnet sein": Das ist der Satz, wegen dem
/// der Hinweis überhaupt da ist, und hinter einem Tipp versteckt wäre
/// er Deko. Eingeklappt ist nur, WARUM ein Foto nicht reicht.
///
/// **Er gilt für beide Quellen und nennt deshalb keine.** Eigene
/// Aufnahmen und Commons-Material stehen im selben Streifen
/// nebeneinander, und wer welches Bild gemacht hat, steht ohnehin in
/// der Zeile darüber. Zwei Hinweise für zwei Herkünfte wären zwei
/// Antworten auf dieselbe Frage (Betreiber, 2026-09-22).
///
/// **Ohne „wir".** Der erste Entwurf schrieb „Bestimmt haben sie wir,
/// nicht ein Pilzsachverständiger" — grammatisch falsch und um eine
/// Aussage herumgebaut, die niemanden weiterbringt. Wer die Bilder
/// zugeordnet hat, ändert für den Leser nichts; dass sie falsch sein
/// können, ändert alles.
const kPhotoDisclaimer =
    'Bilder können falsch zugeordnet sein und wurden nicht von einem '
    'Pilzsachverständigen geprüft. Im Zweifel den Pilz stehen lassen.';

/// Die Überschrift des aufklappbaren Teils.
const kPhotoDisclaimerTitle = 'Warum ein Foto nicht zum Bestimmen reicht';

/// Was beim Aufklappen erscheint — die Begründung zu [kPhotoDisclaimer].
const kPhotoDisclaimerDetail =
    'Ein Foto zeigt nur ein einzelnes Exemplar. Farbe, Form und Größe '
    'ändern sich mit Alter, Wetter und Standort. Was wirklich '
    'entscheidet, liegt oft dort, wo kein Bild hinkommt: an der '
    'Stielbasis, im Schnitt, im Geruch.\n\n'
    'Ein Pilzsachverständiger sieht sich einen Fund an. Die Deutsche '
    'Gesellschaft für Mykologie vermittelt sie ortsnah.';

SpeciesPhoto? photoFor(String? species) {
  final canonical = canonicalSpecies(species);
  return canonical == null ? null : speciesPhotos[canonical];
}

/// Die Zeile unter einem Bild. **Kurz, aber vollständig**: Urheber und
/// Lizenz stehen am Bild, der Rest (Lizenztext, Fundstelle) auf der
/// Lizenzseite.
String photoCredit(SpeciesPhoto photo) =>
    'Foto: ${photo.author} · ${photo.licence}';

/// Der Block für die Lizenzseite — je Bild Art, Urheber, Lizenz und
/// Fundstelle.
///
/// **Aus derselben Tabelle wie die Anzeige.** Eine zweite, von Hand
/// gepflegte Liste in `map_data_license.dart` wäre die Stelle, an der ein
/// getauschtes Bild seinen alten Urheber behält — und eine falsche
/// Namensnennung ist schlimmer als gar keine.
String speciesPhotoCredits() => [
      for (final entry in allSpeciesPhotos())
        '${entry.species}: ${entry.photo.author}, ${entry.photo.licence}\n'
            '${entry.photo.licenceUrl}\n${entry.photo.source}',
    ].join('\n\n');

/// Jedes Bild der App mit seiner Art — Vergleichspaare UND Porträts.
///
/// **Eine Naht, zwei Tabellen.** Die Lizenzseite und der Test, der die
/// Lizenzen prüft, dürfen nicht je selbst wissen müssen, welche Tabellen
/// es gibt: Eine dritte Bildquelle würde sonst an beiden Stellen
/// vergessen, und ein nicht genanntes Bild ist ein Lizenzverstoß.
Iterable<({String species, SpeciesPhoto photo})> allSpeciesPhotos() sync* {
  for (final entry in speciesPhotos.entries) {
    yield (species: entry.key, photo: entry.value);
  }
  for (final entry in speciesPortraits.entries) {
    for (final photo in entry.value) {
      yield (species: entry.key, photo: photo);
    }
  }
}
