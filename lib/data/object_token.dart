import 'dart:math';

final _random = Random.secure();

/// Ein Dateiname für ein hochgeladenes Objekt: 32 Hex-Zeichen Zufall.
///
/// Zufall statt laufender Nummer, damit zwei Geräte desselben Kontos
/// nie kollidieren — und `Random.secure()`, damit ein Pfad nicht zu
/// erraten ist: Der Bucket ist privat, aber ein Name, den jeder
/// hochzählen kann, wäre ein zweites Schloss aus Pappe.
String newObjectToken() => List.generate(
        16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'))
    .join();
