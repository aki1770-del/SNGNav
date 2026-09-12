#!/usr/bin/env dart
// Differential ABI layout check for a `dart:ffi` boundary.
//
// METHOD AND AUTHORSHIP
// ---------------------
// The method is RUST-SYSTEMS-ENGINEER's (RSE), built 2026-09-12 while measuring
// Eclipse iceoryx2: emit C `sizeof`/`_Alignof` for every struct, emit the Dart
// `sizeOf` for its binding, diff. On its first run it caught a real defect —
// `ffigen`, the standard generator, silently drops `__attribute__((aligned(n)))`,
// producing 2 wrong struct sizes out of 60 with no warning and no `@ffi.Align`
// anywhere in 25,581 generated lines. This file preserves that method out of a
// session-scoped scratch directory and wires it onto a surface we ship.
//
// FDD added per-field offsets, and the reason is not decoration. Measured
// 2026-09-12 on this package's own struct: `SimulationResponse` is six 4-byte
// scalars, so EVERY permutation of its fields has size 24 and alignment 4. A
// size-and-alignment check returns CLEAN on a binding where `overallMean` reads
// `executionMs`'s bytes. That is the same failure shape that produced a
// saturated 1.000 safety score on a 0-1 scale from a stale library — a
// plausible number, no crash, no log line. So this check compares, per field:
// OFFSET, WIDTH, and then struct SIZE and ALIGNMENT.
//
// Neither side is trusted to declare its own layout. The C side is measured by
// the compiler (`offsetof`, `sizeof`, `_Alignof`). The Dart side is measured at
// runtime: fill the struct with 0xFF, write the zero value of one field, and the
// run of 0x00 bytes IS that field's offset and width. Dart exposes no `offsetOf`
// and no `alignOf`; both are derived by measurement, never by reading an
// annotation and believing it.
//
// Fields are matched BY NAME, never by declaration position. Comparing field i
// to field i is very nearly a tautology, because each lane derives its offsets
// from its own declaration order — and the first run of this file's self-test
// PASSED a deliberately reordered fixture for exactly that reason. The check
// earned its own first defect before it was ever pointed at real code.
//
// WHAT THIS CHECK CANNOT SEE — stated on its face, because a guard whose bounds
// are unstated gets read as covering more than it does:
//   * It measures the HOST architecture only. Run it on each target you ship to.
//     `--emit-c-only --cc <cross-gcc> --cc-arg -static --run-with qemu-...`
//     measures the C half for another architecture; the Dart half needs a Dart
//     SDK for that target, and there is no way around that from here.
//   * Flat scalar fields only. Pointers, nested structs, arrays, bitfields,
//     unions and function pointers are REFUSED, loudly, never skipped quietly.
//   * It checks the STRUCT, not the function signature. The 0.6.x defect this
//     package carries was an arity change — seven arguments to six — and this
//     check would not have seen it. `simulation_abi_version` guards that; the
//     two are complementary and neither replaces the other.
//   * A field whose zero value is not all-zero bytes would not be located. Every
//     type this tool accepts has an all-zero zero (IEEE-754 +0.0 included).
//
// WHAT IT MEASURED HERE, 2026-09-12, so a later reader can see the bound move:
//   x86_64  C SimulationResponse size=24 align=4, fields at 0/4/8/12/16/20
//           Dart NativeSimulationResponse — identical on all eight numbers.
//   aarch64 C side MEASURED (aarch64-linux-gnu-gcc + qemu-aarch64-static):
//           byte-identical to x86_64. The caution that ARM padding would differ
//           does not hold for this struct — six 4-byte scalars, no alignment
//           attributes, nothing for the ABIs to disagree about.
//           The Dart half on aarch64 is UNVERIFIED. There is no aarch64 Dart SDK
//           on the host that ran this, so the PAIR has never been compared on
//           the architecture the IVI target actually runs. Not cleared. Run this
//           file on the target.
//
// USAGE
//   dart run tool/abi_layout_check.dart \
//     --c native/native_simulation.c \
//     --dart lib/src/simulation/native_simulation_bindings.dart \
//     --pair SimulationResponse=NativeSimulationResponse
//
//   dart run tool/abi_layout_check.dart --self-test
//
// Exit 0 = layouts agree. Exit 1 = mismatch. Exit 2 = the tool could not read
// something and refuses to report agreement it did not verify.

