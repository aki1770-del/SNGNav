import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

class _StaticSessionStateProvider implements SessionStateProvider {
  const _StaticSessionStateProvider(this._state);
  final SessionState? _state;
  @override
  SessionState? get sessionState => _state;
}

void main() {
  group('SessionStateProvider — interface contract', () {
    test('returning a non-null state surfaces it verbatim', () {
      const state = SessionState(
        consecutiveDrivingDays: 5,
        cumulativeFatigue: CumulativeFatigueClass.accumulated,
      );
      const provider = _StaticSessionStateProvider(state);
      expect(provider.sessionState, equals(state));
    });

    test('returning null is the absent-signal convention', () {
      const provider = _StaticSessionStateProvider(null);
      expect(provider.sessionState, isNull);
    });
  });

  group('SessionState — value class', () {
    test('equality + props are stable across same inputs', () {
      const a = SessionState(
        consecutiveDrivingDays: 3,
        cumulativeFatigue: CumulativeFatigueClass.mild,
      );
      const b = SessionState(
        consecutiveDrivingDays: 3,
        cumulativeFatigue: CumulativeFatigueClass.mild,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality on differing consecutiveDrivingDays', () {
      const a = SessionState(
        consecutiveDrivingDays: 3,
        cumulativeFatigue: CumulativeFatigueClass.mild,
      );
      const b = SessionState(
        consecutiveDrivingDays: 4,
        cumulativeFatigue: CumulativeFatigueClass.mild,
      );
      expect(a, isNot(equals(b)));
    });

    test('inequality on differing cumulativeFatigue class', () {
      const a = SessionState(
        consecutiveDrivingDays: 3,
        cumulativeFatigue: CumulativeFatigueClass.mild,
      );
      const b = SessionState(
        consecutiveDrivingDays: 3,
        cumulativeFatigue: CumulativeFatigueClass.accumulated,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('SessionState composition with forDriverContext — '
      'cumulative-fatigue lift (caution-add-only)', () {
    const dc = DriverContext(
      profile: DriverProfile.snowZoneExperienced,
      state: DriverState.alert,
    );

    test('rested produces no warningVisibility lift', () {
      final base = NavigationSafetyConfig.forDriverContext(dc);
      final lifted = NavigationSafetyConfig.forDriverContext(
        dc,
        sessionState: const SessionState(
          consecutiveDrivingDays: 1,
          cumulativeFatigue: CumulativeFatigueClass.rested,
        ),
      );
      expect(
        lifted.warningVisibilityMeters,
        equals(base.warningVisibilityMeters),
      );
    });

    test('mild raises warningVisibilityMeters above baseline', () {
      final base = NavigationSafetyConfig.forDriverContext(dc);
      final lifted = NavigationSafetyConfig.forDriverContext(
        dc,
        sessionState: const SessionState(
          consecutiveDrivingDays: 3,
          cumulativeFatigue: CumulativeFatigueClass.mild,
        ),
      );
      expect(
        lifted.warningVisibilityMeters,
        greaterThan(base.warningVisibilityMeters),
      );
    });

    test('severe lift > accumulated lift > mild lift > rested lift '
        '(monotonic caution-add)', () {
      final rested = NavigationSafetyConfig.forDriverContext(
        dc,
        sessionState: const SessionState(
          consecutiveDrivingDays: 0,
          cumulativeFatigue: CumulativeFatigueClass.rested,
        ),
      );
      final mild = NavigationSafetyConfig.forDriverContext(
        dc,
        sessionState: const SessionState(
          consecutiveDrivingDays: 3,
          cumulativeFatigue: CumulativeFatigueClass.mild,
        ),
      );
      final accumulated = NavigationSafetyConfig.forDriverContext(
        dc,
        sessionState: const SessionState(
          consecutiveDrivingDays: 5,
          cumulativeFatigue: CumulativeFatigueClass.accumulated,
        ),
      );
      final severe = NavigationSafetyConfig.forDriverContext(
        dc,
        sessionState: const SessionState(
          consecutiveDrivingDays: 9,
          cumulativeFatigue: CumulativeFatigueClass.severe,
        ),
      );
      expect(
        rested.warningVisibilityMeters,
        lessThanOrEqualTo(mild.warningVisibilityMeters),
      );
      expect(
        mild.warningVisibilityMeters,
        lessThan(accumulated.warningVisibilityMeters),
      );
      expect(
        accumulated.warningVisibilityMeters,
        lessThan(severe.warningVisibilityMeters),
      );
    });

    test('session-state preserves score-floor tiers '
        '(severity-not-profile)', () {
      final base = NavigationSafetyConfig.forDriverContext(dc);
      final lifted = NavigationSafetyConfig.forDriverContext(
        dc,
        sessionState: const SessionState(
          consecutiveDrivingDays: 9,
          cumulativeFatigue: CumulativeFatigueClass.severe,
        ),
      );
      expect(lifted.safeScoreFloor, base.safeScoreFloor);
      expect(lifted.infoScoreFloor, base.infoScoreFloor);
      expect(lifted.warningScoreFloor, base.warningScoreFloor);
    });

    test('null sessionState falls back to baseline (no effect)', () {
      final base = NavigationSafetyConfig.forDriverContext(dc);
      final passed = NavigationSafetyConfig.forDriverContext(
        dc,
        sessionState: null,
      );
      expect(
        passed.warningVisibilityMeters,
        equals(base.warningVisibilityMeters),
      );
    });
  });
}
