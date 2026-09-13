// Release-mode proof for the vehicle-class override guards.
//
// WHY THIS EXISTS SEPARATELY FROM `dart test`
//
// `dart test` runs with assertions ENABLED. Through 0.11.5 the
// caution-add-only and severity-not-profile guards were `assert`s, so
// the whole suite was green in the one mode in which the guards
// existed at all, while every shipped integrator build — where
// `assert` is elided — silently ACCEPTED a relaxing override and
// warned the driver LATE. A suite that can only run in the mode where
// the guard exists cannot see that class of defect.
//
// So this file is a plain Dart program, not a `package:test` suite,
// and it runs in the modes an integrator actually ships:
//
//   dart run tool/release_mode_proof.dart          # asserts OFF (JIT)
//   dart compile exe tool/release_mode_proof.dart -o /tmp/p && /tmp/p
//                                                  # asserts OFF (AOT)
//
// It refuses to run at all with assertions enabled, so it cannot
// quietly become another green-in-debug-only check.
//
// Exit code 0 = every case held. Non-zero = at least one failed, and
// each failure is printed.
//
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:io';

import 'package:navigation_safety_core/navigation_safety_core.dart';

bool _assertionsEnabled() {
  var enabled = false;
  assert(() {
    enabled = true;
    return true;
  }());
  return enabled;
}

final List<String> _failures = <String>[];

/// Cases actually executed. The instrument counts itself.
///
/// It did not, until 2026-09-13. The author reported "16 cases" for a
/// run that emits 15, having counted the `_check` DEFINITION as a call
/// site by eye; ORS caught it by running `grep -c '^  ok '` against the
/// real output. A proof whose case count comes from a person reading
/// its source is a proof with an unmeasured number in it -- which is
/// the defect class this whole file exists to catch, one level up.
int _checked = 0;

void _check(String what, bool held, {String? detail}) {
  _checked++;
  if (held) {
    stdout.writeln('  ok    $what');
  } else {
    stdout.writeln('  FAIL  $what${detail == null ? '' : ' -- $detail'}');
    _failures.add(what);
  }
}

DrivingContext _frameContext(int coolantC) => DrivingContext(
  speedMps: 80 / 3.6,
  humidityRH: 0.85,
  ambientTempCelsius: coolantC.toDouble(),
  timeSincePrecipitation: const Duration(minutes: 30),
  vehicleClassToken: 'kei-car',
);

/// Config derived INSIDE the loop, in an `async*` body — the shape
/// `example/can_bus_integration.dart` teaches and the shape an
/// uncaught throw terminates.
Stream<int> _perFrameAdvisories(VehicleThresholdOverrides? overrides) async* {
  const profile = DriverProfile.snowZoneExperienced;
  for (final coolantC in const <int>[0, -1, -2, -3, -4]) {
    final config = NavigationSafetyConfig.forProfileWithContext(
      profile,
      context: _frameContext(coolantC),
      vehicleOverrides: overrides,
    );
    if (coolantC <= config.warningTemperatureCelsius) {
      yield config.warningVisibilityMeters;
    }
  }
}

/// Drains the stream, reporting how many advisories arrived and
/// whether the stream died.
Future<({List<int> delivered, Object? died})> _drain(
  VehicleThresholdOverrides? overrides,
) async {
  final delivered = <int>[];
  try {
    await for (final visibilityMeters in _perFrameAdvisories(overrides)) {
      delivered.add(visibilityMeters);
    }
  } catch (error) {
    return (delivered: delivered, died: error);
  }
  return (delivered: delivered, died: null);
}

NavigationSafetyConfig _relaxTo10(NavigationSafetyConfig b) =>
    NavigationSafetyConfig(
      safeScoreFloor: b.safeScoreFloor,
      infoScoreFloor: b.infoScoreFloor,
      warningScoreFloor: b.warningScoreFloor,
      infoTemperatureCelsius: b.infoTemperatureCelsius,
      warningTemperatureCelsius: b.warningTemperatureCelsius,
      criticalTemperatureCelsius: b.criticalTemperatureCelsius,
      infoVisibilityMeters: b.infoVisibilityMeters,
      warningVisibilityMeters: 10,
      criticalVisibilityMeters: b.criticalVisibilityMeters,
      alertsPerMinuteCapOverride: b.alertsPerMinuteCapOverride,
    );

