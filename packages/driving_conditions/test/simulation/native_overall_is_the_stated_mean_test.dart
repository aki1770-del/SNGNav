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
///   runs <= 1000       worst 1.8477e-06   ->  1e-5 tolerance,  5.4x headroom
///   1000..200,000      worst 1.0544e-03   ->  1e-2 tolerance,  9.5x headroom
///
/// ⚑ RE-MEASURED OVER THE FULL REACHABLE INPUT SPACE, which is wider than the
/// probe used to draw from. `requireMeasured` enforces FINITENESS ONLY, so a
/// consumer may pass any finite speed, grip factor or visibility — including
/// negatives and speeds far above 130. The old probe drew speed as a fraction
/// of 130, so a trigger above 130 was behaviourally unreachable; that was the
/// two halves running parallel again, one layer up.
///
/// HONEST LIMIT OF THE LOOSE TIER. At high run counts with saturating inputs
/// accumulation alone reaches 1.05e-03, so the 1e-2 tolerance separates a x0.9
/// override (7.55e-02) by 7.2x but would NOT separate a x0.99 one (7.55e-03).
/// Fine discrimination lives in the low-run tier, where a x0.99 override is
/// 4,000x the tolerance — and since an input-gated trigger does not depend on
/// the run count, the low tier is where such a trigger is caught. Run-count-
/// gated triggers are caught by the whitelist, not here.
const double _epsilonLowRuns = 1e-5;
const double _epsilonHighRuns = 1e-2;
const int _lowRunCeiling = 1000;

/// The top of the range this file asserts. Above it, float32 accumulation
/// dominates and is NOT monotone in run count, so no bound is claimed.
const int _maxAssertedRuns = 200000;

/// The per-run weighting in `native_simulation.c`.
const String _realWeighting =
    'float overall = grip_score * 0.5f + visibility_score * 0.5f;';
const String _brokenWeighting =
    'float overall = grip_score * 0.7f + visibility_score * 0.3f;';

/// ⚑ A WHITELIST, TOTAL OVER THE TRANSLATION UNIT — v4.
///
/// v2 watched `overall` and matched only `=`. v3 widened that to compound
/// assignment and `total_overall`. v4 inverted it to a whitelist, and FDD's
/// verdict on v4 is the one worth keeping: *a whitelist, inside a scope that
/// is a blacklist of one function name*. It scanned `simulation_run_batch`
/// alone, so a static helper was unscanned and a call into it named no term —
/// **which is my own macro argument, turned around.** I pinned the `#define`
/// set reasoning that a macro expanding to a statement carries no identity
/// term where it is used. That is exactly as true of a function call, and I
/// had not pinned functions.
///
/// Three holes, measured, each a different KIND:
///   * SCOPE — `tune(response, speed)` with the arithmetic in a helper outside
///     the scanned body. Evaded everything.
///   * TERMS — `effective_runs` is divided by on BOTH sides of the identity
///     and was not a term. Its declaration carries no term either, so dropping
///     its `const` was invisible, and because the two divisions are separate
///     statements, doubling it between them broke the identity by 0.261 at
///     speed -200 while touching nothing watched.
///   * SPLITTING — splitting on `;` alone made detection depend on BRACE
///     PLACEMENT. The braced variant was caught, and only because its `}`
///     leaked into the next watched chunk; the identical unbraced one passed.
///     ⚑ I nearly banked that red. It was an artifact, not a detection, and
///     the failure text said so. A red accepted at face value is the same
///     trap as a green.
///
/// So the scope is now the whole translation unit, statements split on `;`,
/// `{` AND `}` so brace placement cannot change the answer, the terms include
/// what the identity DEPENDS on rather than only what it is made of, and the
/// function set is pinned beside the macro set. A box always has an outside;
/// the static half is the one that can be made total, so it is.
const List<String> _identityTerms = <String>[
  'overall',
  'grip_score',
  'visibility_score',
  'total_overall',
  'total_grip',
  'total_visibility',
  'overall_mean',
  'grip_mean',
  'visibility_mean',
  // What the identity DEPENDS on: both sides divide by this.
  'effective_runs',
  'runs',
  // The struct that carries the three means out.
  'response',
];

