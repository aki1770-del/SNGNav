// Vehicle-class overrides and the five threshold fields 0.11.6 does not
// check.
//
// These tests FAIL against navigation_safety_core 0.11.6 (git f626d93),
// whose override checker compares five of NavigationSafetyConfig's ten
// threshold fields. They state the behaviour a fix must produce. They do
// not fix it. Tests whose names end in "(holds on 0.11.6)" already pass
// and must keep passing after the fix.
//
// ## The invariant, field by field
//
// Checked by 0.11.6, unchanged here:
//   warningVisibilityMeters, warningTemperatureCelsius  may not decrease
//   safeScoreFloor, infoScoreFloor, warningScoreFloor   may not change
//
// Required here, and NOT checked by 0.11.6. Each may not change at all:
//   criticalVisibilityMeters, criticalTemperatureCelsius
//   infoVisibilityMeters, infoTemperatureCelsius
//   alertsPerMinuteCapOverride (null must stay null, NaN counts as a change)
//
// Why "may not change" rather than "may not decrease":
//
// - Critical thresholds. `AlertSeverity.critical` bypasses the
//   AlertDensityThrottle cap but still takes a slot in its rolling window,
//   so a raise that moves conditions into the critical tier can cause
//   OTHER hazards' warnings to be dropped (measured: two criticals, then a
//   warning, for ageingRural: the warning is dropped). A large enough raise
//   empties the warning band in a first-match evaluator. A cut makes the
//   critical alert later (measured: halving 80 m to 40 m turns 60 m from
//   critical to warning). Neither direction is safe by construction. The
//   library documentation already says these MUST NOT be modified.
// - Info thresholds. Info alerts share the throttle cap with warnings, so a
//   raise can cause a warning to be dropped (measured: two infos, then a
//   warning: dropped). A cut below the warning floor removes the info tier
//   entirely. This package itself lowered an info threshold in 0.3.0
//   because the higher value over-warned. Vehicle-class adjustments are
//   documented as tuning warning timing only.
// - The cap. A transform receives no DriverProfile, so any number it writes
//   replaces a per-profile default with a profile-blind constant (measured:
//   3.0 for an ageingRural driver whose default is 1.2). Loosening the cap
//   otherwise requires the driver's affirmative confirmation
//   (`forDriverContext`, `isHighConfidenceConfirmed`). NaN is accepted by
//   AlertDensityThrottle and drops every non-critical alert after the first;
//   0.0 makes the AlertDensityThrottle constructor throw.
//
// ## When one field of an override is refused
//
// At registration (`VehicleThresholdOverrides.validated`) the whole registry
// is still refused: it throws, at startup, where the developer can fix it.
//
// On the drive path (`applyOverrideForToken`) each violating field is reset
// to the baseline, every legal adjustment is kept, and every violating field
// is reported. The result is therefore always a config that a fully legal
// transform could have produced: warning floors at or above the baseline,
// every other field equal to it. Refusing the whole override instead
// discards a legal warning-floor raise because a DIFFERENT field was wrong,
// which makes that warning fire later than the valid part of the override
// asked for (measured: a +50 m raise refused alongside a relaxed
// temperature floor turns 320 m from warning to info for ageingRural).
//
// Refusals of the five newly checked fields are expected to reuse
// `VehicleOverrideInvariant.severityNotProfile`. A new enum value would stop
// an integrator's exhaustive `switch` over `VehicleOverrideInvariant` from
// compiling on an in-range upgrade.

