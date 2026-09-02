# Änderungen in PilzBuddy

Was sich in welcher Version geändert hat — in Alltagssprache und mit dem
Neuesten zuerst. Dieselbe Liste steht in der App im Profil unter
„Über PilzBuddy" → „Was ist neu".

Die technische Fassung mit allen Einzelheiten liegt in den GitHub-Releases:
https://github.com/MacBuchi/pilzbuddy/releases

## Vom Spot direkt in die Navi-App

*2. September 2026 · Version 1.112.0*

Ein Spot ist schnell gesetzt — aber wie kommt man beim nächsten Mal
wieder hin? Bisher blieb nur, die Stelle auf der Karte zu suchen und sich
den Weg selbst zusammenzureimen.

Im Spot-Detail steht jetzt oben ein neuer Knopf: **In Navi-App öffnen**.
Ein Tipp darauf, und Android fragt, womit du hin willst — Google Maps,
OsmAnd, Locus, Organic Maps, Komoot, OruxMaps: was immer bei dir
installiert ist. Der Spot ist dort schon gesetzt, mit seinem Namen als
Beschriftung.

Das geht auch bei Spots, die ein Pilzfreund mit dir teilt. Löschen darf
sie weiterhin nur, wem sie gehören — hinfahren darfst du.

Zwei Dinge, die dir wichtig sein könnten:

- **Die Koordinate verlässt dein Gerät dabei nicht ins Internet.** Sie
  geht an die App, die du im Auswahlfenster antippst, und an sonst
  niemanden. Wir hätten stattdessen einen Kartendienst im Browser öffnen
  können — das wäre ein fester Empfänger gewesen und ausgerechnet im
  Funkloch nutzlos.
- Ist keine passende App installiert (oder benutzt du PilzBuddy im
  Browser), landen die Koordinaten in der Zwischenablage, und die App
  sagt dir das.

## „Nicht gespeichert" — obwohl gespeichert

*2. September 2026 · Version 1.111.1*

Wenn der Server beim Speichern eines Spots oder eines Fundes gerade
überlastet war, konnte es passieren, dass PilzBuddy „Internet
verfügbar?" meldete, obwohl alles gut gegangen war. Der Spot lag längst
auf dem Server — nur die Liste danach kam nicht mehr durch, und die App
hat diesen zweiten Fehler für den ersten gehalten.

Für dich sah das aus wie ein misslungener Versuch: keine
Bestätigungsmeldung, und auf der Karte war der neue Spot auch nicht zu
sehen. Naheliegenderweise trägt man ihn dann noch einmal ein — und
danach steht er doppelt da.

Jetzt unterscheidet die App die beiden Fälle. Ging das Speichern durch,
sagt sie das auch, selbst wenn die Liste danach hakt: „Spot gespeichert
🍄 — sichtbar, sobald die Liste wieder lädt." Ein echter Fehler beim
Speichern bleibt dagegen ein Fehler; daran ändert sich nichts.

Falls du in den letzten Wochen einen Spot doppelt angelegt hast: Im
Profil steht dann „Dicht beieinander" — dort lassen sich zwei Spots am
selben Fleck zusammenführen. Der Eintrag erscheint nur, wenn es
tatsächlich solche Paare gibt.

## Die Web-App zeigt wieder Regen — und ist auf dem Handy lesbar

*2. September 2026 · Version 1.111.0*

In der Web-App (der Version, die du dir über den Browser auf den
Startbildschirm legst) fehlten der Pilzampel die Regendaten, und die
Regenkarte lag in groben Klötzchen statt weich verlaufend auf der Karte.
Beides hatte dieselbe Ursache: Die Regendaten kamen dort schlicht nie an.

Der Grund liegt in einer Sicherheitsregel der Browser, die den Weg
verbaut, über den die Android-App ihre Regendaten holt. Die Daten liegen
jetzt zusätzlich an einer Adresse, die der Browser lesen darf. Was die
App daraus macht, ist unverändert — es sind dieselben Zahlen aus derselben
Quelle, sie kommen nur auf einem anderen Weg an.

Ärgerlich daran war vor allem, dass nichts davon nach einem Fehler aussah:
Ohne Regendaten zeichnet die Karte ersatzweise das Bild des Deutschen
Wetterdienstes, und das ist absichtlich hart gerastert. Es sah also nicht
kaputt aus, sondern nur schlechter — und die Ampel schwieg einfach.

**Außerdem hat die Web-App ihre Farbe zurück.** Auf dem Startbildschirm
installiert, waren die Systemleisten oben und unten weiß, und damit auch
Uhr, Empfangsbalken und die Bedienelemente von Android darin unsichtbar.
Sie sind jetzt wieder grün. Und die Seite bringt ihren Maßstab wieder
selbst mit — ohne das rechnete der Browser mit einer Bildschirmbreite,
die es nicht gibt.

## Die Einführung zeigt jetzt alle Knöpfe — und weiß, wo es weitergeht

*29. August 2026 · Versionen 1.110.0 und 1.110.1*

Die kurze Einführung beim ersten Start führte an vier Bedienelementen
entlang. Zwei davon fehlten: „Meine Position" kam gar nicht vor, und am
Ende stand kein Weg zur Kurzanleitung — obwohl gerade die Dinge, die die
Einführung bewusst auslässt, dort erklärt sind: Leergänge, was du mit
Buddies teilst, und Karten für unterwegs ohne Empfang.

Jetzt sind es fünf Schritte, und sie decken jeden Knopf auf der Karte ab.
Im letzten steht neben „Los geht's" ein Knopf, der dich direkt in die
Kurzanleitung bringt. Wer sie später noch einmal sehen will, findet sie
wie bisher im Profil unter „Kurzanleitung".

**Die Zurück-Taste beendet jetzt die Einführung.** Bisher tat sie das,
was sie auf der Karte immer tut: Sie legte PilzBuddy in den Hintergrund.
Wer die Abdunkelung auf dem gewohnten Weg loswerden wollte, stand also
plötzlich außerhalb der App. Zurück zählt dabei wie „Überspringen" — wer
abbricht, hat entschieden.

**Und die Erklärkarte sitzt richtig.** Sie stand rund achtzig Pixel zu
tief und lag damit im ersten Schritt ausgerechnet auf dem Fadenkreuz, das
sie erklärt. Auf kleinen Bildschirmen rutschten ihre Knöpfe sogar über
den oberen Rand hinaus — dort ließ sich die Einführung nur noch durch
Tippen irgendwohin weiterschalten. Beides ist behoben; passt der Text
nicht ganz, lässt er sich jetzt scrollen, statt die Knöpfe wegzuschieben.

## Die Karte startet dort, wo du stehst

*29. August 2026 · Version 1.109.0*

Beim Öffnen springt die Karte jetzt einmal zu deiner Position, statt bei
der Mitte Deutschlands anzufangen. Sie zoomt dabei absichtlich nicht so
nah heran wie der Knopf „Auf mich zentrieren": Du siehst rund zehn
Kilometer im Umkreis und damit deine Spots in der Gegend, nicht nur den
Fleck, auf dem du stehst.

**Einmal, nicht dauernd.** Wenn du danach weiterschiebst, bleibt die Karte
dort, wo du sie hingeschoben hast — auch wenn dein GPS beim Gehen laufend
neue Positionen meldet. Und wer schon losgeschoben hat, bevor der erste
Standort da war, wird nicht mitten in der Bewegung weggezogen.

Hat die App den Standort noch nie gedurft, passiert beim Start nichts —
gefragt wird weiterhin nur, wenn du selbst auf „Auf mich zentrieren"
tippst. Danach klappt es bei jedem Start.

## Das Spot-Blatt bleibt unter der Statusleiste

*29. August 2026 · Version 1.108.1*

Das Blatt eines Spots reichte fast bis an den oberen Bildschirmrand —
nachgemessen sieben Pixel unter der Statusleiste. Wer oben nach dem Griff
fasste, um es wegzuwischen, zog dabei die Benachrichtigungsleiste herunter.
Jetzt bleibt darüber ein deutlicher Streifen Karte frei.

**Deine Meldungen tragen künftig die App-Version.** Wenn du in der App
einen Fehler oder Wunsch meldest, steht jetzt dabei, aus welcher Version
er kam — sonst lässt sich oft nicht sagen, ob ein Fehler noch besteht oder
mit dem letzten Update schon behoben wurde. Die Version steht wie der Text
und dein Benutzername im öffentlichen GitHub-Projekt.

## Eine kurze Tour beim ersten Start

*29. August 2026 · Version 1.108.0*

Beim allerersten Start führt dich die App jetzt in **vier Schritten** über
die Karte: wie ein Spot entsteht (das Fadenkreuz und „Neuer Spot" gehören
zusammen), was hinter „Ebenen" liegt, was du unterwegs machen kannst, und
wozu der Filter da ist. Der jeweils erklärte Knopf wird dabei
freigestellt, alles andere abgedunkelt.

Sie hält dich nirgends fest: „Überspringen" steht in **jedem** Schritt,
ein Tipp irgendwohin geht weiter, und die Reiter unten bleiben erreichbar.
Einmal gesehen — oder übersprungen — kommt sie nicht wieder.

Wer sie noch einmal sehen will, findet sie im Profil unter
„Kurzanleitung" ganz unten: „Tour auf der Karte zeigen".

## Die App erklärt sich jetzt selbst

*29. August 2026 · Version 1.107.0*

**Neu: eine Kurzanleitung.** Im Profil unter „Über PilzBuddy" steht jetzt
ein Eintrag „Kurzanleitung" — das Wichtigste in sechs Schritten, mit
genau den Symbolen, die auch auf der Karte stehen: einen Spot anlegen,
Fund und Leergang eintragen, was die Karte zeigt, unterwegs, mit Buddies
teilen, ohne Empfang.

**Wer noch keinen Spot hat, wird nicht mehr allein gelassen.** Auf einer
leeren Karte steht jetzt, wie der erste Spot entsteht: die Karte
schieben, bis das Fadenkreuz in der Mitte auf deiner Stelle liegt, dann
auf „Neuer Spot" tippen. Der Hinweis verschwindet von selbst, sobald dein
erster Spot steht. Wenn schon Spots von Buddies auf der Karte liegen,
kommt er gar nicht erst — er würde sie sonst verdecken.