/// Every statement in the FILE permitted to touch those terms, comments
/// removed and whitespace collapsed. Generated from the real source.
const List<String> _permittedIdentityStatements = <String>[
  'float overall_mean',
  'float grip_mean',
  'float visibility_mean',
  'SimulationResponse simulation_run_batch( uint32_t runs, uint32_t seed, float speed, float grip_factor, uint32_t surface_code, float visibility_meters )',
  'const uint32_t effective_runs = runs == 0u ? 1u : runs',
  'float total_overall = 0.0f',
  'float total_grip = 0.0f',
  'float total_visibility = 0.0f',
  'run_index < effective_runs',
  'float grip_score = clampf_range( grip_factor * (1.0f - grip_jitter) * (1.0f - speed_factor * 0.3f), 0.0f, 1.0f )',
  'float visibility_score = clampf_range( visibility_norm * (1.0f - visibility_jitter), 0.0f, 1.0f )',
  'float overall = grip_score * 0.5f + visibility_score * 0.5f',
  'total_overall += overall',
  'total_grip += grip_score',
  'total_visibility += visibility_score',
  'total_overall_squared += overall * overall',
  'if (overall < 0.4f)',
  'float overall_mean = total_overall / (float) effective_runs',
  'float variance = (total_overall_squared / (float) effective_runs) - (overall_mean * overall_mean)',
  'SimulationResponse response =',
  '.overall_mean = overall_mean, .grip_mean = total_grip / (float) effective_runs, .visibility_mean = total_visibility / (float) effective_runs, .overall_variance = variance, .incident_count = incident_count, .execution_ms = execution_ms,',
  'return response',
];

/// The macro surface. A macro expanding to a statement carries no identity
/// term at its use site.
const List<String> _permittedDefines = <String>[
  '#define SIMULATION_ABI_VERSION 2u',
];

