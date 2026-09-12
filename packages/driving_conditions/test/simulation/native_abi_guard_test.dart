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
  final realLibrary = File(
    '${Directory.current.path}/native/build/libsimulation_engine.so',
  );

  group('native ABI guard', () {
    test('the shipped library declares the expected contract', () {
      if (!Platform.isLinux || !realLibrary.existsSync()) {
        markTestSkipped('needs a built libsimulation_engine.so on Linux');
        return;
      }
      // Constructing IS the assertion: the constructor verifies the ABI and
      // throws on mismatch.
      expect(NativeSimulationBindings(), isA<NativeSimulationBindings>());
    });

    test(
      'a library predating the contract is REFUSED, never read',
      () {
        if (!Platform.isLinux || !sourceFile.existsSync()) {
          markTestSkipped('needs the C source on Linux');
          return;
        }
        final cc = _findCompiler();
        if (cc == null) {
          markTestSkipped('no C compiler on PATH');
          return;
        }

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
