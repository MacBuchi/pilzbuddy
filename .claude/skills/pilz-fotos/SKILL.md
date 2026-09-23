---
name: pilz-fotos
description: Fundfotos des Betreibers bestimmen und daraus Artbilder für PilzBuddy machen — Album aus Google Fotos auslesen, alle Bilder ansehen, Arten zuordnen, zuschneiden und in species_photos.dart eintragen. Auch zu benutzen, wenn nur EIN Bild zugeordnet werden soll oder wenn zu prüfen ist, ob ein vorhandenes Bild noch zum Merkmalstext passt.
---

# Artfotos: vom Fundfoto zur Artseite

Der Betreiber fotografiert seine Funde. Dieser Skill macht daraus die
Bilder auf den Artseiten — und, wichtiger, er hält fest, wo dabei schon
falsch abgebogen wurde.

**Der Zuschnitt zuerst, sonst ist die Arbeit umsonst.** PilzBuddy ist
eine App zum SAMMELN. Eine Art kommt nur hinein, wenn man sie sammelt
oder wenn sie mit etwas Sammelbarem verwechselt wird; alles andere
bleibt draußen, so schön das Foto ist (Betreiber, 2026-09-22). Der
Dunkelviolette Schleierling, der Buchen-Schleimrübling und der Klebrige
Hörnling sind auf genau diesem Weg ausgeschieden, obwohl es gute
Aufnahmen von ihnen gibt.

---

## 1. Das Album auslesen

Es gibt keinen Google-Fotos-Skill und keinen Konnektor, der hier hülfe
(siehe §8). Der geteilte Link reicht, ohne Konto und ohne Schlüssel.

Ein `https://photos.app.goo.gl/<id>` direkt abzurufen liefert nur die
Firebase-Zwischenseite, in der das Ziel NICHT steht. Mit `?_imcp=1` löst
der Dienst den Link serverseitig auf:

```bash
curl -sL -A "Mozilla/5.0" "https://photos.app.goo.gl/<id>?_imcp=1" -o album.html
```

Die Bilder stecken im ZWEITEN `AF_initDataCallback`-Block. `data[1]` ist
die Liste, je Eintrag `[id, [url, breite, hoehe, …], zeitstempel_ms, …]`.
Die URL nimmt einen Größen-Suffix, etwa `=w640` zum Sichten und `=w1800`
zum Prüfen.

```python
import re, json
b = re.findall(r"AF_initDataCallback\((\{.*?\})\);", html, re.S)[1]
d = json.loads(re.search(r"data:(\[.*\])\s*,\s*sideChannel", b, re.S).group(1))
items = d[1]      # [0]=id, [1][0]=url, [1][1]=w, [1][2]=h, [2]=ts_ms
```

Drei Dinge, die man wissen muss:

- **Ein Tiefenlink auf ein EINZELNES Foto funktioniert nicht.** Die Form
  `…/share/<token>/photo/<id>?key=<key>` liefert HTTP 200 und öffnet im
  Browser trotzdem nur das Album. Wer dem Betreiber ein bestimmtes Bild
  zeigen will, schickt die direkte Bildadresse mit `=w1600`.
- **Der Standort ist NICHT dabei.** Google entfernt den GPS-Tag beim
  Teilen. Für die Zuordnung hilft er also nicht — umgekehrt kann aus
  dieser Quelle auch keine Fundstelle versehentlich ins APK wandern.
  Wer den Baum am Fundort braucht, fragt (§4).
- **Der Freigabe-Schlüssel gehört NIE ins Repository.** Nicht in den
  Skill, nicht in ein `tool/`-Skript, nicht in eine Commit-Message. Das
  Repo ist öffentlich. Bei eigenen Fotos steht als Quelle „Eigene
  Aufnahme", keine Adresse.

---

## 1a. Bilder aus Art-Hinweisen anderer Nutzer

Seit 1.197.0 kann ein Melder beim „Hinweis zu dieser Art melden" einen
Haken für die Artgalerie setzen (Patch 034). Nur MIT diesem Haken darf
ein solches Bild hinein; das Issue sagt es in der Zeile „✅ Für die
Artgalerie freigegeben" und nennt den Urheber (Benutzername statt
`MacBuchi`, sonst dieselbe Lizenz CC BY-SA 4.0).

