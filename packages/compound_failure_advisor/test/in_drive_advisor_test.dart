import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:test/test.dart';

/// Builds a [DriveSituation] with sensible defaults; override per axis.
DriveSituation sit({
  PositionTrust positionTrust = PositionTrust.trusted,
  double confidenceRadiusMeters = 10,
  double secondsSinceTrustedFix = 0,
  bool hasPosition = true,
  double? visibilityMeters = 1500,
  double? visibilityAgeSeconds = 10,
  AdvisoryLevel? advisorySeverity,
  double? speedMetersPerSecond = 8,
}) =>
    DriveSituation(
      positionTrust: positionTrust,
      confidenceRadiusMeters: confidenceRadiusMeters,
      secondsSinceTrustedFix: secondsSinceTrustedFix,
      hasPosition: hasPosition,
      visibilityMeters: visibilityMeters,
      visibilityAgeSeconds: visibilityAgeSeconds,
      advisorySeverity: advisorySeverity,
      speedMetersPerSecond: speedMetersPerSecond,
    );

// Representative visibility per concern band: 0=clear, 1=reduced, 2=low,
// 3=whiteout, plus null and a stale reading.
const _visBands = <String, ({double? meters, double? age, int concern})>{
  'clear': (meters: 1500, age: 10, concern: 0),
  'reduced': (meters: 700, age: 10, concern: 1),
  'low': (meters: 300, age: 10, concern: 2),
  'whiteout': (meters: 120, age: 10, concern: 3),
  'null': (meters: null, age: null, concern: 1),
  'stale': (meters: 700, age: 9999, concern: 1),
};

int _expectedPc(PositionTrust trust, {required bool hasPosition}) {
  if (!hasPosition) return 3;
  switch (trust) {
    case PositionTrust.trusted:
      return 0;
    case PositionTrust.suspect:
      return 1;
    case PositionTrust.degraded:
      return 2; // grid uses a small radius + fresh fix → stays 2
    case PositionTrust.lost:
      return 3;
  }
}

int _expectedAc(AdvisoryLevel? a) => switch (a) {
      null || AdvisoryLevel.minor => 0,
      AdvisoryLevel.moderate => 1,
      AdvisoryLevel.severe => 2,
      AdvisoryLevel.extreme => 3,
    };

DriveAction _actionFromScore(int s) => switch (s) {
      0 => DriveAction.continueDriving,
      1 || 2 => DriveAction.heightenedCaution,
      _ => DriveAction.considerStopping,
    };

