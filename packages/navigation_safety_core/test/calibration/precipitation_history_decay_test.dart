import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('computeSurfaceMoistureFraction', () {
    test('zero time-since-precipitation returns 1.0', () {
      final f = computeSurfaceMoistureFraction(
        timeSincePrecipitation: Duration.zero,
        ambientCelsius: 5.0,
      );
      expect(f, closeTo(1.0, 1e-9));
    });

    test('one half-life (90 min default) returns ~0.5', () {
      final f = computeSurfaceMoistureFraction(
        timeSincePrecipitation: const Duration(minutes: 90),
        ambientCelsius: 5.0,
      );
      expect(f, closeTo(0.5, 1e-6));
    });

    test('four half-lives (360 min) returns ~0.0625', () {
      final f = computeSurfaceMoistureFraction(
        timeSincePrecipitation: const Duration(minutes: 360),
        ambientCelsius: 5.0,
      );
      expect(f, closeTo(0.0625, 1e-6));
    });

    test('custom half-life of 30 min, time of 60 min returns ~0.25', () {
      final f = computeSurfaceMoistureFraction(
        timeSincePrecipitation: const Duration(minutes: 60),
        ambientCelsius: 5.0,
        evaporationHalfLifeMinutes: 30.0,
      );
      expect(f, closeTo(0.25, 1e-6));
    });

    test('very long time clamps within [0, 1] without numerical issues', () {
      final f = computeSurfaceMoistureFraction(
        timeSincePrecipitation: const Duration(days: 7),
        ambientCelsius: 5.0,
      );
      expect(f, inInclusiveRange(0.0, 1.0));
      expect(f, lessThan(1e-9));
    });

    test('rejects non-positive half-life', () {
      expect(
        () => computeSurfaceMoistureFraction(
          timeSincePrecipitation: Duration.zero,
          ambientCelsius: 5.0,
          evaporationHalfLifeMinutes: 0.0,
        ),
        throwsArgumentError,
      );
    });

    test('rejects negative duration', () {
      expect(
        () => computeSurfaceMoistureFraction(
          timeSincePrecipitation: const Duration(minutes: -1),
          ambientCelsius: 5.0,
        ),
        throwsArgumentError,
      );
    });
  });
}
