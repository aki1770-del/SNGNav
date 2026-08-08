/// GUARD — an UNMEASURED ambient temperature must not buy a benign verdict.
///
/// Up to and including 0.3.3 this package answered "we did not measure the
/// outside air temperature" with the number **+5.0 °C**
/// (`_kAbsentTempPrecipFallbackCelsius`, `vehicle_signal_fusion.dart:49`, used
/// at `:147` as `airTemp ?? _kAbsentTempPrecipFallbackCelsius`). 0.3.2 had
/// already removed that constant from the ICE rule — a traction-loss event now
/// keeps the ice concern when the temperature is unknown — and its CHANGELOG
/// recorded the rest as a "known residual". This file is the residual, written
/// down as a failing test instead of a paragraph.
///
/// The fabricated +5.0 still decided three things:
///
///   1. **rain vs snow.** `precipType = temp <= 0 ? snow : rain`. With the
///      filler, precipitation on a vehicle that publishes no temperature is
///      always typed `rain` → downstream `RoadSurfaceState.wet` (grip 0.70) or
///      `standingWater`, and the advisory "Wet road — increased stopping
///      distance". If it was actually snowing at −5 °C the truth was `slush`
///      (0.50) or `compactedSnow` (0.30); if it was freezing rain the truth was
///      `blackIce` (0.15).
///
///   2. **the all-clear.** With no precipitation reported, the filler carries
///      the condition past `temp <= -3` (residual ice) and out to `dry` —
///      gripFactor **1.00**, `RecommendedResponse.proceed`, advisory
///      "Conditions normal". That is a positive claim about a road whose
///      deciding field nobody read.
///
///   3. **the public field.** `WeatherCondition.temperatureCelsius` reads
///      `5.0` and `isFreezing` reads `false` — a measurement handed to any
///      caller that displays or gates on it.
///
/// The rule this file pins is the one the package already applies elsewhere:
/// POSITIVE evidence of a hazard classifies on partial data (a low friction
/// reading, or a traction-loss event, still yields black ice with no
/// temperature at all — 0.3.2), while any BENIGN verdict must be earned. The
/// abstention channel already exists on this line: `VehicleConditionUpdate`
/// carries a nullable `assessment` and an `unavailableReason`, and the
/// package's own doc comment tells callers to branch on `isAvailable`.
///
/// EXPECTED RED against 0.3.3. That is L34, not a regression: a guard is not
/// INSERTED until it has been PROVEN to FAIL.
library;

import 'dart:async';

import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:test/test.dart';
import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';

Future<void> pumpEventQueue([int times = 20]) async {
  if (times == 0) return;
  await Future<void>.delayed(Duration.zero);
  return pumpEventQueue(times - 1);
}

/// Drives one snapshot through the complete-snapshot rail and returns every
/// update it emitted.
Future<List<VehicleConditionUpdate>> drive(VehicleConditionSignals s) async {
  final source = StreamController<VehicleConditionSignals>();
  final fusion = VehicleConditionFusion(signals: source.stream);
  final out = <VehicleConditionUpdate>[];
  final sub = fusion.conditions.listen(out.add);
  source.add(s);
  await pumpEventQueue();
  await sub.cancel();
  await fusion.dispose();
  await source.close();
  return out;
}

