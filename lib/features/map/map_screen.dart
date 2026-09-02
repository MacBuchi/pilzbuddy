import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../offline_maps/offline_map_providers.dart';

import '../../core/errors.dart';
import '../../core/geo.dart';
import '../../core/mushroom_species.dart';
import '../../core/update_check.dart';
import '../../core/widgets/mushroom_avatar.dart';
import '../../core/widgets/mushroom_icon.dart';
import '../../data/providers.dart';
import '../../models/friend_location.dart';
import '../../models/spot.dart';
import 'elevation_contour_providers.dart';
import 'elevation_contours.dart';
import '../friends/friend_providers.dart';
import '../profile/profile_providers.dart';
import '../spots/nearby_spots.dart';
import '../spots/spot_providers.dart';
import '../tour/tour_providers.dart';
import '../tour/tour_task_handler.dart';
import '../tour/tour_track.dart';
import '../tour/widgets/tour_icon.dart';
import '../tour/widgets/tour_summary_sheet.dart';
import '../tour/widgets/tour_track_marker.dart';
import '../spots/widgets/add_find_sheet.dart';
import '../help/map_tour.dart';
import '../spots/widgets/spot_detail_sheet.dart';
import 'live_share_providers.dart';
import 'resume_refresh.dart';
import 'forest_data_providers.dart';
import 'map_focus.dart';
import 'widgets/map_layers_sheet.dart';
import 'widgets/map_trip_sheet.dart';
import 'map_gestures.dart';
import 'map_view/camera_tour.dart';
import 'map_view/map_view.dart';
import 'position_provider.dart';
import 'spot_filter.dart';
import 'widgets/add_spot_sheet.dart';
import 'widgets/map_banners.dart';
import 'widgets/forest_layer_sheet.dart';
import 'widgets/terrain_layer_sheet.dart';
import 'widgets/rain_layer_sheet.dart';
import 'widgets/map_legend.dart';
import 'widgets/share_location_sheet.dart';
import 'widgets/spot_filter_sheet.dart';
import '../../core/app_colors.dart';
import '../../core/read_after_write.dart';

