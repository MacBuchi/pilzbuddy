// Ob der Browser zusichert, unseren Speicher nicht von sich aus zu
// räumen.
//
// Der Unterschied, den es zwischen den Plattformen wirklich gibt: Eine
// Datei auf Android bleibt liegen, bis jemand sie löscht. Browser
// dagegen räumen unter Speicherdruck auf — und ein Ausgangskorb, der
// still verfallen kann, ist schlimmer als gar keiner.
//
// Dieselbe Bauweise wie `idb_factory.dart`: Der Web-Weg ist die Vorgabe,
// `dart.library.io` wählt den Stub.
export 'browser_storage_web.dart'
    if (dart.library.io) 'browser_storage_stub.dart';
