# Trägt eine Heatmap der GBIF-Fundorte?

Vormessung zu Issue #467, gemessen am 2026-09-16. **Ergebnis: ja, aber
erst ab 10–20 km Zellgröße** — und damit nicht als die Karte, nach der
gefragt war.

Werkzeug: `tool/gbif_effort.py` (Download, gekachelt und festgenagelt).
Gekachelt, weil tiefes Blättern bei GBIF nicht scheitert, sondern
kriecht: Ab `offset` ~10 000 braucht dieselbe Seite **341 s statt
0,3 s** und liefert danach ihre 300 Treffer — von außen ununterscheidbar
von einem Hänger. Zwei Regionen, bewusst ungleich beprobt:

| Region | Bbox | Fungi-Sichtungen (CC0/CC-BY) |
|---|---|---|
| Harz / Südniedersachsen | 51,5–52,2 N, 9,8–11,0 O | 11 999 |
| Oberbayern / Alpenvorland | 47,6–48,5 N, 11,0–12,3 O | 3 729 |

„Zielarten" sind die 91 Arten aus `mushroom_species.dart` mit `sci`-Name;
Gattungseinträge (`Leccinum`, `Armillaria`) treffen über `genus`.

## 1. Die Effort-Falle ist real — und die Korrektur behebt sie

Dieselbe Falle wie zeitlich bei den Saisonkurven, wo sie längst
korrigiert wird („DIE EFFORT-KORREKTUR IST DER GANZE PUNKT",
`tool/season_curves.py`). Räumlich, Harz, 5-km-Zellen, nur Zellen mit
≥ 30 Meldungen (86 Stück):

| | Harz | Oberbayern |
|---|--:|--:|
| **rohe** Heatmap (Zielarten je Zelle) | **+0,64** | **+0,53** |
| **korrigierte** (Anteil Zielarten) | −0,21 | −0,08 |

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
| Harz, 5 km, ≥ 30 Meldungen | 86 | **8,2** |
| Oberbayern, 5 km, ≥ 30 Meldungen | 26 | **10,5** |

χ²/df = 1,0 wäre reines Rauschen. Die Streuung ist acht- bis
fünfzehnfach größer als der Zufall erlaubt — wo Daten liegen, sagt die
korrigierte Karte etwas.

## 3. Der Störfaktor, der fast alles gekostet hätte: die Melder

**In der typischen Zelle stammen 69 % aller Meldungen von einer einzigen
Person** (Median über 86 Zellen; im 90. Perzentil 97 %). Der Anteil einer
Zelle kann also schlicht die Vorliebe eines Melders sein — wer nur
Speisepilze meldet, erzeugt einen Hotspot, wer alles kartiert, ein Loch.
Dass das kein theoretischer Einwand ist, zeigen die fünf größten Melder
der Harz-Region: Zielarten-Anteile von **0,11 bis 0,27** bei einem
Regionsmittel von 0,19. Der größte (3339 Meldungen) liegt mit 0,11 weit
darunter — das ist ein systematischer Kartierer, kein Sammler.

Gegenprobe: jeder Melder mit ≥ 5 Meldungen bekommt **eine Stimme** je
Zelle, gemittelt statt gezählt. Die Spannweite der Zellwerte (10.–90.
Perzentil), auf 10-km-Zellen:

| | ungewichtet | melder-gemittelt |
|---|--:|--:|
| Harz | 0,13 … 0,32 (2,4×) | 0,15 … 0,38 (**2,5×**) |
| Oberbayern | 0,10 … 0,36 (3,6×) | 0,12 … 0,24 (**2,0×**) |

**Der Melder-Effekt hängt an der Zellgröße, und das ist die gute
Nachricht.** Auf 5-km-Zellen im Harz schrumpfte die Spannweite von 6,2×
auf 3,0× — dort trug tatsächlich rund die Hälfte des Signals die
Melder-Vorliebe. Auf 10 km, wo genug Melder je Zelle zusammenkommen,
ändert die Mittelung im Harz **nichts mehr** (2,4× gegen 2,5×). In der
dünn beprobten Region bleibt sie nötig: Oberbayern verliert auch bei
10 km noch die Hälfte.

Das heißt: Die Korrektur ist kein Ersatz für Datendichte, sondern ein
Anzeiger dafür. Wo sie das Bild stark verändert, war zu wenig da.

## 4. Und das eigentliche Problem: die Abdeckung

Anteil der Regionsfläche, für die eine Zelle ≥ 30 Meldungen von ≥ 3
verschiedenen Meldern hat — also überhaupt eine belastbare Aussage:

| Zellgröße | Harz | Oberbayern |
|---|--:|--:|
| 2,5 km | **2 %** | **0 %** |
| 5 km | 14 % | 1 % |
| 10 km | 53 % | 12 % |
| 20 km | 95 % | 60 % |

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
  drin.** Sie wäre auf 88–99 % der Fläche leer, und „leer" sähe aus wie
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
