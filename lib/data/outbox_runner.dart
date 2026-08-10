// Die Wiedervorlage des Ausgangskorbs (#267): Aufträge der Reihe nach
// senden, das Ergebnis in EINEM Schreibvorgang festhalten.
//
// Die zentrale Schwierigkeit ist die Reihenfolge. Ein Fund kann an einem
// Spot hängen, den es auf dem Server noch gar nicht gibt — dann trägt
// sein Auftrag die Kennung des Spot-Auftrags statt einer Server-id. Beim
// Senden wird daraus die echte id, und dieses Auflösen muss zusammen mit
// dem Entfernen des Spot-Auftrags gültig werden: Stürbe die App
// dazwischen, wäre der Spot angelegt und sein Fund zeigte auf einen
// Auftrag, den es nicht mehr gibt. Deshalb wird am Ende der ganze Korb
// neu geschrieben ([Outbox.replaceAll]) und nicht Zeile für Zeile.
//
// Frei von Riverpod, damit sich jede dieser Regeln ohne Backend prüfen
// lässt.
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../core/errors.dart';
import 'outbox.dart';
import 'spot_repository.dart';

/// Was ein Lauf bewirkt hat — die Grundlage der Rückmeldung.
typedef OutboxRunResult = ({int sent, int remaining, int failed});

class OutboxRunner {
  OutboxRunner({required this.repository, required this.outbox});

  final SpotRepository repository;
  final Outbox outbox;

  /// Nach so vielen erfolglosen Anläufen gilt ein Auftrag als abgelehnt
  /// und wandert in „gescheitert".
  ///
  /// Fünf und nicht unbegrenzt: Ein Auftrag, den der Server dauerhaft
  /// nicht mag, würde sonst bei jeder Verbindung erneut anlaufen und die
  /// dahinter wartenden mitblockieren. Netzfehler zählen NICHT mit —
  /// die brechen den Lauf ab, ohne den Zähler anzufassen.
  static const maxAttempts = 5;

  /// Läuft gerade ein Lauf? Zwei gleichzeitig würden dieselben Aufträge
  /// doppelt senden.
  var _running = false;

  Future<OutboxRunResult> run({required String uid}) async {
    if (_running) return (sent: 0, remaining: 0, failed: 0);
    _running = true;
    try {
      return await _run(uid: uid);
    } finally {
      _running = false;
    }
  }

  Future<OutboxRunResult> _run({required String uid}) async {
    final jobs = await outbox.read(uid: uid);
    if (jobs.isEmpty) return (sent: 0, remaining: 0, failed: 0);

    final remaining = <OutboxJob>[];
    // Kennung des Spot-Auftrags → echte id, für die Funde dahinter.
    final resolved = <String, String>{};
    // Spot-Aufträge, die endgültig gescheitert sind: Ihre Funde haben
    // keinen Ort mehr und dürfen nicht ewig weiterversuchen.
    final lostSpots = <String>{};
    var sent = 0;
    var stopped = false;

    for (final original in jobs) {
      if (stopped) {
        remaining.add(original);
        continue;
      }
      if (original.failure != null) {
        remaining.add(original); // Wartet auf eine Entscheidung von Hand.
        continue;
      }

      var job = original;
      if (job is NewFindsJob && job.spotIsPending) {
        if (lostSpots.contains(job.spotId)) {
          remaining.add(job.copyWith(
              attempts: job.attempts + 1,
              failure: 'Der Spot dazu ließ sich nicht anlegen.'));
          continue;
        }
        final realId = resolved[job.spotId];
        // Der Spot-Auftrag ist noch nicht durch (kommt später in der
        // Liste oder blieb liegen): Dieser Fund wartet mit.
        if (realId == null) {
          remaining.add(job);
          continue;
        }
        job = job.resolvedTo(realId);
      }

      try {
        switch (job) {
          case NewSpotJob():
            final id = await repository.addSpot(
              lat: job.lat,
              lng: job.lng,
              name: job.name,
              finds: job.finds,
              clientId: job.id,
            );
            resolved[job.id] = id;
          case NewFindsJob():
            await repository.addFinds(spotId: job.spotId, finds: job.finds);
        }
        sent++;
      } catch (error) {
        // Kein Netz oder keine Sitzung mehr: Der Lauf endet hier, ohne
        // irgendetwas als gescheitert zu markieren. Alles Übrige bleibt
        // in seiner Reihenfolge liegen — der nächste Anlauf macht weiter.
        if (looksOffline(error) || error is NotSignedInException) {
          remaining.add(job);
          stopped = true;
          continue;
        }
        final attempts = job.attempts + 1;
        // Eine Ablehnung des Servers (RLS, Constraint, gelöschter Spot)
        // wird durch Wiederholen nicht besser.
        final done = _isFinal(error) || attempts >= maxAttempts;
        if (done && job is NewSpotJob) lostSpots.add(job.id);
        remaining.add(job.copyWith(
          attempts: attempts,
          failure: done ? friendlyError(error) : null,
        ));
      }
    }

    await outbox.replaceAll(remaining, uid: uid);
    return (
      sent: sent,
      remaining: remaining.length,
      failed: remaining.where((job) => job.failure != null).length,
    );
  }

  /// Fehler, bei denen ein weiterer Versuch nichts ändert: Der Server hat
  /// die Zeile inhaltlich abgelehnt — RLS, Constraint, gelöschter Spot.
  ///
  /// Ein `23505` gehört NICHT hierher, weil er hier gar nicht ankommt:
  /// Den fängt das Repository ab und deutet ihn als „stand schon" (Patch
  /// 016) — genau der Fall, für den die Kennung da ist.
  bool _isFinal(Object error) =>
      error is WriteRejectedException || error is PostgrestException;
}
