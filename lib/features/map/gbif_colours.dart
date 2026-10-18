import 'package:flutter/painting.dart' show Color;

import '../../core/overlay_argb.dart';

/// Die Farbe einer Ampel-Klasse in der Legende — dieselbe Tabelle wie
/// beim Malen ([OverlayArgb.gbifClassColour]), damit Legende und Fläche
/// nie zwei Töne zeigen.
Color gbifClassColour(String? classKey) =>
    Color(OverlayArgb.gbifClassColour(classKey));
