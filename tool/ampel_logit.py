"""Bedingte logistische Regression ohne numpy.

    python3 tool/ampel_logit.py --self-test        # netzfrei

**Wozu.** Unsere Optima und Breiten kamen bisher aus einem Gitter
(`FIT_GRID_STEP_C = 0.5`). Ein Gitterpunkt sieht praezise aus und sagt
nichts darueber, wie flach die Likelihood um ihn herum liegt — genau
das war der Befund aus Phase 0.4, wo angepasste Optima beim Wechsel des
Instruments um bis zu 3 K wanderten. Ein Logit liefert dieselbe Groesse
**mit Standardfehler**; eine flache Likelihood wird damit sichtbar,
statt sich zu tarnen.

**Das Modell.** Ein Stratum ist ein Fundtag mit seinen Kontrolltagen
(Design B: einer gegen fuenf). Ort, Jahr und Jahreszeit kuerzen sich
heraus, es gibt keinen Achsenabschnitt:

    P(der Fundtag ist Nummer i | Stratum) = exp(b·x_i) / Σ_j exp(b·x_j)

Mit den Merkmalen `[log F, T, T²]` haengt das direkt an der Formel der
Ampel. Denn `log(F · exp(−((T−opt)/σ)²))` ist

    log F − T²/σ² + 2·opt·T/σ² − opt²/σ²

und der letzte Summand ist je Stratum konstant, faellt also heraus.
Also `b_T = 2·opt/σ²` und `b_T² = −1/σ²`, und daraus

    Optimum = −b_T / (2 b_T²)        Breite = sqrt( b_logF / −b_T² )

**Beide Groessen sind massstabsfrei, und hier stand erst das
Gegenteil.** Der Kommentar behauptete, die Breite sei nur bei `b_logF`
nahe 1 mit dem sigma der Ampel vergleichbar. Das ist falsch: Skaliert
man alle Koeffizienten mit demselben Faktor c, so kuerzt er sich in
`−b_T/(2 b_T²)` und in `sqrt(b_logF / −b_T²)` heraus. Die Breite ist
damit unmittelbar das sigma, das zu einem Einheitsgewicht auf `log F`
gehoert — also genau das, was die Ampel rechnet.

Was `b_logF` stattdessen sagt: **wie scharf die Wahl ueberhaupt ist.**
Es ist der gemeinsame Faktor vor dem ganzen Nutzen; ein kleiner Wert
heisst viel Rauschen, nicht ein anderes Gewicht. Bei AUC-Werten um 0,6
gehoert ein kleines `b_logF` zum Bild. `bell_from_beta` gibt es mit
zurueck, weil es die Schaerfe beziffert — nicht, weil die Breite ohne
es unlesbar waere.

Nur Standardbibliothek, wie jedes Werkzeug in `tool/`.
"""
import argparse
import math
import random
import sys


# --- Lineare Algebra, so viel wie noetig -----------------------------------


def solve(matrix, vector):
    """Loest `matrix · x = vector` mit Gauss und Teilpivotisierung.

    Teilpivotisierung ist hier kein Schmuck: Die Hesse-Matrix eines
    Logits mit `[log F, T, T²]` traegt Spalten sehr verschiedener
    Groessenordnung (T² geht bis ~400), und ohne Pivotsuche frisst die
    Ausloeschung die kleinen Eintraege auf.
    """
    n = len(matrix)
    a = [list(zeile) + [wert] for zeile, wert in zip(matrix, vector)]
    for spalte in range(n):
        pivot = max(range(spalte, n), key=lambda r: abs(a[r][spalte]))
        if abs(a[pivot][spalte]) < 1e-300:
            raise ValueError("singulaere Matrix")
        a[spalte], a[pivot] = a[pivot], a[spalte]
        teiler = a[spalte][spalte]
        for zeile in range(spalte + 1, n):
            faktor = a[zeile][spalte] / teiler
            if faktor:
                for k in range(spalte, n + 1):
                    a[zeile][k] -= faktor * a[spalte][k]
    x = [0.0] * n
    for spalte in reversed(range(n)):
        rest = a[spalte][n] - sum(a[spalte][k] * x[k]
                                  for k in range(spalte + 1, n))
        x[spalte] = rest / a[spalte][spalte]
    return x