**„Nichts gefunden" wird erklärt.** An einem Spot, an dem noch nichts
eingetragen ist, steht jetzt eine Zeile darunter: dass ein Leergang
festhält, dass du da warst und nichts da war.

**Ein falscher Rat ist verschwunden.** Im Profil stand „halte auf der
Karte gedrückt, um deinen ersten Pilz-Spot anzulegen". Diese Geste lässt
sich aber seit einer Weile abschalten und ist ab Werk aus — der einzige
Erklärsatz der App zeigte also ins Leere. Jetzt steht dort der Weg, den es
wirklich gibt.

## Der Benutzername nimmt keine Mailadresse mehr an

*29. August 2026 · Version 1.106.1*

Beim Registrieren liegt das Feld für die E-Mail direkt unter dem für den
Benutzernamen, und prompt landet die Adresse manchmal im falschen. Das
fällt jetzt auf, beim Registrieren wie beim späteren Umbenennen — mit
einem Hinweis am Feld statt einer Fehlermeldung erst beim Speichern.

Der Grund ist mehr als Ordnungsliebe: Dein Benutzername ist für andere
sichtbar — in Freundeslisten, an Spots und in der Suche. Eine Adresse
dort steht damit öffentlich, und ausgerechnet die Freundessuche baut
darauf, dass Adressen **nicht** öffentlich sind.

## Die Karte merkt sich, was du eingeschaltet hast

*29. August 2026 · Version 1.106.0*

**Deine Ebenen bleiben liegen.** Waldtypen, Höhenlinien, Regen und
Pilzampel sprangen bisher bei jedem App-Start wieder auf „aus" — das war
Absicht, damit niemand mit einer vergessenen Ebene dasteht. Seit die Zahl
am Ebenen-Knopf sagt, was an ist, braucht es diese Vorsicht nicht mehr.
Was du anschaltest, liegt beim nächsten Start wieder da; was du
ausschaltest, bleibt aus.

Ein Hinweis für unterwegs: Wer die Regenebene oder die Pilzampel anlässt,
lädt sie beim Start automatisch mit. Das sind ein paar hundert Kilobyte —
im Funkloch stört es nicht, am Datenvolumen kann es auffallen. Abschalten
genügt, dann bleibt es aus.

**Der Ampel-Hinweis verschwindet nicht mehr, wenn man ihn benutzt.** Das
Banner „An deinem Spot stünde die Ampel günstig" lädt zum Antippen ein —
und schaltete sich danach bis Mitternacht selbst stumm. Für den nächsten
App-Start sah das aus, als sei der Hinweis kaputt. Jetzt schaltet ihn nur
noch das **X** stumm, und das gilt weiter für den ganzen Tag.

**Das Spot-Blatt hat einen Griff bekommen.** Der graue Balken oben lässt
sich nach unten wischen — damit geht das Blatt zu, ohne dass man daneben
tippen muss. Außerdem ist es ein Stück niedriger, sodass über ihm immer
ein Streifen Karte stehen bleibt.

## Weniger Knöpfe auf der Karte — und mehr Karte

*28. August 2026 · Version 1.105.0*

Rechts auf der Karte standen zuletzt zehn Knöpfe übereinander. Auf einem
normalen Handy waren das zwei Drittel der Bildhöhe, und mit jedem neuen
Knopf wurden alle anderen ein Stück kleiner.

**Jetzt sind es fünf.** Was die Karte zeigt, liegt zusammen hinter einem
Knopf **Ebenen**: Waldtypen, Höhenlinien, Regen, Pilzampel, die
Offline-Karte und das Aktualisieren. Eine Zeile je Ebene, Schalter
gleich daneben — eine Ebene an- oder auszuschalten kostet dich genau so
viele Tipps wie vorher. Wer mehr wissen will (Kartenblöcke laden,
Regenzeitraum wählen, Quellen), tippt die Zeile an und landet im
bekannten Blatt.

Am Knopf steht eine kleine Zahl: wie viele Ebenen gerade an sind. Welche
das sind, sagt wie bisher die Legende links unten.

Pilztour und Standort-Teilen liegen zusammen unter **Unterwegs**. Läuft
eine Tour, erscheint ihr Stopp-Knopf daneben — beenden bleibt ein Tipp.

Unverändert an ihrem Platz: **Filter**, **Meine Position** und **Neuer
Spot**.

Nebenbei sagt die Offline-Karte jetzt in Worten, woran man ist —
„Karten aus dem Netz", „Heruntergeladene Regionen" oder „Aktiv, weil
kein Empfang". Das durchgestrichene Erdball-Symbol konnte den letzten
Fall nie zeigen.

## Ein Tipp aufs Banner bringt dich jetzt zum Spot auf der Karte

*28. August 2026 · Version 1.104.0*

Die Hinweise oben auf der Karte — „Ampel steht günstig", „Neuer Fund von
deinem Buddy", „Erinnerung ans Vorjahr" — nannten einen Spot und öffneten
sein Blatt. Nur blieb die Karte dabei stehen: Blatt zu, und du warst
wieder da, wo du gestartet bist. Bei einem Spot, der 30 Kilometer weit
weg liegt, half nur noch der Name.

**Jetzt springt die Karte mit.** Ein Tipp aufs Banner setzt dich über den
Spot, das Blatt öffnet sich darüber — machst du es zu, liegt der Spot vor
dir. Herangezoomt wird nur, wenn du weiter draußen warst; wer schon nah
dran ist, bleibt es.

Und wenn die Ampel an **mehreren** Spots günstig steht, bekommst du sie
jetzt zur Auswahl statt nur den besten. Bisher öffnete das Banner einen
davon und war für den Tag verschwunden — die anderen standen zwar in der
Zahl, aber es führte kein Weg zu ihnen. Solange du noch nicht alle
angesehen hast, bleibt der Hinweis stehen; wegräumen kannst du ihn wie
immer mit dem X.

## Die Pilztour zeichnet jetzt auch dann auf, wenn die App zu ist

*28. August 2026 · Version 1.103.0*

Beim ersten Feldtest kam heraus: Solange die App offen war, wurde der
Weg aufgezeichnet — hat man sie aus der Übersicht gewischt, hörte die
Aufnahme still auf, obwohl die Benachrichtigung weiterlief. Genau das
ist behoben.

Die Messung läuft jetzt im Hintergrunddienst selbst und nicht mehr in
der App. Der Dienst überlebt das Wegwischen; die App muss nicht mehr
offen bleiben und darf in der Tasche verschwinden.

Außerdem: **Das Symbol der Pilztour trägt jetzt einen Pilzkorb** statt
eines Wanderstocks.

## Die Pilztour: Der Weg zeichnet mit, und am Ende weißt du, wo du warst

*27. August 2026 · Version 1.102.0*

Auf der Karte gibt es einen neuen Knopf: **Pilztour starten**. Danach
merkt sich die App deinen Weg — ab Werk alle 15 Sekunden, einstellbar im
Profil unter „Pilztour: Messabstand" — und zeichnet ihn als Punktspur auf
die Karte. Funde trägst du unterwegs ein wie immer.

Wenn du auf **Pilztour beenden** tippst, zeigt dir die App, an welchen
deiner Spots du warst:

- **Abgesucht** — du warst nah dran und lange genug dort. Diese sind
  angehakt und werden als „nichts gefunden" eingetragen.
- **Nur vorbeigegangen** oder **nur kurz da** — verblasst, mit dem Grund
  und der Zahl daneben („34 m", „15 s"). Die sind ausgeschaltet; wenn du
  dort doch gesucht hast, hakst du sie selbst an.

Stimmt alles, ist es ein Tipp.

**Warum das nützlich ist:** Bisher hat kaum jemand eingetragen, wenn er
an einem Spot *nichts* gefunden hat — verständlich, man ist gerade
enttäuscht. Genau diese Information fehlt aber, wenn man später wissen
will, ob eine Stelle noch trägt. Und die Pilzwetter-Ampel kann sich nur
an Tagen prüfen lassen, an denen man weiß, dass wirklich gesucht wurde.

**Was dabei nicht passiert:** Der aufgezeichnete Weg verlässt dein
Telefon nicht. Er liegt lokal, ist vom Google-Backup ausgenommen und
wird gelöscht, sobald du die Tour abgeschlossen hast. Hochgeladen werden
nur die Einträge, die du bestätigst.

Solange eine Tour läuft, steht eine Benachrichtigung in der Leiste —
daran siehst du jederzeit, dass aufgezeichnet wird. Vergisst du das
Beenden, hört die Aufnahme nach zwölf Stunden von selbst auf.

## Ein Hinweis, wenn das Pilzwetter an einem deiner Spots gut aussieht

*27. August 2026 · Version 1.101.0*

Wer die **Pilzwetter-Ampel** eingeschaltet hat, konnte sie bisher nur
Spot für Spot ablesen — man musste also selbst nachsehen. Neu ist ein
zweiter Schalter direkt darunter im Profil: **Beim Start an meinen Spots
nachsehen**. Ist er an, rechnet die App beim Öffnen der Karte einmal
durch deine eigenen Spots und zeigt oben einen Hinweis, wenn die Ampel
irgendwo günstig steht. Antippen öffnet den Spot, bei dem sie am
deutlichsten dasteht.

Zwei Dinge dazu, damit klar ist, was das ist und was nicht:

- **Es ist ein Hinweis, keine Empfehlung.** Deshalb steht dort „stünde
  die Ampel günstig" und nicht „geh jetzt los". Die Ampel bewertet das
  Wetter, nicht ob dort Pilze stehen, und sie ist weiterhin
  experimentell.
- **Es geht nichts ins Netz.** Gerechnet wird auf dem Gerät, aus Daten,
  die ohnehin schon dort liegen — keine deiner Koordinaten verlässt das
  Telefon. Der Schalter ist trotzdem ab Werk aus, weil die Rechnung beim
  Start ein wenig Zeit kostet; wer sie nicht will, zahlt sie auch nicht.