/// The function surface, pinned for the same reason as the macros and by the
/// same argument — a CALL carries no identity term either. A new function is
/// a new place for the arithmetic to live.
const List<String> _permittedFunctions = <String>[
  'simulation_abi_version',
  'clampf_range',
  'xorshift32',
  'uniform01',
  'simulation_run_batch',
];

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
      'NO arithmetic anywhere in the FILE touches the identity\'s terms '
      'beyond the permitted statements — a whitelist over the whole '
      'translation unit, with the macro AND function surfaces pinned',
      () {
        final raw = source.readAsStringSync();
        final found = _identityStatements(_scannedSource(raw));

        expect(
          found,
          _permittedIdentityStatements,
          reason:
              'the FILE contains arithmetic on the identity\'s terms that '
              'this test does not permit. Either a statement changed, or one '
              'was added. If the change is intentional, the whitelist is what '
              'states the identity and it must be updated deliberately — that '
              'is the point of it being a whitelist.',
        );

        expect(
          RegExp(r'^#define[^\n]*', multiLine: true)
              .allMatches(_stripComments(raw))
              .map((m) => m.group(0)!.trim())
              .toList(),
          _permittedDefines,
          reason:
              'a macro was added or changed. A macro expanding to a statement '
              'carries no identity term at its use site, so it would pass the '
              'whitelist above; pinning the #define set is what closes that.',
        );

        expect(
          _definedFunctions(_scannedSource(raw)),
          _permittedFunctions,
          reason:
              'a function was added, removed or renamed. A CALL carries no '
              'identity term at its call site, exactly as a macro use does, '
              'so a new function is a new place for the identity\'s '
              'arithmetic to live. This is the same argument that pins the '
              'macros, and not applying it to functions is what let a helper '
              'through.',
        );

        // CONTROLS. Every attack class that refuted v2 and v3 must be seen,
        // including the ones whose identifiers were never on any watch list.
        final attacks = <String, String>{
          'v2: surface-conditional override on `overall`': _surfaceAttack(raw),
          'v3: `overall_mean` — THE REPORTED FIELD': raw.replaceFirst(
            '  float overall_mean = total_overall / (float) effective_runs;',
            '  float overall_mean = total_overall / (float) effective_runs;\n'
                '  if (speed > 140.0f) { overall_mean *= 0.9f; }',
          ),
          'v3: `total_grip` accumulator': raw.replaceFirst(
            '    total_grip += grip_score;',
            '    if (speed > 140.0f) { total_grip += grip_score * 0.9f; } '
                'else { total_grip += grip_score; }',
          ),
          'v3: `total_visibility` accumulator': raw.replaceFirst(
            '    total_visibility += visibility_score;',
            '    if (speed > 140.0f) { total_visibility += visibility_score '
                '* 0.9f; } else { total_visibility += visibility_score; }',
          ),
          'v3: the struct initialiser': raw.replaceFirst(
            '    .overall_mean = overall_mean,',
            '    .overall_mean = (speed > 140.0f) ? overall_mean * 0.9f : '
                'overall_mean,',
          ),
          'compound assignment on `overall`': raw.replaceFirst(
            _realWeighting,
            '$_realWeighting\n    if (runs == 5000u) { overall *= 0.85f; }',
          ),
          // v4's three holes, each encoded so it cannot come back.
          'v4 SCOPE: arithmetic in a helper outside the kernel':
              raw.replaceFirst(
            'SimulationResponse simulation_run_batch(',
            'static SimulationResponse tune(SimulationResponse r, float s) {\n'
                '  if (s < -100.0f) { r.overall_mean = r.overall_mean * 0.9f; }\n'
                '  return r;\n}\n\nSimulationResponse simulation_run_batch(',
          ).replaceFirst(
            '  return response;',
            '  response = tune(response, speed);\n  return response;',
          ),
          'v4 TERMS: `effective_runs` doubled between the two divisions, '
                  'UNBRACED': raw
              .replaceFirst(
                '  const uint32_t effective_runs = runs == 0u ? 1u : runs;',
                '  uint32_t effective_runs = runs == 0u ? 1u : runs;',
              )
              .replaceFirst(
                '  float overall_mean = total_overall / (float) effective_runs;',
                '  float overall_mean = total_overall / (float) effective_runs;\n'
                    '  if (speed < -100.0f) effective_runs = effective_runs * 2u;',
              ),
          'v4 SPLITTING: the same mutation BRACED': raw.replaceFirst(
            '  float overall_mean = total_overall / (float) effective_runs;',
            '  float overall_mean = total_overall / (float) effective_runs;\n'
                '  if (speed < -100.0f) { overall_mean *= 0.9f; }',
          ),
          'v4 SPLITTING: the same mutation UNBRACED — detection must not '
                  'depend on brace placement': raw.replaceFirst(
            '  float overall_mean = total_overall / (float) effective_runs;',
            '  float overall_mean = total_overall / (float) effective_runs;\n'
                '  if (speed < -100.0f) overall_mean *= 0.9f;',
          ),
        };
        for (final attack in attacks.entries) {
          expect(
            _identityStatements(_scannedSource(attack.value)),
            isNot(_permittedIdentityStatements),
            reason: 'the whitelist is blind to: ${attack.key}',
          );
        }

        // And it must not fire on text that only APPEARS in a comment.
        expect(
          _identityStatements(_scannedSource(raw.replaceFirst(
            '  const uint32_t effective_runs',
            '  /* overall_mean *= 9; total_grip += grip_score * 2; */\n'
                '  const uint32_t effective_runs',
          ))),
          _permittedIdentityStatements,
          reason: 'the whitelist reads comments, so it will false-positive',
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
              'was ${worst.lowRunsWorst} (measured baseline 1.85e-06 over '
              '48,000 samples, so this tolerance carries 5.4x headroom). A '
              'departure here is a weighting change at a point the grid does '
              'not visit.',
        );
        expect(
          worst.highRunsWorst,
          lessThan(_epsilonHighRuns),
          reason:
              'off-lattice, at runs up to $_maxAssertedRuns, the worst '
              'departure was ${worst.highRunsWorst} (measured baseline '
              '1.05e-03 over 48,000 samples, 9.5x headroom). Float32 '
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
      -50.0 + next() * 450.0,
      -0.5 + next() * 2.5,
      surfaces[(next() * surfaces.length).floor().clamp(0, surfaces.length - 1)],
      -100.0 + next() * 5100.0,
    );
    if (d > lowWorst) lowWorst = d;
    samples++;
  }

  for (var i = 0; i < 1500; i++) {
    final d = measure(
      _lowRunCeiling + (next() * (_maxAssertedRuns - _lowRunCeiling)).floor(),
      (next() * 0x7FFFFFFF).floor(),
      -50.0 + next() * 450.0,
      -0.5 + next() * 2.5,
      surfaces[(next() * surfaces.length).floor().clamp(0, surfaces.length - 1)],
      -100.0 + next() * 5100.0,
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

/// The WHOLE translation unit, comments removed.
///
/// v4 scanned one function body. Everything outside it was unscanned, and a
/// call into a helper carries no identity term at the call site — so the
/// scope was a blacklist of one function name wrapped around a whitelist.
String _scannedSource(String source) {
  final stripped = _stripComments(source);
  if (!stripped.contains('simulation_run_batch')) {
    throw StateError(
      'simulation_run_batch is absent, so the whitelist below would pass '
      'vacuously. Refusing instead.',
    );
  }
  return stripped;
}

/// Every statement of [source] touching a term the identity is made of OR
/// depends on, whitespace collapsed.
///
/// Split on `;`, `{` AND `}`. Splitting on `;` alone made detection depend on
/// brace placement: a braced mutation was caught only because its closing
/// brace leaked into the next watched chunk, while the identical unbraced one
/// produced a chunk with no watched term and passed.
List<String> _identityStatements(String source) {
  final terms = _identityTerms
      .map((t) => RegExp('(?<![_A-Za-z0-9])$t(?![_A-Za-z0-9])'))
      .toList();
  return source
      .split(RegExp(r'[;{}]'))
      .map((s) => s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' '))
      .where((s) => s.isNotEmpty)
      .where((s) => terms.any((t) => t.hasMatch(s)))
      .toList();
}

/// Top-level function definitions in [source].
List<String> _definedFunctions(String source) => RegExp(
      r'^[A-Za-z_][A-Za-z0-9_ \*]*\s+([a-zA-Z_][A-Za-z0-9_]*)\s*\([^;]*?\)\s*\{',
      multiLine: true,
    ).allMatches(source).map((m) => m.group(1)!).toList();
