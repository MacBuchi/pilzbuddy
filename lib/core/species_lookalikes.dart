// Womit eine Art verwechselt wird — und woran man es merkt.
//
// **Dieser Abschnitt ist Warnung, nicht Bestimmung.** Er sagt nicht, was
// jemand in der Hand hält; er sagt, welche Frage offen ist. Deshalb steht
// er direkt unter der Einstufung: „giftig" und „wird mit … verwechselt"
// müssen zusammen gelesen werden, sonst nützt keins von beidem.
//
// **Die Beziehung ist SYMMETRISCH, und das erzwingt ein Test.** Wer den
// Gifthäubling beim Stockschwämmchen nennt, muss das Stockschwämmchen
// beim Gifthäubling nennen. Eine einseitige Warnung findet nur, wer schon
// weiß, wonach er sucht — und wer auf der Seite des Giftpilzes landet,
// ist oft gerade der, der dort nicht hinwollte.
//
// **Der Unterscheidungssatz steht je RICHTUNG, nicht einmal je Paar.**
// „Der Perlpilz rötet an Fraßstellen" ist beim Perlpilz eine Bestätigung
// und beim Pantherpilz ein Ausschluss; dieselben Worte für beide Seiten
// wären für eine der beiden die falsche Frage.
//
// **Vollständigkeit ist hier nicht das Ziel.** Aufgenommen ist, was
// gemeldet wird und was schiefgehen kann: jede giftige Art mit ihrem
// essbaren Doppelgänger, jeder häufig gesammelte Speisepilz mit seiner
// gefährlichen Verwechslung, und ein paar harmlose Paare, die schlicht
// oft verwechselt werden. Eine Art ohne Eintrag heißt „uns ist keine
// häufige Verwechslung bekannt", nicht „die gibt es nicht".
import 'mushroom_species.dart';
import 'species_edibility.dart';

/// Ein Verwechslungspartner, aus Sicht EINER Art.
typedef Lookalike = ({String species, String difference});