Das X am Hinweis blendet ihn bis zum Ende des Tages aus — morgen sind es
neue Wetterdaten und damit eine neue Aussage.

## Offline-Karten, die sich im WLAN selbst auf den neuen Stand bringen

*26. August 2026 · Version 1.100.0*

Bisher hat PilzBuddy nur Bescheid gesagt, wenn es für eine deiner
heruntergeladenen Regionen eine neuere Karte gab — nachladen musstest du
selbst. Auf der Seite „Offline-Karten" gibt es dafür jetzt einen
Schalter: **Im WLAN von selbst aktualisieren**. Ist er an, holt die App
eine veraltete Region ohne Zutun, sobald du im WLAN bist und die App
offen hast.

Ab Werk ist der Schalter aus — eine Regionskarte ist mehrere hundert
Megabyte groß, und das lädt niemand ungefragt.

Drei Dinge, auf die dabei geachtet wird:

- **Nur was schon da ist.** Der Schalter bringt Regionen auf den neuen
  Stand, die du selbst heruntergeladen hast. Neue Regionen holt er nie.
- **Nur wo es nichts kostet.** Ein Handy-Hotspot ist zwar WLAN, kostet
  aber Datenvolumen — Android weiß das, und PilzBuddy fragt danach.
  Über Mobilfunk lädt der Schalter grundsätzlich nicht.
- **Unterwegs hält er an.** Verlässt du das WLAN mitten im Laden, stoppt
  der Download und macht beim nächsten Mal genau dort weiter, statt
  deinen Datentarif zu leeren.

Die alte Karte wird außerdem erst ersetzt, wenn die neue vollständig da
und geprüft ist. Ein abgebrochener Download kann dir also nie eine halbe
Karte im Wald hinterlassen.

## Ein Pilz in der Statusleiste statt eines weißen Flecks

*26. August 2026 · Version 1.99.5*

Kam eine Meldung von PilzBuddy an — etwa ein Fund eines Buddies an einem
gemeinsamen Spot —, zeigte Android dafür nur einen weißen Fleck. Grund war
eine fehlende Angabe in der App: Ohne sie greift Android auf das
App-Symbol zurück, und weil ein Symbol in der Statusleiste immer
einfarbig gezeichnet wird, blieb davon nichts als eine weiße Fläche übrig.

Jetzt steht dort ein kleiner Pilz mit freundlichem Gesicht, und in der
Meldungsansicht ist er grün hinterlegt. Dasselbe Symbol trägt auch die
Meldung, die beim Herunterladen von Offline-Karten und Walddaten läuft.

## „Code ist unterwegs" — und dann kam keiner

*22. August 2026 · Version 1.99.2 · 1.99.3 und 1.99.4: nur Innenausbau, nichts Sichtbares*

Beim Zurücksetzen des Passworts gibt es unter der Code-Eingabe den Knopf
„Code nicht angekommen? Erneut senden". Stand das E-Mail-Feld darüber
leer, meldete die App trotzdem „ein neuer Code ist unterwegs" — verschickt
wurde aber nichts. Wer darauf gewartet hat, hat vergeblich gewartet.

Jetzt sagt die App in dem Fall, was fehlt: „Bitte eine gültige
E-Mail-Adresse angeben."

## Höhenlinien: saubere Kurven, die sich nicht mehr kreuzen

*21. August 2026 · Version 1.99.1*

Beim starken Hineinzoomen sahen die Höhenlinien nicht aus wie
Höhenlinien: lange Geraden statt Kurven, Ringe mit einem Knick, und
manche Linien liefen quer durch ihre Nachbarn hindurch. Beim Verschieben
der Karte sprangen sie außerdem gelegentlich auf einen neuen Verlauf.

Alles drei ist behoben:

- **Die Linien folgen jetzt dem Gelände statt einer groben Näherung.**
  Sie sind glatt, und zwei Linien kreuzen sich nicht mehr — das kann
  eine Höhenlinie schlicht nicht.
- **Geschlossene Ringe sind rundum rund.** Vorher blieb an einer
  zufälligen Stelle eine Ecke stehen.
- **Beim Verschieben bleiben die Linien liegen.** Sie wandern mit der
  Karte, statt sich neu zu berechnen.

Nebenbei tauchen beim Hineinzoomen wieder kleine Kuppen und Mulden auf,
die vorher weggefiltert wurden.

## Höhenlinien: ruhiger, und mit Zahlen dran

*21. August 2026 · Version 1.99.0*

Die Höhenlinien aus der letzten Version waren im Bergland zu dicht — im
Berchtesgadener Land sah die Karte aus, als hätte jemand sie schraffiert.
Und ohne Zahlen sagt eine Höhenlinie nur „hier ist es steiler als dort",
nicht ob es hinauf oder hinunter geht.

Beides ist behoben:

- **Der Abstand richtet sich jetzt nach dem Gelände**, nicht nach der
  Zoomstufe. Im flachen Land liegen die Linien enger, im Steilhang
  weiter auseinander — so, dass man sie in beiden Fällen einzeln sieht.
  Wo selbst der größte Abstand noch zu dicht wäre, zeigt die Karte
  keine Linien und sagt „erst näher dran".
- **Etwa alle 100 Höhenmeter trägt eine kräftigere Linie ihre Höhe in
  Metern.** Die dazwischen zählst du ab, wie auf einer Wanderkarte.
- **Die Linien sind zarter geworden.** Sie liegen über der Karte, sie
  sollen sie nicht ersetzen.

## Die Offline-Karte hat ihr Grün zurück

*21. August 2026 · Version 1.98.1*

Auf der heruntergeladenen Karte fehlten Wald, Wiese und Park. Die
Flächen waren beige wie offenes Feld, und übrig blieben Straßen und
Wege. Die Daten waren die ganze Zeit da — unser Kartenstil hat sie nur
nicht gezeichnet. Jetzt ist der Wald wieder grün; beim starken
Hineinzoomen stehen auch die Namen einzelner Punkte im Gelände wieder
da (Gipfel, Hütten, Haltestellen).

Und die Wege aus der letzten Version sind deutlich zurückgenommen. Sie
waren kräftiger geraten als die Straßen, über die sie laufen — im
Feldgebiet lag ein braunes Netz über allem. Jetzt sind sie zu sehen,
ohne die Karte zu übertönen: Forstwege weiterhin breiter als schmale
Pfade, und Pfade erst beim Hineinzoomen, damit die Übersicht ruhig
bleibt.

Beides betrifft nur die heruntergeladene Karte. Die Online-Karte kommt
fertig gezeichnet von OpenStreetMap.

## Höhenlinien: siehst du, wo es bergauf geht

*20. August 2026 · Version 1.98.0*

Neu auf der Karte: ein Bergsymbol rechts. Ein Tipp darauf, „Höhenlinien
einblenden" — und die Karte zeigt das Gelände. Hänge, Mulden, Kuppen,
Bachtäler. Für die Pilzsuche ist das oft die halbe Miete: Der
Nordhang ist kühler und feuchter als die Kuppe daneben.

Was du wissen solltest:

- **Die Linien werden auf deinem Gerät gerechnet.** Die Höhendaten
  stecken schon in der App — es wird nichts nachgeladen, nichts
  verschickt, und im Funkloch funktioniert es genauso.
- **Der Abstand wächst, je weiter du herauszoomst**: von 20 Metern nah
  dran bis 200 Metern in der Übersicht. In der Legende steht, was
  gerade gilt, und wie hoch es unter dem Fadenkreuz ist. Jede fünfte
  Linie ist kräftiger, damit du mitzählen kannst.
- **Ganz weit draußen zeigt die Karte keine Linien** — dort wären sie
  nur ein Gewirr. Die Legende sagt dann „erst näher dran".
- **Im Flachland bleibt es fast leer.** Das ist kein Fehler: Wo es
  keine Höhenunterschiede gibt, gibt es keine Höhenlinien.

Die Daten sind gröber als eine gedruckte Wanderkarte (eine Wabe ist
etwa 270 Meter breit). Sie zeigen die Form des Geländes, nicht die
einzelne Böschung.

## Wanderwege sind endlich zu sehen

*20. August 2026 · Version 1.97.0*

Auf der heruntergeladenen Offline-Karte waren bisher fast nur Straßen zu
erkennen. Die Wege waren die ganze Zeit da — sie wurden nur so blass
gezeichnet wie eine Hofzufahrt und erst beim starken Hineinzoomen
überhaupt breiter als ein Haar.

Jetzt haben sie eine eigene Farbe:

- **Forstwege** — die breiten, befahrbaren — kräftig in Ockerbraun. Das
  sind die, auf denen man in den Wald kommt.
- **Pfade, Steige, Fußwege und Reitwege** deutlich feiner im selben Ton,
  damit man die beiden auseinanderhält.
- Beide erscheinen früher: Du musst nicht mehr so weit hineinzoomen, bis
  sich etwas zeigt.

Bürgersteige und Fußgängerüberwege an Stadtstraßen fallen dafür weg. Im
Wald helfen sie nicht, und in der Stadt waren sie nur Gewimmel.

Das betrifft die Offline-Karte und die Karte ohne Empfang. Mit Empfang
zeichnet OpenStreetMap die Karte wie bisher selbst.

## Die App fragt sparsamer nach

*17. August 2026 · Versionen 1.95.0 und 1.96.0*

Die Karte hat bisher alle 15 Sekunden nachgesehen, ob ein Freund
gerade seinen Live-Standort teilt — auch wenn du gar keine Freunde
eingetragen hast, auch nachts in der Hosentasche. Das kostete Akku und
Datenvolumen für eine Antwort, die fast immer leer war.

Jetzt gilt:

- Ohne angenommene Freundschaft fragt die App gar nicht erst.
- Mit Freunden, aber ohne aktive Freigabe, schaut sie nur noch alle
  90 Sekunden nach — eine neue Freigabe erscheint also schlimmstenfalls
  anderthalb Minuten später.
