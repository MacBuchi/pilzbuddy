// Was WIRKLICH auf der Karte liegt — im Unterschied zu dem, was
// eingeschaltet ist (#464).
//
// Die Ebenen-Schalter sagen, was der Nutzer haben will. Diese Datei sagt,
// was gerade gezeichnet wird. Dazwischen liegt genau eine Frage: Ist der
// Vorhang zu?
//
// **Eine eigene Datei, kein Platz im Karten-Blatt**: Die Zeichenwege
// (`flutter_map_view.dart`, `maplibre_style_provider.dart`,
// `rain_data_providers.dart`) müssen das hier lesen, und ein Provider,
// der in einer Widget-Datei wohnt, zwänge sie, ein Widget zu
// importieren.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'rain_layer.dart';

/// Sind die Datenflächen gerade ausgeblendet (#464)?
///
/// **Wofür das da ist:** sich kurz auf der nackten OSM-Karte
/// orientieren. Wald, Ampel und Regen liegen als halbdurchsichtige
/// Flächen über allem, und genau dann, wenn man wissen will, wo der Weg
/// hingeht, sind sie im Weg.
///
/// **Es ist ein Vorhang, kein Schalter.** Die Ebenen-Einstellungen
/// werden NICHT angefasst — das Zeichnen fragt zusätzlich hier nach.
/// Daraus folgt das, was der Betreiber verlangt hat („beim Einschalten
/// sollten alle vorausgewählten Ebenen berücksichtigt werden"), ohne
/// dass es jemand herstellen muss: Es gibt keinen Schnappschuss, der
/// verloren gehen könnte, und der Rückweg ist zwangsläufig genau der
/// Zustand von vorher. Ein Merker, der die echten Schalter umlegt, wäre
/// die Fassung, bei der ein Absturz im ausgeblendeten Zustand die
/// Auswahl frisst.
///
/// **Nur für die Sitzung**, wie [ampelBannerMutedProvider] und aus
/// demselben Grund (#425): Ein Zustand, der das Feature wegnimmt und den
/// Neustart überdauert, wird als Fehler gemeldet statt als eigene
/// Entscheidung erkannt. Hier ist der Knopf zwar sichtbar und trägt
/// seinen Zustand — trotzdem ist der nächste Start der ehrlichere
/// Rückweg als ein Merker, der Wochen liegen bleibt.
final mapOverlaysHiddenProvider = StateProvider<bool>((ref) => false);

/// Die Regenebene, wie sie GEZEICHNET wird — `off`, solange der Vorhang
/// zu ist.
///
/// Der Regen braucht diesen Umweg als einziger: Wald, Ampel und
/// Höhenlinien hängen an je einem Fläche-Provider, in dem der Vorhang
/// direkt gefragt werden kann. Beim Regen entscheidet die gewählte Ebene
/// über VIER Dinge — Grenzen, Darstellung (eigene Fläche oder DWD-Bild),
/// Fläche und Bild-URL. Sie hier einmal auf `off` zu drehen nimmt alle
/// vier mit; jedes einzeln abzufangen wären vier Stellen, an denen eine
/// vergessen werden kann.
///
/// **Nicht in [rainLayerProvider] selbst**: Den liest auch das
/// Regen-Blatt, und dort soll weiter stehen, was gewählt IST — nicht,
/// was gerade zu sehen ist.
final drawnRainLayerProvider = Provider<RainLayer>((ref) =>
    ref.watch(mapOverlaysHiddenProvider)
        ? RainLayer.off
        : ref.watch(rainLayerProvider));
