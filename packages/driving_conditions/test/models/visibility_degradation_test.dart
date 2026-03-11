import 'package:driving_conditions/driving_conditions.dart';
import 'package:test/test.dart';

void main() {
  group('VisibilityDegradation.compute', () {
    test('0m visibility → max opacity and blur', () {
      final result = VisibilityDegradation.compute(0);
      expect(result.opacity, 0.9);
      expect(result.blurSigma, 10.0);
    });

    test('100m visibility → 0.9 opacity and 8 blur', () {
      final result = VisibilityDegradation.compute(100);
      expect(result.opacity, 0.9);
      expect(result.blurSigma, 8.0);
    });

    test('200m visibility → 0.8 opacity and 6 blur', () {
      final result = VisibilityDegradation.compute(200);
      expect(result.opacity, 0.8);
      expect(result.blurSigma, 6.0);
    });

    test('500m visibility → 0.5 opacity and zero blur', () {
      final result = VisibilityDegradation.compute(500);
      expect(result.opacity, 0.5);
      expect(result.blurSigma, 0.0);
    });

    test('1000m visibility → clear', () {
      final result = VisibilityDegradation.compute(1000);
      expect(result, VisibilityDegradation.clear);
    });

    test('negative visibility clamps to zero', () {
      final result = VisibilityDegradation.compute(-50);
      expect(result.opacity, 0.9);
      expect(result.blurSigma, 10.0);
    });

    test('very high visibility remains clear', () {
      final result = VisibilityDegradation.compute(10000);
      expect(result, VisibilityDegradation.clear);
    });
  });
}