// A refusal must name the rule the transform actually broke.
//
// Through 0.11.6 the override checker compared five fields, and its words
// were written for those five. Once the critical thresholds, the info
// thresholds and the alerts-per-minute cap override are refused as well, a
// message that still says only "move warning thresholds toward EARLIER
// warning, and preserve every score floor", or that explains a refused cap
// with "adjusts TIMING, never SEVERITY", sends the developer to fix a rule
// they did not break. These tests pin, for each of those five fields, that
// the registration error and the drive-path explanation both name that
// field's own rule.
//
// Tests whose names end in "(holds before this change)" pinned words that
// were already right, and must stay right.

import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  setUp(VehicleThresholdOverrides.resetRejectionReporting);
  tearDown(VehicleThresholdOverrides.resetRejectionReporting);

  group('validated() names the rule the transform broke', () {
    for (final change in _changes) {
      test('${change.field}: the error names the field and its rule', () {
        final message = _registrationMessage({'x': change.transform});
        expect(message, contains('overrides["x"]'));
        expect(message, contains(change.field));
        expect(message, contains(change.rule));
      });
    }

    test('the closing guidance lists every field an override may not '
        'change', () {
      final message = _registrationMessage({'x': _changes.first.transform});
      for (final words in const [
        'a score floor',
        'a critical threshold',
        'an info threshold',
        'the alerts-per-minute cap override',
      ]) {
        expect(message, contains(words));
      }
      expect(message, isNot(contains('must preserve every score floor')));
    });

    test('a transform that breaks two rules is told about both', () {
      final message = _registrationMessage({
        'x': (b) => _copy(
          b,
          warningVisibilityMeters: b.warningVisibilityMeters - 10,
          alertsPerMinuteCapOverride: 3.0,
        ),
      });
      expect(message, contains('warningVisibilityMeters'));
      expect(message, contains('may only make the warning fire EARLIER'));
      expect(message, contains('alertsPerMinuteCapOverride'));
      expect(message, contains('may not change the alerts-per-minute cap'));
    });

    test('a transform that drops a non-null cap to null is told to return '
        "the baseline's cap", () {
      // Every profile baseline carries a null cap, so this transform only
      // meets a non-null cap on a synthetic probe. The message must show
      // that probe's cap, or the developer cannot see what was changed.
      final message = _registrationMessage({
        'x': (b) => _copy(b, alertsPerMinuteCapOverride: null),
      });
      expect(message, contains('alertsPerMinuteCapOverride'));
      expect(message, contains('-> null'));
      expect(message, contains("return the baseline's value, null included"));
    });
  });

  group('the drive-path explanation names the rule the transform broke', () {
    for (final change in _changes) {
      test('${change.field}: explanation names its rule, not TIMING and '
          'SEVERITY', () {
        final rejection = _driveRejection(change);
        expect(rejection.explanation, contains(change.field));
        expect(rejection.explanation, contains(change.rule));
        expect(
          rejection.explanation,
          isNot(contains('adjusts TIMING, never SEVERITY')),
        );
        expect(rejection.toString(), contains(change.rule));
      });
    }

    test('a relaxed warning floor is still explained by the caution-add-only '
        'rule (holds before this change)', () {
      final rejections = <VehicleOverrideRejection>[];
      VehicleThresholdOverrides({
        'x': (b) =>
            _copy(b, warningVisibilityMeters: b.warningVisibilityMeters - 10),
      }, onRejected: rejections.add).applyOverrideForToken('x', _ageingRural());
      expect(
        rejections.single.explanation,
        contains('may only make the warning fire EARLIER, never later'),
      );
    });

    test('a changed score floor is still explained by the severity rule '
        '(holds before this change)', () {
      final rejections = <VehicleOverrideRejection>[];
      VehicleThresholdOverrides({
        'x': (b) => _copy(b, warningScoreFloor: b.warningScoreFloor + 0.01),
      }, onRejected: rejections.add).applyOverrideForToken('x', _ageingRural());
      expect(
        rejections.single.explanation,
        contains('adjusts TIMING, never SEVERITY'),
      );
    });
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────

class _Change {
  const _Change(this.field, this.rule, this.transform);
  final String field;
  final String rule;
  final NavigationSafetyConfig Function(NavigationSafetyConfig) transform;
}

final List<_Change> _changes = [
  _Change(
    'criticalVisibilityMeters',
    'may not change a critical threshold',
    (b) => _copy(b, criticalVisibilityMeters: b.criticalVisibilityMeters + 40),
  ),
  _Change(
    'criticalTemperatureCelsius',
    'may not change a critical threshold',
    (b) =>
        _copy(b, criticalTemperatureCelsius: b.criticalTemperatureCelsius - 7),
  ),
  _Change(
    'infoVisibilityMeters',
    'may not change an info threshold',
    (b) => _copy(b, infoVisibilityMeters: b.infoVisibilityMeters * 4),
  ),
  _Change(
    'infoTemperatureCelsius',
    'may not change an info threshold',
    (b) => _copy(b, infoTemperatureCelsius: b.infoTemperatureCelsius + 5),
  ),
  _Change(
    'alertsPerMinuteCapOverride',
    'may not change the alerts-per-minute cap',
    (b) => _copy(b, alertsPerMinuteCapOverride: 3.0),
  ),
];

NavigationSafetyConfig _ageingRural() =>
    NavigationSafetyConfig.forProfile(DriverProfile.ageingRural);

/// The message of the ArgumentError `validated` throws for [overrides].
String _registrationMessage(
  Map<String, NavigationSafetyConfig Function(NavigationSafetyConfig)>
  overrides,
) {
  try {
    VehicleThresholdOverrides.validated(overrides);
  } on ArgumentError catch (error) {
    return '${error.message}';
  }
  fail('validated() accepted a transform it must refuse');
}

/// The drive-path rejection reported for [change]'s own field.
VehicleOverrideRejection _driveRejection(_Change change) {
  final rejections = <VehicleOverrideRejection>[];
  VehicleThresholdOverrides({
    'x': change.transform,
  }, onRejected: rejections.add).applyOverrideForToken('x', _ageingRural());
  return rejections.singleWhere((r) => r.field == change.field);
}

const Object _keep = Object();

/// Field-wise copy. `alertsPerMinuteCapOverride` uses a sentinel so a test
/// can set it to null explicitly.
NavigationSafetyConfig _copy(
  NavigationSafetyConfig b, {
  double? warningScoreFloor,
  int? infoTemperatureCelsius,
  int? criticalTemperatureCelsius,
  int? infoVisibilityMeters,
  int? warningVisibilityMeters,
  int? criticalVisibilityMeters,
  Object? alertsPerMinuteCapOverride = _keep,
}) {
  return NavigationSafetyConfig(
    safeScoreFloor: b.safeScoreFloor,
    infoScoreFloor: b.infoScoreFloor,
    warningScoreFloor: warningScoreFloor ?? b.warningScoreFloor,
    infoTemperatureCelsius: infoTemperatureCelsius ?? b.infoTemperatureCelsius,
    warningTemperatureCelsius: b.warningTemperatureCelsius,
    criticalTemperatureCelsius:
        criticalTemperatureCelsius ?? b.criticalTemperatureCelsius,
    infoVisibilityMeters: infoVisibilityMeters ?? b.infoVisibilityMeters,
    warningVisibilityMeters:
        warningVisibilityMeters ?? b.warningVisibilityMeters,
    criticalVisibilityMeters:
        criticalVisibilityMeters ?? b.criticalVisibilityMeters,
    alertsPerMinuteCapOverride: identical(alertsPerMinuteCapOverride, _keep)
        ? b.alertsPerMinuteCapOverride
        : alertsPerMinuteCapOverride as double?,
  );
}
