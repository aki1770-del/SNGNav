// The Measured-or-Absent contract on the OFFLINE path.
//
// This is arguably the worst of the fabrication sites, because it is the
// COMPOUND-FAILURE fallback: it is what the app relies on when the network feed
// is gone — precisely the moment a driver most needs the truth.
//
// Up to 0.4.0, `vehicleSignalsToWeatherCondition` did this:
//
//     final temp = s.airTempC ?? kAssumedAboveFreezingCelsius;   // 5.0 °C
//
// A vehicle whose air-temperature sensor was silent was **ASSUMED ABOVE
// FREEZING**. Its constant's own docstring defended this as safe because "a
// missing signal never fabricates ice" — true, and beside the point: the missing
// signal was instead fabricating the *absence* of ice. An Akita car with a dead
// thermometer read +5.0 °C, classified `dry`, scored `gripFactor: 1.0`, and told
// its driver "Conditions normal".
//
// It also emitted `windSpeedKmh: 0.0` immediately after a comment saying the
// signal set does not carry wind, and fell through to `PrecipitationType.none`
// when the car published neither wiper nor rain sensor.

import 'package:driving_weather/driving_weather.dart';
import 'package:driving_conditions/driving_conditions.dart';
import 'package:test/test.dart';
import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';

final _t = DateTime.utc(2026, 1, 15, 6, 30);

