import 'dart:ffi';
import 'dart:io';

// NativeSimulationAbiMismatch comes from the PUBLIC surface deliberately: a
// consumer must be able to catch it by type, and importing it this way makes
// that reachability part of what this test asserts.
import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_conditions/src/simulation/native_simulation_bindings.dart'
    show NativeSimulationBindings;
import 'package:test/test.dart';

/// Guards the ABI contract between `native/native_simulation.c` and the Dart
/// bindings.
///
/// WHY THIS EXISTS, measured 2026-09-12: `native/build/libsimulation_engine.so`
/// was 166 days older than the source it must match. `simulation_run_batch`
/// had gone from seven arguments to six in 0.7.0, so the call crossed a
/// mismatched ABI — and it did NOT crash. It returned `overall = 1.0` exactly,
/// the top of the scale, where the pure-Dart engine returned 0.578. A saturated
/// **safe** reading on a safety score, with no exception, no load error and no
/// log line. A driver would have been told conditions were better than measured.
///
/// The parity test next door catches that — but only if it runs, and it SKIPS
/// when the library is absent. This test verifies the runtime guard instead: a
/// library that does not declare the expected contract must be REFUSED, not
/// read.
///
/// The stale library is not checked in as a fixture. It is generated from the
/// real shipped source with the version symbol removed, so the replica cannot
/// drift away from what actually ships.
void main() {
  final sourceFile = File(
    '${Directory.current.path}/native/native_simulation.c',
  );

  group('native ABI guard', () {
    // ⚑ THIS GROUP NO LONGER SKIPS SILENTLY, measured 2026-09-23. The two
    // tests below used to `markTestSkipped` when the .so or a compiler was
    // absent. The .so is gitignored, so on EVERY developer checkout this
    // file's first test reported green having verified nothing — the guard
    // built for the 2026-09-12 stale-library defect, the one where a saturated
    // `overall = 1.000` reached a safety score with no crash and no log line,
    // was failing open on every machine but CI. A skip reads exactly like a
    // pass in every runner and every summary.
    //
    // The rule applied here: a skip is honest only when the thing CANNOT exist
    // on this platform. It is not honest when the thing is merely absent on a
    // platform where it should be present. The check that needs neither a
    // compiler nor a built library is separated out first, so that one runs
    // everywhere, always.

    test(
      'the C source and the Dart binding declare the SAME ABI version — the '
      'drift that produces a stale library in the first place',
      () {
        // Needs no compiler and no .so, so it runs on every platform and every
        // checkout. This is the assertion that used to be unavailable whenever
        // the library was missing.
        expect(
          sourceFile.existsSync(),
          isTrue,
          reason:
              'native/native_simulation.c is tracked in git. A checkout '
              'without it can verify nothing about the native engine.',
        );
        final declared = RegExp(
          r'#define\s+SIMULATION_ABI_VERSION\s+(\d+)u?',
        ).firstMatch(sourceFile.readAsStringSync());
        expect(
          declared,
          isNotNull,
          reason:
              'SIMULATION_ABI_VERSION is no longer declared in the C source, '
              'so nothing pins the contract the Dart side verifies against.',
        );
        expect(
          int.parse(declared!.group(1)!),
          NativeSimulationBindings.expectedAbiVersion,
          reason:
              'the C source declares a different ABI version than the Dart '
              'binding requires. Whichever side moved, a library built from '
              'this source will be REFUSED by this binding — or, if the Dart '
              'side moved down, silently mis-read.',
        );
      },
    );

    test(
      'the default library is ABI-verified when present and REFUSED when '
      'absent — it is never silently read',
      () {
        // NOT a skip in any branch. Absence is the normal state of a fresh
        // checkout, and the honest assertion about absence is that it FAILS AT
        // LOAD rather than resolving to some other library on the search path.
        String? defaultPath;
        try {
          defaultPath = NativeSimulationBindings.defaultLibraryPath();
        } on UnsupportedError {
          defaultPath = null;
        }

        if (defaultPath == null) {
          expect(
            () => NativeSimulationBindings(),
            throwsA(isA<UnsupportedError>()),
            reason:
                'on a platform with no native build path, constructing '
                'bindings must refuse rather than read something else',
          );
          return;
        }

        if (File(defaultPath).existsSync()) {
          expect(
            () => NativeSimulationBindings(),
            returnsNormally,
            reason:
                'the built library at $defaultPath does not declare ABI '
                'version ${NativeSimulationBindings.expectedAbiVersion}, so it '
                'is STALE. Rebuild it: cd native && cmake --build build',
          );
        } else {
          // SPECIFIC, not `throwsA(anything)`. Measured: an absent library
          // raises ArgumentError carrying 'Failed to load dynamic library'.
          // Matching ANY throw would also be satisfied by an ABI mismatch, by
          // an UnsupportedError, or by a bug in this test — the same
          // substitute-a-proxy-for-the-thing move as gating on the platform.
          expect(
            () => NativeSimulationBindings(),
            throwsA(
              isA<ArgumentError>().having(
                (e) => e.toString(),
                'message',
                contains('Failed to load dynamic library'),
              ),
            ),
            reason:
                'there is no library at $defaultPath, so constructing bindings '
                'MUST fail AT LOAD. If it returns, a different library was '
                'loaded and every number it produces is unverified; if it '
                'fails some other way, the failure is not the one claimed.',
          );
        }
      },
    );

    test(
      'a library predating the contract is REFUSED, never read',
      () {
        // ⚑ THIS GATE READ `!Platform.isLinux`, JUSTIFIED AS A CAPABILITY
        // CLAIM. That substituted a proxy for the thing itself — the same move
        // the fail-open in this file was made of. The question is not what
        // platform this is; it is whether this toolchain can build a shared
        // object that `DynamicLibrary` will load. So it is MEASURED, by doing
        // it. Whether the answer differs from `Platform.isLinux` anywhere is
        // itself unmeasured, and this replaces a guess with a check rather
        // than claiming to know.
        // ⚑ AND THE FIRST VERSION OF THIS PROBE REOPENED THE FAIL-OPEN IT
        // WAS WRITTEN TO CLOSE. It folded "no C compiler" into "capability
        // unavailable" and the caller skipped on it, so on a compiler-free
        // path this file went from exit 1 to exit 0, "All tests passed",
        // and the assertion below became unreachable in the one case it was
        // written for. The two are NOT the same fact:
        //
        //   no compiler            -> merely ABSENT where it should be
        //                             present. RED, by the same rule that
        //                             closed the fail-open in the first place.
        //   compiler present, but
        //   cannot produce a
        //   loadable shared object -> the capability genuinely does not exist
        //                             here. The one honest skip.
        final probe = _sharedObjectCapability();
        expect(
          probe.verdict,
          isNot(_ToolchainVerdict.noCompiler),
          reason:
              'NO C COMPILER ON PATH (looked for cc, clang, gcc), so THE '
              'STALE-LIBRARY GUARD DID NOT RUN. This is the guard for the '
              '2026-09-12 defect in which a mismatched library returned a '
              'saturated safety score with no crash and no log line. Install a '
              'C compiler; do not read this as a pass. Measured: '
              '${probe.reason}',
        );
        if (probe.verdict == _ToolchainVerdict.cannotBuildSharedObject) {
          markTestSkipped(
            'a compiler IS present but this toolchain cannot produce a '
            'loadable shared object, measured: ${probe.reason}. The ABI-drift '
            'test above still ran and still asserted.',
          );
          return;
        }
        // Below this line, absence is a MISSING PRECONDITION on a platform
        // where it should be present, so it is red rather than skipped.
        expect(
          sourceFile.existsSync(),
          isTrue,
          reason:
              'native/native_simulation.c is tracked in git, so on Linux its '
              'absence is a broken checkout, not a reason to pass.',
        );
        final cc = _findCompiler();
        expect(
          cc,
          isNotNull,
          reason:
              'NO C COMPILER ON PATH (looked for cc, clang, gcc), so THE '
              'STALE-LIBRARY GUARD DID NOT RUN. This is the guard for the '
              '2026-09-12 defect in which a mismatched library returned a '
              'saturated safety score with no crash. Install a C compiler; do '
              'not read this as a pass.',
        );

        final tmp = Directory.systemTemp.createTempSync('abi_guard');
        addTearDown(() => tmp.deleteSync(recursive: true));

        // Reproduce a pre-contract binary: the real source with the version
        // export stripped. Everything else — including the CURRENT six-argument
        // signature — stays, which makes this strictly harder to catch than the
        // real 0.6.x case and proves the guard does not rely on a call failing.
        final stripped = sourceFile
            .readAsStringSync()
            .replaceAll(
              RegExp(
                r'uint32_t simulation_abi_version\(void\) \{[^}]*\}',
                multiLine: true,
              ),
              '',
            );
        expect(
          stripped.contains('simulation_abi_version(void) {'),
          isFalse,
          reason: 'the replica must not export the version symbol',
        );

        final src = File('${tmp.path}/old.c')..writeAsStringSync(stripped);
        final out = '${tmp.path}/libold.so';
        final build = Process.runSync(cc!, [
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
          reason: 'replica failed to build: ${build.stderr}',
        );

        final old = DynamicLibrary.open(out);

        expect(
          () => NativeSimulationBindings(library: old),
          throwsA(isA<NativeSimulationAbiMismatch>()),
          reason:
              'a library with no version symbol must be refused at load — '
              'the alternative is a plausible, saturated safety score',
        );
      },
    );

    test('the refusal says what to do about it', () {
      final error = NativeSimulationAbiMismatch(
        expected: NativeSimulationBindings.expectedAbiVersion,
        found: null,
        path: '/somewhere/libsimulation_engine.so',
      );
      final text = error.toString();
      // A guard that fires without telling the reader how to clear it just
      // moves the confusion; assert the remedy travels with the refusal.
      expect(text, contains('cmake --build build'));
      expect(text, contains('/somewhere/libsimulation_engine.so'));
      expect(text, contains('predates the ABI contract'));
      // A vendored consumer's native/ is the OLD one, so "rebuild" alone
      // recompiles the old C and is refused again, forever. The remedy must
      // name the re-copy FIRST or it is an infinite loop with instructions.
      expect(text, contains('UPGRADED package'));
      expect(text, contains('native_simulation.c'));
      // Must NOT name a version range: a correctly-built library from before
      // the contract also exports no symbol, so "0.6.x or older" would state
      // something untrue about a sound build.
      expect(text, isNot(contains('0.6.x')));
    });

    test('a WRONG version is refused as firmly as a missing one', () {
      final error = NativeSimulationAbiMismatch(
        expected: 2,
        found: 1,
        path: '/x.so',
      );
      expect(error.toString(), contains('reports ABI version 1'));
      expect(error.found, 1);
      expect(error.expected, 2);
    });
  });
}

String? _findCompiler() {
  for (final candidate in const ['cc', 'clang', 'gcc']) {
    final which = Process.runSync('which', [candidate]);
    if (which.exitCode == 0) {
      return candidate;
    }
  }
  return null;
}

/// The three outcomes, kept apart because folding the first two together is
/// exactly how this file's fail-open was reopened.
enum _ToolchainVerdict {
  /// A compiler built a shared object and `DynamicLibrary` opened it.
  ok,

  /// No compiler on PATH. ABSENT where it should be present — this is RED.
  noCompiler,

  /// A compiler is present and cannot produce a loadable shared object. The
  /// capability genuinely does not exist here — this is the honest skip.
  cannotBuildSharedObject,
}

typedef _Capability = ({_ToolchainVerdict verdict, String reason});

/// Measures whether this toolchain can build a shared object that
/// `DynamicLibrary` will open — by building a trivial one and opening it.
///
/// Replaces a `Platform.isLinux` test that stood in for this question. A proxy
/// is what the first fail-open in this file was made of.
_Capability _sharedObjectCapability() {
  final cc = _findCompiler();
  if (cc == null) {
    return (
      verdict: _ToolchainVerdict.noCompiler,
      reason: 'no C compiler on PATH (looked for cc, clang, gcc)',
    );
  }
  Directory? tmp;
  try {
    tmp = Directory.systemTemp.createTempSync('so_capability');
    final src = File('${tmp.path}/probe.c')
      ..writeAsStringSync('int probe_symbol(void) { return 7; }\n');
    final out = '${tmp.path}/libprobe.so';
    final build = Process.runSync(cc, ['-shared', '-fPIC', '-o', out, src.path]);
    if (build.exitCode != 0) {
      return (
        verdict: _ToolchainVerdict.cannotBuildSharedObject,
        reason: '$cc could not build a shared object: ${build.stderr}',
      );
    }
    DynamicLibrary.open(
      out,
    ).lookup<NativeFunction<Int32 Function()>>('probe_symbol');
    return (
      verdict: _ToolchainVerdict.ok,
      reason: 'built and loaded a probe object with $cc',
    );
  } on Object catch (e) {
    return (
      verdict: _ToolchainVerdict.cannotBuildSharedObject,
      reason: 'probe object would not load: $e',
    );
  } finally {
    try {
      tmp?.deleteSync(recursive: true);
    } on FileSystemException {
      // Nothing to clean up is not a capability finding.
    }
  }
}
