/// The composed path: black ice under a clear sky, as the simulator computes it.
///
/// [SimulatedSafetyScore] is where `overall` is actually COMPOSED
/// (`0.5 * grip + 0.5 * visibility`), and it carried its own copy of the
/// three threshold comparisons. A copy is how two decisions that must agree
/// drift apart: `navigation_safety_core` gained a per-axis critical floor and
/// this path did not inherit it, so the very type that builds the mean kept
/// returning `info` for zero grip under clear air.
library;

import 'package:driving_conditions/driving_conditions.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('the composed path reaches critical on a single lethal axis', () {
    test('zero grip + perfect visibility is critical, not info', () {
      final config = NavigationSafetyConfig();
      final score = SimulatedSafetyScore(gripScore: 0.0, visibilityScore: 1.0);

      // The mean is unchanged and still means what it says.
      expect(score.overall, 0.5);
      // The verdict is not the mean's alone.
      expect(score.toAlertSeverity(config), AlertSeverity.critical);
    });

    test('agrees with navigation_safety_core on the same numbers', () {
      final config = NavigationSafetyConfig();
      const n = 41;
      for (var i = 0; i < n; i++) {
        for (var j = 0; j < n; j++) {
          final grip = i / (n - 1);
          final visibility = j / (n - 1);
          final simulated = SimulatedSafetyScore(
            gripScore: grip,
            visibilityScore: visibility,
          );
          final core = SafetyScore(
            overall: simulated.overall,
            gripScore: grip,
            visibilityScore: visibility,
            fleetConfidenceScore: 1.0,
          );
          expect(
            simulated.toAlertSeverity(config),
            core.toAlertSeverity(config),
            reason:
                'grip=$grip visibility=$visibility: the two severity paths '
                'must not be able to disagree',
          );
        }
      }
    });
  });

  group('the reverse control: ordinary conditions are not promoted', () {
    test('a good road stays silent', () {
      expect(
        SimulatedSafetyScore(
          gripScore: 0.90,
          visibilityScore: 0.90,
        ).toAlertSeverity(NavigationSafetyConfig()),
        isNull,
      );
    });

    test('compacted snow under clear air is not critical on grip alone', () {
      // 3.0 / 5.5 m/s^2 braking ratio — a winter road, not glare ice.
      expect(
        SimulatedSafetyScore(
          gripScore: 3.0 / 5.5,
          visibilityScore: 1.0,
        ).toAlertSeverity(NavigationSafetyConfig()),
        AlertSeverity.info,
      );
    });
  });
}
