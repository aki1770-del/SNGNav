import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('AlertExplainer.forConditionAndProfile — exhaustive coverage', () {
    test('every (profile × condition) pair returns a non-null entry', () {
      // L7 lock — exhaustive coverage. 6 profiles × 8 conditions = 48
      // combinations must each produce a non-null AlertExplainer with a
      // non-empty action string.
      for (final profile in DriverProfile.values) {
        for (final condition in RoadSurfaceCondition.values) {
          final e = AlertExplainer.forConditionAndProfile(condition, profile);
          expect(
            e.action,
            isNotEmpty,
            reason: 'action for ($profile, $condition) must be non-empty',
          );
          expect(
            e.condition,
            condition,
            reason: 'condition field must match input ($profile, $condition)',
          );
          expect(
            e.localeTag,
            isNotEmpty,
            reason: 'localeTag for ($profile, $condition) must be non-empty',
          );
        }
      }
    });
  });

  group('AlertExplainer verbosity mapping', () {
    test('professional → terse', () {
      final e = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        DriverProfile.professional,
      );
      expect(e.verbosity, VerbosityLevel.terse);
    });

    test('snowZoneExperienced → brief', () {
      final e = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        DriverProfile.snowZoneExperienced,
      );
      expect(e.verbosity, VerbosityLevel.brief);
    });

    test('noviceUrban → standard', () {
      final e = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        DriverProfile.noviceUrban,
      );
      expect(e.verbosity, VerbosityLevel.standard);
    });

    test('agriculturalForestry → standard', () {
      final e = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        DriverProfile.agriculturalForestry,
      );
      expect(e.verbosity, VerbosityLevel.standard);
    });

    test('ageingRural → full', () {
      final e = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        DriverProfile.ageingRural,
      );
      expect(e.verbosity, VerbosityLevel.full);
    });

    test('foreignTouristSnowZone → full', () {
      final e = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        DriverProfile.foreignTouristSnowZone,
      );
      expect(e.verbosity, VerbosityLevel.full);
    });
  });

  group('AlertExplainer locale tag', () {
    test('foreignTouristSnowZone → en, every condition', () {
      for (final condition in RoadSurfaceCondition.values) {
        final e = AlertExplainer.forConditionAndProfile(
          condition,
          DriverProfile.foreignTouristSnowZone,
        );
        expect(
          e.localeTag,
          'en',
          reason: 'foreignTouristSnowZone must use en for $condition',
        );
      }
    });

    test('non-foreign-tourist profiles → ja, every condition', () {
      for (final profile in DriverProfile.values.where(
        (p) => p != DriverProfile.foreignTouristSnowZone,
      )) {
        for (final condition in RoadSurfaceCondition.values) {
          final e = AlertExplainer.forConditionAndProfile(condition, profile);
          expect(
            e.localeTag,
            'ja',
            reason: '$profile must use ja for $condition',
          );
        }
      }
    });
  });

  group('AlertExplainer action-text discipline', () {
    test('no banned imperative-on-control or guarantee tokens', () {
      // Discipline: action verbs are advisory, not control-asserting.
      // No "system will" / "automatically" / "guarantee" / "safe driving"
      // — those would imply the package actuates the vehicle (it does
      // not) or promises an outcome (it does not).
      const banned = <String>[
        'system will',
        'automatically',
        'guarantee',
        'safe driving',
      ];

      for (final profile in DriverProfile.values) {
        for (final condition in RoadSurfaceCondition.values) {
          final e = AlertExplainer.forConditionAndProfile(condition, profile);
          final lower = e.action.toLowerCase();
          for (final token in banned) {
            expect(
              lower.contains(token),
              isFalse,
              reason:
                  'action for ($profile, $condition) must not contain '
                  '"$token" — found in: ${e.action}',
            );
          }
        }
      }
    });

    test('foreignTouristSnowZone WET_ICE uses "if possible" advisory', () {
      // The strongest action ("stop in a safe place") is phrased as an
      // option, not a command. Wording must include "if possible".
      final e = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.wetIce,
        DriverProfile.foreignTouristSnowZone,
      );
      expect(e.action.toLowerCase(), contains('if possible'));
    });

    test('ageingRural WET_ICE uses 可能であれば (advisory phrasing)', () {
      final e = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.wetIce,
        DriverProfile.ageingRural,
      );
      expect(e.action, contains('可能であれば'));
    });
  });

  group('AlertExplainer spot-check table cells (AAA brief)', () {
    test('ageingRural ICE includes 30km speed advisory reference', () {
      final e = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        DriverProfile.ageingRural,
      );
      expect(e.action, contains('30km'));
      // Per AAA brief: "時速30km以下に減速し、急ブレーキは避けてください".
      expect(e.action, contains('減速'));
    });

    test('foreignTouristSnowZone ICE has "Slow to 30 km/h" in EN', () {
      final e = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        DriverProfile.foreignTouristSnowZone,
      );
      expect(e.action, contains('Slow to 30 km/h'));
      expect(e.action, contains('Avoid sudden braking'));
    });

    test('professional WET_ICE is terse (≤25 chars)', () {
      // Per AAA brief: professional → terse one-line "アイスバーン、20km/h".
      final e = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.wetIce,
        DriverProfile.professional,
      );
      expect(
        e.action.length,
        lessThanOrEqualTo(25),
        reason: 'professional WET_ICE expected terse, got: ${e.action}',
      );
      expect(e.action, contains('アイスバーン'));
      expect(e.action, contains('20km/h'));
    });

    test('snowZoneExperienced SNOW is brief (≤30 chars)', () {
      // Per AAA brief: brief format "圧雪、低速ギア、急操作回避".
      final e = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.snow,
        DriverProfile.snowZoneExperienced,
      );
      expect(e.action.length, lessThanOrEqualTo(30));
      expect(e.action, contains('圧雪'));
    });

    test('agriculturalForestry SLUSH includes 轍 (off-road consideration)', () {
      // Per AAA brief: "シャーベット、轍（わだち）に注意".
      final e = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.slush,
        DriverProfile.agriculturalForestry,
      );
      expect(e.action, contains('轍'));
    });

    test('noviceUrban WET_ICE includes "極めて危険" hazard tag', () {
      // Per AAA brief: noviceUrban gets explicit hazard framing.
      final e = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.wetIce,
        DriverProfile.noviceUrban,
      );
      expect(e.action, contains('極めて危険'));
      expect(e.action, contains('20km'));
    });
  });

  group('AlertExplainer ice-formation factual accuracy (0.11.2)', () {
    test('ageingRural ICE must not condition ice on sub-zero air', () {
      // Regression: the pre-0.11.2 string said 「気温0°C以下で薄氷が
      // できています」— asserting ice needs sub-zero AIR. That is false:
      // road surfaces radiate heat and can freeze while the air is above
      // 0°C (bridges first, per JAF). Teaching "air above zero → no ice"
      // to the profile most exposed to radiative frost is the exact
      // misjudgement that kills grip assumptions on a clear cold morning.
      final e = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        DriverProfile.ageingRural,
      );
      expect(e.action, isNot(contains('気温0°C以下')));
      // The corrected string states the above-zero-air possibility.
      expect(e.action, contains('0°Cより高くても'));
      // Speed advisory retained per the AAA brief.
      expect(e.action, contains('30km'));
      expect(e.action, contains('減速'));
    });

    test('ageingRural WET uses JAF term ブラックアイスバーン, not bare ブラックアイス', () {
      // Terminology aligned to the JAF authority (the same term
      // japanese_snow_vocabulary and snow_rendering announce), so the
      // driver hears one consistent hazard name across the stack.
      final e = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.wet,
        DriverProfile.ageingRural,
      );
      expect(e.action, contains('ブラックアイスバーン'));
      expect(e.action, isNot(contains('ブラックアイスが')));
      // Must not condition ice formation on sub-zero air either.
      expect(e.action, isNot(contains('気温0°C以下')));
      // Bridge/tunnel-exit guidance retained.
      expect(e.action, contains('橋'));
    });
  });

  group('AlertExplainer profile-flat conditions (UNKNOWN, DRY)', () {
    test('UNKNOWN: foreignTouristSnowZone uses EN, others JA', () {
      // Per AAA brief: profile-flat content but locale still applies.
      final tourist = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.unknown,
        DriverProfile.foreignTouristSnowZone,
      );
      expect(tourist.localeTag, 'en');
      expect(tourist.action.toLowerCase(), contains('unknown'));

      // All other profiles share JA content for UNKNOWN.
      String? jaUnknown;
      for (final p in DriverProfile.values.where(
        (p) => p != DriverProfile.foreignTouristSnowZone,
      )) {
        final e = AlertExplainer.forConditionAndProfile(
          RoadSurfaceCondition.unknown,
          p,
        );
        jaUnknown ??= e.action;
        expect(
          e.action,
          jaUnknown,
          reason: 'UNKNOWN should be profile-flat for non-tourist profiles',
        );
        expect(e.localeTag, 'ja');
      }
    });

    test('DRY: foreignTouristSnowZone uses EN, others JA, all flat', () {
      final tourist = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.dry,
        DriverProfile.foreignTouristSnowZone,
      );
      expect(tourist.localeTag, 'en');
      expect(tourist.action.toLowerCase(), contains('dry'));

      String? jaDry;
      for (final p in DriverProfile.values.where(
        (p) => p != DriverProfile.foreignTouristSnowZone,
      )) {
        final e = AlertExplainer.forConditionAndProfile(
          RoadSurfaceCondition.dry,
          p,
        );
        jaDry ??= e.action;
        expect(
          e.action,
          jaDry,
          reason: 'DRY should be profile-flat for non-tourist profiles',
        );
      }
    });
  });

  group('VerbosityLevel enum value set', () {
    test('contains the 4 levels in expected order', () {
      // L7 lock — verbosity-level taxonomy must be stable for downstream
      // UX layers that switch on this enum.
      expect(
        VerbosityLevel.values,
        equals(<VerbosityLevel>[
          VerbosityLevel.terse,
          VerbosityLevel.brief,
          VerbosityLevel.standard,
          VerbosityLevel.full,
        ]),
      );
    });
  });

  group('AlertExplainer spoken-form safety (0.11.3)', () {
    test('professional WET names the hazard aloud — 濡路 is spoken as silence',
        () {
      // Regression: the string was 「濡路、注意」. Through open_jtalk 濡路
      // renders as SILENCE, so the driver hears 「（無音）、注意」 — a caution
      // naming no hazard. A warning she cannot hear is not a warning.
      final e = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.wet,
        DriverProfile.professional,
      );
      expect(e.action, isNot(contains('濡路')));
      expect(e.action, contains('濡れた路面'));
    });

    test('no profile uses 濡路 in any WET explainer', () {
      // The outlier existed because one profile drifted from the shared term.
      // Pin the whole set so it cannot drift back on a single profile.
      for (final profile in DriverProfile.values) {
        final e = AlertExplainer.forConditionAndProfile(
          RoadSurfaceCondition.wet,
          profile,
        );
        expect(
          e.action,
          isNot(contains('濡路')),
          reason: '$profile WET explainer must not use the unpronounceable 濡路',
        );
      }
    });
  });
}
