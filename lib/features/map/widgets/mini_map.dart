import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/app_colors.dart';
import '../../offline_maps/offline_map_providers.dart';
import '../../spots/nearby_spots.dart' show kNearbySpotMeters;
import '../finite_camera_constraint.dart';
import '../map_view/flutter_map_view.dart' show tileProviderFactoryProvider;
import 'crosshair.dart';

/// Ein kleiner Kartenausschnitt im Formular (#373).
///
/// **Bewusst NICHT die MapView-Fassade**, obwohl es naheliegt. Drei
/// Gründe, der erste wiegt am schwersten:
///
/// 1. `FlutterMapView` füllt aus `onCameraIdle` die globalen
///    `mapIdle*`-Provider. An denen hängen die Äquidistanz der
///    Höhenlinien, der Wald-Bildausschnitt (#249) und die Legendenwerte
///    (#235) — eine zweite Karte mit derselben Verdrahtung überschriebe
///    sie mit dem Maßstab einer Briefmarke, und die große Karte hinter
///    dem Blatt rechnete danach damit weiter.
/// 2. Sie liest Wald-, Regen- und Höhenlinien-Provider bedingungslos.
///    Dieser Ausschnitt soll nackt sein: Er beantwortet „liegt der Punkt
///    richtig", nicht „wie ist das Wetter".
/// 3. `MapViewMarker` kennt nur Pixelgrößen. Der Genauigkeitskreis ist in
///    METERN, und der Fassade beides beizubringen hieße, es beiden
///    Engines beizubringen — für ein Formularfeld, das auf MapLibre nie
///    laufen soll.
///
/// **Immer flutter_map, nie MapLibre** — auch auf Android, wo die große
/// Karte MapLibre ist. Eine zweite `MapLibreMap` wäre eine zweite native
/// GL-Fläche in einem scrollenden Blatt, im Widget-Test nicht renderbar,
/// und sie erbte das Risiko einer exakt gepinnten jungen Abhängigkeit.
/// Der Preis ist ehrlich: Auf Android sieht der Ausschnitt anders aus als
/// die Karte dahinter. Erträglich, weil er absichtlich nackt ist — er
/// liest sich als Detailausschnitt, nicht als dieselbe Karte im falschen
/// Kostüm.
///
/// **Zwei Invarianten sind von Hand mitkopiert**, weil sie an JEDER
/// `MapOptions` hängen und bis hierher nur in `flutter_map_view.dart`
/// standen: [FiniteCameraConstraint] (die ANR-Kette aus #141/#151) und
/// genau eine TileProvider-Instanz pro eingehängtem TileLayer (#157).
/// Beide sind in `test/mini_map_test.dart` festgenagelt.
enum MiniMapMode {
  /// Verschiebbar, mit Fadenkreuz in der Mitte — die Mitte IST die Wahl.
  pick,

  /// Nur Anschauung: der Fix als Punkt samt Streukreis.
  fix,
}

/// Wie viel von der Kastenkante der maßgebliche Kreis einnehmen soll.
const _fillRatio = 0.4;

/// Meter je Pixel am Äquator bei Zoom 0 (Web-Mercator, 256er-Kacheln).
const _equatorMetersPerPixel = 156543.03392;

/// Startzoom, bei dem ein Kreis von [radiusMeters] rund 40 % der
/// Kastenkante einnimmt.
///
/// Als reine Funktion herausgezogen, weil das der Teil ist, der wirklich
/// schiefgehen kann — und der sich ohne Karte, ohne Kachel und ohne
/// Pumpen prüfen lässt.
///
/// Geklemmt auf [14, 18.5]: Weiter heraus verliert der Ausschnitt seinen
/// Zweck (man sieht den Spot nicht mehr im Gelände), weiter hinein gibt
/// es bei OSM keine Kacheln mehr.
double miniMapZoomFor({
  required double radiusMeters,
  required double boxPixels,
  required double latitude,
}) {
  final metersPerPixel =
      2 * math.max(radiusMeters, 1) / (_fillRatio * boxPixels);
  final zoom = math.log(_equatorMetersPerPixel *
          math.cos(latitude * math.pi / 180) /
          metersPerPixel) /
      math.ln2;
  return zoom.clamp(14.0, 18.5);
}

