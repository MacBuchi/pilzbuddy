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

/// Debug-Schalter für das Regenradar-Overlay — der Flexibilitätsbeweis
/// der Migration (Stufe 6): ein Umschalten erzeugt nur einen neuen
/// Style-String, den die Engine per `setStyle` einspielt — kein
/// Widget-Neuaufbau. Bewusst NICHT persistiert und ohne Release-UI;
/// die Nutzer-Features dazu (#156/#158) bleiben eigene Issues.
/// Liegt HIER statt im Style-Provider, damit `map_screen.dart` (läuft
/// auch im Web) ihn ohne dart:io-Import erreicht.
final rainRadarEnabledProvider = StateProvider<bool>((ref) => false);
