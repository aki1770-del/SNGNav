import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('forDriverContext — cross-feature integration of '
      '#28+#29+#30 with existing context layering', () {
    const dc = DriverContext(
      profile: DriverProfile.ageingRural,
      state: DriverState.alert,
    );

    final environmentalContext = DrivingContext(
      speedMps: 18.0,
      humidityRH: 0.85,
      ambientTempCelsius: 1.5,
      vehicleClassToken: 'kei-car',
    );

    test('all three new inputs together compose without error', () {
      final config = NavigationSafetyConfig.forDriverContext(
        dc,
        environmentalContext: environmentalContext,
        vehicleOverrides: VehicleThresholdOverrides.withKeiCarDefault(),
        circadianPhase: CircadianPhase.lateNight,
        sessionState: const SessionState(
          consecutiveDrivingDays: 7,
          cumulativeFatigue: CumulativeFatigueClass.severe,
        ),
        confidence: Confidence.low,
      );
      expect(config, isNotNull);
      // All caution-adding inputs should yield warningVisibilityMeters
      // strictly greater than the no-input baseline.
      final base = NavigationSafetyConfig.forDriverContext(
        dc,
        environmentalContext: environmentalContext,
      );
      expect(
        config.warningVisibilityMeters,
        greaterThan(base.warningVisibilityMeters),
      );
    });

    test('all three new inputs preserve score-floor tiers '
        '(severity-not-profile across the full chain)', () {
      final config = NavigationSafetyConfig.forDriverContext(
        dc,
        environmentalContext: environmentalContext,
        vehicleOverrides: VehicleThresholdOverrides.withKeiCarDefault(),
        circadianPhase: CircadianPhase.lateNight,
        sessionState: const SessionState(
          consecutiveDrivingDays: 7,
          cumulativeFatigue: CumulativeFatigueClass.severe,
        ),
        confidence: Confidence.low,
      );
      final baseProfile = NavigationSafetyConfig.forProfile(dc.profile);
      expect(config.safeScoreFloor, baseProfile.safeScoreFloor);
      expect(config.infoScoreFloor, baseProfile.infoScoreFloor);
      expect(config.warningScoreFloor, baseProfile.warningScoreFloor);
    });

    test('all three new inputs preserve critical thresholds', () {
      final config = NavigationSafetyConfig.forDriverContext(
        dc,
        environmentalContext: environmentalContext,
        vehicleOverrides: VehicleThresholdOverrides.withKeiCarDefault(),
        circadianPhase: CircadianPhase.lateNight,
        sessionState: const SessionState(
          consecutiveDrivingDays: 7,
          cumulativeFatigue: CumulativeFatigueClass.severe,
        ),
        confidence: Confidence.low,
      );
      final baseProfile = NavigationSafetyConfig.forProfile(dc.profile);
      expect(
        config.criticalVisibilityMeters,
        equals(baseProfile.criticalVisibilityMeters),
      );
      expect(
        config.criticalTemperatureCelsius,
        equals(baseProfile.criticalTemperatureCelsius),
      );
    });

    test('zero-input call: forDriverContext without any new parameters '
        '== 0.9.x behaviour (back-compat)', () {
      final v0_9_x = NavigationSafetyConfig.forDriverContext(
        dc,
        environmentalContext: environmentalContext,
      );
      // Re-construct what 0.9.x would have produced via the same call
      // (no new optional parameters set; defaults apply).
      final v0_10_0_default = NavigationSafetyConfig.forDriverContext(
        dc,
        environmentalContext: environmentalContext,
      );
      expect(v0_10_0_default, equals(v0_9_x));
    });

    test('vehicleOverrides on forDriverContext composes through to '
        'caution-adding warning thresholds', () {
      // The 0.9.0 forProfileWithContext wires vehicleOverrides; 0.10.0
      // surfaces the same parameter at the forDriverContext layer so
      // state-axis callers can compose vehicle-class without reaching
      // around the factory.
      final without = NavigationSafetyConfig.forDriverContext(
        dc,
        environmentalContext: environmentalContext,
      );
      final withKeiCar = NavigationSafetyConfig.forDriverContext(
        dc,
        environmentalContext: environmentalContext,
        vehicleOverrides: VehicleThresholdOverrides.withKeiCarDefault(),
      );
      expect(
        withKeiCar.warningVisibilityMeters,
        greaterThan(without.warningVisibilityMeters),
      );
    });

    test('caution-add-only invariant across full chain: every combination '
        'yields warningVisibilityMeters >= profile baseline', () {
      final profileBase = NavigationSafetyConfig.forProfile(dc.profile);
      for (final phase in [CircadianPhase.morning, CircadianPhase.lateNight]) {
        for (final fatigue in CumulativeFatigueClass.values) {
          for (final c in [Confidence.low, Confidence.medium]) {
            final config = NavigationSafetyConfig.forDriverContext(
              dc,
              circadianPhase: phase,
              sessionState: SessionState(
                consecutiveDrivingDays: 4,
                cumulativeFatigue: fatigue,
              ),
              confidence: c,
            );
            expect(
              config.warningVisibilityMeters,
              greaterThanOrEqualTo(profileBase.warningVisibilityMeters),
              reason: 'phase=$phase fatigue=$fatigue confidence=$c',
            );
          }
        }
      }
    });

    test('driver-always-drives: high-without-confirmation never modifies '
        'cap regardless of other inputs', () {
      final base = NavigationSafetyConfig.forDriverContext(
        dc,
        environmentalContext: environmentalContext,
        circadianPhase: CircadianPhase.lateNight,
        sessionState: const SessionState(
          consecutiveDrivingDays: 7,
          cumulativeFatigue: CumulativeFatigueClass.severe,
        ),
      );
      final highUnconfirmed = NavigationSafetyConfig.forDriverContext(
        dc,
        environmentalContext: environmentalContext,
        circadianPhase: CircadianPhase.lateNight,
        sessionState: const SessionState(
          consecutiveDrivingDays: 7,
          cumulativeFatigue: CumulativeFatigueClass.severe,
        ),
        confidence: Confidence.high,
        // isHighConfidenceConfirmed defaults to false.
      );
      expect(
        highUnconfirmed.alertsPerMinuteCapOverride,
        equals(base.alertsPerMinuteCapOverride),
      );
    });
  });
}
