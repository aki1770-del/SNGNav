/// An absent ambient temperature must not be answered with a temperature.
///
/// `NavigationSafetyConfig.forProfileWithContext` raises the warning
/// visibility by a residual-moisture margin when
/// `DrivingContext.timeSincePrecipitation` is set. Through 0.11.3 that
/// branch read an absent `ambientTempCelsius` as `5.0` before handing it to
/// `computeSurfaceMoistureFraction`, while the black-ice branch seventeen
/// lines below refused to proceed at all without the same field. One
/// function, two opposite treatments of one missing input.
///
/// These tests lock the property that makes the residual-moisture branch
/// honest without changing a single number a consumer sees today:
///
///  1. the surface-moisture calibration ignores `ambientCelsius`, so an
///     absent ambient costs the driver nothing and no temperature needs to
///     be invented (`the calibration contract` group);
///  2. while that holds, the margin applies exactly as it did in 0.11.3
///     (`0.11.3 parity` group);
///  3. the day it stops holding, the branch withholds the add-on and the
///     per-profile baseline stands, rather than deriving a driver-facing
///     threshold from a temperature nobody read (`absent ambient` group).
///
/// **Honest bound, stated so it is not mistaken for more than it is.**
/// Because the calibration ignores `ambientCelsius` today, no test here can
/// distinguish *which* double the old code passed: `5.0` and `-273.15`
/// produce identical output, and so does not passing one at all. What is
/// locked is the stronger and more useful property — that no value this
/// package invents for ambient can reach a threshold, and that the day one
/// could, this suite fails first. The alarm rings in OUR suite, where the
/// package author can act on it; the behaviour stays safe in the
/// consumer's, who cannot.
library;

// `computeSurfaceMoistureFraction` reaches this file through the
// navigation_safety_core barrel, which re-exports navigation_safety_calibration
// as the family's single source of truth (0.11.0).
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

/// Ambient temperatures spanning the range a road vehicle meets, plus the
/// mild value 0.11.3 invented when it had none.
const _ambientSweepCelsius = <double>[
  -40.0,
  -20.0,
  -10.0,
  -1.0,
  0.0,
  5.0, // the value 0.11.3 substituted for an absent reading
  20.0,
  40.0,
];

/// Elapsed times either side of the 90-minute default half-life, including
/// the boundaries where the margin is largest and smallest.
const _elapsed = <Duration>[
  Duration.zero,
  Duration(minutes: 1),
  Duration(minutes: 30),
  Duration(minutes: 90),
  Duration(minutes: 180),
  Duration(hours: 24),
];

/// The moisture fraction if and only if it does not depend on ambient.
///
/// Recomputed here from the sweep rather than imported from the package,
/// so the test measures the calibration independently of the private
/// probe list the implementation uses. A mutation that shrinks that list
/// to a single probe is therefore visible to these tests.
double? _fractionIfAmbientIndependent(Duration elapsed) {
  final seen = <double>{
    for (final c in _ambientSweepCelsius)
      computeSurfaceMoistureFraction(
        timeSincePrecipitation: elapsed,
        ambientCelsius: c,
      ),
  };
  return seen.length == 1 ? seen.single : null;
}

/// The residual-moisture visibility exactly as 0.11.3 computed it.
int _visibility0113({
  required DriverProfile profile,
  required Duration elapsed,
  required double? ambient,
}) {
  final base = NavigationSafetyConfig.forProfile(profile);
  final fraction = computeSurfaceMoistureFraction(
    timeSincePrecipitation: elapsed,
    ambientCelsius: ambient ?? 5.0, // the 0.11.3 substitution
  );
  final margin = (base.warningVisibilityMeters * fraction).round();
  final candidate = base.warningVisibilityMeters + margin;
  return candidate > base.warningVisibilityMeters
      ? candidate
      : base.warningVisibilityMeters;
}

