import 'dart:ffi';
import 'dart:io';

import 'package:driving_conditions/driving_conditions.dart' show RoadSurfaceState;
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
/// reached a release note because nothing asserted the identity of the NATIVE
/// engine: `honest_fleet_absence_test.dart:48` asserts it on the CPU engine
/// only, and `native_simulation_engine_test.dart` compares native to CPU at
/// one point and `skip:`s when the .so is absent.
///
/// ⚑ THIS FILE'S FIRST VERSION WAS REFUTED, and the refutation is encoded
/// below as a standing control rather than described. That version pinned
/// `surfaceCode` to 0 on every cell while the parameter is LIVE (it is
/// `RoadSurfaceState.index`, and the C currently discards it). A weighting
/// that varies BY SURFACE — a likely change in a package whose subject is
/// road surface — broke the identity by 0.19 at `blackIce`, the exact surface
/// the false sentence was about, and the guard stayed green. `surfaceAttack`
/// in this file is that engine. It runs every time.
///
/// Vision 9: the operator must not be the last line of defense against
/// defects — the machine itself must catch them. Here the operator was the
/// only line of defense, was wrong, and then built a guard that was also
/// wrong. Both were caught by a control, which is the point.
///
/// THIS TEST CANNOT SKIP ON A MISSING ARTIFACT. It compiles the in-tree C
/// source itself. The C source is tracked; the .so is gitignored. Its only
/// remaining requirement is a C compiler, and when one is absent it FAILS and
/// says the loom did not run — it never reports success it did not earn.

/// `navigation_safety_core`'s `criticalGripScoreFloor`, 1.5/5.5 — the
/// glare-ice braking ratio. A literal on purpose: this package must not gain a
/// dependency on the consumer whose claim it is checking.
const double _gripFloor = 1.5 / 5.5;

/// The identity is exact in real arithmetic; this covers float32 accumulation.
///
/// BOUNDED BY RUN COUNT, and the bound is real: `SimulationOptions.runs` is a
/// public unbounded `int` (default 1000), and the UNMUTATED engine crosses
/// this epsilon by accumulation alone somewhere between 50,000 and 100,000
/// runs — 7.58e-06 at 50k, 1.42e-05 at 100k, measured. Within the swept
/// range the worst departure is 1.01e-06, so the headroom here is 9.9x, and
/// it does not move with the optimisation level. So the primary test
/// below states the run counts it swept, in its NAME and in its failure
/// message, and `the departure at high run counts is accumulation` covers the
/// rest of the range at a bound appropriate to it.
///
/// ⚑ AN EARLIER VERSION OF THIS COMMENT CALLED 1e-5 "500x tighter than the
/// parity test's 0.005". WITHDRAWN — that compared two different quantities.
/// The parity test's tolerance absorbs Monte Carlo sampling noise between two
/// engines that share only a seed VALUE and not a generator, and its measured
/// headroom is about 1.01x, which is nearly too tight rather than loose. The
/// real case against it is unchanged and stronger: at its single point it is
/// blind to a defect this test catches.
const double _identityEpsilon = 1e-5;

/// The per-run weighting in `native_simulation.c`.
const String _realWeighting =
    'float overall = grip_score * 0.5f + visibility_score * 0.5f;';
const String _brokenWeighting =
    'float overall = grip_score * 0.7f + visibility_score * 0.3f;';

/// Assignments to a bare `overall`, comments removed first. The real kernel
/// assigns it exactly once; a second assignment is how a surface-, speed- or
/// grip-conditional override hides from a sweep that does not happen to vary
/// the trigger.
final RegExp _overallAssignment = RegExp(r'(?<![_A-Za-z0-9])overall\s*=(?!=)');

String _stripComments(String c) => c
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// THE REFUTATION, ENCODED. Leaves [_realWeighting] textually intact — so a
/// control that only checks for that line is satisfied — and overrides
/// `overall` for one surface.
String _surfaceAttack(String source) {
  final withOverride = source.replaceFirst(
    _realWeighting,
    '$_realWeighting\n'
    '    if (surface_code == ${RoadSurfaceState.blackIce.index}u) {\n'
    '      overall = grip_score * 0.7f + visibility_score * 0.3f;\n'
    '    }',
  );
  return withOverride.replaceFirst('(void) surface_code;', '');
}

