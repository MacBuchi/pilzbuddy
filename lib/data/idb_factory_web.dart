// Reicht `idb_shim.dart` mit durch (die Typen), bringt aber zusätzlich
// den Browser-Zugang mit — deshalb genügt dieser eine Import.
import 'package:idb_shim/idb_browser.dart';

/// Der IndexedDB-Zugang des Browsers — oder `null`, wenn es keinen gibt.
///
/// Das kommt vor: Manche Browser sperren IndexedDB im privaten Modus, und
/// in einem `file://`-Kontext ist es ebenfalls aus. Dann bleibt es beim
/// Verhalten von vorher (kein Zwischenspeicher), statt bei jedem Abruf in
/// eine Ausnahme zu laufen.
///
/// Bewusst NICHT `idbFactoryBrowser`: Das fällt still auf die
/// Speicher-Fassung zurück, und ein Zwischenspeicher, der jeden Neustart
/// vergisst, sähe von außen aus wie einer, der bleibt.
IdbFactory? browserIdbFactory() =>
    idbFactoryNativeSupported ? idbFactoryNative : null;
