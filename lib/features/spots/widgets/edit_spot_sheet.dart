// Name und Stelle eines eigenen Spots nachträglich korrigieren (#466).
//
// **Warum es das braucht:** Unter Blätterdach liegt ein GPS-Fix 10–20 m
// daneben, und bis 1.144.0 war die Stelle beim Anlegen endgültig. Der
// Name ebenso — gesetzt beim Anlegen, danach nie wieder erreichbar.
//
// **Warum dasselbe Blatt für beides.** Es ist derselbe Fehler: „ich habe
// das beim Anlegen in Eile falsch gemacht". Zwei Blätter wären zwei
// Wege zu einer Antwort, und das Positionsfeld ist ohnehin dasselbe
// Widget wie im Anlege-Blatt (#407) — die Stelle wird also überall
// gleich gewählt, mit demselben Ring um den Ausgangspunkt und derselben
// Entfernungszeile.
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/app_colors.dart';
import '../../map/widgets/spot_position_field.dart';

/// Was der Nutzer korrigiert hat.
class EditedSpotData {
  const EditedSpotData({required this.name, required this.position});

  /// `null` heißt „kein Name" — dieselbe Bedeutung wie beim Anlegen, wo
  /// ein leeres Feld zu `null` wird und die Liste „Pilz-Spot" anzeigt.
  /// Ein leerer String wäre ein zweiter Weg, dasselbe zu sagen.
  final String? name;

  final LatLng position;
}

/// `null`, wenn abgebrochen wurde — wie bei allen Blättern hier.
Future<EditedSpotData?> showEditSpotSheet(
  BuildContext context, {
  required String? name,
  required LatLng position,
}) {
  return showModalBottomSheet<EditedSpotData>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _EditSpotSheet(name: name, position: position),
  );
}

class _EditSpotSheet extends StatefulWidget {
  const _EditSpotSheet({required this.name, required this.position});

  final String? name;
  final LatLng position;

  @override
  State<_EditSpotSheet> createState() => _EditSpotSheetState();
}

class _EditSpotSheetState extends State<_EditSpotSheet> {
  late final _nameController = TextEditingController(text: widget.name ?? '');

  /// Die Stelle, die gerade gilt — anfangs die bisherige.
  late LatLng _position = widget.position;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    Navigator.of(context).pop(EditedSpotData(
      name: name.isEmpty ? null : name,
      position: _position,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.edit_location_alt_outlined,
                    color: AppColors.forestGreen),
                const SizedBox(width: 8),
                Text('Spot bearbeiten',
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 8),
            // Der Ring liegt auf der BISHERIGEN Stelle, nicht auf der
            // eigenen Position: Die Frage hier ist „wie weit weg von dem,
            // was gespeichert war", nicht „wie weit weg von mir".
            SpotPositionField(
              initial: widget.position,
              onChanged: (at) => _position = at,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                hintText: 'z. B. Fichtenhang am Bach',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Speichern'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
