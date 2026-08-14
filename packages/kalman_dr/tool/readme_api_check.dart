// Oracle for the pub.dev landing page.
//
// kalman_dr is a pure Dart package, so the README's Flutter widget can never be
// compile-checked in-tree — which is exactly how `position.accuracyMetres`
// survived on the landing page while `GeoPosition` never had such a member.
// Both README examples failed to compile, and worse, the page taught accuracy
// as the live-vs-predicted discriminator that 0.5.0 exists to refute.
//
// This asserts every `<receiver>.<member>` the README teaches actually exists
// on the public API. It cannot type-check a widget tree; it CAN prove the page
// never names a member we do not ship.
//
//   dart run tool/readme_api_check.dart
import 'dart:io';

/// Public members declared in [files], across the declaration forms this
/// package actually uses: `T get x {`, `T get x =>`, `T get x;`, `final T x;`,
/// `T method(`, and enum/field entries.
Set<String> _membersOf(List<String> files) {
  final out = <String>{};
  for (final f in files) {
    final src = File(f).readAsStringSync();
    for (final re in [
      RegExp(r'\bget\s+(\w+)'), // getters, any body form
      RegExp(r'^\s*(?:final|const|late final)\s+[\w<>?,\s]+?\s(\w+)\s*[;=]',
          multiLine: true), // fields
      RegExp(r'^\s*(?:[\w<>?,\s]+?\s)?(\w+)\s*\([^)]*\)\s*(?:async\s*)?[{=]',
          multiLine: true), // methods
    ]) {
      out.addAll(re.allMatches(src).map((m) => m.group(1)!));
    }
  }
  return out;
}

void main() {
  final readme = File('README.md').readAsStringSync();

  // Receiver name as written in README code -> files declaring its API,
  // including supertypes, since inherited members are legitimately teachable.
  final api = <String, Set<String>>{
    'position': _membersOf(['lib/src/geo_position.dart']),
    'filter': _membersOf(['lib/src/kalman_filter.dart']),
    'provider': _membersOf([
      'lib/src/dead_reckoning_provider.dart',
      'lib/src/location_provider.dart',
    ]),
  };

  final blocks = RegExp(r'```dart\n(.*?)```', dotAll: true)
      .allMatches(readme)
      .map((m) => m.group(1)!)
      .join('\n');

  final failures = <String>[];
  for (final receiver in api.entries) {
    for (final m
        in RegExp('\\b${receiver.key}\\.(\\w+)').allMatches(blocks)) {
      final member = m.group(1)!;
      if (!receiver.value.contains(member)) {
        failures.add('  README teaches ${receiver.key}.$member '
            '— NOT IN THE PUBLIC API');
      }
    }
  }

  if (failures.isNotEmpty) {
    stderr.writeln('README API check: FAIL\n${failures.toSet().join('\n')}');
    stderr.writeln('\nThe landing page is the first thing a stranger reads. '
        'Fix the page, not this check.');
    exit(1);
  }
  stdout.writeln('README API check: PASS — '
      'every member the page teaches exists on the public API.');
}
