// THE RELEASE-MODE MATRIX CELL.
//
// `dart test` and `flutter test` always run with asserts ENABLED. Measured
// 2026-09-13 on Dart 3.11.1:
//
//     dart test                         asserts ON
//     dart run file.dart                asserts OFF
//     dart compile exe                  asserts OFF
//     dart compile exe --enable-asserts  asserts ON
//
// So every test result this package had ever produced was taken in the one mode
// where an assert-based guard is present, and the mode that reaches a driver —
// AOT, asserts stripped — had no test at all. Constructor validation here was
// five asserts; all five were present in every test run and in no shipped
// build, and no test had ever constructed an invalid monitor in any mode.
//
// This file compiles `tool/release_guard_probe.dart` to a NATIVE EXECUTABLE and
// runs it, so the constructor guards are exercised in the mode that ships.
//
// It also proves the instrument before trusting its verdict — the same
// discipline scripts/sibling_constraint_check.py --self-test applies in CI. The
// second test builds the same probe WITH asserts enabled and requires it to
// refuse a verdict (exit 2). Without that, a probe that had quietly stopped
// being release-representative would keep reporting green.

import 'dart:io';

import 'package:test/test.dart';

/// Compile [source] to a native executable in [dir] and run it.
({int exitCode, String stdout}) _compileAndRun(
  Directory dir,
  String source, {
  bool enableAsserts = false,
}) {
  final out = '${dir.path}/probe_${enableAsserts ? 'asserts' : 'release'}';
  final compile = Process.runSync(
    Platform.resolvedExecutable,
    <String>[
      'compile',
      'exe',
      source,
      '-o',
      out,
      if (enableAsserts) '--enable-asserts',
    ],
  );
  if (compile.exitCode != 0) {
    fail('dart compile exe failed (${compile.exitCode}):\n'
        '${compile.stdout}\n${compile.stderr}');
  }
  final run = Process.runSync(out, const <String>[]);
  return (exitCode: run.exitCode, stdout: '${run.stdout}${run.stderr}');
}

void main() {
  late Directory tmp;
  const probe = 'tool/release_guard_probe.dart';

  setUpAll(() => tmp = Directory.systemTemp.createTempSync('pi_release_guard'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  test(
    'constructor guards still reject invalid configuration in an AOT build '
    'with asserts stripped — the mode that reaches a driver',
    () {
      final r = _compileAndRun(tmp, probe);
      printOnFailure(r.stdout);

      // The probe self-reports its mode. If this line ever says true, the
      // binary is not release-representative and its green means nothing.
      expect(
        r.stdout,
        contains('asserts_enabled=false'),
        reason: 'the probe must run with asserts stripped or it proves nothing',
      );
      expect(
        r.stdout,
        contains('RELEASE-GUARD-PROBE: OK'),
        reason: 'a guard did not fire in release mode:\n${r.stdout}',
      );
      expect(r.exitCode, 0, reason: r.stdout);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'the probe refuses to return a verdict when it is built with asserts '
    'enabled — proving this cell can tell the two modes apart',
    () {
      final r = _compileAndRun(tmp, probe, enableAsserts: true);
      printOnFailure(r.stdout);

      expect(r.stdout, contains('asserts_enabled=true'));
      expect(
        r.stdout,
        contains('PROBE-INVALID'),
        reason: 'the probe reported a verdict from a build it cannot vouch '
            'for; it would keep reporting green after it stopped being '
            'release-representative',
      );
      expect(r.exitCode, 2, reason: r.stdout);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
