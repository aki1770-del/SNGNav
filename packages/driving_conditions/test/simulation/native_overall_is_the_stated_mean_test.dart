import 'dart:ffi';
import 'dart:io';

import 'package:driving_conditions/src/simulation/native_simulation_bindings.dart'
    show NativeSimulationBindings;
import 'package:test/test.dart';

/// Asserts, ON THE NATIVE ENGINE ITSELF, the one arithmetic fact a consumer
/// reasons with: `overallMean` is exactly `0.5 * gripMean + 0.5 * visibilityMean`.
///
/// WHY THIS EXISTS, measured 2026-09-23. A draft of `navigation_safety_core`
/// 0.11.11's changelog named THIS engine's `overallMean` as an example of an
/// `overall` that is NOT that mean, and told readers to re-size their alert
/// throttling for volume that cannot reach them. It is that mean. The guess
/// survived to a release note because nothing anywhere asserted the identity
/// of the native engine:
///
///  * `honest_fleet_absence_test.dart:48` asserts it on the **CPU** engine
///    only, at one point (grip 0.2, visibility 300).
///  * `native_simulation_engine_test.dart` compares native to CPU at ONE point
///    (grip 0.65, visibility 650) within `closeTo(..., 0.005)`, and `skip:`s
///    outright when `native/build/libsimulation_engine.so` is absent. The .so
///    is gitignored, so it skips on every developer checkout; CI builds it, so
///    CI does exercise that single point.
///  * Neither visits the region the false sentence was about — `gripMean`
///    below 0.2727 (`navigation_safety_core`'s `criticalGripScoreFloor`) under
///    good visibility.
///
/// The identity held and no instrument said so. Vision 9: the operator must
/// not be the last line of defense — the machine itself must catch them. Here
/// the operator was the only line of defense, and was wrong.
///
/// THIS TEST CANNOT SKIP ON A MISSING ARTIFACT. It compiles the in-tree C
/// source itself, into a temp directory. The C source is in git; the .so is
/// not. That is the whole of the difference. Its only remaining requirement is
/// a C compiler, and when one is absent this test FAILS and says the loom did
/// not run — it never reports success it did not earn.

/// `navigation_safety_core`'s `criticalGripScoreFloor`, 1.5/5.5 m/s² — the
/// glare-ice braking ratio. Duplicated as a literal on purpose: this package
/// must not gain a dependency on the consumer whose claim it is checking.
const double _gripFloor = 1.5 / 5.5;

/// float32 accumulation over up to 1000 runs. The measured worst case at the
/// time of writing was 2.09e-06 over 26.7M parameter cells; this is ~5x that
/// and still 500x tighter than the parity test's 0.005.
const double _identityEpsilon = 1e-5;

/// The per-run weighting in `native_simulation.c`. The negative control breaks
/// exactly this line, so the control cannot pass by breaking something else.
const String _realWeighting =
    'float overall = grip_score * 0.5f + visibility_score * 0.5f;';
const String _brokenWeighting =
    'float overall = grip_score * 0.7f + visibility_score * 0.3f;';