import 'dart:io';

const int exitOk = 0;
const int exitMismatch = 1;
const int exitUnverifiable = 2;

/// A field as the C compiler or the Dart VM actually lays it out.
class FieldLayout {
  FieldLayout(this.name, this.offset, this.width);
  final String name;
  final int offset;
  final int width;
  @override
  String toString() => '$name@$offset+$width';
}

class StructLayout {
  StructLayout(this.name, this.size, this.align, this.fields);
  final String name;
  final int size;
  final int align;
  final List<FieldLayout> fields;
}

/// Raised when the tool cannot read its input. Never downgraded to a pass.
class Unverifiable implements Exception {
  Unverifiable(this.message);
  final String message;
  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Source parsing. Deliberately narrow: anything it does not fully understand is
// refused rather than guessed at.
// ---------------------------------------------------------------------------

/// Field names of C struct [typeName], in declaration order.
List<String> parseCStructFields(String source, String typeName) {
  final body = _cStructBody(source, typeName);
  final fields = <String>[];
  for (var raw in body.split(';')) {
    final line = raw.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '').trim();
    if (line.isEmpty) continue;
    for (final bad in const ['*', '[', '(', ':', '{']) {
      if (line.contains(bad)) {
        throw Unverifiable(
          'C struct "$typeName" declares "$line", which contains "$bad".\n'
          'Pointers, arrays, bitfields, function pointers and nested aggregates '
          'are outside what this check can verify. Refusing to report agreement '
          'on a struct it cannot fully read.',
        );
      }
    }
    final match = RegExp(r'([A-Za-z_]\w*)\s*$').firstMatch(line);
    if (match == null) {
      throw Unverifiable('Cannot read field declaration "$line" in "$typeName".');
    }
    fields.add(match.group(1)!);
  }
  if (fields.isEmpty) {
    throw Unverifiable('C struct "$typeName" parsed to zero fields.');
  }
  return fields;
}

/// Returns the brace-matched body of C struct [typeName].
String _cStructBody(String source, String typeName) {
  // `typedef struct [tag] { ... } [__attribute__((...))] TypeName;`
  for (final open in _indicesOf(source, 'struct')) {
    final brace = source.indexOf('{', open);
    if (brace < 0) continue;
    final between = source.substring(open + 'struct'.length, brace);
    if (between.contains(';') || between.contains('}')) continue;
    final close = _matchBrace(source, brace);
    if (close < 0) continue;
    // Tagged form: `struct TypeName { ... };`
    if (between.trim() == typeName) {
      return source.substring(brace + 1, close);
    }
    // Typedef form: the name is the last identifier before the `;`. Read it
    // that way rather than stripping attributes: `__attribute__((aligned(16)))`
    // has nested parens, and a non-greedy strip leaves a stray `)` behind —
    // which is how this parser first failed on the very case RSE built the
    // method to catch.
    var tail = source.substring(close + 1);
    final end = tail.indexOf(';');
    if (end < 0) continue;
    tail = tail.substring(0, end).trim();
    if (tail.contains(',')) {
      throw Unverifiable(
        'typedef declares several names ("$tail"). Refusing to guess which one '
        'is "$typeName".',
      );
    }
    final named = RegExp(r'([A-Za-z_]\w*)\s*$').firstMatch(tail);
    if (named != null && named.group(1) == typeName) {
      return source.substring(brace + 1, close);
    }
  }
  throw Unverifiable(
    'C struct "$typeName" not found. This check reads '
    '`typedef struct {...} Name;` and `struct Name {...};` only.',
  );
}

