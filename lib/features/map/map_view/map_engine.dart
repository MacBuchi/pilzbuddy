// Die Engine-Wahl: Seit der Abnahme des Direktvergleichs
// (docs/map-performance.md, 2026-08-03) ist MapLibre auf Android
// Standard; gespeichert wird das OPT-OUT zur bisherigen Karte
// (`classicMapEnabled`) — dasselbe Muster wie
// `OfflineMapEnabledNotifier`: Zustand springt sofort, Speichern läuft
// nach, die Wahl überdauert den Neustart.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors.dart';
import '../../../core/settings.dart';

class MapLibreEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => !ref.read(settingsProvider).classicMapEnabled;

  void toggle() {
    final value = !state;
    state = value;
    unawaited(ref
        .read(settingsProvider)
        .setClassicMapEnabled(!value)
        .catchError((Object e, StackTrace stackTrace) {
      logError('Karten-Engine merken', e, stackTrace);
    }));
  }
}

final mapLibreEnabledProvider =
    NotifierProvider<MapLibreEnabledNotifier, bool>(MapLibreEnabledNotifier.new);