/// Die Paare. Jeder Eintrag steht zweimal — einmal je Richtung.
const speciesLookalikes = <String, List<Lookalike>>{
  // ── Röhrlinge ────────────────────────────────────────────────────
  'Steinpilz': [
    (
      species: 'Gallenröhrling',
      difference: 'Das Netz auf dem Stiel ist beim Steinpilz weiß auf '
          'hellem Grund, beim Gallenröhrling dunkel und grob. Dessen '
          'Poren werden mit dem Alter rosa, und er schmeckt bitter.'
    ),
    (
      species: 'Satansröhrling',
      difference: 'Der Satansröhrling hat ROTE Poren und blaut im '
          'Anschnitt; beim Steinpilz sind die Poren weiß bis gelbgrün, '
          'und sein Fleisch verfärbt sich nicht.'
    ),
    (
      species: 'Schönfußröhrling',
      difference: 'Der Schönfußröhrling trägt ein ROTES Netz auf gelbem '
          'Stiel, blaut im Schnitt und schmeckt bitter; beim Steinpilz '
          'ist das Netz weiß, und nichts verfärbt sich.'
    ),
    (
      species: 'Sommersteinpilz',
      difference: 'Der Sommersteinpilz hat eine matte, trockene Huthaut, die '
          'bald felderig aufreißt, und sein Netz zieht sich über den '
          'GANZEN Stiel. Beim Steinpilz ist der Hut glatt und feucht '
          'klebrig, das Netz sitzt nur oben.'
    ),
    (
      species: 'Kiefernsteinpilz',
      difference: 'Der Kiefernsteinpilz hat einen dunkel rotbraunen bis '
          'kupferfarbenen, oft höckerig-runzeligen Hut und ein '
          'rötlichbraunes Netz auf bräunlichem Stiel. Er wächst bei '
          'Kiefer und Fichte.'
    ),
    (
      species: 'Bronzeröhrling',
      difference: 'Der Bronzeröhrling ist fast SCHWARZBRAUN, seine Huthaut '
          'trocken und feinsamtig, der Stiel bräunlich mit feinem '
          'braunem Netz. Er steht bei Eiche und Buche an warmen '
          'Stellen.'
    ),
  ],
  'Sommersteinpilz': [
    (
      species: 'Gallenröhrling',
      difference: 'Der Sommersteinpilz hat ein weißes Netz über den GANZEN '
          'Stiel und eine feinrissige, matte Huthaut; der Gallenröhrling '
          'ein grobes dunkles Netz, rosa werdende Poren und '
          'Gallengeschmack.'
    ),
    (
      species: 'Steinpilz',
      difference: 'Der Steinpilz hat einen glatten, bei Nässe klebrigen Hut '
          'und ein weißes Netz nur im oberen Stieldrittel. Der '
          'Sommersteinpilz reißt auf der Huthaut felderig auf und ist '
          'bis zur Basis genetzt.'
    ),
    (
      species: 'Kiefernsteinpilz',
      difference: 'Der Kiefernsteinpilz ist kupfer- bis rotbraun mit '
          'rötlichbraunem Netz und an Kiefer gebunden. Der '
          'Sommersteinpilz ist heller lederbraun und steht bei Eiche '
          'und Buche.'
    ),
    (
      species: 'Bronzeröhrling',
      difference: 'Der Bronzeröhrling ist fast schwarzbraun und gleichmäßig '
          'feinsamtig, ohne die felderigen Risse des '
          'Sommersteinpilzes; sein Netz ist fein und braun.'
    ),
  ],
  'Kiefernsteinpilz': [
    (
      species: 'Gallenröhrling',
      difference: 'Der Kiefernsteinpilz ist rotbraun bis weinrot mit '
          'weißem Netz; der Gallenröhrling hell lederbraun mit grobem '
          'dunklem Netz — und bitter.'
    ),
    (
      species: 'Steinpilz',
      difference: 'Der Steinpilz ist heller hell- bis dunkelbraun, sein Hut '
          'glatt, und sein Netz ist WEISS auf hellem Grund. Der '
          'Kiefernsteinpilz ist kupferrot und trägt ein '
          'rötlichbraunes Netz.'
    ),
    (
      species: 'Sommersteinpilz',
      difference: 'Der Sommersteinpilz ist lederbraun, und seine Huthaut '
          'reißt bei Trockenheit FELDERIG auf. Der Kiefernsteinpilz '
          'bleibt kupferrot und runzelig-höckerig.'
    ),
    (
      species: 'Bronzeröhrling',
      difference: 'Der Bronzeröhrling ist schwarzbraun statt kupferrot und '
          'steht bei Eiche und Buche im Warmen, nicht bei Kiefer und '
          'Fichte.'
    ),
  ],
  'Bronzeröhrling': [
    (
      species: 'Gallenröhrling',
      difference: 'Der Bronzeröhrling ist sehr dunkel, fast schwarzbraun, '
          'und trägt ein weißes Netz; der Gallenröhrling ist hell mit '
          'dunklem Netz. Bitter ist nur der Gallenröhrling.'
    ),
    (
      species: 'Steinpilz',
      difference: 'Der Steinpilz ist deutlich heller, sein Hut bei Nässe '
          'klebrig, und sein Netz ist weiß auf hellem Grund. Der '
          'Bronzeröhrling ist fast schwarzbraun und durchweg matt.'
    ),
    (
      species: 'Sommersteinpilz',
      difference: 'Der Sommersteinpilz ist lederbraun und reißt auf dem Hut '
          'felderig auf. Der Bronzeröhrling bleibt dunkel und '
          'geschlossen samtig.'
    ),
    (
      species: 'Kiefernsteinpilz',
      difference: 'Der Kiefernsteinpilz ist kupfer- bis rotbraun und an '
          'Kiefer und Fichte gebunden; der Bronzeröhrling ist dunkler '
          'und ein Laubwaldpilz warmer Lagen.'
    ),
  ],
  'Maronenröhrling': [
    (
      species: 'Gallenröhrling',
      difference: 'Die Marone blaut auf Druck an den Poren; der '
          'Gallenröhrling tut das nicht, hat ein grobes dunkles '
          'Stielnetz und schmeckt bitter.'
    ),
  ],
  'Birkenpilz': [
    (
      species: 'Gallenröhrling',
      difference: 'Der Birkenpilz trägt dunkle Schüppchen auf dem Stiel, '
          'der Gallenröhrling ein erhabenes Netz. Beide stehen gern bei '
          'Birken.'
    ),
  ],
  'Gallenröhrling': [
    (
      species: 'Steinpilz',
      difference: 'Ein Gallenröhrling verdirbt ein ganzes Gericht. Sein '
          'Stielnetz ist dunkel und grob, seine Poren werden rosa — beim '
          'Steinpilz ist das Netz weiß und die Poren bleiben hell.'
    ),
    (
      species: 'Maronenröhrling',
      difference: 'Die Marone blaut auf Druck, der Gallenröhrling nicht.'
    ),
    (
      species: 'Birkenpilz',
      difference: 'Der Birkenpilz hat Schüppchen auf dem Stiel, der '
          'Gallenröhrling ein Netz.'
    ),
    (
      species: 'Sommersteinpilz',
      difference: 'Grobes dunkles Netz, rosa Poren und Gallengeschmack — '
          'der Sommersteinpilz hat ein weißes Netz und schmeckt nussig.'
    ),
    (
      species: 'Kiefernsteinpilz',
      difference: 'Der Kiefernsteinpilz ist deutlich dunkler, rotbraun, '
          'mit weißem Netz; der Gallenröhrling hell und bitter.'
    ),
    (
      species: 'Bronzeröhrling',
      difference: 'Der Bronzeröhrling ist fast schwarzbraun mit weißem '
          'Netz; der Gallenröhrling hell lederbraun mit dunklem Netz.'
    ),
  ],
  'Satansröhrling': [
    (
      species: 'Steinpilz',
      difference: 'Rote Poren und kräftiges Blauen im Schnitt — beides '
          'hat der Steinpilz nicht.'
    ),
    (
      species: 'Flockenstieliger Hexenröhrling',
      difference: 'Der Satansröhrling hat einen WEISSLICH-GRAUEN Hut und '
          'einen rot genetzten, bauchigen Stiel; der Flockenstielige '
          'einen dunkelbraunen Hut und rote FLOCKEN statt eines Netzes. '
          'Beide haben rote Poren.'
    ),
    (
      species: 'Schönfußröhrling',
      difference: 'Der Schönfußröhrling hat GELBE Poren, nie rote; das '
          'rote Netz auf dem Stiel haben beide.'
    ),
    (
      species: 'Netzstieliger Hexenröhrling',
      difference: 'Beide haben rote Poren und ein Stielnetz. Der '
          'Satansröhrling hat einen weißlich-grauen Hut und blaut nur '
          'schwach, der Netzstielige einen braunen Hut und blaut sofort '
          'kräftig.'
    ),
  ],
  'Flockenstieliger Hexenröhrling': [
    (
      species: 'Netzstieliger Hexenröhrling',
      difference: 'Der Stiel trägt rote FLOCKEN, kein Netz. Beide sind '
          'gegart essbar, roh giftig.'
    ),
    (
      species: 'Satansröhrling',
      difference: 'Der Flockenstielige hat einen DUNKELBRAUNEN Hut und '
          'rote Flocken auf gelbem Stiel; der Satansröhrling einen '
          'weißlich-grauen Hut und ein rotes Netz auf bauchigem Stiel. '
          'Rote Poren haben beide — der Hut entscheidet.'
    ),
    (
      species: 'Schönfußröhrling',
      difference: 'Der Schönfußröhrling hat GELBE Poren statt roter und '
          'ein rotes Netz statt Flocken; er ist bitter.'
    ),
  ],
  'Netzstieliger Hexenröhrling': [
    (
      species: 'Flockenstieliger Hexenröhrling',
      difference: 'Der Stiel trägt ein feines rotes NETZ, keine Flocken.'
    ),
    (
      species: 'Satansröhrling',
      difference: 'Der Netzstielige hat einen braunen Hut und blaut '
          'sofort kräftig; der Satansröhrling ist weißlich-grau und '
          'blaut nur schwach.'
    ),
    (
      species: 'Schönfußröhrling',
      difference: 'Beide haben ein rotes Stielnetz und blauen — aber der '
          'Schönfußröhrling hat GELBE Poren, der Netzstielige rote.'
    ),
  ],
  'Schönfußröhrling': [
    (
      species: 'Steinpilz',
      difference: 'Rotes Netz auf gelbem Stiel, gelbe Poren, Blauen im '
          'Schnitt und Gallengeschmack — der Steinpilz hat ein weißes '
          'Netz, verfärbt sich nicht und schmeckt mild.'
    ),
    (
      species: 'Flockenstieliger Hexenröhrling',
      difference: 'Gelbe Poren und ein rotes NETZ — der Flockenstielige '
          'hat rote Poren und rote FLOCKEN. Und der Schönfußröhrling ist '
          'bitter.'
    ),
    (
      species: 'Netzstieliger Hexenröhrling',
      difference: 'Gelbe Poren statt roter; das rote Stielnetz haben '
          'beide. Ein Bissen entscheidet: bitter heißt Schönfußröhrling.'
    ),
    (
      species: 'Satansröhrling',
      difference: 'Gelbe Poren statt roter; beide haben einen hellen Hut '
          'und ein rotes Netz. Der Schönfußröhrling ist bitter, der '
          'Satansröhrling giftig.'
    ),
  ],
  'Butterpilz': [
    (
      species: 'Körnchenröhrling',
      difference: 'Dem Körnchenröhrling fehlt der Ring am Stiel; er '
          'trägt stattdessen milchige Tröpfchen an den Poren.'
    ),
  ],
  'Körnchenröhrling': [
    (
      species: 'Butterpilz',
      difference: 'Der Butterpilz hat einen deutlichen Ring am Stiel.'
    ),
  ],
  'Ziegenlippe': [
    (
      species: 'Rotfußröhrling',
      difference: 'Der Rotfußröhrling zeigt unter der aufgerissenen '
          'Huthaut rotes Fleisch und hat einen rot überhauchten Stiel.'
    ),
  ],
  'Rotfußröhrling': [
    (
      species: 'Ziegenlippe',
      difference: 'Der Ziegenlippe fehlt das Rot — Stiel und Fleisch '
          'unter der Huthaut bleiben gelblich.'
    ),
  ],

  // ── Leistlinge ───────────────────────────────────────────────────
  'Pfifferling': [
    (
      species: 'Falscher Pfifferling',
      difference: 'Der echte Pfifferling hat stumpfe, gegabelte LEISTEN, '
          'die am Stiel herablaufen, und riecht nach Aprikose. Der '
          'falsche hat feine, dicht stehende echte Lamellen und ist '
          'orangeroter.'
    ),
    (
      species: 'Semmelstoppelpilz',
      difference: 'Unter dem Hut sitzen beim Semmelstoppelpilz weiche '
          'STACHELN, keine Leisten.'
    ),
  ],
  'Falscher Pfifferling': [
    (
      species: 'Pfifferling',
      difference: 'Feine, dicht stehende Lamellen statt stumpfer '
          'Leisten, und die Farbe geht ins Orangerote.'
    ),
  ],
  'Trompetenpfifferling': [
    (
      species: 'Herbsttrompete',
      difference: 'Der Trompetenpfifferling hat einen gelben, hohlen '
          'Stiel; die Herbsttrompete ist durchgehend grauschwarz.'
    ),
  ],
  'Herbsttrompete': [
    (
      species: 'Trompetenpfifferling',
      difference: 'Die Herbsttrompete ist grauschwarz, der '
          'Trompetenpfifferling hat einen gelben Stiel.'
    ),
  ],

  // ── Champignons und Knollenblätterpilze ──────────────────────────
  'Wiesenchampignon': [
    (
      species: 'Karbolchampignon',
      difference: 'Ritz die Stielbasis an: Der Karbolchampignon läuft '
          'dort chromgelb an und riecht beim Erhitzen nach Karbol oder '
          'Tinte.'
    ),
    (
      species: 'Grüner Knollenblätterpilz',
      difference: 'Junge Champignons haben ROSA Lamellen, die später '
          'schokoladenbraun werden, und keine Scheide am Stielgrund. '
          'Knollenblätterpilze haben weiße Lamellen und sitzen in einer '
          'häutigen Scheide.'
    ),
    (
      species: 'Kegelhütiger Knollenblätterpilz',
      difference: 'Rein weiße Lamellen und eine Scheide am Stielgrund — '
          'beim Champignon werden die Lamellen rosa bis braun, und eine '
          'Scheide fehlt.'
    ),
  ],
  'Anischampignon': [
    (
      species: 'Karbolchampignon',
      difference: 'Anis gegen Karbol: Der Anischampignon riecht '
          'angenehm nach Anis oder Marzipan und gilbt nur langsam, der '
          'Karbolchampignon läuft an der Stielbasis chromgelb an.'
    ),
  ],
  'Waldchampignon': [
    (
      species: 'Karbolchampignon',
      difference: 'Der Karbolchampignon läuft an der Stielbasis '
          'chromgelb an und stinkt beim Erhitzen.'
    ),
  ],
  'Karbolchampignon': [
    (
      species: 'Wiesenchampignon',
      difference: 'Die chromgelbe Verfärbung an der angeritzten '
          'Stielbasis und der Karbolgeruch beim Erhitzen fehlen den '
          'Speise-Champignons.'
    ),
    (
      species: 'Anischampignon',
      difference: 'Der Anischampignon riecht nach Anis, nicht nach '
          'Karbol.'
    ),
    (
      species: 'Waldchampignon',
      difference: 'Dem Waldchampignon fehlen chromgelbe Stielbasis und '
          'Karbolgeruch.'
    ),
  ],
  'Grüner Knollenblätterpilz': [
    (
      species: 'Wiesenchampignon',
      difference: 'Weiße Lamellen, die weiß BLEIBEN, und eine häutige '
          'Scheide am Stielgrund. Champignons haben rosa bis braune '
          'Lamellen und keine Scheide — grab den Stiel immer ganz aus.'
    ),
    (
      species: 'Frauentäubling',
      difference: 'Täublinge haben weder Ring noch Scheide und brechen '
          'krümelig wie ein Apfel; der Knollenblätterpilz hat beides und '
          'zähes Fleisch.'
    ),
    (
      species: 'Grüngefelderter Täubling',
      difference: 'Der Täubling hat keinen Ring und keine Scheide, und '
          'seine Huthaut ist felderig aufgerissen.'
    ),
    (
      species: 'Flaschenstäubling',
      difference: 'Halbiere jeden Stäubling der Länge nach: Zeigt sich '
          'darin die Silhouette eines Pilzes mit Hut und Stiel, ist es '
          'ein junger Knollenblätterpilz.'
    ),
    (
      species: 'Scheidenstreifling',
      difference: 'Dem Scheidenstreifling fehlt der RING, und sein '
          'Hutrand ist deutlich gerieft. Beide stecken in einer Scheide.'
    ),
    (
      species: 'Perlpilz',
      difference: 'Der Perlpilz trägt Flocken auf dem Hut, hat KEINE häutige '
          'Scheide an der Basis, und er rötet an Fraßstellen '
          'fleischrosa. Der Grüne Knollenblätterpilz ist glatthütig '
          'und bleibt überall weiß.'
    ),
  ],
  'Kegelhütiger Knollenblätterpilz': [
    (
      species: 'Wiesenchampignon',
      difference: 'Rein weiße Lamellen und eine Scheide am Stielgrund; '
          'Champignons haben rosa bis braune Lamellen und keine Scheide.'
    ),
  ],
  'Frühjahrsknollenblätterpilz': [
    (
      species: 'Maipilz',
      difference: 'Beide sind weiß und kommen im Frühjahr. Der Maipilz '
          'hat KEINEN Ring und keine Scheide und riecht stark nach Mehl; '
          'der Knollenblätterpilz hat beides.'
    ),
  ],

  // ── Schirmlinge ──────────────────────────────────────────────────
  'Parasol': [
    (
      species: 'Safranschirmling',
      difference: 'Der Safranschirmling RÖTET im Anschnitt safran- bis '
          'orangerot; der Parasol bleibt weiß und hat einen genatterten '
          'Stiel.'
    ),
  ],
  'Safranschirmling': [
    (
      species: 'Parasol',
      difference: 'Der Parasol rötet nicht und trägt die typische '
          'Schlangenhaut-Natterung am Stiel.'
    ),
  ],

  // ── Wulstlinge ───────────────────────────────────────────────────
  'Fliegenpilz': [
    (
      species: 'Perlpilz',
      difference: 'Der Perlpilz RÖTET: Fraßstellen, Schnittflächen und die '
          'Stielbasis laufen fleischrosa an, und seine Hutflocken '
          'sind schmutzig grau bis rosa. Beim Fliegenpilz bleibt das '
          'Fleisch weiß und die Flocken sind rein weiß.'
    ),
    (
      species: 'Pantherpilz',
      difference: 'Der Pantherpilz hat einen braunen bis olivbraunen Hut, '
          'einen glatten Ring und eine scharf gerandete Knolle. Der '
          'Fliegenpilz ist rot bis orangerot, sein Ring ist oberseits '
          'gerieft, und über der Knolle stehen ringförmige Gürtel.'
    ),
  ],
  'Perlpilz': [
    (
      species: 'Pantherpilz',
      difference: 'Der Perlpilz RÖTET an Fraßstellen und im Schnitt, '
          'sein Ring ist geriefelt, und seine Knolle ist rübenartig. Der '
          'Pantherpilz bleibt weiß, sein Ring ist glatt, und er hat eine '
          'abgesetzte Knolle mit Bergsteigersöckchen.'
    ),
    (
      species: 'Fliegenpilz',
      difference: 'Der Fliegenpilz trägt REIN WEISSE Flocken auf rotem bis '
          'orangerotem Hut und bleibt im Schnitt weiß. Ein vom Regen '
          'ausgeblasster Fliegenpilz kann ockerrot wirken — dann '
          'entscheidet, dass nur der Perlpilz fleischrosa rötet.'
    ),
    (
      species: 'Grüner Knollenblätterpilz',
      difference: 'Der Grüne Knollenblätterpilz hat eine häutige SCHEIDE an '
          'der Basis, einen glatten, oliv- bis gelbgrünen Hut ohne '
          'Flocken, und er rötet nie. Die Stielbasis freizulegen ist '
          'Pflicht, bevor ein Wulstling in den Korb kommt.'
    ),
  ],
  'Pantherpilz': [
    (
      species: 'Perlpilz',
      difference: 'Der Pantherpilz rötet NIE, sein Ring ist glatt, und '
          'am Stielgrund sitzt eine gerandete Knolle. Rötendes Fleisch '
          'und ein geriefelter Ring sprechen für den Perlpilz.'
    ),
    (
      species: 'Fliegenpilz',
      difference: 'Der Fliegenpilz ist rot bis orangerot, sein Ring ist '
          'oberseits GERIEFT, und über der Knolle stehen ringförmige '
          'Gürtel statt eines scharfen Randes. Der Pantherpilz ist '
          'braun und sein Ring glatt.'
    ),
  ],
  'Scheidenstreifling': [
    (
      species: 'Grüner Knollenblätterpilz',
      difference: 'Beide stecken in einer Scheide. Dem Scheidenstreifling '
          'fehlt der Ring, und sein Hutrand ist stark gerieft — wer sich '
          'nicht sicher ist, lässt ihn stehen.'
    ),
  ],

  // ── Täublinge ────────────────────────────────────────────────────
  'Frauentäubling': [
    (
      species: 'Grüner Knollenblätterpilz',
      difference: 'Täublinge haben keinen Ring und keine Scheide und '
          'brechen krümelig. Grab den Stiel aus: Eine häutige Scheide '
          'bedeutet Knollenblätterpilz.'
    ),
  ],
  'Grüngefelderter Täubling': [
    (
      species: 'Grüner Knollenblätterpilz',
      difference: 'Kein Ring, keine Scheide, und die Huthaut ist '
          'felderig aufgerissen.'
    ),
  ],
  'Speisetäubling': [
    (
      species: 'Speitäubling',
      difference: 'Die Geschmacksprobe entscheidet: Ein Stückchen auf '
          'die Zunge — der Speitäubling brennt scharf, der Speisetäubling '
          'schmeckt mild. Ausspucken.'
    ),
  ],
  'Speitäubling': [
    (
      species: 'Speisetäubling',
      difference: 'Brennend scharf statt mild; der Hut ist kräftig rot '
          'und die Huthaut lässt sich weit abziehen.'
    ),
  ],

  'Fichtenreizker': [
    (
      species: 'Edelreizker',
      difference: 'Der Edelreizker steht bei KIEFER, sein Hut ist deutlich '
          'konzentrisch gezont, und seine Milch bleibt stundenlang '
          'karottenrot. Der Fichtenreizker grünt rasch und '
          'großflächig.'
    ),
    (
      species: 'Lachsreizker',
      difference: 'Der Lachsreizker steht bei WEISSTANNE, ist lachs- bis '
          'aprikosenfarben und grünt nicht. Der Fichtenreizker läuft '
          'großflächig grün an und ist an Fichte gebunden.'
    ),
    (
      species: 'Kiefernreizker',
      difference: 'Der Kiefernreizker führt von Anfang an DUNKEL WEINROTE '
          'Milch und hat weinrot überhauchte Lamellen; beim '
          'Fichtenreizker ist die Milch zunächst karottenrot.'
    ),
  ],
  'Edelreizker': [
    (
      species: 'Fichtenreizker',
      difference: 'Der Fichtenreizker steht bei FICHTE und läuft auf Hut und '
          'Lamellen rasch großflächig grün an; seine Milch wird schon '
          'nach einer halben Stunde weinrot bis grünlich.'
    ),
    (
      species: 'Lachsreizker',
      difference: 'Der Lachsreizker ist blasser lachs- bis aprikosenfarben, '
          'kaum gezont und an Weißtanne gebunden. Der Edelreizker ist '
          'kräftig orange mit deutlichen Zonen und steht bei Kiefer.'
    ),
    (
      species: 'Kiefernreizker',
      difference: 'Der Kiefernreizker führt von Anfang an dunkel weinrote '
          'Milch; die des Edelreizkers ist karottenrot. Beide stehen '
          'bei Kiefer, der Kiefernreizker aber auf Kalk und später im '
          'Jahr.'
    ),
  ],
  'Lachsreizker': [
    (
      species: 'Fichtenreizker',
      difference: 'Der Fichtenreizker läuft grün an — beim Lachsreizker '
          'geschieht das nicht — und er ist an Fichte gebunden statt '
          'an Weißtanne.'
    ),
    (
      species: 'Edelreizker',
      difference: 'Der Edelreizker hat einen kräftig orangen, deutlich '
          'gezonten Hut und dunkle Stielgrübchen; er wächst bei '
          'Kiefer, der Lachsreizker bei Weißtanne.'
    ),
    (
      species: 'Kiefernreizker',
      difference: 'Der Kiefernreizker hat weinrote Milch und weinrot '
          'überhauchte Lamellen und steht bei Kiefer auf Kalk. Der '
          'Lachsreizker ist lachsfarben und an Weißtanne gebunden.'
    ),
  ],
  'Kiefernreizker': [
    (
      species: 'Fichtenreizker',
      difference: 'Der Fichtenreizker hat orange Lamellen und karottenrote '
          'Milch, die erst später umschlägt, und er grünt '
          'großflächig. Er steht bei Fichte, nicht bei Kiefer auf '
          'Kalk.'
    ),
    (
      species: 'Edelreizker',
      difference: 'Der Edelreizker hat KAROTTENROTE Milch und leuchtend '
          'orange Lamellen. Beim Kiefernreizker sind Milch und '
          'Lamellen weinrot überlaufen.'
    ),
    (
      species: 'Lachsreizker',
      difference: 'Der Lachsreizker ist lachs- bis aprikosenfarben mit '
          'orangeroter Milch und wächst bei WEISSTANNE, nicht bei '
          'Kiefer.'
    ),
  ],
  // ── Morcheln und Lorcheln ────────────────────────────────────────
  'Speisemorchel': [
    (
      species: 'Frühjahrslorchel',
      difference: 'Morcheln sind INNEN HOHL, von der Hutspitze bis zum '
          'Stielende, und ihr Hut ist wabig. Die Frühjahrslorchel ist '
          'hirnartig gewunden und innen kammerig gefüllt — sie ist '
          'tödlich giftig.'
    ),
  ],
  'Spitzmorchel': [
    (
      species: 'Frühjahrslorchel',
      difference: 'Längs halbieren: Die Spitzmorchel ist durchgehend '
          'hohl und wabig, die Frühjahrslorchel hirnartig gewunden und '
          'innen kammerig.'
    ),
  ],
  'Frühjahrslorchel': [
    (
      species: 'Speisemorchel',
      difference: 'Der hirnartig gewundene Hut und das kammerige Innere '
          'unterscheiden sie von der durchgehend hohlen, wabigen '
          'Speisemorchel.'
    ),
    (
      species: 'Spitzmorchel',
      difference: 'Hirnartig gewunden statt wabig, innen kammerig statt '
          'hohl.'
    ),
  ],
  'Käppchenmorchel': [
    (
      species: 'Böhmische Verpel',
      difference: 'Bei der Käppchenmorchel ist der Hut zur Hälfte mit '
          'dem Stiel verwachsen; bei der Verpel hängt er wie ein '
          'Fingerhut nur an der Spitze.'
    ),
  ],
  'Böhmische Verpel': [
    (
      species: 'Käppchenmorchel',
      difference: 'Der Hut hängt nur an der Spitze am Stiel, statt zur '
          'Hälfte mit ihm verwachsen zu sein.'
    ),
  ],

  // ── Boviste ──────────────────────────────────────────────────────
  'Flaschenstäubling': [
    (
      species: 'Grüner Knollenblätterpilz',
      difference: 'Jeden Stäubling längs halbieren: Reines weißes '
          'Fleisch ohne Zeichnung ist ein Stäubling. Zeigt sich die '
          'Silhouette eines Pilzes mit Hut und Stiel, ist es ein junger '
          'Knollenblätterpilz.'
    ),
  ],

  // ── Baumpilze und Stachelpilze ───────────────────────────────────
  'Austernseitling': [
    (
      species: 'Lungenseitling',
      difference: 'Der Lungenseitling ist heller, dünnfleischiger und '
          'kommt im Sommer; der Austernseitling ist grau bis '
          'blaubraun und ein Pilz der kalten Jahreszeit.'
    ),
  ],
  'Lungenseitling': [
    (
      species: 'Austernseitling',
      difference: 'Der Austernseitling ist dunkler, dickfleischiger und '
          'wächst nach den ersten Frösten.'
    ),
  ],
  'Semmelstoppelpilz': [
    (
      species: 'Pfifferling',
      difference: 'Unter dem Hut sitzen weiche Stacheln statt Leisten. '
          'Beide sind gute Speisepilze.'
    ),
  ],

  // ── Lamellenpilze ────────────────────────────────────────────────
  'Stockschwämmchen': [
    (
      species: 'Gifthäubling',
      difference: 'Der Stiel entscheidet: Beim Stockschwämmchen ist er '
          'unterhalb des Rings deutlich SCHUPPIG, beim Gifthäubling '
          'glatt und nur silbrig überfasert. Der Gifthäubling riecht '
          'mehlig und ist tödlich giftig. Im Zweifel: stehen lassen.'
    ),
    (
      species: 'Grünblättriger Schwefelkopf',
      difference: 'Der Schwefelkopf hat grünlich-gelbe Lamellen, '
          'schmeckt bitter und trägt keinen Ring.'
    ),
    (
      species: 'Hallimasch',
      difference: 'Der Hallimasch ist größer, hat einen wattigen Ring '
          'und dunkle Schüppchen auf dem Hut.'
    ),
  ],
  'Gifthäubling': [
    (
      species: 'Stockschwämmchen',
      difference: 'Sein Stiel ist unterhalb des Rings GLATT und silbrig '
          'überfasert, nicht schuppig, und er riecht mehlig. Er wächst am '
          'selben Holz wie das Stockschwämmchen und enthält dasselbe '
          'Gift wie der Grüne Knollenblätterpilz.'
    ),
    (
      species: 'Samtfußrübling',
      difference: 'Der Samtfußrübling hat einen samtig schwarzbraunen '
          'Stiel und keinen Ring; der Gifthäubling hat einen Ring und '
          'einen glatten, silbrig überfaserten Stiel.'
    ),
  ],
  'Samtfußrübling': [
    (
      species: 'Gifthäubling',
      difference: 'Der Samtfuß ist samtig schwarzbraun und RINGLOS; der '
          'Gifthäubling trägt einen Ring. Beide wachsen im Winter am '
          'selben Holz.'
    ),
    (
      species: 'Grünblättriger Schwefelkopf',
      difference: 'Der Grünblättrige Schwefelkopf hat SCHWEFELGELBE bis '
          'grünliche Lamellen und schmeckt bitter. Die Lamellen des '
          'Samtfußrüblings sind cremefarben bis blassgelb, und sein '
          'Stiel ist nach unten samtig schwarzbraun.'
    ),
  ],
  'Grünblättriger Schwefelkopf': [
    (
      species: 'Stockschwämmchen',
      difference: 'Grünlich-gelbe Lamellen, bitterer Geschmack, kein '
          'Ring — das Stockschwämmchen hat braune Lamellen und einen '
          'Ring mit schuppigem Stiel darunter.'
    ),
    (
      species: 'Hallimasch',
      difference: 'Dem Schwefelkopf fehlt der wattige Ring, und seine '
          'Lamellen sind grünlich statt weißlich.'
    ),
    (
      species: 'Samtfußrübling',
      difference: 'Der Samtfußrübling hat cremefarbene Lamellen, einen nach '
          'unten SAMTIG SCHWARZBRAUNEN Stiel und einen schmierig '
          'honiggelben Hut. Beim Schwefelkopf sind die Lamellen '
          'grünlich und der Geschmack bitter.'
    ),
  ],
  'Hallimasch': [
    (
      species: 'Grünblättriger Schwefelkopf',
      difference: 'Der Hallimasch hat einen wattigen Ring und '
          'weißliche Lamellen; der Schwefelkopf keinen Ring und '
          'grünliche.'
    ),
    (
      species: 'Stockschwämmchen',
      difference: 'Das Stockschwämmchen ist kleiner, sein Hut ist glatt '
          'und zweifarbig ausblassend.'
    ),
  ],
  'Maipilz': [
    (
      species: 'Ziegelroter Risspilz',
      difference: 'Der Risspilz hat einen radialfaserig aufreißenden, '
          'rötlich anlaufenden Hut und riecht spermatisch; der Maipilz '
          'riecht stark nach frischem Mehl.'
    ),
    (
      species: 'Riesenrötling',
      difference: 'Der Riesenrötling bekommt mit dem Alter ROSA '
          'Lamellen; beim Maipilz bleiben sie weiß.'
    ),
    (
      species: 'Frühjahrsknollenblätterpilz',
      difference: 'Dem Maipilz fehlen Ring und Scheide. Findet sich '
          'beides am Stiel, ist es kein Maipilz.'
    ),
  ],
  'Ziegelroter Risspilz': [
    (
      species: 'Maipilz',
      difference: 'Der Hut reißt radialfaserig auf und läuft rötlich an; '
          'der Maipilz hat einen glatten Hut und riecht nach Mehl.'
    ),
  ],
  'Riesenrötling': [
    (
      species: 'Maipilz',
      difference: 'Rosa werdende Lamellen — beim Maipilz bleiben sie '
          'weiß.'
    ),
    (
      species: 'Mönchskopf',
      difference: 'Der Mönchskopf hat weiße, am Stiel herablaufende '
          'Lamellen; beim Riesenrötling werden sie rosa und laufen nicht '
          'herab.'
    ),
  ],
  'Mönchskopf': [
    (
      species: 'Riesenrötling',
      difference: 'Der Riesenrötling hat rosa werdende, nicht '
          'herablaufende Lamellen und ist giftig.'
    ),
    (
      species: 'Nebelkappe',
      difference: 'Die Nebelkappe riecht streng süßlich und hat einen '
          'grauen, wie bereift wirkenden Hut; der Mönchskopf ist '
          'ockerfarben mit eingedelltem Hut.'
    ),
  ],
  'Nebelkappe': [
    (
      species: 'Mönchskopf',
      difference: 'Grauer, wie bereifter Hut und strenger süßlicher '
          'Geruch; der Mönchskopf ist ockerfarben und riecht mild.'
    ),
  ],
  'Violetter Rötelritterling': [
    (
      species: 'Violetter Lacktrichterling',
      difference: 'Der Lacktrichterling ist viel kleiner und dünner, '
          'seine Lamellen stehen entfernt und sind dick.'
    ),
  ],
  'Violetter Lacktrichterling': [
    (
      species: 'Violetter Rötelritterling',
      difference: 'Der Rötelritterling ist deutlich größer und '
          'fleischiger, seine Lamellen stehen dicht.'
    ),
  ],
};

