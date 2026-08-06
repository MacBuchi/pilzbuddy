// Der eine Gesten-Schalter der Karte (#210): Richtet langes Draufhalten
// das Fadenkreuz aus? Ab Werk nein — Begründung in `Settings`.
//
// Muster wie `MapLibreEnabledNotifier` und `OfflineMapEnabledNotifier`:
// Zustand springt sofort, Speichern läuft nach, ein Fehler beim Merken
// wird nur protokolliert. Die Karte darf an einer Einstellung nie
// scheitern.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/settings.dart';

class MapLongPressEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(settingsProvider).mapLongPressEnabled;

  void toggle() {
    final value = !state;
    state = value;
    unawaited(ref
        .read(settingsProvider)
        .setMapLongPressEnabled(value)
        .catchError((Object e, StackTrace stackTrace) {
      logError('Karten-Geste merken', e, stackTrace);
    }));
  }
}

final mapLongPressEnabledProvider =
    NotifierProvider<MapLongPressEnabledNotifier, bool>(
        MapLongPressEnabledNotifier.new);