Iterable<int> _indicesOf(String haystack, String needle) sync* {
  var i = haystack.indexOf(needle);
  while (i >= 0) {
    yield i;
    i = haystack.indexOf(needle, i + 1);
  }
}

int _matchBrace(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// A Dart `Struct` field: its native annotation and its name.
class DartField {
  DartField(this.annotation, this.name);
  final String annotation;
  final String name;

  /// The literal that writes this field's all-zero representation.
  String get zeroLiteral {
    if (annotation == 'Float' || annotation == 'Double') return '0.0';
    if (annotation == 'Bool') return 'false';
    return '0';
  }
}

const Set<String> _supportedAnnotations = {
  'Int8', 'Int16', 'Int32', 'Int64',
  'Uint8', 'Uint16', 'Uint32', 'Uint64',
  'Float', 'Double', 'Bool',
};

List<DartField> parseDartStructFields(String source, String className) {
  final decl = RegExp(
    r'(?:final\s+|base\s+|sealed\s+)*class\s+' + RegExp.escape(className) +
        r'\s+extends\s+Struct\s*\{',
  ).firstMatch(source);
  if (decl == null) {
    throw Unverifiable(
      'Dart class "$className extends Struct" not found in the given file.',
    );
  }
  final close = _matchBrace(source, decl.end - 1);
  if (close < 0) throw Unverifiable('Unbalanced braces in "$className".');
  final body = source.substring(decl.end, close);

  if (RegExp(r'external\s+Pointer\s*<').hasMatch(body) ||
      RegExp(r'@Array').hasMatch(body)) {
    throw Unverifiable(
      'Dart class "$className" declares a Pointer or an @Array field. This '
      'check verifies flat scalar structs only, and refuses rather than report '
      'agreement it did not measure.',
    );
  }

  final fields = <DartField>[];
  final pattern = RegExp(
    r'@(\w+)\s*\(\s*\)\s*(?://[^\n]*\n|\s)*external\s+(?:double|int|bool)\s+(\w+)\s*;',
  );
  for (final m in pattern.allMatches(body)) {
    final annotation = m.group(1)!;
    if (!_supportedAnnotations.contains(annotation)) {
      throw Unverifiable(
        'Dart class "$className" uses @$annotation, which this check does not '
        'know how to zero. Refusing rather than skipping the field.',
      );
    }
    fields.add(DartField(annotation, m.group(2)!));
  }

  // A declared field the pattern did not capture would be silently dropped, and
  // a check that silently drops a field is worse than no check.
  final declared = RegExp(r'\bexternal\b').allMatches(body).length;
  if (declared != fields.length) {
    throw Unverifiable(
      'Dart class "$className" declares $declared external fields but this '
      'check could only read ${fields.length}. Refusing to verify a partial '
      'struct.',
    );
  }
  if (fields.isEmpty) throw Unverifiable('Dart class "$className" has no fields.');
  return fields;
}

// ---------------------------------------------------------------------------
// Measurement. The compiler measures C; the Dart VM measures Dart.
// ---------------------------------------------------------------------------

StructLayout measureC({
  required String cPath,
  required String typeName,
  required List<String> fieldNames,
  required String compiler,
  required List<String> includes,
  required Directory work,
  bool runIt = true,
  List<String> extraCcArgs = const [],
  String? runner,
}) {
  final abs = File(cPath).absolute.path;
  final buf = StringBuffer()
    ..writeln('#include <stdio.h>')
    ..writeln('#include <stddef.h>')
    ..writeln('#include "$abs"')
    ..writeln('int main(void){')
    ..writeln('  printf("STRUCT %zu %zu\\n", sizeof($typeName), _Alignof($typeName));');
  for (final f in fieldNames) {
    buf.writeln(
      '  printf("FIELD $f %zu %zu\\n", offsetof($typeName, $f), '
      'sizeof((($typeName*)0)->$f));',
    );
  }
  buf.writeln('  return 0; }');

  final src = File('${work.path}/abi_c_probe.c')..writeAsStringSync(buf.toString());
  final bin = '${work.path}/abi_c_probe';
  final args = <String>[
    '-O0',
    ...extraCcArgs,
    '-o', bin,
    src.path,
    for (final inc in includes) '-I$inc',
    '-lm',
  ];
  final build = Process.runSync(compiler, args);
  if (build.exitCode != 0) {
    throw Unverifiable('C probe failed to build with $compiler:\n${build.stderr}');
  }
  if (!runIt) return StructLayout(typeName, -1, -1, const []);

  final run = runner == null
      ? Process.runSync(bin, const [])
      : Process.runSync(runner, [bin]);
  if (run.exitCode != 0) {
    throw Unverifiable('C probe failed to run:\n${run.stderr}');
  }
  return _parseProbeOutput(typeName, run.stdout as String);
}

StructLayout measureDart({
  required String dartPath,
  required String className,
  required List<DartField> fields,
  required Directory work,
}) {
  final abs = File(dartPath).absolute.path;
  final buf = StringBuffer()
    ..writeln("import 'dart:ffi' as ffi;")
    ..writeln("import '$abs';")
    ..writeln('final class _AlignProbe extends ffi.Struct {')
    ..writeln('  @ffi.Uint8()')
    ..writeln('  external int pad;')
    ..writeln('  external $className inner;')
    ..writeln('}')
    ..writeln(
      'typedef _MN = ffi.Pointer<ffi.Uint8> Function(ffi.Size);\n'
      'typedef _MD = ffi.Pointer<ffi.Uint8> Function(int);\n'
      'typedef _FN = ffi.Void Function(ffi.Pointer<ffi.Uint8>);\n'
      'typedef _FD = void Function(ffi.Pointer<ffi.Uint8>);',
    )
    ..writeln('void main() {')
    ..writeln('  final size = ffi.sizeOf<$className>();')
    // Dart exposes no alignOf. struct{uint8; T} pads T up to align(T), and
    // sizeof(T) is a multiple of align(T), so the difference IS the alignment.
    ..writeln('  final align = ffi.sizeOf<_AlignProbe>() - size;')
    ..writeln(r"  print('STRUCT $size $align');")
    ..writeln('  final proc = ffi.DynamicLibrary.process();')
    ..writeln("  final malloc = proc.lookupFunction<_MN, _MD>('malloc');")
    ..writeln("  final free = proc.lookupFunction<_FN, _FD>('free');")
    ..writeln('  final p = malloc(size);')
    ..writeln('  final bytes = p.asTypedList(size);')
    ..writeln('  final s = p.cast<$className>().ref;');
  for (final f in fields) {
    buf
      ..writeln('  for (var i = 0; i < size; i++) { bytes[i] = 0xFF; }')
      ..writeln('  s.${f.name} = ${f.zeroLiteral};')
      ..writeln('  {')
      ..writeln('    var first = -1; var count = 0; var last = -1;')
      ..writeln('    for (var i = 0; i < size; i++) {')
      ..writeln('      if (bytes[i] == 0x00) { if (first < 0) first = i; last = i; count++; }')
      ..writeln('    }')
      ..writeln('    final gap = count > 0 && (last - first + 1) != count;')
      ..writeln("    print('FIELD ${f.name} \$first \$count \${gap ? 'GAPPED' : 'OK'}');")
      ..writeln('  }');
  }
  buf
    ..writeln('  free(p);')
    ..writeln('}');

  final src = File('${work.path}/abi_dart_probe.dart')
    ..writeAsStringSync(buf.toString());
  final run = Process.runSync(Platform.resolvedExecutable, ['run', src.path]);
  if (run.exitCode != 0) {
    throw Unverifiable(
      'Dart probe failed to run:\n${run.stdout}\n${run.stderr}',
    );
  }
  final out = run.stdout as String;
  if (out.contains('GAPPED')) {
    throw Unverifiable(
      'A Dart field measured as non-contiguous bytes. The measurement method '
      'does not hold for this struct; refusing to report a result.\n$out',
    );
  }
  return _parseProbeOutput(className, out);
}

StructLayout _parseProbeOutput(String name, String stdout) {
  var size = -1;
  var align = -1;
  final fields = <FieldLayout>[];
  for (final line in stdout.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) continue;
    if (parts[0] == 'STRUCT' && parts.length >= 3) {
      size = int.parse(parts[1]);
      align = int.parse(parts[2]);
    } else if (parts[0] == 'FIELD' && parts.length >= 4) {
      fields.add(FieldLayout(parts[1], int.parse(parts[2]), int.parse(parts[3])));
    }
  }
  if (size < 0) throw Unverifiable('Probe for "$name" emitted no STRUCT line.');
  return StructLayout(name, size, align, fields);
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

class Report {
  final List<String> mismatches = [];
  final List<String> warnings = [];
  final List<String> rows = [];
  bool get failed => mismatches.isNotEmpty;
}

Report compare(StructLayout c, StructLayout d) {
  final r = Report();
  r.rows.add('  C    ${c.name}: size=${c.size} align=${c.align}');
  r.rows.add('  Dart ${d.name}: size=${d.size} align=${d.align}');

  if (c.size != d.size) {
    r.mismatches.add('SIZE: C ${c.size} != Dart ${d.size}');
  }
  if (c.align != d.align) {
    r.mismatches.add(
      'ALIGN: C ${c.align} != Dart ${d.align} '
      '(this is the shape ffigen drops when a C type carries '
      '__attribute__((aligned(n))) — the binding needs @ffi.Align(${c.align}))',
    );
  }

  // Fields are matched BY NAME, never by declaration position.
  //
  // This is the correction the self-test forced, and it is the whole point of
  // the check. Each lane derives its own offsets from its own declaration
  // order, so comparing field i to field i is very nearly a tautology: swap two
  // same-width fields in the Dart binding and position 0 still holds a 4-byte
  // field at offset 0 on both sides. The first run of this self-test passed a
  // deliberately reordered fixture for exactly that reason. Keying on the name
  // asks the question that matters — is `overall_mean` where Dart thinks
  // `overallMean` is — and a reorder cannot hide from it.
  final cByName = {for (final f in c.fields) _normalize(f.name): f};
  final dByName = {for (final f in d.fields) _normalize(f.name): f};

  final onlyC = cByName.keys.where((k) => !dByName.containsKey(k)).toList();
  final onlyD = dByName.keys.where((k) => !cByName.containsKey(k)).toList();
  if (onlyC.isNotEmpty || onlyD.isNotEmpty) {
    r.mismatches.add(
      'FIELD SET: C has ${c.fields.map((f) => f.name).toList()}, '
      'Dart has ${d.fields.map((f) => f.name).toList()}. '
      'Fields cannot be put in correspondence, so no offset can be verified.',
    );
    return r;
  }

  for (var i = 0; i < c.fields.length; i++) {
    final cf = c.fields[i];
    final df = dByName[_normalize(cf.name)]!;
    final dIndex = d.fields.indexOf(df);
    final agree = cf.offset == df.offset && cf.width == df.width;
    r.rows.add(
      '    ${agree ? "ok  " : "BAD "} '
      'C[$i] ${cf.name}@${cf.offset}+${cf.width}   '
      'Dart[$dIndex] ${df.name}@${df.offset}+${df.width}',
    );
    if (!agree) {
      r.mismatches.add(
        'FIELD ${cf.name}: C @${cf.offset}+${cf.width} != '
        'Dart ${df.name} @${df.offset}+${df.width}'
        '${i != dIndex ? "  (declared at position $i in C, $dIndex in Dart — "
            "a REORDER: this field reads another field's bytes)" : ""}',
      );
    } else if (i != dIndex) {
      r.warnings.add(
        '"${cf.name}" is declared at position $i in C and $dIndex in Dart. '
        'The offsets still agree, so the ABI holds, but the declarations have '
        'drifted apart and the next edit is unlikely to be so lucky.',
      );
    }
  }
  return r;
}

