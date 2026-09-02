import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/geo.dart';
import '../../../models/find_position.dart';
import '../../map/position_provider.dart';
import '../../map/widgets/mini_map.dart';
import '../find_offset.dart';

/// Woher die Stelle eines Fundes kommt (#373).
///
/// [spot] ist kein Ort, sondern seine Abwesenheit: „nimm den des Spots",
/// also genau das Verhalten von vor Patch 022. [picked] ist die auf der
/// Karte gewählte Stelle — ohne Genauigkeit, weil ein Fadenkreuz keinen
/// Messfehler hat.
enum FindPositionMode { spot, gps, picked }

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

  /// Worauf die Wähl-Karte beim Öffnen schaut. Bewusst NICHT der
  /// laufende Wert: Gäbe man die gemeldete Mitte als `center` zurück,
  /// schöbe die Karte sich unter dem Finger selbst nach.
  LatLng? _pickStart;

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
    if (mode == FindPositionMode.picked) {
      // Startpunkt ist die zuletzt gewählte Stelle, sonst der Spot — man
      // fängt dort an zu suchen, wo man aufgehört hat.
      final start = _chosen == null
          ? widget.spotAt
          : LatLng(_chosen!.lat, _chosen!.lng);
      final position =
          FindPosition.picked(lat: start.latitude, lng: start.longitude);
      setState(() {
        _mode = mode;
        _pickStart = start;
        _chosen = position;
        _notice = null;
      });
      widget.onChanged(position);
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

  /// Die Karte steht still — die Mitte ist die Wahl.
  void _onPicked(LatLng center) {
    final position =
        FindPosition.picked(lat: center.latitude, lng: center.longitude);
    setState(() => _chosen = position);
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
        // Ohne Symbole: Drei Beschriftungen teilen sich auf einem
        // 360-dp-Schirm rund 100 dp je Segment, ein Symbol daneben
        // kürzte „Meine Position" zu „Meine P…".
        SegmentedButton<FindPositionMode>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(
              value: FindPositionMode.spot,
              label: Text('Am Spot'),
            ),
            ButtonSegment(
              value: FindPositionMode.gps,
              label: const Text('Meine Position'),
              enabled: blocked == null,
            ),
            const ButtonSegment(
              value: FindPositionMode.picked,
              label: Text('Auf Karte'),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (selection) => _choose(selection.first),
        ),
        // Die Karte wird NUR gebaut, wenn es etwas zu zeigen gibt. „Am
        // Spot" ist der Normalfall — dort kostete ein Kartenausschnitt
        // Speicher und Kacheln für eine Aussage, die schon dasteht.
        if (_mode != FindPositionMode.spot && _chosen != null) ...[
          const SizedBox(height: 8),
          MiniMap(
            mode: _mode == FindPositionMode.picked
                ? MiniMapMode.pick
                : MiniMapMode.fix,
            center: _mode == FindPositionMode.picked
                ? (_pickStart ?? widget.spotAt)
                : LatLng(_chosen!.lat, _chosen!.lng),
            reference: widget.spotAt,
            accuracyM: _chosen!.accuracyM,
            onCenterChanged: _onPicked,
          ),
        ],
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
        if (accuracy == null) 'Gewählte Stelle' else '±${formatMeters(accuracy)}',
        '${formatMeters(offset)} vom Spot',
      ].join(' · ');
    }
    if (blocked != null) return '$blocked — der Fund gilt am Spot.';
    return 'Der Fund gilt für den Ort des Spots.';
  }
}
