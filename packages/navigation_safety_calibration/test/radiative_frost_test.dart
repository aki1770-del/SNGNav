import 'package:navigation_safety_calibration/navigation_safety_calibration.dart';
import 'package:test/test.dart';

/// Spec for [isRadiativeFrostBlackIce] — the single source of truth both the
/// pre-trip advisor and the in-drive road-surface classifier call so they can
/// never disagree about black ice.
///
/// Expected classifications were derived independently from the Magnus
/// dew-point formula (constants a=17.625, b=243.04); the effective road-surface
/// temperature equals the dew point, so the test reduces to
/// "ambient <= 3.0 AND dewPoint <= 0.0" with the percent-guard belt.
void main() {
  group('isRadiativeFrostBlackIce — the radiative-frost window is caught', () {
    // The exact cases the in-drive screen used to silently classify DRY /
    // full-grip while the pre-trip briefing (correctly) warned black ice.
    test('+2.0C / 70% RH is black ice (dew point ~ -2.90C)', () {
      expect(
        isRadiativeFrostBlackIce(ambientCelsius: 2.0, humidityRHPercent: 70.0),
        isTrue,
      );
    });

    test('+0.5C / 90% RH is black ice (dew point ~ -0.95C)', () {
      expect(
        isRadiativeFrostBlackIce(ambientCelsius: 0.5, humidityRHPercent: 90.0),
        isTrue,
      );
    });

    test('+1.0C / 80% RH is black ice (dew point ~ -2.06C)', () {
      expect(
        isRadiativeFrostBlackIce(ambientCelsius: 1.0, humidityRHPercent: 80.0),
        isTrue,
      );
    });

    test('+2.5C / 75% RH is black ice (dew point ~ -1.48C)', () {
      expect(
        isRadiativeFrostBlackIce(ambientCelsius: 2.5, humidityRHPercent: 75.0),
        isTrue,
      );
    });

    test('+3.0C / 60% RH is black ice at the ambient ceiling (dew ~ -4.01C)', () {
      expect(
        isRadiativeFrostBlackIce(ambientCelsius: 3.0, humidityRHPercent: 60.0),
        isTrue,
      );
    });
  });

  group('isRadiativeFrostBlackIce — no cry-wolf', () {
    test('20C / 25% RH is NOT frost (above the ambient ceiling)', () {
      expect(
        isRadiativeFrostBlackIce(ambientCelsius: 20.0, humidityRHPercent: 25.0),
        isFalse,
      );
    });

    test('+5C / 60% RH is NOT frost (above the ambient ceiling)', () {
      expect(
        isRadiativeFrostBlackIce(ambientCelsius: 5.0, humidityRHPercent: 60.0),
        isFalse,
      );
    });

    test('+3.01C is NOT frost — just past the ceiling', () {
      expect(
        isRadiativeFrostBlackIce(ambientCelsius: 3.01, humidityRHPercent: 90.0),
        isFalse,
      );
    });

    test('+2.0C / 95% RH is NOT frost — saturated air, dew point ~ +1.28C', () {
      // High humidity does NOT mean frost: when the air is near-saturated the
      // dew point rises toward ambient, so the surface does not cool below 0.
      expect(
        isRadiativeFrostBlackIce(ambientCelsius: 2.0, humidityRHPercent: 95.0),
        isFalse,
      );
    });
  });

  group('isRadiativeFrostBlackIce — never throws, absence is never hazard', () {
    test('null humidity -> false (missing data)', () {
      expect(
        isRadiativeFrostBlackIce(ambientCelsius: 1.0, humidityRHPercent: null),
        isFalse,
      );
    });

    test('NaN humidity -> false', () {
      expect(
        isRadiativeFrostBlackIce(
          ambientCelsius: 1.0,
          humidityRHPercent: double.nan,
        ),
        isFalse,
      );
    });

    test('NaN ambient -> false', () {
      expect(
        isRadiativeFrostBlackIce(
          ambientCelsius: double.nan,
          humidityRHPercent: 90.0,
        ),
        isFalse,
      );
    });

    test('below the 5% plausibility floor -> false (mis-wired fraction guard)', () {
      // A saturated 1.0 mis-passed as a percent would read as 1% RH; the floor
      // refuses to fabricate a deep false depression from it.
      expect(
        isRadiativeFrostBlackIce(ambientCelsius: 1.0, humidityRHPercent: 1.0),
        isFalse,
      );
      expect(
        isRadiativeFrostBlackIce(ambientCelsius: 1.0, humidityRHPercent: 4.9),
        isFalse,
      );
    });

    test('above 105% -> false (implausible feed)', () {
      expect(
        isRadiativeFrostBlackIce(ambientCelsius: 1.0, humidityRHPercent: 106.0),
        isFalse,
      );
    });

    test('supersaturation (100,105] reads as saturated (1.0)', () {
      // At 0C saturated air the dew point equals ambient (0.0) -> frost.
      expect(
        isRadiativeFrostBlackIce(ambientCelsius: 0.0, humidityRHPercent: 102.0),
        isTrue,
      );
    });

    test('does not throw for any guarded input', () {
      expect(
        () => isRadiativeFrostBlackIce(
          ambientCelsius: 1.0,
          humidityRHPercent: 0.0,
        ),
        returnsNormally,
      );
    });
  });

  group('constants are the documented envelope', () {
    test('ambient ceiling is 3.0C', () {
      expect(radiativeFrostAmbientCeilingCelsius, 3.0);
    });
    test('surface frost threshold is 0.0C', () {
      expect(radiativeFrostSurfaceTempCelsius, 0.0);
    });
  });
}
