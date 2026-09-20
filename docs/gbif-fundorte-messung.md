# Trägt eine Heatmap der GBIF-Fundorte?

Vormessung zu Issue #467, gemessen am 2026-09-16. **Ergebnis: ja, aber
erst ab 10–20 km Zellgröße** — und damit nicht als die Karte, nach der
gefragt war.

Gemessen auf **ganz DACH**: 3 782 038 Pilzmeldungen als lokale Datenbank
(`tool/gbif_download.py`, GBIF-Download `10.15468/dl.dwbsuf`), davon
2 012 515 verwertbare Sichtungen. Die beiden Einzelregionen weiter unten
stehen daneben, weil sie den Unterschied zwischen gut und dünn beprobt
zeigen — der ist für das Feature wichtiger als jeder Mittelwert.

Werkzeug: `tool/gbif_effort.py` — `dach`, `harz` oder `obb`. Der
DACH-Lauf geht nur über die lokale Datenbank (`tool/gbif_download.py`);
über die Such-API wären das 12 600 Seiten. Die Regionsläufe können
beides.
Der Netzweg ist gekachelt, weil tiefes Blättern bei GBIF nicht
scheitert, sondern kriecht: Ab `offset` ~10 000 braucht dieselbe Seite
**341 s statt 0,3 s** und liefert danach ihre 300 Treffer — von außen
ununterscheidbar von einem Hänger. Genau deshalb gibt es überhaupt den
Download-Weg; eine Regionsabfrage aus der Datenbank dauert jetzt **6 ms**. Zwei Regionen, bewusst ungleich beprobt:

| Gebiet | Fungi-Sichtungen (CC0/CC-BY) |
|---|--:|
| **DACH gesamt** | **2 012 515** |
| Harz / Südniedersachsen | 11 999 |
| Oberbayern / Alpenvorland | 3 729 |

„Zielarten" sind die 91 Arten aus `mushroom_species.dart` mit `sci`-Name;
Gattungseinträge (`Leccinum`, `Armillaria`) treffen über `genus`.

## 1. Die Effort-Falle ist real — und die Korrektur behebt sie

Dieselbe Falle wie zeitlich bei den Saisonkurven, wo sie längst
korrigiert wird („DIE EFFORT-KORREKTUR IST DER GANZE PUNKT",
`tool/season_curves.py`). Räumlich, Harz, 5-km-Zellen, nur Zellen mit
≥ 30 Meldungen (86 Stück):

| | DACH | Harz | Oberbayern |
|---|--:|--:|--:|
| **rohe** Heatmap (Zielarten je Zelle) | **+0,67** | **+0,64** | **+0,53** |
| **korrigierte** (Anteil Zielarten) | −0,07 | −0,21 | −0,08 |

Die Rohkarte misst zu gut zwei Dritteln, **wo gemeldet wird**. Ein
Beispiel aus derselben Tabelle: Die Zelle mit der höchsten Rohzahl (204
Zielarten-Meldungen) hat einen Anteil von 0,18 — bei einem Mittel von
0,19 also exakt Durchschnitt. Als Heatmap-Hotspot wäre sie eine Lüge
über eine gewöhnliche Zelle, in der nur viel gemeldet wird.

Roh und korrigiert sind auch nicht dasselbe Bild: Spearman +0,53, die
Reihenfolge ändert sich erheblich.

## 2. Nach der Korrektur bleibt Struktur

Nullhypothese: Der Zielarten-Anteil ist überall gleich, Abweichungen
sind Stichprobenrauschen.

| Schnitt | Zellen | χ²/df |
|---|--:|--:|
| **DACH, 5 km, ≥ 30 Meldungen** | **5 547** | **26,5** |
| Harz, 5 km, ≥ 30 Meldungen | 86 | 8,2 |
| Oberbayern, 5 km, ≥ 30 Meldungen | 26 | 10,5 |

χ²/df = 1,0 wäre reines Rauschen. Die Streuung ist acht- bis
fünfzehnfach größer als der Zufall erlaubt — wo Daten liegen, sagt die
korrigierte Karte etwas.