String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

// ---------------------------------------------------------------------------
// Self-test. A gate never shown to fire is decoration.
// ---------------------------------------------------------------------------

const String _fixtureGoodC = '''
#include <stdint.h>
typedef struct {
  float a;
  uint32_t b;
  float c;
} Pair;
''';

const String _fixtureGoodDart = '''
import 'dart:ffi';
final class PairBinding extends Struct {
  @Float()
  external double a;
  @Uint32()
  external int b;
  @Float()
  external double c;
}
''';

// Same size (12) and same alignment (4) as the good pair. Only the ORDER moved.
// A size-and-alignment check passes this. It must not pass here.
const String _fixtureReorderedDart = '''
import 'dart:ffi';
final class PairBinding extends Struct {
  @Uint32()
  external int b;
  @Float()
  external double a;
  @Float()
  external double c;
}
''';

// RSE's original catch: the C type carries __attribute__((aligned(16))) and the
// generated Dart binding has no @Align. ffigen produces exactly this, silently.
const String _fixtureAlignedC = '''
#include <stdint.h>
typedef struct {
  uint64_t v;
} __attribute__((aligned(16))) Wide;
''';

// A struct this check must REFUSE rather than pass: a pointer field it cannot
// locate by the zero-write method.
const String _fixturePointerC = '''
#include <stdint.h>
typedef struct {
  uint32_t n;
  const char *label;
} WithPtr;
''';

