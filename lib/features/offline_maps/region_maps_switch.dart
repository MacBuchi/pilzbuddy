// Der Schalter „Regionskarten verwenden" (#630, seit 1.219.0). Er steht
// an ZWEI Stellen — auf der Seite der Regionskarten und auf der der
// Kartenbereiche —, weil man von beiden Seiten aus vergleichen will. Ein
// Widget, damit der Text an beiden Stellen derselbe bleibt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'offline_map_providers.dart';

class RegionMapsSwitch extends ConsumerWidget {
  const RegionMapsSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      key: const ValueKey('region-maps-switch'),
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.map_outlined),
      title: const Text('Regionskarten verwenden'),
      subtitle: const Text(
          'Aus: Die heruntergeladenen Regionen bleiben auf dem Gerät, die '
          'Karte zeigt sie aber nicht. Ohne Empfang gelten dann nur die '
          'Kartenbereiche.'),
      value: ref.watch(regionMapsEnabledProvider),
      onChanged: (value) =>
          ref.read(regionMapsEnabledProvider.notifier).set(value),
    );
  }
}