import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  setUp(VehicleThresholdOverrides.resetRejectionReporting);
  tearDown(VehicleThresholdOverrides.resetRejectionReporting);

  // ── 1. Per field: registration refuses a change in EITHER direction ──

  group('validated() refuses a change to each field 0.11.6 does not check', () {
    for (final field in _uncheckedFields) {
      for (final move in field.moves) {
        test('${field.name}: ${move.label} throws ArgumentError', () {
          expect(
            () => VehicleThresholdOverrides.validated({'x': move.transform}),
            throwsA(isA<ArgumentError>()),
          );
        });
      }
    }

    test('alertsPerMinuteCapOverride: set to NaN throws ArgumentError', () {
      expect(
        () => VehicleThresholdOverrides.validated({
          'x': (b) => _copy(b, alertsPerMinuteCapOverride: double.nan),
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('alertsPerMinuteCapOverride: a transform that SCALES an existing cap '
        'is refused at registration too', () {
      // Every probe baseline in 0.11.6 carries a null cap, so a transform
      // that only rewrites a non-null cap would pass registration however
      // the comparison is written. Same class of gap as the constant-400
      // warning floor that the HIGH synthetic probe exists to catch.
      expect(
        () => VehicleThresholdOverrides.validated({
          'x': (b) => _copy(
            b,
            alertsPerMinuteCapOverride: b.alertsPerMinuteCapOverride == null
                ? null
                : b.alertsPerMinuteCapOverride! * 2,
          ),
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ── 2. Per field: the drive path resets it, reports it, never throws ──

  group('applyOverrideForToken resets each field 0.11.6 does not check', () {
    for (final field in _uncheckedFields) {
      for (final move in field.moves) {
        test('${field.name}: ${move.label} is not applied, is reported, and '
            'does not throw', () {
          final base = _ageingRural();
          final rejections = <VehicleOverrideRejection>[];
          final reg = VehicleThresholdOverrides({
            'x': move.transform,
          }, onRejected: rejections.add);

          late NavigationSafetyConfig result;
          expect(
            () => result = reg.applyOverrideForToken('x', base),
            returnsNormally,
          );
          expect(field.read(result), field.read(base));
          expect(
            rejections.map((r) => r.field),
            contains(field.name),
            reason: 'the refusal must be reported, naming the field',
          );
        });
      }
    }

    test(
      'alertsPerMinuteCapOverride: NaN is not applied and does not throw',
      () {
        final base = _ageingRural();
        final rejections = <VehicleOverrideRejection>[];
        final reg = VehicleThresholdOverrides({
          'x': (b) => _copy(b, alertsPerMinuteCapOverride: double.nan),
        }, onRejected: rejections.add);

        late NavigationSafetyConfig result;
        expect(
          () => result = reg.applyOverrideForToken('x', base),
          returnsNormally,
        );
        expect(result.alertsPerMinuteCapOverride, isNull);
        expect(rejections, isNotEmpty);
      },
    );

    test('alertsPerMinuteCapOverride: a scaled non-null cap is reset', () {
      final base = _copy(_ageingRural(), alertsPerMinuteCapOverride: 2.0);
      final reg = VehicleThresholdOverrides({
        'x': (b) => _copy(
          b,
          alertsPerMinuteCapOverride: b.alertsPerMinuteCapOverride! * 2,
        ),
      }, onRejected: (_) {});
      expect(
        reg.applyOverrideForToken('x', base).alertsPerMinuteCapOverride,
        2.0,
      );
    });

    test('a refusal of these fields reuses severityNotProfile, so an '
        "integrator's exhaustive switch keeps compiling", () {
      for (final field in _uncheckedFields) {
        final rejections = <VehicleOverrideRejection>[];
        VehicleThresholdOverrides(
          {'x': field.moves.first.transform},
          onRejected: rejections.add,
        ).applyOverrideForToken('x', _ageingRural());
        final forField = rejections.where((r) => r.field == field.name);
        expect(forField, isNotEmpty, reason: '${field.name} not reported');
        expect(
          forField.first.invariant,
          VehicleOverrideInvariant.severityNotProfile,
          reason: field.name,
        );
      }
    });
  });

  // ── 3. Through the factories a driver's config is actually built by ───

  group('the halved critical floor must not reach the evaluator', () {
    NavigationSafetyConfig halve(NavigationSafetyConfig b) =>
        _copy(b, criticalVisibilityMeters: b.criticalVisibilityMeters ~/ 2);

    test('forProfileWithContext at 60 km/h', () {
      const context = DrivingContext(
        speedMps: 60 / 3.6,
        vehicleClassToken: 'x',
      );
      final withOverride = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.ageingRural,
        context: context,
        vehicleOverrides: VehicleThresholdOverrides({
          'x': halve,
        }, onRejected: (_) {}),
      );
      final without = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.ageingRural,
        context: context,
      );
      expect(
        withOverride.criticalVisibilityMeters,
        without.criticalVisibilityMeters,
      );
      // What that means at 60 m in a first-match evaluator: still critical.
      expect(_visibilityTier(withOverride, 60), AlertSeverity.critical);
    });

    test('forDriverContext with impairedVisibility scaling applied after', () {
      const context = DrivingContext(
        speedMps: 60 / 3.6,
        vehicleClassToken: 'x',
      );
      const driver = DriverContext(
        profile: DriverProfile.ageingRural,
        state: DriverState.impairedVisibility,
      );
      final withOverride = NavigationSafetyConfig.forDriverContext(
        driver,
        environmentalContext: context,
        vehicleOverrides: VehicleThresholdOverrides({
          'x': halve,
        }, onRejected: (_) {}),
      );
      final without = NavigationSafetyConfig.forDriverContext(
        driver,
        environmentalContext: context,
      );
      expect(
        withOverride.criticalVisibilityMeters,
        without.criticalVisibilityMeters,
      );
    });
  });

  // ── 4. When one field is refused: reset that field, keep the rest ─────

  group('a refused field does not take the legal adjustments with it', () {
    test('a legal warning-floor raise is KEPT when an already-checked field '
        'is relaxed in the same transform', () {
      final base = _ageingRural();
      final reg = VehicleThresholdOverrides({
        'x': (b) => _copy(
          b,
          warningVisibilityMeters: b.warningVisibilityMeters + 50,
          warningTemperatureCelsius: b.warningTemperatureCelsius - 1,
        ),
      }, onRejected: (_) {});

      final result = reg.applyOverrideForToken('x', base);

      expect(result.warningTemperatureCelsius, base.warningTemperatureCelsius);
      expect(result.warningVisibilityMeters, base.warningVisibilityMeters + 50);
      // At 320 m that raise is the difference between a warning and info.
      expect(_visibilityTier(result, 320), AlertSeverity.warning);
    });

    test('a legal warning-floor raise is KEPT when the same transform also '
        'sets the cap', () {
      final base = _ageingRural();
      final reg = VehicleThresholdOverrides({
        'x': (b) => _copy(
          b,
          warningVisibilityMeters: b.warningVisibilityMeters + 50,
          alertsPerMinuteCapOverride: 3.0,
        ),
      }, onRejected: (_) {});

      final result = reg.applyOverrideForToken('x', base);

      expect(result.alertsPerMinuteCapOverride, isNull);
      expect(result.warningVisibilityMeters, base.warningVisibilityMeters + 50);
    });

    test('EVERY violating field is reported, not only the first', () {
      final rejections = <VehicleOverrideRejection>[];
      VehicleThresholdOverrides({
        'x': (b) => _copy(
          b,
          warningVisibilityMeters: b.warningVisibilityMeters - 150,
          criticalVisibilityMeters: b.criticalVisibilityMeters + 40,
        ),
      }, onRejected: rejections.add).applyOverrideForToken('x', _ageingRural());

      expect(
        rejections.map((r) => r.field).toSet(),
        containsAll(<String>[
          'warningVisibilityMeters',
          'criticalVisibilityMeters',
        ]),
      );
    });

    test('the report does not say the whole override was refused when a '
        'legal adjustment was applied', () {
      final rejections = <VehicleOverrideRejection>[];
      VehicleThresholdOverrides({
        'x': (b) => _copy(
          b,
          warningVisibilityMeters: b.warningVisibilityMeters + 50,
          warningTemperatureCelsius: b.warningTemperatureCelsius - 1,
        ),
      }, onRejected: rejections.add).applyOverrideForToken('x', _ageingRural());

      expect(rejections, isNotEmpty);
      for (final r in rejections) {
        expect(r.toString(), isNot(contains('REFUSED WHOLE')));
      }
    });

    test('relax a warning floor + tighten a critical floor: both fields come '
        'back at baseline (holds on 0.11.6)', () {
      // 0.11.6 returns the baseline for this transform because it refuses
      // the whole override. Under the invariant above it returns the same
      // config for a different reason: each of the two changes is refused
      // on its own. The critical tightening is NOT kept.
      final base = _ageingRural();
      final result = VehicleThresholdOverrides({
        'x': (b) => _copy(
          b,
          warningVisibilityMeters: b.warningVisibilityMeters - 150,
          criticalVisibilityMeters: b.criticalVisibilityMeters + 40,
        ),
      }, onRejected: (_) {}).applyOverrideForToken('x', base);
      expect(result, equals(base));
    });

    test('registration still refuses the WHOLE registry for a mixed '
        'transform (holds on 0.11.6)', () {
      expect(
        () => VehicleThresholdOverrides.validated({
          'x': (b) => _copy(
            b,
            warningVisibilityMeters: b.warningVisibilityMeters + 50,
            warningTemperatureCelsius: b.warningTemperatureCelsius - 1,
          ),
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('over a grid of transforms, the drive-path result is exactly the '
        'legal part of each transform', () {
      final failures = <String>[];
      var checked = 0;
      for (final profile in DriverProfile.values) {
        final base = NavigationSafetyConfig.forProfile(profile);
        for (final t in _transformGrid()) {
          checked++;
          final result = VehicleThresholdOverrides({
            'x': t.transform,
          }, onRejected: (_) {}).applyOverrideForToken('x', base);
          final expected = _legalPart(base, t.transform(base));
          if (result != expected) {
            failures.add(
              '${profile.name} ${t.label}: got ${_describe(result)} '
              'expected ${_describe(expected)}',
            );
          }
        }
      }
      expect(
        failures,
        isEmpty,
        reason:
            '${failures.length} of $checked cases differ; first: '
            '${failures.take(3).join(' | ')}',
      );
    });
  });

  // ── 5. The shipped kei-car default is untouched by all of the above ───

  group(
    'withKeiCarDefault is unchanged by the invariant (holds on 0.11.6)',
    () {
      test('forProfileWithContext: only +50 m and +1 °C on the warning floors, '
          'no refusal, across every profile and a grid of contexts', () {
        final rejections = <VehicleOverrideRejection>[];
        final kei = VehicleThresholdOverrides.withKeiCarDefault(
          onRejected: rejections.add,
        );
        for (final profile in DriverProfile.values) {
          for (final context in _contextGrid('kei-car')) {
            final without = NavigationSafetyConfig.forProfileWithContext(
              profile,
              context: context,
            );
            final withKei = NavigationSafetyConfig.forProfileWithContext(
              profile,
              context: context,
              vehicleOverrides: kei,
            );
            expect(
              withKei,
              equals(
                _copy(
                  without,
                  warningVisibilityMeters: without.warningVisibilityMeters + 50,
                  warningTemperatureCelsius:
                      without.warningTemperatureCelsius + 1,
                ),
              ),
              reason: '${profile.name} $context',
            );
          }
        }
        expect(rejections, isEmpty);
      });

      test('forDriverContext: the five fields are identical with and without '
          'the kei-car registry, for every profile and driver state', () {
        // Captured, not `fail()`ed: applyOverrideForToken swallows anything a
        // handler throws, so a `fail()` in onRejected could never fire.
        final rejections = <VehicleOverrideRejection>[];
        final kei = VehicleThresholdOverrides.withKeiCarDefault(
          onRejected: rejections.add,
        );
        for (final profile in DriverProfile.values) {
          for (final state in DriverState.values) {
            for (final context in _contextGrid('kei-car')) {
              final driver = DriverContext(profile: profile, state: state);
              final without = NavigationSafetyConfig.forDriverContext(
                driver,
                environmentalContext: context,
              );
              final withKei = NavigationSafetyConfig.forDriverContext(
                driver,
                environmentalContext: context,
                vehicleOverrides: kei,
              );
              for (final field in _uncheckedFields) {
                expect(
                  field.read(withKei),
                  field.read(without),
                  reason:
                      '${field.name} ${profile.name} ${state.name} $context',
                );
              }
            }
          }
        }
        expect(rejections, isEmpty);
      });
    },
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────

NavigationSafetyConfig _ageingRural() =>
    NavigationSafetyConfig.forProfile(DriverProfile.ageingRural);

const Object _keep = Object();

/// Field-wise copy. `alertsPerMinuteCapOverride` uses a sentinel so a test
/// can set it to null or NaN explicitly.
NavigationSafetyConfig _copy(
  NavigationSafetyConfig b, {
  double? safeScoreFloor,
  double? infoScoreFloor,
  double? warningScoreFloor,
  int? infoTemperatureCelsius,
  int? warningTemperatureCelsius,
  int? criticalTemperatureCelsius,
  int? infoVisibilityMeters,
  int? warningVisibilityMeters,
  int? criticalVisibilityMeters,
  Object? alertsPerMinuteCapOverride = _keep,
}) {
  return NavigationSafetyConfig(
    safeScoreFloor: safeScoreFloor ?? b.safeScoreFloor,
    infoScoreFloor: infoScoreFloor ?? b.infoScoreFloor,
    warningScoreFloor: warningScoreFloor ?? b.warningScoreFloor,
    infoTemperatureCelsius: infoTemperatureCelsius ?? b.infoTemperatureCelsius,
    warningTemperatureCelsius:
        warningTemperatureCelsius ?? b.warningTemperatureCelsius,
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

typedef _Transform = NavigationSafetyConfig Function(NavigationSafetyConfig);

class _Move {
  const _Move(this.label, this.transform);
  final String label;
  final _Transform transform;
}

class _Field {
  const _Field(this.name, this.read, this.moves);
  final String name;
  final Object? Function(NavigationSafetyConfig) read;
  final List<_Move> moves;
}

final List<_Field> _uncheckedFields = [
  _Field('criticalVisibilityMeters', (c) => c.criticalVisibilityMeters, [
    _Move(
      'halved',
      (b) =>
          _copy(b, criticalVisibilityMeters: b.criticalVisibilityMeters ~/ 2),
    ),
    _Move(
      'raised by 40 m',
      (b) =>
          _copy(b, criticalVisibilityMeters: b.criticalVisibilityMeters + 40),
    ),
  ]),
  _Field('criticalTemperatureCelsius', (c) => c.criticalTemperatureCelsius, [
    _Move(
      'lowered by 7 °C',
      (b) => _copy(
        b,
        criticalTemperatureCelsius: b.criticalTemperatureCelsius - 7,
      ),
    ),
    _Move(
      'raised by 3 °C',
      (b) => _copy(
        b,
        criticalTemperatureCelsius: b.criticalTemperatureCelsius + 3,
      ),
    ),
  ]),
  _Field('infoVisibilityMeters', (c) => c.infoVisibilityMeters, [
    _Move(
      'lowered below the warning floor',
      (b) => _copy(b, infoVisibilityMeters: b.warningVisibilityMeters - 100),
    ),
    _Move(
      'raised fourfold',
      (b) => _copy(b, infoVisibilityMeters: b.infoVisibilityMeters * 4),
    ),
  ]),
  _Field('infoTemperatureCelsius', (c) => c.infoTemperatureCelsius, [
    _Move(
      'lowered by 3 °C',
      (b) => _copy(b, infoTemperatureCelsius: b.infoTemperatureCelsius - 3),
    ),
    _Move(
      'raised by 5 °C',
      (b) => _copy(b, infoTemperatureCelsius: b.infoTemperatureCelsius + 5),
    ),
  ]),
  _Field('alertsPerMinuteCapOverride', (c) => c.alertsPerMinuteCapOverride, [
    _Move(
      'set to 0.5 (below every profile default)',
      (b) => _copy(b, alertsPerMinuteCapOverride: 0.5),
    ),
    _Move(
      'set to 10.0 (above every profile default)',
      (b) => _copy(b, alertsPerMinuteCapOverride: 10.0),
    ),
  ]),
];

/// First-match visibility classifier of the kind an integrator writes:
/// critical, then warning, then info, `<=` on each threshold.
AlertSeverity? _visibilityTier(NavigationSafetyConfig c, int meters) {
  if (meters <= c.criticalVisibilityMeters) return AlertSeverity.critical;
  if (meters <= c.warningVisibilityMeters) return AlertSeverity.warning;
  if (meters <= c.infoVisibilityMeters) return AlertSeverity.info;
  return null;
}

/// The legal part of [transformed] relative to [base]: each warning floor
/// kept only if it did not decrease, every other field taken from [base].
NavigationSafetyConfig _legalPart(
  NavigationSafetyConfig base,
  NavigationSafetyConfig transformed,
) {
  return NavigationSafetyConfig(
    safeScoreFloor: base.safeScoreFloor,
    infoScoreFloor: base.infoScoreFloor,
    warningScoreFloor: base.warningScoreFloor,
    infoTemperatureCelsius: base.infoTemperatureCelsius,
    warningTemperatureCelsius:
        transformed.warningTemperatureCelsius >= base.warningTemperatureCelsius
        ? transformed.warningTemperatureCelsius
        : base.warningTemperatureCelsius,
    criticalTemperatureCelsius: base.criticalTemperatureCelsius,
    infoVisibilityMeters: base.infoVisibilityMeters,
    warningVisibilityMeters:
        transformed.warningVisibilityMeters >= base.warningVisibilityMeters
        ? transformed.warningVisibilityMeters
        : base.warningVisibilityMeters,
    criticalVisibilityMeters: base.criticalVisibilityMeters,
    alertsPerMinuteCapOverride: base.alertsPerMinuteCapOverride,
  );
}

class _GridTransform {
  const _GridTransform(this.label, this.transform);
  final String label;
  final _Transform transform;
}

/// Every combination of -1 / 0 / +1 steps on the six environmental
/// thresholds, three cap values and two warning score floors.
Iterable<_GridTransform> _transformGrid() sync* {
  const steps = [-1, 0, 1];
  const caps = <Object?>[_keep, 1.0, double.nan];
  for (final wv in steps) {
    for (final wt in steps) {
      for (final cv in steps) {
        for (final ct in steps) {
          for (final iv in steps) {
            for (final it in steps) {
              for (final cap in caps) {
                for (final bumpScore in const [false, true]) {
                  yield _GridTransform(
                    'warnV$wv warnT$wt critV$cv critT$ct infoV$iv infoT$it '
                    'cap=${identical(cap, _keep) ? 'kept' : cap} '
                    'warnScore${bumpScore ? '+0.01' : ''}',
                    (b) => _copy(
                      b,
                      warningVisibilityMeters:
                          b.warningVisibilityMeters + 10 * wv,
                      warningTemperatureCelsius:
                          b.warningTemperatureCelsius + wt,
                      criticalVisibilityMeters:
                          b.criticalVisibilityMeters + 10 * cv,
                      criticalTemperatureCelsius:
                          b.criticalTemperatureCelsius + ct,
                      infoVisibilityMeters: b.infoVisibilityMeters + 10 * iv,
                      infoTemperatureCelsius: b.infoTemperatureCelsius + it,
                      alertsPerMinuteCapOverride: cap,
                      warningScoreFloor: bumpScore
                          ? b.warningScoreFloor + 0.01
                          : null,
                    ),
                  );
                }
              }
            }
          }
        }
      }
    }
  }
}

List<DrivingContext> _contextGrid(String token) => [
  for (final speed in const <double?>[null, 30 / 3.6, 80 / 3.6, 120 / 3.6])
    for (final air in const <List<double>?>[
      null,
      [0.9, -1.0],
      [0.5, 5.0],
    ])
      for (final sincePrecipitation in const <Duration?>[
        null,
        Duration(minutes: 10),
        Duration(hours: 6),
      ])
        DrivingContext(
          speedMps: speed,
          humidityRH: air?[0],
          ambientTempCelsius: air?[1],
          timeSincePrecipitation: sincePrecipitation,
          vehicleClassToken: token,
        ),
];

String _describe(NavigationSafetyConfig c) =>
    'vis ${c.criticalVisibilityMeters}/${c.warningVisibilityMeters}/'
    '${c.infoVisibilityMeters} temp ${c.criticalTemperatureCelsius}/'
    '${c.warningTemperatureCelsius}/${c.infoTemperatureCelsius} '
    'cap ${c.alertsPerMinuteCapOverride} warnScore ${c.warningScoreFloor}';
