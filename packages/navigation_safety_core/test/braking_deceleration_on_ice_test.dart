// The warning-visibility floor must be able to use a deceleration other
// than dry pavement's, and must not use dry pavement's where the same
// context already classifies radiative-frost black ice.
//
// Figures:
// - 5.5 m/s2: the calibration's existing default. No source read gives it;
//   a recorded decision. Used here only as the ceiling (the 0.11.7 answer).
// - 1.5 m/s2: a value supplied in some tests below. No source read gives
//   it. It equals friction ~0.153 x 9.81, inside Wallman and Astrom
//   (VTI meddelande 911A, 2001) "Black ice 0.15-0.30" at its lower edge
//   and the 土木技術資料 52-5 (2010) table-2 氷路面 0.2～0.1 range, and
//   above Ichihara and Mizoguchi (TRB SR 115) "around 0.1" for flat ice.
// - 0.981 m/s2: 0.10 x 9.81, the factory's figure where the readings
//   classify radiative-frost black ice, and the ceiling for a supplied
//   value there. A recorded decision: the lower edge of the ice ranges in
//   TRB SR 115 and 土木技術資料 52-5; wet or near-melting ice can be lower.
// - 0.4905 m/s2: 0.05 x 9.81, the lowest friction number in VTI 911A's
//   summary ("Wet black ice 0.05-0.10"). Used for an unreadable supplied
//   value.
// Friction numbers are skiddometer / skid-resistance measurements, not
// vehicle decelerations; a = mu x g is kinematics, and the mapping is a
// recorded decision.
//
// These are advisory warning thresholds. Nothing here controls a vehicle.
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

const double kmh100 = 100 / 3.6;

int floorFor(
  DriverProfile p, {
  required double speedMps,
  double? decel,
  double? ambient,
  double? rh,
  Duration? sincePrecip,
}) =>
    NavigationSafetyConfig.forProfileWithContext(
      p,
      context: DrivingContext(
        speedMps: speedMps,
        brakingDecelerationMps2: decel,
        ambientTempCelsius: ambient,
        humidityRH: rh,
        timeSincePrecipitation: sincePrecip,
      ),
    ).warningVisibilityMeters;

double kinematic(double rt, double v, double a) => rt * v + v * v / (2 * a);

double reactionTimeFor(DriverProfile p) => switch (p) {
      DriverProfile.ageingRural => 2.5,
      DriverProfile.noviceUrban => 3.58,
      DriverProfile.snowZoneExperienced => 1.8,
      DriverProfile.professional => 1.5,
      DriverProfile.agriculturalForestry => 2.0,
      DriverProfile.foreignTouristSnowZone => 3.5,
    };

