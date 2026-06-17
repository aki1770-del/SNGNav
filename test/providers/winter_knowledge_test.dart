/// Tests for the offline winter-guidance provider and the shipped asset.
library;

import 'dart:convert';
import 'dart:io';

import 'package:driving_conditions/driving_conditions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_snow_scene/providers/winter_knowledge.dart';

void main() {
  group('WinterKnowledge.fromJsonString', () {
    const json = '''
    { "cards": {
        "blackIce": { "guidance": "Reduce speed; increase following distance." },
        "wet":      { "guidance": "Slow down to disperse water." }
    } }''';

    test('parses baked cards keyed by surface state', () {
      final wk = WinterKnowledge.fromJsonString(json);
      expect(wk.cardFor(RoadSurfaceState.blackIce)?.guidance,
          contains('Reduce speed'));
      expect(wk.cardFor(RoadSurfaceState.wet)?.guidance, contains('Slow down'));
    });

    test('returns null for an un-baked state (honest degradation)', () {
      final wk = WinterKnowledge.fromJsonString(json);
      // No card for dry / slush / compactedSnow in this fixture.
      expect(wk.cardFor(RoadSurfaceState.dry), isNull);
      expect(wk.cardFor(RoadSurfaceState.slush), isNull);
    });

    test('drops empty-guidance entries', () {
      final wk = WinterKnowledge.fromJsonString(
          '{ "cards": { "slush": { "guidance": "   " } } }');
      expect(wk.cardFor(RoadSurfaceState.slush), isNull);
    });

    test('malformed / empty JSON yields an empty, never-crashing lookup', () {
      final wk = WinterKnowledge.fromJsonString('{}');
      expect(wk.states, isEmpty);
      expect(wk.cardFor(RoadSurfaceState.blackIce), isNull);
    });
  });

  group('shipped asset (assets/winter_knowledge.json)', () {
    // The asset is produced offline by tool/winter_knowledge/ and is the
    // drive-time substrate. Guard that it stays present, parseable, and
    // GROUNDED — every card must carry concrete driver-action vocabulary, not
    // a refusal or boilerplate. (A refusal slipping through would defeat the
    // whole offline-guidance path.)
    final file = File('assets/winter_knowledge.json');

    test('exists and parses', () {
      expect(file.existsSync(), isTrue,
          reason: 'run tool/winter_knowledge/build_asset.py');
      final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(root['cards'], isA<Map<String, dynamic>>());
    });

    test('every baked card is grounded (action vocabulary, not a refusal)', () {
      final wk = WinterKnowledge.fromJsonString(file.readAsStringSync());
      expect(wk.states, isNotEmpty);
      final refusal = RegExp(
        r'cannot answer|do(es)? not contain|please provide|not provided|'
        r'will not invent|i need|lacks',
        caseSensitive: false,
      );
      final action = RegExp(
        r'speed|distance|brak|steer|slow|gentl|traction|tyre|tire',
        caseSensitive: false,
      );
      for (final state in wk.states) {
        final g = wk.cardFor(RoadSurfaceState.values.byName(state))!.guidance;
        expect(refusal.hasMatch(g), isFalse, reason: '$state card is a refusal');
        expect(action.hasMatch(g), isTrue,
            reason: '$state card lacks action vocabulary');
        expect(g.length, greaterThan(60), reason: '$state card too short');
      }
    });
  });
}
