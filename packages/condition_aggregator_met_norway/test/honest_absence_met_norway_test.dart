// An unmeasured precipitation figure must not buy a severity downgrade, and
// must not be printed as "0.0 mm" to a driver.
//
// Up to 0.0.5:
//   final precipitation = _readNum(next1Details?['precipitation_amount']) ?? 0.0;
//
// With a freezing temperature and an ABSENT precipitation figure, `_classify`
// saw `precipitation == 0` and returned 'Subzero forecast' -> moderate, instead
// of the 'Freezing precipitation' -> severe it would have returned had the
// value actually been measured above zero. Absence resolved to the benign
// branch. The same `?? 0.0` then emitted "next_1_hours precipitation_amount
// 0.0 mm" into the advisory description shown to the driver.
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_met_norway/condition_aggregator_met_norway.dart';
import 'package:test/test.dart';

Map<String, dynamic> response({
  required double tempC,
  double? precipitationMm,
}) => {
      'geometry': {
        'type': 'Point',
        'coordinates': [10.0, 60.0],
      },
      'properties': {
        'timeseries': [
          {
            'time': '2026-01-15T07:00:00Z',
            'data': {
              'instant': {
                'details': {'air_temperature': tempC},
              },
              'next_1_hours': {
                'details': {
                  if (precipitationMm != null)
                    'precipitation_amount': precipitationMm,
                },
                'summary': {'symbol_code': 'snow'},
              },
            },
          },
        ],
      },
    };

void main() {
  group('freezing + UNMEASURED precipitation is not the benign branch', () {
    test('severity is NOT moderate — the downgrade is refused', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: -3.0),
      );

      expect(a, isNotNull);
      expect(a!.severity, isNot(AdvisorySeverity.moderate));
      expect(a.severity, AdvisorySeverity.unknown);
      expect(a.eventClass, contains('not measured'));
    });

    test('the description never prints a precipitation figure we do not have',
        () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: -3.0),
      );

      expect(a!.description, isNot(contains('0.0 mm')));
      expect(a.description, contains('not reported'));
    });

    test('a MEASURED zero is still a measurement — subzero/dry stays moderate',
        () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: -3.0, precipitationMm: 0.0),
      );

      expect(a!.severity, AdvisorySeverity.moderate);
      expect(a.eventClass, 'Subzero forecast');
      expect(a.description, contains('0.0 mm'));
    });

    test('measured freezing precipitation is still severe', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: -3.0, precipitationMm: 0.4),
      );

      expect(a!.severity, AdvisorySeverity.severe);
      expect(a.eventClass, 'Freezing precipitation');
    });

    test('measured heavy freezing precipitation is still extreme', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: -3.0, precipitationMm: 9.0),
      );

      expect(a!.severity, AdvisorySeverity.extreme);
    });
  });
}
