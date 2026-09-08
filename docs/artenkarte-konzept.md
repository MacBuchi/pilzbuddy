# Artenkarte: „wo finde ich diesen Pilz bei mir?"

Konzept zu Issue #414. **Noch nichts gebaut** — diese Seite entscheidet,
ob und wie.

Die Frage stammt vom Betreiber (2026-09-08) und ist die eine, die die App
heute nicht beantworten kann: Sie weiß, wo man SCHON war. Wo man
hingehen sollte, sagt sie nicht.

## Was da ist, und was fehlt

| Baustein | Wo | Abdeckung |
|---|---|---|
| Saisonkurve je Art, monatlich, effort-korrigiert | `lib/core/season_curves.g.dart` aus `tool/season_curves.py` | **91 Arten** mit ≥200 GBIF-Meldungen |
| Führende Laub- und Nadelart je Wabe | `lib/features/map/forest_species.dart` | **nur Deutschland** |
| Waldklasse (Laub/Misch/Nadel) | Waldgitter (Copernicus) | DACH |
| Höhe, Regen, Temperatur | die drei bestehenden Gitter | DACH |

Alles liegt auf dem Gerät, alles auf **demselben Hexgitter**, ein
`hexNearestCell` je Wabe. Das ist der Grund, warum das Ganze überhaupt
denkbar ist: kein neues Netzziel, keine neue Zustimmung, offline nutzbar.

**Es fehlt genau eine Sache: die Verknüpfung Pilz → Baum.** `KnownSpecies`
trägt Name, Gruppe, Zweitnamen und den wissenschaftlichen Namen. Kein
Habitat, kein Partnerbaum. Ohne sie lässt sich Baumbestand nicht in eine
Aussage über eine BESTIMMTE Art übersetzen — und damit steht und fällt
das Feature.

## Die neun Bäume sind das Vokabular

Das Gitter unterscheidet **Buche, Eiche, Birke, Erle** und **Fichte,
Kiefer, Tanne, Douglasie, Lärche**. Mehr kann eine Verknüpfung nicht
sagen, und weniger braucht sie nicht: Neun Namen lassen sich von Hand
pflegen und einzeln belegen.

Zwei Eigenheiten dieses Vokabulars, die das Konzept tragen muss:

- **Je Wabe nur die FÜHRENDE Laub- und die führende Nadelart.** Das ist
  gemessen und dokumentiert (`tool/forest_species.py`): Die häufigste Art
  allein verschluckte in 17,6 % der Waldzellen den Mischpartner, deshalb
  zwei Halbbytes. Aber ein buchendominierter Hang hat trotzdem Birken.
  **Die Baumangabe ist deshalb ein Hinweis, kein Filter.**
- **Manche Partner fehlen.** Die Espenrotkappe steht mit der Espe, und
  Espe ist keine der neun. Für solche Arten gibt es keine Aussage — und
  „keine Aussage" muss anders aussehen als „hier nicht".

## Woher die Verknüpfung kommt

Drei Wege, und nur einer trägt.

**Von Hand kuratiert, Art für Art belegt.** Das ist der Vorschlag.
Mykorrhiza-Partnerschaften gehören zu den bestbelegten Tatsachen der
Mykologie, und ein erstaunlicher Teil steht **im deutschen Namen**:
Birkenpilz, Fichtensteinpilz, Kiefernsteinpilz, Goldröhrling (Lärche),
Butterpilz (Kiefer), Fichtenreizker. Wo der Name es sagt, ist die
Verknüpfung so sicher wie die Artbestimmung selbst.

Es gelten dieselben Regeln wie für die Pilz-Grafiken
(`.claude/skills/pilz-designer/`): erst nachschlagen, dann eintragen; die
deutsche Wikipedia als Mindestbeleg; und **wo die Quelle nicht eindeutig
ist, bleibt das Feld leer.** Eine falsche Verknüpfung schickt Leute mit
Zuversicht in den falschen Wald — eine fehlende schickt sie nur nicht los.

Verworfen: **GBIF-Habitatfelder** (Freitext, sehr ungleiche Qualität) und
**Ableitung aus den eigenen Funden** (die Daten gibt es noch nicht, und
für eine spätere Validierung wären sie zirkulär).

**Nicht jede Art hat überhaupt einen Partnerbaum.** Der Hallimasch lebt
von vielen Hölzern, der Austernseitling auf totem Laubholz, die Krause
Glucke am Kiefernstumpf. Das ist eine andere Beziehung — Substrat statt
Symbiose. Der erste Ausbau beschränkt sich deshalb auf
**Mykorrhiza-Arten**, wo „Baum" eindeutig „Partner" heißt. Für die
übrigen bleibt das Feld leer, und die Karte sagt es.