class MiniMap extends ConsumerStatefulWidget {
  const MiniMap({
    super.key,
    required this.mode,
    required this.center,
    required this.reference,
    this.accuracyM,
    this.height = 180,
    this.onCenterChanged,
  });

  final MiniMapMode mode;

  /// Worauf die Karte schaut — im Wähl-Modus der Startpunkt, im
  /// Anschau-Modus der Fix.
  final LatLng center;

  /// Der Spot: Pin plus 20-m-Ring, damit „wie weit weg" sichtbar wird und
  /// nicht nur als Zahl darunter steht.
  final LatLng reference;

  /// Streuradius des Fixes in Metern — nur im [MiniMapMode.fix].
  final double? accuracyM;

  final double height;

  /// Meldet die neue Mitte, aber NUR bei Stillstand.
  ///
  /// **Der Aufrufer darf sie nicht als [center] zurückgeben**, sonst
  /// schöbe `didUpdateWidget` die Karte unter dem Finger nach — eine
  /// Rückkopplung. [center] ist der Startpunkt, nicht der laufende Wert.
  final ValueChanged<LatLng>? onCenterChanged;

  @override
  ConsumerState<MiniMap> createState() => _MiniMapState();
}

class _MiniMapState extends ConsumerState<MiniMap> {
  final _map = MapController();

  /// #157: GENAU EINE Instanz pro eingehängtem TileLayer. Eine neue je
  /// Rebuild (und hier baut jeder Tastendruck im Formular neu) leckte
  /// jedes Mal einen HTTP-Client.
  TileProvider? _tileProvider;