- **Holen:** `python3 tool/feedback_photos.py <issue>` legt die Bilder
  außerhalb des Repos ab. Nie ans Issue hängen, das ist öffentlich.
- **Innerhalb von 90 Tagen**, danach fegt der Bot den Bucket. Bei einem
  fremden Melder gibt es kein Original im Austauschordner; was im
  Bucket liegt, ist die einzige Kopie.
- **Auflösung:** Seit 1.199.0 kommen diese Bilder mit 2048er Kante an,
  genug für die 1200er Fassung. Ältere Meldungen haben nur 1024 — die
  taugen für das 400er Asset, für die große Fassung nicht.

## 2. Alle ansehen, nicht eine Vorauswahl

**Die Vorschau lügt.** Zwei Bilder, die im Kontaktbogen wie ein dunkler
Röhrling aussahen, waren in voller Auflösung ein Lamellenpilz mit
Schleiervelum. Wer nur die vielversprechenden groß ansieht, findet
genau die Fehler nicht, die zählen.

Der Ablauf, der sich bewährt hat: alle auf `=w640` herunterladen, mit
**ffmpeg** nummerierte Kontaktbögen zu neun bauen, jeden Bogen ansehen,
und anschließend jedes Bild, das ein Kandidat ODER zweifelhaft ist, auf
`=w1800`.

**ImageMagick ist auf diesem Rechner nicht installiert**, ffmpeg schon:

```bash
# Nummer einbrennen
ffmpeg -y -i img/$n.jpg -vf "scale=420:420:force_original_aspect_ratio=decrease,\
pad=420:420:(ow-iw)/2:(oh-ih)/2:color=0x202020,\
drawtext=fontfile=/System/Library/Fonts/Supplemental/Arial.ttf:text='$n':\
x=6:y=6:fontsize=30:fontcolor=yellow:box=1:boxcolor=black@0.7:boxborderw=5" lab/$n.png
# Bogen
ffmpeg -y -framerate 1 -pattern_type glob -i 'lab/*.png' \
  -vf "tile=3x3:padding=4:color=0x101010" sheets/s%02d.png
```

Ein Bogen mit mehr als etwa 15 Bildern ist zu lang zum Ansehen; lieber
mehrere.

---

## 3. Nicht raten

**Ein Wulstling, dessen Stielbasis im Laub steckt, wird nicht
bestimmt.** Gerandete Knolle heißt Pantherpilz und damit giftig,
rübenförmig heißt Grauer Wulstling. Steht die Basis auf keinem der
Bilder frei, fällt die Serie ganz weg — vier gute Aufnahmen sind dafür
kein Argument.

Dieselbe Regel für alles, wo der Fehler teuer ist: ein giftiger Partner,
eine tödliche Verwechslung, eine Art, die jemand in die Pfanne legt.

**Was dem Betreiber vorzulegen ist, ist keine Frage nach „was ist das",
sondern nach EINEM Merkmal.** Er war dort, ich nicht. Gute Fragen:

| Unklar | Die eine Frage |
|---|---|
| Reizker-Art | Fichte, Tanne oder Kiefer am Fundort? |
| Falscher Pfifferling ↔ Ölbaumtrichterling | Auf Holz büschelig oder einzeln auf Streu? |
| Stockschwämmchen ↔ Gifthäubling | Stiel unter dem Ring schuppig? |
| Wulstling | Knolle gerandet oder rübenförmig? |

Zur Frage gehört die direkte Bildadresse (§1), sonst muss er suchen.

---

## 4. Die Ökologie entscheidet, wo die Gestalt es nicht tut

Der teuerste Fall dieses Skills, und er ging anders aus als erwartet.

Ein Reizker-Foto zeigte **tiefe, scharf gezeichnete Stielgrübchen** —
nach unserer Merkmalstabelle das Kennzeichen des Edelreizkers — und
zugleich **großflächiges Grünen**, das für den Fichtenreizker spricht.
Zwei Merkmale, zwei Arten.

Aufgelöst hat es der Standort: Nordschwarzwald, praktisch keine Kiefern,
also fallen beide Kiefernarten weg; der Tannenpartner Lachsreizker grünt
nicht. Übrig bleibt der Fichtenreizker — **mit** Grübchen.

Daraus folgen zwei Regeln:

