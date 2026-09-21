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
      for (final entry in speciesPhotos.entries)
        '${entry.key}: ${entry.value.author}, ${entry.value.licence}\n'
            '${entry.value.licenceUrl}\n${entry.value.source}',
    ].join('\n\n');