const String _fixturePointerDart = '''
import 'dart:ffi';
final class WithPtrBinding extends Struct {
  @Uint32()
  external int n;
  external Pointer<Uint8> label;
}
''';

const String _fixtureAlignedDart = '''
import 'dart:ffi';
final class WideBinding extends Struct {
  @Uint64()
  external int v;
}
''';

int runSelfTest(String compiler) {
  final work = Directory.systemTemp.createTempSync('abi_selftest');
  var failures = 0;

  // Three distinct outcomes, kept apart on purpose. A tool that CHOKES on every
  // input would "fire" on both known-bad fixtures and pass a self-test that only
  // asked "did something go wrong?". The first run of this self-test did exactly
  // that: the dropped-align fixture was scored PASS while the real reason was a
  // parser bug that could not read the declaration at all. So the expected
  // outcome is named, and for a mismatch the expected REASON is named too.
  void check(
    String label,
    String cSrc,
    String dartSrc,
    String cType,
    String dartClass, {
    required String expect,
    String? because,
  }) {
    final dir = Directory('${work.path}/$label')..createSync(recursive: true);
    final cFile = File('${dir.path}/f.c')..writeAsStringSync(cSrc);
    final dFile = File('${dir.path}/f.dart')..writeAsStringSync(dartSrc);
    String outcome;
    String verdict;
    try {
      final cNames = parseCStructFields(cSrc, cType);
      final dFields = parseDartStructFields(dartSrc, dartClass);
      final cl = measureC(
        cPath: cFile.path,
        typeName: cType,
        fieldNames: cNames,
        compiler: compiler,
        includes: const [],
        work: dir,
      );
      final dl = measureDart(
        dartPath: dFile.path,
        className: dartClass,
        fields: dFields,
        work: dir,
      );
      final rep = compare(cl, dl);
      outcome = rep.failed ? 'mismatch' : 'agree';
      verdict = rep.failed
          ? rep.mismatches.join(' | ')
          : 'agrees (size=${cl.size} align=${cl.align})';
    } on Unverifiable catch (e) {
      outcome = 'unverifiable';
      verdict = '$e'.replaceAll('\n', ' ');
    }

    var pass = outcome == expect;
    if (pass && because != null && !verdict.contains(because)) {
      pass = false;
      verdict = 'RIGHT OUTCOME, WRONG REASON (wanted "$because"): $verdict';
    }
    if (!pass) failures++;
    stdout.writeln(
      '  ${pass ? "PASS" : "FAIL"}  $label\n'
      '        expected $expect${because != null ? ' because "$because"' : ''}, '
      'got $outcome',
    );
    stdout.writeln('        $verdict');
  }

  stdout.writeln('SELF-TEST — proving this check fires, and does not cry wolf.\n');

  // NEGATIVE CONTROL. A check that fires on everything protects nothing.
  check('negative-control/matched-pair', _fixtureGoodC, _fixtureGoodDart,
      'Pair', 'PairBinding', expect: 'agree');

  // The case a size-and-alignment check CANNOT see: identical size (12) and
  // identical alignment (4); only the declaration order moved. This is the
  // shape live on this package's own struct, where six 4-byte fields make every
  // permutation collide.
  check('known-bad/field-reorder', _fixtureGoodC, _fixtureReorderedDart,
      'Pair', 'PairBinding', expect: 'mismatch', because: 'REORDER');

  // RSE's original catch: ffigen silently drops __attribute__((aligned(n))).
  check('known-bad/dropped-align-attribute', _fixtureAlignedC, _fixtureAlignedDart,
      'Wide', 'WideBinding', expect: 'mismatch', because: 'ALIGN');

  // The check must REFUSE what it cannot read rather than call it agreement —
  // a guard that fails open is not a guard.
  check('refusal/pointer-field', _fixturePointerC, _fixturePointerDart,
      'WithPtr', 'WithPtrBinding', expect: 'unverifiable');

  work.deleteSync(recursive: true);
  stdout.writeln();
  if (failures == 0) {
    stdout.writeln('SELF-TEST PASSED — fires on both known-bad pairs for the '
        'stated reason, stays quiet on the matched one, and refuses what it '
        'cannot read.');
    return exitOk;
  }
  stdout.writeln('SELF-TEST FAILED: $failures case(s) behaved wrongly. '
      'This check cannot be trusted until that is fixed.');
  return exitMismatch;
}

