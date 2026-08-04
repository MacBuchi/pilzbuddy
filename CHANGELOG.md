# Änderungen in PilzBuddy

Was sich in welcher Version geändert hat — in Alltagssprache und mit dem
Neuesten zuerst. Dieselbe Liste steht in der App im Profil unter
„Über PilzBuddy" → „Was ist neu".

Die technische Fassung mit allen Einzelheiten liegt in den GitHub-Releases:
https://github.com/MacBuchi/pilzbuddy/releases

## Deine E-Mail-Adresse lässt sich jetzt ändern

*5. August 2026 · Version 1.52.0*

Die dritte neue Konto-Option im Profil: **„E-Mail-Adresse ändern"**.
Wichtig ist das, weil an der Adresse mehr hängt, als man denkt — Freunde
finden dich darüber, und der Code bei „Passwort vergessen" geht an genau
dieses Postfach. Wer sein altes Postfach verliert, wäre sonst irgendwann
ausgesperrt.

Der Wechsel ist bewusst gründlich abgesichert: Er verlangt dein
aktuelles Passwort, und danach kommen **zwei Mails mit zwei
verschiedenen Codes** — eine an die bisherige, eine an die neue Adresse.
Erst beide Codes zusammen vollziehen den Wechsel. So kann niemand, der
nur kurz an dein entsperrtes Handy oder an eines deiner Postfächer
kommt, dein Konto auf eine fremde Adresse umziehen.

## Andere Geräte abmelden

*5. August 2026 · Version 1.51.0*

Im Profil gibt es jetzt **„Andere Geräte abmelden"**. Der Handgriff für
den Fall, dass ein Handy verloren geht oder ein geteiltes Tablet noch
angemeldet ist: Nach einer Rückfrage wird die Anmeldung überall beendet
— nur auf dem Gerät, auf dem du gerade bist, bleibst du drin.

Gut zu wissen: Ein Passwortwechsel allein beendet laufende Anmeldungen
nicht sofort. Erst dieser Knopf wirft sie wirklich raus.

## Dein Benutzername lässt sich jetzt ändern

*5. August 2026 · Version 1.50.0*

Im Profil gibt es neben „Passwort ändern" jetzt **„Benutzername
ändern"**. Der Name ist das, worunter Freunde dich in der Suche finden —
deshalb steht im Dialog auch dabei: Nach der Änderung finden sie dich
unter dem neuen Namen.

Nebenbei ist eine Lücke geschlossen: Benutzernamen sind jetzt auch dann
einmalig, wenn sie sich nur in Groß- und Kleinschreibung unterscheiden.
Ein zweiter „marcus" neben einem „Marcus" wäre für alle, die suchen,
dasselbe Konto gewesen.

## Wie warm war es an deinem Spot

*4. August 2026 · Version 1.49.0*

Zum Regen im Spot-Blatt kommt jetzt die **Temperatur**: Über den blauen
Balken liegen dünne Linien — die **Bodentemperatur in 5 cm Tiefe** (dort
lebt das Pilzgeflecht) und die Tageshöchst- und Tiefstwerte der Luft.
Beide Achsen sind beschriftet: links Grad, rechts Millimeter. Und an den
Enden der Zeitskala steht jetzt das Datum, rechts zum Beispiel
„gestern, 3.8." — damit klar ist, in welche Richtung sie läuft.

Die Werte kommen von der **nächstgelegenen Wetterstation** des Deutschen
Wetterdienstes, und genau die steht auch dabei: Name, Entfernung und
Höhe. Die Höhe gehört dazu, weil sie den größten Unterschied macht —
eine Station 300 Meter tiefer ist gut zwei Grad wärmer, und das rechnet
die App bewusst nicht heraus, sondern schreibt es dir hin.

Wie beim Regen gilt: Die Suche nach der nächsten Station läuft
**auf deinem Gerät**. Kein Wetterdienst erfährt, wo deine Spots liegen.
Die Frage im Spot-Blatt heißt jetzt „Wetterdaten laden" und deckt beides
ab — wer dem Regen schon zugestimmt hat, bekommt die Temperatur ohne
neue Frage dazu.