void main() {
  group('an unmeasured temperature never buys a benign verdict', () {
    test('no precipitation + NO temperature → the fusion abstains, '
        'never "Conditions normal" at grip 1.00', () async {
      // A perfectly ordinary databroker frame: the vehicle says its traction
      // control is not engaged. It says nothing at all about the outside air.
      // `Vehicle.Exterior.AirTemperature` is optional in VSS and plenty of
      // vehicles never publish it.
      final updates = await drive(
        const VehicleConditionSignals(tcsEngaged: false),
      );

      expect(updates, hasLength(1));
      final u = updates.single;

      expect(
        u.isAvailable,
        isFalse,
        reason:
            'the deciding field (ambient temperature) was never measured '
            'and no hazard signal is present, so there is no verdict to give. '
            'Got: ${u.assessment?.surfaceState.name} '
            'grip=${u.assessment?.gripFactor} '
            '"${u.assessment?.advisoryMessage}"',
      );
      expect(
        u.assessment,
        isNull,
        reason: 'an abstention carries no assessment',
      );
      expect(
        u.unavailableReason,
        isNotNull,
        reason: 'the caller is TOLD why, so an integrator can fix the feed',
      );
      // The signals are retained — this is not "the stream died", it is "the
      // stream is alive and cannot be classified".
      expect(u.signals, isNotNull);
    });

    test('precipitation + NO temperature → the fusion abstains, '
        'never a rain-typed wet road', () async {
      // Wipers at full and the rain sensor at 80%. Something is falling. The
      // vehicle publishes no temperature, so nothing on board can say whether
      // it is rain or snow — and 0.3.3 answered "rain".
      final updates = await drive(
        const VehicleConditionSignals(wiperIntensity: 5, rainIntensity: 80),
      );

      expect(updates, hasLength(1));
      final u = updates.single;

      expect(
        u.isAvailable,
        isFalse,
        reason:
            'only the temperature can tell snow from rain, and it was not '
            'measured. Got: ${u.assessment?.surfaceState.name} '
            '"${u.assessment?.advisoryMessage}"',
      );
    });

    test('the abstention is NOT an alarm — it cannot cry wolf', () async {
      final updates = await drive(
        const VehicleConditionSignals(wiperIntensity: 5, rainIntensity: 80),
      );
      final u = updates.single;
      // Nothing here asserts black ice, or any other hazard, out of absence.
      expect(u.assessment, isNull);
    });
  });

  group('POSITIVE hazard evidence still fires on partial data', () {
    test('low friction + NO temperature → black ice, as before', () async {
      final updates = await drive(
        const VehicleConditionSignals(roadFriction: 0.2),
      );
      final u = updates.single;
      expect(u.isAvailable, isTrue);
      expect(u.assessment!.surfaceState, RoadSurfaceState.blackIce);
    });

    test(
      'traction loss + NO temperature → black ice (the 0.3.2 rule)',
      () async {
        for (final s in const [
          VehicleConditionSignals(tcsEngaged: true),
          VehicleConditionSignals(absEngaged: true),
          VehicleConditionSignals(escEngaged: true),
        ]) {
          final u = (await drive(s)).single;
          expect(u.isAvailable, isTrue, reason: 'hazard must survive absence');
          expect(u.assessment!.surfaceState, RoadSurfaceState.blackIce);
        }
      },
    );
  });

  group('a MEASURED temperature classifies exactly as it did in 0.3.3', () {
    test(
      'snowfall at -5 °C → still slush/compacted snow, not abstention',
      () async {
        final u = (await drive(
          const VehicleConditionSignals(
            wiperIntensity: 5,
            rainIntensity: 80,
            airTempC: -5.0,
          ),
        )).single;
        expect(u.isAvailable, isTrue);
        expect(u.assessment!.surfaceState, RoadSurfaceState.compactedSnow);
      },
    );

    test('rain at +12 °C → still a wet road, not abstention', () async {
      final u = (await drive(
        const VehicleConditionSignals(wiperIntensity: 2, airTempC: 12.0),
      )).single;
      expect(u.isAvailable, isTrue);
      expect(u.assessment!.surfaceState, RoadSurfaceState.wet);
    });

    test('a measured dry cold road still earns its verdict', () async {
      final u = (await drive(
        const VehicleConditionSignals(roadFriction: 0.9, airTempC: -10.0),
      )).single;
      expect(u.isAvailable, isTrue);
      // -10 °C, no precipitation → residual ice, per the shared classifier.
      expect(u.assessment!.surfaceState, RoadSurfaceState.blackIce);
    });
  });

  group('the pure entry point carries the same rule', () {
    test('OrNull abstains on the two benign-from-absence shapes', () {
      expect(
        vehicleSignalsToWeatherConditionOrNull(
          const VehicleConditionSignals(tcsEngaged: false),
        ),
        isNull,
        reason: 'no precipitation, no hazard, no measured temperature',
      );
      expect(
        vehicleSignalsToWeatherConditionOrNull(
          const VehicleConditionSignals(wiperIntensity: 5, rainIntensity: 80),
        ),
        isNull,
        reason: 'snow and rain are indistinguishable without a temperature',
      );
    });

    test('OrNull returns the condition whenever a hazard IS asserted', () {
      final c = vehicleSignalsToWeatherConditionOrNull(
        const VehicleConditionSignals(roadFriction: 0.2),
      );
      expect(c, isNotNull);
      expect(c!.iceRisk, isTrue);
    });

    test(
      'OrNull is byte-identical to 0.3.3 when a temperature WAS measured',
      () {
        final ts = DateTime.utc(2026, 1, 1);
        for (final s in const [
          VehicleConditionSignals(wiperIntensity: 5, airTempC: -5.0),
          VehicleConditionSignals(rainIntensity: 90, airTempC: 12.0),
          VehicleConditionSignals(roadFriction: 0.9, airTempC: 0.0),
          VehicleConditionSignals(tcsEngaged: true, airTempC: 12.0),
        ]) {
          expect(
            vehicleSignalsToWeatherConditionOrNull(s, timestamp: ts),
            // ignore: deprecated_member_use_from_same_package
            equals(vehicleSignalsToWeatherCondition(s, timestamp: ts)),
            reason:
                'a measured temperature classifies exactly as it always did',
          );
        }
      },
    );

    test('the DEPRECATED entry point still fabricates — pinned so nobody '
        'mistakes it for fixed', () {
      // Retained deliberately: removing it would break every ^0.3.x build on
      // the next `pub get`, and a broken build is not a way to tell someone
      // their code is wrong. The @Deprecated notice is the channel.
      // ignore: deprecated_member_use_from_same_package
      final c = vehicleSignalsToWeatherCondition(
        const VehicleConditionSignals(wiperIntensity: 5),
      );
      expect(c.temperatureCelsius, 5.0);
      expect(c.precipType, PrecipitationType.rain);
      expect(c.isFreezing, isFalse);
    });

    test('measuredAmbientCelsius names absence and corruption alike', () {
      expect(measuredAmbientCelsius(const VehicleConditionSignals()), isNull);
      expect(
        measuredAmbientCelsius(
          const VehicleConditionSignals(airTempC: double.nan),
        ),
        isNull,
      );
      expect(
        measuredAmbientCelsius(
          const VehicleConditionSignals(airTempC: double.negativeInfinity),
        ),
        isNull,
      );
      expect(
        measuredAmbientCelsius(const VehicleConditionSignals(airTempC: -7.5)),
        -7.5,
      );
    });
  });

  group('a NON-FINITE temperature is not a measurement either', () {
    test('NaN temperature + traction loss → the ice concern is KEPT', () async {
      // 0.3.3 read `NaN <= kColdSlipCelsius` as false and therefore dismissed a
      // live skid as aquaplaning — the same downgrade 0.3.2 closed for `null`.
      final u = (await drive(
        const VehicleConditionSignals(tcsEngaged: true, airTempC: double.nan),
      )).single;
      expect(u.isAvailable, isTrue);
      expect(u.assessment!.surfaceState, RoadSurfaceState.blackIce);
    });

    test('NaN temperature + precipitation → abstain', () async {
      final u = (await drive(
        const VehicleConditionSignals(
          wiperIntensity: 4,
          airTempC: double.infinity,
        ),
      )).single;
      expect(u.isAvailable, isFalse);
    });
  });
}
