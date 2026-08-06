/// GUARD — the Measured-or-Absent contract at the ONE-FIELD-ABSENT seam.
///
/// The 0.3.0 recall closed the ALL-fields-absent path: a `WeatherCondition`
/// carrying nothing no longer classifies as `dry`. It did NOT close the path
/// where the road IS partly measured and the one field the classifier needs to
/// decide the hazard is the field that is missing.
///
/// `fromCondition`'s `precipType == none` branch consults
/// `isRadiativeFrostBlackIce(temp, humidityRH)`. That function returns `false`
/// on `humidityRH == null` — an ABSTENTION, not a measurement. The branch then
/// falls through to `return dry` — `gripFactor: 1.0`, MAXIMUM GRIP — which
/// yields `RecommendedResponse.proceed` and the advisory "Conditions normal".
///
/// So a hygrometer-less feed at −2.9 °C is told the road is normal, while the
/// SAME feed with a humidity reading is told "Black ice risk". The frost check
/// declined; the answer was reported as an affirmative all-clear. That is the
/// fabricated-clear defect class, one field in from where 0.3.0 stopped.
///
/// The band is bounded and small: `temp ∈ (−3, +3]` with `precipType == none`
/// and `humidityRH == null`. Below −3 °C the deep-cold rule already fires;
/// above +3 °C the ambient ceiling declines on the TEMPERATURE alone, which is
/// a measured decline and honest.
library;

import 'package:driving_weather/driving_weather.dart';
import 'package:navigation_safety_calibration/navigation_safety_calibration.dart'
    show radiativeFrostAmbientCeilingCelsius;
import 'package:snow_rendering/snow_rendering.dart';
import 'package:test/test.dart';

/// A road that IS measured — except for the hygrometer.
WeatherCondition hygrometerless(double temp) => WeatherCondition(
      precipType: PrecipitationType.none,
      intensity: PrecipitationIntensity.none,
      temperatureCelsius: temp,
      visibilityMeters: 20000,
      windSpeedKmh: 3,
      iceRisk: false,
      humidityRH: null, // the feed has no hygrometer
      source: ObservationSource.measured,
      timestamp: DateTime.utc(2026, 1, 15, 6),
    );

/// Air temperatures inside the frost window, where the humidity reading is
/// what decides between black ice and a benign surface.
const _frostBand = <double>[-2.9, -2.0, -1.0, 0.0, 0.5, 1.0, 2.0, 3.0];

void main() {
  group('an ABSTAINED frost check is never a benign surface', () {
    test('no temperature in the frost band classifies as dry', () {
      final offenders = <double>[];
      for (final t in _frostBand) {
        expect(t, lessThanOrEqualTo(radiativeFrostAmbientCeilingCelsius),
            reason: 'band must stay inside the ceiling the check uses');
        if (RoadSurfaceState.fromCondition(hygrometerless(t)) ==
            RoadSurfaceState.dry) {
          offenders.add(t);
        }
      }
      expect(offenders, isEmpty,
          reason: 'humidity absent => the radiative-frost determination could '
              'not be made. `dry` carries gripFactor 1.0 (MAXIMUM GRIP) and is '
              'a POSITIVE claim about the road. These temperatures (°C) '
              'claimed it anyway: $offenders');
    });

    test('no temperature in the frost band hands back maximum grip', () {
      for (final t in _frostBand) {
        final a = DrivingConditionAssessment.fromCondition(hygrometerless(t));
        expect(a.gripFactor, isNot(1.0),
            reason: 'at $t °C with no hygrometer the grip coefficient was '
                'invented at maximum');
      }
    });

    test('no temperature in the frost band reads "Conditions normal"', () {
      for (final t in _frostBand) {
        final a = DrivingConditionAssessment.fromCondition(hygrometerless(t));
        expect(a.recommendedResponse, isNot(RecommendedResponse.proceed),
            reason: 'at $t °C the frost check abstained, yet the tier said '
                'proceed');
        expect(a.advisoryMessage, isNot('Conditions normal'),
            reason: 'at $t °C the driver is shown an all-clear built on a '
                'determination that was never made');
      }
    });

    test(
        'the ONE omitted JSON key must not flip the live advisory '
        '(real Open-Meteo parser)', () {
      Map<String, dynamic> payload({double? rh}) => {
            'current': {
              'temperature_2m': -2.9,
              'weather_code': 0,
              'wind_speed_10m': 3.0,
              if (rh != null) 'relative_humidity_2m': rh,
            },
            'hourly': {
              'snowfall': List<double>.filled(24, 0.0),
              'visibility': List<double>.filled(24, 20000.0),
            },
          };

      final withRh = DrivingConditionAssessment.fromCondition(
          OpenMeteoWeatherProvider.parseWeatherResponse(payload(rh: 40)));
      final withoutRh = DrivingConditionAssessment.fromCondition(
          OpenMeteoWeatherProvider.parseWeatherResponse(payload()));

      expect(withRh.recommendedResponse, RecommendedResponse.reduceSpeed,
          reason: 'sanity: with the humidity key present this IS black ice');

      expect(withoutRh.recommendedResponse, isNot(RecommendedResponse.proceed),
          reason: 'omitting relative_humidity_2m turned "Black ice risk — '
              'reduce speed significantly" into "Conditions normal" at '
              '−2.9 °C. Absence of one key must never manufacture an '
              'all-clear.');
    });

    test('ABOVE the ceiling, dry stays honest (this must NOT regress)', () {
      // Above +3 °C the check declines on the TEMPERATURE, which was measured.
      // That is a real determination and `dry` is earned. Guarding the band
      // must not turn every warm dry road into "unknown" — that is the
      // cry-wolf inverse and would be its own defect.
      for (final t in <double>[3.1, 5.0, 12.0]) {
        expect(RoadSurfaceState.fromCondition(hygrometerless(t)),
            RoadSurfaceState.dry,
            reason: 'at $t °C the frost window is excluded by measured '
                'temperature alone');
      }
    });
  });
}
