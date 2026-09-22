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

/// Off-lattice tolerances, MEASURED rather than derived. Each is the worst
/// departure seen on the unmutated engine over 20,000 pseudo-random samples
/// with continuous speed / grip / visibility across all six surfaces:
///
///   runs <= 1000       worst 1.2815e-06   ->  1e-5 tolerance,  7.8x headroom
///   1000..200,000      worst 5.3436e-05   ->  1e-3 tolerance, 18.7x headroom
///
/// A 0.85 multiplicative override — the ordinary way an override is written —
/// produces about 7.5e-02, so both tolerances catch it by one to four orders.
const double _epsilonLowRuns = 1e-5;
const double _epsilonHighRuns = 1e-3;
const int _lowRunCeiling = 1000;

/// The top of the range this file asserts. Above it, float32 accumulation
/// dominates and is NOT monotone in run count, so no bound is claimed.
const int _maxAssertedRuns = 200000;

/// The per-run weighting in `native_simulation.c`.
const String _realWeighting =
    'float overall = grip_score * 0.5f + visibility_score * 0.5f;';
const String _brokenWeighting =
    'float overall = grip_score * 0.7f + visibility_score * 0.3f;';

/// WRITES to a bare `overall`, comments removed first — plain AND compound.
///
/// ⚑ v2 OF THIS PATTERN MATCHED ONLY `=`, AND WAS REFUTED. `overall *= 0.85f`
/// is how anyone actually writes an override, and it returned zero matches, so
/// four conditional overrides passed the static check. The blind spot was not
/// the exotic macro case this file used to name; it was the ordinary one.
final RegExp _overallWrite =
    RegExp(r'(?<![_A-Za-z0-9])overall\s*(?:[-+*/%^&|]|<<|>>)?=(?!=)');

/// WRITES to the accumulator. Scaling here changes `overallMean` while never
/// touching `overall`, so the check above cannot see it: `total_overall +=
/// overall * 0.9f` is invisible to any pattern that watches `overall` alone.
final RegExp _totalOverallWrite =
    RegExp(r'(?<![_A-Za-z0-9])total_overall\s*(?:[-+*/%^&|]|<<|>>)?=(?!=)');

