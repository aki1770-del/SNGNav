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

  // The Japanese guidance is a faithful, adversarially-verified translation
  // (asset `_meta.translation_ja`). It must reach HER mother in Japanese, fall
  // back to grounded English where absent, and keep its safety-load-bearing
  // figures exact (a number drift in a safety instruction is a D4 event).
  group('Japanese guidance (guidance_ja)', () {
    final file = File('assets/winter_knowledge.json');

    test('guidanceForLanguage(ja) returns Japanese, else falls back to English',
        () {
      const both = WinterCard(
          state: 'blackIce', guidance: 'Reduce speed.', guidanceJa: '速度を落とす。');
      expect(both.guidanceForLanguage('ja'), '速度を落とす。');
      expect(both.guidanceForLanguage('en'), 'Reduce speed.');

      const enOnly = WinterCard(state: 'wet', guidance: 'Slow down.');
      // No Japanese baked → honest fallback to the grounded English, not blank.
      expect(enOnly.guidanceForLanguage('ja'), 'Slow down.');
    });

    test('cardFor(lang: ja) resolves the Japanese text through the loader', () {
      final wk = WinterKnowledge.fromJsonString('''
        { "cards": { "blackIce": {
            "guidance": "Reduce speed; increase following distance.",
            "guidance_ja": "速度を落とし、車間距離を多めにとる。" } } }''');
      expect(wk.cardFor(RoadSurfaceState.blackIce, lang: 'ja')?.guidance,
          contains('車間距離'));
      // Default + English path stay on the English guidance.
      expect(wk.cardFor(RoadSurfaceState.blackIce)?.guidance,
          contains('Reduce speed'));
    });

    test('shipped asset: every Japanese card is grounded and keeps its figures',
        () {
      final wk = WinterKnowledge.fromJsonString(file.readAsStringSync());
      final jaAction = RegExp(r'速度|車間|ブレーキ|ハンドル|スリップ|タイヤ|凍結');
      final jaRefusal = RegExp(r'できません|提供されていません|含まれていません|わかりません');
      var jaCount = 0;
      for (final state in wk.states) {
        final card = wk.cardFor(RoadSurfaceState.values.byName(state))!;
        final ja = card.guidanceJa;
        if (ja == null) continue; // English-only fallback is allowed.
        jaCount++;
        expect(jaRefusal.hasMatch(ja), isFalse,
            reason: '$state JA card is a refusal');
        expect(jaAction.hasMatch(ja), isTrue,
            reason: '$state JA card lacks action vocabulary');
        expect(ja.contains('5〜6秒') || ja.contains('5～6秒'), isTrue,
            reason: '$state JA card lost the 5–6 second following-distance figure');
      }
      // The four winter-hazard states ship verified Japanese today.
      expect(jaCount, greaterThanOrEqualTo(4));
      // Spot-check a safety-critical figure survives translation verbatim.
      final wet = wk.cardFor(RoadSurfaceState.wet)!.guidanceJa!;
      expect(wet, contains('72'));
      expect(wet, contains('93'));
    });
  });
}