void main() {
  final source = File('${Directory.current.path}/native/native_simulation.c');
  final cc = _findCompiler();
  final surfaces = RoadSurfaceState.values.map((s) => s.index).toList();
  late Directory tmp;

  setUp(() {
    // `expect`, not `markTestSkipped`. A skip reads exactly like a pass in
    // every runner and every CI summary, and that is what this package has
    // already paid for twice — see the CI workflow's own note on the parity
    // test, and the ABI guard next door. If the loom cannot run, it is red.
    expect(
      source.existsSync(),
      isTrue,
      reason:
          'native/native_simulation.c is absent, so the identity this test '
          'exists to assert was NOT checked. The source is tracked in git.',
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
    test(
      'it holds on EVERY road surface, at run counts up to 1000, including '
      'below the grip floor',
      () {
        final lib = _compile(cc!, tmp, source.readAsStringSync(), 'real');
        final r = _sweep(NativeSimulationBindings(library: lib), surfaces);

        // ANTI-VACUITY. This is the only counter here that can fail on engine
        // behaviour, and it is falsifiable: flooring grip drives it to zero.
        expect(
          r.cellsBelowGripFloor,
          greaterThan(0),
          reason:
              'the sweep never reached gripMean < $_gripFloor — the exact '
              'region the false sentence was about. A pass would mean nothing.',
        );

        expect(
          r.maxDeviation,
          lessThan(_identityEpsilon),
          reason:
              'on surface index ${r.worstSurface}, overallMean departed from '
              '0.5*gripMean + 0.5*visibilityMean by ${r.maxDeviation}, at run '
              'counts up to 1000. Within that range the departure is float32 '
              'accumulation and is bounded far below this; a departure this '
              'size is a WEIGHTING change, and every consumer reasoning from '
              'the stated identity at these run counts is now wrong.',
        );
      },
    );

    test('NEGATIVE CONTROL A: a reweighted engine goes RED', () {
      final original = source.readAsStringSync();
      expect(
        original.contains(_realWeighting),
        isTrue,
        reason:
            'the weighting line this control mutates is no longer in '
            'native_simulation.c, so the control is not controlling anything. '
            'Re-point it at the real line before trusting the test above.',
      );
      final lib = _compile(
        cc!,
        tmp,
        original.replaceFirst(_realWeighting, _brokenWeighting),
        'reweighted',
      );
      final r = _sweep(NativeSimulationBindings(library: lib), surfaces);
      expect(r.cellsBelowGripFloor, greaterThan(0));
      expect(
        r.maxDeviation,
        greaterThan(0.01),
        reason:
            'a 0.7/0.3 engine was NOT distinguished from a 0.5/0.5 one, so '
            'the identity check cannot fail and is not a check.',
      );
    });

    test(
      'NEGATIVE CONTROL B: a SURFACE-CONDITIONAL override goes RED — the '
      'refutation that killed this file\'s first version',
      () {
        final attacked = _surfaceAttack(source.readAsStringSync());
        // The attack must be invisible to a control that only looks for the
        // weighting line; if it is not, this control has stopped reproducing
        // the defect it was built from.
        expect(
          attacked.contains(_realWeighting),
          isTrue,
          reason:
              'the attack no longer leaves the literal weighting line intact, '
              'so it no longer reproduces the defect that refuted v1',
        );
        final lib = _compile(cc!, tmp, attacked, 'surface_attack');
        final r = _sweep(NativeSimulationBindings(library: lib), surfaces);
        expect(
          r.maxDeviation,
          greaterThan(0.01),
          reason:
              'an engine whose weighting changes on ONE road surface was not '
              'caught. The sweep is not reaching every surface, and a '
              'surface-dependent defect can land unseen in the black-ice '
              'region — which is where it was found the first time.',
        );
        expect(
          r.worstSurface,
          RoadSurfaceState.blackIce.index,
          reason: 'the break should be located on the surface it was planted on',
        );
      },
    );

    test(
      'the C assigns `overall` exactly once, so no conditional override can '
      'hide behind a parameter this sweep does not vary',
      () {
        final stripped = _stripComments(source.readAsStringSync());
        expect(
          _overallAssignment.allMatches(stripped).length,
          1,
          reason:
              'the kernel assigns `overall` more than once. A second '
              'assignment is how a conditional reweighting hides from a '
              'behavioural sweep; if this is intentional, the sweep above '
              'must be widened over whatever the new condition reads.',
        );
        // Control on the control: the check must SEE the attack, and must not
        // be fooled by the word appearing in a comment.
        expect(
          _overallAssignment
              .allMatches(_stripComments(_surfaceAttack(source.readAsStringSync())))
              .length,
          greaterThan(1),
          reason: 'the static check is blind to a second assignment',
        );
        expect(
          _overallAssignment
              .allMatches(_stripComments('/* overall = 9; */ // overall = 8;'))
              .length,
          0,
          reason: 'the static check counts comments, so it will false-positive',
        );
      },
    );

    test(
      'the departure at HIGH run counts is float32 accumulation, and stays far '
      'below any threshold in navigation_safety_core',
      () {
        // Stated because the epsilon above is bounded by run count and `runs`
        // is public and unbounded. This is the honest rest of the range: the
        // identity degrades by accumulation, not by weighting, and a real
        // weighting break (>= 0.01) is still caught here by three orders.
        final lib = _compile(cc!, tmp, source.readAsStringSync(), 'highruns');
        final bindings = NativeSimulationBindings(library: lib);
        var worst = 0.0;
        for (final surfaceCode in surfaces) {
          for (var g = 0; g <= 10; g++) {
            for (final vis in const [0.0, 500.0, 1000.0]) {
              final r = bindings.runBatch(
                runs: 100000,
                seed: 42,
                speed: 60,
                gripFactor: g / 10,
                surfaceCode: surfaceCode,
                visibilityMeters: vis,
              );
              final d = (r.overallMean -
                      (0.5 * r.gripMean + 0.5 * r.visibilityMean))
                  .abs();
              if (d > worst) worst = d;
            }
          }
        }
        expect(
          worst,
          lessThan(1e-3),
          reason:
              'at 100,000 runs the departure was $worst. Accumulation alone '
              'does not reach this; a departure this size would move a '
              'severity decision.',
        );
      },
    );

    test(
      'STRUCTURAL (a regression guard on THIS FILE, not evidence about the '
      'engine): the sweep has the shape it claims',
      () {
        // Separated on FDD\'s finding. The cell count is the same number for
        // every engine, mutation and input, so it can never fail on engine
        // behaviour and must not sit beside evidence that can.
        expect(RoadSurfaceState.values.length, 6);
        final lib = _compile(cc!, tmp, source.readAsStringSync(), 'shape');
        final r = _sweep(NativeSimulationBindings(library: lib), surfaces);
        expect(
          r.cells,
          26136,
          reason: '4 run counts x 3 seeds x 11 grip x 11 visibility x 3 speeds '
              'x 6 surfaces. If this changed, the sweep was narrowed or widened '
              'and the claim above changed with it.',
        );
      },
    );
  });
}

typedef _SweepResult = ({
  double maxDeviation,
  int cellsBelowGripFloor,
  int cells,
  int worstSurface,
});

/// Runs the engine across the parameter space and measures the identity.
///
/// Sweeps EVERY road surface. The first version of this file pinned the
/// surface to 0 and was refuted for exactly that.
_SweepResult _sweep(NativeSimulationBindings bindings, List<int> surfaces) {
  var maxDeviation = 0.0;
  var worstSurface = -1;
  var cellsBelowGripFloor = 0;
  var cells = 0;

  for (final surfaceCode in surfaces) {
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
                surfaceCode: surfaceCode,
                visibilityMeters: v * 100.0,
              );
              final deviation =
                  (r.overallMean - (0.5 * r.gripMean + 0.5 * r.visibilityMean))
                      .abs();
              if (deviation > maxDeviation) {
                maxDeviation = deviation;
                worstSurface = surfaceCode;
              }
              if (r.gripMean < _gripFloor) cellsBelowGripFloor++;
              cells++;
            }
          }
        }
      }
    }
  }

  return (
    maxDeviation: maxDeviation,
    cellsBelowGripFloor: cellsBelowGripFloor,
    cells: cells,
    worstSurface: worstSurface,
  );
}

/// Compiles [csource] into a shared library under [tmp] and returns it loaded.
DynamicLibrary _compile(String cc, Directory tmp, String csource, String name) {
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
/// shared: extracting it would edit that file for a reason unrelated to the
/// change being made there.
String? _findCompiler() {
  for (final candidate in const ['cc', 'clang', 'gcc']) {
    if (Process.runSync('which', [candidate]).exitCode == 0) {
      return candidate;
    }
  }
  return null;
}
