// Essbar oder giftig — die Einstufung je Art (#511 Folgeschritt).
//
// **Die Fehlerrichtung ist vorgegeben, und sie ist nicht symmetrisch.**
// Ein zu vorsichtiges „Ungenießbar" über einem guten Speisepilz kostet
// eine Mahlzeit. Ein zu großzügiges „Gilt als Speisepilz" über einem
// Giftpilz kostet eine Leber. Deshalb gilt hier überall: Im Zweifel die
// Warnung, und wo die Literatur uneins ist, steht das als eigene Stufe
// da statt als Entscheidung, die wir nicht treffen können.
//
// **Die App sagt damit nichts darüber, was jemand in der Hand hält.**
// Diese Tabelle ordnet NAMEN Stufen zu, nicht Pilzen. Wer sich bei der
// Bestimmung irrt, liest hier die Einstufung des falschen Pilzes — und
// genau deshalb steht auf der Detailseite der Satz, dass PilzBuddy
// nicht bestimmt. Die Stufe ersetzt keinen Pilzsachverständigen.
//
// **Woran sie sich orientiert:** an der gängigen deutschsprachigen
// Bewertung, wie sie die Deutsche Gesellschaft für Mykologie in ihrer
// Artenliste zur Speisepilzbewertung führt — inklusive der Kategorie
// „uneinheitlich beurteilte Arten", die es hier als [Edibility.umstritten]
// gibt. Sie ist von Hand gepflegt und maschinell nicht nachprüfbar; was
// sie belastbar hält, ist der Test, der für JEDE bekannte Art einen
// Eintrag verlangt — eine neue Art zwingt zu einer Entscheidung, statt
// stillschweigend ohne Einstufung zu erscheinen.
import 'mushroom_species.dart';

/// Die Stufen — grob mit Absicht.
///
/// Feiner zu unterteilen („essbar, aber minderwertig", „nur die Hüte")
/// wäre Kochbuchwissen und eine Genauigkeit, die eine Zeile in einer App
/// nicht tragen kann. Was darüber hinaus wichtig ist, steht im
/// Freitext daneben.
enum Edibility {
  speisepilz('Gilt als Speisepilz'),

  /// Roh giftig — die häufigste Falle bei ausdrücklichen Speisepilzen
  /// (Hallimasch, Perlpilz, Morcheln, Austernseitling).
  nurGegart('Nur gegart, roh giftig'),

  /// Die Literatur ist uneins, oder der deutsche Name meint mehrere
  /// Arten mit verschiedener Bewertung. **Das ist eine Auskunft, keine
  /// Einladung**: „unklar" heißt hier „nicht essen".
  umstritten('Uneinheitlich beurteilt'),

  /// Nicht giftig, aber kein Essen — bitter, zäh, geschmacklos.
  ungeniessbar('Ungenießbar'),

  giftig('Giftig'),
  toedlichGiftig('Tödlich giftig');

  const Edibility(this.label);

  final String label;

  /// Trägt die Stufe eine Warnung, die auch in der LISTE Platz
  /// verdient? Nur die beiden giftigen — die Zeile ist voll, und knappen
  /// Platz bekommt die Fehlerrichtung, die wehtut.
  bool get warnsInList => this == giftig || this == toedlichGiftig;

  /// Für die Farbe: alles außer „Speisepilz" wird hervorgehoben.
  /// **„Speisepilz" bekommt bewusst kein Grün** — Grün läse sich als
  /// Freigabe, und freigeben kann die App nichts.
  bool get isWarning => this != speisepilz;
}

/// Was zu einer Art über das Essen bekannt ist.
typedef EdibilityEntry = ({Edibility level, String? note});