  /// Vor `onMapReady` wirft `MapController.camera` — der Zustand dahinter
  /// ist noch `null`. Dieselbe Lehre wie `_pendingMove` in der
  /// MapLibre-Fassade.
  bool _ready = false;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MiniMap old) {
    super.didUpdateWidget(old);
    // Auch beim Moduswechsel neu setzen: `initialZoom` ist initial, und
    // ein ±5-m-Fix braucht einen anderen Maßstab als ein 20-m-Ring.
    if (_ready &&
        (old.center != widget.center || old.mode != widget.mode)) {
      _map.move(widget.center, _zoom);
    }
  }

  double get _zoom => miniMapZoomFor(
        radiusMeters: widget.accuracyM ?? kNearbySpotMeters,
        boxPixels: widget.height,
        latitude: widget.center.latitude,
      );

  @override
  Widget build(BuildContext context) {
    final picking = widget.mode == MiniMapMode.pick;
    final offline = ref.watch(noConnectivityProvider);
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            FlutterMap(
              key: const ValueKey('mini-map'),
              mapController: _map,
              options: MapOptions(
                initialCenter: widget.center,
                initialZoom: _zoom,
                minZoom: 14,
                maxZoom: 19,
                // Der Landton der großen Karte, nicht Grau: Wo keine
                // Kachel kommt, soll es nach Gelände aussehen und nicht
                // nach Fehler.
                backgroundColor: AppColors.mapBackground,
                // Pflicht an JEDER MapOptions, nicht nur an der großen
                // Karte: Ein nicht-endlicher Kamerazustand aus einem
                // Gesten-Grenzfall reicht für graue Flächen und den
                // Allokationssturm aus #151.
                cameraConstraint: const FiniteCameraConstraint(),
                interactionOptions: InteractionOptions(
                  // Im Anschau-Modus KEINE Drag-Erkenner — dann geht der
                  // Wischer an den SingleChildScrollView des Blattes
                  // durch. Im Wähl-Modus fängt flutter_map ihn mit seinen
                  // eigenen absorbierenden Erkennern ab, und die Karte
                  // behält ihn. Genau dafür sind sie im Paket da.
                  //
                  // Kein Drehen (Hausregel beider Engines) und kein
                  // Schwung: In 180 px schießt er über das Ziel hinaus.
                  flags: picking
                      ? InteractiveFlag.all &
                          ~InteractiveFlag.rotate &
                          ~InteractiveFlag.flingAnimation
                      : InteractiveFlag.none,
                ),
                onMapReady: () => _ready = true,
                // `onMapEvent` und NICHT `onPositionChanged`: Letzteres
                // feuert während der ganzen Geste. Die Zahl darunter
                // („12 m vom Spot") flackerte dann mit jedem Frame, und
                // jeder Frame baute das Formular neu.
                onMapEvent: (event) {
                  if (!picking) return;
                  if (event is MapEventMoveEnd ||
                      event is MapEventDoubleTapZoomEnd ||
                      event is MapEventScrollWheelZoom) {
                    widget.onCenterChanged?.call(event.camera.center);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'de.mcbuchi.pilzbuddy',
                  tileProvider:
                      _tileProvider ??= ref.read(tileProviderFactoryProvider)(),
                  // Puffer bewusst auf der Paketvorgabe (2/1) — dieselbe
                  // Zahl, die #142 für die große Karte gemessen hat. Eine
                  // eigene wäre eine Stellschraube ohne Messung
                  // (docs/map-performance.md).
                ),
                CircleLayer(circles: [
                  // „So weit gilt es noch als derselbe Ort" (#215).
                  CircleMarker(
                    point: widget.reference,
                    radius: kNearbySpotMeters,
                    useRadiusInMeter: true,
                    color: Colors.transparent,
                    borderStrokeWidth: 1.2,
                    borderColor:
                        AppColors.forestGreen.withValues(alpha: 0.45),
                  ),
                  // Die Streuung des Fixes ist ein KREIS, keine Zahl.
                  // `useRadiusInMeter` ist hier tragend: Ohne das Flag
                  // werden aus ±8 Metern still 8 Pixel, und nichts an der
                  // Oberfläche schreit.
                  if (!picking && widget.accuracyM != null)
                    CircleMarker(
                      point: widget.center,
                      radius: widget.accuracyM!,
                      useRadiusInMeter: true,
                      color: AppColors.friendBlue.withValues(alpha: 0.18),
                      // Der Rand ist nicht Zierde: Die Füllung zeichnet
                      // flutter_map ohne Kantenglättung, der Strich deckt
                      // die Treppe zu.
                      borderStrokeWidth: 1.5,
                      borderColor:
                          AppColors.friendBlue.withValues(alpha: 0.7),
                    ),
                ]),
                MarkerLayer(markers: [
                  Marker(
                    point: widget.reference,
                    width: 22,
                    height: 22,
                    child: const Icon(Icons.place,
                        size: 22, color: AppColors.forestGreen),
                  ),
                  if (!picking)
                    Marker(
                      point: widget.center,
                      width: 14,
                      height: 14,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.friendBlue,
                          border: Border.fromBorderSide(
                              BorderSide(color: Colors.white, width: 2)),
                        ),
                      ),
                    ),
                ]),
                // Ohne Kachel trägt der Maßstab die Aussage mit: Zwei
                // beschriftete Kreise auf Landton sind eine Karte, eine
                // graue Fläche ist keine.
                const Scalebar(
                  alignment: Alignment.bottomLeft,
                  padding: EdgeInsets.all(6),
                ),
                // Lizenzpflicht, nicht Kür — dieselbe Nennung wie auf der
                // großen Karte.
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap-Mitwirkende'),
                  ],
                ),
              ],
            ),
            if (picking)
              const IgnorePointer(child: Center(child: Crosshair(size: 26))),
            if (offline)
              Positioned(
                top: 6,
                left: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      'Karte offline — die Stelle wird trotzdem gespeichert',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