## Der Regen ist jetzt zu lesen

*4. August 2026 · Version 1.48.0*

Die Regensummen auf der Karte sahen bisher so aus: dünne Linien, und
dazwischen ein Farbton, den man kaum sah. Wer nicht wusste, was gemeint
ist, konnte es auch nicht herausfinden — eine Legende gab es nicht.

Jetzt sind es **Flächen**. Jedes Band hat seine Farbe, von sandgelb
(wenig) über grün bis blau (viel), und man erkennt auf einen Blick, wo
mehr und wo weniger gefallen ist. Die Linien dazwischen sind weg; sie
werden nicht mehr gebraucht.

Damit klar ist, was die Farben bedeuten, gibt es jetzt **eine Legende
unten links**. Sie erscheint, sobald du eine Regenebene einschaltest, und
verschwindet wieder, wenn du sie ausschaltest.

Wie stark die Farbe sein darf, ist auf dem Gerät ausprobiert worden: zu
blass, und man sieht die Bänder nicht; zu kräftig, und die Ortsnamen
verschwinden darunter. Der jetzige Wert liegt bewusst dazwischen.

Das **Regenradar** („jetzt" und „in einer Stunde") ist unverändert und
behält die Farben und die Legende des Wetterdienstes.

## Wie viel Regen an genau diesem Spot — Tag für Tag

*4. August 2026 · Version 1.47.0*

Im Blatt eines Spots steht jetzt ganz unten, wie viel Regen dort gefallen
ist: als Summe über 7, 14 und 30 Tage — und als **Balken für jeden
einzelnen der letzten 14 Tage**.

Der Verlauf ist der eigentliche Punkt. Eine Summe kann nicht
unterscheiden, ob die 40 Millimeter vor elf Tagen fielen oder gestern, und
für Pilze ist genau das der Unterschied. Darum steht unter den Balken auch
ein Satz wie „Letzter nennenswerter Regen vor 3 Tagen".

**Deine Fundstelle bleibt geheim.** Das ist keine Nebensache, sondern der
Grund, warum das Ganze so umständlich gebaut ist: Die App fragt *niemanden*
nach dem Wetter an deinem Spot. Sie lädt die Messwerte für ganz Deutschland
herunter und schlägt die Stelle **auf deinem Gerät** nach. Es gibt keine
Anfrage, in der deine Koordinate steht — auch nicht beim Wetterdienst.

Der Preis dafür sind Daten: Beim ersten Mal rund 0,9 MB, danach täglich ein
kleines Stück. Deshalb wird vorher gefragt, und erst nach deinem Tippen
geladen — im Wald gibt man das nicht ungefragt aus. Wer einmal zugestimmt
hat, wird nicht wieder gefragt.

Zwei Dinge, die dazugehören: Die Messung deckt **nur Deutschland** ab, und
sie endet **gestern** — der Wetterdienst rechnet ganze Tage ab. Was heute
vom Himmel kommt, zeigt weiterhin das Regenradar auf der Karte. Liegt ein
Spot außerhalb der Messung, bleibt der Abschnitt einfach weg statt eine
leere Zeile zu zeigen.

## Der Regen liegt jetzt in unseren Farben

*4. August 2026 · Version 1.46.0*

Die beiden Regensummen — **letzte 24 Stunden** und **letzte 30 Tage** —
sehen anders aus als gestern. Statt einer deckenden Fläche liegen dort
jetzt **Höhenlinien**, so wie auf einer Wanderkarte die Höhe: Jede Linie
verbindet Orte mit gleich viel Regen, von sandgelb (wenig) über grün bis
blau (viel). Zwischen den Linien liegt derselbe Ton noch einmal ganz
zart, damit man auf einen Blick sieht, wo mehr und wo weniger war.