/// Antwort auf „hier liegt schon ein Spot" (#215).
enum _NearbyChoice { existingSpot, newSpot }

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
  // Fallback: Mitte Deutschlands, bis die GPS-Position bekannt ist.
  static const _fallbackCenter = LatLng(51.1634, 10.4477);
  static const _fallbackZoom = 6.5;

  /// Der Blick, mit dem der Start auf die eigene Position einrastet (#360).
  ///
  /// Rund 10 km Umkreis auf einem ~400-dp-Schirm — viel weiter weg als
  /// „Auf mich zentrieren" (15) oder ein Spot-Sprung ([kSpotFocusZoom]):
  /// Der Start soll die Gegend zeigen, nicht den Fleck, auf dem man steht.
  ///
  /// **Die Zahl ist auf die Standard-Engine geeicht.** Beide zählen Zoom
  /// verschieden — am Gerät gemessen ist MapLibres 11 exakt der 256er-Zoom
  /// 12 von flutter_map (`docs/map-performance.md`, Nachtrag 2026-08-21).
  /// Auf der klassischen Karte und im Web zeigt dieselbe Zahl deshalb rund
  /// die doppelte Fläche. Bewusst in Kauf genommen: Ein aus dem Radius
  /// gerechneter Zoom bräuchte die Kachelgröße in der Fassade, und die
  /// Kamera wird hier überall mit rohen Zahlen bewegt (Long-Press 16,
  /// „Auf mich zentrieren" 15).
  static const _startZoom = 10.0;

  // Grenzen des Karten-Zooms — 19 ist die höchste Stufe, für die es sowohl
  // OSM-Kacheln als auch Offline-Vektordaten gibt (Engine-Detailkommentare
  // in map_view/flutter_map_view.dart).
  static const _minZoom = 3.0;
  static const _maxZoom = 19.0;

  /// Engine-unabhängiger Kamerazugriff; die Engine hängt sich beim Einbau
  /// selbst ein (map_view.dart).
  final _map = MapViewController(
    initialCenter: _fallbackCenter,
    initialZoom: _fallbackZoom,
  );

  /// Die Anker der geführten Tour (#350). Je Zustand eine Instanz —
  /// global wären es `GlobalKey`s, die einen Neuaufbau überleben und
  /// dann auf abgehängte Elemente zeigen.
  final _tourAnchors = MapTourAnchors();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Der Ausgangskorb (#267) beim Start: Wer gestern im Wald etwas
    // eingetragen hat, soll es heute nicht von Hand losschicken müssen.
    // Nach dem ersten Frame, damit der Start nicht daran hängt; ohne
    // Empfang bleibt einfach alles liegen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(mySpotsProvider.notifier).sendOutbox());
      // Und einmal nachsehen, ob eine Offline-Karte von selbst
      // nachzuladen ist (#332). Beim ersten Frame steht der Katalog
      // meist noch aus; dann übernimmt der Listener weiter unten.
      ref.read(mapAutoUpdateProvider.notifier).sync();
      // Eine Tour, die der Prozess-Kill unterbrochen hat, läuft weiter
      // (#338). Wer im Wald steht und dessen App zwischendurch
      // weggeräumt wurde, hat sie nicht beendet.
      unawaited(ref.read(tourProvider.notifier).restore());
      // Und beim allerersten Mal die geführte Tour (#350). Nach dem
      // ersten Frame, weil die Anker erst dann vermessbar sind — und
      // ohne Rücksicht auf das Intro-Overlay: Das liegt app-weit
      // darüber und gibt die Karte nach 2,6 s von selbst frei.
      if (!ref.read(mapTourSeenProvider)) {
        ref.read(mapTourProvider.notifier).start();
      }
      // Und auf die eigene Position einrasten (#360), falls schon eine
      // dasteht — sonst übernimmt der Listener in `build` den ersten Fix.
      _maybeSnapToStart(ref.read(positionStreamProvider).valueOrNull);
    });
    // Punkte, die das Service-Isolate misst, in die Karte durchreichen
    // (#342). Rein für die Anzeige — geschrieben hat sie der Service
    // schon; ist die App weg, kommt hier nichts an, und genau dann trägt
    // die Datei allein. Kein Plattform-Kanal, nur ein Dart-Callback.
    FlutterForegroundTask.addTaskDataCallback(_onTourTick);
  }

  void _onTourTick(Object data) {
    final point = decodeTourTick(data);
    if (point == null || !mounted) return;
    ref.read(tourProvider.notifier).acceptTick(point);
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTourTick);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Wann die App in den Hintergrund ging — die Grundlage der
  /// Resume-Entscheidung (#316): Ein Blick auf die Uhr und zurück ist
  /// kein „Zurückkehren".
  DateTime? _pausedAt;

  /// Wann die GitHub-Ziele (Update-Check, Karten-Katalog) zuletzt
  /// geladen wurden. Startet JETZT, denn beim ersten Aufbau laden die
  /// Provider ohnehin — die Stunde zählt ab da.
  DateTime _lastMetaRefresh = DateTime.now();

  /// Android hält die App lange im Hintergrund am Leben — beim echten
  /// Zurückkehren neu laden, damit z. B. neue Freundes-Spots und
  /// Anfragen ohne App-Neustart erscheinen. Was „echt" heißt und was
  /// dann lädt, entscheidet `decideResumeRefresh` (#316).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Nur paused/resumed, nicht inactive: Das feuert schon beim
    // App-Umschalter und bei Berechtigungsdialogen — die Schleifen
    // sollen ruhen, wenn die App WEG ist, nicht bei jedem Flackern.
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      ref.read(appInForegroundProvider.notifier).state = false;
    } else if (state == AppLifecycleState.resumed) {
      ref.read(appInForegroundProvider.notifier).state = true;
      final pausedAt = _pausedAt;
      _pausedAt = null;
      // Ohne vorheriges paused (z. B. inactive-Flackern durch einen
      // Berechtigungsdialog) gibt es kein „weg gewesen".
      if (pausedAt == null) return;
      final now = DateTime.now();
      switch (decideResumeRefresh(
        awayFor: now.difference(pausedAt),
        sinceMetaRefresh: now.difference(_lastMetaRefresh),
        minAway: ref.read(resumeRefreshMinAwayProvider),
        metaEvery: ref.read(resumeMetaRefreshEveryProvider),
      )) {
        case ResumeRefresh.none:
          break;
        case ResumeRefresh.local:
          _refreshLocal();
        case ResumeRefresh.localAndMeta:
          _refreshLocal();
          _lastMetaRefresh = now;
          ref.invalidate(updateInfoProvider);
          // Karten-Abo: prüfen, ob es neuere Offline-Karten gibt.
          ref.invalidate(availableMapsProvider);
      }
    }
  }

  /// Die Ziele, die sich ändern, während man weg ist: Supabase-Daten
  /// und der Blick auf die eigene Platte.
  void _refreshLocal() {
    ref.invalidate(mySpotsProvider);
    ref.invalidate(friendSpotsProvider);
    ref.invalidate(friendshipsProvider);
    ref.invalidate(installedMapsProvider);
  }

  /// Der Aktualisieren-Knopf: ausdrücklicher Nutzerwunsch — hier gilt
  /// keine Kadenz, es lädt ALLES (#316 drosselt nur das Automatische).
  void _refreshData() {
    _refreshLocal();
    _lastMetaRefresh = DateTime.now();
    ref.invalidate(updateInfoProvider);
    ref.invalidate(availableMapsProvider);
  }

  /// Ist die Gelegenheit zum Einrasten verbraucht? (#360)
  bool _startSnapDone = false;

  /// Beim Start einmal auf die eigene Position einrasten (#360).
  ///
  /// Drei Regeln, jede mit ihrem Grund:
  ///
  /// **Einmal.** Der Betreiber ausdrücklich: „einmalig, nicht dauernd
  /// umspringen". Die Karte hängt in einem `IndexedStack`
  /// (`StatefulShellRoute`), ihr Zustand überlebt den Reiterwechsel — der
  /// Rückweg aus dem Profil ist kein neuer Start.
  ///
  /// **Aus dem laufenden Positionsstrom, nicht über [_currentPosition].**
  /// Der Unterschied ist die Berechtigungsfrage: Der Strom stellt sie
  /// bewusst nie (`position_provider.dart`), das tut allein „Auf mich
  /// zentrieren". Beim allerersten Start liefe der System-Dialog sonst
  /// mitten in die geführte Tour (#350). Preis, mit Absicht bezahlt: Auf
  /// einem frischen Gerät tut der Sprung nichts, bis die Berechtigung
  /// einmal erteilt ist — danach bei jedem Start.
  ///
  /// **Der Sprung weicht dem Nutzer.** Der erste Fix kann unter
  /// Blätterdach Sekunden brauchen; wer inzwischen geschoben hat oder über
  /// ein Banner auf einem Spot gelandet ist, wird nicht weggerissen.
  /// Verbraucht ist die Gelegenheit trotzdem, sonst spränge der nächste
  /// Fix doch noch.
  void _maybeSnapToStart(Position? position) {
    if (_startSnapDone || position == null || !mounted) return;
    _startSnapDone = true;
    if (!_atStartView) return;
    _map.move(LatLng(position.latitude, position.longitude), _startZoom);
  }

  /// Steht die Karte noch unberührt auf der Startansicht?
  ///
  /// Mit Toleranz statt `==`: Die Kameramitte geht bei MapLibre durch den
  /// Plattform-Kanal und kommt in den letzten Bits verändert zurück — ein
  /// exakter Vergleich wäre gegen die Fake im Test wahr und auf dem Gerät
  /// nie. Ein Kilometer ist dafür reichlich und für eine Geste nichts: bei
  /// Zoom 6,5 der halbe Pixel.
  bool get _atStartView =>
      distanceKm(_map.center.latitude, _map.center.longitude,
              _fallbackCenter.latitude, _fallbackCenter.longitude) <
          1.0 &&
      (_map.zoom - _fallbackZoom).abs() < 0.1;

  Future<Position?> _currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _centerOnMe() async {
    final position = await _currentPosition();
    if (position == null) {
      _showMessage('Standort nicht verfügbar. Berechtigung erteilt?');
      return;
    }
    _map.move(LatLng(position.latitude, position.longitude), 15);
    // Berechtigung wurde ggf. gerade erteilt → Live-Marker starten.
    ref.invalidate(positionStreamProvider);
  }

  /// Das Karten-Blatt (#347) und der Weg von dort in die Detailblätter.
  ///
  /// Das Blatt öffnet nichts selbst, es gibt die Wahl zurück — sonst
  /// stünden die Wege in die Detailblätter an zwei Stellen, und die
  /// zweite hätte keinen `mounted`-Schutz.
  Future<void> _openLayers() async {
    final detail = await showMapLayersSheet(context);
    if (detail == null || !mounted) return;
    switch (detail) {
      case MapLayerDetail.offline:
        await context.push('/profile/offline-maps');
      case MapLayerDetail.forest:
        await showForestLayerSheet(context);
      case MapLayerDetail.terrain:
        await showTerrainLayerSheet(context);
      case MapLayerDetail.rain:
        await showRainLayerSheet(context);
      case MapLayerDetail.refresh:
        _refreshData();
        _showMessage('Karte aktualisiert');
    }
  }

  /// Das Unterwegs-Blatt (#347): Pilztour und Standort-Teilen.
  Future<void> _openTrip() async {
    final action = await showTripSheet(context);
    if (action == null || !mounted) return;
    switch (action) {
      case TripAction.tour:
        await _toggleTour();
      case TripAction.share:
        await _openShareSheet();
    }
  }

  /// Sheet zum Starten/Verlängern/Beenden des Standort-Teilens.
  Future<void> _openShareSheet() async {
    final expiresAt = ref.read(myShareProvider).valueOrNull;
    final active = ref.read(isSharingProvider);
    final action = await showShareLocationSheet(context,
        active: active, expiresAt: expiresAt);
    if (action == null || !mounted) return;
    final duration = action.duration;
    if (duration == null) {
      await _stopSharing();
    } else {
      await _startSharing(duration);
    }
  }

  Future<void> _startSharing(Duration duration) async {
    // Bevorzugt die bereits laufende Live-Position; sonst einmalig anfragen
    // (fragt ggf. nach der Berechtigung, wie „Meine Position").
    var position = ref.read(positionStreamProvider).valueOrNull;
    position ??= await _currentPosition();
    if (position == null) {
      _showMessage('Standort nicht verfügbar. Berechtigung erteilt?');
      return;
    }
    try {
      await ref.read(myShareProvider.notifier).share(
            duration: duration,
            lat: position.latitude,
            lng: position.longitude,
          );
      // Berechtigung ggf. gerade erteilt → eigenen Live-Marker starten.
      ref.invalidate(positionStreamProvider);
      if (!mounted) return;
      final until = ref.read(myShareProvider).valueOrNull;
      _showMessage(until == null
          ? 'Standort wird geteilt 📍'
          : 'Standort geteilt bis '
              '${TimeOfDay.fromDateTime(until.toLocal()).format(context)} Uhr 📍');
    } catch (e, stackTrace) {
      logError('Standort teilen', e, stackTrace);
      _showMessage(friendlyError(e));
    }
  }

  Future<void> _stopSharing() async {
    try {
      await ref.read(myShareProvider.notifier).stop();
      _showMessage('Standort-Teilen beendet');
    } catch (e, stackTrace) {
      logError('Standort-Teilen beenden', e, stackTrace);
      _showMessage(friendlyError(e));
    }
  }

  /// Bei aktiver Freigabe jede neue Position hochschieben, damit Freunde
  /// die Bewegung sehen. `expires_at` bleibt dabei unverändert.
  void _maybeUploadLocation(Position? position) {
    if (position == null || !ref.read(isSharingProvider)) return;
    final expiresAt = ref.read(myShareProvider).valueOrNull;
    if (expiresAt == null) return;
    ref
        .read(liveShareRepositoryProvider)
        .upsertMyLocation(
          lat: position.latitude,
          lng: position.longitude,
          expiresAt: expiresAt,
        )
        // Ein Positions-Tick, der nach dem Abmelden noch eintrudelt, ist
        // kein Fehler — siehe friendLocationsProvider (Issue #124).
        .catchError((Object e, StackTrace st) {
      if (e is NotSignedInException) return;
      logError('Live-Standort aktualisieren', e, st);
    });
  }

  /// Startet die Pilztour oder beendet sie (#338).
  ///
  /// Beim Beenden wird die Aufzeichnung NICHT gelöscht, bevor der Nutzer
  /// das Blatt gesehen hat: Wer hier schon aufräumte, verlöre drei
  /// Stunden Gehen, wenn das Blatt abstürzt oder weggewischt wird.
  Future<void> _toggleTour() async {
    final notifier = ref.read(tourProvider.notifier);
    if (!notifier.isRunning) {
      final result = await notifier.start();
      if (!mounted) return;
      _showMessage(switch (result) {
        TourStartResult.started => 'Pilztour läuft — der Weg wird '
            'aufgezeichnet.',
        TourStartResult.noPermission =>
          'Ohne Standort-Freigabe kann der Weg nicht aufgezeichnet werden.',
        TourStartResult.noService =>
          'Standortdienste sind aus — bitte in den Einstellungen anschalten.',
        TourStartResult.failed => 'Die Pilztour ließ sich nicht starten.',
      });
      return;
    }

    final tour = await notifier.stop();
    if (!mounted || tour == null) return;
    // Erst räumen, dann zeigen: Die SnackBar vom Starten steht 4 s und
    // legt sich über den unteren Rand des Blatts — also genau über
    // „Eintragen". Dieselbe Lehre wie beim PushListener; die SnackBar
    // reiht sich ein, statt zu weichen.
    ScaffoldMessenger.of(context).clearSnackBars();
    final visits = tourVisits(tour.points, ref.read(mySpotListProvider));
    final booked = await showTourSummarySheet(
      context,
      visits: visits,
      duration: DateTime.now().toUtc().difference(tour.startedAt),
      pointCount: tour.points.length,
    );
    if (!mounted) return;
    // Erst wenn das Blatt durch ist, darf die Datei weg — auch beim
    // Abbrechen: Dann hat der Nutzer bewusst nichts eintragen wollen.
    if (booked != null) await notifier.discard();
    if (!mounted) return;
    if (booked != null && booked > 0) {
      _showMessage(booked == 1
          ? '1 Leergang eingetragen.'
          : '$booked Leergänge eingetragen.');
    }
  }

  /// Fragt nach, wenn schon ein eigener Spot in Reichweite liegt (#215).
  ///
  /// Gibt zurück, ob weiter ein NEUER Spot entstehen soll. Ist die Antwort
  /// „dort eintragen", übernimmt diese Methode gleich den Fund und liefert
  /// `false` — der Aufrufer ist dann fertig.
  ///
  /// Erst fragen, dann das Blatt öffnen: Die beiden Wege brauchen
  /// verschiedene Formulare (Fund am bestehenden Spot vs. neuer Spot), und
  /// ein Hinweis im schon offenen Anlege-Blatt hieße, das falsche steht
  /// bereits da.
  Future<bool> _confirmNewSpotNear(LatLng center) async {
    final near = nearestOwnSpot(ref.read(mySpotListProvider), center);
    if (near == null) return true;

    final choice = await showDialog<_NearbyChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hier liegt schon ein Spot'),
        content: Text(
            '${near.meters.round()} m entfernt liegt „${near.spot.displayName}". '
            'Gehört dein Fund dorthin?'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_NearbyChoice.newSpot),
            child: const Text('Trotzdem neuer Spot'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_NearbyChoice.existingSpot),
            child: const Text('Dort eintragen'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return false;
    if (choice == _NearbyChoice.newSpot) return true;

    await _addFindTo(near.spot);
    return false;
  }

  /// „Dort eintragen": derselbe Weg wie „Fund eintragen" im Spot-Blatt.
  Future<void> _addFindTo(Spot spot) async {
    final ownSpecies = ref.read(ownSpeciesProvider);
    final finds = await showAddFindSheet(
      context,
      lastFind: spot.lastOwnFind,
      ownSpecies: ownSpecies,
      fallbackSpecies: ownSpecies.firstOrNull,
    );
    if (finds == null) return;
    try {
      final fresh = await ref
          .read(mySpotsProvider.notifier)
          .addFinds(spotId: spot.id, finds: finds);
      _showMessage('Fund bei „${spot.displayName}" eingetragen 🍄'
          '${fresh ? '' : staleAfterWriteHint}');
    } catch (e, stackTrace) {
      logError('Fund eintragen', e, stackTrace);
      _showMessage(friendlyError(e));
    }
  }

  /// Neuer Spot an der aktuellen Fadenkreuz-Position (Kartenmitte).
  Future<void> _addSpotAtCrosshair() async {
    final center = _map.center;
    if (!await _confirmNewSpotNear(center)) return;
    if (!mounted) return;
    final ownSpecies = ref.read(ownSpeciesProvider);
    // Ohne `defaultSpecies`: Ein neuer Spot ist meist eine andere Art als
    // der letzte, und die Vorbelegung musste erst gelöscht werden
    // (Issue #155). Beim Wiederbesuch bleibt sie — dort ist die Art des
    // Spots die richtige Annahme (add_find_sheet.dart).
    final data = await showAddSpotSheet(
      context,
      center,
      ownSpecies: ownSpecies,
    );
    if (data == null) return;
    try {
      final fresh = await ref.read(mySpotsProvider.notifier).addSpot(
            lat: center.latitude,
            lng: center.longitude,
            name: data.name,
            finds: data.finds,
          );
      _showMessage('Spot gespeichert 🍄${fresh ? '' : staleAfterWriteHint}');
    } catch (e, stackTrace) {
      logError('Spot speichern', e, stackTrace);
      _showMessage(friendlyError(e));
    }
  }

  /// Beschriftung der Filter-Zeile — nennt beide Bedingungen, sonst
  /// wundert man sich über fehlende Freundes-Spots.
  ///
  /// Ab drei Arten steht die Zahl statt der Namen: Die Zeile teilt sich den
  /// Platz mit den übrigen Bannern, und fünf ausgeschriebene Artnamen
  /// machen daraus einen Absatz.
  String _filterLabel(SpotFilter filter) {
    final names = filter.species.toList()..sort();
    final parts = [
      if (names.length == 1) 'nur ${names.single}',
      if (names.length == 2) 'nur ${names.join(', ')}',
      if (names.length > 2) '${names.length} Arten',
      if (filter.onlyMine) 'nur meine',
    ];
    return '🔍 Gefiltert: ${parts.join(', ')}';
  }

  MapViewMarker _spotMarker(Spot spot) {
    return MapViewMarker(
      point: spot.position,
      width: 44,
      height: 44,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: () => showSpotDetailSheet(context, spot.id),
        child: Tooltip(
          message: spot.pending
              ? '${spot.displayName} — wartet auf Verbindung'
              : spot.isOwn
                  ? spot.displayName
                  : '${spot.displayName} (${spot.ownerUsername ?? 'Freund'})',
          child: MushroomIcon(
            seed: stableSeed(spot.id),
            size: 44,
            friend: !spot.isOwn,
            // Wartet noch auf die Übertragung (#267): halb durchsichtig
            // mit Uhr. Er muss zu sehen sein, sonst legt man denselben
            // Spot ein zweites Mal an — aber er darf nicht wie ein
            // gesicherter aussehen.
            pending: spot.pending,
            group: groupFor(spot.lastFind?.species),
            species: spot.lastFind?.species,
          ),
        ),
      ),
    );
  }

  /// Live-Standort eines Freundes: sein Avatar mit blauem Ring.
  MapViewMarker _friendLocationMarker(FriendLocation loc) {
    return MapViewMarker(
      point: loc.position,
      width: 44,
      height: 44,
      child: Tooltip(
        message: '${loc.username ?? 'Freund'} (live)',
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.friendBlue, width: 2.5),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: MushroomAvatar(index: loc.avatar, size: 39),
        ),
      ),
    );
  }

  /// Eigene Live-Position als Avatar — liegt UNTER den Spot-Markern,
  /// damit die tappbar bleiben.
  MapViewMarker _myPositionMarker(Position position, int avatar) {
    return MapViewMarker(
      point: LatLng(position.latitude, position.longitude),
      width: 40,
      height: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.forestGreen, width: 2.5),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: MushroomAvatar(index: avatar, size: 35),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Breite des Kartenfensters in logischen Pixeln — hier geholt und
    // nicht im Rückruf, damit ein Drehen des Geräts sie mitzieht. Sie
    // ist die zweite Zutat der Bodenauflösung (die erste ist das
    // Sichtfenster), und die Karte füllt die volle Breite.
    final mapWidthPixels = MediaQuery.sizeOf(context).width;
    // Gefiltert statt roh (#154): Der Filter gilt für diese Sitzung und
    // steckt in visibleSpotsProvider, damit die Regel testbar bleibt.
    final visible = ref.watch(visibleSpotsProvider);
    final mySpots = visible.mine;
    final friendSpots = visible.friends;
    final filter = ref.watch(spotFilterProvider);
    final friendLocations = ref.watch(friendLocationsProvider).valueOrNull ??
        const <FriendLocation>[];
    final isSharing = ref.watch(isSharingProvider);
    // Die laufende Pilztour (#338) — `null`, solange keine läuft.
    final tour = ref.watch(tourProvider);
    final shareUntil = ref.watch(myShareProvider).valueOrNull;
    // Verbindung zurück ⇒ Ausgangskorb losschicken (#267). Genau hier
    // und nicht am App-Resume: Wer aus dem Wald nach Hause kommt, ohne
    // die App zu schließen, hat kein Resume — aber sehr wohl einen
    // Wechsel von „kein Netz" auf WLAN.
    ref.listen<bool>(noConnectivityProvider, (previous, next) {
      if (previous == true && next == false) {
        unawaited(ref.read(mySpotsProvider.notifier).sendOutbox());
      }
    });
    // Karten-Abo, ohne Tippen (#332): Sobald der Schalter an ist, ein
    // freies Netz besteht und eine installierte Region veraltet ist,
    // lädt die App sie von selbst nach — und hält an, wenn das freie
    // Netz geht. `fireImmediately`, weil der Fall beim Aufbau schon
    // bestehen kann; ein Wechsel allein käme dann nie.
    ref.listen<MapAutoUpdateInputs>(
      mapAutoUpdateInputsProvider,
      (_, _) => ref.read(mapAutoUpdateProvider.notifier).sync(),
    );
    // Der Sprung zu einem Spot (#345). Der Karten-Screen ist der EINZIGE
    // Ort, an dem ein Fokus-Wunsch in eine Kamerabewegung wird — alle
    // anderen (Banner, Auswahlblatt) schreiben nur den Wunsch.
    //
    // `math.max`, damit ein Sprung nie herauszoomt: Wer schon bei z18
    // über dem Waldstück steht, will nicht auf z16 zurückgesetzt werden.
    ref.listen<MapFocus?>(mapFocusProvider, (_, next) {
      if (next == null) return;
      _map.move(next.target, math.max(_map.zoom, kSpotFocusZoom));
    });
    // Solange ich teile, jede neue Position hochschieben (Bewegung sichtbar).
    ref.listen(positionStreamProvider, (_, next) {
      _maybeUploadLocation(next.valueOrNull);
      // Der erste Fix rastet die Karte ein (#360).
      _maybeSnapToStart(next.valueOrNull);
    });
    // Eigene Live-Position (Marker erscheint erst mit GPS-Fix).
    final myPosition = ref.watch(positionStreamProvider).valueOrNull;
    final myAvatar = ref.watch(myProfileProvider).valueOrNull?.avatar ?? 0;
    // Die einzelnen Ebenen-Zustände braucht der Screen seit #347 nicht
    // mehr: Sie leben im Karten-Blatt, und die Engine wertet ihre
    // Provider für die Schichten ohnehin selbst aus
    // (map_view/flutter_map_view.dart).
    // Wie viele Ebenen liegen auf der Karte — die Zahl im Badge am
    // Karten-Knopf (#347). Sie ersetzt die vier eingefärbten Knöpfe für
    // alle, die die Legende ausgeschaltet haben.
    final activeLayers = activeMapLayerCount(ref);
    final longPressEnabled = ref.watch(mapLongPressEnabledProvider);

    // Die Tour liegt ÜBER dem Scaffold, nicht in seinem `body` (#350):
    // Die Knopfspalte hängt an `floatingActionButton` und läge sonst
    // über der Abdunkelung — jeder Knopf sähe aus wie hervorgehoben.
    // Und sie liegt INNERHALB des Karten-Zweigs, damit sie beim
    // Reiterwechsel mit verschwindet; die Reiterleiste selbst bleibt
    // frei, eine Tour darf nicht einsperren.
    return Stack(
      children: [
  Scaffold(
        body: Stack(
          children: [
            MapView(
              controller: _map,
              config: MapViewConfig(
                initialCenter: _fallbackCenter,
                initialZoom: _fallbackZoom,
                minZoom: _minZoom,
                maxZoom: _maxZoom,
                backgroundColor: AppColors.mapBackground,
                // Long-Press richtet das Fadenkreuz auf die gedrückte Stelle
                // — ab Werk aus (#210), Begründung am Schalter im Profil.
                // `null` heißt für beide Engines schon „nichts tun", die
                // Geste wird also gar nicht erst weitergereicht.
                onLongPress: longPressEnabled
                    ? (latLng) => _map.move(latLng, math.max(_map.zoom, 16))
                    : null,
                // Fadenkreuz-Werte (#235) und Wald-Bildausschnitt (#249):
                // beides rechnet an diesem Stillstand, nie während der
                // Geste.
                onCameraIdle: (center, bounds) {
                  ref.read(mapIdleCenterProvider.notifier).state = center;
                  ref.read(mapIdleBoundsProvider.notifier).state = bounds;
                  // Der Maßstab, in dem die Höhenlinien rechnen. Aus
                  // Sichtfenster UND Pixelbreite, nicht aus der Zoomstufe
                  // der Engine — die zählen MapLibre und flutter_map
                  // verschieden.
                  ref.read(mapIdleGroundResolutionProvider.notifier).state =
                      groundResolution(bounds, mapWidthPixels);
                },
              ),
              markers: MapViewMarkers(
                tourTrack:
                    tour == null ? const [] : tourTrackMarkers(tour.points),
                myPosition: [
                  if (myPosition != null) _myPositionMarker(myPosition, myAvatar),
                ],
                friendLocations: [
                  for (final loc in friendLocations) _friendLocationMarker(loc),
                ],
                spots: [
                  for (final s in friendSpots) _spotMarker(s),
                  for (final s in mySpots) _spotMarker(s),
                ],
              ),
            ),
            // Dauerhaftes, dezentes Fadenkreuz in der Kartenmitte —
            // „Neuer Spot" speichert genau dort.
            IgnorePointer(
              child: Center(child: _Crosshair(key: _tourAnchors.crosshair)),
            ),
            // Die Legende zu den aktiven Ebenen (#231), links unten über
            // dem Maßstab. Nicht mehr in einem IgnorePointer: Das X zum
            // Ausblenden braucht den Tipp — die Karte dahinter verliert
            // nur die kleine Kartenfläche der Legende selbst.
            const SafeArea(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: MapLegend(),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, left: 12, right: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Nur solange es die Geste gibt (#210): Eine
                      // dauerhafte Zeile, die eine abgeschaltete Bedienung
                      // erklärt, wäre schlicht falsch — und sie kostet auf
                      // jedem Bildschirm Platz über den Bannern.
                      if (longPressEnabled)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surface
                                .withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                              'Gedrückt halten richtet das Fadenkreuz aus'),
                        ),
                      const MapBanners(),
                      // Ein aktiver Filter versteckt Spots — das muss man
                      // sehen, ohne das Blatt zu öffnen, sonst sucht man eine
                      // Fundstelle, die nur ausgeblendet ist (#154).
                      if (filter.isActive)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: GestureDetector(
                            onTap: () => showSpotFilterSheet(context),
                            child: Container(
                              padding: const EdgeInsets.only(
                                  left: 12, right: 4, top: 2, bottom: 2),
                              decoration: BoxDecoration(
                                color: AppColors.forestGreen
                                    .withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      _filterLabel(filter),
                                      style:
                                          const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => ref
                                        .read(spotFilterProvider.notifier)
                                        .clear(),
                                    icon: const Icon(Icons.close,
                                        size: 18, color: Colors.white),
                                    tooltip: 'Filter aufheben',
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(6),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (isSharing && shareUntil != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: GestureDetector(
                            onTap: _openShareSheet,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.friendBlue.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '📍 Du teilst deinen Standort bis '
                                '${TimeOfDay.fromDateTime(shareUntil.toLocal()).format(context)} Uhr — antippen',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // **Warum die Knopfspalte schrumpfen darf** (seit den Höhenlinien,
        // 1.98.0): Sie ist mit neun Knöpfen am Anschlag — auf 520 px Höhe
        // lief sie um 24 px über, und ein RenderFlex-Überlauf ist kein
        // Schönheitsfehler, sondern ein Knopf, den niemand erreicht.
        //
        // `scaleDown` greift NUR, wenn es sonst nicht passt: Auf jedem
        // normalen Telefon ändert sich nichts, auf einem kurzen Schirm
        // werden alle Knöpfe ein paar Prozent kleiner — und bleiben
        // sichtbar. Die beiden naheliegenden Alternativen sind schlechter:
        // Engere Abstände verschieben das Problem nur bis zum nächsten
        // Knopf, und eine scrollende Spalte versteckt ausgerechnet die
        // Ebenen-Schalter oben (am Testschirm nachgestellt: Der
        // Waldtypen-Knopf lag bei y = −20).
        floatingActionButton: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.bottomRight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // **Fünf Knöpfe statt zehn** (#347). Die Spalte war mit zehn
              // 604 px hoch auf einem 915-px-Schirm und steckte seit
              // 1.98.0 in dem `FittedBox` hier drüber — jeder neue Knopf
              // machte die anderen kleiner. Der Ausweg war kein weiterer
              // Kompromiss, sondern ein Ordnungsprinzip:
              //
              // Fünf der zehn waren gar keine Schalter, sondern TÜREN ZU
              // BLÄTTERN (Waldtypen, Höhenlinien, Regen, Filter, Standort
              // teilen). Sie kosteten längst zwei Tipps, eine gemeinsame
              // Tür davor kostet also keinen dazu. Und den Zustand, den
              // die eingefärbten Knöpfe trugen, nennt die Legende links
              // unten ohnehin — mit Farbskala und ab Werk an.
              //
              // Verworfen: Speed-Dial (drei Tipps statt zwei, deckt beim
              // Ausklappen die Karte zu), bloßes Kategorisieren (macht die
              // Spalte höher), Knöpfe nach Kontext ausblenden (wer sucht,
              // weiß nicht, dass etwas absichtlich fehlt) und zwei Spalten
              // (verdoppelt die verdeckte Kartenbreite — die Karte ist das
              // Produkt).
              FloatingActionButton.small(
                key: _tourAnchors.layers,
                heroTag: 'layers',
                onPressed: _openLayers,
                // **Nicht „Karte"**: So heißt schon der Reiter unten
                // (`router.dart`). Zwei Dinge desselben Namens auf einem
                // Schirm sind für die Nutzerin so mehrdeutig wie für den
                // Test, der sie sucht — genau daran ist der erste Entwurf
                // aufgefallen.
                //
                // Der Tooltip bleibt fest, die Zahl steht im Badge: Ein
                // Tooltip, dessen Text sich ändert, ist als Suchziel und
                // als Beschriftung gleich schlecht.
                tooltip: 'Ebenen',
                child: Badge(
                  isLabelVisible: activeLayers > 0,
                  label: Text('$activeLayers'),
                  backgroundColor: AppColors.warmBrown,
                  child: Icon(
                      activeLayers > 0 ? Icons.layers : Icons.layers_outlined),
                ),
              ),
              const SizedBox(height: 12),
              // Der Filter bleibt eigenständig: Er entscheidet über die
              // SPOTS, nicht über die Ebenen, und er ist der am häufigsten
              // benutzte der Blatt-Knöpfe.
              FloatingActionButton.small(
                key: _tourAnchors.filter,
                heroTag: 'filter',
                onPressed: () => showSpotFilterSheet(context),
                tooltip: 'Karte filtern',
                backgroundColor: filter.isActive ? AppColors.forestGreen : null,
                foregroundColor: filter.isActive ? Colors.white : null,
                child: Icon(filter.isActive
                    ? Icons.filter_alt
                    : Icons.filter_alt_outlined),
              ),
              const SizedBox(height: 12),
              // Unterwegs: Pilztour und Standort-Teilen. Beide beantworten
              // dieselbe Frage („ich bin draußen"), beide laufen weiter,
              // wenn das Telefon in der Tasche steckt.
              //
              // Blau bei aktivem Teilen — GRÜN bleibt dem Stopp-Knopf
              // darunter vorbehalten, sonst stünden zwei grüne Knöpfe
              // untereinander und keiner wäre die Aussage.
              FloatingActionButton.small(
                key: _tourAnchors.trip,
                heroTag: 'trip',
                onPressed: _openTrip,
                tooltip: 'Unterwegs',
                backgroundColor: isSharing ? AppColors.friendBlue : null,
                foregroundColor: isSharing ? Colors.white : null,
                child: const TourIcon(),
              ),
              // Läuft eine Tour, steht ihr Ausgang ZUSÄTZLICH in der
              // Spalte — nicht anstelle des Knopfs darüber.
              //
              // Der erste Entwurf machte „Unterwegs" bei laufender Tour
              // selbst zum Stopp-Knopf. Damit wäre das Standort-Teilen
              // während einer Tour unerreichbar gewesen, und ein
              // verstecktes Lang-Drücken ist keine Antwort darauf. Ein
              // Knopf mehr in genau dem Modus, in dem man den Ausgang
              // griffbereit haben will, ist der ehrlichere Tausch: fünf
              // Knöpfe normal, sechs während einer Tour.
              if (tour != null) ...[
                const SizedBox(height: 12),
                FloatingActionButton.small(
                  heroTag: 'tour-stop',
                  onPressed: _toggleTour,
                  tooltip: 'Pilztour beenden',
                  backgroundColor: AppColors.forestGreen,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.stop),
                ),
              ],
              const SizedBox(height: 12),
              FloatingActionButton.small(
                key: _tourAnchors.locate,
                heroTag: 'locate',
                onPressed: _centerOnMe,
                tooltip: 'Meine Position',
                child: const Icon(Icons.my_location),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.extended(
                key: _tourAnchors.add,
                heroTag: 'add',
                onPressed: _addSpotAtCrosshair,
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Neuer Spot'),
              ),
              // Messhaken des Engine-Direktvergleichs: deterministische
              // Kamerafahrt gegen die Fassade — identisch auf beiden
              // Engines. `!kReleaseMode`, nicht `kDebugMode`: Die
              // Perfetto-Läufe (Stufe 7) messen im PROFILE-Build, dort
              // muss der Knopf da sein; nur das Release bleibt sauber.
              if (!kReleaseMode) ...[
                const SizedBox(height: 12),
                CameraTourButton(controller: _map),
              ],
            ],
          ),
        ),
      ),
        MapTourOverlay(anchors: _tourAnchors),
      ],
    );
  }
}

/// Kleines, dezentes Fadenkreuz: Ring + Haarlinien, grün mit weißem Halo.
class _Crosshair extends StatelessWidget {
  const _Crosshair({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(34, 34),
      painter: _CrosshairPainter(),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final halo = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = AppColors.forestGreen.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    const radius = 9.0;
    const arm = 6.0;

    for (final paint in [halo, line]) {
      canvas.drawCircle(center, radius, paint);
      canvas.drawLine(center - const Offset(0, radius + arm),
          center - const Offset(0, radius + 1.5), paint);
      canvas.drawLine(center + const Offset(0, radius + 1.5),
          center + const Offset(0, radius + arm), paint);
      canvas.drawLine(center - const Offset(radius + arm, 0),
          center - const Offset(radius + 1.5, 0), paint);
      canvas.drawLine(center + const Offset(radius + 1.5, 0),
          center + const Offset(radius + arm, 0), paint);
    }
    canvas.drawCircle(center, 1.8, Paint()..color = Colors.white);
    canvas.drawCircle(center, 1.1, Paint()..color = AppColors.forestGreen);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
