import 'dart:async';

import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('VehicleThresholdOverrides — registry construction + lookup', () {
    test('default constructor stores the supplied map', () {
      final reg = VehicleThresholdOverrides({'foo': (b) => b});
      expect(reg.overrides.keys, contains('foo'));
    });

    test('null token returns the baseline unchanged', () {
      final baseline = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final reg = VehicleThresholdOverrides.withKeiCarDefault();
      final result = reg.applyOverrideForToken(null, baseline);
      expect(result, equals(baseline));
    });

    test('unregistered token returns the baseline unchanged', () {
      final baseline = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final reg = VehicleThresholdOverrides.withKeiCarDefault();
      final result = reg.applyOverrideForToken('commercial-light', baseline);
      expect(result, equals(baseline));
    });
  });

  group('VehicleThresholdOverrides.withKeiCarDefault — kei-car cohort', () {
    test('kei-car token raises warningVisibilityMeters by +50m', () {
      final baseline = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final reg = VehicleThresholdOverrides.withKeiCarDefault();
      final result = reg.applyOverrideForToken('kei-car', baseline);
      expect(
        result.warningVisibilityMeters,
        baseline.warningVisibilityMeters + 50,
      );
    });

    test('kei-car token raises warningTemperatureCelsius by +1°C', () {
      final baseline = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final reg = VehicleThresholdOverrides.withKeiCarDefault();
      final result = reg.applyOverrideForToken('kei-car', baseline);
      expect(
        result.warningTemperatureCelsius,
        baseline.warningTemperatureCelsius + 1,
      );
    });

    test(
      'kei-car override preserves score-floor tiers (severity-not-profile)',
      () {
        final baseline = NavigationSafetyConfig.forProfile(
          DriverProfile.ageingRural,
        );
        final reg = VehicleThresholdOverrides.withKeiCarDefault();
        final result = reg.applyOverrideForToken('kei-car', baseline);
        expect(result.safeScoreFloor, baseline.safeScoreFloor);
        expect(result.infoScoreFloor, baseline.infoScoreFloor);
        expect(result.warningScoreFloor, baseline.warningScoreFloor);
      },
    );

    test('kei-car override preserves critical thresholds + cap-override', () {
      final baseline = NavigationSafetyConfig.forProfile(
        DriverProfile.foreignTouristSnowZone,
      );
      final reg = VehicleThresholdOverrides.withKeiCarDefault();
      final result = reg.applyOverrideForToken('kei-car', baseline);
      expect(
        result.criticalVisibilityMeters,
        baseline.criticalVisibilityMeters,
      );
      expect(
        result.criticalTemperatureCelsius,
        baseline.criticalTemperatureCelsius,
      );
      expect(
        result.alertsPerMinuteCapOverride,
        baseline.alertsPerMinuteCapOverride,
      );
    });

    test('kei-car override preserves info thresholds (warning-tier only)', () {
      final baseline = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final reg = VehicleThresholdOverrides.withKeiCarDefault();
      final result = reg.applyOverrideForToken('kei-car', baseline);
      expect(result.infoVisibilityMeters, baseline.infoVisibilityMeters);
      expect(result.infoTemperatureCelsius, baseline.infoTemperatureCelsius);
    });
  });

  // ── Registration-time refusal (VehicleThresholdOverrides.validated) ──
  //
  // This is where a wrong transform is refused now. It was on the
  // drive path until 2026-09-13, where the throw killed the caller's
  // `async*` stream and the driver stopped being warned at all.

  group('VehicleThresholdOverrides.validated — refuses at REGISTRATION', () {
    test('relaxing warningVisibilityMeters throws at registration', () {
      expect(
        () => VehicleThresholdOverrides.validated({
          'relaxing-vis': (b) =>
              _copy(b, warningVisibilityMeters: b.warningVisibilityMeters - 50),
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('relaxing warningTemperatureCelsius throws at registration', () {
      expect(
        () => VehicleThresholdOverrides.validated({
          'relaxing-temp': (b) => _copy(
            b,
            warningTemperatureCelsius: b.warningTemperatureCelsius - 1,
          ),
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('modifying safeScoreFloor throws at registration', () {
      expect(
        () => VehicleThresholdOverrides.validated({
          'severity-safe': (b) => _copy(b, safeScoreFloor: 0.95),
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('modifying infoScoreFloor throws at registration', () {
      expect(
        () => VehicleThresholdOverrides.validated({
          'severity-info': (b) => _copy(b, infoScoreFloor: 0.45),
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('modifying warningScoreFloor throws at registration', () {
      expect(
        () => VehicleThresholdOverrides.validated({
          'severity-warning': (b) => _copy(b, warningScoreFloor: 0.10),
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a transform that itself throws is refused at registration', () {
      // Through 0.11.5 NOTHING guarded this case: the transform's own
      // exception escaped straight through applyOverrideForToken and
      // killed an `async*` caller exactly as an invariant throw did.
      expect(
        () => VehicleThresholdOverrides.validated({
          'throwing': (b) => throw StateError('integrator bug'),
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a CONSTANT threshold that clears every profile baseline is still '
        'refused — the HIGH synthetic probe is what catches it', () {
      // 400m is >= every DriverProfile baseline warningVisibilityMeters
      // (max 320). But the config reaching the drive path is
      // POST-CONTEXT: speed and precipitation margins push it well
      // past 400m (measured 359m at 80 km/h for snowZoneExperienced,
      // higher for conservative profiles). Probing only the profile
      // baselines would pass this and relax in the car.
      expect(
        () => VehicleThresholdOverrides.validated({
          'constant-400': (b) => _copy(b, warningVisibilityMeters: 400),
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the probe battery covers every DriverProfile plus 2 synthetics', () {
      expect(
        VehicleThresholdOverrides.registrationProbeCount,
        DriverProfile.values.length + 2,
      );
    });

    test('a caution-ADDING transform registers cleanly', () {
      final reg = VehicleThresholdOverrides.validated({
        'adds-caution': (b) => _copy(
          b,
          warningVisibilityMeters: b.warningVisibilityMeters + 40,
          warningTemperatureCelsius: b.warningTemperatureCelsius + 2,
        ),
      });
      expect(reg.validatedAtRegistration, isTrue);
    });

    test('an identity (no-op) transform registers cleanly', () {
      expect(
        VehicleThresholdOverrides.validated({
          'identity': (b) => b,
        }).validatedAtRegistration,
        isTrue,
      );
    });

    test('withKeiCarDefault() is itself probed and passes', () {
      // We do not ask integrators to validate what we decline to
      // validate ourselves.
      final reg = VehicleThresholdOverrides.withKeiCarDefault();
      expect(reg.validatedAtRegistration, isTrue);
    });

    test('the plain const constructor is NOT marked validated', () {
      expect(
        VehicleThresholdOverrides({'x': (b) => b}).validatedAtRegistration,
        isFalse,
      );
    });
  });

  // ── Drive-path refusal: never throws, never silently applies ─────────

  group('applyOverrideForToken — refuses WITHOUT throwing', () {
    setUp(VehicleThresholdOverrides.resetRejectionReporting);
    tearDown(VehicleThresholdOverrides.resetRejectionReporting);

    NavigationSafetyConfig baseline() =>
        NavigationSafetyConfig.forProfile(DriverProfile.snowZoneExperienced);

    test(
      'a relaxing warningVisibilityMeters override returns the BASELINE',
      () {
        final base = baseline();
        final rejections = <VehicleOverrideRejection>[];
        final reg = VehicleThresholdOverrides({
          'relaxing-vis': (b) => _copy(b, warningVisibilityMeters: 10),
        }, onRejected: rejections.add);

        final result = reg.applyOverrideForToken('relaxing-vis', base);

        // Did NOT throw, did NOT apply the relaxation.
        expect(result.warningVisibilityMeters, base.warningVisibilityMeters);
        expect(result, equals(base));
        expect(rejections, hasLength(1));
        expect(rejections.single.field, 'warningVisibilityMeters');
        expect(
          rejections.single.invariant,
          VehicleOverrideInvariant.cautionAddOnly,
        );
        expect(rejections.single.rejectedValue, 10);
      },
    );

    test(
      'a relaxing warningTemperatureCelsius override returns the BASELINE',
      () {
        final base = baseline();
        final rejections = <VehicleOverrideRejection>[];
        final reg = VehicleThresholdOverrides({
          'relaxing-temp': (b) => _copy(
            b,
            warningTemperatureCelsius: b.warningTemperatureCelsius - 5,
          ),
        }, onRejected: rejections.add);

        final result = reg.applyOverrideForToken('relaxing-temp', base);
        expect(result, equals(base));
        expect(rejections.single.field, 'warningTemperatureCelsius');
      },
    );

    test('a score-floor-moving override returns the BASELINE', () {
      final base = baseline();
      final rejections = <VehicleOverrideRejection>[];
      final reg = VehicleThresholdOverrides({
        'severity': (b) => _copy(b, warningScoreFloor: 0.05),
      }, onRejected: rejections.add);

      final result = reg.applyOverrideForToken('severity', base);
      expect(result, equals(base));
      expect(
        rejections.single.invariant,
        VehicleOverrideInvariant.severityNotProfile,
      );
    });

    test('a transform that throws returns the BASELINE, not the exception', () {
      final base = baseline();
      final rejections = <VehicleOverrideRejection>[];
      final reg = VehicleThresholdOverrides({
        'throwing': (b) => throw StateError('integrator bug'),
      }, onRejected: rejections.add);

      final result = reg.applyOverrideForToken('throwing', base);
      expect(result, equals(base));
      expect(
        rejections.single.invariant,
        VehicleOverrideInvariant.transformThrew,
      );
      expect(rejections.single.error, isA<StateError>());
    });

    test('a transform that throws hands onRejected its STACK TRACE, with the '
        "integrator's own transform in it", () {
      // Through 0.11.5 the exception propagated and its top frame was the
      // integrator's transform. Catching it must not take that line away.
      final rejections = <VehicleOverrideRejection>[];
      final reg = VehicleThresholdOverrides({
        'throwing': _brokenIntegratorTransform,
      }, onRejected: rejections.add);

      reg.applyOverrideForToken('throwing', baseline());

      final trace = rejections.single.stackTrace;
      expect(trace, isNotNull);
      expect(trace.toString(), contains('_brokenIntegratorTransform'));
      expect(
        trace.toString(),
        contains('vehicle_threshold_overrides_test.dart'),
      );
      expect(rejections.single.toString(), contains('stack trace: '));
    });

    test('an invariant rejection carries NO stack trace — nothing threw', () {
      final rejections = <VehicleOverrideRejection>[];
      VehicleThresholdOverrides(
        {'relaxing-vis': (b) => _copy(b, warningVisibilityMeters: 10)},
        onRejected: rejections.add,
      ).applyOverrideForToken('relaxing-vis', baseline());
      expect(rejections.single.stackTrace, isNull);
      expect(rejections.single.toString(), isNot(contains('stack trace')));
    });

    test('the DEFAULT report is exactly ONE stdout line, and carries the stack '
        'trace, even when the error text itself spans lines', () {
      // `int.parse` throws a FormatException whose toString puts the
      // source and a caret on following lines. The changelog promises one
      // line per refusal; this is the case that would break the promise.
      final printed = <String>[];
      runZoned(
        () => VehicleThresholdOverrides({
          'parses': _transformThatParses,
        }).applyOverrideForToken('parses', baseline()),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );

      expect(printed, hasLength(1));
      final line = printed.single;
      expect(line, startsWith('navigation_safety_core: '));
      expect(line, isNot(contains('\n')));
      expect(line, isNot(contains('\r')));
      expect(line, contains('FormatException'));
      expect(line, contains('stack trace: '));
      expect(line, contains('_transformThatParses'));
    });

    test('an onRejected handler that THROWS does not escape either', () {
      // Otherwise we have only moved the stream-killing throw from
      // this package into the integrator's logger.
      final base = baseline();
      final reg = VehicleThresholdOverrides({
        'relaxing-vis': (b) => _copy(b, warningVisibilityMeters: 10),
      }, onRejected: (_) => throw StateError('logger blew up'));
      expect(
        () => reg.applyOverrideForToken('relaxing-vis', base),
        returnsNormally,
      );
    });

    test('a LEGAL override still applies on the drive path', () {
      // The refusal must not have become a blanket refusal.
      final base = baseline();
      final reg = VehicleThresholdOverrides.validated({
        'adds-caution': (b) =>
            _copy(b, warningVisibilityMeters: b.warningVisibilityMeters + 40),
      });
      final result = reg.applyOverrideForToken('adds-caution', base);
      expect(result.warningVisibilityMeters, base.warningVisibilityMeters + 40);
    });

    test('the default reporter de-duplicates per token+field', () {
      // A broken override on a 10 Hz CAN bus must not flood an IVI log
      // for the whole journey.
      final base = baseline();
      final seen = <VehicleOverrideRejection>[];
      VehicleThresholdOverrides.rejectionReporter = seen.add;
      final reg = VehicleThresholdOverrides({
        'relaxing-vis': (b) => _copy(b, warningVisibilityMeters: 10),
      });

      for (var i = 0; i < 50; i++) {
        reg.applyOverrideForToken('relaxing-vis', base);
      }
      expect(seen, hasLength(1));
    });

    test('an onRejected handler is NOT de-duplicated — integrator owns it', () {
      final base = baseline();
      final rejections = <VehicleOverrideRejection>[];
      final reg = VehicleThresholdOverrides({
        'relaxing-vis': (b) => _copy(b, warningVisibilityMeters: 10),
      }, onRejected: rejections.add);
      for (var i = 0; i < 5; i++) {
        reg.applyOverrideForToken('relaxing-vis', base);
      }
      expect(rejections, hasLength(5));
    });
  });

  // ── Hand-written implementers keep compiling (0.11.5 interface) ───────

  group('a class that implements VehicleThresholdOverrides', () {
    test('compiles with only the members 0.11.5 had, and is consulted', () {
      // The guard is that this FILE compiles: `_HandWrittenImplementer`
      // below supplies exactly `overrides` and `applyOverrideForToken`.
      // Add a public instance member to the class and this test file
      // stops compiling, which is the break a 0.11.6 holder would meet.
      final implementer = _HandWrittenImplementer();
      final context = _frameContext(0);

      final withImplementer = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.snowZoneExperienced,
        context: context,
        vehicleOverrides: implementer,
      );

      expect(implementer.calls, 1);
      expect(
        withImplementer,
        equals(
          NavigationSafetyConfig.forProfileWithContext(
            DriverProfile.snowZoneExperienced,
            context: context,
          ),
        ),
      );
    });

    test('validatedAtRegistration answers false for it and does not throw', () {
      expect(_HandWrittenImplementer().validatedAtRegistration, isFalse);
    });
  });

  // ── The regression this whole change exists for ──────────────────────

  group('per-frame drive path — the stream must survive', () {
    setUp(VehicleThresholdOverrides.resetRejectionReporting);
    tearDown(VehicleThresholdOverrides.resetRejectionReporting);

    test(
      'a relaxing override registered on a PER-FRAME async* loop delivers '
      'every advisory at BASELINE thresholds instead of killing the stream',
      () async {
        // Shape copied from example/can_bus_integration.dart: the
        // config is derived inside `await for` in an `async*` body.
        // With the unconditional throw this returned 0 of 5 and the
        // nav surface died on frame 1.
        final reg = VehicleThresholdOverrides({
          'kei-car': (b) => _copy(b, warningVisibilityMeters: 10),
        });

        final delivered = await _advisories(reg).toList();

        expect(delivered, hasLength(5));
        final expectedBaseline = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.snowZoneExperienced,
          context: _frameContext(0),
        ).warningVisibilityMeters;
        // Prove it BOTH ways: the stream lived AND the relaxation was
        // refused — 10m never reached the driver.
        expect(delivered.first.visibilityMeters, expectedBaseline);
        expect(delivered.every((a) => a.visibilityMeters != 10), isTrue);
      },
    );

    test('negative control: no overrides — same 5 advisories', () async {
      final delivered = await _advisories(null).toList();
      expect(delivered, hasLength(5));
    });

    test(
      'negative control: legal kei-car default — 5 advisories, +50m',
      () async {
        final reg = VehicleThresholdOverrides.withKeiCarDefault();
        final delivered = await _advisories(reg).toList();
        expect(delivered, hasLength(5));
        final withoutOverride = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.snowZoneExperienced,
          context: _frameContext(0),
        ).warningVisibilityMeters;
        expect(delivered.first.visibilityMeters, withoutOverride + 50);
      },
    );
  });
}

// ── Test helpers ───────────────────────────────────────────────────────

/// Field-wise copy; keeps each transform above to the one field it is
/// about instead of ten lines of boilerplate.
NavigationSafetyConfig _copy(
  NavigationSafetyConfig b, {
  double? safeScoreFloor,
  double? infoScoreFloor,
  double? warningScoreFloor,
  int? warningTemperatureCelsius,
  int? warningVisibilityMeters,
}) {
  return NavigationSafetyConfig(
    safeScoreFloor: safeScoreFloor ?? b.safeScoreFloor,
    infoScoreFloor: infoScoreFloor ?? b.infoScoreFloor,
    warningScoreFloor: warningScoreFloor ?? b.warningScoreFloor,
    infoTemperatureCelsius: b.infoTemperatureCelsius,
    warningTemperatureCelsius:
        warningTemperatureCelsius ?? b.warningTemperatureCelsius,
    criticalTemperatureCelsius: b.criticalTemperatureCelsius,
    infoVisibilityMeters: b.infoVisibilityMeters,
    warningVisibilityMeters:
        warningVisibilityMeters ?? b.warningVisibilityMeters,
    criticalVisibilityMeters: b.criticalVisibilityMeters,
    alertsPerMinuteCapOverride: b.alertsPerMinuteCapOverride,
  );
}

class _Advisory {
  const _Advisory(this.visibilityMeters);
  final int visibilityMeters;
}

DrivingContext _frameContext(int coolantC) => DrivingContext(
  speedMps: 80 / 3.6,
  humidityRH: 0.85,
  ambientTempCelsius: coolantC.toDouble(),
  timeSincePrecipitation: const Duration(minutes: 30),
  vehicleClassToken: 'kei-car',
);

/// Per-frame advisory stream: config derived INSIDE the loop, in an
/// `async*` body — the exact shape an uncaught throw terminates.
Stream<_Advisory> _advisories(VehicleThresholdOverrides? overrides) async* {
  const profile = DriverProfile.snowZoneExperienced;
  for (final coolantC in const [0, -1, -2, -3, -4]) {
    final config = NavigationSafetyConfig.forProfileWithContext(
      profile,
      context: _frameContext(coolantC),
      vehicleOverrides: overrides,
    );
    if (coolantC <= config.warningTemperatureCelsius) {
      yield _Advisory(config.warningVisibilityMeters);
    }
  }
}

/// A transform that fails the way an integrator's might. Named, so its
/// frame can be found in the stack trace the rejection carries.
NavigationSafetyConfig _brokenIntegratorTransform(NavigationSafetyConfig b) =>
    throw StateError('integrator bug');

/// A transform that fails with an error whose text spans several lines:
/// `FormatException.toString` prints the source and a caret below it.
NavigationSafetyConfig _transformThatParses(NavigationSafetyConfig b) =>
    _copy(b, warningVisibilityMeters: int.parse('three hundred'));

/// A registry written by hand, the way a 0.11.5 consumer could write one:
/// exactly the two instance members 0.11.5 declared, nothing else from
/// the interface.
class _HandWrittenImplementer implements VehicleThresholdOverrides {
  int calls = 0;

  @override
  final Map<String, NavigationSafetyConfig Function(NavigationSafetyConfig)>
  overrides = const {};

  @override
  NavigationSafetyConfig applyOverrideForToken(
    String? token,
    NavigationSafetyConfig baseline,
  ) {
    calls++;
    return baseline;
  }
}