Der Grund ist praktisch. Die alte Fläche legte sich über alles, und beim
Hineinzoomen waren Wege und Ortsnamen kaum noch zu lesen. Eine Ebene, die
einen daran hindert, zum Spot zu finden, ist keine Hilfe. Jetzt bleibt
die Karte darunter vollständig sichtbar.

Je weiter man herauszoomt, desto weniger Linien zeigt die Karte — sonst
läge über Deutschland ein Netz, in dem nichts mehr zu erkennen wäre. Was
welche Farbe bedeutet, steht im Regen-Blatt unter der Ebenenwahl.

Nebenbei sind die Daten dabei rund zehnmal kleiner geworden, was im Wald
am Datenvolumen zählt.

Das **Regenradar** („jetzt" und „in einer Stunde") bleibt unverändert in
den Farben des Wetterdienstes: Blau-Grün-Gelb-Rot ist die Darstellung,
die man aus jeder Wetter-App kennt, und daran soll nicht herumgebastelt
werden.

Wenn die neuen Daten einmal nicht erreichbar sind, erscheint
stillschweigend wieder die bisherige Darstellung. Die Regenkarte ist eine
Zugabe und darf nichts kaputt machen.

## Regen auf der Karte

*4. August 2026 · Version 1.45.0*

Der neue Tropfen-Knopf an der Karte legt Regendaten des Deutschen
Wetterdienstes über die Landschaft. Drei Zeiträume stehen zur Wahl, und
sie beantworten verschiedene Fragen:

- **Jetzt** und **in einer Stunde** — das Regenradar. Nützlich für die
  Frage, ob man jetzt losgeht oder lieber nicht.
- **Letzte 24 Stunden** — wo es seit gestern geregnet hat.
- **Letzte 30 Tage** — die wichtigste der drei. Daran sieht man, ob der
  Boden über den Monat wirklich durchfeuchtet wurde, und nicht nur, ob
  es einmal kurz geschüttet hat.

Bewusst zeigt die Ebene nur **Messwerte** und sagt nirgends „hier stehen
jetzt Pilze". Was daraus folgt, weißt du für deine Wälder besser als
jede Formel.

Zwei Dinge, die man wissen sollte: Die Summen gibt es nur für
Deutschland, und das Radar reicht nicht bis in den Osten Österreichs
oder den Westen der Schweiz — dort bleibt die Fläche grau, und die
Legende sagt das auch. Und die Ebene ist beim Start immer aus: Sie lädt
ein Bild aus dem Netz, und das soll im Wald niemand ungefragt tun.

## Deine Spots sind jetzt auch ohne Empfang da

*4. August 2026 · Version 1.44.0*

Wer die App im Wald **neu startete**, wo kein Netz war, sah bisher eine
Karte ohne einen einzigen Spot — ohne Hinweis, woran es lag. Genau dort,
wo die heruntergeladenen Offline-Karten eigentlich helfen sollen.

- Deine eigenen Spots samt Funden liegen jetzt zusätzlich **auf dem Handy**.
  Ohne Empfang zeigt die Karte diesen Stand, statt leer zu bleiben.
- Ein Hinweis oben sagt dir dabei, **von wann** die Daten sind — so weißt
  du, ob der Spot von gestern schon dabei ist.
- Sobald du wieder Empfang hast, aktualisiert sich alles von selbst und der
  Hinweis verschwindet.
- Beim Abmelden wird der Zwischenspeicher gelöscht, und in Googles
  Handy-Backup landet er nie: Deine Fundstellen bleiben deine.

## Eine neue Karten-Engine — erst zum Ausprobieren, jetzt Standard

*3. August 2026 · Versionen 1.39.0 bis 1.43.1*

Im Profil gibt es einen Schalter **„Neue Karten-Engine"** — nur in der
Android-App. Er stellt die Karte auf einen anderen Renderer um, der die
Offline-Karten spürbar flüssiger zeichnet, gerade beim schnellen Zoomen
und Wischen.