- Sobald jemand teilt, gilt wieder der schnelle 15-Sekunden-Takt —
  beim Verfolgen ändert sich nichts.
- Im Hintergrund ruht die Abfrage ganz und springt beim Zurückkehren
  sofort wieder an.

Seit 1.96.0 gilt dasselbe fürs Zurückkehren in die App: Ein kurzer
Blick woandershin (unter 30 Sekunden) lädt gar nichts mehr neu.
Nach echter Abwesenheit werden Spots und Freundschaften wie gewohnt
aufgefrischt; die Suche nach App-Updates und neuen Offline-Karten
läuft höchstens einmal pro Stunde — beides ändert sich nie im
Minutentakt. Der Aktualisieren-Knopf auf der Karte lädt weiterhin
immer alles sofort.

## Das Pilzwetter kennt jetzt die Höhe deines Spots

*17. August 2026 · Version 1.93.0, Nachbesserungen in 1.93.1 und 1.94.0*

Die nächste Wetterstation kann ein paar hundert Höhenmeter über oder
unter deinem Spot liegen — im Gebirge wurde das Pilzwetter dadurch mal
zu warm, mal zu kalt gerechnet. Zeitweise stand die Zugspitzen-Station
für die Täler um sie herum ein.

Jetzt trägt die App eine Höhenkarte in sich (mittlere Geländehöhe in
etwa 250-m-Waben, ganz Deutschland, Österreich und Schweiz) und
rechnet die Stationstemperatur auf die Höhe deines Spots um: 0,65 Grad
je 100 Meter, die bewährte Faustregel der Meteorologie.

- Im Flachland ändert sich nichts — Station und Spot liegen dort auf
  gleicher Höhe, die Umrechnung ist eine Nullnummer.
- Wo sie zählt, steht sie dabei: „zu kühl (7,3 °C auf Spothöhe
  1200 m)".
- Das Temperatur-Diagramm zeigt weiterhin die echten Messwerte der
  Station, mit deren Name und Höhe — Messwerte bleiben Messwerte.
- 1.93.1 zieht die kleine Werte-Tafel unten links auf der Karte nach:
  Sie rechnete zunächst noch ohne die Höhe und konnte dadurch am
  Fadenkreuz etwas anderes sagen, als die Kachelfarbe zeigte — danke
  für die Meldung aus Berchtesgaden.
- 1.94.0 bringt die Höhe auch in die Kartenfärbung selbst: Bisher
  bekamen alle Waben im Umkreis von etwa einem Kilometer dieselbe
  Wetterstufe — im Gebirge liegen dazwischen aber schnell 500
  Höhenmeter. Jetzt rechnet **jede einzelne Wabe** mit ihrer eigenen
  Höhe, egal ob grobe oder feine Waben eingestellt sind. Karte,
  Werte-Tafel und Spot-Ansage können sich damit nicht mehr
  widersprechen.

Wie alles an der Karte funktioniert das ohne Empfang.

## Woher die Pilzwetter-Formel stammt

*15. August 2026 · Version 1.92.0*

Die Rechenregel hinter dem Pilzwetter — um 13 °C herum ist es am
besten, und es zählt der Regen der letzten dreieinhalb Wochen — haben
wir nicht erfunden. Sie stammt aus einer Studie mit zehn Jahren fast
täglicher Steinpilz-Beobachtung in einem Buchenwald bei Bielefeld.
Das sagt die App jetzt auch selbst:

- Unter der Pilzwetter-Zeile im Spot-Blatt steht die Quelle in einem
  Satz.
- Die vollständige Angabe mit Fundstelle und den ehrlichen
  Einschränkungen steht im Profil unter „Über PilzBuddy" →
  „Open-Source-Lizenzen", wo die App auch sonst nennt, woher ihre
  Karten und Daten kommen.

## Benachrichtigungen sagen jetzt, worum es geht

*13. August 2026 · Version 1.91.0, technische Nacharbeit in 1.91.1*

Bisher stand in einer Meldung „PilzBuddy" und darunter „Neue Funde bei
deinen Pilzbuddies" — drei Funde sahen aus wie einer, und der Titel
wiederholte nur den App-Namen, den Android ohnehin anzeigt.

Jetzt steht die Sache oben und die Menge dabei:

- **3 neue Funde bei deinen Buddys** · An 2 Spots
- **Deine Buddys waren unterwegs** · 2 neue Funde und 1 neuer Spot

Was weiterhin **nicht** drinsteht: wer es war und welche Art. Eine
Meldung läuft über die Server von Google, und dorthin gehen weder
Namen noch Fundinhalte — die stehen erst in der App.

## Die Pilzampel ist geprüft — teilweise

*13. August 2026 · Version 1.89.0*

Die Pilzwetter-Ampel lief bisher als „unvalidierte Vorschau". Die Prüfung
ist jetzt durch: Für rund 12.000 echte Fundmeldungen aus zwanzig Jahren
wurde nachgerechnet, wie die Ampel am Fundtag stand — und wie an einem
Vergleichstag am **selben Ort** wenige Wochen daneben. Sie steht an
Fundtagen deutlich höher. Beim Steinpilz in 73 von 100 Vergleichen.

Was die Prüfung **nicht** zeigen konnte: dass die Ampel für verschiedene
Arten verschieden gut passt. Beim Hallimasch, der ganz anders wächst,
passt dieselbe Rechnung genauso gut. Solange das so ist, bleibt es bei
**einer** Ampel für alle Arten statt einer je Art.

Der Schalter im Profil sagt das jetzt so — und heißt weiter
„experimentell", weil genau diese Frage offen ist.

## Neuer Paketname — einmal neu installieren

*13. August 2026 · Version 1.88.0 · Anleitung korrigiert in 1.90.0, Nacharbeiten in 1.90.1*

PilzBuddy heißt für Android ab jetzt `de.mcbuchi.pilzbuddy` statt wie
bisher mit dem Namen des Entwicklers darin. Das musste vor der ersten
Einreichung im Play Store passieren — danach lässt sich dieser Name nie
wieder ändern.

**Für dich heißt das einmalig zwei Handgriffe.** Android hält die neue
Fassung für eine andere App — sie ersetzt die alte also nicht, sondern
stellt sich daneben:

- Update wie immer über „Neue Version verfügbar" einspielen.
- Danach stehen kurz **zwei** PilzBuddy-Symbole auf dem Gerät. Die
  **alte** App löschen (Symbol gedrückt halten → Deinstallieren).
- In der neuen anmelden — fertig. Alle weiteren Updates laufen wieder
  wie gewohnt.

**Dein Konto und deine Spots bleiben** — die liegen auf dem Server.
Verloren gehen die Sachen, die nur auf dem Gerät liegen:
heruntergeladene Offline-Karten, gespeicherte Einstellungen und
**Funde, die noch im Ausgangskorb warten**. Wenn dort noch etwas steht
(das Banner auf der Karte sagt es), gehe vor dem Wechsel einmal mit
Empfang ins Netz, damit alles gesendet ist. Benachrichtigungen musst du
in der neuen App einmal wieder einschalten, falls du sie an hattest.

## Vorbereitung für den Play Store

*12. August 2026 · Version 1.87.1*

An der App ändert sich für dich nichts. Damit PilzBuddy in den Play Store
darf, entstehen ab jetzt zwei Fassungen aus demselben Stand: die hier von
GitHub — die sich wie gewohnt selbst aktualisiert — und eine für den Store,
in der genau diese Selbst-Aktualisierung fehlt. Google verbietet sie dort,
weil im Store der Play Store das Aktualisieren übernimmt.

Wenn PilzBuddy später im Store steht: Ein Wechsel dorthin verlangt einmal
Deinstallieren und Neuinstallieren, weil die Store-Fassung anders signiert
ist. Dein Konto und deine Spots liegen auf dem Server und bleiben erhalten;
neu laden musst du nur heruntergeladene Offline-Karten.

## Benachrichtigungen kommen jetzt richtig an

*12. August 2026 · Version 1.87.0*

Meldungen von Buddies erschienen bisher nur als kleines Symbol in der
Statusleiste — ohne den Banner, den man von anderen Apps kennt. Grund
war ein fehlender Benachrichtigungs-Kanal: Ohne ihn legt Android selbst
einen sehr leisen an. Jetzt gibt es einen eigenen namens **Meldungen**,
den du in den Systemeinstellungen auch nach deinem Geschmack
herunterdrehen kannst.

Und wenn eine Meldung eintrifft, während PilzBuddy offen ist, zeigt die
App sie unten als Einblendung — auch dann, wenn dort gerade eine andere
Rückmeldung steht.

## Welcher Baum steht da eigentlich?

*12. August 2026 · Version 1.86.0*

Die Waldzeile im Spot-Blatt sagte bisher „Laubwald", „Mischwald" oder
„Nadelwald". Für die Pilzsuche ist aber genau die nächste Frage die
wichtige: **welcher** Baum? Fichte oder Kiefer entscheidet zwischen
Marone und Butterpilz, Buche oder Birke zwischen Steinpilz und
Birkenpilz.

Ab jetzt steht es da:

- **Bäume: Fichte und Buche** — die beiden häufigsten in der Wabe,
  benannt in der Reihenfolge, die zum Nadelanteil darüber passt
- **Einzelne Bäume: Eiche** — am Waldrand, wo es keinen geschlossenen
  Wald gibt, aber sehr wohl Bäume

Die Angabe stammt aus einer Baumartenkarte des DLR mit Stand 2022 und
gilt **nur für Deutschland**; in Österreich und der Schweiz bleibt es
bei der bisherigen Zeile. Sie liegt wie die Waldkarte fest in der App —
im Wald ohne Empfang steht sie also genauso da wie zu Hause.


## Vom Sporenstreuer zum Waldpaten

*11. August 2026 · Version 1.85.0*

Teilen bekommt einen Rang. Wer seinen ersten Spot mit den Buddies teilt,
ist **Sporenstreuer** — und von da an geht es weiter:

- 10 Spots: **Hyphenspinner**
- 25: **Myzelweber**
- 50: **Revierkenner**
- 100: **Waldpate**

Das Bild ist mit Absicht gewählt: Ein Pilznetz besteht aus Fäden, und
jeder geteilte Spot knüpft einen davon.

Deinen Rang siehst du im Profil unter „Teilen mit Freunden", den deiner
Buddies in der Freundesliste. In der Freundessuche steht er **nicht** —
Fremde müssen nicht wissen, wie aktiv jemand ist.

Zwei Dinge, die uns wichtig waren:

- **Wer nichts teilt, wird nicht abgestempelt.** Bei null steht dort eine
  Einladung, kein Titel — und schon gar kein Spottname.
- **Gezählt wird, was wirklich ankommt.** Wer das Teilen abgeschaltet hat,
  hat keinen Rang, auch mit hundert Spots. Und einzeln ausgenommene Spots
  zählen nicht mit — dein Geheimspot bleibt geheim, ohne dass es dich
  etwas kostet.

Wenn du deutlich mehr siehst, als du selbst teilst, sagt das Profil es
dir einmal ruhig dazu. Weggenommen wird dir nichts.

## Im Funkloch stand der falsche Grund

*11. August 2026 · Version 1.84.3*

Wer ohne Verbindung die Benachrichtigungen einschalten wollte, bekam zu
lesen, sie seien „nicht erlaubt" — und suchte dann in den
Android-Einstellungen nach einem Schalter, der längst richtig stand. In
Wahrheit fehlte nur das Netz.

Jetzt steht da, was wirklich los ist. Und wer die Erlaubnis tatsächlich
verweigert hat, bekommt weiterhin den Weg in die Einstellungen genannt.

Benachrichtigungen brauchen Verbindung — das ist keine Einschränkung,
sondern liegt in der Natur der Sache. Alles andere in der App
funktioniert im Wald weiter ohne.

## Benachrichtigungen kamen nicht an, wenn die App offen war

*11. August 2026 · Version 1.84.2*

Wer auf „Testnachricht senden" tippte, bekam nichts zu sehen — und das
war kein Zufall, sondern der ungünstigste denkbare Fall: Android zeigt
eine Benachrichtigung nur an, solange die App **nicht** im Vordergrund
ist. Beim Tippen auf den Knopf ist sie das zwangsläufig. Die Meldung kam
an und verschwand spurlos.

Schlimmer war die zweite Hälfte davon: Auch eine **echte** Meldung wäre
verpufft, wenn du die App zufällig offen hattest — und sie wäre nicht
nachgekommen, weil sie serverseitig da schon als zugestellt galt.

Jetzt zeigt die App eintreffende Meldungen selbst an, solange du sie
offen hast.

## Und jetzt melden sie sich auch

*11. August 2026 · Version 1.84.1*

Die Benachrichtigungen aus der vorigen Version haben jetzt einen Anlass.
Wenn du sie eingeschaltet hast, erfährst du,

- wenn ein Pilzbuddy an einem Spot, den ihr beide seht, einen Fund
  einträgt,
- und wenn er einen neuen Spot öffnet.

Zwei Dinge, die dabei bewusst so gebaut sind:

- **Du erfährst nur, was du ohnehin sehen darfst.** Ein Spot, den jemand
  von der Freigabe ausgenommen hat, meldet sich nicht — und wer das
  Teilen ganz abschaltet, löst gar keine Meldungen mehr aus.
- **Zehn Funde auf einem Waldgang sind eine Meldung, nicht zehn.** Die
  App wartet ab, bis Ruhe eingekehrt ist, und fasst zusammen.

