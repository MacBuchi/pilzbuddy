// „An iNaturalist melden" im Blatt „Fund eintragen" (#553).
//
// **Ein Schalter, Vorgabe AUS — und erst dahinter alles andere.** Wer
// nicht meldet, sieht eine Zeile mehr und sonst nichts; wer meldet,
// sieht nur, was iNaturalist wirklich braucht. Das Blatt erscheint
// überhaupt nur mit verbundenem Konto.
//
// **Das Buddy-Foto geht nie ungefragt mit** (Betreiber, 2026-09-23). Es
// ist für Buddys gemacht, nicht zum Bestimmen, und kann Menschen zeigen.
// Liegt eines an, bietet der Abschnitt es als NICHT angehakte Option an.
import 'package:flutter/material.dart';

import '../../core/photo_pipeline.dart';
import '../../core/photo_providers.dart';
import '../../core/widgets/photo_attachment.dart';
import '../map/forest_species.dart';
import 'inat_reporter.dart';

const kInatReportSectionKey = Key('inat-report-section');
const kInatReportSwitchKey = Key('inat-report-switch');
const kInatUseBuddyPhotoKey = Key('inat-use-buddy-photo');
const kInatObscuredKey = Key('inat-obscured');
const kInatExactKey = Key('inat-exact');
const kInatNoPhotoKey = Key('inat-no-photo');
Key inatTreeKey(String tree) => ValueKey('inat-tree-$tree');

/// Höchstens so viele eigene Fotos — Hut, Unterseite, Stielbasis.
const kInatMaxPhotos = 3;

/// Alle Bäume, die die DLR-Karte kennt — die Auswahl für die Chips.
/// Laub vor Nadel, jeweils in der Reihenfolge der Karte.
final List<String> kInatTreeChoices = [
  for (final b in Broadleaf.values) b.label,
  for (final c in Conifer.values) c.label,
];

/// Was die Karte an einem Punkt als Vorauswahl hergibt.
List<String> inatTreePreset(ForestSpeciesNames? names) => [
      if (names?.broadleaf case final b?) b.label,
      if (names?.conifer case final c?) c.label,
    ];

/// Der Stand des Abschnitts. Das Blatt baut daraus beim Speichern den
/// Entwurf — erst dort ist bekannt, ob ein Buddy-Foto anliegt.
class InatSectionValue {
  const InatSectionValue({
    this.enabled = false,
    this.photos = const [],
    this.useBuddyPhoto = false,
    this.obscured = true,
    this.trees = const [],
  });

  final bool enabled;
  final List<PreparedPhoto> photos;
  final bool useBuddyPhoto;
  final bool obscured;
  final List<String> trees;

  /// Der Entwurf — `null`, wenn nicht gemeldet wird.
  InatReportDraft? draftWith(PreparedPhoto? buddyPhoto) => enabled
      ? InatReportDraft(
          photos: [
            if (useBuddyPhoto && buddyPhoto != null) buddyPhoto,
            ...photos,
          ],
          obscured: obscured,
          trees: trees,
        )
      : null;
}

class InatReportSection extends StatefulWidget {
  const InatReportSection({
    super.key,
    required this.species,
    required this.multiple,
    required this.presetTrees,
    required this.pickPhoto,
    required this.preparePhoto,
    required this.buddyPhoto,
    required this.showMissingPhoto,
    required this.onChanged,
    this.alwaysOn = false,
  });

  /// Im eigenen Meldeblatt (nachträglich melden) gibt es keinen
  /// Schalter: Wer es geöffnet hat, will melden.
  final bool alwaysOn;

  /// Die Art des ERSTEN Eintrags — nur der wird gemeldet.
  final String? species;
  final bool multiple;
  final List<String> presetTrees;
  final PhotoPicker pickPhoto;
  final PhotoPreparer preparePhoto;
  final PreparedPhoto? buddyPhoto;

  /// Das Blatt hat „Speichern" ohne Foto versucht — dann steht die
  /// Zeile dazu rot da, statt dass das Blatt wortlos offen bleibt.
  final bool showMissingPhoto;
  final ValueChanged<InatSectionValue> onChanged;

  @override
  State<InatReportSection> createState() => _InatReportSectionState();
}

class _InatReportSectionState extends State<InatReportSection> {
  late InatSectionValue _value =
      InatSectionValue(enabled: widget.alwaysOn, trees: widget.presetTrees);

  void _set(InatSectionValue value) {
    setState(() => _value = value);
    widget.onChanged(value);
  }

  InatSectionValue _copy({
    bool? enabled,
    List<PreparedPhoto>? photos,
    bool? useBuddyPhoto,
    bool? obscured,
    List<String>? trees,
  }) =>
      InatSectionValue(
        enabled: enabled ?? _value.enabled,
        photos: photos ?? _value.photos,
        useBuddyPhoto: useBuddyPhoto ?? _value.useBuddyPhoto,
        obscured: obscured ?? _value.obscured,
        trees: trees ?? _value.trees,
      );