- Seit 1.40.0 zeigt die neue Engine auch **deine Spots, die Positionen
  deiner Freunde und deinen eigenen Standort** — antippen funktioniert wie
  gewohnt.
- Seit 1.41.0 kann sie auch die **Online-Karte**: Mit Empfang kommen die
  gewohnten OpenStreetMap-Kacheln, ohne Empfang springt sie automatisch
  auf deine heruntergeladenen Regionen um — nach denselben Regeln wie die
  bisherige Karte. Maßstab und Kartenhinweis sind auch da. Damit kann die
  neue Engine alles, was die alte kann.
- Mit 1.43.1 ist der Download der App wieder **ein Drittel kleiner**
  (45 statt 67 MB): Im Paket steckten Programmteile für Handy-Prozessoren,
  auf denen PilzBuddy gar nicht läuft. Sie sind jetzt draußen — an der App
  selbst ändert sich nichts.
- Seit 1.43.0 ist die neue Engine **Standard**: Im nachgemessenen
  Direktvergleich zeichnet sie beim Wischen rund fünfmal so viele Bilder
  pro Sekunde und braucht unter Dauerlast nur gut ein Drittel des
  Speichers. Der Schalter bleibt im Profil — wer mag, holt sich damit
  die bisherige Karte zurück.

## Die Karte friert nicht mehr ein — und bleibt nicht mehr grau

*3. August 2026 · Versionen 1.38.2 und 1.38.3*

Zwei Karten-Fehler, deren Folgen manche schon kannten, sind gefunden und
behoben:

- Ein seltener Grenzfall bei den Fingergesten konnte die Kartenansicht in
  einen kaputten Zustand bringen: Die App fror mitten in der Bewegung ein,
  bis Android sie zum Schließen vorschlug. Der kaputte Zustand wird jetzt
  an der Wurzel verworfen und kann gar nicht mehr entstehen.
- Nach einem kurzen Empfangsverlust (U-Bahn, Funkloch am Waldrand) blieben
  neue Online-Kacheln dauerhaft grau: Nur schon besuchte Gegenden
  erschienen noch, und erst ein App-Neustart half. Jetzt übersteht die
  Online-Karte den Wechsel und lädt danach normal weiter.

## Mehrere Pilzarten gleichzeitig filtern

*2. August 2026 · Versionen 1.38.0 und 1.38.1*

Im Filter-Blatt lässt sich jetzt mehr als eine Art anhaken. Wer im Herbst
sowohl nach Maronen als auch nach Pfifferlingen unterwegs ist, sieht beide
Sorten Fundstellen auf einer Karte statt nacheinander.

- Angehakt wird durch Antippen, noch einmal antippen nimmt die Art wieder
  raus.
- **„Alle Arten"** ganz oben räumt die Auswahl in einem Tipp weg — egal wie
  viele Häkchen gesetzt sind. „Nur meine Spots" bleibt davon unberührt, das
  sind zwei getrennte Schalter.
- Gezeigt wird, was zu **einer** der gewählten Arten passt. Nicht: wo alle
  gewählten zusammen vorkommen — das wäre fast immer die leere Karte.
- Oben auf der Karte stehen bei einer oder zwei Arten die Namen, ab drei die
  Zahl. Sonst wüchse die Zeile über die Karte.

## Zweitnamen: „Totentrompete" findet jetzt auch „Herbsttrompete"

*2. August 2026 · Version 1.37.0*

Viele Pilze haben zwei geläufige Namen, und für die App waren das bisher
zwei verschiedene Arten. Wer seine Fundstellen als „Totentrompete"
eingetragen hatte und später nach „Herbsttrompete" filterte, sah sie nicht.

- Beim Eintragen kannst du **beide Namen** tippen. Gespeichert wird immer
  derselbe — die Hauptbezeichnung. Darunter steht dann, wie der Pilz sonst
  noch heißt, damit du siehst, dass du richtig lagst.
