// Was an iNaturalist gemeldet wurde (#553) — die Buchführung in
// Supabase, Patch 029.
//
// **Die Zeile entsteht VOR dem Senden.** Sie trägt die uuid, unter der
// iNaturalist die Beobachtung anlegt; ein Wiederholversuch findet sie
// und sendet dieselbe Kennung noch einmal, statt eine zweite
// Beobachtung zu erzeugen. Dasselbe Muster wie `client_id` beim
// Ausgangskorb (Patch 016), nur mit der Kennung auf der anderen Seite.
import 'package:supabase_flutter/supabase_flutter.dart';

import 'outbox.dart' show newClientId;
import 'session.dart';

const kInatPlatform = 'inat';

/// Der Stand einer Meldung, wie ihn `find_reports.status` trägt.
enum FindReportStatus {
  sending,
  reported,
  needsId,
  research,
  casual,
  withdrawn;

  String get dbValue => switch (this) {
        FindReportStatus.needsId => 'needs_id',
        _ => name,
      };

  static FindReportStatus fromDb(String? value) => values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => FindReportStatus.sending);
}

class FindReport {
  const FindReport({
    required this.findId,
    required this.remoteUuid,
    this.remoteId,
    this.status = FindReportStatus.sending,
    this.gbifId,
  });

  final String findId;
  final String remoteUuid;
  final int? remoteId;
  final FindReportStatus status;

  /// Die Kennung bei GBIF — gesetzt, sobald GBIF die Beobachtung führt.
  final int? gbifId;

  /// Nichts mehr zu erwarten: bei GBIF angekommen oder bei iNaturalist
  /// gelöscht. Alles andere kann sich noch ändern — auch „Casual" wird
  /// „Research Grade", wenn jemand ein Foto nachreicht.
  bool get settled =>
      gbifId != null || status == FindReportStatus.withdrawn;

  FindReport copyWith({FindReportStatus? status, int? gbifId}) => FindReport(
        findId: findId,
        remoteUuid: remoteUuid,
        remoteId: remoteId,
        status: status ?? this.status,
        gbifId: gbifId ?? this.gbifId,
      );

  factory FindReport.fromJson(Map<String, dynamic> json) => FindReport(
        findId: json['find_id'] as String,
        remoteUuid: json['remote_uuid'] as String,
        remoteId: (json['remote_id'] as num?)?.toInt(),
        status: FindReportStatus.fromDb(json['status'] as String?),
        gbifId: (json['gbif_id'] as num?)?.toInt(),
      );
}

class FindReportRepository {
  FindReportRepository(this._client);

  final SupabaseClient _client;

  /// Exakt diese Spalten prüft `tool/schema_check.sh`.
  static const columns = 'find_id, remote_uuid, remote_id, status, gbif_id';

  /// Die Zeile zu diesem Fund — vorhanden oder frisch angelegt.
  ///
  /// Zwei Geräte desselben Kontos könnten gleichzeitig anlegen; der
  /// zweite Insert scheitert dann am Primärschlüssel (23505), und die
  /// Zeile des ersten gilt. Beide senden damit dieselbe uuid.
  Future<FindReport> begin(String findId) async {
    final existing = await _row(findId);
    if (existing != null) return existing;
    try {
      final row = await _client
          .from('find_reports')
          .insert({
            'find_id': findId,
            'user_id': _client.requireUid,
            'platform': kInatPlatform,
            'remote_uuid': newClientId(),
          })
          .select(columns)
          .single();
      return FindReport.fromJson(row);
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
      final raced = await _row(findId);
      if (raced == null) rethrow;
      return raced;
    }
  }

  /// Die Beobachtung steht — ihre id, sobald sie bekannt ist. Die Fotos
  /// folgen noch; bricht der Weg dort ab, zeigt `sending` mit id genau
  /// das an.
  Future<void> setRemoteId(String findId, int remoteId) =>
      _update(findId, {'remote_id': remoteId});

  Future<void> setStatus(String findId, FindReportStatus status) =>
      _update(findId, {'status': status.dbValue});

  Future<void> setGbifId(String findId, int gbifId) =>
      _update(findId, {'gbif_id': gbifId});

  /// Alle eigenen Meldungen — die Policy gibt ohnehin nur die heraus.
  Future<List<FindReport>> mine() async {
    final rows = await _client
        .from('find_reports')
        .select(columns)
        .eq('platform', kInatPlatform);
    return [for (final row in rows) FindReport.fromJson(row)];
  }

  Future<FindReport?> _row(String findId) async {
    final row = await _client
        .from('find_reports')
        .select(columns)
        .eq('find_id', findId)
        .eq('platform', kInatPlatform)
        .maybeSingle();
    return row == null ? null : FindReport.fromJson(row);
  }

  Future<void> _update(String findId, Map<String, dynamic> values) =>
      _client
          .from('find_reports')
          .update({
            ...values,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('find_id', findId)
          .eq('platform', kInatPlatform);
}
