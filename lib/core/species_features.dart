// Die gängigen Bestimmungsmerkmale je Art.
//
// **Das ist der Abschnitt, bei dem die App am weitesten geht** — und
// deshalb der, der am klarsten sagen muss, was er nicht ist. Er
// beschreibt, woran eine Art in der Literatur erkannt wird. Er sagt
// nicht, was jemand in der Hand hält, und er ersetzt keinen
// Pilzsachverständigen. Die Seite trägt diesen Satz mit.
//
// **Sechs Felder, immer dieselben**, in der Reihenfolge, in der man einen
// Pilz auch ansieht: Hut, Unterseite, Stiel, Fleisch, Geruch, Vorkommen.
// Ein festes Raster hat einen Grund, der über Ordnung hinausgeht: Wer
// zwei Arten vergleicht, liest dieselbe Zeile zweimal. Freitext in
// wechselnder Reihenfolge macht genau das unmöglich.
//
// **Wo ein Merkmal nicht zutrifft, steht das da** — nicht nichts. „Keine
// Lamellen" ist bei einer Morchel die Auskunft; ein leeres Feld sähe aus
// wie eine Lücke.
//
// **Gepflegt für JEDE bekannte Art**, seit 1.169.0. Davor galt eine
// engere Regel — Arten mit einem Verwechslungspartner plus die giftigen
// —, und die hat am falschen Ende gemessen: am Giftpilz statt am
// Sammler. Die vier Reizker sind Speisepilze ohne eingetragenen Partner
// und fielen durch beide Siebe; ihre Seite sagte über den Pilz kein
// Wort. So gemeldet vom Betreiber am 2026-09-22, und es betraf 30
// Arten, fast alle Speisepilze.
//
// `test/species_features_test.dart` rechnet die Menge nach: Eine neue
// Art OHNE Merkmale macht den Lauf rot. Das ist die teurere Pflicht,
// aber die billigere Alternative war eine Detailseite, die über den
// Pilz schweigt.
import 'mushroom_species.dart';

/// Die sechs Felder. Alle sind Pflicht; „trifft nicht zu" wird
/// ausgeschrieben.
typedef SpeciesFeatures = ({
  /// Form, Farbe, Oberfläche, Größe.
  String hut,

  /// Was unter dem Hut sitzt: Röhren, Lamellen, Leisten, Stacheln —
  /// Farbe und wie sie am Stiel ansetzen.
  String unterseite,

  /// Form, Oberfläche, Ring, Netz, Scheide, Knolle.
  String stiel,

  /// Farbe, Verfärbung im Schnitt, Konsistenz, Milch.
  String fleisch,

  /// Geruch und Geschmack — bei vielen Arten das Merkmal, das entscheidet.
  String geruch,

  /// Wo, woran und wann: Substrat, Baumpartner, Jahreszeit.
  String vorkommen,
});