void main() {
  group('Obligation 1 — exhaustive grid (position×vis×advisory×speed)', () {
    test('every combination matches the documented fusion model', () {
      const advisories = <AdvisoryLevel?>[
        null,
        AdvisoryLevel.minor,
        AdvisoryLevel.moderate,
        AdvisoryLevel.severe,
        AdvisoryLevel.extreme,
      ];
      const speeds = <String, double?>{
        'null': null,
        'slow': 5.0, // below kFastForConditionsMps
        'fast': 25.0, // above kFastForConditionsMps
      };

      var count = 0;
      for (final trust in PositionTrust.values) {
        for (final visEntry in _visBands.entries) {
          for (final adv in advisories) {
            for (final speedEntry in speeds.entries) {
              final s = sit(
                positionTrust: trust,
                visibilityMeters: visEntry.value.meters,
                visibilityAgeSeconds: visEntry.value.age,
                advisorySeverity: adv,
                speedMetersPerSecond: speedEntry.value,
              );
              final advice = adviseInDrive(s);

              final pc = _expectedPc(trust, hasPosition: true);
              final vc = visEntry.value.concern;
              final ac = _expectedAc(adv);
              final corePair = pc > vc ? pc : vc;
              final compounding = pc >= 2 && vc >= 2;
              final speed = speedEntry.value;
              final fast = speed != null && speed > 13.4;

              var score = corePair;
              if (compounding) score = (score + 1).clamp(0, 3);
              if (ac >= 2) score = (score + 1).clamp(0, 3);
              if (fast && corePair >= 1) score = (score + 1).clamp(0, 3);
              if (ac > score) score = ac;
              if (pc > score) score = pc;
              if (vc > score) score = vc;

              final ctx = '$trust/${visEntry.key}/$adv/${speedEntry.key}';
              expect(advice.action, _actionFromScore(score), reason: ctx);
              expect(advice.compounding, compounding, reason: ctx);

              final known =
                  visEntry.key != 'null' && visEntry.key != 'stale';
              expect(advice.visibilityKnown, known, reason: ctx);
              expect(advice.visibilityLow, known && vc >= 2, reason: ctx);

              // reasons cross-checks
              expect(
                advice.reasons.contains(CautionReason.positionUncertain),
                pc >= 1,
                reason: ctx,
              );
              expect(
                advice.reasons.contains(CautionReason.lowVisibility),
                known && vc >= 2,
                reason: ctx,
              );
              expect(
                advice.reasons.contains(CautionReason.reducedVisibility),
                known && vc == 1,
                reason: ctx,
              );
              expect(
                advice.reasons.contains(CautionReason.unknownVisibility),
                visEntry.key == 'null',
                reason: ctx,
              );
              expect(
                advice.reasons.contains(CautionReason.staleVisibility),
                visEntry.key == 'stale',
                reason: ctx,
              );
              expect(
                advice.reasons.contains(CautionReason.severeAdvisory),
                ac >= 2,
                reason: ctx,
              );
              expect(
                advice.reasons.contains(CautionReason.moderateAdvisory),
                ac == 1,
                reason: ctx,
              );

              // INVARIANT: a raised action always carries a statable WHY.
              if (advice.action != DriveAction.continueDriving) {
                expect(advice.reasons, isNotEmpty,
                    reason: 'raised action with empty reasons: $ctx');
              }
              expect(
                advice.reasons
                    .contains(CautionReason.highSpeedInDegradedConditions),
                fast && corePair >= 1,
                reason: ctx,
              );

              // unknowns cross-checks
              expect(
                advice.unknowns.contains(Unknown.speedUnknown),
                speed == null,
                reason: ctx,
              );
              count++;
            }
          }
        }
      }
      // 4 trust × 6 vis × 5 advisory × 3 speed
      expect(count, 4 * 6 * 5 * 3);
    });
  });

  group('Invariant — a raised action always carries a statable WHY', () {
    test(
        'full sweep: action != continueDriving ⇒ reasons non-empty '
        '(vis × advisory × trust × speed × age)', () {
      const advisories = <AdvisoryLevel?>[
        null,
        AdvisoryLevel.minor,
        AdvisoryLevel.moderate,
        AdvisoryLevel.severe,
        AdvisoryLevel.extreme,
      ];
      const speeds = <double?>[null, 5.0, 25.0];
      const ages = <double?>[10, null, 9999, double.nan];
      var checked = 0;
      var raised = 0;
      for (final trust in PositionTrust.values) {
        for (final hasPos in [true, false]) {
          for (final vis in _visBands.values) {
            for (final adv in advisories) {
              for (final speed in speeds) {
                for (final age in ages) {
                  final advice = adviseInDrive(sit(
                    positionTrust: trust,
                    hasPosition: hasPos,
                    visibilityMeters: vis.meters,
                    visibilityAgeSeconds: age,
                    advisorySeverity: adv,
                    speedMetersPerSecond: speed,
                  ));
                  checked++;
                  if (advice.action != DriveAction.continueDriving) {
                    raised++;
                    expect(advice.reasons, isNotEmpty,
                        reason: '$trust/hasPos=$hasPos/vis=${vis.meters}/'
                            'age=$age/$adv/speed=$speed raised '
                            '${advice.action.name} with no reason');
                  }
                }
              }
            }
          }
        }
      }
      // Sanity: the sweep actually exercised both branches.
      expect(checked, 4 * 2 * 6 * 5 * 3 * 4);
      expect(raised, greaterThan(0));
    });

    test('founding case A: reduced visibility alone (700 m, trusted) ⇒ '
        'heightenedCaution WITH CautionReason.reducedVisibility', () {
      final a = adviseInDrive(sit(visibilityMeters: 700)); // trusted, no adv
      expect(a.action, DriveAction.heightenedCaution);
      expect(a.reasons, isNotEmpty);
      expect(a.reasons, contains(CautionReason.reducedVisibility));
      expect(a.reasons, isNot(contains(CautionReason.lowVisibility)));
    });

    test('founding case B: moderate advisory alone ⇒ heightenedCaution WITH '
        'CautionReason.moderateAdvisory', () {
      final a = adviseInDrive(sit(advisorySeverity: AdvisoryLevel.moderate));
      expect(a.action, DriveAction.heightenedCaution);
      expect(a.reasons, isNotEmpty);
      expect(a.reasons, contains(CautionReason.moderateAdvisory));
      expect(a.reasons, isNot(contains(CautionReason.severeAdvisory)));
    });

    test('mild/hard bands are mutually exclusive (never double-counted)', () {
      // Visibility: reduced XOR low, never both.
      final reduced = adviseInDrive(sit(visibilityMeters: 700));
      expect(
          reduced.reasons.contains(CautionReason.reducedVisibility) &&
              reduced.reasons.contains(CautionReason.lowVisibility),
          isFalse);
      final low = adviseInDrive(sit(visibilityMeters: 300));
      expect(low.reasons, contains(CautionReason.lowVisibility));
      expect(low.reasons, isNot(contains(CautionReason.reducedVisibility)));
      // Advisory: moderate XOR severe, never both.
      final sev = adviseInDrive(sit(advisorySeverity: AdvisoryLevel.severe));
      expect(sev.reasons, contains(CautionReason.severeAdvisory));
      expect(sev.reasons, isNot(contains(CautionReason.moderateAdvisory)));
    });
  });

  group('Obligation 2 — load-bearing compounding invariant', () {
    test('pc>=2 && vc>=2 ⇒ considerStopping && compounding (full sweep)', () {
      // pc>=2 trusts: degraded(2) and lost(3); also !hasPosition(3).
      // vc>=2 visibilities: low(2) and whiteout(3).
      final pcCases = <DriveSituation Function()>[
        () => sit(positionTrust: PositionTrust.degraded), // pc 2
        () => sit(positionTrust: PositionTrust.lost), // pc 3
        () => sit(hasPosition: false), // pc 3
      ];
      final vcMeters = <double>[300, 120]; // low, whiteout
      for (final base in pcCases) {
        for (final m in vcMeters) {
          for (final adv in [null, AdvisoryLevel.minor]) {
            final s0 = base();
            final s = DriveSituation(
              positionTrust: s0.positionTrust,
              confidenceRadiusMeters: s0.confidenceRadiusMeters,
              secondsSinceTrustedFix: s0.secondsSinceTrustedFix,
              hasPosition: s0.hasPosition,
              visibilityMeters: m,
              visibilityAgeSeconds: 10,
              advisorySeverity: adv,
              speedMetersPerSecond: 5,
            );
            final a = adviseInDrive(s);
            // hasPosition:false ⇒ position is "no dot", which the §3.5 model
            // still scores 3 and pairs with low vis; compounding requires pc>=2
            // which holds for all three pcCases.
            expect(a.compounding, isTrue,
                reason: '${s.positionTrust}/$m');
            expect(a.action, DriveAction.considerStopping,
                reason: '${s.positionTrust}/$m');
          }
        }
      }
    });
  });

  group('Obligation 3 — no false confidence', () {
    test('continueDriving requires trusted + known-adequate vis + adv<severe',
        () {
      // Reachable only in the all-clear case.
      final clear = adviseInDrive(sit());
      expect(clear.action, DriveAction.continueDriving);

      // Any single degradation drops it out of continueDriving.
      final droppers = <DriveSituation>[
        sit(positionTrust: PositionTrust.suspect),
        sit(positionTrust: PositionTrust.degraded),
        sit(positionTrust: PositionTrust.lost),
        sit(hasPosition: false),
        sit(visibilityMeters: 700), // reduced
        sit(visibilityMeters: 300), // low
        sit(visibilityMeters: null), // unknown
        sit(visibilityMeters: 700, visibilityAgeSeconds: 9999), // stale
        sit(advisorySeverity: AdvisoryLevel.moderate),
        sit(advisorySeverity: AdvisoryLevel.severe),
        sit(advisorySeverity: AdvisoryLevel.extreme),
      ];
      for (final s in droppers) {
        expect(adviseInDrive(s).action, isNot(DriveAction.continueDriving));
      }
    });

    test('no "safe"/"allClear"/"ok" token exists in the action vocabulary', () {
      final names = DriveAction.values.map((a) => a.name.toLowerCase()).toList();
      for (final banned in ['safe', 'allclear', 'ok', 'clear', 'good']) {
        expect(names.any((n) => n.contains(banned)), isFalse,
            reason: 'DriveAction must not contain "$banned"');
      }
      // continueDriving is the strongest positive — and it is "continue", not
      // an assertion of safety.
      expect(DriveAction.values, contains(DriveAction.continueDriving));
    });
  });

  group('Obligation 4 — unknown handling (held at level 1)', () {
    test('null visibility ⇒ not known, not low, no sight hint, level-1 floor',
        () {
      final a = adviseInDrive(sit(visibilityMeters: null));
      expect(a.visibilityKnown, isFalse);
      expect(a.visibilityLow, isFalse);
      expect(a.sightStoppingSpeedHintMps, isNull);
      expect(a.reasons, contains(CautionReason.unknownVisibility));
      expect(a.unknowns, contains(Unknown.noVisibilityReading));
      // Held level 1: with everything else clear, action is heightenedCaution
      // (not continueDriving=clear, not considerStopping=whiteout).
      expect(a.action, DriveAction.heightenedCaution);
    });

    test('stale visibility is treated as unknown, distinctly flagged', () {
      final a = adviseInDrive(
          sit(visibilityMeters: 700, visibilityAgeSeconds: 9999));
      expect(a.visibilityKnown, isFalse);
      expect(a.visibilityLow, isFalse);
      expect(a.sightStoppingSpeedHintMps, isNull);
      expect(a.reasons, contains(CautionReason.staleVisibility));
      expect(a.reasons, isNot(contains(CautionReason.unknownVisibility)));
      expect(a.unknowns, contains(Unknown.visibilityReadingIsStale));
      expect(a.action, DriveAction.heightenedCaution);
    });

    test('low-band visibility produces a grounded, conservative sight hint', () {
      final a = adviseInDrive(sit(visibilityMeters: 300)); // low band ⇒ emitted
      expect(a.visibilityKnown, isTrue);
      expect(a.visibilityLow, isTrue);
      expect(a.sightStoppingSpeedHintMps, isNotNull);
      // Conservative and FAITHFUL: floored, >= 0, never above the winter
      // ceiling (a speed-vs-speed bound, not the old vis-metres unit mismatch).
      expect(a.sightStoppingSpeedHintMps! >= 0, isTrue);
      expect(a.sightStoppingSpeedHintMps! <= kSightHintCeilingMps, isTrue);
      // ~50 km/h, NOT the ~112 km/h the old packed-snow geometry produced.
      expect(a.sightStoppingSpeedHintMps! <= 14, isTrue);
      expect(a.sightStoppingSpeedHintMps,
          a.sightStoppingSpeedHintMps!.floorToDouble());
    });
  });

  group('Obligation 5 — non-deterrence is structural', () {
    test('exactly three actions, none denote abort/turn-back/do-not-drive', () {
      expect(DriveAction.values.length, 3);
      final names = DriveAction.values.map((a) => a.name.toLowerCase());
      for (final banned in [
        'abort',
        'turnback',
        'turnaround',
        'donotdrive',
        'dontdrive',
        'stopnow',
        'pullover',
        'cancel',
        'return',
      ]) {
        expect(names.any((n) => n.contains(banned)), isFalse,
            reason: 'must not contain "$banned"');
      }
      // The ceiling is an invitation, not a command.
      expect(DriveAction.values.last, DriveAction.considerStopping);
    });

    test('worst possible input still only reaches considerStopping', () {
      final apocalypse = adviseInDrive(sit(
        positionTrust: PositionTrust.lost,
        hasPosition: false,
        visibilityMeters: 5,
        advisorySeverity: AdvisoryLevel.extreme,
        speedMetersPerSecond: 40,
      ));
      expect(apocalypse.action, DriveAction.considerStopping);
    });

    test('output carries no route/destination/safe field (shape audit)', () {
      // The DriveAdvice surface is enums + flags + numbers only — there is no
      // field that names a destination, a route, or "safe". This is a
      // compile-time guarantee; we assert the few numeric/flag fields exist and
      // that the action set has no journey verb (covered above).
      final a = adviseInDrive(sit());
      expect(a.sightStoppingSpeedHintMps, anyOf(isNull, isA<double>()));
      expect(a.compounding, isA<bool>());
    });
  });

  group('Obligation 6 — robustness (degrades, never throws)', () {
    test('NaN / negative radius on degraded ⇒ worst tier, no throw', () {
      for (final r in [double.nan, -50.0]) {
        final a = adviseInDrive(sit(
          positionTrust: PositionTrust.degraded,
          confidenceRadiusMeters: r,
          visibilityMeters: 300, // low → vc 2
        ));
        // pc bumped to 3 by bad radius, vc 2 ⇒ compounding ⇒ ceiling.
        expect(a.action, DriveAction.considerStopping);
        expect(a.compounding, isTrue);
      }
    });

    test('infinity / NaN secondsSinceTrustedFix ⇒ stale, recorded', () {
      for (final t in [double.infinity, double.nan]) {
        final a = adviseInDrive(sit(
          positionTrust: PositionTrust.degraded,
          confidenceRadiusMeters: 20, // small radius
          secondsSinceTrustedFix: t,
        ));
        // Long-blind bumps pc to 3.
        expect(a.unknowns, contains(Unknown.noTrustedGpsForAWhile));
        expect(a.action, isNot(DriveAction.continueDriving));
      }
    });

    test('NaN visibility meters ⇒ treated as unknown (not whiteout)', () {
      final a = adviseInDrive(sit(visibilityMeters: double.nan));
      expect(a.visibilityKnown, isFalse);
      expect(a.visibilityLow, isFalse);
      expect(a.reasons, contains(CautionReason.unknownVisibility));
      expect(a.sightStoppingSpeedHintMps, isNull);
    });

    test('negative visibility ⇒ conservative whiteout band', () {
      final a = adviseInDrive(sit(visibilityMeters: -10));
      expect(a.visibilityKnown, isTrue);
      expect(a.visibilityLow, isTrue);
      // Hint clamps to >= 0 even on a nonsensical reading.
      expect(a.sightStoppingSpeedHintMps, 0);
    });

    test('null speed ⇒ Unknown.speedUnknown, caution not withheld', () {
      final a = adviseInDrive(sit(
        positionTrust: PositionTrust.degraded,
        visibilityMeters: 300,
        speedMetersPerSecond: null,
      ));
      expect(a.unknowns, contains(Unknown.speedUnknown));
      expect(a.action, DriveAction.considerStopping); // compounding still fires
    });

    test('NaN speed ⇒ Unknown.speedUnknown, never fast', () {
      final a = adviseInDrive(sit(
        positionTrust: PositionTrust.degraded,
        visibilityMeters: 700, // reduced, corePair 2
        speedMetersPerSecond: double.nan,
      ));
      expect(a.unknowns, contains(Unknown.speedUnknown));
      expect(a.reasons,
          isNot(contains(CautionReason.highSpeedInDegradedConditions)));
    });
  });

  group('Obligation 7 — monotonicity (caution-add-only)', () {
    test('worsening position never lowers the action', () {
      DriveAction act(PositionTrust t) =>
          adviseInDrive(sit(positionTrust: t, visibilityMeters: 700)).action;
      final order = [
        act(PositionTrust.trusted),
        act(PositionTrust.suspect),
        act(PositionTrust.degraded),
        act(PositionTrust.lost),
      ];
      for (var i = 1; i < order.length; i++) {
        expect(order[i].index >= order[i - 1].index, isTrue,
            reason: 'position step $i lowered caution');
      }
    });

    test('worsening visibility never lowers the action', () {
      DriveAction act(double m) =>
          adviseInDrive(sit(positionTrust: PositionTrust.suspect, visibilityMeters: m))
              .action;
      final order = [act(1500), act(700), act(300), act(120)];
      for (var i = 1; i < order.length; i++) {
        expect(order[i].index >= order[i - 1].index, isTrue,
            reason: 'visibility step $i lowered caution');
      }
    });

    test('worsening advisory never lowers the action', () {
      DriveAction act(AdvisoryLevel? a) => adviseInDrive(
              sit(positionTrust: PositionTrust.suspect, advisorySeverity: a))
          .action;
      final order = [
        act(null),
        act(AdvisoryLevel.minor),
        act(AdvisoryLevel.moderate),
        act(AdvisoryLevel.severe),
        act(AdvisoryLevel.extreme),
      ];
      for (var i = 1; i < order.length; i++) {
        expect(order[i].index >= order[i - 1].index, isTrue,
            reason: 'advisory step $i lowered caution');
      }
    });
  });

  group('compounding semantics', () {
    test('a single worst axis reaches the ceiling WITHOUT compounding', () {
      // Lost position, clear visibility: ceiling but not compounding.
      final lost = adviseInDrive(sit(positionTrust: PositionTrust.lost));
      expect(lost.action, DriveAction.considerStopping);
      expect(lost.compounding, isFalse);

      // Whiteout visibility, trusted position: ceiling but not compounding.
      final white = adviseInDrive(sit(visibilityMeters: 50));
      expect(white.action, DriveAction.considerStopping);
      expect(white.compounding, isFalse);

      // Extreme advisory alone: ceiling, not compounding.
      final ext = adviseInDrive(sit(advisorySeverity: AdvisoryLevel.extreme));
      expect(ext.action, DriveAction.considerStopping);
      expect(ext.compounding, isFalse);
    });

    test('an escalator alone (severe advisory) never reaches the ceiling', () {
      // severe (ac 2) with everything else clear: +1 escalation only ⇒
      // heightenedCaution, not considerStopping.
      final a = adviseInDrive(sit(advisorySeverity: AdvisoryLevel.severe));
      expect(a.action, DriveAction.heightenedCaution);
    });

    test('fast escalator alone never reaches the ceiling', () {
      // suspect(1) + reduced(1) = corePair 1; fast adds +1 ⇒ score 2 ⇒
      // heightenedCaution, never considerStopping.
      final a = adviseInDrive(sit(
        positionTrust: PositionTrust.suspect,
        visibilityMeters: 700,
        speedMetersPerSecond: 30,
      ));
      expect(a.action, DriveAction.heightenedCaution);
      expect(a.reasons, contains(CautionReason.highSpeedInDegradedConditions));
    });
  });

  group('Hardening — sight-stopping hint (OPS-068 review)', () {
    test('hint is suppressed in the clear and reduced bands', () {
      for (final m in <double>[1500, 1000, 999, 700, 500]) {
        expect(adviseInDrive(sit(visibilityMeters: m)).sightStoppingSpeedHintMps,
            isNull,
            reason: 'vis=$m should not surface a sight hint');
      }
    });

    test('hint is emitted only in the low/whiteout band, sane on ice', () {
      final low = adviseInDrive(sit(visibilityMeters: 300));
      expect(low.visibilityLow, isTrue);
      expect(low.sightStoppingSpeedHintMps, isNotNull);
      expect(low.sightStoppingSpeedHintMps! <= kSightHintCeilingMps, isTrue);
      // A 300 m low-vis reading on ice must NOT imply a highway speed.
      expect(low.sightStoppingSpeedHintMps! <= 14, isTrue);
      final white = adviseInDrive(sit(visibilityMeters: 120));
      expect(white.sightStoppingSpeedHintMps,
          lessThan(low.sightStoppingSpeedHintMps!));
    });

    test('hint never exceeds the winter ceiling anywhere in the emit band', () {
      for (double m = 1; m < 500; m += 7) {
        final h = adviseInDrive(sit(visibilityMeters: m)).sightStoppingSpeedHintMps;
        if (h != null) {
          expect(h <= kSightHintCeilingMps, isTrue, reason: 'vis=$m hint=$h');
          expect(h >= 0, isTrue, reason: 'vis=$m hint=$h');
        }
      }
    });

    test('calibration constants are fail-toward-slower (worst-credible ice)', () {
      // Grip assumption is glare-ice, not packed-snow; reaction time is a
      // winter see-then-react figure. Both caution-add-only.
      expect(kWinterDecelMps2 <= 1.0, isTrue);
      expect(kReactionTimeSeconds >= 2.0, isTrue);
      expect(kSightHintCeilingMps <= kFastForConditionsMps, isTrue);
    });
  });

  group('Hardening — visibility freshness (null/NaN/edge age)', () {
    test('a real reading with NULL age is NOT trusted as fresh (held level-1)',
        () {
      final a = adviseInDrive(
          sit(visibilityMeters: 1500, visibilityAgeSeconds: null));
      expect(a.visibilityKnown, isFalse);
      expect(a.visibilityLow, isFalse);
      expect(a.sightStoppingSpeedHintMps, isNull);
      expect(a.reasons, contains(CautionReason.staleVisibility));
      expect(a.unknowns, contains(Unknown.visibilityReadingIsStale));
      // Held level-1 floor: not cleared to continueDriving, not over-warned.
      expect(a.action, DriveAction.heightenedCaution);
    });

    test('a low-band reading with null age emits no grounded hint', () {
      final a =
          adviseInDrive(sit(visibilityMeters: 120, visibilityAgeSeconds: null));
      expect(a.visibilityKnown, isFalse);
      expect(a.sightStoppingSpeedHintMps, isNull);
    });

    test('NaN age is held identically to null age (parity)', () {
      final a = adviseInDrive(
          sit(visibilityMeters: 1500, visibilityAgeSeconds: double.nan));
      expect(a.visibilityKnown, isFalse);
      expect(a.action, DriveAction.heightenedCaution);
    });

    test('zero / negative (recent) age is in-window ⇒ known/fresh', () {
      expect(
          adviseInDrive(sit(visibilityMeters: 1500, visibilityAgeSeconds: 0))
              .visibilityKnown,
          isTrue);
      expect(
          adviseInDrive(sit(visibilityMeters: 1500, visibilityAgeSeconds: -5))
              .visibilityKnown,
          isTrue);
    });
  });

  group('Hardening — suspect position tracks radius & staleness', () {
    test('a neighbourhood-scale suspect radius bumps concern 1 → 2', () {
      final big = adviseInDrive(sit(
        positionTrust: PositionTrust.suspect,
        confidenceRadiusMeters: 1000,
        visibilityMeters: 300, // low ⇒ vc2
      ));
      expect(big.compounding, isTrue); // pc2 & vc2 now stack
      expect(big.action, DriveAction.considerStopping);
    });

    test('a long-blind (stale) suspect fix bumps concern 1 → 2', () {
      final stale = adviseInDrive(sit(
        positionTrust: PositionTrust.suspect,
        confidenceRadiusMeters: 20,
        secondsSinceTrustedFix: double.infinity,
        visibilityMeters: 300,
      ));
      expect(stale.compounding, isTrue);
      expect(stale.action, DriveAction.considerStopping);
    });

    test('a small, fresh suspect fix stays at concern 1', () {
      final small = adviseInDrive(sit(
        positionTrust: PositionTrust.suspect,
        confidenceRadiusMeters: 20,
        visibilityMeters: 300, // low ⇒ vc2
      ));
      expect(small.compounding, isFalse); // pc1, so no stacking
      expect(small.action, DriveAction.heightenedCaution);
    });
  });

  group('Hardening — documented limitations are stable', () {
    test('degraded position + UNKNOWN visibility does not set compounding', () {
      final a = adviseInDrive(sit(
        positionTrust: PositionTrust.degraded,
        confidenceRadiusMeters: 20, // small + fresh ⇒ pc2 (not 3)
        visibilityMeters: null, // unknown ⇒ vc1
      ));
      expect(a.compounding, isFalse); // won't assert a visibility we can't see
      expect(a.visibilityKnown, isFalse);
      expect(a.action, DriveAction.heightenedCaution); // corePair 2, both surfaced
      expect(a.reasons, contains(CautionReason.positionUncertain));
      expect(a.reasons, contains(CautionReason.unknownVisibility));
    });

    test('suspect + known whiteout reaches ceiling via vis axis; not compounding',
        () {
      final a = adviseInDrive(sit(
        positionTrust: PositionTrust.suspect,
        confidenceRadiusMeters: 20, // small/fresh ⇒ pc1
        visibilityMeters: 50, // whiteout ⇒ vc3
      ));
      expect(a.action, DriveAction.considerStopping);
      expect(a.compounding, isFalse); // exact meaning of the flag, not a miss
    });

    test('clear-air black-ice (no advisory) returns continueDriving — grip is unsensed',
        () {
      // Documents the scope boundary: grip reaches the model ONLY via advisory.
      final a = adviseInDrive(sit()); // trusted, clear, slow, no advisory
      expect(a.action, DriveAction.continueDriving);
      // Feeding a severe winter advisory IS the supported path to surface grip.
      final withAdvisory =
          adviseInDrive(sit(advisorySeverity: AdvisoryLevel.severe));
      expect(withAdvisory.action, isNot(DriveAction.continueDriving));
    });
  });

  group('Hardening — band-boundary monotonicity (relaxing-tweak guard)', () {
    test('caution is non-decreasing across each visibility threshold edge', () {
      DriveAction act(double m) => adviseInDrive(sit(
            positionTrust: PositionTrust.suspect,
            confidenceRadiusMeters: 20,
            visibilityMeters: m,
          )).action;
      // Just above / just below each k* visibility threshold.
      final samples = <double>[1500, 1000, 999, 500, 499, 200, 199, 50, 1];
      for (var i = 1; i < samples.length; i++) {
        expect(act(samples[i]).index >= act(samples[i - 1]).index, isTrue,
            reason: 'vis ${samples[i - 1]}→${samples[i]} lowered caution');
      }
    });
  });

  group('determinism + immutability', () {
    test('same input ⇒ identical output', () {
      final s = sit(positionTrust: PositionTrust.degraded, visibilityMeters: 300);
      final a = adviseInDrive(s);
      final b = adviseInDrive(s);
      expect(a.toString(), b.toString());
    });

    test('reasons and unknowns are unmodifiable', () {
      final a = adviseInDrive(sit(visibilityMeters: null));
      expect(() => a.reasons.add(CautionReason.lowVisibility),
          throwsUnsupportedError);
      expect(() => a.unknowns.add(Unknown.speedUnknown),
          throwsUnsupportedError);
    });
  });
}
