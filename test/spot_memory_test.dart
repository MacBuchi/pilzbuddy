// Die Spot-Erinnerung (Baustein C des Ampel-Konzepts): reine Rechnung
// auf der eigenen Historie, ohne Netz und ohne Modell.
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/features/map/spot_memory.dart';
import 'package:pilzbuddy/models/find.dart';
import 'package:pilzbuddy/models/spot.dart';

Find _find(DateTime day,
        {String? species = 'Steinpilz',
        bool isOwn = true,
        bool blank = false}) =>
    Find(
      id: 'f-${day.toIso8601String()}-$species-$isOwn',
      spotId: 's',
      species: blank ? null : species,
      count: blank ? null : 1,
      foundOn: day,
      isOwn: isOwn,
      blank: blank,
    );

Spot _spot(String id, List<Find> finds, {String? name}) => Spot(
      id: id,
      ownerId: 'me',
      name: name,
      lat: 51.0,
      lng: 10.0,
      finds: finds,
    );

void main() {
  final today = DateTime(2026, 9, 20);

  test('erinnert an Funde aus dem Vorjahresfenster', () {
    final spot = _spot('a', [_find(DateTime(2025, 9, 18))], name: 'Buchenhang');
    final memory = spotMemoryOf([spot], today);
    expect(memory, isNotNull);
    expect(memory!.spot.id, 'a');
    expect(memory.count, 1);
    expect(memory.species, 'Steinpilz');
    expect(memory.year, 2025);
  });

  test('das Fenster ist ±14 Tage — und der Rand zählt noch', () {
    Spot at(DateTime day) => _spot('x', [_find(day)]);
    expect(spotMemoryOf([at(DateTime(2025, 9, 6))], today), isNotNull,
        reason: 'genau 14 Tage davor');
    expect(spotMemoryOf([at(DateTime(2025, 10, 4))], today), isNotNull,
        reason: 'genau 14 Tage danach');
    expect(spotMemoryOf([at(DateTime(2025, 8, 20))], today), isNull,
        reason: 'einen Monat daneben ist keine Erinnerung „um diese Zeit"');
  });

  test('das laufende Jahr zählt nicht', () {
    // Was vor drei Wochen war, weiß man noch — die Erinnerung gilt dem,
    // was ein Jahr oder länger her ist.
    final spot = _spot('a', [_find(DateTime(2026, 9, 15))]);
    expect(spotMemoryOf([spot], today), isNull);
  });

  test('Leergänge und fremde Funde erinnern nicht', () {
    final leer = _spot('a', [_find(DateTime(2025, 9, 18), blank: true)]);
    expect(spotMemoryOf([leer], today), isNull,
        reason: '„nichts gefunden" ist keine Erinnerung wert');
    final fremd = _spot('b',
        [_find(DateTime(2025, 9, 18), isOwn: false)]);
    expect(spotMemoryOf([fremd], today), isNull,
        reason: 'der Fund des Buddys ist seine Erinnerung, nicht meine');
  });

  test('der ergiebigste Spot gewinnt, bei Gleichstand das jüngere Jahr', () {
    final wenig = _spot('wenig', [_find(DateTime(2025, 9, 19))]);
    final viel = _spot('viel', [
      _find(DateTime(2024, 9, 19)),
      _find(DateTime(2024, 9, 21)),
    ]);
    expect(spotMemoryOf([wenig, viel], today)!.spot.id, 'viel');

    final alt = _spot('alt', [_find(DateTime(2023, 9, 19))]);
    final neu = _spot('neu', [_find(DateTime(2025, 9, 19))]);
    expect(spotMemoryOf([alt, neu], today)!.spot.id, 'neu');
  });

  test('gemischte Arten im Fenster nennen keine Art', () {
    // „Steinpilz" über einem gemischten Fenster wäre eine Behauptung,
    // die die Daten nicht hergeben.
    final spot = _spot('a', [
      _find(DateTime(2025, 9, 18)),
      _find(DateTime(2025, 9, 19), species: 'Marone'),
    ]);
    final memory = spotMemoryOf([spot], today);
    expect(memory!.count, 2);
    expect(memory.species, isNull);
  });

  test('über die Jahreswende hinweg', () {
    // Der 28. Dezember liegt 8 Tage neben dem 5. Januar, nicht 357 —
    // die naive Tagesdifferenz wäre hier der Fehler.
    final silvester = _spot('winter', [_find(DateTime(2025, 12, 28))]);
    expect(spotMemoryOf([silvester], DateTime(2027, 1, 5)), isNotNull);
    expect(spotMemoryOf([silvester], DateTime(2027, 2, 5)), isNull);
  });

  test('ohne Spots und ohne passende Funde gibt es nichts', () {
    expect(spotMemoryOf(const [], today), isNull);
    expect(spotMemoryOf([_spot('leer', const [])], today), isNull);
  });
}
