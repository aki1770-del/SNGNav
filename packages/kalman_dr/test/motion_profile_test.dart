import 'package:kalman_dr/kalman_dr.dart';
import 'package:test/test.dart';

/// Feeds a carrier through a 90-degree corner and returns the filter's heading
/// after the turn. A profile that models fast turning tracks the corner; one
/// tuned for a car smooths through it.
double _headingAfterCorner(MotionProfile profile) {
  final kf = KalmanFilter(profile: profile);
  var t = DateTime.utc(2026, 1, 1);
  const lat = 39.72; // Akita
  var lon = 140.10;

  // Straight, heading east (90 deg), 3 m/s — a running pace.
  for (var i = 0; i < 5; i++) {
    kf.update(
      lat: lat,
      lon: lon,
      speed: 3.0,
      heading: 90.0,
      accuracy: 5.0,
      timestamp: t,
    );
    lon += 0.00003;
    t = t.add(const Duration(seconds: 1));
  }

  // The corner: the carrier turns to due north (0 deg) over two seconds.
  for (final h in [45.0, 0.0]) {
    kf.update(
      lat: lat,
      lon: lon,
      speed: 3.0,
      heading: h,
      accuracy: 5.0,
      timestamp: t,
    );
    t = t.add(const Duration(seconds: 1));
  }
  return kf.state.heading;
}

void main() {
  group('MotionProfile is a real tuning surface, not an ornament', () {
    test('roadVehicle is byte-for-byte the pre-0.6.2 constants', () {
      // If this drifts, an existing integration silently changes behaviour on
      // upgrade. That is the whole reason the parameter is optional.
      expect(MotionProfile.roadVehicle.asVector, [1e-10, 1e-10, 0.5, 1.0]);
    });

    test('the default constructor is roadVehicle — upgrading changes nothing',
        () {
      expect(KalmanFilter().profile, same(MotionProfile.roadVehicle));
    });

    test('⚑ pedestrian tracks a 90-degree corner that roadVehicle smooths away',
        () {
      final road = _headingAfterCorner(MotionProfile.roadVehicle);
      final ped = _headingAfterCorner(MotionProfile.pedestrian);

      // Truth after the corner is 0 deg (due north). Lower residual = better.
      final roadError = (road - 0.0).abs();
      final pedError = (ped - 0.0).abs();

      expect(
        pedError,
        lessThan(roadError),
        reason:
            'the pedestrian profile exists to stop the filter cutting corners; '
            'if it does not track the turn better it is doing nothing. '
            'road=$road ped=$ped',
      );
    });

    test('CONTROL: on a STRAIGHT run the two profiles agree closely', () {
      // If the profiles differed everywhere, the corner test above would prove
      // only "the numbers are different", not "it tracks turns better".
      double straightHeading(MotionProfile p) {
        final kf = KalmanFilter(profile: p);
        var t = DateTime.utc(2026, 1, 1);
        var lon = 140.10;
        for (var i = 0; i < 6; i++) {
          kf.update(
            lat: 39.72,
            lon: lon,
            speed: 3.0,
            heading: 90.0,
            accuracy: 5.0,
            timestamp: t,
          );
          lon += 0.00003;
          t = t.add(const Duration(seconds: 1));
        }
        return kf.state.heading;
      }

      expect(
        (straightHeading(MotionProfile.roadVehicle) -
                straightHeading(MotionProfile.pedestrian))
            .abs(),
        lessThan(1.0),
        reason: 'with nothing to turn through, the profiles should agree',
      );
    });

    test('a non-positive process-noise term is refused, not silently absorbed',
        () {
      expect(
        () => KalmanFilter(
          profile: const MotionProfile(
            latVariancePerSecond: 0,
            lonVariancePerSecond: 1e-10,
            speedVariancePerSecond: 0.5,
            headingVariancePerSecond: 1.0,
          ),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('isValid rejects non-finite and non-positive terms', () {
      expect(MotionProfile.roadVehicle.isValid, isTrue);
      expect(MotionProfile.pedestrian.isValid, isTrue);
      expect(
        const MotionProfile(
          latVariancePerSecond: double.nan,
          lonVariancePerSecond: 1e-10,
          speedVariancePerSecond: 0.5,
          headingVariancePerSecond: 1.0,
        ).isValid,
        isFalse,
      );
    });

    test('the pedestrian profile SAYS it is derived, not measured', () {
      // The label is load-bearing: a reasoned guess presented as a calibration
      // would read as a warrant this package cannot issue.
      expect(MotionProfile.pedestrian.name, contains('not measured'));
    });
  });
}
