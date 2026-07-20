import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'app_distribution.dart';

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
bool isNewerVersion(String latest, String current) {
  List<int> parse(String v) => v
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