- **Ein Bild, das dem Merkmalstext auf derselben Seite widerspricht, ist
  schlimmer als gar kein Bild.** Bevor es eingebaut wird, wird der
  Widerspruch aufgelöst.
- **Und der Text ist der wahrscheinlichere Fehler.** „Meist ohne die
  Grübchen des Edelreizkers" las sich wie eine Entscheidungsregel und
  war keine. Ein Lehrbuchbild hätte den Fehler bestätigt, weil
  Lehrbuchbilder die Lehrbuchform zeigen. Genau dafür sind eigene
  Fundbilder da. Die Korrektur gehört in denselben oder den nächsten PR
  (so geschehen in 1.169.0).

Nützlich dabei: **PilzBuddy weiß selbst, welche Bäume am Spot stehen**
(Baumarten am Spot, DLR-Karte, nur Deutschland). Bei den Reizkern ist
der Baum das einzige wirklich trennende Merkmal.

---

## 5. Was nicht ins Binary kommt

- **Ein untypisches Exemplar bei einer Art, deren Name die Farbe ist.**
  Alle sechs Schwefelporling-Aufnahmen zeigten ein altes, kreidig
  blasses Stück. Ausgelassen.
- **Fremdkörper im quadratischen Ausschnitt.** Hand, Handschuh, Schuh,
  Messer. Eine Ausnahme ist vertretbar, wenn das Bild als einziges ein
  entscheidendes Merkmal zeigt (Lamellen und Ring beim Champignon).
- **Ein Küchenbild, wenn ein brauchbares Fundbild existiert.** Umgekehrt
  ist ein Küchenbild besser als ein Fundbild, auf dem man nichts
  erkennt — bei der Herbsttrompete ist genau so entschieden worden.
- **Ein Tausch, den niemand braucht.** Hat eine Art schon ein geprüftes
  Bild im Vergleichspaar, ist ein zweites, ähnliches kein Fortschritt.

---

## 6. Assets bauen

Quadratisch, 400×400, WebP q80. Gemessen liegt das bei 20–60 KB je Bild;
33 Bilder waren 1,21 MB.

```bash
ffmpeg -y -i quelle.jpg -vf "crop='min(iw,ih)':'min(iw,ih)',scale=400:400" /tmp/p.png
cwebp -q 80 -m 6 /tmp/p.png -o assets/species/<slug>-<n>.webp
```

Slug wie die vorhandenen Dateien: klein, ohne Sonderzeichen, `ä→ae`,
`ö→oe`, `ü→ue`, `ß→ss`. Mehrere Bilder je Art mit `-1`, `-2`, `-3`.

**Danach gegenprüfen, dass keine Metadaten mitgekommen sind.** `cwebp`
wirft sie zwar weg, aber das ist eine Zusage, keine Beobachtung:

```bash
python3 -c "
import glob
bad=[f for f in glob.glob('assets/species/*.webp')
     if any(t in open(f,'rb').read() for t in (b'EXIF', b'GPS', b'XMP'))]
print('mit Metadaten:', bad or 'keine')"
```

---

## 7. Eintragen

`lib/core/species_photos.dart` führt **zwei** Tabellen, und sie
beantworten verschiedene Fragen:

- `speciesPhotos` — **ein** Bild je Art, für die Vergleichspaare. Dort
  gilt „zwei oder keines": Ein einzelnes Bild löst eine Verwechslung
  nicht auf.
- `speciesPortraits` — **ein bis drei** Bilder je Art, die Porträtreihe.
  Sie beantwortet „wie sieht die Art überhaupt aus", und dafür ist ein
  Bild zu wenig, weil Farbe und Form mit Alter und Wetter wechseln.

Eigene Fotos tragen `author: 'MacBuchi'`, `licence: 'CC BY-SA 4.0'` und
`source: 'Eigene Aufnahme'` — der Klarname des Betreibers steht
bewusst nirgends im Paket (dafür wurde 1.88.0 sogar die applicationId
umbenannt).

**Die Lizenzseite liest EINE Naht**, `allSpeciesPhotos()`. Wer eine
dritte Bildquelle anlegt, hängt sie dort ein; ein nicht genanntes
CC-BY-Bild ist ein Lizenzverstoß, und der fiele sonst niemandem auf.

