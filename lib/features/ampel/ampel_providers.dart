// Die Ampel-Vorschau auf dem Gerät: Schalter, Datenadapter, Ablesung.
//
// Alles LOKAL — Regenstapel, Stationstabelle und Saisonkurven liegen
// längst auf dem Gerät (bzw. kommen über die bestehende Regen-
// Zustimmung); keine Koordinate verlässt es, kein neues Netzziel.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/settings.dart';
import '../map/elevation_grid.dart' show lapseCorrectionK;
import '../map/rain_stack.dart';
import '../map/spot_weather.dart';
import 'ampel_model.dart';

/// Zeigt die App die experimentelle Ampel-Vorschau? Muster
/// `MapLongPressEnabledNotifier`: Zustand springt sofort, Speichern
/// läuft nach, ein Fehler beim Merken wird nur protokolliert.
class AmpelPreviewEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(settingsProvider).ampelPreviewEnabled;

  void set(bool value) {
    state = value;
    unawaited(ref
        .read(settingsProvider)
        .setAmpelPreviewEnabled(value)
        .catchError((Object e, StackTrace stackTrace) {
      logError('Ampel-Vorschau merken', e, stackTrace);
    }));
  }
}

final ampelPreviewEnabledProvider =
    NotifierProvider<AmpelPreviewEnabledNotifier, bool>(
        AmpelPreviewEnabledNotifier.new);

/// So viele der 26 Regentage müssen eine Messung haben, sonst gibt es
/// eine graue Ampel statt einer Stufe: Das Werkzeug rechnet Fehltage
/// als 0 mm — bei vollständigen Open-Meteo-Reihen harmlos, bei einem
/// löchrigen Radarrand eine still zu niedrige Feuchte.
const ampelMinRainDays = 24;

/// Und so viele der 20 Temperaturtage — die Glocke überspringt
/// Fehltage, aber ein Mittel aus einer Handvoll Tagen ist kein
/// 20-Tage-Mittel mehr.
const ampelMinTempDays = 14;

/// Eine Ablesung: entweder eine Stufe samt Komponenten — oder GRAU mit
/// Grund ([reason] gesetzt). Grau ist eine Antwort, kein Fehler:
/// „Lieber eine graue Ampel als eine erfundene" (Konzept).
class AmpelReading {
  const AmpelReading({
    this.level,
    this.score,
    this.rainFactor,
    this.tempFactor,
    this.tempMeanC,
    this.spotHeightM,
    this.heightCorrectionK,
    this.reason,
  });

  const AmpelReading.grau(String this.reason)
      : level = null,
        score = null,
        rainFactor = null,
        tempFactor = null,
        tempMeanC = null,
        spotHeightM = null,
        heightCorrectionK = null;

  final AmpelLevel? level;
  final double? score;
  final double? rainFactor;
  final double? tempFactor;

  /// Das tatsächlich benutzte 20-Tage-Mittel — steht in der
  /// Komponenten-Zeile, damit die Stufe nachvollziehbar ist. Seit der
  /// Höhenkorrektur ist es das Mittel AUF SPOTHÖHE, wenn
  /// [heightCorrectionK] gesetzt ist.
  final double? tempMeanC;

  /// Die Wabenhöhe, auf die umgerechnet wurde — `null`, wenn keine
  /// Korrektur lief (kein Höhengitter, Punkt außerhalb).
  final int? spotHeightM;

  /// Um wie viel Kelvin die Stationswerte verschoben wurden. Steht als
  /// eigenes Feld da, damit die Anzeige entscheiden kann, ab wann die
  /// Umrechnung eine Erwähnung wert ist.
  final double? heightCorrectionK;

  final String? reason;

  bool get isGrau => reason != null;
}

/// Die Ablesung aus Verlauf und Stationstemperatur — eine PURE
/// Funktion, kein eigener Provider: Die Sektion beobachtet die zwei
/// bestehenden Familien (`rainCourseProvider`,
/// `spotTemperatureProvider`) und rechnet die paar Dutzend Werte
/// synchron durch. Ein dritter async Provider über denselben Futures
/// hatte sich in der Fake-Async-Zone des Test-Harness verheddert — und
/// gebraucht wird er nicht: Das hier ist Arithmetik, kein I/O.
/// [spotHeightM] ist die Wabenhöhe aus dem Höhengitter — wenn gesetzt,
/// werden die Stationstage VOR dem Modell um 0,65 K je 100 m
/// Höhendifferenz verschoben (`lapseCorrectionK`). Die Korrektur ist
/// bewusst Eingabe-Aufbereitung und keine Modelländerung: Der
/// Modellkern bleibt Zahl für Zahl der Spiegel des
/// Validierungswerkzeugs — das ohnehin immer schon Temperaturen auf
/// Zielhöhe gesehen hat (Open-Meteo-Downscaling).
AmpelReading ampelReadingFrom(
    RainCourse? course, SpotTemperature? temperature,
    {int? spotHeightM}) {
  if (course == null || course.isEmpty) {
    return const AmpelReading.grau('keine Regendaten für diesen Punkt');
  }
  // Modell-Ordnung: Vortag zuerst. Der Verlauf kommt ältester-zuerst.
  final rain = [
    for (final day in course.days.reversed) day.mm?.toDouble(),
  ];
  if (rain.length < ampelRainWindow) {
    return AmpelReading.grau('Regenreihe erst ${rain.length} von '
        '$ampelRainWindow Tagen tief — kommt mit den nächsten '
        'Daten-Updates');
  }
  final rainKnown =
      rain.take(ampelRainWindow).where((mm) => mm != null).length;
  if (rainKnown < ampelMinRainDays) {
    return const AmpelReading.grau(
        'Regenreihe zu lückig (Rand des Radarverbunds?)');
  }

  final air = temperature?.air;
  if (air == null) {
    return const AmpelReading.grau(
        'keine Wetterstation in Reichweite (100 km)');
  }
  // Tagesmittel ≈ (Max + Min) / 2 der nächsten Luft-Station — bewusste
  // Näherung an das Tagesmittel der Validierung (Open-Meteo t2m-Mittel);
  // im Kopf von ampel_model.dart benannt. Vortag zuerst, wie der Regen.
  final correction = spotHeightM == null
      ? null
      : lapseCorrectionK(
          stationHeightM: air.station.height, targetHeightM: spotHeightM);
  final maxs = air.station.max;
  final mins = air.station.min;
  final temps = <double?>[
    for (var i = maxs.length - 1; i >= 0; i--)
      (maxs[i] != null && mins[i] != null)
          ? (maxs[i]! + mins[i]!) / 2 + (correction ?? 0)
          : null,
  ];
  final tempKnown =
      temps.take(ampelTempWindow).where((c) => c != null).length;
  if (tempKnown < ampelMinTempDays) {
    return const AmpelReading.grau(
        'Temperaturreihe der Station zu lückig');
  }

  final rainFactor = ampelRainFactor(rain);
  final tempFactor = ampelTemperatureFactor(temps);
  final score = rainFactor * tempFactor;
  var tempSum = 0.0;
  var tempCount = 0;
  for (final c in temps.take(ampelTempWindow)) {
    if (c == null) continue;
    tempSum += c;
    tempCount++;
  }
  return AmpelReading(
    level: ampelLevelOf(score),
    score: score,
    rainFactor: rainFactor,
    tempFactor: tempFactor,
    tempMeanC: tempSum / tempCount,
    spotHeightM: correction == null ? null : spotHeightM,
    heightCorrectionK: correction,
  );
}