- Der Filter auf der Karte, die Zahl der Fundstellen und die Top-Arten im
  Profil ziehen beide Namen zusammen. Das gilt auch für deine **alten**
  Funde: Du musst nichts nachtragen.
- In der Fundliste einer Stelle steht weiterhin, was du damals geschrieben
  hast. Der Eintrag ist dein Protokoll, den benennen wir nicht nachträglich
  um.
- Erkannt werden unter anderem: Totentrompete, Marone, Herrenpilz,
  Fichtensteinpilz, Riesenschirmling, Fette Henne, Austernpilz,
  Mairitterling, Butterröhrling, Rötender Wulstling, Flaschenbovist,
  Riesenstäubling, Nebelgrauer Trichterling, Winterrübling, Rotfüßchen und
  Spargelpilz.

**Eine Art wechselt die Zuordnung:** „Braunkappe" ist in der App bisher als
Marone geführt worden. Gemeint ist damit der Riesenträuschling — so heißt er
auch. Deine Spots mit diesem Namen bekommen deshalb ein anderes Symbol und
zählen ab jetzt zum Riesenträuschling.

**Der Igelstachelbart sieht endlich aus wie einer.** Er stand bei den
Baumpilzen und wurde als orange Konsole gezeichnet. Er wächst zwar an Holz,
ist aber ein weißlicher Knollen mit langen hängenden Stacheln — genau so
steht er jetzt auf der Karte. „Affenkopfpilz" und „Löwenmähne" werden als
Namen dafür erkannt.

Auch behoben: Im Profil zählten „Steinpilz" und „steinpilz" als zwei
verschiedene Arten und standen getrennt untereinander.

## Vier neue Pilzarten — und Hexenröhrlinge, die man unterscheidet

*2. August 2026 · Version 1.36.0*

Vier Arten, die ihr euch über das Rückmeldeformular gewünscht habt, stehen
jetzt in der Vorschlagsliste: **Netzstieliger Hexenröhrling**,
**Käppchenmorchel**, **Morchelbecherling** und **Böhmische Verpel**.

Jede hat ein eigenes Kartensymbol bekommen, statt nur das ihrer Gruppe:

- Die beiden **Hexenröhrlinge** sehen jetzt aus, wie sie im Wald aussehen —
  olivbrauner Hut über roten Poren auf gelbem Stiel. Auseinanderhalten kann
  man sie am Stiel: rotes Netz beim Netzstieligen, rote Flocken beim
  Flockenstieligen. Vorher waren beide ein brauner Pilz wie jeder andere,
  und der sah aus wie ein Steinpilz.
- Der **Morchelbecherling** steht als offene Schale mit Adern auf der Karte,
  nicht mehr als Morchelkegel.
- **Käppchenmorchel** und **Böhmische Verpel** haben beide ihren kleinen Hut
  auf dem langen blassen Stiel — die eine mit Waben, die andere mit
  Längsrillen.

Die Verpel lag außerdem in der falschen Schublade und wurde als grauer
Lamellenpilz gezeichnet. Sie steht jetzt bei den Morcheln und Lorcheln, wo
sie hingehört.

Dabei ist noch einer aufgefallen: Der **Semmelstoppelpilz** war ebenfalls
ein grauer Lamellenpilz — obwohl er gar keine Lamellen hat und semmelfarben
ist. Er hat jetzt seinen flachen, hell gebackenen Hut, und darunter sitzen
die Stoppeln, die ihm den Namen geben.

**Pilze ohne Lamellen haben jetzt eine eigene Schublade.** Sie hieß bisher
für alle „Lamellenpilz", und das steht sichtbar am Vorschlag, wenn du eine
Art eintippst. Für vier stimmte es nicht: Krause Glucke, Semmelstoppelpilz,
Habichtspilz und Ziegenbart heißen jetzt „Stachel-/Korallenpilz" und sehen
auch so aus. Die **Krause Glucke** und der **Ziegenbart** werden dabei ohne
Stiel gezeichnet — die haben nämlich keinen.

