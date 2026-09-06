import '../../core/mushroom_species.dart';

/// Ein Vorschlag für das Pilzart-Feld. [name] ist immer die
/// Hauptbezeichnung — das ist auch, was gespeichert wird.
class SpeciesSuggestion {
  final String name;
  final bool isOwn;
  final SpeciesGroup? group;

  /// Der Zweitname, über den dieser Vorschlag gefunden wurde. Wer
  /// „Totentrompete" tippt und „Herbsttrompete" angeboten bekommt, muss
  /// sehen, warum — sonst sieht es aus, als hätte die App die Eingabe
  /// verschluckt.
  final String? matchedSynonym;

  /// Geraten statt gefunden: Die normale Suche hat NICHTS geliefert, und
  /// dieser Vorschlag stammt aus dem Tippfehler-Ausgleich („Bofist" →
  /// „Riesenbovist"). Die Oberfläche muss das kenntlich machen — ein
  /// geratener Treffer, der aussieht wie ein gefundener, ist eine
  /// Behauptung über die Eingabe des Nutzers.
  final bool isGuess;

  const SpeciesSuggestion(this.name,
      {required this.isOwn,
      this.group,
      this.matchedSynonym,
      this.isGuess = false});
}

/// Vorschläge für das Pilzart-Feld: eigene Arten zuerst, dann bekannte
/// Arten; Contains-Match über [foldSpeciesName], dedupliziert. Eigene Arten
/// bekommen ihre Gruppe per Lookup (sofern bekannt).
///
/// Zweitnamen werden mitgesucht, aber nicht angeboten: Ein Treffer auf
/// „Herrenpilz" ergibt den Vorschlag „Steinpilz" (mit [matchedSynonym]),
/// und die Deduplizierung läuft über die Hauptbezeichnung — sonst stünden
/// bei „stein" gleich drei Zeilen für denselben Pilz.
///
/// Findet der Vergleich gar nichts, übernimmt [_guesses] — siehe dort.
List<SpeciesSuggestion> suggestSpecies(
  String query,
  List<String> own,
  List<KnownSpecies> builtin, {
  int limit = 6,
}) {
  final q = foldSpeciesName(query);
  final result = <SpeciesSuggestion>[];
  final seen = <String>{};

  bool matches(String name) => q.isEmpty || foldSpeciesName(name).contains(q);

  for (final name in own) {
    if (result.length >= limit) return result;
    final canonical = canonicalSpecies(name) ?? name;
    final key = foldSpeciesName(canonical);
    if (seen.contains(key) || !matches(name)) continue;
    seen.add(key);
    result.add(SpeciesSuggestion(canonical,
        isOwn: true,
        group: groupFor(canonical),
        matchedSynonym: _synonymHit(name, canonical)));
  }
  for (final species in builtin) {
    if (result.length >= limit) return result;
    final canonical = species.sameAs ?? species.name;
    final key = foldSpeciesName(canonical);
    if (seen.contains(key) || !matches(species.name)) continue;
    seen.add(key);
    result.add(SpeciesSuggestion(canonical,
        isOwn: false,
        group: groupFor(canonical) ?? species.group,
        matchedSynonym: _synonymHit(species.name, canonical)));
  }
  if (result.isEmpty) return _guesses(q, own, builtin, limit);
  return result;
}

/// Der getippte Name, falls er nicht die Hauptbezeichnung ist.
String? _synonymHit(String typed, String canonical) =>
    typed.toLowerCase() == canonical.toLowerCase() ? null : typed;

/// Wie weit eine Eingabe danebenliegen darf, damit sie noch als Tippfehler
/// gilt — abhängig von ihrer Länge, weil bei kurzen Wörtern alles nah an
/// allem liegt. `-1` heißt „gar nicht raten".
///
/// **Die Kosten sind unsymmetrisch, und darum ist die Grenze locker.** Ein
/// überflüssiger Vorschlag ist eine Zeile, die man nicht antippt. Eine
/// leere Liste dagegen ist genau das, was #395 ausgelöst hat: Der Nutzer
/// schließt daraus, die Art fehle, und meldet sie — obwohl sie dasteht.
/// Ein Vorschlag kann dabei nie falsche Daten erzeugen; er wirkt erst beim
/// Antippen, frei Getipptes wird unverändert gespeichert.
///
/// Ein erster Entwurf zog die Grenze auf sechs Zeichen hoch, weil „hallo"
/// sonst den Hallimasch vorschlug. Das war das falsche Kriterium: In einem
/// Artenfeld IST „hallo" höchstwahrscheinlich ein vertipptes „Halli…" —
/// der Fall, für den dieser Rückfall da ist, nicht der, gegen den er
/// schützen soll (Betreiber, 2026-09-06).
///
/// Bei vier und nicht bei drei: Ein Fehler auf drei Zeichen heißt, ein
/// Drittel der Eingabe ist falsch — das ist kein Tippfehlermodell mehr.
/// Darunter liefert der Contains-Vergleich ohnehin fast immer Treffer.
///
/// Gemessen (#395): 23 von 25 geprüften Nicht-Arten bleiben auch so still,
/// „abc" und „xyz" eingeschlossen. Nur „Auto" und „Regen" liegen zufällig
/// einen Fehler neben einem Wortstück — angenommen, siehe oben.
int _maxTypoDistance(int length) => length < 4 ? -1 : (length <= 7 ? 1 : 2);

