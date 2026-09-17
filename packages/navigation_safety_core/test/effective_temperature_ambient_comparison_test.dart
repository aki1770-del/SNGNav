// Inside the calibration's own radiative-frost black-ice classification, a
// consumer comparing AMBIENT with the returned warning temperature must get
// "warn". Outside it, the 0.11.7 answer is unchanged.
//
// The classification is navigation_safety_calibration's single source of
// truth (isRadiativeFrostBlackIce: ambient <= 3.0 C and dew point <= 0 C).
// Its 3.0 C ceiling is that package's recorded decision and is not moved.
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

/// The 0.11.7 warning temperature, re-stated as a characterization.
int oldWarning(DriverProfile p, double t, double rh) {
  final b = NavigationSafetyConfig.forProfile(p).warningTemperatureCelsius;
  final eff =
      computeEffectiveTemperatureCelsius(ambientCelsius: t, humidityRH: rh);
  if (eff <= b.toDouble()) {
    return b + (b - eff.floor()).clamp(0, 10).toInt();
  }
  return b;
}

void main() {
  test('3.0 C at 70 % RH, snowZoneExperienced: ambient meets the threshold',
      () {
    final c = NavigationSafetyConfig.forProfileWithContext(
      DriverProfile.snowZoneExperienced,
      context: const DrivingContext(ambientTempCelsius: 3.0, humidityRH: 0.70),
    );
    expect(3.0 <= c.warningTemperatureCelsius, isTrue,
        reason: 'returned ${c.warningTemperatureCelsius}');
  });

  test(
      'grid: frost-classified => ambient <= warning; otherwise unchanged; '
      'never below 0.11.7; never above baseline + 10', () {
    var frostCells = 0;
    var otherCells = 0;
    var misses = 0;
    for (final p in DriverProfile.values) {
      final b = NavigationSafetyConfig.forProfile(p).warningTemperatureCelsius;
      for (var ti = -100; ti <= 60; ti++) {
        final t = ti / 10.0;
        for (var hi = 5; hi <= 100; hi++) {
          final rh = hi / 100.0;
          final frost = isRadiativeFrostBlackIce(
              ambientCelsius: t, humidityRHPercent: hi.toDouble());
          for (final speed in <double?>[null, 22.22]) {
            final w = NavigationSafetyConfig.forProfileWithContext(
              p,
              context: DrivingContext(
                  ambientTempCelsius: t, humidityRH: rh, speedMps: speed),
            ).warningTemperatureCelsius;
            final old = oldWarning(p, t, rh);
            expect(w, greaterThanOrEqualTo(old), reason: '$p $t $hi');
            expect(w, lessThanOrEqualTo(b + 10), reason: '$p $t $hi');
            if (frost) {
              frostCells++;
              if (t > w) misses++;
            } else {
              otherCells++;
              expect(w, old, reason: 'non-frost cell moved: $p $t $hi');
            }
          }
        }
      }
    }
    expect(frostCells, 147000);
    expect(otherCells, 6 * 161 * 96 * 2 - 147000);
    expect(misses, 0, reason: 'frost-classified cells where ambient > warning');
  });

  test('forDriverContext: frost-classified ambient still meets the threshold',
      () {
    for (final s in DriverState.values) {
      final c = NavigationSafetyConfig.forDriverContext(
        DriverContext(profile: DriverProfile.professional, state: s),
        environmentalContext:
            const DrivingContext(ambientTempCelsius: 3.0, humidityRH: 0.70),
      );
      expect(3.0 <= c.warningTemperatureCelsius, isTrue, reason: '$s');
    }
  });

  test('dry summer afternoon (20 C, 25 % RH) is not raised to ambient', () {
    final c = NavigationSafetyConfig.forProfileWithContext(
      DriverProfile.snowZoneExperienced,
      context: const DrivingContext(ambientTempCelsius: 20.0, humidityRH: 0.25),
    );
    expect(c.warningTemperatureCelsius,
        oldWarning(DriverProfile.snowZoneExperienced, 20.0, 0.25));
    expect(c.warningTemperatureCelsius, lessThan(20));
  });
}
