// Neuheiten und Tipps (#596): die Pflege der Liste und die eine
// Entscheidung, wer wann was sieht.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilzbuddy/core/update_check.dart';
import 'package:pilzbuddy/features/highlights/feature_highlights.dart';

String pubspecVersion() => RegExp(r'^version:\s*([\d.]+)', multiLine: true)
    .firstMatch(File('pubspec.yaml').readAsStringSync())!
    .group(1)!;

FeatureHighlight entry(String id, String since,
        {HighlightKind kind = HighlightKind.highlight}) =>
    FeatureHighlight(
      id: id,
      since: since,
      kind: kind,
      tab: HighlightTab.map,
      icon: Icons.star,
      title: id,
      text: id,
      target: '/',
    );

void main() {
  group('Pflege der Liste', () {
    test('jede Kennung genau einmal', () {
      final ids = kFeatureHighlights.map((h) => h.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('keine Funktion aus der Zukunft', () {
      // Ein Eintrag, dessen Version noch nicht ausgeliefert ist, stünde
      // nie im Blatt (der Planer filtert ihn) — und wäre in „Entdecken"
      // eine Funktion, die es nicht gibt.
      final current = pubspecVersion();
      for (final h in kFeatureHighlights) {
        expect(isNewerVersion(h.since, current), isFalse,
            reason: '${h.id}: ${h.since} > $current');
      }
    });

    test('der Rückblick beginnt mit Highlights, die es gibt', () {
      expect(kRecapLead, hasLength(kHighlightSheetMax));
      for (final id in kRecapLead) {
        final h = kFeatureHighlights.where((h) => h.id == id).single;
        expect(h.kind, HighlightKind.highlight, reason: id);
      }
    });

    test('Texte bleiben kurz: höchstens drei Sätze', () {
      for (final h in kFeatureHighlights) {
        final sentences = RegExp(r'[.!?](\s|$)').allMatches(h.text).length;
        expect(sentences, inInclusiveRange(1, 3), reason: h.id);
        expect(h.title.length, lessThanOrEqualTo(40), reason: h.id);
      }
    });

    test('jedes Ziel ist ein Pfad der App', () {
      // Ob der Router ihn kennt, prüft der Flow-Test; hier nur die Form.
      for (final h in kFeatureHighlights) {
        expect(h.target, startsWith('/'), reason: h.id);
      }
    });
  });

  group('planHighlights', () {
    final all = [
      entry('alt', '1.10.0'),
      entry('mitte', '1.20.0'),
      entry('neu-a', '1.30.0'),
      entry('neu-b', '1.30.0'),
      entry('tipp', '1.30.0', kind: HighlightKind.tip),
      entry('zukunft', '1.40.0'),
    ];

    HighlightPlan plan({
      String? current = '1.30.0',
      String? seen,
      bool tourSeen = true,
    }) =>
        planHighlights(
          current: current,
          seenVersion: seen,
          mapTourSeen: tourSeen,
          all: all,
          recapLead: const ['mitte'],
        );

    List<String> pages(HighlightPlan p) =>
        (p as HighlightShow).pages.map((h) => h.id).toList();

    test('frische Installation: nichts zeigen, Version merken', () {
      final p = plan(tourSeen: false);
      expect(p, isA<HighlightRecord>());
      expect((p as HighlightRecord).version, '1.30.0');
    });

    test('Bestandsnutzer ohne Merker: Rückblick, Spitze zuerst', () {
      final p = plan() as HighlightShow;
      expect(p.recap, isTrue);
      // Die Spitze aus `recapLead`, dann die Liste in ihrer Reihenfolge —
      // nie ein Tipp und nie die Zukunft.
      expect(pages(p), ['mitte', 'alt', 'neu-a']);
      expect(p.more, 1);
    });

    test('nach einem Update: nur Neues, Jüngstes zuerst', () {
      final p = plan(seen: '1.15.0') as HighlightShow;
      expect(p.recap, isFalse);
      expect(pages(p), ['neu-a', 'neu-b', 'mitte']);
      expect(p.more, 0);
    });

    test('mehr als drei: die jüngsten, der Rest zählt als „weitere"', () {
      final p = plan(seen: '1.0.0') as HighlightShow;
      expect(pages(p), ['neu-a', 'neu-b', 'mitte']);
      expect(p.more, 1);
    });

    test('Update ohne Highlight: nur merken', () {
      final p = plan(current: '1.35.0', seen: '1.30.0');
      expect(p, isA<HighlightRecord>());
    });

    test('schon gemerkt: nichts, auch nichts zurückschreiben', () {
      expect(plan(seen: '1.30.0'), isA<HighlightNothing>());
      // Der gemerkte Stand ist JÜNGER (Rückschritt vom Vorabkanal):
      // zurückzuschreiben hieße, alles dazwischen noch einmal zu zeigen.
      expect(plan(seen: '1.35.0'), isA<HighlightNothing>());
    });

    test('Version unbekannt: gar nichts', () {
      expect(plan(current: '–'), isA<HighlightNothing>());
      expect(plan(current: null), isA<HighlightNothing>());
    });
  });
}
