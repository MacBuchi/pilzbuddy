import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/geo.dart';
import '../../../models/find_position.dart';
import '../../map/position_provider.dart';
import '../find_offset.dart';

/// Woher die Stelle eines Fundes kommt (#373).
///
/// [spot] ist kein Ort, sondern seine Abwesenheit: „nimm den des Spots",
/// also genau das Verhalten von vor Patch 022.
enum FindPositionMode { spot, gps }

/// Die Wahl der Fundstelle im Eintragen-Blatt.
///
/// **Das Feld fragt beim Öffnen NIE nach der Berechtigung.** Die
/// Vorbelegung liest den laufenden Positionsstrom, der bewusst nie fragt
/// (`position_provider.dart`); der Systemdialog kommt ausschließlich,
/// wenn jemand „Meine Position" antippt. Genau diese Trennung ist die
/// Zusage im Abschnitt „Prominent Disclosure" von `docs/play-console.md`
/// — und sie ist als Test festgenagelt.
class FindPositionField extends ConsumerStatefulWidget {
  const FindPositionField({
    super.key,
    required this.spotAt,
    required this.onChanged,
  });

  /// Der Ort des Spots — Bezugspunkt für „wie weit weg stehe ich".
  final LatLng spotAt;

  /// `null` heißt „am Spot", also keine eigene Stelle für diesen Fund.
  final ValueChanged<FindPosition?> onChanged;

  @override
  ConsumerState<FindPositionField> createState() => _FindPositionFieldState();
}

class _FindPositionFieldState extends ConsumerState<FindPositionField> {
  FindPositionMode _mode = FindPositionMode.spot;
  FindPosition? _chosen;

  /// Steht hier etwas, ist die letzte Abfrage ins Leere gelaufen.
  String? _notice;

  @override
  void initState() {
    super.initState();
    // Einmalig aus dem laufenden Strom vorbelegen — ohne zu fragen. Wer
    // zweifelsfrei am Spot steht, soll die Stelle nicht erst antippen
    // müssen; wer abends auf dem Sofa nachträgt, bekommt sie nie
    // untergeschoben.
    final fix = ref.read(positionStreamProvider).valueOrNull;
    if (fix != null &&
        fix.accuracy <= kFindUsableAccuracyM &&
        _offsetOf(fix.latitude, fix.longitude) <= kFindFixNearM) {
      _mode = FindPositionMode.gps;
      _chosen = FindPosition.gps(
          lat: fix.latitude, lng: fix.longitude, accuracy: fix.accuracy);
      // Nach dem ersten Frame, weil der Aufrufer während `initState`
      // noch nicht auf ein `setState` reagieren darf.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onChanged(_chosen));
    }
  }

  double _offsetOf(double lat, double lng) => distanceMeters(
      widget.spotAt.latitude, widget.spotAt.longitude, lat, lng);

  /// Warum „Meine Position" gerade nicht geht — oder `null`, wenn sie geht.
  ///
  /// Ein fehlender Fix ist ausdrücklich KEIN Grund zu sperren: Ohne
  /// erteilte Berechtigung liefert der Strom nie etwas, und ein
  /// gesperrter Knopf ließe sich dann nie mehr entsperren. Der Tipp holt
  /// den Fix — und fragt dabei.
  String? _blockedBecause() {
    final fix = ref.read(positionStreamProvider).valueOrNull;
    if (fix == null) return null;
    if (fix.accuracy > kFindUsableAccuracyM) {
      return 'GPS zu ungenau (±${formatMeters(fix.accuracy)})';
    }
    final offset = _offsetOf(fix.latitude, fix.longitude);
    if (offset > kFindFixMaxOffsetM) {
      return 'Du bist ${formatMeters(offset)} vom Spot entfernt';
    }
    return null;
  }

  Future<void> _choose(FindPositionMode mode) async {
    if (mode == FindPositionMode.spot) {
      setState(() {
        _mode = mode;
        _chosen = null;
        _notice = null;
      });
      widget.onChanged(null);
      return;
    }
    // Erst der laufende Strom, dann eine einzelne Abfrage — die fragt
    // nötigenfalls nach der Berechtigung. Dieselbe Reihenfolge wie beim
    // Standort-Teilen auf der Karte.
    var fix = ref.read(positionStreamProvider).valueOrNull;
    fix ??= await ref.read(positionFixProvider)();
    if (!mounted) return;
    if (fix == null) {
      setState(() => _notice = 'Standort nicht verfügbar. Berechtigung '
          'erteilt? Der Fund wird ohne eigene Stelle gespeichert.');
      return;
    }
    final position = FindPosition.gps(
        lat: fix.latitude, lng: fix.longitude, accuracy: fix.accuracy);
    setState(() {
      _mode = mode;
      _chosen = position;
      _notice = null;
    });
    widget.onChanged(position);
  }

  @override
  Widget build(BuildContext context) {
    // Beobachten, damit ein später eintreffender Fix die Sperre und die
    // Zahlen aktualisiert.
    ref.watch(positionStreamProvider);
    final blocked = _blockedBecause();
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Fundstelle', style: small),
        ),
        const SizedBox(height: 6),
        SegmentedButton<FindPositionMode>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(
              value: FindPositionMode.spot,
              icon: Icon(Icons.place_outlined, size: 18),
              label: Text('Am Spot'),
            ),
            ButtonSegment(
              value: FindPositionMode.gps,
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Meine Position'),
              enabled: blocked == null,
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (selection) => _choose(selection.first),
        ),
        const SizedBox(height: 6),
        Text(_detail(blocked), style: small),
      ],
    );
  }

  /// Die Zeile unter der Wahl — sie trägt die Aussage auch dann, wenn
  /// jemand die Zahlen nicht deuten kann: „ist das hier, oder nicht?"
  String _detail(String? blocked) {
    if (_notice case final notice?) return notice;
    if (_chosen case final position?) {
      final offset = _offsetOf(position.lat, position.lng);
      final accuracy = position.accuracyM;
      return [
        if (accuracy != null) '±${formatMeters(accuracy)}',
        '${formatMeters(offset)} vom Spot',
      ].join(' · ');
    }
    if (blocked != null) return '$blocked — der Fund gilt am Spot.';
    return 'Der Fund gilt für den Ort des Spots.';
  }
}
