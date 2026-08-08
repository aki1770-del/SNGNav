// An UNMEASURED precipitation figure must not buy a severity downgrade, and it
// must not be printed to a driver as "0.0 mm".
//
// The defect, at published source (0.0.5,
// lib/src/met_norway_advisory_provider.dart:323):
//
//   final precipitation = _readNum(next1Details?['precipitation_amount']) ?? 0.0;
//
// With a freezing temperature and an ABSENT precipitation figure, `_classify`
// saw `precipitation == 0` and returned 'Subzero forecast' -> moderate, instead
// of the 'Freezing precipitation' -> severe/extreme it would have reached had
// the value actually been measured above zero. Absence resolved to the benign
// branch. The same `?? 0.0` then emitted "next_1_hours precipitation_amount
// 0.0 mm" into the advisory description a driver reads.
//
// The publisher genba (measured 2026-08-08 against the live compact product):
// 32 of 86 timeseries slices for Hardangervidda carried NO `next_1_hours`
// block at all. This mapper reads timeseries[0], which did carry one at every
// coordinate sampled (Hardangervidda / Akita / Svalbard) — so the absent path
// is latent, not observed live. It is guarded here anyway: the honesty of a
// safety verdict cannot rest on a publisher continuing to be generous.
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_met_norway/condition_aggregator_met_norway.dart';
import 'package:test/test.dart';

/// A response whose `next_1_hours.details` carries `precipitation_amount` only
/// when [precipitationMm] is supplied — i.e. the key is absent, not null.
Map<String, dynamic> response({
  required double tempC,
  double? precipitationMm,
}) {
  return <String, dynamic>{
    'geometry': <String, dynamic>{
      'type': 'Point',
      'coordinates': <double>[7.5236, 60.5936],
    },
    'properties': <String, dynamic>{
      'timeseries': <dynamic>[
        <String, dynamic>{
          'time': '2026-01-15T07:00:00Z',
          'data': <String, dynamic>{
            'instant': <String, dynamic>{
              'details': <String, dynamic>{'air_temperature': tempC},
            },
            'next_1_hours': <String, dynamic>{
              'details': <String, dynamic>{
                if (precipitationMm != null)
                  'precipitation_amount': precipitationMm,
              },
              'summary': <String, dynamic>{'symbol_code': 'snow'},
            },
          },
        },
      ],
    },
  };
}

/// The exact live shape measured on 2026-08-08: the whole `next_1_hours` block
/// missing, `instant` and the longer-horizon blocks present. 32 of 86 slices in
/// the real Hardangervidda response look like this.
Map<String, dynamic> responseWithoutNext1Hours({required double tempC}) {
  return <String, dynamic>{
    'geometry': <String, dynamic>{
      'type': 'Point',
      'coordinates': <double>[7.5236, 60.5936],
    },
    'properties': <String, dynamic>{
      'timeseries': <dynamic>[
        <String, dynamic>{
          'time': '2026-01-15T07:00:00Z',
          'data': <String, dynamic>{
            'instant': <String, dynamic>{
              'details': <String, dynamic>{'air_temperature': tempC},
            },
            'next_6_hours': <String, dynamic>{
              'details': <String, dynamic>{'precipitation_amount': 3.0},
              'summary': <String, dynamic>{'symbol_code': 'snow'},
            },
            'next_12_hours': <String, dynamic>{
              'summary': <String, dynamic>{'symbol_code': 'snow'},
            },
          },
        },
      ],
    },
  };
}