// ---------------------------------------------------------------------------

void _usage() {
  stdout.writeln('''
abi_layout_check — differential C/Dart FFI struct layout check
  method by rust-systems-engineer (RSE), 2026-09-12; per-field offsets by FDD

  --c PATH            C source or header declaring the struct
  --dart PATH         Dart file declaring the `extends Struct` binding
  --pair C=Dart       C type name = Dart class name (repeatable)
  --include DIR       extra -I for the C probe (repeatable)
  --cc NAME           C compiler (default: cc)
  --emit-c-only       measure ONLY the C half and print it; use with --cc to
                      read a cross-compiled target's layout. Prints half a
                      check and says so — it compares nothing.
  --run-with CMD      run the compiled C probe under CMD (e.g. qemu-aarch64-static)
  --cc-arg ARG        extra argument for the C compiler, repeatable (a qemu run
                      of a cross build generally needs --cc-arg -static)
  --self-test         prove the check fires on known-bad pairs, then exit
  -h, --help          this text

Exit 0 agree · 1 mismatch · 2 could not verify (never reported as agreement).''');
}

void main(List<String> argv) {
  String? cPath;
  String? dartPath;
  var compiler = 'cc';
  final pairs = <String, String>{};
  final includes = <String>[];
  var selfTest = false;
  var cOnly = false;
  String? runWith;
  final ccArgs = <String>[];

  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    String next() {
      if (i + 1 >= argv.length) {
        stderr.writeln('$a needs a value');
        exit(exitUnverifiable);
      }
      return argv[++i];
    }

    switch (a) {
      case '--c':
        cPath = next();
      case '--dart':
        dartPath = next();
      case '--cc':
        compiler = next();
      case '--include':
        includes.add(next());
      case '--pair':
        final v = next();
        final eq = v.indexOf('=');
        if (eq < 0) {
          stderr.writeln('--pair expects CType=DartClass, got "$v"');
          exit(exitUnverifiable);
        }
        pairs[v.substring(0, eq)] = v.substring(eq + 1);
      case '--emit-c-only':
        cOnly = true;
      case '--run-with':
        runWith = next();
      case '--cc-arg':
        ccArgs.add(next());
      case '--self-test':
        selfTest = true;
      case '-h':
      case '--help':
        _usage();
        exit(exitOk);
      default:
        stderr.writeln('unknown argument "$a"');
        _usage();
        exit(exitUnverifiable);
    }
  }

  if (selfTest) exit(runSelfTest(compiler));

  if (cPath == null || dartPath == null || pairs.isEmpty) {
    _usage();
    exit(exitUnverifiable);
  }
  for (final p in [cPath, dartPath]) {
    if (!File(p).existsSync()) {
      stderr.writeln('not found: $p');
      exit(exitUnverifiable);
    }
  }

  final cSource = File(cPath).readAsStringSync();
  final dartSource = File(dartPath).readAsStringSync();
  final work = Directory.systemTemp.createTempSync('abi_layout');
  var failed = false;

  try {
    stdout.writeln('ABI layout check — host ${_hostTriple()}');
    stdout.writeln('  C    $cPath');
    stdout.writeln('  Dart $dartPath\n');

    if (cOnly) {
      stdout.writeln('C-SIDE ONLY. This compares NOTHING. It reports how the C\n'
          'compiler lays the struct out, so a target architecture can be read\n'
          'without a Dart SDK for that target. The Dart half of the check is\n'
          'NOT run and this result must not be called agreement.\n');
      pairs.forEach((cType, _) {
        final cl = measureC(
          cPath: cPath!,
          typeName: cType,
          fieldNames: parseCStructFields(cSource, cType),
          compiler: compiler,
          includes: includes,
          work: work,
          runner: runWith,
          extraCcArgs: ccArgs,
        );
        stdout.writeln('$cType: size=${cl.size} align=${cl.align}');
        for (final f in cl.fields) {
          stdout.writeln('    ${f.name}@${f.offset}+${f.width}');
        }
        stdout.writeln();
      });
      work.deleteSync(recursive: true);
      exit(exitOk);
    }

    pairs.forEach((cType, dartClass) {
      final cNames = parseCStructFields(cSource, cType);
      final dFields = parseDartStructFields(dartSource, dartClass);
      final cl = measureC(
        cPath: cPath!,
        typeName: cType,
        fieldNames: cNames,
        compiler: compiler,
        includes: includes,
        work: work,
      );
      final dl = measureDart(
        dartPath: dartPath!,
        className: dartClass,
        fields: dFields,
        work: work,
      );
      final rep = compare(cl, dl);
      stdout.writeln('$cType  <->  $dartClass');
      rep.rows.forEach(stdout.writeln);
      for (final w in rep.warnings) {
        stdout.writeln('  warning: $w');
      }
      if (rep.failed) {
        failed = true;
        stdout.writeln('  MISMATCH:');
        for (final m in rep.mismatches) {
          stdout.writeln('    - $m');
        }
      } else {
        stdout.writeln('  agrees on size, alignment and every field offset.');
      }
      stdout.writeln();
    });
  } on Unverifiable catch (e) {
    stderr.writeln('UNVERIFIABLE — refusing to report agreement:\n$e');
    work.deleteSync(recursive: true);
    exit(exitUnverifiable);
  }

  work.deleteSync(recursive: true);
  if (failed) {
    stdout.writeln('RESULT: MISMATCH. The Dart binding does not describe the C '
        'struct it calls. A call across this boundary returns a plausible '
        'number, not an error.');
    exit(exitMismatch);
  }
  stdout.writeln('RESULT: layouts agree on ${_hostTriple()}. This says nothing '
      'about any other architecture — run it there too.');
  exit(exitOk);
}

String _hostTriple() {
  final r = Process.runSync('uname', ['-m']);
  final arch = r.exitCode == 0 ? (r.stdout as String).trim() : 'unknown-arch';
  return '${Platform.operatingSystem}-$arch';
}