Ein **Leergang** („nichts gefunden") löst nichts aus. Und in der Meldung
selbst steht weiterhin nie, um welchen Spot oder welche Stelle es geht —
das siehst du erst beim Öffnen.

## Benachrichtigungen — wenn du sie willst

*11. August 2026 · Version 1.84.0*

Im Profil steht ein neuer Schalter: **Benachrichtigungen**. Er ist aus, und
er bleibt aus, bis du ihn umlegst. Diese Version baut nur die Leitung —
gemeldet wird noch nichts. Was du jetzt schon tun kannst: einschalten und
**„Testnachricht senden"** antippen. Kommt sie an, funktioniert die ganze
Kette bis zu deinem Gerät.

Drei Dinge, die dir dabei wichtig sein dürften:

- **Der Schalter gilt nur für dieses Gerät.** Auf dem Tablet musst du ihn
  eigens umlegen, und Ausschalten wirkt sofort.
- **In einer Meldung steht nie, wo etwas ist.** Kein Fundort, kein
  Spot-Name — nur ein allgemeiner Hinweis. Die Einzelheiten holt die App
  erst, wenn du sie öffnest. Der Grund: Eine Benachrichtigung läuft über
  die Server von Google, und dorthin gehört eine Fundstelle nicht.
- **Nach der Erlaubnis wird erst gefragt, wenn du den Schalter umlegst** —
  nicht beim Start.

Was als Nächstes kommt: eine Meldung, wenn ein Pilzbuddy an einem
gemeinsamen Spot etwas einträgt oder einen neuen Spot öffnet.

## Der Regen-Knopf verrät jetzt auch die Pilzampel

*11. August 2026 · Version 1.83.2*

Hinter dem Tropfen-Knopf auf der Karte sitzen zwei Ebenen: der Regen und
die Pilzampel. Angezeigt hat er bisher nur den Regen — wer allein die
Ampel eingeschaltet hatte, sah einen Knopf, der aussah, als wäre nichts
an, während der halbe Wald leuchtete.

Jetzt zeigt er beides, und zwar unterscheidbar:

- **Nur Regen:** blau mit vollem Tropfen, wie gehabt.
- **Nur Pilzampel:** violett mit einem Ampelsymbol.
- **Beides:** blau mit Tropfen und einem violetten Punkt dazu.

## Die Pilzampel malt keine Kacheln mehr

*11. August 2026 · Version 1.83.1*

Bei Garmisch-Partenkirchen und Innsbruck leuchtete ein großes, auffällig
rechteckiges Stück Wald als „verhalten" — während die Ampel an derselben
Stelle „ungünstig" sagte. Beides konnte nicht stimmen.

Der Grund: Die Farbe auf der Karte holte sich die Temperatur von der
nächsten Wetterstation eines ganzen 16-Kilometer-Quadrats, gemessen von
dessen Mittelpunkt. Der lag am gemeldeten Punkt acht Kilometer entfernt
und griff zu einer Station, die 264 Meter höher steht — also kühler misst
und die Bedingungen deutlich besser aussehen lässt. Der Text daneben hatte
die richtige Station.

Jetzt sucht auch die Karte die Station für jede Stelle einzeln. Farbe und
Text können sich nicht mehr widersprechen, und die geraden Kanten
verschwinden. Das betraf nicht nur die Alpen: Bundesweit war knapp ein
Viertel der leuchtenden Fläche falsch eingefärbt — dort fiel es nur nicht
auf, weil die Flecken klein und verstreut sind.

Ein Hinweis ist dazugekommen, den die Karte nicht wegrechnen kann: Im
Gebirge bleibt die Temperatur unsicher, weil die nächste Wetterstation
Hunderte Höhenmeter tiefer oder höher stehen kann.

## Vorabversionen, wenn du sie willst

*10. August 2026 · Versionen 1.81.0 bis 1.83.0 (1.82.0 und 1.83.0: nur Innenausbau, nichts Sichtbares)*

Im Profil unter „Über PilzBuddy" steht ein neuer Schalter:
**„Vorabversionen erhalten"**. Er ist aus, und für die allermeisten soll
er das auch bleiben.

Hintergrund: An PilzBuddy wird laufend gebaut, und jede fertige Änderung
wird sofort als Vorabversion abgelegt — für dich unsichtbar, denn die App
bietet dir nur die *freigegebenen* Versionen an. Wer beim Ausprobieren
helfen will, legt den Schalter um und bekommt dann jeden Zwischenstand
angeboten.

- Diese Zwischenstände sind **ungetestet** und kommen oft — teils mehrmals
  am Tag.
- Der Schalter gilt nur für dieses Gerät.
- Zurückschalten ist jederzeit möglich. Du behältst die Version, die schon
  installiert ist, und wirst danach wieder erst bei der nächsten Freigabe
  gefragt.

## Die leuchtenden Waben verraten jetzt auch den Wald

*10. August 2026 · Version 1.80.0*

Bisher sahen alle Waben, in denen das Wetter stimmte, gleich aus — und
damit war ausgerechnet dort nicht mehr zu erkennen, ob man in Laub-,
Misch- oder Nadelwald schaut. Jetzt hat **jede Waldart ihre eigene
Leuchtfarbe**: Laubwald violett, Mischwald dazwischen, Nadelwald ein
dunkles Königsblau. Du siehst also mit einem Blick beides — wo das
Wetter passt *und* in welchem Wald.

- „Günstig" ist ruhiger geworden. Die alte Farbe war so grell, dass sie
  Wege und Ortsnamen darunter zugedeckt hat.
- „Verhalten" tritt deutlicher zurück, damit der Blick dorthin geht, wo
  es sich am ehesten lohnt.
- Die Legende zeigt jetzt das ganze Raster: drei Waldarten, zwei Stufen.
- Die Farbauswahl im Regen-Blatt ist entfallen. Türkis war auf der Karte
  kaum von Wasser zu unterscheiden, und die neuen Farben sind auf die
  drei Waldarten abgestimmt — eine zweite Familie hätte davon nichts
  übrig gelassen.

## Funde ohne Empfang gehen nicht mehr verloren

*10. August 2026 · Version 1.79.0*

Bisher brauchte das Eintragen eines Fundes eine Verbindung. Ausgerechnet
im Wald gibt es die selten — wer dort einen Spot anlegte, bekam „Keine
Verbindung" und musste sich den Fund merken, bis er zu Hause war.

Ab jetzt landet ein Fund ohne Empfang in einem **Ausgangskorb** auf
deinem Gerät und geht von allein raus, sobald du wieder Netz hast.

- Der wartende Spot erscheint sofort auf der Karte — blasser und mit
  einer kleinen Uhr. Du siehst also, wo du schon warst, und legst
  denselben Spot nicht zweimal an.
- Oben zeigt ein Hinweis, wie viele Einträge noch warten. Antippen
  versucht es sofort.
- Gesendet wird außerdem beim Start der App und sobald die Verbindung
  zurückkommt — meist musst du gar nichts tun.
- Wartende Einträge zählen ganz normal mit: in der Statistik, in der
  Pilzampel und beim Export. Sie sind ja passiert. Nur ändern lassen sie
  sich erst, wenn sie übertragen sind.
- Ein wartender Eintrag lässt sich verwerfen, falls du ihn doch nicht
  willst. Und wenn du dich abmeldest, während noch etwas wartet, fragt
  die App vorher nach.

Was der Server nicht annimmt, verschwindet nicht still: Solche Einträge
werden gesondert gemeldet, mit dem Grund.

## Die feine Waldkarte am Stück laden

*10. August 2026 · Version 1.78.0*

Die Waldtypen-Ebene kann seit kurzem feiner hinsehen: Waben von etwa
100 Metern statt 250. Diese feinen Daten hat die App bisher unterwegs
nachgeladen — also ausgerechnet dort, wo im Wald selten Empfang ist.

Unter „Offline-Karten" steht jetzt ein Eintrag **Feine Waldkarte**, der
alles auf einmal holt: rund 26 MB für Deutschland, Österreich und die
Schweiz. Einmal zu Hause im WLAN antippen, und die feine Stufe ist
draußen da.

- Der Eintrag zeigt, wie viel schon auf dem Gerät liegt.
- Anhalten geht jederzeit; was geladen ist, bleibt, und der Rest lässt
  sich später nachholen.
- Wird der Platz knapp, löschst du die feinen Daten wieder — die Karte
  zeigt dann weiter die eingebaute Fassung mit den größeren Waben.

## Updates kommen jetzt gebündelt

*10. August 2026 · Version 1.77.0*

Bisher hat jede einzelne Änderung sofort ein Update ausgelöst — an einem
fleißigen Tag waren das acht Hinweise für dieselbe App. Ab jetzt sammeln
sich die Änderungen, und ein Update erscheint erst, wenn ein Stand
bewusst freigegeben wird. Der Hinweis in der App kommt dann einmal, mit
allem, was seit dem letzten Mal dazugekommen ist.

Für dich ändert sich sonst nichts: Was du installiert hast, läuft weiter,
und die Web-Version zeigt denselben freigegebenen Stand wie die App.

## Die Pilzampel leuchtet jetzt IM Wald

*10. August 2026 · Version 1.76.0*

Die eigentliche Frage beim Losfahren ist ja nicht „wo ist Wald" und auch
nicht „wo ist gutes Wetter", sondern **wo ist beides**. Genau das zeigt
die Karte jetzt: Der Schalter „Pilzwetter-Ampel" färbt keine eigene
Fläche mehr über Felder und Städte, sondern lässt die **Waldwaben
leuchten**, wo das Wetter gerade mitspielt — hell bei „verhalten",
kräftig bei „günstig", in der Farbe deiner Wahl. Der übrige Wald bleibt
sichtbar, nur zurückgenommen; sonst hätten die leuchtenden Waben keinen
Zusammenhang, in dem man sie liest.

Das ist zugleich eine Vereinfachung: Es gibt nur noch **einen** Schalter
statt zweier Flächen, die sich gegenseitig ausschließen mussten. Und weil
alles in einem Bild entsteht, liegt nichts mehr übereinander.

- Es sind weiterhin **keine Spots von irgendwem** im Spiel — nur dein
  Gerät, das Waldgitter und die Wetterdaten.
- Waldwetter gibt es nur für Deutschland. Außerhalb bleibt der Wald
  normal eingefärbt; „leuchtet nicht" heißt dort also weder schlecht
  noch unbekannt.
- Die Klassen-Auswahl gilt weiter: Wer nur Nadelwald einblendet, sieht
  auch nur Nadelwald leuchten.
- Der Ampel-Schalter schaltet die Waldebene mit ein, und wer die
  Waldebene abschaltet, nimmt die Ampel mit — sie ist ja die Waldkarte
  in anderen Farben.

## Die Pilzampel bekommt eigene Farben

*9. August 2026 · Version 1.75.0*

Die Ampel-Fläche malte bisher in denselben Grün- und Ockertönen wie die
Waldkarte — und die will man ja gerade zusammen sehen. Über Laubwald war
„verhalten" praktisch nicht mehr zu erkennen.

Jetzt bricht die Ampel aus den Erdtönen aus, und **du wählst die Farbe**:
Im Regen-Blatt stehen unter dem Ampel-Schalter drei Familien zur Wahl —
**Violett**, **Magenta** und **Türkis**. Die Wahl gilt für die Fläche auf
der Karte, den Punkt im Spot-Blatt und die Legende, und sie bleibt
gespeichert. Violett ist voreingestellt: Es ist der einzige Ton, der weder
in der Karte (Wasser, Wald, Wege) noch in der Waldebene vorkommt.

## Die Waldkarte bleibt beim Rauszoomen stehen

*9. August 2026 · Version 1.74.0*

Die Waben der Waldkarte verschwanden beim Rauszoomen: erst Lücken, dann
Streifen, und in der Deutschland-Übersicht war gar nichts mehr zu sehen.
Grund war der Zeichner — Waben, die kleiner als ein Bildpunkt wurden,
fielen beim Runden einfach heraus.

Jetzt zählt jede Wabe mit der Fläche, die sie bedeckt. Damit stimmt die
Karte auf jeder Zoomstufe: In der Übersicht sind Harz, Thüringer Wald,
Bayerischer Wald und die Alpen wieder als das zu erkennen, was sie sind,
und beim Hineinzoomen wachsen daraus dieselben scharfen Waben wie bisher.
Nebenbei laufen Wabenränder jetzt weich aus statt zu treppen, und
zwischen gleichfarbigen Nachbarn ist keine helle Naht mehr.

Und die Karte färbt schneller ein — das Zusammenpacken der Bilder war
dreimal so aufwendig eingestellt, wie es sein musste. Das merkt man auch
bei den Regen- und Ampel-Flächen.

**Weniger Datenverbrauch bei den feinen Waben:** Die nachladbaren
100-m-Waben kommen jetzt erst nah dran — etwa ab Maßstab 1 km, wo man
sie auch wirklich sieht. Wer mit eingeschalteter Feinstufe auf
Deutschland herauszoomte, lud bisher nach und nach das ganze Gebiet
nach (26 MB) für ein Bild, das von der eingebauten Karte nicht zu
unterscheiden war.

## Zum Ausprobieren: die Pilzwetter-Ampel

*9. August 2026 · Versionen 1.72.0 und 1.73.0*

**Neu in 1.73.0 — die Ampel auf der Karte:** Im Regen-Blatt gibt es
(bei eingeschalteter Vorschau) den Schalter „Pilzwetter-Ampel". Er
färbt auf der Karte ein, wo die Wetter-Bedingungen für Steinpilz & Co.
gerade **günstig** (grün) oder **verhalten** (ocker) sind — ungünstige
Gegenden bleiben ungefärbt. Zusammen mit der Waldkarte beantwortet das
die Frage „wo könnte ich noch sammeln?": Wald einblenden, Ampel
einblenden, hin. Es werden dabei **keine Spots von irgendwem**
benutzt oder gezeigt — die Fläche ist reines Wetter, gerechnet auf
deinem Gerät, nur für Deutschland. Eine Regenfläche und die Ampel
schließen sich gegenseitig aus (beides übereinander wäre unlesbar).

Im Profil gibt es einen neuen Schalter: **„Pilzwetter-Ampel
(experimentell)"**. Eingeschaltet zeigt das Spot-Blatt (und „Was ist
hier?") eine Einschätzung in Worten — **ungünstig, verhalten oder
günstig** —, gerechnet aus dem Regen der letzten 26 Tage und der
Temperatur der letzten 20 Tage, direkt auf deinem Gerät.

- **Ehrlich bleibt sie:** Die Ampel bewertet die Wetter-**Bedingungen**,
  nicht ob Pilze dastehen. Sie gilt nur für die sechs Arten, an denen
  das Modell gerade geprüft wird (Steinpilz & Co.) — für alle anderen
  sagt sie bewusst nichts. Und sie ist **unvalidiert**: Die Prüfung an
  echten Funden läuft noch; fällt sie durch, verschwindet die Vorschau
  wieder.
- Daneben stehen die Fakten wie bisher: Regen, Temperatur und die
  Saison der Art — die Saison fließt nicht in die Stufe ein.
- Das Wetterdiagramm zeigt weiterhin 14 Tage; die zusätzlichen Tage
  für die Ampel kommen mit den nächsten Daten-Updates automatisch
  (die erste Wetter-Ladung wächst dadurch auf knapp 2 MB).

## Die Waldkarte kann feiner — wenn du willst

*9. August 2026 · Version 1.71.0*

Im Waldtypen-Blatt gibt es einen neuen Schalter: **„Feine Waben
(≈ 100 m) nachladen"**. Eingeschaltet holt die App für das sichtbare
Gebiet eine deutlich feinere Waldkarte aus dem Netz — je Gebiet rund
1 MB, einmal geladen bleibt es auf dem Gerät. Auch „Wald hier" im
Spot-Blatt, der Laubfaktor am Fadenkreuz und „Was ist hier?" rechnen
dann auf den feinen Waben.

- Ohne den Schalter ändert sich nichts: Die eingebaute 250-m-Karte
  bleibt und funktioniert wie bisher ganz ohne Empfang. Fehlt unterwegs
  das Netz, springt sie auch bei eingeschaltetem Schalter still ein.
- Die feine Karte ist nicht nur schärfer, sondern ehrlicher: Bei 250 m
  macht schon eine Baumreihe die ganze Wabe zu „Wald" — auf 100 m
  schrumpft der Waldanteil von 48 auf ehrliche 44 Prozent. Werte können
  sich also leicht ändern; das ist die feinere Messung, keine neuen
  Daten.
- Die feinen Karten werden zentral gepflegt und beim vierteljährlichen
  Daten-Update automatisch erneuert — dafür ist kein App-Update nötig.

## Die Waldkarte hat jetzt Waben

*9. August 2026 · Version 1.70.0*

Die Waldtypen liegen jetzt als **Sechseck-Waben** auf der Karte statt als
Quadrate — organischer anzusehen, und zwar ehrlich: Die Waben sind nicht
bloß aufgemalt, sondern werden direkt aus den 10-Meter-Satellitendaten
berechnet. Jede Wabe deckt dieselbe Fläche ab wie vorher ein Quadrat
(≈ 250 m), die App wird dadurch nicht größer und nicht langsamer —
nachgemessen, bevor es gebaut wurde.

Auch „Wald hier" im Spot-Blatt und der Laubfaktor rechnen jetzt auf den
Waben. An Bestandsgrenzen kann sich dadurch ein Wert leicht ändern —
das ist die neue Zellform, keine neuen Daten (Stand weiterhin 2024).

## Die Waldkarte wird beim Heranzoomen scharf

*9. August 2026 · Version 1.69.0*

Die Waldtypen-Fläche wird jetzt nur noch für den sichtbaren
Kartenausschnitt gezeichnet statt für ganz DACH auf einmal. Für dich
heißt das: Beim Heranzoomen werden die Kacheln **schärfer** statt
verwaschener, und die App braucht dabei nur noch einen Bruchteil des
Speichers. Beim Schieben bleibt alles flüssig — neu gezeichnet wird
erst, wenn du den vorbereiteten Bereich wirklich verlässt.

## Die Waldfarben lagen daneben — jetzt sitzen sie

*9. August 2026 · Version 1.68.1*

Aufmerksamen Augen ist aufgefallen: Am Brocken malte die Karte Laubwald,
wo die Zahlen völlig richtig „reiner Nadelwald" sagten. Die eingefärbte
Waldfläche lag je nach Gegend bis zu 26 Kilometer zu weit südlich — ein
Projektionsfehler beim Zeichnen, der seit Einführung der Ebene bestand.
Alle Zahlen (Laubfaktor, „Wald hier", Legende) waren davon nie betroffen;
nur die Farben auf der Karte saßen verschoben. Danke für den Hinweis!

## „Was ist hier?" — für jede Stelle, nicht nur für deine Spots

*9. August 2026 · Version 1.68.0*

Regen, Temperatur und Waldtyp gab es bisher nur dort, wo schon ein Spot
liegt — also nur für Stellen, an denen du warst. Zum Erkunden brauchst du
es genau andersherum.

Tipp jetzt auf die kleine Legende links unten auf der Karte: Ein Blatt
zeigt für die Stelle unter dem Fadenkreuz den Waldtyp, den Laubfaktor im
Kilometer ringsum, den Regenverlauf der letzten Wochen und die
Temperaturkurve — dieselben Angaben wie im Spot-Blatt.

Das kostet keine Daten: Alle Werte stammen aus den Gittern, die ohnehin
schon auf dem Gerät liegen. Deine Position und die betrachtete Stelle
verlassen das Handy nicht, und im Funkloch steht dort dasselbe wie
zu Hause.

## Der Laubfaktor misst jetzt einen Kilometer

*9. August 2026 · Version 1.67.0*

Der Wert in der Wald-Legende schaute bisher nur 200 Meter weit um das
Fadenkreuz — bei Kacheln von rund 250 Metern Kantenlänge war der Umkreis
also kleiner als ein einziges Kästchen. Herausgekommen sind vier bis sechs
Kästchen, und der Wert sprang beim Schieben der Karte.

Jetzt zählt der Kilometer ringsum, also rund 70 Kästchen. Die Legende
schreibt die Reichweite dazu, damit klar ist, worüber die Zahl redet.

## Funde lassen sich korrigieren

*8. August 2026 · Version 1.66.0*

Vertippt, falsches Datum, zweimal dasselbe eingetragen? Tipp im Spot-Blatt
einfach den Eintrag an: Art, Anzahl, Datum und Notiz lassen sich ändern —
oder der Eintrag verschwindet einzeln, ohne dass der ganze Spot mit seiner
Historie dran glauben muss. Das gilt auch für „Nichts gefunden"-Einträge;
dort lassen sich Datum und Notiz richtigstellen.

Was Pilzfreunde an deinen Spots eingetragen haben, bleibt unangetastet —
ihre Funde gehören ihnen.

## „Hier warst du letztes Jahr erfolgreich"

*8. August 2026 · Version 1.65.0*

Die Karte erinnert dich jetzt an deine eigenen guten Tage: Hattest du an
einem Spot **um diese Jahreszeit** in einem früheren Jahr Erfolg,
erscheint oben ein grüner Hinweis — mit Ort, Art und Jahr. Antippen
öffnet den Spot.

Das ist keine Vorhersage, sondern deine eigene Geschichte: gerechnet
allein aus deinen Funden, ohne Netz, auch tief im Wald. Das X blendet
den Hinweis für die nächsten zwei Wochen aus — die Erinnerung des
nächsten Zeitfensters kommt dann wieder.

## Die Legende misst jetzt mit

*8. August 2026 · Version 1.64.0*

Die Legende zeigt jetzt die Werte an der Stelle des Fadenkreuzes — als
Strich direkt auf ihren Skalen, sobald die Karte zum Stehen kommt:

- **Regen:** Bei den Summen-Ebenen steht der Millimeterwert der
  Kartenmitte im Titel, und ein Strich markiert ihn auf der Farbskala.
- **Wald:** Die Waldtypen-Legende ist zu einer Skala von Laub bis Nadel
  geworden. Ein Strich zeigt den **Laubfaktor** im 200-m-Umkreis des
  Fadenkreuzes (1 = reiner Laubwald, 0 = reiner Nadelwald — Mischwald
  zählt anteilig), daneben steht, wie viel der Umgebung überhaupt Wald
  ist. So siehst du beim Verschieben der Karte sofort, ob sich die
  Fahrt in dieses Waldstück lohnt.

Gerechnet wird bewusst erst, wenn die Karte stillsteht — das Schieben
selbst bleibt flüssig.

## Wald und Regen zusammen, klarere Farben, Legende auf der Karte

*8. August 2026 · Version 1.63.0*

Gleich drei Wünsche aus dem Feld in einem Update:

- **Neue Waldfarben:** Laubwald ist jetzt herbst-ocker, Mischwald
  gelbgrün, Nadelwald dunkel blaugrün — die drei sind endlich auf einen
  Blick zu unterscheiden.
- **Waldklassen einzeln schaltbar:** Im Waldtypen-Blatt gibt es drei
  Häkchen. Wer nur wissen will, wo Laubwald steht, blendet den Rest aus.
- **Regen und Wald gleichzeitig:** Die beiden Ebenen schließen sich
  nicht mehr aus. Der Regen liegt über dem Wald — und wer es übersichtlich
  mag, lässt vom Wald nur die eine Klasse stehen, die ihn interessiert.
- **Legende auf der Karte:** Solange eine Ebene aktiv ist, liegt ihre
  Legende klein links unten auf der Karte. Das X daran merkt sich das
  Ausblenden; zurück geht es im Ebenen-Blatt über „Legende in Karte
  anzeigen".

## Ebene aus heißt jetzt sofort aus

*8. August 2026 · Version 1.62.2*

Wer die Wald- oder Regenebene abgeschaltet hat, sah sie trotzdem noch —
bis zur nächsten Kartenbewegung. Jetzt verschwindet die Fläche in dem
Moment, in dem du den Schalter umlegst. Danke für die schnelle
Rückmeldung aus dem Feld!

## Welcher Wald ist das? Die Karte weiß es jetzt

*8. August 2026 · Versionen 1.62.0 und 1.62.1 (1.62.1: nur aktualisierte Bibliotheken, nichts Sichtbares)*

Wer Sommersteinpilze sucht, will nicht im reinsten Fichtenforst landen.
Die Karte hat dafür einen neuen Knopf: **Waldtypen** färbt den Wald in
drei Grüntönen ein — hell für Laub, mittel für Misch, dunkel für Nadel.
Die Daten kommen aus dem Copernicus-Satellitenprogramm der EU, decken
Deutschland, Österreich und die Schweiz ab und sind aktuell genug, dass
die Käferflächen der letzten Jahre nicht mehr als Fichtenwald auftauchen.

Im Spot-Blatt steht dazu eine neue Zeile: **„Wald hier"** nennt den
Waldtyp an der Stelle, samt Nadelanteil in Prozent. Beides funktioniert
komplett **offline** — die Waldkarte steckt in der App, es wird nichts
geladen und nichts gesendet.

Ehrlich gesagt dazu: Das Raster ist 250 m grob. Es zeigt dir, in welche
Richtung sich die Fahrt lohnt — den einzelnen Buchenhang im Fichtenwald
zeigt es nicht. Regen- und Waldebene wechseln sich ab, weil beide
halbtransparent sind und übereinander nichts mehr zu lesen wäre.

## Vollständige Lizenzangaben

*7. August 2026 · Version 1.61.1*

Die Seite „Open-Source-Lizenzen" im Profil nennt jetzt auch die
**Kartenschrift** und die **Regendaten**. Beide waren längst in der App,
standen dort aber nicht — bei der Schrift fehlte sogar der Lizenztext
selbst, obwohl ihre Lizenz genau den verlangt.

Für dich ändert sich am Verhalten der App nichts. Es ist trotzdem kein
Schönheitsfehler gewesen: Kartendaten, Wetterdaten und Schriften dürfen wir
nur unter der Bedingung verwenden, dass wir ihre Herkunft nennen.

## Fundorte stapeln sich nicht mehr

*6. August 2026 · Version 1.61.0*

Gehst du fünf Meter weiter und trägst den nächsten Pilz ein, entstand
bisher ein **zweiter Fundort** — auf der Karte liegen die Marker dann
übereinander, obwohl es im Wald dieselbe Stelle ist.

Jetzt fragt die App nach: Liegt in **20 m** schon einer deiner Spots,
kannst du den Fund **dort eintragen** statt einen neuen anzulegen. Willst
du trotzdem einen zweiten, geht das mit einem Tipp daneben — die
Entscheidung bleibt bei dir, die App legt nichts still zusammen.

Für das, was sich schon gestapelt hat, gibt es im Profil einen neuen
Punkt: **„Dicht beieinander"**. Er erscheint nur, wenn es wirklich etwas
zu tun gibt, listet die betroffenen Paare mit ihrem Abstand und führt sie
auf Wunsch zusammen — du sagst, welcher Name bleibt.

Ein Fall bleibt außen vor, und zwar mit Absicht: Hat ein Pilz-Buddy an
einem der beiden Spots eingetragen, wird das Paar nicht angeboten. Seine
Funde könnten nicht mitwandern und gingen beim Zusammenführen verloren.

## Kein versehentlicher Sprung mehr auf der Karte

*6. August 2026 · Version 1.60.0*

Langes Draufhalten setzte das Fadenkreuz auf die gedrückte Stelle **und**
zoomte weit heran. Das löste zu leicht aus: Aus der Übersicht landete man
plötzlich woanders und viel zu nah dran, und der Weg zurück war
rauszoomen und wiederfinden. **Ab jetzt ist die Geste aus.**

Zum Heranzoomen genügt ein **Doppeltipp** auf die Stelle — das konnte die
Karte schon immer, es ging nur unter. Das Fadenkreuz stellst du wie bisher
durchs Schieben ein.

Wer die alte Bedienung mochte, holt sie im Profil unter **„Karte gedrückt
halten"** zurück; dann arbeitet sie wieder genau wie vorher.

## Zwei Pilze sehen richtiger aus, das Wetter liest sich leichter

*6. August 2026 · Version 1.59.0*

Der **Steinpilz** hat jetzt den dicken, bauchigen Stiel, den er in echt
auch hat — damit ist er auf der Karte nicht mehr mit der Marone zu
verwechseln. Der **Samtfußrübling** war bisher grau und sah aus wie
irgendein Blätterpilz; er ist jetzt honig-orange und steht auf einem
dünnen dunklen Stiel, genau wie im Winterwald am Totholz.

Im Diagramm unter „Wetter an diesem Spot" liegen jetzt **feine
Hilfslinien** auf Höhe der Gradzahlen. Du musst einen Punkt der
Temperaturkurve nicht mehr quer durchs Bild bis zur Achse verfolgen, um
ihn abzulesen. Die gestrichelte Frostlinie bei 0 °C bleibt dabei die
auffälligste — sie ist im Herbst die Zahl, auf die es ankommt.

## Mehrere Arten auf einmal — und „nichts gefunden"

*6. August 2026 · Version 1.58.0*

Standen an einem Spot Steinpilze **und** Maronen, musstest du das Blatt
bisher zweimal ausfüllen. Jetzt legst du mit **„weitere Art"** die
fertige Zeile ab und tippst gleich die nächste; Datum und Notiz gelten
für alle. Trägst du nur eine Art ein, ändert sich für dich nichts —
„Speichern" nimmt die offene Zeile ohnehin mit.

Neu daneben: **„Nichts gefunden"**. Warst du an einem Spot und stand
dort nichts, kannst du das jetzt festhalten — mit Datum und wenn du
magst einer Notiz, mehr fragt die App nicht. Solche Einträge zählen
**nirgends als Fund**: Deine Statistik bleibt, wie sie ist, das
Pilz-Bild auf der Karte auch, und der Artfilter zeigt den Spot weiterhin
unter der Art, die dort mal stand.

Warum es das gibt: Die App kennt bisher nur Erfolge. Für eine ehrliche
Wachstums-Vorhersage fehlt genau die andere Hälfte — „war da, war
nichts". Ohne sie lässt sich nie prüfen, ob eine Vorhersage stimmt.
Deine Buddys sehen solche Einträge an geteilten Spots übrigens mit, aber
sie lösen keine Fund-Meldung aus.

Beides steckt auch im GPX-Export: Deine Leergänge kommen beim
Wiedereinlesen zurück.

## Deine Spots vollständig sichern und umziehen

*6. August 2026 · Version 1.57.0*

Der GPX-Export im Profil nimmt jetzt **alles** mit: nicht nur die
Fundorte, sondern jeden einzelnen Fund mit Art, Anzahl, Datum und Notiz,
dazu die Einstellung „Von Freigabe ausschließen". Liest du die Datei
wieder ein, steht dein Revier so da, wie du es verlassen hast — auch in
einem **anderen Konto**. Genau dafür ist es gedacht.

Beim Import erkennt die App eine solche Datei von selbst und zeigt eine
Liste zum Abhaken: alle auf einmal oder einzeln. Spots, die du schon
hast, sind vermerkt und nicht angehakt — dieselbe Datei zweimal
einzuspielen legt also nichts doppelt an. Anhaken kannst du sie trotzdem.

Die Datei bleibt gleichzeitig eine ganz normale GPX-Datei: Jede
Karten- oder Navi-App zeigt weiterhin deine Wegpunkte mit Namen und
Fundhistorie. Nebenbei behoben — die Fundliste stand dort bisher als
Fließtext in einer Zeile, jetzt steht sie untereinander.

**Ein Hinweis, den du vor dem Teilen bekommst:** Weil in der Datei auch
deine **Notizen** stehen, fragt die App jetzt nach, bevor sie das
Teilen-Fenster öffnet. Als Sicherung für dich selbst ist das gewollt —
weitergeben solltest du sie nur, wenn die Notizen jemand lesen darf.

## Wann welche Art gemeldet wird

*5. August 2026 · Version 1.56.0*

Im Spot-Blatt steht jetzt über dem Wetter ein neuer Abschnitt: **„Wann
diese Art gemeldet wird"** — zwölf Balken, einer je Monat, der laufende
hervorgehoben, dazu ein Satz wie „Steinpilz wird am häufigsten im August
bis September gemeldet."

Die Zahlen stammen aus echten Fundmeldungen aus Deutschland, Österreich
und der Schweiz — rund 300 000 Beobachtungen für die 89 Arten, für die es
genug davon gibt. Sie sind gegen den allgemeinen Meldeeifer verrechnet:
Im September und Oktober wird schlicht am meisten gesammelt und gemeldet,
und ohne diese Korrektur sähe jede Art gleich aus. Danach liegt zum
Beispiel die Zeit des Pfifferlings im **Juli**, nicht im August.

**Was der Abschnitt nicht ist:** eine Vorhersage. Er beschreibt frühere
Jahre, nicht dieses Wochenende — es steht kein Prozentzeichen darin und
keine Bewertung. Ob es sich gerade lohnt, hängt am Wetter, und das ist
eine andere Frage, an der noch gearbeitet wird.

Drei Dinge, die dazugehören: Die Kurven liegen **in der App**, sind also
ohne Empfang da und verraten niemandem, wonach du suchst. Arten mit zu
wenigen Meldungen bekommen bewusst gar keinen Abschnitt statt einer
Zackenlinie. Und wo ein Name für mehrere Arten steht — „Rotkappe",
„Hallimasch" —, sagt die App das dazu.

## Die Karte sagt dir, wenn ein Buddy einen Fund eingetragen hat

*5. August 2026 · Version 1.55.0*

Trägt ein Pilz-Buddy einen Fund ein — auf einem deiner Spots oder auf
einem, den er mit dir geteilt hat —, zeigt die Karte oben ein blaues
Banner: **„Neuer Fund von …"**. Antippen öffnet direkt den Spot mit dem
neuesten Fund; das X blendet den Hinweis aus. Beides merkt sich die App
auf dem Gerät, der Hinweis kommt also nicht nach jedem Neustart wieder.

Es gibt dafür keine Push-Nachrichten und keine E-Mails — der Hinweis
erscheint nur in der App, und es verlässt dafür kein einziges neues
Datum dein Gerät.

## Pilz-Buddies können Funde zu geteilten Spots eintragen

*5. August 2026 · Version 1.54.0*

Wenn ein Freund einen Spot mit dir teilt, kannst du dort jetzt **eigene
Funde eintragen** — dein Fund gehört dir, der Spot weiterhin deinem
Freund. In der Fundliste steht bei fremden Funden, von wem sie stammen.

Endet die Freundschaft oder das Teilen, sieht jeder wieder nur die
eigenen Funde — nichts wird gelöscht, und wer sich wieder anfreundet,
sieht auch die Funde des anderen wieder. Funde dritter Freunde bekommt
niemand zu sehen: Was du einträgst, sehen nur du und die Besitzerin
oder der Besitzer des Spots.

Statistik und GPX-Export zählen wie bisher nur deine eigenen Funde.

## Regenkarte ohne Farbblitz, Wetter am Spot aufgeräumt

*5. August 2026 · Version 1.53.0*

Beim Einschalten von **„Letzte 24 Stunden"** oder **„Letzte 30 Tage"**
blitzte bisher kurz die Karte des Wetterdienstes in fremden Farben auf,
bevor unsere eigene Darstellung sie ersetzte — samt falscher Legende im
Regen-Blatt. Das ist bereinigt: Während die Daten laden, bleibt die
Karte ruhig, und die richtige Legende steht sofort da. Nebenbei spart
das bei jedem Einschalten einen unnötigen Download von bis zu einem
halben Megabyte. Kommen gar keine Daten an (kein Empfang), zeigt die
App wie bisher das Bild des Wetterdienstes samt seiner Legende.

Dazu ein aufgeräumtes Erscheinungsbild im PilzBuddy-Stil, wie man ihn
aus den Anmelde-Mails kennt: Die Regensummen im Spot-Blatt stehen jetzt
**in einer cremefarbenen Kachel** mit den Werten fett in Grün, und die
Überschriften von Regen-Blatt, Legende und Wetter-Abschnitt tragen das
PilzBuddy-Grün.

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
