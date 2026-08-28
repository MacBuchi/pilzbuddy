// Der Sprungbefehl an die Karte (#345) — die eine Regel, die ihn trägt.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pilzbuddy/features/map/map_focus.dart';

void main() {
  test('derselbe Spot zweimal löst zweimal aus', () {
    // DER Test dieser Datei, und das KONSTANTE Ziel ist Teil davon.
    //
    // Ein `NotifierProvider` vergleicht über die Objektidentität, nicht
    // über `==` — ein frisch gebautes `LatLng` löst deshalb ohnehin
    // jedes Mal aus, und mit einem gebauten Ziel wäre dieser Test blind.
    // `const LatLng(51.0, 11.0)` ist beim zweiten Aufruf DASSELBE
    // Objekt: Ohne den Zähler kommt der zweite Wunsch nicht an
    // (nachgemessen: 1 statt 2 Auslösungen). Das ist der Fall „ich war
    // im Blatt, habe es zugemacht und wollte noch mal hin" — an der
    // Oberfläche sähe er aus wie ein Aussetzer der Karte.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final seen = <MapFocus?>[];
    container.listen(mapFocusProvider, (_, next) => seen.add(next));

    const target = LatLng(51.0, 11.0);
    container.read(mapFocusProvider.notifier).focusOn(target);
    container.read(mapFocusProvider.notifier).focusOn(target);

    expect(seen, hasLength(2),
        reason: 'zweimal derselbe Wunsch muss zweimal ankommen');
    expect(seen.first, isNot(seen.last),
        reason: 'und die beiden Zustände müssen unterscheidbar sein — '
            'genau das leistet der Zähler');
    expect(seen.last!.target, target);
  });

  test('ohne Wunsch bewegt sich nichts', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(mapFocusProvider), isNull);
  });
}
