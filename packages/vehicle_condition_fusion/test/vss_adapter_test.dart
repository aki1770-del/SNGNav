/// VSS-adapter tests — PURE DART.
///
/// These pin `VehicleConditionSignals.fromVss(...)`: the zero-glue mapping from
/// STANDARD COVESA VSS (v6.0) leaf paths to the typed fields. As with the rest
/// of this package, there is NO `kuksa_dart_sdk`, NO protobuf, NO running
/// databroker — a KUKSA `get` / `subscribe` just yields a `{path: value}` map,
/// which is exactly what `fromVss` consumes.
library;

import 'package:driving_conditions/driving_conditions.dart';
import 'package:test/test.dart';
import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';

void main() {
  group('VehicleConditionSignals.fromVss (standard COVESA VSS leaves)', () {
    test('full map → all nine fields populated, friction ÷100', () {
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.ADAS.ESC.RoadFriction.MostProbable': 25.0, // percent
        'Vehicle.ADAS.TCS.IsEngaged': true,
        'Vehicle.ADAS.ABS.IsEngaged': false,
        'Vehicle.ADAS.ESC.IsEngaged': true,
        'Vehicle.Exterior.AirTemperature': -3.0,
        'Vehicle.Exterior.Humidity': 82.0,
        'Vehicle.Speed': 42.0,
        'Vehicle.Body.Windshield.Front.Wiping.Intensity': 3,
        'Vehicle.Body.Raindetection.Intensity': 80,
      });

      expect(s.roadFriction, 0.25); // 25% → 0.25
      expect(s.tcsEngaged, isTrue);
      expect(s.absEngaged, isFalse);
      expect(s.escEngaged, isTrue);
      expect(s.airTempC, -3.0);
      expect(s.humidityRH, 82.0);
      expect(s.speedKmh, 42.0);
      expect(s.wiperIntensity, 3);
      expect(s.rainIntensity, 80);
      expect(s.hasAnySignal, isTrue);
    });

    test('empty map → all fields null, hasAnySignal == false', () {
      final s = VehicleConditionSignals.fromVss(const {});
      expect(s.roadFriction, isNull);
      expect(s.tcsEngaged, isNull);
      expect(s.absEngaged, isNull);
      expect(s.escEngaged, isNull);
      expect(s.airTempC, isNull);
      expect(s.humidityRH, isNull);
      expect(s.speedKmh, isNull);
      expect(s.wiperIntensity, isNull);
      expect(s.rainIntensity, isNull);
      expect(s.hasAnySignal, isFalse);
    });

    test('Vehicle.Exterior.Humidity → humidityRH (the radiative-frost reach)', () {
      // The offline D3-worst-case wire: a real exterior humidity sensor lets the
      // shared classifier catch radiative-frost black ice BEFORE the wheels slip.
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.Exterior.AirTemperature': 2.0,
        'Vehicle.Exterior.Humidity': 70.0,
      });
      expect(s.airTempC, 2.0);
      expect(s.humidityRH, 70.0);

      // and it flows through to the WeatherCondition the classifier consumes
      final w = vehicleSignalsToWeatherCondition(s);
      expect(w.temperatureCelsius, 2.0);
      expect(w.humidityRH, 70.0);
    });

    test('humidity absent → humidityRH null → never fabricated', () {
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.Exterior.AirTemperature': 2.0,
      });
      expect(s.humidityRH, isNull);
      expect(vehicleSignalsToWeatherCondition(s).humidityRH, isNull);
    });

    test('non-finite humidity (NaN) → null, never a fabricated value', () {
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.Exterior.Humidity': double.nan,
      });
      expect(s.humidityRH, isNull);
    });

    test('partial map → only provided fields set, rest null (no fabrication)',
        () {
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.ADAS.ESC.RoadFriction.MostProbable': 18.0,
        'Vehicle.Exterior.AirTemperature': -6.0,
      });
      expect(s.roadFriction, closeTo(0.18, 1e-9));
      expect(s.airTempC, -6.0);
      // not provided → must stay null, never a default
      expect(s.tcsEngaged, isNull);
      expect(s.absEngaged, isNull);
      expect(s.escEngaged, isNull);
      expect(s.speedKmh, isNull);
      expect(s.wiperIntensity, isNull);
      expect(s.rainIntensity, isNull);
    });

    test('explicit null value → field stays null (not fabricated)', () {
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.ADAS.ESC.RoadFriction.MostProbable': null,
        'Vehicle.ADAS.TCS.IsEngaged': null,
      });
      expect(s.roadFriction, isNull);
      expect(s.tcsEngaged, isNull);
    });

    test('friction clamp: 150% → 1.0, -5% → 0.0', () {
      expect(
        VehicleConditionSignals.fromVss(
          const {'Vehicle.ADAS.ESC.RoadFriction.MostProbable': 150.0},
        ).roadFriction,
        1.0,
      );
      expect(
        VehicleConditionSignals.fromVss(
          const {'Vehicle.ADAS.ESC.RoadFriction.MostProbable': -5.0},
        ).roadFriction,
        0.0,
      );
    });

    test('non-finite friction (NaN / ±Infinity) → null, NOT a fabricated 1.0',
        () {
      // The dangerous case: (NaN/100).clamp(0,1) == 1.0 would assert MAX grip.
      expect(
        VehicleConditionSignals.fromVss(
          {'Vehicle.ADAS.ESC.RoadFriction.MostProbable': double.nan},
        ).roadFriction,
        isNull,
      );
      expect(
        VehicleConditionSignals.fromVss(
          {'Vehicle.ADAS.ESC.RoadFriction.MostProbable': double.infinity},
        ).roadFriction,
        isNull,
      );
      expect(
        VehicleConditionSignals.fromVss(
          {'Vehicle.ADAS.ESC.RoadFriction.MostProbable': double.negativeInfinity},
        ).roadFriction,
        isNull,
      );
    });

    test('garbage types → null, NEVER throws', () {
      late VehicleConditionSignals s;
      expect(
        () => s = VehicleConditionSignals.fromVss(const {
          'Vehicle.ADAS.ESC.RoadFriction.MostProbable': 'icy', // String
          'Vehicle.ADAS.TCS.IsEngaged': 2, // int, not 1/0
          'Vehicle.ADAS.ABS.IsEngaged': 'yes', // String, not bool
          'Vehicle.ADAS.ESC.IsEngaged': 7, // int, not 1/0
          'Vehicle.Exterior.AirTemperature': <String, Object?>{}, // Map
          'Vehicle.Speed': [1, 2, 3], // List
          'Vehicle.Body.Windshield.Front.Wiping.Intensity': 'high',
          'Vehicle.Body.Raindetection.Intensity': true, // bool, not numeric
        }),
        returnsNormally,
      );
      expect(s.roadFriction, isNull);
      expect(s.tcsEngaged, isNull);
      expect(s.absEngaged, isNull);
      expect(s.escEngaged, isNull);
      expect(s.airTempC, isNull);
      expect(s.speedKmh, isNull);
      expect(s.wiperIntensity, isNull);
      expect(s.rainIntensity, isNull);
      expect(s.hasAnySignal, isFalse);
    });

    test('non-finite numerics on numeric leaves → null, NEVER throws', () {
      // double.nan.round() / Infinity.round() throw — must be guarded, not crash.
      late VehicleConditionSignals s;
      expect(
        () => s = VehicleConditionSignals.fromVss({
          'Vehicle.Exterior.AirTemperature': double.nan,
          'Vehicle.Speed': double.infinity,
          'Vehicle.Body.Windshield.Front.Wiping.Intensity': double.nan,
          'Vehicle.Body.Raindetection.Intensity': double.negativeInfinity,
        }),
        returnsNormally,
      );
      expect(s.airTempC, isNull);
      expect(s.speedKmh, isNull);
      expect(s.wiperIntensity, isNull);
      expect(s.rainIntensity, isNull);
    });

    test('int-vs-double coercion: airTempC given as int -3 → -3.0', () {
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.Exterior.AirTemperature': -3, // int
      });
      expect(s.airTempC, -3.0);
      expect(s.airTempC, isA<double>());
    });

    test('friction accepts an int percent too (25 → 0.25)', () {
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.ADAS.ESC.RoadFriction.MostProbable': 25, // int percent
      });
      expect(s.roadFriction, 0.25);
    });

    test('VSS boolean leaf decodes int 1→true / 0→false (faithful, no '
        'under-warn)', () {
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.ADAS.TCS.IsEngaged': 1, // CAN bridge / non-SDK source
        'Vehicle.ADAS.ABS.IsEngaged': 0,
        'Vehicle.ADAS.ESC.IsEngaged': 1,
        'Vehicle.Exterior.AirTemperature': -4.0,
      });
      expect(s.tcsEngaged, isTrue);
      expect(s.absEngaged, isFalse);
      expect(s.escEngaged, isTrue);
      // The whole point: the traction-loss signal is NOT dropped → ice risk.
      expect(vehicleSignalsToWeatherCondition(s).iceRisk, isTrue);
    });

    test('VSS boolean leaf: a non-1/0 int → null (not silently true)', () {
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.ADAS.TCS.IsEngaged': 2,
      });
      expect(s.tcsEngaged, isNull);
    });

    test('numeric leaves never accept a bool (no global numbers-as-bool)', () {
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.Exterior.AirTemperature': true,
        'Vehicle.Speed': false,
      });
      expect(s.airTempC, isNull);
      expect(s.speedKmh, isNull);
    });

    test('rainIntensity 100.0 (double) → 100 (int); 120 → clamp 100', () {
      expect(
        VehicleConditionSignals.fromVss(
          const {'Vehicle.Body.Raindetection.Intensity': 100.0},
        ).rainIntensity,
        100,
      );
      expect(
        VehicleConditionSignals.fromVss(
          const {'Vehicle.Body.Raindetection.Intensity': 120},
        ).rainIntensity,
        100,
      );
      expect(
        VehicleConditionSignals.fromVss(
          const {'Vehicle.Body.Raindetection.Intensity': -10},
        ).rainIntensity,
        0,
      );
    });

    test('wiperIntensity has NO upper clamp, only >= 0', () {
      expect(
        VehicleConditionSignals.fromVss(
          const {'Vehicle.Body.Windshield.Front.Wiping.Intensity': 9},
        ).wiperIntensity,
        9, // not clamped down to any max
      );
      expect(
        VehicleConditionSignals.fromVss(
          const {'Vehicle.Body.Windshield.Front.Wiping.Intensity': -2},
        ).wiperIntensity,
        0, // clamped up to the floor
      );
    });

    test('wiper path is the Front instance-expanded VSS leaf', () {
      // Windshield is an instanced branch (["Front","Rear"]) in VSS v6.0, so
      // the DEPLOYED databroker leaf is the Front-instance path.
      expect(
        VehicleConditionSignals.vssWiperIntensity,
        'Vehicle.Body.Windshield.Front.Wiping.Intensity',
      );
      expect(
        VehicleConditionSignals.recognizedVssPaths,
        contains('Vehicle.Body.Windshield.Front.Wiping.Intensity'),
      );
      // The old non-instanced spelling must NOT be a recognized path.
      expect(
        VehicleConditionSignals.recognizedVssPaths,
        isNot(contains('Vehicle.Body.Windshield.Wiping.Intensity')),
      );
      // The Front path drives the field; the old spelling is now ignored.
      expect(
        VehicleConditionSignals.fromVss(
          const {'Vehicle.Body.Windshield.Front.Wiping.Intensity': 3},
        ).wiperIntensity,
        3,
      );
      expect(
        VehicleConditionSignals.fromVss(
          const {'Vehicle.Body.Windshield.Wiping.Intensity': 3}, // old/wrong
        ).wiperIntensity,
        isNull,
      );
    });

    test('unknown / extra keys are ignored', () {
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.ADAS.EBD.IsEngaged': true, // a real VSS leaf we do NOT map
        'Vehicle.Exterior.RoadSurfaceCondition.Snow': 90, // unreleased family
        'Vehicle.Speed': 30.0,
        'totally.unknown.path': 99,
      });
      expect(s.speedKmh, 30.0);
      // an unmapped engagement leaf is NOT folded into any field
      expect(s.tcsEngaged, isNull);
      expect(s.absEngaged, isNull);
      expect(s.escEngaged, isNull);
    });

    test('recognizedVssPaths has exactly the 9 paths', () {
      expect(VehicleConditionSignals.recognizedVssPaths, hasLength(9));
      expect(
        VehicleConditionSignals.recognizedVssPaths.toSet(),
        {
          'Vehicle.ADAS.ESC.RoadFriction.MostProbable',
          'Vehicle.ADAS.TCS.IsEngaged',
          'Vehicle.ADAS.ABS.IsEngaged',
          'Vehicle.ADAS.ESC.IsEngaged',
          'Vehicle.Exterior.AirTemperature',
          'Vehicle.Exterior.Humidity',
          'Vehicle.Speed',
          'Vehicle.Body.Windshield.Front.Wiping.Intensity',
          'Vehicle.Body.Raindetection.Intensity',
        },
      );
    });

    test('each recognized path drives EXACTLY its own field (no cross-wiring)',
        () {
      // path → the field it must set; used to assert that path sets THAT field
      // and leaves every OTHER field null.
      final fieldOf = <String, Object? Function(VehicleConditionSignals)>{
        VehicleConditionSignals.vssRoadFriction: (s) => s.roadFriction,
        VehicleConditionSignals.vssTcsEngaged: (s) => s.tcsEngaged,
        VehicleConditionSignals.vssAbsEngaged: (s) => s.absEngaged,
        VehicleConditionSignals.vssEscEngaged: (s) => s.escEngaged,
        VehicleConditionSignals.vssAirTemperature: (s) => s.airTempC,
        VehicleConditionSignals.vssHumidity: (s) => s.humidityRH,
        VehicleConditionSignals.vssSpeed: (s) => s.speedKmh,
        VehicleConditionSignals.vssWiperIntensity: (s) => s.wiperIntensity,
        VehicleConditionSignals.vssRainIntensity: (s) => s.rainIntensity,
      };

      // every recognized path is wired
      expect(
        fieldOf.keys.toSet(),
        VehicleConditionSignals.recognizedVssPaths.toSet(),
      );

      for (final path in VehicleConditionSignals.recognizedVssPaths) {
        final s = VehicleConditionSignals.fromVss(
          <String, Object?>{path: _probeValueFor(path)},
        );
        fieldOf.forEach((p, read) {
          if (p == path) {
            expect(read(s), isNotNull, reason: '$path should set its own field');
          } else {
            expect(read(s), isNull, reason: '$path must not set $p');
          }
        });
      }
    });

    test('round-trip: a known-icy VSS frame → classifier yields iceRisk', () {
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.ADAS.ESC.RoadFriction.MostProbable': 20.0, // 0.20 < 0.3
        'Vehicle.Exterior.AirTemperature': -5.0,
      });
      final condition = vehicleSignalsToWeatherCondition(s);
      expect(condition.iceRisk, isTrue);

      final a = DrivingConditionAssessment.fromCondition(condition);
      expect(a.surfaceState, RoadSurfaceState.blackIce);
      expect(a.advisoryMessage.toLowerCase(), contains('ice'));
    });

    test('round-trip: radiative-frost VSS frame (+2C, 70% RH, NO slip) → blackIce', () {
      // THE OFFLINE REACH PROOF. A real exterior temp + humidity frame with NO
      // friction/traction event (roadFriction absent, no TCS/ABS/ESC) — i.e. the
      // wheels have NOT slipped yet. Before this wire, this frame classified DRY
      // ("Conditions normal"); now the shared radiative-frost classifier catches
      // the black ice on the offline in-vehicle screen BEFORE the first slip.
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.Exterior.AirTemperature': 2.0,
        'Vehicle.Exterior.Humidity': 70.0,
      });
      final condition = vehicleSignalsToWeatherCondition(s);
      // CHANGED in 0.5.0 (was `isFalse`). This vehicle publishes NO friction
      // signal and no traction event, so we have no ice measurement at all.
      // `null` = we did not look. `false` would have been a claim we cannot
      // support — and it was the claim that let absence read as "no ice".
      expect(condition.iceRisk, isNull,
          reason: 'no friction signal at all — we do not know');
      expect(condition.humidityRH, 70.0);

      // The reach still holds: black ice is caught from temperature + humidity,
      // BEFORE the first slip, even with no friction signal and no rain sensor.
      final a = DrivingConditionAssessment.fromCondition(condition);
      expect(a.surfaceState, RoadSurfaceState.blackIce);
      expect(a.advisoryMessage, contains('Black ice risk'));
    });

    test(
        'round-trip: same frame WITHOUT humidity → surface UNKNOWN '
        '(honest abstention — and no longer a fabricated "dry")', () {
      // Same +2C frame but the vehicle has no humidity sensor. The classifier
      // must NOT fabricate black ice — it abstains, exactly as before.
      //
      // CHANGED in 0.5.0: it used to abstain all the way to `RoadSurfaceState.dry`
      // (grip 1.0, "Conditions normal"). But this frame carries NO precipitation
      // signal whatsoever — no wiper, no rain sensor — so "dry" was never
      // something we knew; it was the fall-through. Abstention now lands on
      // `null` (cannot classify), which is what abstaining actually means.
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.Exterior.AirTemperature': 2.0,
      });
      final a = DrivingConditionAssessment.fromCondition(
        vehicleSignalsToWeatherCondition(s),
      );
      expect(a.surfaceState, isNull);
      expect(a.surfaceState, isNot(RoadSurfaceState.dry));
      expect(a.gripFactor, isNull); // was 1.0 — maximum grip, from nothing
      expect(a.recommendedResponse, RecommendedResponse.conditionsUnknown);
    });

    test('round-trip: TCS engaged on a cold VSS frame → ice risk', () {
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.ADAS.ESC.RoadFriction.MostProbable': 60.0, // 0.60, not icy
        'Vehicle.ADAS.TCS.IsEngaged': true,
        'Vehicle.Exterior.AirTemperature': 0.0,
      });
      final a = DrivingConditionAssessment.fromCondition(
        vehicleSignalsToWeatherCondition(s),
      );
      expect(a.surfaceState, RoadSurfaceState.blackIce);
    });

    test('round-trip: ESC engaged on a cold VSS frame → ice risk', () {
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.ADAS.ESC.IsEngaged': true,
        'Vehicle.Exterior.AirTemperature': -6.0,
      });
      expect(s.escEngaged, isTrue);
      final a = DrivingConditionAssessment.fromCondition(
        vehicleSignalsToWeatherCondition(s),
      );
      expect(a.surfaceState, RoadSurfaceState.blackIce);
    });

    test('round-trip: ESC engaged on a WARM road → NOT ice (not freezing)', () {
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.ADAS.ESC.IsEngaged': true,
        'Vehicle.Exterior.AirTemperature': 12.0,
      });
      final a = DrivingConditionAssessment.fromCondition(
        vehicleSignalsToWeatherCondition(s),
      );
      expect(a.surfaceState, isNot(RoadSurfaceState.blackIce));
    });
  });
}

/// A type-correct probe value for a single recognized path, used to assert each
/// path drives exactly its own field.
Object _probeValueFor(String path) {
  switch (path) {
    case VehicleConditionSignals.vssTcsEngaged:
    case VehicleConditionSignals.vssAbsEngaged:
    case VehicleConditionSignals.vssEscEngaged:
      return true;
    case VehicleConditionSignals.vssRoadFriction:
      return 20.0;
    default:
      return 5.0;
  }
}
