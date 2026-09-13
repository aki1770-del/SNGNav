// AlertDensityThrottle must refuse a NaN cap at construction.
//
// FAILS against navigation_safety_core 0.11.6 (git f626d93). The
// constructor guard is `alertsPerMinuteCap <= 0`, which is false for NaN,
// so a NaN cap constructs. `shouldFire` then evaluates
// `_firedAt.length < alertsPerMinuteCap`, which is false for every length
// when the cap is NaN: after a cold-start alert, every info and warning
// alert is dropped until the rolling window empties, the same decisions as a
// cap of 1.0 whatever the driver's designed cap, and nothing reports it
// (measured: four warnings ten seconds apart fire [true, false, false, false];
// warnings every 10 s for 180 s fire at 0, 60, 120 and 180 s). Zero and
// negative caps are already refused with ArgumentError
// (alert_density_throttle_test.dart); NaN should meet the same guard, written
// as a negation so NaN cannot pass it.
//
// A throttle is built once per profile or session, not per frame (a fresh
// instance resets its rolling window), so this throw lands where the
// existing zero-cap throw already lands.

import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  test('a NaN alertsPerMinuteCap throws ArgumentError at construction', () {
    expect(
      () => AlertDensityThrottle(alertsPerMinuteCap: double.nan),
      throwsArgumentError,
    );
  });
}
