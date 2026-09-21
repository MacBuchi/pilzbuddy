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
// **Gepflegt für 58 Arten, und die Menge ist eine Regel:** jede Art mit
// einem Verwechslungspartner (ohne Merkmale ließe sich der Unterschied
// nicht nachlesen) und jede giftige Art (die muss beschrieben sein, auch
// wenn sie niemand sucht). `test/species_features_test.dart` rechnet das
// nach — wer ein Paar ergänzt, wird zu den Merkmalen gezwungen.
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
};

/// Die Merkmale zu einem Artnamen — `null`, wenn keine gepflegt sind.
///
/// **`null` heißt „hier steht nichts", nicht „es gibt nichts zu sagen".**
/// Gepflegt ist die Pflichtmenge (siehe Kopf der Datei); für die übrigen
/// Arten zeigt die Seite den Abschnitt gar nicht erst an, statt eine
/// halbe Beschreibung zu behaupten.
SpeciesFeatures? featuresFor(String? species) {
  final canonical = canonicalSpecies(species);
  return canonical == null ? null : speciesFeatures[canonical];
}