**Und die Artenliste ist gewachsen.** Dreizehn geläufige Pilze fehlten
schlicht: Maipilz, Nelkenschwindling, Rehbrauner Dachpilz,
Riesenträuschling, Rotfußröhrling, Körnchenröhrling, Grüngefelderter
Täubling, Speitäubling, Birnenstäubling, Lungenseitling, Habichtspilz,
Ziegenbart und Scheidenstreifling. Der Scheidenstreifling hat ein eigenes
Bild bekommen, weil er als Wulstling sonst rot mit weißen Punkten wäre —
und das ist er gerade nicht.

## Karte nach Pilzart filtern

*2. August 2026 · Version 1.35.0*

- Der neue Knopf mit dem Trichter öffnet ein Blatt mit allen Arten, zu denen
  du Funde hast — samt Zahl der Fundstellen. Eine antippen, und die Karte
  zeigt nur noch diese.
- Gefiltert wird über **alle** Funde einer Stelle, nicht nur den letzten:
  Wenn du dort einmal Pfifferlinge gefunden hast, findest du sie unter
  „Pfifferling" wieder — auch wenn zuletzt etwas anderes dort stand.
- Getrennt davon schaltbar: „Nur meine Spots" blendet die deiner Freunde aus.
- Solange gefiltert ist, steht das oben auf der Karte, mit einem Kreuz zum
  Aufheben. Beim nächsten Start liegt wieder alles auf der Karte — ein
  vergessener Filter, der Fundstellen versteckt, wäre der teurere Fehler.

## Updates wieder in der App

*2. August 2026 · Version 1.34.0 · nur Android, nur die Version von GitHub*

Bisher öffnete „Update" den Browser; die geladene Datei musste man dann
selbst finden und antippen. Das geht wieder direkt in der App.

- Im Update-Hinweis auf „Jetzt aktualisieren" tippen: Die App lädt die neue
  Version mit Fortschrittsanzeige und übergibt sie an Android, das wie
  gewohnt nach der Bestätigung fragt.
- Beim ersten Mal fragt Android einmalig, ob PilzBuddy Apps installieren
  darf. Der Dialog führt mit einem Tipp zu dieser Einstellung — danach ist
  jedes weitere Update ein Tipp.
- Der Weg über den Browser bleibt daneben stehen. Wenn beim Laden etwas
  schiefgeht, sagt der Dialog, was los war, und bietet ihn an.
- Deine Spots und heruntergeladenen Karten bleiben bei einem Update
  selbstverständlich erhalten.

## Zwei Kleinigkeiten aus dem Wald

*2. August 2026 · Version 1.33.1*

- Beim Anlegen eines **neuen** Spots ist das Artenfeld jetzt leer, statt die
  zuletzt gemeldete Art vorzuschlagen. Die musste man vorher jedes Mal
  löschen, wenn der nächste Fund eine andere Art war. Deine eigenen Arten
  stehen weiter als Knöpfe darüber — ein Tipp statt Tippen. Beim
  **Wiederbesuch** bleibt die Art des Spots wie bisher vorbelegt.
- Der Umschalter zwischen Online- und Offline-Karte merkt sich deine Wahl
  über den Neustart hinweg. Vorher stand die App nach jedem Start wieder auf
  Online — ausgerechnet dort, wo man sie bewusst umgestellt hatte.

## Versionshistorie in der App

*2. August 2026 · Version 1.33.0*

- Diese Liste gibt es jetzt auch in der App: Profil → „Über PilzBuddy" →
  „Was ist neu".
- Sie ist mitgeliefert und braucht keine Verbindung — sie lässt sich also
  auch im Wald nachlesen.

## Die Karte bleibt sichtbar

*26. und 27. Juli 2026 · Versionen 1.29 bis 1.32.1*

Der Schwerpunkt dieser Woche: Die Karte soll nie als graue Fläche dastehen,
und sie soll langes Verschieben und Zoomen überstehen, ohne die App
anzuhalten.

