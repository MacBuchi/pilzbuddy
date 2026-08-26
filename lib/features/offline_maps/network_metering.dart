import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Kostet die aktuelle Verbindung Datenvolumen? (#332)
///
/// `connectivity_plus` kennt nur den TRANSPORTWEG, und der beantwortet die
/// Frage nicht: Ein Handy-Hotspot ist WLAN und kostet trotzdem. Genau in
/// diese Lage gerät man unterwegs, und eine Regionskarte ist mehrere
/// hundert MB bis 1,7 GB groß — das darf die App nicht ungefragt aus einem
/// fremden Datentarif ziehen.
///
/// Android weiß es besser: `ConnectivityManager.isActiveNetworkMetered`
/// meldet einen Hotspot als kostenpflichtig, ebenso jedes WLAN, das der
/// Nutzer selbst so markiert hat. Die Auskunft ist ein MethodChannel und
/// **braucht keine neue Berechtigung** — `ACCESS_NETWORK_STATE` bringt
/// `connectivity_plus` ohnehin mit.
abstract interface class NetworkMetering {
  /// true = kostet Datenvolumen. Im Zweifel true: Die harmlose
  /// Fehlerrichtung ist „lädt nicht", nicht „lädt auf fremde Rechnung".
  Future<bool> isMetered();
}

/// Der Name muss zeichengleich in `MainActivity.kt` stehen — bei einem
/// Tippfehler antwortet niemand, und die Abfrage endet still im
/// `MissingPluginException`. `test/android_manifest_test.dart` hält beide
/// Seiten zusammen.
const networkMeteringChannel = 'de.mcbuchi.pilzbuddy/network';

class PlatformNetworkMetering implements NetworkMetering {
  const PlatformNetworkMetering({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(networkMeteringChannel);

  final MethodChannel _channel;

  @override
  Future<bool> isMetered() async {
    // Web und iOS haben den Kanal nicht — dort gibt es auch keine
    // Offline-Karten, die Antwort ist also folgenlos.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _channel.invokeMethod<bool>('isMetered') ?? true;
    } catch (_) {
      // Fehlender Kanal, fehlende Berechtigung, was auch immer: Wer die
      // Kosten nicht kennt, lädt nichts. Nur der Auto-Nachlauf hängt
      // daran — von Hand geht weiterhin alles.
      return true;
    }
  }
}
