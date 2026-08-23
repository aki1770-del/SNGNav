// The safety cap is documented and USER-FACING as "~500m". This suite holds it
// to that number at the latitudes the product exists for.
//
// The defect this catches: `accuracyMetres` converts degree² variance to metres
// weighting longitude by cos(lat), while `isAccuracyExceeded` compared the RAW
// unweighted `P[0][0] + P[1][1]` against a threshold calibrated at the equator.
// The two agree ONLY at the equator, so the cap fired EARLY everywhere else —
// and progressively earlier the further north, i.e. worst exactly where snow is.
import 'package:kalman_dr/kalman_dr.dart';
import 'package:test/test.dart';

/// Run prediction-only (GPS lost) until the filter says the cap is exceeded,
/// and report the accuracy IT ITSELF reports at that moment.
double stopRadiusAt(double lat) {
  final kf = KalmanFilter.withState(
    latitude: lat,
    longitude: 140.1,
    speed: 16.7,
    heading: 90.0,
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
  );
  for (var t = 1; t < 100000; t++) {
    kf.predict(Duration(seconds: t));
    if (kf.isAccuracyExceeded) return kf.accuracyMetres;
  }
  fail('cap never fired at lat=$lat');
}

void main() {
  group('the ~500m safety cap is 500m at every latitude, not just the equator', () {
    // Akita is HER anchor. Tromso is the northern extreme of the snow band.
    const sites = <String, double>{
      'Equator': 0.0,
      'Nagoya': 35.17,
      'Akita (HER)': 39.72,
      'Sapporo': 43.06,
      'Tromso': 69.65,
    };

    // The cap must never fire EARLY — a premature stop takes HER dot away
    // sooner than the package promises. It fires on the first predict step
    // that crosses the cap, so it lands at or just past it, never before.
    for (final e in sites.entries) {
      test('${e.key} (lat ${e.value}) never stops before the 500m cap', () {
        final r = stopRadiusAt(e.value);
        expect(
          r,
          greaterThanOrEqualTo(KalmanFilter.maxAccuracyMetres),
          reason:
              '${e.key}: the cap fired at ${r.toStringAsFixed(1)}m, short of '
              'the ${KalmanFilter.maxAccuracyMetres}m the package documents '
              'and the app displays. A cap that fires early takes HER dot away '
              'sooner than promised.',
        );
      });
    }

    test('⚑ THE DEFECT: the stop radius is IDENTICAL at every latitude', () {
      final radii = sites.values.map(stopRadiusAt).toList();
      final lo = radii.reduce((a, b) => a < b ? a : b);
      final hi = radii.reduce((a, b) => a > b ? a : b);
      expect(
        hi - lo,
        lessThan(1.0),
        reason:
            'stop radii across ${sites.keys.join(", ")} span '
            '${lo.toStringAsFixed(1)}m..${hi.toStringAsFixed(1)}m. They must '
            'not differ: a cap that weakens with latitude is weakest exactly '
            'where the snow is.',
      );
    });

    test('the cap does not degrade with latitude', () {
      final eq = stopRadiusAt(0.0);
      final north = stopRadiusAt(69.65);
      expect(
        north / eq,
        closeTo(1.0, 0.1),
        reason:
            'stop radius at 69.65N is ${north.toStringAsFixed(1)}m vs '
            '${eq.toStringAsFixed(1)}m at the equator — the instrument gets '
            'weaker the further into the snow band it goes.',
      );
    });
  });
}
