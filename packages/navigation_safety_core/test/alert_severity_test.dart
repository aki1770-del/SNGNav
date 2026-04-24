/// AlertSeverity unit tests.
library;

import 'package:test/test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

void main() {
  group('AlertSeverity', () {
    test('has exactly three values', () {
      expect(AlertSeverity.values, hasLength(3));
    });

    test('contains info warning critical', () {
      expect(
        AlertSeverity.values.map((value) => value.name),
        containsAll(['info', 'warning', 'critical']),
      );
    });

    test('info index < warning index', () {
      expect(AlertSeverity.info.index, lessThan(AlertSeverity.warning.index));
    });

    test('warning index < critical index', () {
      expect(AlertSeverity.warning.index, lessThan(AlertSeverity.critical.index));
    });
  });
}