void main() {
  final source = File('${Directory.current.path}/native/native_simulation.c');
  final cc = _findCompiler();
  late Directory tmp;

  setUp(() {
    // These are `expect`s and not `markTestSkipped` deliberately. A skip reads
    // exactly like a pass in every runner and every CI summary, and that is
    // what this package already paid for once (see the CI workflow's own note
    // on the parity test). If the loom cannot run, the loom is red.
    expect(
      source.existsSync(),
      isTrue,
      reason:
          'native/native_simulation.c is absent, so the identity this test '
          'exists to assert was NOT checked. The source is tracked in git; a '
          'checkout missing it is broken.',
    );
    expect(
      cc,
      isNotNull,
      reason:
          'NO C COMPILER ON PATH (looked for cc, clang, gcc), so THIS LOOM DID '
          'NOT RUN. This package\'s safety-score engine is C behind dart:ffi '
          'and cannot be verified without compiling it. Install a C compiler; '
          'do not read this as a pass.',
    );
    tmp = Directory.systemTemp.createTempSync('dc_native_identity');
    addTearDown(() => tmp.deleteSync(recursive: true));
  });

  group('the native engine\'s overallMean is the stated 50/50 mean', () {
    test('it holds across the parameter space, including below the grip floor', () {
      final lib = _compile(cc!, tmp, source.readAsStringSync(), 'real');
      final result = _sweep(NativeSimulationBindings(library: lib));

      // ANTI-VACUITY. 0.11.10 shipped a false conclusion drawn from a counter
      // that was arithmetically pinned to zero, so this test states what it
      // actually visited before it states what it found there.
      expect(
        result.cells,
        greaterThan(1000),
        reason: 'the sweep must be a sweep',
      );
      expect(
        result.cellsBelowGripFloor,
        greaterThan(0),
        reason:
            'the sweep never reached gripMean < $_gripFloor — the exact region '
            'the false sentence was about. A pass here would mean nothing.',
      );

      expect(
        result.maxDeviation,
        lessThan(_identityEpsilon),
        reason:
            'overallMean departed from 0.5*gripMean + 0.5*visibilityMean by '
            '${result.maxDeviation}. The native engine is NOT on the stated '
            'slice, and every consumer reasoning from that identity — '
            'including navigation_safety_core 0.11.11 — is now wrong.',
      );
    });

    test('NEGATIVE CONTROL: the assertion above goes RED on a broken engine', () {
      // Build the same engine with the weighting changed to 0.7/0.3 and run
      // the IDENTICAL check. If this does not blow past the epsilon, the test
      // above proves nothing and is ornament.
      final original = source.readAsStringSync();
      expect(
        original.contains(_realWeighting),
        isTrue,
        reason:
            'the weighting line this control mutates is no longer in '
            'native_simulation.c, so the control is not controlling anything. '
            'Re-point it at the real line before trusting the test above.',
      );
      final broken = original.replaceFirst(_realWeighting, _brokenWeighting);
      expect(
        broken.contains(_brokenWeighting),
        isTrue,
        reason: 'the mutation did not apply',
      );

      final lib = _compile(cc!, tmp, broken, 'broken');
      final result = _sweep(NativeSimulationBindings(library: lib));

      expect(
        result.cellsBelowGripFloor,
        greaterThan(0),
        reason: 'the control swept the same region as the real engine',
      );
      expect(
        result.maxDeviation,
        greaterThan(_identityEpsilon),
        reason:
            'a 0.7/0.3 engine was NOT distinguished from a 0.5/0.5 one. The '
            'identity check cannot fail, so it is not a check.',
      );
      // Not merely over the epsilon — visibly, unmistakably broken, so the
      // control is a real defect and not a rounding artifact.
      expect(result.maxDeviation, greaterThan(0.01));
    });
  });
}

typedef _SweepResult = ({double maxDeviation, int cellsBelowGripFloor, int cells});

/// Runs the engine across the parameter space and measures the identity.
///
/// Deliberately includes low `gripFactor` with high visibility: that is the
/// corner the false sentence claimed lived off the slice.
_SweepResult _sweep(NativeSimulationBindings bindings) {
  var maxDeviation = 0.0;
  var cellsBelowGripFloor = 0;
  var cells = 0;

  for (final runs in const [1, 7, 200, 1000]) {
    for (final seed in const [0, 7, 42]) {
      for (var g = 0; g <= 10; g++) {
        for (var v = 0; v <= 10; v++) {
          for (final speed in const [0.0, 60.0, 130.0]) {
            final r = bindings.runBatch(
              runs: runs,
              seed: seed,
              speed: speed,
              gripFactor: g / 10,
              surfaceCode: 0,
              visibilityMeters: v * 100.0,
            );
            final derived = 0.5 * r.gripMean + 0.5 * r.visibilityMean;
            final deviation = (r.overallMean - derived).abs();
            if (deviation > maxDeviation) maxDeviation = deviation;
            if (r.gripMean < _gripFloor) cellsBelowGripFloor++;
            cells++;
          }
        }
      }
    }
  }

  return (
    maxDeviation: maxDeviation,
    cellsBelowGripFloor: cellsBelowGripFloor,
    cells: cells,
  );
}

/// Compiles [csource] into a shared library under [tmp] and returns it loaded.
DynamicLibrary _compile(
  String cc,
  Directory tmp,
  String csource,
  String name,
) {
  final src = File('${tmp.path}/$name.c')..writeAsStringSync(csource);
  final out = '${tmp.path}/lib$name.so';
  final build = Process.runSync(cc, [
    '-O2',
    '-shared',
    '-fPIC',
    '-o',
    out,
    src.path,
    '-lm',
  ]);
  expect(
    build.exitCode,
    0,
    reason: 'failed to build the $name engine: ${build.stderr}',
  );
  return DynamicLibrary.open(out);
}

/// Mirrors the helper in `native_abi_guard_test.dart`. Duplicated rather than
/// shared: extracting it would edit that file, and this change is meant to add
/// a missing assertion, not to refactor its neighbours.
String? _findCompiler() {
  for (final candidate in const ['cc', 'clang', 'gcc']) {
    if (Process.runSync('which', [candidate]).exitCode == 0) {
      return candidate;
    }
  }
  return null;
}