void main() {
  group('supplied deceleration', () {
    test('a supplied 1.5 at 100 km/h gives 308 m, not the 200 m floor', () {
      expect(
        floorFor(DriverProfile.snowZoneExperienced,
            speedMps: kmh100, decel: 1.5),
        308,
      );
    });

    test('a value above dry pavement never shortens the 0.11.7 answer', () {
      final v = 150 / 3.6; // dry answer 233 m exceeds the 200 m baseline
      expect(floorFor(DriverProfile.snowZoneExperienced, speedMps: v), 233);
      expect(
        floorFor(DriverProfile.snowZoneExperienced, speedMps: v, decel: 9.0),
        233,
      );
    });

    for (final bad in <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
      0.0,
      -1.0,
    ]) {
      test('unreadable deceleration $bad does not throw and uses 0.4905', () {
        expect(
          floorFor(DriverProfile.snowZoneExperienced,
              speedMps: kmh100, decel: bad),
          kinematic(1.8, kmh100, 0.4905).ceil(),
        );
      });
    }

    test('a vanishing positive deceleration returns a finite floor', () {
      final f = floorFor(DriverProfile.snowZoneExperienced,
          speedMps: kmh100, decel: 1e-300);
      expect(f, kinematic(1.8, kmh100, 1e-3).ceil());
    });

    test('forDriverContext inherits the supplied deceleration', () {
      final c = NavigationSafetyConfig.forDriverContext(
        const DriverContext(
            profile: DriverProfile.snowZoneExperienced,
            state: DriverState.alert),
        environmentalContext: const DrivingContext(
            speedMps: kmh100, brakingDecelerationMps2: 1.5),
      );
      expect(c.warningVisibilityMeters, greaterThanOrEqualTo(308));
    });

    test('two contexts differing only in deceleration are not equal', () {
      expect(
        const DrivingContext(speedMps: 20, brakingDecelerationMps2: 1.5) ==
            const DrivingContext(speedMps: 20, brakingDecelerationMps2: 5.5),
        isFalse,
      );
    });

    test('withPercentHumidity carries the deceleration', () {
      expect(
        DrivingContext.withPercentHumidity(
                speedMps: 20, brakingDecelerationMps2: 1.5)
            .brakingDecelerationMps2,
        1.5,
      );
    });
  });

  group('absent deceleration', () {
    test('no frost evidence: the 0.11.7 dry answer is unchanged', () {
      expect(
          floorFor(DriverProfile.snowZoneExperienced, speedMps: kmh100), 200);
      expect(
        floorFor(DriverProfile.snowZoneExperienced,
            speedMps: kmh100, ambient: 10.0, rh: 0.60),
        200,
      );
    });

    test('frost-classified context uses the inferred ice figure (2.0 C, 60 % RH)',
        () {
      expect(
        isRadiativeFrostBlackIce(ambientCelsius: 2.0, humidityRHPercent: 60.0),
        isTrue,
      );
      // 444 m: 1.8 s x v + v^2 / (2 x 0.981), v = 100 km/h. 0.981 m/s2
      // (0.10 x 9.81) is the factory's inferred ice figure, a recorded
      // decision.
      expect(
        floorFor(DriverProfile.snowZoneExperienced,
            speedMps: kmh100, ambient: 2.0, rh: 0.60),
        444,
      );
    });

    test(
        'inside the frost classification a supplied value above the inferred '
        'figure does not shorten the floor', () {
      // The lower of the supplied 5.5 and 0.981 applies: the same floor as
      // leaving the value out.
      final withoutValue = floorFor(DriverProfile.snowZoneExperienced,
          speedMps: kmh100, ambient: 2.0, rh: 0.60);
      expect(
        floorFor(DriverProfile.snowZoneExperienced,
            speedMps: kmh100, ambient: 2.0, rh: 0.60, decel: 5.5),
        444,
      );
      expect(
        floorFor(DriverProfile.snowZoneExperienced,
            speedMps: kmh100, ambient: 2.0, rh: 0.60, decel: 5.5),
        withoutValue,
      );
    });

    test('frost inference does not wait on the residual-moisture decay', () {
      // 444 m, as without precipitation history: the inference does not
      // decay.
      expect(
        floorFor(DriverProfile.snowZoneExperienced,
            speedMps: kmh100,
            ambient: 2.0,
            rh: 0.60,
            sincePrecip: const Duration(hours: 6)),
        444,
      );
    });
  });

  group('invariant grid', () {
    test(
        'never below the 0.11.7 dry answer; never below kinematics at the '
        'effective deceleration', () {
      final decels = <double?>[
        null, 0.3, 0.4905, 1.0, 1.5, 3.0, 5.5, 9.0, //
        double.nan, double.infinity, -1.0, 0.0,
      ];
      var cells = 0;
      for (final p in DriverProfile.values) {
        final base = NavigationSafetyConfig.forProfile(p);
        for (var kmh = 0; kmh <= 200; kmh += 5) {
          final v = kmh / 3.6;
          final dry = NavigationSafetyConfig.forProfileWithContext(p,
                  context: DrivingContext(speedMps: v))
              .warningVisibilityMeters;
          for (final d in decels) {
            final f = floorFor(p, speedMps: v, decel: d);
            cells++;
            expect(f, greaterThanOrEqualTo(dry), reason: '$p $kmh $d');
            expect(f, greaterThanOrEqualTo(base.warningVisibilityMeters));
            final eff = (d == null)
                ? 5.5
                : (!d.isFinite || d <= 0)
                    ? 0.4905
                    : (d > 5.5 ? 5.5 : d);
            expect(
              f.toDouble(),
              greaterThanOrEqualTo(kinematic(reactionTimeFor(p), v, eff) - 1e-9),
              reason: '$p $kmh $d',
            );
          }
        }
      }
      expect(cells, 6 * 41 * 12);
    });
  });
}
