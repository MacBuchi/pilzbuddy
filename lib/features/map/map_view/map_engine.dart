// Der Opt-in-Schalter der MapLibre-Engine (Beta) — dasselbe Muster wie
// `OfflineMapEnabledNotifier`: Zustand springt sofort, Speichern läuft
// nach, die Wahl überdauert den Neustart. flutter_map bleibt Standard,
// bis der Direktvergleich (Migrationsplan, PR 7) abgenommen ist.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors.dart';
import '../../../core/settings.dart';

class MapLibreEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(settingsProvider).mapLibreEnabled;

  void toggle() {
    final value = !state;
    state = value;
    unawaited(ref
        .read(settingsProvider)
        .setMapLibreEnabled(value)
        .catchError((Object e, StackTrace stackTrace) {
      logError('Karten-Engine merken', e, stackTrace);
    }));
  }
}

final mapLibreEnabledProvider =
    NotifierProvider<MapLibreEnabledNotifier, bool>(MapLibreEnabledNotifier.new);
