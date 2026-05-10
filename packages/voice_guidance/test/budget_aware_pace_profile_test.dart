/// Tests for BudgetAwarePaceProfile (0.6.0).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_guidance/voice_guidance.dart';

void main() {
  group('BudgetAwarePaceProfile', () {
    test('default values: minPace=0.7, maxPace=1.0, curve=linear', () {
      const profile = BudgetAwarePaceProfile();
      expect(profile.minPace, 0.7);
      expect(profile.maxPace, 1.0);
      expect(profile.curve, InterpolationCurve.linear);
    });

    test('paceForRemainingRatio linear: 1.0 -> maxPace, 0.0 -> minPace, '
        '0.5 -> midpoint', () {
      const profile = BudgetAwarePaceProfile();
      expect(profile.paceForRemainingRatio(1.0), 1.0);
      expect(profile.paceForRemainingRatio(0.0), 0.7);
      expect(profile.paceForRemainingRatio(0.5), closeTo(0.85, 1e-9));
    });

    test('paceForRemainingRatio clamps out-of-range inputs', () {
      const profile = BudgetAwarePaceProfile();
      expect(profile.paceForRemainingRatio(-0.5), 0.7);
      expect(profile.paceForRemainingRatio(1.5), 1.0);
    });

    test('smoothstep is monotone and matches boundaries; midpoint '
        'equals linear midpoint', () {
      const profile = BudgetAwarePaceProfile(
        curve: InterpolationCurve.smoothstep,
      );
      expect(profile.paceForRemainingRatio(0.0), 0.7);
      expect(profile.paceForRemainingRatio(1.0), 1.0);
      // smoothstep(0.5) = 0.5 by construction (3*0.25 - 2*0.125 = 0.5).
      expect(profile.paceForRemainingRatio(0.5), closeTo(0.85, 1e-9));
      // Monotone non-decreasing on the open interval.
      final a = profile.paceForRemainingRatio(0.25);
      final b = profile.paceForRemainingRatio(0.75);
      expect(a < b, isTrue);
    });

    test('caution-add-only invariant: maxPace > 1.0 fails assert '
        '(pace must never exceed engine-base)', () {
      expect(
        () => BudgetAwarePaceProfile(minPace: 0.7, maxPace: 1.5),
        throwsA(isA<AssertionError>()),
      );
    });

    test('minPace > maxPace fails assert', () {
      expect(
        () => BudgetAwarePaceProfile(minPace: 0.9, maxPace: 0.8),
        throwsA(isA<AssertionError>()),
      );
    });

    test('minPace <= 0 fails assert', () {
      expect(
        () => BudgetAwarePaceProfile(minPace: 0.0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => BudgetAwarePaceProfile(minPace: -0.1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('equality / Equatable props', () {
      const a = BudgetAwarePaceProfile();
      const b = BudgetAwarePaceProfile();
      const c = BudgetAwarePaceProfile(minPace: 0.5);
      expect(a, equals(b));
      expect(a == c, isFalse);
    });
  });
}