- Wo noch keine Karte geladen ist, liegt jetzt ein Landton statt einer
  grauen Fläche; einmal geladene Bereiche bleiben zwischengespeichert.
- Ohne Empfang und im Offline-Modus liegt eine eingebaute Übersichtskarte
  unter der Karte — statt Leere siehst du Land, Küsten und Grenzen.
- Die Karte geht deutlich sparsamer mit Speicher um. Vorher konnte langes
  Verschieben dazu führen, dass Android die App beendet.
- Beendet sich die App unerwartet, meldet sie beim nächsten Start selbst,
  woran es lag. Vorher blieb so etwas unbemerkt.

**Behoben:** Die Offline-Karte blieb leer, sobald eine Region fertig
heruntergeladen war. Beim Abmelden erschien eine Fehlermeldung, obwohl
nichts schiefgegangen war.

## Konto, Anmeldung und Passwort

*25. und 26. Juli 2026 · Versionen 1.27, 1.28, 1.31.0 und 1.31.1*

Die Anmeldung war der Bereich mit den meisten Sackgassen. Für jeden Fall
gibt es jetzt einen Weg zurück ins Konto.

- Bei der Registrierung bestätigst du deine E-Mail-Adresse mit einem Code
  aus der Mail. Damit gehört die Adresse wirklich zum Konto — wichtig, weil
  die Freundessuche und das Zurücksetzen des Passworts daran hängen.
- „Passwort vergessen" läuft ebenfalls über einen Zahlencode. Der
  funktioniert auch dann, wenn du die Mail auf einem anderen Gerät liest.
- „Passwort ändern" gibt es im Profil; es fragt zur Sicherheit das aktuelle
  Passwort ab.
- Beide Mails lassen sich erneut anfordern, mit 60 Sekunden Wartezeit
  dazwischen.
- Passt eine ältere App-Version nicht mehr zum Server, sagt die App das
  jetzt deutlich, statt mit „Internet verfügbar?" zu scheitern.

## Recht, Lizenz und Konto-Löschung

*20. und 21. Juli 2026 · Versionen 1.22 bis 1.26.0*

- Du kannst dein Konto selbst löschen — sofort, ohne Karenzzeit, in der App
  oder über eine Webseite ohne installierte App.
- Eine Datenschutzerklärung sagt, was gespeichert wird und was davon
  öffentlich ist. Sie ist im Profil verlinkt.
- PilzBuddy steht unter der MIT-Lizenz; die Lizenzen aller verwendeten
  Bausteine stehen im Profil.
- Updates lädt jetzt der Browser herunter und du installierst sie selbst.
  Der eingebaute Installer brauchte dafür Berechtigungen, die eine
  Karten-App nicht haben sollte.
- Fehler, die die App abfängt und übersteht, werden gesammelt. Sonst bleibt
  unbemerkt, was Nutzerinnen und Nutzer stört, ohne dass die App abstürzt.

## Live-Standort teilen

*19. und 20. Juli 2026 · Versionen 1.16 bis 1.21.1*

- Deine eigene Position erscheint als Buddy-Avatar auf der Karte.
- Den Live-Standort kannst du für 1, 2 oder 4 Stunden mit Freunden teilen.
  Die Freigabe endet von selbst und lässt sich jederzeit vorher beenden.
- Unten links steht ein Maßstab, und der Zoom endet dort, wo es keine
  Kartendaten mehr gibt.
- Kartendownloads laufen weiter, wenn du zwischendurch die App wechselst.

**Behoben:** Login- und Registrierungsfelder waren für Passwortmanager
unsichtbar. Die Karte setzte gelegentlich aus. Das Feedback-Banner
verschwand sofort nach dem Absenden. Die Anmeldedaten landeten im
Android-Cloud-Backup.

## Import und Export

*19. Juli 2026 · Versionen 1.15 bis 1.16.1*

- GPX-, KML- und KMZ-Dateien aus anderen Karten-Apps importieren; jeder
  Punkt wird einzeln zu einem Spot, den du vorher noch anpassen kannst.
