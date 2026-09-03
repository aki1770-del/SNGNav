// The above-zero black-ice window, which this adapter could not see until 0.1.0.
//
// Up to 0.0.6 the coldest gate here was `air_temperature <= 0`. That is the
// exact threshold `navigation_safety_calibration` documents as missing this
// case: "a 'warn below 0 °C ambient' threshold misses this window". Under
// clear-sky radiative cooling the road surface falls toward the dew point and
// surface moisture freezes while the air still reads +1…+3 °C — and a driver
// reading a Norwegian or Finnish forecast got NOTHING AT ALL in that band,
// while the same hazard was already served elsewhere in this catalogue.
//
// The classification is NOT recomputed here. It is delegated to
// `isRadiativeFrostBlackIce`, whose own documentation gives the reason: "Two
// independently-maintained copies of this threshold logic ARE that disagreement
// waiting to happen." This adapter was a third copy; these tests pin that it no
// longer is.
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_met_norway/condition_aggregator_met_norway.dart';
import 'package:test/test.dart';

Map<String, dynamic> response({
  required double tempC,
  double? precipitationMm,
  double? humidityPercent,
}) => {
      'geometry': {
        'type': 'Point',
        'coordinates': [18.96, 69.65], // Tromsø
      },
      'properties': {
        'timeseries': [
          {
            'time': '2026-01-15T07:00:00Z',
            'data': {
              'instant': {
                'details': {
                  'air_temperature': tempC,
                  if (humidityPercent != null)
                    'relative_humidity': humidityPercent,
                },
              },
              'next_1_hours': {
                'details': {
                  if (precipitationMm != null)
                    'precipitation_amount': precipitationMm,
                },
                'summary': {'symbol_code': 'clearsky_night'},
              },
            },
          },
        ],
      },
    };

void main() {
  group('the window the pre-0.1.0 gate could not see', () {
    test(
        'THE CASE ITSELF — +2 °C with dry-to-moderate air is black ice, and '
        'was silence before', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: 2.0, humidityPercent: 60.0),
      );

      expect(a, isNotNull,
          reason: 'this is the Akita/Nordic pre-dawn bridge-deck hazard. '
              'Returning null here is what 0.0.6 did.');
      expect(a!.eventClass, 'Radiative frost black ice');
      expect(a.severity, AdvisorySeverity.severe,
          reason: 'ice ON the road, not merely a cold road');
    });

    test(
        'NEGATIVE CONTROL — the old gate. Same slice with the humidity the '
        'feed sends REMOVED goes to a different class, proving the humidity '
        'is what does the work and this test is not vacuous', () {
      final withHumidity = mapLocationForecastResponseToAdvisory(
        response: response(tempC: 2.0, humidityPercent: 60.0),
      );
      final withoutHumidity = mapLocationForecastResponseToAdvisory(
        response: response(tempC: 2.0),
      );

      expect(withHumidity!.eventClass, 'Radiative frost black ice');
      expect(withoutHumidity!.eventClass, isNot('Radiative frost black ice'));
    });
  });

  group('the scope the calibration documents, inherited not re-decided', () {
    test('SATURATED air above zero does NOT fire — the model does not cover '
        'freezing fog and must not pretend to', () {
      // Documented verbatim in navigation_safety_calibration: at +2 °C / 95 %
      // RH the dew point is ~ +1.3 °C, so this is not radiative frost.
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: 2.0, humidityPercent: 95.0),
      );
      expect(a, isNull);
    });

    test('above the ambient ceiling does NOT fire — no cry-wolf on a benign '
        'dry afternoon', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: 12.0, humidityPercent: 30.0),
      );
      expect(a, isNull);
    });

    test('a mis-wired FRACTION (0.6 where percent is required) yields no '
        'advisory rather than a fabricated one', () {
      // The calibration floors implausible sub-5 % readings and returns false,
      // deliberately, because a saturated 1.0 passed as a percent would read as
      // 1 % RH and fabricate a deep false depression. Pinned so the behaviour
      // is visible rather than accidental.
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: 2.0, humidityPercent: 0.6),
      );
      expect(a, isNull);
    });
  });

  group('caution-add-only: it may speak where 0.0.6 was silent, never over a '
      'colder finding', () {
    test('measured freezing precipitation still wins', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(
            tempC: -1.0, precipitationMm: 1.0, humidityPercent: 60.0),
      );
      expect(a!.eventClass, 'Freezing precipitation');
      expect(a.severity, AdvisorySeverity.severe);
    });

    test('freezing with UNMEASURED precipitation still refuses the downgrade',
        () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: -3.0, humidityPercent: 60.0),
      );
      expect(a!.eventClass, 'Freezing, precipitation not measured');
      expect(a.severity, AdvisorySeverity.unknown);
    });
  });

  group('absence does not become an all-clear', () {
    test('inside the frost band with NO humidity is named, not silent', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: 2.0),
      );
      expect(a, isNotNull,
          reason: 'the window cannot be ruled OUT without humidity, and '
              '"we could not evaluate it" is not "there is no ice"');
      expect(a!.eventClass, 'Radiative frost, humidity not measured');
      expect(a.severity, AdvisorySeverity.unknown,
          reason: 'an unmeasured field buys no downgrade — same rule as '
              'Freezing, precipitation not measured');
      expect(a.severity, isNot(AdvisorySeverity.moderate));
    });

    test('the description names a humidity it does not have, rather than '
        'omitting the line', () {
      final absent = mapLocationForecastResponseToAdvisory(
        response: response(tempC: 2.0),
      );
      expect(absent!.description, contains('relative_humidity not reported'));

      final present = mapLocationForecastResponseToAdvisory(
        response: response(tempC: 2.0, humidityPercent: 60.0),
      );
      expect(present!.description, contains('relative_humidity 60.0 %'));
    });
  });
}
