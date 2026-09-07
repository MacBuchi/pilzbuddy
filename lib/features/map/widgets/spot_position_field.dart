import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/geo.dart';
import '../position_provider.dart';
import 'mini_map.dart';

/// Die Stelle eines NEUEN Spots, auf der Karte bestimmbar (#407).
///
/// **Kein Modus-Schalter, anders als beim Fund.** Dort gibt es drei
/// Antworten („am Spot", GPS, gewählt), weil ein Fund auch gar keine
/// eigene Stelle haben darf. Hier gibt es nur eine Stelle — die des
/// Spots —, und die Mitte des Ausschnitts IST sie. „Meine Position"
/// schiebt die Karte dorthin, statt einen eigenen Zustand aufzumachen;
/// danach kann man weiterschieben, und die Wahl bleibt eindeutig.
///
/// **Beim Öffnen wird NIE nach der Berechtigung gefragt.** Die
/// Vorbelegung ist das Fadenkreuz, mit dem der Nutzer das Blatt geöffnet
/// hat; der laufende Positionsstrom fragt bewusst nie
/// (`position_provider.dart`), und der Systemdialog kommt ausschließlich
/// auf Tipp. Daran hängt der Abschnitt „Prominent Disclosure" in
/// `docs/play-console.md` — dieselbe Zusage wie bei `FindPositionField`,
/// hier noch einmal, weil eine Kopie keine Zusagen erbt.
class SpotPositionField extends ConsumerStatefulWidget {
  const SpotPositionField({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  /// Womit das Blatt geöffnet wurde — Fadenkreuz oder Importpunkt. Bleibt
  /// der Bezugspunkt: Der Ring auf der Karte zeigt, wie weit man sich
  /// davon entfernt hat.
  final LatLng initial;

  final ValueChanged<LatLng> onChanged;

  @override
  ConsumerState<SpotPositionField> createState() => _SpotPositionFieldState();
}

class _SpotPositionFieldState extends ConsumerState<SpotPositionField> {
  late LatLng _chosen = widget.initial;

  /// Worauf die Karte schaut. Bewusst NICHT [_chosen]: Gäbe man die
  /// gemeldete Mitte als `center` zurück, schöbe die Karte sich unter dem
  /// Finger selbst nach (dieselbe Falle wie im Fund-Blatt).
  late LatLng _center = widget.initial;

  /// Steht hier etwas, ist die letzte Abfrage ins Leere gelaufen.
  String? _notice;

  Future<void> _useMyPosition() async {
    // Erst der laufende Strom, dann eine einzelne Abfrage — die fragt
    // nötigenfalls nach der Berechtigung. Dieselbe Reihenfolge wie im
    // Fund-Blatt und beim Standort-Teilen.
    var fix = ref.read(positionStreamProvider).valueOrNull;
    fix ??= await ref.read(positionFixProvider)();
    if (!mounted) return;
    if (fix == null) {
      setState(() => _notice =
          'Standort nicht verfügbar. Berechtigung erteilt? Der Spot bleibt '
          'an der gewählten Stelle.');
      return;
    }
    final at = LatLng(fix.latitude, fix.longitude);
    setState(() {
      _center = at;
      _chosen = at;
      _notice = null;
    });
    widget.onChanged(at);
  }

  void _onPicked(LatLng at) {
    // Kein `setState` auf [_center] — siehe dort.
    _chosen = at;
    widget.onChanged(at);
    setState(() => _notice = null);
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final moved = distanceMeters(widget.initial.latitude,
        widget.initial.longitude, _chosen.latitude, _chosen.longitude);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MiniMap(
          mode: MiniMapMode.pick,
          center: _center,
          reference: widget.initial,
          onCenterChanged: _onPicked,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                _detail(moved),
                style: small,
              ),
            ),
            TextButton.icon(
              onPressed: _useMyPosition,
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Meine Position'),
            ),
          ],
        ),
      ],
    );
  }

  /// Die Zeile unter der Karte: immer die Koordinate, und ab einer
  /// Verschiebung auch, wie weit man vom Ausgangspunkt weg ist.
  ///
  /// Die Entfernung erst ab einem Meter: Beim Schieben wackelt die Mitte
  /// um Zentimeter, und „0 m verschoben" wäre eine Zahl, die nur
  /// beschäftigt.
  String _detail(double moved) {
    if (_notice case final notice?) return notice;
    final coordinates = '${_chosen.latitude.toStringAsFixed(5)}, '
        '${_chosen.longitude.toStringAsFixed(5)}';
    if (moved < 1) return coordinates;
    return '$coordinates · ${formatMeters(moved)} verschoben';
  }
}
