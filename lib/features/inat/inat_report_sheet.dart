// Nachträglich an iNaturalist melden (#553 Stufe 2) — ein eigenes,
// kleines Blatt für einen Fund, der schon eingetragen ist.
//
// Derselbe Abschnitt wie im Blatt „Fund eintragen", nur ohne Schalter:
// Wer das Blatt geöffnet hat, will melden. Ein Buddy-Foto bietet es
// NICHT an — das liegt nach dem Eintragen im Bucket, lebt 14 Tage und
// müsste erst geladen werden; eigene Fotos wählt man hier neu.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/photo_providers.dart';
import '../../models/find.dart';
import 'inat_report_section.dart';
import 'inat_reporter.dart';

const kInatReportSheetSendKey = Key('inat-report-sheet-send');

Future<InatReportDraft?> showInatReportSheet(
  BuildContext context, {
  required Find find,
  required List<String> presetTrees,
  required PhotoPicker pickPhoto,
  required PhotoPreparer preparePhoto,
}) =>
    showModalBottomSheet<InatReportDraft>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _InatReportSheet(
        find: find,
        presetTrees: presetTrees,
        pickPhoto: pickPhoto,
        preparePhoto: preparePhoto,
      ),
    );

class _InatReportSheet extends StatefulWidget {
  const _InatReportSheet({
    required this.find,
    required this.presetTrees,
    required this.pickPhoto,
    required this.preparePhoto,
  });

  final Find find;
  final List<String> presetTrees;
  final PhotoPicker pickPhoto;
  final PhotoPreparer preparePhoto;

  @override
  State<_InatReportSheet> createState() => _InatReportSheetState();
}

class _InatReportSheetState extends State<_InatReportSheet> {
  late InatSectionValue _value =
      InatSectionValue(enabled: true, trees: widget.presetTrees);
  bool _missingPhoto = false;

  void _send() {
    final draft = _value.draftWith(null);
    if (draft == null || draft.photos.isEmpty) {
      setState(() => _missingPhoto = true);
      return;
    }
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            Row(children: [
              const Icon(Icons.public),
              const SizedBox(width: 8),
              Text('An iNaturalist melden', style: theme.textTheme.titleLarge),
            ]),
            const SizedBox(height: 4),
            Text(
              '${widget.find.label} · '
              '${DateFormat('d.M.y').format(widget.find.foundOn)} — mit '
              'Foto, unter deinem Namen. Bestätigt die Community die Art, '
              'geht die Beobachtung weiter an GBIF.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            InatReportSection(
              species: widget.find.species,
              multiple: false,
              presetTrees: widget.presetTrees,
              pickPhoto: widget.pickPhoto,
              preparePhoto: widget.preparePhoto,
              buddyPhoto: null,
              showMissingPhoto: _missingPhoto,
              alwaysOn: true,
              onChanged: (value) => setState(() => _value = value),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: kInatReportSheetSendKey,
              onPressed: _send,
              icon: const Icon(Icons.send),
              label: const Text('Melden'),
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
