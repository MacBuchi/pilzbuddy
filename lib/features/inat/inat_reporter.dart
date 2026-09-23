// Funde an iNaturalist melden (#553) — die Abläufe, ohne Widgets.
//
// Zwei Wege: VERBINDEN (einmal, im Profil) und MELDEN (je Fund). Beide
// hier und nicht im Notifier oder im Blatt, damit die Reihenfolge an
// EINER Stelle steht — und die ist beim Melden die Sache:
//
//   1. Art auflösen        scheitert, bevor irgendetwas geschrieben ist
//   2. JWT holen           scheitert, wenn der Zugang widerrufen ist
//   3. Zeile anlegen       trägt die uuid — ab hier ist alles wiederholbar
//   4. Beobachtung         mit dieser uuid, id sofort in die Zeile
//   5. Fotos               hängen an der id
//   6. Status `reported`   erst, wenn alles steht
//
// Bricht es zwischen 3 und 6 ab, steht `sending` in der Zeile, und der
// nächste Versuch knüpft daran an statt neu anzufangen.
import 'dart:math' as math;

import '../../core/mushroom_species.dart';
import '../../core/photo_pipeline.dart';
import '../../data/find_report_repository.dart';
import '../../data/inat_account.dart';
import '../../data/inat_api.dart';
import '../../models/find_position.dart';

/// Wie ungenau ein Ort ohne eigene GPS-Messung gilt, in Metern.
///
/// Ein Spot markiert eine Stelle, keinen Pilz: 20 m sind „derselbe Ort"
/// (`kNearbySpotMeters`), und unter Blätterdach liegt GPS 10–20 m
/// daneben. 50 m sind die ehrliche Angabe — zu klein behauptete eine
/// Genauigkeit, die niemand gemessen hat, und genau darauf verlassen
/// sich die, die bei GBIF damit rechnen.
const kInatUnmeasuredAccuracyM = 50;

/// Die Angabe zur Genauigkeit: gemessen ⇒ die Messung (aufgerundet,
/// mindestens 5 m), sonst [kInatUnmeasuredAccuracyM].
int inatAccuracyFor(FindPosition? position) {
  final measured = position?.accuracyM;
  if (measured == null) return kInatUnmeasuredAccuracyM;
  return math.max(5, measured.ceil());
}

/// Was der Nutzer im Blatt für die Meldung gewählt hat.
class InatReportDraft {
  const InatReportDraft({
    required this.photos,
    this.obscured = true,
    this.trees = const [],
  });

  /// Mindestens eines — ohne Foto erreicht eine Beobachtung nie
  /// „Research Grade" und damit nie GBIF.
  final List<PreparedPhoto> photos;

  /// Vorgabe VERSCHLEIERT: Wer nicht darüber nachdenkt, gibt die
  /// Fundstelle nicht öffentlich preis. iNaturalist kennt sie trotzdem
  /// genau — das sagt der Verbinden-Dialog.
  final bool obscured;

  /// Bäume in der Nähe — vorbelegt aus der DLR-Baumartenkarte, vom
  /// Nutzer änderbar.
  final List<String> trees;
}

/// Der Text der Beobachtung. Anzahl und Bäume, sonst nichts — die Notiz
/// des Nutzers bleibt bei uns (Begründung an [InatObservation]).
String inatDescription({int? count, List<String> trees = const []}) => [
      if (count != null && count > 0) 'Anzahl: $count',
      if (trees.isNotEmpty) 'Bäume in der Nähe: ${trees.join(', ')}',
      'Gemeldet mit PilzBuddy.',
    ].join('\n');

/// Der wissenschaftliche Name, unter dem eine Art gemeldet werden
/// kann — `null` für Freitext-Arten und Arten ohne gesicherten Namen.
String? inatScientificNameFor(String? species) =>
    knownSpeciesFor(species)?.sci;

