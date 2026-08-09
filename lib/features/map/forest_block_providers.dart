// Die feine Waldstufe auf dem Gerät (#253): Zustimmung, Katalog,
// Blockverbund unterm Sichtfenster — und die kombinierte Sicht, die alle
// Punktabfragen benutzen.
//
// Kette mit Absicht: Ohne Zustimmung wird NICHTS beobachtet und nichts
// geladen — nicht einmal der Katalog (er ist klein, aber „die App hat
// von sich aus GitHub kontaktiert" ist genau das Versprechen, das der
// Schalter gibt). Mit Zustimmung hängt alles am geplanten
// Bildausschnitt (`forestFillWindowProvider`): Der steht bei kleinem
// Schieben still, also wird auch hier nicht neu geladen.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../data/forest_block_repository.dart';
import 'forest_blocks.dart';
import 'forest_data_providers.dart';
import 'forest_grid.dart';

final forestBlockRepositoryProvider =
    Provider<ForestBlockRepository>((ref) => ForestBlockRepository());

/// Hat die Nutzerin dem Nachladen zugestimmt? Aus den Einstellungen
/// gelesen und dort auch geschrieben — dieselbe Mechanik wie
/// `rainCourseEnabledProvider`: einmal zustimmen, nicht jede Wanderung
/// neu.
final forestFineEnabledProvider = StateProvider<bool>(
    (ref) => ref.watch(settingsProvider).forestFineEnabled);

/// Wie der Katalog beschafft wird — die Test-Naht, exakt das Muster der
/// Regen-Loader: `test/fakes/test_app.dart` überschreibt sie auf `null`,
/// sonst ginge jeder Flow-Test mit erteilter Zustimmung ins Netz.
final forestBlockCatalogLoaderProvider =
    Provider<Future<ForestBlockCatalog?> Function()>(
        (ref) => ref.watch(forestBlockRepositoryProvider).loadCatalog);

/// Wie ein Block beschafft wird — zweite Test-Naht, gleiche Begründung.
final forestBlockGridLoaderProvider = Provider<
        Future<ForestGrid?> Function(ForestBlockCatalog, ForestBlockInfo)>(
    (ref) => ref.watch(forestBlockRepositoryProvider).loadBlock);

/// Der Katalog — `null` ohne Zustimmung, ohne Netz UND Platten-Stand,
/// oder wenn er nicht verstanden wird.
final forestBlockCatalogProvider =
    FutureProvider<ForestBlockCatalog?>((ref) async {
  if (!ref.watch(forestFineEnabledProvider)) return null;
  return ref.watch(forestBlockCatalogLoaderProvider)();
});

/// Der Blockverbund unterm aktuellen Bildausschnitt.
///
/// Geladen werden genau die Blöcke, deren Fläche den geplanten
/// Ausschnitt schneidet (er umfasst das Sichtfenster plus Rand — die
/// Fadenkreuz-Mitte liegt immer darin). Ein Block, der nicht kommt,
/// fehlt eben: Der Verbund trägt dann, was da ist, und [ForestView]
/// bzw. der Zeichner fallen für die Lücke aufs Asset zurück.
final forestBlockSetProvider = FutureProvider<ForestBlockSet?>((ref) async {
  if (!ref.watch(forestFineEnabledProvider)) return null;
  final window = ref.watch(forestFillWindowProvider);
  if (window == null) return null; // noch kein Kamera-Stillstand
  final catalog = await ref.watch(forestBlockCatalogProvider.future);
  if (catalog == null) return null;
  // Zu weit draußen: Blöcke werden erst geholt, wenn ihre Waben im Bild
  // überhaupt zu sehen wären ([ForestBlockCatalog.paysOffIn]). Sonst
  // kostete ein Rauszoomen den ganzen Katalog — für ein Bild, das vom
  // groben nicht zu unterscheiden ist.
  if (!catalog.paysOffIn(window)) return null;
  final loadBlock = ref.watch(forestBlockGridLoaderProvider);
  final loaded = <String, ForestGrid>{};
  for (final block in catalog.blocksIntersecting(
    west: window.west,
    east: window.east,
    north: window.north,
    south: window.south,
  )) {
    final grid = await loadBlock(catalog, block);
    if (grid != null) loaded[block.file] = grid;
  }
  if (loaded.isEmpty) return null;
  return ForestBlockSet(catalog: catalog, loaded: loaded);
});

/// Der aufgelöste Verbund als SYNCHRONER Wert — `null`, solange er lädt
/// oder es nichts gibt.
///
/// Ein eigener Provider aus zwei Gründen: Der Zeichner muss ihn VOR
/// seinen awaits beobachten (`ref.watch` nach einem await ist in
/// Riverpod unbestimmt — der Fill-Provider kam so nie zur Ruhe, im
/// Widget-Test als 10-Minuten-Timeout sichtbar), und „lädt noch" →
/// „nichts da" ist hier DERSELBE Wert `null`: Ein Provider meldet nur
/// Änderungen, also löst das Auflösen ohne Zustimmung kein nutzloses
/// Neumalen aus.
final forestBlocksReadyProvider = Provider<ForestBlockSet?>(
    (ref) => ref.watch(forestBlockSetProvider).valueOrNull);

/// Die EINE Sicht für Punktabfragen (Legende, Spot-Blatt, „Was ist
/// hier?"): feine Stufe, wo sie geladen ist, sonst das Asset — je
/// Antwort. Während Blöcke laden, antwortet das Asset, statt dass die
/// Zeile wartet.
final forestViewProvider = Provider<ForestView?>((ref) {
  final base = ref.watch(forestGridProvider).valueOrNull;
  if (base == null) return null;
  return ForestView(
    base: base,
    fine: ref.watch(forestBlocksReadyProvider),
  );
});
