import 'package:navigation_safety_enums/navigation_safety_enums.dart';
import 'package:test/test.dart';

void main() {
  group('HapticCuePattern', () {
    test('cardinality is 3', () {
      expect(HapticCuePattern.values.length, 3);
    });

    test('declaration order parallels AlertSeverity severity ranking', () {
      // Load-bearing: none < warning < critical, mirroring
      // info < warning < critical on AlertSeverity.
      expect(HapticCuePattern.values, <HapticCuePattern>[
        HapticCuePattern.none,
        HapticCuePattern.warning,
        HapticCuePattern.critical,
      ]);
    });

    test('pulseCount grammar distinguishes the two announced tiers', () {
      // The grammar must DISTINGUISH severity: a single undifferentiated
      // buzz is worse than honest. Warning and critical have different,
      // non-zero pulse counts; none has zero.
      expect(HapticCuePattern.none.pulseCount, 0);
      expect(HapticCuePattern.warning.pulseCount, 2);
      expect(HapticCuePattern.critical.pulseCount, 3);
      // The two announced tiers are distinguishable by count.
      expect(
        HapticCuePattern.warning.pulseCount,
        isNot(HapticCuePattern.critical.pulseCount),
      );
    });

    test('isTactile is true exactly for the announced (non-none) cues', () {
      expect(HapticCuePattern.none.isTactile, isFalse);
      expect(HapticCuePattern.warning.isTactile, isTrue);
      expect(HapticCuePattern.critical.isTactile, isTrue);
    });
  });

  group('hapticCueForSeverity — severity-coupling lock', () {
    test('maps each severity to its corresponding cue', () {
      expect(hapticCueForSeverity(AlertSeverity.info), HapticCuePattern.none);
      expect(
        hapticCueForSeverity(AlertSeverity.warning),
        HapticCuePattern.warning,
      );
      expect(
        hapticCueForSeverity(AlertSeverity.critical),
        HapticCuePattern.critical,
      );
    });

    test(
      'deaf-cue SET == hearing-warning SET (set-parity, off the same gate)',
      () {
        // The audio channel announces a hazard iff
        // severity.index >= AlertSeverity.warning.index.
        final hearingWarningSeverities = AlertSeverity.values
            .where((s) => s.index >= AlertSeverity.warning.index)
            .toSet();

        // The deaf channel produces a TACTILE cue for exactly the same set.
        final deafTactileSeverities = AlertSeverity.values
            .where((s) => hapticCueForSeverity(s).isTactile)
            .toSet();

        expect(
          deafTactileSeverities,
          equals(hearingWarningSeverities),
          reason: 'deaf cue set must equal hearing warning set — no '
              'reduced subset that silently drops warnings for the '
              'driver who can least afford to miss them',
        );
        expect(
          hearingWarningSeverities,
          equals(<AlertSeverity>{
            AlertSeverity.warning,
            AlertSeverity.critical,
          }),
        );

        // And within that set the two tiers are DISTINCT cues so a deaf
        // driver can tell "reduce speed" from "consider turning back".
        final cues = deafTactileSeverities
            .map(hapticCueForSeverity)
            .toSet();
        expect(cues.length, deafTactileSeverities.length);
      },
    );

    test('is a pure function of severity only (no profile parameter)', () {
      // Calling twice with the same severity yields the same cue; the
      // function signature takes no DriverProfile by construction.
      for (final s in AlertSeverity.values) {
        expect(hapticCueForSeverity(s), hapticCueForSeverity(s));
      }
    });
  });
}
