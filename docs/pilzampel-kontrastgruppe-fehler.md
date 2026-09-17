# Die Kontrastgruppe war nach dem Kalender gewählt, die Hypothese ist über Temperatur

Stand: 2026-09-17 · Befund zum Lauf aus
`docs/pilzampel-herbstklasse-messung.md` · betrifft den Prüfplan
`docs/pilzampel-herbstklasse-mitgliedschaft.md`

## Was passiert ist

Der registrierte Plan hat den Ausgang **`generisch`** geliefert: Beide
frischen Kontrastarten bestehen die Latte, und das heißt nach Plan „das
Modell trennt nicht nach Temperaturnische, die Klassenmaschinerie
gehört zurückgebaut".

**Dieser Ausgang ist nicht belastbar, und der Fehler liegt im Plan.**

## Der Beleg, und er hängt nicht am Ergebnis

Die Gruppenzuordnung kam aus dem **Saisongipfel** — dem Monat mit den
meisten Meldungen. Die Hypothese, die geprüft werden sollte, ist aber
eine über **Temperatur**: ob eine Glocke um 13 °C die Fundtage einer
Art trennt.

Gemessen, mittlere 20-Tage-Temperatur am Fundtag:

| Art | Gruppe im Plan | T am Fundtag | Abstand zu 13 °C | AUC |
|---|---|--:|--:|--:|
| Fliegenpilz | herbstnah | 12,0 °C | 1,0 K | 0,791 |
| Steinpilz | herbstnah | 13,7 °C | 0,7 K | 0,762 |
| Maipilz | **Kontrast** | 10,6 °C | 2,4 K | 0,766 |
| Sommersteinpilz | **Kontrast** | 16,7 °C | 3,7 K | 0,647 |
| Judasohr | Kontrast (kalt) | 8,3 °C | 4,7 K | 0,508 |
| Austernseitling | Kontrast (kalt) | 9,0 °C | 4,0 K | 0,463 |
| Samtfußrübling | Kontrast (kalt) | 4,5 °C | 8,5 K | 0,283 |

Die beiden Frühjahrsarten fruchten bei **10,6 und 16,7 °C** — beide
innerhalb der Glocke (13 °C, σ = 5 K). Sie waren nie ein Kontrast zu
diesem Fenster. Der Kalender war ein schlechter Stellvertreter: Mai und
September liegen in Deutschland bei ähnlicher Mitteltemperatur, die
Jahreszeit unterscheidet sie, die Temperatur nicht.

**Das war vor der Messung prüfbar.** Die Temperatur am Fundtag hängt an
keiner AUC; sie hätte beim Einfrieren des Kandidatenkreises
danebengestanden. Der Fehler ist nicht, dass die Daten überraschten,
sondern dass die Gruppen nach der falschen Größe gebildet wurden.

## Was die Zahlen stattdessen zeigen

Die AUC folgt fast monoton dem Abstand zwischen der Fundtag-Temperatur
einer Art und den 13 °C: bis 1 K rund 0,78, bei 2–4 K rund 0,65–0,77,
bei 4–5 K um 0,50, bei 8,5 K dann 0,28. Ein Wert **unter** 0,5 ist
dabei die schärfste Aussage der ganzen Tabelle — beim Samtfußrübling
zeigt das Fenster nicht bloß nichts an, es zeigt in die Gegenrichtung.

Das ist das Verhalten einer **Temperaturnische** und gerade nicht das
eines Modells, das allgemeines Pilzwetter misst: Ein generisches Modell
müsste auch bei Winterarten anschlagen, und es tut das Gegenteil.

## Was daraus NICHT folgt

**Der Ausgang wird nicht umgedeutet.** „Die Kontrastarten bestehen,
also nehme ich sie aus der Kontrastgruppe" wäre genau der Griff, gegen
den der ganze Aufbau antritt. Der Plan hat `generisch` geliefert; diese
Seite sagt, dass der Plan die Frage nicht beantworten konnte, nicht dass
er anders ausgegangen wäre.

Belastbar ist damit **weder** `generisch` **noch** eine Mitgliedschaft.
Ausgeliefert wird nichts.

## Wie die Frage richtig gestellt wird

Nicht als Gruppenvergleich, sondern als **Dosis-Wirkung** über alle
Arten: Wenn das Fenster eine Temperaturnische ist, muss die AUC mit dem
Abstand zwischen Fundtag-Temperatur und 13 °C fallen — und zwar über
den ganzen Bereich, nicht nur zwischen zwei Häufchen. Das braucht keine
Gruppen, keine Stellvertreter und keine Grenzziehung nach Kalender.

Zwei Dinge sind dabei ehrlich zu halten:

- Die AUCs dieses Laufs sind bekannt. Eine an denselben Daten geprüfte
  Dosis-Wirkung ist **explorativ**, egal wie sauber sie gerechnet ist.
- Der Beleg müsste deshalb aus Daten kommen, die daran nicht beteiligt
  waren — AT und CH liegen im lokalen Bestand bereit und sind an keiner
  Zahl dieses Laufs beteiligt.
