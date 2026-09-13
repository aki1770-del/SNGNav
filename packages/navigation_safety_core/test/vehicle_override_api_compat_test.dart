// The refusal API an integrator already compiled against must keep
// compiling on an in-range upgrade.
//
// 0.11.7 refuses five more fields than 0.11.6 did. Each of those refusals
// could have been given a new `VehicleOverrideInvariant` value, or a new
// field on `VehicleOverrideRejection`. Either would break code an
// integrator wrote against 0.11.6: an exhaustive `switch` with no default
// stops compiling when an enum gains a value, and a constructor that gains
// a required parameter breaks every call site. A caret constraint takes the
// upgrade without asking, so the break would arrive unannounced.
//
// This file is the guard, and most of it is checked by the COMPILER: if the
// enum gains a value or the constructor changes its parameters, this file
// stops compiling and every test in the package fails to load with it.
//
// Honest bound: a new OPTIONAL named parameter on the constructor would
// still compile here, and so would a new public static member. Those are
// not breaking for a caller, and this file does not detect them.

import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

/// An integrator's exhaustive switch: no `default`, no wildcard.
String _handle(VehicleOverrideInvariant invariant) => switch (invariant) {
  VehicleOverrideInvariant.cautionAddOnly => 'caution',
  VehicleOverrideInvariant.severityNotProfile => 'severity',
  VehicleOverrideInvariant.transformThrew => 'threw',
};

void main() {
  test(
    'VehicleOverrideInvariant still has exactly the three 0.11.6 values',
    () {
      expect(VehicleOverrideInvariant.values.map((v) => v.name).toList(), [
        'cautionAddOnly',
        'severityNotProfile',
        'transformThrew',
      ]);
      expect(VehicleOverrideInvariant.values.map(_handle).toList(), [
        'caution',
        'severity',
        'threw',
      ]);
    },
  );

  test('VehicleOverrideRejection is still const-constructible with every '
      '0.11.6 parameter', () {
    final trace = StackTrace.current;
    const minimal = VehicleOverrideRejection(
      token: 't',
      field: 'criticalVisibilityMeters',
      invariant: VehicleOverrideInvariant.severityNotProfile,
    );
    final full = VehicleOverrideRejection(
      token: 't',
      field: '(transform)',
      invariant: VehicleOverrideInvariant.transformThrew,
      baselineValue: 1,
      rejectedValue: 2.5,
      error: StateError('x'),
      stackTrace: trace,
    );
    expect(minimal.baselineValue, isNull);
    expect(full.stackTrace, same(trace));
  });

  test('every field an override may not change is reported under a value '
      'the exhaustive switch above already handles', () {
    const unchangeable = [
      'safeScoreFloor',
      'infoScoreFloor',
      'warningScoreFloor',
      'criticalVisibilityMeters',
      'criticalTemperatureCelsius',
      'infoVisibilityMeters',
      'infoTemperatureCelsius',
      'alertsPerMinuteCapOverride',
    ];
    final base = NavigationSafetyConfig.forProfile(DriverProfile.ageingRural);
    final rejections = <VehicleOverrideRejection>[];
    VehicleThresholdOverrides({
      'x': (b) => NavigationSafetyConfig(
        safeScoreFloor: b.safeScoreFloor + 0.01,
        infoScoreFloor: b.infoScoreFloor + 0.01,
        warningScoreFloor: b.warningScoreFloor + 0.01,
        infoTemperatureCelsius: b.infoTemperatureCelsius + 1,
        warningTemperatureCelsius: b.warningTemperatureCelsius,
        criticalTemperatureCelsius: b.criticalTemperatureCelsius + 1,
        infoVisibilityMeters: b.infoVisibilityMeters + 10,
        warningVisibilityMeters: b.warningVisibilityMeters,
        criticalVisibilityMeters: b.criticalVisibilityMeters + 10,
        alertsPerMinuteCapOverride: 2.0,
      ),
    }, onRejected: rejections.add).applyOverrideForToken('x', base);

    expect(rejections.map((r) => r.field).toSet(), unchangeable.toSet());
    for (final r in rejections) {
      expect(_handle(r.invariant), 'severity', reason: r.field);
    }
  });
}
