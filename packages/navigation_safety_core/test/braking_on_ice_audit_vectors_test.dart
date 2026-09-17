// Tests for the braking-on-ice warning floor and the radiative-frost
// inference. They state what the floor must do; they do not control a vehicle,
// and the floor is an advisory warning threshold, not a stopping distance.
//
// Figures (each a recorded decision, not a source figure):
// - 5.5 m/s2: the dry-pavement default and the ceiling for a supplied value.
// - 0.981 m/s2 (0.10 x 9.81): used when no value is supplied and the readings
//   classify radiative-frost black ice. 0.10 is the lower edge of the ice
//   ranges in TRB Special Report 115, Table 1 ("Ice 0.1 to 0.2") and
//   土木技術資料 52-5 table 2 (氷路面 0.2～0.1), and the upper edge of VTI
//   meddelande 911A's "Wet black ice 0.05–0.10". Lower friction is reported
//   for wet or completely flat ice.
// - 0.4905 m/s2 (0.05 x 9.81): used for an unreadable supplied value.
// Friction numbers are skid-resistance measurements, not decelerations.
import 'dart:math' as math;

import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

const double inferredIce = 0.981;
const double dry = 5.5;
const double unreadable = 0.4905;

double rt(DriverProfile p) => switch (p) {
      DriverProfile.ageingRural => 2.5,
      DriverProfile.noviceUrban => 3.58,
      DriverProfile.snowZoneExperienced => 1.8,
      DriverProfile.professional => 1.5,
      DriverProfile.agriculturalForestry => 2.0,
      DriverProfile.foreignTouristSnowZone => 3.5,
    };

int expectedFloor(DriverProfile p, double v, double a) {
  final base = NavigationSafetyConfig.forProfile(p).warningVisibilityMeters;
  final kin = v * rt(p) + (v * v) / (2.0 * a);
  return math.max(base.toDouble(), kin).ceil();
}

int floorFor(DriverProfile p, double v, {double? decel, double? t, double? rh}) =>
    NavigationSafetyConfig.forProfileWithContext(
      p,
      context: DrivingContext(
        speedMps: v,
        brakingDecelerationMps2: decel,
        ambientTempCelsius: t,
        humidityRH: rh,
      ),
    ).warningVisibilityMeters;

double sanitised(double d) =>
    (!d.isFinite || d <= 0) ? unreadable : (d > dry ? dry : math.max(d, 1e-3));

void main() {
  const v100 = 100 / 3.6;

  group('a supplied value can only lengthen the floor', () {
    test('frost readings and a supplied dry figure: the inferred ice figure holds',
        () {
      expect(floorFor(DriverProfile.snowZoneExperienced, v100,
              decel: 5.5, t: 2.0, rh: 0.60),
          expectedFloor(DriverProfile.snowZoneExperienced, v100, inferredIce));
    });

    test('frost readings and a supplied lower value: the lower value holds', () {
      expect(floorFor(DriverProfile.snowZoneExperienced, v100,
              decel: 0.5, t: 2.0, rh: 0.60),
          expectedFloor(DriverProfile.snowZoneExperienced, v100, 0.5));
    });

    test('frost readings and an unreadable value: 0.4905, not the inference', () {
      expect(floorFor(DriverProfile.snowZoneExperienced, v100,
              decel: double.nan, t: 2.0, rh: 0.60),
          expectedFloor(DriverProfile.snowZoneExperienced, v100, unreadable));
    });

    test('grid: supplying any value never gives a shorter floor than leaving it out',
        () {
      final decels = <double>[
        double.nan, double.infinity, -1, 0, 1e-300, 0.3, 0.4905, 0.981, 1.5,
        3.0, 5.5, 9.0,
      ];
      final ctxs = <(double?, double?)>[
        (null, null), (2.0, 0.60), (10.0, 0.60), (-3.0, 0.80), (3.0, 0.70),
        (2.5, 0.95),
      ];
      var cells = 0;
      for (final p in DriverProfile.values) {
        for (var kmh = 0; kmh <= 200; kmh += 10) {
          final v = kmh / 3.6;
          for (final (t, rh) in ctxs) {
            final none = floorFor(p, v, t: t, rh: rh);
            final frost = t != null &&
                rh != null &&
                isRadiativeFrostBlackIce(
                    ambientCelsius: t, humidityRHPercent: rh * 100);
            for (final d in decels) {
              final f = floorFor(p, v, decel: d, t: t, rh: rh);
              expect(f, greaterThanOrEqualTo(none), reason: '$p $kmh $t $rh $d');
              final a = frost ? math.min(sanitised(d), inferredIce) : sanitised(d);
              expect(f, expectedFloor(p, v, a), reason: '$p $kmh $t $rh $d');
              cells++;
            }
          }
        }
      }
      expect(cells, 6 * 21 * 6 * 12);
    });
  });

  group('the inference uses 0.981 exactly where the classifier says frost',
      () {
    test('grid over ambient and humidity, every profile, 100 km/h', () {
      var frostCells = 0;
      for (final p in DriverProfile.values) {
        for (var ti = -100; ti <= 60; ti += 5) {
          final t = ti / 10.0;
          for (var h = 5; h <= 100; h += 5) {
            final frost = isRadiativeFrostBlackIce(
                ambientCelsius: t, humidityRHPercent: h.toDouble());
            if (frost) frostCells++;
            expect(floorFor(p, v100, t: t, rh: h / 100.0),
                expectedFloor(p, v100, frost ? inferredIce : dry),
                reason: '$p $t C $h %');
          }
        }
      }
      expect(frostCells, greaterThan(0));
    });

    test('forDriverContext carries the inference', () {
      final c = NavigationSafetyConfig.forDriverContext(
        const DriverContext(
            profile: DriverProfile.snowZoneExperienced,
            state: DriverState.alert),
        environmentalContext: const DrivingContext(
            speedMps: v100, ambientTempCelsius: 2.0, humidityRH: 0.60),
      );
      expect(c.warningVisibilityMeters,
          greaterThanOrEqualTo(
              expectedFloor(DriverProfile.snowZoneExperienced, v100, inferredIce)));
    });
  });
}