/// Die Tabelle. Reihenfolge wie [kBekannteArten], damit sich beide
/// nebeneinander lesen lassen.
///
/// **Der Freitext steht da, wo die Stufe allein in die Irre führt** —
/// bei Verwechslungen, die Menschen umgebracht haben, bei Arten, die
/// jahrzehntelang als Speisepilz galten, und bei deutschen Namen, die
/// eine ganze Gattung meinen. Wo die Stufe für sich spricht, bleibt er
/// leer; eine Bemerkung an jeder Zeile wäre Lärm, in dem die wichtigen
/// untergehen.
const speciesEdibility = <String, EdibilityEntry>{
  // Röhrlinge
  'Steinpilz': (level: Edibility.speisepilz, note: null),
  'Sommersteinpilz': (level: Edibility.speisepilz, note: null),
  'Kiefernsteinpilz': (level: Edibility.speisepilz, note: null),
  'Bronzeröhrling': (level: Edibility.speisepilz, note: null),
  'Maronenröhrling': (level: Edibility.speisepilz, note: null),
  'Birkenpilz': (level: Edibility.nurGegart, note: null),
  'Rotkappe': (
    level: Edibility.speisepilz,
    note: 'Der Name meint mehrere Arten der Gattung Leccinum; sie gelten '
        'alle als Speisepilze und sind alle roh unverträglich.'
  ),
  'Espenrotkappe': (level: Edibility.nurGegart, note: null),
  'Birkenrotkappe': (level: Edibility.nurGegart, note: null),
  'Butterpilz': (
    level: Edibility.speisepilz,
    note: 'Die schleimige Huthaut wird meist abgezogen; sie kann '
        'abführend wirken.'
  ),
  'Goldröhrling': (level: Edibility.speisepilz, note: null),
  'Sandröhrling': (level: Edibility.speisepilz, note: null),
  'Ziegenlippe': (level: Edibility.speisepilz, note: null),
  'Rotfußröhrling': (level: Edibility.speisepilz, note: null),
  'Körnchenröhrling': (level: Edibility.speisepilz, note: null),
  'Flockenstieliger Hexenröhrling': (
    level: Edibility.nurGegart,
    note: 'Roh giftig. Gegart ein geschätzter Speisepilz — die Blaufärbung '
        'beim Anschnitt ist kein Giftzeichen.'
  ),
  'Netzstieliger Hexenröhrling': (
    level: Edibility.nurGegart,
    note: 'Roh giftig, und auch gegart nicht von jedem vertragen.'
  ),
  'Gallenröhrling': (
    level: Edibility.ungeniessbar,
    note: 'Bitter, nicht giftig — ein einziger verdirbt aber ein ganzes '
        'Gericht. Wird mit dem Steinpilz verwechselt.'
  ),
  'Satansröhrling': (level: Edibility.giftig, note: null),

  // Leistlinge
  'Pfifferling': (level: Edibility.speisepilz, note: null),
  'Trompetenpfifferling': (level: Edibility.speisepilz, note: null),
  'Herbsttrompete': (level: Edibility.speisepilz, note: null),
  'Falscher Pfifferling': (
    level: Edibility.umstritten,
    note: 'Uneinheitlich beurteilt — nicht giftig im engeren Sinn, kann '
        'aber Magen-Darm-Beschwerden auslösen.'
  ),

  // Champignons
  'Wiesenchampignon': (
    level: Edibility.speisepilz,
    note: 'Junge Champignons werden mit jungen Knollenblätterpilzen '
        'verwechselt — die haben weiße Lamellen und eine Scheide am '
        'Stielgrund.'
  ),
  'Stadtchampignon': (level: Edibility.speisepilz, note: null),
  'Anischampignon': (level: Edibility.speisepilz, note: null),
  'Waldchampignon': (level: Edibility.speisepilz, note: null),
  'Karbolchampignon': (
    level: Edibility.giftig,
    note: 'Läuft an der Stielbasis chromgelb an und riecht beim Erhitzen '
        'nach Karbol. Die häufigste Champignon-Vergiftung.'
  ),

  // Schirmlinge
  'Parasol': (level: Edibility.speisepilz, note: null),
  'Safranschirmling': (
    level: Edibility.umstritten,
    note: 'Der Name meint mehrere Arten der Gattung Chlorophyllum. Roh '
        'giftig, und auch gegart werden sie nicht von jedem vertragen.'
  ),
  'Schopftintling': (
    level: Edibility.speisepilz,
    note: 'Nur solange die Lamellen weiß sind — er zerfließt innerhalb '
        'weniger Stunden zu schwarzer Tinte.'
  ),

  // Wulstlinge
  'Fliegenpilz': (level: Edibility.giftig, note: null),
  'Perlpilz': (
    level: Edibility.nurGegart,
    note: 'Roh giftig. Wird mit dem giftigen Pantherpilz verwechselt — '
        'der eine rötet im Fleisch und an Fraßstellen, der andere nicht.'
  ),
  'Pantherpilz': (level: Edibility.giftig, note: null),
  'Grüner Knollenblätterpilz': (
    level: Edibility.toedlichGiftig,
    note: 'Die mit Abstand häufigste tödliche Pilzvergiftung in '
        'Mitteleuropa. Die Beschwerden beginnen erst Stunden später, wenn '
        'die Leber bereits geschädigt ist.'
  ),
  'Kegelhütiger Knollenblätterpilz': (level: Edibility.toedlichGiftig, note: null),
  'Frühjahrsknollenblätterpilz': (level: Edibility.toedlichGiftig, note: null),
  'Scheidenstreifling': (
    level: Edibility.nurGegart,
    note: 'Roh giftig. Ein Wulstling ohne Ring — die Verwechslung geht in '
        'Richtung der Knollenblätterpilze.'
  ),

  // Täublinge und Milchlinge
  'Frauentäubling': (level: Edibility.speisepilz, note: null),
  'Speisetäubling': (level: Edibility.speisepilz, note: null),
  'Ledertäubling': (level: Edibility.speisepilz, note: null),
  'Grüngefelderter Täubling': (
    level: Edibility.speisepilz,
    note: 'Grünhütige Täublinge werden mit dem Grünen Knollenblätterpilz '
        'verwechselt — Täublinge haben keine Scheide und keinen Ring.'
  ),
  'Speitäubling': (
    level: Edibility.giftig,
    note: 'Brennend scharf; führt roh zu Erbrechen.'
  ),
  'Fichtenreizker': (level: Edibility.speisepilz, note: null),
  'Edelreizker': (level: Edibility.speisepilz, note: null),
  'Lachsreizker': (level: Edibility.speisepilz, note: null),
  'Kiefernreizker': (level: Edibility.speisepilz, note: null),
  'Mohrenkopfmilchling': (level: Edibility.speisepilz, note: null),
  'Brätling': (level: Edibility.speisepilz, note: null),

  // Morcheln und Lorcheln
  'Speisemorchel': (
    level: Edibility.nurGegart,
    note: 'Roh giftig — das gilt für alle Morcheln.'
  ),
  'Spitzmorchel': (level: Edibility.nurGegart, note: null),
  'Frühjahrslorchel': (
    level: Edibility.toedlichGiftig,
    note: 'Trotz des wissenschaftlichen Namens „esculenta" (essbar): Das '
        'Gift Gyromitrin ist flüchtig, aber auch die Dämpfe beim Kochen '
        'sind gefährlich. Galt früher als Speisepilz.'
  ),
  'Käppchenmorchel': (level: Edibility.nurGegart, note: null),
  'Morchelbecherling': (level: Edibility.nurGegart, note: null),
  'Böhmische Verpel': (
    level: Edibility.umstritten,
    note: 'Uneinheitlich beurteilt — roh giftig, und auch gegart sind '
        'Unverträglichkeiten beschrieben.'
  ),

  // Boviste
  'Riesenbovist': (
    level: Edibility.speisepilz,
    note: 'Nur solange das Fleisch rein weiß ist. Gelb oder braun heißt: '
        'reife Sporen, nicht mehr essbar.'
  ),
  'Flaschenstäubling': (
    level: Edibility.speisepilz,
    note: 'Nur jung und innen rein weiß. Halbiert man einen Stäubling und '
        'sieht darin einen angelegten Pilz, ist es ein junger '
        'Knollenblätterpilz.'
  ),
  'Birnenstäubling': (level: Edibility.speisepilz, note: null),

  // Baumpilze
  'Austernseitling': (level: Edibility.nurGegart, note: null),
  'Lungenseitling': (level: Edibility.nurGegart, note: null),
  'Schwefelporling': (
    level: Edibility.nurGegart,
    note: 'Nur die jungen, weichen Ränder. An Eibe, Robinie und Eukalyptus '
        'gewachsen gilt er als unverträglich.'
  ),
  'Leberpilz': (level: Edibility.speisepilz, note: null),
  'Judasohr': (level: Edibility.nurGegart, note: null),

  // Stachel- und Korallenpilze
  'Krause Glucke': (level: Edibility.speisepilz, note: null),
  'Semmelstoppelpilz': (level: Edibility.speisepilz, note: null),
  'Habichtspilz': (
    level: Edibility.speisepilz,
    note: 'Jung mild, mit dem Alter zunehmend bitter.'
  ),
  'Ziegenbart': (
    level: Edibility.umstritten,
    note: 'Der Name meint die ganze Gattung Ramaria. Einige Arten gelten '
        'als Speisepilze, andere wirken abführend, und auseinanderhalten '
        'lassen sie sich im Feld kaum.'
  ),
  'Igelstachelbart': (
    level: Edibility.speisepilz,
    note: 'In Deutschland besonders geschützt — wild wachsende Exemplare '
        'dürfen nicht gesammelt werden. Im Handel stammt er aus Zucht.'
  ),

  // Lamellenpilze
  'Stockschwämmchen': (
    level: Edibility.nurGegart,
    note: 'Wird mit dem tödlich giftigen Gifthäubling verwechselt, der am '
        'selben Holz wächst. Ohne sichere Bestimmung nicht sammeln.'
  ),
  'Maipilz': (
    level: Edibility.speisepilz,
    note: 'Zur selben Zeit am selben Ort wachsen der giftige Ziegelrote '
        'Risspilz und der Riesenrötling.'
  ),
  'Nelkenschwindling': (level: Edibility.speisepilz, note: null),
  'Rehbrauner Dachpilz': (level: Edibility.speisepilz, note: null),
  'Riesenträuschling': (level: Edibility.speisepilz, note: null),
  'Hallimasch': (
    level: Edibility.nurGegart,
    note: 'Roh giftig, und auch gegart nicht von jedem vertragen. Das '
        'Kochwasser wird üblicherweise weggegossen.'
  ),
  'Dunkler Hallimasch': (level: Edibility.nurGegart, note: null),
  'Violetter Rötelritterling': (level: Edibility.nurGegart, note: null),
  'Fuchsiger Rötelritterling': (
    level: Edibility.umstritten,
    note: 'Uneinheitlich beurteilt — roh giftig, und Unverträglichkeiten '
        'sind auch gegart beschrieben.'
  ),
  'Nebelkappe': (
    level: Edibility.umstritten,
    note: 'Galt lange als Speisepilz und steht heute zugleich auf der '
        'Giftpilzliste: häufige Unverträglichkeiten, dazu der Verdacht '
        'einer erbgutschädigenden Wirkung.'
  ),
  'Mönchskopf': (level: Edibility.speisepilz, note: null),
  'Reifpilz': (level: Edibility.speisepilz, note: null),
  'Samtfußrübling': (
    level: Edibility.nurGegart,
    note: 'Roh giftig. Wächst im Winter am selben Holz wie der tödlich '
        'giftige Gifthäubling.'
  ),
  'Gifthäubling': (
    level: Edibility.toedlichGiftig,
    note: 'Dasselbe Gift wie im Grünen Knollenblätterpilz. Wird mit dem '
        'Stockschwämmchen verwechselt.'
  ),
  'Grünblättriger Schwefelkopf': (level: Edibility.giftig, note: null),
  'Kahler Krempling': (
    level: Edibility.toedlichGiftig,
    note: 'Wurde jahrzehntelang als Speisepilz gesammelt. Das Gift wirkt '
        'nicht beim ersten Mal: Der Körper bildet Antikörper, und irgendwann '
        'zerstören sie nach einer Mahlzeit die roten Blutkörperchen.'
  ),
  'Spitzgebuckelter Raukopf': (
    level: Edibility.toedlichGiftig,
    note: 'Zerstört die Nieren. Die ersten Beschwerden kommen erst nach '
        'Tagen bis Wochen — bis dahin denkt niemand mehr an den Pilz.'
  ),
  'Orangefuchsiger Raukopf': (level: Edibility.toedlichGiftig, note: null),
  'Riesenrötling': (level: Edibility.giftig, note: null),
  'Tigerritterling': (level: Edibility.giftig, note: null),
  'Ziegelroter Risspilz': (
    level: Edibility.giftig,
    note: 'Enthält viel Muscarin; schwere Verläufe sind lebensbedrohlich.'
  ),
  'Grünling': (
    level: Edibility.giftig,
    note: 'Galt bis um 2000 als guter Speisepilz. Nach mehreren großen '
        'Mahlzeiten an aufeinanderfolgenden Tagen sind Todesfälle durch '
        'Muskelzerfall beschrieben.'
  ),
  'Violetter Lacktrichterling': (level: Edibility.speisepilz, note: null),
};

/// Die Einstufung zu einem Artnamen — `null` für eigene Arten der
/// Nutzer und alles, was nicht in der Liste steht.
///
/// **`null` heißt „wir sagen nichts dazu"**, nicht „unbedenklich".
/// Zweitnamen lösen sich auf: Wer „Marone" schreibt, bekommt die
/// Einstufung des Maronenröhrlings.
EdibilityEntry? edibilityFor(String? species) {
  final canonical = canonicalSpecies(species);
  return canonical == null ? null : speciesEdibility[canonical];
}

/// Der Satz unter der Einstufung — einmal formuliert, damit er überall
/// gleich lautet.
///
/// Er nennt die zwei Dinge, die eine Stufe allein nicht sagen kann: dass
/// sie am NAMEN hängt und nicht am Pilz in der Hand, und dass Rohverzehr
/// auch bei Speisepilzen die Ausnahme ist.
const kEdibilityDisclaimer =
    'Die Einstufung gilt der Art, nicht dem Pilz in deinem Korb — sie '
    'ersetzt keine Bestimmung. Roh sind auch die meisten Speisepilze '
    'unverträglich.';
