/// Die Kennung des Builds, gesetzt in App UND Web Worker (#689, B2):
/// `--dart-define=MAP_WORKER_BUILD=…` bzw. `-DMAP_WORKER_BUILD=…`, in
/// allen drei Web-Builds dieselbe Commit-Kennung.
///
/// Beide Dateien heißen je Deploy gleich, und GitHub Pages lässt sie
/// zehn Minuten im HTTP-Cache. Ohne Abgleich spräche eine neue App mit
/// einem alten Worker — mit anderen Codecs, und das liest sich nicht als
/// Fehler, sondern als Unsinn. Die Kennung steht deshalb in der Adresse
/// des Workers (neuer Build, neue Adresse) und in seiner ersten Meldung
/// (passt sie nicht, rechnet die App selbst). Lokal ist sie auf beiden
/// Seiten leer.
const kMapWorkerBuild = String.fromEnvironment('MAP_WORKER_BUILD');
