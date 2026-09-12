// SPDX-FileCopyrightText: 2026 Akihiko Komada <aki1770@gmail.com>
// SPDX-License-Identifier: Apache-2.0

// Wires driving_conditions/tool/abi_layout_check.dart onto this package's one
// Dart-declared-meets-C-declared layout, and runs it as a test.
//
// WHY THIS IS A TEST AND NOT A NOTE IN THE README. `sngnav_road_friction_t` is
// the only struct in this package declared twice — once in C, once in Dart —
// and a disagreement between the two does not crash. It produces a plausible
// wrong number: `friction_percent` reading `measured_at_unix_ns`'s bytes is a
// finite double that classify() will happily turn into a grip verdict.
//
// A size-and-alignment check is NOT sufficient here and that is measured, not
// assumed: this morning such a check passed a deliberate field reorder on a
// six-scalar struct, because every permutation had the same size. The tool
// below compares per-field OFFSET and WIDTH, matched BY NAME.
//
// It measures the HOST architecture only. Green here says nothing about the
// aarch64 IVI target — see README.md.

import 'dart:io';

import 'package:test/test.dart';

/// Fails with a loud UNVERIFIED rather than skipping. A skipped layout check
/// reads, in a CI summary, exactly like a passing one.
Never _unverified(String what, String why) {
  fail(
    'UNVERIFIED — the ABI layout check did not run: $what\n'
    '$why\n'
    'This is NOT a pass. The Dart and C declarations of '
    'sngnav_road_friction_t are unchecked against each other.',
  );
}

void main() {
  test(
    'sngnav_road_friction_t: Dart and C layouts agree, field by field',
    () {
      final pkg = Directory.current.path;

      final tool = File(
        '$pkg/../driving_conditions/tool/abi_layout_check.dart',
      );
      if (!tool.existsSync()) {
        _unverified('the checker is missing', 'expected at ${tool.path}');
      }

      final header = File('$pkg/native/sngnav_road_friction.h');
      if (!header.existsSync()) {
        _unverified(
          'the C header is missing',
          'expected at ${header.path} — the native half has not landed.',
        );
      }

      // Find the Dart binding by its SHAPE rather than by a hard-coded filename,
      // so that renaming it on the FFI side surfaces as a real mismatch instead
      // of a silently unrun check.
      //
      // The optional `ffi.` prefix is not cosmetic. `import 'dart:ffi' as ffi;`
      // is ordinary Dart and is what the binding here actually uses; a regex
      // demanding the unprefixed spelling finds nothing and reports UNVERIFIED on
      // a perfectly good struct. This test made exactly that mistake on its first
      // run against the real binding.
      final ffiDir = Directory('$pkg/lib/src/ffi');
      if (!ffiDir.existsSync()) {
        _unverified('lib/src/ffi is missing', 'the FFI half has not landed.');
      }
      final structRe = RegExp(
        r'(?:final\s+|base\s+|sealed\s+)*class\s+(\w+)\s+extends\s+(?:\w+\.)?Struct\s*\{',
      );
      // The struct is identified by the fields it declares, not by being the
      // first one in the directory. There is more than one `extends Struct` under
      // lib/src/ffi, and checking whichever happened to sort first would verify
      // the wrong layout while reporting success.
      String norm(String s) => s.toLowerCase().replaceAll('_', '');
      const required = [
        'friction_percent',
        'measured_at_unix_ns',
        'sequence',
        'quality',
      ];
      File? bindingFile;
      String? dartClass;
      for (final f
          in ffiDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        for (final m in structRe.allMatches(src)) {
          final close = src.indexOf('}', m.end);
          if (close < 0) continue;
          final body = src.substring(m.end, close);
          final bodyNorm = norm(body);
          if (required.every((r) => bodyNorm.contains(norm(r)))) {
            bindingFile = f;
            dartClass = m.group(1);
            break;
          }
        }
        if (bindingFile != null) break;
      }
      if (bindingFile == null || dartClass == null) {
        _unverified(
          'no `class ... extends Struct` declaring ${required.join(", ")} '
              'was found under lib/src/ffi',
          'The C struct is declared but nothing in Dart claims to match it.',
        );
      }

      final r = Process.runSync('dart', [
        'run',
        tool.path,
        '--c',
        header.path,
        '--dart',
        bindingFile.path,
        '--pair',
        'sngnav_road_friction_t=$dartClass',
      ]);

      final output = '${r.stdout}${r.stderr}';
      printOnFailure(output);

      // Exit 2 is the checker's "could not verify". It must never read as a pass.
      if (r.exitCode == 2) {
        fail(
          'UNVERIFIED — the layout check ran but refused to report agreement.\n'
          '$output',
        );
      }
      expect(
        r.exitCode,
        0,
        reason: 'C/Dart layout MISMATCH on sngnav_road_friction_t.\n$output',
      );

      // The check prints a per-field table on success; assert the shape of the
      // struct we actually expect, so that a future edit that changes it has to
      // change this line too.
      expect(
        output,
        contains('size=24 align=8'),
        reason: 'the wire struct must stay 24 bytes / align 8',
      );
      for (final field in const [
        'friction_percent',
        'measured_at_unix_ns',
        'sequence',
        'quality',
      ]) {
        expect(
          output,
          contains(field),
          reason: '$field was not compared — a dropped field is a silent hole',
        );
      }
      expect(
        output,
        contains('agrees on size, alignment and every field offset'),
      );

      stdout.writeln(output);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
