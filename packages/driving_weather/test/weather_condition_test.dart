/// WeatherCondition — the Measured-or-Absent contract.
///
/// The load-bearing group is "absence can never become a confident positive".
/// Every test in it FAILS against 0.4.4, where `WeatherCondition.clear()`
/// hardcoded +5.0 °C / 10 km / 0 km/h / iceRisk=false and `bool get isHazardous`
/// resolved absence to its `false` branch — i.e. to "clear road".
library;

import 'package:driving_weather/driving_weather.dart';
import 'package:test/test.dart';

void main() {
  final timestamp = DateTime(2026, 3, 12, 6);

  /// A fully-known, genuinely benign condition. Every field the hazard verdict
  /// needs is present, so — and only so — it may read `notHazardous`.
  WeatherCondition fullyKnownBenign() => WeatherCondition(
    precipType: PrecipitationType.none,
    intensity: PrecipitationIntensity.none,
    temperatureCelsius: 5.0,
    visibilityMeters: 10000,
    windSpeedKmh: 0,
    iceRisk: false,
    source: ObservationSource.measured,
    timestamp: timestamp,
  );

  group('absence can never become a confident positive', () {
    test('unknown() measures nothing — no field is filled in', () {
      final c = WeatherCondition.unknown(timestamp: timestamp);

      // 0.4.4 put 5.0 / 10000.0 / 0.0 / false here. It measured none of them.
      expect(c.temperatureCelsius, isNull);
      expect(c.visibilityMeters, isNull);
      expect(c.windSpeedKmh, isNull);
      expect(c.iceRisk, isNull);
      expect(c.precipType, isNull);
      expect(c.intensity, isNull);
      expect(c.humidityRH, isNull);
      expect(c.hazardAssertion, isNull);
      expect(c.isFullyUnknown, isTrue);
      expect(c.timestamp, timestamp);
    });

    test(
      'unknown() is NOT a clear road — hazard is unknown, not notHazardous',
      () {
        final c = WeatherCondition.unknown(timestamp: timestamp);

        // THE test. In 0.4.4 this path produced `isHazardous == false`, which the
        // downstream classifier read as a clear road and rendered as
        // "Conditions normal" to a driver who might have been on black ice.
        expect(c.hazard, SafetyVerdict.unknown);
        expect(c.hazard, isNot(SafetyVerdict.notHazardous));
      },
    );

    test('every derived verdict abstains when its input was not measured', () {
      final c = WeatherCondition.unknown(timestamp: timestamp);

      expect(c.freezing, SafetyVerdict.unknown); // never "above freezing"
      expect(c.reducedVisibility, SafetyVerdict.unknown); // never "you can see"
      expect(c.snowing, SafetyVerdict.unknown); // never "not snowing"
    });

    test('notHazardous requires COMPLETE knowledge — drop any input and the '
        'verdict falls back to unknown, never to a clear road', () {
      expect(fullyKnownBenign().hazard, SafetyVerdict.notHazardous);

      final noIce = WeatherCondition(
        precipType: PrecipitationType.none,
        intensity: PrecipitationIntensity.none,
        temperatureCelsius: 5.0,
        visibilityMeters: 10000,
        iceRisk: null, // <- not measured
        source: ObservationSource.measured,
        timestamp: timestamp,
      );
      final noVisibility = WeatherCondition(
        precipType: PrecipitationType.none,
        intensity: PrecipitationIntensity.none,
        temperatureCelsius: 5.0,
        visibilityMeters: null, // <- not measured
        iceRisk: false,
        source: ObservationSource.measured,
        timestamp: timestamp,
      );
      final noIntensity = WeatherCondition(
        precipType: PrecipitationType.none,
        intensity: null, // <- not measured
        temperatureCelsius: 5.0,
        visibilityMeters: 10000,
        iceRisk: false,
        source: ObservationSource.measured,
        timestamp: timestamp,
      );

      expect(noIce.hazard, SafetyVerdict.unknown);
      expect(noVisibility.hazard, SafetyVerdict.unknown);
      expect(noIntensity.hazard, SafetyVerdict.unknown);
    });
  });

  group('the asymmetry: positive evidence fires on partial data', () {
    test('ice risk alone is hazardous even when nothing else was measured', () {
      final c = WeatherCondition(
        iceRisk: true,
        source: ObservationSource.measured,
        timestamp: timestamp,
      );

      expect(c.hazard, SafetyVerdict.hazardous);
    });

    test(
      'a severe authority assertion is hazardous with zero measured fields',
      () {
        // The Digitraffic case: an authority declares a severe situation and
        // measures no temperature, no visibility, no wind. The alert must still
        // reach the driver — carried by the real signal, not by invented ones.
        final c = WeatherCondition.unknown(
          timestamp: timestamp,
          hazardAssertion: HazardAssertion.severe,
        );

        expect(c.hazard, SafetyVerdict.hazardous);
        expect(c.temperatureCelsius, isNull);
        expect(c.visibilityMeters, isNull);
        expect(c.windSpeedKmh, isNull);
      },
    );

    test('extreme assertion is hazardous; minor and unstated severity are '
        'unknown — never a clear road', () {
      SafetyVerdict verdictFor(HazardAssertion a) => WeatherCondition.unknown(
        timestamp: timestamp,
        hazardAssertion: a,
      ).hazard;

      expect(verdictFor(HazardAssertion.extreme), SafetyVerdict.hazardous);
      expect(verdictFor(HazardAssertion.severe), SafetyVerdict.hazardous);
      // Not hazardous enough to fire, but the road was never measured — so the
      // answer is "unknown", not "fine".
      expect(verdictFor(HazardAssertion.moderate), SafetyVerdict.unknown);
      expect(verdictFor(HazardAssertion.minor), SafetyVerdict.unknown);
      expect(verdictFor(HazardAssertion.unknown), SafetyVerdict.unknown);
      expect(verdictFor(HazardAssertion.none), SafetyVerdict.unknown);
    });

    test('heavy precipitation alone is hazardous', () {
      final c = WeatherCondition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.heavy,
        source: ObservationSource.measured,
        timestamp: timestamp,
      );

      expect(c.hazard, SafetyVerdict.hazardous);
    });

    test('visibility below 200 m alone is hazardous', () {
      final c = WeatherCondition(
        visibilityMeters: 150,
        source: ObservationSource.measured,
        timestamp: timestamp,
      );

      expect(c.hazard, SafetyVerdict.hazardous);
      expect(c.reducedVisibility, SafetyVerdict.hazardous);
    });

    test('being offline does not mean hazard — it means unknown', () {
      // The anti-cry-wolf half of the asymmetry. If absence raised a hazard,
      // every coverage gap would alert, the driver would learn the alert means
      // nothing, and she would ignore it on the night it is real.
      final c = WeatherCondition.unknown(timestamp: timestamp);

      expect(c.hazard, isNot(SafetyVerdict.hazardous));
      expect(c.hazard, SafetyVerdict.unknown);
    });
  });

  group('measured verdicts', () {
    test('freezing is thresholded at 0 °C', () {
      WeatherCondition at(double t) => WeatherCondition(
        temperatureCelsius: t,
        source: ObservationSource.measured,
        timestamp: timestamp,
      );

      expect(at(0).freezing, SafetyVerdict.hazardous);
      expect(at(-3).freezing, SafetyVerdict.hazardous);
      expect(at(0.1).freezing, SafetyVerdict.notHazardous);
    });

    test('reducedVisibility is thresholded at 1 km', () {
      WeatherCondition at(double v) => WeatherCondition(
        visibilityMeters: v,
        source: ObservationSource.measured,
        timestamp: timestamp,
      );

      expect(at(999).reducedVisibility, SafetyVerdict.hazardous);
      expect(at(1000).reducedVisibility, SafetyVerdict.notHazardous);
    });

    test('snow with none intensity is not snowing', () {
      final c = WeatherCondition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.none,
        source: ObservationSource.measured,
        timestamp: timestamp,
      );

      expect(c.snowing, SafetyVerdict.notHazardous);
    });

    test('snow of unreported intensity is unknown, not "not snowing"', () {
      final c = WeatherCondition(
        precipType: PrecipitationType.snow,
        intensity: null,
        source: ObservationSource.measured,
        timestamp: timestamp,
      );

      expect(c.snowing, SafetyVerdict.unknown);
    });

    test('rain is positively not snowing even with intensity unreported', () {
      // We were told the precipitation type. That is enough to answer THIS
      // question — abstaining here would be false modesty, not honesty.
      final c = WeatherCondition(
        precipType: PrecipitationType.rain,
        intensity: null,
        source: ObservationSource.measured,
        timestamp: timestamp,
      );

      expect(c.snowing, SafetyVerdict.notHazardous);
    });
  });

  group('provenance', () {
    test('simulatedClear states a scenario, and says that it is simulated', () {
      final c = WeatherCondition.simulatedClear(timestamp: timestamp);

      // A simulator ASSERTING a scenario is honest — it is not a measurement
      // claim. The values survive; the provenance is stated.
      expect(c.source, ObservationSource.simulated);
      expect(c.temperatureCelsius, 5.0);
      expect(c.visibilityMeters, 10000.0);
      expect(c.windSpeedKmh, 0.0);
      expect(c.iceRisk, isFalse);
      // Complete knowledge of a scenario — so a negative verdict is legitimate.
      expect(c.hazard, SafetyVerdict.notHazardous);
    });

    test('unknown() defaults to a measured source that measured nothing', () {
      expect(
        WeatherCondition.unknown(timestamp: timestamp).source,
        ObservationSource.measured,
      );
    });

    test('source is part of identity', () {
      final measured = WeatherCondition(
        temperatureCelsius: 1.0,
        source: ObservationSource.measured,
        timestamp: timestamp,
      );
      final derived = WeatherCondition(
        temperatureCelsius: 1.0,
        source: ObservationSource.derived,
        timestamp: timestamp,
      );

      expect(measured, isNot(equals(derived)));
    });
  });

  group('humidityRH — the field that was already honest', () {
    test('is carried, shows in toString, and affects equality', () {
      final base = WeatherCondition(
        precipType: PrecipitationType.none,
        intensity: PrecipitationIntensity.none,
        temperatureCelsius: 1.0,
        visibilityMeters: 10000,
        windSpeedKmh: 5,
        humidityRH: 82.0,
        source: ObservationSource.measured,
        timestamp: timestamp,
      );
      final noHumidity = WeatherCondition(
        precipType: PrecipitationType.none,
        intensity: PrecipitationIntensity.none,
        temperatureCelsius: 1.0,
        visibilityMeters: 10000,
        windSpeedKmh: 5,
        source: ObservationSource.measured,
        timestamp: timestamp,
      );

      expect(base.humidityRH, 82.0);
      expect(noHumidity.humidityRH, isNull);
      expect(base, isNot(equals(noHumidity)));
      expect(base.toString(), contains('RH=82%'));
      expect(noHumidity.toString(), isNot(contains('RH=')));
    });
  });

  group('toString', () {
    test('renders absence as "?" and never as a number', () {
      final s = WeatherCondition.unknown(timestamp: timestamp).toString();

      expect(s, contains('temp=?'));
      expect(s, contains('vis=?'));
      expect(s, contains('wind=?'));
      expect(s, contains('ice=?'));
      expect(s, isNot(contains('5.0°C')));
      expect(s, isNot(contains('10000')));
    });

    test('renders a measured condition with its values and provenance', () {
      final s = fullyKnownBenign().toString();

      expect(s, contains('5.0°C'));
      expect(s, contains('vis=10000m'));
      expect(s, contains('src=measured'));
    });

    test('shows ICE when ice risk is measured true', () {
      final c = WeatherCondition(
        precipType: PrecipitationType.sleet,
        intensity: PrecipitationIntensity.moderate,
        temperatureCelsius: -3,
        visibilityMeters: 800,
        windSpeedKmh: 15,
        iceRisk: true,
        source: ObservationSource.measured,
        timestamp: timestamp,
      );

      expect(c.toString(), contains('ICE'));
      expect(c.props.last, timestamp);
    });
  });

  group('a declared advisory is never overruled by benign measurements', () {
    test(
      'complete benign measurements + a moderate assertion => unknown, '
      'not notHazardous',
      () {
        final c = WeatherCondition(
          precipType: PrecipitationType.none,
          intensity: PrecipitationIntensity.none,
          temperatureCelsius: 3.0,
          visibilityMeters: 9000.0,
          windSpeedKmh: 4.0,
          iceRisk: false,
          source: ObservationSource.measured,
          hazardAssertion: HazardAssertion.moderate,
          timestamp: DateTime.now(),
        );

        // The authority declared something our sensors cannot see. A complete
        // measurement set must not silently discard it.
        expect(c.hazard, SafetyVerdict.unknown);
      },
    );

    test('HazardAssertion.none does not hold the verdict at unknown', () {
      final c = WeatherCondition(
        precipType: PrecipitationType.none,
        intensity: PrecipitationIntensity.none,
        temperatureCelsius: 3.0,
        visibilityMeters: 9000.0,
        windSpeedKmh: 4.0,
        iceRisk: false,
        source: ObservationSource.measured,
        hazardAssertion: HazardAssertion.none,
        timestamp: DateTime.now(),
      );

      expect(c.hazard, SafetyVerdict.notHazardous);
    });
  });
}
