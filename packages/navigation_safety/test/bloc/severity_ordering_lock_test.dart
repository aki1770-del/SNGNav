/// Lock test for AlertSeverity declaration order.
///
/// `NavigationBloc._canUpdateSeverity` uses `.index` to enforce monotonic
/// alert upgrades (lower severity never replaces higher). The semantics
/// depend on the enum declaration order in
/// `packages/navigation_safety_core/lib/src/alert_severity.dart`:
/// info < warning < critical.
///
/// This test fails loudly if:
/// - The enum value set changes (additions / removals)
/// - The declaration order changes (reordering)
///
/// If you intentionally need to add or reorder a severity, update this
/// test deliberately AND audit every call site that compares severities.
/// The compiler will not catch silent semantic drift; this test will.
///
/// Per SNGNav review 2026-04-25 P1 finding (#7 of 12): the prior
/// implementation used a hardcoded order map that could silently desync
/// from the enum. This test is the V14-anti-Jidoka loom for that gap.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

void main() {
  group('AlertSeverity declaration-order lock', () {
    test('value set is exactly {info, warning, critical}', () {
      expect(
        AlertSeverity.values,
        equals(<AlertSeverity>[
          AlertSeverity.info,
          AlertSeverity.warning,
          AlertSeverity.critical,
        ]),
        reason:
            'AlertSeverity values changed. NavigationBloc._canUpdateSeverity uses '
            '.index for monotonic-upgrade semantics; any addition / removal / '
            'reorder requires deliberate audit of every severity comparison.',
      );
    });

    test('declaration order maps to canonical severity ranking', () {
      expect(AlertSeverity.info.index, 0);
      expect(AlertSeverity.warning.index, 1);
      expect(AlertSeverity.critical.index, 2);
    });

    test('index ordering is monotonic and unique', () {
      final indices = AlertSeverity.values.map((s) => s.index).toList();
      // Sorted ascending without duplicates = monotonically increasing.
      final sorted = [...indices]..sort();
      expect(indices, equals(sorted));
      expect(indices.toSet().length, equals(indices.length));
    });

    test('index comparison matches semantic intent (info < warning < critical)', () {
      expect(AlertSeverity.info.index, lessThan(AlertSeverity.warning.index));
      expect(AlertSeverity.warning.index, lessThan(AlertSeverity.critical.index));
    });
  });
}