def inverse(matrix):
    """Die Inverse, spaltenweise ueber `solve` — fuer die Kovarianz."""
    n = len(matrix)
    spalten = []
    for i in range(n):
        einheit = [1.0 if j == i else 0.0 for j in range(n)]
        spalten.append(solve(matrix, einheit))
    return [[spalten[j][i] for j in range(n)] for i in range(n)]


# --- Das Logit -------------------------------------------------------------


def fit_conditional_logit(strata, l2=1e-6, max_iter=100, tol=1e-10):
    """Bedingtes Logit fuer 1:k-Strata. Newton-Raphson.

    `strata` ist eine Liste von `(fall, [kontrolle, …])`, jedes davon ein
    Merkmalsvektor gleicher Laenge. Zurueck kommen Koeffizienten,
    Standardfehler, Kovarianz, Log-Likelihood und ob es konvergiert ist.

    **`l2` ist eine Ridge-Spur und kein Modellbestandteil.** Sie haelt
    die Hesse-Matrix invertierbar, wenn eine Spalte in allen Strata
    konstant ist (dann traegt sie nichts und waere singulaer). Sie ist
    absichtlich winzig; wer sie hochdreht, zieht die Koeffizienten zur
    Null und macht den Standardfehler zu klein.

    **Nicht konvergiert heisst nicht „ungefaehr richtig".** Das Feld
    `konvergiert` gehoert in jeden Bericht, der eine dieser Zahlen
    zeigt.
    """
    if not strata:
        return None
    dim = len(strata[0][0])
    beta = [0.0] * dim
    loglik = konvergiert = None
    schritte = 0
    for schritte in range(1, max_iter + 1):
        grad = [0.0] * dim
        hess = [[0.0] * dim for _ in range(dim)]
        loglik = 0.0
        for fall, kontrollen in strata:
            reihen = [fall] + list(kontrollen)
            roh = [sum(b * x for b, x in zip(beta, reihe)) for reihe in reihen]
            groesster = max(roh)
            gewichte = [math.exp(z - groesster) for z in roh]
            summe = sum(gewichte)
            p = [g / summe for g in gewichte]
            loglik += roh[0] - (groesster + math.log(summe))
            mittel = [sum(p[i] * reihen[i][d] for i in range(len(reihen)))
                      for d in range(dim)]
            for d in range(dim):
                grad[d] += fall[d] - mittel[d]
            for i in range(len(reihen)):
                for d in range(dim):
                    abweichung = reihen[i][d] - mittel[d]
                    for e in range(d, dim):
                        wert = p[i] * abweichung * (reihen[i][e] - mittel[e])
                        hess[d][e] += wert
                        if e != d:
                            hess[e][d] += wert
        for d in range(dim):
            grad[d] -= l2 * beta[d]
            hess[d][d] += l2
        loglik -= 0.5 * l2 * sum(b * b for b in beta)
        schritt = solve(hess, grad)
        beta = [b + s for b, s in zip(beta, schritt)]
        if max(abs(s) for s in schritt) < tol:
            konvergiert = True
            break
    else:
        konvergiert = False
    kov = inverse(hess)
    return {
        "beta": beta,
        "se": [math.sqrt(kov[d][d]) if kov[d][d] > 0 else float("nan")
               for d in range(dim)],
        "kovarianz": kov,
        "loglik": loglik,
        "strata": len(strata),
        "schritte": schritte,
        "konvergiert": konvergiert,
    }