void main() {
  group('freezing + UNMEASURED precipitation is not the benign branch', () {
    test('severity is NOT moderate — the downgrade is refused', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: -3.0),
      );

      expect(a, isNotNull);
      expect(a!.severity, isNot(AdvisorySeverity.moderate));
      expect(a.severity, AdvisorySeverity.unknown);
      expect(a.eventClass, kEventFreezingPrecipNotMeasured);
      expect(a.eventClass, isNot(kEventSubzeroForecast));
    });

    test('the description never prints a figure the publisher never sent', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: -3.0),
      );

      expect(a!.description, isNot(contains('0.0 mm')));
      expect(a.description, contains('not reported'));
    });

    test(
      'the whole next_1_hours block missing — the real live shape — is still '
      'not the benign branch',
      () {
        final a = mapLocationForecastResponseToAdvisory(
          response: responseWithoutNext1Hours(tempC: -4.0),
        );

        expect(a, isNotNull);
        expect(a!.severity, AdvisorySeverity.unknown);
        expect(a.eventClass, kEventFreezingPrecipNotMeasured);
        expect(a.description, isNot(contains('0.0 mm')));
        // No symbol_code is reachable without the next_1_hours summary, so
        // certainty degrades honestly too.
        expect(a.certainty, AdvisoryCertainty.possible);
      },
    );

    test('a non-numeric precipitation value is absence, not zero', () {
      final r = response(tempC: -3.0);
      final ts =
          (r['properties'] as Map<String, dynamic>)['timeseries']
              as List<dynamic>;
      final data =
          (ts.first as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      final next1 = data['next_1_hours'] as Map<String, dynamic>;
      (next1['details'] as Map<String, dynamic>)['precipitation_amount'] =
          'not-a-number';

      final a = mapLocationForecastResponseToAdvisory(response: r);

      expect(a!.severity, AdvisorySeverity.unknown);
      expect(a.eventClass, kEventFreezingPrecipNotMeasured);
    });
  });

  group('measurements keep their meaning — no behaviour lost', () {
    test(
      'a MEASURED zero is still a measurement — subzero/dry stays moderate',
      () {
        final a = mapLocationForecastResponseToAdvisory(
          response: response(tempC: -3.0, precipitationMm: 0.0),
        );

        expect(a!.severity, AdvisorySeverity.moderate);
        expect(a.eventClass, kEventSubzeroForecast);
        expect(a.description, contains('0.0 mm'));
      },
    );

    test('measured freezing precipitation is still severe', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: -3.0, precipitationMm: 0.4),
      );

      expect(a!.severity, AdvisorySeverity.severe);
      expect(a.eventClass, kEventFreezingPrecipitation);
    });

    test('measured heavy freezing precipitation is still extreme', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: -3.0, precipitationMm: 9.0),
      );

      expect(a!.severity, AdvisorySeverity.extreme);
      expect(a.eventClass, kEventFreezingPrecipitation);
    });

    test('above-freezing heavy precipitation is still severe', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: 6.0, precipitationMm: 9.0),
      );

      expect(a!.severity, AdvisorySeverity.severe);
      expect(a.eventClass, kEventHeavyPrecipitation);
    });

    test('an unmeasured precipitation figure alone raises no advisory when '
        'nothing else is hazardous', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: 8.0),
      );

      // Silence, not an all-clear: the adapter emits nothing rather than
      // asserting the road is fine.
      expect(a, isNull);
    });
  });

  group('honest bound — the temperature axis', () {
    // Recorded as a PINNED bound, not silently changed. With air_temperature
    // absent and heavy precipitation measured, the adapter emits 'Heavy
    // precipitation' at `severe` rather than the `extreme` it would reach if
    // the temperature were measured below freezing.
    //
    // This is NOT the 0.0.5 defect class. It invents no measurement and
    // asserts no benign verdict — it declines to claim a freezing component
    // nobody measured, which is the honest ceiling on the evidence held.
    // Stated here so the next reader does not have to rediscover it, and so a
    // future change to it is a deliberate act.
    test('absent temperature yields severe, and never a benign class', () {
      final r = response(tempC: 0.0, precipitationMm: 9.0);
      final ts =
          (r['properties'] as Map<String, dynamic>)['timeseries']
              as List<dynamic>;
      final data =
          (ts.first as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      (data['instant'] as Map<String, dynamic>)['details'] =
          <String, dynamic>{};

      final a = mapLocationForecastResponseToAdvisory(response: r);

      expect(a!.eventClass, kEventHeavyPrecipitation);
      expect(a.severity, AdvisorySeverity.severe);
      // The bound that matters: absence never reaches minor/moderate here.
      expect(a.severity, isNot(AdvisorySeverity.moderate));
      expect(a.severity, isNot(AdvisorySeverity.minor));
      // And no temperature is fabricated into the driver-facing text.
      expect(a.description, isNot(contains('air_temperature')));
    });
  });
}
