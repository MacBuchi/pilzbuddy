// Bedienelemente über der Karte im Browser bedienbar halten (#689).
//
// Mit MapLibre GL JS (`?maplibre=1`) ist die Karte ein HTML-Element, und
// das nimmt jeden Klick, bevor Flutter ihn sieht — ein Knopf darüber wäre
// tot, ein Tipp auf ihn schöbe die Karte. `PointerInterceptor` legt ein
// leeres Element in Größe des Kinds dazwischen (Paket
// `pointer_interceptor`, aus dem Flutter-Team).
//
// **Um das sichtbare Element legen, nie um ein `Align`/`SafeArea`**: Der
// Fänger ist so groß wie sein Kind — um eine bildschirmfüllende Hülle
// gelegt, nähme er der Karte jede Geste.
//
// Überall sonst (flutter_map, Android, Tests) gibt es kein HTML-Element
// darunter, und das Kind kommt unverändert zurück.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import 'map_view.dart' show webMapLibreProvider;

class MapOverlayGuard extends ConsumerWidget {
  const MapOverlayGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      kIsWeb && ref.watch(webMapLibreProvider)
          ? PointerInterceptor(child: child)
          : child;
}
