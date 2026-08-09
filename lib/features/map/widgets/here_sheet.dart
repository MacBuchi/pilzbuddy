// „Was ist hier?" — die Werte des Spot-Blatts für eine BELIEBIGE Stelle
// (#245), erreichbar über einen Tipp auf die Karten-Legende.
//
// Der Wunsch des Betreibers zum Erkunden: Bisher beantwortete die App
// „wie viel Regen, wie warm, welcher Wald" nur dort, wo schon ein Spot
// liegt — also nur für Stellen, an denen man bereits war. Genau umgekehrt
// sucht man aber neue Ecken.
//
// **Es kostet kein neues Netzziel und keine gesendete Koordinate.** Regen-
// verlauf, Monatssumme und Temperatur kommen aus den lokal
// zwischengespeicherten Gittern (`rain-data`-Release), der Waldtyp aus dem
// Asset — alle drei werden längst mit `(lat, lon)` befragt. Der Punkt
// verlässt das Gerät nicht; im Funkloch steht hier dasselbe wie am Spot.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../spots/widgets/spot_forest_section.dart';
import '../../spots/widgets/spot_rain_section.dart';
import '../forest_data_providers.dart';

/// Öffnet das Blatt für [point].
Future<void> showHereSheet(BuildContext context, LatLng point) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _HereSheet(point: point),
  );
}

class _HereSheet extends ConsumerWidget {
  const _HereSheet({required this.point});

  final LatLng point;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grid = ref.watch(forestGridProvider).valueOrNull;
    final around = grid?.broadleafFactorAround(point.latitude, point.longitude);
    return ConstrainedBox(
      // Wie das Spot-Blatt: gedeckelt, damit die Karte dahinter sichtbar
      // bleibt, und scrollbar, damit nichts abgeschnitten wird.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.my_location, size: 22),
                  const SizedBox(width: 8),
                  Text('Was ist hier?',
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 4),
              // Die Koordinate steht dabei: Das Blatt hat keinen Namen,
              // an dem man erkennt, welche Stelle gemeint ist — und wer
              // sie notieren will, kann es.
              Text(
                '${_deg(point.latitude)} N · ${_deg(point.longitude)} O',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SpotForestSection(lat: point.latitude, lon: point.longitude),
              if (around case (:final factor?, :final forestShare))
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 24),
                  child: Text(
                    'Im Kilometer ringsum: Laubfaktor '
                    '${factor.toStringAsFixed(2).replaceAll('.', ',')} '
                    '(1 = Laub, 0 = Nadel) · Wald '
                    '${(forestShare * 100).round()} %',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              SpotRainSection(lat: point.latitude, lon: point.longitude),
              SizedBox(height: MediaQuery.of(context).viewPadding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  /// Vier Nachkommastellen — rund 11 m, die Auflösung, in der ein
  /// Fadenkreuz überhaupt gesetzt wird.
  String _deg(double value) =>
      value.toStringAsFixed(4).replaceAll('.', ',');
}