## 3. Der Störfaktor, der fast alles gekostet hätte: die Melder

**DACH-weit stammen in der typischen 5-km-Zelle 88 % aller Meldungen von
einer einzigen Person** (Median; im Harz sind es 69 %, in Oberbayern
79 %). Der Anteil einer Zelle kann also schlicht die Vorliebe eines
Melders sein: Wer nur Speisepilze meldet, erzeugt einen Hotspot, wer
alles kartiert, ein Loch. Dass das kein theoretischer Einwand ist,
zeigen die fünf größten Melder der Harz-Region — Zielarten-Anteile von
**0,11 bis 0,27** bei einem Regionsmittel von 0,19. Der größte (3339
Meldungen) liegt mit 0,11 weit darunter: ein systematischer Kartierer,
kein Sammler.

Gegenprobe: jeder Melder mit ≥ 5 Meldungen bekommt **eine Stimme** je
Zelle, gemittelt statt gezählt.

| Schnitt | ungewichtet | melder-gemittelt |
|---|--:|--:|
| DACH, 5 km | 0,04 … 0,32 (8,6×) | 0,04 … 0,33 (**8,6×**) |
| Harz, 5 km | 0,06 … 0,37 (6,2×) | 0,12 … 0,36 (**3,0×**) |
| Harz, 10 km | 0,13 … 0,32 (2,4×) | 0,15 … 0,38 (2,5×) |

**Die Gewichtung ändert DACH-weit nichts — und das ist keine
Entwarnung, sondern eine Aussage über den Schnitt.** In die Statistik
kommen nur Zellen mit mindestens drei Meldern; wo die Melder-Vorliebe
durchschlägt, ist diese Bedingung meist gar nicht erfüllt. Die
Melder-Regel wirkt also vor allem als **Filter**, welche Zellen
überhaupt etwas sagen dürfen, und erst nachrangig als Gewicht. Im Harz,
wo mehr Zellen knapp über die Schwelle kommen, sieht man den
Gewichtungseffekt dann doch (6,2× → 3,0×).

Praktische Folge: Die Schwelle ist nicht verhandelbar. Ohne sie wandern
genau die Zellen in die Karte, deren Wert eine einzelne Person bestimmt.

## 4. Und das eigentliche Problem: die Abdeckung

Anteil der Regionsfläche, für die eine Zelle ≥ 30 Meldungen von ≥ 3
verschiedenen Meldern hat — also überhaupt eine belastbare Aussage:

| Zellgröße | DACH (Anteil Landfläche) | Harz | Oberbayern |
|---|--:|--:|--:|
| 2,5 km | **2 %** (8 594 km²) | 2 % | 0 % |
| 5 km | **9 %** (45 475 km²) | 14 % | 1 % |
| 10 km | **34 %** (165 700 km²) | 53 % | 12 % |
| 20 km | **76 %** (367 600 km²) | 95 % | 60 % |

Bezug ist die Landfläche von DE + AT + CH (482 800 km²).

Das ist der Tausch, und er ist hart: **Bei der Auflösung, die einem
Sammler nützt, hat die Karte fast nirgends etwas zu sagen.** Bei der
Auflösung, bei der sie flächig wird, sagt sie „irgendwo in diesem
Landkreis".

Der Vergleich der beiden Regionen ist dabei die wichtigere Zahl als
jede einzelne: Dieselbe Zellgröße liefert 53 % gegen 12 %. Die
Abdeckung hängt nicht am Wald, sondern daran, ob dort jemand meldet —
und ausgerechnet das Alpenvorland, wo viel gesammelt wird, ist dünn.

## Was daraus folgt

- **Eine flächige Heatmap in Sammler-Auflösung (≤ 5 km) ist nicht
  drin.** Sie wäre auf 91–98 % der DACH-Landfläche leer, und „leer" sähe aus wie
  „hier wächst nichts" — genau der Fehler, den `artenkarte-konzept.md`
  für die Wald-Ebene schon einmal vermeiden musste.
