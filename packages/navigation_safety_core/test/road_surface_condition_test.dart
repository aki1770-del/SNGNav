import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('RoadSurfaceCondition enum value set', () {
    test('contains the 8 VSS allowed values', () {
      // Taxonomy cross-reference lock — VSS PR #892 ships
      // exactly these 8 values; any addition / removal / reorder requires
      // deliberate audit (consuming code may switch on this enum).
      expect(
        RoadSurfaceCondition.values,
        equals(<RoadSurfaceCondition>[
          RoadSurfaceCondition.unknown,
          RoadSurfaceCondition.dry,
          RoadSurfaceCondition.wet,
          RoadSurfaceCondition.snow,
          RoadSurfaceCondition.ice,
          RoadSurfaceCondition.slush,
          RoadSurfaceCondition.wetIce,
          RoadSurfaceCondition.looseGravel,
        ]),
        reason:
            'RoadSurfaceCondition values must match VSS allowed-value set '
            'verbatim. See COVESA/vehicle_signal_specification PR #892.',
      );
    });
  });

  group('RoadSurfaceCondition.vssValue + fromVss round-trip', () {
    test('every value round-trips to itself', () {
      for (final c in RoadSurfaceCondition.values) {
        expect(RoadSurfaceCondition.fromVss(c.vssValue), equals(c));
      }
    });

    test('vssValue strings match VSS spec verbatim', () {
      expect(RoadSurfaceCondition.unknown.vssValue, 'UNKNOWN');
      expect(RoadSurfaceCondition.dry.vssValue, 'DRY');
      expect(RoadSurfaceCondition.wet.vssValue, 'WET');
      expect(RoadSurfaceCondition.snow.vssValue, 'SNOW');
      expect(RoadSurfaceCondition.ice.vssValue, 'ICE');
      expect(RoadSurfaceCondition.slush.vssValue, 'SLUSH');
      expect(RoadSurfaceCondition.wetIce.vssValue, 'WET_ICE');
      expect(RoadSurfaceCondition.looseGravel.vssValue, 'LOOSE_GRAVEL');
    });

    test('fromVss throws on unknown value (no silent fallback)', () {
      // Silent fallback to RoadSurfaceCondition.unknown would hide upstream
      // schema drift (a future VSS revision adding values this enum does
      // not yet enumerate). Require explicit ArgumentError instead.
      expect(
        () => RoadSurfaceCondition.fromVss('PACKED_SNOW'),
        throwsArgumentError,
      );
      expect(() => RoadSurfaceCondition.fromVss(''), throwsArgumentError);
      expect(
        () => RoadSurfaceCondition.fromVss('wet'),
        throwsArgumentError,
        reason: 'Case-sensitive match expected per VSS convention.',
      );
    });
  });

  group('RoadSurfaceConditionGlossary.forCondition (default, no profile)', () {
    test('every condition returns non-empty labels + speak-strings', () {
      for (final c in RoadSurfaceCondition.values) {
        final g = RoadSurfaceConditionGlossary.forCondition(c);
        expect(g.jaName, isNotEmpty, reason: 'jaName for $c');
        expect(g.enName, isNotEmpty, reason: 'enName for $c');
        expect(g.jaSpeakString, isNotEmpty, reason: 'jaSpeakString for $c');
        expect(g.enSpeakString, isNotEmpty, reason: 'enSpeakString for $c');
      }
    });

    test('SNOW uses 圧雪 not generic 雪', () {
      // 圧雪 names the road state; generic 雪 conflates falling snow with
      // road state.
      final g = RoadSurfaceConditionGlossary.forCondition(
        RoadSurfaceCondition.snow,
      );
      expect(g.jaName, contains('圧雪'));
      expect(g.jaSpeakString, contains('圧雪'));
    });

    test('ICE uses 凍結 (kanji-native)', () {
      final g = RoadSurfaceConditionGlossary.forCondition(
        RoadSurfaceCondition.ice,
      );
      expect(g.jaName, contains('凍結'));
    });

    test('WET_ICE uses アイスバーン loanword + 濡れた凍結 anchor', () {
      final g = RoadSurfaceConditionGlossary.forCondition(
        RoadSurfaceCondition.wetIce,
      );
      expect(g.jaName, contains('アイスバーン'));
      expect(g.jaName, contains('濡れた凍結'));
    });
  });

  group('RoadSurfaceConditionGlossary.forConditionAndProfile', () {
    test('every (profile × condition) pair returns non-empty entry', () {
      // Locks exhaustive coverage. 6 profiles × 8 conditions = 48
      // combinations must each produce a non-null, non-empty glossary
      // entry. Per-profile overrides apply for ICE / SNOW / WET_ICE /
      // SLUSH (the high-risk subset where vocabulary precision matters;
      // SLUSH added in 0.7.1). Other conditions fall through to
      // defaults.
      for (final p in DriverProfile.values) {
        for (final c in RoadSurfaceCondition.values) {
          final g = RoadSurfaceConditionGlossary.forConditionAndProfile(c, p);
          expect(g.jaName, isNotEmpty, reason: 'jaName for ($p, $c)');
          expect(g.enName, isNotEmpty, reason: 'enName for ($p, $c)');
          expect(
            g.jaSpeakString,
            isNotEmpty,
            reason: 'jaSpeakString for ($p, $c)',
          );
          expect(
            g.enSpeakString,
            isNotEmpty,
            reason: 'enSpeakString for ($p, $c)',
          );
        }
      }
    });

    test('foreignTouristSnowZone ICE uses EN-default + simplified JA', () {
      // EN-default policy: foreign
      // tourists cannot parse kanji-only output mid-drive; EN string
      // is TTS-default; simplified JA is available as secondary.
      final g = RoadSurfaceConditionGlossary.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        DriverProfile.foreignTouristSnowZone,
      );
      expect(g.enSpeakString, contains('Icy road'));
      // Simplified JA — no kanji-native 凍結.
      expect(g.jaSpeakString, isNot(contains('凍結')));
      expect(g.jaSpeakString, contains('氷'));
    });

    test('ageingRural ICE uses kanji-native 凍結 (not loanword)', () {
      // 凍結 (kanji-native) for ageingRural is a recorded wording
      // decision; no source is cited for which terms older drivers know.
      final g = RoadSurfaceConditionGlossary.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        DriverProfile.ageingRural,
      );
      expect(g.jaSpeakString, contains('凍結'));
    });

    test('snowZoneExperienced gets terse speak-string', () {
      // Experienced snow-zone drivers tolerate brief alerts; they can
      // disambiguate「凍結」without explanation.
      final g = RoadSurfaceConditionGlossary.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        DriverProfile.snowZoneExperienced,
      );
      // Single-word or near-single-word — much shorter than ageingRural.
      expect(g.jaSpeakString.length, lessThan(20));
    });

    test('non-overridden conditions fall through to defaults', () {
      // The override table covers ICE / SNOW / WET_ICE / SLUSH (SLUSH
      // added 0.7.1). DRY / WET / LOOSE_GRAVEL / UNKNOWN should return
      // the same entry regardless of profile (defaults).
      final defaultDry = RoadSurfaceConditionGlossary.forCondition(
        RoadSurfaceCondition.dry,
      );
      for (final p in DriverProfile.values) {
        final g = RoadSurfaceConditionGlossary.forConditionAndProfile(
          RoadSurfaceCondition.dry,
          p,
        );
        expect(g.jaName, defaultDry.jaName);
        expect(g.jaSpeakString, defaultDry.jaSpeakString);
      }
    });

    test('SLUSH ageingRural uses full kanji-native phrasing with action cue '
        '(0.7.1)', () {
      // 0.7.1 expansion: SLUSH (シャーベット) added to high-risk subset
      // for the lateral-slip risk of partially-melted snow (a recorded
      // decision; no source is cited for how drivers judge that risk).
      // ageingRural override gives full phrasing + action cue.
      final g = RoadSurfaceConditionGlossary.forConditionAndProfile(
        RoadSurfaceCondition.slush,
        DriverProfile.ageingRural,
      );
      expect(g.jaSpeakString, contains('シャーベット'));
      expect(g.jaSpeakString, contains('横滑り'));
    });

    test('SLUSH snowZoneExperienced + professional get terse single-token '
        '(0.7.1)', () {
      // Terse vocabulary mirrors ICE/SNOW/WET_ICE pattern for these
      // two trained-driver profiles.
      final gExperienced = RoadSurfaceConditionGlossary.forConditionAndProfile(
        RoadSurfaceCondition.slush,
        DriverProfile.snowZoneExperienced,
      );
      expect(gExperienced.jaSpeakString, 'シャーベット');

      final gPro = RoadSurfaceConditionGlossary.forConditionAndProfile(
        RoadSurfaceCondition.slush,
        DriverProfile.professional,
      );
      expect(gPro.jaSpeakString, 'シャーベット');
    });

    test('SLUSH noviceUrban gets explicit hazard wording (0.7.1)', () {
      // Less low-vis / icy-road experience; phrasing surfaces
      // skid-class danger explicitly.
      final g = RoadSurfaceConditionGlossary.forConditionAndProfile(
        RoadSurfaceCondition.slush,
        DriverProfile.noviceUrban,
      );
      expect(g.jaSpeakString, contains('シャーベット'));
      expect(g.jaSpeakString, contains('危険'));
    });

    test('SLUSH foreignTouristSnowZone uses EN-default + simplified JA '
        '(0.7.1)', () {
      // EN-default policy: foreign tourists
      // cannot parse kanji-only output mid-drive; EN string is
      // TTS-default; simplified JA available as secondary.
      final g = RoadSurfaceConditionGlossary.forConditionAndProfile(
        RoadSurfaceCondition.slush,
        DriverProfile.foreignTouristSnowZone,
      );
      expect(g.enSpeakString, contains('Slush'));
      expect(g.enSpeakString, contains('slippery'));
      expect(g.jaSpeakString, contains('シャーベット'));
    });
  });
}
