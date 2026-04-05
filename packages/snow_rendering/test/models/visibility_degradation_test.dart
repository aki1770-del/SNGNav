import 'package:snow_rendering/snow_rendering.dart';
import 'package:test/test.dart';

void main() {
  group('VisibilityDegradation.compute', () {
    test('clear constant: opacity=0.0, blur=0.0', () {
      expect(VisibilityDegradation.clear.opacity, 0.0);
      expect(VisibilityDegradation.clear.blurSigma, 0.0);
    });

    test('1000m visibility → opacity 0.0, blur 0.0 (clear threshold)', () {
      final v = VisibilityDegradation.compute(1000);
      expect(v.opacity, 0.0);
      expect(v.blurSigma, 0.0);
    });

    test('10000m visibility → fully clear (opacity 0.0, blur 0.0)', () {
      final v = VisibilityDegradation.compute(10000);
      expect(v.opacity, 0.0);
      expect(v.blurSigma, 0.0);
    });

    test('100m visibility → opacity 0.9, blur 8.0 (dense fog)', () {
      final v = VisibilityDegradation.compute(100);
      expect(v.opacity, closeTo(0.9, 0.001));
      expect(v.blurSigma, closeTo(8.0, 0.001));
    });

    test('0m visibility → opacity 0.9, blur 10.0 (whiteout)', () {
      final v = VisibilityDegradation.compute(0);
      expect(v.opacity, 0.9);
      expect(v.blurSigma, 10.0);
    });

    test('negative visibility → clamped to 0 (whiteout)', () {
      final v = VisibilityDegradation.compute(-100);
      expect(v.opacity, 0.9);
      expect(v.blurSigma, 10.0);
    });

    test('500m visibility → blur 0.0 (blur threshold boundary)', () {
      final v = VisibilityDegradation.compute(500);
      expect(v.blurSigma, 0.0);
    });

    test('499m visibility → blur > 0 (just below blur threshold)', () {
      final v = VisibilityDegradation.compute(499);
      expect(v.blurSigma, greaterThan(0.0));
    });

    test('opacity never exceeds 0.9', () {
      for (final meters in [0.0, 10.0, 50.0, 100.0, 200.0]) {
        final v = VisibilityDegradation.compute(meters);
        expect(v.opacity, lessThanOrEqualTo(0.9),
            reason: 'opacity exceeded 0.9 at ${meters}m');
      }
    });

    test('opacity is 0.0 at >= 1000m', () {
      for (final meters in [1000.0, 2000.0, 5000.0, 10000.0]) {
        final v = VisibilityDegradation.compute(meters);
        expect(v.opacity, 0.0,
            reason: 'opacity non-zero at ${meters}m');
      }
    });

    test('less visibility → more opacity (monotonic)', () {
      final v1000 = VisibilityDegradation.compute(1000);
      final v500 = VisibilityDegradation.compute(500);
      final v100 = VisibilityDegradation.compute(100);
      expect(v500.opacity, greaterThanOrEqualTo(v1000.opacity));
      expect(v100.opacity, greaterThan(v500.opacity));
    });

    test('less visibility → more blur (monotonic below 500m)', () {
      final v400 = VisibilityDegradation.compute(400);
      final v200 = VisibilityDegradation.compute(200);
      final v50 = VisibilityDegradation.compute(50);
      expect(v200.blurSigma, greaterThan(v400.blurSigma));
      expect(v50.blurSigma, greaterThan(v200.blurSigma));
    });

    test('equality — same visibility produces equal result', () {
      final a = VisibilityDegradation.compute(300);
      final b = VisibilityDegradation.compute(300);
      expect(a, b);
    });
  });
}
