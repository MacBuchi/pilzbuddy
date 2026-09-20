"""SVG-Diagramme fuer die Ampel-Berichte — nur Standardbibliothek.

**Warum selbstgebaut.** In `tool/` laeuft nichts ausser der
Standardbibliothek (dieselbe Regel wie bei `feedback_bot.py` und
`rain_grid.py`); matplotlib ist hier nicht installiert und waere fuer
vier Diagrammtypen auch eine schwere Abhaengigkeit. SVG ist Text, GitHub
rendert es in Markdown, und ein Diagramm, das man im Diff lesen kann,
ist bei einer Messreihe mehr wert als eines, das man nur ansehen kann.

**Zwei Entscheidungen, die man kennen muss:**

- **Jede Flaeche bekommt einen eigenen weissen Grund.** GitHub zeigt
  Markdown hell UND dunkel; ein SVG ohne Hintergrund steht im
  Dunkelmodus mit schwarzer Schrift auf schwarzem Grund. Der weisse
  Kasten ist haesslicher als eine Themenanpassung und dafuer in beiden
  Modi lesbar.
- **Es gibt keine Interaktion und keine Tooltips.** Was man wissen muss,
  steht als Beschriftung im Bild oder in der Tabelle daneben. Ein
  Diagramm ersetzt hier keine Zahl, es ordnet sie ein.
"""

import html
import math

BREITE, HOEHE = 720, 380
RAND = {"links": 62, "rechts": 18, "oben": 44, "unten": 74}

# Die Marken-Toene der App, damit ein Bericht nicht in fremden Farben
# steht (`lib/core/app_colors.dart`).
FARBEN = {
    "fund": "#2e7d32",        # gruen: Fundtage
    "kontrolle": "#8d6e63",   # braun: Vergleichstage
    "kurve": "#1565c0",       # blau: Modellkurve
    "warn": "#c62828",        # rot: ausgelieferte Konstante
    "neben": "#ef6c00",       # orange: Alternative
    "achse": "#444444",
    "gitter": "#dddddd",
    "grund": "#ffffff",
    "text": "#222222",
    "blass": "#777777",
}


def _e(text):
    return html.escape(str(text), quote=True)