/// Die Verwechslungspartner einer Art — leer, wenn keine bekannt sind.
///
/// **Leer heißt „uns ist keine häufige Verwechslung bekannt"**, nicht
/// „es gibt keine". Zweitnamen lösen sich auf, wie überall.
List<Lookalike> lookalikesFor(String? species) {
  final canonical = canonicalSpecies(species);
  return canonical == null
      ? const []
      : speciesLookalikes[canonical] ?? const [];
}

/// Der Einzeiler für den Moment, in dem jemand den Pilz in der Hand hat
/// (Eingabefeld beim Eintragen): „Wird verwechselt mit: Pantherpilz
/// (Giftig)". `null`, wenn die Art unbekannt ist oder keine Partner hat —
/// dann steht dort nichts, kein „keine bekannt".
///
/// **Genannt wird nur, was etwas ändern kann.** Ist die eingetippte Art
/// selbst harmlos, bleiben die harmlosen Partner weg: Wer „Steinpilz"
/// tippt und einen Sommersteinpilz in der Hand hält, dem passiert
/// nichts. Bei einer Art, die selbst warnt, steht alles da. Die volle
/// Liste trägt ohnehin die Artseite.
///
/// **Die Einstufung des Partners steht nur dabei, wenn sie warnt.** Ein
/// Speisepilz als Partner heißt schlicht „Speisetäubling", nie
/// „Speisetäubling (Gilt als Speisepilz)" — das läse sich im Eingabefeld
/// als Freigabe, und freigeben kann die App nichts. Dieselbe Asymmetrie
/// wie in der Liste und auf der Seite.
String? confusionHint(String? species) {
  var partners = lookalikesFor(species);
  if (partners.isEmpty) return null;
  // **Ist die eingetippte Art selbst harmlos, zählen nur die Partner,
  // die warnen.** Seit die Steinpilz-Gruppe und die Reizker
  // untereinander verzeichnet sind (1.171.0), hat der Steinpilz sechs
  // Partner, und die Zeile lief auf 158 Zeichen — mit dem
  // Satansröhrling als zweitem von sechs. Ein Formular ist nicht der
  // Ort für Vollständigkeit: Wer „Steinpilz" eintippt und stattdessen
  // einen Sommersteinpilz in der Hand hält, dem passiert nichts. Wer
  // einen Satansröhrling in der Hand hält, schon.
  //
  // Bei einer Art, die SELBST warnt, bleibt alles stehen — dort
  // erklärt der Speisepilz-Partner erst, warum jemand sie überhaupt im
  // Korb hätte („Speitäubling → Speisetäubling"). Die volle Liste
  // steht ohnehin auf der Artseite.
  final ownLevel = edibilityFor(species)?.level;
  if (ownLevel == null || !ownLevel.isWarning) {
    partners = partners
        .where((p) => edibilityFor(p.species)?.level.isWarning ?? false)
        .toList();
    if (partners.isEmpty) return null;
  }
  final parts = partners.map((p) {
    final level = edibilityFor(p.species)?.level;
    return level != null && level.isWarning
        ? '${p.species} (${level.label})'
        : p.species;
  });
  return 'Wird verwechselt mit: ${parts.join(', ')}';
}