/// The accumulation statement itself. What is accumulated must be `overall`,
/// unscaled — the count above cannot tell `+= overall;` from `+= overall*0.9f;`.
const String _accumulation = 'total_overall += overall;';

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
      '`overall` is WRITTEN exactly once and accumulated UNSCALED, so a '
      'conditional override cannot hide behind a trigger the sweep misses',
      () {
        final raw = source.readAsStringSync();
        final stripped = _stripComments(raw);

        expect(
          _overallWrite.allMatches(stripped).length,
          1,
          reason:
              'the kernel writes `overall` more than once. A second write — '
              'plain OR compound, `overall *= k` included — is how a '
              'conditional reweighting hides from a behavioural sweep. If it '
              'is intentional, the sweep must be widened over whatever the '
              'new condition reads.',
        );
        expect(
          _totalOverallWrite.allMatches(stripped).length,
          2,
          reason:
              'the accumulator is written somewhere other than its '
              'initialisation and the one accumulation statement',
        );
        expect(
          _accumulation.allMatches(stripped).length,
          1,
          reason:
              'the accumulation is no longer the unscaled `$_accumulation`. '
              'Scaling HERE moves overallMean while never touching `overall`, '
              'so the write-count above cannot see it.',
        );

        // CONTROLS. Each must SEE its attack, and none may fire on a comment.
        for (final attack in <String, String>{
          'surface-conditional (compound)': _surfaceAttack(raw),
          'exact-run-count trigger': raw.replaceFirst(
            _realWeighting,
            '$_realWeighting\n    if (runs == 100001u) { overall *= 0.85f; }',
          ),
          'grip-band trigger': raw.replaceFirst(
            _realWeighting,
            '$_realWeighting\n    if (grip_factor > 0.26f && grip_factor < '
                '0.28f) { overall *= 0.85f; }',
          ),
        }.entries) {
          final a = _stripComments(attack.value);
          expect(
            _overallWrite.allMatches(a).length,
            greaterThan(1),
            reason: 'the write check is blind to: ${attack.key}',
          );
        }
        final scaled = _stripComments(
          raw.replaceFirst(_accumulation, 'total_overall += overall * 0.9f;'),
        );
        expect(
          _accumulation.allMatches(scaled).length,
          0,
          reason: 'the accumulation check is blind to a scaled accumulator',
        );
        expect(
          _overallWrite
              .allMatches(_stripComments(
                  '/* overall *= 9; */ // total_overall += overall * 2;'))
              .length,
          0,
          reason: 'the checks count comments, so they will false-positive',
        );
      },
    );

    test(
      'OFF-LATTICE probe: the identity holds at inputs that sit BETWEEN the '
      'swept grid points, at run counts drawn across the range',
      () {
        // ⚑ WHY THIS EXISTS. The lattice sweep above walks grip in steps of
        // 0.1, visibility in steps of 100 and three fixed speeds, so a trigger
        // written just off those points is invisible to it — and the four
        // attacks that refuted v2 sat off the lattice AND used a compound
        // assignment, so BOTH checks failed on the SAME input. The static
        // check is now widened; this is its behavioural complement, and it is
        // deliberately built to fail on different inputs: continuous
        // parameters, a deterministic pseudo-random draw, and the two run
        // counts that were used against this file.
        final lib = _compile(cc!, tmp, source.readAsStringSync(), 'offlattice');
        final bindings = NativeSimulationBindings(library: lib);
        final worst = _offLatticeProbe(bindings, surfaces);

        expect(
          worst.lowRunsWorst,
          lessThan(_epsilonLowRuns),
          reason:
              'off-lattice, at runs <= $_lowRunCeiling, the worst departure '
              'was ${worst.lowRunsWorst} (measured baseline 1.28e-06 over '
              '20,000 samples, so this tolerance carries 7.8x headroom). A '
              'departure here is a weighting change at a point the grid does '
              'not visit.',
        );
        expect(
          worst.highRunsWorst,
          lessThan(_epsilonHighRuns),
          reason:
              'off-lattice, at runs up to $_maxAssertedRuns, the worst '
              'departure was ${worst.highRunsWorst} (measured baseline '
              '5.34e-05 over 20,000 samples, 18.7x headroom). Float32 '
              'accumulation alone does not reach this tolerance ANYWHERE IN '
              'THIS RANGE — see the run-count test for where it does.',
        );
        expect(
          worst.samples,
          greaterThan(2000),
          reason: 'the probe must actually sample',
        );
      },
    );

    test(
      'the run-count range this file asserts, and the measured point where '
      'float32 accumulation stops being negligible',
      () {
        // ⚑ THIS TEST REPLACES ONE WHOSE PROSE WAS FALSE. It said "accumulation
        // alone does not reach this" of a 1e-3 tolerance at 100,000 runs. On
        // the UNMUTATED engine accumulation reaches 1.736e-03 at 1,000,000
        // runs — 1.7x that tolerance. Whoever widened that test to a million
        // runs, the natural next step since it covered the unbounded range,
        // would have watched a CORRECT engine go red and concluded the engine
        // was broken. A sentence about arithmetic written from reasoning
        // rather than from running it, inside the guard built to close exactly
        // that.
        //
        // Measured on the UNMUTATED engine over ONE NAMED GRID — all six
        // surfaces x grip 0.0..1.0 in 0.1 x visibility {0, 500, 1000} x speed
        // 60 x seed 42. The grid is named because these figures MOVE with it,
        // and quoting a departure without its grid is how three wrong numbers
        // got into this branch's record:
        //
        //     100,000 -> 1.61e-05      1,000,000 -> 1.74e-03
        //     200,000 -> 5.58e-05      2,000,000 -> 7.30e-03
        //     500,000 -> 2.16e-04      5,000,000 -> 5.51e-02
        //
        // ⚑ AND THE GROWTH IS NOT MONOTONE. Per cell it DROPS at 400k, 500k,
        // 600k and collapses from 4.87e-05 to 3.49e-06 at 1.1M before jumping
        // to 6.47e-04 at 1.2M, because the float32 accumulator saturates. So
        // there is no bound formula in run count to be had, and fitting one
        // would be the same mistake again. This file therefore asserts the
        // identity only up to $_maxAssertedRuns and SAYS SO rather than
        // implying more.
        //
        // DO NOT widen this to larger run counts expecting green. Above this
        // range a departure is accumulation, not a defect.
        final lib = _compile(cc!, tmp, source.readAsStringSync(), 'runbound');
        final bindings = NativeSimulationBindings(library: lib);

        var worst = 0.0;
        for (final surfaceCode in surfaces) {
          for (var g = 0; g <= 10; g++) {
            for (final vis in const [0.0, 500.0, 1000.0]) {
              final r = bindings.runBatch(
                runs: _maxAssertedRuns,
                seed: 42,
                speed: 60,
                gripFactor: g / 10,
                surfaceCode: surfaceCode,
                visibilityMeters: vis,
              );
              final d =
                  (r.overallMean - (0.5 * r.gripMean + 0.5 * r.visibilityMean))
                      .abs();
              if (d > worst) worst = d;
            }
          }
        }
        expect(
          worst,
          lessThan(_epsilonHighRuns),
          reason:
              'at the top of the asserted range ($_maxAssertedRuns runs) the '
              'departure was $worst against a $_epsilonHighRuns tolerance. '
              'Accumulation reaches roughly 5.6e-05 here, so this is a '
              'weighting change, not rounding.',
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

typedef _ProbeResult = ({
  double lowRunsWorst,
  double highRunsWorst,
  int samples,
});

/// Deterministic pseudo-random probe at inputs BETWEEN the lattice points.
///
/// Fixed seed, so it is reproducible; continuous parameters, so a trigger
/// written just off the grid cannot hide; and it explicitly includes the two
/// run counts used against this file — 5000, which is the parity test's own
/// run count, and 100001, which is one past the probe v2 used.
_ProbeResult _offLatticeProbe(
  NativeSimulationBindings bindings,
  List<int> surfaces,
) {
  var state = 0x9E3779B97F4A7C15;
  double next() {
    state = state * 6364136223846793005 + 1442695040888963407;
    return ((state >>> 11) & 0x1FFFFFFFFFFFFF) / 0x20000000000000;
  }

  var lowWorst = 0.0;
  var highWorst = 0.0;
  var samples = 0;

  double measure(int runs, int seed, double speed, double grip, int surface,
      double vis) {
    final r = bindings.runBatch(
      runs: runs,
      seed: seed,
      speed: speed,
      gripFactor: grip,
      surfaceCode: surface,
      visibilityMeters: vis,
    );
    return (r.overallMean - (0.5 * r.gripMean + 0.5 * r.visibilityMean)).abs();
  }

  for (var i = 0; i < 1500; i++) {
    final d = measure(
      1 + (next() * _lowRunCeiling).floor(),
      (next() * 0x7FFFFFFF).floor(),
      next() * 130.0,
      next(),
      surfaces[(next() * surfaces.length).floor().clamp(0, surfaces.length - 1)],
      next() * 1000.0,
    );
    if (d > lowWorst) lowWorst = d;
    samples++;
  }

  for (var i = 0; i < 1500; i++) {
    final d = measure(
      _lowRunCeiling + (next() * (_maxAssertedRuns - _lowRunCeiling)).floor(),
      (next() * 0x7FFFFFFF).floor(),
      next() * 130.0,
      next(),
      surfaces[(next() * surfaces.length).floor().clamp(0, surfaces.length - 1)],
      next() * 1000.0,
    );
    if (d > highWorst) highWorst = d;
    samples++;
  }

  // The two run counts that were actually used against this file. Random
  // sampling of a 200,000-wide range will not hit an exact-equality trigger,
  // so the known ones are named. The general case is the static write-count
  // check, not this.
  for (final runs in const [5000, 100001]) {
    for (final surface in surfaces) {
      for (var g = 0; g <= 10; g++) {
        final d = measure(runs, 42, 60.0, g / 10, surface, 500.0);
        if (runs <= _lowRunCeiling) {
          if (d > lowWorst) lowWorst = d;
        } else {
          if (d > highWorst) highWorst = d;
        }
        samples++;
      }
    }
  }

  return (lowRunsWorst: lowWorst, highRunsWorst: highWorst, samples: samples);
}