def bell_from_beta(beta, kovarianz):
    """Optimum und Breite aus `[log F, T, T²]`, mit Standardfehler.

    Beide Groessen sind massstabsfrei (siehe Modulkopf): Ein gemeinsamer
    Faktor vor allen Koeffizienten kuerzt sich heraus. Die Breite ist
    deshalb unmittelbar mit dem sigma der Ampel vergleichbar.

    Delta-Methode. Sie unterstellt, dass die Umformung im Bereich eines
    Standardfehlers ungefaehr gerade ist — bei einer flachen Likelihood
    (b_T² nahe null) ist sie das nicht, und der Fehler wird dann eher
    zu klein als zu gross geschaetzt. Deshalb steht `b_T²` samt seinem
    eigenen Standardfehler mit im Ergebnis: Wer sehen will, ob die Zahl
    traegt, sieht dort zuerst hin.
    """
    b_f, b_t, b_t2 = beta
    if b_t2 >= 0:
        # Eine nach OBEN geoeffnete Parabel ist keine Glocke — dann gibt
        # es kein Optimum, sondern ein Minimum. Das ist ein Ergebnis und
        # kein Fehler; es darf nur nicht als Optimum ausgegeben werden.
        return {"optimum": None, "breite": None, "b_t2": b_t2,
                "se_b_t2": math.sqrt(kovarianz[2][2]),
                "grund": "b_T² ist nicht negativ — keine Glocke"}
    optimum = -b_t / (2 * b_t2)
    # d(optimum)/d(b_T, b_T²); log F kommt darin nicht vor.
    g_opt = [0.0, -1 / (2 * b_t2), b_t / (2 * b_t2 * b_t2)]
    var_opt = sum(g_opt[i] * kovarianz[i][j] * g_opt[j]
                  for i in range(3) for j in range(3))
    ergebnis = {"optimum": optimum,
                "se_optimum": math.sqrt(var_opt) if var_opt > 0 else None,
                "b_t2": b_t2, "se_b_t2": math.sqrt(kovarianz[2][2]),
                "b_logf": b_f, "se_b_logf": math.sqrt(kovarianz[0][0]),
                "grund": None}
    if b_f <= 0:
        # Negatives Feuchtegewicht heisst: mehr Regen ist schlechter.
        # Dann hat `sqrt(b_logF / −b_T²)` keine Wurzel, und eine Breite
        # auszugeben waere eine erfundene Zahl.
        ergebnis.update({"breite": None,
                         "grund": "b_logF ist nicht positiv — keine Breite"})
        return ergebnis
    u = b_f / -b_t2
    breite = math.sqrt(u)
    g_br = [1 / (2 * breite * -b_t2), 0.0, b_f / (2 * breite * b_t2 * b_t2)]
    var_br = sum(g_br[i] * kovarianz[i][j] * g_br[j]
                 for i in range(3) for j in range(3))
    ergebnis.update({"breite": breite,
                     "se_breite": math.sqrt(var_br) if var_br > 0 else None})
    return ergebnis


# --- Selbsttest ------------------------------------------------------------


def _paired_sigmoid(strata, l2=1e-6, max_iter=200):
    """**Eine ZWEITE, unabhaengige Fassung fuer 1:1-Strata.**

    Das ist der Ersatz fuer den Abgleich mit der numpy-Referenz aus dem
    Skill (`fit_paired_logit`) — numpy gibt es hier nicht. Statt einer
    Referenz stehen zwei Implementierungen gegeneinander, die von
    verschiedenen Seiten kommen: oben die Softmax ueber das ganze
    Stratum, hier die Sigmoid ueber die Differenz. Stimmen sie auf zehn
    Stellen ueberein, ist ein Vorzeichen- oder Indexfehler in einer von
    beiden ausgeschlossen.
    """
    diffs = [[f[d] - k[0][d] for d in range(len(f))] for f, k in strata]
    dim = len(diffs[0])
    beta = [0.0] * dim
    for _ in range(max_iter):
        grad = [0.0] * dim
        hess = [[0.0] * dim for _ in range(dim)]
        for zeile in diffs:
            z = sum(b * x for b, x in zip(beta, zeile))
            p = 1 / (1 + math.exp(-z))
            for d in range(dim):
                grad[d] += (1 - p) * zeile[d]
                for e in range(dim):
                    hess[d][e] += p * (1 - p) * zeile[d] * zeile[e]
        for d in range(dim):
            grad[d] -= l2 * beta[d]
            hess[d][d] += l2
        schritt = solve(hess, grad)
        beta = [b + s for b, s in zip(beta, schritt)]
        if max(abs(s) for s in schritt) < 1e-12:
            break
    return beta


