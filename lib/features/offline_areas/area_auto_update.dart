// Gespeicherte Kartenbereiche auf den neuen Kartenstand bringen (#630,
// seit 1.217.0; Betreiber: „geht es auch, dass Offline-Kacheln
// automatisch aktualisiert werden?").
//
// Der Kartenhost baut sein Archiv monatlich neu (TrailBuddys
// `map-data.yml`), und jeder Bereich merkt sich den Stand, aus dem er
// kam (`StoredArea.build`). Liegt das Manifest weiter, ist der Bereich
// veraltet. Nachgeladen wird mit DERSELBEN Form unter DERSELBEN Id — der
// alte Bereich bleibt, bis der neue geschrieben und gegengelesen ist
// (`AreaDownloader.download`).
//
// Zwei Wege, und sie teilen sich den Maßstab mit den Regionskarten (#332):
// - **Von selbst** nur im freien Netz (`freeNetworkProvider`: kein
//   Mobilfunk, nicht kostenpflichtig), nur im Vordergrund, und ein
//   selbst gestarteter Download hält auch von selbst wieder an, wenn das
//   freie Netz geht. Im Browser gibt es die Kostenauskunft nicht — dort
//   gilt „kostet", und es bleibt beim Knopf.
// - **Von Hand** („Alle aktualisieren" auf der Seite): wer tippt,
//   entscheidet selbst über die Leitung.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/settings.dart';
import '../map/live_share_providers.dart' show appInForegroundProvider;
import '../map/online_map.dart';
import '../offline_maps/offline_map_providers.dart' show freeNetworkProvider;
import 'area_providers.dart';
import 'area_store.dart';

/// Die Bereiche, deren Stand älter ist als [hostBuild] — in ihrer
/// Reihenfolge. Die Stände sind `JJJJMMTT`, also als Text vergleichbar.
List<StoredArea> staleAreas(List<StoredArea> areas, String? hostBuild) => [
      if (hostBuild != null)
        for (final a in areas)
          if (hostBuild.compareTo(a.build) > 0) a,
    ];

/// Veraltete Bereiche gegen den Stand der Neuen Karte. Das Manifest kommt
/// aus `onlineMapProvider` — kein eigener Abruf; ohne Schalter oder
/// Empfang ist die Liste leer.
final staleAreasProvider = Provider<List<StoredArea>>((ref) {
  final manifest = ref.watch(onlineMapProvider).valueOrNull?.manifest;
  final areas = ref.watch(storedAreasProvider).valueOrNull ?? const [];
  return staleAreas(areas, manifest?.sourceBuild);
});

/// Der Schalter auf der Seite „Kartenbereiche". Muster
/// `MapAutoUpdateEnabledNotifier`.
class AreaAutoUpdateEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(settingsProvider).areaAutoUpdateEnabled;

  void set(bool value) {
    state = value;
    unawaited(ref
        .read(settingsProvider)
        .setAreaAutoUpdateEnabled(value)
        .catchError((Object e, StackTrace stackTrace) {
      logError('Auto-Update der Kartenbereiche merken', e, stackTrace);
    }));
  }
}

final areaAutoUpdateEnabledProvider =
    NotifierProvider<AreaAutoUpdateEnabledNotifier, bool>(
        AreaAutoUpdateEnabledNotifier.new);

/// Was der Nachlauf jetzt tun soll — rein, damit jede Regel ohne Netz
/// prüfbar ist. Zwei Ausgänge wie bei den Regionen: starten UND anhalten.
({StoredArea? start, bool cancel}) planAutoAreaUpdate({
  required bool enabled,
  required bool freeNetwork,
  required bool inForeground,
  required List<StoredArea> stale,
  required bool busy,
  required String? autoRunning,
  required Set<String> failed,
}) {
  // Anhalten hängt nicht am Vordergrund: Das freie Netz kann auch gehen,
  // während die App in der Tasche steckt.
  if (!enabled || !freeNetwork) {
    return (start: null, cancel: autoRunning != null);
  }
  // Nie mit einem laufenden Download streiten, auch nicht mit dem eines
  // Nutzers — es gibt ohnehin nur einen.
  if (!inForeground || busy) return (start: null, cancel: false);
  for (final area in stale) {
    if (!failed.contains(area.id)) return (start: area, cancel: false);
  }
  return (start: null, cancel: false);
}