Future<void> main() async {
  stdout.writeln('navigation_safety_core — release-mode override proof');

  if (_assertionsEnabled()) {
    stderr.writeln(
      'REFUSING TO RUN: assertions are ENABLED. This proof exists to '
      'exercise the guards in the mode an integrator ships, where '
      '`assert` is elided. Run it with `dart run` or an AOT binary, '
      'never with --enable-asserts.',
    );
    exit(2);
  }
  stdout.writeln('  mode: assertions ELIDED (shipped-build equivalent)\n');

  // Silence the default per-rejection report so the proof output stays
  // readable; count the rejections instead.
  final reported = <VehicleOverrideRejection>[];
  VehicleThresholdOverrides.resetRejectionReporting();
  VehicleThresholdOverrides.rejectionReporter = reported.add;

  // ── 1. The regression: per-frame loop with a relaxing override ──────
  stdout.writeln('1. per-frame async* loop, RELAXING override registered');
  final relaxing = VehicleThresholdOverrides({'kei-car': _relaxTo10});
  final withRelaxing = await _drain(relaxing);
  final baselineRun = await _drain(null);

  _check(
    'the stream survives (did not die on frame 1)',
    withRelaxing.died == null,
    detail: '${withRelaxing.died}',
  );
  _check(
    'all 5 advisories delivered',
    withRelaxing.delivered.length == 5,
    detail: 'got ${withRelaxing.delivered.length}',
  );
  _check(
    'the relaxation was REFUSED — 10m never reached the driver',
    withRelaxing.delivered.every((m) => m != 10),
    detail: '${withRelaxing.delivered}',
  );
  _check(
    'the un-overridden baseline was applied instead',
    withRelaxing.delivered.toString() == baselineRun.delivered.toString(),
    detail: '${withRelaxing.delivered} vs ${baselineRun.delivered}',
  );
  _check('the refusal was REPORTED, not silent', reported.isNotEmpty);
  _check(
    'the report names the field and the invariant',
    reported.isNotEmpty &&
        reported.first.field == 'warningVisibilityMeters' &&
        reported.first.invariant == VehicleOverrideInvariant.cautionAddOnly,
  );
  _check(
    'reporting de-duplicated across 5 frames',
    reported.length == 1,
    detail: '${reported.length} reports',
  );

  // ── 2. Negative controls ────────────────────────────────────────────
  stdout.writeln('\n2. negative controls');
  _check(
    'no overrides: 5 advisories, stream alive',
    baselineRun.died == null && baselineRun.delivered.length == 5,
  );

  final keiDefault = await _drain(
    VehicleThresholdOverrides.withKeiCarDefault(),
  );
  _check(
    'legal kei-car default: 5 advisories, stream alive',
    keiDefault.died == null && keiDefault.delivered.length == 5,
  );
  _check(
    'legal kei-car default actually applied (+50m over baseline)',
    keiDefault.delivered.isNotEmpty &&
        keiDefault.delivered.first == baselineRun.delivered.first + 50,
    detail: '${keiDefault.delivered.first} vs ${baselineRun.delivered.first}',
  );

  // ── 3. A transform that throws must not escape either ───────────────
  stdout.writeln('\n3. a transform that itself throws');
  final throwing = VehicleThresholdOverrides({
    'kei-car': (b) => throw StateError('integrator bug'),
  });
  final withThrowing = await _drain(throwing);
  _check(
    'the stream survives a throwing transform',
    withThrowing.died == null,
    detail: '${withThrowing.died}',
  );
  _check(
    'all 5 advisories delivered at baseline',
    withThrowing.delivered.toString() == baselineRun.delivered.toString(),
    detail: '${withThrowing.delivered}',
  );

  // ── 4. Registration still refuses, in release mode too ──────────────
  stdout.writeln('\n4. registration-time refusal (asserts elided)');
  var registrationThrew = false;
  try {
    VehicleThresholdOverrides.validated({'kei-car': _relaxTo10});
  } on ArgumentError {
    registrationThrew = true;
  }
  _check(
    '.validated() throws on a relaxing override with asserts OFF',
    registrationThrew,
  );

  var throwingRegistrationThrew = false;
  try {
    VehicleThresholdOverrides.validated({
      'kei-car': (b) => throw StateError('integrator bug'),
    });
  } on ArgumentError {
    throwingRegistrationThrew = true;
  }
  _check(
    '.validated() throws on a throwing transform with asserts OFF',
    throwingRegistrationThrew,
  );

  var legalRegistrationHeld = true;
  try {
    VehicleThresholdOverrides.withKeiCarDefault();
  } catch (_) {
    legalRegistrationHeld = false;
  }
  _check(
    '.validated() accepts the shipped kei-car default',
    legalRegistrationHeld,
  );

  VehicleThresholdOverrides.resetRejectionReporting();

  stdout.writeln('');
  stdout.writeln(
    'cases executed: $_checked  (plus 1 refusal control, which emits no '
    'case line: this program exits 2 under --enable-asserts)',
  );
  if (_failures.isEmpty) {
    stdout.writeln('ALL $_checked CASES HELD (assertions elided)');
    exit(0);
  }
  stderr.writeln('${_failures.length} of $_checked CASE(S) FAILED:');
  for (final f in _failures) {
    stderr.writeln('  - $f');
  }
  exit(1);
}
