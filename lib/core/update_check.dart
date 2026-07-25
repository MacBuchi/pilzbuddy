import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../data/providers.dart';
import 'app_distribution.dart';
import 'app_info.dart';

/// Informationen über ein verfügbares Update von GitHub Releases.
class UpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final String? releaseNotes;

  const UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    this.releaseNotes,
  });
}

/// `true`, wenn [latest] eine neuere Version als [current] ist
/// (numerischer Vergleich je Segment, z. B. 1.10.0 > 1.9.2).
///
/// Vorab wird alles ab `-` oder `+` abgeschnitten: `1.5.1-rc1` und
/// `1.5.1+42` sind für den Vergleich 1.5.1. Ohne das würde
/// `int.tryParse('1-rc1')` null liefern und die Version stillschweigend auf
/// 1.5.0 zurückfallen — ein Vorabversion-Suffix hätte den Vergleich also
/// verfälscht statt ihn nur zu ignorieren.
bool isNewerVersion(String latest, String current) {
  List<int> parse(String v) => v
      .trim()
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((part) => int.tryParse(part.trim()) ?? 0)
      .toList();
  final l = parse(latest);
  final c = parse(current);
  for (var i = 0; i < 3; i++) {
    final li = i < l.length ? l[i] : 0;
    final ci = i < c.length ? c[i] : 0;
    if (li != ci) return li > ci;
  }
  return false;
}

/// Fragt das neueste GitHub-Release ab und vergleicht mit der installierten
/// Version. Nur relevant für die per APK verteilte Android-App — Web ist
/// immer aktuell, und im Play-Build übernimmt der Store das Aktualisieren.
/// Liefert `null`, wenn kein Update verfügbar ist oder der Check fehlschlägt.
final updateInfoProvider = FutureProvider<UpdateInfo?>((ref) async {
  if (!AppDistribution.showsUpdateHints) return null;
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final response = await http.get(
      Uri.parse(
          'https://api.github.com/repos/MacBuchi/pilzbuddy/releases/latest'),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;

    final release = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = (release['tag_name'] as String? ?? '');
    final latest = tag.startsWith('v') ? tag.substring(1) : tag;
    if (latest.isEmpty || !isNewerVersion(latest, packageInfo.version)) {
      return null;
    }

    final assets = release['assets'] as List<dynamic>? ?? const [];
    final apk = assets.cast<Map<String, dynamic>>().where(
        (a) => (a['name'] as String? ?? '').endsWith('.apk'));
    if (apk.isEmpty) return null;

    return UpdateInfo(
      latestVersion: latest,
      downloadUrl: apk.first['browser_download_url'] as String,
      releaseNotes: release['body'] as String?,
    );
  } catch (_) {
    return null; // Update-Check darf die App nie stören
  }
});

/// Kleinste Version, die noch zum Live-Schema passt (`public.app_config`,
/// Patch 012) — oder `null`, wenn sie sich nicht ermitteln lässt.
///
/// `null` heißt „unbekannt", nicht „0.0.0": ein fehlgeschlagener Abruf darf
/// nie zu einer Sperre führen.
final minimumSupportedVersionProvider = FutureProvider<String?>((ref) async {
  try {
    return await ref
        .watch(appConfigRepositoryProvider)
        .fetchMinimumSupportedVersion();
  } catch (_) {
    return null;
  }
});

/// Ist die installierte App zu alt für das Live-Schema?
///
/// Der Schema Check garantiert nur, dass die *aktuelle* App zu den Tabellen
/// passt. Ein älterer Client fragt nach einer Breaking-Migration Spalten ab,
/// die es nicht mehr gibt, und scheitert still — deshalb sperrt die App sich
/// hier selbst (Issue #80).
///
/// Sperrt ausschließlich bei einer eindeutigen Antwort: fehlt die
/// Mindestversion oder die eigene Version, läuft die App normal weiter. Die
/// App wird im Wald ohne Empfang benutzt; jemanden dort auszusperren, weil
/// eine Abfrage nicht durchkam, wäre schlimmer als ein veralteter Client.
/// Das Ergebnis wird bewusst nicht persistiert — beim nächsten Start wird
/// wieder frisch gefragt.
final updateRequiredProvider = FutureProvider<bool>((ref) async {
  final minimum = await ref.watch(minimumSupportedVersionProvider.future);
  if (minimum == null || minimum.isEmpty) return false;
  final current = await ref.watch(appVersionProvider.future);
  if (current == AppInfo.unknownVersion) return false;
  return isNewerVersion(minimum, current);
});
