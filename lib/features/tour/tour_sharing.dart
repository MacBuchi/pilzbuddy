// Wann die eigene Spur zu den Buddys geht — und wann sie wieder
// verschwindet (#340, Stufe 2).
//
// Rein: Zustand rein, Entscheidung raus. Keine Uhr, kein Netz, kein
// Provider — dieselbe Bauform wie `tour_track.dart` und
// `nearby_spots.dart`, damit die Regel prüfbar bleibt und nicht in einem
// `build` steckt.

/// Wie oft die Spur erneuert wird.
///
/// Eine Minute Verzug ist belanglos, wenn jemand einen Hang absucht —
/// und der Takt entscheidet, wie weit das Schreiben vom Dauerschreiben
/// aus dem Wald entfernt bleibt. Bei 15-Sekunden-Messtakt sind das vier
/// Messungen je Upload.
const kTrackUploadInterval = Duration(seconds: 60);

/// Unter zwei Punkten gibt es keine Spur, sondern einen Punkt — und den
/// zeigt der Standort-Marker bereits. Dieselbe Grenze wie in
/// [tourTrackPolyline].
const kMinSharedTrackPoints = 2;

enum TrackShareAction {
  /// Hochladen (Upsert, ersetzt die vorige Zeile).
  upload,

  /// Vom Server nehmen — die Voraussetzung ist entfallen.
  remove,

  /// Nichts tun.
  nothing,
}

/// Was jetzt mit der eigenen Spur zu geschehen hat.
///
/// **Die Bedingung ist UND, nicht ODER**: Es braucht eine laufende Tour
/// UND eine laufende Standort-Freigabe. Wer aufzeichnet, ohne zu teilen,
/// bekommt Stufe 1 unverändert — die Spur verlässt sein Gerät nicht. Das
/// ist der ganze Zustimmungs-Entwurf in einer Zeile: Die Freigabe, die
/// jemand schon gegeben hat („ich teile meinen Standort für 2 h"), trägt
/// auch die Spur, die denselben Weg erklärt.
///
/// [lastUploadAt] `null` heißt „noch nie hochgeladen" — dann liegt auch
/// nichts auf dem Server, und [remove] wäre ein Aufruf ins Leere.
TrackShareAction planTrackShare({
  required bool tourRunning,
  required int pointCount,
  required DateTime? shareExpiresAt,
  required DateTime? lastUploadAt,
  required int lastUploadedCount,
  required DateTime now,
}) {
  final sharing = shareExpiresAt != null && shareExpiresAt.isAfter(now);
  if (!sharing || !tourRunning) {
    // Zurücknehmen, sobald eine der beiden Voraussetzungen wegfällt —
    // und nicht erst, wenn `expires_at` abläuft. Bis dahin läge dort
    // eine Freigabe, die niemand mehr gibt.
    return lastUploadAt == null
        ? TrackShareAction.nothing
        : TrackShareAction.remove;
  }
  if (pointCount < kMinSharedTrackPoints) return TrackShareAction.nothing;
  if (lastUploadAt == null) return TrackShareAction.upload;
  // Nichts Neues gemessen: Ein Upsert mit denselben Punkten kostet
  // Egress und ändert nichts. `updated_at` soll etwas bedeuten.
  if (pointCount == lastUploadedCount) return TrackShareAction.nothing;
  return now.difference(lastUploadAt) >= kTrackUploadInterval
      ? TrackShareAction.upload
      : TrackShareAction.nothing;
}