/// Verbindet ein Konto: Custom Tab öffnen, Code einlösen, Namen holen.
Future<InatAccount> connectInat({
  required InatApi api,
  required Future<Uri> Function(Uri authorizeUrl) authorize,
  required InatLicense license,
  InatPkce? pkce,
}) async {
  final session = pkce ?? newInatPkce();
  final callback =
      await authorize(inatAuthorizeUrl(appId: api.appId, pkce: session));
  final code = inatCodeFromCallback(callback, state: session.state);
  final accessToken = await api.exchangeCode(code, session.verifier);
  final login = await api.login(await api.apiToken(accessToken));
  return InatAccount(accessToken: accessToken, login: login, license: license);
}

class InatReporter {
  InatReporter({required this.api, required this.reports});

  final InatApi api;
  final FindReportRepository reports;

  /// Meldet einen Fund. Gibt die id der Beobachtung zurück.
  Future<int> report({
    required InatAccount account,
    required String findId,
    required String? species,
    required int? count,
    required DateTime foundOn,
    required double lat,
    required double lng,
    required FindPosition? position,
    required InatReportDraft draft,
  }) async {
    if (draft.photos.isEmpty) {
      throw const InatException('Für iNaturalist fehlt ein Foto.');
    }
    final sci = inatScientificNameFor(species);
    if (sci == null) {
      throw const InatException('Melden geht nur mit einer Art aus der '
          'Liste — Freitext-Arten kennt iNaturalist nicht.');
    }
    final taxonId = await api.taxonId(sci);
    if (taxonId == null) {
      throw InatException('iNaturalist kennt „$sci" nicht.');
    }
    final jwt = await api.apiToken(account.accessToken);

    final row = await reports.begin(findId);
    if (row.status != FindReportStatus.sending && row.remoteId != null) {
      // Schon gemeldet — ein zweiter Tipp legt nichts Neues an.
      return row.remoteId!;
    }
    var observationId = row.remoteId;
    if (observationId == null) {
      observationId = await api.createObservation(
        jwt,
        InatObservation(
          uuid: row.remoteUuid,
          taxonId: taxonId,
          observedOn: foundOn,
          lat: lat,
          lng: lng,
          accuracyM: inatAccuracyFor(position),
          obscured: draft.obscured,
          license: account.license,
          description: inatDescription(count: count, trees: draft.trees),
        ),
      );
      await reports.setRemoteId(findId, observationId);
    }
    for (final photo in draft.photos) {
      await api.addPhoto(jwt, observationId, photo.full);
    }
    await reports.setStatus(findId, FindReportStatus.reported);
    return observationId;
  }

  /// Gleicht offene Meldungen mit iNaturalist und GBIF ab und schreibt,
  /// was sich geändert hat. Gibt die neue Liste zurück.
  ///
  /// **Ein Aufruf für alle, nicht einer je Fund**: iNaturalist nimmt
  /// eine Liste von ids. GBIF wird nur für BESTÄTIGTE gefragt — nur die
  /// können dort ankommen. `sending` bleibt, wie es ist: Dort fehlt noch
  /// etwas, das nur ein neuer Versuch nachholt.
  Future<List<FindReport>> refresh(List<FindReport> rows) async {
    final open = [
      for (final r in rows)
        if (!r.settled &&
            r.remoteId != null &&
            r.status != FindReportStatus.sending)
          r,
    ];
    if (open.isEmpty) return rows;
    final grades =
        await api.qualityGrades([for (final r in open) r.remoteId!]);
    final updated = {for (final r in rows) r.findId: r};
    for (final r in open) {
      final status = switch (grades[r.remoteId]) {
        null => FindReportStatus.withdrawn,
        'research' => FindReportStatus.research,
        'casual' => FindReportStatus.casual,
        _ => FindReportStatus.needsId,
      };
      var next = r.copyWith(status: status);
      if (status == FindReportStatus.research) {
        final gbifId = await api.gbifOccurrenceFor(r.remoteId!);
        if (gbifId != null) {
          next = next.copyWith(gbifId: gbifId);
          await reports.setGbifId(r.findId, gbifId);
        }
      }
      if (status != r.status) await reports.setStatus(r.findId, status);
      updated[r.findId] = next;
    }
    return updated.values.toList();
  }
}
