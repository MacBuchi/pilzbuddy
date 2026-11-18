// Die Kopfzeile der Legenden-Ampel (#732): „rechnet …" nur, solange
// wirklich etwas lädt. Bis 1.226.3 stand es für jede fehlende Stufe —
// ohne Wetter-Zustimmung, nach einem Fehler und bei grauer Ablesung für
// immer.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/map_worker.dart';
import 'package:pilzbuddy/features/ampel/ampel_model.dart';
import 'package:pilzbuddy/features/ampel/ampel_providers.dart';
import 'package:pilzbuddy/features/map/legend_ampel_state.dart';

void main() {
  const done = AsyncValue<Object?>.data(1);
  const loading = AsyncValue<Object?>.loading();
  final failed = AsyncValue<Object?>.error(StateError('kaputt'),
      StackTrace.empty);
  const superseded =
      AsyncValue<Object?>.error(MapWorkerSuperseded(), StackTrace.empty);
  const level = AmpelReading(level: AmpelLevel.guenstig);
  const grau = AmpelReading.grau('keine Wetterstation in Reichweite (100 km)');

  LegendAmpelState of({
    bool consent = true,
    AsyncValue<Object?> course = done,
    AsyncValue<Object?> temperature = done,
    AsyncValue<Object?> height = done,
    AmpelReading? reading = level,
  }) =>
      legendAmpelStateOf(
          consent: consent,
          course: course,
          temperature: temperature,
          height: height,
          reading: reading);

  test('eine Stufe ist eine Stufe', () {
    expect(of(), LegendAmpelState.level);
    expect(legendAmpelWord(LegendAmpelState.level, AmpelLevel.guenstig),
        'günstig');
  });

  test('„rechnet …" nur, solange eine Zutat lädt', () {
    expect(of(course: loading, reading: null), LegendAmpelState.loading);
    expect(of(temperature: loading, reading: null), LegendAmpelState.loading);
    expect(of(height: loading, reading: null), LegendAmpelState.loading);
    expect(legendAmpelWord(LegendAmpelState.loading, null), 'rechnet …');
  });

  test('ein abgelöster Worker-Auftrag heißt „gleich", nicht „Fehler"', () {
    expect(of(course: superseded, reading: grau), LegendAmpelState.loading);
  });

  test('ohne Zustimmung: anbieten, nicht warten', () {
    // Ohne Zustimmung ist der Stapel leer, der Verlauf `null` und die
    // Ablesung grau („keine Regendaten") — das ist NICHT die Antwort.
    expect(of(consent: false, reading: grau), LegendAmpelState.needsConsent);
    expect(of(consent: false, course: loading, reading: null),
        LegendAmpelState.needsConsent);
    expect(legendAmpelWord(LegendAmpelState.needsConsent, null),
        'Wetter laden');
  });

  test('Fehler bei Regen oder Temperatur: keine Daten', () {
    expect(of(course: failed, reading: grau), LegendAmpelState.noData);
    expect(of(temperature: failed, reading: grau), LegendAmpelState.noData);
    expect(legendAmpelWord(LegendAmpelState.noData, null), 'keine Daten');
  });

  test('ohne Höhe rechnet die Ampel unkorrigiert — kein Fehler', () {
    expect(of(height: failed), LegendAmpelState.level);
  });

  test('grau gerechnet: keine Aussage', () {
    expect(of(reading: grau), LegendAmpelState.noStatement);
    expect(legendAmpelWord(LegendAmpelState.noStatement, null),
        'keine Aussage');
  });
}
