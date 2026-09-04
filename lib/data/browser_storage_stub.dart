/// Alles außer dem Browser: Ein Dateisystem verfällt nicht.
///
/// Bewusst `true` und nicht `false`: Ein Warnhinweis auf Android wäre
/// schlicht falsch, und die Fehlerrichtung „warnt, wo nichts ist"
/// verbraucht genau die Aufmerksamkeit, die der echte Fall braucht.
Future<bool> requestDurableStorage() async => true;

/// Siehe [requestDurableStorage].
Future<bool> isStorageDurable() async => true;