## Wie die Faktoren zusammenkommen

    Eignung(Wabe, Art, Datum) = Saison(Art, Monat) × Habitat(Art, Wabe)

**Saison** ist die Kurve aus `season_curves.g.dart`, 0–100. Sie wirkt
multiplikativ, weil sie wirklich ein Tor ist: Im Dezember gibt es keine
Pfifferlinge, egal wie der Wald steht.

**Habitat** ist ABGESTUFT, nicht binär — genau wegen der führenden Art
oben:

| Lage | Faktor |
|---|---|
| Partnerbaum ist die führende Art der Wabe | 1,0 |
| Partner passt zur Klasse, ist aber nicht führend (Buchen-Partner in einer Eichen-Wabe) | ~0,5 |
| falsche Klasse (Nadel-Partner im reinen Laubwald) | ~0,15 |
| kein Wald | 0 |
| keine Baumangabe (außerhalb Deutschlands, oder Art ohne Eintrag) | **keine Aussage** — nicht 0 |

Der letzte Punkt ist der wichtigste. Eine leere Fläche in Österreich, die
aussieht wie „hier wächst nichts", wäre eine Lüge über fehlende Daten —
derselbe Fehler, den die Wald-Ebene schon einmal vermeiden musste.

**Das Wetter bleibt draußen.** Die Ampel beantwortet „ist gerade ein
guter Tag", diese Karte „ist das grundsätzlich ein guter Ort". Beides zu
multiplizieren machte aus zwei nachvollziehbaren Aussagen eine, die
keiner mehr auseinanderhalten kann — und die Ampel trägt aus gutem Grund
das Wort „experimentell".

## Wie es aussieht

Eine **Kartenebene**, hinter einem eigenen Eintrag im Ebenen-Blatt, mit
einer Artenauswahl. Die Wabenfüllung gibt es schon (Waldebene, #249):
dasselbe Gitter, dasselbe Zeichenverfahren, dieselbe Isolate-Rechnung.

Bewusst NICHT über den bestehenden Filter: Der filtert **deine Spots**,
also Vergangenheit. Diese Ebene malt Möglichkeiten. Zwei verschiedene
Fragen in einem Bedienelement wären eine dritte.

## Was die Karte behaupten darf

Das ist die schärfste Frage, und sie entscheidet über den Wortlaut.

Was hier gerechnet wird, ist **Standorteignung aus Literatur mal Saison
aus Beobachtungen**. Es ist keine Vorhersage, dass dort Pilze stehen. Der
Unterschied ist nicht akademisch: Eine eingefärbte Fläche liest sich viel
zuversichtlicher als ein Ampel-Banner, und die Rückwärtsvalidierung
(`docs/pilzampel-validierung.md`) hat ausgerechnet die **Arten-Achse**
nicht bestanden — zwei von drei Holzbewohnern passten zum
Mykorrhiza-Modell, die Artspezifik war also nicht belegbar.

Daraus folgt der Ton: „**Hier passt der Wald zu dieser Art, und die
Jahreszeit stimmt**" — nicht „hier findest du sie". Und in der Legende
steht, woraus sich das speist.

**Eine Validierung ist möglich und gehört dazu**, bevor die Ebene
ausgeliefert wird: Dieselbe GBIF-Stichprobe, die
`tool/ampel_validate.py` schon holt, trägt Koordinaten. Die Frage lautet:
Liegen echte Fundmeldungen einer Art häufiger in Waben mit hoher Eignung
als an zufälligen Waldwaben derselben Region? Das ist dieselbe
AUC-Methode wie bei der Ampel und braucht keine neue Datenquelle.
**Nicht mit unseren eigenen Funden validieren** — die sind die
Stichprobe, die #199 als unabhängigen Prüfstein aufhebt.

## Was zuerst

1. **Die Verknüpfungstabelle**, für die zwanzig bis dreißig Arten, die
   wirklich gesammelt werden — mit Beleg je Zeile, und leer, wo die
   Quelle schwankt. Ohne sie ist alles andere gegenstandslos.
2. **Die Validierung** aus dem Abschnitt darüber. Fällt sie durch, ist
   das Feature beantwortet, bevor eine Zeile Oberfläche entsteht.
3. Erst dann Ebene, Legende und Artenauswahl.

Die Reihenfolge ist Absicht: Schritt 1 und 2 sind Werkzeugarbeit ohne
Risiko für Nutzer, und sie können das Vorhaben abräumen. Schritt 3 ist
der teure Teil.

## Abdeckung, klar gesagt

Baumarten gibt es nur für Deutschland. In Österreich und der Schweiz
bleibt die Ebene ohne Aussage — und sagt das, statt leer zu wirken.
Dieselbe Lösung wie beim Wald-Blatt, das die Copernicus- und
DLR-Abdeckung schon nebeneinander nennt.
