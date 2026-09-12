import 'dart:io';

import 'package:test/test.dart';

/// Arms `tool/abi_layout_check.dart` so the layout check actually runs.
///
/// WHY THIS FILE EXISTS. The sibling `native_abi_guard_test.dart` guards the ABI
/// *version symbol*: it refuses a library that does not declare the contract.
/// That is a different question from this one. A library can declare version 2
/// and still be described wrongly by the Dart binding — the version number says
/// the contract was bumped, not that the struct on the other side of the call
/// has the layout Dart thinks it has.
///
/// The gap is not theoretical for this struct. `SimulationResponse` is six
/// 4-byte scalars, so every permutation of its fields has size 24 and alignment
/// 4. Reorder two fields in the Dart binding and nothing about the size, the
/// alignment or the ABI version changes — `overallMean` simply starts returning
/// `executionMs`'s bytes. That is the same shape as the defect measured on
/// 2026-09-12, where a stale library returned a saturated 1.000 on a 0-1 safety
/// scale with no crash and no log line.
///
/// A check nobody runs is decoration, and this unit has a long ledger of
/// instruments that were built and never armed. These tests are the arming.
void main() {
  final root = Directory.current.path;
  final tool = File('$root/tool/abi_layout_check.dart');

  String? findCompiler() {
    for (final candidate in const ['cc', 'clang', 'gcc']) {
      if (Process.runSync('which', [candidate]).exitCode == 0) return candidate;
    }
    return null;
  }

  group('FFI struct layout', () {
    test('the check fires on a known-bad pair and stays quiet on a good one', () {
      if (!tool.existsSync() || findCompiler() == null) {
        markTestSkipped('needs tool/abi_layout_check.dart and a C compiler');
        return;
      }
      final result = Process.runSync(
        Platform.resolvedExecutable,
        ['run', tool.path, '--self-test'],
        workingDirectory: root,
      );
      // The self-test proves three things at once: it FIRES on a field reorder
      // that size-and-alignment alone cannot see, it FIRES on a dropped
      // __attribute__((aligned(n))), and it does NOT fire on a matched pair.
      // Each expectation names the reason, so a tool that merely chokes on
      // every input cannot pass by throwing.
      expect(
        result.exitCode,
        0,
        reason:
            'the layout check failed its own self-test, so nothing it says '
            'about the real struct can be trusted:\n${result.stdout}\n'
            '${result.stderr}',
      );
      expect(result.stdout, contains('SELF-TEST PASSED'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('the shipped C struct and the Dart binding agree field by field', () {
      if (!tool.existsSync() || findCompiler() == null) {
        markTestSkipped('needs tool/abi_layout_check.dart and a C compiler');
        return;
      }
      final result = Process.runSync(
        Platform.resolvedExecutable,
        [
          'run',
          tool.path,
          '--c',
          'native/native_simulation.c',
          '--dart',
          'lib/src/simulation/native_simulation_bindings.dart',
          '--pair',
          'SimulationResponse=NativeSimulationResponse',
        ],
        workingDirectory: root,
      );
      expect(
        result.exitCode,
        0,
        reason:
            'the Dart binding does not describe the C struct it calls. A call '
            'across this boundary returns a plausible number, not an error:\n'
            '${result.stdout}\n${result.stderr}',
      );
      // Assert the measurement actually happened. Exit 0 alone would also be
      // returned by a check that verified nothing, and "verified" that reported
      // no field is the failure mode this whole file exists to refuse.
      expect(result.stdout, contains('overall_mean@0+4'));
      expect(result.stdout, contains('execution_ms@20+4'));
      expect(result.stdout, contains('every field offset'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
