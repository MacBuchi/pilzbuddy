// Wie der Ausgangskorb (#267) auf der Karte aussieht: Aufträge werden zu
// Spots und Funden, die sich von übertragenen nur durch `pending`
// unterscheiden.
//
// **Warum sie überhaupt sichtbar sind:** Ohne das legt man denselben Spot
// zweimal an — man sieht ja nicht, dass er schon erfasst ist. Genau der
// Fehler, den der Korb verhindern soll.
//
// **Warum sie überall mitzählen** (Statistik, Ampel, GPX-Export): Der Fund
// ist passiert. Ob seine Zeile schon in Frankfurt liegt, ist eine Frage
// der Technik, keine der Pilze. Gesperrt ist nur das Ändern und Löschen
// einzelner Einträge — dafür bräuchte es eine id, die es noch nicht gibt.
//
// Frei und ohne Riverpod, damit die Zuordnung ohne Backend prüfbar ist.
import '../models/find.dart';
import '../models/spot.dart';
import 'outbox.dart';
import 'spot_repository.dart' show NewFind;

/// Was die Karte zeigt: Spots samt Herkunft (`cachedAt`, siehe
/// `spot_cache.dart`) UND den Aufträgen, die noch warten.
///
/// Die Spots enthalten die wartenden Einträge bereits ([Spot.pending]);
/// [pending] ist die Auftragsliste selbst — sie trägt, was ein Spot
/// nicht sagen kann: wie oft es versucht wurde und woran es scheiterte.
typedef SpotsWithOutbox = ({
  List<Spot> spots,
  DateTime? cachedAt,
  List<OutboxJob> pending,
});

/// Die Spots des Servers plus die, die noch im Korb liegen.
///
/// Reihenfolge: erst die übertragenen (in ihrer Reihenfolge), dann die
/// wartenden — die sind die jüngsten, und die Liste ist nach `created_at`
/// sortiert.
List<Spot> withPendingJobs(
  List<Spot> spots,
  List<OutboxJob> jobs, {
  required String ownerId,
}) {
  if (jobs.isEmpty) return spots;

  // Erst die wartenden Spots anlegen, damit Fund-Aufträge sie im zweiten
  // Durchgang finden — ein Fund kann an einem Spot hängen, der selbst
  // noch wartet.
  final pendingSpots = <String, Spot>{};
  for (final job in jobs) {
    if (job is! NewSpotJob) continue;
    pendingSpots[job.id] = Spot(
      id: job.id,
      ownerId: ownerId,
      name: job.name,
      lat: job.lat,
      lng: job.lng,
      pending: true,
      finds: [
        for (final find in job.finds)
          _pendingFind(find, spotId: job.id, ownerId: ownerId, at: job.createdAt),
      ],
    );
  }

  final extraFinds = <String, List<Find>>{};
  for (final job in jobs) {
    if (job is! NewFindsJob) continue;
    final finds = [
      for (final find in job.finds)
        _pendingFind(find,
            spotId: job.spotId, ownerId: ownerId, at: job.createdAt),
    ];
    if (job.spotIsPending) {
      final spot = pendingSpots[job.spotId];
      // Der zugehörige Spot-Auftrag ist weg (verworfen, Konto gewechselt):
      // Dann hat dieser Fund keinen Ort mehr und wird nicht gezeigt. Die
      // Wiedervorlage räumt ihn beim nächsten Lauf ab.
      if (spot == null) continue;
      pendingSpots[job.spotId] = spot.copyWith(finds: [...spot.finds, ...finds]);
    } else {
      (extraFinds[job.spotId] ??= []).addAll(finds);
    }
  }

  return [
    for (final spot in spots)
      if (extraFinds[spot.id] case final waiting?)
        spot.copyWith(finds: [...spot.finds, ...waiting])
      else
        spot,
    ...pendingSpots.values,
  ];
}

/// Wie viele Einträge insgesamt warten — die Zahl im Banner. Gezählt
/// werden Einträge und nicht Aufträge: „3 Einträge" ist das, was die
/// Nutzerin eingetippt hat.
int pendingEntryCount(List<OutboxJob> jobs) =>
    jobs.fold(0, (sum, job) => sum + job.finds.length);

/// Aufträge, die endgültig abgelehnt wurden und von Hand entschieden
/// werden müssen.
List<OutboxJob> failedJobs(List<OutboxJob> jobs) =>
    [for (final job in jobs) if (job.failure != null) job];

Find _pendingFind(
  NewFind find, {
  required String spotId,
  required String ownerId,
  required DateTime at,
}) =>
    Find(
      // Die Kennung aus dem Korb ist auch hier die id: eindeutig, stabil
      // über Neustarts, und sie ist genau der Wert, unter dem die Zeile
      // später auf dem Server steht.
      id: find.clientId ?? '$spotId-${at.microsecondsSinceEpoch}',
      spotId: spotId,
      species: find.species,
      count: find.count,
      foundOn: find.foundOn,
      note: find.note,
      createdAt: at,
      authorId: ownerId,
      blank: find.blank,
      pending: true,
      // Ohne das zeigte ein wartender Fund seine Stelle erst nach dem
      // Senden — und das sähe aus wie Datenverlust.
      position: find.position,
    );