void main() {
  group('D7 — a silent temperature sensor is not "above freezing"', () {
    test('absent airTempC → temperatureCelsius is null, NOT 5.0', () {
      final c = vehicleSignalsToWeatherCondition(
        const VehicleConditionSignals(wiperIntensity: 0),
        timestamp: _t,
      );
      expect(c.temperatureCelsius, isNull);
      expect(c.temperatureCelsius, isNot(5.0)); // kAssumedAboveFreezingCelsius
      expect(c.freezing, SafetyVerdict.unknown); // was "notHazardous"
    });

    test('absent airTempC → the road is NOT classified dry with full grip', () {
      final a = DrivingConditionAssessment.fromCondition(
        vehicleSignalsToWeatherCondition(
          const VehicleConditionSignals(wiperIntensity: 0),
          timestamp: _t,
        ),
      );
      expect(a.surfaceState, isNull);
      expect(a.surfaceState, isNot(RoadSurfaceState.dry));
      expect(a.gripFactor, isNull);
      expect(a.gripFactor, isNot(1.0));
      expect(a.recommendedResponse, RecommendedResponse.conditionsUnknown);
      expect(a.advisoryMessage, isNot(contains('Conditions normal')));
    });

    test('a real temperature still classifies exactly as before', () {
      // No cry-wolf: the honest path is unchanged when the car actually reports.
      final a = DrivingConditionAssessment.fromCondition(
        vehicleSignalsToWeatherCondition(
          const VehicleConditionSignals(
            airTempC: 5.0,
            roadFriction: 0.95,
            wiperIntensity: 0,
          ),
          timestamp: _t,
        ),
      );
      expect(a.surfaceState, RoadSurfaceState.dry);
      expect(a.gripFactor, 1.0);
      expect(a.recommendedResponse, RecommendedResponse.proceed);
    });
  });

  group('absence is never a measurement', () {
    test('wind is always null — the signal set does not carry it', () {
      final c = vehicleSignalsToWeatherCondition(
        const VehicleConditionSignals(airTempC: -3, wiperIntensity: 2),
        timestamp: _t,
      );
      expect(c.windSpeedKmh, isNull); // was a hardcoded 0.0
    });

    test('no wiper AND no rain sensor → precipitation unknown, NOT "none"', () {
      final c = vehicleSignalsToWeatherCondition(
        const VehicleConditionSignals(airTempC: 3.0),
        timestamp: _t,
      );
      expect(c.precipType, isNull);
      expect(c.precipType, isNot(PrecipitationType.none));
      expect(c.intensity, isNull);
      expect(c.visibilityMeters, isNull); // no proxy to derive from
    });

    test('a reported wiper-off IS evidence of no precipitation', () {
      // The asymmetry: silence is unknown, but an actual report of "wipers off"
      // is a real (if coarse) observation, and still reads as `none`.
      final c = vehicleSignalsToWeatherCondition(
        const VehicleConditionSignals(airTempC: 3.0, wiperIntensity: 0),
        timestamp: _t,
      );
      expect(c.precipType, PrecipitationType.none);
      expect(c.intensity, PrecipitationIntensity.none);
    });

    test('no friction signal → iceRisk is null, NOT false', () {
      final c = vehicleSignalsToWeatherCondition(
        const VehicleConditionSignals(airTempC: 3.0, wiperIntensity: 0),
        timestamp: _t,
      );
      expect(c.iceRisk, isNull);
      expect(c.iceRisk, isNot(false));
    });

    test('a MEASURED good friction still says "not icy"', () {
      final c = vehicleSignalsToWeatherCondition(
        const VehicleConditionSignals(
          airTempC: 3.0,
          roadFriction: 0.9,
          wiperIntensity: 0,
        ),
        timestamp: _t,
      );
      expect(c.iceRisk, isFalse); // we looked, and the road has grip
    });

    test('the condition declares itself DERIVED, not measured', () {
      // Visibility is a proxy and the precip type is inferred from wiper+temp.
      // Saying so lets a consumer tell a road-authority reading from a cue.
      final c = vehicleSignalsToWeatherCondition(
        const VehicleConditionSignals(airTempC: -3, wiperIntensity: 4),
        timestamp: _t,
      );
      expect(c.source, ObservationSource.derived);
    });
  });

  group('POSITIVE evidence still fires on partial data', () {
    test('low friction alone → ice, even with no temperature at all', () {
      final c = vehicleSignalsToWeatherCondition(
        const VehicleConditionSignals(roadFriction: 0.2),
        timestamp: _t,
      );
      expect(c.iceRisk, isTrue);

      final a = DrivingConditionAssessment.fromCondition(c);
      expect(a.surfaceState, RoadSurfaceState.blackIce);
      expect(a.recommendedResponse, RecommendedResponse.reduceSpeed);
    });

    test(
        'THE AKITA MORNING — radiative-frost black ice survives with NO rain '
        'sensor and NO friction signal', () {
      // +2 °C, 70% RH, wheels have NOT slipped, car has no rain sensor.
      // This is the offline reach that matters: black ice caught from a
      // thermometer and a hygrometer alone, BEFORE the first slip.
      //
      // The honest-absence work must not cost us this. It would have, if the
      // radiative-frost check had stayed gated behind a *reported* precipType.
      final c = vehicleSignalsToWeatherCondition(
        const VehicleConditionSignals(airTempC: 2.0, humidityRH: 70.0),
        timestamp: _t,
      );
      expect(c.iceRisk, isNull); // no friction signal — we do not claim to know
      expect(c.precipType, isNull); // no rain sensor — we do not claim to know

      final a = DrivingConditionAssessment.fromCondition(c);
      expect(a.surfaceState, RoadSurfaceState.blackIce);
      expect(a.advisoryMessage, contains('Black ice risk'));
      expect(a.recommendedResponse, RecommendedResponse.reduceSpeed);
    });

    test('...and without humidity it abstains rather than fabricating ice', () {
      final c = vehicleSignalsToWeatherCondition(
        const VehicleConditionSignals(airTempC: 2.0),
        timestamp: _t,
      );
      final a = DrivingConditionAssessment.fromCondition(c);
      expect(a.surfaceState, isNull); // unknown — not blackIce, and not dry
      expect(a.recommendedResponse, RecommendedResponse.conditionsUnknown);
    });
  });

  group('the fusion stream never fabricates', () {
    test('a snapshot with no signals at all is not emitted', () async {
      final fusion = VehicleConditionFusion(
        signals: Stream.value(const VehicleConditionSignals()),
      );
      final updates = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(updates.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // The only emission is the honest end-of-stream marker — never a scene.
      expect(updates.where((u) => u.assessment != null), isEmpty);
      expect(updates.last.isAvailable, isFalse);

      await sub.cancel();
      await fusion.dispose();
    });
  });
}
