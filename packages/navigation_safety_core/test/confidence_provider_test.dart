import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

class _StaticConfidenceProvider implements ConfidenceProvider {
  const _StaticConfidenceProvider({
    required Confidence? confidence,
    required bool isHighConfidenceConfirmed,
  }) : _confidence = confidence,
       _isHighConfidenceConfirmed = isHighConfidenceConfirmed;
  final Confidence? _confidence;
  final bool _isHighConfidenceConfirmed;
  @override
  Confidence? get confidence => _confidence;
  @override
  bool get isHighConfidenceConfirmed => _isHighConfidenceConfirmed;
}

void main() {
  // Use ageingRural so the per-profile default cap is well-defined and
  // distinct (alertsPerMinuteCap defaults vary per profile via
  // AlertDensityThrottle.defaultCapFor).
  const dc = DriverContext(
    profile: DriverProfile.ageingRural,
    state: DriverState.alert,
  );

  double effectiveCap(NavigationSafetyConfig cfg) =>
      cfg.effectiveAlertsPerMinuteCap(dc.profile);

  group('ConfidenceProvider — interface contract', () {
    test('returning a non-null confidence + flag surfaces them verbatim', () {
      const provider = _StaticConfidenceProvider(
        confidence: Confidence.high,
        isHighConfidenceConfirmed: true,
      );
      expect(provider.confidence, Confidence.high);
      expect(provider.isHighConfidenceConfirmed, isTrue);
    });

    test('returning null confidence is the absent-signal convention', () {
      const provider = _StaticConfidenceProvider(
        confidence: null,
        isHighConfidenceConfirmed: false,
      );
      expect(provider.confidence, isNull);
    });
  });

  group('Confidence.low — auto-tightens cap (caution-add)', () {
    test('low tightens cap below baseline', () {
      final base = NavigationSafetyConfig.forDriverContext(dc);
      final tightened = NavigationSafetyConfig.forDriverContext(
        dc,
        confidence: Confidence.low,
      );
      expect(effectiveCap(tightened), lessThan(effectiveCap(base)));
    });

    test('low cap floor at 1.0 alerts/min (no zero / negative cap)', () {
      final tightened = NavigationSafetyConfig.forDriverContext(
        dc,
        confidence: Confidence.low,
      );
      expect(effectiveCap(tightened), greaterThanOrEqualTo(1.0));
    });

    test('low does NOT modify warning visibility / temperature floors '
        '(cap-only adjustment)', () {
      final base = NavigationSafetyConfig.forDriverContext(dc);
      final tightened = NavigationSafetyConfig.forDriverContext(
        dc,
        confidence: Confidence.low,
      );
      expect(
        tightened.warningVisibilityMeters,
        equals(base.warningVisibilityMeters),
      );
      expect(
        tightened.warningTemperatureCelsius,
        equals(base.warningTemperatureCelsius),
      );
    });
  });

  group('Confidence.medium — no-op', () {
    test('medium produces identical cap to baseline', () {
      final base = NavigationSafetyConfig.forDriverContext(dc);
      final medium = NavigationSafetyConfig.forDriverContext(
        dc,
        confidence: Confidence.medium,
      );
      expect(
        medium.alertsPerMinuteCapOverride,
        equals(base.alertsPerMinuteCapOverride),
      );
    });
  });

  group('Confidence.high — driver-always-drives invariant', () {
    test('high WITHOUT confirmation: cap unchanged (treated as medium)', () {
      final base = NavigationSafetyConfig.forDriverContext(dc);
      final highUnconfirmed = NavigationSafetyConfig.forDriverContext(
        dc,
        confidence: Confidence.high,
        // isHighConfidenceConfirmed defaults to false.
      );
      expect(
        highUnconfirmed.alertsPerMinuteCapOverride,
        equals(base.alertsPerMinuteCapOverride),
      );
    });

    test(
      'high with isHighConfidenceConfirmed: false explicitly: cap unchanged',
      () {
        final base = NavigationSafetyConfig.forDriverContext(dc);
        final highUnconfirmed = NavigationSafetyConfig.forDriverContext(
          dc,
          confidence: Confidence.high,
          isHighConfidenceConfirmed: false,
        );
        expect(
          highUnconfirmed.alertsPerMinuteCapOverride,
          equals(base.alertsPerMinuteCapOverride),
        );
      },
    );

    test('high WITH confirmation: cap loosens above baseline', () {
      final base = NavigationSafetyConfig.forDriverContext(dc);
      final highConfirmed = NavigationSafetyConfig.forDriverContext(
        dc,
        confidence: Confidence.high,
        isHighConfidenceConfirmed: true,
      );
      expect(effectiveCap(highConfirmed), greaterThan(effectiveCap(base)));
    });

    test('high WITH confirmation does NOT modify warning floors '
        '(cap-only)', () {
      final base = NavigationSafetyConfig.forDriverContext(dc);
      final highConfirmed = NavigationSafetyConfig.forDriverContext(
        dc,
        confidence: Confidence.high,
        isHighConfidenceConfirmed: true,
      );
      expect(
        highConfirmed.warningVisibilityMeters,
        equals(base.warningVisibilityMeters),
      );
      expect(
        highConfirmed.warningTemperatureCelsius,
        equals(base.warningTemperatureCelsius),
      );
    });
  });

  group('Confidence preserves score-floor tiers (severity-not-profile)', () {
    test(
      'every (confidence, confirmation) combination preserves score floors',
      () {
        final base = NavigationSafetyConfig.forDriverContext(dc);
        for (final c in [Confidence.low, Confidence.medium, Confidence.high]) {
          for (final confirmed in [true, false]) {
            final result = NavigationSafetyConfig.forDriverContext(
              dc,
              confidence: c,
              isHighConfidenceConfirmed: confirmed,
            );
            expect(
              result.safeScoreFloor,
              equals(base.safeScoreFloor),
              reason: 'confidence=$c confirmed=$confirmed',
            );
            expect(
              result.infoScoreFloor,
              equals(base.infoScoreFloor),
              reason: 'confidence=$c confirmed=$confirmed',
            );
            expect(
              result.warningScoreFloor,
              equals(base.warningScoreFloor),
              reason: 'confidence=$c confirmed=$confirmed',
            );
          }
        }
      },
    );
  });
}
