// The above-zero band: what this adapter may say there, and what it may not.
//
// 0.0.6 said NOTHING in (0, +3] C. 0.1.0 spoke there for the first time and an
// adversarial gate measured what it actually said on 600 live api.met.no
// slices: the `severe` channel fired on 64 of them, and 54 of those 64 (84%)
// were under cloud >= 80% -- the sky state that SUPPRESSES the longwave cooling
// the class is named for. It also fired on `heavyrain` slices, and on -10 C.
// Every test below pins one of those refutations.
//
// The classification is delegated to `isRadiativeFrostBlackIce`; what this
// package decides is WHEN IT IS ENTITLED TO ASK -- a dry surface, a clear sky,
// and an ambient band bounded at BOTH ends.
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_met_norway/condition_aggregator_met_norway.dart';
import 'package:test/test.dart';

Map<String, dynamic> response({
  required double tempC,
  double? precipitationMm,
  double? humidityPercent,
  double? cloudPercent,
  String? symbolCode = 'clearsky_night',
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
                  if (cloudPercent != null)
                    'cloud_area_fraction': cloudPercent,
                },
              },
              'next_1_hours': {
                'details': {
                  if (precipitationMm != null)
                    'precipitation_amount': precipitationMm,
                },
                if (symbolCode != null) 'summary': {'symbol_code': symbolCode},
              },
            },
          },
        ],
      },
    };

// A dry, clear, +2 C pre-dawn slice: the case the class exists for.
Advisory? frostCase({double rh = 60.0, double cloud = 5.0}) =>
    mapLocationForecastResponseToAdvisory(
      response: response(
          tempC: 2.0, precipitationMm: 0.0, humidityPercent: rh,
          cloudPercent: cloud),
    );

void main() {
  group('the window the pre-0.1.0 gate could not see', () {
    test('THE CASE ITSELF — dry surface, clear sky, +2 C: black ice', () {
      final a = frostCase();
      expect(a, isNotNull, reason: 'silence here is what 0.0.6 did');
      expect(a!.eventClass, 'Radiative frost black ice');
    });

    test('NEGATIVE CONTROL — remove the humidity the feed sends and the same '
        'slice classifies differently, so the humidity is what does the work',
        () {
      final withRh = frostCase();
      final withoutRh = mapLocationForecastResponseToAdvisory(
        response: response(tempC: 2.0, precipitationMm: 0.0, cloudPercent: 5.0),
      );
      expect(withRh!.eventClass, 'Radiative frost black ice');
      expect(withoutRh!.eventClass, isNot('Radiative frost black ice'));
      expect(withoutRh.eventClass, 'Radiative frost, inputs not measured');
    });
  });

  group('CRY-WOLF REFUTATIONS — each pins a slice the gate caught 0.1.0 on',
      () {
    test('MEASURED RAIN below the heavy floor is not black ice. 0.1.0 called a '
        'heavyrain slice "Radiative frost black ice" in its own headline', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(
            tempC: 1.0, precipitationMm: 3.9, humidityPercent: 90.0,
            cloudPercent: 100.0, symbolCode: 'heavyrain'),
      );
      expect(a, isNull);
    });

    test('OVERCAST is not black ice — cloud suppresses the mechanism the class '
        'is named for, and 84% of 0.1.0 fires were under cloud >= 80%', () {
      final overcast = frostCase(cloud: 100.0);
      expect(overcast, isNull);

      // The identical slice with a clear sky DOES fire — so this test is
      // measuring the sky and not something else.
      expect(frostCase(cloud: 5.0)!.eventClass, 'Radiative frost black ice');
    });

    test('an UNREAD sky is an unread input, not a clear one', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(
            tempC: 2.0, precipitationMm: 0.0, humidityPercent: 60.0),
      );
      expect(a!.eventClass, 'Radiative frost, inputs not measured');
      expect(a.severity, AdvisorySeverity.unknown);
    });
  });

  group('BOUNDED AT BOTH ENDS — the calibration has a ceiling and no floor', () {
    test('-10 C is not "ice while the air is above zero". 0.1.0 classified it '
        'as black ice, severe, in a description reading -10.0 C', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(
            tempC: -10.0, precipitationMm: -1.0, humidityPercent: 60.0,
            cloudPercent: 5.0),
      );
      expect(a?.eventClass, isNot('Radiative frost black ice'));
    });

    test('an integrator LOWERING freezingTemperatureCelsius to warn LESS must '
        'not get an escalation instead', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(
            tempC: -1.0, precipitationMm: 0.0, humidityPercent: 60.0,
            cloudPercent: 5.0),
        freezingTemperatureCelsius: -2.0,
      );
      expect(a?.eventClass, isNot('Radiative frost black ice'));
    });

    test('above the ambient ceiling stays silent', () {
      expect(
        mapLocationForecastResponseToAdvisory(
          response: response(
              tempC: 12.0, precipitationMm: 0.0, humidityPercent: 30.0,
              cloudPercent: 0.0),
        ),
        isNull,
      );
    });
  });

  group('the hazard the model CANNOT assess is named, not silenced', () {
    test('saturated air above zero returns the freezing-fog class. 0.1.0 '
        'returned bare null here — D3 worst case, and 0.1.0 had also changed '
        'what that silence MEANT', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(
            tempC: 2.0, precipitationMm: 0.0, humidityPercent: 97.0,
            cloudPercent: 100.0, symbolCode: 'fog'),
      );
      expect(a, isNotNull);
      expect(a!.eventClass, contains('Freezing fog risk'));
      expect(a.severity, AdvisorySeverity.unknown,
          reason: 'a hazard we can see the conditions for and cannot assess is '
              'UNSTATED, never minor and never silence');
    });
  });

  group('whose claim is it', () {
    test('derived classes carry `possible`, never the publisher\'s confidence, '
        'and symbol_code must not lend it', () {
      // symbol_code present would have bought `likely` in 0.1.0.
      final a = frostCase();
      expect(a!.certainty, AdvisoryCertainty.possible);
    });

    test('a publisher-threshold class keeps the prior symbol_code rule', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(
            tempC: -2.0, precipitationMm: 1.0, symbolCode: 'sleet'),
      );
      expect(a!.eventClass, 'Freezing precipitation');
      expect(a.certainty, AdvisoryCertainty.likely);
    });

    test('the description marks a derived claim as OURS, above the byline', () {
      final derived = frostCase();
      expect(derived!.description,
          contains('Derived by condition_aggregator_met_norway'));
      expect(derived.description, contains('not an advisory issued by the '
          'publisher'));

      final relayed = mapLocationForecastResponseToAdvisory(
        response: response(tempC: -2.0, precipitationMm: 1.0),
      );
      expect(relayed!.description,
          isNot(contains('Derived by condition_aggregator_met_norway')),
          reason: 'a relayed publisher threshold is not our inference');
    });
  });

  group('the description change is DECLARED, because it touches every class',
      () {
    test('pre-existing classes gained a humidity segment — the CHANGELOG says '
        'so, and this pins it so it cannot drift back silently', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(tempC: -2.0, precipitationMm: 1.0),
      );
      expect(a!.eventClass, 'Freezing precipitation');
      expect(a.description, contains('relative_humidity not reported'));
    });
  });
}
