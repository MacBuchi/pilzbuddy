// Die Kamerafahrt: eine deterministische ~60-Sekunden-Choreographie
// gegen die MapView-Fassade — auf beiden Engines exakt gleich, damit
// die Perfetto-Frame-Messung des Direktvergleichs (Migrationsstufe 7)
// vergleichbare Last misst. Nur im Debug-Build sichtbar (map_screen.dart
// baut den Knopf hinter kDebugMode ein).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'map_view.dart';

/// Ein Schritt der Fahrt: Sprung zu [center]/[zoom], dann [hold] warten.
class CameraTourStep {
  const CameraTourStep(this.label, this.center, this.zoom, this.hold);

  final String label;
  final LatLng center;
  final double zoom;
  final Duration hold;
}

const _muenchen = LatLng(48.137, 11.575);
const _berlin = LatLng(52.52, 13.405);

/// Die Choreographie — geprüft in test/camera_tour_test.dart. Sie mischt
/// harte Sprünge (alles neu laden) mit Wisch-Schritten auf hoher
/// Zoomstufe (die Markerlast, in der #151 saß) und endet am Start.
const cameraTourSteps = <CameraTourStep>[
  CameraTourStep('Start DE', LatLng(51.1634, 10.4477), 6.5,
      Duration(seconds: 4)),
  CameraTourStep('München z11', _muenchen, 11, Duration(seconds: 4)),
  CameraTourStep('München z14', _muenchen, 14, Duration(seconds: 4)),
  CameraTourStep('München z16', _muenchen, 16, Duration(seconds: 4)),
  // Wischen bei z16: vier kleine Schritte nach Osten/Norden.
  CameraTourStep('Pan 1', LatLng(48.137, 11.595), 16, Duration(seconds: 3)),
  CameraTourStep('Pan 2', LatLng(48.147, 11.615), 16, Duration(seconds: 3)),
  CameraTourStep('Pan 3', LatLng(48.157, 11.635), 16, Duration(seconds: 3)),
  CameraTourStep('Pan 4', LatLng(48.167, 11.655), 16, Duration(seconds: 3)),
  CameraTourStep('München z19', LatLng(48.137, 11.575), 19,
      Duration(seconds: 4)),
  CameraTourStep('Garmisch z13', LatLng(47.492, 11.096), 13,
      Duration(seconds: 4)),
  CameraTourStep('München z8', _muenchen, 8, Duration(seconds: 4)),
  CameraTourStep('Berlin z11', _berlin, 11, Duration(seconds: 4)),
  CameraTourStep('Berlin z15', _berlin, 15, Duration(seconds: 4)),
  CameraTourStep('Berlin Pan', LatLng(52.53, 13.425), 15,
      Duration(seconds: 3)),
  CameraTourStep('Ende DE', LatLng(51.1634, 10.4477), 6.5,
      Duration(seconds: 4)),
];

/// Der Messknopf: startet die Fahrt gegen den Fassaden-Controller,
/// zweiter Tipp bricht ab. Zeigt den laufenden Schritt an, damit im
/// Perfetto-Trace der Abschnitt zuordenbar ist.
class CameraTourButton extends StatefulWidget {
  const CameraTourButton({super.key, required this.controller});

  final MapViewController controller;

  @override
  State<CameraTourButton> createState() => _CameraTourButtonState();
}

class _CameraTourButtonState extends State<CameraTourButton> {
  Timer? _timer;
  int _step = -1;

  bool get _running => _timer != null;

  void _advance() {
    _step++;
    if (_step >= cameraTourSteps.length) {
      _stop();
      return;
    }
    final step = cameraTourSteps[_step];
    widget.controller.move(step.center, step.zoom);
    _timer = Timer(step.hold, _advance);
    setState(() {});
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _step = -1;
    if (mounted) setState(() {});
  }

  void _toggle() {
    if (_running) {
      _stop();
    } else {
      _advance();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'camera-tour',
      onPressed: _toggle,
      backgroundColor: _running ? Colors.red.shade700 : null,
      icon: Icon(_running ? Icons.stop : Icons.videocam_outlined),
      label: Text(_running
          ? '${_step + 1}/${cameraTourSteps.length} '
              '${cameraTourSteps[_step].label}'
          : 'Kamerafahrt'),
    );
  }
}
