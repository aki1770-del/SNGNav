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
      expect(overcast!.eventClass, isNot('Radiative frost black ice'));
      // ⚑ and it is NOT silence: 0.0.7 returned null here while its CHANGELOG
      // promised a wrong threshold "can downgrade a finding, never hide one".
      expect(overcast.eventClass, contains('inputs not measured'));
      expect(overcast.description, contains('clear-sky confirmation'));

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
    test('it covers exactly the band the calibration calls UNCOVERED — a '
        'previous form implemented the COMPLEMENT of its own citation', () {
      // navigation_safety_calibration: "near-zero SATURATED FREEZING FOG above
      // ~ +1 C (dew point >= 0) is therefore NOT detected by this model".
      // A `temperature <= 1.0` ceiling spoke only where the model DOES assess.
      for (final t in <double>[0.5, 1.1, 1.5, 2.0, 2.9]) {
        final a = mapLocationForecastResponseToAdvisory(
          response: response(
              tempC: t, precipitationMm: 0.0, humidityPercent: 97.0,
              cloudPercent: 100.0, symbolCode: 'fog'),
        );
        expect(a, isNotNull, reason: 'silent at $t C, inside the blind spot');
        expect(a!.eventClass, contains('Saturated air above zero'));
        expect(a.severity, AdvisorySeverity.unknown);
      }
    });

    test('⚑ IT FIRES UNDER A CLEAR SKY — radiation fog forms BECAUSE the sky '
        'is clear, so a !clearSky gate was anti-correlated with the hazard',
        () {
      // Measured live: 2 of 84 saturated slices carried cloud <= 50 — the
      // Trondheim 00:00Z and 01:00Z radiation-fog hours, with MET reporting fog
      // under what a cloud gate calls a clear sky.
      for (final cloud in <double>[0.0, 20.0, 33.4]) {
        final a = mapLocationForecastResponseToAdvisory(
          response: response(
              tempC: 0.5, precipitationMm: 0.0, humidityPercent: 97.0,
              cloudPercent: cloud),
        );
        expect(a, isNotNull, reason: 'silent under cloud $cloud');
        expect(a!.eventClass, contains('Saturated air above zero'));
      }
    });

    test('wetter air at the same temperature must never turn a severe advisory '
        'into SILENCE', () {
      // The regression a gate measured across 104 grid cells: at +0.5 C /
      // cloud 20, RH 96.4 gave severe black ice and RH 96.5..100 gave null.
      final severe = mapLocationForecastResponseToAdvisory(
        response: response(
            tempC: 0.5, precipitationMm: 0.0, humidityPercent: 96.4,
            cloudPercent: 20.0),
      );
      expect(severe!.severity, AdvisorySeverity.severe);
      for (final rh in <double>[96.5, 97.0, 99.0, 100.0]) {
        expect(
          mapLocationForecastResponseToAdvisory(
            response: response(
                tempC: 0.5, precipitationMm: 0.0, humidityPercent: rh,
                cloudPercent: 20.0),
          ),
          isNotNull,
          reason: 'wetter air at RH $rh produced silence',
        );
      }
    });

    test('⚑ FREEZING DRIZZLE IN FOG speaks — rain rules out the RADIATIVE '
        'mechanism, not ice, and this is D3\'s compound case', () {
      for (final mm in <double>[0.1, 0.5, 2.0, 3.9]) {
        final a = mapLocationForecastResponseToAdvisory(
          response: response(
              tempC: 0.5, precipitationMm: mm, humidityPercent: 97.0,
              cloudPercent: 0.0, symbolCode: 'sleet'),
        );
        expect(a, isNotNull, reason: 'silent at precipitation $mm mm');
        expect(a!.eventClass, contains('Saturated air above zero'));
      }
    });

    test('raising the freezing floor to warn MORE must not delete the class',
        () {
      // The mirror of the defect already fixed on the black-ice branch: a
      // fixed ceiling crossed by a configurable floor emptied the window.
      for (final floor in <double>[0.0, 0.5, 1.0, 1.5, 2.0]) {
        expect(
          mapLocationForecastResponseToAdvisory(
            response: response(
                tempC: 2.5, precipitationMm: 0.0, humidityPercent: 97.0,
                cloudPercent: 100.0),
            freezingTemperatureCelsius: floor,
          ),
          isNotNull,
          reason: 'class died at freezingTemperatureCelsius $floor',
        );
      }
    });

    test('the positive determination WINS in the overlap, and an unread sky is '
        'NAMED rather than mistaken for fog', () {
      // frost TRUE and saturated FALSE at +0.1 C / RH 95 is the overlap a gate
      // found the fog branch pre-empting when the sky was unread.
      final unreadSky = mapLocationForecastResponseToAdvisory(
        response: response(
            tempC: 0.1, precipitationMm: 0.0, humidityPercent: 60.0),
      );
      expect(unreadSky!.eventClass, 'Radiative frost, inputs not measured');
      expect(unreadSky.description, contains('cloud_area_fraction'));

      final clearSky = mapLocationForecastResponseToAdvisory(
        response: response(
            tempC: 0.1, precipitationMm: 0.0, humidityPercent: 60.0,
            cloudPercent: 20.0),
      );
      expect(clearSky!.eventClass, 'Radiative frost black ice');
    });
  });

  group('an unmeasured input is reported ONLY where it could change the answer',
      () {
    test('absent sky with the predicate ALREADY FALSE stays SILENT — the cloud '
        'gate can only suppress a finding, never create one', () {
      // Previously this manufactured an `unknown` advisory out of a state the
      // package can positively rule out as benign.
      for (final rh in <double>[88.0, 90.0, 92.0, 94.0]) {
        expect(
          mapLocationForecastResponseToAdvisory(
            response: response(
                tempC: 2.0, precipitationMm: 0.0, humidityPercent: rh),
          ),
          isNull,
          reason: 'manufactured an advisory at RH $rh with no sky reading',
        );
      }
    });

    test('absent sky with the predicate TRUE is reported — there the sky could '
        'have changed the answer', () {
      final a = mapLocationForecastResponseToAdvisory(
        response: response(
            tempC: 2.0, precipitationMm: 0.0, humidityPercent: 60.0),
      );
      expect(a!.eventClass, 'Radiative frost, inputs not measured');
      expect(a.severity, AdvisorySeverity.unknown);
    });
  });

  group('severity, and the thresholds that carry it', () {
    test('black ice is SEVERE — above Advisory.isHighImpact', () {
      final a = frostCase();
      expect(a!.severity, AdvisorySeverity.severe);
      expect(a.isHighImpact, isTrue,
          reason: 'invisible ice is the case the windscreen cannot contradict, '
              'so it must reach the axis consumers actually read');
    });

    test('and it is ranked ABOVE Subzero forecast, which the old comment '
        'claimed while shipping the same level for both', () {
      final subzero = mapLocationForecastResponseToAdvisory(
        response: response(tempC: -1.0, precipitationMm: 0.0),
      );
      expect(subzero!.eventClass, 'Subzero forecast');
      expect(subzero.severity, AdvisorySeverity.moderate);
      expect(frostCase()!.severity.index,
          greaterThan(subzero.severity.index));
    });

    test('the cloud ceiling is genuinely OVERRIDABLE — it was documented as '
        'such in three places while being unreachable from outside', () {
      final overcast = response(
          tempC: 2.0, precipitationMm: 0.0, humidityPercent: 60.0,
          cloudPercent: 80.0);
      // Default 50 % — 80 % overcast downgrades, and SAYS SO.
      final suppressed = mapLocationForecastResponseToAdvisory(response: overcast);
      expect(suppressed!.eventClass, isNot('Radiative frost black ice'));
      expect(suppressed.eventClass, contains('inputs not measured'));
      // An integrator who accepts more cloud gets the finding.
      expect(
        mapLocationForecastResponseToAdvisory(
                response: overcast, clearSkyCloudPercentMax: 90.0)!
            .eventClass,
        'Radiative frost black ice',
      );
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

  group('0.0.8 — the recall patch, one test per live defect', () {
    test('MUST-1: the four constants 0.0.6 exported are back, with the same '
        'values — 0.0.7 DELETED them inside the caret range', () {
      // 0.0.6 shipped these under a doc saying they exist "so a consumer can
      // branch on them without matching literal strings that a future release
      // might reword". 0.0.7 removed the constants AND reworded.
      expect(kEventFreezingPrecipitation, 'Freezing precipitation');
      expect(kEventFreezingPrecipNotMeasured,
          'Freezing, precipitation not measured');
      expect(kEventHeavyPrecipitation, 'Heavy precipitation');
      expect(kEventSubzeroForecast, 'Subzero forecast');
      // and the classes this release added are exported too, so the same trap
      // cannot recur on them.
      expect(kEventRadiativeFrostBlackIce, isNotEmpty);
      expect(kEventSaturatedAboveZeroNotAssessed, isNotEmpty);
      expect(kEventRadiativeFrostInputsNotMeasured, isNotEmpty);
    });

    test('MUST-2: a cloud reading above the ceiling can DOWNGRADE a finding, '
        'never hide one — which is what the CHANGELOG already promised', () {
      for (final cloud in <double>[50.1, 60.0, 80.0, 100.0]) {
        final a = mapLocationForecastResponseToAdvisory(
          response: response(
              tempC: 2.0, precipitationMm: 0.0, humidityPercent: 70.0,
              cloudPercent: cloud),
        );
        expect(a, isNotNull, reason: 'silent at cloud $cloud');
        expect(a!.severity, isNot(AdvisorySeverity.severe));
      }
      // control: at the ceiling it is still the full finding
      expect(
        mapLocationForecastResponseToAdvisory(
          response: response(
              tempC: 2.0, precipitationMm: 0.0, humidityPercent: 70.0,
              cloudPercent: 50.0),
        )!.eventClass,
        'Radiative frost black ice',
      );
    });

    test('MUST-5: an implausible humidity is NEVER assessed-benign, and never '
        'fires a hazard', () {
      // Above the band: 0.0.7 read these as "saturated" and fired.
      for (final rh in <double>[106.0, 150.0, 200.0, 999.0]) {
        final a = mapLocationForecastResponseToAdvisory(
          response: response(
              tempC: 2.0, precipitationMm: 0.0, humidityPercent: rh,
              cloudPercent: 10.0),
        );
        expect(a!.eventClass, contains('inputs not measured'),
            reason: 'RH $rh produced a hazard');
      }
      // A mis-wired FRACTION: 0.0.7 certified this benign inside the
      // black-ice window.
      final frac = mapLocationForecastResponseToAdvisory(
        response: response(
            tempC: 1.5, precipitationMm: 0.0, humidityPercent: 0.97,
            cloudPercent: 5.0),
      );
      expect(frac, isNotNull, reason: 'a mis-wired fraction became silence');
      expect(frac!.eventClass, contains('inputs not measured'));
    });

    test('MUST-6: an absent or non-finite air_temperature is NOT benign', () {
      final absent = mapLocationForecastResponseToAdvisory(
        response: {
          'geometry': {'type': 'Point', 'coordinates': [18.96, 69.65]},
          'properties': {
            'timeseries': [
              {
                'time': '2026-01-15T07:00:00Z',
                'data': {
                  'instant': {'details': {'relative_humidity': 70.0}},
                  'next_1_hours': {'details': {'precipitation_amount': 0.0}},
                },
              },
            ],
          },
        },
      );
      expect(absent, isNotNull, reason: 'a missing temperature became silence');
      expect(absent!.description, contains('air_temperature'));
    });
  });
}