- **Bei 10–20 km ist sie ehrlich**, aber ihre Aussage ist grob: eine
  Gegend, kein Ort. Ob das ein Feature trägt, ist eine
  Produktentscheidung, keine Messung.
- **Wenn sie gebaut wird, dann mit beiden Korrekturen** — Effort UND
  Melder. Wo die zweite das Bild noch verändert, ist die Zelle zu dünn
  besetzt; sie ist damit zugleich die Korrektur und der Prüfstein.
- **Zellen ohne Basis müssen „keine Aussage" sein**, optisch
  unterscheidbar von „wenig". Das ist bei dieser Abdeckung die Mehrheit
  der Fläche und damit der Normalfall, nicht der Randfall.

## Was die Daten stattdessen tragen

Die Abdeckungsgrenze trifft die **Fläche**, nicht die Punkte. Zwei
Verwendungen derselben Daten kommen ohne Flächendeckung aus:

1. **Eine Artenliste je Umkreis** („im Umkreis von 10 km gemeldet:
   Steinpilz 45×, Pfifferling 12×"). Sie braucht keine Nachbarzelle und
   wird mit jeder Meldung besser statt gröber.
2. **Die Validierung der Artenkarte aus #414.** `artenkarte-konzept.md`
   sieht dafür bereits GBIF-Koordinaten vor: Liegen echte Fundmeldungen
   häufiger in Waben mit hoher Eignung als in zufälligen Waben derselben
   Region und desselben Monats? Dafür ist die Melder-Schieflage
   verkraftbar, weil beide Seiten des Vergleichs sie tragen.

## Nachtrag 2026-09-21 — was gebaut wurde (1.154.0)

Der Betreiber hat entschieden: **gebaut, aber als Meldungen, nicht als
Heatmap.** Die Ebene „Gemeldete Fundorte" zeichnet je Meldung einer
unserer Arten EINE Scheibe in der Größe ihrer Koordinaten-Unschärfe —
das ist die Aussage, die die Daten Zeile für Zeile tragen, und die
Flächendeckung spielt dabei keine Rolle. Dazu die Umkreis-Liste in
„Was ist hier?" (Verwendung 1 von oben). Werkzeug `tool/gbif_finds.py`,
Asset `assets/gbif/`.

Dabei kam eine Verteilung heraus, die in diesem Bericht bis dahin
fehlte und die Karte prägt — **die drei Länder melden grundverschieden**
(nur Sichtungen, CC0/CC BY, unsere 91 Arten):

| Unschärfe | DE | AT | CH |
|---|--:|--:|--:|
| ≤ 250 m | **69 974** | 1 800 | 1 639 |
| 250 m – 1 km | 380 | 596 | 40 |
| genau 3 535 m | 441 | 76 | **116 316** |
| sonst ≤ 10 km | 468 | 155 | 1 143 |
| ohne Angabe | 3 197 | **96 044** (auf 8 565 Koordinaten) | 234 |
| > 10 km (verworfen) | 808 | 147 | 33 |

Deutschland sind Punkte (naturgucker, iNaturalist, ArtenFinder), die
Schweiz sind Kilometerquadrate (SwissFungi meldet 3535 m — die halbe
Diagonale von 5 km), Österreich sind Rasterpunkte der ÖMG ohne
Unschärfe-Angabe, elf Meldungen je Koordinate. Der frühere Satz im
Issue, die Quadrant-Mittelpunkte seien „die deutschen Kartierer", war
falsch; die deutschen Kartierungsdaten stehen bei GBIF überwiegend
unter CC BY-NC und bleiben deshalb draußen.

Folgen für den Bau: unbekannte Unschärfe wird als 3535 m gezeichnet
(die größere Scheibe ist die harmlose Fehlerrichtung), über 10 km
fliegt raus, scharf und grob tragen verschiedene Deckkraft, und die
Ebene sagt in ihrem Blatt, dass ein Punkt in Deutschland, ein Quadrat
in der Schweiz und ein Rasterpunkt in Österreich dieselbe Sache
sind: eine Meldung.