**Die Obergrenze von drei heißt „best of", nicht „wer zuerst kam".**
Ein neues Bild darf ein altes verdrängen, wenn es mehr zeigt — beim
Fichtenreizker (#568) flog der Hut von oben für das Schnittbild mit
Milch und Grünen raus, weil nur das den Pilz wirklich erkennbar macht.
Jede Reihe braucht dabei die Ansicht, an der man unterscheidet: Fehlt
etwa die Unterseite, ist das die Lücke, die zuerst gefüllt wird
(Betreiber). Eine Collage aus zwei Ansichten ist erlaubt, wenn sonst ein
Detail fehlt — dann aber so zugeschnitten, dass sie bei 400 px lesbar
bleibt.

**Ein ersetztes Bild bekommt einen NEUEN Dateinamen** (`-4`, `-5` …),
nie den alten. Die große Fassung liegt unter demselben Namen auf dem
Branch `species-photos` (#537), und ausgelieferte Apps würden sonst zu
ihrem alten kleinen Bild das neue große zeigen. Die alte große Datei
bleibt auf dem Branch liegen; aus `assets/species/` fliegt die kleine.
Der Branch ist ein Wurzel-Commit: alten Baum übernehmen, neue Dateien
dazu, `git commit-tree`, dann `--force-with-lease` auf den bekannten
Stand.

Unter den Bildern steht `kPhotoDisclaimer`, einmal je Seite, und zwar
gebunden an „zeigt diese Seite irgendein Bild" — nicht an „gibt es
Porträts", sonst stünde unter den Vergleichspaaren nichts.

---

## 8. Testfallen, beide schon zugeschnappt

- **Die Detailseite hat seit der Porträtreihe ZWEI `Scrollable`.** Ein
  Test, der „das Scrollable dieser Seite" sucht, findet zwei und
  scheitert; `descendant` trifft auch das innere, waagerechte. Es
  braucht `find.byKey(kSpeciesDetailListKey)` und ausdrücklich
  `.first`. Dieselbe Falle wie beim Suchfeld (#516).
- **Eine negative Aussage über die Seite braucht einen ANKER.** Nach
  `scrollUntilVisible` steht das Ziel am oberen Rand, alles darüber ist
  nicht gebaut, und `findsNothing` ist grün, egal was dort stünde. In
  der Gegenprobe genau so gemessen. Prüfen, dass BEIDE Nachbarn im
  selben Bild stehen, dann erst auf Abwesenheit.

---

## 9. Konnektoren: einer lohnt, einer nicht

**Google Fotos: nicht einrichten.** Alle Wege (Composio, die
Community-MCP-Server) brauchen eigene Google-Cloud-OAuth-Zugangsdaten,
und Google lässt seit der Umstellung auf die Picker-API ohnehin keinen
stehenden Zugriff auf die Bibliothek mehr zu — der Nutzer wählt je
Sitzung von Hand aus. Der geteilte Link aus §1 kann alles, was hier
gebraucht wird, und braucht kein Konto.

**iNaturalist-MCP: lohnt sich, wenn die Tabellen wachsen.**
`@cyanheads/inaturalist-mcp-server` (Apache 2.0, schlüssellos,
lesend) hat genau die Werkzeuge, die unseren handgepflegten Tabellen
entsprechen:

| Werkzeug | Wofür bei uns |
|---|---|
| `inaturalist_get_similar_species` | Verwechslungspartner — „womit wird diese Art am häufigsten verwechselt" |
| `inaturalist_get_taxon` | Merkmale und Belegfotos gegenlesen |
| `inaturalist_get_histogram` | Saison — aber wir haben GBIF lokal, das ist besser belegt |

Zwei Vorbehalte, bevor jemand das als Quelle nimmt: Die Daten sind
Bürgerwissenschaft, also **Meldungen, keine geprüften Bestimmungen** —
genau der Vorbehalt, den wir bei den GBIF-Fundorten schon schreiben.
Und eine Verwechslungsbeziehung, die von dort kommt, gehört trotzdem
gegen Literatur geprüft, bevor sie in `species_lookalikes.dart` steht:
Dort hängt eine Vergiftung dran, und der Test kann nur die Pflege
prüfen, nie die Mykologie.

Installation, falls gewünscht:
`claude mcp add inaturalist -- npx -y @cyanheads/inaturalist-mcp-server`