- Eigene Spots samt Fundhistorie als GPX exportieren.
- Art und Funddatum werden aus dem Wegpunkt vorbelegt, soweit sie sich
  daraus erkennen lassen.

**Behoben:** GPX- und KML-Dateien waren im Android-Dateidialog ausgegraut
und ließen sich nicht auswählen.

## Offline-Karten

*19. Juli 2026 · Versionen 1.10 bis 1.13.2 · nur Android*

- Karten einzelner Bundesländer im Profil herunterladen. Ohne Empfang
  schaltet die App von selbst darauf um.
- Große Downloads lassen sich fortsetzen und laufen weiter, wenn du in der
  App woanders hin wechselst.
- Heruntergeladene Karten werden gegen eine Prüfsumme geprüft, damit keine
  halbe Datei als fertig gilt.
- Eine Übersichtskarte für Deutschland, Österreich und die Schweiz ist
  eingebaut. Auch ohne heruntergeladene Region siehst du damit Land statt
  einer grauen Fläche.
- Bricht die Verbindung unterwegs ab, gibt der Download nicht mehr auf,
  sondern nimmt den Faden von selbst wieder auf.

**Behoben:** Der Offline-Karte fehlten die Beschriftungen und die Farben
für Wald, Wasser und Siedlung.

## Pilz-Icons, Avatare und App-Icon

*18. bis 25. Juli 2026 · Versionen 1.2.1 bis 1.26.4*

- Die Marker zeigen die Pilzgruppe, statt nur „essbar" oder „giftig" zu
  behaupten. PilzBuddy bestimmt keine Pilze.
- Eigene Zeichnungen für Pfifferling, Totentrompete, Milchlinge und
  Maronen-Röhrling.
- Für das Profil lässt sich ein Pilz-Avatar auswählen.
- Das App-Icon zeigt die Buddies groß, statt sie klein in der Mitte
  verschwinden zu lassen.

**Behoben:** In den Listen fehlten die Arten-Icons, und Stiel und
Kartenansicht waren falsch gezeichnet. Das Diagramm „Funde pro Jahr" hatte
eine unlesbare Achse.

## Rückmeldungen direkt aus der App

*18. und 19. Juli 2026 · Versionen 1.4 bis 1.9.5*

- Wunsch, Fehler oder eine fehlende Pilzart direkt aus der App melden.
  Daraus entsteht automatisch ein Eintrag im öffentlichen Projekt — ein
  Hinweis im Dialog sagt das vorher deutlich.
- Die Android-App weist auf neue Versionen hin.
- Auf Wunsch aufgenommen: Violetter Lacktrichterling.
- Die Daten deiner Freunde aktualisieren sich von selbst. Bei fremden Spots
  steht, wer sie gefunden hat, und die Farbe zeigt, wem ein Spot gehört.

**Behoben:** Die Karte ließ sich versehentlich verdrehen — die Drehgeste
ist abgeschaltet. Ein Update konnte die App nach dem Herunterladen zum
Absturz bringen.

## Der Anfang

*18. Juli 2026 · Versionen 1.0 bis 1.3*

- Pilz-Spots auf der Karte festhalten: Position über ein Fadenkreuz statt
  mit dem Finger zielen, dazu Art, Anzahl, Funddatum und eine Notiz.
- Auswahl bekannter Pilzarten mit Kategorien und passenden Icons.
- Freunde einladen und Spots mit ihnen teilen.
- Animierte Buddies auf dem Anmeldebildschirm.

## Unter der Haube

Nicht jede Version bringt etwas Sichtbares. Dazwischen liegt das, was man
erst bemerkt, wenn es fehlt: ein wöchentliches verschlüsseltes Backup der
Datenbank, automatische Tests vor jeder Veröffentlichung, ein Abgleich
zwischen App und Datenbank, der falsche Änderungen vor der Auslieferung
stoppt, und eine wöchentliche Zusammenfassung aller Fehler, die die App
abgefangen hat.
