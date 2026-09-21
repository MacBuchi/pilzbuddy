// Die von der Ampel ausgenommenen Arten (#495) — der Schalter je Art im
// Reiter „Pilze", gerätelokal wie die Ebenen-Schalter.
//
// Wirkt überall, wo die Ampel je ART spricht: Banner-Nachlauf,
// Spot-Blatt, und über das Saison-Tor auch auf der Fläche (eine Klasse,
// deren Arten alle ausgenommen sind, ist aus). NICHT auf die Scheiben
// der Fundorte-Ebene — die zeigen Meldungen, keine Ampel.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/settings.dart';

class AmpelExcludedSpecies extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.read(settingsProvider).ampelExcludedSpecies;

  void toggle(String species) {
    final next = {...state};
    if (!next.remove(species)) next.add(species);
    state = next;
    unawaited(ref
        .read(settingsProvider)
        .setAmpelExcludedSpecies(next)
        .catchError((Object e, StackTrace s) =>
            logError('Ampel-Ausnahmen merken', e, s)));
  }
}

final ampelExcludedSpeciesProvider =
    NotifierProvider<AmpelExcludedSpecies, Set<String>>(
        AmpelExcludedSpecies.new);