/// Der Tippfehler-Ausgleich: der beste Treffer, wenn es keinen gab.
///
/// Läuft **nur**, wenn die normale Suche leer ausging — er ist ein
/// Rückfall, keine zweite Meinung. Angeboten wird ausschließlich der
/// geringste gefundene Abstand: Wer „Steinpiltz" tippt, will die drei
/// Steinpilze sehen und nicht dahinter noch alles, was zufällig auch in
/// die Nähe passt.
List<SpeciesSuggestion> _guesses(
  String q,
  List<String> own,
  List<KnownSpecies> builtin,
  int limit,
) {
  final maxDistance = _maxTypoDistance(q.length);
  if (maxDistance < 0) return const [];

  final best = <String, (int, SpeciesSuggestion)>{};
  void consider(String typed, {required bool isOwn, SpeciesGroup? group}) {
    final distance = _nearContains(q, foldSpeciesName(typed));
    if (distance > maxDistance) return;
    final canonical = canonicalSpecies(typed) ?? typed;
    final key = foldSpeciesName(canonical);
    final existing = best[key];
    if (existing != null && existing.$1 <= distance) return;
    best[key] = (
      distance,
      SpeciesSuggestion(canonical,
          isOwn: isOwn,
          group: groupFor(canonical) ?? group,
          matchedSynonym: _synonymHit(typed, canonical),
          isGuess: true)
    );
  }

  for (final name in own) {
    consider(name, isOwn: true);
  }
  for (final species in builtin) {
    consider(species.name, isOwn: false, group: species.group);
  }
  if (best.isEmpty) return const [];

  final closest =
      best.values.map((e) => e.$1).reduce((a, b) => a < b ? a : b);
  return [
    for (final entry in best.values)
      if (entry.$1 == closest) entry.$2,
  ].take(limit).toList();
}

/// Der kleinste Editierabstand zwischen [needle] und **irgendeinem**
/// Teilstück von [hay].
///
/// Also nicht der Abstand der ganzen Wörter: „bofist" gegen
/// „flaschenbovist" sind acht Änderungen, gegen das Teilstück „bovist"
/// aber eine — und genau das ist die Frage, die hier zählt. Erreicht wird
/// es über eine Nullzeile (freier Start) und das Minimum über die letzte
/// Zeile (freies Ende); sonst ist es die gewöhnliche
/// Levenshtein-Rechnung.
int _nearContains(String needle, String hay) {
  if (needle.isEmpty) return 0;
  var previous = List<int>.generate(needle.length + 1, (i) => i);
  var best = previous[needle.length];
  final current = List<int>.filled(needle.length + 1, 0);
  for (var j = 1; j <= hay.length; j++) {
    current[0] = 0;
    for (var i = 1; i <= needle.length; i++) {
      final substitution =
          previous[i - 1] + (needle[i - 1] == hay[j - 1] ? 0 : 1);
      final insertion = current[i - 1] + 1;
      final deletion = previous[i] + 1;
      var value = substitution < insertion ? substitution : insertion;
      if (deletion < value) value = deletion;
      current[i] = value;
    }
    if (current[needle.length] < best) best = current[needle.length];
    previous = List<int>.of(current);
  }
  return best;
}

/// Leitet aus Funden (bereits nach „neueste zuerst" sortiert) die Liste der
/// eigenen Arten ab — zuletzt benutzt zuerst, case-insensitiv dedupliziert.
/// Zweitnamen aus älteren Funden werden dabei auf die Hauptbezeichnung
/// gebracht, damit dieselbe Art nicht zweimal vorgeschlagen wird.
List<String> ownSpeciesFromSortedNames(Iterable<String?> speciesNewestFirst) {
  final result = <String>[];
  final seen = <String>{};
  for (final name in speciesNewestFirst) {
    final canonical = canonicalSpecies(name);
    if (canonical == null) continue;
    if (seen.add(canonical.toLowerCase())) result.add(canonical);
  }
  return result;
}
