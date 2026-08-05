// Wann welche Art gemeldet wird — die Saisonkurven aus GBIF.
//
// **Fakten, kein Urteil**, dieselbe Grenze wie beim Wetter am Spot
// (`spot_rain_section.dart`): Hier steht, in welchen Monaten diese Art
// tatsächlich gemeldet wurde. Nicht, ob heute etwas wächst, und schon gar
// nicht, ob jemand etwas finden wird. Eine bewertende Ampel kommt erst,
// wenn die Rückwärtsprüfung an echten Funden zeigt, dass sie etwas taugt
// (docs/pilzampel-konzept.md).
//
// Die Zahlen liegen in `season_curves.g.dart` und sind erzeugt von
// `tool/season_curves.py` — im Binary, nicht im Netz: Die Kurve gilt im
// Wald ohne Empfang, und keine Artenabfrage verrät, wonach jemand sucht.
import 'mushroom_species.dart';
import 'season_curves.g.dart';

/// Unter so vielen Beobachtungen wird keine Kurve gezeigt. Zwölf
/// Monatsfächer aus wenigen Dutzend Meldungen sind Rauschen, und ein
/// Rauschen mit Balken sieht aus wie eine Aussage.
///
/// **Hier wirkt die Schwelle, nicht im Skript.** `tool/season_curves.py`
/// baut bewusst alle Kurven — auch die dünnen, damit sie in der Doku
/// sichtbar bleiben — und nennt beim Lauf nur, welche darunter liegen.
const kMinObservations = 200;

/// So viele Meldungen muss jeder Monat der Hauptzeit mindestens tragen.
///
/// Die Gesamtzahl allein genügt nicht: Die Effort-Korrektur teilt durch
/// den Monatsgang aller Pilze, und der ist im Winter klein — ein
/// Dezember mit sechs Meldungen kann dadurch auf einen Balken von 93
/// steigen. Eine Art kann also bequem über [kMinObservations] liegen und
/// trotzdem einen Gipfel zeigen, der auf einer Handvoll Meldungen steht.
const kMinPeakSupport = 30;

/// Die Monatsnamen für die Klartextzeile. Ausgeschrieben, weil sie in
/// einem Satz stehen („von August bis September") und nicht in einer
/// Tabelle.
const kMonthNames = [
  'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
  'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
];

/// Die Kurzform an den Balken.
const kMonthLetters = ['J', 'F', 'M', 'A', 'M', 'J',
                       'J', 'A', 'S', 'O', 'N', 'D'];

/// Ein Monat gehört zur Hauptzeit, wenn er mindestens so viel vom
/// Maximum erreicht. 0,8 ist gesetzt, nicht gemessen — es trennt bei den
/// vorhandenen Kurven Gipfel von Ausläufern (Steinpilz: August und
/// September, nicht Juli bis Oktober).
const _peakThreshold = 0.8;

class SeasonCurve {
  const SeasonCurve({
    required this.sci,
    required this.taxonKey,
    required this.isGenus,
    required this.observations,
    required this.peakSupport,
    required this.months,
    required this.raw,
  });

  /// Der wissenschaftliche Name, unter dem GBIF gefragt wurde.
  final String sci;

  /// Der GBIF-Schlüssel — macht eine Zuordnung nachprüfbar, ohne sie
  /// erneut zu raten (`gbif.org/species/<key>`).
  final int taxonKey;

  /// Steht [sci] für eine ganze Gattung? Dann meint der deutsche Name
  /// mehr als eine Art („Rotkappe", „Hallimasch"), und die Kurve fasst
  /// sie zusammen. Das gehört ins UI, sonst liest sie sich genauer,
  /// als sie ist.
  final bool isGenus;

  /// Beobachtungen, auf denen die Kurve steht.
  final int observations;

  /// Die Meldungen im schwächsten Monat der Hauptzeit — wie gut der
  /// Gipfel selbst gestützt ist. Siehe [kMinPeakSupport].
  final int peakSupport;

  /// Effort-korrigierter Jahresgang, Index 0 = Januar, Maximum = 100.
  /// Korrigiert heißt: geteilt durch den Monatsgang ALLER Pilzmeldungen.
  /// Ohne das trüge jede Art denselben Herbstberg — den der Melder.
  final List<int> months;

  /// Derselbe Gang ohne Korrektur. Wird nicht angezeigt; er steht in der
  /// Datei, damit nachprüfbar bleibt, was die Korrektur bewirkt hat.
  final List<int> raw;

  /// Genug Daten für eine Anzeige? Beide Schwellen müssen halten — die
  /// eine schützt die Kurve, die andere ihren Gipfel.
  bool get isReliable =>
      observations >= kMinObservations && peakSupport >= kMinPeakSupport;

  /// Kein Monat sticht heraus — die Art wird das ganze Jahr über
  /// gemeldet (Stockschwämmchen). Das ist eine Aussage, keine Lücke,
  /// und muss deshalb von „keine Daten" unterscheidbar bleiben.
  bool get isFlat => _peakRun().length == 12;

  /// Die Hauptzeit als zusammenhängende Monatsfolge, `null` wenn die
  /// Kurve flach ist.
  ///
  /// **Über den Jahreswechsel hinweg**, sonst zerfiele der
  /// Austernseitling (Dezember/Januar) in zwei Enden und die App
  /// behauptete, seine Zeit sei der Dezember.
  List<int>? get peakMonths {
    final run = _peakRun();
    return run.length == 12 ? null : run;
  }

  /// „August bis September", „Dezember bis Januar", „Mai" — oder `null`.
  String? get peakLabel {
    final run = peakMonths;
    if (run == null || run.isEmpty) return null;
    if (run.length == 1) return kMonthNames[run.first];
    return '${kMonthNames[run.first]} bis ${kMonthNames[run.last]}';
  }

  /// **Ausgedehnt vom stärksten Monat aus**, nicht vom kalendarisch
  /// ersten. Hat eine Kurve zwei getrennte Erhebungen, gewinnt sonst die
  /// frühere — auch wenn die spätere doppelt so hoch ist. Dieselbe
  /// Rechnung wie `peak_run` in `tool/season_curves.py`.
  List<int> _peakRun() {
    var peak = 0;
    for (final value in months) {
      if (value > peak) peak = value;
    }
    if (peak == 0) return const [];
    final threshold = peak * _peakThreshold;
    bool strong(int index) => months[(index % 12 + 12) % 12] >= threshold;

    var start = months.indexOf(peak);
    var end = start;
    while (strong(start - 1) && end - start < 11) {
      start--;
    }
    while (strong(end + 1) && end - start < 11) {
      end++;
    }
    return [for (var index = start; index <= end; index++) (index % 12 + 12) % 12];
  }
}

/// Die Kurve zu einem Artnamen — `null`, wenn es keine gibt.
///
/// Drei Wege dorthin, alle drei Absicht:
/// - Freitext-Arten der Nutzer haben keine ([canonicalSpecies] lässt sie
///   unverändert, die Tabelle kennt sie nicht).
/// - Bekannte Arten ohne zweifelsfreie GBIF-Zuordnung haben keine — eine
///   falsche Kurve wäre schlimmer als keine.
/// - Arten unter [kMinObservations] haben keine.
///
/// Zweitnamen lösen sich auf: Wer „Totentrompete" einträgt, bekommt die
/// Kurve der Herbsttrompete.
SeasonCurve? seasonCurveFor(String? species) {
  final canonical = canonicalSpecies(species);
  if (canonical == null) return null;
  final curve = kSeasonCurves[canonical];
  if (curve == null || !curve.isReliable) return null;
  return curve;
}