def self_test():
    # --- Lineare Algebra ---
    m = [[2.0, 1.0, -1.0], [-3.0, -1.0, 2.0], [-2.0, 1.0, 2.0]]
    x = solve(m, [8.0, -11.0, -3.0])
    assert all(abs(a - b) < 1e-12 for a, b in zip(x, [2.0, 3.0, -1.0])), x
    inv = inverse(m)
    produkt = [[sum(m[i][k] * inv[k][j] for k in range(3)) for j in range(3)]
               for i in range(3)]
    for i in range(3):
        for j in range(3):
            assert abs(produkt[i][j] - (1.0 if i == j else 0.0)) < 1e-10
    # **Teilpivotisierung wird wirklich gebraucht.** Ohne Zeilentausch
    # teilt dieses System im ersten Schritt durch null.
    assert solve([[0.0, 1.0], [1.0, 0.0]], [2.0, 3.0]) == [3.0, 2.0]
    try:
        solve([[1.0, 2.0], [2.0, 4.0]], [1.0, 2.0])
    except ValueError:
        pass
    else:
        raise AssertionError("singulaere Matrix muss auffallen")

    # --- Gepflanztes Modell, 1:5 wie in Design B ---
    #
    # Die Wahrheit steht VOR dem Fit fest: Optimum 13, Breite 4, und ein
    # Feuchtegewicht von 1. Erzeugt wird nach genau der Formel, die das
    # Modell unterstellt — der Test prueft damit den Schaetzer, nicht die
    # Biologie.
    rng = random.Random(7)
    opt_wahr, sigma_wahr = 13.0, 4.0

    def merkmale(feuchte, temp):
        return [math.log(feuchte), temp, temp * temp]

    def ziehe(anzahl, kontrollen=5):
        strata = []
        for _ in range(anzahl):
            reihen = [(rng.uniform(0.05, 1.0), rng.uniform(2.0, 24.0))
                      for _ in range(kontrollen + 1)]
            nutzen = [math.log(f) - ((t - opt_wahr) / sigma_wahr) ** 2
                      for f, t in reihen]
            # Gumbel-Rauschen macht aus dem Nutzen genau ein
            # Logit-Modell: Wer gewinnt, ist dann softmax-verteilt.
            mit_rausch = [n - math.log(-math.log(rng.random()))
                          for n in nutzen]
            sieger = max(range(len(reihen)), key=lambda i: mit_rausch[i])
            fall = merkmale(*reihen[sieger])
            rest = [merkmale(*r) for i, r in enumerate(reihen) if i != sieger]
            strata.append((fall, rest))
        return strata

    fit = fit_conditional_logit(ziehe(4000))
    assert fit["konvergiert"], fit
    glocke = bell_from_beta(fit["beta"], fit["kovarianz"])
    assert abs(glocke["optimum"] - opt_wahr) < 3 * glocke["se_optimum"], glocke
    assert abs(glocke["breite"] - sigma_wahr) < 3 * glocke["se_breite"], glocke
    assert abs(glocke["optimum"] - opt_wahr) < 1.0, glocke
    assert abs(glocke["breite"] - sigma_wahr) < 0.6, glocke
    # Das gepflanzte Feuchtegewicht ist 1, und der Schaetzer findet es.
    assert abs(glocke["b_logf"] - 1.0) < 0.15, glocke

    # **Optimum und Breite sind massstabsfrei — das muss eine Zeile
    # festhalten.** Der Modulkopf behauptete zuerst, die Breite sei nur
    # bei `b_logF` nahe 1 mit dem sigma der Ampel vergleichbar. Ein
    # gemeinsamer Faktor vor allen Koeffizienten aendert an beiden
    # Groessen aber nichts; er aendert nur, wie scharf die Wahl ist.
    for faktor in (0.25, 4.0):
        skaliert = [b * faktor for b in fit["beta"]]
        kov_skaliert = [[k * faktor * faktor for k in zeile]
                        for zeile in fit["kovarianz"]]
        g2 = bell_from_beta(skaliert, kov_skaliert)
        assert abs(g2["optimum"] - glocke["optimum"]) < 1e-9, (faktor, g2)
        assert abs(g2["breite"] - glocke["breite"]) < 1e-9, (faktor, g2)
        # Nur die Schaerfe zieht mit.
        assert abs(g2["b_logf"] - faktor * glocke["b_logf"]) < 1e-9

    # --- Die zweite Fassung: 1:1 muss Zahl fuer Zahl uebereinstimmen ---
    eins_zu_eins = ziehe(800, kontrollen=1)
    a = fit_conditional_logit(eins_zu_eins)["beta"]
    b = _paired_sigmoid(eins_zu_eins)
    assert all(abs(x - y) < 1e-10 for x, y in zip(a, b)), (a, b)

    # --- Was der Schaetzer NICHT behaupten darf ---
    #
    # Eine nach oben geoeffnete Parabel ist keine Glocke. Frueher haette
    # die Formel dort klaglos ein „Optimum" ausgerechnet — in
    # Wirklichkeit das Minimum.
    kov = [[0.01, 0, 0], [0, 0.01, 0], [0, 0, 0.0001]]
    hoch = bell_from_beta([1.0, -0.5, +0.02], kov)
    assert hoch["optimum"] is None and "keine Glocke" in hoch["grund"]
    # Und ein negatives Feuchtegewicht gibt keine Wurzel. Auch das ist
    # ein Ergebnis („mehr Regen ist schlechter") und keine Zahl.
    negativ = bell_from_beta([-1.0, 0.5, -0.02], kov)
    assert negativ["optimum"] is not None, "das Optimum gibt es trotzdem"
    assert negativ["breite"] is None and "b_logF" in negativ["grund"]

    # --- Die Umrechnung selbst, an gesetzten Zahlen ---
    # b_T = 2·opt/σ², b_T² = −1/σ² fuer opt = 13, σ = 4 → 1.625, −0.0625
    exakt = bell_from_beta([1.0, 2 * 13.0 / 16.0, -1 / 16.0], kov)
    assert abs(exakt["optimum"] - 13.0) < 1e-12, exakt
    assert abs(exakt["breite"] - 4.0) < 1e-12, exakt

    # --- Eine flache Likelihood muss sich als solche zeigen ---
    #
    # Wenige Strata, viel Rauschen: Der Standardfehler des Optimums muss
    # dann gross sein. Ein Schaetzer, der hier eine enge Zahl meldet,
    # waere schlimmer als einer, der gar nichts meldet.
    schmal = fit_conditional_logit(ziehe(4000))
    duenn = fit_conditional_logit(ziehe(60))
    g_schmal = bell_from_beta(schmal["beta"], schmal["kovarianz"])
    g_duenn = bell_from_beta(duenn["beta"], duenn["kovarianz"])
    assert g_duenn["se_optimum"] > 3 * g_schmal["se_optimum"], \
        (g_duenn["se_optimum"], g_schmal["se_optimum"])

    # --- Die Ableitungen der Delta-Methode, numerisch nachgerechnet ---
    #
    # Die Simulation weiter unten misst, ob der gemeldete Fehler zur
    # wirklichen Streuung passt — sie ist aber selbst verrauscht und
    # laesst einen kleinen falschen Term durch. Hier steht deshalb die
    # scharfe Probe: zentrale Differenzen gegen die analytische
    # Ableitung, ueber ALLE drei Koeffizienten. Ein fehlender Term faellt
    # damit auf die sechste Stelle auf.
    beta_probe = [0.9, 1.6, -0.062]
    kov_probe = [[0.0013, 0.00027, -1.0e-05],
                 [0.00027, 0.00147, -5.5e-05],
                 [-1.0e-05, -5.5e-05, 2.1e-06]]

    def wert(beta, feld):
        return bell_from_beta(list(beta), kov_probe)[feld]

    for feld in ("optimum", "breite"):
        h = 1e-6
        numerisch = []
        for d in range(3):
            plus, minus = list(beta_probe), list(beta_probe)
            plus[d] += h
            minus[d] -= h
            numerisch.append((wert(plus, feld) - wert(minus, feld)) / (2 * h))
        var_numerisch = sum(numerisch[i] * kov_probe[i][j] * numerisch[j]
                            for i in range(3) for j in range(3))
        gemeldet = bell_from_beta(list(beta_probe), kov_probe)["se_" + feld]
        assert abs(math.sqrt(var_numerisch) - gemeldet) < 1e-7, \
            f"{feld}: analytisch {gemeldet!r}, numerisch " \
            f"{math.sqrt(var_numerisch)!r}"

    # --- Der Standardfehler muss stimmen, nicht nur existieren ---
    #
    # **Ohne diese Probe ist die Delta-Methode ungeprueft.** Ein
    # fehlender Term macht den Fehler zu klein, und alle Zusicherungen
    # oben blieben trotzdem gruen — der Schaetzer ist ja genau, nur seine
    # gemeldete Unsicherheit waere gelogen. Gemessen wird deshalb gegen
    # die WIRKLICHE Streuung: vierzig unabhaengige Datensaetze, und die
    # Spanne ihrer Optima muss zu dem passen, was ein einzelner Lauf
    # ueber sich selbst behauptet.
    optima, breiten, gemeldet_opt, gemeldet_br = [], [], [], []
    for _ in range(40):
        einer = fit_conditional_logit(ziehe(500))
        g = bell_from_beta(einer["beta"], einer["kovarianz"])
        if g["optimum"] is None or g["breite"] is None:
            continue
        optima.append(g["optimum"])
        breiten.append(g["breite"])
        gemeldet_opt.append(g["se_optimum"])
        gemeldet_br.append(g["se_breite"])
    assert len(optima) >= 35, len(optima)

    def streuung(werte):
        mittel = sum(werte) / len(werte)
        return math.sqrt(sum((w - mittel) ** 2 for w in werte)
                         / (len(werte) - 1))

    for name, echt, behauptet in (
            ("Optimum", streuung(optima),
             sum(gemeldet_opt) / len(gemeldet_opt)),
            ("Breite", streuung(breiten),
             sum(gemeldet_br) / len(gemeldet_br))):
        verhaeltnis = behauptet / echt
        assert 0.75 < verhaeltnis < 1.35, \
            f"{name}: gemeldet {behauptet:.4f}, wirklich {echt:.4f} " \
            f"(Verhaeltnis {verhaeltnis:.2f})"

    # --- Nicht konvergiert wird gemeldet, nicht verschwiegen ---
    knapp = fit_conditional_logit(ziehe(200), max_iter=1)
    assert knapp["konvergiert"] is False and knapp["schritte"] == 1, knapp

    # --- Leere Eingabe ---
    assert fit_conditional_logit([]) is None

    print("Selbsttest ok")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        raise SystemExit(0)
    parser.print_help()