void main() {
  group('the calibration contract this branch rests on', () {
    test('computeSurfaceMoistureFraction ignores ambientCelsius — if this '
        'fails, the residual-moisture branch must be rewritten to express '
        '"not measured" rather than to fill it in', () {
      for (final elapsed in _elapsed) {
        final byAmbient = <double, double>{
          for (final c in _ambientSweepCelsius)
            c: computeSurfaceMoistureFraction(
              timeSincePrecipitation: elapsed,
              ambientCelsius: c,
            ),
        };
        expect(
          byAmbient.values.toSet(),
          hasLength(1),
          reason:
              'after $elapsed the surface-moisture fraction differs by '
              'ambient temperature: $byAmbient. ambientCelsius has become '
              'load-bearing, so navigation_safety_core can no longer '
              'compute this margin without a measured ambient. Rewrite '
              'NavigationSafetyConfig._residualMoistureFractionOrNull; do '
              'not widen the probe list to make this pass.',
        );
      }
    });
  });

  group('absent ambient is never invented', () {
    test('no residual-moisture margin is ever derived from a temperature '
        'nobody measured', () {
      for (final profile in DriverProfile.values) {
        final base = NavigationSafetyConfig.forProfile(profile);
        for (final elapsed in _elapsed) {
          final config = NavigationSafetyConfig.forProfileWithContext(
            profile,
            context: DrivingContext(timeSincePrecipitation: elapsed),
          );
          final independent = _fractionIfAmbientIndependent(elapsed);

          if (independent == null) {
            // The calibration reads ambient and we have none, so this
            // release answers with the per-profile baseline.
            //
            // The baseline is the honest INPUT, not the honest ANSWER, and
            // this assertion must not be read as claiming otherwise.
            // Measured against a calibration whose half-life lengthens in
            // the cold: 30 minutes after rain, ageingRural's honest floor
            // at a true −5 °C is 560 m; 0.11.3's invented 5.0 reached
            // 554 m; the baseline asserted here is 300 m. Withholding is
            // 260 m short — further from the truth than the fabrication it
            // replaced. That cost is deliberate and it is documented in
            // the 0.11.4 CHANGELOG, together with the alternative that was
            // considered (take the most adverse probe) and why it is an
            // open API question rather than a silent behaviour change.
            //
            // What this test locks is the narrow, defensible property: no
            // driver-facing threshold is derived from a temperature nobody
            // measured. It does NOT lock that the baseline is correct.
            expect(
              config.warningVisibilityMeters,
              base.warningVisibilityMeters,
              reason:
                  'ambient was not measured and the surface-moisture '
                  'fraction now depends on it, so no margin may be '
                  'applied for $profile after $elapsed. Getting anything '
                  'other than the baseline here means a threshold was '
                  'derived from an invented temperature.',
            );
          } else {
            // The absence costs nothing: the answer is the same at every
            // temperature, so it is not really a temperature answer.
            final margin = (base.warningVisibilityMeters * independent).round();
            final expected = base.warningVisibilityMeters + margin;
            expect(
              config.warningVisibilityMeters,
              expected > base.warningVisibilityMeters
                  ? expected
                  : base.warningVisibilityMeters,
              reason:
                  'the fraction is identical at every ambient temperature '
                  'after $elapsed, so an absent ambient must cost $profile '
                  'nothing',
            );
          }
        }
      }
    });

    test('an absent ambient still leaves the warning temperature at the '
        'per-profile baseline — the black-ice branch never invented one, and '
        'both branches now agree', () {
      for (final profile in DriverProfile.values) {
        final base = NavigationSafetyConfig.forProfile(profile);
        for (final elapsed in _elapsed) {
          final config = NavigationSafetyConfig.forProfileWithContext(
            profile,
            // humidity present, ambient absent: the black-ice branch has
            // always refused to proceed here.
            context: DrivingContext(
              humidityRH: 0.95,
              timeSincePrecipitation: elapsed,
            ),
          );
          expect(
            config.warningTemperatureCelsius,
            base.warningTemperatureCelsius,
            reason: 'no ambient was measured for $profile',
          );
        }
      }
    });

    test('the per-profile visibility floor is never lowered', () {
      for (final profile in DriverProfile.values) {
        final base = NavigationSafetyConfig.forProfile(profile);
        for (final elapsed in _elapsed) {
          final config = NavigationSafetyConfig.forProfileWithContext(
            profile,
            context: DrivingContext(timeSincePrecipitation: elapsed),
          );
          expect(
            config.warningVisibilityMeters,
            greaterThanOrEqualTo(base.warningVisibilityMeters),
            reason:
                'caution-add-only: withholding the add-on must leave the '
                'baseline, never reduce it ($profile, $elapsed)',
          );
        }
      }
    });
  });

  group('0.11.3 parity — no consumer number changes', () {
    test('while the calibration ignores ambient, every result is identical to '
        '0.11.3, ambient present or absent', () {
      for (final elapsed in _elapsed) {
        if (_fractionIfAmbientIndependent(elapsed) == null) {
          // Behaviour is intended to diverge from 0.11.3 exactly here;
          // the divergence is asserted in the group above.
          continue;
        }
        for (final profile in DriverProfile.values) {
          for (final ambient in <double?>[null, ..._ambientSweepCelsius]) {
            final config = NavigationSafetyConfig.forProfileWithContext(
              profile,
              context: DrivingContext(
                timeSincePrecipitation: elapsed,
                ambientTempCelsius: ambient,
              ),
            );
            expect(
              config.warningVisibilityMeters,
              _visibility0113(
                profile: profile,
                elapsed: elapsed,
                ambient: ambient,
              ),
              reason:
                  'the 0.11.4 residual-moisture margin must match 0.11.3 '
                  'exactly for $profile after $elapsed at ambient=$ambient',
            );
          }
        }
      }
    });

    test('a measured ambient is still used, and used unchanged', () {
      for (final profile in DriverProfile.values) {
        final base = NavigationSafetyConfig.forProfile(profile);
        for (final elapsed in _elapsed) {
          for (final ambient in _ambientSweepCelsius) {
            final config = NavigationSafetyConfig.forProfileWithContext(
              profile,
              context: DrivingContext(
                timeSincePrecipitation: elapsed,
                ambientTempCelsius: ambient,
              ),
            );
            final fraction = computeSurfaceMoistureFraction(
              timeSincePrecipitation: elapsed,
              ambientCelsius: ambient,
            );
            final margin = (base.warningVisibilityMeters * fraction).round();
            final expected = base.warningVisibilityMeters + margin;
            expect(
              config.warningVisibilityMeters,
              expected > base.warningVisibilityMeters
                  ? expected
                  : base.warningVisibilityMeters,
              reason:
                  'a measured ambient must reach the calibration untouched '
                  '($profile, $elapsed, ambient=$ambient)',
            );
          }
        }
      }
    });
  });
}