/// Der Zustand ist die Id des Bereichs, den der Nachlauf gerade selbst
/// lädt — daran unterscheidet er beim Anhalten seinen Download von einem
/// angetippten.
class AreaAutoUpdateNotifier extends Notifier<String?> {
  /// In dieser Sitzung gescheitert: ruht bis zum nächsten Start, sonst
  /// liefe ein Bereich, den der Host nicht mehr hergibt, bei jedem
  /// Verbindungswechsel erneut an. Von Hand geht er weiter.
  final _failed = <String>{};

  @override
  String? build() => null;

  void sync() {
    final plan = planAutoAreaUpdate(
      enabled: ref.read(areaAutoUpdateEnabledProvider),
      freeNetwork: ref.read(freeNetworkProvider).valueOrNull ?? false,
      inForeground: ref.read(appInForegroundProvider),
      stale: ref.read(staleAreasProvider),
      busy: ref.read(areaDownloadProvider).busy,
      autoRunning: state,
      failed: _failed,
    );
    if (plan.cancel) ref.read(areaDownloadProvider.notifier).cancel();
    final area = plan.start;
    if (area == null) return;
    state = area.id;
    unawaited(_run(area, auto: true));
  }

  /// Von Hand: alle veralteten nacheinander. Hört beim ersten auf, der
  /// nicht durchgeht — die Seite zeigt dann dessen Fehler.
  Future<void> updateAll() async {
    for (final area in ref.read(staleAreasProvider)) {
      if (!await _run(area, auto: false)) return;
    }
  }

  Future<bool> _run(StoredArea area, {required bool auto}) async {
    final download = ref.read(areaDownloadProvider.notifier);
    try {
      final plan = await download.plan(area.shape);
      final done = await download.start(plan, name: area.name, id: area.id);
      if (done == null && auto) {
        final failed = ref.read(areaDownloadProvider).phase ==
            AreaDownloadPhase.failed;
        if (failed) {
          _failed.add(area.id);
          // Niemand hat getippt — keine Fehlerzeile auf der Seite für
          // etwas, das die Nutzerin nicht angestoßen hat.
          download.reset();
        }
      }
      return done != null;
    } catch (e, stackTrace) {
      // Plan gescheitert (Host nicht erreichbar, jetzt zu groß).
      if (auto) {
        _failed.add(area.id);
        logError('Kartenbereich automatisch aktualisieren', e, stackTrace);
      }
      return false;
    } finally {
      if (auto) state = null;
    }
  }
}

final areaAutoUpdateProvider =
    NotifierProvider<AreaAutoUpdateNotifier, String?>(
        AreaAutoUpdateNotifier.new);

/// Die Zutaten in EINEM Wert — Record, damit der Karten-Screen mit einem
/// `ref.listen` auskommt, der nur bei echter Änderung feuert. Die Ids als
/// zusammengefügter Text: zwei gleiche Listen sind für `==` verschieden.
typedef AreaAutoUpdateInputs = ({
  bool enabled,
  bool freeNetwork,
  bool inForeground,
  String staleIds,
  bool busy,
});

final areaAutoUpdateInputsProvider = Provider<AreaAutoUpdateInputs>((ref) => (
      enabled: ref.watch(areaAutoUpdateEnabledProvider),
      freeNetwork: ref.watch(freeNetworkProvider).valueOrNull ?? false,
      inForeground: ref.watch(appInForegroundProvider),
      staleIds: [for (final a in ref.watch(staleAreasProvider)) a.id].join(','),
      busy: ref.watch(areaDownloadProvider.select((s) => s.busy)),
    ));