class Diagramm:
    """Ein Achsenkreuz mit Datenbereich und Pixelumrechnung."""

    def __init__(self, titel, x_von, x_bis, y_von, y_bis,
                 x_titel="", y_titel="", breite=BREITE, hoehe=HOEHE,
                 untertitel=""):
        if x_bis <= x_von or y_bis <= y_von:
            raise ValueError(f"leerer Bereich: x {x_von}..{x_bis}, "
                             f"y {y_von}..{y_bis}")
        self.titel, self.untertitel = titel, untertitel
        self.x_von, self.x_bis = float(x_von), float(x_bis)
        self.y_von, self.y_bis = float(y_von), float(y_bis)
        self.x_titel, self.y_titel = x_titel, y_titel
        self.breite, self.hoehe = breite, hoehe
        self.teile = []
        self.legende = []

    # --- Umrechnung ----------------------------------------------------
    def px(self, x):
        anteil = (x - self.x_von) / (self.x_bis - self.x_von)
        return RAND["links"] + anteil * self._plot_breite()

    def py(self, y):
        anteil = (y - self.y_von) / (self.y_bis - self.y_von)
        return self.hoehe - RAND["unten"] - anteil * self._plot_hoehe()

    def _plot_breite(self):
        return self.breite - RAND["links"] - RAND["rechts"]

    def _plot_hoehe(self):
        return self.hoehe - RAND["oben"] - RAND["unten"]

    # --- Bausteine -----------------------------------------------------
    def balken(self, mitten, werte, breite, farbe, deckkraft=0.75,
               name=None):
        """Senkrechte Balken, an ihren Mittelpunkten gesetzt."""
        for mitte, wert in zip(mitten, werte):
            if wert is None or wert <= self.y_von:
                continue
            links = self.px(mitte - breite / 2)
            rechts = self.px(mitte + breite / 2)
            oben = self.py(min(wert, self.y_bis))
            unten = self.py(self.y_von)
            self.teile.append(
                f'<rect x="{links:.1f}" y="{oben:.1f}" '
                f'width="{max(0.6, rechts - links):.1f}" '
                f'height="{max(0.0, unten - oben):.1f}" fill="{farbe}" '
                f'fill-opacity="{deckkraft}"/>')
        if name:
            self.legende.append((name, farbe, "flaeche"))

    def linie(self, punkte, farbe, dicke=2.2, name=None, gestrichelt=False):
        punkte = [(x, y) for x, y in punkte if y is not None]
        if len(punkte) < 2:
            return
        d = " ".join(
            ("M" if i == 0 else "L") + f"{self.px(x):.1f},{self.py(y):.1f}"
            for i, (x, y) in enumerate(punkte))
        strich = ' stroke-dasharray="6 4"' if gestrichelt else ""
        self.teile.append(
            f'<path d="{d}" fill="none" stroke="{farbe}" '
            f'stroke-width="{dicke}" stroke-linejoin="round"{strich}/>')
        if name:
            self.legende.append((name, farbe, "linie"))

    @staticmethod
    def zahl(wert, stellen=2):
        """Deutsche Schreibweise — fuer Beschriftungen der Aufrufer.

        Sie stand bisher nur an der Achse; die Marken kamen aus
        f-Strings der Aufrufer und schrieben „17.5 °C" mitten ins Bild.
        """
        text = f"{wert:.{stellen}f}".rstrip("0").rstrip(".")
        return (text or "0").replace(".", ",")

    def senkrechte(self, x, farbe, beschriftung=None, oben=True):
        if not self.x_von <= x <= self.x_bis:
            return
        px = self.px(x)
        self.teile.append(
            f'<line x1="{px:.1f}" y1="{self.py(self.y_von):.1f}" '
            f'x2="{px:.1f}" y2="{RAND["oben"]:.1f}" stroke="{farbe}" '
            f'stroke-width="1.8" stroke-dasharray="5 3"/>')
        if beschriftung:
            y = RAND["oben"] + (12 if oben else 26)
            anker = "start" if px < self.breite / 2 else "end"
            versatz = 5 if anker == "start" else -5
            self.teile.append(
                f'<text x="{px + versatz:.1f}" y="{y}" font-size="11" '
                f'fill="{farbe}" text-anchor="{anker}">'
                f'{_e(beschriftung)}</text>')

    def flaeche_x(self, von, bis, farbe, deckkraft=0.12, name=None):
        """Ein senkrechter Streifen — fuer Plateaus und Bereiche."""
        links, rechts = self.px(max(von, self.x_von)), self.px(min(bis, self.x_bis))
        if rechts <= links:
            return
        self.teile.append(
            f'<rect x="{links:.1f}" y="{RAND["oben"]:.1f}" '
            f'width="{rechts - links:.1f}" '
            f'height="{self._plot_hoehe():.1f}" fill="{farbe}" '
            f'fill-opacity="{deckkraft}"/>')
        if name:
            self.legende.append((name, farbe, "flaeche"))

    # --- Rahmen --------------------------------------------------------
    def _ticks(self, von, bis, ziel=6):
        """Runde Stuetzstellen — Schrittweite aus 1, 2, 2,5 oder 5."""
        spanne = bis - von
        roh = spanne / max(1, ziel)
        stufe = 10 ** math.floor(math.log10(roh)) if roh > 0 else 1
        for faktor in (1, 2, 2.5, 5, 10):
            if stufe * faktor >= roh:
                schritt = stufe * faktor
                break
        else:
            schritt = stufe * 10
        start = math.ceil(von / schritt) * schritt
        werte, x = [], start
        while x <= bis + 1e-9:
            werte.append(round(x, 10))
            x += schritt
        return werte

    def _zahl(self, wert):
        if abs(wert - round(wert)) < 1e-9:
            return f"{int(round(wert))}"
        return f"{wert:.2f}".rstrip("0").rstrip(".").replace(".", ",")

    def _rahmen(self, x_beschriftung=None):
        aus = []
        for y in self._ticks(self.y_von, self.y_bis):
            py = self.py(y)
            aus.append(f'<line x1="{RAND["links"]}" y1="{py:.1f}" '
                       f'x2="{self.breite - RAND["rechts"]}" y2="{py:.1f}" '
                       f'stroke="{FARBEN["gitter"]}" stroke-width="1"/>')
            aus.append(f'<text x="{RAND["links"] - 8}" y="{py + 4:.1f}" '
                       f'font-size="11" fill="{FARBEN["blass"]}" '
                       f'text-anchor="end">{_e(self._zahl(y))}</text>')
        marken = (x_beschriftung if x_beschriftung is not None
                  else [(x, self._zahl(x))
                        for x in self._ticks(self.x_von, self.x_bis)])
        for x, text in marken:
            px = self.px(x)
            aus.append(f'<text x="{px:.1f}" '
                       f'y="{self.hoehe - RAND["unten"] + 17}" '
                       f'font-size="11" fill="{FARBEN["blass"]}" '
                       f'text-anchor="middle">{_e(text)}</text>')
        aus.append(f'<line x1="{RAND["links"]}" '
                   f'y1="{self.hoehe - RAND["unten"]}" '
                   f'x2="{self.breite - RAND["rechts"]}" '
                   f'y2="{self.hoehe - RAND["unten"]}" '
                   f'stroke="{FARBEN["achse"]}" stroke-width="1.4"/>')
        return aus

    def _legende(self):
        if not self.legende:
            return []
        aus, x = [], RAND["links"]
        y = self.hoehe - 12
        for name, farbe, art in self.legende:
            if art == "linie":
                aus.append(f'<line x1="{x}" y1="{y - 4}" x2="{x + 16}" '
                           f'y2="{y - 4}" stroke="{farbe}" '
                           f'stroke-width="2.4"/>')
            else:
                aus.append(f'<rect x="{x}" y="{y - 9}" width="16" '
                           f'height="10" fill="{farbe}" '
                           f'fill-opacity="0.75"/>')
            aus.append(f'<text x="{x + 21}" y="{y}" font-size="11" '
                       f'fill="{FARBEN["text"]}">{_e(name)}</text>')
            x += 26 + 6.6 * len(name)
        return aus

    def svg(self, x_beschriftung=None):
        kopf = [
            f'<svg xmlns="http://www.w3.org/2000/svg" '
            f'viewBox="0 0 {self.breite} {self.hoehe}" '
            f'width="{self.breite}" height="{self.hoehe}" '
            f'font-family="system-ui, -apple-system, Segoe UI, sans-serif">',
            f'<rect width="{self.breite}" height="{self.hoehe}" '
            f'fill="{FARBEN["grund"]}"/>',
            f'<text x="{RAND["links"]}" y="22" font-size="14" '
            f'font-weight="600" fill="{FARBEN["text"]}">'
            f'{_e(self.titel)}</text>',
        ]
        if self.untertitel:
            kopf.append(
                f'<text x="{RAND["links"]}" y="38" font-size="11" '
                f'fill="{FARBEN["blass"]}">{_e(self.untertitel)}</text>')
        if self.y_titel:
            mitte = RAND["oben"] + self._plot_hoehe() / 2
            kopf.append(
                f'<text x="14" y="{mitte:.1f}" font-size="11" '
                f'fill="{FARBEN["blass"]}" text-anchor="middle" '
                f'transform="rotate(-90 14 {mitte:.1f})">'
                f'{_e(self.y_titel)}</text>')
        if self.x_titel:
            kopf.append(
                f'<text x="{RAND["links"] + self._plot_breite() / 2:.1f}" '
                f'y="{self.hoehe - RAND["unten"] + 36}" font-size="11" '
                f'fill="{FARBEN["blass"]}" text-anchor="middle">'
                f'{_e(self.x_titel)}</text>')
        return "\n".join(kopf + self._rahmen(x_beschriftung) + self.teile
                         + self._legende() + ["</svg>"]) + "\n"


