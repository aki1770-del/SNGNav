import 'package:driving_weather/driving_weather.dart';
import 'package:navigation_safety_calibration/navigation_safety_calibration.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:test/test.dart';

WeatherCondition _condition({
  PrecipitationType precipType = PrecipitationType.none,
  PrecipitationIntensity intensity = PrecipitationIntensity.none,
  double temperatureCelsius = 5.0,
  double visibilityMeters = 10000,
  bool iceRisk = false,
  double? humidityRH,
}) => WeatherCondition(
  precipType: precipType,
  intensity: intensity,
  temperatureCelsius: temperatureCelsius,
  visibilityMeters: visibilityMeters,
  windSpeedKmh: 0,
  iceRisk: iceRisk,
  humidityRH: humidityRH,
  source: ObservationSource.measured,
  timestamp: DateTime(2026),
);

void main() {
  group('RoadSurfaceState.fromCondition', () {
    test('clear warm → dry', () {
      expect(
        RoadSurfaceState.fromCondition(_condition()),
        RoadSurfaceState.dry,
      );
    });

    test('iceRisk flag → blackIce regardless of precip', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(iceRisk: true)),
        RoadSurfaceState.blackIce,
      );
    });

    test('no precip, very cold → blackIce', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(temperatureCelsius: -5)),
        RoadSurfaceState.blackIce,
      );
    });

    test('rain heavy warm → standingWater', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.rain,
            intensity: PrecipitationIntensity.heavy,
            temperatureCelsius: 10,
          ),
        ),
        RoadSurfaceState.standingWater,
      );
    });

    test('rain light warm → wet', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.rain,
            intensity: PrecipitationIntensity.light,
            temperatureCelsius: 10,
          ),
        ),
        RoadSurfaceState.wet,
      );
    });

    test('freezing rain → blackIce', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.rain,
            intensity: PrecipitationIntensity.moderate,
            temperatureCelsius: -1,
          ),
        ),
        RoadSurfaceState.blackIce,
      );
    });

    test('snow warm → slush (melting)', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.snow,
            intensity: PrecipitationIntensity.moderate,
            temperatureCelsius: 3,
          ),
        ),
        RoadSurfaceState.slush,
      );
    });

    test('snow cold heavy → compactedSnow', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.snow,
            intensity: PrecipitationIntensity.heavy,
            temperatureCelsius: -5,
          ),
        ),
        RoadSurfaceState.compactedSnow,
      );
    });

    test('sleet → slush', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.sleet,
            intensity: PrecipitationIntensity.moderate,
          ),
        ),
        RoadSurfaceState.slush,
      );
    });

    test('hail heavy → standingWater', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.hail,
            intensity: PrecipitationIntensity.heavy,
          ),
        ),
        RoadSurfaceState.standingWater,
      );
    });

    test('snow cold light → slush', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.snow,
            intensity: PrecipitationIntensity.light,
            temperatureCelsius: -5,
          ),
        ),
        RoadSurfaceState.slush,
      );
    });

    test('hail light → wet', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.hail,
            intensity: PrecipitationIntensity.light,
          ),
        ),
        RoadSurfaceState.wet,
      );
    });

    test('heavy rain at exactly 3°C → wet (boundary, not standingWater)', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.rain,
            intensity: PrecipitationIntensity.heavy,
            temperatureCelsius: 3,
          ),
        ),
        RoadSurfaceState.wet,
      );
    });

    test('snow at exactly 2°C → slush (boundary)', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.snow,
            intensity: PrecipitationIntensity.moderate,
            temperatureCelsius: 2,
          ),
        ),
        RoadSurfaceState.slush,
      );
    });

    test('snow moderate at exactly -2°C → slush (boundary, not compacted)', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.snow,
            intensity: PrecipitationIntensity.moderate,
            temperatureCelsius: -2,
          ),
        ),
        RoadSurfaceState.slush,
      );
    });

    test('no precip at exactly -3°C → blackIce (boundary)', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(temperatureCelsius: -3)),
        RoadSurfaceState.blackIce,
      );
    });

    test('no precip at -2°C → dry (above blackIce threshold)', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(temperatureCelsius: -2)),
        RoadSurfaceState.dry,
      );
    });

    test('rain at exactly 0°C → blackIce (freezing boundary)', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.rain,
            intensity: PrecipitationIntensity.light,
            temperatureCelsius: 0,
          ),
        ),
        RoadSurfaceState.blackIce,
      );
    });

    test('rain at exactly 1°C → wet (just above freezing)', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.rain,
            intensity: PrecipitationIntensity.light,
            temperatureCelsius: 1,
          ),
        ),
        RoadSurfaceState.wet,
      );
    });

    test('heavy rain at 4°C → standingWater (just above 3°C boundary)', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.rain,
            intensity: PrecipitationIntensity.heavy,
            temperatureCelsius: 4,
          ),
        ),
        RoadSurfaceState.standingWater,
      );
    });

    test('snow at -3°C moderate → compactedSnow (crosses <-2 boundary)', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.snow,
            intensity: PrecipitationIntensity.moderate,
            temperatureCelsius: -3,
          ),
        ),
        RoadSurfaceState.compactedSnow,
      );
    });

    test('hail moderate → wet (not heavy, not standingWater)', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.hail,
            intensity: PrecipitationIntensity.moderate,
          ),
        ),
        RoadSurfaceState.wet,
      );
    });

    test('iceRisk overrides snow classification', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.snow,
            intensity: PrecipitationIntensity.heavy,
            temperatureCelsius: 5,
            iceRisk: true,
          ),
        ),
        RoadSurfaceState.blackIce,
      );
    });

    test('iceRisk overrides rain classification', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.rain,
            intensity: PrecipitationIntensity.light,
            temperatureCelsius: 20,
            iceRisk: true,
          ),
        ),
        RoadSurfaceState.blackIce,
      );
    });
  });

  group('RoadSurfaceState.fromCondition — radiative-frost black ice', () {
    // The exact case the live in-drive screen used to classify DRY / full-grip
    // while the pre-trip briefing (correctly) warned black ice. HER's Akita
    // pre-dawn commute: clear, no precip, air a couple of degrees above zero,
    // high humidity — a frosted bridge deck.
    test('no precip, +2C, 70% RH -> blackIce (was DRY: the contradiction)', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(temperatureCelsius: 2.0, humidityRH: 70.0),
        ),
        RoadSurfaceState.blackIce,
      );
    });

    test('no precip, +0.5C, 90% RH -> blackIce', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(temperatureCelsius: 0.5, humidityRH: 90.0),
        ),
        RoadSurfaceState.blackIce,
      );
    });

    test('no precip, +2C, humidity ABSENT -> dry (humidity-gated, no fabrication)', () {
      // Without humidity the classifier abstains rather than guessing — absence
      // is never hazard, and never suppresses a colder classification either.
      expect(
        RoadSurfaceState.fromCondition(
          _condition(temperatureCelsius: 2.0),
        ),
        RoadSurfaceState.dry,
      );
    });

    test('no precip, +2C, 95% RH -> dry (saturated air, dew point > 0, no cry-wolf)', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(temperatureCelsius: 2.0, humidityRH: 95.0),
        ),
        RoadSurfaceState.dry,
      );
    });

    test('no precip, +5C, 90% RH -> dry (above the ambient ceiling)', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(temperatureCelsius: 5.0, humidityRH: 90.0),
        ),
        RoadSurfaceState.dry,
      );
    });

    // --- Independent intent pins (literal expected, NOT derived from the
    // function under test) for the dry->blackIce expansion this bond introduced.

    test('no precip, -2C, 40% RH -> blackIce (sub-zero WITH humidity; was dry)', () {
      // The single largest behavior change: at -2C (above the -3C residual-ice
      // threshold) the road used to be dry/full-grip; with humidity present the
      // dew point is ~-13.8C, so it is now correctly blackIce. Pinned by intent.
      expect(
        RoadSurfaceState.fromCondition(
          _condition(temperatureCelsius: -2.0, humidityRH: 40.0),
        ),
        RoadSurfaceState.blackIce,
      );
    });

    test('no precip, -2C, humidity ABSENT -> dry (unchanged; the companion)', () {
      // Same -2C with no humidity feed still returns dry (pre-existing), so the
      // dry->blackIce expansion is strictly humidity-gated.
      expect(
        RoadSurfaceState.fromCondition(
          _condition(temperatureCelsius: -2.0),
        ),
        RoadSurfaceState.dry,
      );
    });

    test('no precip, +2C, 30% RH -> blackIce (INTENDED: dry air fires deeper)', () {
      // Documents intent (lens-3): the dew-point model fires MORE readily as
      // humidity drops (drier air => deeper depression). +2C/30%RH -> dew point
      // ~-13.8C -> blackIce. This is deliberate caution-add on a cold-dry clear
      // morning; a future maintainer can revisit whether a higher moisture floor
      // better matches real dry mornings (see KNOWN_LIMITATIONS.md).
      expect(
        RoadSurfaceState.fromCondition(
          _condition(temperatureCelsius: 2.0, humidityRH: 30.0),
        ),
        RoadSurfaceState.blackIce,
      );
    });

    test('humidity does NOT override the snow branch (+3C snow stays slush)', () {
      // The radiative-frost window is the no-precip case only; a melting-snow
      // classification must not be flipped to black ice by high humidity.
      expect(
        RoadSurfaceState.fromCondition(
          _condition(
            precipType: PrecipitationType.snow,
            intensity: PrecipitationIntensity.moderate,
            temperatureCelsius: 3,
            humidityRH: 95.0,
          ),
        ),
        RoadSurfaceState.slush,
      );
    });

    test('cross-path agreement: fromCondition matches the shared classifier', () {
      // The whole point of the bond: the in-drive classifier and the pre-trip
      // advisor call the SAME isRadiativeFrostBlackIce, so for the no-precip
      // window they can never disagree. This asserts the equivalence directly
      // across a matrix, including the previously-contradictory cases.
      const temps = [-1.0, 0.0, 0.5, 1.0, 2.0, 2.5, 3.0, 3.01, 5.0];
      const humidities = [null, 40.0, 60.0, 70.0, 80.0, 90.0, 95.0, 100.0];
      for (final t in temps) {
        for (final rh in humidities) {
          final surface = RoadSurfaceState.fromCondition(
            _condition(temperatureCelsius: t, humidityRH: rh),
          );
          final expectedBlackIce =
              t <= -3 ||
              isRadiativeFrostBlackIce(ambientCelsius: t, humidityRHPercent: rh);
          expect(
            surface == RoadSurfaceState.blackIce,
            expectedBlackIce,
            reason: 'no-precip t=$t rh=$rh: surface=$surface '
                'expectedBlackIce=$expectedBlackIce',
          );
        }
      }
    });
  });

  group('RoadSurfaceState grip factors', () {
    test('dry = 1.0', () {
      expect(RoadSurfaceState.dry.gripFactor, 1.0);
    });

    test('blackIce = 0.15', () {
      expect(RoadSurfaceState.blackIce.gripFactor, 0.15);
    });

    test('standingWater = 0.6', () {
      expect(RoadSurfaceState.standingWater.gripFactor, 0.6);
    });

    test('wet = 0.7', () {
      expect(RoadSurfaceState.wet.gripFactor, 0.7);
    });

    test('slush = 0.5', () {
      expect(RoadSurfaceState.slush.gripFactor, 0.5);
    });

    test('compactedSnow = 0.3', () {
      expect(RoadSurfaceState.compactedSnow.gripFactor, 0.3);
    });

    test('all grip factors are in 0.0–1.0 range', () {
      for (final state in RoadSurfaceState.values) {
        expect(state.gripFactor, greaterThanOrEqualTo(0.0));
        expect(state.gripFactor, lessThanOrEqualTo(1.0));
      }
    });

    test(
      'grip factors ordered: dry > wet > standingWater > slush > compactedSnow > blackIce',
      () {
        expect(
          RoadSurfaceState.dry.gripFactor,
          greaterThan(RoadSurfaceState.wet.gripFactor),
        );
        expect(
          RoadSurfaceState.wet.gripFactor,
          greaterThan(RoadSurfaceState.standingWater.gripFactor),
        );
        expect(
          RoadSurfaceState.standingWater.gripFactor,
          greaterThan(RoadSurfaceState.slush.gripFactor),
        );
        expect(
          RoadSurfaceState.slush.gripFactor,
          greaterThan(RoadSurfaceState.compactedSnow.gripFactor),
        );
        expect(
          RoadSurfaceState.compactedSnow.gripFactor,
          greaterThan(RoadSurfaceState.blackIce.gripFactor),
        );
      },
    );
  });

  group('HysteresisFilter', () {
    test('debounces transient changes', () {
      final filter = HysteresisFilter<RoadSurfaceState>();
      expect(filter.update(RoadSurfaceState.dry), RoadSurfaceState.dry);
      expect(filter.update(RoadSurfaceState.wet), RoadSurfaceState.dry);
      expect(filter.update(RoadSurfaceState.dry), RoadSurfaceState.dry);
    });

    test('transitions when threshold met', () {
      final filter = HysteresisFilter<RoadSurfaceState>();
      filter.update(RoadSurfaceState.dry);
      filter.update(RoadSurfaceState.wet);
      final result = filter.update(RoadSurfaceState.wet);
      expect(result, RoadSurfaceState.wet);
    });

    test('reset clears buffered state', () {
      final filter = HysteresisFilter<RoadSurfaceState>();
      filter.update(RoadSurfaceState.dry);
      filter.update(RoadSurfaceState.wet);
      filter.reset();
      expect(filter.current, isNull);
      expect(filter.update(RoadSurfaceState.slush), RoadSurfaceState.slush);
    });

    test('first reading always sets current', () {
      final filter = HysteresisFilter<String>();
      expect(filter.current, isNull);
      expect(filter.update('hello'), 'hello');
    });

    test('add and update are aliases', () {
      final filter = HysteresisFilter<int>();
      expect(filter.add(1), 1);
      expect(filter.update(2), 1);
      expect(filter.add(2), 2);
    });
  });
}
