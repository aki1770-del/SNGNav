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
    test('full map → all eight fields populated, friction ÷100', () {
      final s = VehicleConditionSignals.fromVss(const {
        'Vehicle.ADAS.ESC.RoadFriction.MostProbable': 25.0, // percent
        'Vehicle.ADAS.TCS.IsEngaged': true,
        'Vehicle.ADAS.ABS.IsEngaged': false,
        'Vehicle.ADAS.ESC.IsEngaged': true,
        'Vehicle.Exterior.AirTemperature': -3.0,
        'Vehicle.Speed': 42.0,
        'Vehicle.Body.Windshield.Front.Wiping.Intensity': 3,
        'Vehicle.Body.Raindetection.Intensity': 80,
      });

      expect(s.roadFriction, 0.25); // 25% → 0.25
      expect(s.tcsEngaged, isTrue);
      expect(s.absEngaged, isFalse);
      expect(s.escEngaged, isTrue);
      expect(s.airTempC, -3.0);
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
      expect(s.speedKmh, isNull);
      expect(s.wiperIntensity, isNull);
      expect(s.rainIntensity, isNull);
      expect(s.hasAnySignal, isFalse);
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

    test('out-of-spec friction → null (absent), NEVER clamped into a measurement',
        () {
      // This test used to assert the opposite — `150% → 1.0, -5% → 0.0` — and it
      // passed, which is how the defect stayed green. Clamping an out-of-range
      // reading to the maximum asserts PERFECT GRIP: a broken ESC's classic 255
      // "no reading" sentinel became (255/100).clamp(0,1) == 1.0, a
      // positively-measured clear road manufactured out of a dead sensor and
      // handed to every caller that reads `roadFriction`.
      //
      // It is the same harm the NaN case below already refused, on the same
      // clamp. The producer is broken; say so — return absent.
      for (final outOfSpec in const [255.0, 150.0, 100.5, -5.0, -0.1]) {
        expect(
          VehicleConditionSignals.fromVss(
            {'Vehicle.ADAS.ESC.RoadFriction.MostProbable': outOfSpec},
          ).roadFriction,
          isNull,
          reason: '$outOfSpec is outside the VSS 0..100 percent spec. It must '
              'read as ABSENT, not be clamped into a fabricated measurement.',
        );
      }

      // The spec boundaries themselves remain valid measurements.
      expect(
        VehicleConditionSignals.fromVss(
          const {'Vehicle.ADAS.ESC.RoadFriction.MostProbable': 0.0},
        ).roadFriction,
        0.0,
      );
      expect(
        VehicleConditionSignals.fromVss(
          const {'Vehicle.ADAS.ESC.RoadFriction.MostProbable': 100.0},
        ).roadFriction,
        1.0,
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

    test('recognizedVssPaths has exactly the 8 paths', () {
      expect(VehicleConditionSignals.recognizedVssPaths, hasLength(8));
      expect(
        VehicleConditionSignals.recognizedVssPaths.toSet(),
        {
          'Vehicle.ADAS.ESC.RoadFriction.MostProbable',
          'Vehicle.ADAS.TCS.IsEngaged',
          'Vehicle.ADAS.ABS.IsEngaged',
          'Vehicle.ADAS.ESC.IsEngaged',
          'Vehicle.Exterior.AirTemperature',
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