  @override
  void didUpdateWidget(InatReportSection old) {
    super.didUpdateWidget(old);
    // Wechselt die Art auf eine, die sich nicht melden lässt, schaltet
    // der Abschnitt ab — sonst meldete „Speichern" etwas, das die
    // Oberfläche gerade als unmeldbar ausweist.
    if (_value.enabled && inatScientificNameFor(widget.species) == null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _set(_copy(enabled: false)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final sci = inatScientificNameFor(widget.species);
    final reportable = sci != null;
    return Column(
      key: kInatReportSectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.alwaysOn)
        SwitchListTile(
          key: kInatReportSwitchKey,
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.public),
          title: const Text('An iNaturalist melden'),
          subtitle: Text(reportable
              ? (widget.multiple
                  ? 'Gemeldet wird der erste Fund (${widget.species}).'
                  : 'Mit Foto, unter deinem Namen — bestätigt geht es '
                      'weiter an GBIF.')
              : 'Nur mit einer Art aus der Liste — Freitext-Arten kennt '
                  'iNaturalist nicht.'),
          value: reportable && _value.enabled,
          onChanged:
              reportable ? (on) => _set(_copy(enabled: on)) : null,
        ),
        if (reportable && _value.enabled) ...[
          if (widget.buddyPhoto != null)
            CheckboxListTile(
              key: kInatUseBuddyPhotoKey,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: const Text('Buddy-Foto auch verwenden'),
              subtitle: const Text('Nur, wenn es den Pilz gut zeigt und '
                  'keine Menschen.'),
              value: _value.useBuddyPhoto,
              onChanged: (on) => _set(_copy(useBuddyPhoto: on ?? false)),
            ),
          for (var i = 0; i < _value.photos.length; i++)
            PhotoAttachment(
              key: ValueKey('inat-photo-$i'),
              pick: widget.pickPhoto,
              prepare: widget.preparePhoto,
              photo: _value.photos[i],
              label: 'Foto für iNaturalist',
              attachedNote: 'Ohne Aufnahmedaten — der Ort geht als Angabe '
                  'der Beobachtung mit.',
              onChanged: (photo) => _set(_copy(photos: [
                for (var j = 0; j < _value.photos.length; j++)
                  if (j != i) _value.photos[j] else ?photo,
              ])),
            ),
          if (_value.photos.length < kInatMaxPhotos)
            PhotoAttachment(
              key: ValueKey('inat-photo-${_value.photos.length}'),
              pick: widget.pickPhoto,
              prepare: widget.preparePhoto,
              photo: null,
              label: _value.photos.isEmpty
                  ? 'Foto für iNaturalist'
                  : 'Weiteres Foto (Unterseite, Stiel …)',
              onChanged: (photo) {
                if (photo != null) {
                  _set(_copy(photos: [..._value.photos, photo]));
                }
              },
            ),
          if (widget.showMissingPhoto &&
              _value.photos.isEmpty &&
              !(_value.useBuddyPhoto && widget.buddyPhoto != null))
            Text(
              'Für iNaturalist fehlt ein Foto — ohne Bild wird eine '
              'Beobachtung dort nie bestätigt.',
              key: kInatNoPhotoKey,
              style: small?.copyWith(color: theme.colorScheme.error),
            ),
          const SizedBox(height: 8),
          Text('Fundstelle öffentlich', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: true,
                  label: Text('verschleiert', key: kInatObscuredKey)),
              ButtonSegment(
                  value: false, label: Text('genau', key: kInatExactKey)),
            ],
            selected: {_value.obscured},
            onSelectionChanged: (s) => _set(_copy(obscured: s.first)),
          ),
          Text(
            _value.obscured
                ? 'Öffentlich nur ein Gebiet von etwa 20 km. iNaturalist '
                    'selbst kennt die genaue Stelle.'
                : 'Die Stelle ist für alle sichtbar, auch bei GBIF.',
            style: small,
          ),
          const SizedBox(height: 8),
          Text('Bäume in der Nähe', style: theme.textTheme.titleSmall),
          if (widget.presetTrees.isNotEmpty)
            Text('Vorausgewählt aus der Baumartenkarte — tippen zum Ändern.',
                style: small),
          Wrap(
            spacing: 6,
            children: [
              for (final tree in kInatTreeChoices)
                FilterChip(
                  key: inatTreeKey(tree),
                  label: Text(tree),
                  selected: _value.trees.contains(tree),
                  onSelected: (on) => _set(_copy(trees: [
                    for (final t in kInatTreeChoices)
                      if (t == tree ? on : _value.trees.contains(t)) t,
                  ])),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
