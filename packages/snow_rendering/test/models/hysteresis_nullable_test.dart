// HysteresisFilter with a NULLABLE T.
//
// Since 0.3.0 `RoadSurfaceState.fromCondition` can honestly return `null`
// ("cannot classify"), so consumers instantiate
// `HysteresisFilter<RoadSurfaceState?>` — and a `null` reading is then a VALID
// state, not the absence of one.
//
// Up to 0.2.7 the filter used `_current == null` as its "nothing seen yet"
// sentinel. With a nullable T that sentinel is ambiguous: every real `null`
// reading looks like "not seeded", so the seeding branch fires on every frame
// and the filter SILENTLY STOPS DEBOUNCING — accepting exactly the single-frame
// flicker it exists to suppress.
//
// That is a safety-relevant failure: the surface picture the driver sees would
// flicker between "unknown" and a hazard on every frame, which is how an alert
// becomes noise. These tests pin the fix (an explicit `_seeded` flag).

import 'package:snow_rendering/snow_rendering.dart';
import 'package:test/test.dart';

void main() {
  group('HysteresisFilter<T?> — a null reading is a state, not "unseeded"', () {
    test('a single flip away from null is HELD (debouncing still works)', () {
      final f = HysteresisFilter<RoadSurfaceState?>(); // window 3, threshold 2

      expect(f.add(null), isNull); // seed with "unknown"
      expect(f.hasCurrent, isTrue); // we HAVE seen a reading — it was null

      // One lone blackIce reading: below threshold, so it must be HELD.
      // With the old `_current == null` sentinel this returned blackIce
      // immediately, because `_current` was legitimately null and the filter
      // therefore believed it had never seen anything.
      expect(f.add(RoadSurfaceState.blackIce), isNull,
          reason: 'single-frame flip must be suppressed');

      // Second consecutive blackIce reaches the threshold → flip is allowed.
      expect(f.add(RoadSurfaceState.blackIce), RoadSurfaceState.blackIce);
    });

    test('hasCurrent distinguishes "nothing seen" from "saw an unknown"', () {
      final f = HysteresisFilter<RoadSurfaceState?>();
      expect(f.hasCurrent, isFalse); // nothing seen yet
      expect(f.current, isNull);

      f.add(null); // we have now seen a reading, whose value is null
      expect(f.hasCurrent, isTrue);
      expect(f.current, isNull);

      f.reset();
      expect(f.hasCurrent, isFalse);
    });

    test('a single flip TO null is also held', () {
      final f = HysteresisFilter<RoadSurfaceState?>();
      f.add(RoadSurfaceState.dry);
      f.add(RoadSurfaceState.dry);
      expect(f.current, RoadSurfaceState.dry);

      // The feed drops out for exactly one frame. Do not flap the scene.
      expect(f.add(null), RoadSurfaceState.dry);
      // It stays out → the unknown is accepted.
      expect(f.add(null), isNull);
    });

    test('non-nullable T is unaffected', () {
      final f = HysteresisFilter<RoadSurfaceState>();
      expect(f.hasCurrent, isFalse);
      expect(f.add(RoadSurfaceState.dry), RoadSurfaceState.dry);
      expect(f.hasCurrent, isTrue);
      expect(f.add(RoadSurfaceState.blackIce), RoadSurfaceState.dry); // held
      expect(f.add(RoadSurfaceState.blackIce), RoadSurfaceState.blackIce);
    });
  });
}