def histogramm(werte, von, bis, stufen):
    """Anteile je Klasse — nicht Anzahlen.

    **Anteile, damit zwei Reihen verschiedener Groesse vergleichbar
    sind.** Fundtage und Vergleichstage stehen im Verhaeltnis 1:5; als
    Anzahlen uebereinandergelegt sagte das Bild vor allem, dass es
    fuenfmal so viele Vergleichstage gibt.
    """
    if not werte:
        return [], []
    weite = (bis - von) / stufen
    zaehler = [0] * stufen
    drin = 0
    for wert in werte:
        if wert is None or not von <= wert <= bis:
            continue
        i = min(stufen - 1, int((wert - von) / weite))
        zaehler[i] += 1
        drin += 1
    mitten = [von + (i + 0.5) * weite for i in range(stufen)]
    anteile = [z / drin if drin else 0.0 for z in zaehler]
    return mitten, anteile


def self_test():
    d = Diagramm("T", 0, 10, 0, 1, breite=200, hoehe=100)
    assert abs(d.px(0) - RAND["links"]) < 1e-9
    assert abs(d.px(10) - (200 - RAND["rechts"])) < 1e-9
    assert abs(d.py(0) - (100 - RAND["unten"])) < 1e-9
    assert abs(d.py(1) - RAND["oben"]) < 1e-9
    # Die Mitte liegt in der Mitte — sonst stimmt keine Kurve.
    assert abs(d.px(5) - (d.px(0) + d.px(10)) / 2) < 1e-9

    try:
        Diagramm("leer", 0, 0, 0, 1)
        raise AssertionError("leerer Bereich geht durch")
    except ValueError:
        pass

    # **Der weisse Grund ist Pflicht** (Dunkelmodus auf GitHub).
    svg = d.svg()
    assert svg.startswith("<svg") and svg.rstrip().endswith("</svg>")
    assert f'fill="{FARBEN["grund"]}"' in svg

    # Beschriftungen werden maskiert — ein Artname mit `&` darf das
    # Bild nicht zerlegen.
    boese = Diagramm("Steinpilz & Co. <b>", 0, 1, 0, 1)
    assert "&amp;" in boese.svg() and "<b>" not in boese.svg()

    # Werte ausserhalb des Bereichs werden geklemmt, nicht gezeichnet.
    d2 = Diagramm("T", 0, 10, 0, 1)
    d2.balken([5], [None], 1, "#000")
    d2.balken([5], [0.0], 1, "#000")
    assert "<rect" not in "".join(d2.teile), d2.teile
    d2.linie([(0, 0.5)], "#000")
    assert not d2.teile, "eine einzelne Stuetzstelle ist keine Linie"
    d2.senkrechte(99, "#000", "draussen")
    assert not d2.teile, "eine Marke ausserhalb des Bereichs wird gezeichnet"

    # Das Histogramm gibt ANTEILE zurueck, die sich zu 1 summieren.
    mitten, anteile = histogramm([1, 1, 2, 9], 0, 10, 10)
    assert len(mitten) == 10 and abs(sum(anteile) - 1.0) < 1e-12
    assert abs(anteile[1] - 0.5) < 1e-12, anteile
    # Werte ausserhalb zaehlen NICHT mit — sonst summierte sich der
    # gezeigte Teil auf weniger als 1, ohne dass es auffiele.
    m2, a2 = histogramm([1, 1, 2, 9, 99, -5], 0, 10, 10)
    assert abs(sum(a2) - 1.0) < 1e-12 and a2 == anteile, a2
    assert histogramm([], 0, 1, 4) == ([], [])

    # Runde Stuetzstellen, und der Bereich ist abgedeckt.
    t = d._ticks(0, 1)
    assert t[0] >= 0 and t[-1] <= 1 and len(t) >= 3, t
    assert d._zahl(0.5) == "0,5" and d._zahl(13.0) == "13"
    # **Auch die Beschriftungen der Aufrufer, nicht nur die Achse.**
    # „17.5 °C" stand mitten im Bild, waehrend die Achse daneben
    # deutsche Kommata schrieb.
    assert Diagramm.zahl(17.5) == "17,5" and Diagramm.zahl(13.0) == "13"
    assert Diagramm.zahl(0.0) == "0" and Diagramm.zahl(15.0, 2) == "15"
    beschriftet = Diagramm("T", 0, 20, 0, 1)
    beschriftet.senkrechte(17.5, "#000", f"{Diagramm.zahl(17.5)} °C")
    assert "17,5 °C" in "".join(beschriftet.teile)
    assert "17.5" not in "".join(beschriftet.teile)
    print("Selbsttest ok")


if __name__ == "__main__":
    import sys
    if "--self-test" in sys.argv:
        self_test()