/// Die Tabelle. Reihenfolge wie in [kBekannteArten].
const speciesFeatures = <String, SpeciesFeatures>{
  // ── Röhrlinge ────────────────────────────────────────────────────
  'Steinpilz': (
    hut: 'Fünf bis 25 cm, halbkugelig bis polsterförmig, hell- bis '
        'dunkelbraun, matt, bei Feuchtigkeit leicht klebrig; der Rand '
        'bleibt oft heller.',
    unterseite: 'Röhren, jung weiß, später gelb bis olivgrün; am Stiel '
        'ausgebuchtet angewachsen und leicht vom Hut zu lösen.',
    stiel: 'Bauchig bis keulig, weißlich bis hellbraun, mit feinem '
        'WEISSEM Netz auf hellem Grund, meist nur im oberen Teil.',
    fleisch: 'Weiß und fest, verfärbt sich im Schnitt NICHT; unter der '
        'Huthaut bleibt es weiß.',
    geruch: 'Angenehm nussig, mild im Geschmack.',
    vorkommen: 'Mykorrhiza bei Fichte, Kiefer, Buche und Eiche; Juni bis '
        'November, Hauptzeit August und September.',
  ),
  'Sommersteinpilz': (
    hut: 'Sechs bis 20 cm, hell- bis ockerbraun, matt und feinsamtig; die '
        'Huthaut reißt bei Trockenheit FEINRISSIG auf.',
    unterseite: 'Röhren jung weiß, später gelb bis olivgrün, ausgebuchtet '
        'angewachsen.',
    stiel: 'Bauchig, hellbraun, mit weißem Netz über den GANZEN Stiel bis '
        'zur Basis — beim Steinpilz nur oben.',
    fleisch: 'Weiß und fest, unverändert im Schnitt; im Alter schnell '
        'weich.',
    geruch: 'Nussig, mild — wie der Steinpilz.',
    vorkommen: 'Wärmeliebend bei Eiche und Buche; schon ab Mai bis '
        'Oktober, der früheste der Steinpilze.',
  ),
  'Kiefernsteinpilz': (
    hut: 'Sechs bis 25 cm, rotbraun bis weinbraun, jung fast kugelig, '
        'matt, oft mit runzeliger Oberfläche.',
    unterseite: 'Röhren jung weiß, später gelblich bis olivgrün.',
    stiel: 'Kräftig bauchig, rötlichbraun getönt, mit weißem bis '
        'rötlichem Netz im oberen Teil.',
    fleisch: 'Weiß, unter der Huthaut rötlich, unverändert im Schnitt.',
    geruch: 'Nussig und mild, wie beim Steinpilz.',
    vorkommen: 'Bei Kiefer und Fichte auf sauren, sandigen Böden, oft im '
        'Gebirge; Juni bis Oktober.',
  ),
  'Bronzeröhrling': (
    hut: 'Sechs bis 20 cm, sehr dunkel bronze- bis schwarzbraun, jung '
        'samtig, wirkt fast rußig.',
    unterseite: 'Röhren jung weiß, später gelb bis olivgrün.',
    stiel: 'Bauchig, braun mit feinem weißlichem bis bräunlichem Netz.',
    fleisch: 'Weiß, fest, unverändert im Schnitt.',
    geruch: 'Angenehm nussig, mild.',
    vorkommen: 'Wärmeliebend bei Eiche und Edelkastanie, in Deutschland '
        'selten und im Süden; Juli bis September.',
  ),
  'Maronenröhrling': (
    hut: 'Fünf bis 15 cm, kastanien- bis dunkelbraun, jung samtig matt, '
        'bei Nässe schmierig glänzend.',
    unterseite: 'Röhren jung blassgelb, später grünlichgelb; auf Druck '
        'deutlich BLAUEND.',
    stiel: 'Schlank, hellbraun längsfaserig, OHNE Netz.',
    fleisch: 'Weißlich bis blassgelb, im Schnitt schwach blauend.',
    geruch: 'Mild, unauffällig pilzig.',
    vorkommen: 'Mykorrhiza vor allem bei Fichte und Kiefer, auf sauren '
        'Böden; Juli bis November.',
  ),
  'Birkenpilz': (
    hut: 'Fünf bis 15 cm, graubraun bis hellbraun, halbkugelig, später '
        'polsterförmig, trocken bis leicht schmierig.',
    unterseite: 'Röhren weißlich bis graubraun, auf Druck kaum '
        'verfärbend.',
    stiel: 'Lang und schlank, weißlich mit dunklen SCHÜPPCHEN in '
        'Längsreihen — kein Netz.',
    fleisch: 'Weiß, weich, im Alter schwammig; im Schnitt kaum '
        'verfärbend.',
    geruch: 'Mild und unauffällig.',
    vorkommen: 'Ausschließlich bei Birken; Juni bis Oktober.',
  ),
  'Butterpilz': (
    hut: 'Fünf bis zwölf cm, kastanienbraun, bei Feuchtigkeit stark '
        'SCHLEIMIG glänzend; die Huthaut lässt sich abziehen.',
    unterseite: 'Röhren blassgelb, fein, jung von einem weißen '
        'Velum bedeckt.',
    stiel: 'Gelblich, mit deutlichem häutigem RING; oberhalb davon fein '
        'gekörnelt.',
    fleisch: 'Weißlich bis gelb, weich, ohne Verfärbung.',
    geruch: 'Mild, schwach obstig.',
    vorkommen: 'Nur bei Kiefern, gern an Wegrändern und auf jungen '
        'Aufforstungen; Juni bis November.',
  ),
  'Körnchenröhrling': (
    hut: 'Vier bis zehn cm, ocker- bis rotbraun, schmierig glänzend.',
    unterseite: 'Röhren blassgelb; bei jungen Pilzen treten milchige '
        'TRÖPFCHEN aus den Poren.',
    stiel: 'Blassgelb, im oberen Teil fein gekörnelt — OHNE Ring.',
    fleisch: 'Blassgelb, weich, ohne Verfärbung.',
    geruch: 'Mild, unauffällig.',
    vorkommen: 'Bei Kiefern, oft auf kalkhaltigem Boden; Juni bis '
        'Oktober.',
  ),
  'Ziegenlippe': (
    hut: 'Vier bis zehn cm, ocker- bis olivbraun, samtig matt, im Alter '
        'oft feinrissig.',
    unterseite: 'Röhren leuchtend gelb, weit und eckig, auf Druck '
        'schwach blauend.',
    stiel: 'Blassgelb bis bräunlich, längsfaserig, ohne Rot.',
    fleisch: 'Weißlich bis blassgelb, unter der Huthaut NICHT rot.',
    geruch: 'Mild, schwach obstig.',
    vorkommen: 'Bei Laub- und Nadelbäumen, gern an moosigen Stellen; '
        'Juni bis Oktober.',
  ),
  'Rotfußröhrling': (
    hut: 'Drei bis acht cm, olivbraun, samtig, im Alter felderig '
        'aufreißend — in den Rissen zeigt sich ROTES Fleisch.',
    unterseite: 'Röhren gelb, weit, auf Druck blauend.',
    stiel: 'Schlank, gelblich mit deutlich ROTER Überfaserung.',
    fleisch: 'Gelblich, unter der Huthaut rötlich, im Schnitt schwach '
        'blauend.',
    geruch: 'Mild und unauffällig.',
    vorkommen: 'Bei Laub- und Nadelbäumen, häufig; Juni bis Oktober.',
  ),
  'Flockenstieliger Hexenröhrling': (
    hut: 'Sechs bis 20 cm, dunkel olivbraun bis schwarzbraun, samtig '
        'matt.',
    unterseite: 'Röhren ROT bis orangerot, auf Druck sofort '
        'schwarzblau.',
    stiel: 'Kräftig, gelb mit roten FLOCKEN — ausdrücklich ohne Netz.',
    fleisch: 'Gelb, im Schnitt augenblicklich tiefblau.',
    geruch: 'Mild, angenehm pilzig.',
    vorkommen: 'Bei Fichte, Buche und Eiche, auf sauren Böden; Mai bis '
        'Oktober.',
  ),
  'Netzstieliger Hexenröhrling': (
    hut: 'Acht bis 20 cm, olivbraun bis graubraun, samtig, bei Druck '
        'blauend.',
    unterseite: 'Röhren rot bis orangerot, sofort blauend; über den '
        'Röhren liegt eine rote Linie am Hutfleisch.',
    stiel: 'Gelb bis orange mit feinem ROTEM NETZ.',
    fleisch: 'Gelb, im Schnitt sofort dunkelblau.',
    geruch: 'Mild bis schwach säuerlich.',
    vorkommen: 'Bei Buche und Eiche auf kalkhaltigem Boden; Juni bis '
        'Oktober.',
  ),
  'Gallenröhrling': (
    hut: 'Fünf bis 15 cm, hell lederbraun, matt und trocken — dem '
        'Steinpilz täuschend ähnlich.',
    unterseite: 'Röhren jung weiß, später deutlich ROSA bis fleischrosa.',
    stiel: 'Hellbraun mit grobem, DUNKLEM Netz auf hellem Grund.',
    fleisch: 'Weiß, im Schnitt manchmal schwach rosa anlaufend.',
    geruch: 'Geruch unauffällig, Geschmack GALLENBITTER — ein winziges '
        'Stück auf der Zungenspitze genügt; ausspucken.',
    vorkommen: 'Bei Fichte und Buche auf sauren Böden, oft an '
        'Baumstümpfen; Juni bis Oktober.',
  ),
  'Satansröhrling': (
    hut: 'Zehn bis 30 cm, weißlich bis hellgrau, oft wie schmutzig '
        'wirkend, polsterförmig.',
    unterseite: 'Röhren jung gelb, bald ROT bis orangerot; auf Druck '
        'schwach blauend.',
    stiel: 'Dick und bauchig, gelb bis rot, mit feinem rotem NETZ.',
    fleisch: 'Weißlich bis gelblich, im Schnitt nur schwach blauend.',
    geruch: 'Alt unangenehm, aasartig süßlich.',
    vorkommen: 'Wärmeliebend bei Eiche, Buche und Linde auf Kalk; '
        'Juni bis September, im Norden selten.',
  ),
  'Schönfußröhrling': (
    hut: 'Fünf bis 15 cm, hell graubraun bis olivgrau, matt und '
        'feinfilzig — dem Steinpilz ähnlich.',
    unterseite: 'Röhren GELB, auch im Alter, auf Druck blauend — nie rot.',
    stiel: 'Kräftig, oben gelb, nach unten leuchtend ROT, mit feinem '
        'ROTEM NETZ; der „schöne Fuß", der ihm den Namen gibt.',
    fleisch: 'Blassgelb, im Schnitt blauend.',
    geruch: 'Unauffällig, Geschmack deutlich BITTER — ein Stückchen auf '
        'der Zunge genügt; ausspucken.',
    vorkommen: 'In Nadel- und Laubwäldern auf sauren Böden, häufig im '
        'Gebirge; Juli bis Oktober.',
  ),

  'Rotkappe': (
    hut: 'Fünf bis 20 cm, halbkugelig und lange geschlossen, orange bis '
        'ziegelrot; die Huthaut steht am Rand etwas über den Röhren '
        'vor.',
    unterseite: 'Röhren jung weißlich bis grau, auf Druck graubraun '
        'anlaufend, am Stiel frei bleibend und fein.',
    stiel: 'Lang und schlank, weißlich, dicht mit SCHUPPEN besetzt, die '
        'je nach Art weiß, rotbraun oder schwarz sind.',
    fleisch: 'Weiß, im Schnitt erst weinrot bis grau, dann schwarz '
        'anlaufend; jung fest, alt schwammig.',
    geruch: 'Angenehm pilzig, Geschmack mild.',
    vorkommen: 'Mykorrhiza bei Birke, Espe, Eiche und Nadelbäumen; der '
        'deutsche Name meint MEHRERE Arten. Juni bis Oktober.',
  ),
  'Espenrotkappe': (
    hut: 'Sechs bis 20 cm, leuchtend orangerot bis ziegelrot, trocken '
        'und feinfilzig, alt etwas runzelig.',
    unterseite: 'Röhren weißlich bis cremegrau, auf Druck bräunend, am '
        'Stiel ausgebuchtet angewachsen.',
    stiel: 'Kräftig und keulig, weiß, mit anfangs WEISSLICHEN, später '
        'rotbraunen Schuppen.',
    fleisch: 'Weiß, im Anschnitt rasch violettgrau und dann schwarz; '
        'fest und dickfleischig.',
    geruch: 'Angenehm pilzig, Geschmack mild — roh jedoch unverträglich.',
    vorkommen: 'Mykorrhiza bei Espe und Pappel, seltener bei Eiche; Juni '
        'bis Oktober.',
  ),
  'Birkenrotkappe': (
    hut: 'Fünf bis 20 cm, orange bis gelbbraun, matt und feinfilzig, mit '
        'deutlich überstehender Huthaut am Rand.',
    unterseite: 'Röhren grauweiß, auf Druck schmutzig grau; die Poren '
        'sind sehr fein und rund.',
    stiel: 'Hoch und schlank, weiß mit SCHWARZEN Schuppen, zur Basis hin '
        'oft blaugrün fleckend.',
    fleisch: 'Weiß, im Schnitt rosa bis graurot, dann schwarzgrau; im '
        'Stielgrund blaugrün.',
    geruch: 'Mild und unauffällig; roh unverträglich.',
    vorkommen: 'Mykorrhiza ausschließlich bei Birke, gern in feuchten '
        'Mooren und Heiden; Juni bis Oktober.',
  ),
  'Goldröhrling': (
    hut: 'Vier bis zwölf cm, goldgelb bis rotbraun, bei Feuchtigkeit '
        'stark SCHLEIMIG und glänzend, trocken lackartig.',
    unterseite: 'Röhren jung zitronengelb, später ockergelb, am Stiel '
        'kurz herablaufend; jung von einem Velum verdeckt.',
    stiel: 'Gelb, oberhalb des häutigen RINGES genetzt, unterhalb '
        'rotbraun gefleckt.',
    fleisch: 'Hellgelb, weich, im Schnitt kaum verfärbend.',
    geruch: 'Schwach säuerlich, Geschmack mild.',
    vorkommen: 'Mykorrhiza AUSSCHLIESSLICH bei Lärche; Juli bis Oktober.',
  ),
  'Sandröhrling': (
    hut: 'Fünf bis 14 cm, ockergelb bis semmelbraun, feinschuppig-körnig '
        'und nur bei Nässe leicht klebrig.',
    unterseite: 'Röhren jung olivgrau, später zimtbraun, sehr feinporig, '
        'auf Druck schwach blauend.',
    stiel: 'Kräftig und walzig, gelblich bis ockerbraun, ohne Ring und '
        'ohne Netz.',
    fleisch: 'Blassgelb, weich, im Schnitt schwach blauend.',
    geruch: 'Streng säuerlich, fast nach Chlor; Geschmack mild.',
    vorkommen: 'Mykorrhiza bei Kiefer auf Sandböden und in Heiden; Juli '
        'bis November.',
  ),

  // ── Leistlinge und Stachelpilze ──────────────────────────────────
  'Pfifferling': (
    hut: 'Drei bis zehn cm, dottergelb, jung gewölbt, später trichterig '
        'mit welligem, eingerolltem Rand.',
    unterseite: 'Stumpfe, dicke LEISTEN — keine echten Lamellen —, '
        'gegabelt und weit am Stiel herablaufend, in derselben Farbe wie '
        'der Hut.',
    stiel: 'Voll und fest, dottergelb, nach unten verjüngt, ohne '
        'scharfen Übergang zum Hut.',
    fleisch: 'Weißlich bis blassgelb, faserig, nicht brechend.',
    geruch: 'Deutlich nach Aprikose, Geschmack mild bis leicht pfeffrig.',
    vorkommen: 'Mykorrhiza bei Fichte, Buche und Eiche, gern in Moos; '
        'Juni bis Oktober.',
  ),
  'Falscher Pfifferling': (
    hut: 'Zwei bis sechs cm, orangegelb bis orangerot, samtig, mit '
        'lange eingerolltem Rand.',
    unterseite: 'Echte LAMELLEN, fein, dicht stehend, wiederholt '
        'gegabelt, kräftiger orange als der Hut.',
    stiel: 'Schlank, oft verbogen, orange, vom Hut deutlich abgesetzt.',
    fleisch: 'Weich, gelblich, dünn.',
    geruch: 'Unauffällig, kein Aprikosenduft.',
    vorkommen: 'Auf Nadelstreu, morschem Holz und in Heidegebieten; '
        'August bis November.',
  ),
  'Trompetenpfifferling': (
    hut: 'Zwei bis sechs cm, graubraun, trichterig mit welligem Rand, '
        'in der Mitte meist durchbohrt.',
    unterseite: 'Graue bis gelbliche LEISTEN, weit herablaufend, dick '
        'und gegabelt.',
    stiel: 'Deutlich GELB, hohl, längsrillig.',
    fleisch: 'Dünn, zäh-elastisch, blassgelb.',
    geruch: 'Schwach obstig, mild.',
    vorkommen: 'In Nadel- und Mischwäldern, in Moos und auf saurem '
        'Boden, oft in großen Trupps; August bis Dezember.',
  ),
  'Herbsttrompete': (
    hut: 'Fünf bis zwölf cm, trichter- bis trompetenförmig, bis zum '
        'Stiel durchgehend hohl, grauschwarz, außen faserschuppig.',
    unterseite: 'Nahezu glatt, höchstens schwach aderig, aschgrau '
        'bereift — keine Leisten und keine Lamellen.',
    stiel: 'Nicht abgesetzt: Die ganze Trompete ist Hut und Stiel in '
        'einem, durchgehend grauschwarz.',
    fleisch: 'Dünn, zäh-elastisch, grau.',
    geruch: 'Angenehm würzig, getrocknet intensiv.',
    vorkommen: 'Bei Buche und Eiche auf kalkhaltigem Boden, im Laub '
        'leicht zu übersehen; August bis November.',
  ),
  'Semmelstoppelpilz': (
    hut: 'Drei bis zehn cm, cremefarben bis semmelgelb, unregelmäßig '
        'gebuckelt, matt und trocken.',
    unterseite: 'Weiche, weißliche STACHELN, die sich leicht abstreifen '
        'lassen und am Stiel herablaufen.',
    stiel: 'Kurz und dick, weißlich, oft exzentrisch angesetzt.',
    fleisch: 'Weiß, brüchig, im Alter etwas bitter.',
    geruch: 'Mild bis leicht scharf, angenehm.',
    vorkommen: 'In Laub- und Nadelwäldern, oft in Reihen oder Hexenringen; '
        'August bis November.',
  ),

  'Krause Glucke': (
    hut: 'Kein Hut: ein 10 bis 40 cm großer, blumenkohlartiger Ballen '
        'aus krausen, BANDFÖRMIGEN Lappen, cremeweiß bis ockergelb.',
    unterseite: 'Weder Lamellen noch Poren; die Sporen sitzen glatt auf '
        'der Unterseite der Lappen.',
    stiel: 'Ein kurzer, wurzelnder Strunk, der in die Baumwurzel '
        'übergeht.',
    fleisch: 'Zäh-elastisch, bei jungen Stücken zart, im Alter ledrig '
        'und brüchig.',
    geruch: 'Würzig, fast nach Anis oder Marzipan; Geschmack mild und '
        'nussig.',
    vorkommen: 'Am Stammfuß von KIEFERN, seltener anderer Nadelbäume, '
        'oft jahrelang an derselben Stelle; August bis November.',
  ),
  'Habichtspilz': (
    hut: 'Acht bis 25 cm, graubraun, trichterig vertieft und mit groben, '
        'aufgerichteten SCHUPPEN wie ein Vogelgefieder besetzt.',
    unterseite: 'STACHELN statt Lamellen, grau bis braun, am Stiel '
        'deutlich herablaufend.',
    stiel: 'Kurz und dick, graubraun, oft seitlich am Hut angesetzt.',
    fleisch: 'Weißlich bis graubraun, jung fest, im Alter zäh.',
    geruch: 'Würzig; jung mild, mit dem Alter zunehmend BITTER.',
    vorkommen: 'Mykorrhiza bei Fichte auf saurem Boden im Bergwald; '
        'August bis Oktober.',
  ),
  'Ziegenbart': (
    hut: 'Kein Hut: ein fünf bis 20 cm hoher, korallenartig verzweigter '
        'Busch, je nach Art ocker, gelb, rosa oder violett gespitzt.',
    unterseite: 'Weder Lamellen noch Poren; die Sporen sitzen außen an '
        'den Ästen.',
    stiel: 'Ein dicker, weißlicher Strunk, aus dem sich die Äste '
        'wiederholt gabeln.',
    fleisch: 'Weiß bis blass, brüchig; bei manchen Arten auf Druck '
        'weinrot fleckend.',
    geruch: 'Unauffällig bis leicht erdig; bitterer Geschmack spricht '
        'gegen einen Speisepilz.',
    vorkommen: 'Auf Waldboden bei Laub- und Nadelbäumen; der deutsche '
        'Name meint die ganze Gattung. Juli bis Oktober.',
  ),
  'Igelstachelbart': (
    hut: 'Kein Hut: ein fünf bis 25 cm großer, rein weißer Klumpen, von '
        'dem lange, herabhängende STACHELN wie ein Bart ausgehen.',
    unterseite: 'Weder Lamellen noch Poren; die Stacheln selbst tragen '
        'die Sporen.',
    stiel: 'Kein Stiel; der Fruchtkörper sitzt mit schmaler Basis direkt '
        'am Stamm.',
    fleisch: 'Weiß, weich und faserig, im Alter gilbend und zäh.',
    geruch: 'Angenehm pilzig, Geschmack mild.',
    vorkommen: 'An Wunden lebender Laubbäume, vor allem Buche und Eiche; '
        'in Deutschland besonders geschützt. September bis November.',
  ),

  // ── Champignons ──────────────────────────────────────────────────
  'Wiesenchampignon': (
    hut: 'Vier bis zehn cm, weiß bis cremefarben, seidig, jung '
        'halbkugelig.',
    unterseite: 'Lamellen jung ROSA, dann rotbraun, zuletzt '
        'schokoladenbraun; frei, den Stiel nicht berührend.',
    stiel: 'Weiß, mit einfachem, vergänglichem RING — ohne Scheide und '
        'ohne Knolle.',
    fleisch: 'Weiß, im Schnitt allenfalls schwach rötend, nie chromgelb.',
    geruch: 'Angenehm nach Champignon, mild.',
    vorkommen: 'Auf Weiden, Wiesen und in Parks, nie im Wald an Holz; '
        'Mai bis Oktober.',
  ),
  'Anischampignon': (
    hut: 'Acht bis 20 cm, weiß, seidig glänzend, auf Druck gilbend.',
    unterseite: 'Lamellen jung blassgrau bis rosa, später '
        'schokoladenbraun, frei.',
    stiel: 'Weiß, mit breitem, zweilagigem Ring; Basis knollig verdickt.',
    fleisch: 'Weiß, langsam gilbend, besonders an der Stielbasis.',
    geruch: 'Deutlich nach ANIS oder Marzipan — das entscheidende '
        'Merkmal.',
    vorkommen: 'Auf Wiesen, Weiden und an Waldrändern; Juni bis Oktober.',
  ),
  'Waldchampignon': (
    hut: 'Fünf bis zehn cm, blassbraun mit rötlichbraunen Schüppchen.',
    unterseite: 'Lamellen jung blassrosa, später dunkelbraun, frei.',
    stiel: 'Weißlich, mit hängendem Ring, Basis wenig verdickt.',
    fleisch: 'Weiß, im Schnitt deutlich RÖTEND, nie gelb.',
    geruch: 'Angenehm pilzig, mild.',
    vorkommen: 'In Nadelwäldern, gern bei Fichte; Juli bis Oktober.',
  ),
  'Karbolchampignon': (
    hut: 'Fünf bis 15 cm, weiß, oben oft flach abgeflacht wie '
        'abgeschnitten, grau überhaucht.',
    unterseite: 'Lamellen jung weißlich bis blassgrau, später '
        'schokoladenbraun, frei.',
    stiel: 'Weiß mit breitem Ring; die Basis läuft angeritzt sofort '
        'CHROMGELB an.',
    fleisch: 'Weiß, in der Stielbasis leuchtend chromgelb verfärbend.',
    geruch: 'Nach KARBOL, Tinte oder Krankenhaus — beim Erhitzen '
        'unüberriechbar.',
    vorkommen: 'In Parks, Gärten und an Waldrändern, gern unter Hecken; '
        'Juli bis Oktober.',
  ),

  'Stadtchampignon': (
    hut: 'Fünf bis 15 cm, weiß bis cremefarben, dickfleischig, lange '
        'flach gewölbt und oft vom Aufstemmen der Erde rissig.',
    unterseite: 'Lamellen jung blassrosa, dann schokoladenbraun, frei '
        'stehend und sehr dicht.',
    stiel: 'Kurz und dick, weiß, mit DOPPELTEM Ring — einem oberen '
        'häutigen und einem unteren, wulstigen.',
    fleisch: 'Weiß, sehr fest, im Schnitt kaum verfärbend.',
    geruch: 'Angenehm nach Champignon, Geschmack mild; kein Anis und '
        'keine Tinte.',
    vorkommen: 'An Wegrändern, auf Parkrasen und in Pflasterritzen, oft '
        'mitten in Städten; Mai bis Oktober.',
  ),

  // ── Schirmlinge ──────────────────────────────────────────────────
  'Parasol': (
    hut: 'Zehn bis 30 cm, jung paukenschlägelförmig geschlossen, später '
        'flach ausgebreitet mit dunklem Buckel und groben braunen '
        'Schuppen auf hellem Grund.',
    unterseite: 'Lamellen weiß, weich, frei, durch ein Collar vom Stiel '
        'getrennt.',
    stiel: 'Sehr lang, hohl, mit deutlicher SCHLANGENHAUT-Natterung, '
        'knolliger Basis und einem VERSCHIEBBAREN Ring.',
    fleisch: 'Weiß, im Schnitt unverändert oder allenfalls schwach '
        'bräunend.',
    geruch: 'Angenehm nussig, mild.',
    vorkommen: 'Auf Wiesen, Waldwegen und Lichtungen; Juli bis Oktober.',
  ),
  'Safranschirmling': (
    hut: 'Acht bis 20 cm, hell mit groben, wolligen Schuppen, ohne '
        'ausgeprägte Natterung am Stiel.',
    unterseite: 'Lamellen weiß, auf Druck rötend, frei.',
    stiel: 'Glatt bis schwach faserig, NICHT genattert, mit '
        'verschiebbarem Ring und dicker Knolle.',
    fleisch: 'Weiß, im Schnitt deutlich SAFRAN- bis orangerot '
        'anlaufend.',
    geruch: 'Angenehm pilzig, mild.',
    vorkommen: 'In Gärten, an Komposthaufen und in Nadelwäldern; '
        'Juli bis Oktober.',
  ),

  'Schopftintling': (
    hut: 'Vier bis 15 cm hoch, walzlich-eiförmig wie eine Perücke, weiß '
        'mit abstehenden bräunlichen SCHUPPEN; öffnet sich nie ganz.',
    unterseite: 'Lamellen jung weiß, dann von unten her rosa, '
        'schließlich schwarz und zu Tinte zerfließend.',
    stiel: 'Lang, schlank und hohl, weiß, mit einem beweglichen schmalen '
        'Ring.',
    fleisch: 'Jung weiß und zart, altert von unten her schwarz und '
        'flüssig.',
    geruch: 'Mild und angenehm; brauchbar NUR jung mit rein weißen '
        'Lamellen.',
    vorkommen: 'Auf gedüngten Wiesen, an Wegrändern und in Gärten, oft '
        'in Reihen; Mai bis November.',
  ),

  // ── Wulstlinge ───────────────────────────────────────────────────
  'Fliegenpilz': (
    hut: 'Acht bis 20 cm, leuchtend scharlachrot mit weißen '
        'Velumflocken, die der Regen abwaschen kann.',
    unterseite: 'Lamellen rein weiß und dicht gedrängt, frei — sie '
        'berühren den Stiel nicht.',
    stiel: 'Weiß, mit hängendem Ring und einer Knolle, die von '
        'gürtelartigen Velumresten umringt ist.',
    fleisch: 'Weiß, unter der Huthaut gelblich, ohne Verfärbung.',
    geruch: 'Unauffällig und mild — der Geruch warnt hier nicht.',
    vorkommen: 'Bei Birke und Fichte auf sauren Böden; Juli bis '
        'November.',
  ),
  'Perlpilz': (
    hut: 'Fünf bis 15 cm, graurosa bis fleischbräunlich, mit '
        'schmutzigrosa Velumflocken.',
    unterseite: 'Lamellen weiß, im Alter rosa gefleckt, frei.',
    stiel: 'Weißlich bis rosa, mit deutlich GERIEFELTEM Ring, Basis '
        'rübenartig verdickt — ohne abgesetzte Knolle.',
    fleisch: 'Weiß, an Fraßstellen und im Schnitt deutlich WEINROT '
        'ANLAUFEND.',
    geruch: 'Mild, unauffällig.',
    vorkommen: 'Bei Fichte, Buche und Eiche; Juni bis Oktober.',
  ),
  'Pantherpilz': (
    hut: 'Fünf bis zehn cm, graubraun bis olivbraun, mit rein WEISSEN, '
        'gleichmäßig verteilten Velumflocken; der Rand ist gerieft.',
    unterseite: 'Lamellen rein weiß, frei.',
    stiel: 'Weiß, mit GLATTEM Ring und abgesetzter, gerandeter Knolle '
        'mit einem umlaufenden Wulst.',
    fleisch: 'Weiß, im Schnitt UNVERÄNDERT — kein Röten.',
    geruch: 'Schwach rettichartig.',
    vorkommen: 'Bei Buche, Eiche und Fichte; Juni bis Oktober.',
  ),
  'Grüner Knollenblätterpilz': (
    hut: 'Fünf bis 15 cm, oliv- bis gelbgrün, radialfaserig, meist ohne '
        'Flocken; der Rand ist NICHT gerieft.',
    unterseite: 'Lamellen rein weiß und weiß BLEIBEND, dicht, frei.',
    stiel: 'Weiß bis grünlich genattert, mit hängendem Ring und einer '
        'häutigen, lappigen SCHEIDE am Stielgrund.',
    fleisch: 'Weiß, ohne Verfärbung.',
    geruch: 'Jung unauffällig, alt süßlich-widerlich nach Honig.',
    vorkommen: 'Bei Eiche und Buche, selten Fichte; Juli bis Oktober.',
  ),
  'Kegelhütiger Knollenblätterpilz': (
    hut: 'Fünf bis zehn cm, rein weiß, kegelig bis glockig, seidig '
        'glänzend, oft schief.',
    unterseite: 'Lamellen rein weiß, gedrängt, frei; sie bleiben auch '
        'im Alter weiß.',
    stiel: 'Weiß, flockig-faserig, mit fetzigem Ring und häutiger '
        'SCHEIDE.',
    fleisch: 'Weiß, ohne Verfärbung.',
    geruch: 'Alt süßlich-unangenehm.',
    vorkommen: 'In Nadel- und Bergwäldern auf saurem Boden; Juli bis '
        'Oktober.',
  ),
  'Frühjahrsknollenblätterpilz': (
    hut: 'Fünf bis zehn cm, rein weiß, glatt, jung glockig, später '
        'ausgebreitet; der Rand ist nicht gerieft.',
    unterseite: 'Lamellen rein weiß, gedrängt und frei; keine Spur von '
        'Rosa, anders als bei jungen Champignons.',
    stiel: 'Weiß, mit hängendem Ring und häutiger SCHEIDE am '
        'Stielgrund.',
    fleisch: 'Weiß, ohne Verfärbung.',
    geruch: 'Unauffällig bis schwach süßlich.',
    vorkommen: 'Wärmeliebend bei Eiche und Buche auf Kalk; Mai bis '
        'Juli.',
  ),
  'Scheidenstreifling': (
    hut: 'Fünf bis zehn cm, grau bis graubraun, glatt, der Rand '
        'auffällig stark GERIEFT.',
    unterseite: 'Lamellen weiß, frei.',
    stiel: 'Schlank, weißlich, OHNE RING, aus einer weiten, häutigen '
        'Scheide kommend.',
    fleisch: 'Weiß, dünn, zerbrechlich.',
    geruch: 'Unauffällig, ohne besonderen Geschmack.',
    vorkommen: 'In Laub- und Nadelwäldern, gern an feuchten Stellen; '
        'Juni bis Oktober.',
  ),

  // ── Täublinge ────────────────────────────────────────────────────
  'Frauentäubling': (
    hut: 'Fünf bis 15 cm, violett-grün-grau gemischt, oft mehrfarbig '
        'gescheckt; die Huthaut lässt sich zur Hälfte abziehen.',
    unterseite: 'Lamellen weiß, weich und biegsam — sie fühlen sich '
        'speckig an und brechen nicht.',
    stiel: 'Weiß, fest, OHNE Ring und OHNE Scheide.',
    fleisch: 'Weiß, krümelig brechend wie ein Apfel, ohne Milch.',
    geruch: 'Mild und nussig, ohne jede Schärfe.',
    vorkommen: 'Bei Buche und Eiche; Juni bis Oktober.',
  ),
  'Grüngefelderter Täubling': (
    hut: 'Fünf bis zwölf cm, grasgrün bis graugrün, die Huthaut '
        'FELDERIG aufgerissen wie eine Krokodilhaut.',
    unterseite: 'Lamellen weiß bis cremefarben, spröde.',
    stiel: 'Weiß, fest, ohne Ring und ohne Scheide.',
    fleisch: 'Weiß, krümelig, ohne Verfärbung.',
    geruch: 'Mild, angenehm nussig; kein scharfer Geschmack.',
    vorkommen: 'Bei Buche und Eiche auf Kalk; Juni bis September.',
  ),
  'Speisetäubling': (
    hut: 'Fünf bis zehn cm, weinrot bis fleischrosa, oft ausblassend; '
        'die Huthaut endet kurz vor dem Rand, sodass die Lamellenenden '
        'hervorschauen.',
    unterseite: 'Lamellen weiß bis cremefarben, spröde brechend, am '
        'Stiel angewachsen.',
    stiel: 'Weiß, fest, an der Basis oft rostfleckig.',
    fleisch: 'Weiß, fest und krümelig brechend, ohne Milch.',
    geruch: 'Mild, angenehm nussig — der Geschmack entscheidet.',
    vorkommen: 'Bei Buche und Eiche; Juni bis Oktober.',
  ),
  'Speitäubling': (
    hut: 'Vier bis zehn cm, leuchtend kirschrot, glänzend; die Huthaut '
        'lässt sich fast vollständig abziehen.',
    unterseite: 'Lamellen rein weiß, spröde.',
    stiel: 'Rein weiß, zerbrechlich.',
    fleisch: 'Weiß, unter der Huthaut rötlich.',
    geruch: 'Schwach obstig, Geschmack BRENNEND SCHARF — sofort '
        'ausspucken.',
    vorkommen: 'In feuchten Nadelwäldern, gern in Sphagnum-Moos; '
        'Juli bis Oktober.',
  ),

  'Ledertäubling': (
    hut: 'Fünf bis 13 cm, kastanien- bis purpurbraun, in der Mitte oft '
        'heller ocker, der Rand alt deutlich gerieft.',
    unterseite: 'Lamellen jung weiß, reif kräftig OCKERGELB durch das '
        'Sporenpulver, brüchig.',
    stiel: 'Weiß und keulig, fest, ohne Ring; bricht wie Kreide, statt '
        'zu fasern.',
    fleisch: 'Weiß und fest, unter der Huthaut bräunlich; OHNE Milch.',
    geruch: 'Schwach obstartig, Geschmack MILD — auch in den Lamellen.',
    vorkommen: 'Mykorrhiza bei Fichte und Tanne im Bergwald; Juli bis '
        'Oktober.',
  ),
  'Fichtenreizker': (
    hut: 'Fünf bis zwölf cm, orange mit undeutlichen Zonen, bald '
        'trichterig, auf Druck und im Alter rasch GRÜN fleckend.',
    unterseite: 'Lamellen orange, dicht, am Stiel herablaufend, mit der '
        'Zeit ebenfalls grünfleckig.',
    stiel: 'Kurz und hohl, orange, meist OHNE die dunklen Grübchen des '
        'Edelreizkers.',
    fleisch: 'Blass orange und brüchig; Milch KAROTTENROT, nach einer '
        'halben Stunde weinrot bis grünlich.',
    geruch: 'Obstig, Geschmack mild bis leicht bitterlich.',
    vorkommen: 'Mykorrhiza AUSSCHLIESSLICH bei Fichte; Juli bis Oktober.',
  ),
  'Edelreizker': (
    hut: 'Vier bis 14 cm, orange mit deutlich konzentrischen ZONEN, '
        'trichterig vertieft, nur wenig und spät grünend.',
    unterseite: 'Lamellen leuchtend orange, gedrängt und weit am Stiel '
        'herablaufend.',
    stiel: 'Fest und hohl, orange, mit dunkleren GRÜBCHEN gezeichnet.',
    fleisch: 'Weißlich mit orangefarbenen Zonen; Milch karottenrot und '
        'über Stunden unverändert.',
    geruch: 'Angenehm obstig, Geschmack mild und leicht harzig.',
    vorkommen: 'Mykorrhiza bei Kiefer auf kalkhaltigem Boden; August bis '
        'Oktober.',
  ),
  'Lachsreizker': (
    hut: 'Sechs bis 15 cm, lachs- bis aprikosenfarben, kaum gezont, der '
        'Rand lange eingerollt; grünt nicht.',
    unterseite: 'Lamellen blass lachsfarben, sehr dicht stehend und am '
        'Stiel herablaufend.',
    stiel: 'Kräftig und lachsfarben, mit nur schwach angedeuteten '
        'Grübchen.',
    fleisch: 'Cremefarben; Milch orangerot und an der Luft LANGSAM '
        'weinrot werdend.',
    geruch: 'Schwach obstartig, Geschmack mild bis leicht bitter.',
    vorkommen: 'Mykorrhiza AUSSCHLIESSLICH bei Weißtanne; August bis '
        'Oktober.',
  ),
  'Kiefernreizker': (
    hut: 'Fünf bis zwölf cm, ockerorange bis fleischrosa mit grünlichen '
        'Flecken, nur schwach gezont.',
    unterseite: 'Lamellen weinrot überhaucht und damit DUNKLER als bei '
        'den anderen Reizkern, dicht, herablaufend.',
    stiel: 'Kurz und grubig, blass mit weinroten Tönen.',
    fleisch: 'Blass, im Schnitt weinrot; Milch von Anfang an DUNKEL '
        'WEINROT statt orange.',
    geruch: 'Mild und obstig, Geschmack mild.',
    vorkommen: 'Mykorrhiza bei Kiefer auf Kalk, wärmeliebend; September '
        'bis November.',
  ),
  'Mohrenkopfmilchling': (
    hut: 'Drei bis acht cm, SAMTIG dunkelbraun bis fast schwarz, mit '
        'kleinem spitzem Buckel und gekerbtem Rand.',
    unterseite: 'Lamellen auffallend WEISS bis cremefarben und weit '
        'stehend — der Kontrast zum Hut ist das Kennzeichen.',
    stiel: 'Lang und schlank, samtig dunkelbraun, oft längsrunzelig.',
    fleisch: 'Weiß, im Schnitt langsam rosa bis rötlich; Milch weiß und '
        'rötend.',
    geruch: 'Unauffällig, Geschmack mild.',
    vorkommen: 'Mykorrhiza bei Fichte und Tanne im Bergwald, gern in '
        'Moos; Juli bis Oktober.',
  ),
  'Brätling': (
    hut: 'Fünf bis 14 cm, orangebraun bis rostrot, matt und fein samtig, '
        'im Alter felderig rissig.',
    unterseite: 'Lamellen cremeweiß und gedrängt, auf Druck BRAUN '
        'fleckend, am Stiel kurz herablaufend.',
    stiel: 'Fest und hart, in Hutfarbe, ohne Grübchen und ohne Ring.',
    fleisch: 'Weiß und fest; Milch reichlich, WEISS wie Milch, klebrig '
        'und braun eintrocknend.',
    geruch: 'Deutlich nach HERINGSLAKE, Geschmack mild und nussig.',
    vorkommen: 'Mykorrhiza bei Eiche, Buche und Hainbuche auf warmen '
        'Böden; Juli bis September.',
  ),

  // ── Morcheln und Lorcheln ────────────────────────────────────────
  'Speisemorchel': (
    hut: 'Vier bis zehn cm, eiförmig bis rundlich, ockerbraun, mit '
        'unregelmäßigen WABEN; mit dem Stiel vollständig verwachsen.',
    unterseite: 'Keine Lamellen und keine Röhren — die Sporen sitzen in '
        'den Wabenkammern des Hutes.',
    stiel: 'Weißlich, kleiig, HOHL — und der Hohlraum geht ohne '
        'Unterbrechung in den Hut über.',
    fleisch: 'Dünn, wachsartig, komplett hohl. Längs halbieren ist die '
        'Probe, die entscheidet.',
    geruch: 'Angenehm würzig.',
    vorkommen: 'In Auwäldern, Gärten und auf Rindenmulch, gern bei '
        'Esche; April und Mai.',
  ),
  'Spitzmorchel': (
    hut: 'Vier bis zwölf cm, kegelig-spitz, olivbraun bis schwarzbraun, '
        'mit LÄNGS verlaufenden Rippen und Querstegen.',
    unterseite: 'Keine Lamellen — Sporen in den Wabenkammern.',
    stiel: 'Weißlich, hohl, durchgehend mit dem Hut verbunden.',
    fleisch: 'Dünn, komplett hohl.',
    geruch: 'Würzig, angenehm.',
    vorkommen: 'In Nadelwäldern, auf Brandstellen und Rindenmulch; '
        'April bis Juni.',
  ),
  'Käppchenmorchel': (
    hut: 'Zwei bis vier cm, kegelig, olivbraun, wabig — nur zur HÄLFTE '
        'mit dem Stiel verwachsen, der untere Rand steht frei ab.',
    unterseite: 'Keine Lamellen; der freie Hutrand gibt den Blick auf '
        'den Stiel frei.',
    stiel: 'Lang, weißlich, kleiig, hohl.',
    fleisch: 'Sehr dünn, hohl, zerbrechlich.',
    geruch: 'Mild, unauffällig.',
    vorkommen: 'In Auwäldern und Gebüschen, gern bei Esche und Pappel; '
        'April und Mai.',
  ),
  'Böhmische Verpel': (
    hut: 'Zwei bis fünf cm, fingerhutartig, längs gefaltet bis fast '
        'glatt, braun — er hängt NUR AN DER SPITZE am Stiel.',
    unterseite: 'Keine Lamellen; der Hut ist wie eine Glocke über den '
        'Stiel gestülpt und ringsum frei.',
    stiel: 'Lang, weißlich, kleiig, mit watteartigem Mark gefüllt.',
    fleisch: 'Dünn, zerbrechlich.',
    geruch: 'Unauffällig, schwach pilzig.',
    vorkommen: 'In feuchten Auwäldern bei Pappel und Weide; März bis '
        'Mai.',
  ),
  'Frühjahrslorchel': (
    hut: 'Vier bis zwölf cm, HIRNARTIG gewunden und gefurcht, nicht '
        'wabig, rotbraun bis dunkelbraun.',
    unterseite: 'Keine Lamellen — die Sporen sitzen auf der gewundenen '
        'Oberfläche.',
    stiel: 'Kurz, dick, weißlich, unregelmäßig gefurcht.',
    fleisch: 'Innen KAMMERIG gefüllt, nicht durchgehend hohl — die '
        'Probe beim Längshalbieren.',
    geruch: 'Angenehm würzig; der Geruch warnt NICHT.',
    vorkommen: 'In Nadelwäldern auf sandigem Boden und an Brandstellen; '
        'März bis Mai.',
  ),

  'Morchelbecherling': (
    hut: 'Kein Hut: ein fünf bis 15 cm breiter, anfangs tief '
        'BECHERFÖRMIGER Fruchtkörper, der sich ausbreitet und wellig '
        'verbiegt.',
    unterseite: 'Weder Lamellen noch Röhren; die olivbraune Innenseite '
        'trägt das Sporenlager und ist grob ADERIG gerunzelt, außen '
        'weißlich und kleiig.',
    stiel: 'Nur ein kurzer, weißlicher Stummel, der meist ganz im Boden '
        'steckt.',
    fleisch: 'Dünn und brüchig, wässrig braun.',
    geruch: 'Deutlich nach CHLOR oder Schwimmbad; roh giftig.',
    vorkommen: 'In Auwäldern und an feuchten Wegrändern, gern bei Esche '
        'und Pappel; März bis Mai.',
  ),

  // ── Boviste ──────────────────────────────────────────────────────
  'Flaschenstäubling': (
    hut: 'Kein Hut: ein zwei bis sechs cm großer, keulen- bis '
        'birnenförmiger Fruchtkörper mit abgesetztem Stielteil, weiß bis '
        'ockerbraun, mit abwischbaren Stacheln und Körnchen.',
    unterseite: 'Keine Lamellen und keine Röhren; reif öffnet sich oben '
        'ein Loch, aus dem die Sporen stäuben.',
    stiel: 'Der untere, sterile Teil ist als kurzer, schwammiger Stiel '
        'abgesetzt.',
    fleisch: 'Jung rein WEISS und ohne jede Zeichnung — längs halbieren '
        'ist Pflicht. Gelb oder braun heißt: reif, nicht mehr essbar.',
    geruch: 'Jung mild und angenehm, reif muffig nach altem Staub.',
    vorkommen: 'In Wäldern auf Boden und Nadelstreu, oft in Gruppen; '
        'Juni bis November.',
  ),

  'Riesenbovist': (
    hut: 'Kein Hut: eine 20 bis 50 cm große, weiße Kugel ohne jeden '
        'Stiel, die Oberfläche wie Wildleder.',
    unterseite: 'Weder Lamellen noch Röhren noch Stacheln; die Hülle '
        'reißt reif unregelmäßig auf und entlässt olivbraunes '
        'Sporenpulver.',
    stiel: 'Fehlt vollständig; der Fruchtkörper sitzt mit einer '
        'Mycelschnur direkt dem Boden auf.',
    fleisch: 'Jung rein WEISS und gleichmäßig wie Frischkäse — längs '
        'durchschneiden ist Pflicht. Gelb oder oliv heißt reif und '
        'nicht mehr essbar.',
    geruch: 'Jung angenehm pilzig, reif unangenehm streng.',
    vorkommen: 'Auf gedüngten Wiesen, Weiden und in Parks, gern an '
        'Brennnesselsäumen; Juli bis Oktober.',
  ),
  'Birnenstäubling': (
    hut: 'Kein Hut: ein zwei bis fünf cm großer, deutlich BIRNENFÖRMIGER '
        'Fruchtkörper, jung weiß, später ockerbraun, feinwarzig bis '
        'glatt.',
    unterseite: 'Keine Lamellen und keine Röhren; oben öffnet sich reif '
        'ein enges Loch, aus dem die Sporen stäuben.',
    stiel: 'Ein kurzer, zusammengezogener Stielteil, aus dem WEISSE '
        'Mycelstränge ins Holz ziehen.',
    fleisch: 'Jung weiß und fest, später olivbraun und pulverig.',
    geruch: 'Jung mild und angenehm, reif muffig.',
    vorkommen: 'IMMER an morschem Holz, an Stümpfen und vergrabenen '
        'Wurzeln, meist in dichten Rasen; Juli bis November.',
  ),

  // ── Baumpilze ────────────────────────────────────────────────────
  'Austernseitling': (
    hut: 'Fünf bis 20 cm, muschel- bis austernförmig, grau, blaugrau '
        'bis braun, glatt.',
    unterseite: 'Weiße bis cremefarbene Lamellen, weit am Stielansatz '
        'HERABLAUFEND.',
    stiel: 'Sehr kurz, seitlich angewachsen, oft fast fehlend, an der '
        'Basis filzig.',
    fleisch: 'Weiß, dick, zäh-fest; alte Exemplare werden holzig.',
    geruch: 'Angenehm pilzig, mild.',
    vorkommen: 'Büschelig an Laubholz, vor allem Buche und Pappel; nach '
        'den ersten Frösten, Oktober bis März.',
  ),
  'Lungenseitling': (
    hut: 'Fünf bis 15 cm, weißlich bis hell cremefarben, dünnfleischig '
        'und zerbrechlicher als der Austernseitling.',
    unterseite: 'Weiße Lamellen, weit herablaufend.',
    stiel: 'Kurz, seitlich bis exzentrisch, meist deutlicher ausgebildet '
        'als beim Austernseitling.',
    fleisch: 'Weiß, dünn, weich.',
    geruch: 'Mild, schwach mehlig.',
    vorkommen: 'An Laubholz, vor allem Buche; Mai bis September — die '
        'SOMMERform.',
  ),

  'Schwefelporling': (
    hut: 'Dachziegelig übereinander stehende, 10 bis 40 cm breite '
        'Konsolen, schwefelgelb bis orange, am Rand wellig; alt blass '
        'und kreidig.',
    unterseite: 'Feine, schwefelgelbe PORENSCHICHT statt Lamellen, auf '
        'Druck dunkler werdend.',
    stiel: 'Kein Stiel; die Konsolen sitzen breit und seitlich am Stamm '
        'an.',
    fleisch: 'Jung saftig, weich und blassgelb, im Alter hart, faserig '
        'und bröckelig.',
    geruch: 'Säuerlich-fruchtig; brauchbar sind nur die jungen, weichen '
        'Ränder.',
    vorkommen: 'An lebenden und toten Laubbäumen, vor allem Eiche, Weide '
        'und Obstbäumen; Mai bis Juli.',
  ),
  'Leberpilz': (
    hut: 'Zehn bis 25 cm, zungen- bis leberförmig, blutrot bis rotbraun, '
        'feucht klebrig und rau wie eine Katzenzunge.',
    unterseite: 'Cremeweiße bis rosa RÖHRCHEN, die EINZELN nebeneinander '
        'stehen und sich voneinander lösen lassen.',
    stiel: 'Kein oder nur ein kurzer seitlicher Ansatz am Stamm.',
    fleisch: 'Rot marmoriert wie ein Stück Fleisch, saftig; im Schnitt '
        'tritt rötlicher Saft aus.',
    geruch: 'Schwach säuerlich, Geschmack deutlich SAUER.',
    vorkommen: 'Am Stammfuß alter Eichen, seltener an Esskastanien; '
        'August bis Oktober.',
  ),
  'Judasohr': (
    hut: 'Drei bis zehn cm, ohrmuschelförmig und gewellt, rotbraun bis '
        'olivbraun, außen fein samtig behaart.',
    unterseite: 'Keine Lamellen: eine glatte bis aderig gefaltete, '
        'graubraune Fläche.',
    stiel: 'Kein Stiel; seitlich oder mit einem Punkt am Holz '
        'angewachsen.',
    fleisch: 'GALLERTARTIG und elastisch wie Gummi, trocken hornhart, '
        'quillt bei Nässe wieder auf.',
    geruch: 'Nahezu geruchlos, Geschmack mild.',
    vorkommen: 'An totem Laubholz, vor allem HOLUNDER; das ganze Jahr, '
        'besonders in milden Wintern.',
  ),

  // ── Lamellenpilze am Holz ────────────────────────────────────────
  'Stockschwämmchen': (
    hut: 'Drei bis sechs cm, honig- bis zimtbraun, glatt, bei '
        'Trockenheit von der Mitte her ZWEIFARBIG ausblassend.',
    unterseite: 'Lamellen jung blass, dann zimtbraun, am Stiel '
        'angewachsen.',
    stiel: 'Mit häutigem Ring; DARUNTER deutlich dunkel SCHUPPIG bis '
        'schülferig — das entscheidende Merkmal.',
    fleisch: 'Dünn, blass, im Hut weich, im Stiel zäh.',
    geruch: 'Angenehm pilzig, mild.',
    vorkommen: 'Dicht büschelig an Laubholzstümpfen, selten Nadelholz; '
        'April bis November.',
  ),
  'Gifthäubling': (
    hut: 'Zwei bis fünf cm, ocker- bis honigbraun, glatt, hygrophan '
        'ausblassend — dem Stockschwämmchen zum Verwechseln ähnlich.',
    unterseite: 'Lamellen jung blass ocker, später rostbraun, '
        'angewachsen.',
    stiel: 'Mit vergänglichem Ring; DARUNTER GLATT und silbrig '
        'längsüberfasert, niemals schuppig.',
    fleisch: 'Dünn, blassbraun.',
    geruch: 'MEHLIG bis ranzig — nicht angenehm pilzig.',
    vorkommen: 'Einzeln bis kleinbüschelig an morschem Laub- und '
        'Nadelholz, oft neben Stockschwämmchen; das ganze Jahr.',
  ),
  'Samtfußrübling': (
    hut: 'Zwei bis acht cm, honiggelb bis orangebraun, bei Feuchtigkeit '
        'stark SCHLEIMIG glänzend.',
    unterseite: 'Lamellen blassgelb, breit, entfernt stehend, '
        'angewachsen.',
    stiel: 'Zäh, nach unten SAMTIG SCHWARZBRAUN — und OHNE jeden Ring.',
    fleisch: 'Blassgelb, im Hut weich, im Stiel zäh.',
    geruch: 'Mild, unauffällig.',
    vorkommen: 'Büschelig an Laubholz, besonders Weide und Pappel; '
        'Oktober bis März, auch bei Frost.',
  ),
  'Grünblättriger Schwefelkopf': (
    hut: 'Zwei bis sechs cm, schwefelgelb mit rostbrauner Mitte, glatt.',
    unterseite: 'Lamellen jung schwefelgelb, bald deutlich GRÜNLICH, '
        'später olivbraun.',
    stiel: 'Schlank, gelb, ohne echten Ring, oft mit dunkler '
        'Faserzone.',
    fleisch: 'Schwefelgelb und dünn, im Stiel zäh-faserig.',
    geruch: 'Unauffällig, Geschmack sehr BITTER.',
    vorkommen: 'In dichten Büscheln an Stümpfen von Laub- und '
        'Nadelholz; das ganze Jahr.',
  ),
  'Hallimasch': (
    hut: 'Vier bis zwölf cm, honig- bis olivbraun, in der Mitte mit '
        'dunklen SCHÜPPCHEN.',
    unterseite: 'Lamellen weißlich bis blass fleischfarben, im Alter '
        'rostfleckig, am Stiel etwas herablaufend.',
    stiel: 'Lang, faserig, mit deutlichem WATTIGEM Ring; die Stiele '
        'wachsen aus einem gemeinsamen Büschel.',
    fleisch: 'Weißlich, im Stiel zäh-faserig.',
    geruch: 'Streng, im Alter unangenehm; roh scharf.',
    vorkommen: 'In großen Büscheln an lebendem und totem Holz, auch an '
        'Wurzeln im Boden; August bis November.',
  ),

  'Dunkler Hallimasch': (
    hut: 'Drei bis 15 cm, dunkel rotbraun, dicht mit dunklen abstehenden '
        'SCHUPPEN besetzt, vor allem zur Mitte hin.',
    unterseite: 'Lamellen weißlich, im Alter rostfleckig, am Stiel etwas '
        'herablaufend.',
    stiel: 'Fest und braun genattert, mit dickem weißem RING, der außen '
        'bräunlich beflockt ist.',
    fleisch: 'Weiß und fest, im Stiel zäh und faserig.',
    geruch: 'Streng pilzig; roh GIFTIG, nur gut durchgegart und ohne das '
        'Kochwasser.',
    vorkommen: 'An Nadelholz, vor allem Fichte, als Parasit an lebenden '
        'Stämmen und an Stümpfen; August bis November.',
  ),

  // ── Lamellenpilze am Boden ───────────────────────────────────────
  'Maipilz': (
    hut: 'Fünf bis zwölf cm, cremeweiß bis hell ockerlich, glatt, oft '
        'unregelmäßig verbogen.',
    unterseite: 'Lamellen weiß und weiß BLEIBEND, dicht, ausgebuchtet '
        'angewachsen.',
    stiel: 'Weiß, voll und fest, faserig; OHNE Ring und OHNE Scheide.',
    fleisch: 'Weiß, fest, ohne Verfärbung.',
    geruch: 'Stark nach frischem MEHL oder Gurke — das Hauptmerkmal.',
    vorkommen: 'In Hexenringen auf Wiesen, an Hecken und Waldrändern; '
        'April bis Juni.',
  ),
  'Ziegelroter Risspilz': (
    hut: 'Drei bis acht cm, weißlich, mit dem Alter ZIEGELROT '
        'anlaufend, radialfaserig aufreißend.',
    unterseite: 'Lamellen blass, später olivbraun, rötend.',
    stiel: 'Weißlich, längsfaserig, rötend, ohne Ring.',
    fleisch: 'Weiß, auf Druck rötend.',
    geruch: 'Unangenehm SPERMATISCH — nie mehlig.',
    vorkommen: 'Bei Laubbäumen auf Kalk, oft neben Maipilzen; Mai bis '
        'Juli.',
  ),
  'Riesenrötling': (
    hut: 'Zehn bis 20 cm, graubraun bis elfenbeinfarben, glatt, '
        'unregelmäßig gewellt.',
    unterseite: 'Lamellen jung gelblich, später deutlich ROSA bis '
        'fleischrosa; ausgebuchtet angewachsen, nicht herablaufend.',
    stiel: 'Kräftig und voll, weißlich, längsfaserig, ohne Ring.',
    fleisch: 'Weiß und fest, im Schnitt ohne Verfärbung.',
    geruch: 'Mehlartig, im Alter ranzig.',
    vorkommen: 'Bei Laubbäumen auf schweren, kalkhaltigen Böden; '
        'Juni bis Oktober.',
  ),
  'Mönchskopf': (
    hut: 'Sechs bis 20 cm, ocker- bis lederbraun, jung gewölbt, später '
        'tief TRICHTERIG eingedellt.',
    unterseite: 'Lamellen weiß bis cremefarben, weit am Stiel '
        'HERABLAUFEND, dicht.',
    stiel: 'Kräftig, keulig, weißlich, ohne Ring.',
    fleisch: 'Weiß, fest, elastisch.',
    geruch: 'Angenehm, schwach blausäureartig.',
    vorkommen: 'In Hexenringen in Laub- und Nadelwäldern; September bis '
        'November.',
  ),
  'Nebelkappe': (
    hut: 'Sechs bis 20 cm, grau bis graubraun, wie BEREIFT wirkend, '
        'jung gewölbt mit eingerolltem Rand.',
    unterseite: 'Lamellen weißlich bis cremefarben, dicht, am Stiel '
        'kurz herablaufend, leicht ablösbar.',
    stiel: 'Kräftig, keulig verdickt, grauweiß, ohne Ring.',
    fleisch: 'Weiß und weich, im Alter wässrig und leicht madig.',
    geruch: 'Streng SÜSSLICH-parfümiert — unverwechselbar und '
        'aufdringlich.',
    vorkommen: 'In großen Reihen und Hexenringen in Nadel- und '
        'Laubwäldern; September bis Dezember.',
  ),
  'Violetter Rötelritterling': (
    hut: 'Fünf bis 15 cm, violett bis blauviolett, im Alter '
        'lederbraun ausblassend, glatt.',
    unterseite: 'Lamellen violett, DICHT stehend und dünn, ausgebuchtet '
        'angewachsen.',
    stiel: 'Kräftig, faserig, violett, an der Basis oft filzig, ohne '
        'Ring.',
    fleisch: 'Violettlich, fest.',
    geruch: 'Angenehm parfümiert, süßlich.',
    vorkommen: 'Auf Laub und Nadelstreu, gern an Komposträndern; '
        'September bis Dezember.',
  ),
  'Violetter Lacktrichterling': (
    hut: 'Ein bis fünf cm, violett, im Alter stark ausblassend, '
        'feinschuppig, mit gewelltem Rand.',
    unterseite: 'Lamellen violett, auffällig DICK und ENTFERNT stehend, '
        'am Stiel angewachsen.',
    stiel: 'Dünn, zäh-faserig, violett längsfaserig.',
    fleisch: 'Dünn, violettlich.',
    geruch: 'Unauffällig, mild im Geschmack.',
    vorkommen: 'In feuchten Laub- und Nadelwäldern, oft in Moos; '
        'Juli bis November.',
  ),
  'Kahler Krempling': (
    hut: 'Fünf bis 15 cm, olivbraun bis rostbraun, samtig, mit lange '
        'stark EINGEROLLTEM, gerieftem Rand; im Alter trichterig.',
    unterseite: 'Lamellen ockergelb, weit herablaufend, auf Druck '
        'deutlich braun fleckend; sie lassen sich vom Hut ABSCHIEBEN.',
    stiel: 'Kurz, oft exzentrisch, olivbraun, ohne Ring.',
    fleisch: 'Gelblich, im Schnitt braun anlaufend.',
    geruch: 'Säuerlich bis obstig.',
    vorkommen: 'Bei Birke und Fichte, auf sauren Böden und in Gärten; '
        'Juli bis Oktober.',
  ),
  'Spitzgebuckelter Raukopf': (
    hut: 'Drei bis acht cm, orangebraun bis fuchsig, FILZIG-rau, mit '
        'auffällig spitzem Buckel.',
    unterseite: 'Lamellen safran- bis zimtbraun, entfernt stehend, '
        'angewachsen.',
    stiel: 'Schlank, gelblich, mit blassgelben Faserbändern; ohne Ring.',
    fleisch: 'Gelblich bis bräunlich.',
    geruch: 'Schwach rettichartig.',
    vorkommen: 'In Nadelwäldern auf sauren, moosigen Böden; August bis '
        'Oktober.',
  ),
  'Orangefuchsiger Raukopf': (
    hut: 'Drei bis zehn cm, orangebraun bis fuchsigrot, filzig-rau, '
        'gewölbt bis flach, ohne spitzen Buckel.',
    unterseite: 'Lamellen orangebraun bis zimtbraun, dick und entfernt '
        'stehend.',
    stiel: 'Gelbbraun, längsfaserig, ohne Ring.',
    fleisch: 'Gelblich bis ockerbraun.',
    geruch: 'Schwach rettichartig.',
    vorkommen: 'In wärmeren Laubwäldern bei Eiche und Buche; August bis '
        'Oktober.',
  ),
  'Tigerritterling': (
    hut: 'Sechs bis 15 cm, hellgrau mit dunkleren, konzentrisch '
        'angeordneten SCHUPPEN wie ein Tigermuster.',
    unterseite: 'Lamellen weiß bis cremefarben, dick, ausgebuchtet '
        'angewachsen; sie sondern manchmal Tröpfchen ab.',
    stiel: 'Kräftig, weißlich, fest, ohne Ring.',
    fleisch: 'Weiß, fest, dick.',
    geruch: 'Mehlartig, Geschmack mild — die Milde warnt NICHT.',
    vorkommen: 'Bei Fichte und Buche auf Kalk, in Bergwäldern; August '
        'bis Oktober.',
  ),
  'Grünling': (
    hut: 'Fünf bis zwölf cm, schwefel- bis olivgelb, in der Mitte '
        'bräunlich, klebrig, oft mit Sand verbacken.',
    unterseite: 'Lamellen leuchtend SCHWEFELGELB, dicht, ausgebuchtet '
        'angewachsen.',
    stiel: 'Kurz, gelb, meist tief im Sand steckend, ohne Ring.',
    fleisch: 'Weißlich bis gelblich, fest.',
    geruch: 'Mehlartig, mild.',
    vorkommen: 'In sandigen Kiefernwäldern und Dünen, oft halb '
        'vergraben; September bis November.',
  ),
  'Nelkenschwindling': (
    hut: 'Zwei bis fünf cm, ledergelb bis hellbraun, jung glockig, '
        'später flach mit stumpfem Buckel; trocknet aus und lebt bei '
        'Regen wieder auf.',
    unterseite: 'Lamellen blass ockerfarben, dick, auffallend WEIT '
        'stehend und am Stiel frei endend.',
    stiel: 'Dünn und zäh wie Draht, hellbraun; lässt sich verdrehen, '
        'ohne zu brechen.',
    fleisch: 'Blass und dünn, im Stiel zäh und faserig.',
    geruch: 'Würzig nach Bittermandel oder Nelken, Geschmack mild.',
    vorkommen: 'Auf Wiesen, Rasen und an Wegrändern, oft in HEXENRINGEN; '
        'Mai bis November.',
  ),
  'Rehbrauner Dachpilz': (
    hut: 'Vier bis zwölf cm, graubraun bis rehbraun und radialfaserig, '
        'jung glockig, später flach mit Buckel.',
    unterseite: 'Lamellen jung weiß, bald FLEISCHROSA durch das '
        'Sporenpulver, frei stehend und dicht.',
    stiel: 'Weißlich mit dunklen Längsfasern, ohne Ring, an der Basis '
        'leicht verdickt.',
    fleisch: 'Weiß und weich, im Hut dünn, im Schnitt ohne Verfärbung.',
    geruch: 'Schwach rettichartig, Geschmack mild.',
    vorkommen: 'An morschem Laub- und Nadelholz, auf Sägemehl und '
        'Rindenmulch; fast ganzjährig, Schwerpunkt Mai bis Oktober.',
  ),
  'Riesenträuschling': (
    hut: 'Fünf bis 20 cm, jung weinrot bis rotbraun, später ockerbraun '
        'ausblassend, trocken und glatt.',
    unterseite: 'Lamellen jung blassgrau, dann VIOLETTSCHWARZ, breit am '
        'Stiel angewachsen.',
    stiel: 'Kräftig und weiß, mit dickem Ring, dessen Oberseite '
        'STERNFÖRMIG gefurcht ist.',
    fleisch: 'Weiß und fest, im Schnitt unverändert.',
    geruch: 'Angenehm pilzig, Geschmack mild und nussig.',
    vorkommen: 'Auf Stroh, Holzhäcksel und Komposterde in Gärten und '
        'Beeten, selten im Wald; Juni bis Oktober.',
  ),
  'Fuchsiger Rötelritterling': (
    hut: 'Vier bis zehn cm, fuchsig orangebraun, bald tief TRICHTERIG '
        'mit lange eingerolltem Rand, feucht wasserfleckig.',
    unterseite: 'Lamellen gleichfarben bis heller, sehr gedrängt, weit '
        'herablaufend und leicht vom Hut abzulösen.',
    stiel: 'Schlank, in Hutfarbe, an der Basis weißfilzig, ohne Ring.',
    fleisch: 'Dünn, blass orangebraun und wässrig.',
    geruch: 'Schwach süßlich, Geschmack mild.',
    vorkommen: 'In Reihen und Hexenringen auf Nadelstreu, oft in '
        'Fichtenforsten; September bis Dezember.',
  ),
  'Reifpilz': (
    hut: 'Fünf bis zwölf cm, ockergelb bis semmelfarben, jung wie von '
        'WEISSEM Reif überzogen; der Scheitel bleibt runzelig.',
    unterseite: 'Lamellen jung blass, später TONBRAUN durch das '
        'Sporenpulver, am Stiel angewachsen.',
    stiel: 'Kräftig und weißlich, mit häutigem aufsteigendem Ring und '
        'einer bandartigen Zone darunter.',
    fleisch: 'Weiß bis blassgelb, weich, im Schnitt unverändert.',
    geruch: 'Mild und angenehm pilzig, Geschmack nussig.',
    vorkommen: 'Bei Fichte und Birke auf saurem Boden, gern zwischen '
        'Heidelbeeren; August bis Oktober.',
  ),
};

/// Die Merkmale zu einem Artnamen — `null`, wenn keine gepflegt sind.
///
/// **`null` heißt „diesen Namen kennen wir nicht".** Seit 1.169.0 trägt
/// JEDE bekannte Art Merkmale, der Fall tritt für sie also nicht mehr
/// ein. Der Zweig bleibt trotzdem: Hier kommt auch Freitext aus dem
/// Eingabefeld an, und der zeigt den Abschnitt dann gar nicht erst an,
/// statt eine halbe Beschreibung zu behaupten.
SpeciesFeatures? featuresFor(String? species) {
  final canonical = canonicalSpecies(species);
  return canonical == null ? null : speciesFeatures[canonical];
}
